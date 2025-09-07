// lib/data/services/data_service.dart - UNIFIED OFFLINE-FIRST SERVICE
import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/local_database_service.dart';

/// Unified Data Service - Replaces all duplicate services
/// Implements true offline-first pattern with proper sync
class DataService extends ChangeNotifier {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  // Dependencies
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final DatabaseReference _firebaseRef = FirebaseDatabase.instance.ref();
  final Connectivity _connectivity = Connectivity();

  // State
  bool _isOnline = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _pendingItems = 0;
  String? _lastError;
  UserProvider? _userProvider;

  // Subscriptions
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;

  // Getters
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingItems => _pendingItems;
  String? get lastError => _lastError;
  String? get currentUserId => FirebaseAuth.instance.currentUser?.uid;

  // ============ INITIALIZATION ============

  Future<void> initialize(UserProvider userProvider) async {
    _userProvider = userProvider;

    await _checkConnectivity();
    _startConnectivityListener();
    _startPeriodicSync();
    await _updatePendingItemsCount();

    print(
      '✅ DataService initialized - Online: $_isOnline, Pending: $_pendingItems',
    );

    if (_isOnline) {
      unawaited(_performFullSync());
    }
  }

  void _startConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) async {
      final wasOnline = _isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);

      if (_isOnline && !wasOnline) {
        print('📶 Connection restored - starting sync...');
        _lastError = null;
        await _performFullSync();
      } else if (!_isOnline && wasOnline) {
        print('📵 Connection lost - switching to offline mode');
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

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result != ConnectivityResult.none;
  }

  // ============ TRANSACTIONS - OFFLINE FIRST ============

  /// Add transaction - Always save locally first
  Future<void> addTransaction(TransactionModel transaction) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    try {
      // 1. Always save locally first (offline-first)
      await _localDb.saveTransactionLocally(transaction, syncStatus: 0);

      // 2. Update wallet balance locally
      await _updateWalletBalanceLocally(transaction);

      // 3. Save description to history
      if (transaction.description.isNotEmpty) {
        await _localDb.saveDescriptionToHistory(
          currentUserId!,
          transaction.description,
        );
      }

      // 4. Update pending count
      await _updatePendingItemsCount();
      notifyListeners();

      // 5. Try immediate sync if online
      if (_isOnline) {
        try {
          await _syncTransactionToFirebase(transaction);
          await _localDb.markAsSynced('transactions', transaction.id);
          await _updatePendingItemsCount();
          notifyListeners();
        } catch (e) {
          print('⚠️ Immediate sync failed, will retry later: $e');
          // Will be synced by background process
        }
      }
    } catch (e) {
      print('❌ Error adding transaction: $e');
      rethrow;
    }
  }

  /// Get transactions - Offline first with Firebase fallback
  Future<List<TransactionModel>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    if (currentUserId == null) return [];

    try {
      // Always try local first (offline-first pattern)
      final localTransactions = await _localDb.getLocalTransactions(
        userId: currentUserId,
        startDate: startDate,
        endDate: endDate,
        limit: limit,
      );

      // If we have local data, return it (with optional background refresh)
      if (localTransactions.isNotEmpty) {
        print(
          '📱 Returning ${localTransactions.length} transactions from local',
        );

        // Background refresh if online (don't await)
        if (_isOnline) {
          unawaited(_refreshTransactionsFromFirebase(startDate, endDate));
        }

        return localTransactions;
      }

      // If no local data and online, try Firebase
      if (_isOnline) {
        print('☁️ No local data, fetching from Firebase...');
        return await _fetchTransactionsFromFirebase(startDate, endDate, limit);
      }

      // No data available
      return [];
    } catch (e) {
      print('❌ Error getting transactions: $e');
      return [];
    }
  }

  /// Update transaction
  Future<void> updateTransaction(
    TransactionModel newTransaction,
    TransactionModel oldTransaction,
  ) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    try {
      // 1. Update locally first
      await _localDb.updateTransactionLocally(newTransaction);

      // 2. Update wallet balances
      await _revertWalletBalance(oldTransaction);
      await _updateWalletBalanceLocally(newTransaction);

      // 3. Save description
      if (newTransaction.description.isNotEmpty) {
        await _localDb.saveDescriptionToHistory(
          currentUserId!,
          newTransaction.description,
        );
      }

      await _updatePendingItemsCount();
      notifyListeners();

      // 4. Sync if online
      if (_isOnline) {
        try {
          await _updateTransactionOnFirebase(newTransaction, oldTransaction);
          await _localDb.markAsSynced('transactions', newTransaction.id);
        } catch (e) {
          print('⚠️ Update sync failed: $e');
        }
      }
    } catch (e) {
      print('❌ Error updating transaction: $e');
      rethrow;
    }
  }

  /// Delete transaction
  Future<void> deleteTransaction(TransactionModel transaction) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    try {
      // 1. Revert wallet balance
      await _revertWalletBalance(transaction);

      // 2. Delete locally
      await _localDb.deleteTransactionLocally(transaction.id);

      await _updatePendingItemsCount();
      notifyListeners();

      // 3. Delete from Firebase if online
      if (_isOnline) {
        try {
          await _deleteTransactionFromFirebase(transaction);
        } catch (e) {
          print('⚠️ Delete sync failed: $e');
        }
      }
    } catch (e) {
      print('❌ Error deleting transaction: $e');
      rethrow;
    }
  }

  // ============ CATEGORIES - OFFLINE FIRST ============

  /// Add category
  Future<void> addCategory({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    int? iconCodePoint,
    Map<String, String>? subCategories,
  }) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    if (_userProvider == null) throw Exception('UserProvider not initialized');

    try {
      // Determine owner ID
      String ownerId;
      if (ownershipType == CategoryOwnershipType.shared) {
        if (_userProvider!.partnershipId == null) {
          throw Exception('Không thể tạo danh mục chung khi chưa có đối tác');
        }
        ownerId = _userProvider!.partnershipId!;
      } else {
        ownerId = currentUserId!;
      }

      // Create category
      final categoryId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
      final category = Category(
        id: categoryId,
        name: name,
        ownerId: ownerId,
        type: type,
        ownershipType: ownershipType,
        createdBy: currentUserId,
        iconCodePoint: iconCodePoint,
        subCategories: subCategories ?? {},
        createdAt: DateTime.now(),
      );

      // 1. Save locally first
      await _localDb.saveCategoryLocally(category, syncStatus: 0);

      await _updatePendingItemsCount();
      notifyListeners();

      // 2. Sync if online
      if (_isOnline) {
        try {
          await _syncCategoryToFirebase(category);
          await _localDb.markAsSynced('categories', category.id);

          // Send notification if shared
          if (ownershipType == CategoryOwnershipType.shared &&
              _userProvider!.partnerUid != null) {
            await _sendCategoryNotification(
              _userProvider!.partnerUid!,
              'Danh mục chung mới',
              '${_userProvider!.currentUser?.displayName ?? "Đối tác"} đã tạo danh mục "$name" chung',
            );
          }
        } catch (e) {
          print('⚠️ Category sync failed: $e');
        }
      }
    } catch (e) {
      print('❌ Error adding category: $e');
      rethrow;
    }
  }

  /// Get categories
  Future<List<Category>> getCategories({
    String? type,
    CategoryOwnershipType? ownershipType,
  }) async {
    if (currentUserId == null) return [];

    try {
      // Get from local database first
      final localCategories = await _localDb.getLocalCategories(
        ownerId: currentUserId,
        type: type,
      );

      // Filter by ownership if user has partnership
      final filteredCategories = _filterCategoriesByOwnership(localCategories);

      if (filteredCategories.isNotEmpty) {
        print(
          '📱 Returning ${filteredCategories.length} categories from local',
        );

        // Background refresh if online
        if (_isOnline) {
          unawaited(_refreshCategoriesFromFirebase());
        }

        return filteredCategories;
      }

      // If no local data and online, fetch from Firebase
      if (_isOnline) {
        print('☁️ No local categories, fetching from Firebase...');
        return await _fetchCategoriesFromFirebase(type);
      }

      return [];
    } catch (e) {
      print('❌ Error getting categories: $e');
      return [];
    }
  }

  // ============ WALLETS - OFFLINE FIRST ============

  /// Add wallet
  Future<void> addWallet(
    String name,
    double initialBalance, {
    String? ownerId,
  }) async {
    if (currentUserId == null) throw Exception('User not authenticated');

    try {
      final walletId = 'wallet_${DateTime.now().millisecondsSinceEpoch}';
      final wallet = Wallet(
        id: walletId,
        name: name,
        balance: initialBalance,
        ownerId: ownerId ?? currentUserId!,
        createdAt: DateTime.now(),
      );

      // 1. Save locally first
      await _localDb.saveWalletLocally(wallet, syncStatus: 0);

      await _updatePendingItemsCount();
      notifyListeners();

      // 2. Sync if online
      if (_isOnline) {
        try {
          await _syncWalletToFirebase(wallet);
          await _localDb.markAsSynced('wallets', wallet.id);
        } catch (e) {
          print('⚠️ Wallet sync failed: $e');
        }
      }
    } catch (e) {
      print('❌ Error adding wallet: $e');
      rethrow;
    }
  }

  /// Get wallets
  Future<List<Wallet>> getWallets() async {
    if (currentUserId == null) return [];

    try {
      // Get from local first
      final localWallets = await _localDb.getLocalWallets(currentUserId!);

      // Filter by visibility if user has partnership
      final filteredWallets = _filterWalletsByVisibility(localWallets);

      if (filteredWallets.isNotEmpty) {
        print('📱 Returning ${filteredWallets.length} wallets from local');

        // Background refresh
        if (_isOnline) {
          unawaited(_refreshWalletsFromFirebase());
        }

        return filteredWallets;
      }

      // Fetch from Firebase if no local data
      if (_isOnline) {
        print('☁️ No local wallets, fetching from Firebase...');
        return await _fetchWalletsFromFirebase();
      }

      return [];
    } catch (e) {
      print('❌ Error getting wallets: $e');
      return [];
    }
  }

  // ============ BUDGETS - OFFLINE FIRST ============

  /// Add budget
  Future<void> addBudget({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    required BudgetType budgetType,
    BudgetPeriod period = BudgetPeriod.monthly,
    Map<String, String>? notes,
    Map<String, double>? categoryLimits,
  }) async {
    if (currentUserId == null) throw Exception('User not authenticated');
    if (_userProvider == null) throw Exception('UserProvider not initialized');

    try {
      // Determine owner
      String ownerId;
      if (budgetType == BudgetType.shared) {
        if (_userProvider!.partnershipId == null) {
          throw Exception('Không thể tạo ngân sách chung khi chưa có đối tác');
        }
        ownerId = _userProvider!.partnershipId!;
      } else {
        ownerId = currentUserId!;
      }

      final budgetId = 'budget_${DateTime.now().millisecondsSinceEpoch}';
      final budget = Budget(
        id: budgetId,
        ownerId: ownerId,
        month: month,
        totalAmount: totalAmount,
        categoryAmounts: categoryAmounts,
        budgetType: budgetType,
        period: period,
        createdBy: currentUserId,
        notes: notes,
        categoryLimits: categoryLimits,
        createdAt: DateTime.now(),
      );

      // 1. Save locally first
      await _localDb.saveBudgetLocally(budget, syncStatus: 0);

      await _updatePendingItemsCount();
      notifyListeners();

      // 2. Sync if online
      if (_isOnline) {
        try {
          await _syncBudgetToFirebase(budget);
          await _localDb.markAsSynced('budgets', budget.id);

          // Send notification if shared
          if (budgetType == BudgetType.shared &&
              _userProvider!.partnerUid != null) {
            await _sendBudgetNotification(
              _userProvider!.partnerUid!,
              'Ngân sách chung mới',
              '${_userProvider!.currentUser?.displayName ?? "Đối tác"} đã tạo ngân sách chung cho tháng $month',
            );
          }
        } catch (e) {
          print('⚠️ Budget sync failed: $e');
        }
      }
    } catch (e) {
      print('❌ Error adding budget: $e');
      rethrow;
    }
  }

  /// Get budgets
  Future<List<Budget>> getBudgets({
    String? month,
    BudgetType? budgetType,
  }) async {
    if (currentUserId == null) return [];

    try {
      // Get from local first
      final localBudgets = await _localDb.getLocalBudgets(
        ownerId: currentUserId,
        budgetType: budgetType,
        month: month,
      );

      final filteredBudgets = _filterBudgetsByOwnership(localBudgets);

      if (filteredBudgets.isNotEmpty) {
        print('📱 Returning ${filteredBudgets.length} budgets from local');

        // Background refresh
        if (_isOnline) {
          unawaited(_refreshBudgetsFromFirebase());
        }

        return filteredBudgets;
      }

      // Fetch from Firebase if no local data
      if (_isOnline) {
        print('☁️ No local budgets, fetching from Firebase...');
        return await _fetchBudgetsFromFirebase(month, budgetType);
      }

      return [];
    } catch (e) {
      print('❌ Error getting budgets: $e');
      return [];
    }
  }

  // ============ REPORTS ============

  Future<ReportData> getReportData(DateTime startDate, DateTime endDate) async {
    if (currentUserId == null) {
      return ReportData(
        expenseByCategory: {},
        incomeByCategory: {},
        rawTransactions: [],
      );
    }

    try {
      final transactions = await getTransactions(
        startDate: startDate,
        endDate: endDate,
      );

      final categories = await getCategories();

      double personalIncome = 0;
      double personalExpense = 0;
      double sharedIncome = 0;
      double sharedExpense = 0;

      Map<Category, double> expenseByCategory = {};
      Map<Category, double> incomeByCategory = {};

      for (final transaction in transactions) {
        // Get wallet to determine if shared
        final wallet = await _getWalletById(transaction.walletId);
        final isShared = wallet?.ownerId == _userProvider?.partnershipId;

        if (transaction.type == TransactionType.income) {
          if (isShared) {
            sharedIncome += transaction.amount;
          } else {
            personalIncome += transaction.amount;
          }

          // Group by category
          if (transaction.categoryId != null) {
            final category = categories.firstWhere(
              (c) => c.id == transaction.categoryId,
              orElse: () => Category(
                id: 'unknown_income',
                name: 'Chưa phân loại',
                ownerId: '',
                type: 'income',
              ),
            );
            incomeByCategory[category] =
                (incomeByCategory[category] ?? 0) + transaction.amount;
          }
        } else if (transaction.type == TransactionType.expense) {
          if (isShared) {
            sharedExpense += transaction.amount;
          } else {
            personalExpense += transaction.amount;
          }

          // Group by category
          if (transaction.categoryId != null) {
            final category = categories.firstWhere(
              (c) => c.id == transaction.categoryId,
              orElse: () => Category(
                id: 'unknown_expense',
                name: 'Chưa phân loại',
                ownerId: '',
                type: 'expense',
              ),
            );
            expenseByCategory[category] =
                (expenseByCategory[category] ?? 0) + transaction.amount;
          }
        }
      }

      return ReportData(
        totalIncome: personalIncome + sharedIncome,
        totalExpense: personalExpense + sharedExpense,
        personalIncome: personalIncome,
        personalExpense: personalExpense,
        sharedIncome: sharedIncome,
        sharedExpense: sharedExpense,
        expenseByCategory: expenseByCategory,
        incomeByCategory: incomeByCategory,
        rawTransactions: transactions,
      );
    } catch (e) {
      print('❌ Error getting report data: $e');
      return ReportData(
        expenseByCategory: {},
        incomeByCategory: {},
        rawTransactions: [],
      );
    }
  }

  // ============ DESCRIPTION SUGGESTIONS ============

  Future<List<String>> getDescriptionSuggestions({int limit = 10}) async {
    if (currentUserId == null) return [];
    return await _localDb.getDescriptionSuggestions(
      currentUserId!,
      limit: limit,
    );
  }

  Future<List<String>> searchDescriptionHistory(String query) async {
    if (currentUserId == null) return [];
    return await _localDb.searchDescriptionHistory(currentUserId!, query);
  }

  // ============ SYNC OPERATIONS ============

  /// Force sync all data
  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      throw Exception('Không có kết nối internet');
    }
    await _performFullSync();
  }

  /// Main sync operation
  Future<void> _performFullSync() async {
    if (_isSyncing || !_isOnline || currentUserId == null) return;

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      print('🔄 Starting full sync...');

      // Step 1: Push local changes to Firebase
      await _pushLocalChanges();

      // Step 2: Pull latest data from Firebase
      await _pullFirebaseChanges();

      _lastSyncTime = DateTime.now();
      await _updatePendingItemsCount();

      print('✅ Sync completed successfully');
    } catch (e) {
      _lastError = e.toString();
      print('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Push local unsynced changes to Firebase
  Future<void> _pushLocalChanges() async {
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

        // Remove after too many retries
        if ((item['retryCount'] ?? 0) >= 5) {
          await _localDb.removeSyncItem(item['id']);
        }
      }
    }
  }

  /// Pull latest changes from Firebase
  Future<void> _pullFirebaseChanges() async {
    print('📥 Pulling Firebase changes...');

    try {
      // Get last sync time
      final lastSync =
          _lastSyncTime ?? DateTime.now().subtract(Duration(days: 30));

      // Pull data newer than last sync (parallel execution)
      await Future.wait([
        _pullTransactionsFromFirebase(lastSync),
        _pullCategoriesFromFirebase(lastSync),
        _pullWalletsFromFirebase(lastSync),
        _pullBudgetsFromFirebase(lastSync),
      ]);
    } catch (e) {
      print('❌ Pull sync failed: $e');
      // Don't rethrow - partial sync is better than no sync
    }
  }

  // ============ HELPER METHODS ============

  Future<void> _updatePendingItemsCount() async {
    try {
      final stats = await _localDb.getDatabaseStats();
      _pendingItems = stats['pendingSync'] ?? 0;
    } catch (e) {
      print('Error updating pending count: $e');
      _pendingItems = 0;
    }
  }

  List<Category> _filterCategoriesByOwnership(List<Category> categories) {
    if (_userProvider?.partnershipId == null) return categories;

    return categories.where((cat) {
      return cat.ownerId == currentUserId ||
          cat.ownerId == _userProvider!.partnershipId;
    }).toList();
  }

  List<Wallet> _filterWalletsByVisibility(List<Wallet> wallets) {
    if (_userProvider?.partnershipId == null) return wallets;

    return wallets.where((wallet) {
      // Own wallets
      if (wallet.ownerId == currentUserId) return true;
      // Shared wallets
      if (wallet.ownerId == _userProvider!.partnershipId) return true;
      // Partner's visible wallets
      if (wallet.ownerId == _userProvider!.partnerUid &&
          wallet.isVisibleToPartner)
        return true;
      return false;
    }).toList();
  }

  List<Budget> _filterBudgetsByOwnership(List<Budget> budgets) {
    if (_userProvider?.partnershipId == null) return budgets;

    return budgets.where((budget) {
      return budget.ownerId == currentUserId ||
          budget.ownerId == _userProvider!.partnershipId;
    }).toList();
  }

  Future<Wallet?> _getWalletById(String walletId) async {
    try {
      return await _localDb.getWalletById(walletId);
    } catch (e) {
      print('Error getting wallet: $e');
      return null;
    }
  }

  void unawaited(Future<void> future) {
    future.catchError((error) {
      print('Unawaited error: $error');
    });
  }

  // ============ PLACEHOLDER IMPLEMENTATIONS ============
  // These will be implemented in the next step

  Future<void> _updateWalletBalanceLocally(TransactionModel transaction) async {
    // TODO: Implement wallet balance update logic
  }

  Future<void> _revertWalletBalance(TransactionModel transaction) async {
    // TODO: Implement wallet balance revert logic
  }

  Future<void> _syncTransactionToFirebase(TransactionModel transaction) async {
    // TODO: Implement Firebase transaction sync
  }

  Future<void> _processSyncItem(Map<String, dynamic> item) async {
    // TODO: Implement sync item processing
  }

  Future<void> _refreshTransactionsFromFirebase(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    // TODO: Implement background refresh
  }

  Future<List<TransactionModel>> _fetchTransactionsFromFirebase(
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  ) async {
    // TODO: Implement Firebase fetch
    return [];
  }

  Future<void> _updateTransactionOnFirebase(
    TransactionModel newTransaction,
    TransactionModel oldTransaction,
  ) async {
    // TODO: Implement Firebase update
  }

  Future<void> _deleteTransactionFromFirebase(
    TransactionModel transaction,
  ) async {
    // TODO: Implement Firebase delete
  }

  Future<void> _syncCategoryToFirebase(Category category) async {
    // TODO: Implement category sync
  }

  Future<void> _refreshCategoriesFromFirebase() async {
    // TODO: Implement background refresh
  }

  Future<List<Category>> _fetchCategoriesFromFirebase(String? type) async {
    // TODO: Implement Firebase fetch
    return [];
  }

  Future<void> _syncWalletToFirebase(Wallet wallet) async {
    // TODO: Implement wallet sync
  }

  Future<void> _refreshWalletsFromFirebase() async {
    // TODO: Implement background refresh
  }

  Future<List<Wallet>> _fetchWalletsFromFirebase() async {
    // TODO: Implement Firebase fetch
    return [];
  }

  Future<void> _syncBudgetToFirebase(Budget budget) async {
    // TODO: Implement budget sync
  }

  Future<void> _refreshBudgetsFromFirebase() async {
    // TODO: Implement background refresh
  }

  Future<List<Budget>> _fetchBudgetsFromFirebase(
    String? month,
    BudgetType? budgetType,
  ) async {
    // TODO: Implement Firebase fetch
    return [];
  }

  Future<void> _pullTransactionsFromFirebase(DateTime lastSync) async {
    // TODO: Implement pull sync
  }

  Future<void> _pullCategoriesFromFirebase(DateTime lastSync) async {
    // TODO: Implement pull sync
  }

  Future<void> _pullWalletsFromFirebase(DateTime lastSync) async {
    // TODO: Implement pull sync
  }

  Future<void> _pullBudgetsFromFirebase(DateTime lastSync) async {
    // TODO: Implement pull sync
  }

  Future<void> _sendCategoryNotification(
    String userId,
    String title,
    String body,
  ) async {
    // TODO: Implement notification sending
  }

  Future<void> _sendBudgetNotification(
    String userId,
    String title,
    String body,
  ) async {
    // TODO: Implement notification sending
  }

  // ============ CLEANUP ============

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }
}
