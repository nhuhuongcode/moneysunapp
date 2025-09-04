// lib/data/services/enhanced_offline_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:flutter/material.dart';

enum SyncStatus { idle, syncing, error, success }

class OfflineSyncService extends ChangeNotifier {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  // Dependencies
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final Connectivity _connectivity = Connectivity();

  // State management
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<DatabaseEvent>? _firebaseConnectionSubscription;
  Timer? _syncTimer;
  Timer? _retryTimer;

  // Sync state
  bool _isOnline = false;
  bool _isFirebaseConnected = false;
  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  int _pendingCount = 0;
  String? _lastError;
  bool _isSyncing = false;

  // Sync statistics
  int _successfulSyncs = 0;
  int _failedSyncs = 0;

  // Configuration
  static const int _syncIntervalMinutes = 2; // Sync every 2 minutes when online
  static const int _retryIntervalSeconds = 30; // Retry failed syncs every 30s
  static const int _maxRetries = 5;
  static const int _batchSize = 20; // Process 20 items per batch

  // Getters
  bool get isOnline => _isOnline && _isFirebaseConnected;
  bool get isConnectedToNetwork => _isOnline;
  bool get isFirebaseConnected => _isFirebaseConnected;
  SyncStatus get syncStatus => _syncStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingCount => _pendingCount;
  String? get lastError => _lastError;
  bool get isSyncing => _isSyncing;
  int get successfulSyncs => _successfulSyncs;
  int get failedSyncs => _failedSyncs;

  // Public methods
  Future<void> initialize() async {
    print('🚀 Initializing Enhanced Offline Sync Service...');

    await _checkInitialConnectivity();
    _startConnectivityListener();
    _startFirebaseConnectionListener();
    _startPeriodicSync();
    await _loadSyncMetadata();

    // Initial sync if online
    if (isOnline) {
      unawaited(_performFullSync());
    }

    print('✅ Enhanced Offline Sync Service initialized');
  }

  Future<void> _loadSyncMetadata() async {
    try {
      final stats = await _localDb.getDatabaseStats();
      _pendingCount = stats['pendingSync'] ?? 0;

      // Load last sync time from local storage if needed
      // This could be stored in shared preferences or local DB metadata
      notifyListeners();
    } catch (e) {
      print('⚠️ Failed to load sync metadata: $e');
    }
  }

  Future<void> _checkInitialConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = !result.contains(ConnectivityResult.none);
    print('📶 Initial connectivity: ${_isOnline ? "Online" : "Offline"}');
  }

  void _startConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final wasOnline = _isOnline;
      _isOnline = !results.contains(ConnectivityResult.none);

      print('📶 Connectivity changed: ${_isOnline ? "Online" : "Offline"}');

      if (_isOnline && !wasOnline) {
        print('🔄 Connection restored - scheduling sync...');
        await Future.delayed(
          const Duration(seconds: 2),
        ); // Wait for connection to stabilize
        unawaited(_performFullSync());
      } else if (!_isOnline && wasOnline) {
        print('📵 Connection lost - entering offline mode');
        _setSyncStatus(SyncStatus.error, 'Connection lost');
      }
      notifyListeners();
    });
  }

  void _startFirebaseConnectionListener() {
    final connectedRef = _dbRef.child('.info/connected');
    _firebaseConnectionSubscription = connectedRef.onValue.listen((
      DatabaseEvent event,
    ) {
      final wasConnected = _isFirebaseConnected;
      _isFirebaseConnected = event.snapshot.value as bool? ?? false;

      print(
        '🔥 Firebase connection: ${_isFirebaseConnected ? "Connected" : "Disconnected"}',
      );

      if (_isFirebaseConnected && !wasConnected && _isOnline) {
        print('🔄 Firebase reconnected - scheduling sync...');
        unawaited(_performFullSync());
      }
      notifyListeners();
    });
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(Duration(minutes: _syncIntervalMinutes), (
      timer,
    ) {
      if (isOnline && !_isSyncing) {
        unawaited(_performFullSync());
      }
    });

    // Retry failed syncs more frequently
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(Duration(seconds: _retryIntervalSeconds), (
      timer,
    ) {
      if (isOnline && !_isSyncing && _pendingCount > 0) {
        unawaited(_performFullSync());
      }
    });
  }

  // ============ MAIN SYNC LOGIC ============

  Future<void> _performFullSync() async {
    if (_isSyncing || !isOnline) return;

    _isSyncing = true;
    _setSyncStatus(SyncStatus.syncing, null);

    try {
      print('🔄 Starting full sync process...');

      // Step 1: Update pending count
      await _updatePendingCount();

      // Step 2: Push local changes to Firebase
      await _pushLocalChangesToFirebase();

      // Step 3: Pull latest changes from Firebase (if needed)
      // await _pullFirebaseChangesToLocal(); // Implement if needed

      _lastSyncTime = DateTime.now();
      _successfulSyncs++;
      _setSyncStatus(SyncStatus.success, null);

      print('✅ Full sync completed successfully');
    } catch (e, stackTrace) {
      _failedSyncs++;
      _setSyncStatus(SyncStatus.error, e.toString());
      print('❌ Full sync failed: $e');
      print('Stack trace: $stackTrace');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _updatePendingCount() async {
    try {
      final stats = await _localDb.getDatabaseStats();
      _pendingCount = stats['pendingSync'] ?? 0;
    } catch (e) {
      print('⚠️ Failed to update pending count: $e');
    }
  }

  Future<void> _pushLocalChangesToFirebase() async {
    try {
      print('📤 Pushing local changes to Firebase...');

      // Get pending items in batches
      final pendingItems = await _localDb.getPendingSyncItems(
        limit: _batchSize,
      );

      if (pendingItems.isEmpty) {
        print('📭 No pending items to sync');
        return;
      }

      print('📦 Processing ${pendingItems.length} pending items...');

      int processedCount = 0;
      int errorCount = 0;

      for (final item in pendingItems) {
        try {
          await _processSyncItem(item);
          await _localDb.removeSyncItem(item['id']);
          processedCount++;

          // Small delay to prevent overwhelming Firebase
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          errorCount++;
          print('❌ Failed to sync item ${item['id']}: $e');

          final retryCount = item['retryCount'] as int? ?? 0;
          if (retryCount >= _maxRetries) {
            await _localDb.removeSyncItem(item['id']);
            print(
              '🗑️ Removed item ${item['id']} after $_maxRetries failed attempts',
            );
          } else {
            await _localDb.incrementRetryCount(item['id']);
          }
        }
      }

      print(
        '📊 Sync batch completed: $processedCount success, $errorCount errors',
      );
      await _updatePendingCount();
    } catch (e) {
      print('❌ Error in push sync: $e');
      rethrow;
    }
  }

  Future<void> _processSyncItem(Map<String, dynamic> item) async {
    final tableName = item['tableName'] as String;
    final recordId = item['recordId'] as String;
    final operation = item['operation'] as String;
    final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;

    print('🔧 Processing $operation on $tableName (ID: $recordId)');

    switch (tableName) {
      case 'transactions':
        await _syncTransactionToFirebase(operation, recordId, data);
        break;
      case 'wallets':
        await _syncWalletToFirebase(operation, recordId, data);
        break;
      case 'categories':
        await _syncCategoryToFirebase(operation, recordId, data);
        break;
      default:
        print('⚠️ Unknown table: $tableName');
    }
  }

  Future<void> _syncTransactionToFirebase(
    String operation,
    String recordId,
    Map<String, dynamic> data,
  ) async {
    final transactionRef = _dbRef.child('transactions');

    switch (operation) {
      case 'INSERT':
        // Use the local ID as Firebase key for consistency
        await transactionRef.child(recordId).set(data);

        // Update wallet balance
        await _updateWalletBalanceForTransaction(data, isAdd: true);

        // Mark as synced in local DB
        await _localDb.markAsSynced('transactions', recordId);
        break;

      case 'UPDATE':
        await transactionRef.child(recordId).update(data);
        await _localDb.markAsSynced('transactions', recordId);
        break;

      case 'DELETE':
        // Revert wallet balance before deleting
        await _updateWalletBalanceForTransaction(data, isAdd: false);
        await transactionRef.child(recordId).remove();
        break;
    }
  }

  Future<void> _updateWalletBalanceForTransaction(
    Map<String, dynamic> transactionData, {
    required bool isAdd,
  }) async {
    try {
      final walletId = transactionData['walletId'] as String?;
      final amount = (transactionData['amount'] as num?)?.toDouble() ?? 0.0;
      final type = transactionData['type'] as String?;

      if (walletId == null || amount == 0) return;

      double balanceChange = 0;
      switch (type) {
        case 'income':
          balanceChange = isAdd ? amount : -amount;
          break;
        case 'expense':
          balanceChange = isAdd ? -amount : amount;
          break;
        case 'transfer':
          // For transfers, also handle the target wallet
          final transferToWalletId =
              transactionData['transferToWalletId'] as String?;
          balanceChange = isAdd ? -amount : amount; // Source wallet

          // Update source wallet
          await _dbRef
              .child('wallets')
              .child(walletId)
              .child('balance')
              .set(ServerValue.increment(balanceChange));

          // Update target wallet if exists
          if (transferToWalletId != null) {
            await _dbRef
                .child('wallets')
                .child(transferToWalletId)
                .child('balance')
                .set(ServerValue.increment(isAdd ? amount : -amount));
          }
          return; // Early return to avoid double update
      }

      // Update wallet balance
      await _dbRef
          .child('wallets')
          .child(walletId)
          .child('balance')
          .set(ServerValue.increment(balanceChange));
    } catch (e) {
      print('⚠️ Failed to update wallet balance: $e');
    }
  }

  Future<void> _syncWalletToFirebase(
    String operation,
    String recordId,
    Map<String, dynamic> data,
  ) async {
    final walletRef = _dbRef.child('wallets');

    switch (operation) {
      case 'INSERT':
        await walletRef.child(recordId).set(data);
        await _localDb.markAsSynced('wallets', recordId);
        break;

      case 'UPDATE':
        await walletRef.child(recordId).update(data);
        await _localDb.markAsSynced('wallets', recordId);
        break;

      case 'DELETE':
        await walletRef.child(recordId).remove();
        break;
    }
  }

  Future<void> _syncCategoryToFirebase(
    String operation,
    String recordId,
    Map<String, dynamic> data,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final categoryRef = _dbRef.child('categories').child(currentUser.uid);

    switch (operation) {
      case 'INSERT':
        await categoryRef.child(recordId).set(data);
        await _localDb.markAsSynced('categories', recordId);
        break;

      case 'UPDATE':
        await categoryRef.child(recordId).update(data);
        await _localDb.markAsSynced('categories', recordId);
        break;

      case 'DELETE':
        await categoryRef.child(recordId).remove();
        break;
    }
  }

  // ============ PUBLIC API METHODS ============

  /// Force sync now - can be called by UI
  Future<void> forceSyncNow() async {
    if (!isOnline) {
      throw Exception(
        'Không có kết nối internet. Vui lòng kiểm tra kết nối và thử lại.',
      );
    }

    print('🔄 Manual sync requested');
    await _performFullSync();
  }

  /// Add transaction with offline-first approach
  Future<void> addTransactionOffline(TransactionModel transaction) async {
    print('💾 Adding transaction offline-first: ${transaction.id}');

    // Always save to local database first
    await _localDb.saveTransactionLocally(
      transaction,
      syncStatus: 0, // Mark as unsynced
    );

    // Save description to history
    if (transaction.description.isNotEmpty) {
      await _localDb.saveDescriptionToHistory(
        transaction.userId,
        transaction.description,
      );
    }

    await _updatePendingCount();

    // Try immediate sync if online
    if (isOnline && !_isSyncing) {
      unawaited(_performFullSync());
    }

    notifyListeners();
  }

  /// Add wallet with offline-first approach
  Future<void> addWalletOffline(Wallet wallet) async {
    print('💾 Adding wallet offline-first: ${wallet.id}');

    await _localDb.saveWalletLocally(wallet, syncStatus: 0);
    await _updatePendingCount();

    if (isOnline && !_isSyncing) {
      unawaited(_performFullSync());
    }

    notifyListeners();
  }

  /// Add category with offline-first approach
  Future<void> addCategoryOffline(Category category) async {
    print('💾 Adding category offline-first: ${category.id}');

    await _localDb.saveCategoryLocally(category, syncStatus: 0);
    await _updatePendingCount();

    if (isOnline && !_isSyncing) {
      unawaited(_performFullSync());
    }

    notifyListeners();
  }

  /// Get sync statistics
  Map<String, dynamic> getSyncStats() {
    return {
      'isOnline': isOnline,
      'isFirebaseConnected': _isFirebaseConnected,
      'syncStatus': _syncStatus.toString(),
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'pendingCount': _pendingCount,
      'successfulSyncs': _successfulSyncs,
      'failedSyncs': _failedSyncs,
      'lastError': _lastError,
    };
  }

  /// Clear local cache (synced data only)
  Future<void> clearSyncedData() async {
    await _localDb.clearSyncedData();
    await _updatePendingCount();
    notifyListeners();
  }

  /// Reset all local data (use with caution)
  Future<void> resetAllLocalData() async {
    await _localDb.clearAllData();
    _lastSyncTime = null;
    _pendingCount = 0;
    _successfulSyncs = 0;
    _failedSyncs = 0;
    notifyListeners();
  }

  // ============ HELPER METHODS ============

  void _setSyncStatus(SyncStatus status, String? error) {
    _syncStatus = status;
    _lastError = error;
    notifyListeners();
  }

  /// Fire-and-forget helper
  void unawaited(Future<void> future) {
    future.catchError((error, stackTrace) {
      print('🚫 Unawaited error: $error');
      print('Stack trace: $stackTrace');
    });
  }

  // ============ CLEANUP ============

  @override
  void dispose() {
    print('🧹 Disposing Enhanced Offline Sync Service...');
    _connectivitySubscription?.cancel();
    _firebaseConnectionSubscription?.cancel();
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
