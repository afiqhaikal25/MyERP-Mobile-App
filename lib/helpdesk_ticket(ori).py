# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.
import requests
import json
import random
import os
# REMEMBER TO INSTALL oauth2client before restarting Odoo by command (pip install oauth2client)
from oauth2client.service_account import ServiceAccountCredentials
from datetime import timedelta
import math
from dateutil.relativedelta import relativedelta
from random import randint

from google.oauth2 import service_account
from google.auth.transport.requests import Request

from odoo import api, Command, fields, models, tools, http, _
from odoo.http import Controller, route, request
from werkzeug.exceptions import NotFound
from odoo.tools import DEFAULT_SERVER_DATETIME_FORMAT, DEFAULT_SERVER_DATE_FORMAT
from odoo.addons.iap.tools import iap_tools
from odoo.osv import expression
from odoo.exceptions import AccessError, ValidationError
from datetime import datetime, timedelta, time
import re
import logging
import base64
import xlsxwriter
from io import BytesIO
import tempfile
from lxml import etree
import pytz
from pytz import timezone

_logger = logging.getLogger(__name__)
_logger.info('[GEO] FILE ticket33.py LOADED - TEST LOG')

TICKET_PRIORITY = [
    ('0', 'Low priority'),
    ('1', 'Medium priority'),
    ('2', 'High priority'),
    ('3', 'Urgent'),
]

class HelpdeskTag(models.Model):
    _name = 'helpdesk.tag'
    _description = 'Helpdesk Tags'
    _order = 'name'

    def _get_default_color(self):
        return randint(1, 11)

    name = fields.Char(required=True, translate=True)
    color = fields.Integer('Color', default=_get_default_color)

    _sql_constraints = [
        ('name_uniq', 'unique (name)', "Tag name already exists !"),
    ]


class HelpdeskTicketType(models.Model):
    _name = 'helpdesk.ticket.type'
    _description = 'Helpdesk Ticket Type'
    _order = 'sequence, name'

    name = fields.Char(required=True, translate=True)
    sequence = fields.Integer(default=10)

    _sql_constraints = [
        ('name_uniq', 'unique (name)', "Type name already exists !"),
    ]


class HelpdeskSLAStatus(models.Model):
    _name = 'helpdesk.sla.status'
    _description = "Ticket SLA Status"
    _table = 'helpdesk_sla_status'
    _order = 'deadline ASC, sla_stage_id'
    _rec_name = 'sla_id'

    ticket_id = fields.Many2one('helpdesk.ticket', string='Ticket', required=True, ondelete='cascade', index=True)
    sla_id = fields.Many2one('helpdesk.sla', required=True, ondelete='cascade')
    sla_stage_id = fields.Many2one('helpdesk.stage', related='sla_id.stage_id',
                                   store=True)  # need to be stored for the search in `_sla_reach`
    deadline = fields.Datetime("Deadline", compute='_compute_deadline', compute_sudo=True, store=True)
    reached_datetime = fields.Datetime("Reached Date",
                                       help="Datetime at which the SLA stage was reached for the first time")
    status = fields.Selection([('failed', 'Failed'), ('reached', 'Reached'), ('ongoing', 'Ongoing')], string="Status",
                              compute='_compute_status', compute_sudo=True, search='_search_status')
    color = fields.Integer("Color Index", compute='_compute_color')
    exceeded_days = fields.Float("Excedeed Working Days", compute='_compute_exceeded_days', compute_sudo=True,
                                 store=True,
                                 help="Working days exceeded for reached SLAs compared with deadline. Positive number means the SLA was eached after the deadline.")

    @api.depends('ticket_id.create_date', 'sla_id', 'ticket_id.stage_id')
    def _compute_deadline(self):
        for status in self:
            if (status.deadline and status.reached_datetime) or (
                    status.deadline and not status.sla_id.exclude_stage_ids) or (status.status == 'failed'):
                continue
            deadline = status.ticket_id.create_date
            working_calendar = status.ticket_id.team_id.resource_calendar_id
            if not working_calendar:
                # Normally, having a working_calendar is mandatory
                status.deadline = deadline
                continue

            if status.sla_id.exclude_stage_ids:
                if status.ticket_id.stage_id in status.sla_id.exclude_stage_ids:
                    # We are in the freezed time stage: No deadline
                    status.deadline = False
                    continue

            avg_hour = working_calendar.hours_per_day or 8  # default to 8 working hours/day
            time_days = math.floor(status.sla_id.time / avg_hour)
            if time_days > 0:
                deadline = working_calendar.plan_days(time_days + 1, deadline, compute_leaves=True)
                # We should also depend on ticket creation time, otherwise for 1 day SLA, all tickets
                # created on monday will have their deadline filled with tuesday 8:00
                create_dt = working_calendar.plan_hours(0, status.ticket_id.create_date)
                deadline = deadline.replace(hour=create_dt.hour, minute=create_dt.minute, second=create_dt.second,
                                            microsecond=create_dt.microsecond)

            sla_hours = status.sla_id.time % avg_hour

            if status.sla_id.exclude_stage_ids:
                sla_hours += status._get_freezed_hours(working_calendar)

                # Except if ticket creation time is later than the end time of the working day
                deadline_for_working_cal = working_calendar.plan_hours(0, deadline)
                if deadline_for_working_cal and deadline.day < deadline_for_working_cal.day:
                    deadline = deadline.replace(hour=0, minute=0, second=0, microsecond=0)
            # We should execute the function plan_hours in any case because, in a 1 day SLA environment,
            # if I create a ticket knowing that I'm not working the day after at the same time, ticket
            # deadline will be set at time I don't work (ticket creation time might not be in working calendar).
            status.deadline = working_calendar.plan_hours(sla_hours, deadline, compute_leaves=True)

    @api.depends('deadline', 'reached_datetime')
    def _compute_status(self):
        for status in self:
            if status.reached_datetime and status.deadline:  # if reached_datetime, SLA is finished: either failed or succeeded
                status.status = 'reached' if status.reached_datetime < status.deadline else 'failed'
            else:  # if not finished, deadline should be compared to now()
                status.status = 'ongoing' if not status.deadline or status.deadline > fields.Datetime.now() else 'failed'

    @api.model
    def _search_status(self, operator, value):
        """ Supported operators: '=', 'in' and their negative form. """
        # constants
        datetime_now = fields.Datetime.now()
        positive_domain = {
            'failed': ['|', '&', ('reached_datetime', '=', True), ('deadline', '<=', 'reached_datetime'), '&',
                       ('reached_datetime', '=', False), ('deadline', '<=', fields.Datetime.to_string(datetime_now))],
            'reached': ['&', ('reached_datetime', '=', True), ('reached_datetime', '<', 'deadline')],
            'ongoing': ['|', ('deadline', '=', False), '&', ('reached_datetime', '=', False),
                        ('deadline', '>', fields.Datetime.to_string(datetime_now))]
        }
        # in/not in case: we treat value as a list of selection item
        if not isinstance(value, list):
            value = [value]
        # transform domains
        if operator in expression.NEGATIVE_TERM_OPERATORS:
            # "('status', 'not in', [A, B])" tranformed into "('status', '=', C) OR ('status', '=', D)"
            domains_to_keep = [dom for key, dom in positive_domain if key not in value]
            return expression.OR(domains_to_keep)
        else:
            return expression.OR(positive_domain[value_item] for value_item in value)

    @api.depends('status')
    def _compute_color(self):
        for status in self:
            if status.status == 'failed':
                status.color = 1
            elif status.status == 'reached':
                status.color = 10
            else:
                status.color = 0

    @api.depends('deadline', 'reached_datetime')
    def _compute_exceeded_days(self):
        for status in self:
            if status.reached_datetime and status.deadline and status.ticket_id.team_id.resource_calendar_id:
                if status.reached_datetime <= status.deadline:
                    start_dt = status.reached_datetime
                    end_dt = status.deadline
                    factor = -1
                else:
                    start_dt = status.deadline
                    end_dt = status.reached_datetime
                    factor = 1
                duration_data = status.ticket_id.team_id.resource_calendar_id.get_work_duration_data(start_dt, end_dt,
                                                                                                     compute_leaves=True)
                status.exceeded_days = duration_data['days'] * factor
            else:
                status.exceeded_days = False

    def _get_freezed_hours(self, working_calendar):
        self.ensure_one()
        hours_freezed = 0

        field_stage = self.env['ir.model.fields']._get(self.ticket_id._name, "stage_id")
        freeze_stages = self.sla_id.exclude_stage_ids.ids
        tracking_lines = self.ticket_id.message_ids.tracking_value_ids.filtered(
            lambda tv: tv.field == field_stage).sorted(key="create_date")

        if not tracking_lines:
            return 0

        old_time = self.ticket_id.create_date
        for tracking_line in tracking_lines:
            if tracking_line.old_value_integer in freeze_stages:
                # We must use get_work_hours_count to compute real waiting hours (as the deadline computation is also based on calendar)
                hours_freezed += working_calendar.get_work_hours_count(old_time, tracking_line.create_date)
            old_time = tracking_line.create_date
        if tracking_lines[-1].new_value_integer in freeze_stages:
            # the last tracking line is not yet created
            hours_freezed += working_calendar.get_work_hours_count(old_time, fields.Datetime.now())
        return hours_freezed


class HelpdeskTicket(models.Model):
    _name = 'helpdesk.ticket'
    _description = 'Helpdesk Ticket'
    _order = "create_date desc"
    _inherit = ['portal.mixin', 'mail.thread.cc', 'utm.mixin', 'rating.mixin', 'mail.activity.mixin']

    latitude = fields.Float(string='Latitude')
    longitude = fields.Float(string='Longitude')
    
    name = fields.Char(string='Subject', index=True, required=True)
    technician_id = fields.Many2one('res.users', string="Technician", tracking=True)
    check_in = fields.Datetime('Technician Check-in', tracking=True)
    check_in_string = fields.Char(string="Check-In Time (String)")
    check_out = fields.Datetime('Technician Check-out', tracking=True)
    check_out_string = fields.Char(string="Check-Out Time (String)")
    priority = fields.Selection(TICKET_PRIORITY, string='Priority', default='0')
    close_comment = fields.Text(string="Close Comment", tracking=True)
    close_comment_string = fields.Char(string="Close Comment Time (String)")
    stage_id = fields.Many2one('helpdesk.stage', string="Stage", tracking=True)
    kanban_state_label = fields.Char(string="Kanban State Label", compute="_compute_kanban_label", store=True)
    description = fields.Html(string="Description", tracking=True)
    resolution_tech = fields.Html(string="Technician Resolution", tracking=True)

    attachment_ids = fields.One2many(
        'ir.attachment', 'res_id',
        domain=[('res_model', '=', 'helpdesk.ticket')],
        string="Attachments"
    )

    @api.model
    def default_get(self, fields):
        result = super(HelpdeskTicket, self).default_get(fields)
        if result.get('team_id') and fields:
            team = self.env['helpdesk.team'].browse(result['team_id'])
            if 'user_id' in fields and 'user_id' not in result:  # if no user given, deduce it from the team
                result['user_id'] = team._determine_user_to_assign()[team.id].id
            if 'stage_id' in fields and 'stage_id' not in result:  # if no stage given, deduce it from the team
                result['stage_id'] = team._determine_stage()[team.id].id
        return result

    def _default_team_id(self):
        team_id = self.env['helpdesk.team'].search([('member_ids', 'in', self.env.uid)], limit=1).id
        if not team_id:
            team_id = self.env['helpdesk.team'].search([], limit=1).id
        return team_id

    @api.model
    def _read_group_stage_ids(self, stages, domain, order):
        # write the domain
        # - ('id', 'in', stages.ids): add columns that should be present
        # - OR ('team_ids', '=', team_id) if team_id: add team columns
        search_domain = [('id', 'in', stages.ids)]
        if self.env.context.get('default_team_id'):
            search_domain = ['|', ('team_ids', 'in', self.env.context['default_team_id'])] + search_domain

        return stages.search(search_domain, order=order)

    def action_export_custom_excel(self):
        tickets = self.env['helpdesk.ticket'].browse(self.env.context.get('active_ids', []))
        export_model = self.env['helpdesk.ticket.export']
        return export_model.action_export_custom_excel(tickets)
    

    def action_get_attachment_view(self):
        """ Open attachment list for the ticket """
        return {
            'type': 'ir.actions.act_window',
            'name': 'Attachments',
            'res_model': 'ir.attachment',
            'view_mode': 'kanban,tree,form',
            'domain': [('res_model', '=', 'helpdesk.ticket'), ('res_id', '=', self.id)],
            'context': {'default_res_model': 'helpdesk.ticket', 'default_res_id': self.id},
            'target': 'current',
        }
    
    @api.depends('stage_id')
    def _compute_kanban_label(self):
        """ Pastikan `kanban_state_label` sentiasa dikemas kini. """
        for ticket in self:
            ticket.kanban_state_label = ticket.stage_id.name if ticket.stage_id else "Unknown"

    @api.onchange('check_in_string')
    def _compute_check_in(self):
        for record in self:
            if record.check_in_string:
                try:
                    record.check_in = datetime.strptime(record.check_in_string, '%Y-%m-%d %H:%M:%S')
                except ValueError:
                    record.check_in = False
                    _logger.error(f"❌ Invalid check-in format: {record.check_in_string}")

    @api.onchange('check_out_string')
    def _compute_check_out(self):
        for record in self:
            if record.check_out_string:
                try:
                    record.check_out = datetime.strptime(record.check_out_string, '%Y-%m-%d %H:%M:%S')
                except ValueError:
                    record.check_out = False
                    _logger.error(f"❌ Invalid check-out format: {record.check_out_string}")

    def send_push_notification(self, title, message, user_id):
        """ Hantar notifikasi FCM ke pengguna berdasarkan user_id """
        _logger.info(f"📤 Sending FCM notification to User ID {user_id}...")

        tokens = self.env['fcm.token'].sudo().search([('user_id', '=', user_id)])
        if not tokens:
            _logger.warning(f"🚫 No FCM token found for user {user_id}")
            return

        server_key = self.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
        if not server_key:
            _logger.error("❌ FCM Server Key is missing in Odoo configuration.")
            return

        # Get access token using service account
        access_token, project_id = self._get_fcm_access_token()
        
        if not access_token or not project_id:
            _logger.error("❌ Failed to get FCM access token")
            return

        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json; UTF-8",
        }

        for token in tokens:
            v1_payload = {
                "message": {
                    "token": token.token,
                    "notification": {
                        "title": title,
                        "body": message
                    },
                    "data": {
                        "ticket_id": str(self.id)
                    }
                }
            }

            try:
                response = requests.post(
                    f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send',
                    headers=headers,
                    json=v1_payload,
                    timeout=10
                )
                response.raise_for_status()
                _logger.info(f"✅ Notification sent to {token.token}: {response.json()}")
            except requests.exceptions.RequestException as e:
                _logger.error(f"❌ Failed to send notification to {token.token}: {str(e)}")

    def send_push_notification_v1(self, title, body, user_id):
        _logger.info(f"📤 Attempting to send FCM v1 notification to user {user_id}: {title}")
        
        target_user_id = user_id
        user_to_notify = self.env['res.users'].sudo().browse(user_id)
        
        # Check for a specific notification email and redirect if necessary
        if user_to_notify.x_notification_email:
            notification_user = self.env['res.users'].sudo().search([('login', '=', user_to_notify.x_notification_email)], limit=1)
            if notification_user:
                _logger.info(f"Redirecting notification for {user_to_notify.login} to {notification_user.login} (User ID: {notification_user.id})")
                target_user_id = notification_user.id
            else:
                _logger.warning(f"Notification email {user_to_notify.x_notification_email} for user {user_id} not found as an Odoo user. Sending to original user.")

        # Try service account first, then fallback to server key
        SCOPES = ['https://www.googleapis.com/auth/firebase.messaging']
        SERVICE_ACCOUNT_FILE = '/mnt/extra-addons/extra-addons/helpdesk/firebase-fcm.json'
        
        # Check if service account file exists
        import os
        if os.path.exists(SERVICE_ACCOUNT_FILE):
            try:
                credentials = service_account.Credentials.from_service_account_file(
                    SERVICE_ACCOUNT_FILE, scopes=SCOPES
                )
                credentials.refresh(Request())
                access_token = credentials.token
                project_id = credentials.project_id
                
                headers = {
                    'Authorization': f'Bearer {access_token}',
                    'Content-Type': 'application/json; UTF-8',
                }

                tokens = self.env['fcm.token'].sudo().search([('user_id', '=', target_user_id)])
                if not tokens:
                    _logger.warning(f"🚫 No FCM token found for user {target_user_id}")
                    return

                for token in tokens:
                    message = {
                        "message": {
                            "token": token.token,
                            "notification": {
                                "title": title,
                                "body": body
                            }
                        }
                    }

                    url = f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send'
                    try:
                        response = requests.post(url, headers=headers, json=message)
                        if response.status_code == 200:
                            _logger.info(f"✅ FCM v1 notification sent successfully to user {target_user_id}")
                        else:
                            _logger.error(f"❌ Failed to send FCM v1 notification: {response.text}")
                    except Exception as e:
                        _logger.error(f"❌ Exception during FCM v1 send: {e}")
                        
            except Exception as e:
                _logger.error(f"❌ Failed to get FCM access token: {e}")
                # Fallback to server key method
                self._send_fcm_notification_fallback(title, body, target_user_id)
        else:
            _logger.warning(f"⚠️ Firebase service account file not found at {SERVICE_ACCOUNT_FILE}. Using fallback method.")
            # Fallback to server key method
            self._send_fcm_notification_fallback(title, body, target_user_id)

    def _send_fcm_notification_fallback(self, title, body, user_id):
        """Fallback method using FCM Server Key"""
        _logger.info(f"📤 Using FCM Server Key fallback for user {user_id}")
        
        # Get FCM Server Key from system parameters
        server_key = self.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
        if not server_key:
            _logger.error("❌ FCM Server Key is missing in Odoo configuration.")
            return

        tokens = self.env['fcm.token'].sudo().search([('user_id', '=', user_id)])
        if not tokens:
            _logger.warning(f"🚫 No FCM token found for user {user_id}")
            return

        # Get access token using service account
        access_token, project_id = self._get_fcm_access_token()
        
        if not access_token or not project_id:
            _logger.error("❌ Failed to get FCM access token for fallback")
            return

        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json; UTF-8',
        }

        for token in tokens:
            v1_payload = {
                "message": {
                    "token": token.token,
                    "notification": {
                        "title": title,
                        "body": body
                    },
                    "data": {
                        'ticket_id': str(self.id),
                        'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                    }
                }
            }
            try:
                response = requests.post(
                    f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send',
                    headers=headers,
                    json=v1_payload
                )
                response.raise_for_status()
                _logger.info(f"✅ FCM fallback notification sent to {token.token}: {response.json()}")
            except requests.exceptions.RequestException as e:
                _logger.error(f'FCM Fallback Notification Error: {str(e)}')

    def _send_fcm_notification_to_user(self, user_id, ticket):
        user = self.env['res.users'].browse(user_id)
        # Use the correct FCM token model instead of the field
        tokens = self.env['fcm.token'].sudo().search([('user_id', '=', user_id)])
        _logger.info(f"User {user_id} FCM tokens: {[t.token for t in tokens]}")
        if not tokens:
            _logger.warning(f"🚫 No FCM token found for user {user_id}")
            return
        for token in tokens:
            self._send_fcm_notification(token.token, {
                'title': 'New Ticket Assigned',
                'body': f'Ticket {ticket.name} assigned to you.',
                'ticket_id': ticket.id,
            })

    def _send_fcm_notification(self, token, data):
        # Get access token using service account
        access_token, project_id = self._get_fcm_access_token()
        
        if not access_token or not project_id:
            _logger.error("❌ Failed to get FCM access token")
            return
            
        headers = {
            'Authorization': f'Bearer {access_token}',
            'Content-Type': 'application/json; UTF-8',
        }
        
        v1_payload = {
            "message": {
                "token": token,
                "notification": {
                    "title": data['title'],
                    "body": data['body']
                },
                "data": {
                    'ticket_id': str(data.get('ticket_id')),
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                }
            }
        }
        
        try:
            response = requests.post(
                f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send',
                headers=headers,
                json=v1_payload
            )
            response.raise_for_status()
            _logger.info(f"✅ FCM notification sent to {token}: {response.json()}")
        except requests.exceptions.RequestException as e:
            _logger.error(f'FCM Notification Error: {str(e)}')

    def _get_fcm_access_token(self):
        """Get FCM access token using service account credentials."""
        try:
            # Try to get service account file first
            SERVICE_ACCOUNT_FILE = '/mnt/extra-addons/extra-addons/helpdesk/firebase-fcm.json'
            
            if os.path.exists(SERVICE_ACCOUNT_FILE):
                # Use service account file
                credentials = service_account.Credentials.from_service_account_file(
                    SERVICE_ACCOUNT_FILE, 
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
                credentials.refresh(Request())
                access_token = credentials.token
                project_id = credentials.project_id
                _logger.info(f"✅ Using service account file for FCM access token")
                return access_token, project_id
            else:
                # Try to get from system parameters
                credentials_json_str = self.env['ir.config_parameter'].sudo().get_param('fcm.service_account.credentials')
                if not credentials_json_str:
                    _logger.error("FCM service account credentials not found in file or system parameters.")
                    return None, None

                credentials_info = json.loads(credentials_json_str)
                project_id = credentials_info.get('project_id')
                creds = ServiceAccountCredentials.from_json_keyfile_dict(
                    credentials_info,
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
                access_token = creds.get_access_token().access_token
                _logger.info(f"✅ Using system parameter for FCM access token")
                return access_token, project_id
                
        except Exception as e:
            _logger.error(f"Failed to get FCM access token: {e}")
            return None, None

    def upload_file_to_description(self, filename, file_data):
        """ Simpan fail sebagai lampiran dan tambah link ke dalam description """
        self.ensure_one()
        attachment = self.env['ir.attachment'].sudo().create({
            'name': filename,
            'type': 'binary',
            'datas': base64.b64encode(file_data).decode(),
            'res_model': 'helpdesk.ticket',
            'res_id': self.id,
            'mimetype': 'application/octet-stream',
        })

        # Tambah link fail ke dalam description
        file_url = f"/web/content/{attachment.id}?download=true"
        link_html = f'<p><a href="{file_url}" target="_blank">{filename}</a></p>'
        self.description = (self.description or '') + link_html

        return attachment.id

    @api.model
    def create(self, vals):
        _logger.info(f"[GEO] CREATE METHOD CALLED - vals keys: {list(vals.keys())}")
        
        # Geocode address if available
        address = vals.get('address') or vals.get('check_in_address') or vals.get('check_out_address')
        _logger.info(f"[GEO] Address to geocode: '{address}' (type: {type(address)})")
        
        if address and address.strip():  # Check if not empty
            try:
                lat, lon = get_lat_lon_from_address(address)
                _logger.info(f"[GEO] Geocoded lat/lon: {lat}, {lon}")
                if lat is not None and lon is not None:
                    vals.update({'latitude': lat, 'longitude': lon})
            except Exception as e:
                _logger.error(f"[GEO] Error geocoding address '{address}': {e}")
        else:
            _logger.info("[GEO] No address found in vals")
        
        # ... existing code ...
        ticket = super(HelpdeskTicket, self).create(vals)

        # Use user_id for push notifications instead of technician_id
        if ticket.user_id:
            _logger.info(f"📌 New ticket '{ticket.name}' assigned to {ticket.user_id.name}.")
            ticket.send_push_notification_v1(
                title="New Ticket Assigned",
                body=f"Ticket '{ticket.name}' has been assigned to you.",
                user_id=ticket.user_id.id
            )

        if vals.get('close_comment'):
            ticket.message_post(body=f"Close Comment Added: {vals['close_comment']}")

        return ticket

    def write(self, vals):
        """ Kemaskini Tiket & Pastikan `CacheMiss` Tidak Berlaku """
        for ticket in self:
            # ✅ Pastikan Close Comment tidak kosong sebelum dikemas kini
            if 'close_comment' in vals:
                new_comment = vals.get('close_comment', '').strip()
                if new_comment:
                    _logger.info(f"✅ Updating Close Comment for Ticket {ticket.id}: {new_comment}")
                    ticket.message_post(body=f"🔹 Close Comment Updated:\n{new_comment}")
                else:
                    _logger.warning(f"⚠️ Attempt to save empty Close Comment for Ticket ID {ticket.id}")

            # ✅ Pastikan `kanban_state_label` dimuatkan untuk elak CacheMiss
            if not ticket.kanban_state_label:
                ticket.invalidate_cache(fnames=['kanban_state_label'])
                _logger.info(f"🔄 Reloaded kanban_state_label for Ticket {ticket.id}")

            # ✅ Pastikan `stage_id` tidak kosong
            if 'stage_id' not in vals and not ticket.stage_id:
                default_stage = self.env['helpdesk.stage'].search([], limit=1)
                if default_stage:
                    vals['stage_id'] = default_stage.id
                    _logger.info(f"🔄 Assigned default stage {default_stage.name} to Ticket {ticket.id}")

            # ✅ Hantar notifikasi jika user_id berubah (instead of technician_id)
            if 'user_id' in vals and ticket.user_id:
                _logger.info(f"📌 Ticket '{ticket.name}' now assigned to {ticket.user_id.name}.")
                ticket.send_push_notification_v1(
                    title="Ticket Updated",
                    body=f"Ticket '{ticket.name}' is now assigned to you.",
                    user_id=ticket.user_id.id
                )

        return super(HelpdeskTicket, self).write(vals)

    @api.model
    def update_close_comment(self, ticket_id, close_comment):
        """ API untuk mengemas kini Close Comment melalui JSON-RPC """
        try:
            ticket = self.sudo().browse(ticket_id)
            if not ticket.exists():
                return {"jsonrpc": "2.0", "error": {"message": "Ticket not found", "code": 404}}

            ticket.write({'close_comment': close_comment})
            return {"jsonrpc": "2.0", "result": {"success": True, "message": "Close Comment updated successfully"}}
        except Exception as e:
            _logger.error(f"❌ Error updating Close Comment: {str(e)}")
            return {"jsonrpc": "2.0", "error": {"message": str(e), "code": 500}}

    @api.model
    def close_ticket(self, ticket_id):
        """Close a ticket with proper validation and updates."""
        try:
            # Validate ticket_id is an integer
            if not isinstance(ticket_id, int):
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 400,
                        "message": "Invalid ticket ID format. Must be an integer."
                    }
                }

            # Find the ticket
            ticket = self.sudo().browse(ticket_id)
            if not ticket.exists():
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 404,
                        "message": "Ticket not found"
                    }
                }

            # Get the "Technician closed" stage
            technician_closed_stage = self.env['helpdesk.stage'].search([('name', '=', 'Technician closed')], limit=1)
            if not technician_closed_stage:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 500,
                        "message": "Could not find 'Technician closed' stage"
                    }
                }

            # Get current time
            now = fields.Datetime.now()
            
            # Calculate time differences
            create_date = ticket.create_date
            diff_time = now - create_date
            diff_seconds = diff_time.total_seconds()
            diff_hours = diff_time.total_seconds() / 3600

            # Update ticket - Use user_id as closed_by_id if available
            values = {
                'stage_id': technician_closed_stage.id,
                'close_time': now,
                'close_date': now.date(),
                'time_to_close': diff_seconds,
                'time_to_close_hhmm': diff_hours,
                'closed_by_id': ticket.user_id.id if ticket.user_id else self.env.user.id,
                'sla_active': False,
                'prob_solve_time': now,
            }

            # Write changes and handle any errors
            try:
                ticket.write(values)
                self.env.cr.commit()  # Commit the transaction
                
                # Log the action
                ticket.message_post(
                    body=f"Ticket closed by {self.env.user.name}",
                    message_type='notification',
                    subtype_xmlid='mail.mt_note'
                )

                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True,
                        "message": "Ticket closed successfully"
                    }
                }

            except Exception as e:
                self.env.cr.rollback()  # Rollback on error
                _logger.error(f"Error closing ticket {ticket_id}: {str(e)}")
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 500,
                        "message": f"Failed to close ticket: {str(e)}"
                    }
                }

        except Exception as e:
            _logger.error(f"Unexpected error while closing ticket {ticket_id}: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": False,
                    "message": f"Handled with error: {str(e)}"
                }
            }



    name = fields.Char(string='Subject', index=True)  # , required=True
    team_id = fields.Many2one('helpdesk.team', string='Helpdesk Team', default=_default_team_id, index=True)
    use_sla = fields.Boolean(related='team_id.use_sla')
    description = fields.Html()
    active = fields.Boolean(default=True)
    ticket_type_id = fields.Many2one('helpdesk.ticket.type', string="Type")
    tag_ids = fields.Many2many('helpdesk.tag', string='Tags')
    company_id = fields.Many2one(related='team_id.company_id', string='Company', store=True, readonly=True)
    color = fields.Integer(string='Color Index')
    kanban_state = fields.Selection([
        ('normal', 'Grey'),
        ('done', 'Green'),
        ('blocked', 'Red')], string='Kanban State',
        copy=False, default='normal', required=True)
    kanban_state_label = fields.Char(compute='_compute_kanban_state_label', string='Column Status', tracking=True)
    legend_blocked = fields.Char(related='stage_id.legend_blocked', string='Kanban Blocked Explanation', readonly=True,
                                 related_sudo=False)
    legend_done = fields.Char(related='stage_id.legend_done', string='Kanban Valid Explanation', readonly=True,
                              related_sudo=False)
    legend_normal = fields.Char(related='stage_id.legend_normal', string='Kanban Ongoing Explanation', readonly=True,
                                related_sudo=False)
    domain_user_ids = fields.Many2many('res.users', compute='_compute_domain_user_ids')
    user_id = fields.Many2one('res.users', string='Assigned to')  # , compute='_compute_user_and_stage_ids',
    # store=True, readonly=False, tracking=True,  domain=lambda self: [('groups_id', 'in', self.env.ref(
    # 'helpdesk.group_helpdesk_user').id)]
    partner_id = fields.Many2one('res.partner', string='Customer')
    partner_ticket_ids = fields.Many2many('helpdesk.ticket', compute='_compute_partner_ticket_count',
                                          string="Partner Tickets")
    partner_ticket_count = fields.Integer('Number of other tickets from the same partner',
                                          compute='_compute_partner_ticket_count')
    # Used to submit tickets from a contact form
    partner_name = fields.Char(string='Customer Name', compute='_compute_partner_name', store=True, readonly=False)
    partner_email = fields.Char(string='Customer Email', compute='_compute_partner_email', store=True, readonly=False)
    partner_phone = fields.Char(string='Customer Phone', compute='_compute_partner_phone', store=True, readonly=False)
    commercial_partner_id = fields.Many2one(related="partner_id.commercial_partner_id")
    closed_by_partner = fields.Boolean('Closed by Partner', readonly=True,
                                       help="If checked, this means the ticket was closed through the customer portal by the customer.")
    cmform = fields.Char(string="CM Form")
    attachment_ids = fields.One2many('ir.attachment', 'res_id',
                                     domain=[('res_model', '=', 'helpdesk.ticket')],
                                     string="Media Attachments")
    close_comment = fields.Text(string="Close Comment")
    unattended = fields.Boolean(string="Unattended", compute="_compute_unattend", store=True,
                                help="In 'Open' state or 'Customer Replied' state taken into consideration name changes")
    # Used in message_get_default_recipients, so if no partner is created, email is sent anyway
    email = fields.Char(related='partner_email', string='Email on Customer', readonly=False)
    priority = fields.Selection(TICKET_PRIORITY, string='Priority', default='0')
    stage_id = fields.Many2one(
        'helpdesk.stage', string='Stage', compute='_compute_user_and_stage_ids', store=True,
        readonly=False, ondelete='restrict', tracking=True, group_expand='_read_group_stage_ids',
        copy=False, index=True, domain="[('team_ids', '=', team_id)]")
    date_last_stage_update = fields.Datetime("Last Stage Update", copy=False, readonly=True)
    # next 4 fields are computed in write (or create)
    assign_date = fields.Datetime("Assign Date")
    assign_hours = fields.Integer("Time to first assignment (hours)", compute='_compute_assign_hours', store=True,
                                  help="This duration is based on the working calendar of the team")
    close_date = fields.Datetime("Close date", copy=False)
    close_hours = fields.Integer("Time to close (hours)", compute='_compute_close_hours', store=True,
                                 help="This duration is based on the working calendar of the team")
    open_hours = fields.Integer("Open Time (hours)", compute='_compute_open_hours', search='_search_open_hours',
                                help="This duration is not based on the working calendar of the team")
    # SLA relative
    sla_ids = fields.Many2many('helpdesk.sla', 'helpdesk_sla_status', 'ticket_id', 'sla_id', string="SLAs", copy=False)
    sla_status_ids = fields.One2many('helpdesk.sla.status', 'ticket_id', string="SLA Status")
    sla_reached_late = fields.Boolean("Has SLA reached late", compute='_compute_sla_reached_late', compute_sudo=True,
                                      store=True)
    sla_deadline = fields.Datetime("SLA Deadline", compute='_compute_sla_deadline', compute_sudo=True, store=True,
                                   help="The closest deadline of all SLA applied on this ticket")
    sla_fail = fields.Boolean("Failed SLA Policy", compute='_compute_sla_fail', search='_search_sla_fail')
    sla_success = fields.Boolean("Success SLA Policy", compute='_compute_sla_success', search='_search_sla_success')

    use_credit_notes = fields.Boolean(related='team_id.use_credit_notes', string='Use Credit Notes')
    use_coupons = fields.Boolean(related='team_id.use_coupons', string='Use Coupons')
    use_product_returns = fields.Boolean(related='team_id.use_product_returns', string='Use Returns')
    use_product_repairs = fields.Boolean(related='team_id.use_product_repairs', string='Use Repairs')
    use_rating = fields.Boolean(related='team_id.use_rating', string='Use Customer Ratings')

    # customer portal: include comment and incoming emails in communication history
    website_message_ids = fields.One2many(
        domain=lambda self: [('model', '=', self._name), ('message_type', 'in', ['email', 'comment'])])
    inventory_serial_number_id = fields.Many2one(
        'stock.production.lot',
        string='Serial Number',
        domain=[('location_type', '=', 'on_site')]
    )
    loaner_id = fields.Many2one(
        'stock.production.lot',
        string='Loaner Serial Number',
        domain=[('location_type', '=', 'on_store')]
    )
    project_id = fields.Many2one('project.project', string='Project')
    problem = fields.Many2one('helpdesk.ticket.problem', string="Problem")
    #problem = fields.Many2many('helpdesk.ticket.problem', string="Problem")
    category = fields.Many2one('helpdesk.ticket.categories', required="True", string="Category")
    sub_category_id = fields.Many2one('helpdesk.ticket.subcategory', string="Sub Category")
    open_case = fields.Datetime(string='Open Case Time', required=False)
    close_time = fields.Datetime(string="Close Time")
    prob_solve_time = fields.Datetime(string='Date of Completion')
    closed_by_id = fields.Many2one('res.users', string="Closed By")
    sla_active = fields.Boolean(string="SLA Active")

    # this is for ticket timeline information, technician check-in, check-out for tickets.
    time_to_close = fields.Float(string="Time to close",
                                 help="seconds")  # reeditted from format seconds to : @hafizalwi11jan
    time_to_close_hhmm = fields.Float(string="Time to close: ", help="hh:mm format")
    check_in = fields.Datetime('Technician Check-in', help="Time on which technician check-in for the job")
    check_out = fields.Datetime('Technician Check-out', help="Time on which technician check-out for the job")
    check_in_address = fields.Char(string="Check-in address")
    check_out_address = fields.Char(string="Check-out address")
    check_in_lat = fields.Float(string="Check-in latitude", digits=(12, 15))
    check_in_long = fields.Float(string="Check-in longitude", digits=(12, 15))
    check_out_lat = fields.Float(string="Check-out latitude", digits=(12, 15),
                                 help="Floating Precision is set to 15 (maximum for longitude and latitude)")
    check_out_long = fields.Float(string="Check-out longitude", digits=(12, 15),
                                  help="Floating Precision is set to 15 (maximum for longitude and latitude)")
    address = fields.Char(string='Address')
    department = fields.Char(string='Department')
    equipment_user = fields.Char(string='Equipment User')
    person_name = fields.Char(string='Reported By')
    is_saved = fields.Boolean(compute='_compute_is_saved')
    ticket_number = fields.Integer(string="Ticket Number", readonly=True, default="5197")
    ticket_number_display = fields.Char(string="Ticket Number Display", compute="_compute_ticket_number_display",
                                        store=True)
    close_time_raf = fields.Float(string='Time to Close (Hour)', compute='_compute_close_time_raf', store=True)

    cm_form_no = fields.Char(string="CM Form No", compute='_compute_cm_form_no', store=True)
    customer_signature = fields.Binary(string='Customer Signature')
    customer_signature_date = fields.Date('Date')
    customer_feedback = fields.Float(string="Customer Feedback", compute='_compute_total_percentage', store=True)
    lot_product = fields.Char("Brand/Model", related="inventory_serial_number_id.product_id.name")
    #service_types = fields.Char(string='Service Types')
    equipment_type = fields.Selection([
        ('pickup', 'Pickup'),
        ('exchange', 'Exchange')
    ], string='Equipment Type')

    user_helpdesk = fields.Selection([
        ('Helpdesk', 'Helpdesk'),
        ('user_pic', 'PIC')
    ], string='User', default='user_pic')

    is_user_pic = fields.Boolean("Is User PIC", compute='_compute_is_user_pic', store=True)


    job_status = fields.Selection([
        ('done', 'DONE'),
        ('pending', 'PENDING'),
        ('incomplete', 'INCOMPLETE')
    ], string='Job Status', default='done')

    feedback_given = fields.Boolean(string="Feedback Given", default=False)
    total_seconds = fields.Float(string='Total Seconds')
    total_minutes = fields.Float(string='Total Minutes')
    total_days = fields.Float(string='Total Days')
    total_hours = fields.Float(string='Total Hours')
    total_weeks = fields.Float(string='Total Weeks')

    # Feedback scales
    feedback_scale1 = fields.Selection([(str(num), str(num)) for num in range(1, 6)], string="Scale 1")
    feedback_scale2 = fields.Selection([(str(num), str(num)) for num in range(1, 6)], string="Scale 2")
    feedback_scale3 = fields.Selection([(str(num), str(num)) for num in range(1, 6)], string="Scale 3")
    feedback_scale4 = fields.Selection([(str(num), str(num)) for num in range(1, 6)], string="Scale 4")
    feedback_scale5 = fields.Selection([(str(num), str(num)) for num in range(1, 6)], string="Scale 5")
    feedback_scale6 = fields.Selection([(str(num), str(num)) for num in range(1, 6)], string="Scale 6")

    # Satisfaction scale
    satisfaction_scale = fields.Selection([(str(num), label) for num, label in enumerate(
        ['Dissatisfied', 'Somewhat Dissatisfied', 'Somewhat Satisfied', 'Very Satisfied', 'Completely Satisfied'], 1)],
                                          string="Satisfaction Scale")

    # Computed fields
    total_feedback_scale = fields.Float(string="Total Feedback Scale:", compute="_compute_feedback_data", store=True)
    feedback_scale1_display = fields.Char(string="Scale 1 Display", compute="_compute_feedback_data", store=True)
    feedback_scale2_display = fields.Char(string="Scale 2 Display", compute="_compute_feedback_data", store=True)
    feedback_scale3_display = fields.Char(string="Scale 3 Display", compute="_compute_feedback_data", store=True)
    feedback_scale4_display = fields.Char(string="Scale 4 Display", compute="_compute_feedback_data", store=True)
    feedback_scale5_display = fields.Char(string="Scale 5 Display", compute="_compute_feedback_data", store=True)
    feedback_scale6_display = fields.Char(string="Scale 6 Display", compute="_compute_feedback_data", store=True)

    attachment_number = fields.Integer(string="Number of Attachments", compute='_compute_attachment_number')

    partner_name = fields.Char(string='Partner Name', related='partner_id.name', store=True, readonly=True)
    category_name = fields.Char(string='Cat Name', related='category.name', store=True, readonly=True)
    sub_name = fields.Char(string='Sub Name', related='sub_category_id.name', store=True, readonly=True)
    stage_name = fields.Char(string='Stage Name', related='stage_id.name', store=True, readonly=True)
    prob_name = fields.Char(string='Stage Name', related='problem.name', store=True, readonly=True)
    serial_name = fields.Char(string='Serial Name', related='inventory_serial_number_id.name', store=True, readonly=True)

    check_in_string = fields.Char(string="Check-In Time (String)")
    check_out_string = fields.Char(string="Check-Out Time (String)")  # New field
    close_comment_string = fields.Char(string="Close Comment Time (String)")  # New field

    def _compute_attachment_number(self):
        for record in self:
            record.attachment_number = self.env['ir.attachment'].search_count([
                ('res_model', '=', 'helpdesk.ticket'),
                ('res_id', '=', record.id)
            ])

    def action_get_attachment_view(self):
        return {
            'type': 'ir.actions.act_window',
            'name': 'Attachments',
            'res_model': 'ir.attachment',
            'view_mode': 'kanban,tree,form',
            'domain': [('res_model', '=', 'helpdesk.ticket'), ('res_id', '=', self.id)],
            'context': {'default_res_model': 'helpdesk.ticket', 'default_res_id': self.id},
            'target': 'current',
        }


    @api.depends('feedback_scale1', 'feedback_scale2', 'feedback_scale3', 'feedback_scale4', 'feedback_scale5',
                 'feedback_scale6')
    def _compute_feedback_data(self):
        max_score = 5
        num_questions = 6
        for ticket in self:
            scales = [int(ticket[f'feedback_scale{i}'] or 0) for i in range(1, 7)]
            max_total_score = max_score * num_questions
            actual_total_score = sum(scales)
            ticket.total_feedback_scale = (actual_total_score / max_total_score) * 100 if max_total_score else 0

            for i in range(1, 7):
                ticket[f'feedback_scale{i}_display'] = f"{ticket[f'feedback_scale{i}']}/{max_score}" if ticket[
                    f'feedback_scale{i}'] else f"0/{max_score}"

    @api.depends('total_feedback_scale')
    def _compute_total_percentage(self):
        """ Compute customer feedback percentage """
        for ticket in self:
            ticket.customer_feedback = ticket.total_feedback_scale or 0.0

    @api.depends('stage_id', 'name')
    def _compute_unattend(self):
        """ Compute if ticket is unattended """
        for ticket in self:
            # Consider ticket unattended if it's in open state or customer replied state
            # and name has changed (indicating activity)
            open_stages = self.env['helpdesk.stage'].search([('is_close', '=', False)])
            ticket.unattended = ticket.stage_id in open_stages

    technician = fields.Many2one('res.users', string="Technician")
    service_type = fields.Selection([
        ('preventive', 'Preventive Maintenance'),
        ('corrective', 'Corrective Maintenance')
    ], string='Service Type', default='corrective')


    @api.depends('ticket_number')
    def _compute_cm_form_no(self):
        for record in self:
            # Set the cm_form_no to include leading zeros, the ticket_number, and the record id
            record.cm_form_no = f"{record.id:04d}"

    @api.depends('user_helpdesk')
    def _compute_is_user_pic(self):
        for record in self:
            record.is_user_pic = (record.user_helpdesk == 'user_pic')

    @api.depends('open_case', 'prob_solve_time')
    def _compute_close_time_raf(self):
        for ticket in self:
            if ticket.open_case and ticket.prob_solve_time:
                # Define working hours
                working_hours_start = 8.5  # 8:30 AM
                working_hours_end = 17.5  # 5:30 PM
                # Calculate total duration
                total_duration = ticket.prob_solve_time - ticket.open_case
                # Initialize close time RAF
                close_time_raf = 0.0
                # Iterate over each day in the duration
                current_time = ticket.open_case
                while current_time < ticket.prob_solve_time:
                    # Check if current time falls within working hours
                    if current_time.hour + current_time.minute / 60 >= working_hours_start \
                            and current_time.hour + current_time.minute / 60 <= working_hours_end:
                        close_time_raf += 1.0  # Add a working hour
                    # Increment current time by one hour
                    current_time += timedelta(hours=1)
                ticket.close_time_raf = close_time_raf


    def write(self, vals):
        res = super(HelpdeskTicket, self).write(vals)
        # Check if dates have been updated, and if so, recompute fields
        if 'assign_date' in vals or 'prob_solve_time' in vals:
            # Call the compute method to update fields
            self._compute_total_time()
        return res

    def _compute_total_time(self):
        """ Compute total time fields based on assign_date and prob_solve_time """
        for ticket in self:
            if ticket.assign_date and ticket.prob_solve_time:
                # Calculate time difference
                time_diff = ticket.prob_solve_time - ticket.assign_date
                
                # Convert to different time units
                ticket.total_seconds = time_diff.total_seconds()
                ticket.total_minutes = ticket.total_seconds / 60
                ticket.total_hours = ticket.total_minutes / 60
                ticket.total_days = ticket.total_hours / 24
                ticket.total_weeks = ticket.total_days / 7
            else:
                # Reset to 0 if dates are not available
                ticket.total_seconds = 0
                ticket.total_minutes = 0
                ticket.total_hours = 0
                ticket.total_days = 0
                ticket.total_weeks = 0

    @api.depends('ticket_number')
    def _compute_ticket_number_display(self):
        for record in self:
            record.ticket_number_display = str("TN") + str(record.id) + "-" + datetime.today().strftime(
                '%Y%m%d') + "-" + "{:,}".format(record.id)

    def action_cm_form(self):
        self.ensure_one()
        base_url = self.env['ir.config_parameter'].sudo().get_param('web.base.url')
        cm_form_no = self.cm_form_no
        url = f"{base_url}/cmForm/{cm_form_no}"
        return {
            'type': 'ir.actions.act_url',
            'url': url,
            'target': 'new',  # Opens in a new tab
        }

    def write(self, vals):
        # Decode the signature data if present
        if 'customer_signature' in vals and isinstance(vals['customer_signature'], list):
            binary_data = bytes(vals['customer_signature'])
            vals['customer_signature'] = base64.b64encode(binary_data).decode('utf-8')

        return super(HelpdeskTicket, self).write(vals)


    @api.depends('create_date')
    def _compute_is_saved(self):
        for record in self:
            record.is_saved = bool(record.id)

    @api.onchange('inventory_serial_number_id')
    def _onchange_inventory_serial_number_id(self):
        if self.inventory_serial_number_id:
            self.equipment_user = self.inventory_serial_number_id.equipment_user
            self.partner_id = self.inventory_serial_number_id.partner_id
            self.partner_email = self.inventory_serial_number_id.partner_id.email
            self.partner_name = self.inventory_serial_number_id.partner_id.name
            self.partner_phone = self.inventory_serial_number_id.partner_id.phone
            self.project_id = self.inventory_serial_number_id.project_id
            self.department = self.inventory_serial_number_id.equipment_location
            if self.inventory_serial_number_id.partner_id.zip or self.inventory_serial_number_id.partner_id.country_id.name or self.inventory_serial_number_id.partner_id.street or self.inventory_serial_number_id.partner_id.street2 or self.inventory_serial_number_id.partner_id.city or self.inventory_serial_number_id.partner_id.state_id.name:
                if self.inventory_serial_number_id.partner_id.zip:
                    zip = self.inventory_serial_number_id.partner_id.zip + ", "
                else:
                    zip = ""
                if self.inventory_serial_number_id.partner_id.country_id:
                    country = self.inventory_serial_number_id.partner_id.country_id.name + ", "
                else:
                    country = ""
                if self.inventory_serial_number_id.partner_id.street:
                    street = self.inventory_serial_number_id.partner_id.street + ", "
                else:
                    street = ""
                if self.inventory_serial_number_id.partner_id.street2:
                    street2 = self.inventory_serial_number_id.partner_id.street2 + ", "
                else:
                    street2 = ""
                if self.inventory_serial_number_id.partner_id.city:
                    city = self.inventory_serial_number_id.partner_id.city + ", "
                else:
                    city = ""
                if self.inventory_serial_number_id.partner_id.state_id:
                    state = self.inventory_serial_number_id.partner_id.state_id.name
                else:
                    state = ""

                address = "{street}{street2}{city}{zip}{state}".format(
                    zip=zip,
                    country=country,
                    street=street,
                    street2=street2,
                    city=city,
                    state=state)

            else:
                address = ""
            self.address = address

    @api.onchange('partner_id')
    def _onchange_equipment_user(self):
        if self.partner_id:
            self.partner_email = self.partner_id.email
            self.partner_name = self.partner_id.name
            self.partner_phone = self.partner_id.phone
            # self.department = self.equipment_user.department
            if self.partner_id.zip or self.partner_id.country_id.name or self.partner_id.street or self.partner_id.street2 or self.partner_id.city or self.partner_id.state_id.name:
                if self.partner_id.zip:
                    zip = self.partner_id.zip + ", "
                else:
                    zip = ""
                if self.partner_id.country_id:
                    country = self.partner_id.country_id.name + ", "
                else:
                    country = ""
                if self.partner_id.street:
                    street = self.partner_id.street + ", "
                else:
                    street = ""
                if self.partner_id.street2:
                    street2 = self.partner_id.street2 + ", "
                else:
                    street2 = ""
                if self.partner_id.city:
                    city = self.partner_id.city + ", "
                else:
                    city = ""
                if self.partner_id.state_id:
                    state = self.partner_id.state_id.name
                else:
                    state = ""

                address = "{street}{street2}{city}{zip}{state}".format(
                    zip=zip,
                    country=country,
                    street=street,
                    street2=street2,
                    city=city,
                    state=state)

            else:
                address = ""
            self.address = address

    @api.onchange('category')
    def _onchange_category(self):
        self.ensure_one()
        for record in self:
            # Get the category record
            category = self.env['helpdesk.ticket.categories'].browse(record.category.id)

            # Assign the category to 'parent_category_id' of the subcategory linked to the ticket
            record.sub_category_id.parent_category_id = category

    @api.constrains('project_id')
    def _check_project(self):
        for ticket in self:
            if ticket.project_id:
                # Perform validation checks here
                pass

    @api.constrains('inventory_serial_number_id')
    def _check_inventory_serial_number(self):
        for ticket in self:
            if ticket.inventory_serial_number_id:
                # Perform validation checks here
                pass

    @api.depends('stage_id', 'kanban_state')
    def _compute_kanban_state_label(self):
        for ticket in self:
            if ticket.kanban_state == 'normal':
                ticket.kanban_state_label = ticket.legend_normal
            elif ticket.kanban_state == 'blocked':
                ticket.kanban_state_label = ticket.legend_blocked
            else:
                ticket.kanban_state_label = ticket.legend_done

    @api.depends('team_id')
    def _compute_domain_user_ids(self):
        helpdesk_user_group_id = self.env.ref('helpdesk.group_helpdesk_user').id
        helpdesk_manager_group_id = self.env.ref('helpdesk.group_helpdesk_manager').id
        users_data = self.env['res.users'].read_group(
            [('groups_id', 'in', [helpdesk_user_group_id, helpdesk_manager_group_id])],
            ['ids:array_agg(id)', 'groups_id'],
            ['groups_id'],
        )
        mapped_data = {data['groups_id'][0]: data['ids'] for data in users_data}
        for ticket in self:
            if ticket.team_id and ticket.team_id.privacy == 'invite' and ticket.team_id.visibility_member_ids:
                manager_ids = mapped_data.get(helpdesk_manager_group_id, [])
                ticket.domain_user_ids = [Command.set(manager_ids + ticket.team_id.visibility_member_ids.ids)]
            else:
                user_ids = mapped_data.get(helpdesk_user_group_id, [])
                ticket.domain_user_ids = [Command.set(user_ids)]

    def _compute_access_url(self):
        super(HelpdeskTicket, self)._compute_access_url()
        for ticket in self:
            ticket.access_url = '/my/ticket/%s' % ticket.id

    @api.depends('sla_status_ids.deadline', 'sla_status_ids.reached_datetime')
    def _compute_sla_reached_late(self):
        """ Required to do it in SQL since we need to compare 2 columns value """
        mapping = {}
        if self.ids:
            self.env.cr.execute("""
                SELECT ticket_id, COUNT(id) AS reached_late_count
                FROM helpdesk_sla_status
                WHERE ticket_id IN %s AND (deadline < reached_datetime OR (deadline < %s AND reached_datetime IS NULL))
                GROUP BY ticket_id
            """, (tuple(self.ids), fields.Datetime.now()))
            mapping = dict(self.env.cr.fetchall())

        for ticket in self:
            ticket.sla_reached_late = mapping.get(ticket.id, 0) > 0

    @api.depends('sla_status_ids.deadline', 'sla_status_ids.reached_datetime')
    def _compute_sla_deadline(self):
        """ Keep the deadline for the last stage (closed one), so a closed ticket can have a status failed.
            Note: a ticket in a closed stage will probably have no deadline
        """
        for ticket in self:
            deadline = False
            status_not_reached = ticket.sla_status_ids.filtered(
                lambda status: not status.reached_datetime and status.deadline)
            ticket.sla_deadline = min(status_not_reached.mapped('deadline')) if status_not_reached else deadline

    @api.depends('sla_deadline', 'sla_reached_late')
    def _compute_sla_fail(self):
        now = fields.Datetime.now()
        for ticket in self:
            if ticket.sla_deadline:
                ticket.sla_fail = (ticket.sla_deadline < now) or ticket.sla_reached_late
            else:
                ticket.sla_fail = ticket.sla_reached_late

    @api.model
    def _search_sla_fail(self, operator, value):
        datetime_now = fields.Datetime.now()
        if (value and operator in expression.NEGATIVE_TERM_OPERATORS) or (
                not value and operator not in expression.NEGATIVE_TERM_OPERATORS):  # is not failed
            return ['&', ('sla_reached_late', '=', False), '|', ('sla_deadline', '=', False),
                    ('sla_deadline', '>=', datetime_now)]
        return ['|', ('sla_reached_late', '=', True), ('sla_deadline', '<', datetime_now)]  # is failed

    @api.depends('sla_deadline', 'sla_reached_late')
    def _compute_sla_success(self):
        now = fields.Datetime.now()
        for ticket in self:
            ticket.sla_success = (ticket.sla_deadline and ticket.sla_deadline > now)

    @api.model
    def _search_sla_success(self, operator, value):
        datetime_now = fields.Datetime.now()
        if (value and operator in expression.NEGATIVE_TERM_OPERATORS) or (
                not value and operator not in expression.NEGATIVE_TERM_OPERATORS):  # is failed
            return [('sla_status_ids.reached_datetime', '>', datetime_now), ('sla_reached_late', '!=', False)]
        return [('sla_status_ids.reached_datetime', '<', datetime_now), ('sla_fail', '=', False)]  # is success

    @api.depends('team_id')
    def _compute_user_and_stage_ids(self):
        for ticket in self.filtered(lambda ticket: ticket.team_id):
            if not ticket.user_id:
                ticket.user_id = ticket.team_id._determine_user_to_assign()[ticket.team_id.id]
            if not ticket.stage_id or ticket.stage_id not in ticket.team_id.stage_ids:
                ticket.stage_id = ticket.team_id._determine_stage()[ticket.team_id.id]

    @api.depends('partner_id')
    def _compute_partner_name(self):
        for ticket in self:
            if ticket.partner_id:
                ticket.partner_name = ticket.partner_id.name

    @api.depends('partner_id')
    def _compute_partner_email(self):
        for ticket in self:
            if ticket.partner_id:
                ticket.partner_email = ticket.partner_id.email

    @api.depends('partner_id')
    def _compute_partner_phone(self):
        for ticket in self:
            if ticket.partner_id:
                ticket.partner_phone = ticket.partner_id.phone

    @api.depends('partner_id', 'partner_email', 'partner_phone')
    def _compute_partner_ticket_count(self):

        def _get_email_to_search(email):
            domain = tools.email_domain_extract(email)
            return ("@" + domain) if domain and domain not in iap_tools._MAIL_DOMAIN_BLACKLIST else email

        for ticket in self:
            domain = []
            partner_ticket = ticket
            if ticket.partner_email:
                email_search = _get_email_to_search(ticket.partner_email)
                domain = expression.OR([domain, [('partner_email', 'ilike', email_search)]])
            if ticket.partner_phone:
                domain = expression.OR([domain, [('partner_phone', 'ilike', ticket.partner_phone)]])
            if ticket.partner_id:
                domain = expression.OR(
                    [domain, [("partner_id", "child_of", ticket.partner_id.commercial_partner_id.id)]])
            if domain:
                partner_ticket = self.search(domain)
            ticket.partner_ticket_ids = partner_ticket
            ticket.partner_ticket_count = len(partner_ticket - ticket._origin) if partner_ticket else 0

    @api.depends('assign_date')
    def _compute_assign_hours(self):
        for ticket in self:
            create_date = fields.Datetime.from_string(ticket.create_date)
            if create_date and ticket.assign_date and ticket.team_id.resource_calendar_id:
                duration_data = ticket.team_id.resource_calendar_id.get_work_duration_data(create_date,
                                                                                           fields.Datetime.from_string(
                                                                                               ticket.assign_date),
                                                                                           compute_leaves=True)
                ticket.assign_hours = duration_data['hours']
            else:
                ticket.assign_hours = False

    @api.depends('create_date', 'close_date')
    def _compute_close_hours(self):
        for ticket in self:
            create_date = fields.Datetime.from_string(ticket.create_date)
            if create_date and ticket.close_date:
                duration_data = ticket.team_id.resource_calendar_id.get_work_duration_data(create_date,
                                                                                           fields.Datetime.from_string(
                                                                                               ticket.close_date),
                                                                                           compute_leaves=True)
                ticket.close_hours = duration_data['hours']
            else:
                ticket.close_hours = False

    @api.depends('close_hours')
    def _compute_open_hours(self):
        for ticket in self:
            if ticket.create_date:  # fix from https://github.com/odoo/enterprise/commit/928fbd1a16e9837190e9c172fa50828fae2a44f7
                if ticket.close_date:
                    time_difference = ticket.close_date - fields.Datetime.from_string(ticket.create_date)
                else:
                    time_difference = fields.Datetime.now() - fields.Datetime.from_string(ticket.create_date)
                ticket.open_hours = (time_difference.seconds) / 3600 + time_difference.days * 24
            else:
                ticket.open_hours = 0

    @api.model
    def _search_open_hours(self, operator, value):
        dt = fields.Datetime.now() - relativedelta(hours=value)

        d1, d2 = False, False
        if operator in ['<', '<=', '>', '>=']:
            d1 = ['&', ('close_date', '=', False), ('create_date', expression.TERM_OPERATORS_NEGATION[operator], dt)]
            d2 = ['&', ('close_date', '!=', False), ('close_hours', operator, value)]
        elif operator in ['=', '!=']:
            subdomain = ['&', ('create_date', '>=', dt.replace(minute=0, second=0, microsecond=0)),
                         ('create_date', '<=', dt.replace(minute=59, second=59, microsecond=99))]
            if operator in expression.NEGATIVE_TERM_OPERATORS:
                subdomain = expression.distribute_not(subdomain)
            d1 = expression.AND([[('close_date', '=', False)], subdomain])
            d2 = ['&', ('close_date', '!=', False), ('close_hours', operator, value)]
        return expression.OR([d1, d2])

    # ------------------------------------------------------------
    # ORM overrides
    # ------------------------------------------------------------

    def name_get(self):
        result = []
        for ticket in self:
            result.append((ticket.id, "%s (#%d)" % (ticket.ticket_number_display, ticket._origin.id)))
        return result

    @api.model
    def create_action(self, action_ref, title, search_view_ref):
        action = self.env["ir.actions.actions"]._for_xml_id(action_ref)
        if title:
            action['display_name'] = title
        if search_view_ref:
            action['search_view_id'] = self.env.ref(search_view_ref).read()[0]
        action['views'] = [(False, view) for view in action['view_mode'].split(",")]

        return {'action': action}

    @api.model_create_multi
    def create(self, list_value):
        now = fields.Datetime.now()
        # determine user_id and stage_id if not given. Done in batch.
        teams = self.env['helpdesk.team'].browse([vals['team_id'] for vals in list_value if vals.get('team_id')])
        team_default_map = dict.fromkeys(teams.ids, dict())
        for team in teams:
            team_default_map[team.id] = {
                'stage_id': team._determine_stage()[team.id].id,
                'user_id': team._determine_user_to_assign()[team.id].id
            }

        # Manually create a partner now since 'generate_recipients' doesn't keep the name. This is
        # to avoid intrusive changes in the 'mail' module
        # TDE TODO: to extract and clean in mail thread
        for vals in list_value:
            # Get next ticket number from the sequence
            vals['ticket_number'] = self.env['ir.sequence'].next_by_code('helpdesk.ticket')
            partner_id = vals.get('partner_id', False)
            partner_name = vals.get('partner_name', False)
            partner_email = vals.get('partner_email', False)
            if partner_name and partner_email and not partner_id:
                parsed_name, parsed_email = self.env['res.partner']._parse_partner_name(partner_email)
                if not parsed_name:
                    parsed_name = partner_name
                if vals.get('team_id'):
                    team = self.env['helpdesk.team'].browse(vals.get('team_id'))
                    company = team.company_id.id
                else:
                    company = False

                vals['partner_id'] = self.env['res.partner'].with_context(default_company_id=company).find_or_create(
                    tools.formataddr((parsed_name, parsed_email))
                ).id

        # determine partner email for ticket with partner but no email given
        partners = self.env['res.partner'].browse([vals['partner_id'] for vals in list_value if
                                                   'partner_id' in vals and vals.get(
                                                       'partner_id') and 'partner_email' not in vals])
        partner_email_map = {partner.id: partner.email for partner in partners}
        partner_name_map = {partner.id: partner.name for partner in partners}

        for vals in list_value:
            if vals.get('team_id'):
                team_default = team_default_map[vals['team_id']]
                if 'stage_id' not in vals:
                    vals['stage_id'] = team_default['stage_id']
                # Note: this will break the randomly distributed user assignment. Indeed, it will be too difficult to
                # equally assigned user when creating ticket in batch, as it requires to search after the last assigned
                # after every ticket creation, which is not very performant. We decided to not cover this user case.
                if 'user_id' not in vals:
                    vals['user_id'] = team_default['user_id']
                if vals.get(
                        'user_id'):  # if a user is finally assigned, force ticket assign_date and reset assign_hours
                    vals['assign_date'] = fields.Datetime.now()
                    vals['assign_hours'] = 0

            # set partner email if in map of not given
            if vals.get('partner_id') in partner_email_map:
                vals['partner_email'] = partner_email_map.get(vals['partner_id'])
            # set partner name if in map of not given
            if vals.get('partner_id') in partner_name_map:
                vals['partner_name'] = partner_name_map.get(vals['partner_id'])

            if vals.get('stage_id'):
                vals['date_last_stage_update'] = now
        # context: no_log, because subtype already handle this
        tickets = super(HelpdeskTicket, self).create(list_value)
        # make customer follower
        for ticket in tickets:
            if ticket.partner_id:
                ticket.message_subscribe(partner_ids=ticket.partner_id.ids)
            # Send FCM notification
            if ticket.user_id.fcm_token_id:
                # Retrieve all tokens for the user
                fcm_tokens = self.env['fcm.token'].search([('user_id', '=', ticket.user_id.id)])
                for token in fcm_tokens:
                    print('Sending notification to FCM token:', token.token)

                    # Try to load the service account key JSON file with error handling
                    try:
                        # Get Firebase config from system parameters
                        firebase_config_path = self.env['ir.config_parameter'].sudo().get_param('firebase_service_account_path')
                        
                        if not firebase_config_path:
                            _logger.warning("Firebase service account path not configured. Skipping FCM notification.")
                            continue
                            
                        # Load the service account key JSON file.
                        creds = ServiceAccountCredentials.from_json_keyfile_name(
                            firebase_config_path,
                            ['https://www.googleapis.com/auth/firebase.messaging']
                        )

                        # Obtain an access token.
                        access_token_info = creds.get_access_token()
                        access_token = access_token_info.access_token

                        print('Access token obtained:', access_token)

                        url = 'https://fcm.googleapis.com/v1/projects/ticket-76425/messages:send'
                        headers = {
                            'Content-Type': 'application/json',
                            'Authorization': 'Bearer ' + access_token,
                        }
                        data = {
                            'message': {
                                'token': token.token,
                                'notification': {
                                    'title': 'New Ticket: ' + str(ticket.ticket_number),
                                    'body': 'A new ticket has been assigned to you.',
                                },
                            },
                        }
                        try:
                            response = requests.post(url, headers=headers, data=json.dumps(data))
                            if response.status_code == 200:
                                print('Notification sent successfully to:', token.token)
                            else:
                                print('Notification not sent. Response:', response.content)
                        except Exception as e:
                            print('Error sending notification to:', token.token, 'Error:', e)
                    except FileNotFoundError:
                        _logger.error(f"Firebase service account file not found at configured path. Skipping FCM notification.")
                        continue
                    except Exception as e:
                        _logger.error(f"Error loading Firebase credentials: {str(e)}. Skipping FCM notification.")
                        continue
                        
                print('Retrieved FCM tokens for user:', ticket.user_id.id, 'Tokens:', [t.token for t in fcm_tokens])

            ticket._portal_ensure_token()

        # apply SLA
        tickets.sudo()._sla_apply()

        return tickets

    def write(self, vals):
        # we set the assignation date (assign_date) to now for tickets that are being assigned for the first time
        # same thing for the closing date
        assigned_tickets = closed_tickets = self.browse()
        if vals.get('user_id'):
            assigned_tickets = self.filtered(lambda ticket: not ticket.assign_date)

        if vals.get('stage_id'):
            if self.env['helpdesk.stage'].browse(vals.get('stage_id')).is_close:
                closed_tickets = self.filtered(lambda ticket: not ticket.close_date)
            else:  # auto reset the 'closed_by_partner' flag
                vals['closed_by_partner'] = False
                vals['close_date'] = False

        now = fields.Datetime.now()

        # update last stage date when changing stage
        if 'stage_id' in vals:
            vals['date_last_stage_update'] = now
            if 'kanban_state' not in vals:
                vals['kanban_state'] = 'normal'

        res = super(HelpdeskTicket, self - assigned_tickets - closed_tickets).write(vals)
        res &= super(HelpdeskTicket, assigned_tickets - closed_tickets).write(dict(vals, **{
            'assign_date': now,
        }))
        res &= super(HelpdeskTicket, closed_tickets - assigned_tickets).write(dict(vals, **{
            'close_date': now,
        }))
        res &= super(HelpdeskTicket, assigned_tickets & closed_tickets).write(dict(vals, **{
            'assign_date': now,
            'close_date': now,
        }))

        if vals.get('partner_id'):
            self.message_subscribe([vals['partner_id']])

        # SLA business
        sla_triggers = self._sla_reset_trigger()
        if any(field_name in sla_triggers for field_name in vals.keys()):
            self.sudo()._sla_apply(keep_reached=True)
        if 'stage_id' in vals:
            self.sudo()._sla_reach(vals['stage_id'])

        if 'user_id' in vals:
            for ticket in self:
                self._send_fcm_notification_to_user(vals['user_id'], ticket)

        return res

    # ------------------------------------------------------------
    # Actions and Business methods
    # ------------------------------------------------------------

    @api.model
    def _sla_reset_trigger(self):
        """ Get the list of field for which we have to reset the SLAs (regenerate) """
        return ['team_id', 'priority', 'ticket_type_id', 'tag_ids', 'partner_id']

    def _sla_apply(self, keep_reached=False):
        """ Apply SLA to current tickets: erase the current SLAs, then find and link the new SLAs to each ticket.
            Note: transferring ticket to a team "not using SLA" (but with SLAs defined), SLA status of the ticket will be
            erased but nothing will be recreated.
            :returns recordset of new helpdesk.sla.status applied on current tickets
        """
        # get SLA to apply
        sla_per_tickets = self._sla_find()

        # generate values of new sla status
        sla_status_value_list = []
        for tickets, slas in sla_per_tickets.items():
            sla_status_value_list += tickets._sla_generate_status_values(slas, keep_reached=keep_reached)

        sla_status_to_remove = self.mapped('sla_status_ids')
        if keep_reached:  # keep only the reached one to avoid losing reached_date info
            sla_status_to_remove = sla_status_to_remove.filtered(lambda status: not status.reached_datetime)

        # if we are going to recreate many sla.status, then add norecompute to avoid 2 recomputation (unlink + recreate). Here,
        # `norecompute` will not trigger recomputation. It will be done on the create multi (if value list is not empty).
        if sla_status_value_list:
            sla_status_to_remove.with_context(norecompute=True)

        # unlink status and create the new ones in 2 operations (recomputation optimized)
        sla_status_to_remove.unlink()
        return self.env['helpdesk.sla.status'].create(sla_status_value_list)

    def _sla_find_extra_domain(self):
        self.ensure_one()
        return [
            '|', '|', ('partner_ids', 'parent_of', self.partner_id.ids),
            ('partner_ids', 'child_of', self.partner_id.ids), ('partner_ids', '=', False)
        ]

    def _sla_find(self):
        """ Find the SLA to apply on the current tickets
            :returns a map with the tickets linked to the SLA to apply on them
            :rtype : dict {<helpdesk.ticket>: <helpdesk.sla>}
        """
        tickets_map = {}
        sla_domain_map = {}

        def _generate_key(ticket):
            """ Return a tuple identifying the combinaison of field determining the SLA to apply on the ticket """
            fields_list = self._sla_reset_trigger()
            key = list()
            for field_name in fields_list:
                if ticket._fields[field_name].type == 'many2one':
                    key.append(ticket[field_name].id)
                else:
                    key.append(ticket[field_name])
            return tuple(key)

        for ticket in self:
            if ticket.team_id.use_sla:  # limit to the team using SLA
                key = _generate_key(ticket)
                # group the ticket per key
                tickets_map.setdefault(key, self.env['helpdesk.ticket'])
                tickets_map[key] |= ticket
                # group the SLA to apply, by key
                if key not in sla_domain_map:
                    sla_domain_map[key] = expression.AND([[
                        ('team_id', '=', ticket.team_id.id), ('priority', '<=', ticket.priority),
                        ('stage_id.sequence', '>=', ticket.stage_id.sequence),
                        '|', ('ticket_type_id', '=', ticket.ticket_type_id.id), ('ticket_type_id', '=', False)],
                        ticket._sla_find_extra_domain()])

        result = {}
        for key, tickets in tickets_map.items():  # only one search per ticket group
            domain = sla_domain_map[key]
            slas = self.env['helpdesk.sla'].search(domain)
            result[tickets] = slas.filtered(lambda s: s.tag_ids <= tickets.tag_ids)  # SLA to apply on ticket subset
        return result

    def _sla_generate_status_values(self, slas, keep_reached=False):
        """ Return the list of values for given SLA to be applied on current ticket """
        status_to_keep = dict.fromkeys(self.ids, list())

        # generate the map of status to keep by ticket only if requested
        if keep_reached:
            for ticket in self:
                for status in ticket.sla_status_ids:
                    if status.reached_datetime:
                        status_to_keep[ticket.id].append(status.sla_id.id)

        # create the list of value, and maybe exclude the existing ones
        result = []
        for ticket in self:
            for sla in slas:
                if not (keep_reached and sla.id in status_to_keep[ticket.id]):
                    result.append({
                        'ticket_id': ticket.id,
                        'sla_id': sla.id,
                        'reached_datetime': fields.Datetime.now() if ticket.stage_id == sla.stage_id else False
                        # in case of SLA on first stage
                    })

        return result

    def _sla_reach(self, stage_id):
        """ Flag the SLA status of current ticket for the given stage_id as reached, and even the unreached SLA applied
            on stage having a sequence lower than the given one.
        """
        stage = self.env['helpdesk.stage'].browse(stage_id)
        stages = self.env['helpdesk.stage'].search([('sequence', '<=', stage.sequence), (
            'team_ids', 'in', self.mapped('team_id').ids)])  # take previous stages
        self.env['helpdesk.sla.status'].search([
            ('ticket_id', 'in', self.ids),
            ('sla_stage_id', 'in', stages.ids),
            ('reached_datetime', '=', False),
        ]).write({'reached_datetime': fields.Datetime.now()})

    def assign_ticket_to_self(self):
        self.ensure_one()
        self.user_id = self.env.user

    def action_open_helpdesk_ticket(self):
        self.ensure_one()
        action = self.env["ir.actions.actions"]._for_xml_id("helpdesk.helpdesk_ticket_action_main_tree")
        action.update({
            'domain': [('id', '!=', self.id), ('id', 'in', self.partner_ticket_ids.ids)],
            'context': {'create': False},
        })
        return action

    # ------------------------------------------------------------
    # Messaging API
    # ------------------------------------------------------------

    # DVE FIXME: if partner gets created when sending the message it should be set as partner_id of the ticket.
    def _message_get_suggested_recipients(self):
        recipients = super(HelpdeskTicket, self)._message_get_suggested_recipients()
        try:
            for ticket in self:
                if ticket.partner_id and ticket.partner_id.email:
                    ticket._message_add_suggested_recipient(recipients, partner=ticket.partner_id, reason=_('Customer'))
                elif ticket.partner_email:
                    ticket._message_add_suggested_recipient(recipients, email=ticket.partner_email,
                                                            reason=_('Customer Email'))
        except AccessError:  # no read access rights -> just ignore suggested recipients because this implies modifying followers
            pass
        return recipients

    def _ticket_email_split(self, msg):
        email_list = tools.email_split((msg.get('to') or '') + ',' + (msg.get('cc') or ''))
        # check left-part is not already an alias
        return [
            x for x in email_list
            if x.split('@')[0] not in self.mapped('team_id.alias_name')
        ]

    @api.model
    def message_new(self, msg, custom_values=None):
        values = dict(custom_values or {}, partner_email=msg.get('from'), partner_name=msg.get('from'),
                      partner_id=msg.get('author_id'))
        ticket = super(HelpdeskTicket, self.with_context(mail_notify_author=True)).message_new(msg,
                                                                                               custom_values=values)
        partner_ids = [x.id for x in
                       self.env['mail.thread']._mail_find_partner_from_emails(self._ticket_email_split(msg),
                                                                              records=ticket) if x]
        customer_ids = [p.id for p in self.env['mail.thread']._mail_find_partner_from_emails(
            tools.email_split(values['partner_email']), records=ticket) if p]
        partner_ids += customer_ids
        if customer_ids and not values.get('partner_id'):
            ticket.partner_id = customer_ids[0]
        if partner_ids:
            ticket.message_subscribe(partner_ids)
        return ticket

    def message_update(self, msg, update_vals=None):
        partner_ids = [x.id for x in
                       self.env['mail.thread']._mail_find_partner_from_emails(self._ticket_email_split(msg),
                                                                              records=self) if x]
        if partner_ids:
            self.message_subscribe(partner_ids)
        return super(HelpdeskTicket, self).message_update(msg, update_vals=update_vals)

    def _message_post_after_hook(self, message, msg_vals):
        if self.partner_email and self.partner_id and not self.partner_id.email:
            self.partner_id.email = self.partner_email

        if self.partner_email and not self.partner_id:
            # we consider that posting a message with a specified recipient (not a follower, a specific one)
            # on a document without customer means that it was created through the chatter using
            # suggested recipients. This heuristic allows to avoid ugly hacks in JS.
            new_partner = message.partner_ids.filtered(lambda partner: partner.email == self.partner_email)
            if new_partner:
                self.search([
                    ('partner_id', '=', False),
                    ('partner_email', '=', new_partner.email),
                    ('stage_id.fold', '=', False)]).write({'partner_id': new_partner.id})
        return super(HelpdeskTicket, self)._message_post_after_hook(message, msg_vals)

    def _track_template(self, changes):
        res = super(HelpdeskTicket, self)._track_template(changes)
        ticket = self[0]
        if 'stage_id' in changes and ticket.stage_id.template_id:
            res['stage_id'] = (ticket.stage_id.template_id, {
                'auto_delete_message': True,
                'subtype_id': self.env['ir.model.data']._xmlid_to_res_id('mail.mt_note'),
                'email_layout_xmlid': 'mail.mail_notification_light'
            }
                               )
        return res

    def _creation_subtype(self):
        return self.env.ref('helpdesk.mt_ticket_new')

    def _track_subtype(self, init_values):
        self.ensure_one()
        if 'stage_id' in init_values:
            return self.env.ref('helpdesk.mt_ticket_stage')
        return super(HelpdeskTicket, self)._track_subtype(init_values)

    def _notify_get_groups(self, msg_vals=None):
        """ Handle helpdesk users and managers recipients that can assign
        tickets directly from notification emails. Also give access button
        to portal and portal customers. If they are notified they should
        probably have access to the document. """
        groups = super(HelpdeskTicket, self)._notify_get_groups(msg_vals=msg_vals)

        self.ensure_one()
        for group_name, _group_method, group_data in groups:
            if group_name != 'customer':
                group_data['has_button_access'] = True

        if self.user_id:
            return groups

        local_msg_vals = dict(msg_vals or {})
        take_action = self._notify_get_action_link('assign', **local_msg_vals)
        helpdesk_actions = [{'url': take_action, 'title': _('Assign to me')}]
        helpdesk_user_group_id = self.env.ref('helpdesk.group_helpdesk_user').id
        new_groups = [(
            'group_helpdesk_user',
            lambda pdata: pdata['type'] == 'user' and helpdesk_user_group_id in pdata['groups'],
            {'actions': helpdesk_actions}
        )]
        return new_groups + groups

    def _notify_get_reply_to(self, default=None, records=None, company=None, doc_names=None):
        """ Override to set alias of tickets to their team if any. """
        aliases = self.mapped('team_id').sudo()._notify_get_reply_to(default=default, records=None, company=company,
                                                                     doc_names=None)
        res = {ticket.id: aliases.get(ticket.team_id.id) for ticket in self}
        leftover = self.filtered(lambda rec: not rec.team_id)
        if leftover:
            res.update(
                super(HelpdeskTicket, leftover)._notify_get_reply_to(default=default, records=None, company=company,
                                                                     doc_names=doc_names))
        return res

    # ------------------------------------------------------------
    # Rating Mixin
    # ------------------------------------------------------------

    def rating_apply(self, rate, token=None, feedback=None, subtype_xmlid=None):
        return super(HelpdeskTicket, self).rating_apply(rate, token=token, feedback=feedback,
                                                        subtype_xmlid="helpdesk.mt_ticket_rated")

    def _rating_get_parent_field_name(self):
        return 'team_id'

    # ---------------------------------------------------
    # Mail gateway
    # ---------------------------------------------------

    def _mail_get_message_subtypes(self):
        res = super()._mail_get_message_subtypes()
        if len(self) == 1 and self.team_id:
            team = self.team_id
            optional_subtypes = [('use_credit_notes', self.env.ref('helpdesk.mt_ticket_refund_posted')),
                                 ('use_product_returns', self.env.ref('helpdesk.mt_ticket_return_done')),
                                 ('use_product_repairs', self.env.ref('helpdesk.mt_ticket_repair_done'))]
            for field, subtype in optional_subtypes:
                if not team[field] and subtype in res:
                    res -= subtype
        return res

    def open_close_ticket_wizard(self):
        # Ensure 'self' is a valid record
        if not self:
            _logger.error("Attempted to open close ticket wizard on an invalid record.")
            return {}
        return {
            'name': "Close Support Ticket",
            'type': 'ir.actions.act_window',
            'view_type': 'form',
            'view_mode': 'form',
            'res_model': 'helpdesk.ticket.close',
            'context': {'default_ticket_id': self.id},
            'target': 'new'
        }

class HelpdeskImageUpload(Controller):
    @route('/api/helpdesk/upload_file', type='json', auth='public', methods=['POST'])
    def upload_ticket_file(self, ticket_id, file_name, file_data):
        """ API to upload a file to a helpdesk ticket """
        ticket = request.env['helpdesk.ticket'].sudo().browse(ticket_id)
        if not ticket.exists():
            return {"error": "Ticket not found"}

        file_data_decoded = base64.b64decode(file_data)
        attachment_id = ticket.upload_file_to_description(file_name, file_data_decoded)

        return {"success": True, "attachment_id": attachment_id}
    
class FCMTokenController(http.Controller):
    @http.route('/fcm/token', type='json', auth='user', methods=['POST'])
    def create_fcm_token(self, **kwargs):
        try:
            user = request.env.user
            token = kwargs.get('token')

            if not token:
                return {'error': 'Token is required'}
            
            # Check for existing token (unique on token only)
            existing_token = request.env['x_fcm.device.token'].sudo().search([
                ('token', '=', token)
            ], limit=1)
            if existing_token:
                return {'success': True, 'token_id': existing_token.id, 'message': 'Token already exists'}
            
            fcm_token = request.env['x_fcm.device.token'].sudo().create({
                'user_id': user.id,
                'token': token,
            })

            return {'success': True, 'token_id': fcm_token.id}
        except Exception as e:
            _logger.error(f"❌ Error in create_fcm_token: {str(e)}")
            return {'error': f'Failed to create FCM token: {str(e)}'}

    @http.route('/api/fcm/token', type='json', auth='public', methods=['POST'], csrf=False)
    def store_fcm_token_api(self, **kwargs):
        """ API endpoint untuk menyimpan FCM token dari Flutter """
        # Manually parse the JSON body to avoid parameter mapping issues
        data = request.jsonrequest
        user_id = data.get('user_id')
        token = data.get('token') or data.get('fcm_token')  # Support both 'token' and 'fcm_token'
        
        _logger.info(f"FCM token request received with raw data: {data}")
        try:
            if not user_id or not token:
                raise ValidationError(f"user_id and token are required. Received: {data}")

            user = request.env['res.users'].sudo().browse(int(user_id))
            if not user.exists():
                raise ValidationError(f"User with id {user_id} not found.")

            # Check if token already exists for this user
            existing_token = request.env['fcm.token'].sudo().search([
                ('user_id', '=', user.id),
                ('token', '=', token)
            ], limit=1)

            if not existing_token:
                # Create new token
                request.env['fcm.token'].sudo().create({
                    'user_id': user.id,
                    'token': token,
                })
                _logger.info(f"✅ FCM Token stored for user {user.id}: {token}")
            else:
                _logger.info(f"ℹ️ FCM Token already exists for user {user.id}")

            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": True, 
                    "message": "✅ FCM Token stored successfully"
                }
            }

        except Exception as e:
            _logger.error(f"❌ Error storing FCM token: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Failed to store FCM token: {str(e)}",
                    "code": 500
                }
            }

    @http.route('/api/fcm/token/public', type='json', auth='public', methods=['POST'], csrf=False)
    def store_fcm_token_public(self, **kwargs):
        """ Public API endpoint untuk menyimpan FCM token dengan authentication yang lebih fleksibel """
        try:
            # Get user credentials from request
            user_id = kwargs.get('user_id')
            token = kwargs.get('token')
            api_key = kwargs.get('api_key')  # Optional API key for additional security
            
            if not all([user_id, token]):
                return {
                    "jsonrpc": "2.0", 
                    "error": {
                        "message": "user_id and token are required", 
                        "code": 400
                    }
                }
            
            # Validate user exists
            user = request.env['res.users'].sudo().browse(int(user_id))
            if not user.exists():
                return {
                    "jsonrpc": "2.0", 
                    "error": {
                        "message": "User not found", 
                        "code": 404
                    }
                }
            
            # Optional API key validation (if configured)
            if api_key:
                configured_api_key = request.env['ir.config_parameter'].sudo().get_param('fcm.api.key')
                if configured_api_key and api_key != configured_api_key:
                    return {
                        "jsonrpc": "2.0", 
                        "error": {
                            "message": "Invalid API key", 
                            "code": 401
                        }
                    }
            
            # Check if token already exists for this user
            existing_token = request.env['fcm.token'].sudo().search([
                ('user_id', '=', user_id), 
                ('token', '=', token)
            ], limit=1)
            
            if not existing_token:
                # Create new token
                fcm_token = request.env['fcm.token'].sudo().create({
                    'user_id': int(user_id),
                    'token': token,
                })
                _logger.info(f"✅ FCM Token stored for user {user_id}: {token}")
            else:
                _logger.info(f"ℹ️ FCM Token already exists for user {user_id}")
            
            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": True, 
                    "message": "✅ FCM Token stored successfully",
                    "user_id": user_id
                }
            }
            
        except Exception as e:
            _logger.error(f"❌ Error storing FCM token (public): {str(e)}")
            return {
                "jsonrpc": "2.0", 
                "error": {
                    "message": f"Failed to store FCM token: {str(e)}", 
                    "code": 500
                }
            }

    @http.route('/api/fcm/token/refresh', type='json', auth='public', methods=['POST'], csrf=False)
    def refresh_fcm_token(self, **kwargs):
        """ Endpoint untuk refresh FCM token dan session """
        try:
            user_id = kwargs.get('user_id')
            old_token = kwargs.get('old_token')
            new_token = kwargs.get('new_token')
            
            if not all([user_id, old_token, new_token]):
                return {
                    "jsonrpc": "2.0", 
                    "error": {
                        "message": "user_id, old_token, and new_token are required", 
                        "code": 400
                    }
                }
            
            # Find and update the old token
            existing_token = request.env['fcm.token'].sudo().search([
                ('user_id', '=', int(user_id)), 
                ('token', '=', old_token)
            ], limit=1)
            
            if existing_token:
                existing_token.write({'token': new_token})
                _logger.info(f"✅ FCM Token refreshed for user {user_id}")
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True, 
                        "message": "✅ FCM Token refreshed successfully"
                    }
                }
            else:
                # If old token not found, create new one
                request.env['fcm.token'].sudo().create({
                    'user_id': int(user_id),
                    'token': new_token,
                })
                _logger.info(f"✅ New FCM Token created for user {user_id}")
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True, 
                        "message": "✅ New FCM Token created successfully"
                    }
                }
                
        except Exception as e:
            _logger.error(f"❌ Error refreshing FCM token: {str(e)}")
            return {
                "jsonrpc": "2.0", 
                "error": {
                    "message": f"Failed to refresh FCM token: {str(e)}", 
                    "code": 500
                }
            }

    @http.route('/api/fcm/token/validate', type='json', auth='public', methods=['POST'], csrf=False)
    def validate_fcm_token(self, **kwargs):
        """ Endpoint untuk validate FCM token """
        try:
            user_id = kwargs.get('user_id')
            token = kwargs.get('token')
            
            if not all([user_id, token]):
                return {
                    "jsonrpc": "2.0", 
                    "error": {
                        "message": "user_id and token are required", 
                        "code": 400
                    }
                }
            
            # Check if token exists
            existing_token = request.env['fcm.token'].sudo().search([
                ('user_id', '=', int(user_id)), 
                ('token', '=', token)
            ], limit=1)
            
            return {
                "jsonrpc": "2.0",
                "result": {
                    "valid": bool(existing_token),
                    "message": "Token is valid" if existing_token else "Token not found"
                }
            }
                
        except Exception as e:
            _logger.error(f"❌ Error validating FCM token: {str(e)}")
            return {
                "jsonrpc": "2.0", 
                "error": {
                    "message": f"Failed to validate FCM token: {str(e)}", 
                    "code": 500
                }
            }

    @http.route('/api/session/status', type='json', auth='public', methods=['POST'], csrf=False)
    def check_session_status(self, **kwargs):
        """ Endpoint untuk check session status dan provide session info """
        try:
            user_id = kwargs.get('user_id')
            
            if not user_id:
                return {
                    "jsonrpc": "2.0", 
                    "error": {
                        "message": "user_id is required", 
                        "code": 400
                    }
                }
            
            # Check if user exists
            user = request.env['res.users'].sudo().browse(int(user_id))
            if not user.exists():
                return {
                    "jsonrpc": "2.0", 
                    "error": {
                        "message": "User not found", 
                        "code": 404
                    }
                }
            
            # Check if user has FCM tokens
            fcm_tokens = request.env['fcm.token'].sudo().search([
                ('user_id', '=', int(user_id))
            ])
            
            return {
                "jsonrpc": "2.0",
                "result": {
                    "user_id": user_id,
                    "user_name": user.name,
                    "user_active": user.active,
                    "fcm_tokens_count": len(fcm_tokens),
                    "session_valid": True,
                    "timestamp": fields.Datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                }
            }
                
        except Exception as e:
            _logger.error(f"❌ Error checking session status: {str(e)}")
            return {
                "jsonrpc": "2.0", 
                "error": {
                    "message": f"Failed to check session status: {str(e)}", 
                    "code": 500
                }
            }

    @http.route('/test_fcm_endpoint', type='http', auth='user', methods=['GET'])
    def test_fcm_endpoint(self):
        """ Test endpoint untuk memastikan routing berfungsi """
        return "FCM endpoints are working correctly!"

    @http.route('/api/test_fcm', type='json', auth='user', methods=['POST'])
    def test_fcm_json(self, **kwargs):
        """ Test JSON endpoint untuk FCM """
        return {
            "jsonrpc": "2.0",
            "result": {
                "success": True,
                "message": "FCM JSON endpoint is working!"
            }
        }

    @http.route('/api/test_fcm/public', type='json', auth='public', methods=['POST'], csrf=False)
    def test_fcm_public(self, **kwargs):
        """ Test public JSON endpoint untuk FCM """
        return {
            "jsonrpc": "2.0",
            "result": {
                "success": True,
                "message": "FCM Public endpoint is working!",
                "timestamp": fields.Datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            }
        }

    @http.route('/api/public_update_fcm_token', type='json', auth='public', methods=['POST'], csrf=False)
    def public_update_fcm_token(self, **kwargs):
        token = kwargs.get('token')
        user_email = kwargs.get('email')  # Optional: for associating with a user
        if not token:
            return {'success': False, 'error': 'Token is required'}
        user = None
        if user_email:
            user = request.env['res.users'].sudo().search([('login', '=', user_email)], limit=1)
        try:
            vals = {'token': token}
            if user:
                vals['user_id'] = user.id
                # Check for existing token
                existing_token = request.env['fcm.token'].sudo().search([
                    ('user_id', '=', user.id),
                    ('token', '=', token)
                ], limit=1)
                if existing_token:
                    return {'success': True, 'token_id': existing_token.id, 'message': 'Token already exists'}
            # If not found, create new
            fcm_token = request.env['fcm.token'].sudo().create(vals)
            return {'success': True, 'token_id': fcm_token.id}
        except Exception as e:
            return {'success': False, 'error': str(e)}


class HelpdeskCheckController(http.Controller):

    @http.route('/api/update_check_in', type='json', auth='user', methods=['POST'])
    def api_update_check_in(self, ticket_id, check_in_time):
        """ API untuk update Check-In dalam tiket """
        try:
            _logger.info(f"🔹 API Check-In Request: Ticket ID: {ticket_id}, Time: {check_in_time}")

            # 1️⃣ Pastikan parameter tidak kosong
            if not ticket_id or not check_in_time:
                _logger.error("❌ Parameter tidak lengkap untuk check-in.")
                return {"jsonrpc": "2.0", "error": {"message": "Invalid parameters", "code": 400}}

            # 2️⃣ Semak jika tiket wujud
            ticket = request.env['helpdesk.ticket'].sudo().browse(ticket_id)
            if not ticket.exists():
                _logger.error(f"❌ Ticket ID {ticket_id} tidak wujud!")
                return {"jsonrpc": "2.0", "error": {"message": "Ticket not found", "code": 404}}

            # 3️⃣ Pastikan format waktu adalah betul
            try:
                check_in_datetime = datetime.strptime(check_in_time, '%Y-%m-%d %H:%M:%S')
            except ValueError:
                _logger.error(f"❌ Format Check-In tidak sah: {check_in_time}")
                return {"jsonrpc": "2.0", "error": {"message": "Invalid check-in time format", "code": 400}}

            # 4️⃣ Simpan Check-In dalam tiket
            ticket.write({
                'check_in_string': check_in_time,
                'check_in': check_in_datetime,
            })
            _logger.info(f"✅ Check-In dikemaskini untuk Ticket {ticket_id}: {check_in_time}")

            return {
                "jsonrpc": "2.0",
                "result": {"success": True, "message": f"✅ Check-In dikemaskini untuk Ticket {ticket_id}"}
            }
        except Exception as e:
            _logger.error(f"❌ Ralat tidak dijangka dalam Check-In: {str(e)}")
            return {"jsonrpc": "2.0", "error": {"message": str(e), "code": 500}}

    @http.route('/api/update_check_out', type='json', auth='user', methods=['POST'])
    def api_update_check_out(self, ticket_id, check_out_time):
        """ API untuk update Check-Out dalam tiket """
        try:
            _logger.info(f"🔹 API Check-Out Request: Ticket ID: {ticket_id}, Time: {check_out_time}")

            # 1️⃣ Pastikan parameter tidak kosong
            if not ticket_id or not check_out_time:
                _logger.error("❌ Parameter tidak lengkap untuk check-out.")
                return {"jsonrpc": "2.0", "error": {"message": "Invalid parameters", "code": 400}}

            # 2️⃣ Semak jika tiket wujud
            ticket = request.env['helpdesk.ticket'].sudo().browse(ticket_id)
            if not ticket.exists():
                _logger.error(f"❌ Ticket ID {ticket_id} tidak wujud!")
                return {"jsonrpc": "2.0", "error": {"message": "Ticket not found", "code": 404}}

            # 3️⃣ Pastikan format waktu adalah betul
            try:
                check_out_datetime = datetime.strptime(check_out_time, '%Y-%m-%d %H:%M:%S')
            except ValueError:
                _logger.error(f"❌ Format Check-Out tidak sah: {check_out_time}")
                return {"jsonrpc": "2.0", "error": {"message": "Invalid check-out time format", "code": 400}}

            # 4️⃣ Simpan Check-Out dalam tiket
            ticket.write({
                'check_out_string': check_out_time,
                'check_out': check_out_datetime,
            })
            _logger.info(f"✅ Check-Out dikemaskini untuk Ticket {ticket_id}: {check_out_time}")

            return {
                "jsonrpc": "2.0",
                "result": {"success": True, "message": f"✅ Check-Out dikemaskini untuk Ticket {ticket_id}"}
            }
        except Exception as e:
            _logger.error(f"❌ Ralat tidak dijangka dalam Check-Out: {str(e)}")
            return {"jsonrpc": "2.0", "error": {"message": str(e), "code": 500}}


class FCMToken(models.Model):
    _name = 'x_fcm.device.token'
    _description = 'FCM Token'
    
    user_id = fields.Many2one('res.users', string='User', required=True)
    token = fields.Char(string='FCM Token', required=True, index=True)
    create_date = fields.Datetime(string='Created Date', readonly=True)

    _sql_constraints = [
        ('unique_fcm_token', 'unique(token)', 'The FCM token must be unique!')
    ]


def write(self, vals):
    """ Kemaskini medan check-in & check-out secara automatik """
    _logger.info(f"📝 [WRITE] Updating Ticket ID {self.id} with values: {vals}")

    if 'check_in_string' in vals:
        try:
            vals['check_in'] = datetime.strptime(vals['check_in_string'], '%Y-%m-%d %H:%M:%S')
        except ValueError:
            _logger.error(f"❌ Format Check-In tidak sah: {vals['check_in_string']}")
            vals['check_in'] = False

    if 'check_out_string' in vals:
        try:
            vals['check_out'] = datetime.strptime(vals['check_out_string'], '%Y-%m-%d %H:%M:%S')
        except ValueError:
            _logger.error(f"❌ Format Check-Out tidak sah: {vals['check_out_string']}")
            vals['check_out'] = False

    res = super(HelpdeskTicket, self).write(vals)
    _logger.info(f"✅ Check-Out updated successfully for Ticket ID: {self.id}")

    return res


@api.model
def api_update_check_in(self, ticket_id, check_in_time):
    try:
        if not ticket_id or not check_in_time:
            return {"jsonrpc": "2.0", "error": {"message": "Invalid parameters", "code": 400}}

        ticket = self.sudo().browse(ticket_id)
        if not ticket.exists():
            return {"jsonrpc": "2.0", "error": {"message": "Ticket not found", "code": 404}}

        # Pastikan `check_in_string` dan `check_in` dikemas kini
        ticket.write({
            'check_in_string': check_in_time,
        })

        return {
            "jsonrpc": "2.0",
            "result": {"success": True, "message": f"✅ Check-In updated for Ticket {ticket_id}"}
        }
    except Exception as e:
        _logger.error(f"❌ Error updating Check-In: {str(e)}")
        return {"jsonrpc": "2.0", "error": {"message": str(e), "code": 500}}


@api.model
def api_update_check_out(self, ticket_id, check_out_time):
    try:
        if not ticket_id or not check_out_time:
            return {"jsonrpc": "2.0", "error": {"message": "Invalid parameters", "code": 400}}

        ticket = self.sudo().browse(ticket_id)
        if not ticket.exists():
            return {"jsonrpc": "2.0", "error": {"message": "Ticket not found", "code": 404}}

        # Pastikan `check_in_string` dan `check_in` dikemas kini
        ticket.write({
            'check_out_string': check_out_time,
        })

        return {
            "jsonrpc": "2.0",
            "result": {"success": True, "message": f"✅ Check-Out updated for Ticket {ticket_id}"}
        }
    except Exception as e:
        _logger.error(f"❌ Error updating Check-Out: {str(e)}")
        return {"jsonrpc": "2.0", "error": {"message": str(e), "code": 500}}    
   
class FcmToken(models.Model):
    _name = 'fcm.token'

    token = fields.Char(string='FCM Token', required=True)
    user_id = fields.Many2one('res.users', string='User', required=True)

    @api.model
    def store_fcm_token(self, user_id, token):
        # Check if a record with the same user ID and token already exists
        existing_token = self.search([('user_id', '=', user_id), ('token', '=', token)], limit=1)
        if not existing_token:
            # If not, create a new record
            self.create({'user_id': user_id, 'token': token})
            print('Stored FCM token for user ', user_id, ': ', token)
        else:
            print('FCM token for user ', user_id, ' already exists: ', token)

class FcmTokenController(http.Controller):
    @http.route('/store_fcm_token', type='json', auth='user', methods=['POST'])
    def store_fcm_token(self, token):
        """ Simpan FCM Token dalam Odoo dari Flutter """
        user = request.env.user
        if not token:
            return {"error": "Token is required"}
        
        request.env['fcm.token'].sudo().store_fcm_token(user.id, token)
        return {"success": True, "message": "✅ FCM Token stored successfully"}


class ResUsers(models.Model):
    _inherit = 'res.users'

    x_notification_email = fields.Char(string="Notification Email", help="The email address to which push notifications should be sent, if different from the login email.")
    fcm_token_id = fields.One2many('fcm.token', 'user_id', string='FCM Token')

class HelpdeskTicketCategories(models.Model):
    _name = "helpdesk.ticket.categories"
    _order = "sequence asc"

    sequence = fields.Integer(string="Sequence")
    name = fields.Char(required=True, translate=True, string='Category Name')
    color = fields.Integer('Color Index', default=1)

    # commented out to solve creating user by admin issues@hafizalwi2Dec
    @api.model
    @api.constrains('name')
    def _check_duplicate(self):
        for record in self:
            category_tags = record.env['helpdesk.ticket.categories'].search_read(
                [('name', 'in', [record.name])])
            if len(category_tags) > 1:
                raise ValidationError(
                    _("You can't create 2 category with the same name!\n Please try creating with a different category name."))

    @api.model
    def create(self, values):
        sequence = self.env['ir.sequence'].next_by_code('helpdesk.ticket.categories')
        values['sequence'] = sequence
        return super(HelpdeskTicketCategories, self).create(values)

    def action_view_ticket(self):
        action = self.env["ir.actions.actions"]._for_xml_id("helpdesk.helpdesk_ticket_action_team")
        action['display_name'] = self.name
        return action

    def action_view_open_ticket_view(self):
        action = self.action_view_ticket()
        action.update({
            'display_name': _("Tickets"),
            'domain': [('team_id', '=', self.id), ('stage_id.is_close', '=', False)],
        })
        return action


class HelpdeskTicketSubCategories(models.Model):
    _name = "helpdesk.ticket.subcategory"
    _order = "sequence asc"

    sequence = fields.Integer(string="Sequence")
    name = fields.Char(required=True, translate=True, string='Sub Category Name')
    parent_category_id = fields.Many2one('helpdesk.ticket.categories', required=True,
                                         string="Category")  # default=lambda self: self.env['helpdesk.ticket'].search(['category.id','=',self.sub_category_id.id]).category.id) #default=lambda self: self.env['helpdesk.ticket'].search(['category.id','=',self.category.id]).category.id)

    @api.model
    @api.constrains('name', 'parent_category_id', )
    def _check_duplicate(self):
        for record in self:
            subcategory_tags = record.env['helpdesk.ticket.subcategory'].search_read(
                [('name', 'in', [record.name]),
                 ('parent_category_id', '=', record.parent_category_id.id)])  # TODO 14/2/2023
            if len(subcategory_tags) > 1:
                raise ValidationError(
                    _("You can't create 2 subcategory with the same name for each category!\n Please try creating with a different subcategory name or a different category name."))

    @api.model
    def create(self, values):
        sequence = self.env['ir.sequence'].next_by_code('helpdesk.ticket.subcategory')
        values['sequence'] = sequence
        return super(HelpdeskTicketSubCategories, self).create(values)


# class WebsiteSupportTicketSubCategoryField(models.Model):
#    _name = "helpdesk.ticket.subcategory.field"
#
#    wsts_id = fields.Many2one('helpdesk.ticket.subcategory', string="Sub Category")
#    name = fields.Char(string="Label", required="True")
#    type = fields.Selection([('textbox', 'Textbox'), ('many2one', 'Dropdown(m2o)')], default="textbox", required="True",
#                            string="Type")
#    model_id = fields.Many2one('ir.model', string="Model")
#    model_name = fields.Char(related="model_id.model", string="Model Name")
#    filter = fields.Char(string="Filter", default="[]", required="True")


class HelpdeskTicketProblem(models.Model):
    _name = "helpdesk.ticket.problem"
    _order = "sequence asc"

    sequence = fields.Integer(string="Sequence")
    name = fields.Char(required=True, string="Problem Name")
    parent_subcategory_id = fields.Many2one('helpdesk.ticket.subcategory', required=True,
                                            string="Sub Category", context="{'default_abc_vendor_id': id}")

    @api.model
    @api.constrains('name', 'parent_subcategory_id', )
    def _check_duplicate(self):
        for record in self:
            problem_tags = self.env['helpdesk.ticket.problem'].search_read(
                [('name', 'in', [record.name]), ('parent_subcategory_id', '=', record.parent_subcategory_id.id)])
            if len(problem_tags) > 1:
                raise ValidationError(
                    _("You can't create 2 problem tags with the same problem_name and subcategory!\n Please try creating with a different subcategory or a different problem name."))

    @api.model
    def create(self, values):
        sequence = self.env['ir.sequence'].next_by_code('helpdesk.ticket.problem')
        values['sequence'] = sequence
        return super(HelpdeskTicketProblem, self).create(values)


class WebsiteSupportTicketClose(models.TransientModel):
    _name = "helpdesk.ticket.close"

    ticket_id = fields.Many2one('helpdesk.ticket', string="Ticket ID")
    message = fields.Text(string="Close Message")
    cm_form = fields.Char(string="CM Form")
    case_done = fields.Datetime(string="Date of completion")
    template_id = fields.Many2one('mail.template', string="Mail Template",
                                  domain="[('model_id','=','helpdesk.ticket'), ('built_in','=',False)]")
    support_level_id = fields.Many2one('helpdesk.ticket.level', string="Support Level")  # hafiz 18 feb 2022
    attachment_ids = fields.Many2many('ir.attachment', 'sms_close_attachment_rel', 'sms_close_id', 'attachment_id',
                                      'Attachments')

    @api.onchange('template_id')
    def _onchange_template_id(self):
        if self.template_id:
            try:
                values = \
                    self.env['mail.compose.message'].generate_email_for_composer(self.template_id.id,
                                                                                 [self.ticket_id.id])[
                        self.ticket_id.id]
                self.message = values['body']
            except Exception as e:
                _logger.error("Error generating email for composer: %s", e)

    def close_ticket(self):  # @hafiz15dec
        # Ensure 'self.ticket_id' is a valid record
        if not self.ticket_id:
            _logger.error("Attempted to close a ticket without a valid ticket_id.")
            return

        try:
            self.ticket_id.close_time = datetime.now()

            # Also set the date for gamification
            self.ticket_id.close_date = datetime.today().date()

            # Directly subtract datetime objects to get the difference
            diff_time = self.ticket_id.close_time - self.ticket_id.create_date

            diff_time_days = diff_time.days
            diff_time_seconds = diff_time.seconds
            diff_time_hours = diff_time_seconds / 3600 + (diff_time_days * 24)

            self.ticket_id.time_to_close_hhmm = float(str(diff_time_hours))
            self.ticket_id.time_to_close = diff_time.total_seconds()

            # Assign the ticket to the "Solved" stage
            self.ticket_id.stage_id = self.env.ref('helpdesk.stage_solved')

            # Save the attachment_ids if any
            if self.attachment_ids:
                self.ticket_id.attachment_ids = [(6, 0, self.attachment_ids.ids)]

            # Handle message cleaning only if message exists and is a string
            if self.message and isinstance(self.message, str):
                cleanbreak = re.compile('<br\s*?>')
                cleanedbreak = re.sub(cleanbreak, '\n', self.message)
                cleanr = re.compile('<.*?>|&([a-z0-9]+|#[0-9]{1,6}|#x[0-9a-f]{1,6});')
                self.ticket_id.close_comment = re.sub(cleanr, '', cleanedbreak)
            else:
                # Set a default message if none provided
                self.ticket_id.close_comment = "Ticket closed by %s" % self.env.user.name

            self.ticket_id.cmform = self.cm_form
            self.ticket_id.prob_solve_time = self.case_done
            self.ticket_id.closed_by_id = self.env.user.id
            self.ticket_id.sla_active = False

            # Log the action
            self.ticket_id.message_post(
                body=f"Ticket closed by {self.env.user.name}",
                message_type='notification',
                subtype_xmlid='mail.mt_note'
            )

            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": True,
                    "message": "Ticket closed successfully"
                }
            }

        except Exception as e:
            _logger.error(f"Error closing ticket: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "code": 500,
                    "message": f"Failed to close ticket: {str(e)}"
                }
            }


class WebsiteSupportTicketMerge(models.TransientModel):
    _name = "helpdesk.ticket.merge"

    ticket_id = fields.Many2one('helpdesk.ticket', ondelete="cascade", string="Support Ticket")
    merge_ticket_id = fields.Many2one('helpdesk.ticket', ondelete="cascade", required="True",
                                      string="Merge With")

    def merge_tickets(self):

        self.ticket_id.close_time = datetime.datetime.now()

        # Also set the date for gamification
        self.ticket_id.close_date = datetime.date.today()

        diff_time = datetime.datetime.strptime(self.ticket_id.close_time,
                                               DEFAULT_SERVER_DATETIME_FORMAT) - datetime.datetime.strptime(
            self.ticket_id.create_date, DEFAULT_SERVER_DATETIME_FORMAT)

        self.ticket_id.time_to_close = diff_time.seconds

        closed_state = self.env['ir.model.data'].sudo().get_object('website_supportzayd',
                                                                   'website_ticket_state_staff_closed')
        self.ticket_id.state = closed_state.id

        # Lock the ticket to prevent reopening
        self.ticket_id.ticket = True

        # Send merge email
        setting_ticket_merge_email_template_id = self.env['ir.default'].get('helpdesk.settings',
                                                                            'ticket_merge_email_template_id')
        if setting_ticket_merge_email_template_id:
            mail_template = self.env['mail.template'].browse(setting_ticket_merge_email_template_id)
        else:
            # BACK COMPATABLITY FAIL SAFE
            mail_template = self.env['ir.model'].get_object('website_supportzayd', 'support_ticket_merge')

        mail_template.send_mail(self.id, True)

        # Add as follower to new ticket
        if self.ticket_id.partner_id:
            self.merge_ticket_id.message_subscribe([self.ticket_id.partner_id.id])

        return {
            'name': "Support Ticket",
            'type': 'ir.actions.act_window',
            'view_type': 'form',
            'view_mode': 'form',
            'res_model': 'helpdesk.ticket',
            'res_id': self.merge_ticket_id.id
        }


class WebsiteSupportTicketCompose(models.Model):
    _name = "helpdesk.ticket.compose"

    ticket_id = fields.Many2one('helpdesk.ticket', string='Ticket ID')
    partner_id = fields.Many2one('res.partner', string="Partner", readonly="True")
    email = fields.Char(string="Email", readonly="True")
    email_cc = fields.Char(string="Cc")
    subject = fields.Char(string="Subject", readonly="True")
    body = fields.Text(string="Message Body")
    template_id = fields.Many2one('mail.template', string="Mail Template",
                                  domain="[('model_id','=','helpdesk.ticket'), ('built_in','=',False)]")
    approval = fields.Boolean(string="Approval")
    planned_time = fields.Datetime(string="Planned Time")
    attachment_ids = fields.Many2many('ir.attachment', 'sms_compose_attachment_rel', 'sms_compose_id', 'attachment_id',
                                      'Attachments')

    @api.onchange('template_id')
    def _onchange_template_id(self):
        if self.template_id:
            values = \
                self.env['mail.compose.message'].generate_email_for_composer(self.template_id.id, [self.ticket_id.id])[
                    self.ticket_id.id]
            self.body = values['body']

    def send_reply(self):

        # Change the approval state before we send the mail
        if self.approval:
            # Change the ticket state to awaiting approval
            awaiting_approval_state = self.env['ir.model.data'].get_object('website_supportzayd',
                                                                           'website_ticket_state_awaiting_approval')
            self.ticket_id.state = awaiting_approval_state.id

            # One support request per ticket...
            self.ticket_id.planned_time = self.planned_time
            self.ticket_id.approval_message = self.body
            self.ticket_id.sla_active = False

        # Send email
        values = {}

        setting_staff_reply_email_template_id = self.env['ir.default'].get('helpdesk.settings',
                                                                           'staff_reply_email_template_id')

        if setting_staff_reply_email_template_id:
            email_wrapper = self.env['mail.template'].browse(setting_staff_reply_email_template_id)

        values = email_wrapper.generate_email([self.id])[self.id]
        values['model'] = "helpdesk.ticket"
        values['res_id'] = self.ticket_id.id
        values['reply_to'] = email_wrapper.reply_to

        if self.email_cc:
            values['email_cc'] = self.email_cc

        for attachment in self.attachment_ids:
            values['attachment_ids'].append((4, attachment.id))

        send_mail = self.env['mail.mail'].create(values)
        send_mail.send()

        # Add to the message history to keep the data clean from the rest HTML
        self.env['helpdesk.ticket.message'].create({'ticket_id': self.ticket_id.id, 'by': 'staff',
                                                    'content': self.body.replace("<p>", "").replace("</p>", "")})

        # Post in message history
        # self.ticket_id.message_post(body=self.body, subject=self.subject, message_type='comment', subtype='mt_comment')

        if self.approval:
            # Also change the approval
            awaiting_approval = self.env['ir.model.data'].get_object('website_supportzayd', 'awaiting_approval')
            self.ticket_id.approval_id = awaiting_approval.id
        else:
            # Change the ticket state to staff replied
            staff_replied = self.env['ir.model.data'].get_object('website_supportzayd',
                                                                 'website_ticket_state_staff_replied')
            self.ticket_id.state = staff_replied.id


class WebsiteSupportTicketLevel(models.Model):
    _name = "helpdesk.ticket.level"

    name = fields.Char(string="Support Level")  # this is to store model char ?? @hafizalwi1dec2021

class TicketReport(models.AbstractModel):
    _name = 'report.helpdesk.ticket_report_template'
    _description = 'Ticket Report'


    @api.model
    def _get_report_values(self, docids, data=None):
        tickets = self.env['helpdesk.ticket'].browse(docids)
        return {
            'doc_ids': docids,
            'doc_model': 'helpdesk.ticket',
            'docs': tickets,
            'report_type': 'qweb-pdf',

        }

class CorrectiveMaintenanceForm(http.Controller):

    @http.route('/cmForm/<string:cm_form_no>', type='http', auth='public', website=True)
    def action_cm_form(self, cm_form_no):
        ticket = request.env['helpdesk.ticket'].sudo().search([('cm_form_no', '=', cm_form_no)])
        if not ticket:
            raise NotFound("CM number not found")
        
        # Set the timezone to 'Asia/Kuala_Lumpur' for public users
        user_tz = 'Asia/Kuala_Lumpur'  # Ensure public users get the correct timezone

        # Convert prob_solve_time to the Kuala Lumpur timezone
        local_prob_solve_time = fields.Datetime.context_timestamp(
            ticket.with_context(tz=user_tz), ticket.prob_solve_time
        )
        
        return request.render('helpdesk.corrective_maintenance_form', {
            'ticket': ticket,
            'local_prob_solve_time': local_prob_solve_time,  # Pass the converted time
        })


class SignatureController(http.Controller):

    @http.route('/cmForm/save', type='json', auth='public', methods=['POST'], csrf=False)
    def save_signature(self):
        try:
            # Parse JSON request body
            data = request.jsonrequest
            ticket_id = data.get('ticket_id')
            signature = data.get('signature')
            signature_date = data.get('signature_date')
            feedback = data.get('feedback')

            if not (ticket_id and signature and signature_date and feedback is not None and feedback):
                return {'success': False, 'error': 'Missing required parameters.'}

            # Convert the signature list to binary data
            binary_data = bytes(signature)
            # Encode the binary data to base64
            encoded_signature = base64.b64encode(binary_data).decode('utf-8')

            # Write the signature and feedback to the helpdesk.ticket record
            ticket = request.env['helpdesk.ticket'].sudo().browse(ticket_id)
            if ticket:
                ticket.write({
                    'customer_signature': encoded_signature,
                    'customer_signature_date': signature_date,
                    'feedback_scale1': feedback.get('scale1'),
                    'feedback_scale2': feedback.get('scale2'),
                    'feedback_scale3': feedback.get('scale3'),
                    'feedback_scale4': feedback.get('scale4'),
                    'feedback_scale5': feedback.get('scale5'),
                    'feedback_scale6': feedback.get('scale6'),
                    'satisfaction_scale': feedback.get('satisfaction_scale'),
                    'feedback_given': True
                })
                return {'success': True}
            else:
                return {'success': False, 'error': 'Ticket not found'}
        except Exception as e:
            return {'success': False, 'error': str(e)}


class HelpdeskTicketController(http.Controller):

    @route('/close_ticket', type='json', auth='user')
    def close_ticket(self, ticket_id, close_comment=None, **kwargs):
        """Close a ticket from Flutter with proper validation and updates."""
        try:
            # Validate ticket_id is an integer
            if not isinstance(ticket_id, int):
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 400,
                        "message": "Invalid ticket ID format. Must be an integer."
                    }
                }

            # Find the ticket
            ticket = request.env['helpdesk.ticket'].sudo().browse(ticket_id)
            if not ticket.exists():
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 404,
                        "message": "Ticket not found"
                    }
                }

            # Get the "Technician closed" stage
            technician_closed_stage = request.env['helpdesk.stage'].sudo().search([('name', '=', 'Technician closed')], limit=1)
            if not technician_closed_stage:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 500,
                        "message": "Could not find 'Technician closed' stage"
                    }
                }

            # Get current time
            now = fields.Datetime.now()
            
            # Calculate time differences
            create_date = ticket.create_date
            diff_time = now - create_date
            diff_seconds = diff_time.total_seconds()
            diff_hours = diff_time.total_seconds() / 3600

            # Update ticket - Use user_id as closed_by_id if available
            values = {
                'stage_id': technician_closed_stage.id,
                'close_time': now,
                'close_date': now.date(),
                'time_to_close': diff_seconds,
                'time_to_close_hhmm': diff_hours,
                'closed_by_id': ticket.user_id.id if ticket.user_id else request.env.user.id,
                'sla_active': False,
                'prob_solve_time': now,
            }

            # Add close comment if provided
            if close_comment:
                values['close_comment'] = close_comment

            # Write changes and handle any errors
            try:
                ticket.write(values)
                request.env.cr.commit()  # Commit the transaction
                
                # Log the action
                ticket.message_post(
                    body=f"Ticket closed by {request.env.user.name}",
                    message_type='notification',
                    subtype_xmlid='mail.mt_note'
                )

                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True,
                        "message": "Ticket closed successfully"
                    }
                }

            except Exception as e:
                request.env.cr.rollback()  # Rollback on error
                _logger.error(f"Error closing ticket {ticket_id}: {str(e)}")
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": 500,
                        "message": f"Failed to close ticket: {str(e)}"
                    }
                }

        except Exception as e:
            _logger.error(f"Unexpected error while closing ticket {ticket_id}: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": False,
                    "message": f"Handled with error: {str(e)}"
                }
            }

    @http.route('/custom_login', type='json', auth='user')
    def custom_login(self, **kwargs):
        user = request.env.user
        is_admin = request.env.ref('base.group_system').id in user.groups_id.ids
        return {
            'uid': user.id,
            'name': user.name,
            'is_admin': is_admin
        }

    
    @http.route('/api/tickets', type='http', auth='user', methods=['GET', 'POST'], csrf=False)
    def fetch_tickets(self, **kwargs):
        try:
            # Extract user_id
            user_id = kwargs.get('user_id') or json.loads(request.httprequest.data).get('user_id')
            if not user_id:
                return request.make_response(
                    json.dumps({"success": False, "error": "User ID is required."}),
                    headers={'Content-Type': 'application/json'}
                )

            try:
                user_id = int(user_id)
            except ValueError:
                return request.make_response(
                    json.dumps({"success": False, "error": "Invalid user ID format. Must be an integer."}),
                    headers={'Content-Type': 'application/json'}
                )

            # Fetch tickets
            tickets = request.env['helpdesk.ticket'].sudo().search_read(
                ['|',
                 ('user_id', '=', user_id),
                 ('create_uid', '=', user_id)],
                [
                    'name',
                    'ticket_number_display',
                    'priority',
                    'partner_name',
                    'partner_email',
                    'partner_phone',
                    'serial_name',
                    'department',
                    'equipment_user',
                    'person_name',
                    'address',
                    'category_name',
                    'sub_name',
                    'prob_name',
                    'stage_name',
                    'create_date',
                    'latitude',
                    'longitude',
                ]
            )

            if not tickets:
                return request.make_response(
                    json.dumps({"result": [], "message": "Tiada tiket dijumpai untuk pengguna ini."}),
                    headers={'Content-Type': 'application/json'}
                )

            for ticket in tickets:
                if 'create_date' in ticket and ticket['create_date']:
                    ticket['create_date'] = ticket['create_date'].strftime('%Y-%m-%d %H:%M:%S')

            return request.make_response(
                json.dumps({"result": tickets}),
                headers={'Content-Type': 'application/json'}
            )

        except Exception as e:
            request.env['ir.logging'].sudo().create({
                'name': 'API Tickets Error',
                'type': 'server',
                'level': 'error',
                'message': str(e),
            })
            return request.make_response(
                json.dumps({"error": str(e)}),
                headers={'Content-Type': 'application/json'},
                status=500
            )


    @http.route('/api/check-in', type='json', auth='user', methods=['POST'], csrf=False)
    def check_in(self, **kwargs):
        try:
            payload = json.loads(request.httprequest.data)
            user_id = payload.get('user_id')
            ticket_id = payload.get('ticket_id')
            check_in_time = payload.get('check_in_time')
            check_in_lat = payload.get('check_in_lat')
            check_in_long = payload.get('check_in_long')
            check_in_address = payload.get('check_in_address')

            # Pastikan `user_id`, `ticket_id`, dan `check_in_time` wujud
            if not all([user_id, ticket_id, check_in_time]):
                return request.make_response(
                    json.dumps({"error": "Medan wajib tidak lengkap: user_id, ticket_id, check_in_time."}),
                    headers={'Content-Type': 'application/json'},
                    status=400
                )

            # Pastikan tiket wujud
            ticket = request.env['helpdesk.ticket'].sudo().browse(int(ticket_id))
            if not ticket.exists():
                return request.make_response(
                    json.dumps({"error": "Tiket tidak dijumpai."}),
                    headers={'Content-Type': 'application/json'},
                    status=404
                )

            # Update `check_in`
            update_values = {
                'check_in': check_in_time,
                'user_id': int(user_id),  # Use user_id instead of technician_id
            }
            
            # Jika ada GPS, simpan juga `check_in_lat` dan `check_in_long`
            if check_in_lat and check_in_long:
                update_values.update({
                    'check_in_lat': check_in_lat,
                    'check_in_long': check_in_long,
                    'check_in_address': check_in_address or '',
                })

            ticket.sudo().write(update_values)

            # Tambah Log dalam Ticket Timelines
            ticket.message_post(body=f"User <b>{ticket.user_id.name}</b> checked in at {check_in_time}")

            _logger.info(f"Check-in successful for Ticket {ticket_id} by User {user_id}")

            # Hantar Notifikasi ke FCM jika `fcm_token` ada
            self.send_push_notification(ticket, user_id)

            return request.make_response(
                json.dumps({"success": True, "message": "Check-in berjaya direkodkan.", "ticket_id": ticket.id}),
                headers={'Content-Type': 'application/json'}
            )

        except Exception as e:
            _logger.error(f"API Check-In Error: {str(e)}")
            return request.make_response(
                json.dumps({"error": str(e)}),
                headers={'Content-Type': 'application/json'},
                status=500
            )




class StockProductionLot(models.Model):
    _inherit = 'stock.production.lot'

    corrective_maintenance_count = fields.Integer(
        string='CM Count',
        compute='_compute_corrective_maintenance_count',
        store=True
    )

    @api.depends('name')
    def _compute_corrective_maintenance_count(self):
        for lot in self:
            count = self.env['helpdesk.ticket'].search_count([
                ('inventory_serial_number_id', '=', lot.id),
            ])
            lot.corrective_maintenance_count = count

    def action_open_corrective_maintenance_view(self):
        self._compute_corrective_maintenance_count()
        return {
            'name': 'Corrective Maintenance Tickets',
            'view_mode': 'tree,form',
            'res_model': 'helpdesk.ticket',
            'type': 'ir.actions.act_window',
            'domain': [('inventory_serial_number_id', '=', self.id)],
        }


class CustomHelpdesk(http.Controller):

    @http.route('/download/cmform/<string:ticket_id>', type='http', auth="public", website=True)
    def download_ticket_report(self, ticket_id, **kwargs):
        try:
            # Convert the string ticket_id to an integer
            ticket_id_int = int(ticket_id)

            # Fetch the ticket using sudo() to bypass access rights check for public users
            ticket = request.env['helpdesk.ticket'].sudo().browse(ticket_id_int)
            if not ticket:
                return request.not_found()

            # Set the timezone to 'Asia/Kuala_Lumpur' for public users in the context
            kuala_lumpur_tz = 'Asia/Kuala_Lumpur'

            # Convert the datetime fields in the ticket to the Kuala Lumpur timezone (only for reporting)
            local_prob_solve_time_str = None
            if ticket.prob_solve_time:
                ticket_with_tz = ticket.with_context(tz=kuala_lumpur_tz)
                local_prob_solve_time = fields.Datetime.context_timestamp(ticket_with_tz, ticket.prob_solve_time)
                # Format the datetime to remove timezone information
                local_prob_solve_time_str = local_prob_solve_time.strftime('%Y-%m-%d %H:%M:%S')

            local_open_case_str = None
            if ticket.open_case:
                ticket_with_tz = ticket.with_context(tz=kuala_lumpur_tz)
                local_open_case = fields.Datetime.context_timestamp(ticket_with_tz, ticket.open_case)
                # Format the datetime to remove timezone information
                local_open_case_str = local_open_case.strftime('%Y-%m-%d %H:%M:%S')

            # Use sudo() to fetch the report object and render the PDF with the context
            report_obj = request.env.ref('helpdesk.action_report_helpdesk_ticket_customer').sudo()

            # Pass both `local_prob_solve_time_str` and `local_open_case_str` in a single data dictionary
            pdf_content, content_type = report_obj._render_qweb_pdf(
                [ticket_id_int], 
                {'data': {
                    'local_prob_solve_time': local_prob_solve_time_str,
                    'local_open_case': local_open_case_str
                }}
            )

            # Set headers for the downloadable PDF response
            pdf_http_headers = [
                ('Content-Type', 'application/pdf'),
                ('Content-Length', str(len(pdf_content))),
                ('Content-Disposition', f'attachment; filename="ticket_report_{ticket_id}.pdf"')
            ]

            # Return the PDF content as a downloadable response
            return request.make_response(pdf_content, headers=pdf_http_headers)

        except ValueError:
            # Handle invalid ticket_id (non-integer)
            return request.not_found()

        except Exception as e:
            # Render a simple error message for unexpected issues
            return request.make_response(f"<h1>Error</h1><p>{str(e)}</p>", headers=[('Content-Type', 'text/html')])


class HelpdeskFeedbackRanking(models.Model):
    _name = 'helpdesk.ticket.feedback.ranking'
    _description = 'Feedback Ranking by Technician'
    _auto = False

    user_id = fields.Many2one('res.users', string="Technician", readonly=True)
    avg_feedback = fields.Float(string="Average Feedback (%)", readonly=True)
    ticket_count = fields.Integer(string="Total Tickets", readonly=True)

    def init(self):
        self.env.cr.execute("""
            CREATE OR REPLACE VIEW helpdesk_ticket_feedback_ranking AS (
                SELECT
                    MIN(ht.id) AS id,
                    ht.user_id,
                    AVG(ht.total_feedback_scale) AS avg_feedback,
                    COUNT(*) AS ticket_count
                FROM helpdesk_ticket ht
                WHERE ht.total_feedback_scale IS NOT NULL
                GROUP BY ht.user_id
            )
        """)

class FCMTestController(http.Controller):

    @route('/api/test_push', type='json', auth='user')
    def api_test_push(self, **kwargs):
        ticket_id = kwargs.get('ticket_id')
        if not ticket_id:
            return {'error': 'Missing ticket_id'}

        ticket = request.env['helpdesk.ticket'].sudo().browse(ticket_id)
        if not ticket.exists():
            return {'error': 'Ticket not found'}

        _logger.info("📡 API Test Push Triggered for Ticket ID: %s", ticket_id)

        ticket.send_push_notification_v1("🔔 Test Push", "Push notification from API test", ticket.user_id.id)
        return {'status': 'Push triggered successfully'}

    @http.route('/api/test_push_gmail', type='json', auth='user', methods=['POST'], csrf=False)
    def api_test_push_gmail(self, **kwargs):
        """
        Endpoint untuk test push notification FCM ke user Gmail.
        Params:
            - gmail: alamat Gmail yang didaftarkan untuk notifikasi
        """
        gmail = kwargs.get('gmail')
        if not gmail:
            return {'error': 'Gmail is required'}

        # Cari user Gmail
        gmail_user = request.env['res.users'].sudo().search([('login', '=', gmail)], limit=1)
        if not gmail_user:
            return {'error': f'User Gmail {gmail} not found'}

        # Cari satu tiket (boleh guna tiket random)
        ticket = request.env['helpdesk.ticket'].sudo().search([], limit=1)
        if not ticket:
            return {'error': 'No ticket found to use for test'}

        # Trigger push notification
        ticket.send_push_notification_v1(
            title="🔔 Ujian Push Notifikasi FCM",
            body=f"Ini adalah ujian push notifikasi ke {gmail}",
            user_id=gmail_user.id
        )
        return {'status': f'Push notification triggered to youruser@gmail.com (user_id={gmail_user.id})'}

class FcmToken(models.Model):
    _name = 'fcm.token'

    token = fields.Char(string='FCM Token', required=True)
    user_id = fields.Many2one('res.users', string='User', required=True)
    create_date = fields.Datetime(string='Created Date', readonly=True, default=fields.Datetime.now)
    last_used = fields.Datetime(string='Last Used', readonly=True)
    is_active = fields.Boolean(string='Active', default=True)

    _sql_constraints = [
        ('unique_user_token', 'unique(user_id, token)', 'Each user can have only one instance of a specific token!')
    ]

    @api.model
    def store_fcm_token(self, user_id, token):
        """ Store FCM token with better error handling """
        try:
            # Check if a record with the same user ID and token already exists
            existing_token = self.search([('user_id', '=', user_id), ('token', '=', token)], limit=1)
            if not existing_token:
                # If not, create a new record
                new_token = self.create({
                    'user_id': user_id, 
                    'token': token,
                    'last_used': fields.Datetime.now()
                })
                _logger.info(f'✅ FCM Token stored for user {user_id}: {token}')
                return {
                    'success': True,
                    'message': 'Token stored successfully',
                    'token_id': new_token.id
                }
            else:
                # Update last used timestamp
                existing_token.write({'last_used': fields.Datetime.now()})
                _logger.info(f'ℹ️ FCM Token already exists for user {user_id}: {token}')
                return {
                    'success': True,
                    'message': 'Token already exists',
                    'token_id': existing_token.id
                }
        except Exception as e:
            _logger.error(f'❌ Error storing FCM token for user {user_id}: {str(e)}')
            return {
                'success': False,
                'message': f'Failed to store token: {str(e)}'
            }

    @api.model
    def refresh_fcm_token(self, user_id, old_token, new_token):
        """ Refresh FCM token with better error handling """
        try:
            # Find existing token
            existing_token = self.search([
                ('user_id', '=', user_id), 
                ('token', '=', old_token)
            ], limit=1)
            
            if existing_token:
                existing_token.write({
                    'token': new_token,
                    'last_used': fields.Datetime.now()
                })
                _logger.info(f'✅ FCM Token refreshed for user {user_id}')
                return {
                    'success': True,
                    'message': 'Token refreshed successfully'
                }
            else:
                # Create new token if old one not found
                new_token_record = self.create({
                    'user_id': user_id,
                    'token': new_token,
                    'last_used': fields.Datetime.now()
                })
                _logger.info(f'✅ New FCM Token created for user {user_id}')
                return {
                    'success': True,
                    'message': 'New token created successfully',
                    'token_id': new_token_record.id
                }
        except Exception as e:
            _logger.error(f'❌ Error refreshing FCM token for user {user_id}: {str(e)}')
            return {
                'success': False,
                'message': f'Failed to refresh token: {str(e)}'
            }

    @api.model
    def cleanup_inactive_tokens(self, days_old=30):
        """ Clean up inactive FCM tokens older than specified days """
        try:
            cutoff_date = fields.Datetime.now() - timedelta(days=days_old)
            inactive_tokens = self.search([
                ('last_used', '<', cutoff_date),
                ('is_active', '=', True)
            ])
            
            if inactive_tokens:
                inactive_tokens.write({'is_active': False})
                _logger.info(f'✅ Deactivated {len(inactive_tokens)} inactive FCM tokens')
                return len(inactive_tokens)
            return 0
        except Exception as e:
            _logger.error(f'❌ Error cleaning up inactive tokens: {str(e)}')
            return 0

    @api.model
    def get_user_tokens(self, user_id):
        """ Get all active FCM tokens for a user """
        try:
            tokens = self.search([
                ('user_id', '=', user_id),
                ('is_active', '=', True)
            ])
            return tokens
        except Exception as e:
            _logger.error(f'❌ Error getting tokens for user {user_id}: {str(e)}')
            return self.env['fcm.token']

    def mark_as_used(self):
        """ Mark token as used by updating last_used timestamp """
        self.ensure_one()
        self.write({'last_used': fields.Datetime.now()})

class UserProfileController(http.Controller):
    @http.route('/api/user/set_notification_email', type='json', auth='user', methods=['POST'], csrf=False)
    def set_notification_email(self, **kwargs):
        """
        API endpoint for a logged-in user to set their notification email.
        """
        notification_email = kwargs.get('notification_email')
        if not notification_email:
            return {'success': False, 'error': 'Notification email is required.'}

        user = request.env.user
        try:
            # Periksa jika Gmail user sudah wujud
            gmail_user = request.env['res.users'].sudo().search([
                ('login', '=', notification_email)
            ], limit=1)
            
            if not gmail_user:
                # Cipta akaun Gmail baru untuk notifikasi sahaja
                gmail_user = request.env['res.users'].sudo().create({
                    'name': f"Notifikasi ({notification_email})",
                    'login': notification_email,
                    'email': notification_email,
                    'active': True,  # Aktif untuk notifikasi
                    'password': 'not_used_for_login',  # Kata laluan dummy
                })
                _logger.info(f"✅ Akaun Gmail dicipta untuk notifikasi: {notification_email}")
            
            # Simpan Gmail dalam profil pengguna asal
            user.sudo().write({'x_notification_email': notification_email})
            _logger.info(f"✅ Gmail notifikasi disimpan untuk {user.login}: {notification_email}")
            
            return {'success': True, 'message': 'Gmail notifikasi dikemas kini dengan jayanya.'}
        except Exception as e:
            _logger.error(f"❌ Failed to update notification email for user {user.login}: {e}")
            return {'success': False, 'error': f'An error occurred: {e}'}

def get_lat_lon_from_address(address):
    """Get latitude and longitude from address using Google Maps API with fallback to OpenStreetMap"""
    import requests
    
    # Try Google Maps API first
    google_api_key = __import__("os").environ.get("GOOGLE_MAPS_API_KEY", "")
    google_url = "https://maps.googleapis.com/maps/api/geocode/json"
    google_params = {
        "address": address,
        "key": google_api_key
    }
    
    try:
        response = requests.get(google_url, params=google_params, timeout=10)
        if response.status_code == 200:
            data = response.json()
            if data.get('status') == 'OK' and data.get('results'):
                location = data['results'][0]['geometry']['location']
                lat = float(location['lat'])
                lon = float(location['lng'])
                _logger.info(f"[GEO] Google Maps API success for '{address}': {lat}, {lon}")
                return lat, lon
            else:
                _logger.warning(f"[GEO] Google Maps API error for '{address}': {data.get('status')}")
    except Exception as e:
        _logger.error(f"[GEO] Google Maps API exception for '{address}': {e}")
    
    # Fallback to OpenStreetMap
    try:
        osm_url = "https://nominatim.openstreetmap.org/search"
        osm_params = {
            "q": address,
            "format": "json",
            "limit": 1
        }
        osm_headers = {
            "User-Agent": "odoo-ticket"
        }
        response = requests.get(osm_url, params=osm_params, headers=osm_headers, timeout=10)
        if response.status_code == 200:
            results = response.json()
            if results:
                lat = float(results[0]['lat'])
                lon = float(results[0]['lon'])
                _logger.info(f"[GEO] OpenStreetMap fallback success for '{address}': {lat}, {lon}")
                return lat, lon
    except Exception as e:
        _logger.error(f"[GEO] OpenStreetMap fallback exception for '{address}': {e}")
    
    _logger.error(f"[GEO] Both APIs failed for address: '{address}'")
    return 0.0, 0.0


class GeolocationController(http.Controller):
    """Controller for geolocation API endpoints"""
    
    @http.route('/api/geolocation/geocode', type='json', auth='public', methods=['POST'], csrf=False)
    def geocode_address(self, **kwargs):
        """API endpoint to geocode an address"""
        try:
            address = kwargs.get('address')
            if not address:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "Address parameter is required",
                        "code": 400
                    }
                }
            
            lat, lon = get_lat_lon_from_address(address)
            
            if lat != 0.0 or lon != 0.0:
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True,
                        "address": address,
                        "latitude": lat,
                        "longitude": lon
                    }
                }
            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": f"Could not geocode address: {address}",
                        "code": 404
                    }
                }
                
        except Exception as e:
            _logger.error(f"[GEO] API Error: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Geocoding failed: {str(e)}",
                    "code": 500
                }
            }
    
    @http.route('/api/geolocation/reverse', type='json', auth='public', methods=['POST'], csrf=False)
    def reverse_geocode(self, **kwargs):
        """API endpoint to reverse geocode coordinates"""
        try:
            lat = kwargs.get('latitude')
            lon = kwargs.get('longitude')
            
            if lat is None or lon is None:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "Both latitude and longitude parameters are required",
                        "code": 400
                    }
                }
            
            # Use Google Maps API for reverse geocoding
            google_api_key = __import__("os").environ.get("GOOGLE_MAPS_API_KEY", "")
            google_url = "https://maps.googleapis.com/maps/api/geocode/json"
            google_params = {
                "latlng": f"{lat},{lon}",
                "key": google_api_key
            }
            
            response = requests.get(google_url, params=google_params, timeout=10)
            if response.status_code == 200:
                data = response.json()
                if data.get('status') == 'OK' and data.get('results'):
                    address = data['results'][0]['formatted_address']
                    return {
                        "jsonrpc": "2.0",
                        "result": {
                            "success": True,
                            "latitude": lat,
                            "longitude": lon,
                            "address": address
                        }
                    }
            
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Could not reverse geocode coordinates: {lat}, {lon}",
                    "code": 404
                }
            }
                
        except Exception as e:
            _logger.error(f"[GEO] Reverse Geocoding API Error: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Reverse geocoding failed: {str(e)}",
                    "code": 500
                }
            }
    
    @http.route('/api/geolocation/test', type='json', auth='public', methods=['POST'], csrf=False)
    def test_geolocation(self, **kwargs):
        """Test endpoint for geolocation services"""
        try:
            test_address = "Kuala Lumpur, Malaysia"
            lat, lon = get_lat_lon_from_address(test_address)
            
            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": True,
                    "test_address": test_address,
                    "latitude": lat,
                    "longitude": lon,
                    "message": "Geolocation services are working"
                }
            }
                
        except Exception as e:
            _logger.error(f"[GEO] Test API Error: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Test failed: {str(e)}",
                    "code": 500
                }
            }

class FCMNotificationController(http.Controller):
    """Controller for FCM push notification endpoints"""
    
    def _get_fcm_access_token(self):
        """Get FCM access token using service account credentials."""
        try:
            # Try to get service account file first
            SERVICE_ACCOUNT_FILE = '/mnt/extra-addons/extra-addons/helpdesk/firebase-fcm.json'
            
            if os.path.exists(SERVICE_ACCOUNT_FILE):
                # Use service account file
                credentials = service_account.Credentials.from_service_account_file(
                    SERVICE_ACCOUNT_FILE, 
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
                credentials.refresh(Request())
                access_token = credentials.token
                project_id = credentials.project_id
                _logger.info(f"✅ Using service account file for FCM access token")
                return access_token, project_id
            else:
                # Try to get from system parameters
                credentials_json_str = request.env['ir.config_parameter'].sudo().get_param('fcm.service_account.credentials')
                if not credentials_json_str:
                    _logger.error("FCM service account credentials not found in file or system parameters.")
                    return None, None

                credentials_info = json.loads(credentials_json_str)
                project_id = credentials_info.get('project_id')
                creds = ServiceAccountCredentials.from_json_keyfile_dict(
                    credentials_info,
                    scopes=['https://www.googleapis.com/auth/firebase.messaging']
                )
                access_token = creds.get_access_token().access_token
                _logger.info(f"✅ Using system parameter for FCM access token")
                return access_token, project_id
                
        except Exception as e:
            _logger.error(f"Failed to get FCM access token: {e}")
            return None, None
    
    @http.route('/api/fcm/send_notification', type='json', auth='public', methods=['POST'], csrf=False)
    def send_push_notification(self, **kwargs):
        """API endpoint untuk menghantar push notification dari Flutter app"""
        try:
            # Parse request data
            data = request.jsonrequest
            fcm_token = data.get('fcm_token')
            recipient_user_id = data.get('recipient_user_id')
            recipient_email = data.get('recipient_email')
            title = data.get('title')
            body = data.get('body')
            notification_type = data.get('notification_type', 'general')
            sender_id = data.get('sender_id')
            
            # If recipient_user_id is provided, get FCM token from database
            if recipient_user_id:
                fcm_tokens = request.env['fcm.token'].sudo().search([
                    ('user_id', '=', recipient_user_id),
                    ('is_active', '=', True)
                ], order='create_date desc')
                
                if not fcm_tokens:
                    return {
                        "jsonrpc": "2.0",
                        "error": {
                            "message": f"No FCM token found for user {recipient_user_id}",
                            "code": 404
                        }
                    }
                
                fcm_token = fcm_tokens[0].token
                _logger.info(f"📤 Using FCM token from database for user {recipient_user_id}")
            
            # If no FCM token provided and no recipient_user_id, return error
            if not fcm_token:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "FCM token or recipient_user_id is required",
                        "code": 400
                    }
                }
            
            _logger.info(f"📤 Sending push notification to FCM token: {fcm_token}")
            _logger.info(f"📋 Title: {title}")
            _logger.info(f"📋 Body: {body}")
            _logger.info(f"📋 Recipient: {recipient_email}")
            
            # Get FCM Server Key from system parameters
            server_key = request.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
            if not server_key:
                _logger.error("❌ FCM Server Key is missing in Odoo configuration.")
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "FCM Server Key not configured",
                        "code": 500
                    }
                }
            
            # Prepare FCM payload
            fcm_payload = {
                'to': fcm_token,
                'notification': {
                    'title': title,
                    'body': body,
                    'sound': 'default',
                    'badge': '1',
                },
                'data': {
                    'notification_type': notification_type,
                    'sender_id': sender_id,
                    'recipient_email': recipient_email,
                    'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                },
                'priority': 'high',
                'time_to_live': 86400,
            }
            
            # Send to FCM using HTTP v1 API (Legacy API disabled)
            # Get access token using service account
            access_token, project_id = self._get_fcm_access_token()
            
            if not access_token or not project_id:
                _logger.error("❌ Failed to get FCM access token")
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "Failed to get FCM access token",
                        "code": 500
                    }
                }
            
            # Use HTTP v1 API
            headers = {
                'Authorization': f'Bearer {access_token}',
                'Content-Type': 'application/json; UTF-8',
            }
            
            # Prepare v1 payload
            v1_payload = {
                "message": {
                    "token": fcm_token,
                    "notification": {
                        "title": title,
                        "body": body
                    },
                    "data": {
                        'notification_type': notification_type,
                        'sender_id': str(sender_id),
                        'recipient_email': recipient_email,
                        'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                    }
                }
            }
            
            response = requests.post(
                f'https://fcm.googleapis.com/v1/projects/{project_id}/messages:send',
                headers=headers,
                json=v1_payload,
                timeout=10
            )
            
            if response.status_code == 200:
                response_data = response.json()
                _logger.info(f"✅ Push notification sent successfully!")
                _logger.info(f"📋 FCM response: {response_data}")
                
                # Save notification history
                try:
                    sender_user = request.env['res.users'].sudo().browse(int(sender_id)) if sender_id else request.env.user
                    recipient_user = request.env['res.users'].sudo().browse(int(recipient_user_id)) if recipient_user_id else None
                    
                    if recipient_user:
                        request.env['fcm.notification.history'].sudo().create_notification_record(
                            title=title,
                            body=body,
                            sender_id=sender_user.id,
                            recipient_id=recipient_user.id,
                            notification_type=notification_type,
                            fcm_token=fcm_token,
                            status='sent'
                        )
                        _logger.info(f"✅ Notification history saved")
                except Exception as e:
                    _logger.error(f"❌ Failed to save notification history: {e}")
                
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True,
                        "message": "Push notification sent successfully",
                        "fcm_response": response_data
                    }
                }
            else:
                _logger.error(f"❌ Failed to send push notification. Status: {response.status_code}")
                _logger.error(f"📋 Error response: {response.text}")
                
                # Save failed notification history
                try:
                    sender_user = request.env['res.users'].sudo().browse(int(sender_id)) if sender_id else request.env.user
                    recipient_user = request.env['res.users'].sudo().browse(int(recipient_user_id)) if recipient_user_id else None
                    
                    if recipient_user:
                        request.env['fcm.notification.history'].sudo().create_notification_record(
                            title=title,
                            body=body,
                            sender_id=sender_user.id,
                            recipient_id=recipient_user.id,
                            notification_type=notification_type,
                            fcm_token=fcm_token,
                            status='failed'
                        )
                except Exception as e:
                    _logger.error(f"❌ Failed to save failed notification history: {e}")
                
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": f"Failed to send push notification: {response.text}",
                        "code": response.status_code
                    }
                }
                
        except Exception as e:
            _logger.error(f"❌ Error sending push notification: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Failed to send push notification: {str(e)}",
                    "code": 500
                }
            }
    
    @http.route('/api/fcm/send_task_notification', type='json', auth='public', methods=['POST'], csrf=False)
    def send_task_notification(self, **kwargs):
        """API endpoint khusus untuk menghantar notifikasi task assignment"""
        try:
            data = request.jsonrequest
            user_email = data.get('user_email')
            task_title = data.get('task_title')
            assigned_by = data.get('assigned_by')
            
            if not all([user_email, task_title]):
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "user_email and task_title are required",
                        "code": 400
                    }
                }
            
            _logger.info(f"📤 Sending task notification to: {user_email}")
            _logger.info(f"📋 Task: {task_title}")
            
            # Find user by email
            user = request.env['res.users'].sudo().search([('login', '=', user_email)], limit=1)
            if not user:
                _logger.warning(f"⚠️ User not found with email: {user_email}")
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": f"User not found with email: {user_email}",
                        "code": 404
                    }
                }
            
            # Get FCM tokens for the user
            fcm_tokens = request.env['fcm.token'].sudo().search([('user_id', '=', user.id)])
            if not fcm_tokens:
                _logger.warning(f"⚠️ No FCM tokens found for user: {user_email}")
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": f"No FCM tokens found for user: {user_email}",
                        "code": 404
                    }
                }
            
            # Get FCM Server Key
            server_key = request.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
            if not server_key:
                _logger.error("❌ FCM Server Key is missing in Odoo configuration.")
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "FCM Server Key not configured",
                        "code": 500
                    }
                }
            
            # Send notification to all tokens for the user
            success_count = 0
            total_count = len(fcm_tokens)
            
            for token in fcm_tokens:
                try:
                    fcm_payload = {
                        'to': token.token,
                        'notification': {
                            'title': 'New Task Assigned',
                            'body': f'You have been assigned a new task: {task_title}',
                            'sound': 'default',
                            'badge': '1',
                        },
                        'data': {
                            'taskTitle': task_title,
                            'assignedBy': assigned_by,
                            'clickAction': 'FLUTTER_NOTIFICATION_CLICK',
                            'screen': 'task_page',
                            'type': 'task_assignment'
                        },
                        'priority': 'high',
                        'time_to_live': 86400,  # 24 hours
                    }
                    
                    headers = {
                        'Content-Type': 'application/json',
                        'Authorization': f'key={server_key}',
                    }
                    
                    response = requests.post(
                        'https://fcm.googleapis.com/fcm/send',
                        headers=headers,
                        data=json.dumps(fcm_payload),
                        timeout=10
                    )
                    
                    if response.status_code == 200:
                        success_count += 1
                        _logger.info(f"✅ Task notification sent to token: {token.token}")
                    else:
                        _logger.error(f"❌ Failed to send to token {token.token}: {response.text}")
                        
                except Exception as e:
                    _logger.error(f"❌ Error sending to token {token.token}: {str(e)}")
            
            if success_count > 0:
                _logger.info(f"✅ Task notification sent successfully to {success_count}/{total_count} tokens")
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True,
                        "message": f"Task notification sent to {success_count}/{total_count} devices",
                        "success_count": success_count,
                        "total_count": total_count
                    }
                }
            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "Failed to send task notification to any devices",
                        "code": 500
                    }
                }
                
        except Exception as e:
            _logger.error(f"❌ Error sending task notification: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Failed to send task notification: {str(e)}",
                    "code": 500
                }
            }
    
    @http.route('/api/fcm/test_notification', type='json', auth='public', methods=['POST'], csrf=False)
    def test_notification(self, **kwargs):
        """Test endpoint untuk menguji push notification"""
        try:
            data = request.jsonrequest
            user_email = data.get('user_email')
            
            if not user_email:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "user_email is required",
                        "code": 400
                    }
                }
            
            # Find user by email
            user = request.env['res.users'].sudo().search([('login', '=', user_email)], limit=1)
            if not user:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": f"User not found with email: {user_email}",
                        "code": 404
                    }
                }
            
            # Get FCM tokens
            fcm_tokens = request.env['fcm.token'].sudo().search([('user_id', '=', user.id)])
            if not fcm_tokens:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": f"No FCM tokens found for user: {user_email}",
                        "code": 404
                    }
                }
            
            # Send test notification
            server_key = request.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
            if not server_key:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "FCM Server Key not configured",
                        "code": 500
                    }
                }
            
            success_count = 0
            for token in fcm_tokens:
                try:
                    fcm_payload = {
                        'to': token.token,
                        'notification': {
                            'title': 'Test Notification',
                            'body': 'This is a test notification from Odoo server',
                            'sound': 'default',
                        },
                        'data': {
                            'type': 'test',
                            'timestamp': fields.Datetime.now().strftime('%Y-%m-%d %H:%M:%S')
                        },
                        'priority': 'high',
                    }
                    
                    headers = {
                        'Content-Type': 'application/json',
                        'Authorization': f'key={server_key}',
                    }
                    
                    response = requests.post(
                        'https://fcm.googleapis.com/fcm/send',
                        headers=headers,
                        data=json.dumps(fcm_payload),
                        timeout=10
                    )
                    
                    if response.status_code == 200:
                        success_count += 1
                        
                except Exception as e:
                    _logger.error(f"❌ Error sending test notification: {str(e)}")
            
            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": True,
                    "message": f"Test notification sent to {success_count}/{len(fcm_tokens)} devices",
                    "success_count": success_count,
                    "total_count": len(fcm_tokens)
                }
            }
                
        except Exception as e:
            _logger.error(f"❌ Error in test notification: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Test notification failed: {str(e)}",
                    "code": 500
                }
            }

class UserImageController(http.Controller):
    @http.route('/api/user/image', type='json', auth='user', methods=['POST'], csrf=False)
    def get_user_image(self, **kwargs):
        try:
            data = request.jsonrequest
        except Exception:
            data = {}
        _logger.info(f"USER IMAGE DEBUG: kwargs={kwargs}, jsonrequest={data}")
        user_id = data.get('user_id') or kwargs.get('user_id')
        if not user_id and 'params' in kwargs:
            user_id = kwargs['params'].get('user_id')
        if not user_id:
            return {'success': False, 'error': 'user_id is required'}
        user = request.env['res.users'].sudo().browse(int(user_id))
        if not user.exists():
            return {'success': False, 'error': 'User not found'}
        if user.image_1920:
            img = user.image_1920
            if isinstance(img, bytes):
                img = img.decode('utf-8')
            return {
                'success': True,
                'image_base64': img
            }
        else:
            return {'success': False, 'error': 'No image found for user'}

    @http.route('/api/user/update_image', type='json', auth='user', methods=['POST'], csrf=False)
    def update_user_image(self, **kwargs):
        try:
            data = request.jsonrequest
        except Exception:
            data = {}
        
        _logger.info(f"UPDATE USER IMAGE DEBUG: kwargs={kwargs}, jsonrequest={data}")
        
        user_id = data.get('user_id')
        image_base64 = data.get('image_base64')
        
        if not user_id:
            return {'success': False, 'error': 'user_id is required'}
        
        if not image_base64:
            return {'success': False, 'error': 'image_base64 is required'}
        
        try:
            user = request.env['res.users'].sudo().browse(int(user_id))
            if not user.exists():
                return {'success': False, 'error': 'User not found'}
            
            # Update user image
            user.write({'image_1920': image_base64})
            
            _logger.info(f"✅ User image updated successfully for user {user_id}")
            return {'success': True, 'message': 'User image updated successfully'}
            
        except Exception as e:
            _logger.error(f"❌ Error updating user image: {str(e)}")
            return {'success': False, 'error': f'Error updating user image: {str(e)}'}


class UserController(http.Controller):
    @http.route('/api/users', type='json', auth='user', methods=['POST'], csrf=False)
    def get_users(self, **kwargs):
        """Fetch all users for dropdown selection"""
        try:
            users = request.env['res.users'].sudo().search([])
            user_list = []
            
            for user in users:
                user_list.append({
                    'id': user.id,
                    'name': user.name,
                    'email': user.login,
                    'active': user.active,
                })
            
            _logger.info(f"✅ Fetched {len(user_list)} users for dropdown")
            _logger.info(f"📋 Users data: {user_list}")
            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": True,
                    "users": user_list
                }
            }
            
        except Exception as e:
            _logger.error(f"❌ Error fetching users: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Failed to fetch users: {str(e)}",
                    "code": 500
                }
            }

    @http.route('/api/fcm/get_user_token', type='json', auth='user', methods=['POST'], csrf=False)
    def get_user_fcm_token(self, **kwargs):
        """Get the latest FCM token for a specific user"""
        try:
            data = request.jsonrequest
            user_id = data.get('user_id')
            
            if not user_id:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "user_id is required",
                        "code": 400
                    }
                }
            
            # Get the latest FCM token for the user
            fcm_token = request.env['fcm.token'].sudo().search([
                ('user_id', '=', user_id),
                ('is_active', '=', True)
            ], order='create_date desc', limit=1)
            
            if fcm_token:
                _logger.info(f"✅ Found FCM token for user {user_id}")
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True,
                        "fcm_token": fcm_token.token
                    }
                }
            else:
                _logger.warning(f"❌ No FCM token found for user {user_id}")
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": False,
                        "error": "No FCM token found for this user"
                    }
                }
                
        except Exception as e:
            _logger.error(f"❌ Error getting user FCM token: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Failed to get user FCM token: {str(e)}",
                    "code": 500
                }
            }

class FCMNotificationHistory(models.Model):
    _name = 'fcm.notification.history'
    _description = 'FCM Notification History'
    _order = 'create_date desc'

    title = fields.Char(string='Title', required=True)
    body = fields.Text(string='Body', required=True)
    sender_id = fields.Many2one('res.users', string='Sender', required=True)
    recipient_id = fields.Many2one('res.users', string='Recipient', required=True)
    notification_type = fields.Char(string='Notification Type', default='general')
    status = fields.Selection([
        ('sent', 'Sent'),
        ('failed', 'Failed'),
        ('pending', 'Pending')
    ], string='Status', default='sent')
    fcm_token = fields.Char(string='FCM Token')
    create_date = fields.Datetime(string='Sent Date', readonly=True, default=fields.Datetime.now)
    
    @api.model
    def create_notification_record(self, title, body, sender_id, recipient_id, notification_type='general', fcm_token=None, status='sent'):
        """Create a notification history record"""
        return self.create({
            'title': title,
            'body': body,
            'sender_id': sender_id,
            'recipient_id': recipient_id,
            'notification_type': notification_type,
            'fcm_token': fcm_token,
            'status': status,
        })

class FCMNotificationController(http.Controller):
    @http.route('/api/fcm/notification_history', type='json', auth='public', methods=['POST'], csrf=False)
    def get_notification_history(self, **kwargs):
        """API endpoint untuk mengambil notification history dari semua user"""
        try:
            # Get notification history from database
            notifications = request.env['fcm.notification.history'].sudo().search_read(
                [],
                ['title', 'body', 'sender_id', 'recipient_id', 'notification_type', 'status', 'create_date'],
                limit=50,  # Limit to last 50 notifications
                order='create_date desc'
            )
            
            # Format the data for Flutter
            formatted_notifications = []
            for notif in notifications:
                sender = request.env['res.users'].sudo().browse(notif['sender_id'][0])
                recipient = request.env['res.users'].sudo().browse(notif['recipient_id'][0])
                
                formatted_notifications.append({
                    'title': notif['title'],
                    'body': notif['body'],
                    'sender_name': sender.name,
                    'recipient_name': recipient.name,
                    'notification_type': notif['notification_type'],
                    'status': notif['status'],
                    'timestamp': notif['create_date'],
                    'type': 'sent' if notif['status'] == 'sent' else 'failed',
                })
            
            _logger.info(f"📋 Retrieved {len(formatted_notifications)} notifications from history")
            
            return {
                "jsonrpc": "2.0",
                "result": {
                    "success": True,
                    "notifications": formatted_notifications
                }
            }
            
        except Exception as e:
            _logger.error(f"❌ Error in get_notification_history: {str(e)}")
            return {
                "jsonrpc": "2.0",
                "error": {
                    "message": f"Failed to get notification history: {str(e)}",
                    "code": 500
                }
            }