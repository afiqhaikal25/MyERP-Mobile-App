import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ExpenseDetailsPage extends StatelessWidget {
  final Map<String, dynamic> expense;

  const ExpenseDetailsPage({super.key, required this.expense});

  String _formatDate(dynamic raw) {
    if (raw == null || raw == false) return '—';
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(raw.toString()));
    } catch (_) {
      return raw.toString();
    }
  }

  String _formatAmount(dynamic raw) {
    if (raw == null || raw == false) return 'RM 0.00';
    final amt = (raw is num) ? raw.toDouble() : double.tryParse(raw.toString()) ?? 0;
    return 'RM ${amt.toStringAsFixed(2)}';
  }

  String _stateLabel(String? state) {
    switch (state) {
      case 'draft':       return 'To Submit';
      case 'reported':    return 'Submitted';
      case 'approved':    return 'Approved';
      case 'done':        return 'Done';
      case 'refuse':      return 'Refused';
      default:            return state ?? '—';
    }
  }

  Color _stateColor(String? state) {
    switch (state) {
      case 'draft':       return const Color(0xFFFFA726);
      case 'reported':    return Colors.blue;
      case 'approved':    return Colors.green;
      case 'done':        return const Color(0xFF282454);
      case 'refuse':      return Colors.red;
      default:            return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : const Color(0xFFF5F5F5);
    final cardBg = isDark ? const Color(0xFF2D2D2D) : Colors.white;
    final state = expense['state']?.toString();
    final name = expense['name']?.toString() ?? '—';
    final employeeName = expense['employee_name']?.toString() ??
        (expense['employee_id'] is List ? expense['employee_id'][1]?.toString() : null) ?? '—';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Expense Details'),
        backgroundColor: const Color(0xFF282454),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF282454),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _stateColor(state).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _stateLabel(state),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _stateColor(state),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatAmount(expense['total_amount']),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : const Color(0xFF282454),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Details card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.07),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _DetailRow(label: 'Employee', value: employeeName, isDark: isDark),
                  _DetailRow(label: 'Date', value: _formatDate(expense['date']), isDark: isDark),
                  _DetailRow(label: 'Amount', value: _formatAmount(expense['total_amount']), isDark: isDark),
                  _DetailRow(
                    label: 'Expense Report',
                    value: expense['sheet_id'] is List
                        ? expense['sheet_id'][1]?.toString() ?? '—'
                        : (expense['sheet_id'] == false ? 'Not submitted' : '—'),
                    isDark: isDark,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final bool isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.isDark,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF282454),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.grey.shade100,
          ),
      ],
    );
  }
}
