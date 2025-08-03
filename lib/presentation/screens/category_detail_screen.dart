import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';

class CategoryDetailScreen extends StatelessWidget {
  final String categoryName;
  final List<TransactionModel>
  transactions; // Nhận danh sách giao dịch đã được lọc sẵn

  const CategoryDetailScreen({
    super.key,
    required this.categoryName,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: ListView.builder(
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final trans = transactions[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.receipt_long, color: Colors.orange),
              title: Text(
                trans.description.isNotEmpty ? trans.description : 'Chi tiêu',
              ),
              subtitle: Text(DateFormat('dd/MM/yyyy').format(trans.date)),
              trailing: Text(
                currencyFormatter.format(trans.amount),
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
