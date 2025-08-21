import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

class SummaryCard extends StatelessWidget {
  final DateTime initialStartDate;
  final DateTime initialEndDate;
  const SummaryCard({
    super.key,
    required this.initialStartDate,
    required this.initialEndDate,
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final databaseService = DatabaseService();
    final startDate = initialStartDate;
    final endDate = initialEndDate;
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return FutureBuilder<ReportData>(
      future: databaseService.getReportData(userProvider, startDate, endDate),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final report = snapshot.data!;
        final totalBalance = report.totalIncome - report.totalExpense;
        final personalBalance = report.personalIncome - report.personalExpense;
        final sharedBalance = report.sharedIncome - report.sharedExpense;

        return Card(
          elevation: 4,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Text(
                  'Tổng quan',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),

                // Số dư tổng
                Center(
                  child: Column(
                    children: [
                      Text(
                        currencyFormatter.format(totalBalance),
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              color: totalBalance >= 0
                                  ? Colors.green
                                  : Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const Text(
                        'Số dư tổng',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 24),

                // FIX: Tổng thu chi (Personal + Shared)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIncomeExpenseSummary(
                      "Tổng thu nhập",
                      report.totalIncome,
                      Colors.green,
                      currencyFormatter,
                    ),
                    _buildIncomeExpenseSummary(
                      "Tổng chi tiêu",
                      report.totalExpense,
                      Colors.red,
                      currencyFormatter,
                    ),
                  ],
                ),

                // FIX: Thu chi chung (chỉ hiển thị khi có partner)
                if (userProvider.hasPartner) ...[
                  const Divider(height: 20),

                  // FIX: Thu chi cá nhân
                  _buildSectionTitle(
                    '💼 Cá nhân',
                    personalBalance,
                    currencyFormatter,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildIncomeExpenseSummary(
                        "Thu nhập",
                        report.personalIncome,
                        Colors.green.shade600,
                        currencyFormatter,
                      ),
                      _buildIncomeExpenseSummary(
                        "Chi tiêu",
                        report.personalExpense,
                        Colors.red.shade600,
                        currencyFormatter,
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  _buildSectionTitle(
                    '👥 Chung (${userProvider.partnerDisplayName ?? "Đối tác"})',
                    sharedBalance,
                    currencyFormatter,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildIncomeExpenseSummary(
                        "Thu nhập",
                        report.sharedIncome,
                        Colors.green.shade400,
                        currencyFormatter,
                      ),
                      _buildIncomeExpenseSummary(
                        "Chi tiêu",
                        report.sharedExpense,
                        Colors.red.shade400,
                        currencyFormatter,
                      ),
                    ],
                  ),
                ],

                // Thông tin partnership (nếu có)
                if (userProvider.hasPartner) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.people,
                          color: Colors.blue.shade600,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đang kết nối với ${userProvider.partnerDisplayName ?? "đối tác"}',
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // FIX: Build section title với balance
  Widget _buildSectionTitle(
    String title,
    double balance,
    NumberFormat formatter,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(
          formatter.format(balance),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: balance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildIncomeExpenseSummary(
    String title,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            formatter.format(amount),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
