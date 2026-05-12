import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_app_file/open_app_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../odoo_service.dart';
import 'PMform.dart';

class PMListPage extends StatefulWidget {
  final int requestId;
  final String stage;
  final String locationName;

  const PMListPage({
    Key? key,
    required this.requestId,
    required this.stage,
    required this.locationName,
  }) : super(key: key);

  @override
  State<PMListPage> createState() => _PMListPageState();
}

class _PMListPageState extends State<PMListPage> {
  final OdooService _odoo = OdooService();
  Future<List<Map<String, dynamic>>>? _future;
  bool _isDarkMode = false;
  bool _isDownloadingReport = false;
  bool _selectAllPrompted = false;
  bool _reportDialogVisible = false;
  List<Map<String, dynamic>> _items = const [];
  final Set<int> _selected = <int>{};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  static const List<_ReportOption> _reportOptions = [
    _ReportOption(
        'PM Form (PC/Laptop)', 'preventive_maintenance.pm_form_pc_template'),
    _ReportOption(
        'PM Form (Printer)', 'preventive_maintenance.pm_form_printer_template'),
    _ReportOption(
        'PM Form (Switch)', 'preventive_maintenance.pm_form_switch_template'),
    _ReportOption('PM Form (Firewall)',
        'preventive_maintenance.pm_form_firewall_template'),
    _ReportOption(
        'PM Form (UPS)', 'preventive_maintenance.pm_form_ups_template'),
    _ReportOption(
        'PM Form (Access Point)', 'preventive_maintenance.pm_form_ap_template'),
    _ReportOption(
        'PM Form (Server)', 'preventive_maintenance.pm_form_server_template'),
  ];

  @override
  void initState() {
    super.initState();
    _loadDarkMode();
    _refresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getBool('isDarkMode') ?? false;
    if (!mounted) return;
    setState(() => _isDarkMode = savedMode);
  }

  void _refresh() {
    setState(() {
      _selected.clear();
      _future = _odoo.fetchPreventiveMaintenanceByRequest(
        requestId: widget.requestId,
        stage: widget.stage,
      );
    });
    _future?.then((value) {
      if (!mounted) return;
      setState(() => _items = _filterByLocation(value));
    }).catchError((_) {});
  }

  String _m2oName(dynamic v) {
    if (v is List && v.length >= 2) return v[1]?.toString() ?? '';
    return v?.toString() ?? '';
  }

  String _cleanValue(String value) {
    final cleaned = value.trim().toLowerCase();
    if (cleaned.isEmpty || cleaned == 'false' || cleaned == 'null') return '';
    return value.trim();
  }

  List<Map<String, dynamic>> _filterByLocation(
      List<Map<String, dynamic>> rows) {
    return rows.where((row) {
      final name = _m2oName(row['lot_location']).trim();
      final key = name.isEmpty ? 'No Location' : name;
      return key == widget.locationName;
    }).toList();
  }

  List<Map<String, dynamic>> _applySearch(List<Map<String, dynamic>> rows) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((row) {
      final serial =
          (row['lot_serial_number'] ?? _m2oName(row['serial_number_id']))
              .toString();
      return serial.toLowerCase().contains(q);
    }).toList();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'search serial number',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF282454)),
          ),
        ),
      ),
    );
  }

  String _safeFileName(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'pm_report' : cleaned;
  }

  void _showLoadingDialog() {
    if (_reportDialogVisible) return;
    _reportDialogVisible = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFF282454)),
        );
      },
    );
  }

  void _hideLoadingDialog() {
    if (!_reportDialogVisible) return;
    _reportDialogVisible = false;
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _downloadSelectedReports(_ReportOption option) async {
    if (_isDownloadingReport) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Pilih sekurang-kurangnya satu PM untuk print')),
      );
      return;
    }
    setState(() => _isDownloadingReport = true);
    _showLoadingDialog();
    try {
      final bytes = await _odoo.fetchPreventiveMaintenanceReportPdfForIds(
        pmIds: _selected.toList(),
        reportName: option.reportName,
      );
      if (bytes.isEmpty) throw Exception('PDF kosong');
      final fileName =
          _safeFileName('${option.label}-${widget.locationName}.pdf');
      final file = File('${Directory.systemTemp.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenAppFile.open(file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Berjaya download PDF (${_selected.length} PM)')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal download PDF: $e')),
      );
    } finally {
      _hideLoadingDialog();
      if (mounted) setState(() => _isDownloadingReport = false);
    }
  }

  void _toggleSelected(int pmId, bool selected) {
    setState(() {
      if (selected) {
        _selected.add(pmId);
      } else {
        _selected.remove(pmId);
      }
    });
  }

  Future<void> _toggleSelectedWithPrompt(int pmId, bool selected) async {
    if (!_selectAllPrompted && selected) {
      _selectAllPrompted = true;
      final shouldSelectAll = await showDialog<bool>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Select all?'),
                content: const Text('Select all PMs in this location?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF282454)),
                    child: const Text('Yes',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              );
            },
          ) ??
          false;
      if (shouldSelectAll) {
        setState(() {
          _selected
            ..clear()
            ..addAll(
              _items
                  .map((e) => (e['id'] is int)
                      ? e['id'] as int
                      : int.tryParse(e['id'].toString()) ?? 0)
                  .where((id) => id > 0),
            );
        });
        return;
      }
    }
    _toggleSelected(pmId, selected);
  }

  @override
  Widget build(BuildContext context) {
    final visibleItems = _applySearch(_items);
    final totalCount = visibleItems.length;
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _isDarkMode ? Colors.white : const Color(0xFF282454),
                    ),
                  ),
                );
              }
              if (snapshot.hasError) {
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _ListCardBox(
                      title: 'Tak boleh load PM list',
                      message: snapshot.error.toString(),
                      onRetry: _refresh,
                      isDarkMode: _isDarkMode,
                    ),
                  ],
                );
              }

              final items = _applySearch(_items);
              if (items.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    _buildSearchBar(),
                    const _ListInfoBox(
                      title: 'No data',
                      message: 'Serial number not found.',
                    ),
                  ],
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                itemCount: items.length + 1,
                itemBuilder: (context, idx) {
                  if (idx == 0) return _buildSearchBar();
                  final m = items[idx - 1];
                  final pmId = (m['id'] is int)
                      ? m['id'] as int
                      : int.tryParse(m['id'].toString()) ?? 0;
                  final serial = (m['lot_serial_number'] ??
                          _m2oName(m['serial_number_id']))
                      .toString();
                  final productRaw = (m['lot_product'] ?? '').toString();
                  final product = _cleanValue(productRaw);
                  final userRaw = (m['equipment_user'] ?? '').toString();
                  final deptRaw = (m['lot_department'] ?? '').toString();
                  final locationRaw = _m2oName(m['lot_location']);
                  final user = _cleanValue(userRaw);
                  final dept = _cleanValue(deptRaw);
                  final location = _cleanValue(locationRaw);
                  final selected = _selected.contains(pmId);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        if (pmId <= 0) return;
                        final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PMFormPage(
                              pmId: pmId,
                              serialNumberTitle: serial,
                            ),
                          ),
                        );
                        if (updated == true) {
                          _refresh();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    serial,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF282454),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (product.isNotEmpty)
                                    _ListRow(
                                        label: 'Brand/Model', value: product),
                                  _ListRow(label: 'User', value: user),
                                  _ListRow(label: 'Location', value: location),
                                  _ListRow(label: 'Department', value: dept),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Checkbox(
                                value: selected,
                                activeColor: const Color(0xFF282454),
                                onChanged: (val) {
                                  if (val == null) return;
                                  _toggleSelectedWithPrompt(pmId, val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
    );
  }
}

class _ReportOption {
  final String label;
  final String reportName;

  const _ReportOption(this.label, this.reportName);
}

class _ListRow extends StatelessWidget {
  final String label;
  final String value;

  const _ListRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              '$label:',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.black54),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListCardBox extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final bool isDarkMode;

  const _ListCardBox({
    required this.title,
    required this.message,
    required this.onRetry,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.9),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF282454)),
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ListInfoBox extends StatelessWidget {
  final String title;
  final String message;

  const _ListInfoBox({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}
