// lib/presentation/widgets/budget_dialogs.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/enhanced_budget_service.dart';
import 'package:moneysun/data/services/enhanced_category_service.dart';

// ============ EDIT BUDGET DIALOG ============
class EditBudgetDialog extends StatefulWidget {
  final Budget budget;
  final UserProvider userProvider;
  final VoidCallback onUpdated;

  const EditBudgetDialog({
    super.key,
    required this.budget,
    required this.userProvider,
    required this.onUpdated,
  });

  @override
  State<EditBudgetDialog> createState() => _EditBudgetDialogState();
}

class _EditBudgetDialogState extends State<EditBudgetDialog> {
  late final TextEditingController _totalAmountController;
  final _budgetService = EnhancedBudgetService();
  final _categoryService = EnhancedCategoryService();

  late Map<String, double> _categoryAmounts;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _totalAmountController = TextEditingController(
      text: widget.budget.totalAmount.toString(),
    );
    _categoryAmounts = Map<String, double>.from(widget.budget.categoryAmounts);
  }

  @override
  void dispose() {
    _totalAmountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        (widget.budget.budgetType == BudgetType.shared
                                ? Colors.orange
                                : Colors.blue)
                            .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.edit_rounded,
                    color: widget.budget.budgetType == BudgetType.shared
                        ? Colors.orange
                        : Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Chỉnh sửa ${widget.budget.displayName}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Total Amount Input
            TextField(
              controller: _totalAmountController,
              decoration: InputDecoration(
                labelText: 'Tổng ngân sách (₫)',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.account_balance_wallet),
              ),
              keyboardType: TextInputType.number,
              enabled: !_isLoading,
            ),

            const SizedBox(height: 16),

            // Categories List
            Expanded(
              child: StreamBuilder<List<Category>>(
                stream: _categoryService.getCategoriesWithOwnershipStream(
                  widget.userProvider,
                  type: 'expense',
                ),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }

                  final categories = snapshot.data!.where((cat) {
                    if (widget.budget.budgetType == BudgetType.shared) {
                      return cat.ownershipType == CategoryOwnershipType.shared;
                    } else {
                      return cat.ownershipType ==
                          CategoryOwnershipType.personal;
                    }
                  }).toList();

                  return ListView.builder(
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final category = categories[index];
                      return _buildCategoryBudgetInput(category);
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _updateBudget,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          widget.budget.budgetType == BudgetType.shared
                          ? Colors.orange
                          : Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Cập nhật'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBudgetInput(Category category) {
    final currentAmount = _categoryAmounts[category.id] ?? 0.0;
    final controller = TextEditingController(
      text: currentAmount > 0 ? currentAmount.toString() : '',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            category.isShared ? Icons.people : Icons.person,
            size: 20,
            color: category.isShared ? Colors.orange : Colors.blue,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              category.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '0',
                suffixText: '₫',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final amount = double.tryParse(value) ?? 0.0;
                setState(() {
                  if (amount > 0) {
                    _categoryAmounts[category.id] = amount;
                  } else {
                    _categoryAmounts.remove(category.id);
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  void _updateBudget() async {
    final totalAmountText = _totalAmountController.text.trim();
    if (totalAmountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tổng ngân sách'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final totalAmount = double.tryParse(totalAmountText);
    if (totalAmount == null || totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tổng ngân sách phải là số dương'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedBudget = widget.budget.copyWith(
        totalAmount: totalAmount,
        categoryAmounts: _categoryAmounts,
        updatedAt: DateTime.now(),
      );

      await _budgetService.updateBudget(updatedBudget);

      Navigator.pop(context);
      widget.onUpdated();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi cập nhật ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

// ============ SET CATEGORY BUDGET DIALOG ============
class SetCategoryBudgetDialog extends StatefulWidget {
  final Category category;
  final double currentAmount;
  final String budgetId;
  final BudgetType budgetType;
  final String month;
  final UserProvider userProvider;
  final VoidCallback onUpdated;

  const SetCategoryBudgetDialog({
    super.key,
    required this.category,
    required this.currentAmount,
    required this.budgetId,
    required this.budgetType,
    required this.month,
    required this.userProvider,
    required this.onUpdated,
  });

  @override
  State<SetCategoryBudgetDialog> createState() =>
      _SetCategoryBudgetDialogState();
}

class _SetCategoryBudgetDialogState extends State<SetCategoryBudgetDialog> {
  late final TextEditingController _amountController;
  final _budgetService = EnhancedBudgetService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.currentAmount > 0 ? widget.currentAmount.toString() : '',
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        (widget.category.isShared ? Colors.orange : Colors.blue)
                            .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    widget.category.isShared
                        ? Icons.people_rounded
                        : Icons.person_rounded,
                    color: widget.category.isShared
                        ? Colors.orange
                        : Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Đặt ngân sách',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.category.name,
                        style: TextStyle(
                          color: widget.category.isShared
                              ? Colors.orange
                              : Colors.blue,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: (widget.category.isShared ? Colors.orange : Colors.blue)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      (widget.category.isShared ? Colors.orange : Colors.blue)
                          .withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: widget.category.isShared
                            ? Colors.orange
                            : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Thông tin danh mục',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: widget.category.isShared
                              ? Colors.orange
                              : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Loại: ${widget.category.isShared ? "Danh mục chung" : "Danh mục cá nhân"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Tháng: ${DateFormat('MM/yyyy').format(DateFormat('yyyy-MM').parse(widget.month))}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (widget.currentAmount > 0)
                    Text(
                      'Ngân sách hiện tại: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(widget.currentAmount)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Amount Input
            TextField(
              controller: _amountController,
              decoration: InputDecoration(
                labelText: 'Số tiền ngân sách (₫)',
                hintText: 'Nhập số tiền...',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: widget.category.isShared
                        ? Colors.orange
                        : Colors.blue,
                    width: 2,
                  ),
                ),
                prefixIcon: Icon(
                  Icons.attach_money_rounded,
                  color: widget.category.isShared ? Colors.orange : Colors.blue,
                ),
                suffixText: '₫',
              ),
              keyboardType: TextInputType.number,
              enabled: !_isLoading,
              autofocus: true,
            ),

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                if (widget.currentAmount > 0) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _removeBudget,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Xóa'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Hủy'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _setBudget,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.category.isShared
                          ? Colors.orange
                          : Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            widget.currentAmount > 0
                                ? 'Cập nhật'
                                : 'Đặt ngân sách',
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _setBudget() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập số tiền'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số tiền phải là số dương'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Nếu chưa có budgetId, tạo budget mới
      if (widget.budgetId.isEmpty) {
        await _createNewBudgetWithCategory(amount);
      } else {
        await _budgetService.setCategoryBudgetWithOwnership(
          widget.budgetId,
          widget.category.id,
          amount,
          widget.userProvider,
        );
      }

      Navigator.pop(context);
      widget.onUpdated();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi đặt ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _removeBudget() async {
    setState(() => _isLoading = true);

    try {
      await _budgetService.setCategoryBudgetWithOwnership(
        widget.budgetId,
        widget.category.id,
        0.0, // Set to 0 to remove
        widget.userProvider,
      );

      Navigator.pop(context);
      widget.onUpdated();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi xóa ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _createNewBudgetWithCategory(double amount) async {
    await _budgetService.createBudgetWithOwnership(
      month: widget.month,
      totalAmount: amount,
      categoryAmounts: {widget.category.id: amount},
      budgetType: widget.budgetType,
      userProvider: widget.userProvider,
    );
  }
}

// ============ COPY BUDGET DIALOG ============
class CopyBudgetDialog extends StatefulWidget {
  final String currentMonth;
  final BudgetType budgetType;
  final UserProvider userProvider;
  final VoidCallback onCopied;

  const CopyBudgetDialog({
    super.key,
    required this.currentMonth,
    required this.budgetType,
    required this.userProvider,
    required this.onCopied,
  });

  @override
  State<CopyBudgetDialog> createState() => _CopyBudgetDialogState();
}

class _CopyBudgetDialogState extends State<CopyBudgetDialog> {
  final _budgetService = EnhancedBudgetService();
  String? _selectedMonth;
  List<Budget> _availableBudgets = [];
  bool _isLoading = false;
  bool _isLoadingBudgets = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableBudgets();
  }

  void _loadAvailableBudgets() async {
    try {
      final budgets = await _budgetService.getBudgetsOfflineFirst(
        budgetType: widget.budgetType,
        userProvider: widget.userProvider,
      );

      // Filter out current month
      final filteredBudgets = budgets
          .where((budget) => budget.month != widget.currentMonth)
          .toList();

      setState(() {
        _availableBudgets = filteredBudgets;
        _isLoadingBudgets = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingBudgets = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.copy_rounded,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Sao chép ngân sách',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            if (_isLoadingBudgets) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Đang tải danh sách ngân sách...'),
            ] else if (_availableBudgets.isEmpty) ...[
              Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 16),
              Text(
                'Không có ngân sách ${widget.budgetType == BudgetType.shared ? "chung" : "cá nhân"} nào để sao chép',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
              ),
            ] else ...[
              // Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Chọn tháng có ngân sách để sao chép sang ${DateFormat('MM/yyyy').format(DateFormat('yyyy-MM').parse(widget.currentMonth))}',
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Budget List
              Container(
                constraints: const BoxConstraints(maxHeight: 300),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _availableBudgets.length,
                  itemBuilder: (context, index) {
                    final budget = _availableBudgets[index];
                    final isSelected = _selectedMonth == budget.month;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        selected: isSelected,
                        selectedTileColor: Colors.blue.withOpacity(0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? Colors.blue
                                : Colors.grey.shade300,
                          ),
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                (budget.budgetType == BudgetType.shared
                                        ? Colors.orange
                                        : Colors.blue)
                                    .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            budget.budgetType == BudgetType.shared
                                ? Icons.people
                                : Icons.person,
                            size: 20,
                            color: budget.budgetType == BudgetType.shared
                                ? Colors.orange
                                : Colors.blue,
                          ),
                        ),
                        title: Text(
                          DateFormat(
                            'MMMM yyyy',
                            'vi_VN',
                          ).format(DateFormat('yyyy-MM').parse(budget.month)),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(budget.totalAmount)} - ${budget.categoryAmounts.length} danh mục',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Colors.blue)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedMonth = isSelected ? null : budget.month;
                          });
                        },
                      ),
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_isLoading || _selectedMonth == null)
                        ? null
                        : _copyBudget,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Sao chép'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _copyBudget() async {
    if (_selectedMonth == null) return;

    setState(() => _isLoading = true);

    try {
      await _budgetService.copyBudgetFromPreviousMonth(
        widget.currentMonth,
        widget.budgetType,
        widget.userProvider,
      );

      Navigator.pop(context);
      widget.onCopied();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi sao chép ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
