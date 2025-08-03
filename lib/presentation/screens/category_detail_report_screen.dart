import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/widgets/transaction_list_item.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart'; // Import package collection

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
  late DateTime _startDate;
  late DateTime _endDate;
  final DatabaseService _databaseService = DatabaseService();

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStartDate;
    _endDate = widget.initialEndDate;
  }

  // (Thêm các hàm _updateDateRange và _selectCustomDateRange nếu bạn muốn có bộ lọc ở đây)

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
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
              child: Text(
                'Không có giao dịch nào cho "${widget.categoryName}" trong khoảng thời gian này.',
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

          return Column(
            children: [
              // Thẻ Tổng tiền
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Tổng cộng trong kỳ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      currencyFormatter.format(totalAmount),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: Theme.of(context).primaryColorDark,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),

              // Line Chart
              _buildLineChart(transactions),

              const Divider(thickness: 1),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: Row(
                  children: [
                    Icon(Icons.list_alt, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'Chi tiết Giao dịch',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              // Danh sách giao dịch chi tiết
              Expanded(
                child: ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    return TransactionListItem(
                      transaction: transactions[index],
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

  // Widget để build Line Chart
  Widget _buildLineChart(List<TransactionModel> transactions) {
    if (transactions.length < 2) {
      // Cần ít nhất 2 điểm để vẽ một đường line
      return const SizedBox(
        height: 250,
        child: Center(child: Text("Cần thêm dữ liệu để vẽ biểu đồ xu hướng.")),
      );
    }

    // Nhóm giao dịch theo ngày và tính tổng cho mỗi ngày
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
          ..sort((a, b) => a.key.compareTo(b.key)); // Sắp xếp theo ngày

    final List<FlSpot> spots = dailyTotals.map((entry) {
      // Trục X là timestamp (số mili giây từ epoch), Trục Y là tổng tiền
      return FlSpot(entry.key.millisecondsSinceEpoch.toDouble(), entry.value);
    }).toList();

    return SizedBox(
      height: 250,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: LineChart(
          LineChartData(
            gridData: const FlGridData(show: false),
            titlesData: FlTitlesData(
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  interval:
                      (spots.last.x - spots.first.x) /
                      4, // Chia khoảng cách để có khoảng 4-5 nhãn
                  getTitlesWidget: (value, meta) {
                    final date = DateTime.fromMillisecondsSinceEpoch(
                      value.toInt(),
                    );
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        DateFormat('dd/MM').format(date),
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
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
            borderData: FlBorderData(
              show: true,
              border: Border.all(color: Colors.grey.shade300),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: Theme.of(context).primaryColorDark,
                barWidth: 4,
                isStrokeCapRound: true,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  color: Theme.of(context).primaryColor.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
