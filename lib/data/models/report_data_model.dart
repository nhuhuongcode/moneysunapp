import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';

class ReportData {
  final double totalIncome;
  final double totalExpense;
  final double personalIncome;
  final double personalExpense;
  final double sharedIncome;
  final double sharedExpense;
  // Map<Category, double> để lưu tổng chi tiêu theo từng danh mục
  final Map<Category, double> expenseByCategory;
  final Map<Category, double> incomeByCategory;
  final List<TransactionModel> rawTransactions;

  ReportData({
    this.totalIncome = 0.0,
    this.totalExpense = 0.0,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.rawTransactions,
    this.personalIncome = 0.0,
    this.personalExpense = 0.0,
    this.sharedIncome = 0.0,
    this.sharedExpense = 0.0,
  });
}
