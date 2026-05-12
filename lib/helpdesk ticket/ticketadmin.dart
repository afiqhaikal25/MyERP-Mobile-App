import 'package:flutter/material.dart';
import '../odoo_service.dart';
import 'package:intl/intl.dart';
import '../main.dart'; // Add this import for LoginPage
import 'package:shared_preferences/shared_preferences.dart';
import 'ticketdetails.dart';
import 'totalfeedback.dart'; // Add this for TotalFeedbackScreen

class TicketAdminPage extends StatefulWidget {
  final String email;
  final String password;

  const TicketAdminPage({Key? key, required this.email, required this.password}) : super(key: key);

  @override
  State<TicketAdminPage> createState() => _TicketAdminPageState();
}

class _TicketAdminPageState extends State<TicketAdminPage> {
  final OdooService _odooService = OdooService();
  bool _isLoading = true;
  List<dynamic> _allTickets = [];
  List<dynamic> _filteredTickets = [];
  bool _isDarkMode = false; // Add dark mode state
  String? _selectedCategory;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _fetchAllTickets();
    _loadDarkMode(); // Add dark mode loading
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    bool savedMode = prefs.getBool('isDarkMode') ?? false;
    setState(() {
      _isDarkMode = savedMode;
    });
  }

  Future<void> _saveDarkMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', value);
  }

  Future<void> _fetchAllTickets() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final userIdStr = await _odooService.authenticate(widget.email, widget.password);
      debugPrint("🔑 Admin authentication result - User ID: $userIdStr");
      
      if (userIdStr != null) {
        final userId = int.tryParse(userIdStr);
        if (userId != null) {
          debugPrint("📥 Fetching all tickets for admin...");
          final tickets = await _odooService.fetchAllTicketsForAdmin(
            _odooService.database,
            userId,
            widget.password,
          );

          debugPrint("✅ Fetched ${tickets.length} tickets");
          setState(() {
            _allTickets = tickets;
            _filteredTickets = tickets;
            _isLoading = false;
          });
        } else {
          debugPrint("❌ Invalid user ID format");
          setState(() => _isLoading = false);
        }
      } else {
        debugPrint("❌ Authentication failed");
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("❌ Error fetching tickets: $e");
      setState(() => _isLoading = false);
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredTickets = _allTickets.where((ticket) {
        bool matchesCategory = _selectedCategory == null || 
            ticket['category_name'] == _selectedCategory;
        
        bool matchesStatus = _selectedStatus == null;
        if (_selectedStatus != null) {
          final stageName = _getStageName(ticket).toLowerCase();
          if (_selectedStatus == 'Open') {
            matchesStatus = !stageName.contains('closed') && !stageName.contains('done');
          } else if (_selectedStatus == 'Closed') {
            matchesStatus = stageName.contains('closed') || stageName.contains('done');
          }
        }
        
        return matchesCategory && matchesStatus;
      }).toList();
    });
  }

  String _getStageName(Map<String, dynamic> ticket) {
    try {
      final stageId = ticket['stage_id'];
      if (stageId is List && stageId.length > 1) {
        return stageId[1]?.toString() ?? '';
      } else if (stageId is String) {
        return stageId;
      }
      return '';
    } catch (e) {
      debugPrint('Error getting stage name: $e');
      return '';
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Tickets'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Category',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF282454),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('All Categories'),
              selected: _selectedCategory == null,
              onTap: () {
                setState(() => _selectedCategory = null);
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            ..._getUniqueCategories().map((category) => ListTile(
              title: Text(category),
              selected: _selectedCategory == category,
              onTap: () {
                setState(() => _selectedCategory = category);
                _applyFilters();
                Navigator.pop(context);
              },
            )),
            const Divider(height: 32),
            const Text(
              'Status',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF282454),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              title: const Text('All Status'),
              selected: _selectedStatus == null,
              onTap: () {
                setState(() => _selectedStatus = null);
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Open'),
              selected: _selectedStatus == 'Open',
              onTap: () {
                setState(() => _selectedStatus = 'Open');
                _applyFilters();
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Closed'),
              selected: _selectedStatus == 'Closed',
              onTap: () {
                setState(() => _selectedStatus = 'Closed');
                _applyFilters();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getUniqueCategories() {
    final categories = _allTickets
        .map((ticket) => ticket['category_name'] as String?)
        .where((category) => category != null)
        .map((category) => category!)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDarkMode ? Colors.black : const Color(0xFFF1FAF5),
      drawer: _buildDrawer(context),
body: Builder(
  builder: (context) {
    if (_isLoading) {
      print("🔄 Sedang loading data ticket admin...");
      return const Center(child: CircularProgressIndicator());
    }

    if (_filteredTickets == null) {
      print("⚠️ _filteredTickets masih null");
      return const Center(child: Text("Tiada data."));
    }

    if (_filteredTickets.isEmpty) {
      print("📭 _filteredTickets kosong.");
      return Center(
        child: Text(
          "No tickets found.",
          style: TextStyle(
            color: _isDarkMode ? Colors.white : Colors.black,
            fontSize: 16,
          ),
        ),
      );
    }

    print("✅ Jumpa ${_filteredTickets.length} tiket.");
    return RefreshIndicator(
      onRefresh: _fetchAllTickets,
      child: ListView.builder(
        itemCount: _filteredTickets.length,
        itemBuilder: (context, index) {
          final ticket = _filteredTickets[index];
          return _buildTicketCard(ticket);
        },
      ),
    );
  },
),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: Container(
        color: _isDarkMode ? Colors.grey[900] : Colors.white,
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: _isDarkMode ? Colors.grey[850] : const Color(0xFF282454),
              ),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.admin_panel_settings, size: 40, color: const Color(0xFF282454)),
              ),
              accountName: const Text(
                'Admin Dashboard',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              accountEmail: Text(
                widget.email,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.dark_mode,
                color: _isDarkMode ? Colors.white : Colors.grey[800],
              ),
              title: Text(
                'Dark Mode',
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.grey[800],
                ),
              ),
              trailing: Switch(
                value: _isDarkMode,
                onChanged: (value) {
                  setState(() {
                    _isDarkMode = value;
                  });
                  _saveDarkMode(value);
                },
                activeColor: Colors.white,
                activeTrackColor: Colors.grey[600],
                inactiveThumbColor: const Color(0xFF282454),
                inactiveTrackColor: Colors.grey,
              ),
            ),
            ListTile(
              leading: Icon(
                Icons.settings,
                color: _isDarkMode ? Colors.white : Colors.grey[800],
              ),
              title: Text(
                'Settings',
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.grey[800],
                ),
              ),
              onTap: () {},
            ),
            ListTile(
              leading: Icon(
                Icons.logout,
                color: _isDarkMode ? Colors.white : Colors.grey[800],
              ),
              title: Text(
                'Logout',
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.grey[800],
                ),
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
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                foregroundColor: Colors.white,
              ),
              child: const Text('Logout'),
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (Route<dynamic> route) => false,
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    bool isHovered = false;

    // Helper function to safely get stage name
    String getStageName() {
      return _getStageName(ticket);
    }

    // Helper function to safely get user name
    String getUserName() {
      try {
        final userId = ticket['user_id'];
        if (userId is List && userId.length > 1) {
          return userId[1]?.toString() ?? 'Unassigned';
        }
        return 'Unassigned';
      } catch (e) {
        debugPrint('Error getting user name: $e');
        return 'Unassigned';
      }
    }

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
                color: _isDarkMode ? Colors.grey[850] : Colors.white,
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
                              _isDarkMode ? Colors.grey[850]! : Colors.white,
                              const Color(0xFF282454).withOpacity(0.1),
                            ],
                          )
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                                      ticket['ticket_number_display'] ?? ticket['name'] ?? "Unnamed Ticket",
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
                                              color: Color(0xFF19543E),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDate(ticket['create_date']),
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: _isDarkMode ? Colors.white70 : const Color(0xFF19543E),
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
                                children: [
                                  _buildStatusBadge(getStageName()),
                                  const SizedBox(width: 4),
                                  _buildPriorityBadge(ticket['priority']),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 1,
                            color: _isDarkMode ? Colors.grey[800] : Colors.grey.withOpacity(0.1),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isDarkMode ? Colors.grey[800] : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _isDarkMode ? Colors.grey[700]! : Colors.grey.withOpacity(0.1),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildInfoRow(
                              Icons.category_outlined,
                              'Category - ${ticket['category_name'] ?? 'Uncategorized'}',
                              _isDarkMode ? Colors.white70 : const Color(0xFF282454),
                            ),
                            const SizedBox(height: 4),
                            _buildInfoRow(
                              Icons.build_outlined,
                              'Problem - ${ticket['prob_name'] ?? 'No Problem Specified'}',
                              _isDarkMode ? Colors.white70 : const Color(0xFF282454),
                            ),
                            const SizedBox(height: 4),
                            _buildInfoRow(
                              Icons.location_on,
                              'Address - ${ticket['address'] ?? 'No Address'}',
                              _isDarkMode ? Colors.white70 : const Color(0xFF282454),
                            ),
                            const SizedBox(height: 4),
                            _buildInfoRow(
                              Icons.person,
                              'Assigned to - ${getUserName()}',
                              _isDarkMode ? Colors.white70 : const Color(0xFF282454),
                            ),
                          ],
                        ),
                      ),
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
          fontSize: 12,
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
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
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
      return const Color(0xFF46BBFE);
    } else {
      return const Color(0xFF282454);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr).toLocal(); // Convert UTC to local time
      return DateFormat('dd/MM/yyyy  •  hh:mm a').format(date);
    } catch (e) {
      return dateStr;
    }
  }

  void _onTicketTap(Map<String, dynamic> ticket) {
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

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('What would you like to do?'),
        content: Text(isClosed ? 'This ticket is closed.' : 'This ticket is still open.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close popup
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
              Navigator.pop(context); // Close popup
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TicketDetailsPage(
                    ticket: ticket,
                    odooService: _odooService,
                    isDarkMode: _isDarkMode,
                    onTicketUpdated: _fetchAllTickets,
                    isAdminView: true,
                  ),
                ),
              );
            },
            child: const Text('View Ticket Details'),
          ),
        ],
      ),
    );
  }
}
