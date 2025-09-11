// lib/presentation/widgets/transaction_list_item_detailed.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';

class TransactionListItemDetailed extends StatelessWidget {
  final TransactionModel transaction;
  final VoidCallback? onDeleted;

  const TransactionListItemDetailed({
    super.key,
    required this.transaction,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // Xác định màu sắc và icon theo type
    Color amountColor;
    String sign;
    IconData categoryIcon;

    switch (transaction.type) {
      case TransactionType.income:
        amountColor = Colors.green.shade700;
        sign = '+';
        categoryIcon = Icons.trending_up;
        break;
      case TransactionType.expense:
        amountColor = Colors.red.shade700;
        sign = '-';
        categoryIcon = Icons.trending_down;
        break;
      case TransactionType.transfer:
        amountColor = Colors.orange.shade700;
        sign = '';
        categoryIcon = Icons.swap_horiz;
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: amountColor.withOpacity(0.1), width: 1),
      ),
      child: ListTile(
        onTap: () => _showTransactionDetailDialog(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),

        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: amountColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(categoryIcon, color: amountColor, size: 18),
        ),

        title: _buildTransactionTitle(),
        subtitle: _buildTransactionSubtitle(),

        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${currencyFormatter.format(transaction.amount)}',
              style: TextStyle(
                color: amountColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Text(
              DateFormat('HH:mm').format(transaction.date),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),

        isThreeLine: _needsThreeLines(),
      ),
    );
  }

  Widget _buildTransactionTitle() {
    String title = '';

    if (transaction.type == TransactionType.transfer) {
      title = 'Chuyển tiền';
    } else if (transaction.categoryName.isNotEmpty) {
      title = transaction.categoryName;
    } else {
      title = 'Giao dịch';
    }

    return Text(
      title,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildTransactionSubtitle() {
    List<Widget> subtitleWidgets = [];

    if (transaction.description.isNotEmpty) {
      subtitleWidgets.add(
        Text(
          transaction.description,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (transaction.type == TransactionType.transfer) {
      if (transaction.transferFromWalletName!.isNotEmpty &&
          transaction.transferToWalletName!.isNotEmpty) {
        subtitleWidgets.add(
          Text(
            '${transaction.transferFromWalletName} → ${transaction.transferToWalletName}',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
    } else {
      // Show wallet name for income/expense
      if (transaction.walletName.isNotEmpty) {
        subtitleWidgets.add(
          Text(
            transaction.walletName,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: subtitleWidgets,
    );
  }

  bool _needsThreeLines() {
    int lineCount = 1; // Title

    if (transaction.description.isNotEmpty) lineCount++;

    if (transaction.type == TransactionType.transfer) {
      if (transaction.transferFromWalletName!.isNotEmpty &&
          transaction.transferToWalletName!.isNotEmpty) {
        lineCount++;
      }
    } else if (transaction.walletName.isNotEmpty) {
      lineCount++;
    }

    return lineCount > 2;
  }

  void _showTransactionDetailDialog(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header với icon và type
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getAmountColor().withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getTransactionIcon(),
                          color: _getAmountColor(),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getDialogTitle(),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              currencyFormatter.format(transaction.amount),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: _getAmountColor(),
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Chi tiết giao dịch
                  ..._buildDetailRows(),

                  const SizedBox(height: 24),

                  // Các nút hành động
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showConfirmDeleteDialog(context);
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Xóa'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
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
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Chỉnh sửa'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _getAmountColor(),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

  IconData _getTransactionIcon() {
    switch (transaction.type) {
      case TransactionType.income:
        return Icons.trending_up;
      case TransactionType.expense:
        return Icons.trending_down;
      case TransactionType.transfer:
        return Icons.swap_horiz;
    }
  }

  Color _getAmountColor() {
    switch (transaction.type) {
      case TransactionType.income:
        return Colors.green.shade600;
      case TransactionType.expense:
        return Colors.red.shade600;
      case TransactionType.transfer:
        return Colors.orange.shade600;
    }
  }

  List<Widget> _buildDetailRows() {
    List<Widget> rows = [];

    // Ngày và thời gian
    rows.add(
      _buildDetailRow(
        Icons.schedule,
        'Thời gian',
        DateFormat(
          'EEEE, dd/MM/yyyy lúc HH:mm',
          'vi_VN',
        ).format(transaction.date),
      ),
    );

    // Category details (nếu không phải transfer)
    if (transaction.type != TransactionType.transfer) {
      if (transaction.categoryName.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.category_outlined,
            transaction.type == TransactionType.income
                ? 'Nguồn thu'
                : 'Danh mục',
            transaction.categoryName,
          ),
        );
      }

      if (transaction.subCategoryName.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.subdirectory_arrow_right,
            'Danh mục con',
            transaction.subCategoryName,
          ),
        );
      }
    }

    // Wallet information
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
    } else {
      if (transaction.walletName.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.account_balance_wallet,
            'Ví',
            transaction.walletName,
          ),
        );
      }
    }

    // Mô tả (nếu có và chưa hiển thị ở title)
    if (transaction.description.isNotEmpty) {
      rows.add(
        _buildDetailRow(Icons.description, 'Mô tả', transaction.description),
      );
    }

    return rows;
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getAmountColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _getAmountColor(), size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showConfirmDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade600),
            const SizedBox(width: 12),
            const Text('Xác nhận xóa'),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa giao dịch này không? Hành động này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          Consumer<TransactionProvider>(
            builder: (context, transactionProvider, child) {
              return ElevatedButton(
                onPressed: () async {
                  try {
                    // Using TransactionProvider instead of DatabaseService
                    // Note: We would need a delete method in TransactionProvider
                    // For now, show a message that delete functionality needs to be implemented
                    Navigator.pop(ctx);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Chức năng xóa sẽ được thêm vào TransactionProvider',
                        ),
                        backgroundColor: Colors.orange,
                      ),
                    );

                    onDeleted?.call();
                  } catch (e) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi khi xóa: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Xóa'),
              );
            },
          ),
        ],
      ),
    );
  }
}
