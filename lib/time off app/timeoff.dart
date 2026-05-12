import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../home.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../odoo_service.dart';
import 'dart:convert';
import '../pushnoti/notification_service.dart'; // Add import for NotificationService
import 'dart:async'; // Add import for StreamSubscription

class TimeOffPage extends StatefulWidget {
  const TimeOffPage({Key? key}) : super(key: key);

  @override
  State<TimeOffPage> createState() => _TimeOffPageState();
}

class _TimeOffPageState extends State<TimeOffPage> {
  late final int _currentYear;
  late final int _currentMonth;
  int _startYear = 0;
  int _displayMonth = 0; // Track the currently displayed month
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  // Tambah state untuk filter jenis cuti
  Set<String> selectedLeaveTypes = {'unpaid', 'sick', 'annual'};
  Map<int, List<dynamic>> mapLeaves = {};
  List<dynamic> allLeaves = [];
  String? _userId;
  StreamSubscription? _notificationSubscription; // Add subscription for notifications

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentYear = now.year;
    _currentMonth = now.month;
    // Hanya tahun semasa sahaja
    _startYear = _currentYear;
    _displayMonth = _currentMonth; // Initialize display month to current month
    
    // Listen for notifications to refresh data
    _notificationSubscription = NotificationService.onNewTicket.listen((_) {
      print("📩 Time Off notification received, refreshing data...");
      getLeavesForAllMonths();
    });
    
    // Load data for current month
    getLeavesForAllMonths().then((_) {
      print('DEBUG: Data loaded for current month: $_currentMonth');
    });
  }



  void _showAddTimeOffRequestDialog() async {
    final result = await showDialog(
      context: context,
      builder: (context) => TimeOffRequestDialog(
        onLeaveCreated: () async {
          // Refresh data IMMEDIATELY after leave is created
          print('DEBUG: Main page refresh triggered IMMEDIATELY');
          await getLeavesForAllMonths();
          
          // Force rebuild multiple times to ensure UI updates
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 100));
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 100));
          setState(() {});
          print('DEBUG: Main page state forced to rebuild multiple times');
        },
      ),
    );
    if (result == true) {
      print('DEBUG: Dialog closed with success, refreshing data IMMEDIATELY');
      // Refresh immediately without delay
      await getLeavesForAllMonths();
      
      // Force rebuild multiple times to ensure UI updates
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 100));
      setState(() {});
      print('DEBUG: Main page state forced to rebuild multiple times after dialog close');
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel(); // Cancel notification subscription
    super.dispose();
  }

  Future<void> getLeavesForAllMonths() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id');
    final currentYear = _startYear; // Use the current year from state
    final displayMonth = _displayMonth; // Use the display month

    Map<int, List<dynamic>> tempMap = {};
    List<dynamic> all = [];

    // Only fetch data for the display month
    final fetched = await OdooService().fetchLeavesWithUserId(_userId!, currentYear, displayMonth);
    print('✅ Fetched ${fetched.length} leave(s) for month: $displayMonth in year: $currentYear');

    if (fetched.isNotEmpty) {
      tempMap[displayMonth] = fetched;
      all.addAll(fetched);
    }

    setState(() {
      mapLeaves = tempMap;
      allLeaves = all;
    });
    print('DEBUG: mapLeaves after save: $mapLeaves');
  }

  List<Widget> buildLeaveListForMonth(int month) {
    final leaves = mapLeaves[month] ?? [];
    if (leaves.isEmpty) {
      return [Text('Tiada cuti bulan $month')];
    }
    return leaves.map((leave) {
      return ListTile(
        title: Text('${leave['leave_type']}'),
        subtitle: Text('${leave['date_from']} hingga ${leave['date_to']}'),
        trailing: Text(leave['state']),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // Tidak perlu scroll di build lagi
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        backgroundColor: isDarkMode ? Colors.black : const Color(0xFF282454),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.grid_view, color: Colors.white),
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            final email = prefs.getString('email') ?? '';
            final password = prefs.getString('password') ?? '';
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => HomePage(email: email, password: password)),
            );
          },
        ),
        title: Text('Time Off', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            tooltip: 'Leave Status Info',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const LeaveStatusInfoDialog(),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: Container(
            color: isDarkMode ? Colors.black : Colors.white,
            width: 320,
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<SharedPreferences>(
                    future: SharedPreferences.getInstance(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return SizedBox(height: 48);
                      final prefs = snapshot.data!;
                      final userEmail = prefs.getString('user_email') ?? '';
                      final userImageBase64 = prefs.getString('user_image_base64') ?? '';
                      final allLeavesLocal = allLeaves;
                      final userIdLocal = _userId;
                final userEmployeeId = prefs.getString('employee_id');
                // Fallback: try user_id if employee_id not present
                final userId = userEmployeeId ?? prefs.getString('user_id');

                // Helper filter function
                bool isUserLeave(Map leave) {
                  if (userId == null) return true; // fallback: show all
                  final leaveEmpId = int.tryParse(leave['employee_id'].toString());
                  final userIdInt = int.tryParse(userId.toString());
                  return leaveEmpId == userIdInt;
                }

                print('userId: $userId (${userId.runtimeType})');
                allLeaves.forEach((leave) {
                  print('leaveEmpId: ${leave['employee_id']} (${leave['employee_id'].runtimeType})');
                });
                final toApprove = allLeaves.where((leave) => leave['state'] == 'confirm' && isUserLeave(leave)).toList();
                final validated = allLeaves.where((leave) => (leave['state'] == 'validate' || leave['state'] == 'validate1') && isUserLeave(leave)).toList();
                final refused = allLeaves.where((leave) => leave['state'] == 'refuse' && isUserLeave(leave)).toList();
                print('TO APPROVE: $toApprove');
                print('VALIDATED: $validated');
                print('REFUSED: $refused');

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- USER IMAGE & EMAIL ROW ---
                      Row(
                        children: [
                          if (userImageBase64.isNotEmpty)
                            CircleAvatar(
                              radius: 24,
                              backgroundImage: MemoryImage(base64Decode(userImageBase64)),
                              backgroundColor: Colors.grey[300],
                            )
                          else
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.grey[300],
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              userEmail,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                  ),
                  const SizedBox(height: 24),
                      // --- LEGEND (now at the top) ---
                  Text(
                        'Leave Type',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.black : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                      // ML label
                  _buildLegendItem(
                    context,
                    isDarkMode,
                    Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                            color: Colors.blue[700],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[700]!),
                      ),
                          child: Text('ML', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                        'Medical Leave',
                  ),
                      const SizedBox(height: 8),
                      // UPL label
                  _buildLegendItem(
                    context,
                    isDarkMode,
                    Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                            color: Colors.purple[700],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple[700]!),
                          ),
                          child: Text('UPL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        'Unpaid Leave',
                      ),
                      const SizedBox(height: 8),
                      // Annual Leave label (brown)
                      _buildLegendItem(
                        context,
                        isDarkMode,
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.brown[700],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.brown[700]!),
                          ),
                          child: Text('Annual', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        'Annual Leave',
                      ),
                      const SizedBox(height: 8),
                      // Today label
                      _buildLegendItem(
                        context,
                        isDarkMode,
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red[400],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red[400]!),
                          ),
                          child: Text('Today', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        'Today',
                      ),
                      const SizedBox(height: 24),
                      // --- LEAVE STATUS (now after legend) ---
                      Text('Leave Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 30),
                      // Validated (green)
                  _buildLegendItem(
                    context,
                    isDarkMode,
                    Container(
                          width: 16,
                          height: 16,
                      decoration: BoxDecoration(
                            color: Colors.green[100],
                        borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.green[700]!),
                          ),
                        ),
                        'Validated',
                      ),
                      const SizedBox(height: 8),
                      // To Approve (orange)
                      _buildLegendItem(
                        context,
                        isDarkMode,
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.orange[100],
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.orange[700]!),
                          ),
                        ),
                        'To Approve',
                      ),
                      const SizedBox(height: 8),
                      // Today (red)
                      _buildLegendItem(
                        context,
                        isDarkMode,
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.red[400],
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: Colors.red[400]!),
                          ),
                        ),
                        'Today',
                      ),
                      const SizedBox(height: 24),
                      // --- SENARAI LEAVE STATUS ---
                      // Text('To Approve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      // ...allLeaves.where((leave) => leave['state'] == 'confirm' && isUserLeave(leave)).expand<Widget>((leave) {
                      //   final dateFrom = leave['date_from'] != null ? DateTime.tryParse(leave['date_from']) : null;
                      //   final dateTo = leave['date_to'] != null ? DateTime.tryParse(leave['date_to']) : null;
                      //   final leaveType = (leave['leave_type'] ?? '').toString().toLowerCase();
                      //   String typeLabel = '';
                      //   String typeName = '';
                      //   Color? typeColor;
                      //   if (leaveType.contains('sick')) {
                      //     typeLabel = 'ML';
                      //     typeName = 'Medical Leave';
                      //     typeColor = Colors.blue[700];
                      //   } else if (leaveType.contains('unpaid')) {
                      //     typeLabel = 'UPL';
                      //     typeName = 'Unpaid Leave';
                      //     typeColor = Colors.purple[700];
                      //   } else if (leaveType.contains('annual')) {
                      //     typeLabel = 'Annual';
                      //     typeName = 'Annual Leave';
                      //     typeColor = Colors.brown[700];
                      //   } else {
                      //     typeLabel = leaveType.isNotEmpty ? leaveType[0].toUpperCase() + leaveType.substring(1) : '';
                      //     typeName = leaveType;
                      //     typeColor = Colors.grey[700];
                      //   }
                      //   if (dateFrom == null || dateTo == null) return [];
                      //   final days = dateTo.difference(dateFrom).inDays;
                      //   return List.generate(days + 1, (i) {
                      //     final date = dateFrom.add(Duration(days: i));
                      //     return Padding(
                      //       padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
                      //       child: Row(
                      //         children: [
                      //           Icon(Icons.pending_actions, color: Colors.orange[700], size: 16),
                      //           const SizedBox(width: 8),
                      //           Text(DateFormat('dd/MM/yyyy').format(date), style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontSize: 13)),
                      //           const SizedBox(width: 8),
                      //           Container(
                      //             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      //             decoration: BoxDecoration(
                      //               color: typeColor?.withOpacity(0.8),
                      //               borderRadius: BorderRadius.circular(8),
                      //               border: Border.all(color: typeColor ?? Colors.grey),
                      //             ),
                      //             child: Text(typeLabel, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      //           ),
                      //           const SizedBox(width: 4),
                      //           Text('($typeName)', style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white70 : Colors.black54)),
                      //         ],
                      //       ),
                      //     );
                      //   });
                      // }).toList(),
                      // const SizedBox(height: 16),
                      // Text('Validated', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      // ...allLeaves.where((leave) => (leave['state'] == 'validate' || leave['state'] == 'validate1') && isUserLeave(leave)).expand<Widget>((leave) {
                      //   final dateFrom = leave['date_from'] != null ? DateTime.tryParse(leave['date_from']) : null;
                      //   final dateTo = leave['date_to'] != null ? DateTime.tryParse(leave['date_to']) : null;
                      //   final leaveType = (leave['leave_type'] ?? '').toString().toLowerCase();
                      //   String typeLabel = '';
                      //   String typeName = '';
                      //   Color? typeColor;
                      //   if (leaveType.contains('sick')) {
                      //     typeLabel = 'ML';
                      //     typeName = 'Medical Leave';
                      //     typeColor = Colors.blue[700];
                      //   } else if (leaveType.contains('unpaid')) {
                      //     typeLabel = 'UPL';
                      //     typeName = 'Unpaid Leave';
                      //     typeColor = Colors.purple[700];
                      //   } else if (leaveType.contains('annual')) {
                      //     typeLabel = 'Annual';
                      //     typeName = 'Annual Leave';
                      //     typeColor = Colors.brown[700];
                      //   } else {
                      //     typeLabel = leaveType.isNotEmpty ? leaveType[0].toUpperCase() + leaveType.substring(1) : '';
                      //     typeName = leaveType;
                      //     typeColor = Colors.grey[700];
                      //   }
                      //   if (dateFrom == null || dateTo == null) return [];
                      //   final days = dateTo.difference(dateFrom).inDays;
                      //   return List.generate(days + 1, (i) {
                      //     final date = dateFrom.add(Duration(days: i));
                      //     return Padding(
                      //       padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
                      //       child: Row(
                      //         children: [
                      //           Icon(Icons.verified, color: Colors.green[700], size: 16),
                      //           const SizedBox(width: 8),
                      //           Text(DateFormat('dd/MM/yyyy').format(date), style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontSize: 13)),
                      //           const SizedBox(width: 8),
                      //           Container(
                      //             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      //             decoration: BoxDecoration(
                      //               color: typeColor?.withOpacity(0.8),
                      //               borderRadius: BorderRadius.circular(8),
                      //               border: Border.all(color: typeColor ?? Colors.grey),
                      //             ),
                      //             child: Text(typeLabel, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      //           ),
                      //           const SizedBox(width: 4),
                      //           Text('($typeName)', style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white70 : Colors.black54)),
                      //         ],
                      //       ),
                      //     );
                      //   });
                      // }).toList(),
                      // const SizedBox(height: 16),
                      // Text('Refused', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      // ...allLeaves.where((leave) => leave['state'] == 'refuse' && isUserLeave(leave)).expand<Widget>((leave) {
                      //   final dateFrom = leave['date_from'] != null ? DateTime.tryParse(leave['date_from']) : null;
                      //   final dateTo = leave['date_to'] != null ? DateTime.tryParse(leave['date_to']) : null;
                      //   final leaveType = (leave['leave_type'] ?? '').toString().toLowerCase();
                      //   String typeLabel = '';
                      //   String typeName = '';
                      //   Color? typeColor;
                      //   if (leaveType.contains('sick')) {
                      //     typeLabel = 'ML';
                      //     typeName = 'Medical Leave';
                      //     typeColor = Colors.blue[700];
                      //   } else if (leaveType.contains('unpaid')) {
                      //     typeLabel = 'UPL';
                      //     typeName = 'Unpaid Leave';
                      //     typeColor = Colors.purple[700];
                      //   } else if (leaveType.contains('annual')) {
                      //     typeLabel = 'Annual';
                      //     typeName = 'Annual Leave';
                      //     typeColor = Colors.brown[700];
                      //   } else {
                      //     typeLabel = leaveType.isNotEmpty ? leaveType[0].toUpperCase() + leaveType.substring(1) : '';
                      //     typeName = leaveType;
                      //     typeColor = Colors.grey[700];
                      //   }
                      //   if (dateFrom == null || dateTo == null) return [];
                      //   final days = dateTo.difference(dateFrom).inDays;
                      //   return List.generate(days + 1, (i) {
                      //     final date = dateFrom.add(Duration(days: i));
                      //     return Padding(
                      //       padding: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 8.0),
                      //       child: Row(
                      //         children: [
                      //           Icon(Icons.cancel, color: Colors.red[700], size: 16),
                      //           const SizedBox(width: 8),
                      //           Text(DateFormat('dd/MM/yyyy').format(date), style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontSize: 13)),
                      //           const SizedBox(width: 8),
                      //           Container(
                      //             padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      //             decoration: BoxDecoration(
                      //               color: typeColor?.withOpacity(0.8),
                      //               borderRadius: BorderRadius.circular(8),
                      //               border: Border.all(color: typeColor ?? Colors.grey),
                      //             ),
                      //             child: Text(typeLabel, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                      //           ),
                      //           const SizedBox(width: 4),
                      //           Text('($typeName)', style: TextStyle(fontSize: 11, color: isDarkMode ? Colors.white70 : Colors.black54)),
                      //         ],
                      //       ),
                      //     );
                      //   });
                      // }).toList(),
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.assignment_turned_in),
                          label: const Text('Approval'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[800],
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () async {
                            showDialog(
                              context: context,
                              builder: (context) => ApprovalDialog(allLeaves: allLeavesLocal, userId: userIdLocal),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Time Off Request'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF282454),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await Future.delayed(const Duration(milliseconds: 300));
                        _showAddTimeOffRequestDialog();
                      },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
                );
              },
            ),
          ),
        ),
      ),
      endDrawerEnableOpenDragGesture: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              isDarkMode ? 'images/woodb.png' : 'images/wood.png',
              fit: BoxFit.cover,
            ),
          ),
          Column(
            children: [
              const SizedBox(height: 0),
              // Calendar Content - Single Month Display
              Expanded(
                child: GestureDetector(
                  onHorizontalDragEnd: (details) {
                    if (details.primaryVelocity != null) {
                      if (details.primaryVelocity! < 0) {
                        // Swipe left - next month
                        setState(() {
                          if (_displayMonth == 12) {
                            // If December, go to January of next year
                            _displayMonth = 1;
                            _startYear++;
                          } else {
                            // Go to next month
                            _displayMonth++;
                          }
                        });
                        getLeavesForAllMonths();
                      } else if (details.primaryVelocity! > 0) {
                        // Swipe right - previous month
                        setState(() {
                          if (_displayMonth == 1) {
                            // If January, go to December of previous year
                            _displayMonth = 12;
                            _startYear--;
                          } else {
                            // Go to previous month
                            _displayMonth--;
                          }
                        });
                        getLeavesForAllMonths();
                      }
                    }
                  },
                  child: CalendarMonthWidget(
                    key: ValueKey('${_startYear}_${_displayMonth}_${mapLeaves.length}'),
                    year: _startYear,
                    month: _displayMonth,
                    isDarkMode: isDarkMode,
                    selectedLeaveTypes: selectedLeaveTypes,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Tambah fungsi legend item untuk drawer
  Widget _buildLegendItem(BuildContext context, bool isDarkMode, Widget icon, String label) {
    // Center text for ML and UPL only
    bool isShortLabel = false;
    if (icon is Container && icon.child is Text) {
      final text = (icon.child as Text).data ?? '';
      if (text == 'ML' || text == 'UPL') {
        isShortLabel = true;
      }
    }
    return Row(
      children: [
        SizedBox(
          width: 48, // Tetapkan lebar tetap untuk label (boleh adjust ikut kesesuaian)
          child: isShortLabel
              ? Center(child: icon)
              : icon,
        ),
        const SizedBox(width: 16),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }



}

class CalendarMonthWidget extends StatefulWidget {
  final int year;
  final int month;
  final bool isDarkMode;
  final Set<String> selectedLeaveTypes;
  const CalendarMonthWidget({Key? key, required this.year, required this.month, required this.isDarkMode, required this.selectedLeaveTypes}) : super(key: key);

  @override
  State<CalendarMonthWidget> createState() => _CalendarMonthWidgetState();
}

class _CalendarMonthWidgetState extends State<CalendarMonthWidget> {
  Map<DateTime, Map<String, dynamic>> leaveMap = {};

  @override
  void initState() {
    super.initState();
    fetchLeaveData();
  }

  Future<void> fetchLeaveData() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    print('🔍 DEBUG: Retrieved userId from SharedPreferences: $userId');
    print('🔍 DEBUG: userId type: ${userId.runtimeType}');
    print('USER_ID (login): $userId, YEAR: ${widget.year}, MONTH: ${widget.month}');
    
    // Debug: Check all stored preferences
    final allKeys = prefs.getKeys();
    print('🔍 DEBUG: All stored preferences: $allKeys');
    for (String key in allKeys) {
      final value = prefs.get(key);
      print('🔍 DEBUG: $key = $value');
    }
    
    // QUICK DEBUG: Show current user info
    print('🔍 DEBUG: Current user info:');
    print('🔍 DEBUG: - User ID: $userId');
    print('🔍 DEBUG: - Email: ${prefs.getString('email')}');
    print('🔍 DEBUG: - Year: ${widget.year}, Month: ${widget.month}');
    
    // Check employee data for this user
    try {
      final employeeData = await OdooService().checkEmployeeData(int.tryParse(userId ?? '0') ?? 0);
      print('🔍 DEBUG: Employee data for user $userId: $employeeData');
      
      // Extract employee_id from response
      if (employeeData['result'] != null && employeeData['result']['employee'] != null) {
        final employee = employeeData['result']['employee'];
        final employeeId = employee['id'];
        print('🔍 DEBUG: Employee ID for user $userId: $employeeId');
      }
    } catch (e) {
      print('❌ DEBUG: Error checking employee data: $e');
    }
    
    if (userId == null || userId.isEmpty) {
      print('❌ ERROR: user_id is null or empty in fetchLeaveData');
      return;
    }
    
    // REAL FIX: Use actual API call for all users
    print('🔍 DEBUG: Using user ID for API call: $userId');
    final leaves = await OdooService().fetchLeavesWithUserId(userId, widget.year, widget.month);
    print('LEAVES: $leaves');
    print('🔍 DEBUG: Fetched ${leaves.length} leaves for user $userId');
    
    // Debug: Show each leave
    for (var leave in leaves) {
      print('🔍 DEBUG: Leave ID: ${leave['id']}, Employee: ${leave['employee_name']}, Type: ${leave['leave_type']}, State: ${leave['state']}');
    }
    
    // Temporary: Check if this is HAMKA and show warning if data looks wrong
    if (userId == '3' || userId == '4') { // Assuming HAMKA's user ID
      print('⚠️ DEBUG: This appears to be HAMKA (user_id: $userId)');
      if (leaves.isNotEmpty) {
        print('⚠️ DEBUG: HAMKA has ${leaves.length} leaves but should have 0!');
        print('⚠️ DEBUG: This suggests data filtering is not working correctly');
      }
    }
    
    Map<DateTime, Map<String, dynamic>> map = {};
    for (var leave in leaves) {
      // Filter ikut selectedLeaveTypes
      final leaveType = leave['leave_type']?.toLowerCase() ?? '';
      print('LEAVE TYPE: $leaveType');
      print('LEAVE DESCRIPTION: ${leave['description']}');
      // Check if leaveType string contains any of the keywords in selectedLeaveTypes
      if (!widget.selectedLeaveTypes.any((selectedType) => leaveType.contains(selectedType))) continue;

      DateTime from = DateTime.parse(leave['date_from']);
      DateTime to = DateTime.parse(leave['date_to']);
      from = DateTime(from.year, from.month, from.day);
      to = DateTime(to.year, to.month, to.day);
      for (var d = from; !d.isAfter(to); d = d.add(Duration(days: 1))) {
        map[d] = {
          'type': leave['leave_type'],
          'state': leave['state'],
          'date_from': leave['date_from'],
          'date_to': leave['date_to'],
          'description': leave['description'] ?? '',
          'employee_id': leave['employee_id'],
          'id': leave['id'],
        };
      }
    }
    print('DEBUG: leaveMap in CalendarMonthWidget: $map');
    print('DEBUG: leaveMap size after fetch: ${map.length}');
    print('DEBUG: Sample leave data: ${map.isNotEmpty ? map.values.first : 'No data'}');
    if (!mounted) return;
    setState(() {
      leaveMap = map;
    });
    print('DEBUG: State updated with new leave data');
  }

  @override
  void didUpdateWidget(covariant CalendarMonthWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Jika filter berubah, fetch semula data
    if (oldWidget.selectedLeaveTypes != widget.selectedLeaveTypes) {
      fetchLeaveData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final DateTime firstDay = DateTime(widget.year, widget.month, 1);
    final int daysInMonth = DateUtils.getDaysInMonth(widget.year, widget.month);
    final int firstWeekday = firstDay.weekday; // 1=Mon, 7=Sun
    final List<Widget> dayWidgets = [];
    
    print('DEBUG: Building calendar for month ${widget.month}, leaveMap size: ${leaveMap.length}');
    
    // Debug: Check if current month is being displayed
    final DateTime now = DateTime.now();
    if (widget.month == now.month && widget.year == now.year) {
      print('DEBUG: 🎯 CURRENT MONTH IS BEING DISPLAYED!');
      print('DEBUG: Today is ${now.day}');
    }
    
    // Add empty widgets for days before the 1st
    for (int i = 1; i < firstWeekday; i++) {
      dayWidgets.add(const SizedBox());
    }
    // Add day numbers
    for (int day = 1; day <= daysInMonth; day++) {
      dayWidgets.add(_buildDayBox(context, widget.year, widget.month, day, leaveMap));
    }
    // Fill the last week with empty boxes if needed
    while (dayWidgets.length % 7 != 0) {
      dayWidgets.add(const SizedBox());
    }
    // Build week rows
    return Container(
      key: ValueKey('calendar_month_${widget.month}_${leaveMap.length}'),
      margin: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: widget.isDarkMode ? Colors.white10 : Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            DateFormat('MMM yyyy').format(firstDay),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: widget.isDarkMode ? Colors.white : Color(0xFF282454),
            ),
          ),
          const SizedBox(height: 8),
          // Label hari
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ...['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((d) =>
                Expanded(
                  child: Center(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: widget.isDarkMode ? Colors.white70 : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Grid calendar
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 0.7, // Increased from 0.6 to give more height
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
              ),
              itemCount: dayWidgets.length,
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: dayWidgets[index],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          // Month navigation above Today button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_left, color: Color(0xFF282454)),
                onPressed: () async {
                  // Navigate to previous month
                  if (mounted) {
                    final timeOffPage = context.findAncestorStateOfType<_TimeOffPageState>();
                    if (timeOffPage != null) {
                      timeOffPage.setState(() {
                        if (timeOffPage._displayMonth == 1) {
                          // If January, go to December of previous year
                          timeOffPage._displayMonth = 12;
                          timeOffPage._startYear--;
                        } else {
                          // Go to previous month
                          timeOffPage._displayMonth--;
                        }
                      });
                      await timeOffPage.getLeavesForAllMonths();
                    }
                  }
                },
              ),
              Text(
                DateFormat('MMM yyyy').format(DateTime(widget.year, widget.month)),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: widget.isDarkMode ? Colors.white : const Color(0xFF282454),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_right, color: Color(0xFF282454)),
                onPressed: () async {
                  // Navigate to next month
                  if (mounted) {
                    final timeOffPage = context.findAncestorStateOfType<_TimeOffPageState>();
                    if (timeOffPage != null) {
                      timeOffPage.setState(() {
                        if (timeOffPage._displayMonth == 12) {
                          // If December, go to January of next year
                          timeOffPage._displayMonth = 1;
                          timeOffPage._startYear++;
                        } else {
                          // Go to next month
                          timeOffPage._displayMonth++;
                        }
                      });
                      await timeOffPage.getLeavesForAllMonths();
                    }
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Today button at the bottom
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.today, size: 18),
              label: const Text('Today'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () async {
                // Navigate to current month
                final today = DateTime.now();
                print('DEBUG: Today button pressed, navigating to current month');
                print('DEBUG: Current date: $today');
                print('DEBUG: Current month: ${today.month}');
                
                // Update parent state to current month/year
                if (mounted) {
                  // Find the parent TimeOffPage and update its state
                  final timeOffPage = context.findAncestorStateOfType<_TimeOffPageState>();
                  if (timeOffPage != null) {
                    timeOffPage.setState(() {
                      timeOffPage._startYear = today.year;
                      timeOffPage._displayMonth = today.month;
                    });
                    await timeOffPage.getLeavesForAllMonths();
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 8),
          // Add Time Off Request button below Today button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Time Off Request'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                // Show add time off request dialog
                if (mounted) {
                  final timeOffPage = context.findAncestorStateOfType<_TimeOffPageState>();
                  if (timeOffPage != null) {
                    timeOffPage._showAddTimeOffRequestDialog();
                  }
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayBox(BuildContext context, int year, int month, int day, Map<DateTime, Map<String, dynamic>> leaveMap) {
    final DateTime date = DateTime(year, month, day);
    final bool isWeekend = date.weekday == 6 || date.weekday == 7;
    final DateTime today = DateTime.now();
    
    // Debug: Print today's date and current date being processed
    print('DEBUG: Today is ${today.year}-${today.month}-${today.day}');
    print('DEBUG: Processing date ${date.year}-${date.month}-${date.day}');
    
    final bool isToday = date.year == today.year && date.month == today.month && date.day == today.day;
    print('DEBUG: Is today? $isToday');
    
    // Debug: Special print for today
    if (isToday) {
      print('🎯 TODAY FOUND! Day: $day, Date: $date');
      print('🎯 Will render today widget with red background');
    }
    Color? bgColor;
    String? leaveTypeLabel;
    String? leaveStateLabel;
    Color? leaveStateTextColor;
    Color? leaveTypeColor;
    Map<String, dynamic>? leaveData;
    if (leaveMap.containsKey(date)) {
      final leave = leaveMap[date]!;
      leaveData = leave;
      final leaveType = leave['type']?.toLowerCase() ?? '';
      print('BUILD DAY BOX: $date, leaveType: $leaveType, leaveMap size: ${leaveMap.length}');
      // Type label & color
      if (leaveType.contains('sick')) {
        leaveTypeLabel = 'ML';
        leaveTypeColor = Colors.blue[700];
      } else if (leaveType.contains('unpaid')) {
        leaveTypeLabel = 'UPL';
        leaveTypeColor = Colors.purple[700];
      } else if (leaveType.contains('annual')) {
        leaveTypeLabel = 'Annual';
        leaveTypeColor = Colors.brown[700];
      } else if (leaveType.isNotEmpty) {
        leaveTypeLabel = leaveType[0].toUpperCase() + leaveType.substring(1);
        leaveTypeColor = Colors.grey[700];
      }
      // State color/indicator
      final leaveState = leave['state'] ?? '';
      print('DEBUG: Leave state from data: $leaveState');
      
      if (leaveState == 'validate' || leaveState == 'validate1') {
        bgColor = Colors.green[100]; // Light green for validated
        leaveStateLabel = 'Validated';
        leaveStateTextColor = Colors.green[900];
      } else if (leaveState == 'confirm') {
        bgColor = Colors.orange[100]; // Light orange for to approve
        leaveStateLabel = 'To Approve';
        leaveStateTextColor = Colors.orange[900];
      } else if (leaveState == 'refuse') {
        bgColor = Colors.red[100]; // Light red for refused
        leaveStateLabel = 'Refused';
        leaveStateTextColor = Colors.red[900];
      }
      
      print('DEBUG: Leave label set - leaveTypeLabel: $leaveTypeLabel, leaveStateLabel: $leaveStateLabel, bgColor: $bgColor');
      print('DEBUG: Will render leave label: ${leaveTypeLabel != null ? 'YES' : 'NO'} for date: $date');
    }
    return GestureDetector(
      onTap: () {
        if (leaveData != null) {
          // Show leave summary popup
        showDialog(
          context: context,
            builder: (context) => LeaveSummaryDialog(leaveData: leaveData!, date: date),
          );
        } else {
          // Show simple leave request dialog
          print('DEBUG: Showing simple dialog for date: $date');
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.event, color: const Color(0xFF282454)),
                  const SizedBox(width: 8),
                  const Text('Add Time Off Request'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Selected Date: ${DateFormat('dd/MM/yyyy').format(date)}'),
                  const SizedBox(height: 8),
                  Text('From and To dates will be automatically set to this date.'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                                  ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final result = await showDialog(
                        context: context,
                        builder: (context) => TimeOffRequestDialog(
                          initialDate: date,
                                                  onLeaveCreated: () async {
                          // Refresh data IMMEDIATELY after leave is created
                          print('DEBUG: Calendar refresh triggered IMMEDIATELY');
                          
                          // Show loading indicator with specific date
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 16),
                                  Expanded(
                                    child: Text('Refreshing calendar for ${DateFormat('dd/MM/yyyy').format(date)}...'),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.blue,
                              duration: Duration(seconds: 2),
                            ),
                          );
                          
                          try {
                            // Refresh immediately without delay
                            await fetchLeaveData();
                            print('DEBUG: Calendar data refreshed successfully');
                            
                            // Force rebuild multiple times to ensure UI updates
                            for (int i = 0; i < 10; i++) {
                              setState(() {});
                              await Future.delayed(const Duration(milliseconds: 30));
                            }
                            print('DEBUG: Calendar state forced to rebuild 10 times');
                            
                            // Debug: Check if data was updated
                            print('DEBUG: Current leaveMap size after refresh: ${leaveMap.length}');
                            
                            // Force parent rebuild multiple times
                            if (mounted) {
                              for (int i = 0; i < 5; i++) {
                                setState(() {});
                                await Future.delayed(const Duration(milliseconds: 30));
                              }
                              print('DEBUG: Final parent rebuild triggered 5 times');
                            }
                            
                            // Show success message with specific date
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.white),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text('Leave applied for ${DateFormat('dd/MM/yyyy').format(date)}! Check calendar.'),
                                    ),
                                  ],
                                ),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 4),
                              ),
                            );
                          } catch (e) {
                            print('DEBUG: Error refreshing calendar data: $e');
                            
                            // Show error message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error refreshing calendar: $e'),
                                backgroundColor: Colors.red,
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        },
                        ),
                      );
                      
                      // Also refresh if dialog closed with success
                      if (result == true) {
                        print('DEBUG: Calendar dialog closed with success, refreshing again IMMEDIATELY');
                        // Refresh immediately without delay
                        await fetchLeaveData();
                        
                        // Force rebuild multiple times to ensure UI updates
                        setState(() {});
                        await Future.delayed(const Duration(milliseconds: 100));
                        setState(() {});
                        await Future.delayed(const Duration(milliseconds: 100));
                        setState(() {});
                        print('DEBUG: Calendar state forced to rebuild multiple times after dialog close');
                        
                        // Debug: Check if data was updated
                        print('DEBUG: Current leaveMap size after dialog close refresh: ${leaveMap.length}');
                      }
                    },
                    child: const Text('Add Request'),
                  ),
              ],
            ),
          );
        }
      },
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: isToday
            ? (() {
                print('🎯 APPLYING TODAY DECORATION for day $day');
                return BoxDecoration(
                  color: Colors.red[400],
                  borderRadius: BorderRadius.circular(8),
                );
              })()
            : bgColor != null
                ? BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  )
                : isWeekend
                    ? BoxDecoration(
                        color: widget.isDarkMode ? Colors.white12 : Colors.grey[300],
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
        child: isToday
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        day.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      constraints: const BoxConstraints(minWidth: 36),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red, width: 2), // Make border thicker
                      ),
                      child: const Text(
                        'TODAY', // Make text uppercase and more visible
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8, // Increase font size
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      day.toString(),
                      style: TextStyle(
                        color: widget.isDarkMode
                            ? Colors.white
                            : Colors.black87,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (leaveTypeLabel != null || leaveStateLabel != null)
                    const SizedBox(height: 2),
                  if (leaveTypeLabel != null)
                    Container(
                      key: ValueKey('leave_label_${date.day}_${leaveTypeLabel}'),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      constraints: const BoxConstraints(minWidth: 36),
                      decoration: BoxDecoration(
                        color: (leaveTypeLabel == 'ML')
                            ? Colors.blue[700]
                            : (leaveTypeLabel == 'UPL')
                                ? Colors.purple[700]
                                : leaveTypeColor?.withOpacity(0.15) ?? Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: leaveTypeColor ?? Colors.grey),
                      ),
                      child: Text(
                        leaveTypeLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 8,
                          color: (leaveTypeLabel == 'ML' || leaveTypeLabel == 'UPL')
                              ? Colors.white
                              : leaveTypeColor ?? Colors.black87,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (leaveStateLabel != null)
                    Padding(
                      key: ValueKey('state_label_${date.day}_${leaveStateLabel}'),
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        leaveStateLabel,
                        style: TextStyle(
                          fontSize: 7,
                          color: leaveStateTextColor ?? Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const Spacer(),
                ],
              ),
      ),
    );
  }
}

class TimeOffRequestDialog extends StatefulWidget {
  final DateTime? initialDate;
  final VoidCallback? onLeaveCreated;
  const TimeOffRequestDialog({Key? key, this.initialDate, this.onLeaveCreated}) : super(key: key);

  @override
  State<TimeOffRequestDialog> createState() => _TimeOffRequestDialogState();
}

class _TimeOffRequestDialogState extends State<TimeOffRequestDialog> {
  String _selectedType = 'UNPAID LEAVE';
  DateTime? _fromDate;
  DateTime? _toDate;
  String _description = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _fromDate = widget.initialDate;
      _toDate = widget.initialDate;
    } else {
      _fromDate = null;
      _toDate = null;
    }
  }

  double get _duration {
    if (_fromDate == null || _toDate == null) return 0.0;
    return _toDate!.difference(_fromDate!).inDays.abs() + 1;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _fromDate : _toDate) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime((isFrom ? _fromDate : _toDate) ?? DateTime.now()),
      );
      DateTime finalDateTime = pickedDate;
      if (pickedTime != null) {
        finalDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      }
      setState(() {
        if (isFrom) {
          _fromDate = finalDateTime;
          if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
            _toDate = _fromDate;
          }
        } else {
          _toDate = finalDateTime;
          if (_fromDate != null && _fromDate!.isAfter(_toDate!)) {
            _fromDate = _toDate;
          }
        }
      });
    }
  }

  Future<void> _submitRequest() async {
    if (_fromDate == null || _toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sila pilih tarikh mula dan tamat')),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    print('🔍 DEBUG: Retrieved userId from SharedPreferences for leave request: $userId');
    print('🔍 DEBUG: userId type for leave request: ${userId.runtimeType}');
    
    if (userId == null || userId.isEmpty) {
      print('❌ ERROR: user_id is null or empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error: User not logged in. Please login again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Map dropdown value to Odoo leave type name
    String leaveTypeForOdoo;
    switch (_selectedType) {
      case 'UNPAID LEAVE':
        leaveTypeForOdoo = 'Unpaid';
        break;
      case 'ANNUAL LEAVE':
        leaveTypeForOdoo = 'Annual Leave';
        break;
      case 'SICK LEAVE':
        leaveTypeForOdoo = 'Sick Time Off'; // <-- Guna nama tepat dari Odoo
        break;
      default:
        leaveTypeForOdoo = _selectedType;
    }
    print('🔍 DEBUG: Submitting leave request with userId: $userId');
    print('🔍 DEBUG: Leave type: $leaveTypeForOdoo');
    print('🔍 DEBUG: Date from: $_fromDate');
    print('🔍 DEBUG: Date to: $_toDate');
    print('🔍 DEBUG: Description: $_description');
    
    final response = await OdooService().createLeaveRequest(
      userId: userId,
      dateFrom: _fromDate!,
      dateTo: _toDate!,
      leaveType: leaveTypeForOdoo,
      description: _description,
    );
    print('CREATE LEAVE RESPONSE: $response');
    final result = response['result'] ?? response;
    final isSuccess = result['success'] == true;
    if (isSuccess) {
      // Call callback to refresh data IMMEDIATELY
      print('DEBUG: Leave created successfully, calling refresh callback');
      if (widget.onLeaveCreated != null) {
        // Execute callback immediately
        widget.onLeaveCreated!();
        print('DEBUG: Refresh callback executed');
      } else {
        print('DEBUG: No refresh callback provided');
      }
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Leave request saved successfully! Refreshing calendar...'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
      
      // Close dialog
      Navigator.of(context).pop(true);
    } else {
      final errorMsg = result['error'] ?? 'Gagal simpan cuti. Sila cuba lagi.';
      print('CREATE LEAVE ERROR: $errorMsg');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan cuti: $errorMsg')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        color: isDarkMode ? Colors.black : Colors.white,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Time Off Request', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              // Time Off Type row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Time Off Type', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.purple[50],
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.purple[100]!),
                      ),
                      child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedType,
                            isExpanded: true,
                          dropdownColor: Colors.purple[50],
                          style: TextStyle(fontSize: 15, color: isDarkMode ? Colors.white : Colors.black87),
                            items: const [
                            DropdownMenuItem(value: 'UNPAID LEAVE', child: Text('Unpaid Leave')),
                            DropdownMenuItem(value: 'ANNUAL LEAVE', child: Text('Annual Leave')),
                            DropdownMenuItem(value: 'SICK LEAVE', child: Text('Medical Leave')),
                            ],
                            onChanged: (value) {
                              if (value != null) setState(() => _selectedType = value);
                            },
                          ),
                        ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Dates row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                  const Text('Dates', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                  const SizedBox(width: 16),
                  const Text('From', style: TextStyle(fontSize: 15)),
                            const SizedBox(width: 8),
                  Flexible(
                              child: InkWell(
                                onTap: () => _pickDate(isFrom: true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                  decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                                    borderRadius: BorderRadius.circular(4),
                          color: Colors.grey[isDarkMode ? 900 : 100],
                                  ),
                                  child: Text(
                                    _fromDate != null
                              ? DateFormat('MM/dd/yyyy').format(_fromDate!)
                                        : 'Select Date',
                          style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                  const SizedBox(width: 12),
                  const Text('To', style: TextStyle(fontSize: 15)),
                            const SizedBox(width: 8),
                  Flexible(
                              child: InkWell(
                                onTap: () => _pickDate(isFrom: false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                                  decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[400]!),
                                    borderRadius: BorderRadius.circular(4),
                          color: Colors.grey[isDarkMode ? 900 : 100],
                                  ),
                                  child: Text(
                                    _toDate != null
                              ? DateFormat('MM/dd/yyyy').format(_toDate!)
                                        : 'Select Date',
                          style: const TextStyle(fontSize: 15),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
              const SizedBox(height: 20),
                        // Duration
                        Row(
                          children: [
                  const Text('Duration', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
                  const SizedBox(width: 16),
                  Text(_duration.toStringAsFixed(2), style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 4),
                  const Text('Days', style: TextStyle(fontSize: 15)),
                          ],
                        ),
              const SizedBox(height: 20),
                        // Description
              const Text('Description', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16)),
              const SizedBox(height: 8),
                        Container(
                decoration: BoxDecoration(
                  color: Colors.purple[50],
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.purple[100]!),
                ),
                          child: TextField(
                            minLines: 3,
                            maxLines: 5,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(8),
                            ),
                            onChanged: (val) => setState(() => _description = val),
                          ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple[400],
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      await _submitRequest();
                    },
                    child: const Text('Save'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Discard'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LegendDialog extends StatelessWidget {
  const LegendDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        color: isDarkMode ? Colors.black : Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Legend',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 24),
            // Time Off Type Section
            Text(
              'Time Off Type',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            // Time Off Type items
            _buildLegendItem(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[600]!),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              'Time OffType',
            ),
            const SizedBox(height: 8),
            _buildLegendItem(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue[300]!),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              'MEDICAL LEAVE',
            ),
            const SizedBox(height: 8),
            _buildLegendItem(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.red[400]!),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              'UNPAID LEAVE',
            ),
            const SizedBox(height: 8),
            _buildLegendItem(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.brown[300]!),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              'ANNUAL LEAVE',
            ),

            const SizedBox(height: 24),
            // Legend Section
            Text(
              'Legend',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            // Legend items
            _buildLegendItem(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              'Validated',
            ),
            const SizedBox(height: 8),
            _buildLegendItem(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: CustomPaint(
                  painter: DiagonalStripesPainter(),
                ),
              ),
              'To Approve',
            ),
            const SizedBox(height: 8),
            _buildLegendItem(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: const Color(0xFF6B7280),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Center(
                  child: Container(
                    width: 12,
                    height: 2,
                    color: Colors.white,
                  ),
                ),
              ),
              'Refused',
            ),

            const SizedBox(height: 24),
            // Close button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDarkMode ? Colors.white : const Color(0xFF282454),
                    foregroundColor: isDarkMode ? Colors.black : Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Close'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, bool isDarkMode, Widget icon, String label) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class LegendDrawer extends StatefulWidget {
  final BuildContext parentContext;
  final void Function(BuildContext parentContext) onAddTimeOffRequest;
  final List<dynamic> allLeaves;
  final dynamic userId;
  const LegendDrawer({Key? key, required this.parentContext, required this.onAddTimeOffRequest, required this.allLeaves, required this.userId}) : super(key: key);

  @override
  _LegendDrawerState createState() => _LegendDrawerState();
}

class _LegendDrawerState extends State<LegendDrawer> {
  String? userEmail;
  String? userImageBase64;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    // Dapatkan email dari SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userEmail = prefs.getString('user_email') ?? '';
    });

    // Dapatkan image dari OdooService
    final imageBase64 = await OdooService().fetchUserImage();
    setState(() {
      userImageBase64 = imageBase64;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Drawer(
      child: SafeArea(
        child: Container(
          color: isDarkMode ? Colors.black : Colors.white,
          width: 320,
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- USER IMAGE & EMAIL ROW ---
                Row(
                  children: [
                    if (userImageBase64 != null && userImageBase64!.isNotEmpty)
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: MemoryImage(base64Decode(userImageBase64!)),
                        backgroundColor: Colors.grey[300],
                      )
                    else
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: Colors.grey[300],
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        userEmail ?? '',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // --- LEGEND (now at the top) ---
                Text(
                  'Leave Type',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.black : Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                // ML label
                _buildLegendItem(
                  context,
                  isDarkMode,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue[700],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[700]!),
                    ),
                    child: Text('ML', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  'Medical Leave',
                ),
                const SizedBox(height: 8),
                // UPL label
                _buildLegendItem(
                  context,
                  isDarkMode,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.purple[700],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.purple[700]!),
                    ),
                    child: Text('UPL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  'Unpaid Leave',
                ),
                const SizedBox(height: 8),
                // Annual Leave label (brown)
                _buildLegendItem(
                  context,
                  isDarkMode,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.brown[700],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.brown[700]!),
                    ),
                    child: Text('Annual', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  'Annual Leave',
                ),
                const SizedBox(height: 8),
                // Today label
                _buildLegendItem(
                  context,
                  isDarkMode,
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red[400],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red[400]!),
                    ),
                    child: Text('Today', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  'Today',
                ),
                const SizedBox(height: 24),
                // --- LEAVE STATUS (now after legend) ---
                Text('Leave Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                // Validated (green)
                _buildLegendItem(
                  context,
                  isDarkMode,
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.green[700]!),
                    ),
                  ),
                  'Validated',
                ),
                const SizedBox(height: 8),
                // To Approve (orange)
                _buildLegendItem(
                  context,
                  isDarkMode,
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.orange[100],
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.orange[700]!),
                    ),
                  ),
                  'To Approve',
                ),
                const SizedBox(height: 8),
                // Today (red)
                _buildLegendItem(
                  context,
                  isDarkMode,
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.red[400],
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: Colors.red[400]!),
                    ),
                      ),
                  'Today',
                ),
                const SizedBox(height: 32),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.assignment_turned_in),
                        label: const Text('Approval'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange[800],
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () async {
                          showDialog(
                            context: context,
                            builder: (context) => ApprovalDialog(allLeaves: widget.allLeaves, userId: widget.userId),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Time Off Request'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF282454),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () async {
                      Navigator.of(context).pop(); // Tutup drawer
                      await Future.delayed(const Duration(milliseconds: 300));
                      widget.onAddTimeOffRequest(widget.parentContext);
                    },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(BuildContext context, bool isDarkMode, Widget icon, String label) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 16),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
      ],
    );
  }
}

class DiagonalStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.0;

    const double spacing = 3.0;
    for (double i = -size.width; i < size.width + size.height; i += spacing) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }



  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class LeaveStatusInfoDialog extends StatelessWidget {
  const LeaveStatusInfoDialog({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        color: isDarkMode ? Colors.black : Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leave Type section
            Text(
              'Leave Type',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.black : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusRow(
              context,
              isDarkMode,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[700],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[700]!),
                ),
                child: Text('ML', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              'Medical Leave',
            ),
            const SizedBox(height: 8),
            _buildStatusRow(
              context,
              isDarkMode,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple[700],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple[700]!),
                ),
                child: Text('UPL', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              'Unpaid Leave',
            ),
            const SizedBox(height: 8),
            _buildStatusRow(
              context,
              isDarkMode,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.brown[700],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.brown[700]!),
                ),
                child: Text('Annual', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              'Annual Leave',
            ),
            const SizedBox(height: 8),
            _buildStatusRow(
              context,
              isDarkMode,
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red[400],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[400]!),
                ),
                child: Text('Today', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              'Today',
            ),
            const SizedBox(height: 24),
            // Leave Status section
            Text(
              'Leave Status',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 16),
            _buildStatusRow(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.green[700]!),
                ),
              ),
              'Validated',
            ),
            const SizedBox(height: 8),
            _buildStatusRow(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.orange[700]!),
                ),
              ),
              'To Approve',
            ),
            const SizedBox(height: 8),
            _buildStatusRow(
              context,
              isDarkMode,
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Colors.red[400],
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: Colors.red[400]!),
                ),
              ),
              'Today',
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkMode ? Colors.white : const Color(0xFF282454),
                  foregroundColor: isDarkMode ? Colors.black : Colors.white,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(BuildContext context, bool isDarkMode, Widget icon, String label) {
    return Row(
      children: [
        icon,
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}

class ApprovalDialog extends StatelessWidget {
  final List<dynamic> allLeaves;
  final dynamic userId;
  const ApprovalDialog({Key? key, required this.allLeaves, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    // Filter only user leaves
    List<Map<String, dynamic>> userLeaves = allLeaves.where((leave) {
      final leaveEmpId = int.tryParse(leave['employee_id'].toString());
      final userIdInt = int.tryParse(userId.toString());
      return leaveEmpId == userIdInt;
    }).map((e) => Map<String, dynamic>.from(e)).toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 700,
        padding: const EdgeInsets.all(24),
        color: isDarkMode ? Colors.black : Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Leave Approval List', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : Colors.black87)),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Time Off Type')),
                  DataColumn(label: Text('Description')),
                  DataColumn(label: Text('Start Date')),
                  DataColumn(label: Text('End Date')),
                  DataColumn(label: Text('Duration')),
                  DataColumn(label: Text('Status')),
                ],
                rows: userLeaves.map((leave) {
                  final leaveType = (leave['leave_type'] ?? '').toString();
                  final desc = (leave['description'] ?? '').toString();
                  final start = (leave['date_from'] ?? '').toString().replaceFirst('T', ' ');
                  final end = (leave['date_to'] ?? '').toString().replaceFirst('T', ' ');
                  final duration = _calculateDuration(leave['date_from'], leave['date_to']);
                  final status = _statusLabel(leave['state']);
                  return DataRow(cells: [
                    DataCell(Text(leaveType)),
                    DataCell(Text(desc)),
                    DataCell(Text(start)),
                    DataCell(Text(end)),
                    DataCell(Text(duration)),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _statusColor(leave['state']),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(status, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    )),
                  ]);
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.bottomRight,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDarkMode ? Colors.white : const Color(0xFF282454),
                  foregroundColor: isDarkMode ? Colors.black : Colors.white,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _calculateDuration(String? from, String? to) {
    if (from == null || to == null) return '';
    try {
      final start = DateTime.tryParse(from);
      final end = DateTime.tryParse(to);
      if (start == null || end == null) return '';
      final diff = end.difference(start);
      if (diff.inDays >= 1) {
        return '${diff.inDays} days';
      } else if (diff.inHours >= 1) {
        return '${diff.inHours} hours';
      } else {
        return '${diff.inMinutes} minutes';
      }
    } catch (_) {
      return '';
    }
  }

  String _statusLabel(String? state) {
    switch (state) {
      case 'confirm':
        return 'To Approve';
      case 'validate1':
        return 'Second Approval';
      case 'validate':
        return 'Approved';
      case 'refuse':
        return 'Refused';
      default:
        return state ?? '';
    }
  }

  Color _statusColor(String? state) {
    switch (state) {
      case 'confirm':
        return Colors.orange[700]!;
      case 'validate1':
        return Colors.orange[300]!;
      case 'validate':
        return Colors.green[700]!;
      case 'refuse':
        return Colors.red[700]!;
      default:
        return Colors.grey;
    }
  }
}

class LeaveSummaryDialog extends StatelessWidget {
  final Map<String, dynamic> leaveData;
  final DateTime date;
  
  const LeaveSummaryDialog({
    Key? key, 
    required this.leaveData, 
    required this.date
  }) : super(key: key);

  String _getLeaveTypeLabel(String? leaveType) {
    if (leaveType == null) return '';
    final type = leaveType.toLowerCase();
    if (type.contains('sick')) return 'Medical Leave';
    if (type.contains('unpaid')) return 'Unpaid Leave';
    if (type.contains('annual')) return 'Annual Leave';
    return leaveType;
  }

  String _getStatusLabel(String? state) {
    switch (state) {
      case 'confirm':
        return 'To Approve';
      case 'validate1':
        return 'Second Approval';
      case 'validate':
        return 'Approved';
      case 'refuse':
        return 'Refused';
      default:
        return state ?? 'Unknown';
    }
  }

  Color _getStatusColor(String? state) {
    switch (state) {
      case 'confirm':
        return Colors.orange[700]!;
      case 'validate1':
        return Colors.orange[300]!;
      case 'validate':
        return Colors.green[700]!;
      case 'refuse':
        return Colors.red[700]!;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _calculateDuration(String? from, String? to) {
    if (from == null || to == null) return '';
    try {
      final start = DateTime.tryParse(from);
      final end = DateTime.tryParse(to);
      if (start == null || end == null) return '';
      final diff = end.difference(start);
      if (diff.inDays >= 1) {
        return '${diff.inDays + 1} days';
      } else if (diff.inHours >= 1) {
        return '${diff.inHours} hours';
      } else {
        return '${diff.inMinutes} minutes';
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final leaveType = leaveData['type'] ?? '';
    final status = leaveData['state'] ?? '';
    final dateFrom = leaveData['date_from'] ?? '';
    final dateTo = leaveData['date_to'] ?? '';
    final description = leaveData['description'] ?? '';
    
    // Debug print untuk description
    print('DEBUG: LeaveSummaryDialog - Description: "$description"');
    print('DEBUG: LeaveSummaryDialog - Description length: ${description.length}');
    print('DEBUG: LeaveSummaryDialog - Description isEmpty: ${description.isEmpty}');
    print('DEBUG: LeaveSummaryDialog - Full leaveData: $leaveData');
    
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(24),
        color: isDarkMode ? Colors.black : Colors.white,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.event_note,
                    color: const Color(0xFF282454),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Leave Summary',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : const Color(0xFF282454),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              // Date
              _buildInfoRow('Date', DateFormat('dd/MM/yyyy').format(date)),
              const SizedBox(height: 12),
              
              // Leave Type
              _buildInfoRow('Leave Type', _getLeaveTypeLabel(leaveType)),
              const SizedBox(height: 12),
              
              // Status
              Row(
                children: [
                  Text(
                    'Status: ',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _getStatusLabel(status),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Date Range
              _buildInfoRow('From', _formatDate(dateFrom)),
              const SizedBox(height: 8),
              _buildInfoRow('To', _formatDate(dateTo)),
              const SizedBox(height: 8),
              
              // Duration
              _buildInfoRow('Duration', _calculateDuration(dateFrom, dateTo)),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'Description:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  description.isNotEmpty ? description : 'No description provided',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}





