// lib/data/services/offline_first_service.dart - TỔNG HỢP OFFLINE-FIRST
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/enhanced_budget_service.dart';
import 'package:moneysun/data/services/enhanced_category_service.dart';
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/services/database_service.dart';

// ============ MAIN OFFLINE-FIRST SERVICE ============
class OfflineFirstService extends ChangeNotifier {
  static final OfflineFirstService _instance = OfflineFirstService._internal();
  factory OfflineFirstService() => _instance;
  OfflineFirstService._internal();

  // Services
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final DatabaseService _firebaseDb = DatabaseService();
  final EnhancedBudgetService _budgetService = EnhancedBudgetService();
  final EnhancedCategoryService _categoryService = EnhancedCategoryService();
  final Connectivity _connectivity = Connectivity();

  // State
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  Timer? _healthCheckTimer;

  bool _isOnline = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _pendingItems = 0;
  String? _lastError;
  Map<String, int> _syncStats = {};

  // Getters
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
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

    print('✅ Offline-First Service initialized');
    print('📊 Online: $_isOnline, Pending: $_pendingItems items');

    // Initial sync if online
    if (_isOnline) {
      unawaited(_performFullSync());
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
        _lastError = null;
        await _performFullSync();
      } else if (!_isOnline && wasOnline) {
        print('📵 Connection lost - switching to offline mode');
        _setSyncStatus(false);
      }

      notifyListeners();
    });
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isOnline && !_isSyncing && _pendingItems > 0) {
        unawaited(_performFullSync());
      }
    });
  }

  void _startHealthCheck() {
    _healthCheckTimer = Timer.periodic(const Duration(minutes: 1), (
      timer,
    ) async {
      await _updatePendingItemsCount();
      await _updateSyncStats();
      notifyListeners();
    });
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
  }

  void _setSyncStatus(bool syncing) {
    if (_isSyncing != syncing) {
      _isSyncing = syncing;
      notifyListeners();
    }
  }

  // ============ MAIN SYNC OPERATIONS ============
  Future<void> _performFullSync() async {
    if (_isSyncing || !_isOnline) return;

    _setSyncStatus(true);
    _lastError = null;

    try {
      print('🔄 Starting full offline-first sync...');

      int totalSynced = 0;
      int totalFailed = 0;

      // Step 1: Sync categories first (dependencies)
      final categoryResult = await _syncCategories();
      totalSynced += categoryResult.syncedItems;
      totalFailed += categoryResult.failedItems;

      // Step 2: Sync budgets (depends on categories)
      final budgetResult = await _syncBudgets();
      totalSynced += budgetResult.syncedItems;
      totalFailed += budgetResult.failedItems;

      // Step 3: Sync transactions and wallets
      final results = await Future.wait([_syncTransactions(), _syncWallets()]);

      for (final result in results) {
        totalSynced += result.syncedItems;
        totalFailed += result.failedItems;
      }

      _lastSyncTime = DateTime.now();
      await _updatePendingItemsCount();

      print('✅ Sync completed: $totalSynced synced, $totalFailed failed');
    } catch (e) {
      _lastError = e.toString();
      print('❌ Sync failed: $e');
    } finally {
      _setSyncStatus(false);
      await _updatePendingItemsCount();
      await _updateSyncStats();
    }
  }

  // ============ CATEGORY SYNC ============
  Future<SyncResult> _syncCategories() async {
    try {
      print('📂 Syncing categories...');

      final unsyncedCategories = await _localDb.getUnsyncedRecords(
        'categories',
      );
      int synced = 0;
      int failed = 0;

      for (final record in unsyncedCategories) {
        try {
          final category = _categoryFromMap(record);

          // Sync to Firebase
          await _categoryService.createCategoryWithOwnership(
            name: category.name,
            type: category.type,
            ownershipType: category.ownershipType,
            userProvider: _getCurrentUserProvider(),
            iconCodePoint: category.iconCodePoint,
            subCategories: category.subCategories,
          );

          await _localDb.markAsSynced('categories', category.id);
          synced++;
          print('✅ Synced category: ${category.name}');
        } catch (e) {
          print('❌ Failed to sync category ${record['id']}: $e');
          failed++;
        }
      }

      return SyncResult.success(synced);
    } catch (e) {
      print('❌ Category sync error: $e');
      return SyncResult.failure(e.toString(), 0);
    }
  }

  // ============ BUDGET SYNC ============
  Future<SyncResult> _syncBudgets() async {
    try {
      print('💰 Syncing budgets...');

      final unsyncedBudgets = await _localDb.getUnsyncedRecords('budgets');
      int synced = 0;
      int failed = 0;

      for (final record in unsyncedBudgets) {
        try {
          final budget = _budgetFromMap(record);

          // Sync to Firebase
          await _budgetService.createBudgetWithOwnership(
            month: budget.month,
            totalAmount: budget.totalAmount,
            categoryAmounts: budget.categoryAmounts,
            budgetType: budget.budgetType,
            userProvider: _getCurrentUserProvider(),
            period: budget.period,
            notes: budget.notes,
            categoryLimits: budget.categoryLimits,
          );

          await _localDb.markAsSynced('budgets', budget.id);
          synced++;
          print('✅ Synced budget: ${budget.displayName}');
        } catch (e) {
          print('❌ Failed to sync budget ${record['id']}: $e');
          failed++;
        }
      }

      return SyncResult.success(synced);
    } catch (e) {
      print('❌ Budget sync error: $e');
      return SyncResult.failure(e.toString(), 0);
    }
  }

  // ============ TRANSACTION SYNC ============
  Future<SyncResult> _syncTransactions() async {
    try {
      print('💸 Syncing transactions...');

      final unsyncedTransactions = await _localDb.getUnsyncedRecords(
        'transactions',
      );
      int synced = 0;
      int failed = 0;

      for (final record in unsyncedTransactions) {
        try {
          final transaction = _transactionFromMap(record);

          // Sync to Firebase
          await _firebaseDb.addTransaction(transaction);

          await _localDb.markAsSynced('transactions', transaction.id);
          synced++;
          print('✅ Synced transaction: ${transaction.description}');
        } catch (e) {
          print('❌ Failed to sync transaction ${record['id']}: $e');
          failed++;
        }
      }

      return SyncResult.success(synced);
    } catch (e) {
      print('❌ Transaction sync error: $e');
      return SyncResult.failure(e.toString(), 0);
    }
  }

  // ============ WALLET SYNC ============
  Future<SyncResult> _syncWallets() async {
    try {
      print('👛 Syncing wallets...');

      final unsyncedWallets = await _localDb.getUnsyncedRecords('wallets');
      int synced = 0;
      int failed = 0;

      for (final record in unsyncedWallets) {
        try {
          final wallet = _walletFromMap(record);

          // Sync to Firebase
          await _firebaseDb.addWallet(
            wallet.name,
            wallet.balance,
            wallet.ownerId,
          );

          await _localDb.markAsSynced('wallets', wallet.id);
          synced++;
          print('✅ Synced wallet: ${wallet.name}');
        } catch (e) {
          print('❌ Failed to sync wallet ${record['id']}: $e');
          failed++;
        }
      }

      return SyncResult.success(synced);
    } catch (e) {
      print('❌ Wallet sync error: $e');
      return SyncResult.failure(e.toString(), 0);
    }
  }

  // ============ OFFLINE-FIRST DATA ACCESS ============

  /// Categories - Offline First
  Future<List<Category>> getCategoriesOfflineFirst({
    String? type,
    CategoryOwnershipType? ownershipType,
    UserProvider? userProvider,
  }) async {
    try {
      // Try local first
      final localCategories = await _categoryService.getCategoriesOfflineFirst(
        type: type,
        ownershipType: ownershipType,
        userProvider: userProvider,
      );

      if (localCategories.isNotEmpty) {
        print('📱 Returning ${localCategories.length} categories from local');
        return localCategories;
      }

      // Fallback to Firebase if online
      if (_isOnline && userProvider != null) {
        print('☁️ Fetching categories from Firebase...');
        return await _categoryService
            .getCategoriesWithOwnershipStream(userProvider, type: type)
            .first;
      }

      return [];
    } catch (e) {
      print('❌ Error getting categories: $e');
      return [];
    }
  }

  /// Budgets - Offline First
  Future<List<Budget>> getBudgetsOfflineFirst({
    String? month,
    BudgetType? budgetType,
    UserProvider? userProvider,
  }) async {
    try {
      // Try local first
      final localBudgets = await _budgetService.getBudgetsOfflineFirst(
        month: month,
        budgetType: budgetType,
        userProvider: userProvider,
      );

      if (localBudgets.isNotEmpty) {
        print('📱 Returning ${localBudgets.length} budgets from local');
        return localBudgets;
      }

      // Fallback to Firebase if online
      if (_isOnline && userProvider != null) {
        print('☁️ Fetching budgets from Firebase...');
        return await _budgetService
            .getBudgetsWithOwnershipStream(
              userProvider,
              month: month,
              budgetType: budgetType,
            )
            .first;
      }

      return [];
    } catch (e) {
      print('❌ Error getting budgets: $e');
      return [];
    }
  }

  /// Transactions - Offline First
  Future<List<TransactionModel>> getTransactionsOfflineFirst({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    try {
      // Try local first
      final localTransactions = await _localDb.getLocalTransactions(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
      );

      if (localTransactions.isNotEmpty) {
        print(
          '📱 Returning ${localTransactions.length} transactions from local',
        );
        return localTransactions;
      }

      return [];
    } catch (e) {
      print('❌ Error getting transactions: $e');
      return [];
    }
  }

  // ============ OFFLINE-FIRST WRITE OPERATIONS ============

  /// Add Category - Offline First
  Future<void> addCategoryOfflineFirst({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    required UserProvider userProvider,
    int? iconCodePoint,
    Map<String, String>? subCategories,
  }) async {
    try {
      // Always save locally first
      await _categoryService.createCategoryWithOwnership(
        name: name,
        type: type,
        ownershipType: ownershipType,
        userProvider: userProvider,
        iconCodePoint: iconCodePoint,
        subCategories: subCategories,
      );

      // Update pending count
      await _updatePendingItemsCount();
      notifyListeners();

      // Sync immediately if online
      if (_isOnline) {
        unawaited(_performFullSync());
      }
    } catch (e) {
      print('❌ Error adding category: $e');
      rethrow;
    }
  }

  /// Add Budget - Offline First
  Future<void> addBudgetOfflineFirst({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    required BudgetType budgetType,
    required UserProvider userProvider,
    BudgetPeriod period = BudgetPeriod.monthly,
    Map<String, String>? notes,
    Map<String, double>? categoryLimits,
  }) async {
    try {
      // Always save locally first
      await _budgetService.createBudgetWithOwnership(
        month: month,
        totalAmount: totalAmount,
        categoryAmounts: categoryAmounts,
        budgetType: budgetType,
        userProvider: userProvider,
        period: period,
        notes: notes,
        categoryLimits: categoryLimits,
      );

      // Update pending count
      await _updatePendingItemsCount();
      notifyListeners();

      // Sync immediately if online
      if (_isOnline) {
        unawaited(_performFullSync());
      }
    } catch (e) {
      print('❌ Error adding budget: $e');
      rethrow;
    }
  }

  /// Add Transaction - Offline First
  Future<void> addTransactionOfflineFirst(TransactionModel transaction) async {
    try {
      // Always save locally first
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

      // Update pending count
      await _updatePendingItemsCount();
      notifyListeners();

      // Try to sync immediately if online
      if (_isOnline) {
        try {
          await _firebaseDb.addTransaction(transaction);
          await _localDb.markAsSynced('transactions', transaction.id);
        } catch (e) {
          print('Failed to sync transaction immediately: $e');
          // Will be synced later by background process
        }
      }
    } catch (e) {
      print('❌ Error adding transaction: $e');
      rethrow;
    }
  }

  // ============ HELPER METHODS ============
  Future<void> _updatePendingItemsCount() async {
    try {
      final stats = await _localDb.getDatabaseStats();
      _pendingItems = stats['pendingSync'] ?? 0;
    } catch (e) {
      print('Error updating pending items count: $e');
      _pendingItems = 0;
    }
  }

  Future<void> _updateSyncStats() async {
    try {
      final stats = await _localDb.getDatabaseStats();
      _syncStats = Map<String, int>.from(stats);
    } catch (e) {
      print('Error updating sync stats: $e');
      _syncStats = {};
    }
  }

  UserProvider _getCurrentUserProvider() {
    // This should be injected or retrieved from app context
    // For now, return a mock - in real app, get from Provider context
    throw UnimplementedError('UserProvider should be injected');
  }

  // ============ MODEL CONVERTERS ============
  Category _categoryFromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      ownerId: map['ownerId'],
      type: map['type'],
      iconCodePoint: map['iconCodePoint'],
      subCategories: map['subCategories'] != null
          ? Map<String, String>.from(map['subCategories'])
          : {},
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == (map['ownershipType'] ?? 'personal'),
        orElse: () => CategoryOwnershipType.personal,
      ),
      createdBy: map['createdBy'],
      isArchived: (map['isArchived'] ?? 0) == 1,
    );
  }

  Budget _budgetFromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'],
      ownerId: map['ownerId'],
      month: map['month'],
      totalAmount: (map['totalAmount'] as num).toDouble(),
      categoryAmounts: map['categoryAmounts'] != null
          ? Map<String, double>.from(map['categoryAmounts'])
          : {},
      budgetType: BudgetType.values.firstWhere(
        (e) => e.name == (map['budgetType'] ?? 'personal'),
        orElse: () => BudgetType.personal,
      ),
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == (map['period'] ?? 'monthly'),
        orElse: () => BudgetPeriod.monthly,
      ),
      createdBy: map['createdBy'],
      isActive: (map['isActive'] ?? 1) == 1,
    );
  }

  TransactionModel _transactionFromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => TransactionType.expense,
      ),
      categoryId: map['categoryId'],
      walletId: map['walletId'],
      date: DateTime.parse(map['date']),
      description: map['description'] ?? '',
      userId: map['userId'],
      subCategoryId: map['subCategoryId'],
      transferToWalletId: map['transferToWalletId'],
    );
  }

  Wallet _walletFromMap(Map<String, dynamic> map) {
    return Wallet(
      id: map['id'],
      name: map['name'],
      balance: (map['balance'] as num).toDouble(),
      ownerId: map['ownerId'],
      isVisibleToPartner: (map['isVisibleToPartner'] ?? 1) == 1,
    );
  }

  // ============ PUBLIC INTERFACE ============
  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      throw Exception('Không có kết nối internet');
    }
    await _performFullSync();
  }

  Future<Map<String, dynamic>> getHealthStatus() async {
    return {
      'isOnline': _isOnline,
      'isSyncing': _isSyncing,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'pendingItems': _pendingItems,
      'lastError': _lastError,
      'syncStats': _syncStats,
    };
  }

  Future<void> clearAllLocalData() async {
    await _localDb.clearAllData();
    await _updatePendingItemsCount();
    _lastSyncTime = null;
    notifyListeners();
  }

  // ============ CLEANUP ============
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _healthCheckTimer?.cancel();
    super.dispose();
  }

  void unawaited(Future<void> future) {
    future.catchError((error) {
      print('Unawaited error: $error');
    });
  }
}

// ============ SYNC RESULT MODEL ============
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
}

// ============ OFFLINE-FIRST MIXIN ============
mixin OfflineFirstMixin {
  final OfflineFirstService _offlineService = OfflineFirstService();

  bool get isOnline => _offlineService.isOnline;
  bool get isSyncing => _offlineService.isSyncing;
  int get pendingItems => _offlineService.pendingItems;

  Future<void> syncIfOnline() async {
    if (isOnline) {
      await _offlineService.forceSyncNow();
    }
  }

  String getConnectivityStatus() {
    if (isSyncing) return 'Đang đồng bộ...';
    if (!isOnline) return 'Offline';
    if (pendingItems > 0) return 'Có $pendingItems mục chưa đồng bộ';
    return 'Đã đồng bộ';
  }
}
