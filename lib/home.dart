import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'expenses.dart';
import 'helpdesk ticket/ticket.dart';
import 'helpdesk ticket/ticketadmin.dart';
import 'main.dart';
import 'odoo_service.dart';
import 'inventory.dart';
import 'PM/pm.dart';
import 'project app/project.dart';
import 'time off app/timeoff.dart';
import 'task.dart';

class HomePage extends StatefulWidget {
  final String email;
  final String password;
  final void Function(bool)? onThemeChanged;

  const HomePage({
    super.key,
    required this.email,
    required this.password,
    this.onThemeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _gridScrollController = ScrollController();

  String _displayEmail = '';
  String? _userImageBase64;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _displayEmail = prefs.getString('email') ?? widget.email;
      _userImageBase64 = prefs.getString('user_image_base64');
    });

    try {
      final odoo = OdooService();
      await odoo.loadSessionCredentials();
      final isAdmin = await odoo.isAdmin();
      if (!mounted) return;
      setState(() {
        _isAdmin = isAdmin;
      });
    } catch (_) {
      if (!mounted) return;
    }
  }

  String get _displayName {
    final source = _displayEmail.isEmpty ? widget.email : _displayEmail;
    final name = source.contains('@') ? source.split('@').first : source;
    if (name.isEmpty) return 'User';
    return name[0].toUpperCase() + name.substring(1);
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sessionId');
    await prefs.remove('session_id');
    await prefs.remove('email');
    await prefs.remove('password');
    await prefs.remove('user_id');

    if (!mounted) return;
    final next = await getInitialPage(onThemeChanged: widget.onThemeChanged);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => next),
      (route) => false,
    );
  }

  void _onHomeDockTap() {
    if (_gridScrollController.hasClients) {
      _gridScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showProfileSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          isDark ? const Color(0xFF1E2226) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                if (_userImageBase64 != null && _userImageBase64!.isNotEmpty)
                  CircleAvatar(
                    radius: 40,
                    backgroundImage:
                        MemoryImage(base64Decode(_userImageBase64!)),
                  )
                else
                  CircleAvatar(
                    radius: 40,
                    backgroundColor:
                        isDark ? Colors.white12 : const Color(0xFFDDF5E8),
                    child: const Icon(Icons.person,
                        size: 40, color: Color(0xFF0D7A57)),
                  ),
                const SizedBox(height: 12),
                Text(
                  _displayName,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _displayEmail.isEmpty ? widget.email : _displayEmail,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isDark,
                  title: const Text('Dark mode'),
                  onChanged: (v) {
                    widget.onThemeChanged?.call(v);
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Open full menu'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _scaffoldKey.currentState?.openDrawer();
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Logout',
                      style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _logout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPushNotificationLogHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('notification_logs') ?? '[]';
    List<Map<String, dynamic>> logs = [];
    try {
      final list = json.decode(raw) as List<dynamic>;
      logs = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {}

    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (ctx) {
          return Scaffold(
            backgroundColor: isDark ? const Color(0xFF111315) : Colors.white,
            appBar: AppBar(
              backgroundColor: isDark ? const Color(0xFF111315) : Colors.white,
              foregroundColor: isDark ? Colors.white70 : Colors.black87,
              elevation: 0,
              title: const Text('Push notification log'),
            ),
            body: logs.isEmpty
                ? Center(
                    child: Text(
                      'No notification history yet.\nLogs appear when tasks send push from My Task.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black54,
                        height: 1.4,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                    itemBuilder: (context, i) {
                      final log = logs[i];
                      final ok = log['success'] == true;
                      final title =
                          (log['taskTitle'] ?? 'Task').toString();
                      final msg = (log['message'] ?? '').toString();
                      final when =
                          (log['timestampDisplay'] ?? '').toString();
                      final assignee =
                          (log['assignedToName'] ?? '').toString();
                      return ListTile(
                        leading: Icon(
                          ok ? Icons.check_circle_outline : Icons.error_outline,
                          color: ok ? Colors.green : Colors.redAccent,
                          size: 28,
                        ),
                        title: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (assignee.isNotEmpty)
                              Text(
                                'To: $assignee',
                                style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      isDark ? Colors.white60 : Colors.black54,
                                ),
                              ),
                            Text(
                              msg,
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            if (when.isNotEmpty)
                              Text(
                                when,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      isDark ? Colors.white38 : Colors.black45,
                                ),
                              ),
                          ],
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  Future<void> _openMyTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString('user_id');
    if (!mounted) return;
    if (id == null || id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sila log masuk semula (tiada user ID).')),
      );
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => TaskPage(
          isDarkMode: isDark,
          currentUserId: id,
        ),
      ),
    );
  }

  Widget _floatingDockItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 24,
                color: isDark ? Colors.white70 : const Color(0xFF0D7A57),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomFloatingMenu(bool isDark) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final barColor = isDark ? const Color(0xFF1E2226) : Colors.white;
    final shadow = isDark
        ? <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.45),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ]
        : <BoxShadow>[
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 12 + bottomInset),
      child: Material(
        elevation: 0,
        color: barColor,
        shadowColor: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark ? Colors.white12 : const Color(0xFFDCEEE3),
            ),
            boxShadow: shadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _floatingDockItem(
                    icon: Icons.person_outline_rounded,
                    label: 'Profile',
                    onTap: _showProfileSheet,
                    isDark: isDark,
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: const Offset(0, -14),
                        child: Material(
                          elevation: 8,
                          shadowColor: Colors.black26,
                          shape: const CircleBorder(),
                          color: const Color(0xFF0D7A57),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _onHomeDockTap,
                            child: const Padding(
                              padding: EdgeInsets.all(16),
                              child: Icon(
                                Icons.home_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        'Home',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : const Color(0xFF0D7A57),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _floatingDockItem(
                    icon: Icons.task_alt_outlined,
                    label: 'My Task',
                    onTap: _openMyTasks,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF4FBF7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFDCEEE3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: const BoxDecoration(
                color: Color(0xFFDDF5E8),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Color(0xFF0D7A57), size: 22),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: ListView(
          children: [
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2CBF82), Color(0xFF0D7A57)],
                ),
              ),
              accountName: Text(_displayName),
              accountEmail: Text(_displayEmail.isEmpty ? widget.email : _displayEmail),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.person, color: Color(0xFF0D7A57)),
              ),
            ),
            SwitchListTile(
              value: isDark,
              title: const Text('Dark Mode'),
              onChanged: (v) => widget.onThemeChanged?.call(v),
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: _logout,
            ),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF111315) : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(
          color: isDark ? Colors.white70 : Colors.black87,
        ),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            tooltip: 'Push notification log',
            icon: Icon(
              Icons.notifications_outlined,
              color: isDark ? Colors.white70 : const Color(0xFF0D7A57),
            ),
            onPressed: _openPushNotificationLogHistory,
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              color: isDark ? const Color(0xFF111315) : Colors.white,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Image.asset(
                    'images/myerp.com-removebg.png',
                    height: 100,
                    width: double.infinity,
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(height: 12),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                    children: [
                      TextSpan(
                        text: 'My',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF90CAF9)
                              : const Color(0xFF042E7A),
                        ),
                      ),
                      TextSpan(
                        text: 'ERP',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFF69F0AE)
                              : const Color(0xFF0D7A57),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF111315) : Colors.white,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(30),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: GridView.count(
                              controller: _gridScrollController,
                              crossAxisCount: 3,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.82,
                              children: [
                                _tile(
                                  icon: Icons.confirmation_number_outlined,
                                  label: 'Corrective Maintenance',
                                  onTap: () {
                                    final page = _isAdmin
                                        ? TicketAdminPage(
                                            email: widget.email,
                                            password: widget.password,
                                          )
                                        : TicketPage(
                                            email: widget.email,
                                            password: widget.password,
                                          );
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => page),
                                    );
                                  },
                                ),
                                _tile(
                                  icon: Icons.construction_outlined,
                                  label: 'Preventive Maintenance',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PMPage(
                                        email: widget.email,
                                        password: widget.password,
                                      ),
                                    ),
                                  ),
                                ),
                                _tile(
                                  icon: Icons.access_time_filled_outlined,
                                  label: 'Time Off',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const TimeOffPage(),
                                    ),
                                  ),
                                ),
                                _tile(
                                  icon: Icons.receipt_long_outlined,
                                  label: 'Expenses',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const ExpensesPage(),
                                    ),
                                  ),
                                ),
                                _tile(
                                  icon: Icons.folder_open_outlined,
                                  label: 'Project',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ProjectPage(
                                        email: widget.email,
                                        password: widget.password,
                                      ),
                                    ),
                                  ),
                                ),
                                _tile(
                                  icon: Icons.inventory_2_outlined,
                                  label: 'Inventory',
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const InventoryPage(),
                                    ),
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
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomFloatingMenu(isDark),
          ),
        ],
      ),
    );
  }
}
