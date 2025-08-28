// lib/data/services/offline_sync_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:flutter/material.dart';

class OfflineSyncService extends ChangeNotifier {
  static final OfflineSyncService _instance = OfflineSyncService._internal();
  factory OfflineSyncService() => _instance;
  OfflineSyncService._internal();

  final LocalDatabaseService _localDb = LocalDatabaseService();
  final DatabaseService _firebaseDb = DatabaseService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;

  bool _isSyncing = false;
  bool _isOnline = false;
  DateTime? _lastSyncTime;

  // Getters
  bool get isSyncing => _isSyncing;
  bool get isOnline => _isOnline;
  DateTime? get lastSyncTime => _lastSyncTime;

  // Initialize service
  Future<void> initialize() async {
    await _checkConnectivity();
    _startConnectivityListener();
    _startPeriodicSync();

    // Initial sync if online
    if (_isOnline) {
      unawaited(_performSync());
    }
  }

  void _startConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) async {
      final wasOnline = _isOnline;
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);

      _isOnline = hasNetwork;

      if (_isOnline && !wasOnline) {
        print('📶 Connection restored - starting sync...');
        await _performSync();
      } else if (!_isOnline && wasOnline) {
        print('📵 Connection lost - switching to offline mode');
      }
      notifyListeners();
    });
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isOnline && !_isSyncing) {
        unawaited(_performSync());
      }
    });
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
  }

  // ============ MAIN SYNC OPERATIONS ============
  Future<void> _performSync() async {
    if (_isSyncing || !_isOnline) return;

    _isSyncing = true;
    notifyListeners();

    try {
      print('🔄 Starting sync process...');

      // Step 1: Push local changes to Firebase
      await _pushLocalChanges();

      // Step 2: Pull latest data from Firebase
      await _pullFirebaseData();

      _lastSyncTime = DateTime.now();
      print('✅ Sync completed successfully at ${_lastSyncTime}');
    } catch (e) {
      print('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // Push local unsynced data to Firebase
  Future<void> _pushLocalChanges() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    print('📤 Pushing local changes...');

    // Get pending sync items
    final pendingItems = await _localDb.getPendingSyncItems(limit: 100);

    for (final item in pendingItems) {
      try {
        await _processSyncItem(item);
        await _localDb.removeSyncItem(item['id']);
      } catch (e) {
        print('❌ Failed to sync item ${item['id']}: $e');
        await _localDb.incrementRetryCount(item['id']);

        // Remove items with too many retries (after 5 attempts)
        if (item['retryCount'] >= 5) {
          await _localDb.removeSyncItem(item['id']);
          print('🗑️ Removed item ${item['id']} after 5 failed attempts');
        }
      }
    }
  }

  Future<void> _processSyncItem(Map<String, dynamic> item) async {
    final tableName = item['tableName'] as String;
    final operation = item['operation'] as String;
    final data = jsonDecode(item['data'] as String);

    switch (tableName) {
      case 'transactions':
        await _syncTransaction(operation, data);
        break;
      case 'wallets':
        await _syncWallet(operation, data);
        break;
      case 'categories':
        await _syncCategory(operation, data);
        break;
    }
  }

  Future<void> _syncTransaction(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final transaction = TransactionModel(
          id: data['id'] ?? '',
          amount: data['amount'].toDouble(),
          type: TransactionType.values.firstWhere(
            (e) => e.name == data['type'],
          ),
          categoryId: data['categoryId'],
          walletId: data['walletId'],
          date: DateTime.parse(data['date']),
          description: data['description'] ?? '',
          userId: data['userId'],
          subCategoryId: data['subCategoryId'],
          transferToWalletId: data['transferToWalletId'],
        );

        await _firebaseDb.addTransaction(transaction);
        await _localDb.markAsSynced('transactions', transaction.id);
        break;

      case 'UPDATE':
        // Handle transaction updates
        break;

      case 'DELETE':
        // Handle transaction deletions
        break;
    }
  }

  Future<void> _syncWallet(String operation, Map<String, dynamic> data) async {
    switch (operation) {
      case 'INSERT':
        await _firebaseDb.addWallet(
          data['name'],
          data['balance'].toDouble(),
          data['ownerId'],
        );
        await _localDb.markAsSynced('wallets', data['id']);
        break;
    }
  }

  Future<void> _syncCategory(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        await _firebaseDb.addCategory(data['name'], data['type']);
        await _localDb.markAsSynced('categories', data['id']);
        break;
    }
  }

  // Pull latest data from Firebase and update local storage
  Future<void> _pullFirebaseData() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    print('📥 Pulling Firebase data...');

    // This would typically involve streaming data from Firebase
    // and updating local database with syncStatus = 1 (synced)

    // For now, we'll implement a basic version
    // In a real implementation, you'd want to:
    // 1. Get the last sync timestamp
    // 2. Query Firebase for changes since that timestamp
    // 3. Update local database with new/changed records

    // Example implementation would go here...
  }

  // ============ OFFLINE DATA ACCESS METHODS ============

  // Get transactions with fallback to local data
  Future<List<TransactionModel>> getTransactions({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      if (_isOnline) {
        // Try to get from Firebase first
        // If successful, cache to local DB
        // Return Firebase data
      }
    } catch (e) {
      print('Failed to get online data, falling back to local: $e');
    }

    // Fallback to local data
    return await _localDb.getLocalTransactions(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      limit: limit,
    );
  }

  // Add transaction with offline support
  Future<void> addTransaction(TransactionModel transaction) async {
    // Always save to local database first
    await _localDb.saveTransactionLocally(
      transaction,
      syncStatus: _isOnline ? 1 : 0,
    );

    // Save description to history
    if (transaction.description.isNotEmpty) {
      await _localDb.saveDescriptionToHistory(
        transaction.userId,
        transaction.description,
      );
    }

    if (_isOnline) {
      try {
        await _firebaseDb.addTransaction(transaction);
        await _localDb.markAsSynced('transactions', transaction.id);
      } catch (e) {
        print('Failed to sync transaction immediately: $e');
        // Will be synced later by background process
      }
    }
  }

  // Get description suggestions from local storage
  Future<List<String>> getDescriptionSuggestions(
    String userId, {
    int limit = 10,
  }) async {
    return await _localDb.getDescriptionSuggestions(userId, limit: limit);
  }

  // Search description history
  Future<List<String>> searchDescriptionHistory(
    String userId,
    String query,
  ) async {
    return await _localDb.searchDescriptionHistory(userId, query);
  }

  // Add wallet with offline support
  Future<void> addWallet(String name, double balance, String ownerId) async {
    final wallet = Wallet(
      id: DateTime.now().millisecondsSinceEpoch.toString(), // Temporary ID
      name: name,
      balance: balance,
      ownerId: ownerId,
    );

    await _localDb.saveWalletLocally(wallet, syncStatus: _isOnline ? 1 : 0);

    if (_isOnline) {
      try {
        await _firebaseDb.addWallet(name, balance, ownerId);
        await _localDb.markAsSynced('wallets', wallet.id);
      } catch (e) {
        print('Failed to sync wallet immediately: $e');
      }
    }
  }

  // Get wallets with offline support
  Future<List<Wallet>> getWallets(String ownerId) async {
    try {
      if (_isOnline) {
        // Try Firebase first, then cache locally
      }
    } catch (e) {
      print('Failed to get online wallets, using local: $e');
    }

    return await _localDb.getLocalWallets(ownerId);
  }

  // ============ FORCE SYNC METHODS ============

  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      throw Exception('Không có kết nối internet');
    }

    await _performSync();
  }

  Future<Map<String, int>> getSyncStats() async {
    return await _localDb.getDatabaseStats();
  }

  Future<void> clearLocalCache() async {
    await _localDb.clearSyncedData();
    notifyListeners();
  }

  Future<void> resetAllData() async {
    await _localDb.clearAllData();
    _lastSyncTime = null;
    notifyListeners();
  }

  // ============ CLEANUP ============

  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  // Helper method for fire-and-forget operations
  void unawaited(Future<void> future) {
    future.catchError((error) {
      print('Unawaited error: $error');
    });
  }
}
