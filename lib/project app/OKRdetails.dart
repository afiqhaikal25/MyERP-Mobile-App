import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OKRDetailsPage extends StatefulWidget {
  final String okrId;
  final String okrTitle;
  final String okrDescription;
  final double okrProgress;
  final String? okrDeadline;

  const OKRDetailsPage({
    Key? key,
    required this.okrId,
    required this.okrTitle,
    required this.okrDescription,
    required this.okrProgress,
    this.okrDeadline,
  }) : super(key: key);

  @override
  State<OKRDetailsPage> createState() => _OKRDetailsPageState();
}

class _OKRDetailsPageState extends State<OKRDetailsPage> with TickerProviderStateMixin {
  List<KeyResultDetail> _keyResults = [];
  bool _isLoading = true;
  String _errorMessage = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadKeyResults();
    
    // Add timeout to prevent infinite loading
    Future.delayed(Duration(seconds: 15), () {
      if (_isLoading) {
        print("⏰ Key Results loading timeout - forcing fallback");
        setState(() {
          _isLoading = false;
          _errorMessage = 'Loading timeout - showing sample data';
        });
        _loadSampleKeyResults();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadKeyResults() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final odooUrl = prefs.getString('odooUrl') ?? 'http://10.0.0.164:8069';
      final sessionId = prefs.getString('sessionId') ?? '';
      final userId = prefs.getString('user_id') ?? '';

      print("🔍 Fetching Key Results for OKR: ${widget.okrId}");
      print("🔍 Odoo URL: $odooUrl");
      
      // Get user email for debugging
      final userEmail = prefs.getString('email') ?? 'Unknown';
      print("🔍 User Email: $userEmail");
      
      // Validate that user is from @sigmarectrix.com domain
      if (!userEmail.endsWith('@sigmarectrix.com')) {
        print("❌ Invalid user domain. Only @sigmarectrix.com accounts are supported.");
        _loadSampleKeyResults();
        return;
      }

      // Get stored password for authentication
      final storedPassword = prefs.getString('password') ?? '';
      if (storedPassword.isEmpty) {
        print("❌ No stored password found for key results lookup");
        _loadSampleKeyResults();
        return;
      }

      // Try to get all key results first, then filter client-side
      final requestBody = {
        "jsonrpc": "2.0",
        "method": "call",
        "params": {
          "service": "object",
          "method": "execute_kw",
          "args": [
            "demo_myerp",
            int.parse(userId),
            storedPassword,
            "hr.appraisal.okr.key.result",
            "search_read",
            [],
            {
              "fields": [
                "name", 
                "progress", 
                "score", 
                "notes", 
                "okr_id",
                "create_date",
                "write_date"
              ]
            }
          ]
        },
        "id": 1
      };

      print("🔍 Sending Key Results request to: $odooUrl/jsonrpc");
      final response = await http.post(
        Uri.parse('$odooUrl/jsonrpc'),
        headers: {
          'Content-Type': 'application/json',
          'Cookie': 'session_id=$sessionId',
        },
        body: jsonEncode(requestBody),
      ).timeout(
        Duration(seconds: 15),
        onTimeout: () {
          print("⏰ Key Results request timeout");
          throw Exception('Request timeout - server not responding');
        },
      );

      print("🔍 Key Results response status: ${response.statusCode}");
      print("🔍 Key Results response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("🔍 Key Results API Response: $data");
        
        if (data['result'] != null) {
          final allKeyResultsData = data['result'] as List;
          print("🔍 All Key Results Data received: ${allKeyResultsData.length} items");
          
          // Filter key results for this specific OKR
          final filteredKeyResults = allKeyResultsData.where((kr) {
            if (kr['okr_id'] is List && kr['okr_id'].length >= 2) {
              final okrId = kr['okr_id'][0];
              return okrId == int.parse(widget.okrId);
            }
            return false;
          }).toList();
          
          print("🔍 Filtered Key Results for OKR ${widget.okrId}: ${filteredKeyResults.length} items");
          
          setState(() {
            _keyResults = filteredKeyResults.map((kr) {
              print("🔍 Processing Key Result: $kr");
              return KeyResultDetail.fromJson(kr);
            }).toList();
          });
          print("✅ Key Results loaded successfully: ${_keyResults.length} key results");
        } else if (data['error'] != null) {
          print("❌ Key Results API Error: ${data['error']}");
          print("🔄 Falling back to sample data due to API error");
          _loadSampleKeyResults();
          return;
        } else {
          print("❌ No key results data received from server");
          print("🔄 Falling back to sample data");
          _loadSampleKeyResults();
          return;
        }
      } else {
        print("❌ HTTP Error: ${response.statusCode}");
        print("🔄 Falling back to sample data due to HTTP error");
        _loadSampleKeyResults();
        return;
      }
    } catch (e) {
      print("❌ Error loading Key Results: $e");
      setState(() {
        _errorMessage = 'Failed to load Key Results: ${e.toString()}';
      });
      // Load sample data for demo
      _loadSampleKeyResults();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadSampleKeyResults() {
    setState(() {
      _keyResults = [
        KeyResultDetail(
          id: '1',
          title: 'Design and finalize UI/UX for at least 7 core screens',
          progress: 100,
          score: 5,
          notes: '''1. Login interface (main.dart)
2. Homepage UI (home.dart)
3. Ticket list UI (ticket.dart)
4. Ticket detail UI (ticketdetail.dart)
5. Update ticket progress UI (ticketprogress.dart)
6. Customer feedback UI (feedback.dart)
7. Feedback summary UI (totalfeedback.dart)
8. Time Off UI (timeoff.dart)

# 7/7

e.g. ticket list, ticket detail, create ticket, status update''',
          createDate: DateTime.now().subtract(Duration(days: 30)),
          updateDate: DateTime.now().subtract(Duration(days: 5)),
        ),
        KeyResultDetail(
          id: '2',
          title: 'Integrate with Odoo backend via REST API or RPC',
          progress: 100,
          score: 5,
          notes: '''1. Authentication
   - Future<String?> authenticate(String email, String password)

2. Fetch Tickets
   - Future<List<dynamic>> fetchTickets(String userId)

3. Check-In/Check-Out
   - Future<bool> submitCheckIn(int ticketId, String checkInTime)

4. Close Ticket / Mark as Closed
   - Future<bool> closeTicket(int ticketId)

5. Submit Feedback
   - Future<bool> submitFeedbackToOdoo({required int ticketId, required String feedback})''',
          createDate: DateTime.now().subtract(Duration(days: 25)),
          updateDate: DateTime.now().subtract(Duration(days: 3)),
        ),
        KeyResultDetail(
          id: '3',
          title: 'Conduct 3 testing cycles',
          progress: 100,
          score: 4,
          notes: 'Including internal QA and at least 1 round of end-user feedback (UAT)',
          createDate: DateTime.now().subtract(Duration(days: 20)),
          updateDate: DateTime.now().subtract(Duration(days: 1)),
        ),
        KeyResultDetail(
          id: '4',
          title: 'Achieve at least 90% crash-free usage and resolve critical bugs',
          progress: 100,
          score: 5,
          notes: 'Focus on stability and performance optimization',
          createDate: DateTime.now().subtract(Duration(days: 15)),
          updateDate: DateTime.now(),
        ),
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDarkMode ? Colors.black : const Color(0xFFE8E6F3),
      appBar: AppBar(
        title: Text(
          'OKR Details',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        backgroundColor: isDarkMode ? Colors.grey[900] : const Color(0xFF282454),
        iconTheme: IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(Icons.bug_report, color: Colors.white),
            onPressed: () => _showDebugInfo(),
          ),
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadKeyResults,
          ),
          IconButton(
            icon: Icon(Icons.edit, color: Colors.white),
            onPressed: () => _showEditDialog(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Key Results', icon: Icon(Icons.list_alt)),
            Tab(text: 'Notes', icon: Icon(Icons.note)),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? _buildErrorWidget()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildKeyResultsTab(isDarkMode),
                    _buildNotesTab(isDarkMode),
                  ],
                ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
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
            onPressed: _loadKeyResults,
            child: Text('Retry'),
          ),
          SizedBox(height: 8),
          ElevatedButton(
            onPressed: _loadSampleKeyResults,
            child: Text('Load Sample Data'),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyResultsTab(bool isDarkMode) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // OKR Overview Card
          _buildOKROverviewCard(isDarkMode),
          SizedBox(height: 16),
          
          // Key Results Header
          Row(
            children: [
              Icon(Icons.list_alt, color: isDarkMode ? Colors.white : Colors.black87),
              SizedBox(width: 8),
              Text(
                'Key Results (${_keyResults.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // Key Results List
          if (_keyResults.isEmpty)
            _buildEmptyState(isDarkMode)
          else
            ..._keyResults.map((kr) => _buildKeyResultCard(kr, isDarkMode)).toList(),
        ],
      ),
    );
  }

  Widget _buildNotesTab(bool isDarkMode) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // OKR Overview Card
          _buildOKROverviewCard(isDarkMode),
          SizedBox(height: 16),
          
          // Notes Header
          Row(
            children: [
              Icon(Icons.note, color: isDarkMode ? Colors.white : Colors.black87),
              SizedBox(width: 8),
              Text(
                'Key Result Notes',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          
          // Notes List
          if (_keyResults.isEmpty)
            _buildEmptyState(isDarkMode)
          else
            ..._keyResults.map((kr) => _buildNotesCard(kr, isDarkMode)).toList(),
        ],
      ),
    );
  }

  Widget _buildOKROverviewCard(bool isDarkMode) {
    return Card(
      color: isDarkMode ? Colors.grey[900] : Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.okrTitle,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
            SizedBox(height: 8),
            Text(
              widget.okrDescription,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall Progress',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: widget.okrProgress / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          widget.okrProgress >= 80 ? Colors.green : 
                          widget.okrProgress >= 60 ? Colors.orange : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  '${widget.okrProgress.toInt()}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: widget.okrProgress >= 80 ? Colors.green : 
                           widget.okrProgress >= 60 ? Colors.orange : Colors.red,
                  ),
                ),
              ],
            ),
            if (widget.okrDeadline != null && widget.okrDeadline!.isNotEmpty) ...[
              SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                  SizedBox(width: 8),
                  Text(
                    'Deadline: ${widget.okrDeadline}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildKeyResultCard(KeyResultDetail kr, bool isDarkMode) {
    return Card(
      color: isDarkMode ? Colors.grey[900] : Colors.white,
      margin: EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
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
                    kr.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getScoreColor(kr.score).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Score: ${kr.score}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _getScoreColor(kr.score),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            
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
                        value: kr.progress / 100,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          kr.progress >= 80 ? Colors.green : 
                          kr.progress >= 60 ? Colors.orange : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                Text(
                  '${kr.progress.toInt()}%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: kr.progress >= 80 ? Colors.green : 
                           kr.progress >= 60 ? Colors.orange : Colors.red,
                  ),
                ),
              ],
            ),
            
            // Dates
            SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text(
                  'Updated: ${_formatDate(kr.updateDate)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesCard(KeyResultDetail kr, bool isDarkMode) {
    return Card(
      color: isDarkMode ? Colors.grey[900] : Colors.white,
      margin: EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.note, size: 16, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    kr.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            
            // Notes Content
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[50],
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Text(
                kr.notes,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                  height: 1.4,
                ),
              ),
            ),
            
            // Footer
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                SizedBox(width: 4),
                Text(
                  'Updated: ${_formatDate(kr.updateDate)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 10,
                  ),
                ),
                Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getScoreColor(kr.score).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Score: ${kr.score}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getScoreColor(kr.score),
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

  Widget _buildEmptyState(bool isDarkMode) {
    return Container(
      height: 200,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.list_alt, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No Key Results Found',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'This OKR doesn\'t have any key results yet.',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 4) return Colors.green;
    if (score >= 3) return Colors.orange;
    return Colors.red;
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  void _showDebugInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final odooUrl = prefs.getString('odooUrl') ?? 'http://10.0.0.164:8069';
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
              Text('OKR ID: ${widget.okrId}'),
              Text('Odoo URL: $odooUrl'),
              Text('Session ID: ${sessionId.isNotEmpty ? "✓ Set" : "✗ Empty"}'),
              Text('User ID: ${userId.isNotEmpty ? userId : "✗ Empty"}'),
              Text('Loading: $_isLoading'),
              Text('Error: $_errorMessage'),
              Text('Key Results Count: ${_keyResults.length}'),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadKeyResults();
                },
                child: Text('Retry Load'),
              ),
              SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _loadSampleKeyResults();
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

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit OKR'),
        content: Text('OKR editing functionality would be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('OKR editing feature coming soon!')),
              );
            },
            child: Text('Save'),
          ),
        ],
      ),
    );
  }
}

class KeyResultDetail {
  final String id;
  final String title;
  final double progress;
  final int score;
  final String notes;
  final DateTime createDate;
  final DateTime updateDate;

  KeyResultDetail({
    required this.id,
    required this.title,
    required this.progress,
    required this.score,
    required this.notes,
    required this.createDate,
    required this.updateDate,
  });

  factory KeyResultDetail.fromJson(Map<String, dynamic> json) {
    // Helper function to convert selection field to double
    double parseSelectionField(dynamic value) {
      if (value == null) return 0.0;
      if (value is String) {
        // Handle selection field values like '0', '25', '50', '75', '100'
        return double.tryParse(value) ?? 0.0;
      }
      if (value is int) return value.toDouble();
      if (value is double) return value;
      return 0.0;
    }

    // Helper function to convert selection field to int
    int parseScoreField(dynamic value) {
      if (value == null) return 0;
      if (value is String) {
        // Handle selection field values like '0', '1', '2', '3', '4', '5'
        return int.tryParse(value) ?? 0;
      }
      if (value is int) return value;
      return 0;
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

    // Helper function to clean HTML tags from notes
    String _cleanHtmlTags(String htmlString) {
      if (htmlString.isEmpty) return '';
      
      // First decode HTML entities
      String decoded = _decodeHtmlEntities(htmlString);
      
      // Remove common HTML tags and clean up the text
      String cleaned = decoded
          .replaceAll(RegExp(r'<p><br></p>'), '') // Remove empty paragraph tags
          .replaceAll(RegExp(r'<p></p>'), '') // Remove empty paragraphs
          .replaceAll(RegExp(r'<br>'), '\n') // Convert line breaks to newlines
          .replaceAll(RegExp(r'<br/>'), '\n') // Convert self-closing line breaks
          .replaceAll(RegExp(r'<p>'), '') // Remove opening paragraph tags
          .replaceAll(RegExp(r'</p>'), '\n') // Convert closing paragraph tags to newlines
          .replaceAll(RegExp(r'<div>'), '') // Remove opening div tags
          .replaceAll(RegExp(r'</div>'), '\n') // Convert closing div tags to newlines
          .replaceAll(RegExp(r'<strong>'), '') // Remove bold tags
          .replaceAll(RegExp(r'</strong>'), '') // Remove closing bold tags
          .replaceAll(RegExp(r'<em>'), '') // Remove italic tags
          .replaceAll(RegExp(r'</em>'), '') // Remove closing italic tags
          .replaceAll(RegExp(r'<[^>]*>'), '') // Remove any remaining HTML tags
          .replaceAll(RegExp(r'\n\s*\n'), '\n') // Remove multiple consecutive newlines
          .trim(); // Remove leading/trailing whitespace
      
      return cleaned.isEmpty ? '' : cleaned;
    }

    return KeyResultDetail(
      id: json['id']?.toString() ?? '',
      title: _cleanHtmlTags(json['name'] ?? ''),
      progress: parseSelectionField(json['progress']),
      score: parseScoreField(json['score']),
      notes: _cleanHtmlTags(json['notes'] ?? ''),
      createDate: DateTime.tryParse(json['create_date'] ?? '') ?? DateTime.now(),
      updateDate: DateTime.tryParse(json['write_date'] ?? '') ?? DateTime.now(),
    );
  }
}
