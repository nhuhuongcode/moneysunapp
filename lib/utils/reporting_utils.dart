// lib/utils/_report_utils.dart
import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/category_model.dart';

// ============ REPORT DATA MODELS ============
class ReportData {
  final double totalIncome;
  final double totalExpense;
  final double netAmount;
  final double personalIncome;
  final double personalExpense;
  final double sharedIncome;
  final double sharedExpense;
  final Map<Category, double> incomeByCategory;
  final Map<Category, double> expenseByCategory;
  final Map<String, double> dailyTotals;
  final Map<String, int> transactionCounts;
  final List<TransactionModel> topTransactions;
  final DateTime startDate;
  final DateTime endDate;
  final ReportTrend trend;

  const ReportData({
    required this.totalIncome,
    required this.totalExpense,
    required this.netAmount,
    required this.personalIncome,
    required this.personalExpense,
    required this.sharedIncome,
    required this.sharedExpense,
    required this.incomeByCategory,
    required this.expenseByCategory,
    required this.dailyTotals,
    required this.transactionCounts,
    required this.topTransactions,
    required this.startDate,
    required this.endDate,
    required this.trend,
  });

  bool get hasData => totalIncome > 0 || totalExpense > 0;
  bool get isPositive => netAmount > 0;
  double get totalTransactionAmount => totalIncome + totalExpense;
  int get totalTransactionCount =>
      transactionCounts.values.fold(0, (sum, count) => sum + count);
}

class ReportTrend {
  final TrendDirection direction;
  final double changePercentage;
  final String description;
  final List<double> dailyAmounts;

  const ReportTrend({
    required this.direction,
    required this.changePercentage,
    required this.description,
    required this.dailyAmounts,
  });
}

enum TrendDirection { increasing, decreasing, stable, noData }

// ============ REPORT UTILS CLASS ============
class ReportUtils {
  static ReportData calculateReportData({
    required List<TransactionModel> transactions,
    required List<Category> categories,
    required DateTime startDate,
    required DateTime endDate,
    String? partnershipId,
  }) {
    double totalIncome = 0;
    double totalExpense = 0;
    double personalIncome = 0;
    double personalExpense = 0;
    double sharedIncome = 0;
    double sharedExpense = 0;

    final Map<Category, double> incomeByCategory = {};
    final Map<Category, double> expenseByCategory = {};
    final Map<String, double> dailyTotals = {};
    final Map<String, int> transactionCounts = {};

    // Process each transaction
    for (final transaction in transactions) {
      final dateKey = DateFormat('yyyy-MM-dd').format(transaction.date);
      final category = categories.firstWhereOrNull(
        (c) => c.id == transaction.categoryId,
      );

      // Update daily totals
      dailyTotals[dateKey] = (dailyTotals[dateKey] ?? 0) + transaction.amount;

      // Update transaction counts
      final countKey = '${transaction.type.name}_${dateKey}';
      transactionCounts[countKey] = (transactionCounts[countKey] ?? 0) + 1;

      // Process by transaction type
      switch (transaction.type) {
        case TransactionType.income:
          totalIncome += transaction.amount;

          // Determine if personal or shared
          if (category?.isShared == true ||
              (partnershipId != null && category?.ownerId == partnershipId)) {
            sharedIncome += transaction.amount;
          } else {
            personalIncome += transaction.amount;
          }

          // Add to category breakdown
          if (category != null) {
            incomeByCategory[category] =
                (incomeByCategory[category] ?? 0) + transaction.amount;
          }
          break;

        case TransactionType.expense:
          totalExpense += transaction.amount;

          // Determine if personal or shared
          if (category?.isShared == true ||
              (partnershipId != null && category?.ownerId == partnershipId)) {
            sharedExpense += transaction.amount;
          } else {
            personalExpense += transaction.amount;
          }

          // Add to category breakdown
          if (category != null) {
            expenseByCategory[category] =
                (expenseByCategory[category] ?? 0) + transaction.amount;
          }
          break;

        case TransactionType.transfer:
          // Transfers don't affect income/expense totals
          break;
      }
    }

    // Calculate trend
    final trend = _calculateTrend(dailyTotals, startDate, endDate);

    // Get top transactions
    final topTransactions = _getTopTransactions(transactions, 5);

    return ReportData(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      netAmount: totalIncome - totalExpense,
      personalIncome: personalIncome,
      personalExpense: personalExpense,
      sharedIncome: sharedIncome,
      sharedExpense: sharedExpense,
      incomeByCategory: incomeByCategory,
      expenseByCategory: expenseByCategory,
      dailyTotals: dailyTotals,
      transactionCounts: transactionCounts,
      topTransactions: topTransactions,
      startDate: startDate,
      endDate: endDate,
      trend: trend,
    );
  }

  static ReportTrend _calculateTrend(
    Map<String, double> dailyTotals,
    DateTime startDate,
    DateTime endDate,
  ) {
    if (dailyTotals.isEmpty) {
      return const ReportTrend(
        direction: TrendDirection.noData,
        changePercentage: 0,
        description: 'Không có dữ liệu',
        dailyAmounts: [],
      );
    }

    final sortedEntries = dailyTotals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final dailyAmounts = sortedEntries.map((e) => e.value).toList();

    if (dailyAmounts.length < 2) {
      return ReportTrend(
        direction: TrendDirection.stable,
        changePercentage: 0,
        description: 'Ổn định',
        dailyAmounts: dailyAmounts,
      );
    }

    // Calculate trend using linear regression
    final n = dailyAmounts.length;
    final x = List.generate(n, (i) => i.toDouble());
    final y = dailyAmounts;

    final xMean = x.reduce((a, b) => a + b) / n;
    final yMean = y.reduce((a, b) => a + b) / n;

    double numerator = 0;
    double denominator = 0;

    for (int i = 0; i < n; i++) {
      numerator += (x[i] - xMean) * (y[i] - yMean);
      denominator += (x[i] - xMean) * (x[i] - xMean);
    }

    final slope = denominator != 0 ? numerator / denominator : 0;
    final changePercentage = yMean != 0 ? (slope / yMean) * 100 : 0;

    TrendDirection direction;
    String description;

    if (changePercentage.abs() < 5) {
      direction = TrendDirection.stable;
      description = 'Ổn định';
    } else if (changePercentage > 0) {
      direction = TrendDirection.increasing;
      description = 'Tăng ${changePercentage.toStringAsFixed(1)}%';
    } else {
      direction = TrendDirection.decreasing;
      description = 'Giảm ${changePercentage.abs().toStringAsFixed(1)}%';
    }

    return ReportTrend(
      direction: direction,
      changePercentage: changePercentage as double,
      description: description,
      dailyAmounts: dailyAmounts,
    );
  }

  static List<TransactionModel> _getTopTransactions(
    List<TransactionModel> transactions,
    int count,
  ) {
    final sortedTransactions = List<TransactionModel>.from(transactions)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return sortedTransactions.take(count).toList();
  }

  static Map<String, double> calculateMonthlyComparison(
    List<TransactionModel> currentMonthTransactions,
    List<TransactionModel> previousMonthTransactions,
  ) {
    final currentIncome = currentMonthTransactions
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);

    final currentExpense = currentMonthTransactions
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (sum, t) => sum + t.amount);

    final previousIncome = previousMonthTransactions
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);

    final previousExpense = previousMonthTransactions
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (sum, t) => sum + t.amount);

    final incomeChange = previousIncome != 0
        ? ((currentIncome - previousIncome) / previousIncome) * 100
        : 0.0;

    final expenseChange = previousExpense != 0
        ? ((currentExpense - previousExpense) / previousExpense) * 100
        : 0.0;

    return {
      'currentIncome': currentIncome,
      'currentExpense': currentExpense,
      'previousIncome': previousIncome,
      'previousExpense': previousExpense,
      'incomeChange': incomeChange,
      'expenseChange': expenseChange,
    };
  }
}

// ============  TRANSACTION SUMMARY WIDGET ============
class TransactionSummary extends StatelessWidget {
  final ReportData reportData;
  final bool showTrend;
  final bool showComparison;
  final VoidCallback? onTap;

  const TransactionSummary({
    super.key,
    required this.reportData,
    this.showTrend = true,
    this.showComparison = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 4,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).primaryColor.withOpacity(0.1),
                Theme.of(context).primaryColor.withOpacity(0.05),
              ],
            ),
          ),
          child: Column(
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tổng quan tài chính',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (showTrend) _buildTrendIndicator(),
                ],
              ),

              const SizedBox(height: 20),

              // Main stats
              Row(
                children: [
                  Expanded(
                    child: _buildStatColumn(
                      'Thu nhập',
                      reportData.totalIncome,
                      Colors.green,
                      Icons.trending_up,
                      currencyFormatter,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 60,
                    color: Colors.grey.shade300,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  Expanded(
                    child: _buildStatColumn(
                      'Chi tiêu',
                      reportData.totalExpense,
                      Colors.red,
                      Icons.trending_down,
                      currencyFormatter,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Net amount
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (reportData.isPositive ? Colors.green : Colors.red)
                      .withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (reportData.isPositive ? Colors.green : Colors.red)
                        .withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Số dư ròng',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: reportData.isPositive
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                    Text(
                      '${reportData.isPositive ? '+' : ''}${currencyFormatter.format(reportData.netAmount)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: reportData.isPositive
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),

              // Transaction count
              if (reportData.totalTransactionCount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '${reportData.totalTransactionCount} giao dịch • ${DateFormat('dd/MM').format(reportData.startDate)} - ${DateFormat('dd/MM/yyyy').format(reportData.endDate)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    String label,
    double amount,
    Color color,
    IconData icon,
    NumberFormat formatter,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
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
          formatter.format(amount),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTrendIndicator() {
    if (reportData.trend.direction == TrendDirection.noData) {
      return const SizedBox.shrink();
    }

    Color trendColor;
    IconData trendIcon;

    switch (reportData.trend.direction) {
      case TrendDirection.increasing:
        trendColor = Colors.green;
        trendIcon = Icons.trending_up;
        break;
      case TrendDirection.decreasing:
        trendColor = Colors.red;
        trendIcon = Icons.trending_down;
        break;
      case TrendDirection.stable:
        trendColor = Colors.blue;
        trendIcon = Icons.trending_flat;
        break;
      case TrendDirection.noData:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: trendColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: trendColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(trendIcon, color: trendColor, size: 16),
          const SizedBox(width: 4),
          Text(
            reportData.trend.description,
            style: TextStyle(
              fontSize: 12,
              color: trendColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============  CONNECTION STATUS BANNER ============
class ConnectionStatusBanner extends StatelessWidget {
  final bool isOnline;
  final bool isSyncing;
  final int pendingItems;
  final String? lastError;
  final DateTime? lastSyncTime;
  final VoidCallback? onRetry;
  final VoidCallback? onDismiss;

  const ConnectionStatusBanner({
    super.key,
    required this.isOnline,
    this.isSyncing = false,
    this.pendingItems = 0,
    this.lastError,
    this.lastSyncTime,
    this.onRetry,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (isOnline && !isSyncing && pendingItems == 0 && lastError == null) {
      return const SizedBox.shrink();
    }

    final statusInfo = _getStatusInfo();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      color: statusInfo['color'],
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (isSyncing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      statusInfo['iconColor']!,
                    ),
                  ),
                )
              else
                Icon(
                  statusInfo['icon'],
                  color: statusInfo['iconColor'],
                  size: 16,
                ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusInfo['title']!,
                      style: TextStyle(
                        color: statusInfo['textColor'],
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (statusInfo['subtitle'] != null)
                      Text(
                        statusInfo['subtitle']!,
                        style: TextStyle(
                          color: statusInfo['textColor']!.withOpacity(0.8),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),

              if (onRetry != null &&
                  (lastError != null || (!isOnline && pendingItems > 0)))
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(
                    foregroundColor: statusInfo['textColor'],
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                  ),
                  child: const Text('Thử lại', style: TextStyle(fontSize: 12)),
                ),

              if (onDismiss != null)
                IconButton(
                  onPressed: onDismiss,
                  icon: Icon(
                    Icons.close,
                    color: statusInfo['iconColor'],
                    size: 16,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo() {
    if (lastError != null) {
      return {
        'color': Colors.red.shade600,
        'iconColor': Colors.white,
        'textColor': Colors.white,
        'icon': Icons.error_outline,
        'title': 'Lỗi đồng bộ',
        'subtitle': 'Một số thay đổi có thể chưa được lưu',
      };
    }

    if (isSyncing) {
      return {
        'color': Colors.blue.shade600,
        'iconColor': Colors.white,
        'textColor': Colors.white,
        'icon': Icons.sync,
        'title': 'Đang đồng bộ...',
        'subtitle': pendingItems > 0 ? '$pendingItems mục đang xử lý' : null,
      };
    }

    if (!isOnline) {
      return {
        'color': Colors.orange.shade600,
        'iconColor': Colors.white,
        'textColor': Colors.white,
        'icon': Icons.cloud_off,
        'title': 'Chế độ Offline',
        'subtitle': pendingItems > 0
            ? '$pendingItems mục chờ đồng bộ'
            : 'Mọi thay đổi sẽ được đồng bộ khi có mạng',
      };
    }

    if (pendingItems > 0) {
      return {
        'color': Colors.blue.shade600,
        'iconColor': Colors.white,
        'textColor': Colors.white,
        'icon': Icons.sync_problem,
        'title': 'Đang chờ đồng bộ',
        'subtitle': '$pendingItems mục chưa được đồng bộ',
      };
    }

    return {
      'color': Colors.green.shade600,
      'iconColor': Colors.white,
      'textColor': Colors.white,
      'icon': Icons.cloud_done,
      'title': 'Đã đồng bộ',
      'subtitle': lastSyncTime != null
          ? 'Lần cuối: ${DateFormat('HH:mm').format(lastSyncTime!)}'
          : null,
    };
  }
}
