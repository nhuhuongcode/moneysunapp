import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final DatabaseService _databaseService = DatabaseService();
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ngân sách'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _showMonthPicker,
          ),
        ],
      ),
      body: StreamBuilder<Budget?>(
        stream: _databaseService.getBudgetForMonthStream(_selectedMonth),
        builder: (context, budgetSnapshot) {
          return FutureBuilder<ReportData>(
            // FIX: Lấy dữ liệu thực tế để so sánh
            future: _getActualSpendingData(userProvider),
            builder: (context, actualSnapshot) {
              if (!actualSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final actualData = actualSnapshot.data!;
              final budget = budgetSnapshot.data;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header với tháng được chọn
                    _buildMonthHeader(),
                    const SizedBox(height: 16),

                    // FIX: Tổng quan ngân sách vs thực tế
                    _buildBudgetOverviewCard(
                      budget,
                      actualData,
                      currencyFormatter,
                    ),
                    const SizedBox(height: 16),

                    // FIX: Danh sách categories với ngân sách vs thực tế
                    _buildCategoryBudgetList(
                      budget,
                      actualData,
                      currencyFormatter,
                    ),
                    const SizedBox(height: 16),

                    // Nút thêm/sửa ngân sách
                    _buildActionButtons(budget),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildMonthHeader() {
    final date = DateFormat('yyyy-MM').parse(_selectedMonth);
    final displayMonth = DateFormat('MMMM yyyy', 'vi_VN').format(date);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Ngân sách $displayMonth',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.edit_calendar),
              onPressed: _showMonthPicker,
            ),
          ],
        ),
      ),
    );
  }

  // FIX: Tổng quan ngân sách
  Widget _buildBudgetOverviewCard(
    Budget? budget,
    ReportData actualData,
    NumberFormat formatter,
  ) {
    final totalBudget = budget?.totalAmount ?? 0.0;
    final totalSpent = actualData.totalExpense;
    final remaining = totalBudget - totalSpent;
    final spentPercentage = totalBudget > 0
        ? (totalSpent / totalBudget * 100)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Tổng quan',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Progress indicator
            Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: spentPercentage / 100,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: _getProgressColor(spentPercentage),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Text(
              '${spentPercentage.toStringAsFixed(1)}% đã sử dụng',
              style: TextStyle(
                color: _getProgressColor(spentPercentage),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Thống kê chi tiết
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildBudgetStat(
                  'Ngân sách',
                  totalBudget,
                  Colors.blue,
                  formatter,
                ),
                _buildBudgetStat('Đã chi', totalSpent, Colors.red, formatter),
                _buildBudgetStat(
                  'Còn lại',
                  remaining,
                  remaining >= 0 ? Colors.green : Colors.red,
                  formatter,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetStat(
    String label,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          formatter.format(amount),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // FIX: Danh sách categories với so sánh ngân sách vs thực tế
  Widget _buildCategoryBudgetList(
    Budget? budget,
    ReportData actualData,
    NumberFormat formatter,
  ) {
    return StreamBuilder<List<Category>>(
      stream: _databaseService.getCategoriesByTypeStream('expense'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final categories = snapshot.data!;
        if (categories.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Chưa có danh mục chi tiêu nào'),
            ),
          );
        }

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
              ...categories.map((category) {
                final budgetAmount =
                    budget?.categoryAmounts[category.id] ?? 0.0;
                final actualAmount =
                    actualData.expenseByCategory[category] ?? 0.0;
                final percentage = budgetAmount > 0
                    ? (actualAmount / budgetAmount * 100)
                    : 0.0;

                return _buildCategoryBudgetItem(
                  category,
                  budgetAmount,
                  actualAmount,
                  percentage,
                  formatter,
                  budget?.id ?? '',
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryBudgetItem(
    Category category,
    double budgetAmount,
    double actualAmount,
    double percentage,
    NumberFormat formatter,
    String budgetId,
  ) {
    final progressColor = _getProgressColor(percentage);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: progressColor.withOpacity(0.2),
        child: Icon(Icons.category, color: progressColor),
      ),
      title: Text(category.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // Progress bar
          Stack(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: (percentage / 100).clamp(0.0, 1.0),
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: progressColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${formatter.format(actualAmount)} / ${formatter.format(budgetAmount)}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${percentage.toStringAsFixed(0)}%',
            style: TextStyle(fontWeight: FontWeight.bold, color: progressColor),
          ),
          Text(
            formatter.format(budgetAmount - actualAmount),
            style: TextStyle(
              fontSize: 10,
              color: budgetAmount - actualAmount >= 0
                  ? Colors.green
                  : Colors.red,
            ),
          ),
        ],
      ),
      onTap: () => _showSetBudgetDialog(category, budgetAmount, budgetId),
    );
  }

  Widget _buildActionButtons(Budget? budget) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showSetTotalBudgetDialog(budget),
            icon: const Icon(Icons.add),
            label: Text(
              budget == null ? 'Tạo ngân sách tháng' : 'Sửa tổng ngân sách',
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (budget != null)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _deleteBudget(budget),
              icon: const Icon(Icons.delete, color: Colors.red),
              label: const Text(
                'Xóa ngân sách',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
      ],
    );
  }

  Color _getProgressColor(double percentage) {
    if (percentage <= 50) return Colors.green;
    if (percentage <= 80) return Colors.orange;
    return Colors.red;
  }

  Future<ReportData> _getActualSpendingData(UserProvider userProvider) async {
    final date = DateFormat('yyyy-MM').parse(_selectedMonth);
    final startDate = DateTime(date.year, date.month, 1);
    final endDate = DateTime(date.year, date.month + 1, 0);

    return await _databaseService.getReportData(
      userProvider,
      startDate,
      endDate,
    );
  }

  void _showMonthPicker() async {
    final date = DateFormat('yyyy-MM').parse(_selectedMonth);
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDatePickerMode: DatePickerMode.year,
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateFormat('yyyy-MM').format(picked);
      });
    }
  }

  void _showSetTotalBudgetDialog(Budget? existingBudget) {
    final controller = TextEditingController(
      text: existingBudget?.totalAmount.toString() ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existingBudget == null ? 'Tạo ngân sách' : 'Sửa tổng ngân sách',
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Tổng ngân sách',
            suffixText: '₫',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount > 0) {
                final budget = Budget(
                  id: existingBudget?.id ?? '',
                  ownerId: Provider.of<UserProvider>(
                    context,
                    listen: false,
                  ).currentUser!.uid,
                  month: _selectedMonth,
                  totalAmount: amount,
                  categoryAmounts: existingBudget?.categoryAmounts ?? {},
                );

                await _databaseService.saveBudget(budget);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      existingBudget == null
                          ? 'Đã tạo ngân sách'
                          : 'Đã cập nhật ngân sách',
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập số tiền hợp lệ')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showSetBudgetDialog(
    Category category,
    double currentAmount,
    String budgetId,
  ) {
    final controller = TextEditingController(
      text: currentAmount > 0 ? currentAmount.toString() : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Ngân sách: ${category.name}'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Ngân sách cho danh mục',
            suffixText: '₫',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          if (currentAmount > 0)
            TextButton(
              onPressed: () async {
                // Xóa ngân sách cho category này
                await _databaseService.setCategoryBudget(
                  budgetId,
                  category.id,
                  0,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa ngân sách danh mục')),
                );
              },
              child: const Text('Xóa', style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text);
              if (amount != null && amount >= 0) {
                if (budgetId.isEmpty) {
                  // Tạo budget mới nếu chưa có
                  final budget = Budget(
                    id: '',
                    ownerId: Provider.of<UserProvider>(
                      context,
                      listen: false,
                    ).currentUser!.uid,
                    month: _selectedMonth,
                    totalAmount: 0,
                    categoryAmounts: {category.id: amount},
                  );
                  await _databaseService.saveBudget(budget);
                } else {
                  await _databaseService.setCategoryBudget(
                    budgetId,
                    category.id,
                    amount,
                  );
                }

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã cập nhật ngân sách danh mục'),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vui lòng nhập số tiền hợp lệ')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _deleteBudget(Budget budget) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa ngân sách'),
        content: const Text(
          'Bạn có chắc chắn muốn xóa toàn bộ ngân sách tháng này không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await FirebaseDatabase.instance
                    .ref()
                    .child('budgets')
                    .child(budget.id)
                    .remove();

                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã xóa ngân sách')),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Lỗi khi xóa: $e')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
