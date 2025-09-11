// lib/presentation/screens/_dashboard_screen.dart
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/presentation/screens/all_transactions_screen.dart';
import 'package:moneysun/presentation/widgets/summary_card.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final AuthService _authService = AuthService();

  // Animation Controllers
  late AnimationController _refreshController;
  late AnimationController _fabController;
  late Animation<double> _refreshAnimation;
  late Animation<double> _fabScaleAnimation;

  // State Management
  Key _refreshKey = UniqueKey();
  bool _isRefreshing = false;
  String? _lastErrorMessage;

  // Time filter state
  TimeFilter _selectedTimeFilter = TimeFilter.thisMonth;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  // Quick Stats Cache
  Map<String, dynamic>? _cachedStats;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadDataWithDataService();
  }

  void _initializeAnimations() {
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _refreshAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _refreshController, curve: Curves.elasticOut),
    );
    _fabScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.elasticOut),
    );

    _fabController.forward();
  }

  Future<void> _loadDataWithDataService() async {
    if (_isRefreshing) return;

    setState(() {
      _isRefreshing = true;
      _lastErrorMessage = null;
    });

    try {
      _refreshController.forward();

      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final transactionProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );

      // Load data in parallel with timeout
      await Future.wait([
        walletProvider.loadWallets().timeout(const Duration(seconds: 10)),
        transactionProvider
            .loadTransactions(startDate: _startDate, endDate: _endDate)
            .timeout(const Duration(seconds: 10)),
      ]);

      // Cache quick stats for performance
      _cacheQuickStats();

      debugPrint('✅ Dashboard data loaded successfully with DataService');
    } catch (e) {
      _lastErrorMessage = e.toString();
      debugPrint('❌ Error loading dashboard data: $e');

      // Show error snackbar
      if (mounted) {
        _showErrorSnackbar('Không thể tải dữ liệu: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
          _refreshKey = UniqueKey();
        });
        _refreshController.reset();
      }
    }
  }

  void _cacheQuickStats() {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);

    _cachedStats = {
      'totalBalance': walletProvider.totalBalance,
      'transactionCount': transactionProvider.transactionCount,
      'lastUpdated': DateTime.now(),
      ...transactionProvider.getStatistics(),
    };
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'Thử lại',
          textColor: Colors.white,
          onPressed: _loadDataWithDataService,
        ),
      ),
    );
  }

  Future<void> _navigateToAddTransaction() async {
    // Animate FAB before navigation
    await _fabController.reverse();

    if (!mounted) return;

    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AddTransactionScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0.0, 1.0),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          );
        },
      ),
    );

    // Animate FAB back
    _fabController.forward();

    if (result == true) {
      await _loadDataWithDataService();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return Scaffold(
          appBar: _buildAppBar(connectionStatus),
          body: _buildBody(),
          floatingActionButton: _buildFAB(),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(ConnectionStatusProvider connectionStatus) {
    return TimeFilterAppBar(
      title: 'Tổng quan tài chính',
      selectedFilter: _selectedTimeFilter,
      startDate: _startDate,
      endDate: _endDate,
      onFilterChanged: (filter, start, end) {
        setState(() {
          _selectedTimeFilter = filter;
          _startDate = start;
          _endDate = end;
        });
        _loadDataWithDataService();
      },
      syncStatus: SyncStatusInfo(
        status: connectionStatus.isOnline
            ? ConnectivityStatus.online
            : ConnectivityStatus.offline,
        lastSyncTime: connectionStatus.lastSyncTime,
        pendingCount: connectionStatus.pendingItems,
        errorMessage: connectionStatus.lastError,
        isSyncing: connectionStatus.isSyncing,
      ),
      onSyncPressed: _performManualSync,
      onSyncStatusTap: _showSyncStatusDialog,
      additionalActions: [
        // Quick action menu
        PopupMenuButton<String>(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.more_vert,
              color: Theme.of(context).primaryColor,
              size: 20,
            ),
          ),
          onSelected: _handleQuickAction,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Làm mới'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'add_wallet',
              child: ListTile(
                leading: Icon(Icons.add_circle),
                title: Text('Thêm ví'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            const PopupMenuItem(
              value: 'export',
              child: ListTile(
                leading: Icon(Icons.file_download),
                title: Text('Xuất báo cáo'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _loadDataWithDataService,
      color: Theme.of(context).primaryColor,
      backgroundColor: Colors.white,
      strokeWidth: 3,
      child: CustomScrollView(
        key: _refreshKey,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Quick stats header
          _buildQuickStatsSliver(),

          // Main content
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                //  Summary Card
                AnimatedBuilder(
                  animation: _refreshAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.9 + (_refreshAnimation.value * 0.1),
                      child: Opacity(
                        opacity: 0.7 + (_refreshAnimation.value * 0.3),
                        child: SummaryCard(
                          startDate: _startDate,
                          endDate: _endDate,
                          //cachedStats: _cachedStats,
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Wallets Section
                _buildWalletsSection(),

                const SizedBox(height: 24),

                // Transactions Section
                _buildTransactionsSection(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsSliver() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.1),
              Theme.of(context).primaryColor.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.2),
          ),
        ),
        child: Consumer2<WalletProvider, TransactionProvider>(
          builder: (context, walletProvider, transactionProvider, child) {
            return Row(
              children: [
                Expanded(
                  child: _buildQuickStatItem(
                    'Tổng số dư',
                    NumberFormat.currency(
                      locale: 'vi_VN',
                      symbol: '₫',
                    ).format(walletProvider.totalBalance),
                    Icons.account_balance_wallet,
                    Colors.blue,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                ),
                Expanded(
                  child: _buildQuickStatItem(
                    'Giao dịch',
                    '${transactionProvider.transactionCount}',
                    Icons.receipt_long,
                    Colors.green,
                  ),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: Theme.of(context).primaryColor.withOpacity(0.2),
                ),
                Expanded(
                  child: _buildQuickStatItem(
                    'Chờ sync',
                    '${Provider.of<ConnectionStatusProvider>(context).pendingItems}',
                    Icons.sync,
                    Colors.orange,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuickStatItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildWalletsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tài khoản & Ví',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () => _handleQuickAction('add_wallet'),
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: const Text('Thêm ví'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildWalletsList(),
      ],
    );
  }

  Widget _buildTransactionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Giao dịch gần đây',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AllTransactionsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward, size: 16),
              label: const Text('Xem tất cả'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildTransactionsList(),
      ],
    );
  }

  Widget _buildWalletsList() {
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, child) {
        if (walletProvider.isLoading) {
          return _buildWalletsLoadingState();
        }

        if (walletProvider.hasError) {
          return _buildWalletsErrorState(walletProvider.error);
        }

        if (walletProvider.wallets.isEmpty) {
          return _buildWalletsEmptyState();
        }

        return _buildWalletsContent(walletProvider);
      },
    );
  }

  Widget _buildWalletsContent(WalletProvider walletProvider) {
    return Column(
      children: [
        // Total balance card with animations
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          child: Card(
            elevation: 4,
            shadowColor: Theme.of(context).primaryColor.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Theme.of(context).primaryColor.withOpacity(0.1),
                    Theme.of(context).primaryColor.withOpacity(0.05),
                  ],
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.account_balance_wallet,
                      color: Theme.of(context).primaryColor,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tổng số dư',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          NumberFormat.currency(
                            locale: 'vi_VN',
                            symbol: '₫',
                          ).format(walletProvider.totalBalance),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                color: Theme.of(context).primaryColor,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Wallets list with staggered animation
        ...walletProvider.wallets.take(5).toList().asMap().entries.map((entry) {
          final index = entry.key;
          final wallet = entry.value;

          return AnimatedContainer(
            duration: Duration(milliseconds: 300 + (index * 100)),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.only(bottom: 8),
            child: _buildWalletItem(wallet, index),
          );
        }).toList(),

        if (walletProvider.wallets.length > 5)
          TextButton(
            onPressed: () {
              // Navigate to all wallets screen
            },
            child: Text('Xem thêm ${walletProvider.wallets.length - 5} ví'),
          ),
      ],
    );
  }

  Widget _buildWalletItem(Wallet wallet, int index) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    IconData walletIcon;
    String walletTag = "";
    Color iconColor = Colors.green;

    if (wallet.ownerId == userProvider.partnershipId) {
      walletIcon = Icons.people;
      walletTag = " (Chung)";
      iconColor = Colors.orange;
    } else if (wallet.ownerId == userProvider.partnerUid) {
      walletIcon = Icons.military_tech;
      walletTag = " (Partner)";
      iconColor = Colors.blueGrey;
    } else {
      walletIcon = Icons.person;
      walletTag = "";
    }

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: iconColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Hero(
          tag: 'wallet_${wallet.id}',
          child: CircleAvatar(
            backgroundColor: iconColor.withOpacity(0.2),
            child: Icon(walletIcon, color: iconColor, size: 20),
          ),
        ),
        title: Text(
          wallet.name + walletTag,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          wallet.formattedBalance,
          style: TextStyle(color: iconColor, fontWeight: FontWeight.w500),
        ),
        trailing: wallet.ownerId == FirebaseAuth.instance.currentUser?.uid
            ? Switch(
                value: wallet.isVisibleToPartner,
                onChanged: (newValue) {
                  // TODO: Implement updateWalletVisibility with DataService
                  _showFeatureNotImplemented('Cập nhật visibility ví');
                },
                activeColor: iconColor,
              )
            : null,
      ),
    );
  }

  Widget _buildWalletsLoadingState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            Text(
              'Đang tải ví...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletsErrorState(String? error) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Lỗi tải ví',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.red.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Provider.of<WalletProvider>(
                context,
                listen: false,
              ).loadWallets(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletsEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có ví nào',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thêm ví đầu tiên để bắt đầu quản lý tài chính',
              style: TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _handleQuickAction('add_wallet'),
              icon: const Icon(Icons.add),
              label: const Text('Thêm ví mới'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList() {
    return Consumer<TransactionProvider>(
      builder: (context, transactionProvider, child) {
        if (transactionProvider.isLoading) {
          return _buildTransactionsLoadingState();
        }

        if (transactionProvider.hasError) {
          return _buildTransactionsErrorState(transactionProvider.error);
        }

        if (transactionProvider.transactions.isEmpty) {
          return _buildTransactionsEmptyState();
        }

        return _buildTransactionsContent(transactionProvider);
      },
    );
  }

  Widget _buildTransactionsContent(TransactionProvider transactionProvider) {
    final transactions = transactionProvider.transactions;

    // Group by date
    final groupedTransactions = groupBy(transactions, (TransactionModel t) {
      return DateTime(t.date.year, t.date.month, t.date.day);
    });

    return Column(
      children: groupedTransactions.entries
          .take(5) // Show only last 5 days on dashboard
          .toList()
          .asMap()
          .entries
          .map((entry) {
            final index = entry.key;
            final dateEntry = entry.value;

            return AnimatedContainer(
              duration: Duration(milliseconds: 300 + (index * 100)),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(bottom: 8),
              child: DailyTransactionsGroup(
                date: dateEntry.key,
                transactions: dateEntry.value,
                onTransactionUpdated: _loadDataWithDataService,
                isCompact: true,
              ),
            );
          })
          .toList(),
    );
  }

  Widget _buildTransactionsLoadingState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            CircularProgressIndicator(color: Theme.of(context).primaryColor),
            const SizedBox(height: 16),
            Text(
              'Đang tải giao dịch...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsErrorState(String? error) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text(
              'Lỗi tải giao dịch',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.red.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error,
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  Provider.of<TransactionProvider>(
                    context,
                    listen: false,
                  ).loadTransactions(
                    startDate: _startDate,
                    endDate: _endDate,
                    forceRefresh: true,
                  ),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsEmptyState() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có giao dịch nào',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Thêm giao dịch đầu tiên để bắt đầu theo dõi',
              style: TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _navigateToAddTransaction,
              icon: const Icon(Icons.add),
              label: const Text('Thêm giao dịch'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAB() {
    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return AnimatedBuilder(
          animation: _fabScaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _fabScaleAnimation.value,
              child: FloatingActionButton.extended(
                onPressed: _navigateToAddTransaction,
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 6,
                icon: const Icon(Icons.add, size: 24),
                label: const Text(
                  'Giao dịch',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                tooltip: 'Thêm giao dịch mới',
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _performManualSync() async {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      await dataService.forceSyncNow();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                const Text('Đồng bộ thành công'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        await _loadDataWithDataService();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Đồng bộ thất bại: $e');
      }
    }
  }

  void _showSyncStatusDialog() {
    final dataService = Provider.of<DataService>(context, listen: false);
    final connectionStatus = Provider.of<ConnectionStatusProvider>(
      context,
      listen: false,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              connectionStatus.isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: connectionStatus.statusColor,
            ),
            const SizedBox(width: 12),
            const Text('Trạng thái đồng bộ'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusRow('Kết nối', connectionStatus.statusMessage),
            _buildStatusRow(
              'Mục chờ đồng bộ',
              '${connectionStatus.pendingItems}',
            ),
            if (connectionStatus.lastSyncTime != null)
              _buildStatusRow(
                'Lần cuối đồng bộ',
                DateFormat(
                  'dd/MM/yyyy HH:mm',
                ).format(connectionStatus.lastSyncTime!),
              ),
            if (connectionStatus.lastError != null)
              _buildStatusRow('Lỗi', connectionStatus.lastError!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          if (!connectionStatus.isOnline)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _performManualSync();
              },
              child: const Text('Đồng bộ'),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _handleQuickAction(String action) {
    switch (action) {
      case 'refresh':
        _loadDataWithDataService();
        break;
      case 'add_wallet':
        _showAddWalletDialog();
        break;
      case 'export':
        _showFeatureNotImplemented('Xuất báo cáo');
        break;
    }
  }

  void _showAddWalletDialog() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final nameController = TextEditingController();
    final balanceController = TextEditingController();

    String ownerType = 'personal';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Thêm ví mới'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Tên ví',
                      prefixIcon: Icon(Icons.account_balance_wallet),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: balanceController,
                    decoration: const InputDecoration(
                      labelText: 'Số dư ban đầu',
                      prefixIcon: Icon(Icons.monetization_on),
                      border: OutlineInputBorder(),
                      suffixText: '₫',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (userProvider.partnershipId != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Loại ví:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    RadioListTile<String>(
                      title: const Text('Cá nhân'),
                      value: 'personal',
                      groupValue: ownerType,
                      onChanged: (value) =>
                          setDialogState(() => ownerType = value!),
                    ),
                    RadioListTile<String>(
                      title: const Text('Chung (Cả hai cùng xem)'),
                      value: 'shared',
                      groupValue: ownerType,
                      onChanged: (value) =>
                          setDialogState(() => ownerType = value!),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    final balance =
                        double.tryParse(balanceController.text) ?? 0.0;

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Vui lòng nhập tên ví'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    final String ownerId;
                    if (ownerType == 'shared') {
                      ownerId = userProvider.partnershipId!;
                    } else {
                      ownerId = _authService.getCurrentUser()!.uid;
                    }

                    final walletProvider = Provider.of<WalletProvider>(
                      context,
                      listen: false,
                    );

                    Navigator.pop(context);

                    final success = await walletProvider.addWallet(
                      name: name,
                      initialBalance: balance,
                      ownerId: ownerId,
                    );

                    if (success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.white),
                              const SizedBox(width: 12),
                              const Text('Ví đã được thêm thành công'),
                            ],
                          ),
                          backgroundColor: Colors.green.shade600,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    } else {
                      _showErrorSnackbar(
                        'Không thể thêm ví. Vui lòng thử lại.',
                      );
                    }
                  },
                  child: const Text('Thêm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFeatureNotImplemented(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature chưa được triển khai'),
        backgroundColor: Colors.orange.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  void dispose() {
    _refreshController.dispose();
    _fabController.dispose();
    super.dispose();
  }
}
