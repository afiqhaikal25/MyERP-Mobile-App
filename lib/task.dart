import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:ticket/odoo_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';

class TaskPage extends StatefulWidget {
  final bool isDarkMode;
  final String currentUserId;
  final String? selectedProject;
  final String? projectId;

  const TaskPage({
    Key? key, 
    required this.isDarkMode, 
    required this.currentUserId,
    this.selectedProject,
    this.projectId,
  }) : super(key: key);

  @override
  State<TaskPage> createState() => _TaskPageState();
}

class _TaskPageState extends State<TaskPage> {
  final TextEditingController _taskTitleController = TextEditingController();
  final TextEditingController _projectController = TextEditingController();
  final TextEditingController _dueDateController = TextEditingController();

  Map<String, dynamic>? _getCurrentUserFromList() {
  try {
    return _users.firstWhere(
      (u) => (u['id']?.toString() ?? '') == widget.currentUserId,
    );
  } catch (_) {
    return null;
  }
}

  
  List<Map<String, dynamic>> _users = [];
  String? _selectedUser;
  String? _selectedUserName;
  String? _selectedUserEmail;
  DateTime? _selectedDueDate;
  bool _isLoadingUsers = false;
  bool _isAssigningTask = false;
  List<Map<String, dynamic>> _localTasks = [];
  List<Map<String, dynamic>> _notificationLogs = [];
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadLocalTasks();
    _loadNotificationLogs();
    _registerFCMToken();
    _startCountdownTimer();
    
    // Pre-fill project field if project is selected
    if (widget.selectedProject != null) {
      _projectController.text = widget.selectedProject!;
    }
  }

  void _startCountdownTimer() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          // This will trigger a rebuild every second to update countdown
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _taskTitleController.dispose();
    _projectController.dispose();
    _dueDateController.dispose();
    super.dispose();
  }

  // Load tasks from SharedPreferences
  Future<void> _loadLocalTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = prefs.getString('local_tasks') ?? '[]';
      final tasksList = json.decode(tasksJson) as List;
      setState(() {
        _localTasks = tasksList.map((task) => Map<String, dynamic>.from(task)).toList();
      });
      print("✅ Loaded ${_localTasks.length} local tasks");
    } catch (e) {
      print("❌ Error loading local tasks: $e");
    }
  }

  // Save tasks to SharedPreferences
  Future<void> _saveLocalTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = json.encode(_localTasks);
      await prefs.setString('local_tasks', tasksJson);
      print("✅ Saved ${_localTasks.length} tasks to local storage");
    } catch (e) {
      print("❌ Error saving local tasks: $e");
    }
  }

  // Load notification logs from SharedPreferences
  Future<void> _loadNotificationLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = prefs.getString('notification_logs') ?? '[]';
      final logsList = json.decode(logsJson) as List;
      setState(() {
        _notificationLogs = logsList.map((log) => Map<String, dynamic>.from(log)).toList();
      });
      print("✅ Loaded ${_notificationLogs.length} notification logs");
    } catch (e) {
      print("❌ Error loading notification logs: $e");
    }
  }

  // Save notification logs to SharedPreferences
  Future<void> _saveNotificationLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final logsJson = json.encode(_notificationLogs);
      await prefs.setString('notification_logs', logsJson);
      print("✅ Saved ${_notificationLogs.length} notification logs");
    } catch (e) {
      print("❌ Error saving notification logs: $e");
    }
  }

  // Get notification log for a specific task
  Map<String, dynamic>? _getNotificationLogForTask(String taskTitle) {
    try {
      return _notificationLogs.firstWhere(
        (log) => log['taskTitle'] == taskTitle,
        orElse: () => <String, dynamic>{},
      );
    } catch (e) {
      return null;
    }
  }

  // Build countdown timer widget
  Widget _buildTaskCountdownTimer(Map<String, dynamic> task) {
    final dueDate = task['dueDate'];
    print('🔍 Task countdown - Task: ${task['title']}');
    print('🔍 Task countdown - Due date: $dueDate');
    
    if (dueDate == null) {
      print('🔍 Task countdown - No due date found');
      // Show a test countdown for debugging
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer, size: 12, color: Colors.blue),
            const SizedBox(width: 4),
            Text(
              'Test Countdown',
              style: TextStyle(
                fontSize: 10,
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    }
    
    try {
      final dueDateTime = DateTime.parse(dueDate);
      print('🔍 Task countdown - Parsed due date: $dueDateTime');
      final now = DateTime.now();
      final difference = dueDateTime.difference(now);
      print('🔍 Task countdown - Time difference: ${difference.inMinutes} minutes');
      
      if (difference.isNegative) {
        // Past due
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning, size: 12, color: Colors.red),
              const SizedBox(width: 4),
              Text(
                'Overdue',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      } else {
        // Countdown
        final days = difference.inDays;
        final hours = difference.inHours % 24;
        final minutes = difference.inMinutes % 60;
        
        String countdownText = '';
        if (days > 0) {
          countdownText = '${days}d ${hours}h ${minutes}m';
        } else if (hours > 0) {
          countdownText = '${hours}h ${minutes}m';
        } else {
          countdownText = '${minutes}m';
        }
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.timer, size: 12, color: Colors.green),
              const SizedBox(width: 4),
              Text(
                countdownText,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      return SizedBox.shrink();
    }
  }

  // Add notification log entry
  Future<void> _addNotificationLog(String taskTitle, String assignedToName, String assignedToEmail, bool success, String message) async {
    final logEntry = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'taskTitle': taskTitle,
      'assignedToName': assignedToName,
      'assignedToEmail': assignedToEmail,
      'success': success,
      'message': message,
      'timestamp': DateTime.now().toIso8601String(),
      'timestampDisplay': DateFormat('dd/MM/yyyy HH:mm:ss').format(DateTime.now()),
    };
    
    if (mounted) {
      setState(() {
        _notificationLogs.insert(0, logEntry); // Add to beginning of list
      });
    }
    
    await _saveNotificationLogs();
  }

  Future<void> _loadUsers() async {
    try {
      print("🔄 Starting to load users...");
      if (mounted) {
        setState(() {
          _isLoadingUsers = true;
        });
      }
      
      final odooService = OdooService();
      
      // Check if user is authenticated
      bool isAuthenticated = await odooService.checkAndLoadUserCredentials();
      if (!isAuthenticated) {
        throw Exception("User not authenticated. Please login first.");
      }
      
      final users = await odooService.fetchUsersFromOdoo();
      print("✅ Fetched ${users.length} users from Odoo");
      print("🔍 Users data: $users");
      
      if (users.isEmpty) {
        print("⚠️ No users found - this might be an authentication or permission issue");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("No users found. Please check your login credentials."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      
      if (mounted) {
        setState(() {
          _users = users;
          _isLoadingUsers = false;
        });
        print("✅ Loading users completed. _isLoadingUsers: $_isLoadingUsers, Users count: ${_users.length}");
      }
    } catch (e) {
      print("❌ Error loading users: $e");
      if (mounted) {
        setState(() {
          _isLoadingUsers = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to load users: $e"), 
            backgroundColor: Colors.red
          ),
        );
      }
    }
  }

  Future<void> _selectDueDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedDueDate = picked;
        _dueDateController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  // Show user selection popup
  void _showUserSelectionPopup(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select User'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: _isLoadingUsers
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      return ListTile(
                        title: Text(user['name'] ?? 'Unknown User'),
                        subtitle: Text(user['login'] ?? user['email'] ?? ''),
                        onTap: () {
                          setState(() {
                            _selectedUser = user['id'].toString();
                            _selectedUserName = user['name'];
                            _selectedUserEmail = user['login'] ?? user['email'] ?? '';
                          });
                          Navigator.of(context).pop();
                          // Rebuild the dialog to show selected user
                          setState(() {});
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (_isLoadingUsers)
              ElevatedButton(
                onPressed: _loadUsers,
                child: const Text('Reload Users'),
              ),
          ],
        );
      },
    );
  }

  // Register FCM token for current user
  Future<void> _registerFCMToken() async {
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        // Hantar ke Odoo (endpoint konsisten)
        final response = await http.post(
          Uri.parse('https://myerp.com.my/api/fcm/token'), // Pastikan endpoint ini yang digunakan semua tempat
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'user_id': widget.currentUserId,
            'token': fcmToken,
          }),
        );
        print("Register FCM token response: ${response.body}");
      }
    } catch (e) {
      print("❌ Error registering FCM token: $e");
    }
  }

  // Assume always true for Odoo push notification
  Future<bool> _checkUserFCMToken(String userEmail) async {
    return true;
  }

  Future<void> _sendPushNotification(String userEmail, String taskTitle) async {
    try {
      print("📤 Attempting to send push notification to: $userEmail");
      print("📋 Task title: $taskTitle");
      
      // Send push notification via Odoo server endpoint
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/fcm/send_task_notification'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_email': userEmail,
          'task_title': taskTitle,
          'assigned_by': widget.currentUserId,
        }),
      );
      
      print("📋 Response status: ${response.statusCode}");
      print("📋 Response body: ${response.body}");
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['result']?['success'] == true) {
          print("✅ Push notification sent successfully!");
          print("📋 Server response: $responseData");
          return;
        } else {
          print("❌ Server returned error: $responseData");
          throw Exception("Server error: ${responseData['error']?['message'] ?? 'Unknown error'}");
        }
      } else {
        print("❌ HTTP error: ${response.statusCode}");
        print("📋 Error response: ${response.body}");
        throw Exception("HTTP ${response.statusCode}: ${response.body}");
      }
      
    } catch (e) {
      print("❌ Error sending push notification: $e");
      throw e;
    }
  }

  // Test push notification function
  Future<void> _testPushNotification(String userEmail) async {
    try {
      print("🧪 Testing push notification for: $userEmail");
      
      final response = await http.post(
        Uri.parse('https://myerp.com.my/api/fcm/test_notification'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'user_email': userEmail,
        }),
      );
      
      print("📋 Test response status: ${response.statusCode}");
      print("📋 Test response body: ${response.body}");
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['result']?['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("✅ Test notification sent successfully!"),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("❌ Test notification failed: ${responseData['error']?['message'] ?? 'Unknown error'}"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ Test notification failed: HTTP ${response.statusCode}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print("❌ Error testing push notification: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Test notification error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _assignTask() async {
    if (_taskTitleController.text.isEmpty || 
        _projectController.text.isEmpty || 
        _selectedUser == null || 
        _selectedDueDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill in all fields."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isAssigningTask = true;
      });
    }

    try {
      // Get the assigned user's details
      final assignedUser = _users.firstWhere((user) => user['id'].toString() == _selectedUser);
      final assignedUserName = assignedUser['name'] ?? 'Unknown User';
      final assignedUserEmail = _selectedUserEmail ?? assignedUser['login'] ?? assignedUser['email'] ?? '';
      final assignedUserId = int.tryParse(_selectedUser ?? '') ?? 0;

      // Create task in Odoo
      final odooService = OdooService();
      final odooSuccess = await odooService.createProjectTask(
        title: _taskTitleController.text,
        project: _projectController.text, // You may need to resolve project name to project_id
        assignedUserId: assignedUserId,
        dueDate: _selectedDueDate!,
        description: null,
      );

      if (!odooSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to create task in Odoo. Please try again."),
            backgroundColor: Colors.red,
          ),
        );
        if (mounted) {
          setState(() {
            _isAssigningTask = false;
          });
        }
        return;
      }

      final task = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(), // Unique ID
        'title': _taskTitleController.text,
        'project': _projectController.text,
        'assignedTo': _selectedUser,
        'assignedToName': assignedUserName,
        'assignedToEmail': assignedUserEmail,
        'assignedBy': widget.currentUserId,
        'dueDate': _selectedDueDate!.toIso8601String(),
        'dueDateDisplay': DateFormat('dd/MM/yyyy').format(_selectedDueDate!),
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
        'createdAtDisplay': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      };

      // Save to local storage
      _localTasks.add(task);
      await _saveLocalTasks();

      // Check if assigned user has FCM token and send notification
      final hasFCMToken = await _checkUserFCMToken(assignedUserEmail);
      if (hasFCMToken) {
        await _sendPushNotification(assignedUserEmail, _taskTitleController.text);
        await _addNotificationLog(
          _taskTitleController.text,
          assignedUserName,
          assignedUserEmail,
          true,
          "Push notification sent successfully."
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Task assigned to $assignedUserName! Push notification sent."),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await _addNotificationLog(
          _taskTitleController.text,
          assignedUserName,
          assignedUserEmail,
          false,
          "Push notification failed. User not registered."
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Task assigned to $assignedUserName! (No push notification - user not registered)"),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // Clear form
      _taskTitleController.clear();
      _projectController.clear();
      _dueDateController.clear();
      if (mounted) {
        setState(() {
          _selectedUser = null;
          _selectedUserName = null;
          _selectedUserEmail = null;
          _selectedDueDate = null;
        });
      }

      Navigator.of(context).pop();
    } catch (e) {
      await _addNotificationLog(
        _taskTitleController.text,
        _selectedUserName ?? 'Unknown User',
        _selectedUserEmail ?? '',
        false,
        "Failed to assign task: $e"
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to assign task: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssigningTask = false;
        });
      }
    }
  }

  void _showAssignTaskDialog() {
    if (mounted) {
      setState(() {
        _selectedUser = null;
        _selectedUserName = null;
        _selectedUserEmail = null;
        _selectedDueDate = null;
        _dueDateController.clear();
      });
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Text(
                'Assign New Task',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Task Title',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _taskTitleController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        hintText: 'Enter task title',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Project',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _projectController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        hintText: 'Enter project name',
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Assign To',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _showUserSelectionPopup(context),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _selectedUserName != null ? Colors.green : Colors.grey,
                                  width: _selectedUserName != null ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                color: _selectedUserName != null ? Colors.green.shade50 : Colors.grey.shade200,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedUserName ?? 'Select a user',
                                          style: TextStyle(
                                            color: _selectedUserName != null ? Colors.black : Colors.grey,
                                            fontWeight: _selectedUserName != null ? FontWeight.bold : FontWeight.normal,
                                          ),
                                        ),
                                        if (_selectedUserName != null)
                                          Text(
                                            'User ID: $_selectedUser',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    _selectedUserName != null ? Icons.check_circle : Icons.arrow_drop_down,
                                    color: _selectedUserName != null ? Colors.green : Colors.grey,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_selectedUserName != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedUser = null;
                                _selectedUserName = null;
                                _selectedUserEmail = null;
                              });
                            },
                            icon: const Icon(Icons.clear, color: Colors.red),
                            tooltip: 'Clear selection',
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    const Text(
                      'Due Date',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _dueDateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                        hintText: 'Select due date',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_today),
                          onPressed: () => _selectDueDate(context),
                        ),
                      ),
                      onTap: () => _selectDueDate(context),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                ElevatedButton(
                  onPressed: _isAssigningTask ? null : _assignTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF282454),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isAssigningTask
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Assign Task',
                          style: TextStyle(color: Colors.white),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Build task card with notification details
  Widget _buildTaskCard(Map<String, dynamic> task, int index) {
    final notificationLog = _getNotificationLogForTask(task['title']);
    final isDarkMode = widget.isDarkMode;
    
    // Debug: Print task data
    print('🔍 Building task card for: ${task['title']}');
    print('🔍 Task data: $task');
    print('🔍 Task due date: ${task['dueDate']}');
    print('🔍 Task due date display: ${task['dueDateDisplay']}');
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: notificationLog != null 
            ? (notificationLog['success'] == true ? Colors.green : Colors.red).withOpacity(0.3)
            : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode 
              ? [
                  Colors.grey[900]!,
                  Colors.grey[800]!,
                ]
              : [
                  Colors.white,
                  Colors.grey[50]!,
                ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status and notification status
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['title'] ?? 'No Title',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Project: ${task['project'] ?? 'No Project'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      task['status']?.toUpperCase() ?? 'PENDING',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Task details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800]!.withOpacity(0.5) : Colors.grey[100]!.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.person, size: 16, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Assigned to: ${task['assignedToName'] ?? 'Unknown'}',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode ? Colors.white : Colors.black,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.calendar_today, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          'Due: ${task['dueDateDisplay'] ?? 'No Due Date'}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.white : Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 8),
                        Text(
                          'Created: ${task['createdAtDisplay'] ?? 'Unknown'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Countdown Timer
                    Row(
                      children: [
                        Icon(Icons.timer, size: 16, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildTaskCountdownTimer(task),
                        ),
                      ],
                    ),
                    // Debug: Always show countdown section
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.yellow.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Debug: Countdown section rendered - Task: ${task['title']}',
                        style: TextStyle(fontSize: 8, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Push notification details
              if (notificationLog != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: notificationLog['success'] == true 
                      ? Colors.green.withOpacity(0.1)
                      : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: notificationLog['success'] == true 
                        ? Colors.green.withOpacity(0.3)
                        : Colors.red.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        notificationLog['success'] == true ? Icons.notifications_active : Icons.notifications_off,
                        color: notificationLog['success'] == true ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notificationLog['success'] == true 
                                ? 'Push Notification Sent'
                                : 'Push Notification Failed',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: notificationLog['success'] == true ? Colors.green : Colors.red,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              notificationLog['message'] ?? 'No message',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Time: ${notificationLog['timestampDisplay'] ?? 'Unknown'}',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.grey.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.notifications_none, color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'No push notification sent',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Actions
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      _localTasks.removeAt(index);
                      await _saveLocalTasks();
                      if (mounted) {
                        setState(() {});
                      }
                    },
                    tooltip: 'Delete Task',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.isDarkMode ? Colors.black : const Color(0xFFE8E6F3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: widget.isDarkMode ? Colors.grey[900] : const Color(0xFF282454),
        title: Text(
          widget.selectedProject != null 
            ? "Tasks - ${widget.selectedProject}"
            : "My Tasks",
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        titleSpacing: 0,
        actions: [
          // Test button to add a task with due date
          IconButton(
            icon: const Icon(Icons.bug_report, color: Colors.white),
            onPressed: () async {
              // Create a test task with due date
              final testTask = {
                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                'title': 'Test Task with Countdown',
                'project': 'Test Project',
                'assignedTo': '1',
                'assignedToName': 'Test User',
                'assignedToEmail': 'test@example.com',
                'assignedBy': widget.currentUserId,
                'dueDate': DateTime.now().add(const Duration(days: 2)).toIso8601String(), // 2 days from now
                'dueDateDisplay': DateFormat('dd/MM/yyyy').format(DateTime.now().add(const Duration(days: 2))),
                'status': 'pending',
                'createdAt': DateTime.now().toIso8601String(),
                'createdAtDisplay': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
              };
              
              if (mounted) {
                setState(() {
                  _localTasks.add(testTask);
                });
              }
              
              await _saveLocalTasks();
              
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Test task added with countdown!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            tooltip: 'Add Test Task',
          ),
        ],
      ),
      body: _localTasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.task_alt,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.selectedProject != null
                        ? 'No tasks for ${widget.selectedProject} yet.\nTap the + button to assign a new task.'
                        : 'No tasks assigned yet.\nTap the + button to assign a new task.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _localTasks.length,
              itemBuilder: (context, index) {
                return _buildTaskCard(_localTasks[index], index);
              },
            ),
          floatingActionButton: FloatingActionButton(
      onPressed: _showAddOptionsDialog,
      backgroundColor: const Color(0xFF282454),
      child: const Icon(Icons.add, color: Colors.white),
      tooltip: 'Add Task',
    ),
    );
  }


  Future<void> _createMyTask() async {
  if (_taskTitleController.text.isEmpty ||
      _projectController.text.isEmpty ||
      _selectedDueDate == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Please fill in all fields."), backgroundColor: Colors.red),
    );
    return;
  }

  if (mounted) {
    setState(() => _isAssigningTask = true);
  }

  try {
    // Dapatkan info current user
    final me = _getCurrentUserFromList();
    final assignedUserName  = me?['name'] ?? 'Me';
    final assignedUserEmail = me?['login'] ?? me?['email'] ?? '';
    final assignedUserId    = int.tryParse(widget.currentUserId) ?? 0;

    // Cipta task dalam Odoo
    final odooService = OdooService();
    final odooSuccess = await odooService.createProjectTask(
      title: _taskTitleController.text,
      project: _projectController.text,
      assignedUserId: assignedUserId,
      dueDate: _selectedDueDate!,
      description: null,
    );

    if (!odooSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to create task in Odoo. Please try again."),
          backgroundColor: Colors.red,
        ),
      );
      if (mounted) setState(() => _isAssigningTask = false);
      return;
    }

    // Simpan ke local list (konsisten dengan struktur sedia ada)
    final task = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'title': _taskTitleController.text,
      'project': _projectController.text,
      'assignedTo': widget.currentUserId,
      'assignedToName': assignedUserName,
      'assignedToEmail': assignedUserEmail,
      'assignedBy': widget.currentUserId,
      'dueDate': _selectedDueDate!.toIso8601String(),
      'dueDateDisplay': DateFormat('dd/MM/yyyy').format(_selectedDueDate!),
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
      'createdAtDisplay': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
    };

    _localTasks.add(task);
    await _saveLocalTasks();

    // Hantar push noti (jika perlu)
    if (assignedUserEmail.isNotEmpty) {
      await _sendPushNotification(assignedUserEmail, _taskTitleController.text);
      await _addNotificationLog(
        _taskTitleController.text, assignedUserName, assignedUserEmail, true,
        "Push notification sent successfully.",
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("My Task created! Push notification sent."), backgroundColor: Colors.green),
      );
    } else {
      await _addNotificationLog(
        _taskTitleController.text, assignedUserName, assignedUserEmail, false,
        "Push notification skipped (no email).",
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("My Task created! (No push notification)"), backgroundColor: Colors.orange),
      );
    }

    // Clear & tutup dialog
    _taskTitleController.clear();
    _projectController.clear();
    _dueDateController.clear();

    if (mounted) {
      setState(() {
        _selectedDueDate = null;
        _isAssigningTask = false;
      });
    }
    Navigator.of(context).pop();
  } catch (e) {
    await _addNotificationLog(
      _taskTitleController.text,
      'Me',
      '',
      false,
      "Error creating my task: $e",
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
    );
    if (mounted) setState(() => _isAssigningTask = false);
  }
}


  void _showAddOptionsDialog() {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final isDark = widget.isDarkMode;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 48, height: 5,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(4),
              ),
            ),

            ListTile(
              leading: const Icon(Icons.person_add_alt_1),
              title: const Text('Assign New Task'),
              subtitle: const Text('Assign task to employee'),
              onTap: () {
                Navigator.pop(ctx);
                _showAssignTaskDialog(); // guna dialog sedia ada
              },
            ),
            const Divider(height: 0),

            ListTile(
              leading: const Icon(Icons.task_alt),
              title: const Text('My Task'),
              subtitle: const Text('Create My own task'),
              onTap: () {
                Navigator.pop(ctx);
                _showMyTaskDialog(); // dialog baru (langkah 2)
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
void _showMyTaskDialog() {
  // reset field ringkas
  if (mounted) {
    setState(() {
      _taskTitleController.clear();
      _projectController.clear();
      _selectedDueDate = null;
      _dueDateController.clear();
    });
  }

  // baca info current user (jika ada)
  final me = _getCurrentUserFromList();
  final myName  = me?['name'] ?? 'Me';
  final myEmail = me?['login'] ?? me?['email'] ?? '';

  showDialog(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Create My Task'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  const Text('Task Title', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _taskTitleController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      hintText: 'Enter task title',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Project
                  const Text('Project', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _projectController,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      hintText: 'Enter project name',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Assigned To (read-only “You”)
                  const Text('Assigned To', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade200,
                      border: Border.all(color: Colors.grey.shade400),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.account_circle, color: Colors.grey),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(myName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text(
                                myEmail.isNotEmpty ? myEmail : 'You',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.lock, color: Colors.grey), // read-only
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Due date
                  const Text('Due Date', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _dueDateController,
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 0)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          _selectedDueDate = picked;
                          _dueDateController.text = DateFormat('dd/MM/yyyy').format(picked);
                        });
                      }
                    },
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      hintText: 'Select due date',
                      suffixIcon: const Icon(Icons.calendar_today),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.red)),
              ),
              ElevatedButton(
                onPressed: _isAssigningTask ? null : _createMyTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF282454),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _isAssigningTask
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                      )
                    : const Text('Create My Task', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      );
    },
  );
}

}
