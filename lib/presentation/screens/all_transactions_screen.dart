// lib/presentation/screens/all_transactions_screen.dart - UPDATED VERSION

import 'package:flutter/material.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/sync_status_provider.dart'; // NEW
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart'; // NEW
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart'; // NEW
import 'package:moneysun/presentation/widgets/connection_status_banner.dart'; // NEW
import 'package:moneysun/presentation/widgets/daily_transactions_group.dart';
import 'package:provider/provider.dart';
import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AllTransactionsScreen extends StatefulWidget {
  const AllTransactionsScreen({super.key});

  @override
  State<AllTransactionsScreen> createState() => _AllTransactionsScreenState();
}

class _AllTransactionsScreenState extends State<AllTransactionsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final OfflineSyncService _syncService = OfflineSyncService(); // NEW

  // Time filter state
  TimeFilter _selectedFilter = TimeFilter.thisMonth;
  late DateTime _startDate;
  late DateTime _endDate;

  // NEW: Local state for offline data
  List<TransactionModel> _localTransactions = [];
  bool _isLoadingLocal = true;

  @override
  void initState() {
    super.initState();
    _updateDateRange(TimeFilter.thisMonth);
    _loadOfflineData(); // NEW: Load offline data first
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

    // NEW: Reload offline data when date range changes
    _loadOfflineData();
  }

  // NEW: Load offline data first for immediate UI response
  Future<void> _loadOfflineData() async {
    setState(() {
      _isLoadingLocal = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        final localTransactions = await _syncService.getTransactions(
          userId: userId,
          startDate: _startDate,
          endDate: _endDate,
        );

        setState(() {
          _localTransactions = localTransactions;
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

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final syncProvider = Provider.of<SyncStatusProvider>(context); // NEW

    return Scaffold(
      appBar: TimeFilterAppBar(
        title: 'Lịch sử Giao dịch',
        selectedFilter: _selectedFilter,
        startDate: _startDate,
        endDate: _endDate,
        onFilterChanged: (filter, start, end) {
          setState(() {
            _selectedFilter = filter;
            _startDate = start;
            _endDate = end;
          });
          // NEW: Reload offline data when filter changes
          _loadOfflineData();
        },
        // NEW: Add sync status to AppBar
        syncStatus: syncProvider.getSyncStatusInfo(),
        onSyncPressed: () async {
          try {
            await syncProvider.forceSyncNow();
            await _loadOfflineData(); // Reload after sync
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Đồng bộ thành công!'),
                backgroundColor: Colors.green,
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Lỗi đồng bộ: $e'),
                backgroundColor: Colors.red,
              ),
            );
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

          // Transactions list
          Expanded(child: _buildTransactionsList(userProvider, syncProvider)),
        ],
      ),
    );
  }

  // NEW: Enhanced transactions list with offline-first approach
  Widget _buildTransactionsList(
    UserProvider userProvider,
    SyncStatusProvider syncProvider,
  ) {
    // Show offline data immediately when offline or loading
    if (!syncProvider.isOnline && _localTransactions.isNotEmpty) {
      return _buildTransactionListContent(_localTransactions);
    }

    // Show loading indicator only if no local data available
    if (_isLoadingLocal && _localTransactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<TransactionModel>>(
      stream: _databaseService.getTransactionsStream(
        userProvider,
        _startDate,
        _endDate,
      ),
      builder: (context, snapshot) {
        // While waiting for online data, show offline data if available
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (_localTransactions.isNotEmpty) {
            return _buildTransactionListContent(_localTransactions);
          }
          return const Center(child: CircularProgressIndicator());
        }

        // On error, fall back to offline data
        if (snapshot.hasError) {
          if (_localTransactions.isNotEmpty) {
            return Column(
              children: [
                // Show error banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  color: Colors.orange.shade100,
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning,
                        color: Colors.orange.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hiển thị dữ liệu offline (${_localTransactions.length} giao dịch)',
                          style: TextStyle(
                            color: Colors.orange.shade700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildTransactionListContent(_localTransactions),
                ),
              ],
            );
          }
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  'Lỗi tải dữ liệu',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vui lòng kiểm tra kết nối và thử lại',
                  style: TextStyle(color: Colors.red.shade400),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {});
                    _loadOfflineData();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          );
        }

        // No data case
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          if (_localTransactions.isNotEmpty) {
            return _buildTransactionListContent(_localTransactions);
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Không có giao dịch nào',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Trong khoảng thời gian này',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final transactions = snapshot.data!;
        return RefreshIndicator(
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
          },
          child: _buildTransactionListContent(transactions),
        );
      },
    );
  }

  Widget _buildTransactionListContent(List<TransactionModel> transactions) {
    // Group by date using DailyTransactionsGroup template
    final groupedTransactions = groupBy(
      transactions,
      (TransactionModel t) => DateTime(t.date.year, t.date.month, t.date.day),
    );

    if (groupedTransactions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'Không có giao dịch nào',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Trong khoảng thời gian này',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: groupedTransactions.length,
      itemBuilder: (context, index) {
        final entry = groupedTransactions.entries.elementAt(index);
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: DailyTransactionsGroup(
            date: entry.key,
            transactions: entry.value,
          ),
        );
      },
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
            Text('Chi tiết đồng bộ'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow(
                'Trạng thái kết nối:',
                syncProvider.isConnectedToNetwork ? '🟢 Online' : '🔴 Offline',
              ),
              _buildStatRow(
                'Firebase:',
                syncProvider.isFirebaseConnected
                    ? '🟢 Kết nối'
                    : '🔴 Ngắt kết nối',
              ),
              _buildStatRow(
                'Trạng thái sync:',
                _getSyncStatusText(syncProvider.syncStatus),
              ),
              _buildStatRow(
                'Đồng bộ thành công:',
                '${syncProvider.successfulSyncs}',
              ),
              _buildStatRow('Đồng bộ thất bại:', '${syncProvider.failedSyncs}'),
              _buildStatRow(
                'Dữ liệu chờ sync:',
                '${syncProvider.pendingCount}',
              ),
              _buildStatRow(
                'Dữ liệu offline:',
                '${_localTransactions.length} giao dịch',
              ),

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
                    border: Border.all(color: Colors.red.shade200),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đồng bộ thành công!')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Lỗi đồng bộ: $e')));
                }
              },
              child: const Text('Đồng bộ ngay'),
            ),
          if (!syncProvider.isOnline)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _loadOfflineData();
              },
              child: const Text('Tải lại dữ liệu'),
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

  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.idle:
        return '⚪ Chờ';
      case SyncStatus.syncing:
        return '🔄 Đang đồng bộ';
      case SyncStatus.success:
        return '✅ Thành công';
      case SyncStatus.error:
        return '❌ Lỗi';
    }
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
