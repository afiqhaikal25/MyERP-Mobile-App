import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../home.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../odoo_service.dart';
import 'dart:convert';

class CalendarPage extends StatefulWidget {
  const CalendarPage({Key? key}) : super(key: key);

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime _focusedMonth = DateTime.now();
  bool _isSwipeInProgress = false;

  String? userEmail;
  String? userImageBase64;

  // Meeting history list from Odoo
  List<Map<String, dynamic>> _meetingHistory = [];
  bool _isLoadingMeetings = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadMeetingsFromOdoo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userEmail = prefs.getString('user_email') ?? '';
    });
    final imageBase64 = await OdooService().fetchUserImage();
    setState(() {
      userImageBase64 = imageBase64;
    });
  }

  Future<void> _loadMeetingsFromOdoo() async {
    setState(() {
      _isLoadingMeetings = true;
    });

    try {
      // Add timeout to prevent hanging
      final meetings = await OdooService().fetchCalendarEvents()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              print('❌ Load meetings timeout');
              return <Map<String, dynamic>>[];
            },
          );
      
      setState(() {
        _meetingHistory = meetings;
        _isLoadingMeetings = false;
      });
      print('✅ Loaded ${meetings.length} meetings from Odoo');
    } catch (e) {
      print('❌ Error loading meetings: $e');
      setState(() {
        _isLoadingMeetings = false;
      });
    }
  }

  void _showAddMeetingDialog() {
    final TextEditingController _subjectController = TextEditingController();
    final TextEditingController _locationController = TextEditingController();
    final TextEditingController _urlController = TextEditingController();
    final TextEditingController _descriptionController = TextEditingController();

    DateTime _startDateTime = DateTime.now();
    DateTime _endDateTime = DateTime.now().add(Duration(hours: 1));
    bool _isAllDay = false;
    String _selectedCategory = 'General';
    String _selectedPriority = 'Medium';
    bool _isLoading = false;

    final List<String> _categories = [
      'General',
      'Business',
      'Personal',
      'Team Meeting',
      'Client Meeting',
      'Training',
      'Conference',
      'Other'
    ];

    final List<String> _priorities = [
      'Low',
      'Medium',
      'High',
      'Urgent'
    ];

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setState) {
        return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                    // Header with gradient
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF282454),
                            const Color(0xFF282454).withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.event_note,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                                const Text(
                                  'Create New Meeting',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                        Text(
                                  'Schedule your meeting details',
                          style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 24,
                            ),
                        ),
                      ],
                    ),
                  ),
                    
                    // Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Subject Field
                            _buildModernTextField(
                              controller: _subjectController,
                              label: 'Meeting Subject',
                              hint: 'Enter meeting title',
                              icon: Icons.title,
                              isRequired: true,
                              isDark: isDark,
                              onChanged: (value) => setState(() {}),
                            ),
                            const SizedBox(height: 20),
                            
                            // Category and Priority Row
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDropdownField(
                                    label: 'Category',
                                    value: _selectedCategory,
                                    items: _categories,
                                    icon: Icons.category,
                                    isDark: isDark,
                                    onChanged: (value) => setState(() => _selectedCategory = value!),
                                  ),
                                ),
                                const SizedBox(width: 16),
                      Expanded(
                                  child: _buildDropdownField(
                                    label: 'Priority',
                                    value: _selectedPriority,
                                    items: _priorities,
                                    icon: Icons.flag,
                                    isDark: isDark,
                                    onChanged: (value) => setState(() => _selectedPriority = value!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // All Day Toggle
                            _buildToggleCard(
                              title: 'All Day Event',
                              subtitle: 'Meeting spans the entire day',
                              icon: Icons.event,
                              value: _isAllDay,
                              isDark: isDark,
                              onChanged: (value) {
                                    setState(() {
                                  _isAllDay = value;
                                  if (_isAllDay) {
                                    _startDateTime = DateTime(_startDateTime.year, _startDateTime.month, _startDateTime.day);
                                    _endDateTime = DateTime(_endDateTime.year, _endDateTime.month, _endDateTime.day);
                                } else {
                                    _startDateTime = DateTime.now();
                                    _endDateTime = DateTime.now().add(Duration(hours: 1));
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            
                            // Date/Time Selection
                            _buildDateTimeSection(
                              startDateTime: _startDateTime,
                              endDateTime: _endDateTime,
                              isAllDay: _isAllDay,
                              isDark: isDark,
                              onStartChanged: (dateTime) => setState(() => _startDateTime = dateTime),
                              onEndChanged: (dateTime) => setState(() => _endDateTime = dateTime),
                            ),
                            const SizedBox(height: 20),
                            
                            // Location Field
                            _buildModernTextField(
                    controller: _locationController,
                              label: 'Location',
                              hint: 'Meeting room, address, or online',
                              icon: Icons.location_on,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 20),
                            
                            // URL Field
                            _buildModernTextField(
                    controller: _urlController,
                              label: 'Meeting URL',
                              hint: 'https://meet.google.com/...',
                              icon: Icons.link,
                              isDark: isDark,
                              keyboardType: TextInputType.url,
                            ),
                            const SizedBox(height: 20),
                            
                            // Description Field
                            _buildModernTextField(
                    controller: _descriptionController,
                              label: 'Description',
                              hint: 'Add meeting details, agenda, or notes...',
                              icon: Icons.description,
                              isDark: isDark,
                              maxLines: 4,
                            ),
                            const SizedBox(height: 32),
                            
                            // Action Buttons
                            Row(
                    children: [
                                Expanded(
                                  child: _buildActionButton(
                                    text: 'Cancel',
                                    isPrimary: false,
                                    isDark: isDark,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildActionButton(
                                    text: _isLoading ? 'Creating...' : 'Create Meeting',
                                    isPrimary: true,
                                    isDark: isDark,
                                    isLoading: _isLoading,
                                    onPressed: _isLoading ? null : () async {
                          // Validate required fields
                          if (_subjectController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.warning, color: Colors.white),
                                                const SizedBox(width: 8),
                                                const Text('Please enter a meeting subject'),
                                              ],
                                            ),
                                backgroundColor: Colors.orange,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            );
                            return;
                          }

                          if (_endDateTime.isBefore(_startDateTime)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.warning, color: Colors.white),
                                                const SizedBox(width: 8),
                                                const Text('End time must be after start time'),
                                              ],
                                            ),
                                backgroundColor: Colors.orange,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            );
                            return;
                          }

                                      setState(() => _isLoading = true);

                          try {
                            print('🔍 DEBUG: Starting to create meeting...');
                            print('🔍 DEBUG: Subject: ${_subjectController.text}');
                            print('🔍 DEBUG: Start: $_startDateTime');
                            print('🔍 DEBUG: End: $_endDateTime');
                            
                            // Create meeting in Odoo
                            final result = await OdooService().createCalendarEvent(
                              name: _subjectController.text.trim(),
                              start: _startDateTime,
                              stop: _endDateTime,
                              description: _descriptionController.text.trim(),
                              location: _locationController.text.trim(),
                              videocallLocation: _urlController.text.trim(),
                              allday: _isAllDay,
                            );

                                        setState(() => _isLoading = false);

                            if (result != null && result['id'] != null) {
                              print('✅ Meeting created successfully with ID: ${result['id']}');
                              
                              // Refresh meetings from Odoo
                              await _loadMeetingsFromOdoo();
                              
                              // Close add meeting dialog
                              Navigator.of(context).pop();
                              
                              // Show success message
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.check_circle, color: Colors.white),
                                                  const SizedBox(width: 8),
                                                  Text('Meeting "${_subjectController.text}" created successfully!'),
                                                ],
                                              ),
                                  backgroundColor: Colors.green,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            } else {
                              print('❌ Failed to create meeting - result: $result');
                              // Show error message
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.error, color: Colors.white),
                                                  const SizedBox(width: 8),
                                                  const Text('Failed to create meeting. Please try again.'),
                                                ],
                                              ),
                                  backgroundColor: Colors.red,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          } catch (e) {
                            print('❌ Error creating meeting: $e');
                                        setState(() => _isLoading = false);
                            
                            // Show error message
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.error, color: Colors.white),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text('Error: ${e.toString()}')),
                                              ],
                                            ),
                                backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                duration: const Duration(seconds: 4),
                              ),
                            );
                          }
                        },
                                  ),
                      ),
                    ],
                            ),
                ],
              ),
                      ),
                    ),
                  ],
            ),
          ),
            );
          },
        );
      },
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool isRequired = false,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF282454),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF282454),
              ),
            ),
            if (isRequired) ...[
              const SizedBox(width: 4),
              Text(
                '*',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.white54 : Colors.black54,
              fontSize: 14,
            ),
            filled: true,
            fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFF282454),
                width: 2,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required IconData icon,
    required bool isDark,
    required Function(String?) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF282454),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF282454),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[800] : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
              dropdownColor: isDark ? Colors.grey[800] : Colors.white,
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(item),
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required bool isDark,
    required Function(bool) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF282454).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF282454),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF282454),
          ),
        ],
      ),
    );
  }

  Widget _buildDateTimeSection({
    required DateTime startDateTime,
    required DateTime endDateTime,
    required bool isAllDay,
    required bool isDark,
    required Function(DateTime) onStartChanged,
    required Function(DateTime) onEndChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.schedule,
              size: 16,
              color: isDark ? Colors.white70 : const Color(0xFF282454),
            ),
            const SizedBox(width: 8),
            Text(
              isAllDay ? 'Date Range' : 'Date & Time',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : const Color(0xFF282454),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDateTimeCard(
                label: isAllDay ? 'Start Date' : 'Start',
                dateTime: startDateTime,
                isAllDay: isAllDay,
                isDark: isDark,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: startDateTime,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) {
                    if (isAllDay) {
                      onStartChanged(DateTime(date.year, date.month, date.day));
                    } else {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(startDateTime),
                      );
                      if (time != null) {
                        onStartChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                      }
                    }
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.arrow_forward,
              color: isDark ? Colors.white54 : Colors.black54,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateTimeCard(
                label: isAllDay ? 'End Date' : 'End',
                dateTime: endDateTime,
                isAllDay: isAllDay,
                isDark: isDark,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: endDateTime,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (date != null) {
                    if (isAllDay) {
                      onEndChanged(DateTime(date.year, date.month, date.day));
                    } else {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(endDateTime),
                      );
                      if (time != null) {
                        onEndChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
                      }
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateTimeCard({
    required String label,
    required DateTime dateTime,
    required bool isAllDay,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    String formattedText;
    if (isAllDay) {
      formattedText = DateFormat('MMM dd, yyyy').format(dateTime);
    } else {
      formattedText = DateFormat('MMM dd, yyyy\nHH:mm').format(dateTime);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formattedText,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required bool isPrimary,
    required bool isDark,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Container(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFF282454) : Colors.transparent,
          foregroundColor: isPrimary ? Colors.white : (isDark ? Colors.white70 : Colors.black54),
          elevation: isPrimary ? 2 : 0,
          shadowColor: isPrimary ? const Color(0xFF282454).withOpacity(0.3) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isPrimary ? BorderSide.none : BorderSide(
              color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
              width: 1,
            ),
          ),
        ),
        child: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isPrimary ? Colors.white : const Color(0xFF282454),
                  ),
                ),
              )
            : Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Future<void> _onGridViewPressed() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('email') ?? '';
    final password = prefs.getString('password') ?? '';
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomePage(email: email, password: password)),
    );
  }

  String _formatMeetingTime(Map<String, dynamic> meeting) {
    try {
      final startStr = meeting['start'] as String?;
      final stopStr = meeting['stop'] as String?;
      final isAllDay = meeting['allday'] == true;
      
      if (startStr != null && stopStr != null) {
        final start = DateTime.parse(startStr);
        final stop = DateTime.parse(stopStr);
        
        // Calculate the difference in days
        final startDate = DateTime(start.year, start.month, start.day);
        final stopDate = DateTime(stop.year, stop.month, stop.day);
        final daysDifference = stopDate.difference(startDate).inDays;
        
        if (isAllDay) {
          if (daysDifference == 0) {
            // Same day - all day event
            return '${DateFormat('dd MMM yyyy').format(start)} (All Day)';
          } else if (daysDifference == 1) {
            // 2 days
            return '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM yyyy').format(stop)} (2 Days)';
          } else {
            // Multiple days
            return '${DateFormat('dd MMM').format(start)} - ${DateFormat('dd MMM yyyy').format(stop)} (${daysDifference + 1} Days)';
          }
        } else {
          // Regular timed meeting
          if (daysDifference == 0) {
            // Same day - show time
        return '${DateFormat('dd MMM yyyy, HH:mm').format(start)} - ${DateFormat('HH:mm').format(stop)}';
          } else if (daysDifference == 1) {
            // 2 days
            return '${DateFormat('dd MMM, HH:mm').format(start)} - ${DateFormat('dd MMM yyyy, HH:mm').format(stop)} (2 Days)';
          } else {
            // Multiple days
            return '${DateFormat('dd MMM, HH:mm').format(start)} - ${DateFormat('dd MMM yyyy, HH:mm').format(stop)} (${daysDifference + 1} Days)';
          }
        }
      }
    } catch (e) {
      print('Error formatting meeting time: $e');
    }
    return 'Time not available';
  }

  String _cleanHtmlTags(String htmlString) {
    // Remove common HTML tags
    return htmlString
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove all HTML tags
        .replaceAll('&nbsp;', ' ') // Replace &nbsp; with space
        .replaceAll('&amp;', '&') // Replace &amp; with &
        .replaceAll('&lt;', '<') // Replace &lt; with <
        .replaceAll('&gt;', '>') // Replace &gt; with >
        .replaceAll('&quot;', '"') // Replace &quot; with "
        .replaceAll('&#39;', "'") // Replace &#39; with '
        .trim(); // Remove leading/trailing whitespace
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFF282454).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isDark ? Colors.white70 : const Color(0xFF282454),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFF282454),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFF282454).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isDark ? Colors.white70 : const Color(0xFF282454),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$label:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : const Color(0xFF282454),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _getMeetingsForDate(DateTime date) {
    return _meetingHistory.where((meeting) {
      try {
        final startStr = meeting['start'] as String?;
        final stopStr = meeting['stop'] as String?;
        
        if (startStr != null && stopStr != null) {
          final start = DateTime.parse(startStr);
          final stop = DateTime.parse(stopStr);
          
          // Check if the date falls within the meeting period
          final startDate = DateTime(start.year, start.month, start.day);
          final stopDate = DateTime(stop.year, stop.month, stop.day);
          final checkDate = DateTime(date.year, date.month, date.day);
          
          // Meeting is on this date if:
          // 1. The date is the start date, OR
          // 2. The date is between start and stop dates (inclusive)
          return (checkDate.isAtSameMomentAs(startDate)) || 
                 (checkDate.isAfter(startDate) && checkDate.isBefore(stopDate)) ||
                 (checkDate.isAtSameMomentAs(stopDate));
        }
      } catch (e) {
        print('Error parsing meeting date: $e');
      }
      return false;
    }).toList();
  }

  void _showMeetingDetailsPopup(List<Map<String, dynamic>> meetings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.95,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Header with gradient
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF282454),
                      const Color(0xFF282454).withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.event_note,
                        color: Colors.white,
                      size: 24,
                    ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Meeting Details',
                      style: TextStyle(
                              fontSize: 22,
                        fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${meetings.length} meeting${meetings.length > 1 ? 's' : ''} on this date',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.8),
                            ),
                    ),
                  ],
                ),
                    ),
                  ],
                ),
              ),
              
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                
                // Meetings list
                ...meetings.map<Widget>((meeting) => Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2D3748) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                    border: Border.all(
                      color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFF282454).withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                            // Header with meeting subject and action buttons
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFF282454),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(16),
                            topRight: Radius.circular(16),
                          ),
                        ),
                              child: Row(
                                children: [
                                  Expanded(
                        child: Text(
                          meeting['name']?.toString() ?? 'No Subject',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                                    ),
                                  ),
                                  // Action buttons
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Edit button
                                      GestureDetector(
                                        onTap: () => _editMeeting(meeting),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.edit,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Delete button
                                      GestureDetector(
                                        onTap: () => _deleteMeeting(meeting),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                        ),
                      ),
                      
                      // Content
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Time/Date
                            _buildInfoRow(
                              icon: Icons.access_time,
                              label: 'Time/Date',
                              value: _formatMeetingTime(meeting),
                              isDark: isDark,
                            ),
                            
                            // Location
                            if (meeting['location'] != null && meeting['location'].toString().isNotEmpty)
                              _buildInfoRow(
                                icon: Icons.location_on,
                                label: 'Location',
                                value: meeting['location']?.toString() ?? '',
                                isDark: isDark,
                              ),
                            
                            // Description
                            if (meeting['description'] != null && meeting['description'].toString().isNotEmpty)
                              _buildDescriptionRow(
                                icon: Icons.description,
                                label: 'Description',
                                value: _cleanHtmlTags(meeting['description']?.toString() ?? ''),
                                isDark: isDark,
                              ),
                            
                            // Organizer
                            _buildInfoRow(
                              icon: Icons.person,
                              label: 'Organizer',
                              value: 'You',
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )),
                
                const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isMultiDayMeeting(Map<String, dynamic> meeting) {
    try {
      final startStr = meeting['start'] as String?;
      final stopStr = meeting['stop'] as String?;
      
      if (startStr != null && stopStr != null) {
        final start = DateTime.parse(startStr);
        final stop = DateTime.parse(stopStr);
        
        final startDate = DateTime(start.year, start.month, start.day);
        final stopDate = DateTime(stop.year, stop.month, stop.day);
        final daysDifference = stopDate.difference(startDate).inDays;
        
        return daysDifference > 0;
      }
    } catch (e) {
      print('Error checking multi-day meeting: $e');
    }
    return false;
  }

  bool _isMeetingStartDay(Map<String, dynamic> meeting, DateTime date) {
    try {
      final startStr = meeting['start'] as String?;
      
      if (startStr != null) {
        final start = DateTime.parse(startStr);
        final startDate = DateTime(start.year, start.month, start.day);
        final checkDate = DateTime(date.year, date.month, date.day);
        
        return checkDate.isAtSameMomentAs(startDate);
      }
    } catch (e) {
      print('Error checking meeting start day: $e');
    }
    return false;
  }

  bool _isMeetingEndDay(Map<String, dynamic> meeting, DateTime date) {
    try {
      final stopStr = meeting['stop'] as String?;
      
      if (stopStr != null) {
        final stop = DateTime.parse(stopStr);
        final stopDate = DateTime(stop.year, stop.month, stop.day);
        final checkDate = DateTime(date.year, date.month, date.day);
        
        return checkDate.isAtSameMomentAs(stopDate);
      }
    } catch (e) {
      print('Error checking meeting end day: $e');
    }
    return false;
  }

  void _editMeeting(Map<String, dynamic> meeting) {
    // Close the details popup first
    Navigator.of(context).pop();
    
    // Pre-fill the add meeting dialog with existing data
    _showEditMeetingDialog(meeting);
  }

  void _deleteMeeting(Map<String, dynamic> meeting) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.warning,
              color: Colors.red,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'Delete Meeting',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${meeting['name']?.toString() ?? 'this meeting'}"? This action cannot be undone.',
          style: TextStyle(
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
                    onPressed: () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              // Close confirmation dialog
              Navigator.of(context).pop();
              
              // Show better loading indicator
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => Dialog(
                  backgroundColor: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Animated delete icon
                        TweenAnimationBuilder<double>(
                          duration: const Duration(milliseconds: 1000),
                          tween: Tween(begin: 0.0, end: 1.0),
                          builder: (context, value, child) {
                            return Transform.scale(
                              scale: 0.8 + (0.2 * value),
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 30,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Deleting Meeting...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please wait a moment',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Better progress indicator
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
              
              try {
                // Delete meeting from Odoo with timeout
                final success = await OdooService().deleteCalendarEvent(meeting['id'])
                    .timeout(
                      const Duration(seconds: 10),
                      onTimeout: () {
                        print('❌ Delete meeting timeout');
                        return false;
                      },
                    );
                
                // Close loading dialog
                Navigator.of(context).pop();
                
                if (success) {
                  // Close meeting details dialog
                  Navigator.of(context).pop();
                  
                  // Show success message with better animation
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.check_circle,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Meeting "${meeting['name']?.toString() ?? 'Unknown'}" deleted successfully',
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.green,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      duration: const Duration(seconds: 3),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                  
                  // Refresh meetings in background (optimized)
                  _loadMeetingsFromOdoo().catchError((error) {
                    print('❌ Error refreshing meetings after delete: $error');
                  });
                } else {
                  // Show error message
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Failed to delete meeting. Please try again.',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      duration: const Duration(seconds: 4),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                }
              } catch (e) {
                // Close loading dialog
                Navigator.of(context).pop();
                
                // Show error message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.error_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Error: ${e.toString().length > 50 ? e.toString().substring(0, 50) + '...' : e.toString()}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    duration: const Duration(seconds: 4),
                    margin: const EdgeInsets.all(16),
                  ),
                );
              }
            },
                    style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditMeetingDialog(Map<String, dynamic> meeting) {
    final TextEditingController _subjectController = TextEditingController(text: meeting['name']?.toString() ?? '');
    final TextEditingController _locationController = TextEditingController(text: meeting['location']?.toString() ?? '');
    final TextEditingController _urlController = TextEditingController(text: meeting['videocall_location']?.toString() ?? '');
    final TextEditingController _descriptionController = TextEditingController(text: _cleanHtmlTags(meeting['description']?.toString() ?? ''));

    DateTime _startDateTime = DateTime.now();
    DateTime _endDateTime = DateTime.now().add(Duration(hours: 1));
    bool _isAllDay = meeting['allday'] == true;
    String _selectedCategory = 'General';
    String _selectedPriority = 'Medium';
    bool _isLoading = false;

    // Parse existing date/time
    try {
      if (meeting['start'] != null) {
        _startDateTime = DateTime.parse(meeting['start']);
      }
      if (meeting['stop'] != null) {
        _endDateTime = DateTime.parse(meeting['stop']);
      }
    } catch (e) {
      print('Error parsing meeting date/time: $e');
    }

    final List<String> _categories = [
      'General',
      'Business',
      'Personal',
      'Team Meeting',
      'Client Meeting',
      'Training',
      'Conference',
      'Other'
    ];

    final List<String> _priorities = [
      'Low',
      'Medium',
      'High',
      'Urgent'
    ];

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.9,
                ),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                ),
              ],
            ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header with gradient
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange,
                            Colors.orange.withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Edit Meeting',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Update meeting details',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Content (same as add meeting dialog)
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Subject Field
                            _buildModernTextField(
                              controller: _subjectController,
                              label: 'Meeting Subject',
                              hint: 'Enter meeting title',
                              icon: Icons.title,
                              isRequired: true,
                              isDark: isDark,
                              onChanged: (value) => setState(() {}),
                            ),
                            const SizedBox(height: 20),
                            
                            // Category and Priority Row
                            Row(
                              children: [
                                Expanded(
                                  child: _buildDropdownField(
                                    label: 'Category',
                                    value: _selectedCategory,
                                    items: _categories,
                                    icon: Icons.category,
                                    isDark: isDark,
                                    onChanged: (value) => setState(() => _selectedCategory = value!),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildDropdownField(
                                    label: 'Priority',
                                    value: _selectedPriority,
                                    items: _priorities,
                                    icon: Icons.flag,
                                    isDark: isDark,
                                    onChanged: (value) => setState(() => _selectedPriority = value!),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // All Day Toggle
                            _buildToggleCard(
                              title: 'All Day Event',
                              subtitle: 'Meeting spans the entire day',
                              icon: Icons.event,
                              value: _isAllDay,
                              isDark: isDark,
                              onChanged: (value) {
                                setState(() {
                                  _isAllDay = value;
                                  if (_isAllDay) {
                                    _startDateTime = DateTime(_startDateTime.year, _startDateTime.month, _startDateTime.day);
                                    _endDateTime = DateTime(_endDateTime.year, _endDateTime.month, _endDateTime.day);
                                  } else {
                                    _startDateTime = DateTime.now();
                                    _endDateTime = DateTime.now().add(Duration(hours: 1));
                                  }
                                });
                              },
                            ),
                            const SizedBox(height: 20),
                            
                            // Date/Time Selection
                            _buildDateTimeSection(
                              startDateTime: _startDateTime,
                              endDateTime: _endDateTime,
                              isAllDay: _isAllDay,
                              isDark: isDark,
                              onStartChanged: (dateTime) => setState(() => _startDateTime = dateTime),
                              onEndChanged: (dateTime) => setState(() => _endDateTime = dateTime),
                            ),
                            const SizedBox(height: 20),
                            
                            // Location Field
                            _buildModernTextField(
                              controller: _locationController,
                              label: 'Location',
                              hint: 'Meeting room, address, or online',
                              icon: Icons.location_on,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 20),
                            
                            // URL Field
                            _buildModernTextField(
                              controller: _urlController,
                              label: 'Meeting URL',
                              hint: 'https://meet.google.com/...',
                              icon: Icons.link,
                              isDark: isDark,
                              keyboardType: TextInputType.url,
                            ),
                            const SizedBox(height: 20),
                            
                            // Description Field
                            _buildModernTextField(
                              controller: _descriptionController,
                              label: 'Description',
                              hint: 'Add meeting details, agenda, or notes...',
                              icon: Icons.description,
                              isDark: isDark,
                              maxLines: 4,
                            ),
                            const SizedBox(height: 32),
                            
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildActionButton(
                                    text: 'Cancel',
                                    isPrimary: false,
                                    isDark: isDark,
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildActionButton(
                                    text: _isLoading ? 'Updating...' : 'Update Meeting',
                                    isPrimary: true,
                                    isDark: isDark,
                                    isLoading: _isLoading,
                                    onPressed: _isLoading ? null : () async {
                                      // Validate required fields
                                      if (_subjectController.text.trim().isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.warning, color: Colors.white),
                                                const SizedBox(width: 8),
                                                const Text('Please enter a meeting subject'),
                                              ],
                                            ),
                                            backgroundColor: Colors.orange,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        );
                                        return;
                                      }

                                      if (_endDateTime.isBefore(_startDateTime)) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.warning, color: Colors.white),
                                                const SizedBox(width: 8),
                                                const Text('End time must be after start time'),
                                              ],
                                            ),
                                            backgroundColor: Colors.orange,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          ),
                                        );
                                        return;
                                      }

                                      setState(() => _isLoading = true);

                                      try {
                                        // Update meeting in Odoo
                                        final result = await OdooService().updateCalendarEvent(
                                          eventId: meeting['id'],
                                          name: _subjectController.text.trim(),
                                          start: _startDateTime,
                                          stop: _endDateTime,
                                          description: _descriptionController.text.trim(),
                                          location: _locationController.text.trim(),
                                          videocallLocation: _urlController.text.trim(),
                                          allday: _isAllDay,
                                        );

                                        setState(() => _isLoading = false);

                                        if (result != null && result['id'] != null) {
                                          // Refresh meetings from Odoo
                                          await _loadMeetingsFromOdoo();
                                          
                                          // Close edit meeting dialog
                                          Navigator.of(context).pop();
                                          
                                          // Show success message
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.check_circle, color: Colors.white),
                                                  const SizedBox(width: 8),
                                                  Text('Meeting updated successfully!'),
                                                ],
                                              ),
                                              backgroundColor: Colors.green,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              duration: const Duration(seconds: 3),
                                            ),
                                          );
                                        } else {
                                          // Show error message
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.error, color: Colors.white),
                                                  const SizedBox(width: 8),
                                                  const Text('Failed to update meeting. Please try again.'),
                                                ],
                                              ),
                                              backgroundColor: Colors.red,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              duration: const Duration(seconds: 4),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        setState(() => _isLoading = false);
                                        
                                        // Show error message
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.error, color: Colors.white),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text('Error: ${e.toString()}')),
                                              ],
                                            ),
                                            backgroundColor: Colors.red,
                                            behavior: SnackBarBehavior.floating,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            duration: const Duration(seconds: 4),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color mainColor = isDark ? Colors.black : const Color(0xFF282454);
    final DateTime now = DateTime.now();
    final DateTime firstDayOfMonth = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final int daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final int firstWeekday = firstDayOfMonth.weekday;
    final int totalGrid = ((daysInMonth + firstWeekday - 1) / 7).ceil() * 7;

    Widget calendarView = Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white, // Black background in dark mode
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.grey.withOpacity(0.12),
          width: 0.5,
        ),
      ),
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      padding: const EdgeInsets.all(12),
      child: _buildCalendarGrid(
        firstWeekday: firstWeekday,
        daysInMonth: daysInMonth,
        totalGrid: totalGrid,
        now: now,
        mainColor: isDark ? Colors.black : const Color(0xFF282454),
        isDark: isDark,
      ),
    );

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white, // Black background in dark mode
      appBar: AppBar(
        backgroundColor: mainColor,
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
          icon: const Icon(Icons.grid_view, color: Colors.white),
          onPressed: _onGridViewPressed,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.only(left: 2.0),
          child: const Text(
              'Calendar',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
        ),
        centerTitle: false,
        actions: [
          // Month Navigation
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Previous Month Button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                  });
                  _loadMeetingsFromOdoo(); // Reload meetings for new month
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.chevron_left,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Month Text
              Flexible(
                child: Text(
                  DateFormat('MMM yyyy').format(_focusedMonth),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: Colors.white70,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              // Next Month Button
              GestureDetector(
                onTap: () {
                  setState(() {
                    _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                  });
                  _loadMeetingsFromOdoo(); // Reload meetings for new month
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
          // Hamburger Menu
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {
              _scaffoldKey.currentState?.openEndDrawer();
            },
            tooltip: 'Meeting History',
          ),
        ],
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: Container(
            color: isDark ? Colors.black : Colors.white,
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
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Meeting History',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.black : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_isLoadingMeetings)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_meetingHistory.isEmpty)
                    Text('No meetings yet.', style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                  if (_meetingHistory.isNotEmpty)
                    ..._meetingHistory.reversed.map((meeting) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2D3748) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFF282454).withOpacity(0.1),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Meeting Subject
                          Text(
                            meeting['name']?.toString() ?? 'No Subject',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF282454),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          
                          // Time
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 14,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _formatMeetingTime(meeting),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          
                          // Location (if available)
                          if (meeting['location'] != null && meeting['location'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 14,
                                  color: isDark ? Colors.white70 : Colors.black54,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    meeting['location']?.toString() ?? '',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark ? Colors.white70 : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    )),
                  const SizedBox(height: 32),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Add Meeting'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF282454),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: _showAddMeetingDialog,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      endDrawerEnableOpenDragGesture: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              isDark ? 'images/woodb.png' : 'images/wood.png',
              fit: BoxFit.cover,
            ),
          ),
          Column(
            children: [
              // Calendar View - No gap from header
              Expanded(
                child: GestureDetector(
                  onPanStart: (details) {
                    _isSwipeInProgress = false;
                  },
                  onPanUpdate: (details) {
                    if (!_isSwipeInProgress && details.delta.dx.abs() > 20) {
                      _isSwipeInProgress = true;
                      if (details.delta.dx > 20) {
                        // Swipe right - go to previous month
                        setState(() {
                          _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                        });
                        _loadMeetingsFromOdoo(); // Reload meetings for new month
                      } else if (details.delta.dx < -20) {
                        // Swipe left - go to next month
                        setState(() {
                          _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                        });
                        _loadMeetingsFromOdoo(); // Reload meetings for new month
                      }
                    }
                  },
                  onPanEnd: (details) {
                    _isSwipeInProgress = false;
                  },
                  child: SingleChildScrollView(
                    child: calendarView,
                  ),
                ),
              ),
            ],
          ),
          // Add Meeting Button - positioned near previous month button
          Positioned(
            left: 20,
            bottom: 100,
            child: GestureDetector(
              onTap: _showAddMeetingDialog,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFF282454).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 6,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
          ),
          // Month Navigation at Bottom Center (below calendar card)
          Positioned(
            left: 0,
            right: 0,
            bottom: 100,
            child: Center(
              child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Previous Month Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                    });
                    _loadMeetingsFromOdoo(); // Reload meetings for new month
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF282454).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chevron_left,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Month Text
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282454).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 6,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Text(
                    DateFormat('MMM yyyy').format(_focusedMonth),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Next Month Button
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                    });
                    _loadMeetingsFromOdoo(); // Reload meetings for new month
                  },
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF282454).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.chevron_right,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildCalendarGrid({
    required int firstWeekday,
    required int daysInMonth,
    required int totalGrid,
    required DateTime now,
    required Color mainColor,
    required bool isDark,
  }) {
    int numRows = (totalGrid / 7).ceil();
    List<TableRow> rows = [];
    int dayNum = 1 - (firstWeekday - 1);
    Color borderColor = Colors.grey.shade200;
    List<String> days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    // Header nama hari dengan design yang lebih clean
    rows.add(
      TableRow(
        children: List.generate(7, (i) => Container(
          height: 48,
          decoration: BoxDecoration(
            color: isDark ? Colors.black : const Color(0xFFF8FAFC), // Black header in dark mode
            border: Border(
              right: i < 6 ? BorderSide(color: borderColor, width: 0.3) : BorderSide.none,
              bottom: BorderSide(color: borderColor, width: 0.8),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            days[i],
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black54,
              letterSpacing: 0.3,
            ),
          ),
        )),
      ),
    );

    // Baris hari-hari dengan design yang lebih cantik dan lebar
    for (int week = 0; week < numRows; week++) {
      List<Widget> cells = [];
      for (int d = 0; d < 7; d++) {
        bool inMonth = dayNum > 0 && dayNum <= daysInMonth;
        bool isToday = false;
        bool isWeekend = (d == 5 || d == 6); // Saturday or Sunday
        bool isNextMonth = dayNum > daysInMonth;
        bool isPrevMonth = dayNum <= 0;
        
        // Calculate actual day number for display
        int displayDayNum = dayNum;
        if (isNextMonth) {
          displayDayNum = dayNum - daysInMonth;
        } else if (isPrevMonth) {
          // Get previous month's last day
          DateTime prevMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
          int prevMonthDays = DateTime(prevMonth.year, prevMonth.month + 1, 0).day;
          displayDayNum = prevMonthDays + dayNum;
        }
        
        if (inMonth) {
          final today = DateTime.now();
          isToday = dayNum == today.day &&
              _focusedMonth.month == today.month &&
              _focusedMonth.year == today.year;
        }
        
        // Check if this date has meetings
        final dateMeetings = inMonth ? _getMeetingsForDate(DateTime(_focusedMonth.year, _focusedMonth.month, dayNum)) : <Map<String, dynamic>>[];
        final hasMeetings = dateMeetings.isNotEmpty;

        cells.add(
          GestureDetector(
            onTap: inMonth && hasMeetings ? () => _showMeetingDetailsPopup(dateMeetings) : null,
            child: Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: inMonth 
                    ? (isToday && hasMeetings
                        ? null // Use gradient for today with meetings
                        : isToday 
                            ? const Color(0xFFFEE2E2) 
                            : hasMeetings 
                                ? const Color(0xFF059669) // Dark green background for dates with meetings
                                : (isDark ? Colors.white : Colors.white)) // White boxes in both modes
                    : (isDark ? Colors.white : const Color(0xFFF8F9FA)), // White boxes in dark mode, gray in light mode
                gradient: isToday && hasMeetings
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFFFEE2E2), // More prominent red for today
                          const Color(0xFF059669), // Dark green for meetings
                        ],
                        stops: const [0.7, 0.7], // Split at 70% for today, 30% for meetings
                      )
                    : null,
                border: Border(
                  right: d < 6 ? BorderSide(color: borderColor, width: 0.3) : BorderSide.none,
                  bottom: week < numRows - 1 ? BorderSide(color: borderColor, width: 0.3) : BorderSide.none,
                ),
              ),
              alignment: Alignment.topLeft,
              padding: const EdgeInsets.all(10),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Day number
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isToday ? Colors.red : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    displayDayNum.toString(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isToday 
                          ? Colors.white
                          : (inMonth 
                              ? (isWeekend 
                                  ? const Color(0xFF9E9E9E)
                                  : const Color(0xFF2D3748))
                              : const Color(0xFFB0B0B0)),
                    ),
                  ),
                ),
                // Today indicator - positioned right below day number
                if (isToday)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                    decoration: BoxDecoration(
                      color: hasMeetings 
                          ? Colors.red.withOpacity(0.2) // More visible on gradient
                          : Colors.red.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: hasMeetings 
                            ? Colors.red.withOpacity(0.4) // More visible on gradient
                            : Colors.red.withOpacity(0.25), 
                        width: 0.5
                      ),
                    ),
                    child: Text(
                      'Today',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: hasMeetings 
                            ? Colors.red.shade800 // Darker red for better contrast
                            : Colors.red.shade700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                // Space for events/meetings
                Expanded(
                  child: Container(
                    width: double.infinity,
                    child: Column(
                      mainAxisAlignment: isToday ? MainAxisAlignment.end : MainAxisAlignment.center, // Center for normal dates, bottom for today
                      children: [
                        // Meeting indicators
                        if (inMonth && hasMeetings)
                          ...dateMeetings
                              .take(2) // Show max 2 meetings per day
                              .map<Widget>((meeting) {
                                // Check if this is a multi-day meeting
                                final isMultiDay = _isMultiDayMeeting(meeting);
                                final isStartDay = _isMeetingStartDay(meeting, DateTime(_focusedMonth.year, _focusedMonth.month, dayNum));
                                final isEndDay = _isMeetingEndDay(meeting, DateTime(_focusedMonth.year, _focusedMonth.month, dayNum));
                                
                                return Container(
                                margin: const EdgeInsets.only(top: 1),
                                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 0.5),
                                decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(2),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.6), 
                                      width: 0.5
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isMultiDay) ...[
                                        Icon(
                                          isStartDay ? Icons.play_arrow : isEndDay ? Icons.stop : Icons.more_horiz,
                                          size: 4,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 1),
                                      ],
                                      Expanded(
                                child: Text(
                                  meeting['name'] ?? 'Meeting',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w500,
                                            color: isMultiDay 
                                                ? (isStartDay ? Colors.white : isEndDay ? Colors.white : Colors.white)
                                                : Colors.white,
                                    letterSpacing: 0.1,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                        // Show "..." if there are more than 2 meetings
                        if (inMonth && hasMeetings && dateMeetings.length > 2)
                          Container(
                            margin: const EdgeInsets.only(top: 1),
                            child: Text(
                              '...',
                              style: TextStyle(
                                fontSize: 6,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF282454).withOpacity(0.6),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        );
        dayNum++;
      }
      rows.add(TableRow(children: cells));
    }
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white, // Black background in dark mode
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Table(
        border: TableBorder(
          horizontalInside: BorderSide(color: borderColor, width: 0.3),
          verticalInside: BorderSide(color: borderColor, width: 0.3),
          left: BorderSide(color: borderColor, width: 0.3),
          right: BorderSide(color: borderColor, width: 0.3),
          top: BorderSide(color: borderColor, width: 0.3),
          bottom: BorderSide(color: borderColor, width: 0.3),
        ),
        children: rows,
      ),
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
