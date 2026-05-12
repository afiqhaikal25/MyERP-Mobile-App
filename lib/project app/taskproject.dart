import 'package:flutter/material.dart';
import 'dart:async';
import '../odoo_service.dart';
import 'subtask.dart';

class ProjectTaskPage extends StatefulWidget {
  final String projectName;
  final int projectId;
  final String email;
  final String password;

  const ProjectTaskPage({
    Key? key,
    required this.projectName,
    required this.projectId,
    required this.email,
    required this.password,
  }) : super(key: key);

  @override
  _ProjectTaskPageState createState() => _ProjectTaskPageState();
}

class _ProjectTaskPageState extends State<ProjectTaskPage> {
  List<Map<String, dynamic>> _tasks = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _searchQuery = '';
  String _sortBy = 'name';
  bool _sortAscending = true;
  String _selectedCategory = 'all'; // New category filter
  final TextEditingController _searchController = TextEditingController();
  DateTime? _lastRefreshTime;
  Timer? _countdownTimer;
  
  // Category options based on Odoo's three main status categories
  final List<Map<String, String>> _categories = [
    {'value': 'all', 'label': 'All Tasks'},
    {'value': 'upcoming', 'label': 'Upcoming'},
    {'value': 'ongoing', 'label': 'Ongoing'},
    {'value': 'done', 'label': 'Done'},
  ];

  @override
  void initState() {
    super.initState();
    print("🚀 ProjectTaskPage initialized for project: ${widget.projectName} (ID: ${widget.projectId})");
    print("🚀 Email: ${widget.email}");
    print("🚀 Password length: ${widget.password.length}");
    
    // Add a small delay to ensure the page is fully loaded
    Future.delayed(Duration(milliseconds: 100), () {
      _fetchTasks();
    });
    
    // Start countdown timer to update task cards every minute
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        print("🔄 Countdown timer triggered - updating task cards");
        setState(() {
          // This will trigger a rebuild of all task cards with updated countdown
        });
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchTasks({bool forceRefresh = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      print("🚀 Starting task fetch process... (Force refresh: $forceRefresh)");
      print("🔍 Project: ${widget.projectName} (ID: ${widget.projectId})");
      print("🔍 Email: ${widget.email}");
      print("🔍 Password: ${widget.password.isNotEmpty ? '***' : 'EMPTY'}");
      
      // Validate input parameters
      if (widget.email.isEmpty || widget.password.isEmpty) {
        throw Exception('Email or password is empty');
      }
      
      if (widget.projectId <= 0) {
        throw Exception('Invalid project ID: ${widget.projectId}');
      }
      
      final odooService = OdooService();
      
      print("🔐 Attempting authentication...");
      final userId = await odooService.authenticate(widget.email, widget.password);
      print("🔍 Authentication result: $userId");
      
      if (userId == null) {
        throw Exception('Authentication failed - invalid credentials or server error');
      }
      
      print("✅ Authentication successful! User ID: $userId");
      print("📋 Fetching tasks for project ID: ${widget.projectId}...");

      // Clear existing tasks if force refresh
      if (forceRefresh) {
        setState(() {
          _tasks = [];
        });
        print("🔄 Force refresh: Cleared existing tasks");
      }

      // Wait a bit to ensure authentication is fully processed
      await Future.delayed(Duration(milliseconds: 500));
      
      // Try to fetch tasks with retry mechanism
      List<Map<String, dynamic>> tasks = [];
      int retryCount = 0;
      const maxRetries = 2; // Reduced retries since we have fallback
      
      while (retryCount < maxRetries) {
        try {
          print("🔄 Attempt ${retryCount + 1} to fetch tasks...");
          tasks = await odooService.fetchTasksFromOdoo(widget.projectId);
          if (tasks.isNotEmpty) {
            print("✅ Successfully fetched ${tasks.length} tasks on attempt ${retryCount + 1}");
            break;
          } else {
            print("⚠️ No tasks returned on attempt ${retryCount + 1}");
            retryCount++;
          }
        } catch (e) {
          retryCount++;
          print("⚠️ Attempt ${retryCount} failed: $e");
          if (retryCount < maxRetries) {
            print("⏳ Waiting before retry...");
            await Future.delayed(Duration(seconds: 1));
          }
        }
      }
      
      if (tasks.isEmpty) {
        print("⚠️ No tasks found after all attempts - this might be normal if project has no tasks");
      }
      print("📊 Raw tasks received: ${tasks.length} tasks");
      
      if (tasks.isNotEmpty) {
        print("📝 First task sample: ${tasks.first}");
        print("📝 Task keys: ${tasks.first.keys.toList()}");
        print("📝 First task deadline: ${tasks.first['date_deadline']}");
        print("📝 First task deadline type: ${tasks.first['date_deadline'].runtimeType}");
      } else {
        print("⚠️ No tasks found for this project");
      }
      
      setState(() {
        _tasks = tasks;
        _isLoading = false;
        _lastRefreshTime = DateTime.now();
      });

      print("✅ Task fetch completed successfully! Total tasks: ${tasks.length}");
      print("🕒 Last refresh time: ${_lastRefreshTime}");
      
      // Log status information for debugging
      if (tasks.isNotEmpty) {
        print("🔍 Task status summary:");
        for (var task in tasks.take(3)) { // Show first 3 tasks
          final status = _getCategoryLabel(task);
          print("  - ${task['name']}: $status (kanban_state: ${task['kanban_state']}, stage: ${task['stage_name']})");
          print("  - Deadline: ${task['date_deadline']}");
          print("  - All task keys: ${task.keys.toList()}");
        }
      }
    } catch (e) {
      print("❌ Error in _fetchTasks: $e");
      print("❌ Error type: ${e.runtimeType}");
      print("❌ Stack trace: ${StackTrace.current}");
      
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load tasks: ${e.toString()}';
      });
    }
  }


  List<Map<String, dynamic>> get _filteredTasks {
    List<Map<String, dynamic>> filtered = _tasks;
    
    print("🔍 Filtering tasks - Original: ${_tasks.length}, Search: '$_searchQuery', Category: '$_selectedCategory'");

    // Apply category filter using improved categorization logic
    if (_selectedCategory != 'all') {
      filtered = filtered.where((task) {
        final categoryLabel = _getCategoryLabel(task);
        return categoryLabel.toLowerCase() == _selectedCategory;
      }).toList();
      print("🔍 After category filter: ${filtered.length} tasks");
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((task) =>
          (task['name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (task['description'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (task['user_name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (task['stage_name'] ?? '').toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
      print("🔍 After search filter: ${filtered.length} tasks");
    }

    // Apply sorting
    filtered.sort((a, b) {
      int comparison = 0;
      switch (_sortBy) {
        case 'name':
          comparison = (a['name'] ?? '').compareTo(b['name'] ?? '');
          break;
        case 'user':
          comparison = (a['user_name'] ?? '').compareTo(b['user_name'] ?? '');
          break;
        case 'stage':
          comparison = (a['stage_name'] ?? '').compareTo(b['stage_name'] ?? '');
          break;
        case 'deadline':
          comparison = (a['date_deadline'] ?? '').compareTo(b['date_deadline'] ?? '');
          break;
        case 'priority':
          comparison = (a['priority'] ?? '').compareTo(b['priority'] ?? '');
          break;
        default:
          comparison = (a['name'] ?? '').compareTo(b['name'] ?? '');
      }
      return _sortAscending ? comparison : -comparison;
    });
    
    print("🔍 After sorting: ${filtered.length} tasks (Sort by: $_sortBy, Ascending: $_sortAscending)");
    return filtered;
  }


  List<Map<String, dynamic>> get _allFilteredItems {
    // Only show main tasks in projecttask.dart
    // Subtasks will be shown in subtask.dart when user taps on a main task
    List<Map<String, dynamic>> mainTasksOnly = [];
    
    print("🔍 DEBUG: Filtering tasks to show only main tasks...");
    print("🔍 DEBUG: Total tasks before filtering: ${_filteredTasks.length}");
    
    // Add only main tasks (filter out subtasks by name pattern)
    for (var task in _filteredTasks) {
      print("🔍 DEBUG: Task: ${task['name']} (ID: ${task['id']})");
      print("🔍 DEBUG: parent_id: ${task['parent_id']} (type: ${task['parent_id'].runtimeType})");
      
      // Check if this task is a subtask by name pattern
      final taskName = (task['name'] ?? '').toLowerCase();
      final isSubtaskByName = (taskName.contains('design') && 
                              (taskName.contains('countdown') || taskName.contains('label'))) ||
                              taskName.contains('fetch user image') ||
                              taskName.contains('add label');
      
      print("🔍 DEBUG: Checking task: ${task['name']}");
      print("🔍 DEBUG: isSubtaskByName: $isSubtaskByName");
      
      if (!isSubtaskByName) {
        task['item_type'] = 'task';
        mainTasksOnly.add(task);
        print("✅ DEBUG: Added as main task: ${task['name']}");
      } else {
        print("❌ DEBUG: Skipped as subtask: ${task['name']} (isSubtaskByName: $isSubtaskByName)");
      }
    }
    
    print("🔍 Main tasks only: ${mainTasksOnly.length} total (filtered from ${_filteredTasks.length} tasks)");
    print("🔍 Subtasks will be shown in subtask.dart when user taps on main task");
    return mainTasksOnly;
  }



  Duration _getTimeRemaining(String? deadline) {
    print("🔍 _getTimeRemaining called with deadline: $deadline");
    
    if (deadline == null || deadline.isEmpty) {
      print("❌ Deadline is null or empty");
      return Duration.zero;
    }
    
    try {
      final deadlineDate = DateTime.parse(deadline);
      final now = DateTime.now();
      
      print("🔍 Deadline date: $deadlineDate");
      print("🔍 Current time: $now");
      
      if (deadlineDate.isAfter(now)) {
        final remaining = deadlineDate.difference(now);
        print("✅ Time remaining: $remaining");
        return remaining;
      } else {
        print("⚠️ Deadline has passed");
        return Duration.zero; // Deadline has passed
      }
    } catch (e) {
      print("❌ Error parsing deadline: $e");
      return Duration.zero;
    }
  }

  String _formatCountdown(Duration duration) {
    if (duration == Duration.zero) {
      return "Overdue";
    }

    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;

    print("🔍 Formatting countdown: days=$days, hours=$hours, minutes=$minutes");

    if (days > 0) {
      return "${days} hari ${hours}h";
    } else if (hours > 0) {
      return "${hours}h ${minutes}m";
    } else if (minutes > 0) {
      return "${minutes}m";
    } else {
      return "<1m";
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

  Widget _buildCountdownDisplay(Map<String, dynamic> task) {
    print("🎯 _buildCountdownDisplay called for task: ${task['name']}");
    print("🎯 Task deadline: ${task['date_deadline']}");
    
    final timeRemaining = _getTimeRemaining(task['date_deadline']);
    final countdownText = timeRemaining == Duration.zero 
        ? 'Deadline passed'
        : 'Due in: ${_formatCountdown(timeRemaining)}';
    
    print("🔍 Task: ${task['name']} - Deadline: ${task['date_deadline']}");
    print("🔍 Time remaining: $timeRemaining");
    print("🔍 Countdown text: $countdownText");
    
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _getCountdownColor(timeRemaining).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _getCountdownColor(timeRemaining).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                timeRemaining == Duration.zero 
                    ? Icons.warning 
                    : Icons.access_time,
                size: 16,
                color: _getCountdownColor(timeRemaining),
              ),
              const SizedBox(width: 6),
              Text(
                countdownText,
                style: TextStyle(
                  fontSize: 14,
                  color: _getCountdownColor(timeRemaining),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
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


  Color _getStageColor(String? stageName) {
    switch (stageName?.toLowerCase()) {
      case 'new':
        return Colors.blue;
      case 'in progress':
      case 'in_progress':
        return Colors.orange;
      case 'done':
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
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

  // Category detection methods based on Odoo's three main status categories
  String _getCategoryLabel(Map<String, dynamic> task) {
    final kanbanState = (task['kanban_state'] ?? '').toLowerCase();
    final stageName = (task['stage_name'] ?? '').toLowerCase();
    
    print("🔍 Task: ${task['name']} - kanban_state: '$kanbanState', stage_name: '$stageName'");
    print("🔍 Raw task data: ${task.toString()}");
    
    // Map to Odoo's three main status categories: Upcoming, Ongoing, Done
    switch (kanbanState) {
      case 'done':
        print("✅ Status: Done (kanban_state: done)");
        return 'Done';
      case 'blocked':
        // Blocked tasks are considered as Upcoming (not started)
        print("✅ Status: Upcoming (kanban_state: blocked)");
        return 'Upcoming';
      case 'normal':
      default:
        // For normal state, determine if it's Upcoming or Ongoing based on stage
        if (stageName.contains('new') || 
            stageName.contains('draft') || 
            stageName.contains('todo') ||
            stageName.contains('pending') ||
            stageName.contains('to do') ||
            stageName.contains('backlog') ||
            stageName.contains('ready')) {
          print("✅ Status: Upcoming (kanban_state: normal, stage: $stageName)");
          return 'Upcoming';
        } else if (stageName.contains('done') || 
                   stageName.contains('completed') || 
                   stageName.contains('finished') ||
                   stageName.contains('closed')) {
          print("✅ Status: Done (kanban_state: normal, stage: $stageName)");
          return 'Done';
        } else if (stageName.contains('progress') || 
                   stageName.contains('working') || 
                   stageName.contains('active') ||
                   stageName.contains('development') ||
                   stageName.contains('testing') ||
                   stageName.contains('review')) {
          print("✅ Status: Ongoing (kanban_state: normal, stage: $stageName)");
          return 'Ongoing';
        } else {
          // Default fallback - if stage is not recognized, check if task has progress
          final progress = task['progress'] ?? 0;
          if (progress > 0) {
            print("✅ Status: Ongoing (kanban_state: normal, progress: $progress)");
            return 'Ongoing';
          } else {
            print("✅ Status: Upcoming (kanban_state: normal, no progress)");
            return 'Upcoming';
          }
        }
    }
  }

  Color _getCategoryColor(Map<String, dynamic> task) {
    final kanbanState = (task['kanban_state'] ?? '').toLowerCase();
    final stageName = (task['stage_name'] ?? '').toLowerCase();
    
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
          final progress = task['progress'] ?? 0;
          if (progress > 0) {
            return const Color(0xFFE65100); // Dark orange for Ongoing
          } else {
            return Colors.blue; // Upcoming
          }
        }
    }
  }

  IconData _getCategoryIcon(Map<String, dynamic> task) {
    final kanbanState = (task['kanban_state'] ?? '').toLowerCase();
    final stageName = (task['stage_name'] ?? '').toLowerCase();
    
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
          final progress = task['progress'] ?? 0;
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
    
    // Debug UI state
    print("🎨 Building UI - Loading: $_isLoading, Error: '$_errorMessage', Tasks: ${_tasks.length}");
    
    return Scaffold(
      appBar: AppBar(
        title: Transform.translate(
          offset: const Offset(-15, 0),
          child: Container(
            width: MediaQuery.of(context).size.width - 140, // More space for buttons
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.projectName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.1,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                // Only show date if project has date information
                // You can add date logic here when needed
                // Text(
                //   '(7/9-9/9)',
                //   style: const TextStyle(
                //     fontSize: 12,
                //     fontWeight: FontWeight.w400,
                //     color: Colors.white70,
                //     height: 1.0,
                //   ),
                //   overflow: TextOverflow.ellipsis,
                //   maxLines: 1,
                // ),
              ],
            ),
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
            onPressed: _isLoading ? null : () {
              _fetchTasks(forceRefresh: true);
            },
            tooltip: 'Force refresh tasks from Odoo',
          ),
        ],
      ),
      body: Container(
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
                  hintText: 'Search main tasks...',
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
            
            // Category filter chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length,
                  itemBuilder: (context, index) {
                    final category = _categories[index];
                    final isSelected = _selectedCategory == category['value'];
                    
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(
                          category['label']!,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedCategory = category['value']!;
                          });
                        },
                        backgroundColor: Colors.white.withOpacity(0.9),
                        selectedColor: const Color(0xFF282454),
                        checkmarkColor: Colors.white,
                        elevation: isSelected ? 2 : 0,
                        shadowColor: isSelected ? const Color(0xFF282454).withOpacity(0.3) : Colors.transparent,
                      ),
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 8),
            
            // Content
            Expanded(
              child: _isLoading
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.1),
                            Colors.white.withOpacity(0.05),
                          ],
                        ),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Animated loading container
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF282454).withOpacity(0.1),
                                    const Color(0xFF282454).withOpacity(0.3),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF282454).withOpacity(0.2),
                                    blurRadius: 20,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF282454)),
                                  strokeWidth: 3,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            
                            // Loading text with animation
                            TweenAnimationBuilder<double>(
                              duration: const Duration(seconds: 2),
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: 0.5 + (0.5 * value),
                                  child: Text(
                                    'Loading tasks...',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF282454),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            
                            // Project name with fade animation
                            TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 1500),
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Text(
                                    widget.projectName,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ),
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            
                            // Animated dots
                            TweenAnimationBuilder<double>(
                              duration: const Duration(seconds: 1),
                              tween: Tween(begin: 0.0, end: 1.0),
                              builder: (context, value, child) {
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: List.generate(3, (index) {
                                    final delay = index * 0.2;
                                    final animationValue = (value - delay).clamp(0.0, 1.0);
                                    return Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Transform.scale(
                                        scale: 0.5 + (0.5 * animationValue),
                                        child: Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF282454).withOpacity(0.3 + (0.7 * animationValue)),
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),
                          ],
                        ),
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
                              const SizedBox(height: 8),
                              Text(
                                'Project: ${widget.projectName} (ID: ${widget.projectId})',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => _fetchTasks(forceRefresh: true),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        )
                      : _allFilteredItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.task_alt, size: 64, color: Colors.black),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No main tasks found for project: ${widget.projectName}',
                                    style: const TextStyle(fontSize: 16, color: Colors.black),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Project ID: ${widget.projectId}',
                                    style: const TextStyle(fontSize: 12, color: Colors.black),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Total main tasks: ${_tasks.where((task) => task['parent_id'] == null || task['parent_id'] == false).length}',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF1A365D)),
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: () async {
                                      await _fetchTasks(forceRefresh: true);
                                    },
                                    child: const Text('Refresh'),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: () async {
                                await _fetchTasks(forceRefresh: true);
                              },
                              child: ListView.builder(
                                itemCount: _allFilteredItems.length,
                                itemBuilder: (context, index) {
                                  final item = _allFilteredItems[index];
                                  // Only show main tasks in projecttask.dart
                                  return _buildTaskCard(item, isDarkMode);
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task, bool isDarkMode) {
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
              builder: (context) => SubtaskPage(
                task: task,
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
              // Task Title
              Text(
                task['name'] ?? 'Untitled Task',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 8),
              
              // Task Description
              if (task['description'] != null && task['description'].toString().isNotEmpty) ...[
                Text(
                  _cleanDescription(task['description'].toString()),
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
              
              
              // Countdown Display (replaces user info)
              Builder(
                builder: (context) {
                  print("🔍 Building countdown for task: ${task['name']}");
                  print("🔍 Task deadline: ${task['date_deadline']}");
                  print("🔍 Deadline is null: ${task['date_deadline'] == null}");
                  print("🔍 Deadline is empty: ${task['date_deadline'].toString().isEmpty}");
                  
                  if (task['date_deadline'] != null && task['date_deadline'].toString().isNotEmpty) {
                    print("✅ Showing countdown for task: ${task['name']}");
                    return _buildCountdownDisplay(task);
                  } else {
                    print("❌ No countdown for task: ${task['name']} - deadline is null or empty");
                    return const SizedBox.shrink();
                  }
                },
              ),
              
              
              // Task Status and Labels
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Primary Status Row (Status + Hours + Progress)
                  Row(
                    children: [
                      // Category Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _getCategoryColor(task),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: _getCategoryColor(task).withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getCategoryIcon(task),
                              size: 16,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _getCategoryLabel(task),
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
                      
                      // Hours Label (Combined)
                      if (task['planned_hours'] != null && task['planned_hours'] > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32), // Dark green
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
                                '${task['planned_hours']}h',
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
                      if (task['progress'] != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDarkMode ? Colors.white : const Color(0xFF282454), // Header color
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
                                  text: '${task['progress']}',
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
                      
                      // Countdown Timer (only show if deadline exists)
                      if (task['date_deadline'] != null && task['date_deadline'].toString().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _getCountdownColor(_getTimeRemaining(task['date_deadline'])),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: _getCountdownColor(_getTimeRemaining(task['date_deadline'])).withOpacity(0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _getTimeRemaining(task['date_deadline']) == Duration.zero 
                                    ? Icons.warning 
                                    : Icons.access_time,
                                size: 14,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatCountdown(_getTimeRemaining(task['date_deadline'])),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Stage Row (if available)
                  if (task['stage_name'] != null && _isRecognizedStage(task['stage_name'])) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStageColor(task['stage_name']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _getStageColor(task['stage_name']).withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.flag,
                            size: 14,
                            color: _getStageColor(task['stage_name']),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            task['stage_name'],
                            style: TextStyle(
                              fontSize: 12,
                              color: _getStageColor(task['stage_name']),
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
        ),
      ),
    );
  }

}
