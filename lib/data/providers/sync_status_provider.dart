// lib/data/providers/sync_status_provider.dart
import 'package:flutter/material.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'package:moneysun/presentation/widgets/time_filter_appbar_widget.dart';

class SyncStatusProvider extends ChangeNotifier {
  final OfflineSyncService _syncService = OfflineSyncService();

  // State
  bool _isInitialized = false;
  bool _showSyncNotifications = true;

  // Getters
  bool get isInitialized => _isInitialized;
  bool get showSyncNotifications => _showSyncNotifications;

  // Sync service getters (proxy)
  bool get isOnline => _syncService.isOnline;
  bool get isConnectedToNetwork => _syncService.isConnectedToNetwork;
  bool get isFirebaseConnected => _syncService.isFirebaseConnected;
  SyncStatus get syncStatus => _syncService.syncStatus;
  DateTime? get lastSyncTime => _syncService.lastSyncTime;
  int get pendingCount => _syncService.pendingCount;
  String? get lastError => _syncService.lastError;
  bool get isSyncing => _syncService.isSyncing;
  int get successfulSyncs => _syncService.successfulSyncs;
  int get failedSyncs => _syncService.failedSyncs;

  SyncStatusProvider() {
    _initializeService();
  }

  Future<void> _initializeService() async {
    try {
      // Listen to sync service changes
      _syncService.addListener(_onSyncServiceChanged);

      // Initialize the sync service
      await _syncService.initialize();

      _isInitialized = true;
      notifyListeners();

      print('✅ SyncStatusProvider initialized');
    } catch (e) {
      print('❌ Failed to initialize SyncStatusProvider: $e');
    }
  }

  void _onSyncServiceChanged() {
    // Propagate changes from sync service
    notifyListeners();
  }

  // ============ UI HELPER METHODS ============

  /// Get SyncStatusInfo for TimeFilterAppBar
  SyncStatusInfo getSyncStatusInfo() {
    if (!isInitialized) {
      return const SyncStatusInfo(status: ConnectivityStatus.unknown);
    }

    if (isSyncing) {
      return SyncStatusInfo.syncing();
    }

    if (!isConnectedToNetwork) {
      return SyncStatusInfo.offline(pendingCount: pendingCount);
    }

    if (!isFirebaseConnected) {
      return SyncStatusInfo.error('Firebase không kết nối');
    }

    if (syncStatus == SyncStatus.error && lastError != null) {
      return SyncStatusInfo.error(lastError!);
    }

    return SyncStatusInfo.online(lastSyncTime: lastSyncTime);
  }

  /// Get connectivity status for UI
  ConnectivityStatus getConnectivityStatus() {
    if (!isInitialized) return ConnectivityStatus.unknown;
    if (isSyncing) return ConnectivityStatus.syncing;
    if (!isConnectedToNetwork) return ConnectivityStatus.offline;
    if (!isFirebaseConnected) return ConnectivityStatus.syncError;
    if (syncStatus == SyncStatus.error) return ConnectivityStatus.syncError;
    return ConnectivityStatus.online;
  }

  /// Get user-friendly status message
  String getStatusMessage() {
    final status = getConnectivityStatus();

    switch (status) {
      case ConnectivityStatus.online:
        if (lastSyncTime != null) {
          final diff = DateTime.now().difference(lastSyncTime!);
          if (diff.inMinutes < 1) return 'Đã đồng bộ';
          if (diff.inMinutes < 60)
            return 'Đồng bộ ${diff.inMinutes} phút trước';
          if (diff.inHours < 24) return 'Đồng bộ ${diff.inHours} giờ trước';
          return 'Đồng bộ ${diff.inDays} ngày trước';
        }
        return 'Trực tuyến';

      case ConnectivityStatus.offline:
        return pendingCount > 0
            ? 'Ngoại tuyến ($pendingCount chờ đồng bộ)'
            : 'Ngoại tuyến';

      case ConnectivityStatus.syncing:
        return 'Đang đồng bộ...';

      case ConnectivityStatus.syncError:
        if (!isConnectedToNetwork) return 'Không có kết nối mạng';
        if (!isFirebaseConnected) return 'Lỗi kết nối Firebase';
        return lastError ?? 'Lỗi đồng bộ';

      case ConnectivityStatus.unknown:
        return 'Đang khởi tạo...';
    }
  }

  /// Get sync statistics for debug/settings screen
  Map<String, dynamic> getDetailedStats() {
    return _syncService.getSyncStats();
  }

  // ============ USER ACTIONS ============

  /// Force manual sync
  Future<void> forceSyncNow() async {
    try {
      await _syncService.forceSyncNow();

      if (_showSyncNotifications) {
        // Could show a success snackbar here if needed
      }
    } catch (e) {
      // Handle error - could show error snackbar
      rethrow;
    }
  }

  /// Toggle sync notifications
  void toggleSyncNotifications() {
    _showSyncNotifications = !_showSyncNotifications;
    notifyListeners();
  }

  /// Clear synced local data
  Future<void> clearLocalCache() async {
    await _syncService.clearSyncedData();
  }

  /// Reset all data (dangerous operation)
  Future<void> resetAllData() async {
    await _syncService.resetAllLocalData();
  }

  // ============ OFFLINE-FIRST DATA OPERATIONS ============

  /// Add transaction with offline-first approach
  Future<void> addTransactionOffline(
    Map<String, dynamic> transactionData,
  ) async {
    // This would typically convert the data to TransactionModel
    // and call the sync service
    // Implementation depends on how you structure the data flow
  }

  @override
  void dispose() {
    _syncService.removeListener(_onSyncServiceChanged);
    _syncService.dispose();
    super.dispose();
  }
}
