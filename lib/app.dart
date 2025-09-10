import 'package:flutter/material.dart' hide NotificationListener;
import 'package:moneysun/core/theme/app_theme.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/features/auth/presentation/screens/auth_gate.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/presentation/widgets/notification_listener.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class MoneySunApp extends StatelessWidget {
  const MoneySunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ============ LEVEL 1: BASE PROVIDERS ============

        // 1. UserProvider - No dependencies
        ChangeNotifierProvider(create: (context) => UserProvider()),

        // ============ LEVEL 2: SERVICE PROVIDERS ============

        // 2. DataService - Single source of truth
        ChangeNotifierProxyProvider<UserProvider, DataService>(
          create: (context) => DataService(),
          update: (context, userProvider, dataService) {
            final service = dataService ?? DataService();

            // Initialize DataService when UserProvider changes
            if (userProvider.isInitialized && !service.isInitialized) {
              WidgetsBinding.instance.addPostFrameCallback((_) async {
                try {
                  await service.initialize(userProvider);
                  debugPrint('✅ DataService initialized with UserProvider');
                } catch (error) {
                  debugPrint('❌ Failed to initialize DataService: $error');
                }
              });
            }

            return service;
          },
        ),

        // ============ LEVEL 3:  FEATURE PROVIDERS ============

        // 3. WalletProvider - Depends on DataService + UserProvider
        ChangeNotifierProxyProvider2<DataService, UserProvider, WalletProvider>(
          create: (context) => WalletProvider(
            Provider.of<DataService>(context, listen: false),
            Provider.of<UserProvider>(context, listen: false),
          ),
          update: (context, dataService, userProvider, walletProvider) {
            if (walletProvider != null) {
              return walletProvider;
            }
            return WalletProvider(dataService, userProvider);
          },
        ),

        // 4. CategoryProvider - Depends on DataService + UserProvider
        ChangeNotifierProxyProvider2<
          DataService,
          UserProvider,
          CategoryProvider
        >(
          create: (context) => CategoryProvider(
            Provider.of<DataService>(context, listen: false),
            Provider.of<UserProvider>(context, listen: false),
          ),
          update: (context, dataService, userProvider, categoryProvider) {
            if (categoryProvider != null) {
              return categoryProvider;
            }
            return CategoryProvider(dataService, userProvider);
          },
        ),

        // 5. TransactionProvider - Depends on DataService + UserProvider
        ChangeNotifierProxyProvider2<
          DataService,
          UserProvider,
          TransactionProvider
        >(
          create: (context) => TransactionProvider(
            Provider.of<DataService>(context, listen: false),
            Provider.of<UserProvider>(context, listen: false),
          ),
          update: (context, dataService, userProvider, transactionProvider) {
            if (transactionProvider != null) {
              return transactionProvider;
            }
            return TransactionProvider(dataService, userProvider);
          },
        ),

        // ============ LEVEL 4: UI STATE PROVIDERS ============

        // 6.  Connection Status Provider - Depends on DataService
        ChangeNotifierProxyProvider<DataService, ConnectionStatusProvider>(
          create: (context) => ConnectionStatusProvider(),
          update: (context, dataService, connectionProvider) {
            final provider = connectionProvider ?? ConnectionStatusProvider();
            if (dataService.isInitialized) {
              provider.updateFromDataService(dataService);
            }
            return provider;
          },
        ),
      ],
      child: Consumer<ConnectionStatusProvider>(
        builder: (context, connectionStatus, child) {
          return MaterialApp(
            title: 'Money Sun',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: AppScaffold(connectionStatus: connectionStatus),
            builder: (context, child) {
              // Global error handling
              ErrorWidget.builder = (FlutterErrorDetails details) {
                return ErrorDisplayWidget(error: details.exception.toString());
              };
              return child ?? const SizedBox.shrink();
            },
          );
        },
      ),
    );
  }
}

///  App Scaffold with DataService integration
class AppScaffold extends StatefulWidget {
  final ConnectionStatusProvider connectionStatus;

  const AppScaffold({super.key, required this.connectionStatus});

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  @override
  void initState() {
    super.initState();
    _initializeProvidersWithDataService();
  }

  void _initializeProvidersWithDataService() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Check if user is authenticated before loading data
        final userProvider = Provider.of<UserProvider>(context, listen: false);

        if (userProvider.isInitialized && userProvider.currentUser != null) {
          debugPrint(
            '🔄 User authenticated, loading initial data with DataService...',
          );

          // Load initial data for authenticated user using  providers
          await _loadInitialDataWithDataService();
        }
      } catch (e) {
        debugPrint('❌ Error during initial data loading with DataService: $e');
      }
    });
  }

  Future<void> _loadInitialDataWithDataService() async {
    try {
      final walletProvider = Provider.of<WalletProvider>(
        context,
        listen: false,
      );
      final categoryProvider = Provider.of<CategoryProvider>(
        context,
        listen: false,
      );
      final transactionProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );

      // Load data in parallel for better performance using  providers
      await Future.wait([
        walletProvider.loadWallets(),
        categoryProvider.loadCategories(),
        transactionProvider.loadRecentTransactions(),
      ]);

      debugPrint('✅ Initial data loaded successfully with DataService');
    } catch (e) {
      debugPrint('❌ Error loading initial data with DataService: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main app content
        const NotificationListener(child: AuthGate()),

        //  Connection Status Banner
        if (widget.connectionStatus.shouldShowBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: ConnectionStatusBanner(status: widget.connectionStatus),
            ),
          ),

        //  Debug Panel (only in debug mode)
        if (kDebugMode) const DebugPanel(),
      ],
    );
  }
}

///  Connection Status Banner with DataService integration
class ConnectionStatusBanner extends StatelessWidget {
  final ConnectionStatusProvider status;

  const ConnectionStatusBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: status.shouldShowBanner ? 36 : 0,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: status.statusColor.withOpacity(0.9),
          boxShadow: status.shouldShowBanner
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: status.shouldShowBanner
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Sync indicator
                  if (status.isSyncing)
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                  if (status.isSyncing) const SizedBox(width: 8),

                  // Status icon
                  Icon(
                    _getStatusIcon(),
                    size: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 8),

                  // Status message
                  Expanded(
                    child: Text(
                      status.statusMessage,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Action buttons
                  if (status.lastError != null) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showErrorDetails(context),
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Retry button for errors
                  if (status.lastError != null)
                    GestureDetector(
                      onTap: () => _retrySyncManually(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Thử lại',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(width: 12),
                ],
              )
            : null,
      ),
    );
  }

  IconData _getStatusIcon() {
    if (status.lastError != null) return Icons.error_outline;
    if (status.isSyncing) return Icons.sync;
    if (!status.isOnline) return Icons.wifi_off;
    if (status.pendingItems > 0) return Icons.cloud_upload;
    return Icons.check_circle;
  }

  void _showErrorDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chi Tiết Lỗi'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(status.lastError ?? 'Không có thông tin lỗi'),
              const SizedBox(height: 16),
              if (status.lastSyncTime != null) ...[
                Text(
                  'Lần đồng bộ cuối: ${_formatDateTime(status.lastSyncTime!)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
              ],
              Text(
                'Mục chưa đồng bộ: ${status.pendingItems}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _retrySyncManually(context);
            },
            child: const Text('Thử Lại'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:'
        '${dateTime.minute.toString().padLeft(2, '0')} '
        '${dateTime.day}/${dateTime.month}';
  }

  void _retrySyncManually(BuildContext context) async {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      await dataService.forceSyncNow();

      // Clear error status
      Provider.of<ConnectionStatusProvider>(
        context,
        listen: false,
      ).clearError();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đồng bộ thành công'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đồng bộ thất bại: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

///  Error Display Widget
class ErrorDisplayWidget extends StatelessWidget {
  final String error;

  const ErrorDisplayWidget({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Container(
        color: Colors.red.shade50,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Đã xảy ra lỗi với DataService',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ứng dụng gặp lỗi với DataService. Vui lòng thử khởi động lại.',
                    style: TextStyle(fontSize: 16, color: Colors.red.shade600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chi tiết lỗi:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        // Could implement app restart logic here
                        debugPrint('Restart app requested');
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Khởi động lại'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

///  Debug Panel with DataService info
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Consumer3<DataService, UserProvider, ConnectionStatusProvider>(
      builder: (context, dataService, userProvider, connectionStatus, child) {
        return Positioned(
          bottom: 100,
          right: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // DataService debug info button
              FloatingActionButton.small(
                heroTag: "dataservice_debug",
                onPressed: () => _showDataServiceDebugInfo(
                  context,
                  dataService,
                  userProvider,
                  connectionStatus,
                ),
                backgroundColor: Colors.purple,
                child: const Icon(Icons.storage, color: Colors.white),
              ),
              const SizedBox(height: 8),

              // Force sync button
              FloatingActionButton.small(
                heroTag: "force_sync",
                onPressed: () => _performDataServiceSync(context, dataService),
                backgroundColor: Colors.blue,
                child: const Icon(Icons.sync, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDataServiceDebugInfo(
    BuildContext context,
    DataService dataService,
    UserProvider userProvider,
    ConnectionStatusProvider connectionStatus,
  ) async {
    final healthStatus = await dataService.getHealthStatus();

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('DataService Debug Info'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSection('🔧 DataService Status', [
                  _buildDebugRow('Initialized', '${dataService.isInitialized}'),
                  _buildDebugRow('Online Status', '${dataService.isOnline}'),
                  _buildDebugRow('Syncing', '${dataService.isSyncing}'),
                  _buildDebugRow(
                    'Pending Items',
                    '${dataService.pendingItems}',
                  ),
                  _buildDebugRow('Last Error', dataService.lastError ?? 'none'),
                ]),

                _buildSection('👤 User Info', [
                  _buildDebugRow(
                    'User ID',
                    userProvider.currentUser?.uid ?? 'null',
                  ),
                  _buildDebugRow(
                    'Partnership',
                    userProvider.partnershipId ?? 'null',
                  ),
                  _buildDebugRow(
                    'Partner',
                    userProvider.partnerDisplayName ?? 'null',
                  ),
                ]),

                _buildSection('🔄 Sync Health', [
                  _buildDebugRow(
                    'Last Sync',
                    healthStatus['lastSyncTime'] ?? 'never',
                  ),
                  _buildDebugRow(
                    'Pending Sync',
                    '${healthStatus['pendingSync'] ?? 0}',
                  ),
                  _buildDebugRow('Connection', '${connectionStatus.isOnline}'),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  await dataService.forceSyncNow();
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('DataService sync completed'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('DataService sync failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Force Sync'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _performDataServiceSync(
    BuildContext context,
    DataService dataService,
  ) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Starting DataService sync...'),
          duration: Duration(seconds: 1),
        ),
      );

      await dataService.forceSyncNow();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('DataService sync completed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('DataService sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
