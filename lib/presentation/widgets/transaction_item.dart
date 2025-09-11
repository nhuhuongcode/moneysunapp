// lib/presentation/widgets/_transaction_item.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';

class TransactionItem extends StatefulWidget {
  final TransactionModel transaction;
  final VoidCallback? onDeleted;
  final VoidCallback? onTap;
  final bool showDate;
  final bool isCompact;
  final bool showActions;

  const TransactionItem({
    super.key,
    required this.transaction,
    this.onDeleted,
    this.onTap,
    this.showDate = true,
    this.isCompact = false,
    this.showActions = true,
  });

  @override
  State<TransactionItem> createState() => _TransactionItemState();
}

class _TransactionItemState extends State<TransactionItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // Determine colors and icons based on transaction type
    final transactionColors = _getTransactionColors();
    final transactionIcon = _getTransactionIcon();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: GestureDetector(
              onTapDown: (_) => _handleTapDown(),
              onTapUp: (_) => _handleTapUp(),
              onTapCancel: () => _handleTapCancel(),
              onTap: () => _handleTap(),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: transactionColors['primary']!.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: EdgeInsets.all(widget.isCompact ? 12 : 16),
                  child: Row(
                    children: [
                      _buildLeadingIcon(transactionIcon, transactionColors),
                      const SizedBox(width: 12),
                      Expanded(child: _buildTransactionInfo()),
                      const SizedBox(width: 12),
                      _buildTrailingInfo(currencyFormatter, transactionColors),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Map<String, Color> _getTransactionColors() {
    switch (widget.transaction.type) {
      case TransactionType.income:
        return {
          'primary': Colors.green.shade600,
          'background': Colors.green.withOpacity(0.1),
          'border': Colors.green.withOpacity(0.3),
        };
      case TransactionType.expense:
        return {
          'primary': Colors.red.shade600,
          'background': Colors.red.withOpacity(0.1),
          'border': Colors.red.withOpacity(0.3),
        };
      case TransactionType.transfer:
        return {
          'primary': Colors.orange.shade600,
          'background': Colors.orange.withOpacity(0.1),
          'border': Colors.orange.withOpacity(0.3),
        };
    }
  }

  IconData _getTransactionIcon() {
    switch (widget.transaction.type) {
      case TransactionType.income:
        return Icons.arrow_downward_rounded;
      case TransactionType.expense:
        return Icons.arrow_upward_rounded;
      case TransactionType.transfer:
        return Icons.swap_horiz_rounded;
    }
  }

  Widget _buildLeadingIcon(IconData icon, Map<String, Color> colors) {
    return Hero(
      tag: 'transaction_${widget.transaction.id}',
      child: Container(
        padding: EdgeInsets.all(widget.isCompact ? 8 : 10),
        decoration: BoxDecoration(
          color: colors['background'],
          borderRadius: BorderRadius.circular(widget.isCompact ? 8 : 10),
          border: Border.all(color: colors['border']!, width: 1),
        ),
        child: Icon(
          icon,
          color: colors['primary'],
          size: widget.isCompact ? 16 : 18,
        ),
      ),
    );
  }

  Widget _buildTransactionInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Title
        Text(
          _getTransactionTitle(),
          style: TextStyle(
            fontSize: widget.isCompact ? 13 : 14,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).textTheme.titleMedium?.color,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),

        const SizedBox(height: 2),

        // Subtitle with description and wallet info
        if (widget.transaction.description.isNotEmpty ||
            _shouldShowWalletInfo()) ...[
          Text(
            _getSubtitleText(),
            style: TextStyle(
              fontSize: widget.isCompact ? 11 : 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
            maxLines: widget.isCompact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // Transfer specific info
        if (widget.transaction.type == TransactionType.transfer &&
            _hasTransferInfo()) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Icon(Icons.arrow_forward, size: 12, color: Colors.grey.shade500),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '${widget.transaction.transferFromWalletName} → ${widget.transaction.transferToWalletName}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],

        // Date (if should show)
        if (widget.showDate) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              DateFormat('dd/MM HH:mm').format(widget.transaction.date),
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTrailingInfo(NumberFormat formatter, Map<String, Color> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Amount
        Text(
          '${_getAmountPrefix()}${formatter.format(widget.transaction.amount)}',
          style: TextStyle(
            color: colors['primary'],
            fontWeight: FontWeight.bold,
            fontSize: widget.isCompact ? 13 : 14,
          ),
        ),

        // Time (if not showing date in main content)
        if (!widget.showDate) ...[
          const SizedBox(height: 2),
          Text(
            DateFormat('HH:mm').format(widget.transaction.date),
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],

        // Action button (if enabled)
        if (widget.showActions && !widget.isCompact) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: _showActionsMenu,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                Icons.more_horiz,
                size: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  String _getTransactionTitle() {
    if (widget.transaction.type == TransactionType.transfer) {
      return 'Chuyển tiền';
    } else if (widget.transaction.categoryName.isNotEmpty) {
      return widget.transaction.categoryName;
    } else {
      return widget.transaction.type == TransactionType.income
          ? 'Thu nhập'
          : 'Chi tiêu';
    }
  }

  String _getSubtitleText() {
    List<String> parts = [];

    if (widget.transaction.description.isNotEmpty) {
      parts.add(widget.transaction.description);
    }

    if (_shouldShowWalletInfo()) {
      if (widget.transaction.type == TransactionType.transfer) {
        // For transfers, wallet info is shown separately
      } else if (widget.transaction.walletName.isNotEmpty) {
        parts.add('• ${widget.transaction.walletName}');
      }
    }

    if (widget.transaction.subCategoryName.isNotEmpty) {
      parts.add('• ${widget.transaction.subCategoryName}');
    }

    return parts.join(' ');
  }

  bool _shouldShowWalletInfo() {
    return widget.transaction.type != TransactionType.transfer &&
        widget.transaction.walletName.isNotEmpty;
  }

  bool _hasTransferInfo() {
    return widget.transaction.transferFromWalletName?.isNotEmpty == true &&
        widget.transaction.transferToWalletName?.isNotEmpty == true;
  }

  String _getAmountPrefix() {
    switch (widget.transaction.type) {
      case TransactionType.income:
        return '+';
      case TransactionType.expense:
        return '-';
      case TransactionType.transfer:
        return '';
    }
  }

  void _handleTapDown() {
    setState(() {
      _isPressed = true;
    });
    _controller.forward();
  }

  void _handleTapUp() {
    setState(() {
      _isPressed = false;
    });
    _controller.reverse();
  }

  void _handleTapCancel() {
    setState(() {
      _isPressed = false;
    });
    _controller.reverse();
  }

  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
    } else {
      _showTransactionDetailDialog();
    }
  }

  void _showActionsMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildActionsBottomSheet(),
    );
  }

  Widget _buildActionsBottomSheet() {
    return Container(
      margin: const EdgeInsets.all(16),
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

          // Actions
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // View details
                _buildActionItem(
                  icon: Icons.visibility_rounded,
                  label: 'Xem chi tiết',
                  onTap: () {
                    Navigator.pop(context);
                    _showTransactionDetailDialog();
                  },
                ),

                const SizedBox(height: 8),

                // Edit
                _buildActionItem(
                  icon: Icons.edit_rounded,
                  label: 'Chỉnh sửa',
                  onTap: () {
                    Navigator.pop(context);
                    _editTransaction();
                  },
                ),

                const SizedBox(height: 8),

                // Delete
                _buildActionItem(
                  icon: Icons.delete_rounded,
                  label: 'Xóa',
                  color: Colors.red,
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final actionColor = color ?? Theme.of(context).textTheme.bodyMedium?.color;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: actionColor, size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(color: actionColor, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionDetailDialog() {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
    final colors = _getTransactionColors();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors['background'],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors['border']!),
                        ),
                        child: Icon(
                          _getTransactionIcon(),
                          color: colors['primary'],
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getTransactionTitle(),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              currencyFormatter.format(
                                widget.transaction.amount,
                              ),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: colors['primary'],
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Details
                  ..._buildDetailRows(),

                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _showDeleteConfirmation();
                          },
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Xóa'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _editTransaction();
                          },
                          icon: const Icon(Icons.edit, size: 18),
                          label: const Text('Chỉnh sửa'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors['primary'],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
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

  List<Widget> _buildDetailRows() {
    List<Widget> rows = [];

    // Date and time
    rows.add(
      _buildDetailRow(
        Icons.schedule_rounded,
        'Thời gian',
        DateFormat(
          'EEEE, dd/MM/yyyy lúc HH:mm',
          'vi_VN',
        ).format(widget.transaction.date),
      ),
    );

    // Category details (if not transfer)
    if (widget.transaction.type != TransactionType.transfer) {
      if (widget.transaction.categoryName.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.category_rounded,
            widget.transaction.type == TransactionType.income
                ? 'Nguồn thu'
                : 'Danh mục',
            widget.transaction.categoryName,
          ),
        );
      }

      if (widget.transaction.subCategoryName.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.subdirectory_arrow_right_rounded,
            'Danh mục con',
            widget.transaction.subCategoryName,
          ),
        );
      }
    }

    // Wallet information
    if (widget.transaction.type == TransactionType.transfer) {
      if (widget.transaction.transferFromWalletName?.isNotEmpty == true) {
        rows.add(
          _buildDetailRow(
            Icons.call_made_rounded,
            'Từ ví',
            widget.transaction.transferFromWalletName!,
          ),
        );
      }
      if (widget.transaction.transferToWalletName?.isNotEmpty == true) {
        rows.add(
          _buildDetailRow(
            Icons.call_received_rounded,
            'Đến ví',
            widget.transaction.transferToWalletName!,
          ),
        );
      }
    } else {
      if (widget.transaction.walletName.isNotEmpty) {
        rows.add(
          _buildDetailRow(
            Icons.account_balance_wallet_rounded,
            'Ví',
            widget.transaction.walletName,
          ),
        );
      }
    }

    // Description
    if (widget.transaction.description.isNotEmpty) {
      rows.add(
        _buildDetailRow(
          Icons.description_rounded,
          'Mô tả',
          widget.transaction.description,
        ),
      );
    }

    return rows;
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    final colors = _getTransactionColors();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors['background'],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colors['primary'], size: 18),
          ),
          const SizedBox(width: 16),
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
                const SizedBox(height: 4),
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

  void _editTransaction() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AddTransactionScreen(transactionToEdit: widget.transaction),
      ),
    ).then((result) {
      if (result == true) {
        widget.onDeleted?.call();
      }
    });
  }

  void _showDeleteConfirmation() {
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
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteTransaction();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTransaction() async {
    try {
      // TODO: Implement delete functionality in TransactionProvider
      // For now, show a message that delete functionality needs to be implemented
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chức năng xóa sẽ được thêm vào TransactionProvider'),
          backgroundColor: Colors.orange,
        ),
      );

      widget.onDeleted?.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xóa: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
