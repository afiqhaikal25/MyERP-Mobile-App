import 'package:flutter/material.dart';
import 'dart:async';
import '../odoo_service.dart';
import 'ticketdetails.dart';
import '../main.dart'; // Adjust the import path if necessary
import '../pushnoti/notification_service.dart'; 
import 'package:intl/intl.dart'; // Pastikan import package ini
import 'package:shared_preferences/shared_preferences.dart';
import '../task.dart';
import 'dart:convert'; // Untuk base64Decode
import 'totalfeedback.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import '../odoo_display.dart';


enum TicketFilter {
  latest,
  urgent,
  high,
  low,
  history
}

final GlobalKey<_TicketPageState> ticketPageKey = GlobalKey<_TicketPageState>(); // ✅ GlobalKey untuk akses state

Map<String, Timer> _untappedTicketTimers = {};
Set<int> _viewedTicketIds = {}; // Track yang user dah buka


class TicketPage extends StatefulWidget {
  final String email;
  final String password;

  const TicketPage({Key? key, required this.email, required this.password}) : super(key: key); // ✅ Gunakan key biasa

  @override
  State<TicketPage> createState() => _TicketPageState();
}


class _TicketPageState extends State<TicketPage> with TickerProviderStateMixin {
  final OdooService _odooService = OdooService();
  Future<List<dynamic>>? _tickets;
  bool _isLoading = false;
  TicketFilter _currentFilter = TicketFilter.latest;
  bool _isDarkMode = false; // For dark mode toggle
  final StreamController<void> _ticketStreamController = StreamController.broadcast();
  String? _userImageBase64;
  bool _isFirstTimeLogin = false; // Track first time login
  final TextEditingController _gmailController = TextEditingController(); // Gmail input controller

  Timer? _newTicketTimer;



@override
void initState() {
  super.initState();
  print("🚀 TicketPage initState() called");
  tzdata.initializeTimeZones(); // Initialize timezone database
  _loadDarkMode();
  print("📥 About to call _initialFetchTickets()");
  _tickets = _initialFetchTickets(); // Single call to fetch tickets
  print("📥 _initialFetchTickets() called");

  _odooService.fetchUserImage().then((image) {
    setState(() {
      _userImageBase64 = image;
    });
  });

  NotificationService.onNewTicket.listen((_) {
    manualRefresh();
    _startNewTicketTimer();
  });

  // Check if this is first time login and show Gmail form
  // _checkFirstTimeLogin(); // Removed as per edit hint
}


  // 🔥 Start timer selepas notifikasi diterima
  void _startNewTicketTimer() {
    _newTicketTimer?.cancel(); // Cancel any existing timer
    _newTicketTimer = Timer(const Duration(minutes: 30), () {
      print("⏳ 30 minutes passed. Checking if user has checked in for any tickets.");
      _checkIfTicketOpened();
    });
  }

    void _checkIfTicketOpened() {
    if (!mounted) return;

    // Get the current ticket from the list
    _tickets?.then((tickets) {
      if (tickets.isEmpty) return;

      // Check each ticket that hasn't been checked in
      for (var ticket in tickets) {
        if (!_isClosedTicket(ticket) && ticket['check_in'] == null) {
          // Send check-in reminder
          NotificationService().sendCheckInReminder(
            ticket['id'].toString(),
            ticket['ticket_number_display'] ?? ticket['name'] ?? "Unnamed Ticket",
          );
        }
      }
    });
  }

@override
void dispose() {
  _newTicketTimer?.cancel();
  _untappedTicketTimers.forEach((_, timer) => timer.cancel());
  _untappedTicketTimers.clear();
  _gmailController.dispose(); // Dispose Gmail controller
  super.dispose();
}


  bool _isValidFeedback(dynamic scale) {
  final value = double.tryParse(scale?.toString() ?? '');
  return value != null && value > 0;
}

Map<String, dynamic> _addHasFeedbackFlag(Map<String, dynamic> ticket) {
  final feedbackScales = [
    ticket['feedback_scale1'],
    ticket['feedback_scale2'],
    ticket['feedback_scale3'],
    ticket['feedback_scale4'],
    ticket['feedback_scale5'],
    ticket['feedback_scale6'],
  ];
  ticket['has_feedback'] = feedbackScales.every(_isValidFeedback);
  return ticket;
}

Future<List<dynamic>> _fetchTickets() async {
  try {
    final userId = await _odooService.authenticate(widget.email, widget.password);
    if (userId != null) {
      final rawTickets = await _odooService.fetchTickets(userId);
      print("✅ Fetched tickets: ${rawTickets.length}");

      final updatedTickets = rawTickets
          .map((ticket) => normalizeOdooRecord(
              Map<String, dynamic>.from(ticket as Map<String, dynamic>)))
          .map(_addHasFeedbackFlag)
          .toList();

      setState(() {
        _tickets = Future.value(updatedTickets); // ✅ BETUL
      });

      return updatedTickets;
    }
  } catch (e) {
    print("❌ Error fetching tickets: $e");
    // Don't return empty list on error - keep existing tickets if available
    if (_tickets != null) {
      try {
        final existingTickets = await _tickets;
        if (existingTickets != null && existingTickets.isNotEmpty) {
          print("⚠️ Error occurred, but keeping ${existingTickets.length} existing tickets");
          return existingTickets;
        }
      } catch (_) {
        // If we can't get existing tickets, return empty
      }
    }
  }

  return [];
}






Future<List<dynamic>> _initialFetchTickets() async {
  try {
    print("🔑 _initialFetchTickets() - Attempting to authenticate user...");
    print("🔑 Email: ${widget.email}");
    final userId = await _odooService.authenticate(widget.email, widget.password);
    print("🔑 Authentication result: $userId");

    if (userId == null || userId == 'false') {
      print("❌ Authentication failed: Invalid userId: $userId");
      return [];
    }

    print("✅ User authenticated successfully with ID: $userId");

    print("📥 Fetching tickets from server...");
    final rawTickets = await _odooService.fetchTickets(userId);
    print("📥 Raw tickets received: ${rawTickets.length} tickets");
    
    if (rawTickets.isEmpty) {
      print("ℹ️ No tickets found for user");
      return [];
    }

    print("✅ Successfully fetched ${rawTickets.length} tickets");

    // Process and return tickets
    final updatedTickets = rawTickets
        .map((ticket) => normalizeOdooRecord(
            Map<String, dynamic>.from(ticket as Map<String, dynamic>)))
        .map(_addHasFeedbackFlag)
        .toList();

    print("✅ Processed ${updatedTickets.length} tickets with feedback flags");
    return updatedTickets;

  } catch (e) {
    print("❌ Error during ticket fetch: $e");
    print("❌ Stack trace: ${StackTrace.current}");
    return [];
  }
}



Future<void> _loadDarkMode() async {
  final prefs = await SharedPreferences.getInstance();
  bool savedMode = prefs.getBool('isDarkMode') ?? false;
  print("🌓 Dark mode status from SharedPreferences: $savedMode"); // Debug log

  setState(() {
    _isDarkMode = savedMode;
  });
}

Future<void> _saveDarkMode(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('isDarkMode', value);
  print("💾 Dark mode saved: $value"); // Debug log
}


Future<void> manualRefresh() async {

  if (_isLoading) return;
  setState(() => _isLoading = true);
  try {
    final newTickets = await _fetchTickets();
    setState(() {
      _tickets = Future.value(newTickets); // ✅ PENTING!
    });
    print("✅ UI updated with new tickets.");

    

  } catch (e) {
    print("❌ Error refreshing tickets: $e");
  } finally {
    setState(() => _isLoading = false);
  }
}




List<dynamic> _filterTickets(List<dynamic> tickets) {
  print("Tickets before filtering: ${tickets.length}");
  
  // Separate closed and open tickets
  final closedTickets = tickets.where((ticket) => _isClosedTicket(ticket)).toList();
  final openTickets = tickets.where((ticket) => !_isClosedTicket(ticket)).toList();
  
  List<dynamic> filteredOpenTickets;
  switch (_currentFilter) {
    case TicketFilter.urgent:
      filteredOpenTickets = openTickets.where((ticket) =>
          ticket['priority']?.toString() == '3').toList();
      print("Urgent tickets count: ${filteredOpenTickets.length}");
      break;
    case TicketFilter.high:
      filteredOpenTickets = openTickets.where((ticket) =>
          ticket['priority']?.toString() == '2').toList();
      print("High priority tickets count: ${filteredOpenTickets.length}");
      break;
    case TicketFilter.low:
      filteredOpenTickets = openTickets.where((ticket) =>
          (ticket['priority']?.toString() == '0' ||
              ticket['priority']?.toString() == '1')).toList();
      print("Low priority tickets count: ${filteredOpenTickets.length}");
      break;
    case TicketFilter.history:
      print("Closed tickets count: ${closedTickets.length}");
      return closedTickets;
    case TicketFilter.latest:
    default:
      filteredOpenTickets = openTickets;
      print("Latest tickets count: ${filteredOpenTickets.length}");
      break;
  }
  
  // Always return filtered open tickets first, followed by closed tickets
  return [...filteredOpenTickets, ...closedTickets];
}

  bool _isClosedTicket(Map<String, dynamic> ticket) {
    final stageName = ticket['stage_name']?.toString().toLowerCase() ?? '';
    return stageName.contains('closed') ||
        stageName.contains('done') ||
        stageName.contains('completed');
  }



@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: _isDarkMode ? Colors.black : const Color(0xFFF1FAF5),
    body: Stack(
      children: [
        RefreshIndicator(
          onRefresh: manualRefresh,
          color: const Color(0xFF282454),
          child: StreamBuilder<void>(
            stream: _ticketStreamController.stream,
            builder: (context, snapshot) {
              return FutureBuilder<List<dynamic>>(
                future: _tickets,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            "Loading tickets...",
                            style: TextStyle(
                              color: _isDarkMode ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            "Error loading tickets:  {snapshot.error}",
                            style: TextStyle(
                              color: _isDarkMode ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: manualRefresh,
                            child: const Text("Try Again"),
                          ),
                        ],
                      ),
                    );
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.inbox,
                            size: 48,
                            color: _isDarkMode ? Colors.white70 : Colors.grey,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "No tickets available",
                            style: TextStyle(
                              color: _isDarkMode ? Colors.white : Colors.black,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  final tickets = snapshot.data!;
                  return ListView.builder(
                    itemCount: tickets.length,
                    itemBuilder: (context, index) {
                      return _buildTicketCard(tickets[index]);
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}



Widget _buildDrawer(BuildContext context) {
  return Drawer(
    child: Container(
      color: _isDarkMode ? Colors.black : Colors.white, // Dark background for dark mode
      child: Column(
        children: [
 UserAccountsDrawerHeader(
  decoration: BoxDecoration(
    color: _isDarkMode ? Colors.grey[850] : const Color(0xFF282454),
  ),
currentAccountPicture: _userImageBase64 != null
    ? Center(
        child: CircleAvatar(
          backgroundImage: MemoryImage(base64Decode(_userImageBase64!)),
        ),
      )
    : Center(
        child: CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(Icons.person, size: 40, color: const Color(0xFF282454)),
        ),
      ),

  accountName: const Text(
    'Hello', // Updated text
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Colors.white, // Always white
    ),
  ),
  accountEmail: Text(
    widget.email,
    style: const TextStyle(
      fontSize: 14,
      color: Colors.white, // Always white
    ),
  ),
),
            ListTile(
              leading: Icon(Icons.dark_mode, color: _isDarkMode ? Colors.white : Colors.grey[800]),
              title: Text(
                'Dark Mode',
                style: TextStyle(color: _isDarkMode ? Colors.white : Colors.grey[800]),
              ),
              trailing: Switch(
                value: _isDarkMode,
                onChanged: (value) {
                  setState(() {
                    _isDarkMode = value;
                  });
                    _saveDarkMode(value); // Simpan setting dark mode
                },
                activeColor: Colors.white,
                activeTrackColor: Colors.grey[600],
                inactiveThumbColor: const Color(0xFF282454),
                inactiveTrackColor: Colors.grey,
              ),
            ),
            ListTile(
              leading: Icon(Icons.settings, color: _isDarkMode ? Colors.white : Colors.grey[800]),
              title: Text(
                'Settings',
                style: TextStyle(color: _isDarkMode ? Colors.white : Colors.grey[800]),
              ),
              onTap: () {
                // _showGmailSettingsDialog(); // Removed as per edit hint
              },
            ),
            ListTile(
              leading: Icon(Icons.notifications, color: _isDarkMode ? Colors.white : Colors.grey[800]),
              title: Text(
                'Test Notification',
                style: TextStyle(color: _isDarkMode ? Colors.white : Colors.grey[800]),
              ),
              onTap: () {
                _testNotification();
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: _isDarkMode ? Colors.white : Colors.grey[800]),
              title: Text(
                'Logout',
                style: TextStyle(color: _isDarkMode ? Colors.white : Colors.grey[800]),
              ),
              onTap: () {
                _showLogoutConfirmationDialog(context);
            },
          ),
        ],
      ),
    ),
  );
}



Widget _buildTicketCard(Map<String, dynamic> ticket) {
  bool isHovered = false;

  return StatefulBuilder(
    builder: (context, setState) {
      return GestureDetector(
        onTap: () {
          _onTicketTap(ticket);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            transform: Matrix4.identity()
              ..translate(0.0, isHovered ? -2.0 : 0.0),
            child: Card(
              elevation: isHovered ? 8 : 4,
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
              color: _isDarkMode ? Colors.black : const Color(0xFFF4FBF7),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isHovered
                      ? const Color(0xFF282454).withOpacity(0.5)
                      : Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: isHovered
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            _isDarkMode ? Colors.black : const Color(0xFFF4FBF7),
                            const Color(0xFF282454).withOpacity(0.1),
                          ],
                        )
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      // Header section with divider
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      odooStr(ticket['ticket_number_display'] ?? ticket['name'], "Unnamed Ticket"),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: _isDarkMode ? Colors.white : const Color(0xFF282454),
                                        letterSpacing: 0.3,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(vertical: 2),
                                      child: Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF19543E).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Icon(
                                              Icons.calendar_today_outlined,
                                              size: 12,
                                              color: Color(0xFF6EE7B7), // Lighter green
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDate(ticket['create_date']),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _isDarkMode ? Colors.white : const Color(0xFF19543E),
                                              letterSpacing: 0.2,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: _buildStatusBadge(ticket['stage_name']),
                                ),
                                const SizedBox(width: 4),
                                _buildPriorityBadge(ticket['priority']),
                              ],
                            ),

                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 1,
                            color: Colors.grey.withOpacity(0.1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      
                      // Info section with background
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isDarkMode ? Colors.grey[900] : const Color(0xFFEAF7F0),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.1),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              Icons.person,
                              'Customer - ${odooStr(ticket['partner_name'], 'No Customer')}',
                              _isDarkMode ? Colors.white : const Color(0xFF282454),
                            ),
                            const SizedBox(height: 4),
                            _buildInfoRow(
                              Icons.location_on,
                              'Address - ${odooStr(ticket['address'], 'No Address')}',
                              _isDarkMode ? Colors.white : const Color(0xFF282454),
                            ),
                            const SizedBox(height: 4),
                            _buildInfoRow(
                              Icons.category_outlined,
                              'Category - ${odooStr(ticket['category_name'], 'Uncategorized')}',
                              _isDarkMode ? Colors.white : const Color(0xFF282454),
                            ),
                            const SizedBox(height: 4),
                            _buildInfoRow(
                              Icons.build_outlined,
                              'Problem - ${odooStr(ticket['prob_name'], 'No Problem Specified')}',
                              _isDarkMode ? Colors.white : const Color(0xFF282454),
                            ),
                          ],
                        ),
                      ),

                      // Add action button at the bottom
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String text, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: color,
              letterSpacing: 0.2,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String? status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _getStageColor(status),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: _getStageColor(status).withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        _getStageLabel(status ?? 'Unknown'),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(dynamic priority) {
    final Color priorityColor = _getPriorityColor(priority);
    final String label = _getPriorityLabel(priority);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: priorityColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: priorityColor.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  IconData _getPriorityIcon(dynamic priority) {
    switch (priority?.toString()) {
      case '3':
        return Icons.priority_high;      // Exclamation mark for Urgent (Red)
      case '2':
        return Icons.warning;            // Warning triangle for High (Orange)
      case '1':
        return Icons.info;               // Info icon for Medium (Blue)
      default:
        return Icons.arrow_downward;     // Down arrow for Low (Green)
    }
  }

  Color _getPriorityColor(dynamic priority) {
    switch(priority?.toString()) {
      case '3': // Urgent
        return const Color(0xFF800000); // Maroon for urgent
      case '2': // High
        return const Color(0xFFFF6B00); // Orange for high
      case '1': // Normal
      case '0': // Low
        return const Color(0xFF2E7D32); // Green for low/normal
      default:
        return Colors.grey;
    }
  }

  String _getPriorityLabel(dynamic priority) {
    switch(priority?.toString()) {
      case '3':
        return 'URGENT';
      case '2':
        return 'HIGH';
      case '1':
      case '0':
        return 'LOW';
      default:
        return 'NORMAL';
    }
  }


String _formatDate(String? dateStr) {
  if (dateStr == null) return 'Unknown';
  try {
    final utcDate = DateTime.parse(dateStr).toUtc();
    final klTz = tz.getLocation('Asia/Kuala_Lumpur');
    final klDate = tz.TZDateTime.from(utcDate, klTz);
    return DateFormat('dd/MM/yyyy  •  hh:mm a').format(klDate);
  } catch (e) {
    print("❌ Error formatting date: $e");
    return dateStr;
  }
}




  String _getStageLabel(String stage) {
    if (stage.toLowerCase().contains('staff closed')) {
      return 'Closed';
    }
    return stage;
  }

  Color _getStageColor(String? stage) {
    if (stage == null) return Colors.grey;
    
    if (stage.toLowerCase().contains('closed')) {
      return Colors.grey;
    } else if (stage.toLowerCase().contains('open')) {
      return const Color(0xFF46BBFE); // Changed from Colors.green to #46bbfe
    } else {
      return const Color(0xFF282454); // Default to theme color for other stages
    }
  }
  
void _showLogoutConfirmationDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF282454),
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginPage()), // Updated to LoginPage
                (Route<dynamic> route) => false, // Clear all routes in the stack
              );
            },
          ),
        ],
      );
    },
  );
}



void _onTicketTap(Map<String, dynamic> ticket) async {
  final ticketId = ticket['id'];
  _viewedTicketIds.add(ticketId);

  // Cancel timer jika ada
  if (_untappedTicketTimers.containsKey(ticketId)) {
    _untappedTicketTimers[ticketId]?.cancel();
    _untappedTicketTimers.remove(ticketId);
  }

  final stageName = (ticket['stage_name'] ?? '').toString().toLowerCase();
  final feedbackScales = [
    ticket['feedback_scale1'],
    ticket['feedback_scale2'],
    ticket['feedback_scale3'],
    ticket['feedback_scale4'],
    ticket['feedback_scale5'],
    ticket['feedback_scale6'],
  ];


  bool isClosed = stageName.contains('closed') || stageName.contains('done');
  final hasFeedback = feedbackScales.every((scale) {
    final value = double.tryParse(scale?.toString() ?? '');
    return value != null && value > 0;
  });

  if (isClosed) {
    // ✅ Delay untuk pastikan data terkini dah rebuild
    await Future.delayed(const Duration(milliseconds: 200));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What would you like to do?'),
        content: const Text('This ticket is closed and feedback has been submitted.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Tutup popup
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TotalFeedbackScreen(ticketId: ticket['id']),
                ),
              );
            },
            child: const Text('View Feedback Summary'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Tutup popup
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TicketDetailsPage(
                    ticket: ticket,
                    odooService: _odooService,
                    isDarkMode: _isDarkMode,
                    onTicketUpdated: manualRefresh,
                  ),
                ),
              );
            },
            child: const Text('View Ticket Details'),
          ),
        ],
      ),
    );
  } else {
    // 👇 Navigate terus ke TicketDetailsPage
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TicketDetailsPage(
          ticket: ticket,
          odooService: _odooService,
          isDarkMode: _isDarkMode,
          onTicketUpdated: manualRefresh,
        ),
      ),
    );
  }
}

// Remove all Gmail notification related code, popups, settings, and local storage.
// Only use the login email (Sigma email) for push notification.
// Remove _gmailController, _checkFirstTimeLogin, _showGmailFormDialog, _submitGmailForm, _isValidGmail, _markGmailFormAsShown, _showGmailSettingsDialog, _hasGmailForNotifications, _getCurrentGmail, and all references to them.
// Remove all UI for Gmail setup in drawer/settings.
// Remove NotificationService.updateGmailForNotifications and related calls.
// Remove any code that uses x_notification_email for notification redirection.

void _testNotification() async {
  try {
    // Test local notification first
    await NotificationService().sendLocalNotification(
      title: "Ujian Notifikasi Tempatan",
      body: "Ini adalah ujian notifikasi tempatan pada ${DateTime.now().toString()}",
    );
    
    // Test FCM token
    String? fcmToken = await FirebaseMessaging.instance.getToken();
    print("🔥 Current FCM Token: $fcmToken");
    
    // Get current Gmail
    // String? currentGmail = await _getCurrentGmail(); // Removed as per edit hint
    
    // Show info dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ujian Notifikasi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('✅ Notifikasi tempatan dihantar!'),
            const SizedBox(height: 16),
            Text('FCM Token: ${fcmToken ?? "Tidak tersedia"}'),
            const SizedBox(height: 8),
            // Text('Gmail: ${currentGmail ?? "Belum ditetapkan"}'), // Removed as per edit hint
            const SizedBox(height: 16),
            const Text('ℹ️ Nota: Ujian push notification dimatikan - perlu server key yang betul'),
            const SizedBox(height: 8),
            const Text('💡 Notifikasi tempatan berfungsi dengan sempurna!'),
            const SizedBox(height: 8),
            // const Text('📧 Gmail akan digunakan untuk push notification'), // Removed as per edit hint
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    
  } catch (e) {
    print('❌ Error testing notification: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ralat: $e')),
    );
  }
}
}