import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';
import 'package:provider/provider.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen>
    with TickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());

  late AnimationController _slideController;
  late AnimationController _progressController;
  late Animation<double> _slideAnimation;
  late Animation<double> _progressAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );
    _progressAnimation = CurvedAnimation(
      parent: _progressController,
      curve: Curves.easeInOut,
    );

    _slideController.forward();
    _progressController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: AnimatedBuilder(
        animation: _slideAnimation,
        builder: (context, child) {
          return StreamBuilder<Budget?>(
            stream: _databaseService.getBudgetForMonthStream(_selectedMonth),
            builder: (context, budgetSnapshot) {
              return FutureBuilder<ReportData>(
                future: _getActualSpendingData(userProvider),
                builder: (context, actualSnapshot) {
                  if (!actualSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final actualData = actualSnapshot.data!;
                  final budget = budgetSnapshot.data;
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {});
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Month Header Card with Animation
                          FadeTransition(
                            opacity: _slideAnimation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, -0.3),
                                end: Offset.zero,
                              ).animate(_slideAnimation),
                              child: _buildEnhancedMonthHeader(),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Budget Overview Card with Enhanced Progress
                          FadeTransition(
                            opacity: _slideAnimation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(-0.3, 0),
                                end: Offset.zero,
                              ).animate(_slideAnimation),
                              child: _buildEnhancedBudgetOverviewCard(
                                budget,
                                actualData,
                                currencyFormatter,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Category Budget List with Enhanced UI
                          FadeTransition(
                            opacity: _slideAnimation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.3, 0),
                                end: Offset.zero,
                              ).animate(_slideAnimation),
                              child: _buildEnhancedCategoryBudgetList(
                                budget,
                                actualData,
                                currencyFormatter,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Action Buttons with Enhanced Design
                          FadeTransition(
                            opacity: _slideAnimation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(_slideAnimation),
                              child: _buildEnhancedActionButtons(budget),
                            ),
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: const Text(
        'Ngân sách',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
      ),
      actions: [
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.analytics_rounded),
            onPressed: _showBudgetAnalytics,
            tooltip: 'Phân tích ngân sách',
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedMonthHeader() {
    final date = DateFormat('yyyy-MM').parse(_selectedMonth);
    final displayMonth = DateFormat('MMMM yyyy', 'vi_VN').format(date);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.indigo.shade600, Colors.indigo.shade400],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ngân sách tháng',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      displayMonth,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  icon: const Icon(
                    Icons.edit_calendar_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _showMonthPicker,
                  tooltip: 'Chọn tháng khác',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Quick Month Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMonthNavButton(
                Icons.chevron_left_rounded,
                'Tháng trước',
                () => _navigateMonth(-1),
              ),
              const SizedBox(width: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Tháng ${date.month}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 24),
              _buildMonthNavButton(
                Icons.chevron_right_rounded,
                'Tháng sau',
                () => _navigateMonth(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNavButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }

  Widget _buildEnhancedBudgetOverviewCard(
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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getProgressColor(spentPercentage).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.pie_chart_rounded,
                  color: _getProgressColor(spentPercentage),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'Tổng quan ngân sách',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Enhanced Progress Indicator
          AnimatedBuilder(
            animation: _progressAnimation,
            builder: (context, child) {
              return Column(
                children: [
                  // Progress Bar
                  Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value:
                            (spentPercentage / 100 * _progressAnimation.value)
                                .clamp(0.0, 1.0),
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getProgressColor(spentPercentage),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Percentage Display
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${(spentPercentage * _progressAnimation.value).toStringAsFixed(1)}% đã sử dụng',
                        style: TextStyle(
                          color: _getProgressColor(spentPercentage),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (totalBudget > 0)
                        Text(
                          '${formatter.format(totalBudget - totalSpent)} còn lại',
                          style: TextStyle(
                            color: remaining >= 0 ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // Budget Statistics Grid
          Row(
            children: [
              Expanded(
                child: _buildBudgetStatCard(
                  'Ngân sách',
                  totalBudget,
                  Colors.blue,
                  Icons.account_balance_wallet_rounded,
                  formatter,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBudgetStatCard(
                  'Đã chi',
                  totalSpent,
                  Colors.red,
                  Icons.trending_down_rounded,
                  formatter,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildBudgetStatCard(
                  'Còn lại',
                  remaining,
                  remaining >= 0 ? Colors.green : Colors.red,
                  remaining >= 0
                      ? Icons.trending_up_rounded
                      : Icons.warning_rounded,
                  formatter,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetStatCard(
    String label,
    double amount,
    Color color,
    IconData icon,
    NumberFormat formatter,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatter.format(amount.abs()),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedCategoryBudgetList(
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
          return _buildEmptyCategoriesState();
        }

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.category_rounded,
                        color: Colors.purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Chi tiết theo danh mục',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${categories.length} danh mục',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),

              // Categories List
              ...categories.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;
                final budgetAmount =
                    budget?.categoryAmounts[category.id] ?? 0.0;
                final actualAmount =
                    actualData.expenseByCategory[category] ?? 0.0;
                final percentage = budgetAmount > 0
                    ? (actualAmount / budgetAmount * 100)
                    : 0.0;

                return AnimatedContainer(
                  duration: Duration(milliseconds: 300 + (index * 100)),
                  margin: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: index == categories.length - 1 ? 20 : 12,
                  ),
                  child: _buildEnhancedCategoryBudgetItem(
                    category,
                    budgetAmount,
                    actualAmount,
                    percentage,
                    formatter,
                    budget?.id ?? '',
                  ),
                );
              }).toList(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEnhancedCategoryBudgetItem(
    Category category,
    double budgetAmount,
    double actualAmount,
    double percentage,
    NumberFormat formatter,
    String budgetId,
  ) {
    final progressColor = _getProgressColor(percentage);
    final hasExceeded = percentage > 100;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: progressColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: progressColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: progressColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.category_outlined,
                  color: progressColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  category.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: hasExceeded
                      ? Colors.red.withOpacity(0.1)
                      : progressColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${percentage.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: hasExceeded ? Colors.red : progressColor,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Progress Bar
          Stack(
            children: [
              Container(
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              FractionallySizedBox(
                widthFactor: (percentage / 100).clamp(0.0, 1.0),
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: progressColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Amount Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Đã chi',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    formatter.format(actualAmount),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: progressColor,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Ngân sách',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    formatter.format(budgetAmount),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasExceeded ? 'Vượt' : 'Còn lại',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  Text(
                    formatter.format((budgetAmount - actualAmount).abs()),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: hasExceeded ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  _showSetBudgetDialog(category, budgetAmount, budgetId),
              icon: Icon(
                budgetAmount > 0 ? Icons.edit_rounded : Icons.add_rounded,
                size: 18,
                color: progressColor,
              ),
              label: Text(
                budgetAmount > 0 ? 'Chỉnh sửa ngân sách' : 'Đặt ngân sách',
                style: TextStyle(color: progressColor),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: progressColor.withOpacity(0.5)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCategoriesState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.category_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text(
            'Chưa có danh mục chi tiêu',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tạo danh mục chi tiêu để thiết lập ngân sách',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // Navigate to manage categories screen
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tạo danh mục'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedActionButtons(Budget? budget) {
    return Column(
      children: [
        // Main Action Button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _showSetTotalBudgetDialog(budget),
            icon: Icon(
              budget == null ? Icons.add_circle_rounded : Icons.edit_rounded,
              size: 20,
            ),
            label: Text(
              budget == null ? 'Tạo ngân sách tháng' : 'Sửa tổng ngân sách',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
            ),
          ),
        ),

        if (budget != null) ...[
          const SizedBox(height: 16),

          // Secondary Actions Row
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showBudgetTemplateDialog(),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Sao chép'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showDeleteBudgetDialog(budget),
                  icon: const Icon(
                    Icons.delete_rounded,
                    size: 18,
                    color: Colors.red,
                  ),
                  label: const Text('Xóa', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
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

  void _navigateMonth(int direction) {
    final currentDate = DateFormat('yyyy-MM').parse(_selectedMonth);
    final newDate = DateTime(
      currentDate.year,
      currentDate.month + direction,
      1,
    );
    setState(() {
      _selectedMonth = DateFormat('yyyy-MM').format(newDate);
    });
  }

  void _showMonthPicker() async {
    final date = DateFormat('yyyy-MM').parse(_selectedMonth);
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.indigo,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedMonth = DateFormat('yyyy-MM').format(picked);
      });
    }
  }

  void _showSetTotalBudgetDialog(Budget? existingBudget) {
    final controller = TextEditingController();
    if (existingBudget != null) {
      controller.text = NumberFormat(
        '#,###',
        'vi_VN',
      ).format(existingBudget.totalAmount);
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      existingBudget == null
                          ? Icons.add_circle_rounded
                          : Icons.edit_rounded,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      existingBudget == null
                          ? 'Tạo ngân sách'
                          : 'Sửa tổng ngân sách',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Smart Amount Input
              SmartAmountInput(
                controller: controller,
                labelText: 'Tổng ngân sách tháng',
                hintText: 'Nhập tổng ngân sách...',
                showQuickButtons: true,
                showSuggestions: true,
                customSuggestions: [
                  1000000,
                  2000000,
                  3000000,
                  5000000,
                  10000000,
                  15000000,
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập số tiền';
                  }
                  final amount = parseAmount(value);
                  if (amount <= 0) {
                    return 'Số tiền phải lớn hơn 0';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Theme.of(context).primaryColor.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: Theme.of(context).primaryColor,
                      width: 2,
                    ),
                  ),
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Theme.of(context).primaryColor,
                      size: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          _saveTotalBudget(existingBudget, controller.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Lưu',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSetBudgetDialog(
    Category category,
    double currentAmount,
    String budgetId,
  ) {
    final controller = TextEditingController();
    if (currentAmount > 0) {
      controller.text = NumberFormat('#,###', 'vi_VN').format(currentAmount);
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.category_rounded,
                      color: Colors.purple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Ngân sách: ${category.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Smart Amount Input for Category Budget
              SmartAmountInput(
                controller: controller,
                labelText: 'Ngân sách cho danh mục',
                hintText: 'Nhập ngân sách...',
                categoryType: category.name.toLowerCase(),
                showQuickButtons: true,
                showSuggestions: true,
                customSuggestions: _getCategoryBudgetSuggestions(category.name),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập số tiền';
                  }
                  final amount = parseAmount(value);
                  if (amount < 0) {
                    return 'Số tiền không được âm';
                  }
                  return null;
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.purple.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Colors.purple,
                      width: 2,
                    ),
                  ),
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.savings_rounded,
                      color: Colors.purple,
                      size: 18,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  if (currentAmount > 0) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _deleteCategoryBudget(budgetId, category.id),
                        icon: const Icon(
                          Icons.delete_rounded,
                          size: 18,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Xóa',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _saveCategoryBudget(
                        budgetId,
                        category.id,
                        controller.text,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Lưu',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<double> _getCategoryBudgetSuggestions(String categoryName) {
    switch (categoryName.toLowerCase()) {
      case 'ăn uống':
      case 'thực phẩm':
        return [300000, 500000, 800000, 1000000, 1500000, 2000000];
      case 'di chuyển':
      case 'xe cộ':
      case 'giao thông':
        return [200000, 400000, 600000, 1000000, 1500000, 2000000];
      case 'mua sắm':
      case 'quần áo':
        return [500000, 1000000, 1500000, 2000000, 3000000, 5000000];
      case 'giải trí':
      case 'vui chơi':
        return [200000, 500000, 800000, 1000000, 1500000, 2000000];
      case 'hóa đơn':
      case 'tiện ích':
        return [500000, 800000, 1000000, 1500000, 2000000, 2500000];
      case 'y tế':
      case 'sức khỏe':
        return [300000, 500000, 1000000, 1500000, 2000000, 3000000];
      case 'học tập':
      case 'giáo dục':
        return [500000, 1000000, 2000000, 3000000, 5000000, 8000000];
      default:
        return [200000, 500000, 1000000, 1500000, 2000000, 3000000];
    }
  }

  void _showBudgetTemplateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sao chép ngân sách'),
        content: const Text('Chọn tháng để sao chép ngân sách hiện tại:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement budget template functionality
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tính năng sao chép ngân sách sẽ sớm ra mắt!'),
                ),
              );
            },
            child: const Text('Chọn tháng'),
          ),
        ],
      ),
    );
  }

  void _showDeleteBudgetDialog(Budget budget) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Xác nhận xóa', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa toàn bộ ngân sách tháng này không?\n\nHành động này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => _deleteBudget(budget),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Xóa ngân sách'),
          ),
        ],
      ),
    );
  }

  void _showBudgetAnalytics() {
    // This would show detailed budget analytics
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.analytics_rounded,
                color: Colors.blue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Phân tích ngân sách'),
          ],
        ),
        content: const Text('Tính năng phân tích chi tiết sẽ sớm ra mắt!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _saveTotalBudget(Budget? existingBudget, String amountText) async {
    final amount = parseAmount(amountText);
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập số tiền hợp lệ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final budget = Budget(
        id: existingBudget?.id ?? '',
        ownerId: userProvider.currentUser!.uid,
        month: _selectedMonth,
        totalAmount: amount,
        categoryAmounts: existingBudget?.categoryAmounts ?? {},
      );

      await _databaseService.saveBudget(budget);
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 12),
              Text(
                existingBudget == null
                    ? 'Đã tạo ngân sách thành công'
                    : 'Đã cập nhật ngân sách thành công',
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi lưu ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _saveCategoryBudget(
    String budgetId,
    String categoryId,
    String amountText,
  ) async {
    final amount = parseAmount(amountText);

    if (amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số tiền không được âm'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      if (budgetId.isEmpty) {
        // Create new budget if doesn't exist
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final budget = Budget(
          id: '',
          ownerId: userProvider.currentUser!.uid,
          month: _selectedMonth,
          totalAmount: 0,
          categoryAmounts: {categoryId: amount},
        );
        await _databaseService.saveBudget(budget);
      } else {
        await _databaseService.setCategoryBudget(budgetId, categoryId, amount);
      }

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 12),
              const Text('Đã cập nhật ngân sách danh mục'),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi cập nhật ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteCategoryBudget(String budgetId, String categoryId) async {
    try {
      await _databaseService.setCategoryBudget(budgetId, categoryId, 0);
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 12),
              const Text('Đã xóa ngân sách danh mục'),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi xóa ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _deleteBudget(Budget budget) async {
    try {
      await FirebaseDatabase.instance
          .ref()
          .child('budgets')
          .child(budget.id)
          .remove();

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 12),
              const Text('Đã xóa ngân sách thành công'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi xóa ngân sách: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
