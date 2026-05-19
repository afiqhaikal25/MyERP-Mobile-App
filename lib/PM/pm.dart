import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../odoo_service.dart';
import 'PMdetails.dart';
import 'collectiondetails.dart';

enum _PmStatusFilter { all, active, complete }

class PMPage extends StatefulWidget {
  final String email;
  final String password;
  final bool initialFilterActive;

  const PMPage({
    Key? key,
    required this.email,
    required this.password,
    this.initialFilterActive = false,
  }) : super(key: key);

  @override
  State<PMPage> createState() => _PMPageState();
}

class _PMPageState extends State<PMPage> {
  bool _isDarkMode = false;
  String _selectedMenu = 'PM';
  int _selectedView = 0; // 0 = Dashboard, 1 = PM UI
  _PmStatusFilter _statusFilter = _PmStatusFilter.all;
  final OdooService _odoo = OdooService();
  Future<List<Map<String, dynamic>>>? _pmFuture;
  Future<Map<String, dynamic>>? _pmDashboardFuture;
  Future<List<Map<String, dynamic>>>? _collectionFuture;
  Future<List<Map<String, dynamic>>>? _uatFuture;

  @override
  void initState() {
    super.initState();
    _loadDarkMode();
    _bootstrapPm();
  }

  Future<void> _bootstrapPm() async {
    await _odoo.loadSessionCredentials();
    await _odoo.checkAndLoadUserCredentials();
    if (widget.initialFilterActive) {
      _statusFilter = _PmStatusFilter.active;
    }
    if (!mounted) return;
    _refreshPmKanban(includeAll: _includeAllForStatus());
    _refreshPmDashboard();
  }

  Future<void> _loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getBool('isDarkMode') ?? false;
    if (!mounted) return;
    setState(() {
      _isDarkMode = savedMode;
    });
  }

  void _refreshPmKanban({bool includeAll = false}) {
    setState(() {
      _pmFuture = _odoo.fetchPmKanbanRequests(
        includeAll: includeAll,
        status: _statusKey(),
      );
    });
  }

  void _refreshPmDashboard() {
    setState(() {
      _pmDashboardFuture = _buildPmDashboardData();
    });
  }

  DateTime? _parseOdooDate(dynamic v) {
    if (v == null || v == false) return null;
    final s = v.toString().trim();
    if (s.isEmpty || s == 'false') return null;
    return DateTime.tryParse(s.replaceFirst(' ', 'T'));
  }

  Future<Map<String, dynamic>> _buildPmDashboardData() async {
    final rows = await _odoo.fetchPreventiveMaintenanceDashboardRows();
    final total = rows.length;
    int done = 0;
    int todo = 0;
    int signed = 0;
    int overdueLike = 0; // proxy: old unfinished work (30+ days)
    final now = DateTime.now();
    // Latest 3 months window (inclusive): e.g. Mar => Jan 1 onward.
    final start3Months = DateTime(now.year, now.month - 2, 1);

    final Map<int, Map<String, dynamic>> byTech = {};
    for (final r in rows) {
      final stage = (r['stage']?.toString() ?? '').toLowerCase();
      final isDone = stage == 'done';
      if (isDone) {
        done++;
      } else {
        todo++;
      }

      if (r['user_signature_date'] != null &&
          r['user_signature_date'] != false) {
        signed++;
      }
      final createDate = _parseOdooDate(r['create_date']);
      if (!isDone &&
          createDate != null &&
          now.difference(createDate).inDays >= 30) {
        overdueLike++;
      }

      final tech = r['technician'];
      int? techId;
      String techName = 'Unassigned';
      if (tech is List && tech.isNotEmpty && tech[0] != false) {
        techId =
            tech[0] is int ? tech[0] as int : int.tryParse(tech[0].toString());
        if (tech.length > 1 && tech[1] != false)
          techName = tech[1]?.toString() ?? techName;
      } else if (tech is int) {
        techId = tech;
      }
      if (techId == null) continue;
      final createdAt = _parseOdooDate(r['create_date']);
      if (createdAt == null || createdAt.isBefore(start3Months)) continue;

      byTech.putIfAbsent(techId, () {
        return {
          'id': techId,
          'name': techName,
          'done': 0,
          'todo': 0,
          'total': 0,
          'latest': createDate ?? now,
        };
      });
      byTech[techId]!['total'] = (byTech[techId]!['total'] as int) + 1;
      if (isDone) {
        byTech[techId]!['done'] = (byTech[techId]!['done'] as int) + 1;
      } else {
        byTech[techId]!['todo'] = (byTech[techId]!['todo'] as int) + 1;
      }
      final latest = _parseOdooDate(r['write_date']) ?? createDate ?? now;
      final curLatest = byTech[techId]!['latest'] as DateTime;
      if (latest.isAfter(curLatest)) byTech[techId]!['latest'] = latest;
    }

    final userMap = await _odoo.fetchUsersByIds(byTech.keys.toList());
    final techList = byTech.values.map((e) {
      final d = e['done'] as int;
      final t = e['total'] as int;
      final td = e['todo'] as int;
      final completion = t > 0 ? d / t : 0.0;
      final score = (d * 10.0) + (completion * 100.0) - (td * 2.5);
      final u = userMap[e['id'] as int];
      return {
        ...e,
        'completion': completion,
        'score': score,
        'image': u?['image_128'],
      };
    }).toList();

    techList.sort((a, b) {
      final byScore = (b['score'] as double).compareTo(a['score'] as double);
      if (byScore != 0) return byScore;
      final byDone = (b['done'] as int).compareTo(a['done'] as int);
      if (byDone != 0) return byDone;
      final da = a['latest'] as DateTime;
      final db = b['latest'] as DateTime;
      return db.compareTo(da);
    });

    return {
      'total': total,
      'done': done,
      'todo': todo,
      'signed': signed,
      'overdueLike': overdueLike,
      'completion': total > 0 ? (done / total) : 0.0,
      'topTech': techList.take(5).toList(),
    };
  }

  void _refreshCollectionDashboard() {
    setState(() {
      _collectionFuture = _odoo.fetchCollectionDashboardCards();
    });
  }

  void _refreshUatDashboard() {
    setState(() {
      _uatFuture = _odoo.fetchUatDashboardProjects();
    });
  }

  void _onMenuSelected(String value) {
    setState(() {
      _selectedMenu = value;
    });
    if (value == 'PM') {
      _refreshPmKanban(includeAll: _includeAllForStatus());
      _refreshPmDashboard();
    } else if (value == 'Collection') {
      _refreshCollectionDashboard();
    } else if (value == 'UAT') {
      _refreshUatDashboard();
    }
  }

  String _filterLabel(_PmStatusFilter f) {
    switch (f) {
      case _PmStatusFilter.active:
        return 'Active';
      case _PmStatusFilter.complete:
        return 'Complete';
      case _PmStatusFilter.all:
        return 'All';
    }
  }

  String _statusKey() {
    switch (_statusFilter) {
      case _PmStatusFilter.active:
        return 'active';
      case _PmStatusFilter.complete:
        return 'complete';
      case _PmStatusFilter.all:
        return 'all';
    }
  }

  bool _includeAllForStatus() {
    // Complete list should include older records too.
    return _statusFilter == _PmStatusFilter.complete;
  }

  Future<void> _onHomeButtonPressed() async {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final barInk = _isDarkMode ? Colors.white : const Color(0xFF282454);
    final barMuted = _isDarkMode ? Colors.white70 : Colors.black54;
    return Scaffold(
      backgroundColor: _isDarkMode ? Colors.grey[900] : Colors.white,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: IconButton(
                      icon: Icon(Icons.grid_view, color: barInk),
                      onPressed: _onHomeButtonPressed,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _selectedMenu == 'PM'
                          ? 'Preventive Maintenance'
                          : _selectedMenu,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: barInk,
                        letterSpacing: 0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: IconTheme(
                      data: IconThemeData(color: barInk, size: 28),
                      child: const Icon(Icons.arrow_drop_down, size: 28),
                    ),
                    onSelected: _onMenuSelected,
                    itemBuilder: (BuildContext context) => const [
                      PopupMenuItem<String>(
                        value: 'PM',
                        child: Row(
                          children: [
                            Icon(Icons.build,
                                color: Color(0xFF282454), size: 20),
                            SizedBox(width: 12),
                            Text('PM'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'Collection',
                        child: Row(
                          children: [
                            Icon(Icons.collections,
                                color: Color(0xFF282454), size: 20),
                            SizedBox(width: 12),
                            Text('Collection'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'UAT',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Color(0xFF282454), size: 20),
                            SizedBox(width: 12),
                            Text('UAT'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  PopupMenuButton<_PmStatusFilter>(
                    tooltip: 'Filter PM: ${_filterLabel(_statusFilter)}',
                    icon: Icon(
                      Icons.filter_list,
                      color: _selectedMenu == 'PM'
                          ? (_statusFilter == _PmStatusFilter.all
                              ? barInk
                              : Colors.amberAccent)
                          : barMuted,
                    ),
                    onSelected: (v) {
                      setState(() {
                        _statusFilter = v;
                        _pmFuture = _odoo.fetchPmKanbanRequests(
                          includeAll: _includeAllForStatus(),
                          status: _statusKey(),
                        );
                      });
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<_PmStatusFilter>(
                        value: _PmStatusFilter.all,
                        child: Text('All'),
                      ),
                      PopupMenuItem<_PmStatusFilter>(
                        value: _PmStatusFilter.active,
                        child: Text('Active'),
                      ),
                      PopupMenuItem<_PmStatusFilter>(
                        value: _PmStatusFilter.complete,
                        child: Text('Complete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: _isDarkMode ? Colors.grey[900] : Colors.white,
              child: _buildContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_selectedMenu == 'Collection') return _buildCollectionDashboard();
    if (_selectedMenu == 'UAT') return _buildUatDashboard();
    if (_selectedMenu != 'PM') return _buildComingSoon();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Material(
                  color: _selectedView == 0
                      ? const Color(0xFF282454)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => setState(() => _selectedView = 0),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedView == 0
                              ? Colors.transparent
                              : (_isDarkMode
                                  ? Colors.white54
                                  : const Color(0xFF282454)),
                          width: 1,
                        ),
                        color: _selectedView == 0
                            ? const Color(0xFF282454)
                            : Colors.white
                                .withOpacity(_isDarkMode ? 0.10 : 0.20),
                      ),
                      child: Center(
                        child: Text(
                          'Dashboard',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _selectedView == 0
                                ? Colors.white
                                : (_isDarkMode
                                    ? Colors.white70
                                    : const Color(0xFF282454)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Material(
                  color: _selectedView == 1
                      ? const Color(0xFF282454)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () => setState(() => _selectedView = 1),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _selectedView == 1
                              ? Colors.transparent
                              : (_isDarkMode
                                  ? Colors.white54
                                  : const Color(0xFF282454)),
                          width: 1,
                        ),
                        color: _selectedView == 1
                            ? const Color(0xFF282454)
                            : Colors.white
                                .withOpacity(_isDarkMode ? 0.10 : 0.20),
                      ),
                      child: Center(
                        child: Text(
                          'PM UI',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _selectedView == 1
                                ? Colors.white
                                : (_isDarkMode
                                    ? Colors.white70
                                    : const Color(0xFF282454)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _selectedView == 0 ? _buildPmDashboardTab() : _buildPmUiTab(),
        ),
      ],
    );
  }

  Widget _buildPmDashboardTab() {
    final future = _pmDashboardFuture ?? _buildPmDashboardData();
    _pmDashboardFuture ??= future;
    return RefreshIndicator(
      onRefresh: () async => _refreshPmDashboard(),
      child: FutureBuilder<Map<String, dynamic>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF282454)));
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _ErrorCard(
                  isDarkMode: _isDarkMode,
                  title: 'Tak boleh load PM dashboard',
                  message: snapshot.error.toString(),
                  onRetry: _refreshPmDashboard,
                ),
              ],
            );
          }
          final data = snapshot.data ?? const {};
          final total = (data['total'] as int?) ?? 0;
          final done = (data['done'] as int?) ?? 0;
          final todo = (data['todo'] as int?) ?? 0;
          final signed = (data['signed'] as int?) ?? 0;
          final overdueLike = (data['overdueLike'] as int?) ?? 0;
          final completion = ((data['completion'] as double?) ?? 0.0) * 100.0;
          final topTech = (data['topTech'] as List<dynamic>? ?? const [])
              .cast<Map<String, dynamic>>();

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.35,
                children: [
                  _KpiBox(title: 'Total PM', value: '$total'),
                  _KpiBox(title: 'Done', value: '$done'),
                  _KpiBox(title: 'To Do', value: '$todo'),
                  _KpiBox(
                      title: 'Completion',
                      value: '${completion.toStringAsFixed(0)}%'),
                  _KpiBox(title: 'Signed', value: '$signed'),
                  _KpiBox(title: '30d Pending', value: '$overdueLike'),
                ],
              ),
              const SizedBox(height: 0),
              Card(
                color: _isDarkMode
                    ? Colors.black.withOpacity(0.55)
                    : Colors.white.withOpacity(0.92),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Formula Top Ranking PM',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: _isDarkMode
                              ? Colors.white
                              : const Color(0xFF282454),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Score = (Done x 10) + (Completion x 100) - (To Do x 2.5)',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _isDarkMode
                                ? Colors.white70
                                : const Color(0xFF282454)),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tie-breaker: score tinggi > done tinggi > aktiviti terbaru (write_date). Data ranking ditapis 3 bulan terkini.',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                _isDarkMode ? Colors.white60 : Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                color: _isDarkMode
                    ? Colors.black.withOpacity(0.55)
                    : Colors.white.withOpacity(0.92),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Top Technician (Preventive Maintenance)',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: _isDarkMode
                              ? Colors.white
                              : const Color(0xFF282454),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ranking by completion score: done, completion rate, low backlog, recent activity.',
                        style: TextStyle(
                            fontSize: 11,
                            color:
                                _isDarkMode ? Colors.white60 : Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      if (topTech.isEmpty)
                        Text(
                          'No technician data found.',
                          style: TextStyle(
                              color: _isDarkMode
                                  ? Colors.white70
                                  : Colors.black87),
                        )
                      else
                        ...topTech
                            .take(5)
                            .toList()
                            .asMap()
                            .entries
                            .map((entry) {
                          final i = entry.key;
                          final t = entry.value;
                          final name =
                              (t['name']?.toString() ?? 'Technician').trim();
                          final doneCount = (t['done'] as int?) ?? 0;
                          final todoCount = (t['todo'] as int?) ?? 0;
                          final completionRate =
                              (((t['completion'] as double?) ?? 0.0) * 100.0)
                                  .toStringAsFixed(0);
                          final score = ((t['score'] as double?) ?? 0.0)
                              .toStringAsFixed(1);
                          final imageBase64 = t['image']?.toString();
                          return Padding(
                            padding: EdgeInsets.only(
                                bottom: i == topTech.length - 1 ? 0 : 10),
                            child: Row(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: const Color(0xFF282454)
                                        .withOpacity(0.15),
                                  ),
                                  child: Text('${i + 1}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11,
                                          color: Color(0xFF282454))),
                                ),
                                const SizedBox(width: 8),
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor:
                                      const Color(0xFF282454).withOpacity(0.15),
                                  backgroundImage: imageBase64 != null &&
                                          imageBase64.isNotEmpty &&
                                          imageBase64 != 'false'
                                      ? (() {
                                          try {
                                            return MemoryImage(
                                                base64Decode(imageBase64));
                                          } catch (_) {
                                            return null;
                                          }
                                        })()
                                      : null,
                                  child: (imageBase64 == null ||
                                          imageBase64.isEmpty ||
                                          imageBase64 == 'false')
                                      ? Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: Color(0xFF282454),
                                              fontWeight: FontWeight.w800))
                                      : null,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              color: _isDarkMode
                                                  ? Colors.white
                                                  : Colors.black87)),
                                      Text(
                                        '$doneCount done, $todoCount to do, completion $completionRate%',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: _isDarkMode
                                                ? Colors.white60
                                                : Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Score $score',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                      color: _isDarkMode
                                          ? Colors.white70
                                          : const Color(0xFF282454)),
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPmUiTab() {
    final future = _pmFuture ??
        _odoo.fetchPmKanbanRequests(
          includeAll: _includeAllForStatus(),
          status: _statusKey(),
        );
    _pmFuture ??= future;
    return RefreshIndicator(
      onRefresh: () async =>
          _refreshPmKanban(includeAll: _includeAllForStatus()),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final raw = snapshot.error.toString();
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _ErrorCard(
                  isDarkMode: _isDarkMode,
                  title: 'Tak boleh load PM dashboard',
                  message: raw,
                  onRetry: () =>
                      _refreshPmKanban(includeAll: _includeAllForStatus()),
                ),
              ],
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _InfoCard(
                  isDarkMode: _isDarkMode,
                  title: 'No PM request',
                  message: 'No Maintenance Request found.',
                ),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final m = items[i];
              return _PmKanbanCard(
                isDarkMode: _isDarkMode,
                data: m,
                statusFilter: _statusFilter,
                onUpdated: () =>
                    _refreshPmKanban(includeAll: _includeAllForStatus()),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCollectionDashboard() {
    final future = _collectionFuture ?? _odoo.fetchCollectionDashboardCards();
    _collectionFuture ??= future;

    return RefreshIndicator(
      onRefresh: () async => _refreshCollectionDashboard(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _ErrorCard(
                  isDarkMode: _isDarkMode,
                  title: 'Tak boleh load Collection dashboard',
                  message: snapshot.error.toString(),
                  onRetry: _refreshCollectionDashboard,
                ),
              ],
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _InfoCard(
                  isDarkMode: _isDarkMode,
                  title: 'Tiada Collection dashboard',
                  message: 'No Collection dashboard cards found.',
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              return _CollectionKanbanCard(
                isDarkMode: _isDarkMode,
                data: items[i],
                onReturn: _refreshCollectionDashboard,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildUatDashboard() {
    final future = _uatFuture ?? _odoo.fetchUatDashboardProjects();
    _uatFuture ??= future;

    return RefreshIndicator(
      onRefresh: () async => _refreshUatDashboard(),
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _ErrorCard(
                  isDarkMode: _isDarkMode,
                  title: 'Tak boleh load UAT dashboard',
                  message: snapshot.error.toString(),
                  onRetry: _refreshUatDashboard,
                ),
              ],
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _InfoCard(
                  isDarkMode: _isDarkMode,
                  title: 'Tiada UAT dashboard',
                  message: 'No UAT dashboard cards found.',
                ),
              ],
            );
          }

          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              return _UatKanbanCard(
                isDarkMode: _isDarkMode,
                data: items[i],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildComingSoon() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.dashboard_outlined,
            size: 64,
            color: _isDarkMode ? Colors.white70 : Colors.grey[700],
          ),
          const SizedBox(height: 16),
          Text(
            _selectedMenu,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _isDarkMode ? Colors.white : const Color(0xFF282454),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(
              fontSize: 16,
              color: _isDarkMode ? Colors.white60 : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiBox extends StatelessWidget {
  final String title;
  final String value;
  const _KpiBox({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF282454).withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF282454))),
        ],
      ),
    );
  }
}

class _PmKanbanCard extends StatelessWidget {
  final bool isDarkMode;
  final Map<String, dynamic> data;
  final _PmStatusFilter statusFilter;
  final VoidCallback onUpdated;

  const _PmKanbanCard({
    required this.isDarkMode,
    required this.data,
    required this.statusFilter,
    required this.onUpdated,
  });

  String _m2oDisplay(dynamic v) {
    // Odoo many2one comes as [id, "Display Name"]
    if (v is List && v.length >= 2) return v[1]?.toString() ?? '';
    return v?.toString() ?? '';
  }

  int _m2oId(dynamic v) {
    if (v is List && v.isNotEmpty) {
      final id = v[0];
      if (id is int) return id;
      return int.tryParse(id?.toString() ?? '') ?? 0;
    }
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  Color _daysColor(int days) {
    if (days <= 0) return Colors.redAccent;
    if (days <= 10) return Colors.red;
    if (days <= 20) return Colors.orange;
    return isDarkMode ? Colors.white70 : Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    final projectName = _m2oDisplay(data['project_id']);
    final subject = (data['name'] ?? '').toString();
    final done = _asInt(data['preventive_maintenance_count_done']);
    final todo = _asInt(data['preventive_maintenance_count_new']);
    final daysLeft = _asInt(data['days_left_deadline']);
    final pct = _asDouble(data['preventive_maintenance_done_percentage']);
    final pctColor =
        pct >= 70 ? Colors.green : (pct >= 30 ? Colors.orange : Colors.red);
    final progress = (pct.clamp(0, 100)) / 100.0;

    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 12),
      color: isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    projectName.isEmpty ? 'Project' : projectName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          isDarkMode ? Colors.white : const Color(0xFF282454),
                    ),
                  ),
                ),
                if (statusFilter != _PmStatusFilter.complete) ...[
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$daysLeft Days',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _daysColor(daysLeft),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    subject,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 2.2,
                          value: progress.isNaN ? 0 : progress,
                          backgroundColor:
                              isDarkMode ? Colors.white24 : Colors.black12,
                          valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                        ),
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontSize: 6.5,
                            fontWeight: FontWeight.w800,
                            color: pctColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Done / To Do become buttons inside the card
            Row(
              children: [
                Expanded(
                  child: _CountButton(
                    label: 'Done',
                    value: done,
                    background: Colors.green,
                    foreground: Colors.white,
                    onPressed: () async {
                      if (done == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('No to do data for this project')),
                        );
                        return;
                      }
                      final projectId = _m2oId(data['project_id']);
                      final projectName = _m2oDisplay(data['project_id']);
                      if (projectId <= 0) return;
                      final requestId = _asInt(data['id']);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PMDetailsPage(
                            projectName: projectName,
                            projectId: projectId,
                            requestId: requestId,
                            stage: 'done',
                          ),
                        ),
                      );
                      onUpdated();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountButton(
                    label: 'To Do',
                    value: todo,
                    background: Colors.red,
                    foreground: Colors.white,
                    onPressed: () async {
                      if (todo == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('No to do data for this project')),
                        );
                        return;
                      }
                      final projectId = _m2oId(data['project_id']);
                      final projectName = _m2oDisplay(data['project_id']);
                      if (projectId <= 0) return;
                      final requestId = _asInt(data['id']);
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PMDetailsPage(
                            projectName: projectName,
                            projectId: projectId,
                            requestId: requestId,
                            stage: 'new',
                          ),
                        ),
                      );
                      onUpdated();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  final String label;
  final int value;
  final Color background;
  final Color foreground;
  final VoidCallback onPressed;

  const _CountButton({
    required this.label,
    required this.value,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$value',
              style: TextStyle(fontWeight: FontWeight.w800, color: foreground),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.w600, color: foreground),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionKanbanCard extends StatelessWidget {
  final bool isDarkMode;
  final Map<String, dynamic> data;
  final VoidCallback onReturn;

  const _CollectionKanbanCard({
    required this.isDarkMode,
    required this.data,
    required this.onReturn,
  });

  String _m2oDisplay(dynamic v) {
    if (v is List && v.length >= 2) return v[1]?.toString() ?? '';
    return v?.toString() ?? '';
  }

  int _m2oId(dynamic v) {
    if (v is List && v.isNotEmpty) {
      return int.tryParse(v.first?.toString() ?? '') ?? 0;
    }
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final projectName = _m2oDisplay(data['project_id']);
    final cfName = (data['cf_name'] ?? '').toString();
    final done = _asInt(data['project_collection_count_done']);
    final todo = _asInt(data['project_collection_count_new']);
    final pct = _asDouble(data['project_collection_done_percentage']);
    final progress = (pct.clamp(0, 100)) / 100.0;
    final pctColor =
        pct >= 70 ? Colors.green : (pct >= 30 ? Colors.orange : Colors.red);

    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 12),
      color: isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    projectName.isEmpty ? 'Project' : projectName,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          isDarkMode ? Colors.white : const Color(0xFF282454),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Collection',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: cfName.isEmpty
                      ? const SizedBox.shrink()
                      : Text(
                          cfName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color:
                                isDarkMode ? Colors.white60 : Colors.grey[700],
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2.2,
                        value: progress.isNaN ? 0 : progress,
                        backgroundColor:
                            isDarkMode ? Colors.white24 : Colors.black12,
                        valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                      ),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 6.5,
                          fontWeight: FontWeight.w800,
                          color: pctColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CountButton(
                    label: 'Done',
                    value: done,
                    background: Colors.green,
                    foreground: Colors.white,
                    onPressed: () {
                      if (done == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('No to do data for this project')),
                        );
                        return;
                      }
                      final projectId = _m2oId(data['project_id']);
                      final projectName = _m2oDisplay(data['project_id']);
                      if (projectId <= 0) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CollectionDetailsPage(
                            projectName: projectName,
                            projectId: projectId,
                            stage: 'collected',
                          ),
                        ),
                      ).then((_) => onReturn());
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountButton(
                    label: 'To Do',
                    value: todo,
                    background: Colors.red,
                    foreground: Colors.white,
                    onPressed: () {
                      if (todo == 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('No to do data for this project')),
                        );
                        return;
                      }
                      final projectId = _m2oId(data['project_id']);
                      final projectName = _m2oDisplay(data['project_id']);
                      if (projectId <= 0) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CollectionDetailsPage(
                            projectName: projectName,
                            projectId: projectId,
                            stage: 'new',
                          ),
                        ),
                      ).then((_) => onReturn());
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UatKanbanCard extends StatelessWidget {
  final bool isDarkMode;
  final Map<String, dynamic> data;

  const _UatKanbanCard({required this.isDarkMode, required this.data});

  int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.round();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  double _asDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final name = (data['name'] ?? '').toString();
    final done = _asInt(data['done_count']);
    final todo = _asInt(data['todo_count']);
    final pct = _asDouble(data['progress_percentage']);
    final progress = (pct.clamp(0, 100)) / 100.0;
    final pctColor =
        pct >= 70 ? Colors.green : (pct >= 30 ? Colors.orange : Colors.red);

    return Card(
      elevation: 6,
      margin: const EdgeInsets.only(bottom: 12),
      color: isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.85),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    name.isEmpty ? 'Project' : name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color:
                          isDarkMode ? Colors.white : const Color(0xFF282454),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'UAT',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.white70 : Colors.grey[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(child: SizedBox.shrink()),
                const SizedBox(width: 12),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        strokeWidth: 2.2,
                        value: progress.isNaN ? 0 : progress,
                        backgroundColor:
                            isDarkMode ? Colors.white24 : Colors.black12,
                        valueColor: AlwaysStoppedAnimation<Color>(pctColor),
                      ),
                      Text(
                        '${pct.toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 6.5,
                          fontWeight: FontWeight.w800,
                          color: pctColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CountButton(
                    label: 'Done',
                    value: done,
                    background: Colors.green,
                    foreground: Colors.white,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Open UAT Done list: coming soon')),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CountButton(
                    label: 'To Do',
                    value: todo,
                    background: Colors.red,
                    foreground: Colors.white,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Open UAT To Do list: coming soon')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final bool isDarkMode;
  final String title;
  final String message;

  const _InfoCard(
      {required this.isDarkMode, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.85),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? Colors.white : const Color(0xFF282454),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black87),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final bool isDarkMode;
  final String title;
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({
    required this.isDarkMode,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.85),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: isDarkMode ? Colors.white : const Color(0xFF282454),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF282454),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
