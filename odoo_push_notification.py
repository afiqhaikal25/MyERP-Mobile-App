#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import logging
import requests
from odoo import http
from odoo.http import request

_logger = logging.getLogger(__name__)

class FCMNotificationController(http.Controller):
    @http.route('/api/fcm/send_notification', type='json', auth='public', methods=['POST'], csrf=False)
    def send_push_notification(self, **kwargs):
        try:
            data = request.jsonrequest
            fcm_token = data.get('fcm_token')
            recipient_user_id = data.get('recipient_user_id')
            recipient_email = data.get('recipient_email')
            title = data.get('title')
            body = data.get('body')
            notification_type = data.get('notification_type', 'general')
            sender_id = data.get('sender_id')
            
            _logger.info(f"📤 Received push notification request:")
            _logger.info(f"📋 Title: {title}")
            _logger.info(f"📋 Body: {body}")
            
            if recipient_user_id and not fcm_token:
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
            
            if not fcm_token:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "FCM token or recipient_user_id is required",
                        "code": 400
                    }
                }
            
            server_key = request.env['ir.config_parameter'].sudo().get_param('firebase_server_key')
            if not server_key:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": "FCM Server Key not configured",
                        "code": 500
                    }
                }
            
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
                response_data = response.json()
                _logger.info(f"✅ Push notification sent successfully!")
                
                return {
                    "jsonrpc": "2.0",
                    "result": {
                        "success": True,
                        "message": "Push notification sent successfully",
                        "fcm_response": response_data
                    }
                }
            else:
                return {
                    "jsonrpc": "2.0",
                    "error": {
                        "message": f"FCM API error: {response.status_code}",
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