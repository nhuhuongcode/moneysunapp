import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';

class MonthlySummaryCard extends StatelessWidget {
  const MonthlySummaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final databaseService = DatabaseService();
    final now = DateTime.now();
    final startDate = DateTime(now.year, now.month, 1);
    final endDate = DateTime(now.year, now.month + 1, 0);
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return FutureBuilder<ReportData>(
      // Lấy dữ liệu báo cáo cho tháng hiện tại
      future: databaseService.getReportData(userProvider, startDate, endDate),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Đang tải..."),
            ),
          );
        }

        final report = snapshot.data!;
        final balance = report.totalIncome - report.totalExpense;

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Tổng quan tháng ${now.month}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    currencyFormatter.format(balance),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: balance >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Text(
                  'Số dư cuối tháng',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIncomeExpense(
                      "Thu nhập",
                      report.totalIncome,
                      Colors.green,
                      currencyFormatter,
                    ),
                    _buildIncomeExpense(
                      "Chi tiêu",
                      report.totalExpense,
                      Colors.red,
                      currencyFormatter,
                    ),
                  ],
                ),
                const Divider(height: 24),
                _buildIncomeExpense(
                  "Thu nhập Cá nhân",
                  report.personalIncome,
                  Colors.green,
                  currencyFormatter,
                ),
                const SizedBox(height: 8),
                _buildIncomeExpense(
                  "Chi tiêu Cá nhân",
                  report.personalExpense,
                  Colors.red,
                  currencyFormatter,
                ),

                if (userProvider.partnershipId != null) ...[
                  const Divider(height: 16, indent: 20, endIndent: 20),
                  _buildIncomeExpense(
                    "Thu nhập Chung",
                    report.sharedIncome,
                    Colors.green.shade300,
                    currencyFormatter,
                  ),
                  const SizedBox(height: 8),
                  _buildIncomeExpense(
                    "Chi tiêu Chung",
                    report.sharedExpense,
                    Colors.red.shade300,
                    currencyFormatter,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildIncomeExpense(
    String title,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
        const SizedBox(height: 4),
        Text(
          formatter.format(amount),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
