// lib/presentation/screens/_dashboard_screen.dart
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';

import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';
import 'package:moneysun/presentation/screens/all_transactions_screen.dart';
import 'package:moneysun/presentation/widgets/summary_card.dart';
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

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
  late AnimationController _cardController;
  late Animation<double> _refreshAnimation;
  late Animation<double> _fabScaleAnimation;
  late Animation<Offset> _cardSlideAnimation;

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
  bool _showPartnershipData = true;

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
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _fabController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _cardController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _refreshAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _refreshController, curve: Curves.elasticOut),
    );
    _fabScaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.elasticOut),
    );
    _cardSlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(parent: _cardController, curve: Curves.easeOutCubic),
        );

    _fabController.forward();
    _cardController.forward();
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

      // Load data in parallel with  error handling
      await Future.wait([
        walletProvider.loadWallets().timeout(const Duration(seconds: 15)),
        transactionProvider
            .loadTransactions(startDate: _startDate, endDate: _endDate)
            .timeout(const Duration(seconds: 15)),
      ]);

      // Cache stats for performance
      _cacheQuickStats();

      debugPrint('✅  Dashboard data loaded successfully');
    } catch (e) {
      _lastErrorMessage = e.toString();
      debugPrint('❌ Error loading  dashboard data: $e');

      if (mounted) {
        _showErrorSnackbar(
          'Không thể tải dữ liệu: ${_getShortErrorMessage(e.toString())}',
        );
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

  String _getShortErrorMessage(String fullError) {
    if (fullError.contains('timeout')) return 'Kết nối quá chậm';
    if (fullError.contains('network')) return 'Lỗi mạng';
    if (fullError.contains('permission')) return 'Không có quyền truy cập';
    return 'Lỗi không xác định';
  }

  void _cacheQuickStats() {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );
    final walletProvider = Provider.of<WalletProvider>(context, listen: false);
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    final stats = transactionProvider.getStatistics();

    _cachedStats = {
      'totalBalance': walletProvider.totalBalance,
      'personalBalance': walletProvider.personalBalance,
      'sharedBalance': walletProvider.sharedBalance,
      'transactionCount': transactionProvider.transactionCount,
      'hasPartner': userProvider.hasPartner,
      'partnerName': userProvider.partnerDisplayName,
      'lastUpdated': DateTime.now(),
      ...stats,
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

    _fabController.forward();

    if (result == true) {
      await _loadDataWithDataService();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Consumer3<ConnectionStatusProvider, UserProvider, DataService>(
      builder: (context, connectionStatus, userProvider, dataService, child) {
        return Scaffold(
          appBar: _buildAppBar(connectionStatus, userProvider),
          body: _buildBody(userProvider),
          floatingActionButton: _buildFAB(connectionStatus),
          floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(
    ConnectionStatusProvider connectionStatus,
    UserProvider userProvider,
  ) {
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
        // Partnership toggle (if has partner)
        if (userProvider.hasPartner)
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: _showPartnershipData
                  ? Colors.orange.withOpacity(0.2)
                  : Colors.grey.withOpacity(0.2),
            ),
            child: IconButton(
              icon: Icon(
                _showPartnershipData ? Icons.people : Icons.person,
                size: 20,
              ),
              color: _showPartnershipData ? Colors.orange : Colors.grey,
              tooltip: _showPartnershipData
                  ? 'Ẩn dữ liệu chung'
                  : 'Hiện dữ liệu chung',
              onPressed: () {
                setState(() {
                  _showPartnershipData = !_showPartnershipData;
                });
                _cacheQuickStats(); // Refresh cache
              },
            ),
          ),

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
            if (userProvider.hasPartner)
              const PopupMenuItem(
                value: 'partnership_info',
                child: ListTile(
                  leading: Icon(Icons.people),
                  title: Text('Thông tin Partnership'),
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

  Widget _buildBody(UserProvider userProvider) {
    return RefreshIndicator(
      onRefresh: _loadDataWithDataService,
      color: Theme.of(context).primaryColor,
      backgroundColor: Colors.white,
      strokeWidth: 3,
      child: CustomScrollView(
        key: _refreshKey,
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Partnership banner (if applicable)
          //if (userProvider.hasPartner) _buildPartnershipBanner(userProvider),

          // Quick stats header
          //_buildQuickStatsSliver(userProvider),

          // Main content
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                //  Summary Card
                SlideTransition(
                  position: _cardSlideAnimation,
                  child: AnimatedBuilder(
                    animation: _refreshAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: 0.95 + (_refreshAnimation.value * 0.05),
                        child: Opacity(
                          opacity: 0.8 + (_refreshAnimation.value * 0.2),
                          child: SummaryCard(
                            startDate: _startDate,
                            endDate: _endDate,
                            showPartnership:
                                _showPartnershipData && userProvider.hasPartner,
                            cachedStats: _cachedStats,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 24),

                //  Wallets Section
                _buildWalletsSection(userProvider),

                const SizedBox(height: 24),

                //  Transactions Section
                _buildTransactionsSection(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnershipBanner(UserProvider userProvider) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.orange.withOpacity(0.1),
              Colors.orange.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.orange.withOpacity(0.2),
              backgroundImage: userProvider.partnerPhotoURL != null
                  ? NetworkImage(userProvider.partnerPhotoURL!)
                  : null,
              child: userProvider.partnerPhotoURL == null
                  ? Icon(Icons.people, color: Colors.orange, size: 20)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kết nối với ${userProvider.partnerDisplayName ?? "Đối tác"}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    _showPartnershipData
                        ? 'Hiển thị dữ liệu chung'
                        : 'Chỉ hiển thị dữ liệu cá nhân',
                    style: TextStyle(
                      color: Colors.orange.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _showPartnershipData,
              onChanged: (value) {
                setState(() {
                  _showPartnershipData = value;
                });
                _cacheQuickStats();
              },
              activeColor: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsSliver(UserProvider userProvider) {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).primaryColor.withOpacity(0.1),
              Theme.of(context).primaryColor.withOpacity(0.05),
              Colors.transparent,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).primaryColor.withOpacity(0.2),
          ),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child:
            Consumer3<
              WalletProvider,
              TransactionProvider,
              ConnectionStatusProvider
            >(
              builder:
                  (
                    context,
                    walletProvider,
                    transactionProvider,
                    connectionStatus,
                    child,
                  ) {
                    return Column(
                      children: [
                        // Main stats row
                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickStatItem(
                                'Tổng số dư',
                                NumberFormat.currency(
                                  locale: 'vi_VN',
                                  symbol: '₫',
                                ).format(
                                  _showPartnershipData ||
                                          !userProvider.hasPartner
                                      ? walletProvider.totalBalance
                                      : walletProvider.personalBalance,
                                ),
                                Icons.account_balance_wallet,
                                walletProvider.totalBalance >= 0
                                    ? Colors.green
                                    : Colors.red,
                                isMain: true,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Secondary stats row
                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickStatItem(
                                'Giao dịch',
                                '${transactionProvider.transactionCount}',
                                Icons.receipt_long,
                                Colors.blue,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Theme.of(
                                context,
                              ).primaryColor.withOpacity(0.2),
                            ),
                            Expanded(
                              child: _buildQuickStatItem(
                                'Số ví',
                                '${walletProvider.walletCount}',
                                Icons.account_balance,
                                Colors.purple,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Theme.of(
                                context,
                              ).primaryColor.withOpacity(0.2),
                            ),
                            Expanded(
                              child: _buildQuickStatItem(
                                'Chờ sync',
                                '${connectionStatus.pendingItems}',
                                Icons.sync,
                                connectionStatus.pendingItems > 0
                                    ? Colors.orange
                                    : Colors.green,
                              ),
                            ),
                          ],
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
    Color color, {
    bool isMain = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isMain ? 16 : 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(isMain ? 16 : 12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: isMain ? 28 : 20),
          SizedBox(height: isMain ? 8 : 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              value,
              key: ValueKey(value),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: isMain ? 18 : 14,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: isMain ? 12 : 11,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWalletsSection(UserProvider userProvider) {
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
            Row(
              children: [
                if (userProvider.hasPartner)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _showPartnershipData
                          ? Colors.orange.withOpacity(0.1)
                          : Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _showPartnershipData ? 'Cả hai' : 'Cá nhân',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _showPartnershipData
                            ? Colors.orange
                            : Colors.blue,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
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
          ],
        ),
        const SizedBox(height: 12),
        _buildWalletsList(userProvider),
      ],
    );
  }

  Widget _buildWalletsList(UserProvider userProvider) {
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

        return _buildWalletsContent(walletProvider, userProvider);
      },
    );
  }

  Widget _buildWalletsContent(
    WalletProvider walletProvider,
    UserProvider userProvider,
  ) {
    // Filter wallets based on partnership display setting
    List<Wallet> walletsToShow = walletProvider.wallets;

    if (userProvider.hasPartner && !_showPartnershipData) {
      // Show only personal wallets
      walletsToShow = walletProvider.personalWallets;
    }

    // Group wallets by ownership
    final personalWallets = walletsToShow
        .where((w) => w.ownerId == userProvider.currentUser?.uid)
        .toList();
    final sharedWallets = walletsToShow
        .where((w) => w.ownerId == userProvider.partnershipId)
        .toList();
    final partnerWallets = walletsToShow
        .where(
          (w) => w.ownerId == userProvider.partnerUid && w.isVisibleToPartner,
        )
        .toList();

    return Column(
      children: [
        // Total balance card
        _buildTotalBalanceCard(walletProvider, userProvider),

        const SizedBox(height: 16),

        // Personal Wallets
        if (personalWallets.isNotEmpty) ...[
          _buildWalletGroupHeader(
            '💼 Ví cá nhân',
            personalWallets.length,
            Colors.blue,
          ),
          const SizedBox(height: 8),
          ...personalWallets.take(3).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final wallet = entry.value;
            return AnimatedContainer(
              duration: Duration(milliseconds: 300 + (index * 100)),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(bottom: 8),
              child: _buildWalletItem(wallet, index, Colors.blue),
            );
          }).toList(),
          if (personalWallets.length > 3)
            _buildShowMoreButton(personalWallets.length - 3, 'ví cá nhân'),
        ],

        // Shared Wallets
        if (sharedWallets.isNotEmpty && _showPartnershipData) ...[
          if (personalWallets.isNotEmpty) const SizedBox(height: 16),
          _buildWalletGroupHeader(
            '👥 Ví chung',
            sharedWallets.length,
            Colors.orange,
          ),
          const SizedBox(height: 8),
          ...sharedWallets.take(3).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final wallet = entry.value;
            return AnimatedContainer(
              duration: Duration(milliseconds: 300 + (index * 100)),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(bottom: 8),
              child: _buildWalletItem(wallet, index, Colors.orange),
            );
          }).toList(),
          if (sharedWallets.length > 3)
            _buildShowMoreButton(sharedWallets.length - 3, 'ví chung'),
        ],

        // Partner Wallets (visible)
        if (partnerWallets.isNotEmpty && _showPartnershipData) ...[
          if (personalWallets.isNotEmpty || sharedWallets.isNotEmpty)
            const SizedBox(height: 16),
          _buildWalletGroupHeader(
            '👤 Ví của ${userProvider.partnerDisplayName ?? "Đối tác"}',
            partnerWallets.length,
            Colors.green,
          ),
          const SizedBox(height: 8),
          ...partnerWallets.take(2).toList().asMap().entries.map((entry) {
            final index = entry.key;
            final wallet = entry.value;
            return AnimatedContainer(
              duration: Duration(milliseconds: 300 + (index * 100)),
              curve: Curves.easeOutCubic,
              margin: const EdgeInsets.only(bottom: 8),
              child: _buildWalletItem(wallet, index, Colors.green),
            );
          }).toList(),
          if (partnerWallets.length > 2)
            _buildShowMoreButton(partnerWallets.length - 2, 'ví đối tác'),
        ],
      ],
    );
  }

  Widget _buildWalletGroupHeader(String title, int count, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            title.contains('👥')
                ? Icons.people
                : title.contains('👤')
                ? Icons.person
                : Icons.person_outline,
            size: 16,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTotalBalanceCard(
    WalletProvider walletProvider,
    UserProvider userProvider,
  ) {
    final totalBalance = _showPartnershipData || !userProvider.hasPartner
        ? walletProvider.totalBalance
        : walletProvider.personalBalance;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      child: Card(
        elevation: 6,
        shadowColor: Theme.of(context).primaryColor.withOpacity(0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                totalBalance >= 0
                    ? Colors.green.withOpacity(0.1)
                    : Colors.red.withOpacity(0.1),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (totalBalance >= 0 ? Colors.green : Colors.red)
                          .withOpacity(0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      totalBalance >= 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                      color: totalBalance >= 0 ? Colors.green : Colors.red,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _showPartnershipData && userProvider.hasPartner
                              ? 'Tổng số dư (Cả hai)'
                              : 'Tổng số dư',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 500),
                          child: Text(
                            NumberFormat.currency(
                              locale: 'vi_VN',
                              symbol: '₫',
                            ).format(totalBalance),
                            key: ValueKey(totalBalance),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: totalBalance >= 0
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Breakdown (if partnership)
              if (userProvider.hasPartner && _showPartnershipData) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    _buildBalanceBreakdown(
                      'Cá nhân',
                      walletProvider.personalBalance,
                      Colors.blue,
                    ),
                    const SizedBox(width: 12),
                    _buildBalanceBreakdown(
                      'Chung',
                      walletProvider.sharedBalance,
                      Colors.orange,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBalanceBreakdown(String label, double amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              NumberFormat.currency(
                locale: 'vi_VN',
                symbol: '₫',
              ).format(amount),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: amount >= 0 ? Colors.green : Colors.red,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletItem(Wallet wallet, int index, Color themeColor) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      shadowColor: themeColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [themeColor.withOpacity(0.05), Colors.transparent],
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: Hero(
            tag: 'wallet_${wallet.id}',
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(wallet.type.icon, color: themeColor, size: 24),
            ),
          ),
          title: Text(
            wallet.displayName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(
                wallet.formattedBalance,
                style: TextStyle(
                  color: wallet.balance >= 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              if (wallet.type != WalletType.general) ...[
                const SizedBox(height: 2),
                Text(
                  wallet.type.displayName,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ],
          ),
          trailing: wallet.ownerId == FirebaseAuth.instance.currentUser?.uid
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      wallet.isVisibleToPartner
                          ? Icons.visibility
                          : Icons.visibility_off,
                      size: 16,
                      color: wallet.isVisibleToPartner
                          ? Colors.green
                          : Colors.grey,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      wallet.isVisibleToPartner ? 'Hiện' : 'Ẩn',
                      style: TextStyle(
                        fontSize: 10,
                        color: wallet.isVisibleToPartner
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                  ],
                )
              : Icon(Icons.info_outline, size: 16, color: Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildShowMoreButton(int count, String type) {
    return TextButton.icon(
      onPressed: () {
        // Navigate to all wallets screen
        _showFeatureNotImplemented('Xem tất cả $type');
      },
      icon: const Icon(Icons.expand_more, size: 16),
      label: Text('Xem thêm $count $type'),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                _getShortErrorMessage(error),
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
              margin: const EdgeInsets.only(bottom: 12),
              child: Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: DailyTransactionsGroup(
                  date: dateEntry.key,
                  transactions: dateEntry.value,
                  onTransactionUpdated: _loadDataWithDataService,
                  isCompact: true,
                ),
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
                _getShortErrorMessage(error),
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

  Widget _buildFAB(ConnectionStatusProvider connectionStatus) {
    return AnimatedBuilder(
      animation: _fabScaleAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _fabScaleAnimation.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Connection status mini FAB (if offline)
              if (!connectionStatus.isOnline ||
                  connectionStatus.pendingItems > 0) ...[
                FloatingActionButton.small(
                  onPressed: _performManualSync,
                  backgroundColor: connectionStatus.statusColor,
                  foregroundColor: Colors.white,
                  heroTag: "sync_fab",
                  child: connectionStatus.isSyncing
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Icon(Icons.sync, size: 20),
                ),
                const SizedBox(height: 12),
              ],

              // Main FAB
              FloatingActionButton.extended(
                onPressed: _navigateToAddTransaction,
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 8,
                heroTag: "main_fab",
                icon: const Icon(Icons.add, size: 24),
                label: const Text(
                  'Giao dịch',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                tooltip: 'Thêm giao dịch mới',
              ),
            ],
          ),
        );
      },
    );
  }

  // Event handlers
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
        _showErrorSnackbar(
          'Đồng bộ thất bại: ${_getShortErrorMessage(e.toString())}',
        );
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
            _buildStatusDialogRow('Kết nối', connectionStatus.statusMessage),
            _buildStatusDialogRow(
              'Mục chờ đồng bộ',
              '${connectionStatus.pendingItems}',
            ),
            if (connectionStatus.lastSyncTime != null)
              _buildStatusDialogRow(
                'Lần cuối đồng bộ',
                DateFormat(
                  'dd/MM/yyyy HH:mm',
                ).format(connectionStatus.lastSyncTime!),
              ),
            if (connectionStatus.lastError != null)
              _buildStatusDialogRow('Lỗi', connectionStatus.lastError!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
          if (!connectionStatus.isOnline || connectionStatus.pendingItems > 0)
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

  Widget _buildStatusDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    switch (action) {
      case 'refresh':
        _loadDataWithDataService();
        break;
      case 'add_wallet':
        _showAddWalletDialog();
        break;
      case 'partnership_info':
        if (userProvider.hasPartner) {
          _showPartnershipInfoDialog(userProvider);
        }
        break;
      case 'export':
        _showFeatureNotImplemented('Xuất báo cáo');
        break;
    }
  }

  void _showPartnershipInfoDialog(UserProvider userProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Partnership với ${userProvider.partnerDisplayName ?? "Đối tác"}',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoDialogRow(
              'Partnership ID',
              userProvider.partnershipId ?? 'N/A',
            ),
            _buildInfoDialogRow(
              'Partner UID',
              userProvider.partnerUid ?? 'N/A',
            ),
            if (userProvider.partnershipCreationDate != null)
              _buildInfoDialogRow(
                'Ngày tạo',
                DateFormat(
                  'dd/MM/yyyy',
                ).format(userProvider.partnershipCreationDate!),
              ),
            const SizedBox(height: 16),
            Text(
              'Hiển thị dữ liệu: ${_showPartnershipData ? "Cả hai" : "Chỉ cá nhân"}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'Courier'),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddWalletDialog() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final nameController = TextEditingController();
    final balanceController = TextEditingController();
    String ownerType = 'personal';
    WalletType selectedWalletType = WalletType.general;

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
              content: SingleChildScrollView(
                child: Column(
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

                    const SizedBox(height: 16),

                    // Wallet type selection
                    const Text(
                      'Loại ví:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    DropdownButtonFormField<WalletType>(
                      value: selectedWalletType,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      items: WalletType.values.map((type) {
                        return DropdownMenuItem(
                          value: type,
                          child: Row(
                            children: [
                              Icon(type.icon, size: 20),
                              const SizedBox(width: 8),
                              Text(type.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) =>
                          setDialogState(() => selectedWalletType = value!),
                    ),

                    if (userProvider.partnershipId != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Quyền sở hữu:',
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
                        title: Text(
                          'Chung (${userProvider.partnerDisplayName ?? "Đối tác"})',
                        ),
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
                      type: selectedWalletType,
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
    _cardController.dispose();
    super.dispose();
  }
}
