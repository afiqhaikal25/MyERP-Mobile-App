import 'package:flutter/material.dart';

class ExpenseDetailsPage extends StatelessWidget {
  final int expenseId;

  const ExpenseDetailsPage({super.key, required this.expenseId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Expense Details'),
      ),
      body: Center(
        child: Text('Expense #$expenseId'),
      ),
    );
  }
}
