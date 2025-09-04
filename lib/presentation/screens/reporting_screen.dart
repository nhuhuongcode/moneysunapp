// lib/presentation/screens/reporting_screen.dart - UPDATED VERSION

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/sync_status_provider.dart'; // NEW
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart'; // NEW
import 'package:moneysun/presentation/screens/category_detail_report_screen.dart';
import 'package:moneysun/presentation/widgets/connection_status_banner.dart'; // NEW
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:collection/collection.dart';

class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final OfflineSyncService _syncService = OfflineSyncService(); // NEW

  TimeFilter _selectedTimeFilter = TimeFilter.thisMonth;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month + 1,
    0,
  );

  // NEW: Local cache for offline data
  ReportData? _cachedReportData;
  bool _isLoadingLocal = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadOfflineReportData(); // NEW: Load offline data first
  }

  // NEW: Load offline report data
  Future<void> _loadOfflineReportData() async {
    setState(() {
      _isLoadingLocal = true;
    });

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId != null) {
        // Get offline transactions
        final transactions = await _syncService.getTransactions(
          userId: userId,
          startDate: _startDate,
          endDate: _endDate,
        );

        // Process transactions to create report data
        _cachedReportData = _processTransactionsToReportData(transactions);

        setState(() {
          _isLoadingLocal = false;
        });
      }
    } catch (e) {
      print('Error loading offline report data: $e');
      setState(() {
        _isLoadingLocal = false;
      });
    }
  }

  // NEW: Process transactions to create report data offline
  ReportData _processTransactionsToReportData(
    List<TransactionModel> transactions,
  ) {
    double totalIncome = 0;
    double totalExpense = 0;
    Map<Category, double> expenseByCategory = {};
    Map<Category, double> incomeByCategory = {};

    // Create dummy categories for unknown categories
    final unknownExpenseCategory = Category(
      id: 'unknown_expense',
      name: 'Chưa phân loại',
      ownerId: '',
      type: 'expense',
    );
    final unknownIncomeCategory = Category(
      id: 'unknown_income',
      name: 'Chưa phân loại',
      ownerId: '',
      type: 'income',
    );

    for (final transaction in transactions) {
      if (transaction.type == TransactionType.income) {
        totalIncome += transaction.amount;

        // Use category name as key since we don't have full category objects offline
        final categoryKey = transaction.categoryName.isNotEmpty
            ? Category(
                id: transaction.categoryId ?? 'unknown',
                name: transaction.categoryName,
                ownerId: '',
                type: 'income',
              )
            : unknownIncomeCategory;

        incomeByCategory.update(
          categoryKey,
          (value) => value + transaction.amount,
          ifAbsent: () => transaction.amount,
        );
      } else if (transaction.type == TransactionType.expense) {
        totalExpense += transaction.amount;

        final categoryKey = transaction.categoryName.isNotEmpty
            ? Category(
                id: transaction.categoryId ?? 'unknown',
                name: transaction.categoryName,
                ownerId: '',
                type: 'expense',
              )
            : unknownExpenseCategory;

        expenseByCategory.update(
          categoryKey,
          (value) => value + transaction.amount,
          ifAbsent: () => transaction.amount,
        );
      }
    }

    return ReportData(
      totalIncome: totalIncome,
      totalExpense: totalExpense,
      expenseByCategory: expenseByCategory,
      incomeByCategory: incomeByCategory,
      rawTransactions: transactions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncProvider = Provider.of<SyncStatusProvider>(context); // NEW

    return Scaffold(
      appBar: TimeFilterAppBarWithTabs(
        title: 'Báo cáo',
        selectedFilter: _selectedTimeFilter,
        startDate: _startDate,
        endDate: _endDate,
        onFilterChanged: (filter, start, end) {
          setState(() {
            _selectedTimeFilter = filter;
            _startDate = start;
            _endDate = end;
          });
          // NEW: Reload offline data when time filter changes
          _loadOfflineReportData();
        },
        tabController: _tabController,
        tabs: const [
          Tab(text: 'Chi tiêu'),
          Tab(text: 'Thu nhập'),
        ],
        // NEW: Add sync status
        syncStatus: syncProvider.getSyncStatusInfo(),
        onSyncPressed: () async {
          try {
            await syncProvider.forceSyncNow();
            await _loadOfflineReportData(); // Reload after sync
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Đồng bộ và cập nhật báo cáo thành công!'),
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

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                ExpenseReportPage(
                  startDate: _startDate,
                  endDate: _endDate,
                  syncService: _syncService, // NEW
                  cachedReportData: _cachedReportData, // NEW
                ),
                IncomeReportPage(
                  startDate: _startDate,
                  endDate: _endDate,
                  syncService: _syncService, // NEW
                  cachedReportData: _cachedReportData, // NEW
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // NEW: Show sync details dialog
  void _showSyncDetailsDialog(SyncStatusProvider syncProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.analytics, color: Colors.blue),
            SizedBox(width: 8),
            Text('Trạng thái báo cáo'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildStatRow(
                'Kết nối:',
                syncProvider.isOnline ? '🟢 Online' : '🔴 Offline',
              ),
              _buildStatRow(
                'Dữ liệu báo cáo:',
                _cachedReportData != null ? '✅ Có sẵn' : '❌ Chưa có',
              ),
              _buildStatRow(
                'Số giao dịch:',
                '${_cachedReportData?.rawTransactions.length ?? 0}',
              ),
              _buildStatRow(
                'Tổng thu nhập:',
                NumberFormat.currency(
                  locale: 'vi_VN',
                  symbol: '₫',
                ).format(_cachedReportData?.totalIncome ?? 0),
              ),
              _buildStatRow(
                'Tổng chi tiêu:',
                NumberFormat.currency(
                  locale: 'vi_VN',
                  symbol: '₫',
                ).format(_cachedReportData?.totalExpense ?? 0),
              ),

              if (syncProvider.lastError != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Lỗi: ${syncProvider.lastError!}',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (syncProvider.isOnline)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await _loadOfflineReportData();
              },
              child: const Text('Cập nhật báo cáo'),
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
            width: 100,
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

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

// NEW: Updated ExpenseReportPage with offline support
class ExpenseReportPage extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final OfflineSyncService syncService; // NEW
  final ReportData? cachedReportData; // NEW

  const ExpenseReportPage({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.syncService, // NEW
    this.cachedReportData, // NEW
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final syncProvider = Provider.of<SyncStatusProvider>(context); // NEW
    final databaseService = DatabaseService();
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // NEW: Show cached data immediately when offline
    if (!syncProvider.isOnline && cachedReportData != null) {
      return _buildReportContent(
        cachedReportData!,
        currencyFormatter,
        context,
        isOffline: true,
      );
    }

    return FutureBuilder<ReportData>(
      future: databaseService.getReportData(userProvider, startDate, endDate),
      builder: (context, snapshot) {
        // Show cached data while loading online data
        if (snapshot.connectionState == ConnectionState.waiting &&
            cachedReportData != null) {
          return _buildReportContent(
            cachedReportData!,
            currencyFormatter,
            context,
            isOffline: true,
          );
        }

        if (snapshot.hasError) {
          // Fall back to cached data on error
          if (cachedReportData != null) {
            return Column(
              children: [
                // Error banner
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
                          'Hiển thị dữ liệu offline',
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
                  child: _buildReportContent(
                    cachedReportData!,
                    currencyFormatter,
                    context,
                    isOffline: true,
                  ),
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
                  'Lỗi tải dữ liệu báo cáo',
                  style: TextStyle(color: Colors.red.shade600),
                ),
                ElevatedButton(
                  onPressed: () => (context as Element).reassemble(),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.expenseByCategory.isEmpty) {
          if (cachedReportData != null &&
              cachedReportData!.expenseByCategory.isNotEmpty) {
            return _buildReportContent(
              cachedReportData!,
              currencyFormatter,
              context,
              isOffline: true,
            );
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.trending_down, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Không có dữ liệu chi tiêu',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  Text(
                    'trong khoảng thời gian này',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final report = snapshot.data!;
        return _buildReportContent(report, currencyFormatter, context);
      },
    );
  }

  Widget _buildReportContent(
    ReportData report,
    NumberFormat currencyFormatter,
    BuildContext context, {
    bool isOffline = false,
  }) {
    final expenseCategories = report.expenseByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: () async {
        final syncProvider = Provider.of<SyncStatusProvider>(
          context,
          listen: false,
        );
        if (syncProvider.isOnline) {
          try {
            await syncProvider.forceSyncNow();
          } catch (e) {
            print('Sync failed during refresh: $e');
          }
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Show offline indicator
            if (isOffline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.offline_bolt,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Báo cáo từ dữ liệu offline (${report.rawTransactions.length} giao dịch)',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            _buildHeaderCard(
              'Chi tiêu',
              report.totalExpense,
              Colors.red,
              currencyFormatter,
            ),
            const SizedBox(height: 16),
            _buildExpenseChart(expenseCategories),
            const SizedBox(height: 16),
            _buildCategoryList(
              expenseCategories,
              currencyFormatter,
              report.totalExpense,
              context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    String title,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tổng $title',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              formatter.format(amount),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseChart(List<MapEntry<Category, double>> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();

    final chartData = categories.take(8).map((entry) {
      final amount = entry.value;
      return PieChartSectionData(
        value: amount,
        title: '',
        color: _getCategoryColor(categories.indexOf(entry)),
        radius: 60,
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Phân bố chi tiêu theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: chartData,
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildChartLegend(categories.take(8).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(
    List<MapEntry<Category, double>> categories,
    NumberFormat formatter,
    double totalAmount,
    BuildContext context,
  ) {
    return Card(
      child: Column(
        children: [
          ...categories.map((entry) {
            final category = entry.key;
            final amount = entry.value;
            final percentage = totalAmount > 0
                ? (amount / totalAmount * 100)
                : 0;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _getCategoryColor(
                  categories.indexOf(entry),
                ).withOpacity(0.2),
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: _getCategoryColor(categories.indexOf(entry)),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(category.name),
              trailing: Text(
                formatter.format(amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryDetailReportScreen(
                      categoryId: category.id,
                      categoryName: category.name,
                      initialStartDate: startDate,
                      initialEndDate: endDate,
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildChartLegend(List<MapEntry<Category, double>> categories) {
    return Wrap(
      children: categories.map((entry) {
        final index = categories.indexOf(entry);
        final color = _getCategoryColor(index);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text(entry.key.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getCategoryColor(int index) {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.purple,
      Colors.blue,
      Colors.green,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
    ];
    return colors[index % colors.length];
  }
}

// NEW: Updated IncomeReportPage with offline support (similar structure)
class IncomeReportPage extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final OfflineSyncService syncService; // NEW
  final ReportData? cachedReportData; // NEW

  const IncomeReportPage({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.syncService, // NEW
    this.cachedReportData, // NEW
  });

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final syncProvider = Provider.of<SyncStatusProvider>(context); // NEW
    final databaseService = DatabaseService();
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    // NEW: Show cached data immediately when offline
    if (!syncProvider.isOnline && cachedReportData != null) {
      return _buildReportContent(
        cachedReportData!,
        currencyFormatter,
        context,
        isOffline: true,
      );
    }

    return FutureBuilder<ReportData>(
      future: databaseService.getReportData(userProvider, startDate, endDate),
      builder: (context, snapshot) {
        // Show cached data while loading
        if (snapshot.connectionState == ConnectionState.waiting &&
            cachedReportData != null) {
          return _buildReportContent(
            cachedReportData!,
            currencyFormatter,
            context,
            isOffline: true,
          );
        }

        if (snapshot.hasError) {
          if (cachedReportData != null) {
            return Column(
              children: [
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
                      Text(
                        'Hiển thị dữ liệu offline',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _buildReportContent(
                    cachedReportData!,
                    currencyFormatter,
                    context,
                    isOffline: true,
                  ),
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
                  'Lỗi tải dữ liệu báo cáo',
                  style: TextStyle(color: Colors.red.shade600),
                ),
              ],
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.incomeByCategory.isEmpty) {
          if (cachedReportData != null &&
              cachedReportData!.incomeByCategory.isNotEmpty) {
            return _buildReportContent(
              cachedReportData!,
              currencyFormatter,
              context,
              isOffline: true,
            );
          }
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.trending_up, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Không có dữ liệu thu nhập',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  Text(
                    'trong khoảng thời gian này',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final report = snapshot.data!;
        return _buildReportContent(report, currencyFormatter, context);
      },
    );
  }

  Widget _buildReportContent(
    ReportData report,
    NumberFormat currencyFormatter,
    BuildContext context, {
    bool isOffline = false,
  }) {
    final incomeCategories = report.incomeByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: () async {
        final syncProvider = Provider.of<SyncStatusProvider>(
          context,
          listen: false,
        );
        if (syncProvider.isOnline) {
          try {
            await syncProvider.forceSyncNow();
          } catch (e) {
            print('Sync failed during refresh: $e');
          }
        }
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Show offline indicator
            if (isOffline)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.offline_bolt,
                      color: Colors.blue.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Báo cáo từ dữ liệu offline (${report.rawTransactions.length} giao dịch)',
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            _buildHeaderCard(
              'Thu nhập',
              report.totalIncome,
              Colors.green,
              currencyFormatter,
            ),
            const SizedBox(height: 16),
            _buildIncomeChart(incomeCategories),
            const SizedBox(height: 16),
            _buildCategoryList(
              incomeCategories,
              currencyFormatter,
              report.totalIncome,
              context,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(
    String title,
    double amount,
    Color color,
    NumberFormat formatter,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tổng $title',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              formatter.format(amount),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncomeChart(List<MapEntry<Category, double>> categories) {
    if (categories.isEmpty) return const SizedBox.shrink();

    final chartData = categories.take(8).map((entry) {
      final amount = entry.value;
      return PieChartSectionData(
        value: amount,
        title: '',
        color: _getCategoryColor(categories.indexOf(entry)),
        radius: 60,
      );
    }).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Phân bố thu nhập theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: chartData,
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildChartLegend(categories.take(8).toList()),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(
    List<MapEntry<Category, double>> categories,
    NumberFormat formatter,
    double totalAmount,
    BuildContext context,
  ) {
    return Card(
      child: Column(
        children: [
          ...categories.map((entry) {
            final category = entry.key;
            final amount = entry.value;
            final percentage = totalAmount > 0
                ? (amount / totalAmount * 100)
                : 0;

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: _getCategoryColor(
                  categories.indexOf(entry),
                ).withOpacity(0.2),
                child: Text(
                  '${percentage.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: _getCategoryColor(categories.indexOf(entry)),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(category.name),
              trailing: Text(
                formatter.format(amount),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CategoryDetailReportScreen(
                      categoryId: category.id,
                      categoryName: category.name,
                      initialStartDate: startDate,
                      initialEndDate: endDate,
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildChartLegend(List<MapEntry<Category, double>> categories) {
    return Wrap(
      children: categories.map((entry) {
        final index = categories.indexOf(entry);
        final color = _getCategoryColor(index);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, color: color),
              const SizedBox(width: 4),
              Text(entry.key.name, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getCategoryColor(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
      Colors.teal,
      Colors.amber,
      Colors.indigo,
    ];
    return colors[index % colors.length];
  }
}
