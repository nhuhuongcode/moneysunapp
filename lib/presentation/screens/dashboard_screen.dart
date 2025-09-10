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

class _DashboardScreenState extends State<DashboardScreen> {
  final AuthService _authService = AuthService();

  Key _refreshKey = UniqueKey();

  // Add time filter state
  TimeFilter _selectedTimeFilter = TimeFilter.thisMonth;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  @override
  void initState() {
    super.initState();
    _loadDataWithDataService();
  }

  Future<void> _loadDataWithDataService() async {
    // Load data using  providers
    try {
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final transactionProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );

      await Future.wait([
        walletProvider.loadWallets(),
        transactionProvider.loadTransactions(
          startDate: _startDate,
          endDate: _endDate,
        ),
      ]);

      debugPrint('✅ Dashboard data loaded with DataService');
    } catch (e) {
      debugPrint('❌ Error loading dashboard data with DataService: $e');
    }
  }

  Future<void> _navigateToAddTransaction() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AddTransactionScreen()),
    );

    // Reload data if transaction was added
    if (result == true) {
      await _loadDataWithDataService();
      setState(() {
        _refreshKey = UniqueKey(); // Force rebuild
      });
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
              title: const Text('Thêm ví mới (DataService)'),
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
                      final walletProvider = Provider.of<WalletProvider>(
                        context,
                        listen: false,
                      );

                      final success = await walletProvider.addWallet(
                        name: name,
                        initialBalance: balance,
                        ownerId: ownerId,
                      );

                      Navigator.pop(context);

                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Ví đã được thêm thành công với DataService',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Không thể thêm ví. Vui lòng thử lại.',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
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

    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return Scaffold(
          appBar: TimeFilterAppBar(
            title: 'Tổng quan (DataService)',
            selectedFilter: _selectedTimeFilter,
            startDate: _startDate,
            endDate: _endDate,
            onFilterChanged: (filter, start, end) {
              setState(() {
                _selectedTimeFilter = filter;
                _startDate = start;
                _endDate = end;
              });
              // Reload transactions with new date range
              final transactionProvider = Provider.of<TransactionProvider>(
                context,
                listen: false,
              );
              transactionProvider.loadTransactions(
                startDate: start,
                endDate: end,
              );
            },
            // Add sync status info
            syncStatus: SyncStatusInfo(
              status: connectionStatus.isOnline
                  ? ConnectivityStatus.online
                  : ConnectivityStatus.offline,
              lastSyncTime: connectionStatus.lastSyncTime,
              pendingCount: connectionStatus.pendingItems,
              errorMessage: connectionStatus.lastError,
              isSyncing: connectionStatus.isSyncing,
            ),
            onSyncPressed: () async {
              // Manual sync trigger
              try {
                final dataService = Provider.of<DataService>(
                  context,
                  listen: false,
                );
                await dataService.forceSyncNow();

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đồng bộ thành công'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Đồng bộ thất bại: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await _loadDataWithDataService();
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
                  //  Summary Card with DataService
                  SummaryCard(
                    initialStartDate: _startDate,
                    initialEndDate: _endDate,
                  ),
                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Các ví của bạn (DataService)',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      IconButton(
                        onPressed: _showAddWalletDialog,
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Thêm ví mới',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildWalletsListWithDataService(currencyFormatter),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Giao dịch gần đây (DataService)',
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
                  _buildFilteredTransactionsWithDataService(currencyFormatter),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: _navigateToAddTransaction,
            tooltip: 'Thêm giao dịch (DataService)',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  Widget _buildWalletsListWithDataService(NumberFormat currencyFormatter) {
    return Consumer<WalletProvider>(
      builder: (context, walletProvider, child) {
        if (walletProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (walletProvider.hasError) {
          return Center(
            child: Column(
              children: [
                Text('Lỗi DataService: ${walletProvider.error}'),
                ElevatedButton(
                  onPressed: () =>
                      walletProvider.loadWallets(forceRefresh: true),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          );
        }

        if (walletProvider.wallets.isEmpty) {
          return const Center(
            child: Text('Chưa có ví nào. Hãy thêm ví mới với DataService!'),
          );
        }

        final wallets = walletProvider.wallets;

        return Column(
          children: [
            //  total balance card
            Card(
              elevation: 2,
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tổng số dư',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          currencyFormatter.format(walletProvider.totalBalance),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cá nhân: ${currencyFormatter.format(walletProvider.personalBalance)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            Text(
                              'Chung: ${currencyFormatter.format(walletProvider.sharedBalance)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        Icon(
                          walletProvider.isLoading
                              ? Icons.sync
                              : Icons.account_balance_wallet,
                          color: Colors.grey,
                          size: 16,
                        ),
                      ],
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
                final userProvider = Provider.of<UserProvider>(
                  context,
                  listen: false,
                );

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
                    trailing:
                        wallet.ownerId == FirebaseAuth.instance.currentUser?.uid
                        ? Switch(
                            value: wallet.isVisibleToPartner,
                            onChanged: (newValue) {
                              // TODO: Implement updateWalletVisibility with DataService
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Cập nhật visibility chưa được implement với DataService',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
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
      },
    );
  }

  Widget _buildFilteredTransactionsWithDataService(
    NumberFormat currencyFormatter,
  ) {
    return Consumer<TransactionProvider>(
      builder: (context, transactionProvider, child) {
        if (transactionProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (transactionProvider.hasError) {
          return Center(
            child: Column(
              children: [
                Text('Lỗi DataService: ${transactionProvider.error}'),
                ElevatedButton(
                  onPressed: () => transactionProvider.loadTransactions(
                    startDate: _startDate,
                    endDate: _endDate,
                    forceRefresh: true,
                  ),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          );
        }

        if (transactionProvider.transactions.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Chưa có giao dịch nào trong khoảng thời gian này (DataService)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final transactions = transactionProvider.transactions;

        // Group by date and use DailyTransactionsGroup template
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
      },
    );
  }
}
