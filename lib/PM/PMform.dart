import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_app_file/open_app_file.dart';
import 'package:signature/signature.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../odoo_service.dart';

class PMFormPage extends StatefulWidget {
  final int pmId;
  final String serialNumberTitle; // shown on header

  const PMFormPage({
    Key? key,
    required this.pmId,
    required this.serialNumberTitle,
  }) : super(key: key);

  @override
  State<PMFormPage> createState() => _PMFormPageState();
}

class _PMFormPageState extends State<PMFormPage> {
  final OdooService _odoo = OdooService();
  Future<Map<String, dynamic>?>? _future;
  Future<List<Map<String, dynamic>>>? _tasksFuture;
  List<Map<String, dynamic>> _tasks = const [];
  bool _isDarkMode = false;
  bool _signatureFieldsInitialized = false;
  bool _isSavingUserSignature = false;
  bool _isSavingPicSignature = false;
  bool _isDownloadingReport = false;
  bool _reportDialogVisible = false;
  bool _showUserSignatureEditor = false;
  bool _showPicSignatureEditor = false;
  bool _showTechnicianPicker = false;
  bool _isLoadingAttachments = false;
  bool _showRemarksEditor = false;
  bool _isBulkUpdatingTasks = false;
  bool _isLoadingTechnicians = false;
  bool _canEditTasks = true;
  bool _isNetworkPm = false;
  bool _pmUpdated = false;
  // Signature type: true = User Signature (auto-fill), false = Representative
  bool _signatureTypeIsUser = true;
  String _lastKnownTechnician = '';
  String _lastKnownEquipmentUser = '';
  List<Map<String, dynamic>> _technicians = const [];
  final SignatureController _userSignatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );
  final SignatureController _picSignatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
  );
  final TextEditingController _representativeController =
      TextEditingController();
  final TextEditingController _picNameController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

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
    _userSignatureController.dispose();
    _picSignatureController.dispose();
    _representativeController.dispose();
    _picNameController.dispose();
    _remarksController.dispose();
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
      _future = _odoo.fetchPreventiveMaintenanceDetail(widget.pmId);
      _tasksFuture = _odoo.fetchMaintenanceTasksByPmId(widget.pmId);
    });
    _future?.then((value) {
      if (!mounted || value == null) return;
      final type = (value['equipment_type'] ?? '').toString();
      final projectName = _m2oName(value['project_id']);
      final subject = (value['name'] ?? '').toString();
      final isNetworkByType = _isNetworkEquipmentType(type);
      final isNetworkByProject = _isNetworkProject(projectName, subject);
      final isNetwork = isNetworkByType || isNetworkByProject;
      final tech = _m2oName(value['technician']);
      final eqUser = (value['equipment_user'] ?? '').toString().trim();
      final cleanEqUser =
          (eqUser.toLowerCase() == 'false' || eqUser.toLowerCase() == 'null')
              ? ''
              : eqUser;
      setState(() {
        if (isNetwork != _isNetworkPm) _isNetworkPm = isNetwork;
        _lastKnownTechnician = tech;
        _lastKnownEquipmentUser = cleanEqUser;
      });
    }).catchError((_) {});
    _tasksFuture?.then((value) {
      if (!mounted) return;
      setState(() => _tasks = value);
    }).catchError((_) {});
  }

  String _m2oName(dynamic v) {
    if (v is List && v.length >= 2) return v[1]?.toString() ?? '';
    return v?.toString() ?? '';
  }

  bool _isEmptyValue(String value) {
    final cleaned = value.trim().toLowerCase();
    return cleaned.isEmpty ||
        cleaned == 'false' ||
        cleaned == '-' ||
        cleaned == 'null';
  }

  String _cleanFieldValue(String v) {
    final t = v.trim().toLowerCase();
    if (t == 'false' || t == 'null') return '';
    return v.trim();
  }

  String _cleanEditValue(String v) {
    final t = v.trim().toLowerCase();
    if (t == 'false' || t == 'null') return '';
    return v.trim();
  }

  int _countWords(String text) {
    if (text.trim().isEmpty) return 0;
    return text.trim().split(RegExp(r'\s+')).length;
  }

  double _getCategoryFontSize(String category) {
    final wordCount = _countWords(category);
    return wordCount > 3 ? 10.0 : 12.0;
  }

  Widget _buildRow(String label, String value) {
    final cleaned = _isEmptyValue(value) ? '' : value.trim();
    final display = cleaned.isEmpty ? '-' : cleaned;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _isDarkMode ? Colors.white70 : Colors.black54,
              ),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: TextStyle(
                color: _isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadTechnicians() async {
    if (_isLoadingTechnicians || _technicians.isNotEmpty) return;
    setState(() => _isLoadingTechnicians = true);
    try {
      final list = await _odoo.fetchTechnicians();
      if (!mounted) return;
      setState(() => _technicians = list);
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _isLoadingTechnicians = false);
    }
  }

  Future<void> _saveTechnician(int technicianId, String name) async {
    try {
      await _odoo.updatePreventiveMaintenanceTechnician(
        pmId: widget.pmId,
        technicianId: technicianId,
      );
      if (!mounted) return;
      setState(() {
        _showTechnicianPicker = false;
        _lastKnownTechnician = name;
      });
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Technician set to $name')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan technician: $e')),
      );
    }
  }

  Widget _buildSignatureImage(String? base64Str) {
    final raw = (base64Str ?? '').trim();
    if (raw.isEmpty || raw.toLowerCase() == 'false') {
      return const SizedBox.shrink();
    }
    try {
      final bytes = base64Decode(raw);
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, height: 140, fit: BoxFit.contain),
      );
    } catch (_) {
      return const Text('-', style: TextStyle(color: Colors.black54));
    }
  }

  String _formatDate(String raw) {
    final cleaned = raw.trim();
    if (_isEmptyValue(cleaned)) return '';
    final parsed = DateTime.tryParse(cleaned);
    if (parsed == null) return cleaned;
    return DateFormat('dd/MM/yyyy').format(parsed);
  }

  bool _hasSignature(String? base64Str) {
    final raw = (base64Str ?? '').trim();
    if (raw.isEmpty || raw.toLowerCase() == 'false') return false;
    return true;
  }

  String _todayDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _saveUserSignature() async {
    final name = _representativeController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please fill the name field before saving')),
      );
      return;
    }
    if (_userSignatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please draw the signature before saving')),
      );
      return;
    }
    if (_lastKnownTechnician.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please select a technician first (Technician Signature section)')),
      );
      return;
    }
    setState(() => _isSavingUserSignature = true);
    try {
      final bytes = await _userSignatureController.toPngBytes();
      if (bytes == null) {
        throw Exception('Failed to capture user signature');
      }
      final stageUpdated = await _odoo.updatePreventiveMaintenanceSignatures(
        pmId: widget.pmId,
        userSignatureBytes: bytes,
        representativeName: _representativeController.text.trim(),
        userSignatureDate: _todayDate(),
        markDone: true,
      );
      _refresh();
      _pmUpdated = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User signature saved')),
      );
      if (stageUpdated == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Signature saved. Stage could not be set to Done (Odoo server needs fix).'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan user signature: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingUserSignature = false);
    }
  }

  Future<void> _deleteUserSignature() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete User Signature'),
        content: const Text(
            'Remove user signature from this PM form and from the server?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isSavingUserSignature = true);
    try {
      await _odoo.clearPreventiveMaintenanceSignatures(
          pmId: widget.pmId, clearUser: true);
      _userSignatureController.clear();
      _representativeController.clear();
      setState(() => _showUserSignatureEditor = false);
      _refresh();
      _pmUpdated = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User signature deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal padam signature: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSavingUserSignature = false);
    }
  }

  Future<void> _savePicSignature() async {
    if (_picSignatureController.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide PIC signature')),
      );
      return;
    }
    setState(() => _isSavingPicSignature = true);
    try {
      final bytes = await _picSignatureController.toPngBytes();
      if (bytes == null) {
        throw Exception('Failed to capture PIC signature');
      }
      final stageUpdated = await _odoo.updatePreventiveMaintenanceSignatures(
        pmId: widget.pmId,
        picSignatureBytes: bytes,
        picName: _picNameController.text.trim(),
        picSignatureDate: _todayDate(),
        markDone: true,
      );
      _refresh();
      _pmUpdated = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIC signature saved')),
      );
      if (stageUpdated == false && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Signature saved. Stage could not be set to Done (Odoo server needs fix).'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal simpan PIC signature: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingPicSignature = false);
    }
  }

  Future<void> _deletePicSignature() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete PIC Signature'),
        content: const Text(
            'Remove PIC signature from this PM form and from the server?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isSavingPicSignature = true);
    try {
      await _odoo.clearPreventiveMaintenanceSignatures(
          pmId: widget.pmId, clearPic: true);
      _picSignatureController.clear();
      _picNameController.clear();
      setState(() => _showPicSignatureEditor = false);
      _refresh();
      _pmUpdated = true;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIC signature deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal padam PIC signature: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSavingPicSignature = false);
    }
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

  Future<void> _downloadReport(_ReportOption option) async {
    if (_isDownloadingReport) return;
    setState(() => _isDownloadingReport = true);
    _showLoadingDialog();
    try {
      final bytes = await _odoo.fetchPreventiveMaintenanceReportPdf(
        pmId: widget.pmId,
        reportName: option.reportName,
      );
      if (bytes.isEmpty) {
        throw Exception('PDF kosong');
      }
      final fileName = _safeFileName('${option.label}-${widget.pmId}.pdf');
      final file = File('${Directory.systemTemp.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenAppFile.open(file.path);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF disimpan: ${file.path}')),
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

  String _taskLabel(Map<String, dynamic> task) {
    final name = (task['name'] ?? '').toString().trim();
    if (name.isNotEmpty && name.toLowerCase() != 'false') return name;
    final equipmentTask = (task['equipment_task'] ?? '').toString().trim();
    if (equipmentTask.isNotEmpty && equipmentTask.toLowerCase() != 'false')
      return equipmentTask;
    return 'Task';
  }

  String _taskNote(Map<String, dynamic> task) {
    final note = (task['note'] ?? '').toString().trim();
    if (note.isNotEmpty && note.toLowerCase() != 'false') return note;
    final remarks = (task['remarks'] ?? '').toString().trim();
    if (remarks.toLowerCase() == 'false') return '';
    return remarks;
  }

  String _taskCategory(Map<String, dynamic> task) {
    final categoryId = task['category_id'];
    if (categoryId is List && categoryId.length >= 2) {
      return categoryId[1]?.toString() ?? 'Others';
    }
    final category = (task['category'] ?? '').toString().trim();
    if (category.isNotEmpty) return category;
    final equipment = task['equipment'];
    if (equipment is List && equipment.length >= 2) {
      return equipment[1]?.toString() ?? 'Others';
    }
    return 'Others';
  }

  bool _taskChecked(Map<String, dynamic> task) {
    if (_isNetworkPm) {
      final isYes = task['is_yes'];
      if (isYes is bool) return isYes;
      final isNo = task['is_no'];
      if (isNo is bool) return !isNo;
      return false;
    }
    final check = task['check'];
    if (check is bool) return check;
    return false;
  }

  bool _isNetworkEquipmentType(String type) {
    final cleaned = type.trim().toLowerCase();
    return cleaned == 'switch' || cleaned == 'firewall' || cleaned == 'wifi';
  }

  bool _isNetworkProject(String projectName, String subject) {
    final projectLower = projectName.trim().toLowerCase();
    final subjectLower = subject.trim().toLowerCase();
    return projectLower.contains('network') || subjectLower.contains('network');
  }

  bool _isNetworkYes(Map<String, dynamic> task) {
    final isYes = task['is_yes'];
    return isYes is bool && isYes == true;
  }

  bool _isNetworkNo(Map<String, dynamic> task) {
    final isNo = task['is_no'];
    return isNo is bool && isNo == true;
  }

  List<TextSpan> _getCategoryStatusSpans(
      List<Map<String, dynamic>> tasks, bool isDarkMode) {
    final spans = <TextSpan>[];

    if (_isNetworkPm) {
      // Network PM: Yes / No / No tick
      int yesCount = 0;
      int noCount = 0;
      int noTickCount = 0;

      for (final task in tasks) {
        if (_isNetworkYes(task)) {
          yesCount++;
        } else if (_isNetworkNo(task)) {
          noCount++;
        } else {
          noTickCount++;
        }
      }

      if (yesCount > 0) {
        spans.add(TextSpan(
          text: 'Yes: $yesCount',
          style: TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ));
      }

      if (noCount > 0) {
        if (spans.isNotEmpty) {
          spans.add(TextSpan(
            text: ' / ',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : const Color(0xFF282454),
              fontSize: 10,
            ),
          ));
        }
        spans.add(TextSpan(
          text: 'No: $noCount',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ));
      }

      if (noTickCount > 0) {
        if (spans.isNotEmpty) {
          spans.add(TextSpan(
            text: ' / ',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : const Color(0xFF282454),
              fontSize: 10,
            ),
          ));
        }
        spans.add(TextSpan(
          text: 'No tick: $noTickCount',
          style: TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ));
      }
    } else {
      // Non-network PM: tick / untick / total
      int tickCount = 0;
      int untickCount = 0;
      int totalCount = tasks.length;

      for (final task in tasks) {
        if (_taskChecked(task)) {
          tickCount++;
        } else {
          untickCount++;
        }
      }

      if (tickCount > 0) {
        spans.add(TextSpan(
          text: 'tick: $tickCount',
          style: TextStyle(
            color: Colors.green,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ));
      }

      if (untickCount > 0) {
        if (spans.isNotEmpty) {
          spans.add(TextSpan(
            text: ' / ',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : const Color(0xFF282454),
              fontSize: 10,
            ),
          ));
        }
        spans.add(TextSpan(
          text: 'untick: $untickCount',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ));
      }

      if (totalCount > 0) {
        if (spans.isNotEmpty) {
          spans.add(TextSpan(
            text: ' / ',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : const Color(0xFF282454),
              fontSize: 10,
            ),
          ));
        }
        spans.add(TextSpan(
          text: 'total: $totalCount',
          style: TextStyle(
            color: isDarkMode ? Colors.white70 : const Color(0xFF282454),
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
        ));
      }
    }

    if (spans.isEmpty) return [];

    return [
      TextSpan(
        text: ' (',
        style: TextStyle(
          color: isDarkMode ? Colors.white70 : const Color(0xFF282454),
          fontSize: 10,
        ),
      ),
      ...spans,
      TextSpan(
        text: ')',
        style: TextStyle(
          color: isDarkMode ? Colors.white70 : const Color(0xFF282454),
          fontSize: 10,
        ),
      ),
    ];
  }

  Future<void> _setNetworkTaskChoice(
      Map<String, dynamic> task, bool isYes) async {
    // Check current state
    final currentlyYes = _isNetworkYes(task);
    final currentlyNo = _isNetworkNo(task);

    // If clicking the same option that's already selected, toggle to the opposite
    if (isYes && currentlyYes) {
      isYes = false; // Toggle from Yes to No
    } else if (!isYes && currentlyNo) {
      isYes = true; // Toggle from No to Yes
    }
    // Otherwise, set to the clicked option (Yes or No)

    final rawId = task['id'];
    final taskId =
        (rawId is int) ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
    if (taskId <= 0) return;

    final prev = Map<String, dynamic>.from(task);

    // Update UI immediately for better responsiveness
    setState(() {
      task['is_yes'] = isYes;
      task['is_no'] = !isYes;
    });

    try {
      await _odoo.updateMaintenanceTaskStatus(
        taskId: taskId,
        isYes: isYes,
        isNo: !isYes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(isYes ? 'Task set to Yes' : 'Task set to No')),
      );
    } catch (e) {
      if (!mounted) return;
      // Revert on error
      setState(() {
        task
          ..clear()
          ..addAll(prev);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tak boleh simpan checklist: $e')),
      );
    }
  }

  Future<void> _toggleTask(Map<String, dynamic> task, bool value) async {
    final rawId = task['id'];
    final taskId =
        (rawId is int) ? rawId : int.tryParse(rawId?.toString() ?? '') ?? 0;
    if (taskId <= 0) return;

    final prev = Map<String, dynamic>.from(task);
    setState(() {
      if (!_isNetworkPm && task['check'] is bool) {
        task['check'] = value;
      }
      if (_isNetworkPm && task.containsKey('is_yes')) {
        // For network PM: value=true means Yes, value=false means no tick (both false)
        task['is_yes'] = value;
      }
      if (_isNetworkPm && task.containsKey('is_no')) {
        // When unticking, set is_no to false (no tick), not true
        task['is_no'] = false;
      }
    });

    try {
      await _odoo.updateMaintenanceTaskStatus(
        taskId: taskId,
        check: _isNetworkPm ? null : value,
        isYes: _isNetworkPm ? value : null,
        isNo: _isNetworkPm
            ? false
            : null, // Always false when unticking (no tick, not No)
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(value ? 'Task ticked' : 'Task unticked')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        task
          ..clear()
          ..addAll(prev);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tak boleh simpan checklist: $e')),
      );
    }
  }

  Future<void> _setAllTasks(bool value) async {
    if (_isBulkUpdatingTasks || _tasks.isEmpty) return;
    setState(() => _isBulkUpdatingTasks = true);
    final ids = <int>[];

    setState(() {
      for (final task in _tasks) {
        final id = (task['id'] is int)
            ? task['id'] as int
            : int.tryParse(task['id'].toString()) ?? 0;
        if (id <= 0) continue;
        if (_isNetworkPm && task.containsKey('is_yes')) {
          // For network PM: value=true means Yes, value=false means no tick (both false)
          task['is_yes'] = value;
        }
        if (_isNetworkPm && task.containsKey('is_no')) {
          // When unticking all, set is_no to false (no tick), not true
          task['is_no'] = false;
        }
        if (!_isNetworkPm && task['check'] is bool) {
          task['check'] = value;
        }
        ids.add(id);
      }
    });

    try {
      await _odoo.updateMaintenanceTasksBulk(
        taskIds: ids,
        values: {
          if (!_isNetworkPm) "check": value,
          if (_isNetworkPm) "is_yes": value,
          if (_isNetworkPm)
            "is_no":
                false, // Always false when using select all (no tick, not No)
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(value ? 'All tasks ticked' : 'All tasks unticked')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tak boleh simpan checklist: $e')),
      );
      _refresh();
    } finally {
      if (mounted) setState(() => _isBulkUpdatingTasks = false);
    }
  }

  Widget _buildChecklistCard() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _tasksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _tasks.isEmpty) {
          return Card(
            elevation: 6,
            color: _isDarkMode
                ? Colors.black.withOpacity(0.55)
                : Colors.white.withOpacity(0.9),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        if (snapshot.hasError && _tasks.isEmpty) {
          return _CardBox(
            isDarkMode: _isDarkMode,
            title: 'Tak boleh load checklist',
            message: snapshot.error.toString(),
            actionLabel: 'Retry',
            onPressed: _refresh,
          );
        }

        final tasks = _tasks;
        if (tasks.isEmpty) {
          return const _InfoBox(
              title: 'Checklist kosong', message: 'Tiada task untuk PM ini.');
        }

        final allChecked = tasks.isNotEmpty && tasks.every(_taskChecked);
        final anyChecked = tasks.any(_taskChecked);
        final noneChecked = !anyChecked;
        final grouped = <String, List<Map<String, dynamic>>>{};
        for (final task in tasks) {
          final category = _taskCategory(task);
          grouped.putIfAbsent(category, () => []).add(task);
        }
        final categoryKeys = grouped.keys.toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

        return Card(
          elevation: 6,
          color: _isDarkMode
              ? Colors.black.withOpacity(0.55)
              : Colors.white.withOpacity(0.9),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isNetworkPm
                            ? 'Network Maintenance Tasks'
                            : 'Maintenance Tasks',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: _isDarkMode
                              ? Colors.white
                              : const Color(0xFF282454),
                        ),
                      ),
                    ),
                    if (allChecked || noneChecked) ...[
                      Text(
                        allChecked ? 'All tick' : 'No tick',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _isDarkMode ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'Tick All',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    Transform.scale(
                      scale: 0.85,
                      child: Switch(
                        value: allChecked,
                        onChanged: _isBulkUpdatingTasks ? null : _setAllTasks,
                        activeColor: const Color(0xFF282454),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final category in categoryKeys)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: _isDarkMode ? Colors.white10 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: _isDarkMode
                              ? Colors.white24
                              : Colors.grey.shade200),
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              category,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: _getCategoryFontSize(category),
                                color: _isDarkMode
                                    ? Colors.white70
                                    : const Color(0xFF282454),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          if (_getCategoryStatusSpans(
                                  grouped[category]!, _isDarkMode)
                              .isNotEmpty)
                            RichText(
                              text: TextSpan(
                                children: _getCategoryStatusSpans(
                                    grouped[category]!, _isDarkMode),
                              ),
                            ),
                        ],
                      ),
                      trailing: Icon(
                        Icons.expand_more,
                        color: _isDarkMode
                            ? Colors.white54
                            : const Color(0xFF282454),
                      ),
                      children: [
                        for (final task in grouped[category]!)
                          Builder(
                            builder: (context) {
                              final note = _taskNote(task);
                              return Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _taskLabel(task),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            if (note.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2),
                                                child: Text(
                                                  note,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: _isDarkMode
                                                        ? Colors.white60
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (_isNetworkPm)
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            GestureDetector(
                                              onTap: _canEditTasks
                                                  ? () => _setNetworkTaskChoice(
                                                      task, true)
                                                  : null,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Yes',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: _isDarkMode
                                                          ? Colors.white70
                                                          : Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Checkbox(
                                                    value: _isNetworkYes(task),
                                                    onChanged: _canEditTasks
                                                        ? (_) =>
                                                            _setNetworkTaskChoice(
                                                                task, true)
                                                        : null,
                                                    activeColor:
                                                        const Color(0xFF282454),
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            GestureDetector(
                                              onTap: _canEditTasks
                                                  ? () => _setNetworkTaskChoice(
                                                      task, false)
                                                  : null,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'No',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: _isDarkMode
                                                          ? Colors.white70
                                                          : Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Checkbox(
                                                    value: _isNetworkNo(task),
                                                    onChanged: _canEditTasks
                                                        ? (_) =>
                                                            _setNetworkTaskChoice(
                                                                task, false)
                                                        : null,
                                                    activeColor:
                                                        Colors.redAccent,
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    visualDensity:
                                                        VisualDensity.compact,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      else
                                        Checkbox(
                                          value: _taskChecked(task),
                                          activeColor: const Color(0xFF282454),
                                          materialTapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          onChanged: _canEditTasks
                                              ? (val) {
                                                  if (val == null) return;
                                                  _toggleTask(task, val);
                                                }
                                              : null,
                                        ),
                                    ],
                                  ),
                                  Divider(
                                      height: 12,
                                      color: _isDarkMode
                                          ? Colors.white12
                                          : Colors.grey.shade300),
                                ],
                              );
                            },
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _cleanRemarksFromOdoo(dynamic value) {
    final s = (value ?? '').toString().trim();
    if (s.isEmpty) return '';
    final lower = s.toLowerCase();
    if (lower == 'false' || lower == 'null') return '';
    return s;
  }

  Widget _buildRemarksCard(Map<String, dynamic> m) {
    final rawRemarks = m['other_remarks'] ?? m['remarks'] ?? '';
    final remarks = _cleanRemarksFromOdoo(rawRemarks);

    // Initialize remarks controller if not already initialized
    if (!_signatureFieldsInitialized) {
      _remarksController.text = remarks;
    }

    final hasRemarks = remarks.isNotEmpty;

    return Card(
      elevation: 6,
      color: _isDarkMode
          ? Colors.black.withOpacity(0.55)
          : Colors.white.withOpacity(0.9),
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
                    'Other Remarks / Note',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color:
                          _isDarkMode ? Colors.white : const Color(0xFF282454),
                    ),
                  ),
                ),
                if (!_showRemarksEditor)
                  IconButton(
                    icon: Icon(Icons.edit,
                        color: _isDarkMode
                            ? Colors.white
                            : const Color(0xFF282454),
                        size: 20),
                    onPressed: () {
                      setState(() {
                        _showRemarksEditor = true;
                        _remarksController.text = remarks;
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!_showRemarksEditor && hasRemarks)
              Text(
                remarks,
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
              )
            else if (_showRemarksEditor) ...[
              TextField(
                controller: _remarksController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Enter remarks or notes...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: _isDarkMode ? Colors.white10 : Colors.grey.shade50,
                ),
                style: TextStyle(
                  color: _isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showRemarksEditor = false;
                        _remarksController.text = remarks; // Reset to original
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _saveRemarks(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF282454),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _guessMimeType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  Future<_PendingAttachment?> _pickFileAttachment() async {
    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return null;
    final file = picked.files.first;
    final bytes = file.bytes ?? await File(file.path!).readAsBytes();
    final name = file.name;
    final mime = _guessMimeType(name);
    return _PendingAttachment(name: name, bytes: bytes, mime: mime);
  }

  Future<_PendingAttachment?> _pickImageFromCamera() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.camera);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name;
    final mime = _guessMimeType(name);
    return _PendingAttachment(name: name, bytes: bytes, mime: mime);
  }

  Future<_PendingAttachment?> _pickImageFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final name = file.name;
    final mime = _guessMimeType(name);
    return _PendingAttachment(name: name, bytes: bytes, mime: mime);
  }

  Future<bool> _uploadAttachmentBytes({
    required String name,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final ok = await _odoo.uploadPmAttachment(
      pmId: widget.pmId,
      fileName: name,
      bytes: bytes,
      mimeType: mimeType,
    );
    if (!mounted) return ok;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal upload attachment')),
      );
    }
    return ok;
  }

  String _buildAttachmentUrl(String rawUrl, int id) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      return '${_odoo.baseUrl}/web/content/$id?download=1';
    }
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return '${_odoo.baseUrl}$path';
  }

  Future<Map<String, String>> _attachmentHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    String? cookie = prefs.getString('session_id');
    final sessId = prefs.getString('sessionId') ?? '';
    if ((cookie == null || cookie.isEmpty) && sessId.isNotEmpty) {
      cookie = 'session_id=$sessId';
    }
    if (cookie == null || cookie.isEmpty) {
      await _odoo.checkAndLoadUserCredentials();
      final refreshed = await SharedPreferences.getInstance();
      cookie = refreshed.getString('session_id');
      final refreshedSessId = refreshed.getString('sessionId') ?? '';
      if ((cookie == null || cookie.isEmpty) && refreshedSessId.isNotEmpty) {
        cookie = 'session_id=$refreshedSessId';
      }
    }
    return {
      if (cookie != null && cookie.isNotEmpty) 'Cookie': cookie,
    };
  }

  Future<Uint8List> _fetchAttachmentBytes({
    required int id,
    required String rawUrl,
    required String name,
  }) async {
    String fileName = name.trim().isEmpty ? 'attachment' : name.trim();
    final encodedName = Uri.encodeComponent(fileName);
    final base = _odoo.baseUrl;
    final candidates = <String>[];

    if (rawUrl.trim().isNotEmpty) {
      final u = _buildAttachmentUrl(rawUrl, id);
      candidates.add(u);
      candidates.add(
          '$u${u.contains('?') ? '&' : '?'}download=1&filename=$encodedName');
    }

    candidates.add('$base/web/content/$id?download=1&filename=$encodedName');
    candidates.add('$base/web/content/$id/$encodedName?download=1');
    candidates.add('$base/web/content/$id');

    final headers = await _attachmentHeaders();
    int? lastStatus;
    for (final url in candidates) {
      final resp = await http.get(Uri.parse(url), headers: headers);
      lastStatus = resp.statusCode;
      if (resp.statusCode == 200) {
        return resp.bodyBytes;
      }
    }

    // Retry once with refreshed session cookie
    await _odoo.checkAndLoadUserCredentials();
    final refreshedHeaders = await _attachmentHeaders();
    for (final url in candidates) {
      final resp = await http.get(Uri.parse(url), headers: refreshedHeaders);
      lastStatus = resp.statusCode;
      if (resp.statusCode == 200) {
        return resp.bodyBytes;
      }
    }

    throw Exception('HTTP ${lastStatus ?? 0}');
  }

  Future<void> _openImagePreview({
    required int id,
    required String rawUrl,
    required String name,
  }) async {
    try {
      final bytes =
          await _fetchAttachmentBytes(id: id, rawUrl: rawUrl, name: name);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.black,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Center(
                      child: Text('Gagal load image',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Text(
                  name,
                  style: const TextStyle(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal buka image: $e')),
      );
    }
  }

  Future<void> _downloadAndOpenAttachment({
    required int id,
    required String rawUrl,
    required String name,
  }) async {
    try {
      final bytes =
          await _fetchAttachmentBytes(id: id, rawUrl: rawUrl, name: name);
      final fileName = _safeFileName(name.isEmpty ? 'attachment' : name);
      final file = File('${Directory.systemTemp.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenAppFile.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal buka attachment: $e')),
      );
    }
  }

  IconData _attachmentIcon(String? mime) {
    if (mime == null || mime.isEmpty) return Icons.insert_drive_file;
    final lower = mime.toLowerCase();
    if (lower.startsWith('image/')) return Icons.image;
    if (lower == 'application/pdf') return Icons.picture_as_pdf;
    if (lower.contains('word')) return Icons.description;
    if (lower.contains('excel') || lower.contains('spreadsheet'))
      return Icons.table_chart;
    return Icons.insert_drive_file;
  }

  Future<void> _showAttachmentsDialog() async {
    if (_isLoadingAttachments) return;
    setState(() => _isLoadingAttachments = true);
    var attachments = await _odoo.getPmAttachments(widget.pmId);
    if (!mounted) return;
    setState(() => _isLoadingAttachments = false);

    await showDialog<void>(
      context: context,
      builder: (context) {
        bool isUploading = false;
        final List<_PendingAttachment> pending = [];
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> refreshLocal() async {
              final latest = await _odoo.getPmAttachments(widget.pmId);
              setLocalState(() => attachments = latest);
            }

            Future<void> handlePick(
              Future<_PendingAttachment?> Function() picker,
            ) async {
              if (isUploading) return;
              setLocalState(() => isUploading = true);
              final picked = await picker();
              if (picked != null) {
                pending.add(picked);
              }
              setLocalState(() => isUploading = false);
            }

            Future<void> confirmDelete(int attachmentId, String name) async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Delete attachment?'),
                    content:
                        Text('Delete ${name.isEmpty ? 'this file' : name}?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Delete'),
                      ),
                    ],
                  );
                },
              );
              if (confirmed == true) {
                setLocalState(() => isUploading = true);
                final ok = await _odoo.deletePmAttachment(attachmentId);
                setLocalState(() => isUploading = false);
                if (ok) {
                  await refreshLocal();
                } else {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Gagal delete attachment')),
                    );
                  }
                }
              }
            }

            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Container(
                constraints:
                    const BoxConstraints(maxWidth: 500, maxHeight: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF282454),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.attach_file,
                              color: Colors.white, size: 24),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Attachments',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    // Content
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isUploading)
                              const Padding(
                                padding: EdgeInsets.all(16),
                                child:
                                    Center(child: CircularProgressIndicator()),
                              ),
                            if (pending.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.orange.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.pending_actions,
                                        color: Colors.orange.shade700,
                                        size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Pending uploads (${pending.length})',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange.shade900,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...pending.map((p) => Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                    ),
                                    child: ListTile(
                                      leading: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.orange.shade100,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Icon(_attachmentIcon(p.mime),
                                            color: Colors.orange.shade700,
                                            size: 20),
                                      ),
                                      title: Text(
                                        p.name.isEmpty ? 'Attachment' : p.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 13),
                                      ),
                                      subtitle: Text(
                                        p.mime,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600),
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.close,
                                            color: Colors.red, size: 20),
                                        onPressed: () {
                                          setLocalState(
                                              () => pending.remove(p));
                                        },
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 4),
                                    ),
                                  )),
                              const Divider(height: 24),
                            ],
                            if (attachments.isEmpty && pending.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    children: [
                                      Icon(Icons.attach_file,
                                          size: 48,
                                          color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text(
                                        'No attachments',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            else if (attachments.isNotEmpty) ...[
                              Text(
                                'Uploaded Attachments',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...attachments.asMap().entries.map((entry) {
                                final att = entry.value;
                                final id = att['id'] is int
                                    ? att['id']
                                    : int.tryParse(
                                            att['id']?.toString() ?? '') ??
                                        0;
                                final name = (att['name'] ?? '').toString();
                                final mime = (att['mimetype'] ?? '').toString();
                                final rawUrl = (att['url'] ?? '').toString();
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.shade200,
                                        blurRadius: 2,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: ListTile(
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF282454)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Icon(
                                        _attachmentIcon(mime),
                                        color: const Color(0xFF282454),
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(
                                      name.isEmpty ? 'Attachment $id' : name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    subtitle: Text(
                                      mime.isEmpty ? 'Unknown type' : mime,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red, size: 20),
                                      onPressed: isUploading
                                          ? null
                                          : () => confirmDelete(id, name),
                                    ),
                                    onTap: () async {
                                      if (mime
                                          .toLowerCase()
                                          .startsWith('image/')) {
                                        await _openImagePreview(
                                            id: id, rawUrl: rawUrl, name: name);
                                      } else {
                                        await _downloadAndOpenAttachment(
                                            id: id, rawUrl: rawUrl, name: name);
                                      }
                                    },
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      ),
                    ),
                    // Actions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isUploading
                                      ? null
                                      : () => handlePick(_pickImageFromCamera),
                                  icon: const Icon(Icons.camera_alt, size: 18),
                                  label: const Text('Camera',
                                      style: TextStyle(fontSize: 10)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isUploading
                                      ? null
                                      : () => handlePick(_pickImageFromGallery),
                                  icon: const Icon(Icons.image, size: 18),
                                  label: const Text('Gallery',
                                      style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: isUploading
                                      ? null
                                      : () => handlePick(_pickFileAttachment),
                                  icon: const Icon(Icons.attach_file, size: 18),
                                  label: const Text('File',
                                      style: TextStyle(fontSize: 12)),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: isUploading
                                  ? null
                                  : () async {
                                      if (pending.isEmpty) {
                                        Navigator.pop(context);
                                        return;
                                      }
                                      setLocalState(() => isUploading = true);
                                      for (final p in pending) {
                                        await _uploadAttachmentBytes(
                                          name: p.name,
                                          bytes: p.bytes,
                                          mimeType: p.mime,
                                        );
                                      }
                                      setLocalState(() {
                                        isUploading = false;
                                        pending.clear();
                                      });
                                      await refreshLocal();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content:
                                                  Text('Attachments uploaded')),
                                        );
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: pending.isEmpty
                                    ? Colors.grey
                                    : const Color(0xFF282454),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                pending.isEmpty
                                    ? 'Close'
                                    : 'Upload ${pending.length} Attachment${pending.length > 1 ? 's' : ''}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
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

  Future<void> _saveRemarks() async {
    final remarks = _remarksController.text.trim();
    try {
      await _odoo.updatePreventiveMaintenanceRemarks(
        pmId: widget.pmId,
        remarks: remarks,
      );
      if (!mounted) return;
      setState(() {
        _showRemarksEditor = false;
      });
      _refresh();
      _pmUpdated = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Remarks saved successfully')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save remarks: $e')),
      );
    }
  }

  Future<void> _showEquipmentDetailsEditor({
    required int pmId,
    required String serial,
    required String product,
    required String equipmentType,
    required String ip,
    required String rackNo,
  }) async {
    final serialCtrl = TextEditingController(text: _cleanEditValue(serial));
    final productCtrl = TextEditingController(text: _cleanEditValue(product));
    final typeCtrl =
        TextEditingController(text: _cleanEditValue(equipmentType));
    final ipCtrl = TextEditingController(text: _cleanEditValue(ip));
    final rackCtrl = TextEditingController(text: _cleanEditValue(rackNo));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Equipment Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: serialCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Serial Number', isDense: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: productCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Brand/Model', isDense: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Equipment Type', isDense: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: ipCtrl,
                  decoration:
                      const InputDecoration(labelText: 'IP', isDense: true)),
              const SizedBox(height: 12),
              TextField(
                  controller: rackCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Rack No', isDense: true)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: const Text('Save changes?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _odoo.updatePreventiveMaintenanceFields(
        pmId: pmId,
        fields: {
          'lot_product': productCtrl.text.trim(),
          'equipment_type': typeCtrl.text.trim(),
          'lot_ip_address': ipCtrl.text.trim(),
          'rack_no': rackCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      _refresh();
      setState(() => _pmUpdated = true);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Equipment details saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  Future<void> _showUserDetailsEditor({
    required int pmId,
    required String location,
    required String user,
    required String dept,
    required String email,
    required String phone,
  }) async {
    final locCtrl = TextEditingController(text: _cleanEditValue(location));
    final userCtrl = TextEditingController(text: _cleanEditValue(user));
    final deptCtrl = TextEditingController(text: _cleanEditValue(dept));
    final emailCtrl = TextEditingController(text: _cleanEditValue(email));
    final phoneCtrl = TextEditingController(text: _cleanEditValue(phone));
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit User Details'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: locCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Location', isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: userCtrl,
                  decoration: const InputDecoration(
                      labelText: 'User Name', isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: deptCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Department', isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: emailCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Email', isDense: true)),
              const SizedBox(height: 8),
              TextField(
                  controller: phoneCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Phone', isDense: true)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm'),
        content: const Text('Save changes?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF282454),
                foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _odoo.updatePreventiveMaintenanceFields(
        pmId: pmId,
        fields: {
          'lot_department': deptCtrl.text.trim(),
          'equipment_user': userCtrl.text.trim(),
          'lot_user_mail': emailCtrl.text.trim(),
          'lot_user_no': phoneCtrl.text.trim(),
        },
      );
      if (!mounted) return;
      _refresh();
      setState(() => _pmUpdated = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('User details saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.serialNumberTitle.isEmpty
        ? 'Serial Number'
        : widget.serialNumberTitle;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, _pmUpdated);
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: FutureBuilder<Map<String, dynamic>?>(
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
                      _CardBox(
                        isDarkMode: _isDarkMode,
                        title: 'Tak boleh load PM form',
                        message: snapshot.error.toString(),
                        actionLabel: 'Retry',
                        onPressed: _refresh,
                      ),
                    ],
                  );
                }

                final m = snapshot.data;
                if (m == null) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _CardBox(
                        isDarkMode: _isDarkMode,
                        title: 'Tiada data',
                        message: 'PM record not found.',
                        actionLabel: 'Retry',
                        onPressed: _refresh,
                      ),
                    ],
                  );
                }

                final project = _m2oName(m['project_id']);
                final zone = _m2oName(m['zone_id']);
                final location = _cleanFieldValue(_m2oName(m['lot_location']));
                final serial = _cleanFieldValue(
                    (m['lot_serial_number'] ?? _m2oName(m['serial_number_id']))
                        .toString());
                final user =
                    _cleanFieldValue((m['equipment_user'] ?? '').toString());
                final dept =
                    _cleanFieldValue((m['lot_department'] ?? '').toString());
                final ip =
                    _cleanFieldValue((m['lot_ip_address'] ?? '').toString());
                final email =
                    _cleanFieldValue((m['lot_user_mail'] ?? '').toString());
                final phone =
                    _cleanFieldValue((m['lot_user_no'] ?? '').toString());
                final product =
                    _cleanFieldValue((m['lot_product'] ?? '').toString());
                final equipmentType =
                    _cleanFieldValue((m['equipment_type'] ?? '').toString());
                final rackNo =
                    _cleanFieldValue((m['rack_no'] ?? '').toString());
                final userSignature = m['user_signature']?.toString();
                final userSignatureDate =
                    _formatDate((m['user_signature_date'] ?? '').toString());
                final representativeNameRaw = m['representative_name'];
                final representativeName = (representativeNameRaw == null ||
                        representativeNameRaw == false ||
                        representativeNameRaw == 'false')
                    ? ''
                    : representativeNameRaw.toString().trim();
                final qrCodeUser = m['qr_code_user']?.toString();
                final technician = _m2oName(m['technician']);
                final picSignature = m['pic_sign']?.toString();
                final picSignatureDate =
                    _formatDate((m['pic_sign_date'] ?? '').toString());
                final picNameRaw = m['pic_name'];
                final picName = (picNameRaw == null ||
                        picNameRaw == false ||
                        picNameRaw == 'false')
                    ? ''
                    : picNameRaw.toString().trim();
                final qrCodePic = m['qr_code_pic']?.toString();

                if (!_signatureFieldsInitialized) {
                  // Auto-fill representative name from equipment user if no existing name saved
                  _representativeController.text =
                      representativeName.isNotEmpty ? representativeName : user;
                  _picNameController.text = picName;
                  _signatureFieldsInitialized = true;
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      elevation: 6,
                      color: _isDarkMode
                          ? Colors.black.withOpacity(0.55)
                          : Colors.white.withOpacity(0.9),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'PM Details',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                      color: _isDarkMode
                                          ? Colors.white
                                          : const Color(0xFF282454),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.attach_file,
                                    color: _isDarkMode
                                        ? Colors.white70
                                        : const Color(0xFF282454),
                                  ),
                                  tooltip: 'Attachments',
                                  onPressed: () => _showAttachmentsDialog(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    _isDarkMode ? Colors.white10 : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isDarkMode
                                      ? Colors.white24
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRow('Project', project),
                                  _buildRow('Zone', zone),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  'User Details',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: _isDarkMode
                                        ? Colors.white
                                        : const Color(0xFF282454),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: Icon(Icons.edit,
                                      color: _isDarkMode
                                          ? Colors.white70
                                          : const Color(0xFF282454),
                                      size: 20),
                                  onPressed: () => _showUserDetailsEditor(
                                    pmId: widget.pmId,
                                    location: location,
                                    user: user,
                                    dept: dept,
                                    email: email,
                                    phone: phone,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    _isDarkMode ? Colors.white10 : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isDarkMode
                                      ? Colors.white24
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRow('Location', location),
                                  _buildRow('User Name', user),
                                  _buildRow('Department', dept),
                                  _buildRow('Email', email),
                                  _buildRow('Phone', phone),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Text(
                                  'Equipment Details',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: _isDarkMode
                                        ? Colors.white
                                        : const Color(0xFF282454),
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: Icon(Icons.edit,
                                      color: _isDarkMode
                                          ? Colors.white70
                                          : const Color(0xFF282454),
                                      size: 20),
                                  onPressed: () => _showEquipmentDetailsEditor(
                                    pmId: widget.pmId,
                                    serial: serial,
                                    product: product,
                                    equipmentType: equipmentType,
                                    ip: ip,
                                    rackNo: rackNo,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color:
                                    _isDarkMode ? Colors.white10 : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _isDarkMode
                                      ? Colors.white24
                                      : Colors.grey.shade200,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRow('Serial Number', serial),
                                  _buildRow('Brand/Model', product),
                                  _buildRow('Equipment Type', equipmentType),
                                  _buildRow('IP', ip),
                                  _buildRow('Rack No', rackNo),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildChecklistCard(),
                    const SizedBox(height: 12),
                    _buildRemarksCard(m),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 6,
                      color: _isDarkMode
                          ? Colors.black.withOpacity(0.55)
                          : Colors.white.withOpacity(0.9),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Signatures',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: _isDarkMode
                                    ? Colors.white
                                    : const Color(0xFF282454),
                              ),
                            ),
                            const SizedBox(height: 8),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'User Signature',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _isDarkMode
                                      ? Colors.white70
                                      : const Color(0xFF282454),
                                ),
                              ),
                              children: [
                                // Stage is now automatic — shown read-only
                                _buildRow(
                                    'Stage', (m['stage'] ?? '').toString()),
                                const SizedBox(height: 8),
                                _buildSignatureImage(userSignature),
                                if (_hasSignature(userSignature) &&
                                    !_showUserSignatureEditor)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 20),
                                          label: const Text('Delete sign user'),
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.red),
                                          onPressed: _isSavingUserSignature
                                              ? null
                                              : _deleteUserSignature,
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.edit,
                                              color: _isDarkMode
                                                  ? Colors.white
                                                  : const Color(0xFF282454)),
                                          onPressed: () => setState(() =>
                                              _showUserSignatureEditor = true),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                _buildRow('Name', representativeName),
                                _buildRow('Date', userSignatureDate),
                                if (!_hasSignature(userSignature) ||
                                    _showUserSignatureEditor) ...[
                                  // Signature type selector
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text(
                                      'Select Signature Type:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: _isDarkMode
                                            ? Colors.white70
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Radio<bool>(
                                        value: true,
                                        groupValue: _signatureTypeIsUser,
                                        activeColor: const Color(0xFF282454),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: (v) {
                                          setState(() {
                                            _signatureTypeIsUser = true;
                                            _representativeController.text =
                                                _lastKnownEquipmentUser;
                                          });
                                        },
                                      ),
                                      const Text('User Signature',
                                          style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      Radio<bool>(
                                        value: false,
                                        groupValue: _signatureTypeIsUser,
                                        activeColor: const Color(0xFF282454),
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        onChanged: (v) {
                                          setState(() {
                                            _signatureTypeIsUser = false;
                                            _representativeController.text = '';
                                          });
                                        },
                                      ),
                                      const Text("Representative's Signature",
                                          style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _representativeController,
                                    decoration: InputDecoration(
                                      labelText: _signatureTypeIsUser
                                          ? 'User Name'
                                          : 'Representative Name',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 150,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Signature(
                                      controller: _userSignatureController,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: _isSavingUserSignature
                                            ? null
                                            : _userSignatureController.clear,
                                        style: TextButton.styleFrom(
                                            foregroundColor: Colors.red),
                                        child: const Text('Clear'),
                                      ),
                                      ElevatedButton(
                                        onPressed: _isSavingUserSignature
                                            ? null
                                            : _saveUserSignature,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF282454),
                                          foregroundColor: Colors.white,
                                        ),
                                        child: _isSavingUserSignature
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white),
                                              )
                                            : const Text('Save'),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                _buildSignatureImage(qrCodeUser),
                              ],
                            ),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'Technician Signature',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _isDarkMode
                                      ? Colors.white70
                                      : const Color(0xFF282454),
                                ),
                              ),
                              children: [
                                _buildRow('Technician', technician),
                                if (!_showTechnicianPicker)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      icon: Icon(Icons.edit,
                                          color: _isDarkMode
                                              ? Colors.white
                                              : const Color(0xFF282454)),
                                      onPressed: () {
                                        setState(
                                            () => _showTechnicianPicker = true);
                                        _loadTechnicians();
                                      },
                                    ),
                                  ),
                                if (_showTechnicianPicker)
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_isLoadingTechnicians)
                                        const Padding(
                                          padding:
                                              EdgeInsets.symmetric(vertical: 8),
                                          child: LinearProgressIndicator(
                                              color: Color(0xFF282454)),
                                        ),
                                      Autocomplete<Map<String, dynamic>>(
                                        optionsBuilder: (TextEditingValue
                                            textEditingValue) {
                                          final query = textEditingValue.text
                                              .trim()
                                              .toLowerCase();
                                          if (query.isEmpty)
                                            return _technicians;
                                          return _technicians.where((option) {
                                            final name = (option['name'] ?? '')
                                                .toString()
                                                .toLowerCase();
                                            return name.contains(query);
                                          });
                                        },
                                        displayStringForOption: (option) =>
                                            (option['name'] ?? '').toString(),
                                        onSelected: (option) {
                                          final id = (option['id'] is int)
                                              ? option['id'] as int
                                              : int.tryParse(option['id']
                                                      .toString()) ??
                                                  0;
                                          if (id > 0) {
                                            showDialog<bool>(
                                              context: context,
                                              builder: (context) {
                                                return AlertDialog(
                                                  title: const Text(
                                                      'Save technician?'),
                                                  content: Text(
                                                    'Set technician to ${option['name'] ?? ''}?',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context, false),
                                                      child:
                                                          const Text('Cancel'),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context, true),
                                                      style: ElevatedButton
                                                          .styleFrom(
                                                        backgroundColor:
                                                            const Color(
                                                                0xFF282454),
                                                        foregroundColor:
                                                            Colors.white,
                                                      ),
                                                      child: const Text('Save'),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ).then((confirmed) {
                                              if (confirmed == true) {
                                                _saveTechnician(
                                                    id,
                                                    (option['name'] ?? '')
                                                        .toString());
                                              }
                                            });
                                          }
                                        },
                                        fieldViewBuilder: (context, controller,
                                            focusNode, onFieldSubmitted) {
                                          return TextField(
                                            controller: controller,
                                            focusNode: focusNode,
                                            decoration: InputDecoration(
                                              labelText: 'Search technician',
                                              isDense: true,
                                              border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8)),
                                            ),
                                          );
                                        },
                                        optionsViewBuilder:
                                            (context, onSelected, options) {
                                          return Align(
                                            alignment: Alignment.topLeft,
                                            child: Material(
                                              elevation: 4,
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: SizedBox(
                                                width: MediaQuery.of(context)
                                                        .size
                                                        .width -
                                                    64,
                                                child: ListView.builder(
                                                  padding:
                                                      const EdgeInsets.all(8),
                                                  shrinkWrap: true,
                                                  itemCount: options.length,
                                                  itemBuilder:
                                                      (context, index) {
                                                    final option = options
                                                        .elementAt(index);
                                                    return ListTile(
                                                      dense: true,
                                                      title: Text(
                                                          (option['name'] ?? '')
                                                              .toString()),
                                                      onTap: () =>
                                                          onSelected(option),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                'PIC Signature',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: _isDarkMode
                                      ? Colors.white70
                                      : const Color(0xFF282454),
                                ),
                              ),
                              children: [
                                _buildSignatureImage(picSignature),
                                if (_hasSignature(picSignature) &&
                                    !_showPicSignatureEditor)
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton.icon(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 20),
                                          label: const Text('Delete sign'),
                                          style: TextButton.styleFrom(
                                              foregroundColor: Colors.red),
                                          onPressed: _isSavingPicSignature
                                              ? null
                                              : _deletePicSignature,
                                        ),
                                        IconButton(
                                          icon: Icon(Icons.edit,
                                              color: _isDarkMode
                                                  ? Colors.white
                                                  : const Color(0xFF282454)),
                                          onPressed: () => setState(() =>
                                              _showPicSignatureEditor = true),
                                        ),
                                      ],
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                _buildRow('Date', picSignatureDate),
                                if (!_hasSignature(picSignature) ||
                                    _showPicSignatureEditor) ...[
                                  TextField(
                                    controller: _picNameController,
                                    decoration: InputDecoration(
                                      labelText: 'PIC Signature',
                                      isDense: true,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    height: 150,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      border: Border.all(
                                          color: Colors.grey.shade300),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Signature(
                                      controller: _picSignatureController,
                                      backgroundColor: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton(
                                        onPressed: _isSavingPicSignature
                                            ? null
                                            : _picSignatureController.clear,
                                        style: TextButton.styleFrom(
                                            foregroundColor: Colors.red),
                                        child: const Text('Clear'),
                                      ),
                                      ElevatedButton(
                                        onPressed: _isSavingPicSignature
                                            ? null
                                            : _savePicSignature,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              const Color(0xFF282454),
                                          foregroundColor: Colors.white,
                                        ),
                                        child: _isSavingPicSignature
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Colors.white),
                                              )
                                            : const Text('Save'),
                                      ),
                                    ],
                                  ),
                                ],
                                const SizedBox(height: 8),
                                _buildSignatureImage(qrCodePic),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
      ),
    );
  }
}

class _PendingAttachment {
  final String name;
  final Uint8List bytes;
  final String mime;
  _PendingAttachment(
      {required this.name, required this.bytes, required this.mime});
}

class _CardBox extends StatelessWidget {
  final bool isDarkMode;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onPressed;

  const _CardBox({
    required this.isDarkMode,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onPressed,
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF282454)),
                child: Text(actionLabel),
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
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class _ReportOption {
  final String label;
  final String reportName;

  const _ReportOption(this.label, this.reportName);
}
