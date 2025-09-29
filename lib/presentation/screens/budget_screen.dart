// lib/presentation/screens/budget_screen_complete.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:moneysun/data/models/budget_model.dart'
    hide BudgetAnalytics, CategoryBudgetAnalytics;
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/providers/budget_provider.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';

class BudgetScreenComplete extends StatefulWidget {
  const BudgetScreenComplete({super.key});

  @override
  State<BudgetScreenComplete> createState() => _BudgetScreenCompleteState();
}

class _BudgetScreenCompleteState extends State<BudgetScreenComplete>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late AnimationController _progressController;
  late Animation<double> _slideAnimation;
  late Animation<double> _progressAnimation;

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
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Month Header
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

                          // Budget Type Selector
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
                                child: _buildBudgetOverviewCard(
                                  budgetProvider,
                                  transactionProvider,
                                  userProvider,
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 24),

                          // Category Budget Section
                          AnimatedBuilder(
                            animation: _slideAnimation,
                            builder: (context, child) {
                              return FadeTransition(
                                opacity: _slideAnimation,
                                child: _buildCategoryBudgetSection(
                                  budgetProvider,
                                  categoryProvider,
                                  transactionProvider,
                                  userProvider,
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
                                child: _buildActionButtons(
                                  budgetProvider,
                                  userProvider,
                                  categoryProvider,
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
          Text(
            'Ngân sách',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(width: 12),
          _buildBudgetTypeBadge(),
        ],
      ),
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
                itemBuilder: (context) => _buildMenuItems(connectionStatus),
                onSelected: _handleMenuSelection,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBudgetTypeBadge() {
    return Container(
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
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(
    ConnectionStatusProvider connectionStatus,
  ) {
    return [
      PopupMenuItem<String>(
        enabled: false,
        child: Row(
          children: [
            Icon(
              connectionStatus.isOnline ? Icons.cloud_done : Icons.cloud_off,
              size: 18,
              color: connectionStatus.statusColor,
            ),
            const SizedBox(width: 12),
            Text(connectionStatus.statusMessage),
          ],
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'analytics',
        child: Row(
          children: [
            Icon(Icons.analytics_rounded, size: 18),
            SizedBox(width: 12),
            Text('Phân tích ngân sách'),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        value: 'copy_budget',
        child: Row(
          children: [
            Icon(Icons.copy_rounded, size: 18),
            SizedBox(width: 12),
            Text('Sao chép từ tháng khác'),
          ],
        ),
      ),
      const PopupMenuItem<String>(
        value: 'history',
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 18),
            SizedBox(width: 12),
            Text('Lịch sử ngân sách'),
          ],
        ),
      ),
    ];
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'analytics':
        _showBudgetAnalytics();
        break;
      case 'copy_budget':
        _showCopyBudgetDialog();
        break;
      case 'history':
        _showBudgetHistory();
        break;
    }
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
              'Với ${userProvider.partnerDisplayName ?? "đối tác"}',
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
        _progressController.reset();
        _progressController.forward();
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
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    if (budget == null) {
      return _buildNoBudgetCard(userProvider);
    }

    return FutureBuilder<BudgetAnalytics?>(
      future: budgetProvider.getBudgetAnalytics(budget.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingCard();
        }

        final analytics = snapshot.data;
        if (analytics == null) {
          return _buildNoBudgetCard(userProvider);
        }

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
              _buildOverviewHeader(budget, userProvider),
              const SizedBox(height: 24),
              _buildProgressSection(analytics),
              const SizedBox(height: 24),
              _buildStatsRow(analytics, currencyFormatter),
              if (analytics.alerts.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildAlertsSection(analytics),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewHeader(Budget budget, UserProvider userProvider) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.pie_chart_rounded,
            color: Colors.purple,
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
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                'Được tạo bởi ${budget.createdBy == userProvider.currentUser?.uid ? "bạn" : userProvider.partnerDisplayName ?? "đối tác"}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressSection(BudgetAnalytics analytics) {
    final progressColor = _getProgressColor(analytics.spentPercentage);

    return AnimatedBuilder(
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
                      (analytics.spentPercentage /
                              100 *
                              _progressAnimation.value)
                          .clamp(0.0, 1.0),
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(analytics.spentPercentage * _progressAnimation.value).toStringAsFixed(1)}% đã sử dụng',
                  style: TextStyle(
                    color: progressColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(analytics.totalRemaining)} còn lại',
                  style: TextStyle(
                    color: analytics.totalRemaining >= 0
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatsRow(
    BudgetAnalytics analytics,
    NumberFormat currencyFormatter,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Ngân sách',
            analytics.totalBudget,
            Colors.blue,
            Icons.account_balance_wallet_rounded,
            currencyFormatter,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Đã chi',
            analytics.totalSpent,
            Colors.red,
            Icons.trending_down_rounded,
            currencyFormatter,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Còn lại',
            analytics.totalRemaining,
            analytics.totalRemaining >= 0 ? Colors.green : Colors.red,
            analytics.totalRemaining >= 0
                ? Icons.trending_up_rounded
                : Icons.warning_rounded,
            currencyFormatter,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
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
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsSection(BudgetAnalytics analytics) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text(
                'Cảnh báo (${analytics.alerts.length})',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...analytics.alerts.take(3).map((alert) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 6,
                    color: _getAlertColor(alert.severity),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      alert.message,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
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

            return FutureBuilder<CategoryBudgetAnalytics?>(
              future: _getCategoryAnalytics(
                budget?.id,
                category.id,
                budgetProvider,
              ),
              builder: (context, snapshot) {
                final analytics = snapshot.data;
                return AnimatedContainer(
                  duration: Duration(milliseconds: 300 + (index * 100)),
                  margin: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    bottom: index == categories.length - 1 ? 20 : 12,
                  ),
                  child: _buildCategoryBudgetItem(
                    category,
                    analytics,
                    budget?.id ?? '',
                    budgetProvider,
                  ),
                );
              },
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildCategoryBudgetItem(
    Category category,
    CategoryBudgetAnalytics? analytics,
    String budgetId,
    BudgetProvider budgetProvider,
  ) {
    if (analytics == null) {
      return const SizedBox.shrink();
    }

    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );
    final progressColor = _getProgressColor(analytics.spentPercentage);
    final hasExceeded = analytics.spentPercentage > 100;

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
                  '${analytics.spentPercentage.toStringAsFixed(0)}%',
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
                widthFactor: (analytics.spentPercentage / 100).clamp(0.0, 1.0),
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
              _buildAmountColumn(
                'Đã chi',
                analytics.spentAmount,
                progressColor,
                currencyFormatter,
              ),
              _buildAmountColumn(
                'Ngân sách',
                analytics.budgetAmount,
                Colors.grey.shade700,
                currencyFormatter,
              ),
              _buildAmountColumn(
                hasExceeded ? 'Vượt' : 'Còn lại',
                analytics.remainingAmount.abs(),
                hasExceeded ? Colors.red : Colors.green,
                currencyFormatter,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showSetBudgetDialog(
                category,
                analytics.budgetAmount,
                budgetId,
                budgetProvider,
              ),
              icon: Icon(
                analytics.budgetAmount > 0
                    ? Icons.edit_rounded
                    : Icons.add_rounded,
                size: 18,
                color: progressColor,
              ),
              label: Text(
                analytics.budgetAmount > 0
                    ? 'Chỉnh sửa ngân sách'
                    : 'Đặt ngân sách',
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

  Widget _buildAmountColumn(
    String label,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
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

  Widget _buildActionButtons(
    BudgetProvider budgetProvider,
    UserProvider userProvider,
    CategoryProvider categoryProvider,
  ) {
    final budget = budgetProvider.budgets.isEmpty
        ? null
        : budgetProvider.budgets.first;

    if (budget == null) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _showCreateBudgetDialog(
            budgetProvider,
            userProvider,
            categoryProvider,
          ),
          icon: const Icon(Icons.add_circle_rounded),
          label: Text(
            'Tạo ngân sách ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"}',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
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
      );
    }

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _showEditBudgetDialog(
              budget,
              budgetProvider,
              userProvider,
              categoryProvider,
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
            onPressed: () => _showDeleteBudgetDialog(budget, budgetProvider),
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
    );
  }

  Widget _buildNoBudgetCard(UserProvider userProvider) {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
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
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Center(child: CircularProgressIndicator()),
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

  Widget _buildMonthNavButton(IconData icon, VoidCallback onTap) {
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

  // Helper Methods
  Color _getProgressColor(double percentage) {
    if (percentage < 50) return Colors.green;
    if (percentage < 80) return Colors.orange;
    return Colors.red;
  }

  Color _getAlertColor(BudgetAlertSeverity severity) {
    switch (severity) {
      case BudgetAlertSeverity.low:
        return Colors.blue;
      case BudgetAlertSeverity.medium:
        return Colors.orange;
      case BudgetAlertSeverity.high:
        return Colors.red;
      case BudgetAlertSeverity.critical:
        return Colors.red.shade800;
    }
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

  Future<CategoryBudgetAnalytics?> _getCategoryAnalytics(
    String? budgetId,
    String categoryId,
    BudgetProvider budgetProvider,
  ) async {
    if (budgetId == null) return null;

    final analytics = await budgetProvider.getBudgetAnalytics(budgetId);
    return analytics?.categoryAnalytics[categoryId];
  }

  void _navigateMonth(int delta) {
    final currentDate = DateFormat('yyyy-MM').parse(_selectedMonth);
    final newDate = DateTime(currentDate.year, currentDate.month + delta);
    setState(() {
      _selectedMonth = DateFormat('yyyy-MM').format(newDate);
    });
    _loadBudgetData();
    _progressController.reset();
    _progressController.forward();
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
    _progressController.reset();
    _progressController.forward();
  }

  // Dialog Methods
  void _showCreateBudgetDialog(
    BudgetProvider budgetProvider,
    UserProvider userProvider,
    CategoryProvider categoryProvider,
  ) {
    final categories = _getFilteredCategories(categoryProvider);
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Vui lòng tạo danh mục ${_selectedBudgetType == BudgetType.shared ? "chung" : "cá nhân"} trước',
          ),
          action: SnackBarAction(
            label: 'Tạo danh mục',
            onPressed: () => Navigator.pushNamed(context, '/manage-categories'),
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBudgetFormSheet(
        budgetProvider,
        userProvider,
        categories,
        isEdit: false,
      ),
    );
  }

  void _showEditBudgetDialog(
    Budget budget,
    BudgetProvider budgetProvider,
    UserProvider userProvider,
    CategoryProvider categoryProvider,
  ) {
    final categories = _getFilteredCategories(categoryProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildBudgetFormSheet(
        budgetProvider,
        userProvider,
        categories,
        isEdit: true,
        existingBudget: budget,
      ),
    );
  }

  Widget _buildBudgetFormSheet(
    BudgetProvider budgetProvider,
    UserProvider userProvider,
    List<Category> categories, {
    required bool isEdit,
    Budget? existingBudget,
  }) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEdit ? 'Chỉnh sửa ngân sách' : 'Tạo ngân sách mới',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _BudgetForm(
                  budgetProvider: budgetProvider,
                  userProvider: userProvider,
                  categories: categories,
                  selectedMonth: _selectedMonth,
                  budgetType: _selectedBudgetType,
                  isEdit: isEdit,
                  existingBudget: existingBudget,
                  onSaved: () {
                    Navigator.pop(context);
                    _refreshData();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSetBudgetDialog(
    Category category,
    double currentAmount,
    String budgetId,
    BudgetProvider budgetProvider,
  ) {
    final controller = TextEditingController(
      text: currentAmount > 0 ? currentAmount.toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Đặt ngân sách cho ${category.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SmartAmountInput(
              controller: controller,
              labelText: 'Số tiền ngân sách',
              onChanged: (amount) {},
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount =
                  double.tryParse(
                    controller.text.replaceAll('.', '').replaceAll(',', ''),
                  ) ??
                  0;

              if (amount < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Số tiền không được âm'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                await budgetProvider.setCategoryBudget(
                  budgetId,
                  category.id,
                  amount,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã cập nhật ngân sách'),
                    backgroundColor: Colors.green,
                  ),
                );
                _refreshData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedBudgetType == BudgetType.shared
                  ? Colors.orange
                  : Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Lưu'),
          ),
        ],
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
                _refreshData();
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

  void _showBudgetAnalytics() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tính năng phân tích ngân sách đang phát triển'),
      ),
    );
  }

  void _showCopyBudgetDialog() {
    final budgetProvider = Provider.of<BudgetProvider>(context, listen: false);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sao chép ngân sách'),
        content: const Text(
          'Bạn có muốn sao chép ngân sách từ tháng trước không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final currentDate = DateFormat('yyyy-MM').parse(_selectedMonth);
              final previousMonth = DateTime(
                currentDate.year,
                currentDate.month - 1,
              );
              final previousMonthStr = DateFormat(
                'yyyy-MM',
              ).format(previousMonth);

              try {
                await budgetProvider.copyBudgetFromMonth(
                  previousMonthStr,
                  _selectedMonth,
                  _selectedBudgetType,
                );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã sao chép ngân sách thành công'),
                    backgroundColor: Colors.green,
                  ),
                );
                _refreshData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Lỗi: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Sao chép'),
          ),
        ],
      ),
    );
  }

  void _showBudgetHistory() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tính năng lịch sử ngân sách đang phát triển'),
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

// Budget Form Widget
class _BudgetForm extends StatefulWidget {
  final BudgetProvider budgetProvider;
  final UserProvider userProvider;
  final List<Category> categories;
  final String selectedMonth;
  final BudgetType budgetType;
  final bool isEdit;
  final Budget? existingBudget;
  final VoidCallback onSaved;

  const _BudgetForm({
    required this.budgetProvider,
    required this.userProvider,
    required this.categories,
    required this.selectedMonth,
    required this.budgetType,
    required this.isEdit,
    this.existingBudget,
    required this.onSaved,
  });

  @override
  State<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends State<_BudgetForm> {
  final Map<String, TextEditingController> _controllers = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    for (final category in widget.categories) {
      final amount = widget.existingBudget?.categoryAmounts[category.id] ?? 0.0;
      _controllers[category.id] = TextEditingController(
        text: amount > 0 ? amount.toStringAsFixed(0) : '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Đặt ngân sách cho từng danh mục:',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        ...widget.categories.map((category) {
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            child: SmartAmountInput(
              controller: _controllers[category.id]!,
              labelText: category.name,
              onChanged: (amount) {},
              prefixIcon: Icon(
                category.isShared ? Icons.people_rounded : Icons.person_rounded,
                color: widget.budgetType == BudgetType.shared
                    ? Colors.orange
                    : Colors.blue,
              ),
            ),
          );
        }).toList(),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _saveBudget,
            style: ElevatedButton.styleFrom(
              backgroundColor: widget.budgetType == BudgetType.shared
                  ? Colors.orange
                  : Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    widget.isEdit ? 'Cập nhật ngân sách' : 'Tạo ngân sách',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveBudget() async {
    setState(() => _isLoading = true);

    try {
      final categoryAmounts = <String, double>{};
      double totalAmount = 0;

      for (final entry in _controllers.entries) {
        final amount =
            double.tryParse(
              entry.value.text.replaceAll('.', '').replaceAll(',', ''),
            ) ??
            0;
        if (amount > 0) {
          categoryAmounts[entry.key] = amount;
          totalAmount += amount;
        }
      }

      if (categoryAmounts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vui lòng đặt ngân sách cho ít nhất một danh mục'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      if (widget.isEdit && widget.existingBudget != null) {
        final updatedBudget = widget.existingBudget!.copyWith(
          totalAmount: totalAmount,
          categoryAmounts: categoryAmounts,
          updatedAt: DateTime.now(),
        );
        await widget.budgetProvider.updateBudget(updatedBudget);
      } else {
        await widget.budgetProvider.addBudget(
          month: widget.selectedMonth,
          totalAmount: totalAmount,
          categoryAmounts: categoryAmounts,
          budgetType: widget.budgetType,
          period: BudgetPeriod.monthly,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? 'Đã cập nhật ngân sách thành công'
                : 'Đã tạo ngân sách thành công',
          ),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSaved();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}
