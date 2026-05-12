import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pushnoti/notification_service.dart';

class PushNotificationPage extends StatefulWidget {
  const PushNotificationPage({Key? key}) : super(key: key);

  @override
  State<PushNotificationPage> createState() => _PushNotificationPageState();
}

class _PushNotificationPageState extends State<PushNotificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _recipientController = TextEditingController();
  final _fcmTokenController = TextEditingController();
  
  String _selectedNotificationType = 'general';
  bool _isLoading = false;
  List<Map<String, dynamic>> _notificationHistory = [];
  
  final List<String> _notificationTypes = [
    'general',
    'ticket',
    'timeoff',
    'expense',
    'project',
    'urgent'
  ];

  @override
  void initState() {
    super.initState();
    _loadNotificationHistory();
    _loadCurrentUserInfo();
  }

  Future<void> _loadCurrentUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('user_id') ?? '';
    final currentUserEmail = prefs.getString('email') ?? '';
    
    setState(() {
      _recipientController.text = currentUserEmail;
    });
  }

  Future<void> _loadNotificationHistory() async {
    final prefs = await SharedPreferences.getInstance();
    List<String> logs = prefs.getStringList('push_notification_logs') ?? [];
    setState(() {
      _notificationHistory = logs
          .map((e) => jsonDecode(e) as Map<String, dynamic>)
          .toList()
          .reversed
          .toList();
    });
  }

  Future<void> _sendPushNotification() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final odooUrl = prefs.getString('odooUrl') ?? 'https://sigmarectrix.com';
      final sessionId = prefs.getString('sessionId') ?? '';
      final senderId = prefs.getString('user_id') ?? '';

      // Prepare notification data
      final notificationData = {
        'title': _titleController.text,
        'body': _bodyController.text,
        'recipient_email': _recipientController.text,
        'fcm_token': _fcmTokenController.text.isNotEmpty ? _fcmTokenController.text : null,
        'notification_type': _selectedNotificationType,
        'sender_id': senderId,
        'timestamp': DateTime.now().toIso8601String(),
      };

      // Send to Odoo server
      final response = await http.post(
        Uri.parse('$odooUrl/api/send_push_notification'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$sessionId',
        },
        body: jsonEncode(notificationData),
      );

      print('Push notification response: ${response.statusCode} ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final result = data['result'] ?? {};
        
        if (result['success'] == true) {
          // Save to local history
          await _saveNotificationLog(_titleController.text, _bodyController.text);
          
          // Show success message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Push notification sent successfully!'),
                backgroundColor: Colors.green,
              ),
            );
            
            // Clear form
            _titleController.clear();
            _bodyController.clear();
            _fcmTokenController.clear();
            
            // Reload history
            await _loadNotificationHistory();
          }
        } else {
          throw Exception(result['message'] ?? 'Failed to send notification');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending push notification: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending notification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveNotificationLog(String title, String body) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().toIso8601String();
    final logEntry = {
      'title': title,
      'body': body,
      'timestamp': now,
      'type': 'sent',
    };
    List<String> logs = prefs.getStringList('push_notification_logs') ?? [];
    logs.add(jsonEncode(logEntry));
    await prefs.setStringList('push_notification_logs', logs);
  }

  Future<void> _sendTestNotification() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Send local test notification
      await NotificationService().sendLocalNotification(
        title: 'Test Notification',
        body: 'This is a test notification from MyERP app',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Test notification sent!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending test notification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : const Color(0xFFE8E6F3),
      appBar: AppBar(
        title: Text('Push Notification Test', style: TextStyle(color: Colors.white)),
        backgroundColor: isDarkMode ? Colors.grey[900] : const Color(0xFF282454),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Test Notification Button
            Card(
              color: isDarkMode ? Colors.grey[900] : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Test Local Notification',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Send a test notification to this device',
                      style: TextStyle(
                        color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _sendTestNotification,
                      icon: Icon(Icons.notifications),
                      label: Text('Send Test Notification'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Send Push Notification Form
            Card(
              color: isDarkMode ? Colors.grey[900] : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Send Push Notification',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      SizedBox(height: 16),
                      
                      // Notification Type Dropdown
                      DropdownButtonFormField<String>(
                        value: _selectedNotificationType,
                        decoration: InputDecoration(
                          labelText: 'Notification Type',
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(
                            color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                        dropdownColor: isDarkMode ? Colors.grey[800] : Colors.white,
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        items: _notificationTypes.map((String type) {
                          return DropdownMenuItem<String>(
                            value: type,
                            child: Text(type.toUpperCase()),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedNotificationType = newValue!;
                          });
                        },
                      ),
                      
                      SizedBox(height: 16),
                      
                      // Title Field
                      TextFormField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Notification Title',
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(
                            color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a title';
                          }
                          return null;
                        },
                      ),
                      
                      SizedBox(height: 16),
                      
                      // Body Field
                      TextFormField(
                        controller: _bodyController,
                        decoration: InputDecoration(
                          labelText: 'Notification Body',
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(
                            color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        maxLines: 3,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a message';
                          }
                          return null;
                        },
                      ),
                      
                      SizedBox(height: 16),
                      
                      // Recipient Email Field
                      TextFormField(
                        controller: _recipientController,
                        decoration: InputDecoration(
                          labelText: 'Recipient Email',
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(
                            color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                          ),
                        ),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter recipient email';
                          }
                          if (!value.contains('@')) {
                            return 'Please enter a valid email';
                          }
                          return null;
                        },
                      ),
                      
                      SizedBox(height: 16),
                      
                      // FCM Token Field (Optional)
                      TextFormField(
                        controller: _fcmTokenController,
                        decoration: InputDecoration(
                          labelText: 'FCM Token (Optional)',
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(
                            color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                          ),
                          helperText: 'Leave empty to send to all users with this email',
                        ),
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      
                      SizedBox(height: 24),
                      
                      // Send Button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _sendPushNotification,
                          icon: _isLoading 
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Icon(Icons.send),
                          label: Text(_isLoading ? 'Sending...' : 'Send Push Notification'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF282454),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Notification History
            Card(
              color: isDarkMode ? Colors.grey[900] : Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Notification History',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.remove('push_notification_logs');
                            await _loadNotificationHistory();
                          },
                          child: Text('Clear History'),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Container(
                      height: 200,
                      child: _notificationHistory.isEmpty
                          ? Center(
                              child: Text(
                                'No notifications yet',
                                style: TextStyle(
                                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                            )
                          : ListView.builder(
                              itemCount: _notificationHistory.length,
                              itemBuilder: (context, index) {
                                final notification = _notificationHistory[index];
                                return ListTile(
                                  title: Text(
                                    notification['title'] ?? 'No Title',
                                    style: TextStyle(
                                      color: isDarkMode ? Colors.white : Colors.black,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notification['body'] ?? '',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                                        ),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        notification['timestamp'] != null
                                            ? notification['timestamp'].toString().substring(0, 19).replaceFirst('T', ' ')
                                            : '',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  leading: Icon(
                                    Icons.notifications,
                                    color: notification['type'] == 'sent' ? Colors.green : Colors.blue,
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _recipientController.dispose();
    _fcmTokenController.dispose();
    super.dispose();
  }
} 