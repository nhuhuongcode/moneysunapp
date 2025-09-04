// lib/presentation/screens/dashboard_screen.dart - UPDATED VERSION

import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/sync_status_provider.dart'; // NEW
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart'; // NEW
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/presentation/screens/all_transactions_screen.dart';
import 'package:moneysun/presentation/screens/transfer_screen.dart';
import 'package:moneysun/presentation/widgets/summary_card.dart';
import 'package:moneysun/presentation/widgets/connection_status_banner.dart'; // NEW
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  final OfflineSyncService _syncService = OfflineSyncService(); // NEW

  Key _refreshKey = UniqueKey();

  // Time filter state
  TimeFilter _selectedTimeFilter = TimeFilter.thisMonth;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  // NEW: Local state for offline data
  List<TransactionModel> _localTransactions = [];
  List<Wallet> _localWallets = [];
  bool _isLoadingLocal = true;

  @override
  void initState() {
    super.initState();
    _loadOfflineData(); // NEW: Load offline data first
  }

  // NEW: Load offline data first for immediate UI response
  Future<void> _loadOfflineData() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        // Load local transactions
        final localTransactions = await _syncService.getTransactions(
          userId: userId,
          startDate: _startDate,
          endDate: _endDate,
          limit: 15,
        );

        final userProvider = Provider.of<UserProvider>(context, listen: false);
        final localWallets = await _syncService.getWallets(userId);

        setState(() {
          _localTransactions = localTransactions;
          _localWallets = localWallets;
          _isLoadingLocal = false;
        });
      }
    } catch (e) {
      print('Error loading offline data: $e');
      setState(() {
        _isLoadingLocal = false;
      });
    }
  }

  // NEW: Enhanced navigation to AddTransaction with result handling
  Future<void> _navigateToAddTransaction() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AddTransactionScreen()),
    );

    // NEW: If transaction was added successfully, refresh both local and stream data
    if (result == true) {
      setState(() {
        _refreshKey = UniqueKey(); // Force rebuild streams
      });

      // Also reload offline data immediately
      await _loadOfflineData();

      // Show refresh indicator briefly
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Dữ liệu đã được cập nhật'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
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
              title: const Text('Thêm ví mới'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Tên ví'),
                  ),
                  TextField(
                    controller: balanceController,
                    decoration: const InputDecoration(
                      labelText: 'Số dư ban đầu',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (userProvider.partnershipId != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Tạo cho:',
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
                    final name = nameController.text;
                    final balance =
                        double.tryParse(balanceController.text) ?? 0.0;

                    final String ownerId;
                    if (ownerType == 'shared') {
                      ownerId = userProvider.partnershipId!;
                    } else {
                      ownerId = _authService.getCurrentUser()!.uid;
                    }

                    if (name.isNotEmpty) {
                      // NEW: Use offline-first approach
                      await _syncService.addWalletOffline(
                        Wallet(
                          id: DateTime.now().millisecondsSinceEpoch.toString(),
                          name: name,
                          balance: balance,
                          ownerId: ownerId,
                        ),
                      );

                      Navigator.pop(context);

                      // Refresh local data
                      await _loadOfflineData();
                      setState(() {
                        _refreshKey = UniqueKey();
                      });
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

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // NEW: Get sync provider for connection status
    final syncProvider = Provider.of<SyncStatusProvider>(context);

    return Scaffold(
      appBar: TimeFilterAppBar(
        title: 'Tổng quan',
        selectedFilter: _selectedTimeFilter,
        startDate: _startDate,
        endDate: _endDate,
        onFilterChanged: (filter, start, end) {
          setState(() {
            _selectedTimeFilter = filter;
            _startDate = start;
            _endDate = end;
          });
          // Reload offline data with new date range
          _loadOfflineData();
        },
        // NEW: Add sync status to AppBar
        syncStatus: syncProvider.getSyncStatusInfo(),
        onSyncPressed: () async {
          try {
            await syncProvider.forceSyncNow();
            await _loadOfflineData(); // Reload after sync
          } catch (e) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Lỗi đồng bộ: $e')));
          }
        },
        onSyncStatusTap: () => _showSyncDetailsDialog(syncProvider),
      ),
      body: Column(
        children: [
          // NEW: Connection status banner
          const EnhancedConnectionStatusBanner(
            showWhenOnline: false,
            showDetailedInfo: true,
          ),

          // Main content
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                // Force sync when online, otherwise just reload local data
                if (syncProvider.isOnline) {
                  try {
                    await syncProvider.forceSyncNow();
                  } catch (e) {
                    print('Sync failed during refresh: $e');
                  }
                }

                // Always reload local data
                await _loadOfflineData();
                setState(() {
                  _refreshKey = UniqueKey();
                });
              },
              child: SingleChildScrollView(
                key: _refreshKey,
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SummaryCard(
                      initialStartDate: _startDate,
                      initialEndDate: _endDate,
                    ),
                    const SizedBox(height: 16),

                    Text(
                      'Các ví của bạn',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),

                    // NEW: Use both offline and online data for wallets
                    _buildWalletsList(currencyFormatter, syncProvider),
                    const SizedBox(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Giao dịch gần đây',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AllTransactionsScreen(),
                              ),
                            );
                          },
                          child: const Text('Xem tất cả'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // NEW: Use both offline and online data for transactions
                    _buildTransactionsList(currencyFormatter, syncProvider),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddTransaction,
        tooltip: 'Thêm giao dịch',
        child: const Icon(Icons.add),
      ),
    );
  }

  // NEW: Enhanced wallets list with offline-first approach
  Widget _buildWalletsList(
    NumberFormat currencyFormatter,
    SyncStatusProvider syncProvider,
  ) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final auth = FirebaseAuth.instance;

    // NEW: Show offline data immediately, then update with online data
    if (!syncProvider.isOnline && _localWallets.isNotEmpty) {
      return _buildWalletListContent(
        _localWallets,
        currencyFormatter,
        auth,
        userProvider,
      );
    }

    return StreamBuilder<List<Wallet>>(
      stream: _databaseService.getWalletsStream(userProvider),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _localWallets.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          // Fall back to local data on error
          if (_localWallets.isNotEmpty) {
            return _buildWalletListContent(
              _localWallets,
              currencyFormatter,
              auth,
              userProvider,
            );
          }
          return Center(child: Text('Đã xảy ra lỗi: ${snapshot.error}'));
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          if (_localWallets.isNotEmpty) {
            return _buildWalletListContent(
              _localWallets,
              currencyFormatter,
              auth,
              userProvider,
            );
          }
          return const Center(child: Text('Chưa có ví nào. Hãy thêm ví mới!'));
        }

        final wallets = snapshot.data!;
        return _buildWalletListContent(
          wallets,
          currencyFormatter,
          auth,
          userProvider,
        );
      },
    );
  }

  Widget _buildWalletListContent(
    List<Wallet> wallets,
    NumberFormat currencyFormatter,
    FirebaseAuth auth,
    UserProvider userProvider,
  ) {
    final totalBalance = wallets.fold(
      0.0,
      (sum, wallet) => sum + wallet.balance,
    );

    return Column(
      children: [
        // Total balance card
        Card(
          elevation: 2,
          color: Theme.of(context).colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tổng số dư',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  currencyFormatter.format(totalBalance),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Wallets list
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: wallets.length,
          itemBuilder: (context, index) {
            final wallet = wallets[index];
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
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).primaryColor.withOpacity(0.2),
                  child: Icon(walletIcon, color: iconColor),
                ),
                title: Text(wallet.name + walletTag),
                subtitle: Text(currencyFormatter.format(wallet.balance)),
                trailing: wallet.ownerId == auth.currentUser?.uid
                    ? Switch(
                        value: wallet.isVisibleToPartner,
                        onChanged: (newValue) {
                          _databaseService.updateWalletVisibility(
                            wallet.id,
                            newValue,
                          );
                        },
                      )
                    : null,
              ),
            );
          },
        ),
      ],
    );
  }

  // NEW: Enhanced transactions list with offline-first approach
  Widget _buildTransactionsList(
    NumberFormat currencyFormatter,
    SyncStatusProvider syncProvider,
  ) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // NEW: Show offline data immediately when offline
    if (!syncProvider.isOnline && _localTransactions.isNotEmpty) {
      return _buildTransactionListContent(_localTransactions);
    }

    return StreamBuilder<List<TransactionModel>>(
      stream: _databaseService.getTransactionsStream(
        userProvider,
        _startDate,
        _endDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            _localTransactions.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          if (_localTransactions.isNotEmpty) {
            return _buildTransactionListContent(_localTransactions);
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Chưa có giao dịch nào trong khoảng thời gian này',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final transactions = snapshot.data!;
        return _buildTransactionListContent(transactions);
      },
    );
  }

  Widget _buildTransactionListContent(List<TransactionModel> transactions) {
    final groupedTransactions = groupBy(transactions, (TransactionModel t) {
      return DateTime(t.date.year, t.date.month, t.date.day);
    });

    return Column(
      children: groupedTransactions.entries
          .take(7) // Show only last 7 days on dashboard
          .map((entry) {
            return DailyTransactionsGroup(
              date: entry.key,
              transactions: entry.value,
            );
          })
          .toList(),
    );
  }

  // NEW: Show sync details dialog
  void _showSyncDetailsDialog(SyncStatusProvider syncProvider) {
    final stats = syncProvider.getDetailedStats();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sync, color: Colors.blue),
            SizedBox(width: 8),
            Text('Trạng thái đồng bộ'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow(
                'Kết nối mạng:',
                syncProvider.isConnectedToNetwork ? '🟢 Online' : '🔴 Offline',
              ),
              _buildStatRow(
                'Firebase:',
                syncProvider.isFirebaseConnected
                    ? '🟢 Kết nối'
                    : '🔴 Ngắt kết nối',
              ),
              _buildStatRow(
                'Dữ liệu chờ sync:',
                '${syncProvider.pendingCount}',
              ),
              _buildStatRow(
                'Đồng bộ thành công:',
                '${syncProvider.successfulSyncs}',
              ),
              _buildStatRow('Đồng bộ thất bại:', '${syncProvider.failedSyncs}'),

              if (syncProvider.lastSyncTime != null)
                _buildStatRow(
                  'Lần sync cuối:',
                  _formatDateTime(syncProvider.lastSyncTime!),
                ),

              if (syncProvider.lastError != null) ...[
                const SizedBox(height: 8),
                const Text(
                  'Lỗi gần nhất:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    syncProvider.lastError!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (syncProvider.pendingCount > 0 && syncProvider.isOnline)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                try {
                  await syncProvider.forceSyncNow();
                  await _loadOfflineData();
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Lỗi đồng bộ: $e')));
                }
              },
              child: const Text('Đồng bộ ngay'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    return '${diff.inDays} ngày trước';
  }
}
