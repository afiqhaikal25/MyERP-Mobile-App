import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../odoo_service.dart';

class TaskProgressPage extends StatefulWidget {
  final Map<String, dynamic> task;
  final String email;
  final String password;
  final String projectName;

  const TaskProgressPage({
    Key? key,
    required this.task,
    required this.email,
    required this.password,
    required this.projectName,
  }) : super(key: key);

  @override
  _TaskProgressPageState createState() => _TaskProgressPageState();
}

class _TaskProgressPageState extends State<TaskProgressPage> {
  Timer? _countdownTimer;
  Duration _timeRemaining = Duration.zero;
  List<Map<String, dynamic>> _subTasks = [];
  bool _isLoadingSubTasks = false;

  @override
  void initState() {
    super.initState();
    _startCountdownTimer();
    _loadSubTasks();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }


  void _startCountdownTimer() {
    final deadline = widget.task['date_deadline'];
    if (deadline == null || deadline.toString().isEmpty) {
      return; // No deadline set
    }

    try {
      final deadlineDate = DateTime.parse(deadline.toString());
      final now = DateTime.now();
      
      if (deadlineDate.isAfter(now)) {
        _timeRemaining = deadlineDate.difference(now);
        _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            final now = DateTime.now();
            if (deadlineDate.isAfter(now)) {
              _timeRemaining = deadlineDate.difference(now);
            } else {
              _timeRemaining = Duration.zero;
              timer.cancel();
            }
          });
        });
      } else {
        _timeRemaining = Duration.zero; // Deadline has passed
      }
    } catch (e) {
      print("❌ Error parsing deadline: $e");
    }
  }

  Future<void> _loadSubTasks() async {
    setState(() {
      _isLoadingSubTasks = true;
    });

    try {
      print("🔍 DEBUG: Starting subtask fetch for task details page");
      print("🔍 DEBUG: Task ID: ${widget.task['id']}");
      print("🔍 DEBUG: Task Name: ${widget.task['name']}");
      print("🔍 DEBUG: Task Project: ${widget.projectName}");
      print("🔍 DEBUG: Email: ${widget.email}");
      
      final odooService = OdooService();
      
      // Authenticate first
      final userId = await odooService.authenticate(widget.email, widget.password);
      if (userId == null) {
        throw Exception('Authentication failed');
      }
      
      print("🔍 DEBUG: Authentication successful, User ID: $userId");

      // First, let's check if this task has subtasks using the new method
      print("🔍 DEBUG: Checking if task ${widget.task['id']} has subtasks...");
      final tasksWithSubtasks = await odooService.findTasksWithSubtasks(widget.task['project_id'] ?? 0);
      final currentTaskHasSubtasks = tasksWithSubtasks.any((task) => task['id'] == widget.task['id']);
      print("🔍 DEBUG: Current task has subtasks: $currentTaskHasSubtasks");
      
      if (tasksWithSubtasks.isNotEmpty) {
        print("🔍 DEBUG: Found ${tasksWithSubtasks.length} tasks with subtasks in this project:");
        for (var task in tasksWithSubtasks) {
          print("  - Task: ${task['name']} (ID: ${task['id']}) has ${task['child_ids']?.length ?? 0} subtasks");
        }
        
        // If current task doesn't have subtasks, let's test with the first task that has subtasks
        if (!currentTaskHasSubtasks && tasksWithSubtasks.isNotEmpty) {
          final testTask = tasksWithSubtasks.first;
          print("🔍 DEBUG: Testing with task that has subtasks: ${testTask['name']} (ID: ${testTask['id']})");
          final testSubTasks = await odooService.fetchSubTasks(testTask['id']);
          print("🔍 DEBUG: Test task returned ${testSubTasks.length} subtasks");
        }
      } else {
        print("🔍 DEBUG: No tasks with subtasks found in this project");
      }

      // Fetch sub-tasks for this task
      print("🔍 DEBUG: Calling fetchSubTasks for task ID: ${widget.task['id']}");
      final subTasks = await odooService.fetchSubTasks(widget.task['id']);
      
      print("🔍 DEBUG: fetchSubTasks returned ${subTasks.length} subtasks");
      if (subTasks.isNotEmpty) {
        print("🔍 DEBUG: First subtask: ${subTasks.first}");
      }
      
      setState(() {
        _subTasks = subTasks;
      });
      
      // Only log if we actually found subtasks, otherwise it's normal
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
      });
    } finally {
      setState(() {
        _isLoadingSubTasks = false;
      });
    }
  }


  String _formatCountdown(Duration duration) {
    if (duration == Duration.zero) {
      return "Deadline passed";
    }

    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (days > 0) {
      return "${days} hari ${hours}h ${minutes}m";
    } else if (hours > 0) {
      return "${hours}h ${minutes}m ${seconds}s";
    } else if (minutes > 0) {
      return "${minutes}m ${seconds}s";
    } else {
      return "${seconds}s";
    }
  }

  Color _getCountdownColor(Duration duration) {
    if (duration == Duration.zero) {
      return Colors.red; // Deadline passed
    }

    final totalHours = duration.inHours;
    if (totalHours < 24) {
      return Colors.red; // Less than 1 day - urgent
    } else if (totalHours < 72) {
      return Colors.orange; // Less than 3 days - warning
    } else {
      return Colors.green; // More than 3 days - safe
    }
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'No deadline';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatDateTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (e) {
      return dateString;
    }
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

  bool _isRecognizedStage(String? stageName) {
    if (stageName == null || stageName.isEmpty) return false;
    
    final lowerStageName = stageName.toLowerCase();
    return lowerStageName == 'new' ||
           lowerStageName == 'in progress' ||
           lowerStageName == 'in_progress' ||
           lowerStageName == 'done' ||
           lowerStageName == 'completed' ||
           lowerStageName == 'cancelled';
  }

  String _getCategoryLabel([Map<String, dynamic>? task]) {
    final taskData = task ?? widget.task;
    final kanbanState = (taskData['kanban_state'] ?? '').toLowerCase();
    final stageName = (taskData['stage_name'] ?? '').toLowerCase();
    
    // Map to Odoo's three main status categories: Upcoming, Ongoing, Done
    switch (kanbanState) {
      case 'done':
        return 'Done';
      case 'blocked':
        // Blocked tasks are considered as Upcoming (not started)
        return 'Upcoming';
      case 'normal':
      default:
        // For normal state, determine if it's Upcoming or Ongoing
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
          // Default fallback - check if task has progress
          final progress = taskData['progress'] ?? 0;
          if (progress > 0) {
            return 'Ongoing';
          } else {
            return 'Upcoming';
          }
        }
    }
  }

  Color _getCategoryColor([Map<String, dynamic>? task]) {
    final taskData = task ?? widget.task;
    final kanbanState = (taskData['kanban_state'] ?? '').toLowerCase();
    final stageName = (taskData['stage_name'] ?? '').toLowerCase();
    
    // Colors for Odoo's three main status categories
    switch (kanbanState) {
      case 'done':
        return Colors.green; // Done
      case 'blocked':
        return Colors.blue; // Upcoming (blocked tasks)
      case 'normal':
      default:
        // For normal state, use different colors based on stage
        if (stageName.contains('new') || 
            stageName.contains('draft') || 
            stageName.contains('todo') ||
            stageName.contains('pending') ||
            stageName.contains('to do') ||
            stageName.contains('backlog') ||
            stageName.contains('ready')) {
          return Colors.blue; // Upcoming
        } else if (stageName.contains('done') || 
                   stageName.contains('completed') || 
                   stageName.contains('finished') ||
                   stageName.contains('closed')) {
          return Colors.green; // Done
        } else if (stageName.contains('progress') || 
                   stageName.contains('working') || 
                   stageName.contains('active') ||
                   stageName.contains('development') ||
                   stageName.contains('testing') ||
                   stageName.contains('review')) {
          return const Color(0xFFE65100); // Dark orange for Ongoing
        } else {
          // Default fallback - check progress
          final progress = taskData['progress'] ?? 0;
          if (progress > 0) {
            return const Color(0xFFE65100); // Dark orange for Ongoing
          } else {
            return Colors.blue; // Upcoming
          }
        }
    }
  }

  IconData _getCategoryIcon([Map<String, dynamic>? task]) {
    final taskData = task ?? widget.task;
    final kanbanState = (taskData['kanban_state'] ?? '').toLowerCase();
    final stageName = (taskData['stage_name'] ?? '').toLowerCase();
    
    // Icons for Odoo's three main status categories
    switch (kanbanState) {
      case 'done':
        return Icons.check_circle; // Done
      case 'blocked':
        return Icons.schedule; // Upcoming (blocked tasks)
      case 'normal':
      default:
        // For normal state, use different icons based on stage
        if (stageName.contains('new') || 
            stageName.contains('draft') || 
            stageName.contains('todo') ||
            stageName.contains('pending') ||
            stageName.contains('to do') ||
            stageName.contains('backlog') ||
            stageName.contains('ready')) {
          return Icons.schedule; // Upcoming
        } else if (stageName.contains('done') || 
                   stageName.contains('completed') || 
                   stageName.contains('finished') ||
                   stageName.contains('closed')) {
          return Icons.check_circle; // Done
        } else if (stageName.contains('progress') || 
                   stageName.contains('working') || 
                   stageName.contains('active') ||
                   stageName.contains('development') ||
                   stageName.contains('testing') ||
                   stageName.contains('review')) {
          return Icons.play_circle; // Ongoing
        } else {
          // Default fallback - check progress
          final progress = taskData['progress'] ?? 0;
          if (progress > 0) {
            return Icons.play_circle; // Ongoing
          } else {
            return Icons.schedule; // Upcoming
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
                widget.task['name'] ?? 'Task Details',
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
                widget.projectName,
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              
              // Task Details Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: const Color(0xFF282454),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Task Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF282454),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      // Description
                      if (widget.task['description'] != null && widget.task['description'].toString().isNotEmpty) ...[
                        _buildDetailRow('Description', _cleanDescription(widget.task['description'].toString())),
                        const SizedBox(height: 12),
                      ],
                      
                      // Sub-tasks Count
                      _buildDetailRow('Total Subtasks', '${_subTasks.length} subtasks'),
                      const SizedBox(height: 12),
                      
                      // Assigned User
                      if (widget.task['user_name'] != null) ...[
                        _buildDetailRow('Assigned to', widget.task['user_name']),
                        const SizedBox(height: 12),
                      ],
                      
                      // Deadline with Countdown
                      if (widget.task['date_deadline'] != null) ...[
                        _buildDetailRow('Deadline', _formatDate(widget.task['date_deadline'])),
                        const SizedBox(height: 8),
                        // Countdown Details
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _getCountdownColor(_timeRemaining).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getCountdownColor(_timeRemaining).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _timeRemaining == Duration.zero 
                                    ? Icons.warning 
                                    : Icons.access_time,
                                size: 16,
                                color: _getCountdownColor(_timeRemaining),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _timeRemaining == Duration.zero 
                                    ? 'Deadline has passed'
                                    : 'Time remaining: ${_formatCountdown(_timeRemaining)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: _getCountdownColor(_timeRemaining),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      
                      // Stage (only show recognized stages)
                      if (widget.task['stage_name'] != null && _isRecognizedStage(widget.task['stage_name'])) ...[
                        _buildDetailRow('Stage', widget.task['stage_name']),
                        const SizedBox(height: 12),
                      ],
                      
                      // Planned Hours
                      if (widget.task['planned_hours'] != null && widget.task['planned_hours'] > 0) ...[
                        _buildDetailRow('Planned Hours', '${widget.task['planned_hours']} hours'),
                        const SizedBox(height: 12),
                      ],
                      
                      // Effective Hours
                      if (widget.task['effective_hours'] != null && widget.task['effective_hours'] > 0) ...[
                        _buildDetailRow('Effective Hours', '${widget.task['effective_hours']} hours'),
                        const SizedBox(height: 12),
                      ],
                      
                      // Remaining Hours
                      if (widget.task['remaining_hours'] != null && widget.task['remaining_hours'] > 0) ...[
                        _buildDetailRow('Remaining Hours', '${widget.task['remaining_hours']} hours'),
                        const SizedBox(height: 12),
                      ],
                      
                      // Total Hours Spent
                      if (widget.task['total_hours_spent'] != null && widget.task['total_hours_spent'] > 0) ...[
                        _buildDetailRow('Total Hours Spent', '${widget.task['total_hours_spent']} hours'),
                        const SizedBox(height: 12),
                      ],
                      
                      // Created Date
                      if (widget.task['create_date'] != null) ...[
                        _buildDetailRow('Created', _formatDateTime(widget.task['create_date'])),
                        const SizedBox(height: 12),
                      ],
                      
                      // Last Updated
                      if (widget.task['write_date'] != null) ...[
                        _buildDetailRow('Last Updated', _formatDateTime(widget.task['write_date'])),
                      ],
                    ],
                  ),
                ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Sub-Tasks List
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.list_alt,
                              color: const Color(0xFF282454),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Sub-Tasks',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF282454),
                              ),
                            ),
                            const Spacer(),
                            if (_isLoadingSubTasks)
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            else
                              IconButton(
                                icon: const Icon(Icons.refresh),
                                onPressed: _loadSubTasks,
                                tooltip: 'Refresh sub-tasks',
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        
                        if (_subTasks.isEmpty && !_isLoadingSubTasks) ...[
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.task_alt,
                                  size: 48,
                                  color: Colors.grey[400],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No sub-tasks found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'This task doesn\'t have any sub-tasks yet.\nSub-tasks will appear here when they are created.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[500],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ] else if (_subTasks.isNotEmpty) ...[
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _subTasks.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final subTask = _subTasks[index];
                              return _buildSubTaskItem(subTask, isDarkMode);
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.black54,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubTaskItem(Map<String, dynamic> subTask, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-task title
          Text(
            subTask['name'] ?? 'Untitled Sub-Task',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          
          const SizedBox(height: 8),
          
          // Sub-task description
          if (subTask['description'] != null && subTask['description'].toString().isNotEmpty) ...[
            Text(
              _cleanDescription(subTask['description'].toString()),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.grey,
                height: 1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
          ],
          
          // Sub-task status and info
          Row(
            children: [
              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getCategoryColor(subTask),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getCategoryIcon(subTask),
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _getCategoryLabel(subTask),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 8),
              
              // Progress
              if (subTask['progress'] != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white : const Color(0xFF282454),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '${subTask['progress']}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text: '%',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode ? Colors.black : Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              
              // Planned hours
              if (subTask['planned_hours'] != null && subTask['planned_hours'] > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${subTask['planned_hours']}h',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

}
