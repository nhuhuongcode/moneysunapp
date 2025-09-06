// lib/data/services/enhanced_offline_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import 'package:moneysun/data/models/enhanced_budget_model.dart';
import 'package:moneysun/data/models/enhanced_category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/services/enhanced_local_database_service.dart';
import 'package:moneysun/data/services/local_database_service.dart';

enum SyncPriority { low, medium, high, critical }
enum SyncStatus { idle, syncing, error, completed }

class SyncResult {
  final bool success;
  final String? error;
  final int syncedItems;
  final int failedItems;
  final DateTime timestamp;

  const SyncResult({
    required this.success,
    this.error,
    required this.syncedItems,
    required this.failedItems,
    required this.timestamp,
  });

  factory SyncResult.success(int syncedItems) => SyncResult(
    success: true,
    syncedItems: syncedItems,
    failedItems: 0,
    timestamp: DateTime.now(),
  );

  factory SyncResult.failure(String error, int failedItems) => SyncResult(
    success: false,
    error: error,
    syncedItems: 0,
    failedItems: failedItems,
    timestamp: DateTime.now(),
  );

  factory SyncResult.partial(int synced, int failed, String? error) => SyncResult(
    success: synced > 0,
    error: error,
    syncedItems: synced,
    failedItems: failed,
    timestamp: DateTime.now(),
  );
}

class EnhancedOfflineSyncService extends ChangeNotifier {
  static final EnhancedOfflineSyncService _instance = 
      EnhancedOfflineSyncService._internal();
  factory EnhancedOfflineSyncService() => _instance;
  EnhancedOfflineSyncService._internal();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  Timer? _healthCheckTimer;

  SyncStatus _syncStatus = SyncStatus.idle;
  bool _isOnline = false;
  DateTime? _lastSyncTime;
  int _pendingItems = 0;
  String? _lastError;
  Map<String, int> _syncStats = {};

  // Sync configuration
  static const int _maxRetries = 3;
  static const Duration _syncInterval = Duration(minutes: 5);
  static const Duration _healthCheckInterval = Duration(minutes: 1);
  static const int _batchSize = 50;

  // Getters
  SyncStatus get syncStatus => _syncStatus;
  bool get isOnline => _isOnline;
  bool get isSyncing => _syncStatus == SyncStatus.syncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingItems => _pendingItems;
  String? get lastError => _lastError;
  Map<String, int> get syncStats => Map.unmodifiable(_syncStats);

  // ============ INITIALIZATION ============

  Future<void> initialize() async {
    await _checkConnectivity();
    _startConnectivityListener();
    _startPeriodicSync();
    _startHealthCheck();
    await _updatePendingItemsCount();

    print('✅ Enhanced Offline Sync Service initialized');
    print('📊 Online: $_isOnline, Pending: $_pendingItems items');

    // Initial sync if online
    if (_isOnline) {
      unawaited(_performFullSync());
    }
  }

  void _startConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        final wasOnline = _isOnline;
        final hasNetwork = results.any((r) => r != ConnectivityResult.none);

        _isOnline = hasNetwork;

        if (_isOnline && !wasOnline) {
          print('📶 Connection restored - starting enhanced sync...');
          _lastError = null;
          await _performFullSync();
        } else if (!_isOnline && wasOnline) {
          print('📵 Connection lost - switching to offline mode');
          _setSyncStatus(SyncStatus.idle);
        }
        
        notifyListeners();
      },
    );
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(_syncInterval, (timer) {
      if (_isOnline && !isSyncing && _pendingItems > 0) {
        unawaited(_performFullSync());
      }
    });
  }

  void _startHealthCheck() {
    _healthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) async {
      await _updatePendingItemsCount();
      await _updateSyncStats();
    });
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
  }

  void _setSyncStatus(SyncStatus status) {
    if (_syncStatus != status) {
      _syncStatus = status;
      notifyListeners();
    }
  }

  // ============ MAIN SYNC OPERATIONS ============

  Future<SyncResult> _performFullSync() async {
    if (isSyncing || !_isOnline) {
      return SyncResult.failure('Already syncing or offline', 0);
    }

    _setSyncStatus(SyncStatus.syncing);
    _lastError = null;

    try {
      print('🔄 Starting enhanced full sync...');
      
      int totalSynced = 0;
      int totalFailed = 0;

      // Step 1: Sync in priority order
      final results = await Future.wait([
        _syncTableData('transactions', SyncPriority.high),
        _syncTableData('wallets', SyncPriority.high),
        _syncTableData('enhanced_categories', SyncPriority.medium),
        _syncTableData('enhanced_budgets', SyncPriority.medium),
      ]);

      for (final result in results) {
        totalSynced += result.syncedItems;
        totalFailed += result.failedItems;
      }

      // Step 2: Pull latest data from Firebase
      await _pullLatestData();

      _lastSyncTime = DateTime.now();
      await _updatePendingItemsCount();

      final finalResult = totalFailed == 0
          ? SyncResult.success(totalSynced)
          : SyncResult.partial(totalSynced, totalFailed, 'Some items failed to sync');

      _setSyncStatus(SyncStatus.completed);

      print('✅ Enhanced sync completed: ${finalResult.syncedItems} synced, ${finalResult.failedItems} failed');
      
      // Reset to idle after a short delay
      Timer(const Duration(seconds: 2), () => _setSyncStatus(SyncStatus.idle));

      return finalResult;
    } catch (e) {
      _lastError = e.toString();
      _setSyncStatus(SyncStatus.error);
      print('❌ Enhanced sync failed: $e');
      
      Timer(const Duration(seconds: 5), () => _setSyncStatus(SyncStatus.idle));
      return SyncResult.failure(_lastError!, 0);
    } finally {
      await _updatePendingItemsCount();
      await _updateSyncStats();
    }
  }
