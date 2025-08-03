import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';

class TransactionListItem extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback? onTap;

  const TransactionListItem({super.key, required this.transaction, this.onTap});

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // Logic xác định màu sắc và icon
    IconData icon;
    Color color;
    String sign = '';

    switch (transaction.type) {
      case TransactionType.income:
        icon = Icons.arrow_downward;
        color = Colors.green;
        sign = '+';
        break;
      case TransactionType.expense:
        icon = Icons.arrow_upward;
        color = Colors.red;
        sign = '-';
        break;
      case TransactionType.transfer:
        icon = Icons.swap_horiz;
        color = Colors.blue;
        sign = ''; // Giao dịch chuyển tiền thường không có dấu
        break;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          transaction.description.isNotEmpty
              ? transaction.description
              : 'Giao dịch',
        ),
        subtitle: Text(
          DateFormat('dd/MM/yyyy, HH:mm').format(transaction.date),
        ),
        trailing: Text(
          '$sign ${currencyFormatter.format(transaction.amount)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
