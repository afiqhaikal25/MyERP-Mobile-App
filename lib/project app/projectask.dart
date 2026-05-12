import 'package:flutter/material.dart';
import '../home.dart';
import '../odoo_service.dart';
import '../task.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProjectData {
  final String name;
  final bool billable;
  final bool timesheets;
  final String emailAlias;
  ProjectData({required this.name, required this.billable, required this.timesheets, required this.emailAlias});
}

class ProjectAskPage extends StatefulWidget {
  const ProjectAskPage({Key? key}) : super(key: key);

  @override
  State<ProjectAskPage> createState() => _ProjectAskPageState();
}

class _ProjectAskPageState extends State<ProjectAskPage> {
  List<Map<String, dynamic>> _projects = [];
  bool _isLoading = true;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

  Future<void> _fetchProjects() async {
    setState(() => _isLoading = true);
    print('🔍 DEBUG: Starting to fetch projects...');
    
    try {
      // Try basic project fetch first (no special permissions required)
      print('🔍 DEBUG: Trying basic project fetch...');
      var projects = await OdooService().fetchProjectsBasic();
      
      // If basic fetch fails, try full fetch
      if (projects.isEmpty) {
        print('🔍 DEBUG: Basic fetch returned empty, trying full fetch...');
        projects = await OdooService().fetchProjectsFromOdoo();
      }
      
      print('🔍 DEBUG: Fetched ${projects.length} projects from Odoo');
      print('🔍 DEBUG: Projects data: $projects');
      
      // If no projects from Odoo, use mock data for testing
      if (projects.isEmpty) {
        print('🔍 DEBUG: No projects from Odoo, using mock data for testing');
        final mockProjects = await OdooService().getMockProjects();
        setState(() {
          _projects = mockProjects;
          _isLoading = false;
        });
        print('🔍 DEBUG: State updated with ${_projects.length} mock projects');
        
        // Show a snackbar to inform user about using mock data
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Using demo data - Check permissions or connection'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Check',
                textColor: Colors.white,
                onPressed: () async {
                  // Show detailed diagnostic dialog
                  final isConnected = await OdooService().testOdooConnection();
                  final groupInfo = await OdooService().checkUserGroups();
                  
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Diagnostic Information'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Connection: ${isConnected ? '✅ OK' : '❌ Failed'}'),
                          const SizedBox(height: 8),
                          Text('Project Access: ${groupInfo['has_project_access'] ? '✅ Yes' : '❌ No'}'),
                          if (groupInfo['groups'] != null) ...[
                            const SizedBox(height: 8),
                            const Text('User Groups:', style: TextStyle(fontWeight: FontWeight.bold)),
                            ...(groupInfo['groups'] as Map<String, dynamic>).entries.map((entry) => 
                              Text('• ${entry.key}: ${entry.value ? '✅' : '❌'}')
                            ),
                          ],
                          const SizedBox(height: 16),
                          const Text(
                            'Solutions:',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (!isConnected) ...[
                            const Text('• Check network connection'),
                            const Text('• Verify server is running'),
                            const Text('• Check firewall settings'),
                          ],
                          if (!groupInfo['has_project_access']) ...[
                            const Text('• Contact administrator'),
                            const Text('• Request project permissions'),
                            const Text('• Add to Project User group'),
                          ],
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          );
        }
      } else {
        setState(() {
          _projects = projects;
          _isLoading = false;
        });
        print('🔍 DEBUG: State updated with ${_projects.length} projects');
        
        // Debug: Log first project data
        if (projects.isNotEmpty) {
          print('🔍 DEBUG: First project data: ${projects.first}');
          print('🔍 DEBUG: Project name: ${projects.first['name']}');
          print('🔍 DEBUG: Project description type: ${projects.first['description'].runtimeType}');
          print('🔍 DEBUG: Project description: ${projects.first['description']}');
        }
      }
    } catch (e) {
      print('❌ DEBUG: Error fetching projects: $e');
      
      // Check if it's an access/permission error
      if (e.toString().contains('AccessError') || 
          e.toString().contains('Access Denied') ||
          e.toString().contains('permission')) {
        
        // Use mock data as fallback for permission issues
        try {
          final mockProjects = await OdooService().getMockProjects();
          setState(() {
            _projects = mockProjects;
            _isLoading = false;
          });
          print('🔍 DEBUG: Using mock data due to permission issues');
          
          // Show informative message about permission issue
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Permission denied - Using demo data. Contact administrator for project access.'),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'Dismiss',
                  textColor: Colors.white,
                  onPressed: () {
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  },
                ),
              ),
            );
          }
        } catch (mockError) {
          print('❌ DEBUG: Error with mock data too: $mockError');
          setState(() {
            _projects = [];
            _isLoading = false;
          });
          
          // Show error message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load projects: Permission denied'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      } else {
        // For other errors, try mock data as fallback
        try {
          final mockProjects = await OdooService().getMockProjects();
          setState(() {
            _projects = mockProjects;
            _isLoading = false;
          });
          print('🔍 DEBUG: Using mock data as fallback for other errors');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Connection issue - Using demo data'),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } catch (mockError) {
          print('❌ DEBUG: Error with mock data too: $mockError');
          setState(() {
            _projects = [];
            _isLoading = false;
          });
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to load projects: $e'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _refreshProjects() async {
    setState(() => _isRefreshing = true);
    await _fetchProjects();
    setState(() => _isRefreshing = false);
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Not set';
    try {
      // Handle different date formats
      String cleanDateString = dateString.toString().trim();
      
      // If it's already a formatted date, return as is
      if (cleanDateString.contains('-') && cleanDateString.length == 10) {
        final date = DateTime.parse(cleanDateString);
        return DateFormat('MMM dd, yyyy').format(date);
      }
      
      // If it's a full datetime string
      if (cleanDateString.contains('T') || cleanDateString.contains(' ')) {
        final date = DateTime.parse(cleanDateString);
        return DateFormat('MMM dd, yyyy').format(date);
      }
      
      // If it's just a string, return as is
      return cleanDateString;
    } catch (e) {
      print('❌ Error formatting date: $dateString - $e');
      return 'Invalid date';
    }
  }

  Color _getStatusColor(String? status) {
    if (status == null) return Colors.blue;
    
    String statusStr = status.toString().toLowerCase();
    switch (statusStr) {
      case 'on_track':
        return Colors.green;
      case 'at_risk':
        return Colors.orange;
      case 'off_track':
        return Colors.red;
      case 'on_hold':
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  String _getStatusText(String? status) {
    if (status == null) return 'Unknown';
    
    String statusStr = status.toString().toLowerCase();
    switch (statusStr) {
      case 'on_track':
        return 'On Track';
      case 'at_risk':
        return 'At Risk';
      case 'off_track':
        return 'Off Track';
      case 'on_hold':
        return 'On Hold';
      default:
        return 'Unknown';
    }
  }

  void _showCreateProjectDialog(BuildContext context) {
    String projectName = '';
    String projectDescription = '';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final double dialogWidth = constraints.maxWidth < 440 ? constraints.maxWidth - 24 : 420;
                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 16,
                  backgroundColor: Colors.white,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: dialogWidth),
                    child: Stack(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple[100],
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(10),
                                      child: Icon(Icons.assignment, color: Colors.deepPurple, size: 32),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        'Create a Project',
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.deepPurple[900],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 28),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple[50],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Project Name', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                      const SizedBox(height: 8),
                                      TextField(
                                        decoration: InputDecoration(
                                          hintText: 'e.g. Office Party',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        ),
                                        onChanged: (v) => projectName = v,
                                      ),
                                      const SizedBox(height: 18),
                                      Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                      const SizedBox(height: 8),
                                      TextField(
                                        decoration: InputDecoration(
                                          hintText: 'Project description (optional)',
                                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                        ),
                                        maxLines: 2,
                                        onChanged: (v) => projectDescription = v,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 32),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.deepPurple,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          elevation: 2,
                                        ),
                                        onPressed: () async {
                                          if (projectName.trim().isEmpty) return;
                                          
                                          // Show loading indicator
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (BuildContext context) {
                                              return const Center(
                                                child: CircularProgressIndicator(),
                                              );
                                            },
                                          );
                                          
                                          try {
                                            final result = await OdooService().createProjectInOdoo(
                                              name: projectName.trim(),
                                              description: projectDescription.trim(),
                                            );
                                            
                                            Navigator.of(context).pop(); // Close loading dialog
                                            
                                            if (result['success'] == true) {
                                              // Refresh the project list
                                              await _fetchProjects();
                                              Navigator.of(context).pop(); // Close create dialog
                                              
                                              // Show success message
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Project "${projectName.trim()}" created successfully!'),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                            } else {
                                              Navigator.of(context).pop(); // Close create dialog
                                              
                                              // Check if it's a permission issue
                                              if (result['permission_issue'] == true) {
                                                // Show permission error dialog
                                                showDialog(
                                                  context: context,
                                                  builder: (context) => AlertDialog(
                                                    title: const Text('Permission Denied'),
                                                    content: Column(
                                                      mainAxisSize: MainAxisSize.min,
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(result['error']),
                                                        const SizedBox(height: 16),
                                                        const Text(
                                                          'To create projects, contact your administrator to:',
                                                          style: TextStyle(fontWeight: FontWeight.bold),
                                                        ),
                                                        const SizedBox(height: 8),
                                                        const Text('• Add you to the "Project User" group'),
                                                        const Text('• Grant create access to project.project model'),
                                                        const Text('• Ensure proper access rights are set'),
                                                      ],
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.of(context).pop(),
                                                        child: const Text('OK'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              } else {
                                                // Show regular error message
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Failed to create project: ${result['error']}'),
                                                    backgroundColor: Colors.red,
                                                  ),
                                                );
                                              }
                                            }
                                          } catch (e) {
                                            Navigator.of(context).pop(); // Close loading dialog
                                            Navigator.of(context).pop(); // Close create dialog
                                            
                                            // Show error message
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Error creating project: $e'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
                                        },
                                        child: const Text('Create'),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.deepPurple, width: 2),
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        child: Text('Discard', style: TextStyle(color: Colors.deepPurple[800])),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: IconButton(
                            icon: Icon(Icons.close, size: 28, color: Colors.grey[600]),
                            splashRadius: 22,
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Close',
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : const Color(0xFFE8E6F3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDarkMode ? Colors.grey[900]! : const Color(0xFF282454),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.home, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => const HomePage(email: '', password: ''),
              ),
            );
          },
        ),
        title: const Text(
          'Projects',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _isRefreshing ? null : _refreshProjects,
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: () {
              _showCreateProjectDialog(context);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _projects.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No projects found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to create your first project',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Add test button for debugging
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Test button pressed');
                          await _fetchProjects();
                        },
                        child: const Text('Test Fetch Projects'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Checking authentication...');
                          final prefs = await SharedPreferences.getInstance();
                          final userId = prefs.getString('user_id');
                          final password = prefs.getString('user_password');
                          print('🔍 DEBUG: User ID: $userId');
                          print('🔍 DEBUG: Password exists: ${password != null}');
                        },
                        child: const Text('Check Auth'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Testing project database...');
                          final result = await OdooService().testProjectDatabase();
                          print('🔍 DEBUG: Database test result: $result');
                          
                          // Show result in a dialog
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Database Test Result'),
                              content: Text(result.toString()),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Test Database'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Creating test project...');
                          final result = await OdooService().createProjectInOdoo(
                            name: 'Test Project ${DateTime.now().millisecondsSinceEpoch}',
                            description: 'This is a test project created for debugging',
                          );
                          print('🔍 DEBUG: Create test project result: $result');
                          
                          if (result['success'] == true) {
                            // Refresh the project list
                            await _fetchProjects();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Test project created successfully!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to create test project: ${result['error']}'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        child: const Text('Create Test Project'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Loading mock data...');
                          setState(() => _isLoading = true);
                          
                          try {
                            final mockProjects = await OdooService().getMockProjects();
                            setState(() {
                              _projects = mockProjects;
                              _isLoading = false;
                            });
                            print('🔍 DEBUG: Loaded ${mockProjects.length} mock projects');
                            
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Loaded ${mockProjects.length} mock projects'),
                                backgroundColor: Colors.blue,
                              ),
                            );
                          } catch (e) {
                            print('❌ DEBUG: Error loading mock data: $e');
                            setState(() => _isLoading = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error loading mock data: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                        child: const Text('Load Mock Data'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Checking user groups...');
                          final groupInfo = await OdooService().checkUserGroups();
                          print('🔍 DEBUG: Group info: $groupInfo');
                          
                          // Show result in a dialog
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('User Groups & Permissions'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('User ID: ${groupInfo['user_id'] ?? 'Unknown'}'),
                                  const SizedBox(height: 8),
                                  Text('Has Project Access: ${groupInfo['has_project_access'] ? 'Yes' : 'No'}'),
                                  if (groupInfo['message'] != null) ...[
                                    const SizedBox(height: 8),
                                    Text('Status: ${groupInfo['message']}'),
                                  ],
                                  if (groupInfo['groups'] != null) ...[
                                    const SizedBox(height: 8),
                                    const Text('Group Memberships:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ...(groupInfo['groups'] as Map<String, dynamic>).entries.map((entry) => 
                                      Text('• ${entry.key}: ${entry.value ? 'Yes' : 'No'}')
                                    ),
                                  ],
                                  if (groupInfo['error'] != null) ...[
                                    const SizedBox(height: 8),
                                    Text('Error: ${groupInfo['error']}', 
                                         style: TextStyle(color: Colors.red)),
                                  ],
                                  const SizedBox(height: 16),
                                  const Text(
                                    'To get project access, administrator needs to:',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text('• Add user to "Project User" group'),
                                  const Text('• Grant access to project.project model'),
                                  const Text('• Check network connectivity'),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Check User Groups'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Testing Odoo connection...');
                          final isConnected = await OdooService().testOdooConnection();
                          
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Connection Test'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Odoo Server: https://myerp.com.my/jsonrpc'),
                                  const SizedBox(height: 8),
                                  Text('Connection Status: ${isConnected ? 'Connected' : 'Failed'}'),
                                  const SizedBox(height: 8),
                                  if (isConnected) ...[
                                    const Text('✅ Server is reachable', style: TextStyle(color: Colors.green)),
                                    const Text('The issue is likely permissions, not connection.'),
                                  ] else ...[
                                    const Text('❌ Cannot reach server', style: TextStyle(color: Colors.red)),
                                    const Text('Check network connection and server status.'),
                                  ],
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Test Connection'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          final instructions = await OdooService().getAdminInstructions();
                          
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Administrator Instructions'),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Share these instructions with your Odoo administrator:',
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      instructions,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Admin Instructions'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Testing permission error simulation...');
                          
                          // Simulate a permission error by throwing an exception
                          try {
                            throw Exception('AccessError: You are not allowed to access this resource');
                          } catch (e) {
                            print('🔍 DEBUG: Simulated error: $e');
                            
                            // Test the error handling logic
                            if (e.toString().contains('AccessError')) {
                              print('🔍 DEBUG: AccessError detected, using mock data');
                              final mockProjects = await OdooService().getMockProjects();
                              setState(() {
                                _projects = mockProjects;
                                _isLoading = false;
                              });
                              
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Permission denied - Using demo data'),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Test Permission Error'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Running quick diagnostic...');
                          
                          // Show loading dialog
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => const AlertDialog(
                              content: Row(
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(width: 16),
                                  Text('Running diagnostic...'),
                                ],
                              ),
                            ),
                          );
                          
                          try {
                            final isConnected = await OdooService().testOdooConnection();
                            final groupInfo = await OdooService().checkUserGroups();
                            
                            Navigator.of(context).pop(); // Close loading dialog
                            
                            // Show diagnostic results
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Quick Diagnostic'),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isConnected ? Icons.check_circle : Icons.error,
                                          color: isConnected ? Colors.green : Colors.red,
                                        ),
                                        const SizedBox(width: 8),
                                        Text('Server Connection: ${isConnected ? 'OK' : 'Failed'}'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(
                                          groupInfo['has_project_access'] ? Icons.check_circle : Icons.error,
                                          color: groupInfo['has_project_access'] ? Colors.green : Colors.red,
                                        ),
                                        const SizedBox(width: 8),
                                        Text('Project Access: ${groupInfo['has_project_access'] ? 'OK' : 'No Access'}'),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    if (!isConnected) ...[
                                      const Text(
                                        'Connection Issues:',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const Text('• Check network connection'),
                                      const Text('• Verify server is running'),
                                      const Text('• Check firewall settings'),
                                    ],
                                    if (!groupInfo['has_project_access']) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Permission Issues:',
                                        style: TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const Text('• Contact administrator'),
                                      const Text('• Request project permissions'),
                                      const Text('• Add to Project User group'),
                                    ],
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          } catch (e) {
                            Navigator.of(context).pop(); // Close loading dialog
                            
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Diagnostic Error'),
                                content: Text('Error running diagnostic: $e'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                        child: const Text('Quick Diagnostic'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Testing basic project fetch...');
                          setState(() => _isLoading = true);
                          
                          try {
                            final projects = await OdooService().fetchProjectsBasic();
                            print('🔍 DEBUG: Basic fetch result: ${projects.length} projects');
                            
                            setState(() {
                              _projects = projects;
                              _isLoading = false;
                            });
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Basic fetch: ${projects.length} projects loaded'),
                                  backgroundColor: projects.isNotEmpty ? Colors.green : Colors.orange,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          } catch (e) {
                            print('❌ DEBUG: Basic fetch error: $e');
                            setState(() => _isLoading = false);
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Basic fetch failed: $e'),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Test Basic Fetch'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          print('🔍 DEBUG: Current projects count: ${_projects.length}');
                          if (_projects.isNotEmpty) {
                            print('🔍 DEBUG: First project: ${_projects.first}');
                            print('🔍 DEBUG: All project names: ${_projects.map((p) => p['name']).toList()}');
                          }
                          
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Debug Information'),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Projects loaded: ${_projects.length}'),
                                  if (_projects.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    const Text('Project names:', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ..._projects.take(3).map((p) => Text('• ${p['name'] ?? 'Unknown'}')),
                                    if (_projects.length > 3) ...[
                                      Text('... and ${_projects.length - 3} more'),
                                    ],
                                  ],
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text('Show Debug Info'),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () async {
                          print('🔍 DEBUG: Loading mock data with new UI design...');
                          setState(() => _isLoading = true);
                          
                          try {
                            final mockProjects = await OdooService().getMockProjects();
                            setState(() {
                              _projects = mockProjects;
                              _isLoading = false;
                            });
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Loaded ${mockProjects.length} mock projects with new design'),
                                  backgroundColor: Colors.green,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          } catch (e) {
                            print('❌ DEBUG: Error loading mock data: $e');
                            setState(() => _isLoading = false);
                            
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Error loading mock data: $e'),
                                  backgroundColor: Colors.red,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          }
                        },
                        child: const Text('Test New UI Design'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshProjects,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _projects.length,
                    itemBuilder: (context, index) {
                      try {
                        final project = _projects[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 6,
                          shadowColor: Colors.black.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  Colors.grey[50]!,
                                ],
                              ),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                // Get current user ID from SharedPreferences
                                final prefs = await SharedPreferences.getInstance();
                                final currentUserId = prefs.getString('user_id') ?? '';
                                
                                // Navigate to task page with project information
                                if (mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TaskPage(
                                        isDarkMode: Theme.of(context).brightness == Brightness.dark,
                                        currentUserId: currentUserId,
                                        selectedProject: project['name'] ?? 'Unknown Project',
                                        projectId: project['id']?.toString() ?? '',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header row with icon, title, and status
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [Colors.deepPurple[400]!, Colors.deepPurple[600]!],
                                            ),
                                            borderRadius: BorderRadius.circular(12),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.deepPurple.withOpacity(0.3),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: Icon(
                                            Icons.extension,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      (project['name'] ?? 'Unnamed Project').toString(),
                                                      style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.bold,
                                                        color: Colors.black87,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  if (project['is_favorite'] == true) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.amber[100],
                                                        borderRadius: BorderRadius.circular(8),
                                                      ),
                                                      child: Icon(Icons.star, color: Colors.amber[700], size: 18),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (project['manager_name'] != null) ...[
                                                const SizedBox(height: 6),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey[200],
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Icon(
                                                        Icons.person,
                                                        size: 12,
                                                        color: Colors.grey[700],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        project['manager_name'].toString(),
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.grey[700],
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                              if (project['manager_email'] != null) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding: const EdgeInsets.all(4),
                                                      decoration: BoxDecoration(
                                                        color: Colors.blue[100],
                                                        borderRadius: BorderRadius.circular(6),
                                                      ),
                                                      child: Icon(
                                                        Icons.email,
                                                        size: 12,
                                                        color: Colors.blue[700],
                                                      ),
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        project['manager_email'].toString(),
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          color: Colors.grey[700],
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // Status badge
                                        if (project['last_update_status'] != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: _getStatusColor(project['last_update_status'].toString()).withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: _getStatusColor(project['last_update_status'].toString()).withOpacity(0.3),
                                                width: 1,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: _getStatusColor(project['last_update_status'].toString()).withOpacity(0.1),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.circle,
                                                  size: 8,
                                                  color: _getStatusColor(project['last_update_status'].toString()),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _getStatusText(project['last_update_status'].toString()),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: _getStatusColor(project['last_update_status'].toString()),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),

                                    if ((project['description'] ?? '').toString().isNotEmpty) ...[
                                      const SizedBox(height: 16),
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[50],
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.grey[200]!),
                                        ),
                                        child: Text(
                                          project['description'].toString(),
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[700],
                                            height: 1.4,
                                          ),
                                          maxLines: 3,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],

                                    const SizedBox(height: 18),
                                    
                                    // Project stats row with improved layout
                                    Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      children: [
                                        _buildStatItem(
                                          Icons.task,
                                          '${project['task_count'] ?? 0}',
                                          'Tasks',
                                        ),
                                        _buildStatItem(
                                          Icons.description,
                                          '${project['doc_count'] ?? 0}',
                                          'Docs',
                                        ),
                                        if ((project['milestone_count'] ?? 0) > 0)
                                          _buildStatItem(
                                            Icons.flag,
                                            '${project['milestone_count'] ?? 0}',
                                            'Milestones',
                                          ),
                                      ],
                                    ),

                                    const SizedBox(height: 16),

                                    // Project dates with improved layout
                                    if (project['date_start'] != null || project['date'] != null) ...[
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [Colors.blue[50]!, Colors.blue[100]!],
                                          ),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: Colors.blue[200]!),
                                        ),
                                        child: Row(
                                          children: [
                                            if (project['date_start'] != null) ...[
                                              Expanded(
                                                child: _buildDateItem(
                                                  Icons.play_arrow,
                                                  'Started',
                                                  _formatDate(project['date_start'].toString()),
                                                ),
                                              ),
                                            ],
                                            if (project['date_start'] != null && project['date'] != null) ...[
                                              Container(
                                                width: 1,
                                                height: 40,
                                                color: Colors.blue[300],
                                              ),
                                            ],
                                            if (project['date'] != null) ...[
                                              Expanded(
                                                child: _buildDateItem(
                                                  Icons.schedule,
                                                  'Due',
                                                  _formatDate(project['date'].toString()),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      } catch (e) {
                        print('❌ Error rendering project at index $index: $e');
                        print('❌ Project data: ${_projects[index]}');
                        
                        // Return a fallback card
                        return Card(
                          margin: const EdgeInsets.only(bottom: 16),
                          elevation: 4,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: Colors.red[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        Icons.error,
                                        color: Colors.red[700],
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Error Loading Project',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Error: $e',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey[700]),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateItem(IconData icon, String label, String date) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 14, color: Colors.blue[700]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
