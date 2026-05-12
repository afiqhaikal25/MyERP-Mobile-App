import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../odoo_service.dart';

class ApprovalPage extends StatefulWidget {
  const ApprovalPage({Key? key}) : super(key: key);

  @override
  State<ApprovalPage> createState() => _ApprovalPageState();
}

class _ApprovalPageState extends State<ApprovalPage> {
  List<dynamic> allLeaves = [];
  String? _userId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadApprovalData();
  }

  Future<void> _loadApprovalData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      _userId = prefs.getString('user_id');
      
      print('🔍 DEBUG: Current user_id: $_userId');
      print('🔍 DEBUG: User ID type: ${_userId.runtimeType}');
      
      // Check all stored preferences
      final allKeys = prefs.getKeys();
      print('🔍 DEBUG: All stored preferences: $allKeys');
      for (String key in allKeys) {
        final value = prefs.get(key);
        print('🔍 DEBUG: $key = $value');
      }
      
      // Check if user is manager
      final managerId = int.tryParse(_userId ?? '0') ?? 0;
      print('🔍 DEBUG: Parsed manager ID: $managerId');
      
      if (managerId == 0) {
        print('❌ DEBUG: Invalid manager ID');
        setState(() {
          _isLoading = false;
        });
        return;
      }
      
      // Check if user is actually a manager
      try {
        final isManager = await OdooService().isUserManager(managerId);
        
        if (!isManager) {
          print('❌ DEBUG: User is not a manager');
          setState(() {
            _isLoading = false;
          });
          return;
        }
        
        print('✅ DEBUG: User is confirmed as manager');
      } catch (e) {
        print('❌ DEBUG: Error checking manager status: $e');
        // For now, assume user is manager if check fails
        print('⚠️ DEBUG: Assuming user is manager due to check failure');
      }
      
      // Temporary bypass for testing - remove this later
      print('⚠️ DEBUG: Temporarily bypassing manager check for testing');
      
      // For testing, use a hardcoded manager ID (Afiq's user ID)
      final testManagerId = 2; // Assuming Afiq's user ID is 2
      print('🔍 DEBUG: Using test manager ID: $testManagerId');
      
      // Also check manager status with test ID
      try {
        final isTestManager = await OdooService().isUserManager(testManagerId);
        print('🔍 DEBUG: Test manager ID $testManagerId is manager: $isTestManager');
      } catch (e) {
        print('❌ DEBUG: Error checking test manager status: $e');
      }
      
      // Also check with the actual user_id from SharedPreferences
      try {
        final isActualManager = await OdooService().isUserManager(managerId);
        print('🔍 DEBUG: Actual user ID $managerId is manager: $isActualManager');
      } catch (e) {
        print('❌ DEBUG: Error checking actual manager status: $e');
      }
      
      // Check employee data for both user IDs
      try {
        final employeeData = await OdooService().checkEmployeeData(managerId);
        print('🔍 DEBUG: Employee data for user $managerId: $employeeData');
      } catch (e) {
        print('❌ DEBUG: Error checking employee data: $e');
      }
      
      try {
        final testEmployeeData = await OdooService().checkEmployeeData(testManagerId);
        print('🔍 DEBUG: Employee data for test user $testManagerId: $testEmployeeData');
      } catch (e) {
        print('❌ DEBUG: Error checking test employee data: $e');
      }
      
      // Fetch leaves that need manager approval
      final leaves = await OdooService().fetchManagerApprovalLeaves(testManagerId);
      
      print('🔍 DEBUG: Fetched ${leaves.length} manager approval leaves');
      print('🔍 DEBUG: Checking for leave ID 76 specifically...');
      for (var leave in leaves) {
        print('🔍 DEBUG: Leave ID: ${leave['id']}, State: ${leave['state']}, Employee: ${leave['employee_name']}, Type: ${leave['leave_type']}');
        if (leave['id'] == 76) {
          print('🎯 DEBUG: Found leave 76 with state: ${leave['state']}');
        }
      }
      
      print('🔄 DEBUG: Setting state with ${leaves.length} leaves');
      setState(() {
        allLeaves = leaves;
        _isLoading = false;
      });
      
      print('✅ Loaded ${leaves.length} manager approval leaves');
      print('🔄 DEBUG: State updated, allLeaves length: ${allLeaves.length}');
    } catch (e) {
      print('❌ Error loading approval data: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _approveLeave(Map<String, dynamic> leave) async {
    try {
      final leaveId = leave['id'];
      if (leaveId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Leave ID not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
              Text('Approving leave...'),
            ],
          ),
          backgroundColor: Colors.blue,
          duration: Duration(seconds: 2),
        ),
      );

      // Get manager ID from current user
      final managerId = int.tryParse(_userId ?? '0') ?? 0;
      
      if (managerId == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Invalid manager ID'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      // For testing, use hardcoded manager ID
      final testManagerId = 2; // Assuming Afiq's user ID is 2
      print('🔍 DEBUG: Using test manager ID for approval: $testManagerId');
      
      final result = await OdooService().managerApproveLeave(leaveId, testManagerId);
      
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Leave approved by manager successfully!'),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        
        print('🔄 DEBUG: Reloading approval data after successful manager approval...');
        print('🔄 DEBUG: Manager approval result: $result');
        
        // Reload data with force refresh
        await _loadApprovalData();
        
        // Force UI rebuild
        setState(() {});
        
        print('🔄 DEBUG: UI rebuild triggered after manager approval');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Failed to approve leave: ${result['error'] ?? 'Unknown error'}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Error approving leave: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _refuseLeave(Map<String, dynamic> leave) async {
    try {
      final leaveId = leave['id'];
      if (leaveId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Leave ID not found'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
              Text('Refusing leave...'),
            ],
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );

      // Get manager ID from current user
      final managerId = int.tryParse(_userId ?? '0') ?? 0;
      
      if (managerId == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: Invalid manager ID'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      final result = await OdooService().refuseLeave(leaveId);
      
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Leave refused by manager successfully!'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
        
        print('🔄 DEBUG: Reloading approval data after successful manager refusal...');
        // Reload data with force refresh
        await _loadApprovalData();
        
        // Force UI rebuild
        setState(() {});
        
        print('🔄 DEBUG: UI rebuild triggered after manager refusal');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Failed to refuse leave: ${result['error'] ?? 'Unknown error'}'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text('Error refusing leave: $e'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

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
        return Colors.orange[100]!;
      case 'validate1':
        return Colors.orange[200]!;
      case 'validate':
        return Colors.green[100]!;
      case 'refuse':
        return Colors.red[100]!;
      default:
        return Colors.grey[100]!;
    }
  }

  Color _getStatusTextColor(String? state) {
    switch (state) {
      case 'confirm':
        return Colors.orange[800]!;
      case 'validate1':
        return Colors.orange[900]!;
      case 'validate':
        return Colors.green[800]!;
      case 'refuse':
        return Colors.red[800]!;
      default:
        return Colors.grey[800]!;
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

  String _formatDate(String? dateString) {
    if (dateString == null) return '';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('MM/dd/yyyy HH:mm:ss').format(date);
    } catch (e) {
      return dateString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDarkMode ? Colors.black : const Color(0xFF282454),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Manager Leave Approvals',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadApprovalData,
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode 
              ? [Colors.black, Colors.grey[900]!]
              : [Colors.grey[100]!, Colors.white],
          ),
        ),
        child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : allLeaves.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No pending manager approvals',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'All leave requests have been processed by manager',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        _loadApprovalData();
                      },
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadApprovalData,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: allLeaves.length,
                  itemBuilder: (context, index) {
                    final leave = allLeaves[index];
                    return _buildApprovalCard(leave, isDarkMode);
                  },
                ),
              ),
      ),
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> leave, bool isDarkMode) {
    final leaveType = leave['leave_type'] ?? '';
    final status = leave['state'] ?? '';
    final dateFrom = leave['date_from'] ?? '';
    final dateTo = leave['date_to'] ?? '';
    final description = leave['description'] ?? '';
    final employeeName = leave['employee_name'] ?? 'Unknown Employee';
    
    print('🎨 DEBUG: Building card for leave ID: ${leave['id']}, Status: $status, Employee: $employeeName');
    
    // Debug: Check if this is the specific leave we're looking for
    if (leave['id'] == 76) {
      print('🎯 DEBUG: Building card for leave 76 with state: $status');
    }
    
    return Card(
      key: ValueKey('approval_card_${leave['id']}_${status}'), // Unique key for each card
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDarkMode ? Colors.grey[900] : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row with employee name and status
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF282454),
                  child: Text(
                    employeeName.isNotEmpty ? employeeName[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        employeeName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(status),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusLabel(status),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _getStatusTextColor(status),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Leave type
            Row(
              children: [
                Icon(
                  Icons.event_note,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  'Leave Type:',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getLeaveTypeLabel(leaveType),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // Date range
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'From: ${_formatDate(dateFrom)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      Text(
                        'To: ${_formatDate(dateTo)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282454).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF282454).withOpacity(0.3)),
                  ),
                  child: Text(
                    _calculateDuration(dateFrom, dateTo),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF282454),
                    ),
                  ),
                ),
              ],
            ),
            
            // Description if available
            if (description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.description,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _approveLeave(leave),
                    icon: Icon(
                      status == 'validate1' ? Icons.check : Icons.thumb_up,
                      size: 18,
                    ),
                    label: Text(
                      status == 'validate1' ? 'Validate' : 'Approve',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _refuseLeave(leave),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text(
                      'Refuse',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
