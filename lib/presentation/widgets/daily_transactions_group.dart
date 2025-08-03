import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/presentation/widgets/transaction_list_item_detailed.dart';

class DailyTransactionsGroup extends StatelessWidget {
  final DateTime date;
  final List<TransactionModel> transactions;

  const DailyTransactionsGroup({
    super.key,
    required this.date,
    required this.transactions,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
    // Tính tổng chi tiêu cho ngày này
    final dailyTotal = transactions.fold(0.0, (sum, item) {
      return item.type == TransactionType.expense
          ? sum + item.amount
          : sum - item.amount;
    });

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      child: Column(
        children: [
          // Header của ngày
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12.0),
                topRight: Radius.circular(12.0),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('EEEE, dd/MM/yyyy', 'vi_VN').format(date),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  currencyFormatter.format(dailyTotal),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          // Danh sách giao dịch
          ...transactions
              .map((trans) => TransactionListItemDetailed(transaction: trans))
              .toList(),
        ],
      ),
    );
  }
}
