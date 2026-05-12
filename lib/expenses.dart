import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_app_file/open_app_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpdesk ticket/flutter_pdfview.dart';
import 'odoo_service.dart';
import 'expensedetails.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({Key? key}) : super(key: key);

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final OdooService _odoo = OdooService();

  String? userEmail;
  String? userImageBase64;
  bool _isLoading = true;
  String? _errorMessage;

  /// Totals from Odoo: to report, under validation, to be reimbursed
  double _toReportTotal = 0;
  double _underValidationTotal = 0;
  double _toBeReimbursedTotal = 0;

  /// Expense list from Odoo (hr.expense)
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _expenseReports = [];
  String _activeSection = 'my_expenses';
  bool _isCreateReportMode = false;
  final Set<int> _selectedReportExpenseIds = <int>{};
  final Set<int> _createdReportExpenseIds = <int>{};

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    _loadExpensesFromOdoo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) setState(() => userEmail = prefs.getString('email') ?? '');
    final imageBase64 = await _odoo.fetchUserImage();
    if (mounted) setState(() => userImageBase64 = imageBase64);
  }

  Future<void> _loadExpensesFromOdoo() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final ok = await _odoo.checkAndLoadUserCredentials();
      if (!ok) {
        if (mounted)
          setState(() {
            _isLoading = false;
            _errorMessage = 'Please log in again';
          });
        return;
      }
      final toReport = await _odoo.getExpenseToReportTotal();
      final underValidation = await _odoo.getExpenseUnderValidationTotal();
      final toBeReimbursed = await _odoo.getExpenseToBeReimbursedTotal();
      final list = await _odoo.fetchMyExpenses();
      final reports = await _odoo.fetchMyExpenseReports();
      final validIds = list
          .map<int>((e) => e['id'] is int
              ? e['id'] as int
              : int.tryParse(e['id']?.toString() ?? '0') ?? 0)
          .where((id) => id > 0)
          .toSet();
      if (mounted) {
        setState(() {
          _toReportTotal = toReport;
          _underValidationTotal = underValidation;
          _toBeReimbursedTotal = toBeReimbursed;
          _expenses = list;
          _expenseReports = reports;
          _selectedReportExpenseIds.removeWhere((id) => !validIds.contains(id));
          _createdReportExpenseIds.removeWhere((id) => !validIds.contains(id));
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteExpense(int expenseId, String description) async {
    final snippet = description.trim();
    final short =
        snippet.length > 100 ? '${snippet.substring(0, 100)}…' : snippet;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense'),
        content: Text('Remove this expense from Odoo?\n\n"$short"'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final err = await _odoo.deleteMyHrExpense(expenseId);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (err == null) {
      setState(() {
        _selectedReportExpenseIds.remove(expenseId);
        _createdReportExpenseIds.remove(expenseId);
      });
      messenger.showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('Expense deleted',
              style: TextStyle(color: Colors.white)),
        ),
      );
      _loadExpensesFromOdoo();
    } else {
      messenger.showSnackBar(SnackBar(content: Text(err)));
    }
  }

  bool _isToReportExpense(Map<String, dynamic> expense) {
    final state = expense['state']?.toString() ?? '';
    return state == 'draft';
  }

  List<Map<String, dynamic>> get _myExpensesSectionList =>
      List<Map<String, dynamic>>.from(_expenses);

  List<Map<String, dynamic>> get _toReportSectionList =>
      _expenses.where((expense) {
        return _isToReportExpense(expense);
      }).toList();

  void _toggleExpenseReportSelection(int expenseId, bool? checked) {
    setState(() {
      if (checked == true) {
        _selectedReportExpenseIds.add(expenseId);
      } else {
        _selectedReportExpenseIds.remove(expenseId);
      }
    });
  }

  void _openCreateReportMode() {
    setState(() {
      _activeSection = 'my_expenses';
      _isCreateReportMode = true;
    });
  }

  void _cancelCreateReportMode() {
    setState(() {
      _isCreateReportMode = false;
      _selectedReportExpenseIds.clear();
    });
  }

  Future<void> _showCreateActionsSheet() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = isDark ? Colors.white : const Color(0xFF282454);
    final subtext = isDark ? Colors.white70 : Colors.grey.shade700;

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.receipt_long_outlined, color: primary),
              title: const Text('Create Expenses'),
              subtitle: Text(
                'Open the form to add a new expense',
                style: TextStyle(color: subtext),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showAddExpenseDialog();
              },
            ),
            ListTile(
              leading: Icon(
                _isCreateReportMode
                    ? Icons.check_circle_outline
                    : Icons.assignment_add,
                color: primary,
              ),
              title: Text(
                _isCreateReportMode ? 'Submit Create Report' : 'Create Report',
              ),
              subtitle: Text(
                _isCreateReportMode
                    ? '${_selectedReportExpenseIds.length} expense selected'
                    : 'Select expenses to group into one report',
                style: TextStyle(color: subtext),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                if (_isCreateReportMode) {
                  _submitCreateReportSelection();
                } else {
                  _openCreateReportMode();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Select expense items, then tap the Create Report button to submit the report.',
                      ),
                    ),
                  );
                }
              },
            ),
            if (_isCreateReportMode)
              ListTile(
                leading: Icon(Icons.close, color: Colors.red.shade700),
                title: Text(
                  'Cancel Report Selection',
                  style: TextStyle(color: Colors.red.shade800),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _cancelCreateReportMode();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<String?> _promptCreateReportTitle() async {
    String draftTitle = '';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create report'),
        content: TextField(
          autofocus: true,
          onChanged: (value) => draftTitle = value,
          decoration: const InputDecoration(
            labelText: 'Report title',
            hintText: 'Enter report title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(draftTitle.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    return result?.trim();
  }

  Future<void> _submitCreateReportSelection() async {
    if (_selectedReportExpenseIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one expense.')),
      );
      return;
    }
    final reportTitle = await _promptCreateReportTitle();
    if (!mounted) return;
    if (reportTitle == null) return;
    if (reportTitle.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a report title.')),
      );
      return;
    }
    final selectedIds = _selectedReportExpenseIds.toList();
    final result = await _odoo.createExpenseReportFromExpenses(
      selectedIds,
      reportTitle: reportTitle,
    );
    if (!mounted) return;
    if (result.id != null) {
      setState(() {
        _createdReportExpenseIds.addAll(_selectedReportExpenseIds);
        _selectedReportExpenseIds.clear();
        _isCreateReportMode = false;
        _activeSection = 'my_report';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: Text('Report created (#${result.id})',
              style: const TextStyle(color: Colors.white)),
        ),
      );
      await _loadExpensesFromOdoo();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not create report')),
      );
    }
  }

  Future<void> _editExpenseReport(int reportId, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit report'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Report name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == currentName.trim()) return;
    final err = await _odoo.renameExpenseReport(
        reportId: reportId, newName: newName.trim());
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('Report updated',
              style: TextStyle(color: Colors.white)),
        ),
      );
      _loadExpensesFromOdoo();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _deleteExpenseReport(int reportId, String reportName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete report'),
        content: Text('Delete "$reportName"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await _odoo.deleteExpenseReport(reportId);
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('Report deleted',
              style: TextStyle(color: Colors.white)),
        ),
      );
      _loadExpensesFromOdoo();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _submitExpenseReportToManager(
      int reportId, String reportName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit to manager'),
        content: Text('Submit "$reportName" to manager?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true) return;

    final err = await _odoo.submitExpenseReportToManager(reportId);
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('Report submitted to manager',
              style: TextStyle(color: Colors.white)),
        ),
      );
      _loadExpensesFromOdoo();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _resetExpenseReportToDraft(
      int reportId, String reportName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset to draft'),
        content: Text('Reset "$reportName" back to draft?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reset')),
        ],
      ),
    );
    if (confirmed != true) return;

    final err = await _odoo.resetExpenseReportToDraft(reportId);
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('Report reset to draft',
              style: TextStyle(color: Colors.white)),
        ),
      );
      _loadExpensesFromOdoo();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _printExpenseReportPdf(int reportId, String reportName) async {
    final path =
        await _odoo.fetchExpenseSheetReportPdf(reportId, preferSigma: false);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load Expenses Report PDF')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PdfViewerPage(filePath: path)),
    );
  }

  Future<void> _printSigmaExpenseReportPdf(
      int reportId, String reportName) async {
    final path =
        await _odoo.fetchExpenseSheetReportPdf(reportId, preferSigma: true);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Could not load Sigma Expenses Report PDF')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PdfViewerPage(filePath: path)),
    );
  }

  Future<void> _openExpenseLineFromReport(int expenseId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => ExpenseDetailsPage(expenseId: expenseId)),
    );
    if (mounted) _loadExpensesFromOdoo();
  }

  Future<void> _handleReportExpenseDeleteAction({
    required int expenseId,
    required String expenseName,
    required int reportId,
    required String reportName,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Remove from report'),
              subtitle: Text(reportName),
              onTap: () => Navigator.of(ctx).pop('remove'),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
              title: Text('Delete expense',
                  style: TextStyle(color: Colors.red.shade800)),
              subtitle: Text(expenseName),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null) return;

    if (action == 'delete') {
      await _deleteExpense(expenseId, expenseName);
      return;
    }

    final err = await _odoo.removeExpenseFromReport(
      expenseId: expenseId,
      reportId: reportId,
    );
    if (!mounted) return;
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.green.shade700,
          content: const Text('Expense removed from report',
              style: TextStyle(color: Colors.white)),
        ),
      );
      _loadExpensesFromOdoo();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _showAttachmentActions(int expenseId) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload file'),
              onTap: () {
                Navigator.of(ctx).pop();
                _uploadExpenseAttachment(expenseId, fromCamera: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Camera'),
              onTap: () {
                Navigator.of(ctx).pop();
                _uploadExpenseAttachment(expenseId, fromCamera: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.attach_file),
              title: const Text('View file'),
              onTap: () {
                Navigator.of(ctx).pop();
                _showExpenseAttachmentsPopup(expenseId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadExpenseAttachment(int expenseId,
      {required bool fromCamera}) async {
    final messenger = ScaffoldMessenger.of(context);
    late Uint8List bytes;
    String fileName = 'attachment';
    String? mimeType;
    try {
      if (fromCamera) {
        final picked =
            await ImagePicker().pickImage(source: ImageSource.camera);
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        fileName = picked.name.isNotEmpty
            ? picked.name
            : 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
        mimeType = 'image/jpeg';
      } else {
        final result = await FilePicker.platform.pickFiles(withData: true);
        if (result == null || result.files.isEmpty) return;
        final f = result.files.first;
        final pickedBytes = f.bytes;
        if (pickedBytes != null) {
          bytes = pickedBytes;
        } else if (f.path != null) {
          bytes = await File(f.path!).readAsBytes();
        } else {
          messenger.showSnackBar(
              const SnackBar(content: Text('Could not read selected file')));
          return;
        }
        if (bytes.isEmpty) {
          messenger.showSnackBar(
              const SnackBar(content: Text('Could not read selected file')));
          return;
        }
        fileName = (f.name.isNotEmpty)
            ? f.name
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        mimeType =
            f.extension?.toLowerCase() == 'pdf' ? 'application/pdf' : null;
      }

      if (bytes.isEmpty) return;
      final err = await _odoo.uploadExpenseAttachment(
        expenseId: expenseId,
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (!mounted) return;
      if (err == null) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: const Text('Attachment uploaded',
                style: TextStyle(color: Colors.white)),
          ),
        );
        _loadExpensesFromOdoo();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(err)));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Future<void> _showExpenseAttachmentsPopup(int expenseId) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    const primaryColor = Color(0xFF282454);

    IconData attachmentIcon(String? mimetype) {
      final m = (mimetype ?? '').toLowerCase();
      if (m.contains('pdf')) return Icons.picture_as_pdf;
      if (m.contains('image') ||
          m.contains('jpeg') ||
          m.contains('png') ||
          m.contains('gif') ||
          m.contains('webp')) {
        return Icons.image;
      }
      return Icons.insert_drive_file;
    }

    Future<void> replaceAttachment({
      required BuildContext popupContext,
      required int expenseId,
      required int attachmentId,
      required Future<void> Function() refreshList,
    }) async {
      final source = await showModalBottomSheet<String>(
        context: popupContext,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Upload file'),
                onTap: () => Navigator.of(sheetCtx).pop('file'),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.of(sheetCtx).pop('camera'),
              ),
            ],
          ),
        ),
      );
      if (source == null) return;

      late Uint8List bytes;
      String fileName = 'attachment';
      String? mimeType;

      if (source == 'camera') {
        final picked =
            await ImagePicker().pickImage(source: ImageSource.camera);
        if (picked == null) return;
        bytes = await picked.readAsBytes();
        fileName = picked.name.isNotEmpty
            ? picked.name
            : 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
        mimeType = 'image/jpeg';
      } else {
        final result = await FilePicker.platform.pickFiles(withData: true);
        if (result == null || result.files.isEmpty) return;
        final f = result.files.first;
        final pickedBytes = f.bytes;
        if (pickedBytes != null) {
          bytes = pickedBytes;
        } else if (f.path != null) {
          bytes = await File(f.path!).readAsBytes();
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not read selected file')));
          return;
        }
        if (bytes.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Could not read selected file')));
          return;
        }
        fileName = f.name.isNotEmpty
            ? f.name
            : 'file_${DateTime.now().millisecondsSinceEpoch}';
        mimeType =
            f.extension?.toLowerCase() == 'pdf' ? 'application/pdf' : null;
      }

      final messenger = ScaffoldMessenger.of(context);
      final uploadErr = await _odoo.uploadExpenseAttachment(
        expenseId: expenseId,
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
      if (!mounted) return;
      if (uploadErr == null) {
        final deleteErr = await _odoo.deleteExpenseAttachment(attachmentId);
        if (!mounted) return;
        if (deleteErr != null) {
          messenger.showSnackBar(
            SnackBar(
                content: Text(
                    'New file uploaded, but old file could not be deleted: $deleteErr')),
          );
          await refreshList();
          _loadExpensesFromOdoo();
          return;
        }
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: const Text('Attachment replaced',
                style: TextStyle(color: Colors.white)),
          ),
        );
        await refreshList();
        _loadExpensesFromOdoo();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(uploadErr)));
      }
    }

    Future<void> deleteAttachment({
      required BuildContext popupContext,
      required int attachmentId,
      required String name,
      required Future<void> Function() refreshList,
    }) async {
      final confirmed = await showDialog<bool>(
        context: popupContext,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete attachment'),
          content: Text('Delete "$name"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final messenger = ScaffoldMessenger.of(context);
      final err = await _odoo.deleteExpenseAttachment(attachmentId);
      if (!mounted) return;
      if (err == null) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: const Text('Attachment deleted',
                style: TextStyle(color: Colors.white)),
          ),
        );
        await refreshList();
        _loadExpensesFromOdoo();
      } else {
        messenger.showSnackBar(SnackBar(content: Text(err)));
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        Future<List<Map<String, dynamic>>> attachmentsFuture =
            _odoo.getExpenseAttachments(expenseId);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> refreshList() async {
              setDialogState(() {
                attachmentsFuture = _odoo.getExpenseAttachments(expenseId);
              });
            }

            return Dialog(
              backgroundColor: isDark ? Colors.grey.shade900 : Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 400, maxHeight: 420),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.attach_file,
                              color: primaryColor, size: 24),
                          const SizedBox(width: 8),
                          Text('Attachments',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: textColor)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: FutureBuilder<List<Map<String, dynamic>>>(
                          future: attachmentsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            final list = snapshot.data ?? [];
                            if (list.isEmpty) {
                              return Center(
                                  child: Text('No attachments',
                                      style: TextStyle(color: textColor)));
                            }
                            return ListView.builder(
                              itemCount: list.length,
                              itemBuilder: (context, index) {
                                final att = list[index];
                                final id = att['id'] is int
                                    ? att['id'] as int
                                    : int.tryParse(
                                            att['id']?.toString() ?? '0') ??
                                        0;
                                final name = att['name']?.toString() ?? 'file';
                                final mimetype =
                                    att['mimetype']?.toString() ?? '';
                                return ListTile(
                                  leading: Icon(attachmentIcon(mimetype),
                                      color: primaryColor),
                                  title: Text(name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: textColor)),
                                  trailing: PopupMenuButton<String>(
                                    icon:
                                        Icon(Icons.more_vert, color: textColor),
                                    onSelected: (value) async {
                                      if (value == 'edit') {
                                        await replaceAttachment(
                                          popupContext: ctx,
                                          expenseId: expenseId,
                                          attachmentId: id,
                                          refreshList: refreshList,
                                        );
                                      } else if (value == 'delete') {
                                        await deleteAttachment(
                                          popupContext: ctx,
                                          attachmentId: id,
                                          name: name,
                                          refreshList: refreshList,
                                        );
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      const PopupMenuItem<String>(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(Icons.swap_horiz, size: 18),
                                            SizedBox(width: 8),
                                            Text('Replace file'),
                                          ],
                                        ),
                                      ),
                                      PopupMenuItem<String>(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete_outline,
                                                size: 18,
                                                color: Colors.red.shade700),
                                            const SizedBox(width: 8),
                                            Text('Delete',
                                                style: TextStyle(
                                                    color:
                                                        Colors.red.shade800)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () async {
                                    Navigator.of(ctx).pop();
                                    await _openExpenseAttachment(
                                        id: id, name: name, mimetype: mimetype);
                                  },
                                );
                              },
                            );
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
    );
  }

  Future<void> _openExpenseAttachment({
    required int id,
    required String name,
    required String mimetype,
  }) async {
    if (id <= 0) return;
    final messenger = ScaffoldMessenger.of(context);
    final m = mimetype.toLowerCase();
    final lower = name.toLowerCase();
    final isPdf = m.contains('pdf') || lower.endsWith('.pdf');
    final isImage = m.startsWith('image/') ||
        m.contains('jpeg') ||
        m.contains('png') ||
        m.contains('gif') ||
        m.contains('webp') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');

    if (isImage) {
      Uint8List? bytes = await _odoo.getExpenseAttachmentBytes(id, name);
      if ((bytes == null || bytes.isEmpty)) {
        final path = await _odoo.getExpenseAttachmentFile(id, name);
        if (path != null && path.isNotEmpty) {
          try {
            final file = File(path);
            if (await file.exists()) {
              bytes = await file.readAsBytes();
              file.deleteSync();
            }
          } catch (_) {}
        }
      }
      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Could not load image')));
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(name),
          content: Image.memory(bytes!, fit: BoxFit.contain),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(c).pop(),
                child: const Text('Close'))
          ],
        ),
      );
      return;
    }

    final path = await _odoo.getExpenseAttachmentFile(id, name);
    if (!mounted) return;
    if (path == null || path.isEmpty) {
      messenger
          .showSnackBar(const SnackBar(content: Text('Could not load file')));
      return;
    }
    if (isPdf) {
      await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => PdfViewerPage(filePath: path)));
    } else {
      await OpenAppFile.open(path);
    }
  }

  String _statusLabel(String? state) {
    if (state == null || state.isEmpty) return 'To Submit';
    switch (state) {
      case 'draft':
        return 'To Submit';
      case 'reported':
        return 'Submitted';
      case 'approved':
        return 'Approved';
      case 'done':
        return 'Paid';
      case 'refuse':
        return 'Refused';
      default:
        return state;
    }
  }

  String _getSelectedItemLabel(
      List<Map<String, dynamic>> list, int? id, String defaultLabel) {
    if (id == null) return defaultLabel;
    for (final e in list) {
      final eid = e['id'] is int
          ? e['id'] as int
          : int.tryParse(e['id']?.toString() ?? '0');
      if (eid == id) return e['name']?.toString() ?? defaultLabel;
    }
    return defaultLabel;
  }

  Color _statusColor(String? state) {
    if (state == null || state.isEmpty) return Colors.orange;
    switch (state) {
      case 'draft':
        return Colors.orange;
      case 'reported':
        return Colors.blue;
      case 'approved':
        return Colors.green;
      case 'done':
        return Colors.teal;
      case 'refuse':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Shows a searchable picker dialog for Product or Project selection.
  Future<void> _showSearchablePicker({
    required BuildContext context,
    required String title,
    required List<Map<String, dynamic>> items,
    required int? currentId,
    required void Function(int?) onSelected,
  }) async {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> filtered = List.from(items);

    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          final screenSize = MediaQuery.sizeOf(ctx);
          final dialogW = (screenSize.width - 48).clamp(280.0, 520.0);
          final dialogH = (screenSize.height * 0.65).clamp(320.0, 560.0);

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: SizedBox(
              width: dialogW,
              height: dialogH,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: StatefulBuilder(
                  builder: (ctx2, setPickerState) {
                    void filterList(String query) {
                      setPickerState(() {
                        if (query.trim().isEmpty) {
                          filtered = List.from(items);
                        } else {
                          final q = query.toLowerCase().trim();
                          filtered = items
                              .where((e) => (e['name']?.toString() ?? '')
                                  .toLowerCase()
                                  .contains(q))
                              .toList();
                        }
                      });
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(title, style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        TextField(
                          controller: searchController,
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            prefixIcon: Icon(Icons.search,
                                size: 20, color: Colors.grey.shade600),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          onChanged: filterList,
                          autofocus: true,
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Scrollbar(
                            thumbVisibility: filtered.length > 8,
                            child: ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, i) {
                                final item = filtered[i];
                                final id = item['id'] is int
                                    ? item['id'] as int
                                    : int.tryParse(
                                        item['id']?.toString() ?? '0');
                                final name = item['name']?.toString() ?? '';
                                final isSelected = id == currentId;
                                return ListTile(
                                  title: Text(
                                    name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? const Color(0xFF282454)
                                          : Colors.black87,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 2,
                                  ),
                                  leading: isSelected
                                      ? const Icon(Icons.check,
                                          color: Color(0xFF282454), size: 20)
                                      : const SizedBox(width: 20),
                                  onTap: () {
                                    onSelected(
                                        id != null && id > 0 ? id : null);
                                    Navigator.of(ctx).pop();
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      );
    } finally {
      // After route is fully removed — avoids TextField using disposed controller during teardown.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        searchController.dispose();
      });
    }
  }

  Future<void> _showAddExpenseDialog() async {
    List<Map<String, dynamic>> productList = [];
    List<Map<String, dynamic>> projectList = [];
    List<Map<String, dynamic>> taxList = [];
    try {
      productList = await _odoo.fetchExpenseProductList();
      projectList = await _odoo.fetchExpenseProjectList();
      taxList = await _odoo.fetchExpenseTaxList();
    } catch (_) {}
    if (!mounted) return;

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final TextEditingController _descriptionController =
        TextEditingController();
    final TextEditingController _totalController = TextEditingController();
    final TextEditingController _unitPriceController = TextEditingController();
    final TextEditingController _quantityController =
        TextEditingController(text: '1');
    final TextEditingController _fromController = TextEditingController();
    final TextEditingController _toController = TextEditingController();
    final TextEditingController _notesController = TextEditingController();
    int? _selectedProductId;
    int? _selectedProjectId;
    int? _selectedTaxId;
    String _selectedProjectSalesOrder = '';
    String _selectedAnalyticAccount = '';
    String _selectedCurrency = 'MYR';
    String? _selectedWayMode;
    String _paidBy = 'Employee (to reimburse)';
    DateTime _selectedDate = DateTime.now();

    double? parseAmount(String raw) {
      final normalized = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
      if (normalized.isEmpty) return null;
      return double.tryParse(normalized);
    }

    String selectedProductLabel() =>
        _getSelectedItemLabel(productList, _selectedProductId, '')
            .toLowerCase();

    Map<String, dynamic>? selectedProductMap() {
      for (final product in productList) {
        final rawId = product['id'];
        final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
        if (id != null && id == _selectedProductId) return product;
      }
      return null;
    }

    bool isMileageProduct() {
      final label = selectedProductLabel();
      final isMileage = label.contains('mileage');
      final isVehicle = label.contains('car') ||
          label.contains('motorcycle') ||
          label.contains('motorbike') ||
          label.contains('motor bike');
      return isMileage && isVehicle;
    }

    double currentMileageUnitPrice() {
      final selected = selectedProductMap();
      final raw = selected?['expense_unit_amount'] ??
          selected?['standard_price'] ??
          selected?['list_price'];
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? 0.0;
    }

    double computedMileageTotal() {
      final unitPrice = currentMileageUnitPrice();
      final quantity = parseAmount(_quantityController.text) ?? 0;
      return unitPrice * quantity;
    }

    await showDialog(
        context: context,
        builder: (dialogContext) {
          var saving = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return Dialog(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                insetPadding:
                    EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width - 48,
                    maxHeight: MediaQuery.of(context).size.height * 0.8,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text("Add Expense",
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF282454))),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt,
                                    color: Color(0xFF282454), size: 18),
                                Text(" 0",
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF282454))),
                                Text(" Receipts",
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Description
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Description",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _descriptionController,
                              decoration: InputDecoration(
                                hintText: "e.g. Lunch with Customer",
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade400, fontSize: 12),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Product (from Odoo) — same domain as Odoo expense form: expensable + company
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text("Product",
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500)),
                                Text(' *',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red.shade700)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: productList.isEmpty
                                  ? null
                                  : () => _showSearchablePicker(
                                        context: context,
                                        title: 'Select product (expensable)',
                                        items: productList,
                                        currentId: _selectedProductId,
                                        onSelected: (id) => setDialogState(() {
                                          _selectedProductId = id;
                                          _selectedTaxId = null;
                                          _selectedWayMode = null;
                                          _totalController.clear();
                                          final selected =
                                              productList.firstWhere(
                                            (e) {
                                              final rawId = e['id'];
                                              final pid = rawId is int
                                                  ? rawId
                                                  : int.tryParse(
                                                      rawId?.toString() ?? '');
                                              return pid == id;
                                            },
                                            orElse: () => <String, dynamic>{},
                                          );
                                          final priceRaw =
                                              selected['expense_unit_amount'] ??
                                                  selected['standard_price'] ??
                                                  selected['list_price'];
                                          final price = priceRaw is num
                                              ? priceRaw.toDouble()
                                              : double.tryParse(
                                                      priceRaw?.toString() ??
                                                          '') ??
                                                  0.0;
                                          _unitPriceController.text = price > 0
                                              ? price.toStringAsFixed(2)
                                              : '';
                                          _quantityController.text = '1';
                                        }),
                                      ),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _selectedProductId == null
                                        ? Colors.red.shade200
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        productList.isEmpty
                                            ? "No expensable products or loading…"
                                            : _getSelectedItemLabel(
                                                productList,
                                                _selectedProductId,
                                                'Select product'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _selectedProductId == null
                                              ? Colors.grey.shade600
                                              : Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                    Icon(Icons.arrow_drop_down,
                                        color: Colors.grey.shade600, size: 24),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        if (isMileageProduct()) ...[
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Unit Price",
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _unitPriceController,
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        hintText: "Auto from Odoo",
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                        suffixText: _selectedCurrency,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text("Quantity (KM)",
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: _quantityController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      onChanged: (_) => setDialogState(() {}),
                                      decoration: InputDecoration(
                                        hintText: "0",
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  'Total',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                                const Spacer(),
                                Text(
                                  '$_selectedCurrency ${computedMileageTotal().toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text("Way",
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                value: _selectedWayMode,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.grey.shade50,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                ),
                                hint: Text("Select Way",
                                    style: TextStyle(fontSize: 12)),
                                items: const [
                                  DropdownMenuItem<String>(
                                    value: '1way',
                                    child: Text('One Way',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                  DropdownMenuItem<String>(
                                    value: '2way',
                                    child: Text('Two Way',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                                onChanged: (String? newValue) {
                                  setDialogState(() {
                                    _selectedWayMode = newValue;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ] else ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Total",
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _totalController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: InputDecoration(
                                        hintText: "RM0.00",
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 8),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 90,
                                    child: DropdownButtonFormField<String>(
                                      value: _selectedCurrency,
                                      decoration: InputDecoration(
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 8),
                                      ),
                                      items: ['MYR'].map((String value) {
                                        return DropdownMenuItem<String>(
                                          value: value,
                                          child: Text(value,
                                              style: TextStyle(fontSize: 12)),
                                        );
                                      }).toList(),
                                      onChanged: (String? newValue) {
                                        setDialogState(() {
                                          _selectedCurrency = newValue ?? 'MYR';
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(Icons.open_in_new,
                                      size: 18, color: Colors.grey.shade600),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text("Taxes",
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500)),
                              const SizedBox(height: 4),
                              InkWell(
                                onTap: taxList.isEmpty
                                    ? null
                                    : () => _showSearchablePicker(
                                          context: context,
                                          title: 'Select tax',
                                          items: taxList,
                                          currentId: _selectedTaxId,
                                          onSelected: (id) => setDialogState(
                                              () => _selectedTaxId = id),
                                        ),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          taxList.isEmpty
                                              ? "No taxes available"
                                              : _getSelectedItemLabel(
                                                  taxList,
                                                  _selectedTaxId,
                                                  'Select tax',
                                                ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: _selectedTaxId == null
                                                ? Colors.grey.shade600
                                                : Colors.black87,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        ),
                                      ),
                                      Icon(Icons.arrow_drop_down,
                                          color: Colors.grey.shade600,
                                          size: 24),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Project Name (from Odoo) - with search
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text("Project Name",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: projectList.isEmpty
                                  ? null
                                  : () => _showSearchablePicker(
                                        context: context,
                                        title: 'Select Project',
                                        items: projectList,
                                        currentId: _selectedProjectId,
                                        onSelected: (id) => setDialogState(
                                            () => _selectedProjectId = id),
                                      ),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        projectList.isEmpty
                                            ? "Loading..."
                                            : _getSelectedItemLabel(
                                                projectList,
                                                _selectedProjectId,
                                                'Select Project'),
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: _selectedProjectId == null
                                                ? Colors.grey.shade600
                                                : Colors.black87),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                    Icon(Icons.arrow_drop_down,
                                        color: Colors.grey.shade600, size: 24),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Project Sales Order Number
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text("Project Sales Order Number",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    menuMaxHeight: 200,
                                    value: _selectedProjectSalesOrder.isEmpty
                                        ? null
                                        : _selectedProjectSalesOrder,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                    ),
                                    hint: Text("Select Order",
                                        style: TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis),
                                    items: [
                                      'SO-001',
                                      'SO-002',
                                      'SO-003',
                                    ].map((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(value,
                                            style: TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      setDialogState(() {
                                        _selectedProjectSalesOrder =
                                            newValue ?? '';
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Expense Date
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Expense Date",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            InkWell(
                              onTap: () async {
                                final DateTime? picked = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    _selectedDate = picked;
                                  });
                                }
                              },
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}",
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    Icon(Icons.calendar_today,
                                        size: 14, color: Colors.grey.shade600),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Analytic Account
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text("Analytic Account",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    menuMaxHeight: 200,
                                    value: _selectedAnalyticAccount.isEmpty
                                        ? null
                                        : _selectedAnalyticAccount,
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.grey.shade50,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                    ),
                                    hint: Text("Select Account",
                                        style: TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis),
                                    items: [
                                      'Account A',
                                      'Account B',
                                      'Account C',
                                    ].map((String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(value,
                                            style: TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      setDialogState(() {
                                        _selectedAnalyticAccount =
                                            newValue ?? '';
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Paid By
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Paid By",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Radio<String>(
                                      value: 'Employee (to reimburse)',
                                      groupValue: _paidBy,
                                      onChanged: (String? value) {
                                        setDialogState(() {
                                          _paidBy = value ??
                                              'Employee (to reimburse)';
                                        });
                                      },
                                      activeColor: Color(0xFF282454),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    Expanded(
                                      child: Text("Employee (to reimburse)",
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Radio<String>(
                                      value: 'Company',
                                      groupValue: _paidBy,
                                      onChanged: (String? value) {
                                        setDialogState(() {
                                          _paidBy = value ??
                                              'Employee (to reimburse)';
                                        });
                                      },
                                      activeColor: Color(0xFF282454),
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    Expanded(
                                      child: Text("Company",
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // From
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("From",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _fromController,
                              decoration: InputDecoration(
                                hintText: "Enter starting location",
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade400, fontSize: 12),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // To
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("To",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _toController,
                              decoration: InputDecoration(
                                hintText: "Enter destination",
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade400, fontSize: 12),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Notes
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Notes...",
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _notesController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                hintText: "Notes...",
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade400, fontSize: 12),
                                filled: true,
                                fillColor: Colors.grey.shade50,
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Buttons
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              child: Text("Cancel",
                                  style: TextStyle(
                                      color: Color(0xFF282454), fontSize: 14)),
                              onPressed: saving
                                  ? null
                                  : () => Navigator.of(dialogContext).pop(),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Color(0xFF282454),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: saving
                                  ? null
                                  : () async {
                                      if (_selectedProductId == null) {
                                        scaffoldMessenger.showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Please select a product (required in Odoo).')),
                                        );
                                        return;
                                      }
                                      final desc =
                                          _descriptionController.text.trim();
                                      if (desc.isEmpty) {
                                        scaffoldMessenger.showSnackBar(
                                          const SnackBar(
                                              content: Text(
                                                  'Please enter description.')),
                                        );
                                        return;
                                      }
                                      final mileageMode = isMileageProduct();
                                      double amount;
                                      double? quantity;
                                      double? unitAmount;
                                      List<int>? taxIds;

                                      if (mileageMode) {
                                        final parsedUnitAmount = parseAmount(
                                            _unitPriceController.text.trim());
                                        final parsedQuantity = parseAmount(
                                            _quantityController.text.trim());
                                        if (parsedUnitAmount == null ||
                                            parsedUnitAmount <= 0 ||
                                            parsedQuantity == null ||
                                            parsedQuantity <= 0) {
                                          scaffoldMessenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Unit price could not be loaded from Odoo or quantity is invalid.'),
                                            ),
                                          );
                                          return;
                                        }
                                        unitAmount = parsedUnitAmount;
                                        quantity = parsedQuantity;
                                        amount =
                                            parsedUnitAmount * parsedQuantity;
                                      } else {
                                        final totalRaw =
                                            _totalController.text.trim();
                                        if (totalRaw.isEmpty) {
                                          scaffoldMessenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Please enter total amount.'),
                                            ),
                                          );
                                          return;
                                        }
                                        final parsedAmount =
                                            parseAmount(totalRaw);
                                        if (parsedAmount == null ||
                                            parsedAmount <= 0) {
                                          scaffoldMessenger.showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                  'Enter a valid total amount.'),
                                            ),
                                          );
                                          return;
                                        }
                                        amount = parsedAmount;
                                        taxIds = _selectedTaxId != null
                                            ? <int>[_selectedTaxId!]
                                            : null;
                                      }
                                      setDialogState(() => saving = true);
                                      final r = await _odoo.createHrExpense(
                                        productId: _selectedProductId!,
                                        name: desc,
                                        totalAmount: amount,
                                        date: _selectedDate,
                                        paidByEmployee: _paidBy ==
                                            'Employee (to reimburse)',
                                        note:
                                            _notesController.text.trim().isEmpty
                                                ? null
                                                : _notesController.text.trim(),
                                        projectId: _selectedProjectId,
                                        fromAddress:
                                            _fromController.text.trim().isEmpty
                                                ? null
                                                : _fromController.text.trim(),
                                        toAddress:
                                            _toController.text.trim().isEmpty
                                                ? null
                                                : _toController.text.trim(),
                                        wayMode: mileageMode
                                            ? _selectedWayMode
                                            : null,
                                        quantity: quantity,
                                        unitAmount: unitAmount,
                                        taxIds: taxIds,
                                      );
                                      if (!dialogContext.mounted) return;
                                      setDialogState(() => saving = false);
                                      if (r.id != null) {
                                        Navigator.of(dialogContext).pop();
                                        if (!mounted) return;
                                        scaffoldMessenger.showSnackBar(
                                          SnackBar(
                                            backgroundColor:
                                                Colors.green.shade700,
                                            content: Text(
                                              'Expense saved to Odoo (#${r.id})',
                                              style: const TextStyle(
                                                  color: Colors.white),
                                            ),
                                          ),
                                        );
                                        _loadExpensesFromOdoo();
                                      } else {
                                        scaffoldMessenger.showSnackBar(
                                          SnackBar(
                                              content: Text(r.error ??
                                                  'Could not save expense')),
                                        );
                                      }
                                    },
                              child: saving
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : Text('Save',
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 14)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color mainColor = isDark ? Colors.black : const Color(0xFF282454);

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 20),
              // Summary Cards (from Odoo: to report, under validation, to be reimbursed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        label: 'To Report',
                        amount: _toReportTotal,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        label: 'Under Validation',
                        amount: _underValidationTotal,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryCard(
                        label: 'To Be Reimbursed',
                        amount: _toBeReimbursedTotal,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF262626)
                        : Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.16 : 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SectionTabButton(
                          label: 'My Expenses',
                          isSelected: _activeSection == 'my_expenses',
                          onTap: () {
                            setState(() {
                              _activeSection = 'my_expenses';
                              _isCreateReportMode = false;
                              _selectedReportExpenseIds.clear();
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: _SectionTabButton(
                          label: 'To Report',
                          isSelected: _activeSection == 'to_report',
                          onTap: () {
                            setState(() {
                              _activeSection = 'to_report';
                              _isCreateReportMode = false;
                              _selectedReportExpenseIds.clear();
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: _SectionTabButton(
                          label: 'My Report',
                          isSelected: _activeSection == 'my_report',
                          onTap: () {
                            setState(() {
                              _activeSection = 'my_report';
                              _isCreateReportMode = false;
                              _selectedReportExpenseIds.clear();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Expenses List
              Expanded(
                child: Builder(
                  builder: (context) {
                    final visibleExpenses = _activeSection == 'to_report'
                        ? _toReportSectionList
                        : _myExpensesSectionList;
                    final visibleReports = _expenseReports;
                    final emptyTitle = _activeSection == 'to_report'
                        ? 'No expenses in To Report'
                        : _activeSection == 'my_report'
                            ? 'No reports yet'
                            : 'No expenses yet';
                    final emptySubtitle = _activeSection == 'to_report'
                        ? 'Draft expenses from Odoo will appear here'
                        : _activeSection == 'my_report'
                            ? 'Submitted reports with expense lines will appear here'
                            : 'Expenses from Odoo will appear here';
                    return _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFF282454)))
                        : _errorMessage != null
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.error_outline,
                                          size: 48,
                                          color: Colors.grey.shade600),
                                      const SizedBox(height: 16),
                                      Text(
                                        _errorMessage!,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 14,
                                            color: isDark
                                                ? Colors.white70
                                                : Colors.grey.shade700),
                                      ),
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: _loadExpensesFromOdoo,
                                        style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFF282454)),
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : (_activeSection == 'my_report'
                                    ? visibleReports.isEmpty
                                    : visibleExpenses.isEmpty)
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.receipt_long,
                                            size: 64,
                                            color: Colors.grey.shade400),
                                        const SizedBox(height: 16),
                                        Text(
                                          emptyTitle,
                                          style: TextStyle(
                                              fontSize: 18,
                                              color: Colors.grey.shade600,
                                              fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          emptySubtitle,
                                          style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.grey.shade500),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  )
                                : _activeSection == 'my_report'
                                    ? ListView.builder(
                                        padding: const EdgeInsets.only(
                                            top: 8, bottom: 20),
                                        itemCount: visibleReports.length,
                                        itemBuilder: (context, index) =>
                                            _ExpenseReportCard(
                                          report: visibleReports[index],
                                          isDark: isDark,
                                          statusLabel: _statusLabel,
                                          statusColor: _statusColor,
                                          onEditReport:
                                              (reportId, reportName) =>
                                                  _editExpenseReport(
                                                      reportId, reportName),
                                          onDeleteReport:
                                              (reportId, reportName) =>
                                                  _deleteExpenseReport(
                                                      reportId, reportName),
                                          onSubmitReport:
                                              (reportId, reportName) =>
                                                  _submitExpenseReportToManager(
                                                      reportId, reportName),
                                          onResetReport:
                                              (reportId, reportName) =>
                                                  _resetExpenseReportToDraft(
                                                      reportId, reportName),
                                          onPrintReport:
                                              (reportId, reportName) =>
                                                  _printExpenseReportPdf(
                                                      reportId, reportName),
                                          onPrintSigmaReport:
                                              (reportId, reportName) =>
                                                  _printSigmaExpenseReportPdf(
                                                      reportId, reportName),
                                          onEditExpenseLine: (expenseId) =>
                                              _openExpenseLineFromReport(
                                                  expenseId),
                                          onDeleteExpenseLine: (expenseId,
                                                  expenseName,
                                                  reportId,
                                                  reportName) =>
                                              _handleReportExpenseDeleteAction(
                                            expenseId: expenseId,
                                            expenseName: expenseName,
                                            reportId: reportId,
                                            reportName: reportName,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.only(
                                            top: 8, bottom: 20),
                                        itemCount: visibleExpenses.length,
                                        itemBuilder: (context, index) {
                                          final exp = visibleExpenses[index];
                                          final eid = exp['id'] is int
                                              ? exp['id'] as int
                                              : int.tryParse(
                                                      exp['id']?.toString() ??
                                                          '0') ??
                                                  0;
                                          final desc =
                                              exp['name']?.toString() ?? '—';
                                          return _ExpenseCard(
                                            expense: exp,
                                            isDark: isDark,
                                            statusLabel: _statusLabel,
                                            statusColor: _statusColor,
                                            showReportCheckbox:
                                                _activeSection ==
                                                        'my_expenses' &&
                                                    _isCreateReportMode,
                                            isReportSelected:
                                                _selectedReportExpenseIds
                                                    .contains(eid),
                                            onReportChecked: eid > 0
                                                ? (checked) =>
                                                    _toggleExpenseReportSelection(
                                                        eid, checked)
                                                : null,
                                            onAttachmentPressed: eid > 0
                                                ? () =>
                                                    _showAttachmentActions(eid)
                                                : null,
                                            onDeletePressed: eid > 0
                                                ? () =>
                                                    _deleteExpense(eid, desc)
                                                : null,
                                          );
                                        },
                                      );
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: SafeArea(
        child: _isCreateReportMode
            ? FloatingActionButton.extended(
                heroTag: 'expenses_create_report',
                backgroundColor: mainColor,
                foregroundColor: Colors.white,
                elevation: 0,
                onPressed: _submitCreateReportSelection,
                icon: const Icon(Icons.assignment_add),
                label: Text(
                  _selectedReportExpenseIds.isEmpty
                      ? 'Create Report'
                      : 'Create Report (${_selectedReportExpenseIds.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              )
            : FloatingActionButton(
                heroTag: 'expenses_add_actions',
                mini: true,
                backgroundColor: mainColor,
                foregroundColor: Colors.white,
                elevation: 0,
                onPressed: _showCreateActionsSheet,
                child: const Icon(Icons.add),
              ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double amount;
  final bool isDark;

  const _SummaryCard(
      {required this.label, required this.amount, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white70 : Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'RM ${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF282454),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SectionTabButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SectionTabButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF282454) : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? Colors.white : const Color(0xFF282454),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final Map<String, dynamic> expense;
  final bool isDark;
  final String Function(String?) statusLabel;
  final Color Function(String?) statusColor;
  final bool showReportCheckbox;
  final bool isReportSelected;
  final ValueChanged<bool?>? onReportChecked;
  final VoidCallback? onAttachmentPressed;
  final VoidCallback? onDeletePressed;

  const _ExpenseCard({
    required this.expense,
    required this.isDark,
    required this.statusLabel,
    required this.statusColor,
    this.showReportCheckbox = false,
    this.isReportSelected = false,
    this.onReportChecked,
    this.onAttachmentPressed,
    this.onDeletePressed,
  });

  static String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    if (dateStr.trim().toLowerCase() == 'false') return '—';
    try {
      final d = DateTime.tryParse(dateStr);
      if (d == null) return dateStr;
      return DateFormat('dd/MM/yyyy').format(d);
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final description = expense['name']?.toString() ?? '—';
    final employeeName = expense['employee_name']?.toString() ?? '—';
    final totalAmount = expense['total_amount'] is num
        ? (expense['total_amount'] as num).toDouble()
        : 0.0;
    final attachmentCount = expense['attachment_count'] is int
        ? expense['attachment_count'] as int
        : (int.tryParse(expense['attachment_count']?.toString() ?? '0') ?? 0);
    final dateStr = expense['date']?.toString();
    final state = expense['state']?.toString();
    final imageBase64 = expense['employee_image'];

    // Display 2 chars in front of name only (e.g. "AB" for "Aiman Bin")
    String initial(String s) {
      if (s.isEmpty) return '?';
      s = s.trim();
      if (s.length >= 2) return s.substring(0, 2).toUpperCase();
      return s[0].toUpperCase();
    }

    Widget avatar;
    if (imageBase64 != null && imageBase64.toString().isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64.toString());
        avatar = CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFF282454).withOpacity(0.2),
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        avatar = CircleAvatar(
          radius: 24,
          backgroundColor: const Color(0xFF282454).withOpacity(0.2),
          child: Text(
            initial(employeeName),
            style: const TextStyle(
                color: Color(0xFF282454),
                fontWeight: FontWeight.bold,
                fontSize: 12),
          ),
        );
      }
    } else {
      avatar = CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFF282454).withOpacity(0.2),
        child: Text(
          initial(employeeName),
          style: const TextStyle(
              color: Color(0xFF282454),
              fontWeight: FontWeight.bold,
              fontSize: 12),
        ),
      );
    }

    final expenseId = expense['id'] is int
        ? expense['id'] as int
        : int.tryParse(expense['id']?.toString() ?? '0') ?? 0;
    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showReportCheckbox)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 18),
              child: Checkbox(
                value: isReportSelected,
                activeColor: const Color(0xFF282454),
                onChanged: onReportChecked,
              ),
            ),
          Expanded(
            child: InkWell(
              onTap: !showReportCheckbox && expenseId > 0
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ExpenseDetailsPage(expenseId: expenseId),
                        ),
                      )
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        avatar,
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.attach_file, size: 14, color: subColor),
                            const SizedBox(width: 2),
                            Text(
                              '$attachmentCount',
                              style: TextStyle(fontSize: 11, color: subColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            description,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final dateWidget = Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.calendar_today,
                                      size: 14, color: subColor),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      _formatDate(dateStr),
                                      style: TextStyle(
                                          fontSize: 12, color: subColor),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              );

                              final amountWidget = Text(
                                'RM ${totalAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF282454),
                                ),
                              );

                              if (constraints.maxWidth < 210) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    dateWidget,
                                    const SizedBox(height: 6),
                                    amountWidget,
                                  ],
                                );
                              }

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(child: dateWidget),
                                  const SizedBox(width: 8),
                                  amountWidget,
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, right: 8, bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 110),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor(state).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(
                      statusLabel(state),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor(state)),
                    ),
                  ),
                ),
                if (onAttachmentPressed != null || onDeletePressed != null)
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    icon: Icon(Icons.more_vert, size: 20, color: subColor),
                    onSelected: (value) {
                      if (value == 'attachments') onAttachmentPressed?.call();
                      if (value == 'delete') onDeletePressed?.call();
                    },
                    itemBuilder: (ctx) {
                      final items = <PopupMenuEntry<String>>[];
                      if (onAttachmentPressed != null) {
                        items.add(
                          const PopupMenuItem<String>(
                            value: 'attachments',
                            child: Row(
                              children: [
                                Icon(Icons.attach_file, size: 20),
                                SizedBox(width: 8),
                                Text('Attachments'),
                              ],
                            ),
                          ),
                        );
                      }
                      if (onDeletePressed != null) {
                        items.add(
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 20, color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Text('Delete',
                                    style:
                                        TextStyle(color: Colors.red.shade800)),
                              ],
                            ),
                          ),
                        );
                      }
                      return items;
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final bool isDark;
  final String Function(String?) statusLabel;
  final Color Function(String?) statusColor;
  final void Function(int reportId, String reportName)? onEditReport;
  final void Function(int reportId, String reportName)? onDeleteReport;
  final void Function(int reportId, String reportName)? onSubmitReport;
  final void Function(int reportId, String reportName)? onResetReport;
  final void Function(int reportId, String reportName)? onPrintReport;
  final void Function(int reportId, String reportName)? onPrintSigmaReport;
  final void Function(int expenseId)? onEditExpenseLine;
  final void Function(
          int expenseId, String expenseName, int reportId, String reportName)?
      onDeleteExpenseLine;

  const _ExpenseReportCard({
    required this.report,
    required this.isDark,
    required this.statusLabel,
    required this.statusColor,
    this.onEditReport,
    this.onDeleteReport,
    this.onSubmitReport,
    this.onResetReport,
    this.onPrintReport,
    this.onPrintSigmaReport,
    this.onEditExpenseLine,
    this.onDeleteExpenseLine,
  });

  static String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    if (dateStr.trim().toLowerCase() == 'false') return '—';
    try {
      final d = DateTime.tryParse(dateStr);
      if (d == null) return dateStr;
      return DateFormat('dd/MM/yyyy').format(d);
    } catch (_) {
      return dateStr;
    }
  }

  static String _cleanText(dynamic value, {String fallback = '—'}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'false') return fallback;
    return text;
  }

  static String _reportStatusLabel(String? state) {
    final s = (state ?? '').trim().toLowerCase();
    switch (s) {
      case '':
      case 'false':
      case 'draft':
        return 'To Submit';
      case 'submit':
      case 'reported':
        return 'Submitted';
      case 'approve':
      case 'approved':
        return 'Approved';
      case 'post':
      case 'done':
        return 'Posted';
      case 'cancel':
      case 'refuse':
        return 'Refused';
      default:
        return state ?? 'To Submit';
    }
  }

  static Color _reportStatusColor(String? state) {
    final s = (state ?? '').trim().toLowerCase();
    switch (s) {
      case '':
      case 'false':
      case 'draft':
        return Colors.orange;
      case 'submit':
      case 'reported':
        return Colors.blue;
      case 'approve':
      case 'approved':
        return Colors.green;
      case 'post':
      case 'done':
        return Colors.teal;
      case 'cancel':
      case 'refuse':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String _paymentStatusLabel(String? paymentState) {
    final s = (paymentState ?? '').trim().toLowerCase();
    switch (s) {
      case 'paid':
      case 'reconciled':
        return 'Paid';
      case 'in_payment':
        return 'In Payment';
      case 'not_paid':
      case 'unpaid':
      case '':
      case 'false':
        return 'Not Paid';
      default:
        return s
            .split('_')
            .where((part) => part.isNotEmpty)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join(' ');
    }
  }

  static Color _paymentStatusColor(String? paymentState) {
    final s = (paymentState ?? '').trim().toLowerCase();
    switch (s) {
      case 'paid':
      case 'reconciled':
        return Colors.green;
      case 'in_payment':
        return Colors.blue;
      case 'not_paid':
      case 'unpaid':
      case '':
      case 'false':
        return Colors.redAccent;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final lines = report['lines'] is List
        ? List<Map<String, dynamic>>.from(report['lines'] as List)
        : <Map<String, dynamic>>[];
    final totalAmount = report['total_amount'] is num
        ? (report['total_amount'] as num).toDouble()
        : 0.0;
    final state = report['state']?.toString();
    final paymentState = report['payment_state']?.toString();
    final reportStatusLabel = _reportStatusLabel(state);
    final reportStatusColor = _reportStatusColor(state);
    final paymentStatusLabel = _paymentStatusLabel(paymentState);
    final paymentStatusColor = _paymentStatusColor(paymentState);
    final canSubmit =
        ['', 'false', 'draft'].contains((state ?? '').trim().toLowerCase());
    final canResetToDraft =
        ['submit', 'reported'].contains((state ?? '').trim().toLowerCase());
    final reportId = report['id'] is int
        ? report['id'] as int
        : int.tryParse(report['id']?.toString() ?? '0') ?? 0;
    final reportName = _cleanText(report['name'], fallback: 'Report');

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reportName,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: textColor),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${lines.length} expenses',
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(report['date']?.toString()),
                      style: TextStyle(fontSize: 12, color: subColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: reportStatusColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          reportStatusLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: reportStatusColor),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: paymentStatusColor.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          paymentStatusLabel,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: paymentStatusColor),
                        ),
                      ),
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        icon: Icon(Icons.more_vert, color: subColor, size: 20),
                        onSelected: (value) {
                          if (value == 'print')
                            onPrintReport?.call(reportId, reportName);
                          if (value == 'print_sigma')
                            onPrintSigmaReport?.call(reportId, reportName);
                          if (value == 'submit')
                            onSubmitReport?.call(reportId, reportName);
                          if (value == 'reset_to_draft')
                            onResetReport?.call(reportId, reportName);
                          if (value == 'edit')
                            onEditReport?.call(reportId, reportName);
                          if (value == 'delete')
                            onDeleteReport?.call(reportId, reportName);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem<String>(
                            value: 'print',
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Print Expenses Report'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'print_sigma',
                            child: Row(
                              children: [
                                Icon(Icons.picture_as_pdf_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Print Sigma Expenses Report'),
                              ],
                            ),
                          ),
                          if (canSubmit)
                            const PopupMenuItem<String>(
                              value: 'submit',
                              child: Row(
                                children: [
                                  Icon(Icons.send_outlined, size: 18),
                                  SizedBox(width: 8),
                                  Text('Submit to manager'),
                                ],
                              ),
                            ),
                          if (canResetToDraft)
                            const PopupMenuItem<String>(
                              value: 'reset_to_draft',
                              child: Row(
                                children: [
                                  Icon(Icons.undo, size: 18),
                                  SizedBox(width: 8),
                                  Text('Reset to draft'),
                                ],
                              ),
                            ),
                          const PopupMenuItem<String>(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit_outlined, size: 18),
                                SizedBox(width: 8),
                                Text('Edit'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'RM ${totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF282454)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.black12 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines.isEmpty
                  ? [
                      Text(
                        'No expenses linked to this report',
                        style: TextStyle(fontSize: 12, color: subColor),
                      ),
                    ]
                  : lines.map((line) {
                      final expenseId = line['id'] is int
                          ? line['id'] as int
                          : int.tryParse(line['id']?.toString() ?? '0') ?? 0;
                      final expenseName = line['name']?.toString() ?? '—';
                      final amount = line['total_amount'] is num
                          ? (line['total_amount'] as num).toDouble()
                          : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.receipt_long, size: 16, color: subColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _cleanText(line['name']),
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: textColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _formatDate(line['date']?.toString()),
                                    style: TextStyle(
                                        fontSize: 11, color: subColor),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'RM ${amount.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF282454)),
                                ),
                                PopupMenuButton<String>(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(Icons.more_vert,
                                      color: subColor, size: 18),
                                  onSelected: (value) {
                                    if (value == 'edit')
                                      onEditExpenseLine?.call(expenseId);
                                    if (value == 'delete')
                                      onDeleteExpenseLine?.call(expenseId,
                                          expenseName, reportId, reportName);
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(Icons.edit_outlined, size: 18),
                                          SizedBox(width: 8),
                                          Text('Edit'),
                                        ],
                                      ),
                                    ),
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete_outline,
                                              size: 18, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('Delete',
                                              style:
                                                  TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _OdooActionResult {
  final int? id;
  final String? error;

  const _OdooActionResult({this.id, this.error});
}

extension _ExpenseCompatOdoo on OdooService {
  Future<double> getExpenseToReportTotal() async => 0;

  Future<double> getExpenseUnderValidationTotal() async => 0;

  Future<double> getExpenseToBeReimbursedTotal() async => 0;

  Future<List<Map<String, dynamic>>> fetchMyExpenses() async => <Map<String, dynamic>>[];

  Future<List<Map<String, dynamic>>> fetchMyExpenseReports() async =>
      <Map<String, dynamic>>[];

  Future<String?> deleteMyHrExpense(int expenseId) async => null;

  Future<_OdooActionResult> createExpenseReportFromExpenses(
    List<int> expenseIds, {
    required String reportTitle,
  }) async {
    return const _OdooActionResult(id: null, error: 'Feature not available in this build');
  }

  Future<String?> renameExpenseReport({
    required int reportId,
    required String newName,
  }) async =>
      'Feature not available in this build';

  Future<String?> deleteExpenseReport(int reportId) async =>
      'Feature not available in this build';

  Future<String?> submitExpenseReportToManager(int reportId) async =>
      'Feature not available in this build';

  Future<String?> resetExpenseReportToDraft(int reportId) async =>
      'Feature not available in this build';

  Future<String?> fetchExpenseSheetReportPdf(
    int reportId, {
    bool preferSigma = false,
  }) async =>
      null;

  Future<String?> removeExpenseFromReport({
    required int expenseId,
    required int reportId,
  }) async =>
      'Feature not available in this build';

  Future<String?> uploadExpenseAttachment({
    required int expenseId,
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async =>
      'Feature not available in this build';

  Future<String?> deleteExpenseAttachment(int attachmentId) async =>
      'Feature not available in this build';

  Future<List<Map<String, dynamic>>> getExpenseAttachments(int expenseId) async =>
      <Map<String, dynamic>>[];

  Future<Uint8List?> getExpenseAttachmentBytes(int id, String name) async => null;

  Future<String?> getExpenseAttachmentFile(int id, String name) async => null;

  Future<List<Map<String, dynamic>>> fetchExpenseProductList() async =>
      <Map<String, dynamic>>[];

  Future<List<Map<String, dynamic>>> fetchExpenseProjectList() async =>
      <Map<String, dynamic>>[];

  Future<List<Map<String, dynamic>>> fetchExpenseTaxList() async =>
      <Map<String, dynamic>>[];

  Future<_OdooActionResult> createHrExpense({
    required int productId,
    required String name,
    required double totalAmount,
    required DateTime date,
    required bool paidByEmployee,
    String? note,
    int? projectId,
    String? fromAddress,
    String? toAddress,
    String? wayMode,
    double? quantity,
    double? unitAmount,
    List<int>? taxIds,
  }) async {
    return const _OdooActionResult(id: null, error: 'Feature not available in this build');
  }
}
