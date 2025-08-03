import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';

class TransactionListItemDetailed extends StatelessWidget {
  final TransactionModel transaction;

  const TransactionListItemDetailed({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // FIX: Xác định màu sắc và icon theo type
    Color amountColor;
    String sign;
    IconData categoryIcon;

    switch (transaction.type) {
      case TransactionType.income:
        amountColor = Colors.green.shade700;
        sign = '+';
        categoryIcon = Icons.trending_up; // Icon thu nhập
        break;
      case TransactionType.expense:
        amountColor = Colors.red.shade700;
        sign = '-';
        categoryIcon = Icons.trending_down; // Icon chi tiêu
        break;
      case TransactionType.transfer:
        amountColor = Colors.orange.shade700; // FIX: Màu vàng/cam cho transfer
        sign = '';
        categoryIcon = Icons.swap_horiz; // Icon chuyển tiền
        break;
    }

    return ListTile(
      onTap: () {
        _showTransactionDetailDialog(context, transaction);
      },
      // FIX: Thay đổi icon từ mũi tên thành category icon
      leading: CircleAvatar(
        backgroundColor: amountColor.withOpacity(0.1),
        child: Icon(categoryIcon, color: amountColor),
      ),
      // FIX: Title hiển thị category name hoặc transfer format
      title: _buildTransactionTitle(),
      // FIX: Subtitle hiển thị subcategory, description, wallet
      subtitle: _buildTransactionSubtitle(),
      trailing: Text(
        '${sign}${currencyFormatter.format(transaction.amount)}',
        style: TextStyle(
          color: amountColor,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
      // Cho phép subtitle có nhiều dòng nếu cần
      isThreeLine: _needsThreeLines(),
    );
  }

  // FIX: Build title theo format yêu cầu
  Widget _buildTransactionTitle() {
    if (transaction.type == TransactionType.transfer) {
      // FIX: Hiển thị "Chuyển tiền" và từ -> đến
      if (transaction.transferFromWalletName!.isNotEmpty &&
          transaction.transferToWalletName!.isNotEmpty) {
        return Text(
          'Chuyển ${transaction.transferFromWalletName} → ${transaction.transferToWalletName}',
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      }
      return const Text(
        'Chuyển tiền',
        style: TextStyle(fontWeight: FontWeight.bold),
      );
    } else {
      // Hiển thị category name
      return Text(
        transaction.categoryName.isNotEmpty
            ? transaction.categoryName
            : (transaction.type == TransactionType.income
                  ? 'Thu nhập'
                  : 'Chi tiêu'),
        style: const TextStyle(fontWeight: FontWeight.bold),
      );
    }
  }

  // FIX: Build subtitle với format mới
  Widget _buildTransactionSubtitle() {
    List<String> subtitleParts = [];

    // Thêm subcategory nếu có
    if (transaction.subCategoryName.isNotEmpty) {
      subtitleParts.add(transaction.subCategoryName);
    }

    // Thêm description nếu có
    if (transaction.description.isNotEmpty) {
      subtitleParts.add(transaction.description);
    }

    // Thêm wallet name
    if (transaction.walletName.isNotEmpty) {
      subtitleParts.add(transaction.walletName);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Dòng đầu: SubCategory (nếu có)
        if (transaction.subCategoryName.isNotEmpty)
          Text(
            transaction.subCategoryName,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

        // Dòng thứ hai: Description (nếu có)
        if (transaction.description.isNotEmpty)
          Text(
            transaction.description,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

        // Dòng cuối: Wallet name
        Text(
          transaction.walletName.isNotEmpty
              ? transaction.walletName
              : 'Ví đã xóa',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // Xác định có cần 3 dòng không
  bool _needsThreeLines() {
    int lineCount = 1; // Luôn có ít nhất wallet name

    if (transaction.subCategoryName.isNotEmpty) lineCount++;
    if (transaction.description.isNotEmpty) lineCount++;

    return lineCount > 2;
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
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề
            Text(
              _getDialogTitle(),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),

            // Số tiền với màu phù hợp
            Text(
              currencyFormatter.format(transaction.amount),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _getAmountColor(),
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 24),

            // Chi tiết giao dịch
            ..._buildDetailRows(),

            const SizedBox(height: 24),

            // Các nút hành động
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showConfirmDeleteDialog(context, transaction);
                  },
                  child: const Text('XÓA', style: TextStyle(color: Colors.red)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
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

  String _getDialogTitle() {
    if (transaction.type == TransactionType.transfer) {
      return 'Chi tiết chuyển tiền';
    } else if (transaction.description.isNotEmpty) {
      return transaction.description;
    } else {
      return transaction.categoryName.isNotEmpty
          ? transaction.categoryName
          : 'Chi tiết giao dịch';
    }
  }

  Color _getAmountColor() {
    switch (transaction.type) {
      case TransactionType.income:
        return Colors.green;
      case TransactionType.expense:
        return Colors.red;
      case TransactionType.transfer:
        return Colors.orange;
    }
  }

  List<Widget> _buildDetailRows() {
    List<Widget> rows = [];

    // Ngày
    rows.add(
      _buildDetailRow(
        Icons.calendar_today,
        'Ngày',
        DateFormat('dd/MM/yyyy, HH:mm').format(transaction.date),
      ),
    );

    // Nguồn tiền
    rows.add(
      _buildDetailRow(
        Icons.account_balance_wallet,
        'Nguồn tiền',
        transaction.walletName,
      ),
    );

    // Category (nếu không phải transfer)
    if (transaction.type != TransactionType.transfer &&
        transaction.categoryName.isNotEmpty) {
      rows.add(
        _buildDetailRow(
          Icons.category,
          transaction.type == TransactionType.income ? 'Nguồn thu' : 'Danh mục',
          transaction.categoryName,
        ),
      );
    }

    // Sub-category (nếu có)
    if (transaction.subCategoryName.isNotEmpty) {
      rows.add(
        _buildDetailRow(
          Icons.subdirectory_arrow_right,
          'Danh mục con',
          transaction.subCategoryName,
        ),
      );
    }

    // Transfer details (nếu là transfer)
    if (transaction.type == TransactionType.transfer) {
      if (transaction.transferFromWalletName!.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.call_made,
            'Từ ví',
            transaction.transferFromWalletName!,
          ),
        );
      }
      if (transaction.transferToWalletName!.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.call_received,
            'Đến ví',
            transaction.transferToWalletName!,
          ),
        );
      }
    }

    // Mô tả (nếu có)
    if (transaction.description.isNotEmpty) {
      rows.add(
        _buildDetailRow(Icons.description, 'Mô tả', transaction.description),
      );
    }

    return rows;
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
            onPressed: () async {
              try {
                await databaseService.deleteTransaction(transaction);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa giao dịch')),
                );
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Lỗi khi xóa: $e')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
