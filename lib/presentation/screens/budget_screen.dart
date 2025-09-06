// lib/presentation/screens/enhanced_budget_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/enhanced_budget_service.dart';
import 'package:moneysun/data/services/enhanced_category_service.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen>
    with TickerProviderStateMixin {
  final EnhancedBudgetService _budgetService = EnhancedBudgetService();
  final EnhancedCategoryService _categoryService = EnhancedCategoryService();
  final DatabaseService _databaseService = DatabaseService();

  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  BudgetType _selectedBudgetType = BudgetType.personal;
  
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
    final currencyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(userProvider),
      body: AnimatedBuilder(
        animation: _slideAnimation,
        builder: (context, child) {
          return StreamBuilder<List<Budget>>(
            stream: _budgetService.getBudgetsWithOwnershipStream(
              userProvider,
              month: _selectedMonth,
              budgetType: _selectedBudgetType,
            ),
            builder: (context, budgetSnapshot) {
              return FutureBuilder<ReportData>(
                future: _getActualSpendingData(userProvider),
                builder: (context, actualSnapshot) {
                  if (!actualSnapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final actualData = actualSnapshot.data!;
                  final budget = budgetSnapshot.data?.firstOrNull;
                  
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {});
                    },
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Enhanced Month Header with Budget Type Selector
                          FadeTransition(
                            opacity: _slideAnimation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, -0.3),
                                end: Offset.zero,
                              ).animate(_slideAnimation),
                              child: _buildEnhancedMonthHeader(userProvider),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Budget Type Selector (if user has partner)
                          if (userProvider.hasPartner) ...[
                            FadeTransition(
                              opacity: _slideAnimation,
                              child: _buildBudgetTypeSelector(userProvider),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Budget Overview Card
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
                                userProvider,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Category Budget List
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
                                userProvider,
                              ),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Smart Recommendations (if no budget exists)
                          if (budget == null)
                            FadeTransition(
                              opacity: _slideAnimation,
                              child: _buildSmartRecommendations(userProvider),
                            ),

                          const SizedBox(height: 24),

                          // Action Buttons
                          FadeTransition(
                            opacity: _slideAnimation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0, 0.3),
                                end: Offset.zero,
                              ).animate(_slideAnimation),
                              child: _buildEnhancedActionButtons(budget, userProvider),
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

  PreferredSizeWidget _buildAppBar(UserProvider userProvider) {
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
      title: Row(
        children: [
          const Text(
            'Ngân sách',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          if (userProvider.hasPartner) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _selectedBudgetType == BudgetType.shared
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedBudgetType == BudgetType.shared
                      ? Colors.orange.withOpacity(0.3)
                      : Colors.blue.withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _selectedBudgetType == BudgetType.shared
                        ? Icons.people_rounded
                        : Icons.person_rounded,
                    size: 14,
                    color: _selectedBudgetType == BudgetType.shared
                        ? Colors.orange.shade700
                        : Colors.blue.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _selectedBudgetType == BudgetType.shared ? 'CHUNG' : 'CÁ NHÂN',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _selectedBudgetType == BudgetType.shared
                          ? Colors.orange.shade700
                          : Colors.blue.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
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
          child: PopupMenuButton(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: const Row(
                  children: [
                    Icon(Icons.analytics_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('Phân tích ngân sách'),
                  ],
                ),
                onTap: () => _showBudgetAnalytics(userProvider),
              ),
              PopupMenuItem(
                child: const Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('Sao chép từ tháng khác'),
                  ],
                ),
                onTap: () => _showCopyBudgetDialog(userProvider),
              ),
              if (userProvider.hasPartner)
                PopupMenuItem(
                  child: const Row(
                    children: [
                      Icon(Icons.compare_arrows_rounded, size: 18),
                      SizedBox(width: 12),
                      Text('So sánh cá nhân vs chung'),
                    ],
                  ),
                  onTap: () => _showBudgetComparison(userProvider),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnhancedMonthHeader(UserProvider userProvider) {
    final date = DateFormat('yyyy-MM').parse(_selectedMonth);
    final displayMonth = DateFormat('MMMM yyyy', 'vi_VN').format(date);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _selectedBudgetType == BudgetType.shared
              ? [Colors.orange.shade600, Colors.orange.shade400]
              : [Colors.indigo.shade600, Colors.indigo.shade400],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (_selectedBudgetType == BudgetType.shared
                ? Colors.orange
                : Colors.indigo).withOpacity(0.3),
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
                child: Icon(
                  _selectedBudgetType == BudgetType.shared
                      ? Icons.people_rounded
                      : Icons.calendar_month_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ngân sách ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"}',
                      style: const TextStyle(
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
                    if (_selectedBudgetType == BudgetType.shared && userProvider.hasPartner)
                      Text(
                        'Với ${userProvider.partnerDisplayName ?? "đối tác"}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 14,
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

  Widget _buildBudgetTypeSelector(UserProvider userProvider) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildBudgetTypeOption(
              BudgetType.personal,
              Icons.person_rounded,
              'Cá nhân',
              Colors.blue.shade600,
              'Ngân sách riêng của bạn',
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildBudgetTypeOption(
              BudgetType.shared,
              Icons.people_rounded,
              'Chung',
              Colors.orange.shade600,
              'Ngân sách chung với ${userProvider.partnerDisplayName ?? "đối tác"}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBudgetTypeOption(
    BudgetType type,
    IconData icon,
    String label,
    Color color,
    String description,
  ) {
    final isSelected = _selectedBudgetType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedBudgetType = type;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [color.withOpacity(0.8), color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : color,
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white.withOpacity(0.8) : Colors.grey,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedBudgetOverviewCard(
    Budget? budget,
    ReportData actualData,
    NumberFormat formatter,
    UserProvider userProvider,
  ) {
    final totalBudget = budget?.totalAmount ?? 0.0;
    final totalSpent = actualData.totalExpense;
    final remaining = totalBudget - totalSpent;
    final spentPercentage = totalBudget > 0 ? (totalSpent / totalBudget * 100) : 0.0;

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tổng quan ngân sách',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    if (budget != null)
                      Text(
                        'Được tạo bởi ${budget.createdBy == userProvider.currentUser?.uid ? "bạn" : userProvider.partnerDisplayName ?? "đối tác"}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          if (budget != null) ...[
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
                          value: (spentPercentage / 100 * _progressAnimation.value).clamp(0.0, 1.0),
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
                            '${formatter.format(remaining)} còn lại',
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
                    remaining >= 0 ? Icons.trending_up_rounded : Icons.warning_rounded,
                    formatter,
                  ),
                ),
              ],
            ),
          ] else ...[
            // No budget created yet
            Container(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(
                    _selectedBudgetType == BudgetType.shared
                        ? Icons.people_outline_rounded
                        : Icons.person_outline_rounded,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _selectedBudgetType == BudgetType.shared
                        ? 'Chưa có ngân sách chung'
                        : 'Chưa có ngân sách cá nhân',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tạo ngân sách để theo dõi chi tiêu hiệu quả',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEnhancedCategoryBudgetList(
    Budget? budget,
    ReportData actualData,
    NumberFormat formatter,
    UserProvider userProvider,
  ) {
    return StreamBuilder<List<Category>>(
      stream: _categoryService.getCategoriesWithOwnershipStream(
        userProvider,
        type: 'expense',
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allCategories = snapshot.data!;
        
        // Filter categories based on budget type
        final filteredCategories = allCategories.where((category) {
          if (_selectedBudgetType == BudgetType.shared) {
            return category.ownershipType == CategoryOwnershipType.shared;
          } else {
            return category.ownershipType == CategoryOwnershipType.personal;
          }
        }).toList();

        if (filteredCategories.isEmpty) {
          return _buildEmptyCategoriesState(userProvider);
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
                        color: (_selectedBudgetType == BudgetType.shared
                            ? Colors.orange
                            : Colors.purple).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.category_rounded,
                        color: _selectedBudgetType == BudgetType.shared
                            ? Colors.orange
                            : Colors.purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chi tiết theo danh mục',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${filteredCategories.length} danh mục ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Categories List
              ...filteredCategories.asMap().entries.map((entry) {
                final index = entry.key;
                final category = entry.value;
                final budgetAmount = budget?.categoryAmounts[category.id] ?? 0.0;
                final actualAmount = actualData.expenseByCategory[category] ?? 0.0;
                final percentage = budgetAmount > 0 ? (actualAmount / budgetAmount * 100) : 0.0;

                return AnimatedContainer(
                  duration: Duration(milliseconds: 300 + (index * 100)),
                  margin: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: index == filteredCategories.length - 1 ? 20 : 12,
                  ),
                  child: _buildEnhancedCategoryBudgetItem(
                    category,
                    budgetAmount,
                    actualAmount,
                    percentage,
                    formatter,
                    budget?.id ?? '',
                    userProvider,
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
    UserProvider userProvider,
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
          // Category Header with Ownership Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: progressColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  category.isShared ? Icons.people_rounded : Icons.person_rounded,
                  color: progressColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (category.isShared)
                      Text(
                        'Danh mục chung',
                        style: TextStyle(
                          color: Colors.orange.shade600,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: hasExceeded ? Colors.red.withOpacity(0.1) : progressColor.withOpacity(0.1),
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
              onPressed: () => _showSetBudgetDialog(
                category,
                budgetAmount,
                budgetId,
                userProvider,
              ),
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

  Widget _buildSmartRecommendations(UserProvider userProvider) {
    return FutureBuilder<Map<String, double>>(
      future: _budgetService.getBudgetRecommendations(
        _selectedMonth,
        _selectedBudgetType,
        userProvider,
      ),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final recommendations = snapshot.data!;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.blue.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.lightbulb_rounded,
                      color: Colors.blue,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Gợi ý ngân sách thông minh',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Dựa trên chi tiêu 3 tháng gần đây',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _applyRecommendations(recommendations, userProvider),
                icon: const Icon(Icons.auto_fix_high_rounded),
                label: const Text('Áp dụng gợi ý'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Helper methods continue in next part...