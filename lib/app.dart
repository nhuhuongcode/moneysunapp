// lib/app.dart - FIXED PROVIDER SETUP
import 'package:flutter/material.dart' hide NotificationListener;
import 'package:moneysun/core/theme/app_theme.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/features/auth/presentation/screens/auth_gate.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
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
        ChangeNotifierProvider(
          create: (context) => UserProvider(),
        ),

        // ============ LEVEL 2: SERVICE PROVIDERS ============
        
        // 2. DataService - Depends on UserProvider
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

        // ============ LEVEL 3: FEATURE PROVIDERS ============
        
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
        ChangeNotifierProxyProvider2<DataService, UserProvider, CategoryProvider>(
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
        ChangeNotifierProxyProvider2<DataService, UserProvider, TransactionProvider>(
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
        
        // 6. Connection Status Provider - Depends on DataService
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

/// Main App Scaffold with connection status and debug panel
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
    _initializeProviders();
  }

  void _initializeProviders() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Check if user is authenticated before loading data
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        
        if (userProvider.isInitialized && userProvider.currentUser != null) {
          debugPrint('🔄 User authenticated, loading initial data...');
          
          // Load initial data for authenticated user
          await _loadInitialData();
        }
      } catch (e) {
        debugPrint('❌ Error during initial data loading: $e');
      }
    });
  }

  Future<void> _loadInitialData() async {
    try {
      final walletProvider = Provider.of<WalletProvider>(context, listen: false);
      final categoryProvider = Provider.of<CategoryProvider>(context, listen: false);
      final transactionProvider = Provider.of<TransactionProvider>(context, listen: false);

      // Load data in parallel for better performance
      await Future.wait([
        walletProvider.loadWallets(),
        categoryProvider.loadCategories(),
        transactionProvider.loadRecentTransactions(),
      ]);

      debugPrint('✅ Initial data loaded successfully');
    } catch (e) {
      debugPrint('❌ Error loading initial data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main app content
        const NotificationListener(child: AuthGate()),

        // Connection Status Banner
        if (widget.connectionStatus.shouldShowBanner)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: ConnectionStatusBanner(status: widget.connectionStatus),
            ),
          ),

        // Debug Panel (only in debug mode)
        if (kDebugMode) const DebugPanel(),
      ],
    );
  }
}

/// ENHANCED Connection Status Provider
class ConnectionStatusProvider extends ChangeNotifier {
  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingItems = 0;
  String? _lastError;
  DateTime? _lastSyncTime;
  bool _isInitialized = false;

  // Getters
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingItems => _pendingItems;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isInitialized => _isInitialized;

  bool get shouldShowBanner =>
      !_isOnline || _pendingItems > 0 || _lastError != null;

  String get statusMessage {
    if (_lastError != null) return 'Lỗi đồng bộ';
    if (_isSyncing) return 'Đang đồng bộ...';
    if (!_isOnline) return 'Chế độ Offline';
    if (_pendingItems > 0) return '$_pendingItems mục chưa đồng bộ';
    return 'Đã đồng bộ';
  }

  Color get statusColor {
    if (_lastError != null) return Colors.red;
    if (_isSyncing) return Colors.orange;
    if (!_isOnline) return Colors.grey;
    if (_pendingItems > 0) return Colors.blue;
    return Colors.green;
  }

  void updateFromDataService(DataService dataService) {
    final newIsOnline = dataService.isOnline;
    final newIsSyncing = dataService.isSyncing;
    final newPendingItems = dataService.pendingItems;
    final newLastError = dataService.lastError;
    final newLastSyncTime = dataService.lastSyncTime;
    final newIsInitialized = dataService.isInitialized;

    bool hasChanges = false;

    if (newIsOnline != _isOnline ||
        newIsSyncing != _isSyncing ||
        newPendingItems != _pendingItems ||
        newLastError != _lastError ||
        newLastSyncTime != _lastSyncTime ||
        newIsInitialized != _isInitialized) {
      
      _isOnline = newIsOnline;
      _isSyncing = newIsSyncing;
      _pendingItems = newPendingItems;
      _lastError = newLastError;
      _lastSyncTime = newLastSyncTime;
      _isInitialized = newIsInitialized;
      hasChanges = true;
    }

    if (hasChanges) {
      notifyListeners();
    }
  }

  // Manual sync trigger
  void clearError() {
    if (_lastError != null) {
      _lastError = null;
      notifyListeners();
    }
  }
}

/// ENHANCED Connection Status Banner
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
      Provider.of<ConnectionStatusProvider>(context, listen: false).clearError();

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

/// Global Error Display Widget
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
                    'Đã xảy ra lỗi',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ứng dụng gặp lỗi không mong muốn. Vui lòng thử khởi động lại.',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.red.shade600,
                    ),
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

/// ENHANCED Debug Panel with more features
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
              // Debug info button
              FloatingActionButton.small(
                heroTag: "debug_info",
                onPressed: () => _showDebugInfo(
                  context,
                  dataService,
                  userProvider,
                  connectionStatus,
                ),
                backgroundColor: Colors.purple,
                child: const Icon(Icons.bug_report, color: Colors.white),
              ),
              const SizedBox(height: 8),
              
              // Force sync button
              FloatingActionButton.small(
                heroTag: "force_sync",
                onPressed: () => _performForceSync(context, dataService),
                backgroundColor: Colors.blue,
                child: const Icon(Icons.sync, color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDebugInfo(
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
          title: const Text('Debug Info - MoneySun'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSection('🔧 Core Services', [
                  _buildDebugRow('DataService Init', '${dataService.isInitialized}'),
                  _buildDebugRow('Online Status', '${dataService.isOnline}'),
                  _buildDebugRow('Syncing', '${dataService.isSyncing}'),
                  _buildDebugRow('Pending Items', '${dataService.pendingItems}'),
                ]),
                
                _buildSection('👤 User Info', [
                  _buildDebugRow('User ID', userProvider.currentUser?.uid ?? 'null'),
                  _buildDebugRow('Partnership', userProvider.partnershipId ?? 'null'),
                  _buildDebugRow('Partner', userProvider.partnerDisplayName ?? 'null'),
                ]),
                
                _buildSection('🔄 Sync Status', [
                  _buildDebugRow('Last Sync', healthStatus['lastSyncTime'] ?? 'never'),
                  _buildDebugRow('Last Error', healthStatus['lastError'] ?? 'none'),
                  _buildDebugRow('Connection', '${connectionStatus.isOnline}'),
                ]),
                
                if (healthStatus['databaseStats'] != null)
                  _buildSection('📊 Database', [
                    ...(healthStatus['databaseStats'] as Map<String, dynamic>)
                        .entries
                        .map((e) => _buildDebugRow(e.key, '${e.value}')),
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
                      content: Text('Force sync completed'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Sync failed: $e'),
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
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
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
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
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

  void _performForceSync(BuildContext context, DataService dataService) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Starting force sync...'),
          duration: Duration(seconds: 1),
        ),
      );

      await dataService.forceSyncNow();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Force sync completed successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Force sync failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}