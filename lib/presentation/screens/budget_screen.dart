import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final _amountController = TextEditingController();
  DateTime _selectedMonth = DateTime.now();

  // Dialog để đặt/sửa ngân sách TỔNG
  void _showSetTotalBudgetDialog(Budget? currentBudget) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _amountController.text = currentBudget?.totalAmount.toString() ?? '';
    String ownerType = 'personal';
    if (currentBudget != null &&
        currentBudget.ownerId == userProvider.partnershipId) {
      ownerType = 'shared';
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                'Đặt ngân sách cho tháng ${DateFormat('MM/yyyy').format(_selectedMonth)}',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tổng ngân sách',
                      ),
                    ),
                    if (userProvider.partnershipId != null &&
                        currentBudget == null) ...[
                      const SizedBox(height: 16),
                      RadioListTile<String>(
                        title: const Text('Cá nhân'),
                        value: 'personal',
                        groupValue: ownerType,
                        onChanged: (value) =>
                            setDialogState(() => ownerType = value!),
                      ),
                      RadioListTile<String>(
                        title: const Text('Chung'),
                        value: 'shared',
                        groupValue: ownerType,
                        onChanged: (value) =>
                            setDialogState(() => ownerType = value!),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () => _handleSaveTotalBudget(
                    dialogContext: dialogContext,
                    userProvider: userProvider,
                    currentBudget: currentBudget,
                    ownerType: ownerType,
                  ),
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Dialog để đặt hạn mức cho một DANH MỤC CỤ THỂ
  void _showSetCategoryBudgetDialog(
    String budgetId,
    List<Category> allCategories,
  ) {
    Category? selectedCategory;
    final categoryAmountController = TextEditingController();

    // Sửa lỗi Dropdown
    if (selectedCategory != null &&
        !allCategories.any((cat) => cat.id == selectedCategory!.id)) {
      selectedCategory = null;
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Đặt hạn mức cho Danh mục'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<Category>(
                    hint: const Text('Chọn danh mục'),
                    isExpanded: true,
                    value: selectedCategory,
                    items: allCategories.map((cat) {
                      return DropdownMenuItem<Category>(
                        value: cat,
                        child: Text(cat.name),
                      );
                    }).toList(),
                    onChanged: (cat) =>
                        setDialogState(() => selectedCategory = cat),
                    validator: (value) =>
                        value == null ? 'Vui lòng chọn một danh mục' : null,
                  ),
                  TextField(
                    controller: categoryAmountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Hạn mức chi tiêu',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final amount = double.tryParse(
                      categoryAmountController.text,
                    );
                    if (amount != null && selectedCategory != null) {
                      _databaseService.setCategoryBudget(
                        budgetId,
                        selectedCategory!.id,
                        amount,
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Logic xử lý lưu ngân sách TỔNG
  void _handleSaveTotalBudget({
    required BuildContext dialogContext,
    required UserProvider userProvider,
    required Budget? currentBudget,
    required String ownerType,
  }) {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập một số tiền hợp lệ.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final String ownerId = (currentBudget != null)
        ? currentBudget.ownerId
        : (ownerType == 'shared'
              ? userProvider.partnershipId!
              : FirebaseAuth.instance.currentUser!.uid);

    final newBudget = Budget(
      id: currentBudget?.id ?? '',
      ownerId: ownerId,
      month: DateFormat('yyyy-MM').format(_selectedMonth),
      totalAmount: amount,
      categoryAmounts: currentBudget?.categoryAmounts ?? {},
    );

    _databaseService.saveBudget(newBudget);
    Navigator.pop(dialogContext);
  }

  @override
  Widget build(BuildContext context) {
    final monthString = DateFormat('yyyy-MM').format(_selectedMonth);
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ngân sách tháng')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Bộ chọn tháng
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(
                    () => _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                    ),
                  ),
                ),
                Text(
                  DateFormat('MMMM yyyy', 'vi_VN').format(_selectedMonth),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(
                    () => _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Nội dung chính
            StreamBuilder<Budget?>(
              stream: _databaseService.getBudgetForMonthStream(monthString),
              builder: (context, budgetSnapshot) {
                if (budgetSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final budget = budgetSnapshot.data;

                // TRƯỜNG HỢP 1: CHƯA CÓ NGÂN SÁCH
                if (budget == null) {
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Center(
                        child: ElevatedButton.icon(
                          onPressed: () => _showSetTotalBudgetDialog(null),
                          icon: const Icon(Icons.add),
                          label: const Text('Tạo Ngân Sách Tổng'),
                        ),
                      ),
                    ),
                  );
                }

                // TRƯỜNG HỢP 2: ĐÃ CÓ NGÂN SÁCH (budget chắc chắn không null ở đây)
                return Column(
                  children: [
                    // Hiển thị ngân sách tổng
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            Text(
                              'Ngân sách đã đặt',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              currencyFormatter.format(budget.totalAmount),
                              style: Theme.of(context).textTheme.displaySmall
                                  ?.copyWith(
                                    color: Theme.of(context).primaryColor,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () =>
                                  _showSetTotalBudgetDialog(budget),
                              icon: const Icon(Icons.edit),
                              label: const Text('Chỉnh Sửa'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Hiển thị ngân sách theo danh mục
                    Text(
                      'Hạn mức theo Danh mục',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _buildCategoryBudgetsList(
                      budget,
                      currencyFormatter,
                    ), // Gọi hàm build danh sách con
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Widget để xây dựng danh sách ngân sách theo danh mục
  Widget _buildCategoryBudgetsList(Budget budget, NumberFormat formatter) {
    return StreamBuilder<List<Category>>(
      stream: _databaseService.getCategoriesStream(),
      builder: (context, categorySnapshot) {
        if (!categorySnapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final allCategories = categorySnapshot.data!;
        final categoryBudgets = budget.categoryAmounts;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                if (categoryBudgets.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: Text('Chưa có hạn mức nào được đặt.'),
                  ),

                // Lặp qua các hạn mức đã đặt và hiển thị
                ...categoryBudgets.entries.map((entry) {
                  final categoryId = entry.key;
                  final amount = (entry.value as num).toDouble();
                  final category = allCategories.firstWhere(
                    (c) => c.id == categoryId,
                    orElse: () => Category(
                      id: '',
                      name: 'Danh mục đã xóa',
                      ownerId: '',
                      type: 'expense',
                    ),
                  );

                  return ListTile(
                    leading: const Icon(
                      Icons.label_important_outline,
                      color: Colors.grey,
                    ),
                    title: Text(category.name),
                    trailing: Text(formatter.format(amount)),
                    dense: true,
                  );
                }).toList(),

                // Nút để thêm hạn mức mới
                const Divider(),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm hạn mức cho danh mục'),
                  onPressed: () {
                    final expenseCategories = allCategories
                        .where((c) => c.type == 'expense')
                        .toList();
                    if (expenseCategories.isNotEmpty) {
                      _showSetCategoryBudgetDialog(
                        budget.id,
                        expenseCategories,
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Bạn cần tạo danh mục Chi tiêu trước!'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
