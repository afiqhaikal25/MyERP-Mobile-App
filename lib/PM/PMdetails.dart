import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../odoo_service.dart';
import 'PMform.dart';
import 'PMlist.dart';

class PMDetailsPage extends StatefulWidget {
  final String projectName;
  final int projectId;
  final int requestId; // maintenance.request id (pm_name)
  final String stage; // 'new' (To Do) or 'done' (Done)

  const PMDetailsPage({
    Key? key,
    required this.projectName,
    required this.projectId,
    required this.requestId,
    required this.stage,
  }) : super(key: key);

  @override
  State<PMDetailsPage> createState() => _PMDetailsPageState();
}

class _PMDetailsPageState extends State<PMDetailsPage> {
  final OdooService _odoo = OdooService();
  Future<List<Map<String, dynamic>>>? _future;
  bool _isDarkMode = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _stageFilter = 'new'; // new=To Do, done=Done
  final Set<String> _groupByFields = <String>{};

  @override
  void initState() {
    super.initState();
    _stageFilter = widget.stage;
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
      _future = widget.requestId > 0
          ? _odoo.fetchPreventiveMaintenanceByRequest(
              requestId: widget.requestId,
              stage: _stageFilter,
            )
          : _odoo.fetchPreventiveMaintenanceByProject(
              projectId: widget.projectId,
              stage: _stageFilter,
            );
    });
  }

  String _m2oName(dynamic v) {
    if (v is List && v.length >= 2) return v[1]?.toString() ?? '';
    return v?.toString() ?? '';
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _groupByZoneLocation(
    List<Map<String, dynamic>> rows,
  ) {
    // Zone -> Location -> Rows
    final Map<String, Map<String, List<Map<String, dynamic>>>> grouped = {};
    for (final r in rows) {
      final zone = _m2oName(r['zone_id']).trim();
      final zoneKey = zone.isEmpty ? 'No Zone' : zone;
      final location = _m2oName(r['lot_location']).trim();
      final locationKey = location.isEmpty ? 'No Location' : location;
      final zoneMap = grouped.putIfAbsent(
          zoneKey, () => <String, List<Map<String, dynamic>>>{});
      zoneMap.putIfAbsent(locationKey, () => <Map<String, dynamic>>[]).add(r);
    }

    // Sort zones and locations alphabetically for stable UI.
    final zoneKeys = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final Map<String, Map<String, List<Map<String, dynamic>>>> sorted = {};
    for (final z in zoneKeys) {
      final locMap = grouped[z] ?? {};
      final locKeys = locMap.keys.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      sorted[z] = {for (final l in locKeys) l: locMap[l]!};
    }
    return sorted;
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  String _fieldText(Map<String, dynamic> row, String field) {
    String technicianName(Map<String, dynamic> r) {
      // Odoo source of truth:
      // field `technician` (many2one -> res.users)
      final t = _m2oName(r['technician']).trim();
      if (t.isNotEmpty) return t;
      final tId = _m2oName(r['technician_id']).trim();
      if (tId.isNotEmpty) return tId;
      final tName = (r['technician_name'] ?? '').toString().trim();
      if (tName.isNotEmpty && tName.toLowerCase() != 'false') return tName;
      return '';
    }

    String equipmentTypeLabel(dynamic raw) {
      final value = (raw ?? '').toString().trim();
      if (value.isEmpty || value.toLowerCase() == 'false') return '';
      const labels = <String, String>{
        'personal_computer': 'Personal Computer',
        'laptop': 'Laptop',
        'printer': 'Printer',
        'monitor': 'Monitor',
        'switch': 'Switch',
        'firewall': 'Firewall',
        'waf': 'WAF',
        'wifi': 'Wifi',
        'projector': 'Projector',
        'access_point': 'Access Point',
        'access point': 'Access Point',
        'server': 'Server',
        'ups': 'UPS',
        'poe': 'POE Switch',
        'software': 'Software',
      };
      final normalized = value.toLowerCase();
      if (labels.containsKey(normalized)) return labels[normalized]!;
      if (value.contains('_')) {
        return value
            .split('_')
            .map((w) =>
                w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
      }
      return value;
    }

    switch (field) {
      case 'department':
        final dept = (row['lot_department'] ?? '').toString().trim();
        if (dept.isNotEmpty && dept.toLowerCase() != 'false') return dept;
        return _m2oName(row['department_id']).trim();
      case 'equipment_type':
        final direct = equipmentTypeLabel(row['equipment_type']);
        if (direct.isNotEmpty) return direct;
        final byId = _m2oName(row['equipment_type_id']).trim();
        if (byId.isNotEmpty) return byId;
        return equipmentTypeLabel(row['lot_product']);
      case 'technician':
        return technicianName(row);
      default:
        return '';
    }
  }

  bool _matchesSearch(Map<String, dynamic> row) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    final serial = (row['lot_serial_number'] ?? _m2oName(row['serial_number_id']))
        .toString()
        .toLowerCase();
    final product = (row['lot_product'] ?? '').toString().toLowerCase();
    final user = (row['equipment_user'] ?? '').toString().toLowerCase();
    final dept = (row['lot_department'] ?? '').toString().toLowerCase();
    final location = _m2oName(row['lot_location']).toLowerCase();
    final zone = _m2oName(row['zone_id']).toLowerCase();
    final equipmentType = _fieldText(row, 'equipment_type').toLowerCase();
    final technician = _fieldText(row, 'technician').toLowerCase();
    final haystack = [
      serial,
      product,
      user,
      dept,
      location,
      zone,
      equipmentType,
      technician,
    ].join(' ');
    return haystack.contains(q);
  }

  Widget _searchAndFilterBar() {
    final cardColor =
        _isDarkMode ? Colors.black.withOpacity(0.55) : Colors.white.withOpacity(0.92);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: _isDarkMode ? Colors.black26 : Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Filter',
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilterPanel,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.projectName.isEmpty ? 'PM Details' : widget.projectName;
    final subtitle = _stageFilter == 'done' ? 'Done' : 'To Do';

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
            children: [
              _searchAndFilterBar(),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
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
                          _ErrorBox(
                            title: 'Tak boleh load PM details',
                            message: snapshot.error.toString(),
                            onRetry: _refresh,
                            isDarkMode: _isDarkMode,
                          ),
                        ],
                      );
                    }

                    final rows = (snapshot.data ?? const <Map<String, dynamic>>[])
                        .where(_matchesSearch)
                        .toList();
                    if (rows.isEmpty) {
                      return ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [
                          _InfoBox(
                            title: 'Tiada data',
                            message:
                                'No preventive maintenance records found for this project.',
                          ),
                        ],
                      );
                    }

                    final grouped = _groupByZoneLocation(rows);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      children: [
                        for (final entry in grouped.entries)
                          _ZoneDropdown(
                            zoneName: entry.key,
                            locations: entry.value,
                            formatDate: _formatDate,
                            m2oName: _m2oName,
                            isDarkMode: _isDarkMode,
                            requestId: widget.requestId,
                            stage: _stageFilter,
                            groupByFields: _groupByFields,
                            groupValueForField: _fieldText,
                            onUpdated: _refresh,
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }

  Future<void> _openFilterPanel() async {
    String tempStage = _stageFilter;
    final tempGroups = Set<String>.from(_groupByFields);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Widget tile(String key, String label) {
              return CheckboxListTile(
                dense: true,
                value: tempGroups.contains(key),
                title: Text(label),
                onChanged: (v) {
                  setModalState(() {
                    if (v == true) {
                      tempGroups.add(key);
                    } else {
                      tempGroups.remove(key);
                    }
                  });
                  setState(() => _groupByFields
                    ..clear()
                    ..addAll(tempGroups));
                },
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      dense: true,
                      value: 'new',
                      groupValue: tempStage,
                      title: const Text('To Do'),
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => tempStage = v);
                        setState(() => _stageFilter = v);
                        _refresh();
                      },
                    ),
                    RadioListTile<String>(
                      dense: true,
                      value: 'done',
                      groupValue: tempStage,
                      title: const Text('Done'),
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() => tempStage = v);
                        setState(() => _stageFilter = v);
                        _refresh();
                      },
                    ),
                    const Divider(),
                    tile('department', 'Group by Department'),
                    tile('equipment_type', 'Group by Equipment Type'),
                    tile('technician', 'Group by Technician'),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Done'),
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
}

class _ZoneDropdown extends StatefulWidget {
  final String zoneName;
  final Map<String, List<Map<String, dynamic>>> locations;
  final String Function(String?) formatDate;
  final String Function(dynamic) m2oName;
  final bool isDarkMode;
  final int requestId;
  final String stage;
  final Set<String> groupByFields;
  final String Function(Map<String, dynamic>, String) groupValueForField;
  final VoidCallback onUpdated;

  const _ZoneDropdown({
    required this.zoneName,
    required this.locations,
    required this.formatDate,
    required this.m2oName,
    required this.isDarkMode,
    required this.requestId,
    required this.stage,
    required this.groupByFields,
    required this.groupValueForField,
    required this.onUpdated,
  });

  @override
  State<_ZoneDropdown> createState() => _ZoneDropdownState();
}

class _ZoneDropdownState extends State<_ZoneDropdown> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final total =
        widget.locations.values.fold<int>(0, (acc, v) => acc + v.length);
    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 12),
      color: widget.isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.92),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.zoneName,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: widget.isDarkMode
                      ? Colors.white
                      : const Color(0xFF282454),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF282454).withOpacity(0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$total',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: widget.isDarkMode
                      ? Colors.white
                      : const Color(0xFF282454),
                ),
              ),
            ),
          ],
        ),
        trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
            color:
                widget.isDarkMode ? Colors.white70 : const Color(0xFF282454)),
        children: [
          const SizedBox(height: 4),
          for (final entry in widget.locations.entries)
            _LocationDropdown(
              locationName: entry.key,
              items: entry.value,
              formatDate: widget.formatDate,
              m2oName: widget.m2oName,
              isDarkMode: widget.isDarkMode,
              requestId: widget.requestId,
              stage: widget.stage,
              groupByFields: widget.groupByFields,
              groupValueForField: widget.groupValueForField,
              onUpdated: widget.onUpdated,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _LocationDropdown extends StatefulWidget {
  final String locationName;
  final List<Map<String, dynamic>> items;
  final String Function(String?) formatDate;
  final String Function(dynamic) m2oName;
  final bool isDarkMode;
  final int requestId;
  final String stage;
  final Set<String> groupByFields;
  final String Function(Map<String, dynamic>, String) groupValueForField;
  final VoidCallback onUpdated;

  const _LocationDropdown({
    required this.locationName,
    required this.items,
    required this.formatDate,
    required this.m2oName,
    required this.isDarkMode,
    required this.requestId,
    required this.stage,
    required this.groupByFields,
    required this.groupValueForField,
    required this.onUpdated,
  });

  @override
  State<_LocationDropdown> createState() => _LocationDropdownState();
}

class _LocationDropdownState extends State<_LocationDropdown> {
  bool _expanded = false;

  List<String> get _orderedGroupFields {
    const order = ['department', 'equipment_type', 'technician'];
    return order.where(widget.groupByFields.contains).toList();
  }

  Widget _buildGroupedContent(
    List<Map<String, dynamic>> items,
    List<String> fields,
    int depth,
  ) {
    if (fields.isEmpty) {
      return Column(
        children: items
            .map(
              (m) => _PmDetailCard(
                m: m,
                m2oName: widget.m2oName,
                formatDate: widget.formatDate,
                isDarkMode: widget.isDarkMode,
                onUpdated: widget.onUpdated,
              ),
            )
            .toList(),
      );
    }

    final current = fields.first;
    final rest = fields.sublist(1);
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in items) {
      final raw = widget.groupValueForField(row, current).trim();
      final key = raw.isEmpty ? 'Unspecified' : raw;
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
    }
    final keys = grouped.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final title = current == 'department'
        ? 'Department'
        : current == 'equipment_type'
            ? 'Equipment Type'
            : 'Technician';
    return Column(
      children: [
        for (final k in keys)
          Padding(
            padding: EdgeInsets.fromLTRB(8 + (depth * 6), 0, 8, 8),
            child: Container(
              decoration: BoxDecoration(
                color: widget.isDarkMode
                    ? Colors.black.withOpacity(0.28)
                    : const Color(0xFFF8F8FC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.isDarkMode ? Colors.white12 : Colors.grey.shade200,
                ),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 10),
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  '$title: $k',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color:
                        widget.isDarkMode ? Colors.white : const Color(0xFF282454),
                  ),
                ),
                trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282454).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${grouped[k]!.length}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: widget.isDarkMode
                          ? Colors.white
                          : const Color(0xFF282454),
                    ),
                  ),
                ),
                children: [
                  _buildGroupedContent(grouped[k]!, rest, depth + 1),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Container(
        decoration: BoxDecoration(
          color:
              widget.isDarkMode ? Colors.black.withOpacity(0.45) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: widget.isDarkMode ? Colors.white24 : Colors.grey.shade200),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.only(bottom: 8),
          onExpansionChanged: (v) => setState(() => _expanded = v),
          title: Row(
            children: [
              Icon(Icons.location_on,
                  size: 18,
                  color: widget.isDarkMode
                      ? Colors.white70
                      : const Color(0xFF282454)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.locationName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: widget.isDarkMode
                        ? Colors.white
                        : const Color(0xFF282454),
                    fontSize: 12,
                  ),
                  softWrap: true,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.list_alt,
                    size: 20, color: Color(0xFF282454)),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PMListPage(
                        requestId: widget.requestId,
                        stage: widget.stage,
                        locationName: widget.locationName,
                      ),
                    ),
                  );
                  widget.onUpdated();
                },
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF282454).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${widget.items.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: widget.isDarkMode
                        ? Colors.white
                        : const Color(0xFF282454),
                  ),
                ),
              ),
            ],
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: widget.isDarkMode ? Colors.white70 : const Color(0xFF282454),
          ),
          children: [
            // Show a single-card viewport with internal scrolling for the rest.
            SizedBox(
              height: 210,
              child: SingleChildScrollView(
                child: _buildGroupedContent(
                  widget.items,
                  _orderedGroupFields,
                  0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PmDetailCard extends StatelessWidget {
  final Map<String, dynamic> m;
  final String Function(dynamic) m2oName;
  final String Function(String?) formatDate;
  final bool isDarkMode;
  final VoidCallback onUpdated;

  const _PmDetailCard({
    required this.m,
    required this.m2oName,
    required this.formatDate,
    required this.isDarkMode,
    required this.onUpdated,
  });

  String _cleanValue(String value) {
    final cleaned = value.trim().toLowerCase();
    if (cleaned.isEmpty || cleaned == 'false' || cleaned == 'null') return '';
    return value.trim();
  }

  @override
  Widget build(BuildContext context) {
    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is double) return v.round();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final serial =
        (m['lot_serial_number'] ?? m2oName(m['serial_number_id'])).toString();
    final product = _cleanValue((m['lot_product'] ?? '').toString());
    final userRaw = (m['equipment_user'] ?? '').toString();
    final deptRaw = (m['lot_department'] ?? '').toString();
    final locationRaw = m2oName(m['lot_location']);
    final user = _cleanValue(userRaw);
    final dept = _cleanValue(deptRaw);
    final location = _cleanValue(locationRaw);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final pmId = asInt(m['id']);
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
            onUpdated();
          }
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.black.withOpacity(0.45) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: isDarkMode ? Colors.white24 : Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                serial,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isDarkMode ? Colors.white : const Color(0xFF282454)),
              ),
              const SizedBox(height: 6),
              _RowInfo(
                  label: 'Brand/Model', value: product.isEmpty ? '-' : product),
              _RowInfo(label: 'User', value: user),
              _RowInfo(label: 'Location', value: location),
              _RowInfo(label: 'Department', value: dept),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowInfo extends StatelessWidget {
  final String label;
  final String value;

  const _RowInfo({required this.label, required this.value});

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

class _ErrorBox extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onRetry;
  final bool isDarkMode;

  const _ErrorBox({
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

class _InfoBox extends StatelessWidget {
  final String title;
  final String message;

  const _InfoBox({required this.title, required this.message});

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
