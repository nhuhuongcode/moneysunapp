// lib/presentation/screens/_main_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/presentation/screens/all_transactions_screen.dart';
import 'package:moneysun/presentation/screens/dashboard_screen.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

import 'package:provider/provider.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _widgetOptions = <Widget>[
    DashboardScreen(), //  trang tổng quan với DataService
    ReportingScreen(), //  trang báo cáo với DataService
    BudgetScreen(), //  trang ngân sách với DataService
    ProfileScreen(), //  trang cài đặt với DataService
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return Scaffold(
          body: Center(child: _widgetOptions.elementAt(_selectedIndex)),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Add DataService status indicator at bottom
              if (connectionStatus.shouldShowBanner)
                Container(
                  width: double.infinity,
                  height: 24,
                  color: connectionStatus.statusColor.withOpacity(0.8),
                  child: Center(
                    child: Text(
                      'DataService: ${connectionStatus.statusMessage}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),

              BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                items: const <BottomNavigationBarItem>[
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard),
                    label: 'Tổng quan',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.pie_chart),
                    label: 'Báo cáo',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.account_balance_wallet),
                    label: 'Ngân sách',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.settings),
                    label: 'Cài đặt',
                  ),
                ],
                currentIndex: _selectedIndex,
                selectedItemColor: Theme.of(context).primaryColor,
                unselectedItemColor: Colors.grey,
                onTap: _onItemTapped,
                showUnselectedLabels: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

// lib/presentation/screens/_reporting_screen.dart
class ReportingScreen extends StatefulWidget {
  const ReportingScreen({super.key});

  @override
  State<ReportingScreen> createState() => _ReportingScreenState();
}

class _ReportingScreenState extends State<ReportingScreen> {
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
    _loadReportDataWithDataService();
  }

  Future<void> _loadReportDataWithDataService() async {
    final transactionProvider = Provider.of<TransactionProvider>(
      context,
      listen: false,
    );

    await transactionProvider.loadTransactions(
      startDate: _startDate,
      endDate: _endDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return Scaffold(
          appBar: TimeFilterAppBar(
            title: 'Báo cáo (DataService)',
            selectedFilter: _selectedTimeFilter,
            startDate: _startDate,
            endDate: _endDate,
            onFilterChanged: (filter, start, end) {
              setState(() {
                _selectedTimeFilter = filter;
                _startDate = start;
                _endDate = end;
              });
              _loadReportDataWithDataService();
            },
            syncStatus: SyncStatusInfo(
              status: connectionStatus.isOnline
                  ? ConnectivityStatus.online
                  : ConnectivityStatus.offline,
              lastSyncTime: connectionStatus.lastSyncTime,
              pendingCount: connectionStatus.pendingItems,
              isSyncing: connectionStatus.isSyncing,
            ),
          ),
          body: Consumer<TransactionProvider>(
            builder: (context, transactionProvider, child) {
              if (transactionProvider.isLoading) {
                return const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Đang tải dữ liệu báo cáo với DataService...'),
                    ],
                  ),
                );
              }

              if (transactionProvider.hasError) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Lỗi DataService: ${transactionProvider.error}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadReportDataWithDataService,
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                );
              }

              final stats = transactionProvider.getStatistics();
              final transactions = transactionProvider.transactions;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // DataService status card
                    Card(
                      color: connectionStatus.isOnline
                          ? Colors.green.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(
                              connectionStatus.isOnline
                                  ? Icons.cloud_done
                                  : Icons.cloud_off,
                              color: connectionStatus.isOnline
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Trạng thái DataService',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: connectionStatus.isOnline
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                    ),
                                  ),
                                  Text(
                                    connectionStatus.statusMessage,
                                    style: TextStyle(
                                      color: connectionStatus.isOnline
                                          ? Colors.green.shade600
                                          : Colors.orange.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    //  Statistics with DataService
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thống kê (DataService)',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),

                            Row(
                              children: [
                                Expanded(
                                  child: _buildStatCard(
                                    'Tổng thu nhập',
                                    NumberFormat.currency(
                                      locale: 'vi_VN',
                                      symbol: '₫',
                                    ).format(stats['totalIncome']),
                                    Colors.green,
                                    Icons.trending_up,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildStatCard(
                                    'Tổng chi tiêu',
                                    NumberFormat.currency(
                                      locale: 'vi_VN',
                                      symbol: '₫',
                                    ).format(stats['totalExpense']),
                                    Colors.red,
                                    Icons.trending_down,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            _buildStatCard(
                              'Số dư ròng',
                              NumberFormat.currency(
                                locale: 'vi_VN',
                                symbol: '₫',
                              ).format(stats['netAmount']),
                              stats['netAmount'] >= 0
                                  ? Colors.green
                                  : Colors.red,
                              stats['netAmount'] >= 0
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                            ),

                            const SizedBox(height: 16),

                            // Transaction count
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Số giao dịch',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${stats['transactionCount']} giao dịch',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Recent transactions summary
                    if (transactions.isNotEmpty) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Giao dịch gần đây (${transactions.length})',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),

                              ...transactions.take(5).map((transaction) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        transaction.type ==
                                            TransactionType.income
                                        ? Colors.green.withOpacity(0.2)
                                        : Colors.red.withOpacity(0.2),
                                    child: Icon(
                                      transaction.type == TransactionType.income
                                          ? Icons.trending_up
                                          : Icons.trending_down,
                                      color:
                                          transaction.type ==
                                              TransactionType.income
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  title: Text(transaction.description),
                                  subtitle: Text(
                                    DateFormat(
                                      'dd/MM/yyyy',
                                    ).format(transaction.date),
                                  ),
                                  trailing: Text(
                                    NumberFormat.currency(
                                      locale: 'vi_VN',
                                      symbol: '₫',
                                    ).format(transaction.amount),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color:
                                          transaction.type ==
                                              TransactionType.income
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                );
                              }).toList(),

                              if (transactions.length > 5) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const AllTransactionsScreen(),
                                      ),
                                    );
                                  },
                                  child: Text(
                                    'Xem thêm ${transactions.length - 5} giao dịch',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  Icons.receipt_long,
                                  size: 64,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Chưa có giao dịch nào trong khoảng thời gian này',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Dữ liệu được cung cấp bởi DataService',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

// lib/presentation/screens/_budget_screen.dart
class BudgetScreen extends StatelessWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Ngân sách (DataService)'),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            actions: [
              // DataService status indicator in app bar
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: connectionStatus.statusColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      connectionStatus.isOnline
                          ? Icons.cloud_done
                          : Icons.cloud_off,
                      size: 14,
                      color: connectionStatus.statusColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      connectionStatus.isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 10,
                        color: connectionStatus.statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'Tính năng Ngân sách với DataService',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Sẽ được phát triển trong phiên bản tiếp theo',
                  style: TextStyle(color: Colors.grey),
                ),
                SizedBox(height: 16),
                Text(
                  'DataService sẵn sàng hỗ trợ Budget management',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// lib/presentation/screens/_profile_screen.dart
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<UserProvider, ConnectionStatusProvider>(
      builder: (context, userProvider, connectionStatus, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Cài đặt (DataService)'),
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // DataService Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trạng thái DataService',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),

                        _buildStatusRow(
                          'Kết nối',
                          connectionStatus.isOnline ? 'Online' : 'Offline',
                          connectionStatus.isOnline ? Colors.green : Colors.red,
                          connectionStatus.isOnline
                              ? Icons.cloud_done
                              : Icons.cloud_off,
                        ),

                        _buildStatusRow(
                          'Đồng bộ',
                          connectionStatus.isSyncing
                              ? 'Đang đồng bộ...'
                              : 'Sẵn sàng',
                          connectionStatus.isSyncing
                              ? Colors.orange
                              : Colors.green,
                          connectionStatus.isSyncing
                              ? Icons.sync
                              : Icons.check_circle,
                        ),

                        _buildStatusRow(
                          'Mục chờ đồng bộ',
                          '${connectionStatus.pendingItems} mục',
                          connectionStatus.pendingItems > 0
                              ? Colors.orange
                              : Colors.green,
                          connectionStatus.pendingItems > 0
                              ? Icons.pending
                              : Icons.done_all,
                        ),

                        if (connectionStatus.lastSyncTime != null)
                          _buildStatusRow(
                            'Lần đồng bộ cuối',
                            DateFormat(
                              'dd/MM/yyyy HH:mm',
                            ).format(connectionStatus.lastSyncTime!),
                            Colors.grey,
                            Icons.history,
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // User Profile Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thông tin người dùng',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),

                        if (userProvider.currentUser != null) ...[
                          ListTile(
                            leading: CircleAvatar(
                              backgroundImage:
                                  userProvider.currentUser!.photoURL != null
                                  ? NetworkImage(
                                      userProvider.currentUser!.photoURL!,
                                    )
                                  : null,
                              child: userProvider.currentUser!.photoURL == null
                                  ? const Icon(Icons.person)
                                  : null,
                            ),
                            title: Text(
                              userProvider.currentUser!.displayName ??
                                  'Không có tên',
                            ),
                            subtitle: Text(
                              userProvider.currentUser!.email ??
                                  'Không có email',
                            ),
                          ),

                          if (userProvider.hasPartner) ...[
                            const Divider(),
                            ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.people),
                              ),
                              title: Text(
                                'Đối tác: ${userProvider.partnerDisplayName ?? "Không rõ"}',
                              ),
                              subtitle: Text(
                                'Partnership ID: ${userProvider.partnershipId}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.info_outline),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text(
                                        'Thông tin Partnership',
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Partnership ID: ${userProvider.partnershipId}',
                                          ),
                                          Text(
                                            'Partner UID: ${userProvider.partnerUid}',
                                          ),
                                          Text(
                                            'Partner Name: ${userProvider.partnerDisplayName}',
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            'Dữ liệu được đồng bộ qua DataService',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.blue,
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text('Đóng'),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ] else ...[
                          const ListTile(
                            leading: CircleAvatar(child: Icon(Icons.person)),
                            title: Text('Chưa đăng nhập'),
                            subtitle: Text(
                              'Vui lòng đăng nhập để sử dụng DataService',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // DataService Actions
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Thao tác DataService',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),

                        ListTile(
                          leading: const Icon(Icons.sync),
                          title: const Text('Đồng bộ thủ công'),
                          subtitle: const Text('Buộc đồng bộ dữ liệu ngay'),
                          onTap: () async {
                            try {
                              final dataService = Provider.of<DataService>(
                                context,
                                listen: false,
                              );
                              await dataService.forceSyncNow();

                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Đồng bộ DataService thành công',
                                    ),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Lỗi đồng bộ DataService: $e',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                              }
                            }
                          },
                        ),

                        ListTile(
                          leading: const Icon(Icons.info),
                          title: const Text('Thông tin DataService'),
                          subtitle: const Text(
                            'Xem chi tiết trạng thái DataService',
                          ),
                          onTap: () async {
                            final dataService = Provider.of<DataService>(
                              context,
                              listen: false,
                            );
                            final healthStatus = await dataService
                                .getHealthStatus();

                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text(
                                    'DataService Health Status',
                                  ),
                                  content: SingleChildScrollView(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'Initialized: ${dataService.isInitialized}',
                                        ),
                                        Text('Online: ${dataService.isOnline}'),
                                        Text(
                                          'Syncing: ${dataService.isSyncing}',
                                        ),
                                        Text(
                                          'Pending Items: ${dataService.pendingItems}',
                                        ),
                                        Text(
                                          'Last Error: ${dataService.lastError ?? "none"}',
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Health Status:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        ...healthStatus.entries.map(
                                          (e) => Text('${e.key}: ${e.value}'),
                                        ),
                                      ],
                                    ),
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
                          },
                        ),

                        ListTile(
                          leading: const Icon(Icons.logout, color: Colors.red),
                          title: const Text(
                            'Đăng xuất',
                            style: TextStyle(color: Colors.red),
                          ),
                          subtitle: const Text('Đăng xuất khỏi ứng dụng'),
                          onTap: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Xác nhận đăng xuất'),
                                content: const Text(
                                  'Bạn có chắc chắn muốn đăng xuất? '
                                  'Dữ liệu chưa đồng bộ có thể bị mất.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Hủy'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Đăng xuất'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true && context.mounted) {
                              final authService = AuthService();
                              await authService.signOut();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusRow(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
