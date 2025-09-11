// lib/presentation/screens/_reporting_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/presentation/screens/category_detail_report_screen.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  TimeFilter _selectedTimeFilter = TimeFilter.thisMonth;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReportData();
    });
  }

  void _loadReportData() {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );
    transactionProvider.setDateFilter(_startDate, _endDate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ExpenseReportTab(
            startDate: _startDate,
            endDate: _endDate,
            onRefresh: _loadReportData,
          ),
          _IncomeReportTab(
            startDate: _startDate,
            endDate: _endDate,
            onRefresh: _loadReportData,
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight * 2),
      child: Consumer<ConnectionStatusProvider>(
        builder: (context, connectionStatus, child) {
          return TimeFilterAppBarWithTabs(
            title: 'Báo cáo',
            selectedFilter: _selectedTimeFilter,
            startDate: _startDate,
            endDate: _endDate,
            onFilterChanged: (filter, start, end) {
              setState(() {
                _selectedTimeFilter = filter;
                _startDate = start;
                _endDate = end;
              });
              _loadReportData();
            },
            tabController: _tabController,
            tabs: const [
              Tab(text: 'Chi tiêu'),
              Tab(text: 'Thu nhập'),
            ],
            //  with sync status
            syncStatus: connectionStatus.isOnline
                ? SyncStatusInfo.online(
                    lastSyncTime: connectionStatus.lastSyncTime,
                  )
                : SyncStatusInfo.offline(
                    pendingCount: connectionStatus.pendingItems,
                  ),
            onSyncPressed: () {
              // Trigger manual sync
              Provider.of<TransactionProvider>(
                context,
                listen: false,
              ).loadTransactions(forceRefresh: true);
              Provider.of<CategoryProvider>(
                context,
                listen: false,
              ).loadCategories(forceRefresh: true);
            },
            onSyncStatusTap: () {
              _showSyncStatusDialog();
            },
          );
        },
      ),
    );
  }

  void _showSyncStatusDialog() {
    final connectionStatus = Provider.of<ConnectionStatusProvider>(
      context,
      listen: false,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              connectionStatus.isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: connectionStatus.isOnline ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(
              connectionStatus.isOnline
                  ? 'Trạng thái Online'
                  : 'Trạng thái Offline',
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusRow(
              'Kết nối',
              connectionStatus.isOnline ? 'Online' : 'Offline',
            ),
            if (!connectionStatus.isOnline && connectionStatus.pendingItems > 0)
              _buildStatusRow(
                'Chờ đồng bộ',
                '${connectionStatus.pendingItems} mục',
              ),
            if (connectionStatus.lastSyncTime != null)
              _buildStatusRow(
                'Lần sync cuối',
                DateFormat(
                  'dd/MM HH:mm',
                ).format(connectionStatus.lastSyncTime!),
              ),
            if (connectionStatus.lastError != null)
              _buildStatusRow(
                'Lỗi',
                connectionStatus.lastError!,
                isError: true,
              ),
          ],
        ),
        actions: [
          if (!connectionStatus.isOnline)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _loadReportData();
              },
              child: const Text('Thử lại'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, {bool isError = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: TextStyle(
              color: isError ? Colors.red : null,
              fontWeight: isError ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

// ============ EXPENSE REPORT TAB ============
class _ExpenseReportTab extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback onRefresh;

  const _ExpenseReportTab({
    required this.startDate,
    required this.endDate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<TransactionProvider, CategoryProvider>(
      builder: (context, transactionProvider, categoryProvider, child) {
        if (transactionProvider.isLoading || categoryProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final transactions = transactionProvider.transactions
            .where((t) => t.type == TransactionType.expense)
            .toList();

        if (transactions.isEmpty) {
          return _buildEmptyState('chi tiêu');
        }

        final reportData = _calculateExpenseReportData(
          transactions,
          categoryProvider.categories,
        );

        return RefreshIndicator(
          onRefresh: () async {
            onRefresh();
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _buildHeaderCard(
                  'Chi tiêu',
                  reportData.totalExpense,
                  Colors.red,
                ),
                const SizedBox(height: 16),
                if (reportData.expenseByCategory.isNotEmpty) ...[
                  _buildExpenseChart(reportData.expenseByCategory),
                  const SizedBox(height: 16),
                  _buildCategoryList(
                    reportData.expenseByCategory,
                    reportData.totalExpense,
                    context,
                    'expense',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String type) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              type == 'chi tiêu' ? Icons.trending_down : Icons.trending_up,
              size: 80,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Không có dữ liệu $type',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(
              'trong khoảng thời gian này',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(String title, double amount, Color color) {
    final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

    return Card(
      elevation: 2,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                title == 'Chi tiêu' ? Icons.trending_down : Icons.trending_up,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tổng $title',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatter.format(amount),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color,
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

  Widget _buildExpenseChart(Map<Category, double> expenseByCategory) {
    final sortedEntries = expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final chartData = sortedEntries.take(8).map((entry) {
      final index = sortedEntries.indexOf(entry);
      return PieChartSectionData(
        value: entry.value,
        title: '',
        color: _getCategoryColor(index, isExpense: true),
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              'Phân bố chi tiêu theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: chartData,
                  sectionsSpace: 3,
                  centerSpaceRadius: 50,
                  borderData: FlBorderData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildChartLegend(sortedEntries.take(8).toList(), isExpense: true),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLegend(
    List<MapEntry<Category, double>> categories, {
    required bool isExpense,
  }) {
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: categories.asMap().entries.map((entry) {
        final index = entry.key;
        final categoryEntry = entry.value;
        final color = _getCategoryColor(index, isExpense: isExpense);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                categoryEntry.key.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildCategoryList(
    Map<Category, double> categoryMap,
    double totalAmount,
    BuildContext context,
    String type,
  ) {
    final sortedEntries = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Chi tiết theo danh mục',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedEntries.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = sortedEntries[index];
              final category = entry.key;
              final amount = entry.value;
              final percentage = (amount / totalAmount * 100);
              final color = _getCategoryColor(
                index,
                isExpense: type == 'expense',
              );

              return ListTile(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CategoryDetailReportScreen(
                        category: category,
                        startDate: startDate,
                        endDate: endDate,
                      ),
                    ),
                  );
                },
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    category.iconCodePoint != null
                        ? IconData(
                            category.iconCodePoint!,
                            fontFamily: 'MaterialIcons',
                          )
                        : (type == 'expense'
                              ? Icons.trending_down
                              : Icons.trending_up),
                    color: color,
                    size: 20,
                  ),
                ),
                title: Text(
                  category.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${percentage.toStringAsFixed(1)}% của tổng $type',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatter.format(amount),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      child: Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade400,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(int index, {required bool isExpense}) {
    final expenseColors = [
      Colors.red.shade600,
      Colors.orange.shade600,
      Colors.pink.shade600,
      Colors.purple.shade600,
      Colors.deepPurple.shade600,
      Colors.indigo.shade600,
      Colors.blue.shade600,
      Colors.brown.shade600,
    ];

    final incomeColors = [
      Colors.green.shade600,
      Colors.teal.shade600,
      Colors.cyan.shade600,
      Colors.lightGreen.shade600,
      Colors.lime.shade600,
      Colors.amber.shade600,
      Colors.yellow.shade600,
      Colors.orange.shade600,
    ];

    final colors = isExpense ? expenseColors : incomeColors;
    return colors[index % colors.length];
  }

  // Calculate report data from transactions and categories
  _ReportData _calculateExpenseReportData(
    List<TransactionModel> transactions,
    List<Category> categories,
  ) {
    final expenseByCategory = <Category, double>{};
    double totalExpense = 0;

    for (final transaction in transactions) {
      totalExpense += transaction.amount;

      if (transaction.categoryId != null) {
        final category = categories.firstWhereOrNull(
          (c) => c.id == transaction.categoryId,
        );
        if (category != null) {
          expenseByCategory[category] =
              (expenseByCategory[category] ?? 0) + transaction.amount;
        }
      }
    }

    return _ReportData(
      totalExpense: totalExpense,
      expenseByCategory: expenseByCategory,
      incomeByCategory: {},
      totalIncome: 0,
    );
  }
}

// ============ INCOME REPORT TAB ============
class _IncomeReportTab extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback onRefresh;

  const _IncomeReportTab({
    required this.startDate,
    required this.endDate,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<TransactionProvider, CategoryProvider>(
      builder: (context, transactionProvider, categoryProvider, child) {
        if (transactionProvider.isLoading || categoryProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final transactions = transactionProvider.transactions
            .where((t) => t.type == TransactionType.income)
            .toList();

        if (transactions.isEmpty) {
          return const _ExpenseReportTab(
            startDate: DateTime.now(),
            endDate: DateTime.now(),
            onRefresh: _dummyRefresh,
          )._buildEmptyState('thu nhập');
        }

        final reportData = _calculateIncomeReportData(
          transactions,
          categoryProvider.categories,
        );

        return RefreshIndicator(
          onRefresh: () async {
            onRefresh();
            await Future.delayed(const Duration(milliseconds: 500));
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _ExpenseReportTab(
                  startDate: DateTime.now(),
                  endDate: DateTime.now(),
                  onRefresh: _dummyRefresh,
                )._buildHeaderCard(
                  'Thu nhập',
                  reportData.totalIncome,
                  Colors.green,
                ),
                const SizedBox(height: 16),
                if (reportData.incomeByCategory.isNotEmpty) ...[
                  _buildIncomeChart(reportData.incomeByCategory),
                  const SizedBox(height: 16),
                  _ExpenseReportTab(
                    startDate: DateTime.now(),
                    endDate: DateTime.now(),
                    onRefresh: _dummyRefresh,
                  )._buildCategoryList(
                    reportData.incomeByCategory,
                    reportData.totalIncome,
                    context,
                    'income',
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  static void _dummyRefresh() {}

  Widget _buildIncomeChart(Map<Category, double> incomeByCategory) {
    // Similar to expense chart but with different colors
    return _ExpenseReportTab(
      startDate: DateTime.now(),
      endDate: DateTime.now(),
      onRefresh: _dummyRefresh,
    )._buildExpenseChart(incomeByCategory);
  }

  _ReportData _calculateIncomeReportData(
    List<TransactionModel> transactions,
    List<Category> categories,
  ) {
    final incomeByCategory = <Category, double>{};
    double totalIncome = 0;

    for (final transaction in transactions) {
      totalIncome += transaction.amount;

      if (transaction.categoryId != null) {
        final category = categories.firstWhereOrNull(
          (c) => c.id == transaction.categoryId,
        );
        if (category != null) {
          incomeByCategory[category] =
              (incomeByCategory[category] ?? 0) + transaction.amount;
        }
      }
    }

    return _ReportData(
      totalIncome: totalIncome,
      incomeByCategory: incomeByCategory,
      expenseByCategory: {},
      totalExpense: 0,
    );
  }
}

// ============ HELPER CLASSES ============
class _ReportData {
  final double totalIncome;
  final double totalExpense;
  final Map<Category, double> expenseByCategory;
  final Map<Category, double> incomeByCategory;

  const _ReportData({
    required this.totalIncome,
    required this.totalExpense,
    required this.expenseByCategory,
    required this.incomeByCategory,
  });
}
