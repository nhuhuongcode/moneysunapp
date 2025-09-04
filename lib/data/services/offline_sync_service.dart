// lib/data/services/offline_sync_service.dart - FIXED VERSION
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
  static const int _syncIntervalMinutes = 2;
  static const int _retryIntervalSeconds = 30;
  static const int _maxRetries = 5;
  static const int _batchSize = 20;

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

  // ============ FIXED: MISSING METHOD IMPLEMENTATIONS ============

  /// FIX: Get transactions from local database
  Future<List<TransactionModel>> getTransactions({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    int? limit,
  }) async {
    try {
      print('📱 Getting offline transactions for user: $userId');

      final transactions = await _localDb.getLocalTransactions(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
      );

      print('✅ Retrieved ${transactions.length} offline transactions');
      return transactions;
    } catch (e) {
      print('❌ Error getting offline transactions: $e');
      return [];
    }
  }

  /// FIX: Get wallets from local database
  Future<List<Wallet>> getWallets(String userId) async {
    try {
      print('📱 Getting offline wallets for user: $userId');

      final wallets = await _localDb.getLocalWallets(userId);

      print('✅ Retrieved ${wallets.length} offline wallets');
      return wallets;
    } catch (e) {
      print('❌ Error getting offline wallets: $e');
      return [];
    }
  }

  /// FIX: Get categories from local database
  Future<List<Category>> getCategories({String? userId, String? type}) async {
    try {
      print('📱 Getting offline categories for user: $userId, type: $type');

      final categories = await _localDb.getLocalCategories(
        ownerId: userId,
        type: type,
      );

      print('✅ Retrieved ${categories.length} offline categories');
      return categories;
    } catch (e) {
      print('❌ Error getting offline categories: $e');
      return [];
    }
  }

  /// FIX: Enhanced description suggestions with better error handling
  Future<List<String>> getDescriptionSuggestions(
    String userId, {
    int limit = 10,
    String? query,
    TransactionType? type,
  }) async {
    try {
      print('🔍 Getting description suggestions for user: $userId');

      // Get smart suggestions first
      if (query != null && query.isNotEmpty) {
        final searchResults = await searchDescriptionHistory(
          userId,
          query,
          limit: limit,
          type: type,
          fuzzySearch: true,
        );

        if (searchResults.isNotEmpty) {
          return searchResults;
        }
      }

      // Get contextual or recent suggestions
      final suggestions = await _localDb.getSmartDescriptionSuggestions(
        userId,
        limit: limit,
        query: query,
        type: type?.name,
      );

      // Fallback to basic suggestions
      if (suggestions.isEmpty) {
        final basicSuggestions = await _localDb.getDescriptionSuggestions(
          userId,
          limit: limit,
        );
        return basicSuggestions;
      }

      return suggestions;
    } catch (e) {
      print('❌ Error getting description suggestions: $e');

      // Ultimate fallback - return common descriptions
      return _getDefaultDescriptions(type);
    }
  }

  /// FIX: Get default descriptions as fallback
  List<String> _getDefaultDescriptions(TransactionType? type) {
    switch (type) {
      case TransactionType.expense:
        return [
          'Ăn trưa',
          'Cafe',
          'Xăng xe',
          'Đi chợ',
          'Mua sắm',
          'Hóa đơn điện',
          'Nước',
          'Internet',
          'Điện thoại',
          'Thuốc men',
        ];
      case TransactionType.income:
        return [
          'Lương',
          'Thưởng',
          'Tiền lãi',
          'Bán hàng',
          'Freelance',
          'Đầu tư',
          'Cho vay',
          'Tiền thuê',
          'Thưởng tết',
          'Phụ cấp',
        ];
      case TransactionType.transfer:
        return [
          'Chuyển tiết kiệm',
          'Nạp ví điện tử',
          'Rút tiền ATM',
          'Chuyển khoản',
          'Nạp thẻ',
          'Đầu tư',
          'Trả nợ',
        ];
      default:
        return ['Giao dịch', 'Chi tiêu', 'Thu nhập'];
    }
  }

  // ============ EXISTING METHODS (IMPROVED) ============

  Future<void> initialize() async {
    print('🚀 Initializing Enhanced Offline Sync Service...');

    try {
      await _checkInitialConnectivity();
      _startConnectivityListener();
      _startFirebaseConnectionListener();
      _startPeriodicSync();
      await _loadSyncMetadata();

      // Initial sync if online
      if (isOnline) {
        unawaited(_performFullSync());
      }

      print('✅ Enhanced Offline Sync Service initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize OfflineSyncService: $e');
      _lastError = 'Initialization failed: $e';
      _setSyncStatus(SyncStatus.error, _lastError);
    }
  }

  Future<void> _loadSyncMetadata() async {
    try {
      final stats = await _localDb.getDatabaseStats();
      _pendingCount = stats['pendingSync'] ?? 0;

      // Load last sync time from metadata
      final metadata = await _localDb.getSyncMetadata();
      final lastSyncStr = metadata['lastSyncTime'];
      if (lastSyncStr != null) {
        _lastSyncTime = DateTime.tryParse(lastSyncStr);
      }

      notifyListeners();
    } catch (e) {
      print('⚠️ Failed to load sync metadata: $e');
    }
  }

  Future<void> _checkInitialConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _isOnline = !result.contains(ConnectivityResult.none);
      print('📶 Initial connectivity: ${_isOnline ? "Online" : "Offline"}');
    } catch (e) {
      print('⚠️ Error checking connectivity: $e');
      _isOnline = false;
    }
  }

  void _startConnectivityListener() {
    _connectivitySubscription?.cancel();

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        final wasOnline = _isOnline;
        _isOnline = !results.contains(ConnectivityResult.none);

        print('📶 Connectivity changed: ${_isOnline ? "Online" : "Offline"}');

        if (_isOnline && !wasOnline) {
          print('🔄 Connection restored - scheduling sync...');
          await Future.delayed(const Duration(seconds: 2));
          unawaited(_performFullSync());
        } else if (!_isOnline && wasOnline) {
          print('📵 Connection lost - entering offline mode');
          _setSyncStatus(SyncStatus.error, 'Connection lost');
        }
        notifyListeners();
      },
      onError: (error) {
        print('❌ Connectivity listener error: $error');
      },
    );
  }

  void _startFirebaseConnectionListener() {
    _firebaseConnectionSubscription?.cancel();

    try {
      final connectedRef = _dbRef.child('.info/connected');
      _firebaseConnectionSubscription = connectedRef.onValue.listen(
        (DatabaseEvent event) {
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
        },
        onError: (error) {
          print('❌ Firebase connection listener error: $error');
          _isFirebaseConnected = false;
          notifyListeners();
        },
      );
    } catch (e) {
      print('❌ Error setting up Firebase connection listener: $e');
      _isFirebaseConnected = false;
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    _retryTimer?.cancel();

    _syncTimer = Timer.periodic(Duration(minutes: _syncIntervalMinutes), (
      timer,
    ) {
      if (isOnline && !_isSyncing) {
        unawaited(_performFullSync());
      }
    });

    _retryTimer = Timer.periodic(Duration(seconds: _retryIntervalSeconds), (
      timer,
    ) {
      if (isOnline && !_isSyncing && _pendingCount > 0) {
        unawaited(_performFullSync());
      }
    });
  }

  // ============ SYNC LOGIC (IMPROVED ERROR HANDLING) ============

  Future<void> _performFullSync() async {
    if (_isSyncing || !isOnline) return;

    _isSyncing = true;
    _setSyncStatus(SyncStatus.syncing, null);

    try {
      print('🔄 Starting full sync process...');

      await _updatePendingCount();
      await _pushLocalChangesToFirebase();

      // Save successful sync time
      _lastSyncTime = DateTime.now();
      await _localDb.setSyncMetadata(
        'lastSyncTime',
        _lastSyncTime!.toIso8601String(),
      );

      _successfulSyncs++;
      _setSyncStatus(SyncStatus.success, null);

      print('✅ Full sync completed successfully');
    } catch (e, stackTrace) {
      _failedSyncs++;
      final errorMsg = 'Sync failed: $e';
      _setSyncStatus(SyncStatus.error, errorMsg);

      print('❌ Full sync failed: $e');
      print('Stack trace: $stackTrace');

      // Log sync error for debugging
      await _localDb.logSyncOperation(
        operation: 'FULL_SYNC',
        tableName: 'all',
        success: false,
        error: errorMsg,
      );
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

    try {
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
          throw Exception('Unknown table: $tableName');
      }
    } catch (e) {
      print('❌ Error processing sync item: $e');
      rethrow;
    }
  }

  Future<void> _syncTransactionToFirebase(
    String operation,
    String recordId,
    Map<String, dynamic> data,
  ) async {
    final transactionRef = _dbRef.child('transactions');

    try {
      switch (operation) {
        case 'INSERT':
          await transactionRef.child(recordId).set(data);
          await _updateWalletBalanceForTransaction(data, isAdd: true);
          await _localDb.markAsSynced('transactions', recordId);
          break;

        case 'UPDATE':
          await transactionRef.child(recordId).update(data);
          await _localDb.markAsSynced('transactions', recordId);
          break;

        case 'DELETE':
          await _updateWalletBalanceForTransaction(data, isAdd: false);
          await transactionRef.child(recordId).remove();
          break;
      }
    } catch (e) {
      print('❌ Error syncing transaction: $e');
      rethrow;
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
          final transferToWalletId =
              transactionData['transferToWalletId'] as String?;
          balanceChange = isAdd ? -amount : amount;

          await _dbRef
              .child('wallets')
              .child(walletId)
              .child('balance')
              .set(ServerValue.increment(balanceChange));

          if (transferToWalletId != null) {
            await _dbRef
                .child('wallets')
                .child(transferToWalletId)
                .child('balance')
                .set(ServerValue.increment(isAdd ? amount : -amount));
          }
          return;
      }

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

    try {
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
    } catch (e) {
      print('❌ Error syncing wallet: $e');
      rethrow;
    }
  }

  Future<void> _syncCategoryToFirebase(
    String operation,
    String recordId,
    Map<String, dynamic> data,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    final categoryRef = _dbRef.child('categories').child(currentUser.uid);

    try {
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
    } catch (e) {
      print('❌ Error syncing category: $e');
      rethrow;
    }
  }

  // ============ PUBLIC API METHODS (IMPROVED) ============

  Future<void> forceSyncNow() async {
    if (!isOnline) {
      throw Exception(
        'Không có kết nối internet. Vui lòng kiểm tra kết nối và thử lại.',
      );
    }

    if (_isSyncing) {
      print('⚠️ Sync already in progress, skipping...');
      return;
    }

    print('🔄 Manual sync requested');
    await _performFullSync();
  }

  Future<void> addTransactionOffline(TransactionModel transaction) async {
    try {
      print('💾 Adding transaction offline-first: ${transaction.id}');

      await _localDb.saveTransactionLocally(transaction, syncStatus: 0);

      if (transaction.description.isNotEmpty) {
        await _localDb.saveDescriptionToHistory(
          transaction.userId,
          transaction.description,
        );
      }

      await _updatePendingCount();

      if (isOnline && !_isSyncing) {
        unawaited(_performFullSync());
      }

      notifyListeners();
    } catch (e) {
      print('❌ Error adding transaction offline: $e');
      rethrow;
    }
  }

  Future<void> addWalletOffline(Wallet wallet) async {
    try {
      print('💾 Adding wallet offline-first: ${wallet.id}');

      await _localDb.saveWalletLocally(wallet, syncStatus: 0);
      await _updatePendingCount();

      if (isOnline && !_isSyncing) {
        unawaited(_performFullSync());
      }

      notifyListeners();
    } catch (e) {
      print('❌ Error adding wallet offline: $e');
      rethrow;
    }
  }

  Future<void> addCategoryOffline(Category category) async {
    try {
      print('💾 Adding category offline-first: ${category.id}');

      await _localDb.saveCategoryLocally(category, syncStatus: 0);
      await _updatePendingCount();

      if (isOnline && !_isSyncing) {
        unawaited(_performFullSync());
      }

      notifyListeners();
    } catch (e) {
      print('❌ Error adding category offline: $e');
      rethrow;
    }
  }

  // FIX: Enhanced description search with proper error handling
  Future<List<String>> searchDescriptionHistory(
    String userId,
    String query, {
    int limit = 5,
    TransactionType? type,
    bool fuzzySearch = true,
  }) async {
    if (query.trim().isEmpty) return [];

    try {
      return await _localDb.searchDescriptionHistory(
        userId,
        query.trim(),
        limit: limit,
        type: type?.name,
        fuzzySearch: fuzzySearch,
      );
    } catch (e) {
      print("❌ Error searching description history: $e");

      // Fallback to simple contains search
      return _getDefaultDescriptions(type)
          .where((desc) => desc.toLowerCase().contains(query.toLowerCase()))
          .take(limit)
          .toList();
    }
  }

  Future<void> saveDescriptionWithContext(
    String userId,
    String description, {
    TransactionType? type,
    String? categoryId,
    double? amount,
  }) async {
    if (description.trim().isEmpty) return;

    try {
      await _localDb.saveDescriptionWithContext(
        userId,
        description.trim(),
        type: type?.name,
        categoryId: categoryId,
        amount: amount,
      );

      if (isOnline) {
        try {
          await _dbRef.child('user_descriptions').child(userId).update({
            description.trim(): {
              'count': ServerValue.increment(1),
              'lastUsed': ServerValue.timestamp,
              'type': type?.name,
              'categoryId': categoryId,
              'amount': amount,
            },
          });
        } catch (e) {
          print("⚠️ Warning: Failed to sync description to Firebase: $e");
        }
      }
    } catch (e) {
      print("❌ Error saving description with context: $e");
    }
  }

  Future<List<String>> getContextualSuggestions(
    String userId, {
    TransactionType? type,
    String? categoryId,
    double? amount,
    int limit = 5,
  }) async {
    try {
      return await _localDb.getContextualSuggestions(
        userId,
        type: type?.name,
        categoryId: categoryId,
        amount: amount,
        limit: limit,
      );
    } catch (e) {
      print("❌ Error getting contextual suggestions: $e");
      return [];
    }
  }

  Map<String, dynamic> getSyncStats() {
    return {
      'isOnline': isOnline,
      'isNetworkConnected': _isOnline,
      'isFirebaseConnected': _isFirebaseConnected,
      'syncStatus': _syncStatus.toString(),
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'pendingCount': _pendingCount,
      'successfulSyncs': _successfulSyncs,
      'failedSyncs': _failedSyncs,
      'lastError': _lastError,
      'isSyncing': _isSyncing,
    };
  }

  Future<void> clearSyncedData() async {
    try {
      await _localDb.clearSyncedData();
      await _updatePendingCount();
      notifyListeners();
    } catch (e) {
      print('❌ Error clearing synced data: $e');
      rethrow;
    }
  }

  Future<void> resetAllLocalData() async {
    try {
      await _localDb.clearAllData();
      _lastSyncTime = null;
      _pendingCount = 0;
      _successfulSyncs = 0;
      _failedSyncs = 0;
      notifyListeners();
    } catch (e) {
      print('❌ Error resetting local data: $e');
      rethrow;
    }
  }

  // ============ HELPER METHODS ============

  void _setSyncStatus(SyncStatus status, String? error) {
    _syncStatus = status;
    _lastError = error;
    notifyListeners();
  }

  void unawaited(Future<void> future) {
    future.catchError((error, stackTrace) {
      print('🚫 Unawaited error: $error');
      print('Stack trace: $stackTrace');
    });
  }

  @override
  void dispose() {
    print('🔄 Disposing Enhanced Offline Sync Service...');
    _connectivitySubscription?.cancel();
    _firebaseConnectionSubscription?.cancel();
    _syncTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
