# FCM Push Notification Endpoint Deployment Instructions

## Problem
The `/api/fcm/send_notification` endpoint is not deployed on the Odoo server, causing 404 errors when trying to send push notifications.

## Solution
Deploy the FCM push notification endpoint to the Odoo server.

## Steps to Deploy

### 1. Copy the Python file to Odoo server
Copy the file `odoo_push_notification.py` to the Odoo addons directory:

```bash
# On the Odoo server (<ODOO_SERVER_HOST>)
sudo cp odoo_push_notification.py /usr/lib/python3/dist-packages/odoo/addons/
```

### 2. Restart Odoo service
```bash
# On the Odoo server
sudo systemctl restart odoo
```

### 3. Alternative: Add to existing module
If you have access to the existing helpdesk module, add the controller classes to the existing `ticket33.py` file:

```python
# Add these classes to the existing ticket33.py file
class FCMNotificationController(http.Controller):
    @http.route('/api/fcm/send_notification', type='json', auth='public', methods=['POST'], csrf=False)
    def send_push_notification(self, **kwargs):
        # ... (copy the implementation from odoo_push_notification.py)
```

### 4. Test the endpoint
After deployment, test the endpoint:

```bash
curl -X POST http://<ODOO_SERVER_HOST>:8040/api/fcm/send_notification \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Notification",
    "body": "This is a test notification",
    "fcm_token": "YOUR_FCM_TOKEN_HERE"
  }'
```

## Expected Response
If successful, you should see:
```json
{
  "jsonrpc": "2.0",
  "result": {
    "success": true,
    "message": "Push notification sent successfully",
    "fcm_response": {...}
  }
}
```

## Troubleshooting

### 1. Check Odoo logs
```bash
sudo tail -f /var/log/odoo/odoo-server.log
```

### 2. Verify FCM Server Key
Make sure the FCM Server Key is configured in Odoo:
- Go to Settings > Technical > Parameters > System Parameters
- Look for `firebase_server_key`
- If not found, add it with your Firebase Server Key

### 3. Check FCM Token Model
Make sure the `fcm.token` model exists in the database:
```sql
SELECT * FROM fcm_token LIMIT 1;
```

## Current Status
- ✅ Users dropdown working (nested JSON-RPC fix applied)
- ✅ FCM token fetching working
- ❌ Push notification sending (endpoint not deployed)
- 🔄 Flutter app updated to use correct endpoint

## Next Steps
1. Deploy the endpoint to Odoo server
2. Test with real FCM tokens
3. Verify push notifications are received on target devices 