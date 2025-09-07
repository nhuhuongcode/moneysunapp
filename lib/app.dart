// lib/app.dart - FIXED WITH PROPER SERVICE INJECTION
import 'package:flutter/material.dart' hide NotificationListener;
import 'package:moneysun/core/theme/app_theme.dart';
import 'package:moneysun/features/auth/presentation/screens/auth_gate.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/presentation/widgets/notification_listener.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class MoneySunApp extends StatelessWidget {
  const MoneySunApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Primary UserProvider
        ChangeNotifierProvider(create: (context) => UserProvider()),

        // DataService with UserProvider dependency injection
        ChangeNotifierProxyProvider<UserProvider, DataService>(
          create: (context) => DataService(),
          update: (context, userProvider, dataService) {
            // FIX: Proper dependency injection to prevent crash
            if (dataService != null && userProvider != null) {
              // Initialize DataService with UserProvider when available
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _initializeDataService(dataService, userProvider);
              });
            }
            return dataService ?? DataService();
          },
        ),

        // Connection Status Provider for UI
        ChangeNotifierProxyProvider<DataService, ConnectionStatusProvider>(
          create: (context) => ConnectionStatusProvider(),
          update: (context, dataService, connectionProvider) {
            final provider = connectionProvider ?? ConnectionStatusProvider();
            if (dataService != null) {
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
            home: Stack(
              children: [
                const NotificationListener(child: AuthGate()),

                // Connection Status Banner
                if (connectionStatus.shouldShowBanner)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      child: ConnectionStatusBanner(status: connectionStatus),
                    ),
                  ),
              ],
            ),
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

  /// Initialize DataService with UserProvider - FIXES CRASH BUG
  void _initializeDataService(
    DataService dataService,
    UserProvider userProvider,
  ) async {
    try {
      // Check if already initialized
      if (dataService.isInitialized) {
        print('✅ DataService already initialized');
        return;
      }

      print('🔄 Initializing DataService with UserProvider...');
      await dataService.initialize(userProvider);
      print('✅ DataService initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize DataService: $e');
      // Don't rethrow - app should continue working even if sync fails
    }
  }
}

/// Connection Status Provider for UI state management
class ConnectionStatusProvider extends ChangeNotifier {
  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingItems = 0;
  String? _lastError;
  DateTime? _lastSyncTime;

  // Getters
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingItems => _pendingItems;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;

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

    if (newIsOnline != _isOnline ||
        newIsSyncing != _isSyncing ||
        newPendingItems != _pendingItems ||
        newLastError != _lastError ||
        newLastSyncTime != _lastSyncTime) {
      _isOnline = newIsOnline;
      _isSyncing = newIsSyncing;
      _pendingItems = newPendingItems;
      _lastError = newLastError;
      _lastSyncTime = newLastSyncTime;
      notifyListeners();
    }
  }
}

/// Connection Status Banner Widget
class ConnectionStatusBanner extends StatelessWidget {
  final ConnectionStatusProvider status;

  const ConnectionStatusBanner({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: status.shouldShowBanner ? 32 : 0,
      child: Container(
        width: double.infinity,
        color: status.statusColor.withOpacity(0.9),
        child: status.shouldShowBanner
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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

                  Icon(
                    _getStatusIcon(),
                    size: 16,
                    color: Colors.white.withOpacity(0.9),
                  ),
                  const SizedBox(width: 8),

                  Text(
                    status.statusMessage,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

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
                  ],
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
        content: Text(status.lastError ?? 'Không có thông tin lỗi'),
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

  void _retrySyncManually(BuildContext context) async {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);
      await dataService.forceSyncNow();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đồng bộ thành công'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đồng bộ thất bại: $e'),
            backgroundColor: Colors.red,
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
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                const SizedBox(height: 16),
                Text(
                  'Đã xảy ra lỗi',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.red.shade600),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Restart app or navigate to safe screen
                  },
                  child: const Text('Tải lại'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Development Debug Panel (only shown in debug mode)
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Consumer2<DataService, UserProvider>(
      builder: (context, dataService, userProvider, child) {
        return Positioned(
          bottom: 100,
          right: 16,
          child: FloatingActionButton.small(
            onPressed: () => _showDebugInfo(context, dataService, userProvider),
            child: const Icon(Icons.bug_report),
          ),
        );
      },
    );
  }

  void _showDebugInfo(
    BuildContext context,
    DataService dataService,
    UserProvider userProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Debug Info'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDebugRow('Online', dataService.isOnline.toString()),
              _buildDebugRow('Syncing', dataService.isSyncing.toString()),
              _buildDebugRow('Pending', dataService.pendingItems.toString()),
              _buildDebugRow(
                'User ID',
                userProvider.currentUser?.uid ?? 'null',
              ),
              _buildDebugRow(
                'Partnership',
                userProvider.partnershipId ?? 'null',
              ),
              _buildDebugRow(
                'Last Sync',
                dataService.lastSyncTime?.toString() ?? 'null',
              ),
              if (dataService.lastError != null)
                _buildDebugRow('Error', dataService.lastError!),
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
              } catch (e) {
                print('Debug sync failed: $e');
              }
            },
            child: const Text('Force Sync'),
          ),
        ],
      ),
    );
  }

  Widget _buildDebugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}
