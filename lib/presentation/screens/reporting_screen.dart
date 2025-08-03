import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';

// Enum để quản lý filter time
enum TimeFilter { week, month, year, custom }

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  TimeFilter _selectedTimeFilter = TimeFilter.month;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _updateDateRange();
  }

  void _updateDateRange() {
    final now = DateTime.now();
    switch (_selectedTimeFilter) {
      case TimeFilter.week:
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _endDate = _startDate.add(const Duration(days: 6));
        break;
      case TimeFilter.month:
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = DateTime(now.year, now.month + 1, 0);
        break;
      case TimeFilter.year:
        _startDate = DateTime(now.year, 1, 1);
        _endDate = DateTime(now.year, 12, 31);
        break;
      case TimeFilter.custom:
        // Giữ nguyên startDate và endDate hiện tại
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Thu nhập', icon: Icon(Icons.trending_up)),
            Tab(text: 'Chi tiêu', icon: Icon(Icons.trending_down)),
          ],
        ),
        actions: [
          PopupMenuButton<TimeFilter>(
            icon: const Icon(Icons.filter_list),
            onSelected: (filter) {
              setState(() {
                _selectedTimeFilter = filter;
                if (filter != TimeFilter.custom) {
                  _updateDateRange();
                }
              });
              if (filter == TimeFilter.custom) {
                _showCustomDatePicker();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: TimeFilter.week,
                child: Text('Tuần này'),
              ),
              const PopupMenuItem(
                value: TimeFilter.month,
                child: Text('Tháng này'),
              ),
              const PopupMenuItem(
                value: TimeFilter.year,
                child: Text('Năm này'),
              ),
              const PopupMenuItem(
                value: TimeFilter.custom,
                child: Text('Tùy chọn...'),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          IncomeReportPage(startDate: _startDate, endDate: _endDate),
          ExpenseReportPage(startDate: _startDate, endDate: _endDate),
        ],
      ),
    );
  }

  void _showCustomDatePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

// FIX: Trang báo cáo thu nhập riêng biệt
class IncomeReportPage extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;

  const IncomeReportPage({
    super.key,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final databaseService = DatabaseService();
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return FutureBuilder<ReportData>(
      future: databaseService.getReportData(userProvider, startDate, endDate),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.incomeByCategory.isEmpty) {
          return const Center(
            child: Text('Không có dữ liệu thu nhập trong khoảng thời gian này'),
          );
        }

        final report = snapshot.data!;
        final incomeCategories = report.incomeByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)); // Sắp xếp giảm dần

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Header với tổng thu nhập
              _buildHeaderCard(
                'Thu nhập',
                report.totalIncome,
                Colors.green,
                currencyFormatter,
              ),
              const SizedBox(height: 16),

              // FIX: Pie Chart với legend
              _buildIncomeChart(incomeCategories),
              const SizedBox(height: 16),

              // FIX: Danh sách categories có thể click
              _buildCategoryList(
                incomeCategories,
                currencyFormatter,
                report.totalIncome,
                context,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderCard(
    String title,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tổng $title',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              formatter.format(amount),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeChart(List<MapEntry<Category, double>> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();

    // Tạo data cho chart
    final chartData = categories.take(8).map((entry) {
      // Chỉ lấy 8 categories đầu
      final category = entry.key;
      final amount = entry.value;
      return PieChartSectionData(
        value: amount,
        title: '', // Không hiển thị title trên chart
        color: _getCategoryColor(categories.indexOf(entry)),
        radius: 60,
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Phân bố thu nhập theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: chartData,
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // FIX: Legend hiển thị trên chart
            _buildChartLegend(categories.take(8).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLegend(List<MapEntry<Category, double>> categories) {
    return Wrap(
      children: categories.map((entry) {
        final index = categories.indexOf(entry);
        final color = _getCategoryColor(index);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text(entry.key.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryList(
    List<MapEntry<Category, double>> categories,
    NumberFormat formatter,
    double totalAmount,
    BuildContext context,
  ) {
    return Card(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Chi tiết theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ...categories.map((entry) {
            final category = entry.key;
            final amount = entry.value;
            final percentage = (amount / totalAmount * 100);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _getCategoryColor(
                  categories.indexOf(entry),
                ).withOpacity(0.2),
                child: Icon(
                  Icons.trending_up,
                  color: _getCategoryColor(categories.indexOf(entry)),
                ),
              ),
              title: Text(category.name),
              subtitle: Text('${percentage.toStringAsFixed(1)}%'),
              trailing: Text(
                formatter.format(amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              onTap: () {
                // FIX: Navigate to category detail
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryDetailScreen(
                      category: category,
                      startDate: startDate,
                      endDate: endDate,
                      isIncome: true,
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ],
      ),
    );
  }

  Color _getCategoryColor(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
    ];
    return colors[index % colors.length];
  }
}

// FIX: Trang báo cáo chi tiêu riêng biệt (tương tự IncomeReportPage)
class ExpenseReportPage extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;

  const ExpenseReportPage({
    super.key,
    required this.startDate,
    required this.endDate,
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final databaseService = DatabaseService();
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return FutureBuilder<ReportData>(
      future: databaseService.getReportData(userProvider, startDate, endDate),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.expenseByCategory.isEmpty) {
          return const Center(
            child: Text('Không có dữ liệu chi tiêu trong khoảng thời gian này'),
          );
        }

        final report = snapshot.data!;
        final expenseCategories = report.expenseByCategory.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildHeaderCard(
                'Chi tiêu',
                report.totalExpense,
                Colors.red,
                currencyFormatter,
              ),
              const SizedBox(height: 16),
              _buildExpenseChart(expenseCategories),
              const SizedBox(height: 16),
              _buildCategoryList(
                expenseCategories,
                currencyFormatter,
                report.totalExpense,
                context,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderCard(
    String title,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tổng $title',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              formatter.format(amount),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseChart(List<MapEntry<Category, double>> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();

    final chartData = categories.take(8).map((entry) {
      final amount = entry.value;
      return PieChartSectionData(
        value: amount,
        title: '',
        color: _getCategoryColor(categories.indexOf(entry)),
        radius: 60,
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Phân bố chi tiêu theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: chartData,
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildChartLegend(categories.take(8).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildChartLegend(List<MapEntry<Category, double>> categories) {
    return Wrap(
      children: categories.map((entry) {
        final index = categories.indexOf(entry);
        final color = _getCategoryColor(index);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text(entry.key.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCategoryList(
    List<MapEntry<Category, double>> categories,
    NumberFormat formatter,
    double totalAmount,
    BuildContext context,
  ) {
    return Card(
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Chi tiết theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ...categories.map((entry) {
            final category = entry.key;
            final amount = entry.value;
            final percentage = (amount / totalAmount * 100);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _getCategoryColor(
                  categories.indexOf(entry),
                ).withOpacity(0.2),
                child: Icon(
                  Icons.trending_down,
                  color: _getCategoryColor(categories.indexOf(entry)),
                ),
              ),
              title: Text(category.name),
              subtitle: Text('${percentage.toStringAsFixed(1)}%'),
              trailing: Text(
                formatter.format(amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryDetailScreen(
                      category: category,
                      startDate: startDate,
                      endDate: endDate,
                      isIncome: false,
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ],
      ),
    );
  }

  Color _getCategoryColor(int index) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
    ];
    return colors[index % colors.length];
  }
}

// FIX: Category Detail Screen
class CategoryDetailScreen extends StatelessWidget {
  final Category category;
  final DateTime startDate;
  final DateTime endDate;
  final bool isIncome;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    required this.startDate,
    required this.endDate,
    required this.isIncome,
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final databaseService = DatabaseService();
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      appBar: AppBar(title: Text('Chi tiết: ${category.name}')),
      body: StreamBuilder(
        stream: databaseService.getTransactionsForCategoryStream(
          userProvider: userProvider,
          categoryId: category.id,
          startDate: startDate,
          endDate: endDate,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Không có giao dịch nào trong khoảng thời gian này'),
            );
          }

          final transactions = snapshot.data!;
          final totalAmount = transactions.fold(
            0.0,
            (sum, t) => sum + t.amount,
          );

          return Column(
            children: [
              // Header
              Card(
                margin: const EdgeInsets.all(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'Tổng ${isIncome ? "thu nhập" : "chi tiêu"}',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        currencyFormatter.format(totalAmount),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${transactions.length} giao dịch',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              // Transaction list
              Expanded(
                child: ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = transactions[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (isIncome ? Colors.green : Colors.red)
                            .withOpacity(0.1),
                        child: Icon(
                          isIncome ? Icons.trending_up : Icons.trending_down,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                      title: Text(
                        transaction.description.isNotEmpty
                            ? transaction.description
                            : category.name,
                      ),
                      subtitle: Text(
                        '${DateFormat('dd/MM/yyyy').format(transaction.date)} • ${transaction.walletName}',
                      ),
                      trailing: Text(
                        currencyFormatter.format(transaction.amount),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isIncome ? Colors.green : Colors.red,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
