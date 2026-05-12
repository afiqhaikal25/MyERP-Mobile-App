import 'package:flutter/material.dart';
import 'dart:convert';
import '../odoo_service.dart';
import 'taskproject.dart';

class ProjectPage extends StatefulWidget {
  final String email;
  final String password;

  const ProjectPage({
    Key? key,
    required this.email,
    required this.password,
  }) : super(key: key);

  @override
  _ProjectPageState createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  List<Project> _projects = [];
  bool _isLoading = true;
  String _errorMessage = '';
  String _searchQuery = '';
  String _selectedCategory = 'all';
  final TextEditingController _searchController = TextEditingController();
  
  // Category options
  final List<Map<String, String>> _categories = [
    {'value': 'all', 'label': 'All Projects'},
    {'value': 'planned', 'label': 'Planned Projects'},
    {'value': 'todo', 'label': 'To Do'},
    {'value': 'in_progress', 'label': 'In Progress'},
    {'value': 'done', 'label': 'Done'},
    {'value': 'cancelled', 'label': 'Cancelled'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchProjects();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchProjects() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      print("🔍 Fetching projects...");
      
      final odooService = OdooService();
      final userId = await odooService.authenticate(widget.email, widget.password);
      
      if (userId == null) {
        throw Exception('Authentication failed');
      }

      print("✅ Authenticated successfully, fetching projects for user ID: $userId...");

      final projects = await odooService.fetchProjects();
      
      setState(() {
        _projects = projects;
        _isLoading = false;
      });

      print("✅ Projects fetched successfully: ${projects.length} projects assigned to current user");
    } catch (e) {
      print("❌ Error fetching projects: $e");
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load projects: ${e.toString()}';
      });
    }
  }

  List<Project> get _filteredProjects {
    List<Project> filtered = _projects;

    // Apply category filter
    if (_selectedCategory != 'all') {
      filtered = filtered.where((project) {
        final stageName = project.stageName?.toLowerCase() ?? '';
        switch (_selectedCategory) {
          case 'planned':
            return stageName.contains('planned') || stageName.contains('draft') || stageName.contains('new');
          case 'todo':
            return stageName.contains('todo') || stageName.contains('to do') || stageName.contains('pending');
          case 'in_progress':
            return stageName.contains('progress') || stageName.contains('working') || stageName.contains('active');
          case 'done':
            return stageName.contains('done') || stageName.contains('completed') || stageName.contains('finished');
          case 'cancelled':
            return stageName.contains('cancelled') || stageName.contains('canceled') || stageName.contains('closed');
          default:
            return true;
        }
      }).toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((project) =>
          project.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (project.partnerName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (project.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }

    // Sort by name
    filtered.sort((a, b) => a.name.compareTo(b.name));

    return filtered;
  }

  void _showCategoryFilter() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter by Category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: _categories.map((category) {
              return RadioListTile<String>(
                title: Text(category['label']!),
                value: category['value']!,
                groupValue: _selectedCategory,
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value!;
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showAddProjectDialog() {
    final TextEditingController _nameController = TextEditingController();
    final TextEditingController _emailController = TextEditingController();
    bool _isBillable = true;
    bool _isTimesheets = true;
    bool _isLoading = false;

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
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.bug_report,
                            color: const Color(0xFF282454),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Create a Project',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF282454),
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close,
                              color: Colors.grey[600],
                              size: 20,
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
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
                            // Project Name
                            _buildSimpleTextField(
                              controller: _nameController,
                              label: 'Project Name',
                              hint: 'e.g. Office Party',
                              isDark: isDark,
                            ),
                            const SizedBox(height: 20),
                            
                            // Checkboxes
                            Column(
                              children: [
                                _buildCheckbox(
                                  value: _isBillable,
                                  label: 'Billable',
                                  isDark: isDark,
                                  onChanged: (value) => setState(() => _isBillable = value!),
                                ),
                                const SizedBox(height: 12),
                                _buildCheckbox(
                                  value: _isTimesheets,
                                  label: 'Timesheets',
                                  isDark: isDark,
                                  onChanged: (value) => setState(() => _isTimesheets = value!),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // Email Task Creation
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Create tasks by sending an email to',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildSimpleTextField(
                                        controller: _emailController,
                                        label: '',
                                        hint: 'e.g. office-party',
                                        isDark: isDark,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                      decoration: BoxDecoration(
                                        color: isDark ? Colors.grey[800] : Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                                        ),
                                      ),
                                      child: Text(
                                        '@sigmarectrix.com',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: isDark ? Colors.white70 : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 32),
                            
                            // Action Buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildSimpleButton(
                                    text: 'Discard',
                                    isPrimary: false,
                                    isDark: isDark,
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _buildSimpleButton(
                                    text: _isLoading ? 'Creating...' : 'Create',
                                    isPrimary: true,
                                    isDark: isDark,
                                    isLoading: _isLoading,
                                    onPressed: _isLoading ? null : () async {
                                      if (_nameController.text.trim().isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Row(
                                              children: [
                                                Icon(Icons.warning, color: Colors.white),
                                                const SizedBox(width: 8),
                                                const Text('Please enter a project name'),
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
                                        // Ensure user is authenticated first
                                        final odooService = OdooService();
                                        final userId = await odooService.authenticate(widget.email, widget.password);
                                        
                                        if (userId == null) {
                                          if (mounted) {
                                            setState(() => _isLoading = false);
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Row(
                                                  children: [
                                                    Icon(Icons.error, color: Colors.white),
                                                    const SizedBox(width: 8),
                                                    const Text('Authentication failed. Please try again.'),
                                                  ],
                                                ),
                                                backgroundColor: Colors.red,
                                                behavior: SnackBarBehavior.floating,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                                duration: const Duration(seconds: 4),
                                              ),
                                            );
                                          }
                                          return;
                                        }

                                        // Create project in Odoo
                                        final result = await odooService.createProject(
                                          name: _nameController.text.trim(),
                                          description: '',
                                          partnerName: null,
                                          dateStart: null,
                                          dateEnd: null,
                                          stageName: 'New',
                                        );

                                        if (mounted) {
                                          setState(() => _isLoading = false);
                                        }

                                        if (result != null && result['id'] != null) {
                                          // Close dialog first for better UX
                                          Navigator.of(context).pop();
                                          
                                          // Show success message
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.check_circle, color: Colors.white),
                                                  const SizedBox(width: 8),
                                                  Text('Project "${_nameController.text}" created successfully!'),
                                                ],
                                              ),
                                              backgroundColor: Colors.green,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              duration: const Duration(seconds: 2),
                                            ),
                                          );
                                          
                                          // Refresh projects list in background
                                          _fetchProjects();
                                        } else {
                                          // Show error message
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.error, color: Colors.white),
                                                  const SizedBox(width: 8),
                                                  const Text('Failed to create project. Please try again.'),
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
                                        if (mounted) {
                                          setState(() => _isLoading = false);
                                          
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Row(
                                                children: [
                                                  Icon(Icons.error, color: Colors.white),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      'Error: ${e.toString().length > 100 ? e.toString().substring(0, 100) + '...' : e.toString()}',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              backgroundColor: Colors.red,
                                              behavior: SnackBarBehavior.floating,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              duration: const Duration(seconds: 4),
                                            ),
                                          );
                                        }
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

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool isRequired = false,
    int maxLines = 1,
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

  Widget _buildDateField({
    required String label,
    required DateTime date,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : const Color(0xFF282454),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
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
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: isDark ? Colors.white70 : const Color(0xFF282454),
                ),
                const SizedBox(width: 8),
                Text(
                  '${date.day}/${date.month}/${date.year}',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildButton({
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

  Widget _buildSimpleTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: controller,
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
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                width: 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
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

  Widget _buildCheckbox({
    required bool value,
    required String label,
    required bool isDark,
    required Function(bool?) onChanged,
  }) {
    return Row(
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF282454),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleButton({
    required String text,
    required bool isPrimary,
    required bool isDark,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Container(
      height: 44,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? const Color(0xFF282454) : Colors.white,
          foregroundColor: isPrimary ? Colors.white : Colors.black87,
          elevation: isPrimary ? 2 : 0,
          shadowColor: isPrimary ? const Color(0xFF282454).withOpacity(0.3) : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: isPrimary ? BorderSide.none : BorderSide(
              color: Colors.grey[300]!,
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
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final backgroundImage = isDarkMode ? 'images/woodb.png' : 'images/wood.png';
    
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const SizedBox(width: 0),
            Transform.translate(
              offset: const Offset(-15, 0),
              child: const Text(
                'Projects',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        backgroundColor: isDarkMode ? Colors.black : const Color(0xFF282454),
        foregroundColor: Colors.white,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: IconButton(
            icon: const Icon(Icons.grid_view, color: Colors.white),
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showAddProjectDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchProjects,
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
                hintText: 'Search projects...',
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
                          color: isSelected ? Colors.white : (isDarkMode ? Colors.white70 : Colors.black87),
                          fontSize: 12,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedCategory = category['value']!;
                        });
                      },
                      backgroundColor: isDarkMode ? Colors.black.withOpacity(0.8) : Colors.white.withOpacity(0.9),
                      selectedColor: isDarkMode ? Colors.black : const Color(0xFF282454),
                      checkmarkColor: Colors.white,
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
                ? const Center(child: CircularProgressIndicator())
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
                              onPressed: _fetchProjects,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _filteredProjects.isEmpty
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.folder_open, size: 64, color: Colors.grey),
                                SizedBox(height: 16),
                                Text(
                                  'No projects assigned to you',
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _fetchProjects,
                            child: ListView.builder(
                              itemCount: _filteredProjects.length,
                              itemBuilder: (context, index) {
                                final project = _filteredProjects[index];
                                return _buildProjectCard(project, isDarkMode);
                              },
                            ),
                          ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildProjectCard(Project project, bool isDarkMode) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      color: isDarkMode ? Colors.black.withOpacity(0.8) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () {
          print("🎯 Project tapped: ${project.name} (ID: ${project.id})");
          print("🎯 Project assigned to user ID: ${project.userId}");
          print("🎯 Project ID type: ${project.id.runtimeType}");
          print("🎯 Email: ${widget.email}");
          print("🎯 Password: ${widget.password.isNotEmpty ? '***' : 'EMPTY'}");
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ProjectTaskPage(
                projectName: project.name,
                projectId: project.id,
                email: widget.email,
                password: widget.password,
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
              // Project Title
              Text(
                project.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 8),
              
              // Tags/Categories
              if (project.stageName != null) ...[
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      project.stageName!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Project',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              
              // Customer/Organization
              if (project.partnerName != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: isDarkMode ? Colors.white70 : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        project.partnerName!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode ? Colors.white70 : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              
              // Date Range
              if (project.dateStart != null && project.dateEnd != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 16,
                      color: isDarkMode ? Colors.white70 : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatDate(project.dateStart!)} -> ${_formatDate(project.dateEnd!)}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDarkMode ? Colors.white70 : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              
              // Bottom Row - Task Count and Status
              Row(
                children: [
                  // Task Count
                  Text(
                    '${project.taskCount} Tasks',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode ? Colors.white : const Color(0xFF6B46C1), // Purple color
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: isDarkMode ? Colors.white70 : Colors.grey,
                  ),
                  
                  const Spacer(),
                  
                  // Status Indicator
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  
                  // User Avatar (if available)
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[300],
                    child: project.userImage != null && project.userImage!.isNotEmpty
                        ? ClipOval(
                            child: Image.memory(
                              base64Decode(project.userImage!),
                              width: 24,
                              height: 24,
                              fit: BoxFit.cover,
                            ),
                          )
                        : Icon(
                            Icons.person,
                            size: 16,
                            color: isDarkMode ? Colors.white70 : Colors.grey,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }


  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

}
