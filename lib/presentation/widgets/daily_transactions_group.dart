// lib/presentation/widgets/daily_transactions_group.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/presentation/widgets/transaction_list_item_detailed.dart';

class DailyTransactionsGroup extends StatelessWidget {
  final DateTime date;
  final List<TransactionModel> transactions;
  final VoidCallback? onTransactionUpdated;
  final bool showHeader;
  final bool isCompact;

  const DailyTransactionsGroup({
    super.key,
    required this.date,
    required this.transactions,
    this.onTransactionUpdated,
    this.showHeader = true,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // Calculate daily totals
    final dailyStats = _calculateDailyStats();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          if (showHeader) _buildHeader(context, currencyFormatter, dailyStats),

          // Transaction list
          ...transactions.asMap().entries.map((entry) {
            final index = entry.key;
            final transaction = entry.value;
            final isLast = index == transactions.length - 1;

            return Column(
              children: [
                TransactionListItemDetailed(
                  transaction: transaction,
                  onDeleted: onTransactionUpdated,
                ),
                if (!isLast)
                  Divider(
                    height: 1,
                    color: Colors.grey.shade200,
                    indent: 72,
                    endIndent: 16,
                  ),
              ],
            );
          }).toList(),

          // Footer with summary (compact mode)
          if (isCompact && !showHeader)
            _buildCompactFooter(context, currencyFormatter, dailyStats),
        ],
      ),
    );
  }

  DailyStats _calculateDailyStats() {
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

    return DailyStats(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      netAmount: totalIncome - totalExpense,
      incomeCount: incomeCount,
      expenseCount: expenseCount,
      transferCount: transferCount,
      totalTransactions: transactions.length,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    NumberFormat formatter,
    DailyStats stats,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).primaryColor.withOpacity(0.1),
            Theme.of(context).primaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          // Date and net amount
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('EEEE', 'vi_VN').format(date),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    DateFormat('dd/MM/yyyy').format(date),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Số dư',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    formatter.format(stats.netAmount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: stats.netAmount >= 0
                          ? Colors.green.shade600
                          : Colors.red.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Income and expense summary
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  'Thu nhập',
                  stats.totalIncome,
                  stats.incomeCount,
                  Colors.green,
                  Icons.trending_up,
                  formatter,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  context,
                  'Chi tiêu',
                  stats.totalExpense,
                  stats.expenseCount,
                  Colors.red,
                  Icons.trending_down,
                  formatter,
                ),
              ),
              if (stats.transferCount > 0) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _buildTransferCard(
                    context,
                    stats.transferCount,
                    formatter,
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
    BuildContext context,
    String label,
    double amount,
    int count,
    Color color,
    IconData icon,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            formatter.format(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            '$count giao dịch',
            style: TextStyle(fontSize: 10, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferCard(
    BuildContext context,
    int transferCount,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swap_horiz, color: Colors.orange.shade600, size: 16),
              const SizedBox(width: 4),
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
          const SizedBox(height: 4),
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

  Widget _buildCompactFooter(
    BuildContext context,
    NumberFormat formatter,
    DailyStats stats,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${stats.totalTransactions} giao dịch',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Text(
            formatter.format(stats.netAmount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: stats.netAmount >= 0
                  ? Colors.green.shade600
                  : Colors.red.shade600,
            ),
          ),
        ],
      ),
    );
  }
}

// Data class for daily statistics
class DailyStats {
  final double totalIncome;
  final double totalExpense;
  final double netAmount;
  final int incomeCount;
  final int expenseCount;
  final int transferCount;
  final int totalTransactions;

  const DailyStats({
    required this.totalIncome,
    required this.totalExpense,
    required this.netAmount,
    required this.incomeCount,
    required this.expenseCount,
    required this.transferCount,
    required this.totalTransactions,
  });
}

// Enhanced widget for displaying multiple days with transactions
class TransactionsByDateWidget extends StatelessWidget {
  final Map<DateTime, List<TransactionModel>> transactionsByDate;
  final VoidCallback? onTransactionUpdated;
  final bool showEmptyDays;
  final int maxDaysToShow;

  const TransactionsByDateWidget({
    super.key,
    required this.transactionsByDate,
    this.onTransactionUpdated,
    this.showEmptyDays = false,
    this.maxDaysToShow = 30,
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
          padding: const EdgeInsets.only(bottom: 8),
          child: DailyTransactionsGroup(
            date: date,
            transactions: transactions,
            onTransactionUpdated: onTransactionUpdated,
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Chưa có giao dịch nào',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Text(
            'Thêm giao dịch đầu tiên để bắt đầu theo dõi tài chính',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

// Utility function to group transactions by date
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
