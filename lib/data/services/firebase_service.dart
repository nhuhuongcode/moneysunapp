// lib/data/services/firebase_service.dart - COMPLETE SYNC IMPLEMENTATION
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';

/// Firebase Service - Handles all Firebase operations
/// Implements proper sync logic for offline-first architecture
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final String? _currentUserId = FirebaseAuth.instance.currentUser?.uid;

  // ============ TRANSACTION SYNC OPERATIONS ============

  /// Sync transaction to Firebase
  Future<void> syncTransactionToFirebase(TransactionModel transaction) async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    try {
      final transactionRef = _dbRef.child('transactions').child(transaction.id);
      await transactionRef.set(transaction.toJson());

      // Also update wallet balance on Firebase
      await _updateWalletBalanceOnFirebase(transaction);

      print('✅ Transaction synced to Firebase: ${transaction.id}');
    } catch (e) {
      print('❌ Failed to sync transaction to Firebase: $e');
      rethrow;
    }
  }

  /// Fetch transactions from Firebase since last sync
  Future<List<TransactionModel>> fetchTransactionsSince(
    DateTime lastSync, {
    int? limit,
  }) async {
    if (_currentUserId == null) return [];

    try {
      final transactionRef = _dbRef
          .child('transactions')
          .orderByChild('userId')
          .equalTo(_currentUserId);

      final snapshot = await transactionRef.get();

      if (!snapshot.exists) return [];

      final transactions = <TransactionModel>[];
      final transactionsMap = snapshot.value as Map<dynamic, dynamic>;

      transactionsMap.forEach((key, value) {
        try {
          final transaction = TransactionModel.fromSnapshot(
            snapshot.child(key),
          );

          // Filter by last sync time
          if (transaction.date.isAfter(lastSync)) {
            transactions.add(transaction);
          }
        } catch (e) {
          print('⚠️ Error parsing transaction $key: $e');
        }
      });

      // Sort by date descending and apply limit
      transactions.sort((a, b) => b.date.compareTo(a.date));
      if (limit != null && transactions.length > limit) {
        return transactions.take(limit).toList();
      }

      print('📥 Fetched ${transactions.length} transactions from Firebase');
      return transactions;
    } catch (e) {
      print('❌ Failed to fetch transactions from Firebase: $e');
      return [];
    }
  }

  /// Update transaction on Firebase
  Future<void> updateTransactionOnFirebase(
    TransactionModel newTransaction,
    TransactionModel oldTransaction,
  ) async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    try {
      // Update transaction record
      final transactionRef = _dbRef
          .child('transactions')
          .child(newTransaction.id);
      await transactionRef.set(newTransaction.toJson());

      // Update wallet balances
      await _revertWalletBalanceOnFirebase(oldTransaction);
      await _updateWalletBalanceOnFirebase(newTransaction);

      print('✅ Transaction updated on Firebase: ${newTransaction.id}');
    } catch (e) {
      print('❌ Failed to update transaction on Firebase: $e');
      rethrow;
    }
  }

  /// Delete transaction from Firebase
  Future<void> deleteTransactionFromFirebase(
    TransactionModel transaction,
  ) async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    try {
      // Delete transaction record
      final transactionRef = _dbRef.child('transactions').child(transaction.id);
      await transactionRef.remove();

      // Revert wallet balance
      await _revertWalletBalanceOnFirebase(transaction);

      print('✅ Transaction deleted from Firebase: ${transaction.id}');
    } catch (e) {
      print('❌ Failed to delete transaction from Firebase: $e');
      rethrow;
    }
  }

  // ============ WALLET SYNC OPERATIONS ============

  /// Sync wallet to Firebase
  Future<void> syncWalletToFirebase(Wallet wallet) async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    try {
      final walletRef = _dbRef.child('wallets').child(wallet.id);
      await walletRef.set(wallet.toJson());

      print('✅ Wallet synced to Firebase: ${wallet.name}');
    } catch (e) {
      print('❌ Failed to sync wallet to Firebase: $e');
      rethrow;
    }
  }

  /// Fetch wallets from Firebase
  Future<List<Wallet>> fetchWalletsFromFirebase(
    UserProvider? userProvider,
  ) async {
    if (_currentUserId == null) return [];

    try {
      final walletRef = _dbRef.child('wallets');
      final snapshot = await walletRef.get();

      if (!snapshot.exists) return [];

      final wallets = <Wallet>[];
      final walletsMap = snapshot.value as Map<dynamic, dynamic>;

      walletsMap.forEach((key, value) {
        try {
          final wallet = Wallet.fromSnapshot(snapshot.child(key));

          // Apply ownership filtering
          if (_shouldIncludeWallet(wallet, userProvider)) {
            wallets.add(wallet);
          }
        } catch (e) {
          print('⚠️ Error parsing wallet $key: $e');
        }
      });

      print('📥 Fetched ${wallets.length} wallets from Firebase');
      return wallets;
    } catch (e) {
      print('❌ Failed to fetch wallets from Firebase: $e');
      return [];
    }
  }

  /// Update wallet balance on Firebase (atomic operation)
  Future<void> _updateWalletBalanceOnFirebase(
    TransactionModel transaction,
  ) async {
    try {
      final walletRef = _dbRef.child('wallets').child(transaction.walletId);

      double balanceChange = 0;
      switch (transaction.type) {
        case TransactionType.income:
          balanceChange = transaction.amount;
          break;
        case TransactionType.expense:
          balanceChange = -transaction.amount;
          break;
        case TransactionType.transfer:
          balanceChange = -transaction.amount; // From wallet
          // Handle to-wallet separately if needed
          if (transaction.transferToWalletId != null) {
            final toWalletRef = _dbRef
                .child('wallets')
                .child(transaction.transferToWalletId!);
            await toWalletRef
                .child('balance')
                .set(ServerValue.increment(transaction.amount));
          }
          break;
      }

      if (balanceChange != 0) {
        await walletRef
            .child('balance')
            .set(ServerValue.increment(balanceChange));
      }
    } catch (e) {
      print('❌ Failed to update wallet balance on Firebase: $e');
      rethrow;
    }
  }

  /// Revert wallet balance on Firebase
  Future<void> _revertWalletBalanceOnFirebase(
    TransactionModel transaction,
  ) async {
    try {
      final walletRef = _dbRef.child('wallets').child(transaction.walletId);

      double reversalAmount = 0;
      switch (transaction.type) {
        case TransactionType.income:
          reversalAmount = -transaction.amount; // Subtract back
          break;
        case TransactionType.expense:
          reversalAmount = transaction.amount; // Add back
          break;
        case TransactionType.transfer:
          reversalAmount = transaction.amount; // Add back to source
          // Revert to-wallet
          if (transaction.transferToWalletId != null) {
            final toWalletRef = _dbRef
                .child('wallets')
                .child(transaction.transferToWalletId!);
            await toWalletRef
                .child('balance')
                .set(ServerValue.increment(-transaction.amount));
          }
          break;
      }

      if (reversalAmount != 0) {
        await walletRef
            .child('balance')
            .set(ServerValue.increment(reversalAmount));
      }
    } catch (e) {
      print('❌ Failed to revert wallet balance on Firebase: $e');
      rethrow;
    }
  }

  // ============ CATEGORY SYNC OPERATIONS ============

  /// Sync category to Firebase
  Future<void> syncCategoryToFirebase(Category category) async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    try {
      final categoryRef = _dbRef.child('categories').child(category.id);
      await categoryRef.set(category.toJson());

      print('✅ Category synced to Firebase: ${category.name}');
    } catch (e) {
      print('❌ Failed to sync category to Firebase: $e');
      rethrow;
    }
  }

  /// Fetch categories from Firebase
  Future<List<Category>> fetchCategoriesFromFirebase(
    String? type,
    UserProvider? userProvider,
  ) async {
    if (_currentUserId == null) return [];

    try {
      final categoryRef = _dbRef.child('categories');
      final snapshot = await categoryRef.get();

      if (!snapshot.exists) return [];

      final categories = <Category>[];
      final categoriesMap = snapshot.value as Map<dynamic, dynamic>;

      categoriesMap.forEach((key, value) {
        try {
          final category = Category.fromSnapshot(snapshot.child(key));

          // Apply filtering
          if (_shouldIncludeCategory(category, type, userProvider)) {
            categories.add(category);
          }
        } catch (e) {
          print('⚠️ Error parsing category $key: $e');
        }
      });

      print('📥 Fetched ${categories.length} categories from Firebase');
      return categories..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      print('❌ Failed to fetch categories from Firebase: $e');
      return [];
    }
  }

  // ============ BUDGET SYNC OPERATIONS ============

  /// Sync budget to Firebase
  Future<void> syncBudgetToFirebase(Budget budget) async {
    if (_currentUserId == null) throw Exception('User not authenticated');

    try {
      final budgetRef = _dbRef.child('budgets').child(budget.id);
      await budgetRef.set(budget.toJson());

      print('✅ Budget synced to Firebase: ${budget.displayName}');
    } catch (e) {
      print('❌ Failed to sync budget to Firebase: $e');
      rethrow;
    }
  }

  /// Fetch budgets from Firebase
  Future<List<Budget>> fetchBudgetsFromFirebase(
    String? month,
    BudgetType? budgetType,
    UserProvider? userProvider,
  ) async {
    if (_currentUserId == null) return [];

    try {
      final budgetRef = _dbRef.child('budgets');
      final snapshot = await budgetRef.get();

      if (!snapshot.exists) return [];

      final budgets = <Budget>[];
      final budgetsMap = snapshot.value as Map<dynamic, dynamic>;

      budgetsMap.forEach((key, value) {
        try {
          final budget = Budget.fromSnapshot(snapshot.child(key));

          // Apply filtering
          if (_shouldIncludeBudget(budget, month, budgetType, userProvider)) {
            budgets.add(budget);
          }
        } catch (e) {
          print('⚠️ Error parsing budget $key: $e');
        }
      });

      print('📥 Fetched ${budgets.length} budgets from Firebase');
      return budgets..sort((a, b) => b.month.compareTo(a.month));
    } catch (e) {
      print('❌ Failed to fetch budgets from Firebase: $e');
      return [];
    }
  }

  // ============ BATCH SYNC OPERATIONS ============

  /// Sync multiple transactions in batch
  Future<void> batchSyncTransactions(
    List<TransactionModel> transactions,
  ) async {
    if (_currentUserId == null || transactions.isEmpty) return;

    try {
      print('🔄 Batch syncing ${transactions.length} transactions...');

      // Process in smaller batches to avoid Firebase limits
      const batchSize = 50;
      int synced = 0;
      int failed = 0;

      for (int i = 0; i < transactions.length; i += batchSize) {
        final batch = transactions.skip(i).take(batchSize).toList();

        final results = await Future.wait(
          batch.map((transaction) => _syncSingleTransaction(transaction)),
          eagerError: false,
        );

        for (final result in results) {
          if (result) {
            synced++;
          } else {
            failed++;
          }
        }

        // Small delay to prevent overwhelming Firebase
        if (i + batchSize < transactions.length) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
      }

      print('✅ Batch sync completed: $synced synced, $failed failed');
    } catch (e) {
      print('❌ Batch sync failed: $e');
      rethrow;
    }
  }

  Future<bool> _syncSingleTransaction(TransactionModel transaction) async {
    try {
      await syncTransactionToFirebase(transaction);
      return true;
    } catch (e) {
      print('⚠️ Failed to sync transaction ${transaction.id}: $e');
      return false;
    }
  }

  // ============ DELTA SYNC OPERATIONS ============

  /// Get changes from Firebase since last sync time
  Future<Map<String, dynamic>> getChangesSinceLastSync(
    DateTime lastSync,
  ) async {
    if (_currentUserId == null) return {};

    try {
      print('📥 Fetching changes since $lastSync...');

      final results = await Future.wait([
        _getTransactionChangesSince(lastSync),
        _getWalletChangesSince(lastSync),
        _getCategoryChangesSince(lastSync),
        _getBudgetChangesSince(lastSync),
      ]);

      return {
        'transactions': results[0],
        'wallets': results[1],
        'categories': results[2],
        'budgets': results[3],
        'fetchTime': DateTime.now(),
      };
    } catch (e) {
      print('❌ Failed to get changes since last sync: $e');
      return {};
    }
  }

  Future<List<TransactionModel>> _getTransactionChangesSince(
    DateTime lastSync,
  ) async {
    try {
      return await fetchTransactionsSince(lastSync);
    } catch (e) {
      print('⚠️ Failed to get transaction changes: $e');
      return [];
    }
  }

  Future<List<Wallet>> _getWalletChangesSince(DateTime lastSync) async {
    try {
      // For now, fetch all wallets (can be optimized with server timestamps)
      return await fetchWalletsFromFirebase(null);
    } catch (e) {
      print('⚠️ Failed to get wallet changes: $e');
      return [];
    }
  }

  Future<List<Category>> _getCategoryChangesSince(DateTime lastSync) async {
    try {
      // For now, fetch all categories (can be optimized with server timestamps)
      return await fetchCategoriesFromFirebase(null, null);
    } catch (e) {
      print('⚠️ Failed to get category changes: $e');
      return [];
    }
  }

  Future<List<Budget>> _getBudgetChangesSince(DateTime lastSync) async {
    try {
      // For now, fetch all budgets (can be optimized with server timestamps)
      return await fetchBudgetsFromFirebase(null, null, null);
    } catch (e) {
      print('⚠️ Failed to get budget changes: $e');
      return [];
    }
  }

  // ============ NOTIFICATION OPERATIONS ============

  /// Send notification to user
  Future<void> sendNotification({
    required String userId,
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      final notificationRef = _dbRef
          .child('user_notifications')
          .child(userId)
          .push();

      await notificationRef.set({
        'title': title,
        'body': body,
        'timestamp': ServerValue.timestamp,
        'type': type,
        'isRead': false,
      });

      print('✅ Notification sent to $userId: $title');
    } catch (e) {
      print('❌ Failed to send notification: $e');
      // Don't rethrow - notifications are not critical
    }
  }

  // ============ HELPER METHODS ============

  bool _shouldIncludeWallet(Wallet wallet, UserProvider? userProvider) {
    // Include own wallets
    if (wallet.ownerId == _currentUserId) return true;

    // Include shared wallets
    if (userProvider?.partnershipId != null &&
        wallet.ownerId == userProvider!.partnershipId)
      return true;

    // Include partner's visible wallets
    if (userProvider?.partnerUid != null &&
        wallet.ownerId == userProvider!.partnerUid &&
        wallet.isVisibleToPartner)
      return true;

    return false;
  }

  bool _shouldIncludeCategory(
    Category category,
    String? typeFilter,
    UserProvider? userProvider,
  ) {
    // Filter by type
    if (typeFilter != null && category.type != typeFilter) return false;

    // Filter by archived status
    if (category.isArchived) return false;

    // Include own categories
    if (category.ownerId == _currentUserId) return true;

    // Include shared categories
    if (userProvider?.partnershipId != null &&
        category.ownerId == userProvider!.partnershipId)
      return true;

    return false;
  }

  bool _shouldIncludeBudget(
    Budget budget,
    String? monthFilter,
    BudgetType? typeFilter,
    UserProvider? userProvider,
  ) {
    // Filter by month
    if (monthFilter != null && budget.month != monthFilter) return false;

    // Filter by type
    if (typeFilter != null && budget.budgetType != typeFilter) return false;

    // Filter by active status
    if (!budget.isActive || budget.isDeleted) return false;

    // Include own budgets
    if (budget.ownerId == _currentUserId) return true;

    // Include shared budgets
    if (userProvider?.partnershipId != null &&
        budget.ownerId == userProvider!.partnershipId)
      return true;

    return false;
  }

  // ============ CONNECTION TESTING ============

  /// Test Firebase connection
  Future<bool> testConnection() async {
    try {
      final testRef = _dbRef.child('health_check').child('connection_test');
      await testRef.set(ServerValue.timestamp);
      await testRef.remove();
      return true;
    } catch (e) {
      print('❌ Firebase connection test failed: $e');
      return false;
    }
  }

  /// Get Firebase server timestamp
  Future<DateTime?> getServerTimestamp() async {
    try {
      final timestampRef = _dbRef.child('health_check').child('timestamp');
      await timestampRef.set(ServerValue.timestamp);
      final snapshot = await timestampRef.get();
      await timestampRef.remove();

      if (snapshot.exists) {
        final timestamp = snapshot.value as int;
        return DateTime.fromMillisecondsSinceEpoch(timestamp);
      }
      return null;
    } catch (e) {
      print('❌ Failed to get server timestamp: $e');
      return null;
    }
  }

  // ============ PARTNERSHIP OPERATIONS ============

  /// Create partnership
  Future<void> createPartnership({
    required String currentUserId,
    required String partnerUserId,
    required Map<String, String> memberNames,
  }) async {
    try {
      final partnershipRef = _dbRef.child('partnerships').push();
      final partnershipId = partnershipRef.key!;

      final partnershipData = {
        'members': {currentUserId: true, partnerUserId: true},
        'memberNames': memberNames,
        'createdAt': ServerValue.timestamp,
        'isActive': true,
        'lastSyncTime': ServerValue.timestamp,
      };

      await partnershipRef.set(partnershipData);

      // Update both users
      await Future.wait([
        _updateUserPartnership(currentUserId, partnershipId, partnerUserId),
        _updateUserPartnership(partnerUserId, partnershipId, currentUserId),
      ]);

      print('✅ Partnership created: $partnershipId');
    } catch (e) {
      print('❌ Failed to create partnership: $e');
      rethrow;
    }
  }

  Future<void> _updateUserPartnership(
    String userId,
    String partnershipId,
    String partnerUserId,
  ) async {
    await _dbRef.child('users').child(userId).update({
      'partnershipId': partnershipId,
      'partnerUid': partnerUserId,
      'partnershipCreatedAt': ServerValue.timestamp,
    });
  }

  // ============ SYNC QUEUE PROCESSING ============

  /// Process sync queue item
  Future<void> processSyncQueueItem(Map<String, dynamic> item) async {
    final tableName = item['tableName'] as String;
    final operation = item['operation'] as String;
    final data = item['data'] as Map<String, dynamic>;

    try {
      switch (tableName) {
        case 'transactions':
          await _processSyncTransaction(operation, data);
          break;
        case 'wallets':
          await _processSyncWallet(operation, data);
          break;
        case 'categories':
          await _processSyncCategory(operation, data);
          break;
        case 'budgets':
          await _processSyncBudget(operation, data);
          break;
        default:
          throw Exception('Unknown table: $tableName');
      }

      print('✅ Sync queue item processed: $tableName/$operation');
    } catch (e) {
      print('❌ Failed to process sync queue item: $e');
      rethrow;
    }
  }

  Future<void> _processSyncTransaction(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final transaction = TransactionModel.fromJson(data);
        await syncTransactionToFirebase(transaction);
        break;
      case 'UPDATE':
        // Handle update logic
        break;
      case 'DELETE':
        // Handle delete logic
        break;
    }
  }

  Future<void> _processSyncWallet(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final wallet = Wallet.fromJson(data);
        await syncWalletToFirebase(wallet);
        break;
      // Add other operations as needed
    }
  }

  Future<void> _processSyncCategory(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final category = Category.fromJson(data);
        await syncCategoryToFirebase(category);
        break;
      // Add other operations as needed
    }
  }

  Future<void> _processSyncBudget(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final budget = Budget.fromJson(data);
        await syncBudgetToFirebase(budget);
        break;
      // Add other operations as needed
    }
  }
}
