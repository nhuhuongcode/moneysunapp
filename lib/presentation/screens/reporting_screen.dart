import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/presentation/screens/category_detail_report_screen.dart';
import 'package:moneysun/presentation/screens/category_detail_screen.dart';
import 'package:provider/provider.dart';

enum TimeRangeFilter { thisWeek, thisMonth, custom }

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  late DateTime _startDate;
  late DateTime _endDate;
  late TabController _tabController;
  Future<ReportData>? _reportDataFuture;
  TimeRangeFilter _selectedFilter = TimeRangeFilter.thisMonth;

  final List<Color> _chartColors = const [
    Color(0xFFFFB6C1),
    Color(0xFF87CEEB),
    Color(0xFF98FB98),
    Color(0xFFFFD700),
    Color(0xFFE6E6FA),
    Color(0xFFFFA07A),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _updateDateRange(TimeRangeFilter.thisMonth);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Gọi fetch data khi dependencies thay đổi (lần đầu build)
    if (_reportDataFuture == null) {
      _fetchReportData();
    }
  }

  void _fetchReportData() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    setState(() {
      _reportDataFuture = _databaseService.getReportData(
        userProvider,
        _startDate,
        _endDate,
      );
    });
  }

  void _updateDateRange(TimeRangeFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case TimeRangeFilter.thisWeek:
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _endDate = _startDate.add(const Duration(days: 6));
        break;
      case TimeRangeFilter.thisMonth:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case TimeRangeFilter.custom:
        // Sẽ được xử lý bởi showDateRangePicker
        break;
    }
    setState(() {
      _selectedFilter = filter;
    });
    _fetchReportData();
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _selectedFilter = TimeRangeFilter.custom;
      });
      _fetchReportData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo tài chính'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.arrow_circle_up), text: 'CHI TIÊU'),
            Tab(icon: Icon(Icons.arrow_circle_down), text: 'THU NHẬP'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          Expanded(
            child: FutureBuilder<ReportData>(
              future: _reportDataFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData ||
                    (snapshot.data!.totalExpense == 0 &&
                        snapshot.data!.totalIncome == 0)) {
                  return const Center(child: Text('Không có dữ liệu.'));
                }
                final report = snapshot.data!;
                // Truyền dữ liệu vào TabBarView
                return TabBarView(
                  controller: _tabController,
                  children: [
                    // Trang Báo cáo Chi
                    _buildReportPage(
                      context: context,
                      totalAmount: report.totalExpense,
                      categoryData: report.expenseByCategory,
                      reportType: 'expense',
                    ),
                    // Trang Báo cáo Thu
                    _buildReportPage(
                      context: context,
                      totalAmount: report.totalIncome,
                      categoryData: report.incomeByCategory,
                      reportType: 'income',
                    ),
                  ],
                );
                // if (snapshot.hasError) {
                //   return Center(
                //     child: Text('Lỗi tải dữ liệu: ${snapshot.error}'),
                //   );
                // }
                // if (!snapshot.hasData ||
                //     (snapshot.data!.totalExpense == 0 &&
                //         snapshot.data!.totalIncome == 0)) {
                //   return const Center(
                //     child: Text('Không có dữ liệu trong khoảng thời gian này.'),
                //   );
                // }
                // final report = snapshot.data!;
                // return _buildReportBody(report);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Wrap(
        spacing: 8.0,
        children: [
          FilterChip(
            label: const Text('Tháng này'),
            selected: _selectedFilter == TimeRangeFilter.thisMonth,
            onSelected: (_) => _updateDateRange(TimeRangeFilter.thisMonth),
          ),
          FilterChip(
            label: const Text('Tuần này'),
            selected: _selectedFilter == TimeRangeFilter.thisWeek,
            onSelected: (_) => _updateDateRange(TimeRangeFilter.thisWeek),
          ),
          FilterChip(
            label: const Text('Tùy chọn'),
            selected: _selectedFilter == TimeRangeFilter.custom,
            onSelected: (_) => _selectCustomDateRange(),
          ),
        ],
      ),
    );
  }

  Widget _buildReportBody(ReportData report) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
    final totalExpense = report.totalExpense;
    final sortedCategories = report.expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Tổng thu',
                report.totalIncome,
                Colors.green,
                currencyFormatter,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Tổng chi',
                totalExpense,
                Colors.red,
                currencyFormatter,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Phân tích chi tiêu',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: totalExpense > 0
              ? PieChart(
                  PieChartData(
                    sections: List.generate(sortedCategories.length, (i) {
                      final entry = sortedCategories[i];
                      final percentage = (entry.value / totalExpense) * 100;
                      return PieChartSectionData(
                        color: _chartColors[i % _chartColors.length],
                        value: entry.value,
                        title: '${percentage.toStringAsFixed(0)}%',
                        radius: 80,
                        titleStyle: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                        ),
                      );
                    }),
                    sectionsSpace: 2,
                    centerSpaceRadius: 40,
                  ),
                )
              : const Center(child: Text('Không có chi tiêu nào')),
        ),
        const SizedBox(height: 24),
        ...List.generate(sortedCategories.length, (i) {
          final entry = sortedCategories[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: _chartColors[i % _chartColors.length],
                child: const SizedBox.shrink(),
              ),
              title: Text(entry.key.name),
              trailing: Text(currencyFormatter.format(entry.value)),
              onTap: () {
                // 1. Lấy ID của danh mục được nhấn
                final categoryId = entry.key.id;

                // 2. Lọc danh sách giao dịch thô để chỉ lấy các giao dịch thuộc danh mục này
                final filteredTransactions = report.rawTransactions
                    .where(
                      (transaction) => transaction.categoryId == categoryId,
                    )
                    .toList();

                // 3. Sắp xếp các giao dịch theo ngày mới nhất lên đầu
                filteredTransactions.sort((a, b) => b.date.compareTo(a.date));

                // 4. Điều hướng đến màn hình chi tiết và truyền dữ liệu qua
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryDetailScreen(
                      categoryName: entry.key.name,
                      transactions: filteredTransactions,
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
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
        ),
      ),
    );
  }

  Widget _buildReportPage({
    required BuildContext context,
    required double totalAmount,
    required Map<Category, double> categoryData,
    required String reportType, // 'expense' hoặc 'income'
  }) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
    final sortedCategories = categoryData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final color = reportType == 'expense' ? Colors.red : Colors.green;

    if (totalAmount == 0) {
      return Center(
        child: Text(
          'Không có dữ liệu ${reportType == 'expense' ? 'chi tiêu' : 'thu nhập'}.',
        ),
      );
    }
    int touchedIndex = -1;

    return StatefulBuilder(
      builder: (context, setChartState) {
        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Tổng tiền
            Text(
              'Tổng ${reportType == 'expense' ? 'Chi tiêu' : 'Thu nhập'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              currencyFormatter.format(totalAmount),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),

            // Biểu đồ tròn
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (FlTouchEvent event, pieTouchResponse) {
                      setChartState(() {
                        if (!event.isInterestedForInteractions ||
                            pieTouchResponse == null ||
                            pieTouchResponse.touchedSection == null) {
                          touchedIndex = -1;
                          return;
                        }
                        touchedIndex = pieTouchResponse
                            .touchedSection!
                            .touchedSectionIndex;
                      });
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: List.generate(sortedCategories.length, (i) {
                    final isTouched = i == touchedIndex;
                    final fontSize = isTouched ? 20.0 : 16.0;
                    final radius = isTouched ? 90.0 : 80.0;
                    final entry = sortedCategories[i];
                    final percentage = (entry.value / totalAmount) * 100;
                    return PieChartSectionData(
                      color: _chartColors[i % _chartColors.length],
                      value: entry.value,
                      title: '${percentage.toStringAsFixed(0)}%',
                      radius: 80,
                      titleStyle: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                      ),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Danh sách chi tiết
            ...List.generate(sortedCategories.length, (i) {
              final entry = sortedCategories[i];
              final percentage = (entry.value / totalAmount) * 100;
              return Card(
                child: ListTile(
                  // leading: CircleAvatar(
                  //   backgroundColor: _chartColors[i % _chartColors.length],
                  //   child: Text('${percentage.toStringAsFixed(0)}%'),
                  //   foregroundColor: Colors.white,
                  // ),
                  leading: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _chartColors[i % _chartColors.length],
                      shape: BoxShape.circle,
                    ),
                  ),
                  title: Text(entry.key.name),
                  subtitle: Text('${percentage.toStringAsFixed(1)}%'),
                  trailing: Text(
                    currencyFormatter.format(entry.value),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onTap: () {
                    // ĐIỀU HƯỚNG ĐẾN MÀN HÌNH CHI TIẾT NÂNG CAO
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CategoryDetailReportScreen(
                          categoryId: entry.key.id,
                          categoryName: entry.key.name,
                          initialStartDate:
                              _startDate, // Truyền khoảng thời gian đang xem
                          initialEndDate: _endDate,
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
