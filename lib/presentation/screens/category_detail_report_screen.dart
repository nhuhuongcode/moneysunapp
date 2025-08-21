import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:moneysun/utils/chart_utils.dart';

class CategoryDetailReportScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;
  final DateTime initialStartDate;
  final DateTime initialEndDate;

  const CategoryDetailReportScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
    required this.initialStartDate,
    required this.initialEndDate,
  });

  @override
  State<CategoryDetailReportScreen> createState() =>
      _CategoryDetailReportScreenState();
}

class _CategoryDetailReportScreenState
    extends State<CategoryDetailReportScreen> {
  // FIX: Use TimeFilter from TimeFilterAppBar widget
  TimeFilter _selectedFilter = TimeFilter.thisMonth;
  late DateTime _startDate;
  late DateTime _endDate;
  final DatabaseService _databaseService = DatabaseService();

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return Scaffold(
      appBar: TimeFilterAppBar(
        title: 'Chi tiết ${widget.categoryName}',
        selectedFilter: _selectedFilter,
        startDate: _startDate,
        endDate: _endDate,
        onFilterChanged: (filter, start, end) {
          setState(() {
            _selectedFilter = filter;
            _startDate = start;
            _endDate = end;
          });
        },
      ),
      body: StreamBuilder<List<TransactionModel>>(
        stream: _databaseService.getTransactionsForCategoryStream(
          userProvider: userProvider,
          categoryId: widget.categoryId,
          startDate: _startDate,
          endDate: _endDate,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Không có giao dịch nào',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'cho "${widget.categoryName}" trong khoảng thời gian này',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            );
          }

          final transactions = snapshot.data!;
          final totalAmount = transactions.fold(
            0.0,
            (sum, item) => sum + item.amount,
          );
          final currencyFormatter = NumberFormat.currency(
            locale: 'vi_VN',
            symbol: '₫',
          );

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {}); // Trigger rebuild
            },
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  // Header Card with total
                  _buildHeaderCard(totalAmount, currencyFormatter),
                  const SizedBox(height: 16),

                  // Line Chart
                  _buildLineChart(transactions),
                  const SizedBox(height: 16),

                  // FIX: Use DailyTransactionsGroup template instead of simple list
                  _buildTransactionsList(transactions),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // FIX: Enhanced header card
  Widget _buildHeaderCard(double totalAmount, NumberFormat formatter) {
    return Card(
      elevation: 2,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${widget.categoryName}',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              formatter.format(totalAmount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // FIX: Use DailyTransactionsGroup template
  Widget _buildTransactionsList(List<TransactionModel> transactions) {
    // Group transactions by date
    final groupedTransactions = groupBy(
      transactions,
      (TransactionModel t) => DateTime(t.date.year, t.date.month, t.date.day),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Row(
            children: [
              Icon(Icons.list_alt, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'Chi tiết giao dịch',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),

        // FIX: Use DailyTransactionsGroup for consistent UI
        ...groupedTransactions.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8.0),
            child: DailyTransactionsGroup(
              date: entry.key,
              transactions: entry.value,
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildLineChart(List<TransactionModel> transactions) {
    if (transactions.length < 2) {
      return Card(
        child: Container(
          height: 200,
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.show_chart, size: 48, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                "Cần thêm dữ liệu để vẽ biểu đồ xu hướng",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Group by date and calculate daily totals
    final dailyTotals =
        groupBy(
              transactions,
              (TransactionModel t) =>
                  DateTime(t.date.year, t.date.month, t.date.day),
            )
            .map(
              (date, transList) => MapEntry(
                date,
                transList.fold(0.0, (sum, item) => sum + item.amount),
              ),
            )
            .entries
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    final List<FlSpot> spots = dailyTotals.map((entry) {
      return FlSpot(entry.key.millisecondsSinceEpoch.toDouble(), entry.value);
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'Xu hướng chi tiêu theo ngày',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                // FIX: Use safe chart data from ChartUtils
                ChartUtils.createSafeLineChartData(
                  spots: spots,
                  lineColor: Theme.of(context).primaryColor,
                  showDots: true,
                  showGrid: true,
                  showTitles: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
