# Gmail Push Notification Setup

## Overview
This feature allows users to provide their Gmail address for receiving push notifications for new tickets, separate from their login email (Sigma email).

## How It Works

### First-Time Login
1. When a user logs in for the first time, a popup dialog appears asking for their Gmail address
2. The popup explains that this Gmail is only for push notifications, not for login
3. Users can either:
   - Enter their Gmail address and save it
   - Skip the setup for now

### Gmail Validation
- Only Gmail addresses (@gmail.com) are accepted
- Basic email format validation is performed
- Empty fields are not allowed

### Data Storage
- Gmail address is stored in SharedPreferences with key: `push_notification_gmail_{user_email}`
- Gmail address is also saved to Firestore for server-side push notifications
- A flag is set to prevent showing the popup again: `has_shown_gmail_form_{user_email}`

### Settings Access
- Users can access Gmail settings through the drawer menu
- The settings dialog shows the current Gmail address (if set)
- Users can update their Gmail address at any time

## Implementation Details

### Files Modified
1. `lib/ticket.dart` - Main implementation
2. `lib/notification_service.dart` - Helper methods for Gmail management

### Key Methods
- `_checkFirstTimeLogin()` - Checks if user has seen the Gmail form
- `_showGmailFormDialog()` - Shows the first-time setup popup
- `_showGmailSettingsDialog()` - Shows the settings dialog
- `_submitGmailForm()` - Handles Gmail submission and validation
- `_isValidGmail()` - Validates Gmail format
- `NotificationService.updateGmailForNotifications()` - Saves Gmail to both SharedPreferences and Firestore

### UI Features
- Modern, responsive dialog design
- Clear explanation of purpose
- Skip option for first-time setup
- Current Gmail display in settings
- Success/error feedback messages
- Consistent with app theme colors

## Usage

### For Users
1. First login: Popup appears automatically
2. Settings: Access via drawer menu → Settings
3. Update: Change Gmail address anytime through settings

### For Developers
```dart
// Check if user has Gmail set up
bool hasGmail = await _hasGmailForNotifications();

// Get current Gmail
String? gmail = await _getCurrentGmail();

// Update Gmail
await NotificationService.updateGmailForNotifications(userEmail, gmail);
```

## Benefits
- Separates login credentials from notification preferences
- Allows users to use personal Gmail for notifications
- Maintains security by keeping login email separate
- Provides flexibility for users to update notification preferences
- Integrates with existing Firebase push notification system 