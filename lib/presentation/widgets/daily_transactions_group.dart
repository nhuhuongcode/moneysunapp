// lib/presentation/widgets/_daily_transactions_group.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/presentation/widgets/transaction_item.dart';
import 'package:moneysun/presentation/widgets/transaction_list_item.dart';
import 'package:collection/collection.dart';

class DailyTransactionsGroup extends StatefulWidget {
  final DateTime date;
  final List<TransactionModel> transactions;
  final VoidCallback? onTransactionUpdated;
  final bool showHeader;
  final bool isCompact;
  final bool showAnimations;
  final int maxItemsToShow;

  const DailyTransactionsGroup({
    super.key,
    required this.date,
    required this.transactions,
    this.onTransactionUpdated,
    this.showHeader = true,
    this.isCompact = false,
    this.showAnimations = true,
    this.maxItemsToShow = 5,
  });

  @override
  State<DailyTransactionsGroup> createState() => _DailyTransactionsGroupState();
}

class _DailyTransactionsGroupState extends State<DailyTransactionsGroup>
    with TickerProviderStateMixin {
  late AnimationController _expandController;
  late AnimationController _slideController;
  late Animation<double> _expandAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isExpanded = false;
  DailyStats? _dailyStats;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _calculateStats();
  }

  void _initializeAnimations() {
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _expandAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _expandController, curve: Curves.easeInOut),
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
        );

    if (widget.showAnimations) {
      _slideController.forward();
    } else {
      _slideController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(DailyTransactionsGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.transactions, widget.transactions)) {
      _calculateStats();
    }
  }

  void _calculateStats() {
    _dailyStats = DailyStats.fromTransactions(widget.transactions);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transactions.isEmpty) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          children: [
            if (widget.showHeader) _buildHeader(),
            _buildTransactionsList(),
            if (widget.isCompact && !widget.showHeader) _buildCompactFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (_dailyStats == null) return const SizedBox.shrink();

    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor.withOpacity(0.08),
            Theme.of(context).primaryColor.withOpacity(0.03),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Date and main stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date section
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        DateFormat('EEEE', 'vi_VN').format(widget.date),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('dd/MM/yyyy').format(widget.date),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_dailyStats!.totalTransactions} giao dịch',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // Net amount section
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Số dư',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (_dailyStats!.netAmount >= 0
                                    ? Colors.green
                                    : Colors.red)
                                .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              (_dailyStats!.netAmount >= 0
                                      ? Colors.green
                                      : Colors.red)
                                  .withOpacity(0.3),
                        ),
                      ),
                      child: Text(
                        currencyFormatter.format(_dailyStats!.netAmount),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: _dailyStats!.netAmount >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Stats cards row
          Row(
            children: [
              if (_dailyStats!.totalIncome > 0)
                Expanded(
                  child: _buildStatCard(
                    'Thu nhập',
                    _dailyStats!.totalIncome,
                    _dailyStats!.incomeCount,
                    Colors.green,
                    Icons.trending_up,
                    currencyFormatter,
                  ),
                ),
              if (_dailyStats!.totalIncome > 0 && _dailyStats!.totalExpense > 0)
                const SizedBox(width: 12),
              if (_dailyStats!.totalExpense > 0)
                Expanded(
                  child: _buildStatCard(
                    'Chi tiêu',
                    _dailyStats!.totalExpense,
                    _dailyStats!.expenseCount,
                    Colors.red,
                    Icons.trending_down,
                    currencyFormatter,
                  ),
                ),
              if (_dailyStats!.transferCount > 0) ...[
                if (_dailyStats!.totalIncome > 0 ||
                    _dailyStats!.totalExpense > 0)
                  const SizedBox(width: 12),
                Expanded(
                  child: _buildTransferCard(
                    _dailyStats!.transferCount,
                    currencyFormatter,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String label,
    double amount,
    int count,
    Color color,
    IconData icon,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            formatter.format(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            '$count giao dịch',
            style: TextStyle(fontSize: 10, color: color.withOpacity(0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTransferCard(int transferCount, NumberFormat formatter) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.swap_horiz,
                  color: Colors.orange.shade600,
                  size: 16,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Chuyển',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$transferCount',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.orange.shade700,
            ),
          ),
          Text(
            'giao dịch',
            style: TextStyle(fontSize: 10, color: Colors.orange.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    final displayTransactions = widget.transactions
        .take(widget.maxItemsToShow)
        .toList();
    final hasMore = widget.transactions.length > widget.maxItemsToShow;

    return Column(
      children: [
        // Transactions list
        ...displayTransactions.asMap().entries.map((entry) {
          final index = entry.key;
          final transaction = entry.value;
          final isLast = index == displayTransactions.length - 1 && !hasMore;

          return Column(
            children: [
              if (widget.showAnimations)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 200 + (index * 100)),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Opacity(opacity: value, child: child),
                    );
                  },
                  child: _buildTransactionItem(transaction),
                )
              else
                _buildTransactionItem(transaction),
              if (!isLast)
                Divider(
                  height: 1,
                  color: Colors.grey.shade200,
                  indent: 72,
                  endIndent: 20,
                ),
            ],
          );
        }).toList(),

        // Show more button
        if (hasMore) _buildShowMoreButton(),

        // Expanded transactions
        AnimatedSize(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          child: _isExpanded
              ? _buildExpandedTransactions()
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTransactionItem(TransactionModel transaction) {
    return TransactionItem(
      transaction: transaction,
      onDeleted: widget.onTransactionUpdated,
      showDate: false, // Don't show date since it's in the header
      isCompact: widget.isCompact,
    );
  }

  Widget _buildShowMoreButton() {
    final remainingCount = widget.transactions.length - widget.maxItemsToShow;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: TextButton.icon(
        onPressed: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
          if (_isExpanded) {
            _expandController.forward();
          } else {
            _expandController.reverse();
          }
        },
        icon: AnimatedRotation(
          turns: _isExpanded ? 0.5 : 0,
          duration: const Duration(milliseconds: 300),
          child: Icon(
            Icons.keyboard_arrow_down,
            size: 20,
            color: Theme.of(context).primaryColor,
          ),
        ),
        label: Text(
          _isExpanded ? 'Thu gọn' : 'Xem thêm $remainingCount giao dịch',
          style: TextStyle(
            color: Theme.of(context).primaryColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: TextButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
    );
  }

  Widget _buildExpandedTransactions() {
    final remainingTransactions = widget.transactions
        .skip(widget.maxItemsToShow)
        .toList();

    return Column(
      children: remainingTransactions.asMap().entries.map((entry) {
        final index = entry.key;
        final transaction = entry.value;
        final isLast = index == remainingTransactions.length - 1;

        return FadeTransition(
          opacity: _expandAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(_expandAnimation),
            child: Column(
              children: [
                Divider(
                  height: 1,
                  color: Colors.grey.shade200,
                  indent: 72,
                  endIndent: 20,
                ),
                _buildTransactionItem(transaction),
                if (isLast) const SizedBox(height: 8),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCompactFooter() {
    if (_dailyStats == null) return const SizedBox.shrink();

    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                DateFormat('dd/MM').format(widget.date),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_dailyStats!.totalTransactions} giao dịch',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          Text(
            currencyFormatter.format(_dailyStats!.netAmount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _dailyStats!.netAmount >= 0
                  ? Colors.green.shade600
                  : Colors.red.shade600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _expandController.dispose();
    _slideController.dispose();
    super.dispose();
  }
}

//  daily statistics data class
class DailyStats {
  final double totalIncome;
  final double totalExpense;
  final double netAmount;
  final int incomeCount;
  final int expenseCount;
  final int transferCount;
  final int totalTransactions;
  final List<TransactionModel> topTransactions;

  const DailyStats({
    required this.totalIncome,
    required this.totalExpense,
    required this.netAmount,
    required this.incomeCount,
    required this.expenseCount,
    required this.transferCount,
    required this.totalTransactions,
    required this.topTransactions,
  });

  factory DailyStats.fromTransactions(List<TransactionModel> transactions) {
    double totalIncome = 0;
    double totalExpense = 0;
    int incomeCount = 0;
    int expenseCount = 0;
    int transferCount = 0;

    for (final transaction in transactions) {
      switch (transaction.type) {
        case TransactionType.income:
          totalIncome += transaction.amount;
          incomeCount++;
          break;
        case TransactionType.expense:
          totalExpense += transaction.amount;
          expenseCount++;
          break;
        case TransactionType.transfer:
          transferCount++;
          break;
      }
    }

    // Get top transactions by amount
    final sortedTransactions = List<TransactionModel>.from(transactions)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final topTransactions = sortedTransactions.take(3).toList();

    return DailyStats(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      netAmount: totalIncome - totalExpense,
      incomeCount: incomeCount,
      expenseCount: expenseCount,
      transferCount: transferCount,
      totalTransactions: transactions.length,
      topTransactions: topTransactions,
    );
  }

  bool get hasPositiveBalance => netAmount > 0;
  bool get hasTransactions => totalTransactions > 0;
  bool get hasIncomeAndExpense => incomeCount > 0 && expenseCount > 0;
}

// Utility functions for grouping transactions
Map<DateTime, List<TransactionModel>> groupTransactionsByDate(
  List<TransactionModel> transactions,
) {
  final groupedTransactions = <DateTime, List<TransactionModel>>{};

  for (final transaction in transactions) {
    final date = DateTime(
      transaction.date.year,
      transaction.date.month,
      transaction.date.day,
    );

    if (groupedTransactions.containsKey(date)) {
      groupedTransactions[date]!.add(transaction);
    } else {
      groupedTransactions[date] = [transaction];
    }
  }

  // Sort transactions within each day by time (newest first)
  for (final transactions in groupedTransactions.values) {
    transactions.sort((a, b) => b.date.compareTo(a.date));
  }

  return groupedTransactions;
}

// Widget for displaying multiple days with  features
class TransactionsByDateWidget extends StatelessWidget {
  final Map<DateTime, List<TransactionModel>> transactionsByDate;
  final VoidCallback? onTransactionUpdated;
  final bool showEmptyDays;
  final int maxDaysToShow;
  final bool showAnimations;

  const TransactionsByDateWidget({
    super.key,
    required this.transactionsByDate,
    this.onTransactionUpdated,
    this.showEmptyDays = false,
    this.maxDaysToShow = 30,
    this.showAnimations = true,
  });

  @override
  Widget build(BuildContext context) {
    final sortedDates = transactionsByDate.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Most recent first

    final datesToShow = sortedDates.take(maxDaysToShow).toList();

    if (datesToShow.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: datesToShow.length,
      itemBuilder: (context, index) {
        final date = datesToShow[index];
        final transactions = transactionsByDate[date] ?? [];

        if (transactions.isEmpty && !showEmptyDays) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DailyTransactionsGroup(
            date: date,
            transactions: transactions,
            onTransactionUpdated: onTransactionUpdated,
            showAnimations: showAnimations,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Chưa có giao dịch nào',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thêm giao dịch đầu tiên để bắt đầu theo dõi tài chính của bạn',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // Navigate to add transaction
            },
            icon: const Icon(Icons.add),
            label: const Text('Thêm giao dịch đầu tiên'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
