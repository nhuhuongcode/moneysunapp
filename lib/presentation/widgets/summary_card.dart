// lib/presentation/widgets/summary_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';

class SummaryCard extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final bool showPartnership;

  const SummaryCard({
    super.key,
    required this.startDate,
    required this.endDate,
    this.showPartnership = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserProvider, TransactionProvider>(
      builder: (context, userProvider, transactionProvider, child) {
        return FutureBuilder<List<TransactionModel>>(
          future: _getTransactionsInRange(transactionProvider),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _buildLoadingCard(context);
            }

            if (snapshot.hasError) {
              return _buildErrorCard(context, snapshot.error.toString());
            }

            final transactions = snapshot.data ?? [];
            final summary = _calculateSummary(transactions, userProvider);

            return _buildSummaryCard(context, summary, userProvider);
          },
        );
      },
    );
  }

  Future<List<TransactionModel>> _getTransactionsInRange(
    TransactionProvider transactionProvider,
  ) async {
    // Set date filter to get transactions in range
    transactionProvider.setDateFilter(startDate, endDate);

    // Wait a bit for the filter to apply
    await Future.delayed(const Duration(milliseconds: 100));

    return transactionProvider.transactions;
  }

  SummaryData _calculateSummary(
    List<TransactionModel> transactions,
    UserProvider userProvider,
  ) {
    double totalIncome = 0;
    double totalExpense = 0;
    double personalIncome = 0;
    double personalExpense = 0;
    double sharedIncome = 0;
    double sharedExpense = 0;

    final currentUserId = userProvider.currentUser?.uid;
    final partnershipId = userProvider.partnershipId;

    for (final transaction in transactions) {
      switch (transaction.type) {
        case TransactionType.income:
          totalIncome += transaction.amount;

          // Determine if it's personal or shared based on wallet ownership
          if (_isSharedTransaction(transaction, currentUserId, partnershipId)) {
            sharedIncome += transaction.amount;
          } else {
            personalIncome += transaction.amount;
          }
          break;

        case TransactionType.expense:
          totalExpense += transaction.amount;

          if (_isSharedTransaction(transaction, currentUserId, partnershipId)) {
            sharedExpense += transaction.amount;
          } else {
            personalExpense += transaction.amount;
          }
          break;

        case TransactionType.transfer:
          // Transfers don't affect income/expense totals
          break;
      }
    }

    return SummaryData(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      personalIncome: personalIncome,
      personalExpense: personalExpense,
      sharedIncome: sharedIncome,
      sharedExpense: sharedExpense,
      transactionCount: transactions.length,
    );
  }

  bool _isSharedTransaction(
    TransactionModel transaction,
    String? currentUserId,
    String? partnershipId,
  ) {
    // This logic would need to be improved based on wallet ownership
    // For now, we'll use a simple heuristic based on category or wallet names
    // In a real implementation, you'd check the wallet's ownerId
    return transaction.walletName.toLowerCase().contains('chung') ||
        transaction.categoryName.toLowerCase().contains('chung');
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Đang tải tổng quan...',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context, String error) {
    return Card(
      elevation: 4,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600, size: 48),
            const SizedBox(height: 16),
            Text(
              'Không thể tải dữ liệu',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    BuildContext context,
    SummaryData summary,
    UserProvider userProvider,
  ) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    final totalBalance = summary.totalIncome - summary.totalExpense;
    final personalBalance = summary.personalIncome - summary.personalExpense;
    final sharedBalance = summary.sharedIncome - summary.sharedExpense;

    return Card(
      elevation: 6,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.05),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tổng quan tài chính',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _formatDateRange(),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Số dư tổng
              Center(
                child: Column(
                  children: [
                    Text(
                      currencyFormatter.format(totalBalance),
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            color: totalBalance >= 0
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: (totalBalance >= 0 ? Colors.green : Colors.red)
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Số dư tổng',
                        style: TextStyle(
                          color: totalBalance >= 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Thu chi tổng
              Row(
                children: [
                  Expanded(
                    child: _buildIncomeExpenseCard(
                      context,
                      'Tổng thu nhập',
                      summary.totalIncome,
                      Colors.green,
                      Icons.trending_up,
                      currencyFormatter,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildIncomeExpenseCard(
                      context,
                      'Tổng chi tiêu',
                      summary.totalExpense,
                      Colors.red,
                      Icons.trending_down,
                      currencyFormatter,
                    ),
                  ),
                ],
              ),

              // Partnership details (if user has partner)
              if (showPartnership && userProvider.hasPartner) ...[
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 20),

                // Partnership header
                Row(
                  children: [
                    Icon(
                      Icons.people_rounded,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Chi tiết theo loại',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Personal section
                _buildSectionCard(
                  context,
                  '💼 Cá nhân',
                  personalBalance,
                  summary.personalIncome,
                  summary.personalExpense,
                  Colors.blue,
                  currencyFormatter,
                ),

                const SizedBox(height: 12),

                // Shared section
                _buildSectionCard(
                  context,
                  '👥 Chung (${userProvider.partnerDisplayName ?? "Đối tác"})',
                  sharedBalance,
                  summary.sharedIncome,
                  summary.sharedExpense,
                  Colors.orange,
                  currencyFormatter,
                ),
              ],

              // Transaction count
              if (summary.transactionCount > 0) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long,
                        color: Colors.grey.shade600,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tổng ${summary.transactionCount} giao dịch',
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomeExpenseCard(
    BuildContext context,
    String title,
    double amount,
    Color color,
    IconData icon,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            formatter.format(amount),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    String title,
    double balance,
    double income,
    double expense,
    Color color,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
                ),
              ),
              Text(
                formatter.format(balance),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: balance >= 0
                      ? Colors.green.shade600
                      : Colors.red.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSmallStat('Thu nhập', income, Colors.green, formatter),
              _buildSmallStat('Chi tiêu', expense, Colors.red, formatter),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallStat(
    String label,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        ),
        Text(
          formatter.format(amount),
          style: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _formatDateRange() {
    final formatter = DateFormat('dd/MM/yyyy');
    if (startDate.year == endDate.year &&
        startDate.month == endDate.month &&
        startDate.day == endDate.day) {
      return formatter.format(startDate);
    }
    return '${formatter.format(startDate)} - ${formatter.format(endDate)}';
  }
}

// Data class for summary calculations
class SummaryData {
  final double totalIncome;
  final double totalExpense;
  final double personalIncome;
  final double personalExpense;
  final double sharedIncome;
  final double sharedExpense;
  final int transactionCount;

  const SummaryData({
    required this.totalIncome,
    required this.totalExpense,
    required this.personalIncome,
    required this.personalExpense,
    required this.sharedIncome,
    required this.sharedExpense,
    required this.transactionCount,
  });

  double get totalBalance => totalIncome - totalExpense;
  double get personalBalance => personalIncome - personalExpense;
  double get sharedBalance => sharedIncome - sharedExpense;
}
