import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/screens/add_transaction_screen.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/presentation/screens/all_transactions_screen.dart';
import 'package:moneysun/presentation/screens/transfer_screen.dart';
import 'package:moneysun/presentation/widgets/summary_card.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart'; // Thêm package collection
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

  Key _refreshKey = UniqueKey();

  // Add time filter state
  TimeFilter _selectedTimeFilter = TimeFilter.thisMonth;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  Future<void> _navigateToAddTransaction() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const AddTransactionScreen()),
    );

    // FIX: Reload data if transaction was added
    if (result == true) {
      setState(() {
        _refreshKey = UniqueKey(); // Force rebuild
      });
    }
  }

  // Hàm để hiển thị dialog thêm ví
  void _showAddWalletDialog() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final nameController = TextEditingController();
    final balanceController = TextEditingController();

    // Biến để lưu lựa chọn của người dùng (cá nhân hay chung)
    String ownerType = 'personal';

    showDialog(
      context: context,
      builder: (context) {
        // Sử dụng StatefulBuilder để dialog có thể tự cập nhật state bên trong nó
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
                  // Chỉ hiển thị lựa chọn này nếu user đã có partner
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
                  onPressed: () {
                    final name = nameController.text;
                    final balance =
                        double.tryParse(balanceController.text) ?? 0.0;

                    // Xác định ownerId dựa trên lựa chọn
                    final String ownerId;
                    if (ownerType == 'shared') {
                      ownerId = userProvider.partnershipId!;
                    } else {
                      ownerId = _authService.getCurrentUser()!.uid;
                    }

                    if (name.isNotEmpty) {
                      _databaseService.addWallet(name, balance, ownerId);
                      Navigator.pop(context);
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
    // Dùng để định dạng tiền tệ
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

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
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Cập nhật lại dữ liệu khi kéo để làm mới
          setState(() {
            _refreshKey = UniqueKey(); // Force rebuild
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
              _buildWalletsList(currencyFormatter),
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
              _buildFilteredTransactions(currencyFormatter),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToAddTransaction,
        tooltip: 'Thêm giao dịch',
        child: const Icon(Icons.add),
      ),
    );
  }

  // Widget xây dựng danh sách ví từ Stream
  Widget _buildWalletsList(NumberFormat currencyFormatter) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final auth = FirebaseAuth.instance;
    return StreamBuilder<List<Wallet>>(
      stream: _databaseService.getWalletsStream(userProvider),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Đã xảy ra lỗi: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Chưa có ví nào. Hãy thêm ví mới!'));
        }

        final wallets = snapshot.data!;

        // Tính tổng số dư
        final totalBalance = wallets.fold(
          0.0,
          (sum, wallet) => sum + wallet.balance,
        );

        return Column(
          children: [
            // Thẻ tổng quan
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
            // Danh sách chi tiết
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: wallets.length,
              itemBuilder: (context, index) {
                final wallet = wallets[index];
                IconData walletIcon;
                String walletTag = ""; // Nhãn phụ (tag)
                Color iconColor = Colors.green; // Mặc định
                if (wallet.ownerId == userProvider.partnershipId) {
                  walletIcon = Icons.people;
                  walletTag = " (Chung)";
                  iconColor = Colors.orange; // Màu khác cho ví chung
                } else if (wallet.ownerId == userProvider.partnerUid) {
                  walletIcon = Icons.military_tech;
                  walletTag = " (Partner)";
                  iconColor = Colors.blueGrey; // Màu khác cho ví của partner
                } else {
                  // Ví của chính mình
                  walletIcon = Icons.person;
                  walletTag = ""; // Không cần nhãn
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
      },
    );
  }

  Widget _buildRecentTransactions(NumberFormat currencyFormatter) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    return StreamBuilder<List<TransactionModel>>(
      stream: _databaseService.getRecentTransactionsStream(userProvider),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Chưa có giao dịch nào.'));
        }
        final transactions = snapshot.data!;

        final groupedTransactions = groupBy(transactions, (TransactionModel t) {
          return DateTime(t.date.year, t.date.month, t.date.day);
        });
        return Column(
          children: groupedTransactions.entries.map((entry) {
            return DailyTransactionsGroup(
              date: entry.key,
              transactions: entry.value,
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildFilteredTransactions(NumberFormat currencyFormatter) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return StreamBuilder<List<TransactionModel>>(
      stream: _databaseService.getTransactionsStream(
        userProvider,
        _startDate,
        _endDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
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

        // FIX: Group by date and use DailyTransactionsGroup template
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
