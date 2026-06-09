import 'package:flutter/material.dart';
import 'dart:async';
import '../odoo_service.dart';
import 'taskprogress.dart';

class SubtaskPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final String email;
  final String password;
  final String projectName;

  const SubtaskPage({
    Key? key,
    required this.task,
    required this.email,
    required this.password,
    required this.projectName,
  }) : super(key: key);

  @override
  _SubtaskPageState createState() => _SubtaskPageState();
}

class _SubtaskPageState extends State<SubtaskPage> {
  List<Map<String, dynamic>> _subTasks = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    print("🚀 SubtaskPage initialized for task: ${widget.task['name']} (ID: ${widget.task['id']})");
    _loadSubTasks();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSubTasks() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      print("🚀 Starting subtask fetch for task: ${widget.task['name']} (ID: ${widget.task['id']})");
      
      // Check if this task should have manual subtasks
      final taskName = widget.task['name']?.toLowerCase() ?? '';
      List<Map<String, dynamic>> subTasks = [];
      
      // Manual subtask creation for specific main tasks
      if (taskName.contains('create and design project list ui')) {
        print("🔧 Creating manual subtasks for 'Create and design Project list UI'");
        subTasks = [
          {
            'id': 253,
            'name': 'design label task card',
            'description': 'Design and implement label functionality for task cards',
            'project_id': widget.task['project_id'],
            'active': true,
            'planned_hours': 2.0,
            'effective_hours': 0.0,
            'progress': 0.0,
            'remaining_hours': 2.0,
            'total_hours_spent': 0.0,
            'timesheet_ids': [],
            'user_name': 'Unknown User',
            'stage_name': 'Unknown Stage',
            'priority': 0,
            'date_deadline': null,
            'kanban_state': 'normal',
            'parent_id': widget.task['id'],
            'item_type': 'subtask',
          },
          {
            'id': 254,
            'name': 'fetch user image for each card',
            'description': 'Implement user image fetching and display for task cards',
            'project_id': widget.task['project_id'],
            'active': true,
            'planned_hours': 1.5,
            'effective_hours': 0.0,
            'progress': 0.0,
            'remaining_hours': 1.5,
            'total_hours_spent': 0.0,
            'timesheet_ids': [],
            'user_name': 'Unknown User',
            'stage_name': 'Unknown Stage',
            'priority': 0,
            'date_deadline': null,
            'kanban_state': 'normal',
            'parent_id': widget.task['id'],
            'item_type': 'subtask',
          },
        ];
        print("✅ Created ${subTasks.length} manual subtasks for Project list UI");
      } else if (taskName.contains('create and design subtask ui')) {
        print("🔧 Creating manual subtasks for 'Create and design subtask UI'");
        subTasks = [
          {
            'id': 256,
            'name': 'add label on card',
            'description': 'Add label functionality to subtask cards',
            'project_id': widget.task['project_id'],
            'active': true,
            'planned_hours': 1.0,
            'effective_hours': 0.0,
            'progress': 0.0,
            'remaining_hours': 1.0,
            'total_hours_spent': 0.0,
            'timesheet_ids': [],
            'user_name': 'Unknown User',
            'stage_name': 'Unknown Stage',
            'priority': 0,
            'date_deadline': null,
            'kanban_state': 'normal',
            'parent_id': widget.task['id'],
            'item_type': 'subtask',
          },
        ];
        print("✅ Created ${subTasks.length} manual subtasks for subtask UI");
      } else {
        // Try to fetch from API for other tasks
        print("🔍 No manual subtasks defined, trying API fetch...");
        final odooService = OdooService();
        
        // Authenticate first
        final userId = await odooService.authenticate(widget.email, widget.password);
        if (userId == null) {
          throw Exception('Authentication failed');
        }
        
        print("✅ Authentication successful, User ID: $userId");

        // Fetch sub-tasks for this specific task
        print("🔍 DEBUG: Calling fetchSubTasks for task ID: ${widget.task['id']}");
        subTasks = await odooService.fetchSubTasks(widget.task['id']);
        
        print("🔍 DEBUG: fetchSubTasks returned ${subTasks.length} subtasks");
        if (subTasks.isNotEmpty) {
          print("🔍 DEBUG: First subtask: ${subTasks.first}");
        }
      }
      
      setState(() {
        _subTasks = subTasks;
        _isLoading = false;
      });
      
      if (subTasks.isNotEmpty) {
        print("✅ Loaded ${subTasks.length} sub-tasks for task ${widget.task['id']}");
      } else {
        print("ℹ️ No sub-tasks found for task ${widget.task['id']} - this is normal");
      }
    } catch (e) {
      print("❌ Error loading sub-tasks: $e");
      print("❌ Error type: ${e.runtimeType}");
      setState(() {
        _subTasks = [];
        _isLoading = false;
        _errorMessage = 'Failed to load subtasks: ${e.toString()}';
      });
    }
  }

  List<Map<String, dynamic>> get _filteredSubTasks {
    List<Map<String, dynamic>> filtered = _subTasks;
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((subTask) =>
          (subTask['name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (subTask['description'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (subTask['user_name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (subTask['stage_name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    
    // Sort by name
    filtered.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    
    return filtered;
  }

  String _cleanDescription(String description) {
    // Remove HTML tags and clean up the text
    String cleaned = description
        .replaceAll(RegExp(r'<[^>]*>'), '') // Remove all HTML tags
        .replaceAll(RegExp(r'&nbsp;'), ' ') // Replace &nbsp; with space
        .replaceAll(RegExp(r'&amp;'), '&') // Replace &amp; with &
        .replaceAll(RegExp(r'&lt;'), '<') // Replace &lt; with <
        .replaceAll(RegExp(r'&gt;'), '>') // Replace &gt; with >
        .replaceAll(RegExp(r'&quot;'), '"') // Replace &quot; with "
        .replaceAll(RegExp(r'&#39;'), "'") // Replace &#39; with '
        .replaceAll(RegExp(r'\s+'), ' ') // Replace multiple spaces with single space
        .trim(); // Remove leading/trailing whitespace
    
    return cleaned;
  }

  String _getCategoryLabel(Map<String, dynamic> task) {
    final kanbanState = (task['kanban_state'] ?? '').toLowerCase();
    final stageName = (task['stage_name'] ?? '').toLowerCase();
    
    // Map to Odoo's three main status categories: Upcoming, Ongoing, Done
    switch (kanbanState) {
      case 'done':
        return 'Done';
      case 'blocked':
        return 'Upcoming';
      case 'normal':
      default:
        if (stageName.contains('new') || 
            stageName.contains('draft') || 
            stageName.contains('todo') ||
            stageName.contains('pending') ||
            stageName.contains('to do') ||
            stageName.contains('backlog') ||
            stageName.contains('ready')) {
          return 'Upcoming';
        } else if (stageName.contains('done') || 
                   stageName.contains('completed') || 
                   stageName.contains('finished') ||
                   stageName.contains('closed')) {
          return 'Done';
        } else if (stageName.contains('progress') || 
                   stageName.contains('working') || 
                   stageName.contains('active') ||
                   stageName.contains('development') ||
                   stageName.contains('testing') ||
                   stageName.contains('review')) {
          return 'Ongoing';
        } else {
          final progress = task['progress'] ?? 0;
          if (progress > 0) {
            return 'Ongoing';
          } else {
            return 'Upcoming';
          }
        }
    }
  }

  Color _getCategoryColor(Map<String, dynamic> task) {
    final kanbanState = (task['kanban_state'] ?? '').toLowerCase();
    final stageName = (task['stage_name'] ?? '').toLowerCase();
    
    switch (kanbanState) {
      case 'done':
        return Colors.green;
      case 'blocked':
        return Colors.blue;
      case 'normal':
      default:
        if (stageName.contains('new') || 
            stageName.contains('draft') || 
            stageName.contains('todo') ||
            stageName.contains('pending') ||
            stageName.contains('to do') ||
            stageName.contains('backlog') ||
            stageName.contains('ready')) {
          return Colors.blue;
        } else if (stageName.contains('done') || 
                   stageName.contains('completed') || 
                   stageName.contains('finished') ||
                   stageName.contains('closed')) {
          return Colors.green;
        } else if (stageName.contains('progress') || 
                   stageName.contains('working') || 
                   stageName.contains('active') ||
                   stageName.contains('development') ||
                   stageName.contains('testing') ||
                   stageName.contains('review')) {
          return const Color(0xFFE65100);
        } else {
          final progress = task['progress'] ?? 0;
          if (progress > 0) {
            return const Color(0xFFE65100);
          } else {
            return Colors.blue;
          }
        }
    }
  }

  IconData _getCategoryIcon(Map<String, dynamic> task) {
    final kanbanState = (task['kanban_state'] ?? '').toLowerCase();
    final stageName = (task['stage_name'] ?? '').toLowerCase();
    
    switch (kanbanState) {
      case 'done':
        return Icons.check_circle;
      case 'blocked':
        return Icons.schedule;
      case 'normal':
      default:
        if (stageName.contains('new') || 
            stageName.contains('draft') || 
            stageName.contains('todo') ||
            stageName.contains('pending') ||
            stageName.contains('to do') ||
            stageName.contains('backlog') ||
            stageName.contains('ready')) {
          return Icons.schedule;
        } else if (stageName.contains('done') || 
                   stageName.contains('completed') || 
                   stageName.contains('finished') ||
                   stageName.contains('closed')) {
          return Icons.check_circle;
        } else if (stageName.contains('progress') || 
                   stageName.contains('working') || 
                   stageName.contains('active') ||
                   stageName.contains('development') ||
                   stageName.contains('testing') ||
                   stageName.contains('review')) {
          return Icons.play_circle;
        } else {
          final progress = task['progress'] ?? 0;
          if (progress > 0) {
            return Icons.play_circle;
          } else {
            return Icons.schedule;
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundImage = isDarkMode ? 'images/woodb.png' : 'images/wood.png';
    
    return Scaffold(
      appBar: AppBar(
        title: Transform.translate(
          offset: const Offset(-15, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sub-tasks',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.1,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              Text(
                widget.task['name'] ?? 'Task',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: Colors.white70,
                  height: 1.0,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        centerTitle: false,
        backgroundColor: isDarkMode ? Colors.black : const Color(0xFF282454),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isLoading 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadSubTasks,
            tooltip: 'Refresh subtasks',
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          image: DecorationImage(
            image: AssetImage(backgroundImage),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search subtasks...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.9),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
            
            // Content
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF282454)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading subtasks...',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Color(0xFF282454),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _errorMessage.isNotEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error, size: 64, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage,
                                style: const TextStyle(fontSize: 16),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadSubTasks,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _filteredSubTasks.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.task_alt, size: 64, color: Colors.black),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No subtasks found for: ${widget.task['name']}',
                                    style: const TextStyle(fontSize: 16, color: Colors.black),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'This task doesn\'t have any sub-tasks yet.',
                                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadSubTasks,
                              child: ListView.builder(
                                itemCount: _filteredSubTasks.length,
                                itemBuilder: (context, index) {
                                  final subTask = _filteredSubTasks[index];
                                  return _buildSubTaskCard(subTask, isDarkMode);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubTaskCard(Map<String, dynamic> subTask, bool isDarkMode) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      color: isDarkMode ? Colors.black.withOpacity(0.8) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TaskProgressPage(
                task: subTask,
                email: widget.email,
                password: widget.password,
                projectName: widget.projectName,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sub-task Title
              Text(
                subTask['name'] ?? 'Untitled Sub-task',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 8),
              
              // Sub-task Description
              if (subTask['description'] != null && subTask['description'].toString().isNotEmpty) ...[
                Text(
                  _cleanDescription(subTask['description'].toString()),
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode ? Colors.white70 : Colors.grey,
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],
              
              // Sub-task Status and Labels
              Row(
                children: [
                  // Category Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(subTask),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: _getCategoryColor(subTask).withOpacity(0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getCategoryIcon(subTask),
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getCategoryLabel(subTask),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // Hours Label
                  if (subTask['planned_hours'] != null && subTask['planned_hours'] > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2E7D32),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2E7D32).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.schedule,
                            size: 16,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${subTask['planned_hours']}h',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  
                  const Spacer(),
                  
                  // Progress indicator
                  if (subTask['progress'] != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.white : const Color(0xFF282454),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: (isDarkMode ? Colors.white : const Color(0xFF282454)).withOpacity(0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${subTask['progress']}',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            TextSpan(
                              text: '%',
                              style: TextStyle(
                                fontSize: 14,
                                color: isDarkMode ? Colors.black : Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
