// lib/presentation/widgets/enhanced_summary_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';

class SummaryCard extends StatefulWidget {
  final DateTime startDate;
  final DateTime endDate;
  final bool showPartnership;
  final bool showAnimations;
  final Map<String, dynamic>? cachedStats;

  const SummaryCard({
    super.key,
    required this.startDate,
    required this.endDate,
    this.showPartnership = true,
    this.showAnimations = true,
    this.cachedStats,
  });

  @override
  State<SummaryCard> createState() => _EnhancedSummaryCardState();
}

class _EnhancedSummaryCardState extends State<SummaryCard>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _scaleController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  bool _isExpanded = false;
  SummaryData? _summaryData;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _calculateSummary();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.elasticOut),
    );

    if (widget.showAnimations) {
      _slideController.forward();
      _scaleController.forward();
    } else {
      _slideController.value = 1.0;
      _scaleController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(SummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate) {
      _calculateSummary();
    }
  }

  Future<void> _calculateSummary() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Use cached stats if available and recent
      if (widget.cachedStats != null) {
        final lastUpdated = widget.cachedStats!['lastUpdated'] as DateTime?;
        if (lastUpdated != null &&
            DateTime.now().difference(lastUpdated).inMinutes < 5) {
          _summaryData = SummaryData.fromCachedStats(widget.cachedStats!);
          setState(() {
            _isLoading = false;
          });
          return;
        }
      }

      final transactionProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );
      final userProvider = Provider.of<UserProvider>(context, listen: false);

      // Wait a bit for provider to load data
      await Future.delayed(const Duration(milliseconds: 200));

      final transactions = transactionProvider.transactions
          .where(
            (t) =>
                t.date.isAfter(
                  widget.startDate.subtract(const Duration(days: 1)),
                ) &&
                t.date.isBefore(widget.endDate.add(const Duration(days: 1))),
          )
          .toList();

      _summaryData = _calculateSummaryFromTransactions(
        transactions,
        userProvider,
      );
    } catch (e) {
      debugPrint('Error calculating summary: $e');
      _summaryData = SummaryData.empty();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  SummaryData _calculateSummaryFromTransactions(
    List<TransactionModel> transactions,
    UserProvider userProvider,
  ) {
    double totalIncome = 0;
    double totalExpense = 0;
    double personalIncome = 0;
    double personalExpense = 0;
    double sharedIncome = 0;
    double sharedExpense = 0;
    int transferCount = 0;

    final currentUserId = userProvider.currentUser?.uid;
    final partnershipId = userProvider.partnershipId;

    for (final transaction in transactions) {
      switch (transaction.type) {
        case TransactionType.income:
          totalIncome += transaction.amount;
          if (_isSharedTransaction(transaction, currentUserId, partnershipId)) {
            sharedIncome += transaction.amount;
          } else {
            personalIncome += transaction.amount;
          }
          break;

        case TransactionType.expense:
          totalExpense += transaction.amount;
          if (_isSharedTransaction(transaction, currentUserId, partnershipId)) {
            sharedExpense += transaction.amount;
          } else {
            personalExpense += transaction.amount;
          }
          break;

        case TransactionType.transfer:
          transferCount++;
          break;
      }
    }

    return SummaryData(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      personalIncome: personalIncome,
      personalExpense: personalExpense,
      sharedIncome: sharedIncome,
      sharedExpense: sharedExpense,
      transactionCount: transactions.length,
      transferCount: transferCount,
    );
  }

  bool _isSharedTransaction(
    TransactionModel transaction,
    String? currentUserId,
    String? partnershipId,
  ) {
    // Simple heuristic - in a real app, you'd check wallet ownership
    return transaction.walletName.toLowerCase().contains('chung') ||
        transaction.categoryName.toLowerCase().contains('chung');
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: _buildSummaryCard(),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard() {
    return Consumer3<UserProvider, WalletProvider, ConnectionStatusProvider>(
      builder:
          (context, userProvider, walletProvider, connectionStatus, child) {
            return Card(
              elevation: 8,
              shadowColor: Theme.of(context).primaryColor.withOpacity(0.3),
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Theme.of(context).primaryColor.withOpacity(0.05),
                      Theme.of(context).scaffoldBackgroundColor,
                      Theme.of(context).primaryColor.withOpacity(0.02),
                    ],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(connectionStatus),
                      const SizedBox(height: 24),
                      _buildMainBalance(walletProvider),
                      const SizedBox(height: 24),
                      _buildIncomeExpenseRow(),
                      if (widget.showPartnership &&
                          userProvider.hasPartner) ...[
                        const SizedBox(height: 20),
                        _buildPartnershipSection(userProvider),
                      ],
                      const SizedBox(height: 20),
                      _buildBottomInfo(),
                    ],
                  ),
                ),
              ),
            );
          },
    );
  }

  Widget _buildHeader(ConnectionStatusProvider connectionStatus) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
            ),
          ),
          child: Icon(
            Icons.account_balance_wallet_rounded,
            color: Theme.of(context).primaryColor,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tổng quan tài chính',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                _formatDateRange(),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        // Sync status indicator
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: connectionStatus.statusColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: connectionStatus.statusColor.withOpacity(0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (connectionStatus.isSyncing)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      connectionStatus.statusColor,
                    ),
                  ),
                )
              else
                Icon(
                  connectionStatus.isOnline
                      ? Icons.cloud_done
                      : Icons.cloud_off,
                  size: 12,
                  color: connectionStatus.statusColor,
                ),
              const SizedBox(width: 4),
              Text(
                connectionStatus.isOnline ? 'Online' : 'Offline',
                style: TextStyle(
                  fontSize: 10,
                  color: connectionStatus.statusColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainBalance(WalletProvider walletProvider) {
    if (_isLoading) {
      return _buildLoadingBalance();
    }

    final totalBalance = _summaryData?.totalBalance ?? 0.0;
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Center(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: Text(
              currencyFormatter.format(totalBalance),
              key: ValueKey(totalBalance),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: totalBalance >= 0
                    ? Colors.green.shade600
                    : Colors.red.shade600,
                fontWeight: FontWeight.bold,
                fontSize: 32,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: (totalBalance >= 0 ? Colors.green : Colors.red)
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: (totalBalance >= 0 ? Colors.green : Colors.red)
                    .withOpacity(0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  totalBalance >= 0 ? Icons.trending_up : Icons.trending_down,
                  size: 16,
                  color: totalBalance >= 0
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Số dư tổng',
                  style: TextStyle(
                    color: totalBalance >= 0
                        ? Colors.green.shade700
                        : Colors.red.shade700,
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

  Widget _buildLoadingBalance() {
    return Center(
      child: Column(
        children: [
          CircularProgressIndicator(
            color: Theme.of(context).primaryColor,
            strokeWidth: 3,
          ),
          const SizedBox(height: 16),
          Text(
            'Đang tính toán...',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildIncomeExpenseRow() {
    if (_summaryData == null) {
      return const SizedBox.shrink();
    }

    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Row(
      children: [
        Expanded(
          child: _buildIncomeExpenseCard(
            context,
            'Thu nhập',
            _summaryData!.totalIncome,
            Colors.green,
            Icons.trending_up,
            currencyFormatter,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildIncomeExpenseCard(
            context,
            'Chi tiêu',
            _summaryData!.totalExpense,
            Colors.red,
            Icons.trending_down,
            currencyFormatter,
          ),
        ),
      ],
    );
  }

  Widget _buildIncomeExpenseCard(
    BuildContext context,
    String title,
    double amount,
    Color color,
    IconData icon,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              formatter.format(amount),
              key: ValueKey('${title}_$amount'),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnershipSection(UserProvider userProvider) {
    if (_summaryData == null) {
      return const SizedBox.shrink();
    }

    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.people_rounded,
                    color: Colors.blue.shade600,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Chi tiết theo loại',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Column(
                    children: [
                      const SizedBox(height: 16),
                      _buildSectionCard(
                        context,
                        '💼 Cá nhân',
                        _summaryData!.personalBalance,
                        _summaryData!.personalIncome,
                        _summaryData!.personalExpense,
                        Colors.blue,
                        currencyFormatter,
                      ),
                      const SizedBox(height: 12),
                      _buildSectionCard(
                        context,
                        '👥 Chung (${userProvider.partnerDisplayName ?? "Đối tác"})',
                        _summaryData!.sharedBalance,
                        _summaryData!.sharedIncome,
                        _summaryData!.sharedExpense,
                        Colors.orange,
                        currencyFormatter,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    String title,
    double balance,
    double income,
    double expense,
    Color color,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
                ),
              ),
              Text(
                formatter.format(balance),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: balance >= 0
                      ? Colors.green.shade600
                      : Colors.red.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSmallStat('Thu nhập', income, Colors.green, formatter),
              _buildSmallStat('Chi tiêu', expense, Colors.red, formatter),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStat(
    String label,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          formatter.format(amount),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInfo() {
    if (_summaryData == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildBottomInfoItem(
            Icons.receipt_long,
            'Giao dịch',
            '${_summaryData!.transactionCount}',
            Colors.blue,
          ),
          if (_summaryData!.transferCount > 0)
            _buildBottomInfoItem(
              Icons.swap_horiz,
              'Chuyển tiền',
              '${_summaryData!.transferCount}',
              Colors.orange,
            ),
          _buildBottomInfoItem(
            Icons.schedule,
            'Cập nhật',
            DateFormat('HH:mm').format(DateTime.now()),
            Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInfoItem(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  String _formatDateRange() {
    final formatter = DateFormat('dd/MM/yyyy');
    if (widget.startDate.year == widget.endDate.year &&
        widget.startDate.month == widget.endDate.month &&
        widget.startDate.day == widget.endDate.day) {
      return formatter.format(widget.startDate);
    }
    return '${formatter.format(widget.startDate)} - ${formatter.format(widget.endDate)}';
  }

  @override
  void dispose() {
    _slideController.dispose();
    _scaleController.dispose();
    super.dispose();
  }
}

// Enhanced data class for summary calculations
class SummaryData {
  final double totalIncome;
  final double totalExpense;
  final double personalIncome;
  final double personalExpense;
  final double sharedIncome;
  final double sharedExpense;
  final int transactionCount;
  final int transferCount;

  const SummaryData({
    required this.totalIncome,
    required this.totalExpense,
    required this.personalIncome,
    required this.personalExpense,
    required this.sharedIncome,
    required this.sharedExpense,
    required this.transactionCount,
    this.transferCount = 0,
  });

  double get totalBalance => totalIncome - totalExpense;
  double get personalBalance => personalIncome - personalExpense;
  double get sharedBalance => sharedIncome - sharedExpense;

  static SummaryData empty() {
    return const SummaryData(
      totalIncome: 0,
      totalExpense: 0,
      personalIncome: 0,
      personalExpense: 0,
      sharedIncome: 0,
      sharedExpense: 0,
      transactionCount: 0,
      transferCount: 0,
    );
  }

  static SummaryData fromCachedStats(Map<String, dynamic> stats) {
    return SummaryData(
      totalIncome: (stats['totalIncome'] ?? 0).toDouble(),
      totalExpense: (stats['totalExpense'] ?? 0).toDouble(),
      personalIncome: (stats['personalIncome'] ?? 0).toDouble(),
      personalExpense: (stats['personalExpense'] ?? 0).toDouble(),
      sharedIncome: (stats['sharedIncome'] ?? 0).toDouble(),
      sharedExpense: (stats['sharedExpense'] ?? 0).toDouble(),
      transactionCount: stats['transactionCount'] ?? 0,
      transferCount: stats['transferCount'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'personalIncome': personalIncome,
      'personalExpense': personalExpense,
      'sharedIncome': sharedIncome,
      'sharedExpense': sharedExpense,
      'transactionCount': transactionCount,
      'transferCount': transferCount,
      'totalBalance': totalBalance,
      'personalBalance': personalBalance,
      'sharedBalance': sharedBalance,
    };
  }
}
