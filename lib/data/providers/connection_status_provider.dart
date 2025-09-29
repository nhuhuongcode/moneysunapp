import 'package:flutter/material.dart';
import 'package:moneysun/data/services/data_service.dart';

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

    /// ✅ NEW: Check if error is an index error
    bool _isIndexError(String error) {
      return error.contains('index not defined') ||
          error.contains('indexOn') ||
          error.contains('firebase_database/index-not-defined');
    }

    bool _shouldUpdateError(String? newError) {
      // Ignore index errors
      if (newError != null && _isIndexError(newError)) {
        return false;
      }
      return newError != _lastError;
    }

    /// ✅ NEW: Filter out index errors from display
    String? _filterError(String? error) {
      if (error == null) return null;

      // Don't show index errors to users
      if (_isIndexError(error)) {
        return null;
      }

      return error;
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
