// lib/presentation/screens/_category_detail_report_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:moneysun/utils/chart_utils.dart';

class CategoryDetailReportScreen extends StatefulWidget {
  final Category category;
  final DateTime startDate;
  final DateTime endDate;

  const CategoryDetailReportScreen({
    super.key,
    required this.category,
    required this.startDate,
    required this.endDate,
  });

  @override
  State<CategoryDetailReportScreen> createState() =>
      _CategoryDetailReportScreenState();
}

class _CategoryDetailReportScreenState extends State<CategoryDetailReportScreen>
    with SingleTickerProviderStateMixin {
  TimeFilter _selectedFilter = TimeFilter.thisMonth;
  late DateTime _startDate;
  late DateTime _endDate;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _startDate = widget.startDate;
    _endDate = widget.endDate;

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Load initial data and start animations
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategoryData();
      _animationController.forward();
    });
  }

  void _loadCategoryData() {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );
    transactionProvider.setDateFilter(_startDate, _endDate);
    transactionProvider.setCategoryFilter(widget.category.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Consumer<TransactionProvider>(
        builder: (context, transactionProvider, child) {
          if (transactionProvider.isLoading) {
            return _buildLoadingState();
          }

          final categoryTransactions = transactionProvider.transactions
              .where((t) => t.categoryId == widget.category.id)
              .toList();

          if (categoryTransactions.isEmpty) {
            return _buildEmptyState();
          }

          return _buildContent(categoryTransactions);
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: Consumer<ConnectionStatusProvider>(
        builder: (context, connectionStatus, child) {
          return TimeFilterAppBar(
            title: 'Chi tiết ${widget.category.name}',
            selectedFilter: _selectedFilter,
            startDate: _startDate,
            endDate: _endDate,
            onFilterChanged: (filter, start, end) {
              setState(() {
                _selectedFilter = filter;
                _startDate = start;
                _endDate = end;
              });
              _loadCategoryData();
            },
            syncStatus: connectionStatus.isOnline
                ? SyncStatusInfo.online(
                    lastSyncTime: connectionStatus.lastSyncTime,
                  )
                : SyncStatusInfo.offline(
                    pendingCount: connectionStatus.pendingItems,
                  ),
            onSyncPressed: () {
              Provider.of<TransactionProvider>(
                context,
                listen: false,
              ).loadTransactions(forceRefresh: true);
            },
            additionalActions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: _showCategoryInfo,
                tooltip: 'Thông tin danh mục',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Đang tải dữ liệu...', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _getCategoryColor().withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getCategoryIcon(),
                size: 64,
                color: _getCategoryColor().withOpacity(0.6),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Không có giao dịch nào',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'cho "${widget.category.name}" trong khoảng thời gian này',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                // Navigate to add transaction with this category pre-selected
                Navigator.pop(context);
              },
              icon: const Icon(Icons.add),
              label: const Text('Thêm giao dịch'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _getCategoryColor(),
                side: BorderSide(color: _getCategoryColor()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(List<TransactionModel> transactions) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
    final totalAmount = transactions.fold(0.0, (sum, t) => sum + t.amount);

    return RefreshIndicator(
      onRefresh: () async {
        _loadCategoryData();
        await Future.delayed(const Duration(milliseconds: 500));
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            //  Header Card
            _buildHeaderCard(
              totalAmount,
              transactions.length,
              currencyFormatter,
            ),
            const SizedBox(height: 16),

            // Analytics Cards Row
            _buildAnalyticsCards(transactions, currencyFormatter),
            const SizedBox(height: 16),

            // Trend Chart
            _buildTrendChart(transactions),
            const SizedBox(height: 16),

            // Time Distribution Chart
            _buildTimeDistributionChart(transactions),
            const SizedBox(height: 16),

            // Transactions List with Daily Groups
            _buildTransactionsList(transactions),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    double totalAmount,
    int transactionCount,
    NumberFormat formatter,
  ) {
    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, -0.5), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            ),
          ),
      child: FadeTransition(
        opacity: _animationController,
        child: Card(
          elevation: 4,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  _getCategoryColor().withOpacity(0.1),
                  _getCategoryColor().withOpacity(0.05),
                ],
              ),
            ),
            child: Column(
              children: [
                // Category Icon and Name
                Row(
                  children: [
                    Hero(
                      tag: 'category_${widget.category.id}',
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _getCategoryColor().withOpacity(0.2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          _getCategoryIcon(),
                          color: _getCategoryColor(),
                          size: 32,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.category.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            _getCategoryTypeLabel(),
                            style: TextStyle(
                              color: _getCategoryColor(),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildOwnershipBadge(),
                  ],
                ),

                const SizedBox(height: 20),

                // Amount and Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatItem(
                        'Tổng số tiền',
                        formatter.format(totalAmount),
                        _getCategoryColor(),
                        Icons.payments,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatItem(
                        'Số giao dịch',
                        '$transactionCount',
                        Colors.blue,
                        Icons.receipt_long,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalyticsCards(
    List<TransactionModel> transactions,
    NumberFormat formatter,
  ) {
    final averageAmount = transactions.isNotEmpty
        ? transactions.fold(0.0, (sum, t) => sum + t.amount) /
              transactions.length
        : 0.0;

    final maxTransaction = transactions.isNotEmpty
        ? transactions.reduce((a, b) => a.amount > b.amount ? a : b)
        : null;

    final minTransaction = transactions.isNotEmpty
        ? transactions.reduce((a, b) => a.amount < b.amount ? a : b)
        : null;

    return ScaleTransition(
      scale: Tween<double>(begin: 0.8, end: 1.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildAnalyticsCard(
              'Trung bình',
              formatter.format(averageAmount),
              Icons.analytics,
              Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildAnalyticsCard(
              'Cao nhất',
              maxTransaction != null
                  ? formatter.format(maxTransaction.amount)
                  : '0₫',
              Icons.trending_up,
              Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildAnalyticsCard(
              'Thấp nhất',
              minTransaction != null
                  ? formatter.format(minTransaction.amount)
                  : '0₫',
              Icons.trending_down,
              Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart(List<TransactionModel> transactions) {
    if (transactions.length < 2) {
      return _buildChartPlaceholder('Cần thêm dữ liệu để vẽ biểu đồ xu hướng');
    }

    // Group by date and calculate daily totals
    final dailyTotals =
        groupBy(
          transactions,
          (TransactionModel t) =>
              DateTime(t.date.year, t.date.month, t.date.day),
        ).map(
          (date, transList) =>
              MapEntry(date, transList.fold(0.0, (sum, t) => sum + t.amount)),
        );

    final sortedEntries = dailyTotals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final spots = sortedEntries
        .map(
          (entry) =>
              FlSpot(entry.key.millisecondsSinceEpoch.toDouble(), entry.value),
        )
        .toList();

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            ),
          ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.show_chart, color: _getCategoryColor(), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Xu hướng theo thời gian',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: LineChart(
                  ChartUtils.createSafeLineChartData(
                    spots: spots,
                    lineColor: _getCategoryColor(),
                    showDots: true,
                    showGrid: true,
                    showTitles: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeDistributionChart(List<TransactionModel> transactions) {
    // Group by hour of day
    final hourlyDistribution = <int, double>{};
    for (final transaction in transactions) {
      final hour = transaction.date.hour;
      hourlyDistribution[hour] =
          (hourlyDistribution[hour] ?? 0) + transaction.amount;
    }

    if (hourlyDistribution.isEmpty) {
      return _buildChartPlaceholder('Không có dữ liệu phân bố thời gian');
    }

    final barGroups = hourlyDistribution.entries.map((entry) {
      return BarChartGroupData(
        x: entry.key,
        barRods: [
          BarChartRodData(
            toY: entry.value,
            color: _getCategoryColor().withOpacity(0.8),
            width: 16,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    }).toList();

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(-1, 0), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            ),
          ),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.access_time, color: _getCategoryColor(), size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'Phân bố theo giờ trong ngày',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    barGroups: barGroups,
                    borderData: FlBorderData(show: false),
                    gridData: const FlGridData(show: false),
                    titlesData: FlTitlesData(
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (value, meta) {
                            if (value.toInt() % 6 == 0) {
                              return Text(
                                '${value.toInt()}h',
                                style: const TextStyle(fontSize: 10),
                              );
                            }
                            return const Text('');
                          },
                        ),
                      ),
                      leftTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                      rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartPlaceholder(String message) {
    return Card(
      child: Container(
        height: 200,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList(List<TransactionModel> transactions) {
    final groupedTransactions = groupTransactionsByDate(transactions);
    final sortedDates = groupedTransactions.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // Most recent first

    return SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
          .animate(
            CurvedAnimation(
              parent: _animationController,
              curve: Curves.easeOut,
            ),
          ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Icon(Icons.list_alt, color: _getCategoryColor(), size: 20),
                const SizedBox(width: 8),
                Text(
                  'Chi tiết giao dịch (${transactions.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          TransactionsByDateWidget(
            transactionsByDate: groupedTransactions,
            showAnimations: true,
            maxDaysToShow: 30,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
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
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildOwnershipBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: widget.category.isShared
            ? Colors.orange.withOpacity(0.1)
            : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.category.isShared
              ? Colors.orange.withOpacity(0.3)
              : Colors.blue.withOpacity(0.3),
        ),
      ),
      child: Text(
        widget.category.isShared ? 'CHUNG' : 'CÁ NHÂN',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: widget.category.isShared
              ? Colors.orange.shade700
              : Colors.blue.shade700,
        ),
      ),
    );
  }

  Color _getCategoryColor() {
    return widget.category.type == 'income'
        ? Colors.green.shade600
        : Colors.red.shade600;
  }

  IconData _getCategoryIcon() {
    if (widget.category.iconCodePoint != null) {
      return IconData(
        widget.category.iconCodePoint!,
        fontFamily: 'MaterialIcons',
      );
    }
    return widget.category.type == 'income'
        ? Icons.trending_up
        : Icons.trending_down;
  }

  String _getCategoryTypeLabel() {
    return widget.category.type == 'income'
        ? 'Danh mục thu nhập'
        : 'Danh mục chi tiêu';
  }

  void _showCategoryInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getCategoryColor().withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getCategoryIcon(),
                          color: _getCategoryColor(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thông tin danh mục',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              widget.category.name,
                              style: TextStyle(color: _getCategoryColor()),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Info rows
                  _buildInfoRow('Loại', _getCategoryTypeLabel()),
                  _buildInfoRow(
                    'Quyền sở hữu',
                    widget.category.isShared ? 'Chung' : 'Cá nhân',
                  ),
                  _buildInfoRow(
                    'Số lần sử dụng',
                    '${widget.category.usageCount}',
                  ),
                  if (widget.category.lastUsed != null)
                    _buildInfoRow(
                      'Sử dụng gần nhất',
                      DateFormat(
                        'dd/MM/yyyy HH:mm',
                      ).format(widget.category.lastUsed!),
                    ),
                  if (widget.category.subCategories.isNotEmpty)
                    _buildInfoRow(
                      'Danh mục con',
                      '${widget.category.subCategories.length}',
                    ),

                  const SizedBox(height: 24),

                  // Close button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getCategoryColor(),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Đóng'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
