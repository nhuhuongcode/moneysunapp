// lib/presentation/screens/_all_transactions_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:moneysun/presentation/widgets/connection_status_banner.dart';

class AllTransactionsScreen extends StatefulWidget {
  final DateTime? initialStartDate;
  final DateTime? initialEndDate;
  final TimeFilter? initialFilter;

  const AllTransactionsScreen({
    super.key,
    this.initialStartDate,
    this.initialEndDate,
    this.initialFilter,
  });

  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Filter state
  TimeFilter _selectedFilter = TimeFilter.thisMonth;
  late DateTime _startDate;
  late DateTime _endDate;

  // UI state
  bool _isInitialized = false;
  String? _searchQuery;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _initializeDateRange();
    _loadInitialData();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );
  }

  void _initializeDateRange() {
    if (widget.initialStartDate != null && widget.initialEndDate != null) {
      _startDate = widget.initialStartDate!;
      _endDate = widget.initialEndDate!;
      _selectedFilter = widget.initialFilter ?? TimeFilter.custom;
    } else {
      _selectedFilter = widget.initialFilter ?? TimeFilter.thisMonth;
      _updateDateRange(_selectedFilter);
    }
  }

  void _loadInitialData() async {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );

    // Apply date filter to transaction provider
    transactionProvider.setDateFilter(_startDate, _endDate);

    // Start animation after a brief delay
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _animationController.forward();
        setState(() {
          _isInitialized = true;
        });
      }
    });
  }

  void _updateDateRange(TimeFilter filter) {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = filter;
      switch (filter) {
        case TimeFilter.thisWeek:
          _startDate = now.subtract(Duration(days: now.weekday - 1));
          _endDate = _startDate.add(const Duration(days: 6));
          break;
        case TimeFilter.thisMonth:
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month + 1, 0);
          break;
        case TimeFilter.thisYear:
          _startDate = DateTime(now.year, 1, 1);
          _endDate = DateTime(now.year, 12, 31);
          break;
        case TimeFilter.custom:
          // Keep current dates
          break;
      }
    });

    // Update transaction provider filter
    Provider.of<TransactionProvider>(
      context,
      listen: false,
    ).setDateFilter(_startDate, _endDate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body:
          Consumer3<
            TransactionProvider,
            UserProvider,
            ConnectionStatusProvider
          >(
            builder:
                (
                  context,
                  transactionProvider,
                  userProvider,
                  connectionStatus,
                  child,
                ) {
                  return CustomScrollView(
                    slivers: [
                      //  App Bar with sync status
                      _buildSliverAppBar(connectionStatus),

                      // Connection status banner
                      if (connectionStatus.shouldShowBanner)
                        SliverToBoxAdapter(
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: _buildConnectionBanner(connectionStatus),
                          ),
                        ),

                      // Search bar
                      SliverToBoxAdapter(child: _buildSearchSection()),

                      // Statistics summary
                      SliverToBoxAdapter(
                        child: _buildStatisticsSummary(transactionProvider),
                      ),

                      // Transactions list
                      if (_isInitialized) ...[
                        if (transactionProvider.isLoading)
                          _buildLoadingSliver()
                        else if (transactionProvider.hasError)
                          _buildErrorSliver(transactionProvider.error!)
                        else
                          _buildTransactionsSliver(transactionProvider),
                      ] else
                        _buildLoadingSliver(),
                    ],
                  );
                },
          ),

      // Floating action button
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  Widget _buildSliverAppBar(ConnectionStatusProvider connectionStatus) {
    return SliverAppBar(
      expandedHeight: 160,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: Theme.of(context).primaryColor,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          'Lịch sử Giao dịch',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withOpacity(0.8),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(top: 60, left: 16, right: 16),
              child: Row(
                children: [
                  Expanded(child: _buildDateRangeInfo()),
                  _buildSyncStatusIndicator(connectionStatus),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        // Filter menu
        PopupMenuButton<TimeFilter>(
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          onSelected: (filter) => _handleFilterSelection(filter),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: TimeFilter.thisWeek,
              child: _buildFilterMenuItem('Tuần này', Icons.view_week_rounded),
            ),
            PopupMenuItem(
              value: TimeFilter.thisMonth,
              child: _buildFilterMenuItem(
                'Tháng này',
                Icons.calendar_month_rounded,
              ),
            ),
            PopupMenuItem(
              value: TimeFilter.thisYear,
              child: _buildFilterMenuItem(
                'Năm này',
                Icons.calendar_today_rounded,
              ),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: TimeFilter.custom,
              child: _buildFilterMenuItem(
                'Tùy chọn...',
                Icons.date_range_rounded,
              ),
            ),
          ],
        ),

        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          onPressed: _refreshData,
          tooltip: 'Làm mới',
        ),
      ],
    );
  }

  Widget _buildDateRangeInfo() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getFilterDisplayText(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _getDateRangeText(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncStatusIndicator(ConnectionStatusProvider connectionStatus) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: connectionStatus.statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connectionStatus.isSyncing)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else
            Icon(
              connectionStatus.isOnline ? Icons.cloud_done : Icons.cloud_off,
              size: 12,
              color: Colors.white,
            ),
          const SizedBox(width: 4),
          Text(
            connectionStatus.statusMessage,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner(ConnectionStatusProvider connectionStatus) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: connectionStatus.statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: connectionStatus.statusColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            connectionStatus.isOnline
                ? Icons.info_outline
                : Icons.warning_amber,
            color: connectionStatus.statusColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              connectionStatus.statusMessage,
              style: TextStyle(
                color: connectionStatus.statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (connectionStatus.pendingItems > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: connectionStatus.statusColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${connectionStatus.pendingItems}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            margin: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm giao dịch...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: _clearSearch,
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: _handleSearchChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatisticsSummary(TransactionProvider transactionProvider) {
    final stats = transactionProvider.getStatistics();
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        return SlideTransition(
          position: _slideAnimation,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.analytics_rounded,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Tổng quan giao dịch',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Thu nhập',
                        stats['totalIncome']?.toDouble() ?? 0.0,
                        Colors.green,
                        Icons.trending_up,
                        currencyFormatter,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Chi tiêu',
                        stats['totalExpense']?.toDouble() ?? 0.0,
                        Colors.red,
                        Icons.trending_down,
                        currencyFormatter,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Chênh lệch',
                        stats['netAmount']?.toDouble() ?? 0.0,
                        (stats['netAmount']?.toDouble() ?? 0.0) >= 0
                            ? Colors.green
                            : Colors.red,
                        Icons.balance,
                        currencyFormatter,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.blue.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long,
                              color: Colors.blue,
                              size: 20,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${stats['transactionCount'] ?? 0}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            Text(
                              'Giao dịch',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            formatter.format(amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: color),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingSliver() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            Text(
              'Đang tải giao dịch...',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorSliver(String error) {
    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 80,
                color: Colors.red.shade300,
              ),
              const SizedBox(height: 24),
              Text(
                'Đã xảy ra lỗi',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _refreshData,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Thử lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionsSliver(TransactionProvider transactionProvider) {
    List<TransactionModel> transactions = transactionProvider.transactions;

    // Apply search filter
    if (_searchQuery != null && _searchQuery!.isNotEmpty) {
      transactions = transactionProvider.searchTransactions(_searchQuery!);
    }

    if (transactions.isEmpty) {
      return _buildEmptyStateSliver();
    }

    // Group transactions by date
    final groupedTransactions = groupBy(
      transactions,
      (TransactionModel t) => DateTime(t.date.year, t.date.month, t.date.day),
    );

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final entry = groupedTransactions.entries.elementAt(index);
        return AnimatedBuilder(
          animation: _fadeAnimation,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: DailyTransactionsGroup(
                  date: entry.key,
                  transactions: entry.value,
                  onTransactionUpdated: _refreshData,
                  showAnimations: true,
                  maxItemsToShow: 3,
                ),
              ),
            );
          },
        );
      }, childCount: groupedTransactions.length),
    );
  }

  Widget _buildEmptyStateSliver() {
    return SliverFillRemaining(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.receipt_long_outlined,
                  size: 80,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _searchQuery?.isNotEmpty == true
                    ? 'Không tìm thấy giao dịch'
                    : 'Chưa có giao dịch nào',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery?.isNotEmpty == true
                    ? 'Thử thay đổi từ khóa tìm kiếm'
                    : 'Trong khoảng thời gian này',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (_searchQuery?.isNotEmpty != true) ...[
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/add-transaction'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Thêm giao dịch đầu tiên'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: FloatingActionButton.extended(
            onPressed: () => Navigator.pushNamed(context, '/add-transaction'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Thêm giao dịch'),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
        );
      },
    );
  }

  Widget _buildFilterMenuItem(String label, IconData icon) {
    return Row(
      children: [Icon(icon, size: 20), const SizedBox(width: 12), Text(label)],
    );
  }

  // Helper methods
  String _getFilterDisplayText() {
    switch (_selectedFilter) {
      case TimeFilter.thisWeek:
        return 'TUẦN NÀY';
      case TimeFilter.thisMonth:
        return 'THÁNG NÀY';
      case TimeFilter.thisYear:
        return 'NĂM NÀY';
      case TimeFilter.custom:
        return 'TÙY CHỌN';
    }
  }

  String _getDateRangeText() {
    final formatter = DateFormat('dd/MM/yyyy');
    if (_startDate.year == _endDate.year &&
        _startDate.month == _endDate.month &&
        _startDate.day == _endDate.day) {
      return formatter.format(_startDate);
    }
    return '${formatter.format(_startDate)} - ${formatter.format(_endDate)}';
  }

  void _handleFilterSelection(TimeFilter filter) {
    if (filter == TimeFilter.custom) {
      _showCustomDatePicker();
    } else {
      _updateDateRange(filter);
    }
  }

  Future<void> _showCustomDatePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      helpText: 'Chọn khoảng thời gian',
      cancelText: 'Hủy',
      confirmText: 'Xác nhận',
    );

    if (picked != null) {
      setState(() {
        _selectedFilter = TimeFilter.custom;
        _startDate = picked.start;
        _endDate = picked.end;
      });

      // Update transaction provider filter
      Provider.of<TransactionProvider>(
        context,
        listen: false,
      ).setDateFilter(_startDate, _endDate);
    }
  }

  void _handleSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = null;
    });
  }

  void _refreshData() {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );
    transactionProvider.loadTransactions(
      startDate: _startDate,
      endDate: _endDate,
      forceRefresh: true,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}
