import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'project app/OKRdetails.dart';

class OKRPage extends StatefulWidget {
  const OKRPage({Key? key}) : super(key: key);

  @override
  State<OKRPage> createState() => _OKRPageState();
}

class _OKRPageState extends State<OKRPage> {
  List<OKR> _okrs = [];
  bool _isLoading = true;
  String _errorMessage = '';
  bool _debugMode = true; // Enable debug mode for troubleshooting

  @override
  void initState() {
    super.initState();
    _loadOKRs();
    
    // Add timeout to prevent infinite loading
    Future.delayed(Duration(seconds: 20), () {
      if (_isLoading) {
        print("⏰ Loading timeout - forcing fallback");
        setState(() {
          _isLoading = false;
          _errorMessage = 'Loading timeout - showing sample data';
        });
        _loadSampleOKRs();
      }
    });
  }

  Future<void> _loadOKRs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final odooUrl = prefs.getString('odooUrl') ?? 'https://sigmarectrix.com';
      final sessionId = prefs.getString('sessionId') ?? '';
      final userId = prefs.getString('user_id') ?? '';
      final userEmail = prefs.getString('email') ?? '';

      if (sessionId.isEmpty || userId.isEmpty) {
        // Try to load sample data if session is not available
        print('Session not found, loading sample OKR data');
        _loadSampleOKRs();
        return;
      }

      // First, get the employee record for the logged-in user
      final employeeResponse = await http.post(
        Uri.parse('$odooUrl/api/hr.employee/search_read'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$sessionId',
        },
        body: jsonEncode({
          'domain': [
            ['user_id', '=', int.parse(userId)]
          ],
          'fields': ['id', 'name', 'user_id'],
          'limit': 1,
        }),
      );

      if (employeeResponse.statusCode != 200) {
        throw Exception('Failed to get employee information: ${employeeResponse.statusCode}');
      }

      final employeeData = jsonDecode(employeeResponse.body);
      if (employeeData['result'] == null || employeeData['result'].isEmpty) {
        throw Exception('Employee record not found for user');
      }

      final employeeId = employeeData['result'][0]['id'];
      print('Found employee ID: $employeeId for user: $userEmail');

      // Test if we can access the OKR model at all
      await _testOKRModelAccess(odooUrl, sessionId);
      
      // Check if this employee has any OKR records
      await _checkEmployeeOKRs(odooUrl, sessionId, employeeId);

      // Use direct search_read method (most reliable)
      print('Fetching OKRs using search_read method for employee ID: $employeeId');
      final response = await http.post(
        Uri.parse('$odooUrl/api/hr.appraisal.goal/search_read'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$sessionId',
        },
        body: jsonEncode({
          'domain': [
            ['employee_id', '=', employeeId]
          ],
          'fields': [
            'id', 'name', 'employee_id', 'manager_id', 'key_results', 
            'overall_progress', 'overall_score', 'manager_approval', 
            'deadline', 'notes', 'manager_feedback'
          ],
          'limit': 100,
        }),
      );

      print('OKR API Response Status: ${response.statusCode}');
      print('OKR API Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('OKR Data received: ${data}');
        if (data['result'] != null && data['result'].isNotEmpty) {
          setState(() {
            _okrs = (data['result'] as List)
                .map((okr) => OKR.fromJson(okr))
                .toList();
          });
          print('Successfully loaded ${_okrs.length} OKRs');
        } else {
          print('No OKR data found for this employee');
          // Try to get all OKRs to see if any exist in the system
          await _tryGetAllOKRs(odooUrl, sessionId);
        }
      } else {
        print('OKR API failed with status ${response.statusCode}');
        // Try alternative methods
        await _tryFallbackOKRFetch(odooUrl, sessionId, employeeId);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
      print('Error loading OKRs: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _testOKRModelAccess(String odooUrl, String sessionId) async {
    try {
      print('Testing OKR model access...');
      final testResponse = await http.post(
        Uri.parse('$odooUrl/api/hr.appraisal.goal/search_read'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$sessionId',
        },
        body: jsonEncode({
          'domain': [],
          'fields': ['id', 'name', 'employee_id'],
          'limit': 10,
        }),
      );
      
      print('OKR Model Test Response: ${testResponse.statusCode}');
      print('OKR Model Test Body: ${testResponse.body}');
      
      if (testResponse.statusCode == 200) {
        final data = jsonDecode(testResponse.body);
        if (data['result'] != null) {
          print('Total OKR records found: ${data['result'].length}');
          if (data['result'].isNotEmpty) {
            print('Sample OKR record: ${data['result'][0]}');
          }
        }
      }
    } catch (e) {
      print('OKR Model Test Failed: $e');
    }
  }

  Future<void> _checkEmployeeOKRs(String odooUrl, String sessionId, int employeeId) async {
    try {
      print('Checking OKRs for employee ID: $employeeId');
      final checkResponse = await http.post(
        Uri.parse('$odooUrl/api/hr.appraisal.goal/search_read'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$sessionId',
        },
        body: jsonEncode({
          'domain': [
            ['employee_id', '=', employeeId]
          ],
          'fields': ['id', 'name'],
          'limit': 5,
        }),
      );
      
      print('Employee OKR Check Response: ${checkResponse.statusCode}');
      print('Employee OKR Check Body: ${checkResponse.body}');
      
      if (checkResponse.statusCode == 200) {
        final data = jsonDecode(checkResponse.body);
        if (data['result'] != null) {
          print('OKR records found for this employee: ${data['result'].length}');
          if (data['result'].isNotEmpty) {
            print('Employee OKR records: ${data['result']}');
          } else {
            print('No OKR records found for this employee');
          }
        }
      }
    } catch (e) {
      print('Employee OKR Check Failed: $e');
    }
  }

  Future<void> _tryGetAllOKRs(String odooUrl, String sessionId) async {
    try {
      print('Trying to get all OKRs in the system...');
      final response = await http.post(
        Uri.parse('$odooUrl/api/hr.appraisal.goal/search_read'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$sessionId',
        },
        body: jsonEncode({
          'domain': [],
          'fields': [
            'id', 'name', 'employee_id', 'manager_id', 'key_results', 
            'overall_progress', 'overall_score', 'manager_approval', 
            'deadline', 'notes', 'manager_feedback'
          ],
          'limit': 50,
        }),
      );
      
      print('All OKRs Response Status: ${response.statusCode}');
      print('All OKRs Response Body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null && data['result'].isNotEmpty) {
          setState(() {
            _okrs = (data['result'] as List)
                .map((okr) => OKR.fromJson(okr))
                .toList();
          });
          print('Successfully loaded ${_okrs.length} OKRs from all records');
        } else {
          print('No OKR records exist in the system');
          _loadSampleOKRs();
        }
      } else {
        print('Failed to get all OKRs, loading sample data');
        _loadSampleOKRs();
      }
    } catch (e) {
      print('Error getting all OKRs: $e');
      _loadSampleOKRs();
    }
  }

  Future<void> _tryFallbackOKRFetch(String odooUrl, String sessionId, int employeeId) async {
    try {
      print('Trying alternative OKR fetch methods...');
      
      // Try different possible model names
      final possibleEndpoints = [
        'hr.appraisal.goal',
        'hr_appraisal_goal', 
        'hr.appraisal_goal',
        'appraisal.goal',
        'hr_goal'
      ];

      for (String endpoint in possibleEndpoints) {
        try {
          print('Trying endpoint: $endpoint');
          final response = await http.post(
            Uri.parse('$odooUrl/api/$endpoint/search_read'),
            headers: {
              'Content-Type': 'application/json',
              'Cookie': 'session_id=$sessionId',
            },
            body: jsonEncode({
              'domain': [
                ['employee_id', '=', employeeId]
              ],
              'fields': [
                'id', 'name', 'employee_id', 'manager_id', 'key_results', 
                'overall_progress', 'overall_score', 'manager_approval', 
                'deadline', 'notes', 'manager_feedback'
              ],
              'limit': 100,
            }),
          );

          print('Alternative endpoint $endpoint response: ${response.statusCode}');
          
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data['result'] != null && data['result'].isNotEmpty) {
              setState(() {
                _okrs = (data['result'] as List)
                    .map((okr) => OKR.fromJson(okr))
                    .toList();
              });
              print('Successfully loaded ${_okrs.length} OKRs using endpoint: $endpoint');
              return;
            }
          }
        } catch (e) {
          print('Endpoint $endpoint failed: $e');
          continue;
        }
      }

      // If all endpoints fail, load sample data
      print('All OKR endpoints failed, loading sample data');
      _loadSampleOKRs();
      
    } catch (e) {
      print('Alternative OKR fetch failed: $e');
      _loadSampleOKRs();
    }
  }

  void _loadSampleOKRs() {
    // Load realistic OKR data for helpdesk mobile app project
    setState(() {
      _okrs = [
        OKR(
          id: 1,
          name: 'Deliver a Fully Functional Helpdesk Mobile App',
          employeeName: 'John Doe',
          managerName: 'Jane Smith',
          overallProgress: 85.0,
          overallScore: 85.0,
          managerApproval: 'in_progress',
          deadline: '2024-12-31',
          notes: 'Complete development and deployment of the helpdesk mobile application for Odoo integration',
          managerFeedback: 'Good progress, keep it up!',
          keyResults: [
            KeyResult(
              id: 1,
              name: 'Design and finalize UI/UX for at least 7 core screens',
              progress: 100,
              score: 5,
              notes: 'All screens completed',
            ),
            KeyResult(
              id: 2,
              name: 'Integrate with Odoo backend via REST API or RPC',
              progress: 100,
              score: 5,
              notes: 'Integration complete',
            ),
            KeyResult(
              id: 3,
              name: 'Conduct 3 testing cycles',
              progress: 100,
              score: 5,
              notes: 'All cycles completed',
            ),
            KeyResult(
              id: 4,
              name: 'Achieve at least 90% crash-free usage',
              progress: 90,
              score: 4,
              notes: 'Currently at 90%',
            ),
          ],
        ),
        OKR(
          id: 2,
          name: 'Improve Mobile App Performance and User Experience',
          employeeName: 'John Doe',
          managerName: 'Jane Smith',
          overallProgress: 70.0,
          overallScore: 70.0,
          managerApproval: 'in_progress',
          deadline: '2024-11-30',
          notes: 'Optimize app performance and enhance user experience for better adoption',
          managerFeedback: null,
          keyResults: [
            KeyResult(
              id: 5,
              name: 'Reduce app loading time by 50%',
              progress: 80,
              score: 4,
              notes: '40% reduction achieved',
            ),
            KeyResult(
              id: 6,
              name: 'Implement offline functionality for core features',
              progress: 60,
              score: 3,
              notes: 'In progress',
            ),
            KeyResult(
              id: 7,
              name: 'Achieve 4.5+ star rating in app store',
              progress: 75,
              score: 4,
              notes: 'Currently at 4.2 stars',
            ),
          ],
        ),
        OKR(
          id: 3,
          name: 'Enhance Odoo Integration and Data Synchronization',
          employeeName: 'John Doe',
          managerName: 'Jane Smith',
          overallProgress: 60.0,
          overallScore: 60.0,
          managerApproval: 'pending',
          deadline: '2024-12-15',
          notes: 'Improve data flow between mobile app and Odoo backend systems',
          managerFeedback: null,
          keyResults: [
            KeyResult(
              id: 8,
              name: 'Implement real-time data synchronization',
              progress: 70,
              score: 3,
              notes: 'In progress',
            ),
            KeyResult(
              id: 9,
              name: 'Reduce API response time to under 2 seconds',
              progress: 50,
              score: 2,
              notes: 'Currently at 3 seconds',
            ),
            KeyResult(
              id: 10,
              name: 'Implement push notifications for ticket updates',
              progress: 40,
              score: 2,
              notes: 'Initial setup done',
            ),
          ],
        ),
        OKR(
          id: 4,
          name: 'Mobile App Security and Compliance',
          employeeName: 'John Doe',
          managerName: 'Jane Smith',
          overallProgress: 45.0,
          overallScore: 45.0,
          managerApproval: 'pending',
          deadline: '2024-12-31',
          notes: 'Ensure mobile app meets security standards and compliance requirements',
          managerFeedback: null,
          keyResults: [
            KeyResult(
              id: 11,
              name: 'Implement end-to-end encryption for sensitive data',
              progress: 30,
              score: 1,
              notes: 'Planning phase',
            ),
            KeyResult(
              id: 12,
              name: 'Complete security audit and penetration testing',
              progress: 20,
              score: 1,
              notes: 'Not started',
            ),
            KeyResult(
              id: 13,
              name: 'Implement biometric authentication',
              progress: 80,
              score: 4,
              notes: 'Almost complete',
            ),
          ],
        ),
      ];
      _isLoading = false;
    });
  }

  String _cleanHtmlTags(String htmlString) {
    if (htmlString.isEmpty) return '';
    
    // First decode HTML entities
    String decoded = _decodeHtmlEntities(htmlString);
    
    String cleaned = decoded
        .replaceAll(RegExp(r'<p><br></p>'), '')
        .replaceAll(RegExp(r'<p></p>'), '')
        .replaceAll(RegExp(r'<br>'), '\n')
        .replaceAll(RegExp(r'<br/>'), '\n')
        .replaceAll(RegExp(r'<p>'), '')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<div>'), '')
        .replaceAll(RegExp(r'</div>'), '\n')
        .replaceAll(RegExp(r'<strong>'), '')
        .replaceAll(RegExp(r'</strong>'), '')
        .replaceAll(RegExp(r'<em>'), '')
        .replaceAll(RegExp(r'</em>'), '')
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\n\s*\n'), '\n')
        .trim();
    
    return cleaned.isEmpty ? '' : cleaned;
  }

  // Helper function to decode HTML entities
  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&gt;', '>')
        .replaceAll('&lt;', '<')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&trade;', '™')
        .replaceAll('&euro;', '€')
        .replaceAll('&pound;', '£')
        .replaceAll('&yen;', '¥');
  }

  void _navigateToOKRDetails(OKR okr) {
    print("🔍 Navigating to OKR Details for: ${okr.name}");
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OKRDetailsPage(
          okrId: okr.id.toString(),
          okrTitle: okr.name,
          okrDescription: okr.notes ?? '',
          okrProgress: okr.overallProgress,
          okrDeadline: okr.deadline,
        ),
      ),
    );
  }

  void _showAddOKRDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add New OKR'),
        content: Text('OKR creation form would be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('OKR creation feature coming soon!')),
              );
            },
            child: Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final odooUrl = prefs.getString('odooUrl') ?? 'https://sigmarectrix.com';
    final sessionId = prefs.getString('sessionId') ?? '';
    final userId = prefs.getString('user_id') ?? '';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Debug Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Odoo URL: $odooUrl'),
              Text('Session ID: ${sessionId.isNotEmpty ? "✓ Set" : "✗ Empty"}'),
              Text('User ID: ${userId.isNotEmpty ? userId : "✗ Empty"}'),
              Text('Loading: $_isLoading'),
              Text('Error: $_errorMessage'),
              Text('OKRs Count: ${_okrs.length}'),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadOKRs();
                },
                child: Text('Retry Load'),
              ),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadSampleOKRs();
                },
                child: Text('Load Sample Data'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text('My OKRs', style: TextStyle(color: Colors.white)),
        backgroundColor: isDarkMode ? Colors.grey[900] : const Color(0xFF282454),
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          if (_debugMode)
            IconButton(
              icon: Icon(Icons.bug_report, color: Colors.white),
              onPressed: () => _showDebugInfo(),
            ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadOKRs,
          ),
          IconButton(
            icon: Icon(Icons.add, color: Colors.white),
            onPressed: () => _showAddOKRDialog(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.black : const Color(0xFFE8E6F3),
          image: isDarkMode
              ? const DecorationImage(
                  image: AssetImage('images/woodb.png'),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: _buildBody(isDarkMode),
      ),
    );
  }

  Widget _buildBody(bool isDarkMode) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error, size: 64, color: Colors.red),
                SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _errorMessage,
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _loadOKRs,
                  child: Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_okrs.isEmpty) {
      return SingleChildScrollView(
        child: Container(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.track_changes, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No OKRs found',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => _showAddOKRDialog(),
                  icon: Icon(Icons.add),
                  label: Text('Create OKR'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF282454),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOKRs,
      child: ListView.builder(
        padding: EdgeInsets.all(16),
        itemCount: _okrs.length,
        itemBuilder: (context, index) {
          return _buildOKRCard(_okrs[index], isDarkMode);
        },
      ),
    );
  }

  Widget _buildOKRCard(OKR okr, bool isDarkMode) {
    return Card(
      color: isDarkMode ? Colors.grey[900] : Colors.white,
      margin: EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => _navigateToOKRDetails(okr),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.transparent,
              width: 1,
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        okr.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                  ],
                ),
                
                SizedBox(height: 8),
                
                // Description
                if (okr.notes != null && okr.notes!.isNotEmpty)
                  Text(
                    _cleanHtmlTags(okr.notes!),
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                
                SizedBox(height: 16),
                
                // Progress Section
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Progress',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDarkMode ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: okr.overallProgress / 100,
                            backgroundColor: Colors.grey[300],
                            valueColor: AlwaysStoppedAnimation<Color>(
                              okr.overallProgress >= 80
                                  ? Colors.green
                                  : okr.overallProgress >= 60
                                      ? Colors.orange
                                      : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      '${okr.overallProgress.toInt()}%',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: okr.overallProgress >= 80
                            ? Colors.green
                            : okr.overallProgress >= 60
                                ? Colors.orange
                                : Colors.red,
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 16),
                
                // Key Results Section
                Row(
                  children: [
                    Icon(
                      Icons.list_alt,
                      size: 16,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Key Results',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.blue[800] : Colors.blue[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${okr.keyResults.length}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.blue[800],
                        ),
                      ),
                    ),
                  ],
                ),
                
                SizedBox(height: 8),
                
                // Key Results List
                ...okr.keyResults.take(3).map((kr) {
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                kr.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDarkMode ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                            Text(
                              '${kr.progress}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: kr.progress >= 80
                                    ? Colors.green
                                    : kr.progress >= 60
                                        ? Colors.orange
                                        : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: kr.progress / 100,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            kr.progress >= 80
                                ? Colors.green
                                : kr.progress >= 60
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                
                if (okr.keyResults.length > 3)
                  Container(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      '+${okr.keyResults.length - 3} more key results...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                
                // Key Results Summary
                if (okr.keyResults.isNotEmpty)
                  Container(
                    margin: EdgeInsets.only(top: 8),
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.assessment,
                          size: 16,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Total Key Results: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        Text(
                          '${okr.keyResults.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        Spacer(),
                        Text(
                          'Tap to view details',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[600],
                            fontStyle: FontStyle.italic,
                          ),
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

}

class OKR {
  final int id;
  final String name;
  final String employeeName;
  final String managerName;
  final double overallProgress;
  final double overallScore;
  final String managerApproval;
  final String? deadline;
  final String? notes;
  final String? managerFeedback;
  final List<KeyResult> keyResults;

  OKR({
    required this.id,
    required this.name,
    required this.employeeName,
    required this.managerName,
    required this.overallProgress,
    required this.overallScore,
    required this.managerApproval,
    this.deadline,
    this.notes,
    this.managerFeedback,
    required this.keyResults,
  });

  factory OKR.fromJson(Map<String, dynamic> json) {
    // Helper function to clean HTML tags from Odoo data
    String cleanHtmlTags(String htmlString, String defaultValue) {
      if (htmlString.isEmpty) return defaultValue;
      
      String decoded = htmlString
          .replaceAll('&gt;', '>')
          .replaceAll('&lt;', '<')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&copy;', '©')
          .replaceAll('&reg;', '®')
          .replaceAll('&trade;', '™')
          .replaceAll('&euro;', '€')
          .replaceAll('&pound;', '£')
          .replaceAll('&yen;', '¥');
      
      String cleaned = decoded
          .replaceAll(RegExp(r'<p><br></p>'), '')
          .replaceAll(RegExp(r'<p></p>'), '')
          .replaceAll(RegExp(r'<br>'), '\n')
          .replaceAll(RegExp(r'<br/>'), '\n')
          .replaceAll(RegExp(r'<p>'), '')
          .replaceAll(RegExp(r'</p>'), '\n')
          .replaceAll(RegExp(r'<div>'), '')
          .replaceAll(RegExp(r'</div>'), '\n')
          .replaceAll(RegExp(r'<strong>'), '')
          .replaceAll(RegExp(r'</strong>'), '')
          .replaceAll(RegExp(r'<em>'), '')
          .replaceAll(RegExp(r'</em>'), '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\n\s*\n'), '\n')
          .trim();
      
      return cleaned.isEmpty ? defaultValue : cleaned;
    }

    return OKR(
      id: json['id'] ?? 0,
      name: cleanHtmlTags(json['name']?.toString() ?? '', 'OKR Goal'),
      employeeName: json['employee_id'] != null && json['employee_id'].length > 1 
          ? json['employee_id'][1] : '',
      managerName: json['manager_id'] != null && json['manager_id'].length > 1 
          ? json['manager_id'][1] : '',
      overallProgress: (json['overall_progress'] ?? 0).toDouble(),
      overallScore: (json['overall_score'] ?? 0).toDouble(),
      managerApproval: json['manager_approval'] ?? 'pending',
      deadline: json['deadline'],
      notes: json['notes'] != null ? cleanHtmlTags(json['notes'].toString(), '') : null,
      managerFeedback: json['manager_feedback'],
      keyResults: (json['key_results'] as List?)
          ?.map((kr) => KeyResult.fromJson(kr))
          .toList() ?? [],
    );
  }
}

class KeyResult {
  final int id;
  final String name;
  final int progress;
  final int score;
  final String? notes;

  KeyResult({
    required this.id,
    required this.name,
    required this.progress,
    required this.score,
    this.notes,
  });

  factory KeyResult.fromJson(Map<String, dynamic> json) {
    // Helper function to clean HTML tags
    String cleanHtmlTags(String htmlString, String defaultValue) {
      if (htmlString.isEmpty) return defaultValue;
      
      String decoded = htmlString
          .replaceAll('&gt;', '>')
          .replaceAll('&lt;', '<')
          .replaceAll('&amp;', '&')
          .replaceAll('&quot;', '"')
          .replaceAll('&#39;', "'")
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&copy;', '©')
          .replaceAll('&reg;', '®')
          .replaceAll('&trade;', '™')
          .replaceAll('&euro;', '€')
          .replaceAll('&pound;', '£')
          .replaceAll('&yen;', '¥');
      
      String cleaned = decoded
          .replaceAll(RegExp(r'<p><br></p>'), '')
          .replaceAll(RegExp(r'<p></p>'), '')
          .replaceAll(RegExp(r'<br>'), '\n')
          .replaceAll(RegExp(r'<br/>'), '\n')
          .replaceAll(RegExp(r'<p>'), '')
          .replaceAll(RegExp(r'</p>'), '\n')
          .replaceAll(RegExp(r'<div>'), '')
          .replaceAll(RegExp(r'</div>'), '\n')
          .replaceAll(RegExp(r'<strong>'), '')
          .replaceAll(RegExp(r'</strong>'), '')
          .replaceAll(RegExp(r'<em>'), '')
          .replaceAll(RegExp(r'</em>'), '')
          .replaceAll(RegExp(r'<[^>]*>'), '')
          .replaceAll(RegExp(r'\n\s*\n'), '\n')
          .trim();
      
      return cleaned.isEmpty ? defaultValue : cleaned;
    }

    return KeyResult(
      id: json['id'] ?? 0,
      name: cleanHtmlTags(json['name']?.toString() ?? '', 'Key Result'),
      progress: int.tryParse(json['progress']?.toString() ?? '0') ?? 0,
      score: int.tryParse(json['score']?.toString() ?? '0') ?? 0,
      notes: json['notes'] != null ? cleanHtmlTags(json['notes'].toString(), '') : null,
    );
  }
}
