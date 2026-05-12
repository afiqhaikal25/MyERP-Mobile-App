# -*- coding: utf-8 -*-
# Part of Odoo. See LICENSE file for full copyright and licensing details.

# Copyright (c) 2005-2006 Axelor SARL. (http://www.axelor.com)

from collections import defaultdict
from datetime import timedelta
from itertools import groupby
from pytz import timezone, utc

from odoo import api, fields, models, _
from odoo.tools.misc import get_lang
from odoo.http import Controller, route, request


def format_time(env, time):
    return time.strftime(get_lang(env).time_format)


def format_date(env, date):
    return date.strftime(get_lang(env).date_format)


class HrLeave(models.Model):
    _inherit = "hr.leave"

    @api.model
    def _get_leave_interval(self, date_from, date_to, employee_ids):
        # Validated hr.leave create a resource.calendar.leaves
        calendar_leaves = self.env['resource.calendar.leaves'].search([
            ('time_type', '=', 'leave'),
            '|', ('company_id', 'in', employee_ids.mapped('company_id').ids),
                 ('company_id', '=', False),
            '|', ('resource_id', 'in', employee_ids.mapped('resource_id').ids),
                 ('resource_id', '=', False),
            ('date_from', '<=', date_to),
            ('date_to', '>=', date_from),
        ], order='date_from')

        leaves = defaultdict(list)
        for leave in calendar_leaves:
            for employee in employee_ids:
                if (not leave.company_id or leave.company_id == employee.company_id) and\
                   (not leave.resource_id or leave.resource_id == employee.resource_id) and\
                   (not leave.calendar_id or leave.calendar_id == employee.resource_calendar_id):
                    leaves[employee.id].append(leave)

        # Get non-validated time off
        leaves_query = self.env['hr.leave'].search([
            ('employee_id', 'in', employee_ids.ids),
            ('state', 'in', ['confirm', 'validate1']),
            ('date_from', '<=', date_to),
            ('date_to', '>=', date_from)
        ], order='date_from')
        for leave in leaves_query:
            leaves[leave.employee_id.id].append(leave)
        return leaves

    def _get_leave_warning(self, leaves, employee, date_from, date_to):
        loc_cache = {}

        def localize(date):
            if date not in loc_cache:
                loc_cache[date] = utc.localize(date).astimezone(timezone(self.env.user.tz or 'UTC')).replace(tzinfo=None)
            return loc_cache.get(date)

        warning = ''
        periods = self._group_leaves(leaves, employee, date_from, date_to)
        periods_by_states = [list(b) for a, b in groupby(periods, key=lambda x: x['is_validated'])]

        for periods in periods_by_states:
            period_leaves = ''
            for period in periods:
                dfrom = period['from']
                dto = period['to']
                prefix = ''
                if period != periods[0]:
                    if period == periods[-1]:
                        prefix = _(' and')
                    else:
                        prefix = ','

                if period.get('show_hours', False):
                    period_leaves += _('%(prefix)s from the %(dfrom_date)s at %(dfrom)s to the %(dto_date)s at %(dto)s',
                                        prefix=prefix,
                                        dfrom_date=format_date(self.env, localize(dfrom)),
                                        dfrom=format_time(self.env, localize(dfrom)),
                                        dto_date=format_date(self.env, localize(dto)),
                                        dto=format_time(self.env, localize(dto)))
                else:
                    period_leaves += _('%(prefix)s from the %(dfrom)s to the %(dto)s',
                                        prefix=prefix,
                                        dfrom=format_date(self.env, localize(dfrom)),
                                        dto=format_date(self.env, localize(dto)))

            time_off_type = _('is on time off') if periods[0].get('is_validated') else _('has requested time off')
            warning += _('%(employee)s %(time_off_type)s%(period_leaves)s. \n',
                         employee=employee.name, period_leaves=period_leaves, time_off_type=time_off_type)
        return warning

    def _group_leaves(self, leaves, employee_id, date_from, date_to):
        """
            Returns all the leaves happening between `planned_date_begin` and `planned_date_end`
        """
        work_times = {wk[0]: wk[1] for wk in employee_id.list_work_time_per_day(date_from, date_to)}

        def has_working_hours(start_dt, end_dt):
            """
                Returns `True` if there are any working days between `start_dt` and `end_dt`.
            """
            diff_days = (end_dt - start_dt).days
            all_dates = [start_dt.date() + timedelta(days=delta) for delta in range(diff_days + 1)]
            return any(d in work_times for d in all_dates)

        periods = []
        for leave in leaves:
            if leave.date_from > date_to or leave.date_to < date_from:
                continue

            # Can handle both hr.leave and resource.calendar.leaves
            number_of_days = 0
            is_validated = True
            if issubclass(type(leave), self.pool['hr.leave']):
                number_of_days = leave.number_of_days
                is_validated = False
            else:
                dt_delta = (leave.date_to - leave.date_from)
                number_of_days = dt_delta.days + ((dt_delta.seconds / 3600) / 24)

            if not periods or has_working_hours(periods[-1]['from'], leave.date_to):
                periods.append({'is_validated': is_validated, 'from': leave.date_from, 'to': leave.date_to, 'show_hours': number_of_days <= 1})
            else:
                periods[-1]['is_validated'] = is_validated
                if periods[-1]['to'] < leave.date_to:
                    periods[-1]['to'] = leave.date_to
                periods[-1]['show_hours'] = periods[-1].get('show_hours') or number_of_days <= 1
        return periods

    @api.model
    def gantt_unavailability(self, start_date, end_date, scale, group_bys=None, rows=None):
        start_datetime = fields.Datetime.from_string(start_date)
        end_datetime = fields.Datetime.from_string(end_date)
        employee_ids = set()

        # function to "mark" top level rows concerning employees
        # the propagation of that item to subrows is taken care of in the traverse function below
        def tag_employee_rows(rows):
            for row in rows:
                group_bys = row.get('groupedBy')
                res_id = row.get('resId')
                if group_bys:
                    # if employee_id is the first grouping attribute, we mark the row
                    if group_bys[0] == 'employee_id' and res_id:
                        employee_id = res_id
                        employee_ids.add(employee_id)
                        row['employee_id'] = employee_id
                    # else we recursively traverse the rows where employee_id appears in the group_by
                    elif 'employee_id' in group_bys:
                        tag_employee_rows(row.get('rows'))

        tag_employee_rows(rows)
        employees = self.env['hr.employee'].browse(employee_ids)
        leaves_mapping = employees.mapped('resource_id')._get_unavailable_intervals(start_datetime, end_datetime)

        # function to recursively replace subrows with the ones returned by func
        def traverse(func, row):
            new_row = dict(row)
            if new_row.get('employee_id'):
                for sub_row in new_row.get('rows'):
                    sub_row['employee_id'] = new_row['employee_id']
            new_row['rows'] = [traverse(func, row) for row in new_row.get('rows')]
            return func(new_row)

        cell_dt = timedelta(hours=1) if scale in ['day', 'week'] else timedelta(hours=12)

        # for a single row, inject unavailability data
        def inject_unvailabilty(row):
            new_row = dict(row)

            if row.get('employee_id'):
                employee_id = self.env['hr.employee'].browse(row.get('employee_id'))
                if employee_id:
                    # remove intervals smaller than a cell, as they will cause half a cell to turn grey
                    # ie: when looking at a week, a employee start everyday at 8, so there is a unavailability
                    # like: 2019-05-22 20:00 -> 2019-05-23 08:00 which will make the first half of the 23's cell grey
                    notable_intervals = filter(lambda interval: interval[1] - interval[0] >= cell_dt, leaves_mapping[employee_id.resource_id.id])
                    new_row['unavailabilities'] = [{'start': interval[0], 'stop': interval[1]} for interval in notable_intervals]
            return new_row

        return [traverse(inject_unvailabilty, row) for row in rows]

    def write(self, vals):
        import logging
        _logger = logging.getLogger(__name__)
        _logger.info(f"[DEBUG] HrLeave.write called with vals: {vals}")
        res = super(HrLeave, self).write(vals)
        for leave in self:
            if 'state' in vals and vals['state'] in ['validate', 'validate1']:
                _logger.info(f"[DEBUG] HrLeave.write: state change detected for leave {leave.id}, user {leave.employee_id.user_id.id}")
                user = leave.employee_id.user_id
                if user:
                    # Cari semua FCM token user (guna model fcm.token)
                    fcm_tokens = self.env['fcm.token'].sudo().search([('user_id', '=', user.id)])
                    if not fcm_tokens:
                        self.env['ir.logging'].sudo().create({
                            'name': 'TimeOff PushNoti',
                            'type': 'server',
                            'level': 'warning',
                            'message': f"No FCM token found for user {user.id}",
                            'path': 'hr_leave.py',
                            'func': 'write',
                            'line': 0,
                        })
                        continue
                    # Dapatkan server key dari config
                    server_key = self.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
                    if not server_key:
                        self.env['ir.logging'].sudo().create({
                            'name': 'TimeOff PushNoti',
                            'type': 'server',
                            'level': 'error',
                            'message': "FCM Server Key is missing in Odoo configuration.",
                            'path': 'hr_leave.py',
                            'func': 'write',
                            'line': 0,
                        })
                        continue
                    headers = {
                        'Content-Type': 'application/json',
                        'Authorization': f'key={server_key}',
                    }
                    for token in fcm_tokens:
                        payload = {
                            'to': token.token,
                            'notification': {
                                'title': "Your Time Off have been Approved",
                                'body': "Please Check Your Time Off",
                                'sound': 'default',
                            },
                            'data': {
                                'type': 'timeoff_approved',
                                'leave_id': leave.id,
                                'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                            },
                            'priority': 'high',
                        }
                        try:
                            import requests
                            response = requests.post(
                                'https://fcm.googleapis.com/fcm/send',
                                headers=headers,
                                json=payload,
                                timeout=10
                            )
                            if response.status_code == 200:
                                self.env['ir.logging'].sudo().create({
                                    'name': 'TimeOff PushNoti',
                                    'type': 'server',
                                    'level': 'info',
                                    'message': "Time Off notification sent to ...",
                                    'path': 'hr_leave.py',
                                    'func': 'write',
                                    'line': 0,
                                })
                            else:
                                self.env['ir.logging'].sudo().create({
                                    'name': 'TimeOff PushNoti',
                                    'type': 'server',
                                    'level': 'error',
                                    'message': f"Failed to send Time Off notification: {response.text}",
                                    'path': 'hr_leave.py',
                                    'func': 'write',
                                    'line': 0,
                                })
                        except Exception as e:
                            self.env['ir.logging'].sudo().create({
                                'name': 'TimeOff PushNoti',
                                'type': 'server',
                                'level': 'error',
                                'message': f"Exception sending Time Off notification: {str(e)}",
                                'path': 'hr_leave.py',
                                'func': 'write',
                                'line': 0,
                            })
        return res


class LeaveApiController(Controller):
    @route('/api/leaves', type='json', auth='public')
    def get_leaves(self, employee_id=None, user_id=None, year=None, month=None, approval_only=None):
        import logging
        import calendar
        from datetime import datetime, date, time

        _logger = logging.getLogger(__name__)
        _logger.info(f'[API DEBUG] INPUT: employee_id={employee_id}, user_id={user_id}, year={year}, month={month}, approval_only={approval_only}')
        _logger.info(f'[API DEBUG] User ID type: {type(user_id)}, value: {user_id}')
        _logger.info(f'[API DEBUG] Employee ID type: {type(employee_id)}, value: {employee_id}')
        
        # Debug: Check if employee_id is being passed correctly
        if employee_id:
            _logger.info(f'[API DEBUG] ✅ Employee ID provided: {employee_id}')
        else:
            _logger.info(f'[API DEBUG] ❌ No Employee ID provided')
            
        domain = []
        
        # Handle approval_only parameter
        if approval_only:
            # Get all leaves that need approval (confirm or validate1 status)
            domain.extend([
                ('state', 'in', ['confirm', 'validate1'])
            ])
            _logger.info(f'[API DEBUG] Fetching approval leaves only')
            _logger.info(f'[API DEBUG] Domain for approval leaves: {domain}')
        else:
            # Logic for user-specific leaves (simplified)
            _logger.info(f'[API DEBUG] Processing user-specific leaves')
                    
            # Use employee_id from frontend if provided, otherwise find it from user_id
            if employee_id:
                domain.append(('employee_id', '=', int(employee_id)))
                _logger.info(f'[API DEBUG] Added employee filter from frontend: employee_id = {employee_id}')
            elif user_id:
                # Fallback: find employee_id from user_id
                user = request.env['res.users'].sudo().browse(int(user_id))
                if user.exists():
                    employee = request.env['hr.employee'].sudo().search([('user_id', '=', user.id)], limit=1)
                    if employee:
                        domain.append(('employee_id', '=', employee.id))
                        _logger.info(f'[API DEBUG] Added employee filter from user_id: employee_id = {employee.id}')
                    else:
                        _logger.warning(f'[API DEBUG] No employee found for user_id: {user_id}')
                        # Don't return any leaves if no employee found
                        domain.append(('employee_id', '=', -1))  # Force no results
                else:
                    _logger.warning(f'[API DEBUG] User {user_id} does not exist')
                    # Don't return any leaves if user doesn't exist
                    domain.append(('employee_id', '=', -1))  # Force no results
            else:
                _logger.warning(f'[API DEBUG] No employee_id or user_id provided, will return all leaves')
                
            # DEBUG: Show what domain we're using
            _logger.info(f'[API DEBUG] Final domain for leaves: {domain}')

            if year and month:
                try:
                    year_int = int(year)
                    month_int = int(month)
                    _, last_day = calendar.monthrange(year_int, month_int)
                    month_start_dt = datetime.combine(date(year_int, month_int, 1), time.min).date()
                    month_end_dt = datetime.combine(date(year_int, month_int, last_day), time.max).date()
                    domain.extend([
                        ('request_date_from', '<=', month_end_dt),
                        ('request_date_to', '>=', month_start_dt),
                    ])
                except (ValueError, TypeError) as e:
                    _logger.warning(f'Invalid year/month format: year={year}, month={month}, error: {e}')
        
        _logger.info(f'[API DEBUG] Final domain: {domain}')
        _logger.info(f'[API DEBUG] Domain type: {type(domain)}')
        _logger.info(f'[API DEBUG] Domain length: {len(domain)}')
        leaves = request.env['hr.leave'].sudo().search(domain)
        _logger.info(f'[API DEBUG] Found {len(leaves)} leave(s)')
        
        # Debug: Show all leaves in system
        all_leaves = request.env['hr.leave'].sudo().search([])
        _logger.info(f'[API DEBUG] Total leaves in system: {len(all_leaves)}')
        for leave in all_leaves[:5]:  # Show first 5 leaves
            _logger.info(f'[API DEBUG] ALL LEAVES: {leave.employee_id.name} (ID: {leave.employee_id.id}) | {leave.holiday_status_id.name} | {leave.request_date_from} - {leave.request_date_to} | {leave.state}')
        
        # Debug: Show filtered leaves
        _logger.info(f'[API DEBUG] Found {len(leaves)} filtered leaves')
        for leave in leaves:
            _logger.info(f'[API DEBUG] FILTERED LEAVE: {leave.employee_id.name} (ID: {leave.employee_id.id}) | {leave.holiday_status_id.name} | {leave.request_date_from} - {leave.request_date_to} | {leave.state}')
            
        # Debug: Check if filtering is working
        if employee_id:
            expected_leaves = request.env['hr.leave'].sudo().search([('employee_id', '=', int(employee_id))])
            _logger.info(f'[API DEBUG] Expected leaves for employee_id {employee_id}: {len(expected_leaves)}')
            for leave in expected_leaves:
                _logger.info(f'[API DEBUG] EXPECTED LEAVE: {leave.employee_id.name} (ID: {leave.employee_id.id}) | {leave.holiday_status_id.name} | {leave.request_date_from} - {leave.request_date_to} | {leave.state}')
        result = []
        for leave in leaves:
            result.append({
                'id': leave.id,
                'employee_id': leave.employee_id.id,
                'employee_name': leave.employee_id.name,
                'date_from': datetime.combine(leave.request_date_from, time.min).isoformat(),
                'date_to': datetime.combine(leave.request_date_to, time.max).isoformat(),
                'leave_type': leave.holiday_status_id.name,
                'state': leave.state,
                'description': leave.name or '',
            })
        _logger.info(f'[API DEBUG] Returning {len(result)} leave(s)')
        return result

    @route('/api/leaves/create', type='json', auth='public', methods=['POST'])
    def create_leave(self, **kwargs):
        import logging
        _logger = logging.getLogger(__name__)
        data = request.jsonrequest
        user_id = data.get('user_id')
        date_from_str = data.get('date_from')
        date_to_str = data.get('date_to')
        leave_type = data.get('leave_type')
        description = data.get('description', '')
        
        _logger.info(f'[API DEBUG] Create leave request: user_id={user_id}, leave_type={leave_type}')
        _logger.info(f'[API DEBUG] Date range: {date_from_str} to {date_to_str}')
        
        # Validate user_id
        if not user_id:
            _logger.error('[API DEBUG] user_id is missing')
            return {'success': False, 'error': 'user_id is required'}
        
        try:
            user_id_int = int(user_id)
        except (ValueError, TypeError):
            _logger.error(f'[API DEBUG] Invalid user_id format: {user_id}')
            return {'success': False, 'error': f'Invalid user_id format: {user_id}'}
        
        # Cari employee_id dari user_id
        employee = request.env['hr.employee'].sudo().search([('user_id', '=', user_id_int)], limit=1)
        
        if not employee:
            _logger.error(f'[API DEBUG] Employee not found for user_id: {user_id_int}')
            _logger.error(f'[API DEBUG] Available employees with user_id: {request.env["hr.employee"].sudo().search([]).mapped("user_id")}')
            return {'success': False, 'error': f'Employee not found for user_id: {user_id_int}. Please check if employee record exists and is linked to user.'}
        
        _logger.info(f'[API DEBUG] Found employee: {employee.name} (ID: {employee.id})')
        
        # Cari holiday_status_id dari nama leave_type
        leave_type_rec = request.env['hr.leave.type'].sudo().search([('name', 'ilike', leave_type)], limit=1)
        
        if not leave_type_rec:
            _logger.error(f'[API DEBUG] Leave type not found: {leave_type}')
            _logger.error(f'[API DEBUG] Available leave types: {request.env["hr.leave.type"].sudo().search([]).mapped("name")}')
            return {'success': False, 'error': f'Leave type "{leave_type}" not found. Available types: {", ".join(request.env["hr.leave.type"].sudo().search([]).mapped("name"))}'}
        
        _logger.info(f'[API DEBUG] Found leave type: {leave_type_rec.name} (ID: {leave_type_rec.id})')
        # Create leave
        try:
            from datetime import datetime

            def parse_datetime(dt_str):
                dt = fields.Datetime.from_string(dt_str)
                if dt is not None:
                    return dt
                try:
                    # Remove 'Z' if present (for UTC)
                    dt_str = dt_str.replace('Z', '')
                    # Remove milliseconds if present
                    if '.' in dt_str:
                        dt_str = dt_str.split('.')[0]
                    # Replace 'T' with space
                    dt_str = dt_str.replace('T', ' ')
                    # Try several formats
                    for fmt in ('%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M', '%Y-%m-%d'):
                        try:
                            return datetime.strptime(dt_str, fmt)
                        except Exception:
                            continue
                    return None
                except Exception as e:
                    return None

            date_from_dt = parse_datetime(date_from_str)
            date_to_dt = parse_datetime(date_to_str)

            if not date_from_dt or not date_to_dt:
                return {'success': False, 'error': 'Invalid date format'}

            leave = request.env['hr.leave'].sudo().create({
                'employee_id': employee.id,
                'holiday_status_id': leave_type_rec.id,
                'request_date_from': date_from_dt.date(),
                'request_date_to': date_to_dt.date(),
                'date_from': date_from_str,
                'date_to': date_to_str,
                'name': description or leave_type,
                'state': 'confirm',
            })
            _logger.info(f'[API DEBUG] Created leave id={leave.id}')
            return {'success': True, 'leave_id': leave.id}
        except Exception as e:
            _logger.error(f'Error creating leave: {e}')
            return {'success': False, 'error': str(e)}

    @route('/api/leaves/approve', type='json', auth='public', methods=['POST'])
    def approve_leave(self, **kwargs):
        import logging
        _logger = logging.getLogger(__name__)
        data = request.jsonrequest
        leave_id = data.get('leave_id')
        
        _logger.info(f'[API DEBUG] Approve leave request: leave_id={leave_id}')
        
        if not leave_id:
            return {'success': False, 'error': 'Leave ID is required'}
        
        try:
            leave = request.env['hr.leave'].sudo().browse(int(leave_id))
            if not leave.exists():
                _logger.error(f'[API DEBUG] Leave {leave_id} not found')
                return {'success': False, 'error': 'Leave not found'}
            
            _logger.info(f'[API DEBUG] Current leave state: {leave.state}')
            
            # Approve the leave
            if leave.state == 'confirm':
                leave.write({'state': 'validate1'})
                _logger.info(f'[API DEBUG] Leave {leave_id} approved: confirm → validate1')
                
                # Send notification to employee
                self._send_approval_notification(leave, 'first_approval')
                
                return {'success': True, 'message': 'Leave approved to first level', 'new_state': 'validate1'}
            elif leave.state == 'validate1':
                leave.write({'state': 'validate'})
                _logger.info(f'[API DEBUG] Leave {leave_id} approved: validate1 → validate')
                
                # Send notification to employee
                self._send_approval_notification(leave, 'final_approval')
                
                return {'success': True, 'message': 'Leave fully approved', 'new_state': 'validate'}
            else:
                _logger.warning(f'[API DEBUG] Leave {leave_id} cannot be approved in state: {leave.state}')
                return {'success': False, 'error': f'Leave cannot be approved in current state: {leave.state}'}
            
        except Exception as e:
            _logger.error(f'Error approving leave {leave_id}: {e}')
            return {'success': False, 'error': str(e)}

    @route('/api/leaves/refuse', type='json', auth='public', methods=['POST'])
    def refuse_leave(self, **kwargs):
        import logging
        _logger = logging.getLogger(__name__)
        data = request.jsonrequest
        leave_id = data.get('leave_id')
        
        _logger.info(f'[API DEBUG] Refuse leave request: leave_id={leave_id}')
        
        if not leave_id:
            return {'success': False, 'error': 'Leave ID is required'}
        
        try:
            leave = request.env['hr.leave'].sudo().browse(int(leave_id))
            if not leave.exists():
                _logger.error(f'[API DEBUG] Leave {leave_id} not found')
                return {'success': False, 'error': 'Leave not found'}
            
            _logger.info(f'[API DEBUG] Current leave state: {leave.state}')
            
            # Refuse the leave
            leave.write({'state': 'refuse'})
            _logger.info(f'[API DEBUG] Leave {leave_id} refused: {leave.state} → refuse')
            
            # Send notification to employee
            self._send_approval_notification(leave, 'refused')
            
            return {'success': True, 'message': 'Leave refused successfully', 'new_state': 'refuse'}
        except Exception as e:
            _logger.error(f'Error refusing leave {leave_id}: {e}')
            return {'success': False, 'error': str(e)}

    @route('/api/leaves/manager/approve', type='json', auth='public', methods=['POST'])
    def manager_approve_leave(self, **kwargs):
        import logging
        _logger = logging.getLogger(__name__)
        data = request.jsonrequest
        leave_id = data.get('leave_id')
        manager_id = data.get('manager_id')
        
        _logger.info(f'[API DEBUG] Manager approve leave request: leave_id={leave_id}, manager_id={manager_id}')
        
        if not leave_id or not manager_id:
            return {'success': False, 'error': 'Leave ID and Manager ID are required'}
        
        try:
            result = self.approve_as_manager(leave_id, manager_id)
            _logger.info(f'[API DEBUG] Manager approval result: {result}')
            return result
        except Exception as e:
            _logger.error(f'Error in manager approval: {e}')
            return {'success': False, 'error': str(e)}

    @route('/api/leaves/manager/list', type='json', auth='public')
    def get_manager_leaves(self, manager_id=None):
        import logging
        _logger = logging.getLogger(__name__)
        
        _logger.info(f'[API DEBUG] Get manager leaves request: manager_id={manager_id}')
        
        try:
            leaves = self.get_manager_approvals(manager_id)
            result = []
            for leave in leaves:
                result.append({
                    'id': leave.id,
                    'employee_id': leave.employee_id.id,
                    'employee_name': leave.employee_id.name,
                    'date_from': leave.request_date_from.isoformat(),
                    'date_to': leave.request_date_to.isoformat(),
                    'leave_type': leave.holiday_status_id.name,
                    'state': leave.state,
                    'description': leave.name or '',
                })
                _logger.info(f'[API DEBUG] Added leave to result: ID={leave.id}, Employee={leave.employee_id.name}, State={leave.state}')
            _logger.info(f'[API DEBUG] Returning {len(result)} manager leaves')
            return result
        except Exception as e:
            _logger.error(f'Error getting manager leaves: {e}')
            return []

    @route('/api/leaves/manager/check', type='json', auth='public')
    def check_user_is_manager(self, **kwargs):
        import logging
        _logger = logging.getLogger(__name__)
        data = request.jsonrequest
        user_id = data.get('user_id')
        
        _logger.info(f'[API DEBUG] Check if user is manager: user_id={user_id}')
        
        if not user_id:
            return {'result': False}
            
    @route('/api/leaves/employee/check', type='json', auth='public')
    def check_employee_data(self, **kwargs):
        import logging
        _logger = logging.getLogger(__name__)
        data = request.jsonrequest
        user_id = data.get('user_id')
        
        _logger.info(f'[API DEBUG] Check employee data: user_id={user_id}')
        
        if not user_id:
            return {'result': False}
        
        try:
            # Check if user exists
            user = request.env['res.users'].sudo().browse(int(user_id))
            if not user.exists():
                return {'result': False, 'error': 'User not found'}
            
            # Check if user has employee record
            employee = request.env['hr.employee'].sudo().search([
                ('user_id', '=', int(user_id))
            ], limit=1)
            
            if not employee:
                return {'result': False, 'error': 'Employee record not found'}
            
            # Get employee data
            employee_data = {
                'id': employee.id,
                'name': employee.name,
                'user_id': employee.user_id.id if employee.user_id else None,
                'parent_id': employee.parent_id.id if employee.parent_id else None,
                'parent_name': employee.parent_id.name if employee.parent_id else None,
                'parent_user_id': employee.parent_id.user_id.id if employee.parent_id and employee.parent_id.user_id else None,
                'parent_user_name': employee.parent_id.user_id.name if employee.parent_id and employee.parent_id.user_id else None,
            }
            
            _logger.info(f'[API DEBUG] Employee data: {employee_data}')
            return {'result': True, 'employee': employee_data}
            
        except Exception as e:
            _logger.error(f'Error checking employee data: {e}')
            return {'result': False, 'error': str(e)}
        
        try:
            # Debug: Show all users in system
            all_users = request.env['res.users'].sudo().search([])
            _logger.info(f'[API DEBUG] Total users in system: {len(all_users)}')
            for user in all_users[:5]:  # Show first 5 users
                _logger.info(f'[API DEBUG] User: {user.name} (ID: {user.id})')
            
            # Check if user exists
            user = request.env['res.users'].sudo().browse(int(user_id))
            if not user.exists():
                _logger.error(f'[API DEBUG] User {user_id} does not exist')
                return {'result': False}
            
            _logger.info(f'[API DEBUG] Checking if user {user_id} ({user.name}) is manager')
            
            # Check if user has any employees under them (is a manager)
            _logger.info(f'[API DEBUG] Searching for employees with parent_id.user_id = {user_id}')
            
            # First, let's check if there are any employees at all
            all_employees = request.env['hr.employee'].sudo().search([])
            _logger.info(f'[API DEBUG] Total employees found: {len(all_employees)}')
            
            # Check if any employee has a parent
            employees_with_parent = request.env['hr.employee'].sudo().search([
                ('parent_id', '!=', False)
            ])
            _logger.info(f'[API DEBUG] Employees with parent: {len(employees_with_parent)}')
            
            # Check if any employee has a parent with user_id
            employees_with_parent_user = request.env['hr.employee'].sudo().search([
                ('parent_id.user_id', '!=', False)
            ])
            _logger.info(f'[API DEBUG] Employees with parent user: {len(employees_with_parent_user)}')
            
            # Now search for employees under this specific user
            employees = request.env['hr.employee'].sudo().search([
                ('parent_id.user_id', '=', int(user_id))
            ])
            
            # Debug: Show all employees and their managers
            all_employees = request.env['hr.employee'].sudo().search([])
            _logger.info(f'[API DEBUG] Total employees in system: {len(all_employees)}')
            for emp in all_employees[:10]:  # Show first 10 employees
                manager_name = emp.parent_id.name if emp.parent_id else "None"
                manager_user_name = emp.parent_id.user_id.name if emp.parent_id and emp.parent_id.user_id else "None"
                manager_user_id = emp.parent_id.user_id.id if emp.parent_id and emp.parent_id.user_id else "None"
                _logger.info(f'[API DEBUG] Employee: {emp.name} (ID: {emp.id}), Manager: {manager_name}, Manager User: {manager_user_name} (ID: {manager_user_id})')
            
            is_manager = len(employees) > 0
            _logger.info(f'[API DEBUG] User {user_id} is manager: {is_manager} (has {len(employees)} employees)')
            
            # Debug: Show employees under this user
            for emp in employees:
                _logger.info(f'[API DEBUG] Employee under user {user_id}: {emp.name} (ID: {emp.id})')
            
            return {'result': is_manager}
        except Exception as e:
            _logger.error(f'Error checking if user is manager: {e}')
            return {'result': False}

    def get_manager_approvals(self, manager_id=None):
        """Get all leaves that need manager approval"""
        import logging
        _logger = logging.getLogger(__name__)
        
        domain = [('state', 'in', ['confirm', 'validate1'])]
        
        if manager_id:
            # Filter by specific manager
            domain.append(('employee_id.parent_id.user_id', '=', manager_id))
            _logger.info(f'[API DEBUG] Manager ID: {manager_id}')
            _logger.info(f'[API DEBUG] Domain for manager approvals: {domain}')
        
        leaves = self.env['hr.leave'].sudo().search(domain)
        _logger.info(f'[API DEBUG] Found {len(leaves)} leaves for manager {manager_id}')
        
        # Debug: Show all leaves in system
        all_leaves = self.env['hr.leave'].sudo().search([])
        _logger.info(f'[API DEBUG] Total leaves in system: {len(all_leaves)}')
        for leave in all_leaves[:5]:  # Show first 5 leaves
            _logger.info(f'[API DEBUG] Leave: {leave.employee_id.name}, State: {leave.state}, Manager: {leave.employee_id.parent_id.name if leave.employee_id.parent_id else "None"}')
        
        # Debug: Show leaves for this manager
        for leave in leaves:
            _logger.info(f'[API DEBUG] Leave for manager {manager_id}: {leave.employee_id.name}, State: {leave.state}')
        
        return leaves
        
    def approve_as_manager(self, leave_id, manager_id):
        """Approve leave as manager"""
        try:
            leave = self.env['hr.leave'].sudo().browse(int(leave_id))
            if not leave.exists():
                return {'success': False, 'error': 'Leave not found'}
                
            # Check if user is manager for this employee
            if leave.employee_id.parent_id.user_id.id != int(manager_id):
                return {'success': False, 'error': 'Not authorized to approve this leave'}
                
            # Approve the leave
            if leave.state == 'confirm':
                leave.write({'state': 'validate1'})
                self._send_approval_notification(leave, 'first_approval')
                return {'success': True, 'message': 'Leave approved by manager', 'new_state': 'validate1'}
            elif leave.state == 'validate1':
                leave.write({'state': 'validate'})
                self._send_approval_notification(leave, 'final_approval')
                return {'success': True, 'message': 'Leave fully approved by manager', 'new_state': 'validate'}
            else:
                return {'success': False, 'error': f'Leave cannot be approved in current state: {leave.state}'}
                
        except Exception as e:
            return {'success': False, 'error': str(e)}
            
    def _send_approval_notification(self, leave, action_type):
        """Send push notification to employee about leave approval/refusal"""
        try:
            user = leave.employee_id.user_id
            if not user:
                return
            fcm_tokens = self.env['fcm.token'].sudo().search([('user_id', '=', user.id)])
            if not fcm_tokens:
                return
            
            # Get server key
            server_key = self.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
            if not server_key:
                return
            
            # Prepare notification message
            if action_type == 'first_approval':
                title = "Leave Request Approved (First Level)"
                body = f"Your leave request from {leave.request_date_from} to {leave.request_date_to} has been approved by first approver."
                notification_type = 'timeoff_first_approved'
            elif action_type == 'final_approval':
                title = "Leave Request Fully Approved"
                body = f"Your leave request from {leave.request_date_from} to {leave.request_date_to} has been fully approved!"
                notification_type = 'timeoff_approved'
            elif action_type == 'refused':
                title = "Leave Request Refused"
                body = f"Your leave request from {leave.request_date_from} to {leave.request_date_to} has been refused."
                notification_type = 'timeoff_refused'
            else:
                return
            
            headers = {
                'Content-Type': 'application/json',
                'Authorization': f'key={server_key}',
            }
            
            for token in fcm_tokens:
                payload = {
                    'to': token.token,
                    'notification': {
                        'title': title,
                        'body': body,
                        'sound': 'default',
                    },
                    'data': {
                        'type': notification_type,
                        'leave_id': leave.id,
                        'action_type': action_type,
                        'click_action': 'FLUTTER_NOTIFICATION_CLICK'
                    },
                    'priority': 'high',
                }
                
                try:
                    import requests
                    response = requests.post(
                        'https://fcm.googleapis.com/fcm/send',
                        headers=headers,
                        json=payload,
                        timeout=10
                    )
                    if response.status_code == 200:
                        self.env['ir.logging'].sudo().create({
                            'name': 'Leave Approval Notification',
                            'type': 'server',
                            'level': 'info',
                            'message': f"Leave {action_type} notification sent to user {user.id}",
                            'path': 'hr_leave.py',
                            'func': '_send_approval_notification',
                            'line': 0,
                        })
                except Exception as e:
                    self.env['ir.logging'].sudo().create({
                        'name': 'Leave Approval Notification',
                        'type': 'server',
                        'level': 'error',
                        'message': f"Failed to send leave {action_type} notification: {str(e)}",
                        'path': 'hr_leave.py',
                        'func': '_send_approval_notification',
                        'line': 0,
                    })
        except Exception as e:
            self.env['ir.logging'].sudo().create({
                'name': 'Leave Approval Notification',
                'type': 'server',
                'level': 'error',
                'message': f"Exception in _send_approval_notification: {str(e)}",
                'path': 'hr_leave.py',
                'func': '_send_approval_notification',
                'line': 0,
            })