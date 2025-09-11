// lib/presentation/screens/_budget_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/services/budget_provider.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';
import 'package:moneysun/presentation/widgets/category_ownership_selector.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late AnimationController _slideController;
  late AnimationController _progressController;
  late Animation<double> _slideAnimation;
  late Animation<double> _progressAnimation;

  // State variables
  String _selectedMonth = DateFormat('yyyy-MM').format(DateTime.now());
  BudgetType _selectedBudgetType = BudgetType.personal;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadBudgetData();
  }

  void _initializeAnimations() {
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

  void _loadBudgetData() {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    budgetProvider.setMonthFilter(_selectedMonth);
    budgetProvider.setBudgetTypeFilter(_selectedBudgetType);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body:
          Consumer4<
            BudgetProvider,
            CategoryProvider,
            TransactionProvider,
            UserProvider
          >(
            builder:
                (
                  context,
                  budgetProvider,
                  categoryProvider,
                  transactionProvider,
                  userProvider,
                  child,
                ) {
                  return RefreshIndicator(
                    onRefresh: () => _refreshData(),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Month Header with Budget Type Selector
                          AnimatedBuilder(
                            animation: _slideAnimation,
                            builder: (context, child) {
                              return FadeTransition(
                                opacity: _slideAnimation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, -0.3),
                                    end: Offset.zero,
                                  ).animate(_slideAnimation),
                                  child: _buildMonthHeader(userProvider),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          // Budget Type Selector (if user has partner)
                          if (userProvider.hasPartner) ...[
                            AnimatedBuilder(
                              animation: _slideAnimation,
                              builder: (context, child) {
                                return FadeTransition(
                                  opacity: _slideAnimation,
                                  child: _buildBudgetTypeSelector(userProvider),
                                );
                              },
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Budget Overview Card
                          AnimatedBuilder(
                            animation: _slideAnimation,
                            builder: (context, child) {
                              return FadeTransition(
                                opacity: _slideAnimation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(-0.3, 0),
                                    end: Offset.zero,
                                  ).animate(_slideAnimation),
                                  child: _buildBudgetOverviewCard(
                                    budgetProvider,
                                    transactionProvider,
                                    userProvider,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          // Category Budget List or Empty State
                          AnimatedBuilder(
                            animation: _slideAnimation,
                            builder: (context, child) {
                              return FadeTransition(
                                opacity: _slideAnimation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0.3, 0),
                                    end: Offset.zero,
                                  ).animate(_slideAnimation),
                                  child: _buildCategoryBudgetSection(
                                    budgetProvider,
                                    categoryProvider,
                                    transactionProvider,
                                    userProvider,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          // Action Buttons
                          AnimatedBuilder(
                            animation: _slideAnimation,
                            builder: (context, child) {
                              return FadeTransition(
                                opacity: _slideAnimation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.3),
                                    end: Offset.zero,
                                  ).animate(_slideAnimation),
                                  child: _buildActionButtons(
                                    budgetProvider,
                                    userProvider,
                                  ),
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  );
                },
          ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      // Nút back bên trái
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
      // Tiêu đề + loại ngân sách
      title: Row(
        children: [
          Text(
            'Ngân sách',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          // Loại ngân sách hiển thị
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
                  _selectedBudgetType == BudgetType.shared
                      ? 'CHUNG'
                      : 'CÁ NHÂN',
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
      ),
      // Nút menu bên phải
      actions: [
        Consumer<ConnectionStatusProvider>(
          builder: (context, connectionStatus, child) {
            return Container(
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
              child: PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                // Danh sách menu
                itemBuilder: (context) {
                  final List<PopupMenuEntry<String>> items = [];

                  // Hiển thị trạng thái mạng (disabled)
                  items.add(
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Row(
                        children: [
                          Icon(
                            connectionStatus.isOnline
                                ? Icons.cloud_done
                                : Icons.cloud_off,
                            size: 18,
                            color: connectionStatus.statusColor,
                          ),
                          const SizedBox(width: 12),
                          Text(connectionStatus.statusMessage),
                        ],
                      ),
                    ),
                  );

                  items.add(const PopupMenuDivider());

                  // Phân tích ngân sách
                  items.add(
                    PopupMenuItem<String>(
                      value: 'analytics',
                      child: const Row(
                        children: [
                          Icon(Icons.analytics_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Phân tích ngân sách'),
                        ],
                      ),
                    ),
                  );

                  // Sao chép từ tháng khác
                  items.add(
                    PopupMenuItem<String>(
                      value: 'copy_budget',
                      child: const Row(
                        children: [
                          Icon(Icons.copy_rounded, size: 18),
                          SizedBox(width: 12),
                          Text('Sao chép từ tháng khác'),
                        ],
                      ),
                    ),
                  );

                  return items;
                },
                // Xử lý chọn menu
                onSelected: (value) {
                  switch (value) {
                    case 'analytics':
                      _showBudgetAnalytics();
                      break;
                    case 'copy_budget':
                      _showCopyBudgetDialog();
                      break;
                  }
                },
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMonthHeader(UserProvider userProvider) {
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
            color:
                (_selectedBudgetType == BudgetType.shared
                        ? Colors.orange
                        : Colors.indigo)
                    .withOpacity(0.3),
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
                    if (_selectedBudgetType == BudgetType.shared &&
                        userProvider.hasPartner)
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
        _loadBudgetData();
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
            Icon(icon, color: isSelected ? Colors.white : color, size: 24),
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

  Widget _buildBudgetOverviewCard(
    BudgetProvider budgetProvider,
    TransactionProvider transactionProvider,
    UserProvider userProvider,
  ) {
    final budget = budgetProvider.budgets.isEmpty
        ? null
        : budgetProvider.budgets.first;
    final stats = transactionProvider.getStatistics();
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    final totalBudget = budget?.totalAmount ?? 0.0;
    final totalSpent = _getSpentAmount(stats, userProvider);
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tổng quan ngân sách',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
            // Progress Indicator
            AnimatedBuilder(
              animation: _progressAnimation,
              builder: (context, child) {
                return Column(
                  children: [
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
                            '${currencyFormatter.format(remaining)} còn lại',
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
            Row(
              children: [
                Expanded(
                  child: _buildBudgetStatCard(
                    'Ngân sách',
                    totalBudget,
                    Colors.blue,
                    Icons.account_balance_wallet_rounded,
                    currencyFormatter,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildBudgetStatCard(
                    'Đã chi',
                    totalSpent,
                    Colors.red,
                    Icons.trending_down_rounded,
                    currencyFormatter,
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
                    currencyFormatter,
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

  Widget _buildCategoryBudgetSection(
    BudgetProvider budgetProvider,
    CategoryProvider categoryProvider,
    TransactionProvider transactionProvider,
    UserProvider userProvider,
  ) {
    final budget = budgetProvider.budgets.isEmpty
        ? null
        : budgetProvider.budgets.first;
    final categories = _getFilteredCategories(categoryProvider);

    if (categories.isEmpty) {
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        (_selectedBudgetType == BudgetType.shared
                                ? Colors.orange
                                : Colors.purple)
                            .withOpacity(0.1),
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
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${categories.length} danh mục ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"}',
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
          ...categories.asMap().entries.map((entry) {
            final index = entry.key;
            final category = entry.value;
            final budgetAmount = budget?.categoryAmounts[category.id] ?? 0.0;
            final actualAmount = _getCategorySpentAmount(
              category,
              transactionProvider,
            );
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
              child: _buildCategoryBudgetItem(
                category,
                budgetAmount,
                actualAmount,
                percentage,
                budget?.id ?? '',
                budgetProvider,
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildCategoryBudgetItem(
    Category category,
    double budgetAmount,
    double actualAmount,
    double percentage,
    String budgetId,
    BudgetProvider budgetProvider,
  ) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: progressColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  category.isShared
                      ? Icons.people_rounded
                      : Icons.person_rounded,
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
                    currencyFormatter.format(actualAmount),
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
                    currencyFormatter.format(budgetAmount),
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
                    currencyFormatter.format(
                      (budgetAmount - actualAmount).abs(),
                    ),
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
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showSetBudgetDialog(
                category,
                budgetAmount,
                budgetId,
                budgetProvider,
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

  Widget _buildActionButtons(
    BudgetProvider budgetProvider,
    UserProvider userProvider,
  ) {
    final budget = budgetProvider.budgets.isEmpty
        ? null
        : budgetProvider.budgets.first;

    return Column(
      children: [
        if (budget == null) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () =>
                  _showCreateBudgetDialog(budgetProvider, userProvider),
              icon: const Icon(Icons.add_circle_rounded),
              label: Text(
                'Tạo ngân sách ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedBudgetType == BudgetType.shared
                    ? Colors.orange
                    : Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showEditBudgetDialog(
                    budget,
                    budgetProvider,
                    userProvider,
                  ),
                  icon: const Icon(Icons.edit_rounded),
                  label: const Text('Chỉnh sửa'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () =>
                      _showDeleteBudgetDialog(budget, budgetProvider),
                  icon: const Icon(Icons.delete_rounded),
                  label: const Text('Xóa'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildEmptyCategoriesState(UserProvider userProvider) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            _selectedBudgetType == BudgetType.shared
                ? Icons.people_outline_rounded
                : Icons.category_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'Chưa có danh mục ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"} nào',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _selectedBudgetType == BudgetType.shared
                ? 'Tạo danh mục chung với đối tác để bắt đầu'
                : 'Tạo danh mục cá nhân để bắt đầu',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/manage-categories'),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Tạo danh mục ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"}',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedBudgetType == BudgetType.shared
                  ? Colors.orange
                  : Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // Helper widgets
  Widget _buildMonthNavButton(
    IconData icon,
    String tooltip,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
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
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            formatter.format(amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  // Helper methods
  Color _getProgressColor(double percentage) {
    if (percentage < 50) return Colors.green;
    if (percentage < 80) return Colors.orange;
    return Colors.red;
  }

  List<Category> _getFilteredCategories(CategoryProvider categoryProvider) {
    final categories = categoryProvider.expenseCategories;
    return categories.where((category) {
      if (_selectedBudgetType == BudgetType.shared) {
        return category.ownershipType == CategoryOwnershipType.shared;
      } else {
        return category.ownershipType == CategoryOwnershipType.personal;
      }
    }).toList();
  }

  double _getSpentAmount(
    Map<String, dynamic> stats,
    UserProvider userProvider,
  ) {
    if (_selectedBudgetType == BudgetType.shared) {
      // For shared budget, we need to implement shared expense calculation
      // This is a simplified version
      return (stats['totalExpense']?.toDouble() ?? 0.0) * 0.5;
    } else {
      // For personal budget, return total expense (simplified)
      return stats['totalExpense']?.toDouble() ?? 0.0;
    }
  }

  double _getCategorySpentAmount(
    Category category,
    TransactionProvider transactionProvider,
  ) {
    // This is a simplified implementation
    // In practice, you would filter transactions by category and calculate the sum
    return 0.0;
  }

  void _navigateMonth(int delta) {
    final currentDate = DateFormat('yyyy-MM').parse(_selectedMonth);
    final newDate = DateTime(currentDate.year, currentDate.month + delta);
    setState(() {
      _selectedMonth = DateFormat('yyyy-MM').format(newDate);
    });
    _loadBudgetData();
  }

  Future<void> _showMonthPicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateFormat('yyyy-MM').parse(_selectedMonth),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _selectedBudgetType == BudgetType.shared
                  ? Colors.orange
                  : Colors.blue,
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
      _loadBudgetData();
    }
  }

  Future<void> _refreshData() async {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);
    await budgetProvider.loadBudgets(forceRefresh: true);
  }

  // Dialog methods (simplified - would need full implementation)
  void _showCreateBudgetDialog(
    BudgetProvider budgetProvider,
    UserProvider userProvider,
  ) {
    // Implement create budget dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chức năng tạo ngân sách sẽ được implement'),
      ),
    );
  }

  void _showEditBudgetDialog(
    Budget budget,
    BudgetProvider budgetProvider,
    UserProvider userProvider,
  ) {
    // Implement edit budget dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chức năng chỉnh sửa ngân sách sẽ được implement'),
      ),
    );
  }

  void _showDeleteBudgetDialog(Budget budget, BudgetProvider budgetProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc chắn muốn xóa ngân sách ${budget.displayName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await budgetProvider.deleteBudget(budget.id);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã xóa ngân sách thành công'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi khi xóa ngân sách: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showSetBudgetDialog(
    Category category,
    double currentAmount,
    String budgetId,
    BudgetProvider budgetProvider,
  ) {
    // Implement set budget dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Chức năng đặt ngân sách cho ${category.name} sẽ được implement',
        ),
      ),
    );
  }

  void _showBudgetAnalytics() {
    // Navigate to budget analytics screen
    Navigator.pushNamed(context, '/budget-analytics');
  }

  void _showCopyBudgetDialog() {
    // Implement copy budget dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chức năng sao chép ngân sách sẽ được implement'),
      ),
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    _progressController.dispose();
    super.dispose();
  }
}
