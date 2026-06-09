import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../odoo_service.dart';
import 'PMform.dart';

/// Drill-down from the Collection dashboard for one project and stage.
class CollectionDetailsPage extends StatefulWidget {
  final String projectName;
  final int projectId;
  /// Server-specific stage label (e.g. `new`, `collected`).
  final String stage;

  const CollectionDetailsPage({
    Key? key,
    required this.projectName,
    required this.projectId,
    required this.stage,
  }) : super(key: key);

  @override
  State<CollectionDetailsPage> createState() => _CollectionDetailsPageState();
}

class _CollectionDetailsPageState extends State<CollectionDetailsPage> {
  final OdooService _odoo = OdooService();
  Future<List<Map<String, dynamic>>>? _future;
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    _loadDarkMode();
    _refresh();
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getBool('isDarkMode') ?? false;
    if (!mounted) return;
    setState(() => _isDarkMode = savedMode);
  }

  Future<void> _refreshAsync() async {
    final f = _odoo.fetchCollectionPmRows(
      projectId: widget.projectId,
      stage: widget.stage,
    );
    setState(() => _future = f);
    await f;
  }

  void _refresh() {
    setState(() {
      _future = _odoo.fetchCollectionPmRows(
        projectId: widget.projectId,
        stage: widget.stage,
      );
    });
  }

  String _m2oName(dynamic v) {
    if (v is List && v.length >= 2) return v[1]?.toString() ?? '';
    return v?.toString() ?? '';
  }

  String _clean(String? s) {
    final t = (s ?? '').trim().toLowerCase();
    if (t.isEmpty || t == 'false' || t == 'null') return '';
    return s!.trim();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.projectName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: const Color(0xFF282454),
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.white,
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  snapshot.error.toString(),
                  style: TextStyle(
                    color: _isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: _refresh, child: const Text('Retry')),
              ],
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'No records for this stage. If your Odoo model uses different field names for collection status, update OdooService.fetchCollectionPmRows.',
                  style: TextStyle(
                    color: _isDarkMode ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: _refresh, child: const Text('Refresh')),
              ],
            );
          }
          return RefreshIndicator(
            onRefresh: _refreshAsync,
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: rows.length,
              itemBuilder: (context, i) {
                final m = rows[i];
                final serial = _clean(
                  (m['lot_serial_number'] ?? _m2oName(m['serial_number_id']))
                      .toString(),
                );
                final product = _clean((m['lot_product'] ?? '').toString());
                final location = _clean(_m2oName(m['lot_location']));
                final pmId = m['id'] is int
                    ? m['id'] as int
                    : int.tryParse(m['id']?.toString() ?? '') ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(
                      serial.isEmpty ? 'PM #$pmId' : serial,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        if (product.isNotEmpty) product,
                        if (location.isNotEmpty) location,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: pmId <= 0
                        ? null
                        : () async {
                            final updated = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PMFormPage(
                                  pmId: pmId,
                                  serialNumberTitle: serial,
                                ),
                              ),
                            );
                            if (updated == true) _refresh();
                          },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
