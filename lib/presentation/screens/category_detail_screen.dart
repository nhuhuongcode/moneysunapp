// lib/presentation/screens/_category_detail_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';

class CategoryDetailScreen extends StatefulWidget {
  final Category category;
  final DateTime? startDate;
  final DateTime? endDate;

  const CategoryDetailScreen({
    super.key,
    required this.category,
    this.startDate,
    this.endDate,
  });

  @override
  State<CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<CategoryDetailScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _statsAnimationController;
  late Animation<double> _statsAnimation;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _selectedPeriod = '30_days';

  @override
  void initState() {
    super.initState();

    if (widget.startDate != null && widget.endDate != null) {
      _startDate = widget.startDate!;
      _endDate = widget.endDate!;
      _selectedPeriod = 'custom';
    }

    _tabController = TabController(length: 3, vsync: this);

    _statsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _statsAnimation = CurvedAnimation(
      parent: _statsAnimationController,
      curve: Curves.easeOutCubic,
    );

    _statsAnimationController.forward();

    // Load transactions for this category
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategoryTransactions();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _statsAnimationController.dispose();
    super.dispose();
  }

  void _loadCategoryTransactions() {
    context.read<TransactionProvider>().loadTransactions(
      startDate: _startDate,
      endDate: _endDate,
      categoryId: widget.category.id,
      forceRefresh: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Header with category info and stats
          _buildCategoryHeader(),

          // Period selector
          _buildPeriodSelector(),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildTransactionsTab(),
                _buildAnalyticsTab(),
              ],
            ),
          ),
        ],
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
      title: Text(
        widget.category.name,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'edit',
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('Chỉnh sửa danh mục'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.download_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('Xuất dữ liệu'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('Chia sẻ thống kê'),
                  ],
                ),
              ),
            ],
            onSelected: _handleMenuAction,
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: _buildTabBar(),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: _getCategoryColor(),
          borderRadius: BorderRadius.circular(23),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: _getCategoryColor(),
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        dividerColor: Colors.transparent,
        indicatorPadding: const EdgeInsets.all(2),
        tabs: const [
          Tab(text: 'Tổng quan'),
          Tab(text: 'Giao dịch'),
          Tab(text: 'Phân tích'),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader() {
    return AnimatedBuilder(
      animation: _statsAnimation,
      builder: (context, child) {
        return FadeTransition(
          opacity: _statsAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(_statsAnimation),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _getCategoryColor(),
                    _getCategoryColor().withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _getCategoryColor().withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
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
                          widget.category.iconCodePoint != null
                              ? IconData(
                                  widget.category.iconCodePoint!,
                                  fontFamily: 'MaterialIcons',
                                )
                              : (widget.category.isShared
                                    ? Icons.people_rounded
                                    : Icons.category_rounded),
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.category.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    widget.category.isShared
                                        ? 'CHUNG'
                                        : 'CÁ NHÂN',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  widget.category.type == 'income'
                                      ? 'Thu nhập'
                                      : 'Chi tiêu',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Quick stats
                  Consumer<TransactionProvider>(
                    builder: (context, transactionProvider, child) {
                      final transactions = transactionProvider.transactions
                          .where((t) => t.categoryId == widget.category.id)
                          .toList();

                      return _buildQuickStats(transactions);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickStats(List<TransactionModel> transactions) {
    final totalAmount = transactions.fold(0.0, (sum, t) => sum + t.amount);
    final avgAmount = transactions.isNotEmpty
        ? totalAmount / transactions.length
        : 0.0;
    final thisMonth = transactions.where((t) {
      final now = DateTime.now();
      return t.date.month == now.month && t.date.year == now.year;
    }).length;

    return Row(
      children: [
        _buildStatCard(
          'Tổng cộng',
          NumberFormat.currency(
            locale: 'vi_VN',
            symbol: '₫',
          ).format(totalAmount),
          Icons.account_balance_wallet_rounded,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          'Giao dịch',
          '${transactions.length}',
          Icons.receipt_long_rounded,
        ),
        const SizedBox(width: 12),
        _buildStatCard('Tháng này', '$thisMonth', Icons.calendar_today_rounded),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPeriodChip('7_days', '7 ngày'),
                  _buildPeriodChip('30_days', '30 ngày'),
                  _buildPeriodChip('90_days', '3 tháng'),
                  _buildPeriodChip('1_year', '1 năm'),
                  _buildPeriodChip('custom', 'Tùy chọn'),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              _loadCategoryTransactions();
            },
            tooltip: 'Làm mới dữ liệu',
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String period, String label) {
    final isSelected = _selectedPeriod == period;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          if (selected) {
            setState(() {
              _selectedPeriod = period;
              _updateDateRange(period);
            });
            _loadCategoryTransactions();
          }
        },
        selectedColor: _getCategoryColor().withOpacity(0.2),
        checkmarkColor: _getCategoryColor(),
        labelStyle: TextStyle(
          color: isSelected ? _getCategoryColor() : null,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Consumer<TransactionProvider>(
      builder: (context, transactionProvider, child) {
        final transactions = transactionProvider.transactions
            .where((t) => t.categoryId == widget.category.id)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary cards
              _buildSummaryCards(transactions),

              const SizedBox(height: 20),

              // Sub-categories breakdown
              if (widget.category.subCategories.isNotEmpty)
                _buildSubCategoriesBreakdown(transactions),

              const SizedBox(height: 20),

              // Recent transactions preview
              _buildRecentTransactionsPreview(transactions),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryCards(List<TransactionModel> transactions) {
    final totalAmount = transactions.fold(0.0, (sum, t) => sum + t.amount);
    final avgAmount = transactions.isNotEmpty
        ? totalAmount / transactions.length
        : 0.0;

    // Calculate this month vs last month
    final now = DateTime.now();
    final thisMonth = transactions
        .where((t) => t.date.month == now.month && t.date.year == now.year)
        .fold(0.0, (sum, t) => sum + t.amount);

    final lastMonth = transactions
        .where(
          (t) =>
              t.date.month == (now.month == 1 ? 12 : now.month - 1) &&
              t.date.year == (now.month == 1 ? now.year - 1 : now.year),
        )
        .fold(0.0, (sum, t) => sum + t.amount);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Tổng số tiền',
                totalAmount,
                Icons.account_balance_wallet_rounded,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Trung bình',
                avgAmount,
                Icons.analytics_rounded,
                Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildComparisonCard(
                'Tháng này',
                thisMonth,
                lastMonth,
                Icons.calendar_today_rounded,
                Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSummaryCard(
                'Giao dịch',
                transactions.length.toDouble(),
                Icons.receipt_rounded,
                Colors.purple,
                isCount: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    double value,
    IconData icon,
    Color color, {
    bool isCount = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Icon(Icons.trending_up, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isCount
                ? value.toInt().toString()
                : NumberFormat.currency(
                    locale: 'vi_VN',
                    symbol: '₫',
                  ).format(value),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard(
    String title,
    double currentValue,
    double previousValue,
    IconData icon,
    Color color,
  ) {
    final difference = currentValue - previousValue;
    final isIncrease = difference > 0;
    final percentageChange = previousValue != 0
        ? (difference / previousValue) * 100
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Icon(
                isIncrease ? Icons.trending_up : Icons.trending_down,
                color: isIncrease ? Colors.green : Colors.red,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            NumberFormat.currency(
              locale: 'vi_VN',
              symbol: '₫',
            ).format(currentValue),
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${isIncrease ? '+' : ''}${percentageChange.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: isIncrease ? Colors.green : Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'so với tháng trước',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubCategoriesBreakdown(List<TransactionModel> transactions) {
    if (widget.category.subCategories.isEmpty) return const SizedBox.shrink();

    // Group transactions by sub-category
    final subCategoryAmounts = <String, double>{};
    for (final transaction in transactions) {
      final subCatId = transaction.subCategoryId ?? 'uncategorized';
      subCategoryAmounts[subCatId] =
          (subCategoryAmounts[subCatId] ?? 0) + transaction.amount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Phân bổ theo danh mục con',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...widget.category.subCategories.entries.map((entry) {
          final amount = subCategoryAmounts[entry.key] ?? 0;
          final totalAmount = subCategoryAmounts.values.fold(
            0.0,
            (sum, val) => sum + val,
          );
          final percentage = totalAmount > 0
              ? (amount / totalAmount) * 100
              : 0.0;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.value,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        NumberFormat.currency(
                          locale: 'vi_VN',
                          symbol: '₫',
                        ).format(amount),
                        style: TextStyle(
                          color: _getCategoryColor(),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildTransactionsTab() {
    return Consumer<TransactionProvider>(
      builder: (context, transactionProvider, child) {
        final transactions = transactionProvider.transactions
            .where((t) => t.categoryId == widget.category.id)
            .toList();

        if (transactions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long_outlined,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'Chưa có giao dịch nào',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Trong khoảng thời gian đã chọn',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            return _buildTransactionCard(transaction);
          },
        );
      },
    );
  }

  Widget _buildTransactionCard(TransactionModel transaction) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getCategoryColor().withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getTransactionIcon(transaction.type),
            color: _getCategoryColor(),
            size: 24,
          ),
        ),
        title: Text(
          transaction.description.isNotEmpty
              ? transaction.description
              : 'Giao dịch',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              DateFormat('dd/MM/yyyy - HH:mm').format(transaction.date),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            if (transaction.subCategoryName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                transaction.subCategoryName,
                style: TextStyle(
                  color: _getCategoryColor(),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        trailing: AmountDisplayWidget(
          amount: transaction.amount,
          currency: 'VND',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          isNegative: transaction.type == TransactionType.expense,
        ),
      ),
    );
  }

  Widget _buildRecentTransactionsPreview(List<TransactionModel> transactions) {
    final recentTransactions = transactions.take(5).toList();

    if (recentTransactions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Giao dịch gần đây',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _tabController.animateTo(1),
              child: const Text('Xem tất cả'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...recentTransactions
            .map((transaction) => _buildTransactionCard(transaction))
            .toList(),
      ],
    );
  }

  Widget _buildAnalyticsTab() {
    return Consumer<TransactionProvider>(
      builder: (context, transactionProvider, child) {
        final transactions = transactionProvider.transactions
            .where((t) => t.categoryId == widget.category.id)
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Spending pattern analysis
              _buildSpendingPatternAnalysis(transactions),

              const SizedBox(height: 20),

              // Monthly trend
              _buildMonthlyTrendAnalysis(transactions),

              const SizedBox(height: 20),

              // Time-based analysis
              _buildTimeBasedAnalysis(transactions),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSpendingPatternAnalysis(List<TransactionModel> transactions) {
    // Analyze spending patterns
    final dailyAmounts = <int, double>{};
    for (final transaction in transactions) {
      final day = transaction.date.day;
      dailyAmounts[day] = (dailyAmounts[day] ?? 0) + transaction.amount;
    }

    final avgDaily = dailyAmounts.values.isNotEmpty
        ? dailyAmounts.values.reduce((a, b) => a + b) / dailyAmounts.length
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phân tích xu hướng',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildAnalyticsItem(
                  'Trung bình/ngày',
                  NumberFormat.currency(
                    locale: 'vi_VN',
                    symbol: '₫',
                  ).format(avgDaily),
                  Icons.today_rounded,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAnalyticsItem(
                  'Tần suất',
                  '${(transactions.length / 30).toStringAsFixed(1)}/ngày',
                  Icons.repeat_rounded,
                  Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsItem(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(color: color, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendAnalysis(List<TransactionModel> transactions) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Xu hướng theo tháng',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Biểu đồ xu hướng sẽ được hiển thị ở đây',
            style: TextStyle(color: Colors.grey.shade600),
          ),
          // TODO: Implement chart widget
        ],
      ),
    );
  }

  Widget _buildTimeBasedAnalysis(List<TransactionModel> transactions) {
    // Analyze by hour of day
    final hourlyData = <int, int>{};
    for (final transaction in transactions) {
      final hour = transaction.date.hour;
      hourlyData[hour] = (hourlyData[hour] ?? 0) + 1;
    }

    final peakHour = hourlyData.entries.isNotEmpty
        ? hourlyData.entries.reduce((a, b) => a.value > b.value ? a : b).key
        : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Phân tích theo thời gian',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            'Giờ cao điểm: ${peakHour}:00',
            style: TextStyle(
              color: _getCategoryColor(),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bạn thường thực hiện giao dịch vào khoảng ${peakHour}:00',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // Helper methods
  Color _getCategoryColor() {
    return widget.category.isShared ? Colors.orange : Colors.blue;
  }

  IconData _getTransactionIcon(TransactionType type) {
    switch (type) {
      case TransactionType.income:
        return Icons.add_circle_rounded;
      case TransactionType.expense:
        return Icons.remove_circle_rounded;
      case TransactionType.transfer:
        return Icons.swap_horiz_rounded;
    }
  }

  void _updateDateRange(String period) {
    final now = DateTime.now();
    switch (period) {
      case '7_days':
        _startDate = now.subtract(const Duration(days: 7));
        _endDate = now;
        break;
      case '30_days':
        _startDate = now.subtract(const Duration(days: 30));
        _endDate = now;
        break;
      case '90_days':
        _startDate = now.subtract(const Duration(days: 90));
        _endDate = now;
        break;
      case '1_year':
        _startDate = now.subtract(const Duration(days: 365));
        _endDate = now;
        break;
      case 'custom':
        _showDateRangePicker();
        break;
    }
  }

  void _showDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadCategoryTransactions();
    }
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'edit':
        // Navigate to edit category screen
        break;
      case 'export':
        // Export category data
        break;
      case 'share':
        // Share category statistics
        break;
    }
  }
}
