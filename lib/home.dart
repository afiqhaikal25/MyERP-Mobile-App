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
  String _displayEmail = '';
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _displayEmail = prefs.getString('email') ?? widget.email;
    });

    try {
      final isAdmin = await OdooService().isAdmin();
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
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        automaticallyImplyLeading: true,
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
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: GridView.count(
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
                                        initialFilterActive: true,
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
        ],
      ),
    );
  }
}
