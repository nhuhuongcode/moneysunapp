import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';

class TransactionListItemDetailed extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionListItemDetailed({
    super.key,
    required this.transaction,
    // required this.categoryIcon,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
    Color amountColor;
    String sign;
    switch (transaction.type) {
      case TransactionType.income:
        amountColor = Colors.green.shade700;
        sign = '+';
        break;
      case TransactionType.expense:
        amountColor = Colors.red.shade700;
        sign = '-';
        break;
      case TransactionType.transfer:
        amountColor = Colors.yellow.shade700;
        sign = '';
        break;
    }

    return ListTile(
      onTap: () {
        _showTransactionDetailDialog(context, transaction);
      },
      leading: CircleAvatar(
        backgroundColor: amountColor.withOpacity(0.1),
        child: Icon(Icons.label_outline, color: amountColor),
      ),
      title: Text(
        transaction.categoryName, // Dòng đầu tiên là tên Category
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dòng 2 là Description (nếu có)
          if (transaction.description.isNotEmpty)
            Text(
              transaction.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          // Dòng 3 là SubCategory và Wallet
          Text(
            '${transaction.subCategoryName.isNotEmpty ? "${transaction.subCategoryName} • " : ""}${transaction.walletName}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
      trailing: Text(
        '${sign} ${currencyFormatter.format(transaction.amount)}',
        style: TextStyle(
          color: amountColor,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      isThreeLine:
          transaction.description.isNotEmpty, // Cho phép subtitle có 2 dòng
    );
  }

  void _showTransactionDetailDialog(
    BuildContext context,
    TransactionModel transaction,
  ) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề
            Text(
              transaction.description.isNotEmpty
                  ? transaction.description
                  : transaction.categoryName,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            // Số tiền
            Text(
              currencyFormatter.format(transaction.amount),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: transaction.type == TransactionType.expense
                    ? Colors.red
                    : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),
            // Chi tiết
            _buildDetailRow(
              Icons.calendar_today,
              'Ngày',
              DateFormat('dd/MM/yyyy, HH:mm').format(transaction.date),
            ),
            _buildDetailRow(
              Icons.account_balance_wallet,
              'Nguồn tiền',
              transaction.walletName,
            ),
            _buildDetailRow(
              Icons.category,
              'Danh mục',
              transaction.categoryName,
            ),
            const SizedBox(height: 24),
            // Các nút hành động
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _showConfirmDeleteDialog(
                      context,
                      transaction,
                    ); // Mở dialog xác nhận
                    Navigator.pop(ctx);
                  },
                  child: const Text('XÓA', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    // Đóng bottom sheet
                    Navigator.pop(ctx);
                    // Điều hướng đến màn hình sửa
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AddTransactionScreen(
                          transactionToEdit: transaction,
                        ),
                      ),
                    );
                  },
                  child: const Text('SỬA'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 20),
          const SizedBox(width: 16),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  void _showConfirmDeleteDialog(
    BuildContext context,
    TransactionModel transaction,
  ) {
    final databaseService = DatabaseService();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận Xóa'),
        content: const Text(
          'Bạn có chắc chắn muốn xóa giao dịch này không? Hành động này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              databaseService.deleteTransaction(transaction);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
