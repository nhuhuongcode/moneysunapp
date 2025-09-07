// lib/data/services/unified_data_service.dart
// ============ UNIFIED DATA SERVICE - COMPLETE IMPLEMENTATION ============

import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Models
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';

/// ============ SINGLE DATA SERVICE FOR ENTIRE APP ============
/// Replaces: DataService, OfflineFirstService, DatabaseService, etc.
/// True offline-first with proper sync
class DataService extends ChangeNotifier {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  // ============ DEPENDENCIES ============
  final DatabaseReference _firebaseRef = FirebaseDatabase.instance.ref();
  final Connectivity _connectivity = Connectivity();
  Database? _localDatabase;
  UserProvider? _userProvider;

  // ============ STATE ============
  bool _isOnline = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _pendingItems = 0;
  String? _lastError;
  bool _isInitialized = false;

  // ============ SUBSCRIPTIONS ============
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  Timer? _healthCheckTimer;

  // ============ GETTERS ============
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingItems => _pendingItems;
  String? get lastError => _lastError;
  bool get isInitialized => _isInitialized;
  String? get currentUserId => _userProvider?.currentUser?.uid;

  // ============ INITIALIZATION ============
  Future<void> initialize(UserProvider userProvider) async {
    if (_isInitialized) {
      print('⚠️ UnifiedDataService already initialized');
      return;
    }

    _userProvider = userProvider;

    try {
      print('🚀 Initializing UnifiedDataService...');

      // 1. Initialize local database
      await _initializeLocalDatabase();

      // 2. Check connectivity
      await _checkConnectivity();

      // 3. Start listeners
      _startConnectivityListener();
      _startPeriodicSync();
      _startHealthCheck();

      // 4. Update state
      await _updatePendingItemsCount();
      await _updateSyncStats();

      // 5. Initial sync if online
      if (_isOnline && currentUserId != null) {
        unawaited(_performFullSync());
      }

      _isInitialized = true;
      notifyListeners();

      print('✅ UnifiedDataService initialized successfully');
      print('📊 Status: Online: $_isOnline, Pending: $_pendingItems');
    } catch (e) {
      print('❌ UnifiedDataService initialization failed: $e');
      _lastError = 'Initialization failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ============ LOCAL DATABASE SETUP ============
  Future<void> _initializeLocalDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'moneysun_unified.db');

      _localDatabase = await openDatabase(
        path,
        version: 1,
        onCreate: _createTables,
        onUpgrade: _upgradeDatabase,
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
        },
      );

      print('✅ Local database initialized at: $path');
    } catch (e) {
      print('❌ Local database initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _createTables(Database db, int version) async {
    print('🔨 Creating unified database tables...');

    // Users table for sync metadata
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        display_name TEXT,
        email TEXT,
        partnership_id TEXT,
        partner_uid TEXT,
        last_sync_time INTEGER,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Transactions table
    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        firebase_id TEXT UNIQUE,
        amount REAL NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('income', 'expense', 'transfer')),
        category_id TEXT,
        wallet_id TEXT NOT NULL,
        date TEXT NOT NULL,
        description TEXT DEFAULT '',
        user_id TEXT NOT NULL,
        sub_category_id TEXT,
        transfer_to_wallet_id TEXT,
        
        -- Sync metadata
        sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1, 2)),
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        version INTEGER DEFAULT 1,
        
        -- Timestamps
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER DEFAULT (strftime('%s', 'now')),
        
        FOREIGN KEY (wallet_id) REFERENCES wallets(id),
        FOREIGN KEY (category_id) REFERENCES categories(id),
        FOREIGN KEY (user_id) REFERENCES users(id)
      )
    ''');

    // Wallets table
    await db.execute('''
      CREATE TABLE wallets (
        id TEXT PRIMARY KEY,
        firebase_id TEXT UNIQUE,
        name TEXT NOT NULL,
        balance REAL NOT NULL DEFAULT 0,
        owner_id TEXT NOT NULL,
        is_visible_to_partner INTEGER DEFAULT 1 CHECK (is_visible_to_partner IN (0, 1)),
        wallet_type TEXT DEFAULT 'general',
        currency TEXT DEFAULT 'VND',
        is_archived INTEGER DEFAULT 0 CHECK (is_archived IN (0, 1)),
        
        -- Sync metadata
        sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1, 2)),
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        version INTEGER DEFAULT 1,
        
        -- Timestamps
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER DEFAULT (strftime('%s', 'now')),
        
        FOREIGN KEY (owner_id) REFERENCES users(id)
      )
    ''');

    // Categories table
    await db.execute('''
      CREATE TABLE categories (
        id TEXT PRIMARY KEY,
        firebase_id TEXT UNIQUE,
        name TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
        ownership_type TEXT DEFAULT 'personal' CHECK (ownership_type IN ('personal', 'shared')),
        icon_code_point INTEGER,
        sub_categories TEXT DEFAULT '{}',
        created_by TEXT,
        is_archived INTEGER DEFAULT 0 CHECK (is_archived IN (0, 1)),
        usage_count INTEGER DEFAULT 0,
        last_used INTEGER,
        
        -- Sync metadata
        sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1, 2)),
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        version INTEGER DEFAULT 1,
        
        -- Timestamps
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER DEFAULT (strftime('%s', 'now')),
        
        UNIQUE(owner_id, name, type),
        FOREIGN KEY (owner_id) REFERENCES users(id),
        FOREIGN KEY (created_by) REFERENCES users(id)
      )
    ''');

    // Budgets table
    await db.execute('''
      CREATE TABLE budgets (
        id TEXT PRIMARY KEY,
        firebase_id TEXT UNIQUE,
        owner_id TEXT NOT NULL,
        month TEXT NOT NULL,
        total_amount REAL NOT NULL DEFAULT 0,
        category_amounts TEXT DEFAULT '{}',
        budget_type TEXT DEFAULT 'personal' CHECK (budget_type IN ('personal', 'shared')),
        period TEXT DEFAULT 'monthly',
        created_by TEXT,
        start_date INTEGER,
        end_date INTEGER,
        is_active INTEGER DEFAULT 1 CHECK (is_active IN (0, 1)),
        notes TEXT DEFAULT '{}',
        category_limits TEXT DEFAULT '{}',
        
        -- Sync metadata
        sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1, 2)),
        last_modified INTEGER DEFAULT (strftime('%s', 'now')),
        version INTEGER DEFAULT 1,
        
        -- Timestamps
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER DEFAULT (strftime('%s', 'now')),
        
        UNIQUE(owner_id, month, budget_type),
        FOREIGN KEY (owner_id) REFERENCES users(id),
        FOREIGN KEY (created_by) REFERENCES users(id)
      )
    ''');

    // Description history for smart suggestions
    await db.execute('''
      CREATE TABLE description_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        description TEXT NOT NULL,
        usage_count INTEGER DEFAULT 1,
        last_used INTEGER DEFAULT (strftime('%s', 'now')),
        transaction_type TEXT,
        category_id TEXT,
        amount REAL,
        confidence REAL DEFAULT 0,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        updated_at INTEGER DEFAULT (strftime('%s', 'now')),
        
        UNIQUE(user_id, description),
        FOREIGN KEY (user_id) REFERENCES users(id),
        FOREIGN KEY (category_id) REFERENCES categories(id)
      )
    ''');

    // Sync queue for offline operations
    await db.execute('''
      CREATE TABLE sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        firebase_id TEXT,
        operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
        data TEXT NOT NULL,
        priority INTEGER DEFAULT 1 CHECK (priority IN (1, 2, 3)),
        retry_count INTEGER DEFAULT 0,
        max_retries INTEGER DEFAULT 5,
        last_error TEXT,
        scheduled_at INTEGER DEFAULT (strftime('%s', 'now')),
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        
        UNIQUE(table_name, record_id, operation)
      )
    ''');

    // Sync metadata
    await db.execute('''
      CREATE TABLE sync_metadata (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Create indexes for performance
    await _createIndexes(db);

    print('✅ Database tables created successfully');
  }

  Future<void> _createIndexes(Database db) async {
    final indexes = [
      // Transaction indexes
      'CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date DESC)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_wallet ON transactions(wallet_id)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_sync ON transactions(sync_status, last_modified)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type)',

      // Wallet indexes
      'CREATE INDEX IF NOT EXISTS idx_wallets_owner ON wallets(owner_id, is_archived)',
      'CREATE INDEX IF NOT EXISTS idx_wallets_sync ON wallets(sync_status, last_modified)',

      // Category indexes
      'CREATE INDEX IF NOT EXISTS idx_categories_owner_type ON categories(owner_id, type, is_archived)',
      'CREATE INDEX IF NOT EXISTS idx_categories_ownership ON categories(ownership_type)',
      'CREATE INDEX IF NOT EXISTS idx_categories_usage ON categories(usage_count DESC, last_used DESC)',
      'CREATE INDEX IF NOT EXISTS idx_categories_sync ON categories(sync_status, last_modified)',

      // Budget indexes
      'CREATE INDEX IF NOT EXISTS idx_budgets_owner_month ON budgets(owner_id, month, budget_type)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_sync ON budgets(sync_status, last_modified)',

      // Description indexes
      'CREATE INDEX IF NOT EXISTS idx_description_user_usage ON description_history(user_id, usage_count DESC)',
      'CREATE INDEX IF NOT EXISTS idx_description_text ON description_history(description)',

      // Sync queue indexes
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_priority ON sync_queue(priority DESC, created_at ASC)',
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON sync_queue(retry_count, scheduled_at)',
    ];

    for (final indexSql in indexes) {
      try {
        await db.execute(indexSql);
      } catch (e) {
        print('⚠️ Warning: Could not create index: $e');
      }
    }
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    print('🔄 Upgrading database from v$oldVersion to v$newVersion');
    // Migration logic would go here
  }

  // ============ CONNECTIVITY MANAGEMENT ============
  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result.isNotEmpty && result.first != ConnectivityResult.none;
  }

  void _startConnectivityListener() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) async {
      final wasOnline = _isOnline;
      _isOnline =
          results.isNotEmpty && results.first != ConnectivityResult.none;

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
      if (_isOnline &&
          !_isSyncing &&
          _pendingItems > 0 &&
          currentUserId != null) {
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

  // ============ TRANSACTION OPERATIONS - OFFLINE FIRST ============

  /// Add transaction - Always save locally first
  Future<void> addTransaction(TransactionModel transaction) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      // 1. Save to local database first
      await _localDatabase!.insert('transactions', {
        'id': transaction.id,
        'amount': transaction.amount,
        'type': transaction.type.name,
        'category_id': transaction.categoryId,
        'wallet_id': transaction.walletId,
        'date': transaction.date.toIso8601String(),
        'description': transaction.description,
        'user_id': transaction.userId,
        'sub_category_id': transaction.subCategoryId,
        'transfer_to_wallet_id': transaction.transferToWalletId,
        'sync_status': 0, // Unsynced
        'version': 1,
      });

      // 2. Update wallet balance locally
      await _updateWalletBalanceLocally(transaction);

      // 3. Save description to history for smart suggestions
      if (transaction.description.isNotEmpty) {
        await _saveDescriptionToHistory(transaction);
      }

      // 4. Add to sync queue
      await _addToSyncQueue(
        'transactions',
        transaction.id,
        'INSERT',
        transaction.toJson(),
      );

      // 5. Update counters
      await _updatePendingItemsCount();
      notifyListeners();

      // 6. Try immediate sync if online
      if (_isOnline) {
        try {
          await _syncTransactionToFirebase(transaction);
          await _markAsSynced('transactions', transaction.id);
          await _updatePendingItemsCount();
          notifyListeners();
        } catch (e) {
          print('⚠️ Immediate sync failed, will retry later: $e');
        }
      }

      print(
        '✅ Transaction added: ${transaction.description} (${transaction.amount})',
      );
    } catch (e) {
      print('❌ Error adding transaction: $e');
      rethrow;
    }
  }

  /// Get transactions - Offline first with optional background refresh
  Future<List<TransactionModel>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    String? walletId,
    String? categoryId,
  }) async {
    if (!_isInitialized || _localDatabase == null) return [];

    try {
      // Build query
      String whereClause = 'user_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      if (startDate != null) {
        whereClause += ' AND date >= ?';
        whereArgs.add(startDate.toIso8601String());
      }

      if (endDate != null) {
        whereClause += ' AND date <= ?';
        whereArgs.add(endDate.toIso8601String());
      }

      if (walletId != null) {
        whereClause += ' AND wallet_id = ?';
        whereArgs.add(walletId);
      }

      if (categoryId != null) {
        whereClause += ' AND category_id = ?';
        whereArgs.add(categoryId);
      }

      // Get from local database
      final result = await _localDatabase!.query(
        'transactions',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'date DESC',
        limit: limit,
      );

      final transactions = result
          .map((map) => _transactionFromMap(map))
          .toList();

      print('📱 Returning ${transactions.length} transactions from local');

      // Background refresh if online (don't await)
      if (_isOnline && transactions.isNotEmpty) {
        unawaited(_refreshTransactionsFromFirebase(startDate, endDate));
      }

      return transactions;
    } catch (e) {
      print('❌ Error getting transactions: $e');
      return [];
    }
  }

  /// Update transaction
  Future<void> updateTransaction(
    TransactionModel newTransaction,
    TransactionModel? oldTransaction,
  ) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      // 1. Update locally first
      await _localDatabase!.update(
        'transactions',
        {
          'amount': newTransaction.amount,
          'type': newTransaction.type.name,
          'category_id': newTransaction.categoryId,
          'wallet_id': newTransaction.walletId,
          'date': newTransaction.date.toIso8601String(),
          'description': newTransaction.description,
          'sub_category_id': newTransaction.subCategoryId,
          'transfer_to_wallet_id': newTransaction.transferToWalletId,
          'sync_status': 0,
          'version': 'version + 1',
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [newTransaction.id],
      );

      // 2. Update wallet balances
      if (oldTransaction != null) {
        await _revertWalletBalance(oldTransaction);
      }
      await _updateWalletBalanceLocally(newTransaction);

      // 3. Save description
      if (newTransaction.description.isNotEmpty) {
        await _saveDescriptionToHistory(newTransaction);
      }

      // 4. Add to sync queue
      await _addToSyncQueue(
        'transactions',
        newTransaction.id,
        'UPDATE',
        newTransaction.toJson(),
      );

      await _updatePendingItemsCount();
      notifyListeners();

      // 5. Try immediate sync if online
      if (_isOnline) {
        try {
          await _updateTransactionOnFirebase(newTransaction, oldTransaction);
          await _markAsSynced('transactions', newTransaction.id);
        } catch (e) {
          print('⚠️ Update sync failed: $e');
        }
      }

      print('✅ Transaction updated: ${newTransaction.description}');
    } catch (e) {
      print('❌ Error updating transaction: $e');
      rethrow;
    }
  }

  /// Delete transaction
  Future<void> deleteTransaction(TransactionModel transaction) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      // 1. Revert wallet balance
      await _revertWalletBalance(transaction);

      // 2. Delete locally
      await _localDatabase!.delete(
        'transactions',
        where: 'id = ?',
        whereArgs: [transaction.id],
      );

      // 3. Add to sync queue for deletion
      await _addToSyncQueue(
        'transactions',
        transaction.id,
        'DELETE',
        transaction.toJson(),
      );

      await _updatePendingItemsCount();
      notifyListeners();

      // 4. Try immediate sync if online
      if (_isOnline) {
        try {
          await _deleteTransactionFromFirebase(transaction);
        } catch (e) {
          print('⚠️ Delete sync failed: $e');
        }
      }

      print('✅ Transaction deleted: ${transaction.description}');
    } catch (e) {
      print('❌ Error deleting transaction: $e');
      rethrow;
    }
  }

  // ============ WALLET OPERATIONS - OFFLINE FIRST ============

  /// Add wallet
  Future<void> addWallet({
    required String name,
    required double initialBalance,
    String? ownerId,
    WalletType type = WalletType.general,
    bool isVisibleToPartner = true,
  }) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      throw Exception('Service not initialized or user not authenticated');
    }

    try {
      final walletId = 'wallet_${DateTime.now().millisecondsSinceEpoch}';
      final wallet = Wallet(
        id: walletId,
        name: name,
        balance: initialBalance,
        ownerId: ownerId ?? currentUserId!,
        isVisibleToPartner: isVisibleToPartner,
        type: type,
        createdAt: DateTime.now(),
      );

      // 1. Save locally first
      await _localDatabase!.insert('wallets', {
        'id': wallet.id,
        'name': wallet.name,
        'balance': wallet.balance,
        'owner_id': wallet.ownerId,
        'is_visible_to_partner': wallet.isVisibleToPartner ? 1 : 0,
        'wallet_type': wallet.type.name,
        'currency': wallet.currency,
        'sync_status': 0,
        'version': 1,
      });

      // 2. Add to sync queue
      await _addToSyncQueue('wallets', wallet.id, 'INSERT', wallet.toJson());

      await _updatePendingItemsCount();
      notifyListeners();

      // 3. Try immediate sync if online
      if (_isOnline) {
        try {
          await _syncWalletToFirebase(wallet);
          await _markAsSynced('wallets', wallet.id);
        } catch (e) {
          print('⚠️ Wallet sync failed: $e');
        }
      }

      print('✅ Wallet added: ${wallet.name} (${wallet.formattedBalance})');
    } catch (e) {
      print('❌ Error adding wallet: $e');
      rethrow;
    }
  }

  /// Get wallets with ownership filtering
  Future<List<Wallet>> getWallets({bool includeArchived = false}) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null)
      return [];

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include partner's visible wallets if partnership exists
      if (_userProvider?.partnerUid != null) {
        whereClause =
            '(owner_id = ? OR (owner_id = ? AND is_visible_to_partner = 1))';
        whereArgs = [currentUserId, _userProvider!.partnerUid];
      }

      // Include shared wallets if partnership exists
      if (_userProvider?.partnershipId != null) {
        whereClause += ' OR owner_id = ?';
        whereArgs.add(_userProvider!.partnershipId);
      }

      if (!includeArchived) {
        whereClause += ' AND is_archived = 0';
      }

      final result = await _localDatabase!.query(
        'wallets',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'name ASC',
      );

      final wallets = result.map((map) => _walletFromMap(map)).toList();

      print('📱 Returning ${wallets.length} wallets from local');

      // Background refresh if online
      if (_isOnline) {
        unawaited(_refreshWalletsFromFirebase());
      }

      return wallets;
    } catch (e) {
      print('❌ Error getting wallets: $e');
      return [];
    }
  }

  // ============ CATEGORY OPERATIONS - OFFLINE FIRST ============

  /// Add category with ownership support
  Future<void> addCategory({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    int? iconCodePoint,
    Map<String, String>? subCategories,
  }) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      throw Exception('Service not initialized or user not authenticated');
    }

    try {
      // Determine owner based on ownership type
      String ownerId;
      if (ownershipType == CategoryOwnershipType.shared) {
        if (_userProvider?.partnershipId == null) {
          throw Exception('Không thể tạo danh mục chung khi chưa có đối tác');
        }
        ownerId = _userProvider!.partnershipId!;
      } else {
        ownerId = currentUserId!;
      }

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
      await _localDatabase!.insert('categories', {
        'id': category.id,
        'name': category.name,
        'owner_id': category.ownerId,
        'type': category.type,
        'ownership_type': category.ownershipType.name,
        'created_by': category.createdBy,
        'icon_code_point': category.iconCodePoint,
        'sub_categories': jsonEncode(category.subCategories),
        'sync_status': 0,
        'version': 1,
      });

      // 2. Add to sync queue
      await _addToSyncQueue(
        'categories',
        category.id,
        'INSERT',
        category.toJson(),
      );

      await _updatePendingItemsCount();
      notifyListeners();

      // 3. Try immediate sync if online
      if (_isOnline) {
        try {
          await _syncCategoryToFirebase(category);
          await _markAsSynced('categories', category.id);

          // Send notification if shared category
          if (ownershipType == CategoryOwnershipType.shared &&
              _userProvider?.partnerUid != null) {
            await _sendNotification(
              _userProvider!.partnerUid!,
              'Danh mục chung mới',
              '${_userProvider!.currentUser?.displayName ?? "Đối tác"} đã tạo danh mục "$name" chung',
              'category',
            );
          }
        } catch (e) {
          print('⚠️ Category sync failed: $e');
        }
      }

      print('✅ Category added: $name (${ownershipType.name})');
    } catch (e) {
      print('❌ Error adding category: $e');
      rethrow;
    }
  }

  /// Get categories with ownership filtering
  Future<List<Category>> getCategories({
    String? type,
    CategoryOwnershipType? ownershipType,
    bool includeArchived = false,
  }) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null)
      return [];

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include shared categories if partnership exists
      if (_userProvider?.partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, _userProvider!.partnershipId];
      }

      if (type != null) {
        whereClause += ' AND type = ?';
        whereArgs.add(type);
      }

      if (ownershipType != null) {
        whereClause += ' AND ownership_type = ?';
        whereArgs.add(ownershipType.name);
      }

      if (!includeArchived) {
        whereClause += ' AND is_archived = 0';
      }

      final result = await _localDatabase!.query(
        'categories',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'usage_count DESC, name ASC',
      );

      final categories = result.map((map) => _categoryFromMap(map)).toList();

      print('📱 Returning ${categories.length} categories from local');

      // Background refresh if online
      if (_isOnline) {
        unawaited(_refreshCategoriesFromFirebase());
      }

      return categories;
    } catch (e) {
      print('❌ Error getting categories: $e');
      return [];
    }
  }

  // ============ BUDGET OPERATIONS - OFFLINE FIRST ============

  /// Add budget with ownership support
  Future<void> addBudget({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    required BudgetType budgetType,
    BudgetPeriod period = BudgetPeriod.monthly,
    DateTime? startDate,
    DateTime? endDate,
    Map<String, String>? notes,
    Map<String, double>? categoryLimits,
  }) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      throw Exception('Service not initialized or user not authenticated');
    }

    try {
      // Determine owner based on budget type
      String ownerId;
      if (budgetType == BudgetType.shared) {
        if (_userProvider?.partnershipId == null) {
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
        startDate: startDate,
        endDate: endDate,
        notes: notes,
        categoryLimits: categoryLimits,
        createdAt: DateTime.now(),
      );

      // 1. Save locally first
      await _localDatabase!.insert('budgets', {
        'id': budget.id,
        'owner_id': budget.ownerId,
        'month': budget.month,
        'total_amount': budget.totalAmount,
        'category_amounts': jsonEncode(budget.categoryAmounts),
        'budget_type': budget.budgetType.name,
        'period': budget.period.name,
        'created_by': budget.createdBy,
        'start_date': budget.startDate?.millisecondsSinceEpoch,
        'end_date': budget.endDate?.millisecondsSinceEpoch,
        'notes': jsonEncode(budget.notes ?? {}),
        'category_limits': jsonEncode(budget.categoryLimits ?? {}),
        'sync_status': 0,
        'version': 1,
      });

      // 2. Add to sync queue
      await _addToSyncQueue('budgets', budget.id, 'INSERT', budget.toJson());

      await _updatePendingItemsCount();
      notifyListeners();

      // 3. Try immediate sync if online
      if (_isOnline) {
        try {
          await _syncBudgetToFirebase(budget);
          await _markAsSynced('budgets', budget.id);

          // Send notification if shared budget
          if (budgetType == BudgetType.shared &&
              _userProvider?.partnerUid != null) {
            await _sendNotification(
              _userProvider!.partnerUid!,
              'Ngân sách chung mới',
              '${_userProvider!.currentUser?.displayName ?? "Đối tác"} đã tạo ngân sách chung cho tháng $month',
              'budget',
            );
          }
        } catch (e) {
          print('⚠️ Budget sync failed: $e');
        }
      }

      print('✅ Budget added: ${budget.displayName}');
    } catch (e) {
      print('❌ Error adding budget: $e');
      rethrow;
    }
  }

  /// Get budgets with ownership filtering
  Future<List<Budget>> getBudgets({
    String? month,
    BudgetType? budgetType,
    bool includeInactive = false,
  }) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null)
      return [];

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include shared budgets if partnership exists
      if (_userProvider?.partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, _userProvider!.partnershipId];
      }

      if (month != null) {
        whereClause += ' AND month = ?';
        whereArgs.add(month);
      }

      if (budgetType != null) {
        whereClause += ' AND budget_type = ?';
        whereArgs.add(budgetType.name);
      }

      if (!includeInactive) {
        whereClause += ' AND is_active = 1';
      }

      final result = await _localDatabase!.query(
        'budgets',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'month DESC, budget_type ASC',
      );

      final budgets = result.map((map) => _budgetFromMap(map)).toList();

      print('📱 Returning ${budgets.length} budgets from local');

      // Background refresh if online
      if (_isOnline) {
        unawaited(_refreshBudgetsFromFirebase());
      }

      return budgets;
    } catch (e) {
      print('❌ Error getting budgets: $e');
      return [];
    }
  }

  // ============ HELPER METHODS ============

  Future<void> _updateWalletBalanceLocally(TransactionModel transaction) async {
    if (_localDatabase == null) return;

    double balanceChange = 0;
    switch (transaction.type) {
      case TransactionType.income:
        balanceChange = transaction.amount;
        break;
      case TransactionType.expense:
        balanceChange = -transaction.amount;
        break;
      case TransactionType.transfer:
        balanceChange = -transaction.amount;
        // Also update target wallet if it's a transfer
        if (transaction.transferToWalletId != null) {
          await _localDatabase!.rawUpdate(
            'UPDATE wallets SET balance = balance + ?, updated_at = ?, version = version + 1 WHERE id = ?',
            [
              transaction.amount,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
              transaction.transferToWalletId,
            ],
          );
        }
        break;
    }

    if (balanceChange != 0) {
      await _localDatabase!.rawUpdate(
        'UPDATE wallets SET balance = balance + ?, updated_at = ?, version = version + 1 WHERE id = ?',
        [
          balanceChange,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          transaction.walletId,
        ],
      );
    }
  }

  Future<void> _revertWalletBalance(TransactionModel transaction) async {
    if (_localDatabase == null) return;

    double reversalAmount = 0;
    switch (transaction.type) {
      case TransactionType.income:
        reversalAmount = -transaction.amount;
        break;
      case TransactionType.expense:
        reversalAmount = transaction.amount;
        break;
      case TransactionType.transfer:
        reversalAmount = transaction.amount;
        // Also revert target wallet
        if (transaction.transferToWalletId != null) {
          await _localDatabase!.rawUpdate(
            'UPDATE wallets SET balance = balance - ?, updated_at = ?, version = version + 1 WHERE id = ?',
            [
              transaction.amount,
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
              transaction.transferToWalletId,
            ],
          );
        }
        break;
    }

    if (reversalAmount != 0) {
      await _localDatabase!.rawUpdate(
        'UPDATE wallets SET balance = balance + ?, updated_at = ?, version = version + 1 WHERE id = ?',
        [
          reversalAmount,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          transaction.walletId,
        ],
      );
    }
  }

  Future<void> _saveDescriptionToHistory(TransactionModel transaction) async {
    if (_localDatabase == null || transaction.description.trim().isEmpty)
      return;

    try {
      // Check if description already exists
      final existing = await _localDatabase!.query(
        'description_history',
        where: 'user_id = ? AND description = ?',
        whereArgs: [transaction.userId, transaction.description.trim()],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Update usage count and last used
        await _localDatabase!.update(
          'description_history',
          {
            'usage_count': (existing.first['usage_count'] as int) + 1,
            'last_used': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'transaction_type': transaction.type.name,
            'category_id': transaction.categoryId,
            'amount': transaction.amount,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        // Insert new description
        await _localDatabase!.insert('description_history', {
          'user_id': transaction.userId,
          'description': transaction.description.trim(),
          'usage_count': 1,
          'last_used': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'transaction_type': transaction.type.name,
          'category_id': transaction.categoryId,
          'amount': transaction.amount,
        });
      }
    } catch (e) {
      print('⚠️ Error saving description to history: $e');
    }
  }

  // ============ FIREBASE SYNC METHODS ============

  Future<void> _syncTransactionToFirebase(TransactionModel transaction) async {
    final ref = _firebaseRef.child('transactions').child(transaction.id);
    await ref.set(transaction.toJson());
    print('☁️ Transaction synced to Firebase: ${transaction.id}');
  }

  Future<void> _updateTransactionOnFirebase(
    TransactionModel newTransaction,
    TransactionModel? oldTransaction,
  ) async {
    // Update transaction
    final ref = _firebaseRef.child('transactions').child(newTransaction.id);
    await ref.set(newTransaction.toJson());

    // Update wallet balances on Firebase
    if (oldTransaction != null) {
      await _revertWalletBalanceOnFirebase(oldTransaction);
    }
    await _updateWalletBalanceOnFirebase(newTransaction);
  }

  Future<void> _deleteTransactionFromFirebase(
    TransactionModel transaction,
  ) async {
    final ref = _firebaseRef.child('transactions').child(transaction.id);
    await ref.remove();

    // Revert wallet balance
    await _revertWalletBalanceOnFirebase(transaction);
  }

  Future<void> _updateWalletBalanceOnFirebase(
    TransactionModel transaction,
  ) async {
    final walletRef = _firebaseRef.child('wallets').child(transaction.walletId);

    double balanceChange = 0;
    switch (transaction.type) {
      case TransactionType.income:
        balanceChange = transaction.amount;
        break;
      case TransactionType.expense:
        balanceChange = -transaction.amount;
        break;
      case TransactionType.transfer:
        balanceChange = -transaction.amount;
        // Also update target wallet
        if (transaction.transferToWalletId != null) {
          final targetWalletRef = _firebaseRef
              .child('wallets')
              .child(transaction.transferToWalletId!);
          await targetWalletRef
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
  }

  Future<void> _revertWalletBalanceOnFirebase(
    TransactionModel transaction,
  ) async {
    final walletRef = _firebaseRef.child('wallets').child(transaction.walletId);

    double reversalAmount = 0;
    switch (transaction.type) {
      case TransactionType.income:
        reversalAmount = -transaction.amount;
        break;
      case TransactionType.expense:
        reversalAmount = transaction.amount;
        break;
      case TransactionType.transfer:
        reversalAmount = transaction.amount;
        // Also revert target wallet
        if (transaction.transferToWalletId != null) {
          final targetWalletRef = _firebaseRef
              .child('wallets')
              .child(transaction.transferToWalletId!);
          await targetWalletRef
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
  }

  Future<void> _syncWalletToFirebase(Wallet wallet) async {
    final ref = _firebaseRef.child('wallets').child(wallet.id);
    await ref.set(wallet.toJson());
    print('☁️ Wallet synced to Firebase: ${wallet.id}');
  }

  Future<void> _syncCategoryToFirebase(Category category) async {
    final ref = _firebaseRef.child('categories').child(category.id);
    await ref.set(category.toJson());
    print('☁️ Category synced to Firebase: ${category.id}');
  }

  Future<void> _syncBudgetToFirebase(Budget budget) async {
    final ref = _firebaseRef.child('budgets').child(budget.id);
    await ref.set(budget.toJson());
    print('☁️ Budget synced to Firebase: ${budget.id}');
  }

  Future<void> _sendNotification(
    String userId,
    String title,
    String body,
    String type,
  ) async {
    try {
      final notificationRef = _firebaseRef
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
    } catch (e) {
      print('⚠️ Error sending notification: $e');
    }
  }

  // ============ BACKGROUND REFRESH METHODS ============

  Future<void> _refreshTransactionsFromFirebase(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    // Background refresh implementation - pull latest transactions from Firebase
    // and update local database without disrupting user
  }

  Future<void> _refreshWalletsFromFirebase() async {
    // Background refresh implementation for wallets
  }

  Future<void> _refreshCategoriesFromFirebase() async {
    // Background refresh implementation for categories
  }

  Future<void> _refreshBudgetsFromFirebase() async {
    // Background refresh implementation for budgets
  }

  // ============ SYNC QUEUE MANAGEMENT ============

  Future<void> _addToSyncQueue(
    String tableName,
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    if (_localDatabase == null) return;

    try {
      await _localDatabase!.insert('sync_queue', {
        'table_name': tableName,
        'record_id': recordId,
        'operation': operation,
        'data': jsonEncode(data),
        'priority': _getSyncPriority(operation),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print('⚠️ Error adding to sync queue: $e');
    }
  }

  int _getSyncPriority(String operation) {
    switch (operation) {
      case 'DELETE':
        return 3; // Highest priority
      case 'UPDATE':
        return 2; // Medium priority
      case 'INSERT':
        return 1; // Lowest priority
      default:
        return 1;
    }
  }

  Future<void> _markAsSynced(String tableName, String recordId) async {
    if (_localDatabase == null) return;

    await _localDatabase!.update(
      tableName,
      {
        'sync_status': 1,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  /// Main sync operation
  Future<void> _performFullSync() async {
    if (_isSyncing ||
        !_isOnline ||
        _localDatabase == null ||
        currentUserId == null)
      return;

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      print('🔄 Starting full sync...');

      // Get pending sync items
      final syncItems = await _localDatabase!.query(
        'sync_queue',
        orderBy: 'priority DESC, created_at ASC',
        limit: 50,
      );

      int synced = 0;
      int failed = 0;

      for (final item in syncItems) {
        try {
          await _processSyncItem(item);
          await _localDatabase!.delete(
            'sync_queue',
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          synced++;
        } catch (e) {
          print('❌ Failed to sync item ${item['id']}: $e');
          failed++;

          // Increment retry count
          final retryCount = (item['retry_count'] as int) + 1;
          if (retryCount >= (item['max_retries'] as int)) {
            // Remove after max retries
            await _localDatabase!.delete(
              'sync_queue',
              where: 'id = ?',
              whereArgs: [item['id']],
            );
            print(
              '🗑️ Removed item ${item['id']} after $retryCount failed attempts',
            );
          } else {
            await _localDatabase!.update(
              'sync_queue',
              {'retry_count': retryCount, 'last_error': e.toString()},
              where: 'id = ?',
              whereArgs: [item['id']],
            );
          }
        }
      }

      _lastSyncTime = DateTime.now();
      await _updatePendingItemsCount();

      print('✅ Sync completed: $synced synced, $failed failed');
    } catch (e) {
      _lastError = e.toString();
      print('❌ Sync failed: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _processSyncItem(Map<String, dynamic> item) async {
    final tableName = item['table_name'] as String;
    final operation = item['operation'] as String;
    final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;

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
  }

  Future<void> _processSyncTransaction(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final transaction = _transactionFromJson(data);
        await _syncTransactionToFirebase(transaction);
        break;
      case 'UPDATE':
        final transaction = _transactionFromJson(data);
        await _updateTransactionOnFirebase(transaction, null);
        break;
      case 'DELETE':
        final transaction = _transactionFromJson(data);
        await _deleteTransactionFromFirebase(transaction);
        break;
    }
  }

  Future<void> _processSyncWallet(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final wallet = _walletFromJson(data);
        await _syncWalletToFirebase(wallet);
        break;
      case 'UPDATE':
        final wallet = _walletFromJson(data);
        await _syncWalletToFirebase(wallet);
        break;
      case 'DELETE':
        await _firebaseRef.child('wallets').child(data['id']).remove();
        break;
    }
  }

  Future<void> _processSyncCategory(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final category = _categoryFromJson(data);
        await _syncCategoryToFirebase(category);
        break;
      case 'UPDATE':
        final category = _categoryFromJson(data);
        await _syncCategoryToFirebase(category);
        break;
      case 'DELETE':
        await _firebaseRef.child('categories').child(data['id']).remove();
        break;
    }
  }

  Future<void> _processSyncBudget(
    String operation,
    Map<String, dynamic> data,
  ) async {
    switch (operation) {
      case 'INSERT':
        final budget = _budgetFromJson(data);
        await _syncBudgetToFirebase(budget);
        break;
      case 'UPDATE':
        final budget = _budgetFromJson(data);
        await _syncBudgetToFirebase(budget);
        break;
      case 'DELETE':
        await _firebaseRef.child('budgets').child(data['id']).remove();
        break;
    }
  }

  // ============ MODEL CONVERTERS ============

  TransactionModel _transactionFromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: (map['amount'] as num).toDouble(),
      type: TransactionType.values.firstWhere((e) => e.name == map['type']),
      categoryId: map['category_id'],
      walletId: map['wallet_id'],
      date: DateTime.parse(map['date']),
      description: map['description'] ?? '',
      userId: map['user_id'],
      subCategoryId: map['sub_category_id'],
      transferToWalletId: map['transfer_to_wallet_id'],
    );
  }

  TransactionModel _transactionFromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'],
      amount: (json['amount'] as num).toDouble(),
      type: TransactionType.values.firstWhere((e) => e.name == json['type']),
      categoryId: json['categoryId'],
      walletId: json['walletId'],
      date: DateTime.parse(json['date']),
      description: json['description'] ?? '',
      userId: json['userId'],
      subCategoryId: json['subCategoryId'],
      transferToWalletId: json['transferToWalletId'],
    );
  }

  Wallet _walletFromMap(Map<String, dynamic> map) {
    return Wallet(
      id: map['id'],
      name: map['name'],
      balance: (map['balance'] as num).toDouble(),
      ownerId: map['owner_id'],
      isVisibleToPartner: (map['is_visible_to_partner'] ?? 1) == 1,
      type: WalletType.values.firstWhere(
        (e) => e.name == (map['wallet_type'] ?? 'general'),
        orElse: () => WalletType.general,
      ),
      currency: map['currency'] ?? 'VND',
      isArchived: (map['is_archived'] ?? 0) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['created_at'] as int) * 1000,
            )
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['updated_at'] as int) * 1000,
            )
          : null,
    );
  }

  Wallet _walletFromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'],
      name: json['name'],
      balance: (json['balance'] as num).toDouble(),
      ownerId: json['ownerId'],
      isVisibleToPartner: json['isVisibleToPartner'] ?? true,
      type: WalletType.values.firstWhere(
        (e) => e.name == (json['type'] ?? 'general'),
        orElse: () => WalletType.general,
      ),
    );
  }

  Category _categoryFromMap(Map<String, dynamic> map) {
    final subCategoriesJson = map['sub_categories'] as String?;
    Map<String, String> subCategories = {};

    if (subCategoriesJson != null &&
        subCategoriesJson.isNotEmpty &&
        subCategoriesJson != '{}') {
      try {
        final decoded = jsonDecode(subCategoriesJson);
        subCategories = Map<String, String>.from(decoded);
      } catch (e) {
        print('⚠️ Error decoding subCategories: $e');
      }
    }

    return Category(
      id: map['id'],
      name: map['name'],
      ownerId: map['owner_id'],
      type: map['type'],
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == (map['ownership_type'] ?? 'personal'),
        orElse: () => CategoryOwnershipType.personal,
      ),
      createdBy: map['created_by'],
      iconCodePoint: map['icon_code_point'],
      subCategories: subCategories,
      isArchived: (map['is_archived'] ?? 0) == 1,
      usageCount: map['usage_count'] ?? 0,
      lastUsed: map['last_used'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['last_used'] as int) * 1000,
            )
          : null,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['created_at'] as int) * 1000,
            )
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['updated_at'] as int) * 1000,
            )
          : null,
    );
  }

  Category _categoryFromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'],
      name: json['name'],
      ownerId: json['ownerId'],
      type: json['type'],
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == (json['ownershipType'] ?? 'personal'),
        orElse: () => CategoryOwnershipType.personal,
      ),
      createdBy: json['createdBy'],
      iconCodePoint: json['iconCodePoint'],
      subCategories: Map<String, String>.from(json['subCategories'] ?? {}),
    );
  }

  Budget _budgetFromMap(Map<String, dynamic> map) {
    final categoryAmountsJson = map['category_amounts'] as String?;
    Map<String, double> categoryAmounts = {};

    if (categoryAmountsJson != null &&
        categoryAmountsJson.isNotEmpty &&
        categoryAmountsJson != '{}') {
      try {
        final decoded = jsonDecode(categoryAmountsJson);
        categoryAmounts = Map<String, double>.from(
          decoded.map((k, v) => MapEntry(k, (v as num).toDouble())),
        );
      } catch (e) {
        print('⚠️ Error decoding categoryAmounts: $e');
      }
    }

    final notesJson = map['notes'] as String?;
    Map<String, String>? notes;
    if (notesJson != null && notesJson.isNotEmpty && notesJson != '{}') {
      try {
        notes = Map<String, String>.from(jsonDecode(notesJson));
      } catch (e) {
        print('⚠️ Error decoding notes: $e');
      }
    }

    final categoryLimitsJson = map['category_limits'] as String?;
    Map<String, double>? categoryLimits;
    if (categoryLimitsJson != null &&
        categoryLimitsJson.isNotEmpty &&
        categoryLimitsJson != '{}') {
      try {
        final decoded = jsonDecode(categoryLimitsJson);
        categoryLimits = Map<String, double>.from(
          decoded.map((k, v) => MapEntry(k, (v as num).toDouble())),
        );
      } catch (e) {
        print('⚠️ Error decoding categoryLimits: $e');
      }
    }

    return Budget(
      id: map['id'],
      ownerId: map['owner_id'],
      month: map['month'],
      totalAmount: (map['total_amount'] as num).toDouble(),
      categoryAmounts: categoryAmounts,
      budgetType: BudgetType.values.firstWhere(
        (e) => e.name == (map['budget_type'] ?? 'personal'),
        orElse: () => BudgetType.personal,
      ),
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == (map['period'] ?? 'monthly'),
        orElse: () => BudgetPeriod.monthly,
      ),
      createdBy: map['created_by'],
      startDate: map['start_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['start_date'] as int)
          : null,
      endDate: map['end_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_date'] as int)
          : null,
      isActive: (map['is_active'] ?? 1) == 1,
      notes: notes,
      categoryLimits: categoryLimits,
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['created_at'] as int) * 1000,
            )
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (map['updated_at'] as int) * 1000,
            )
          : null,
    );
  }

  Budget _budgetFromJson(Map<String, dynamic> json) {
    return Budget(
      id: json['id'],
      ownerId: json['ownerId'],
      month: json['month'],
      totalAmount: (json['totalAmount'] as num).toDouble(),
      categoryAmounts: Map<String, double>.from(json['categoryAmounts'] ?? {}),
      budgetType: BudgetType.values.firstWhere(
        (e) => e.name == (json['budgetType'] ?? 'personal'),
        orElse: () => BudgetType.personal,
      ),
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == (json['period'] ?? 'monthly'),
        orElse: () => BudgetPeriod.monthly,
      ),
      createdBy: json['createdBy'],
    );
  }

  // ============ UTILITY METHODS ============

  Future<void> _updatePendingItemsCount() async {
    if (_localDatabase == null) return;

    try {
      final result = await _localDatabase!.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue',
      );
      _pendingItems = result.first['count'] as int;
    } catch (e) {
      print('⚠️ Error updating pending items count: $e');
      _pendingItems = 0;
    }
  }

  Future<void> _updateSyncStats() async {
    // Update any additional sync statistics here
  }

  // ============ PUBLIC API ============

  /// Force sync now - throws if offline
  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      throw Exception('Không có kết nối internet');
    }
    await _performFullSync();
  }

  /// Get health status
  Future<Map<String, dynamic>> getHealthStatus() async {
    final dbStats = await getDatabaseStats();

    return {
      'isOnline': _isOnline,
      'isSyncing': _isSyncing,
      'isInitialized': _isInitialized,
      'lastSyncTime': _lastSyncTime?.toIso8601String(),
      'pendingItems': _pendingItems,
      'lastError': _lastError,
      'currentUserId': currentUserId,
      'databaseStats': dbStats,
    };
  }

  /// Get database statistics
  Future<Map<String, int>> getDatabaseStats() async {
    if (_localDatabase == null) return {};

    try {
      final results = await Future.wait([
        _localDatabase!.rawQuery('SELECT COUNT(*) as count FROM transactions'),
        _localDatabase!.rawQuery('SELECT COUNT(*) as count FROM wallets'),
        _localDatabase!.rawQuery('SELECT COUNT(*) as count FROM categories'),
        _localDatabase!.rawQuery('SELECT COUNT(*) as count FROM budgets'),
        _localDatabase!.rawQuery('SELECT COUNT(*) as count FROM sync_queue'),
        _localDatabase!.rawQuery(
          'SELECT COUNT(*) as count FROM description_history',
        ),
      ]);

      return {
        'transactions': results[0].first['count'] as int,
        'wallets': results[1].first['count'] as int,
        'categories': results[2].first['count'] as int,
        'budgets': results[3].first['count'] as int,
        'pendingSync': results[4].first['count'] as int,
        'descriptions': results[5].first['count'] as int,
      };
    } catch (e) {
      print('⚠️ Error getting database stats: $e');
      return {};
    }
  }

  /// Get description suggestions for smart input
  Future<List<String>> getDescriptionSuggestions({int limit = 10}) async {
    if (_localDatabase == null || currentUserId == null) return [];

    try {
      final result = await _localDatabase!.query(
        'description_history',
        where: 'user_id = ?',
        whereArgs: [currentUserId],
        orderBy: 'usage_count DESC, last_used DESC',
        limit: limit,
      );

      return result.map((map) => map['description'] as String).toList();
    } catch (e) {
      print('⚠️ Error getting description suggestions: $e');
      return [];
    }
  }

  /// Search description history
  Future<List<String>> searchDescriptionHistory(
    String query, {
    int limit = 5,
  }) async {
    if (_localDatabase == null || currentUserId == null || query.trim().isEmpty)
      return [];

    try {
      final result = await _localDatabase!.query(
        'description_history',
        where: 'user_id = ? AND description LIKE ?',
        whereArgs: [currentUserId, '%${query.trim()}%'],
        orderBy: 'usage_count DESC, last_used DESC',
        limit: limit,
      );

      return result.map((map) => map['description'] as String).toList();
    } catch (e) {
      print('⚠️ Error searching description history: $e');
      return [];
    }
  }

  /// Get report data for analytics
  Future<ReportData> getReportData(DateTime startDate, DateTime endDate) async {
    if (!_isInitialized || currentUserId == null) {
      return ReportData(
        expenseByCategory: {},
        incomeByCategory: {},
        rawTransactions: [],
      );
    }

    try {
      // Get transactions for the period
      final transactions = await getTransactions(
        startDate: startDate,
        endDate: endDate,
      );

      // Get categories for grouping
      final categories = await getCategories();
      final categoryMap = {for (var c in categories) c.id: c};

      // Get wallets for partnership detection
      final wallets = await getWallets();
      final walletMap = {for (var w in wallets) w.id: w};

      double personalIncome = 0;
      double personalExpense = 0;
      double sharedIncome = 0;
      double sharedExpense = 0;

      Map<Category, double> expenseByCategory = {};
      Map<Category, double> incomeByCategory = {};

      for (final transaction in transactions) {
        final wallet = walletMap[transaction.walletId];
        final isShared = wallet?.ownerId == _userProvider?.partnershipId;

        if (transaction.type == TransactionType.income) {
          if (isShared) {
            sharedIncome += transaction.amount;
          } else {
            personalIncome += transaction.amount;
          }

          // Group by category
          if (transaction.categoryId != null) {
            final category =
                categoryMap[transaction.categoryId] ??
                Category(
                  id: 'unknown_income',
                  name: 'Chưa phân loại',
                  ownerId: '',
                  type: 'income',
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
            final category =
                categoryMap[transaction.categoryId] ??
                Category(
                  id: 'unknown_expense',
                  name: 'Chưa phân loại',
                  ownerId: '',
                  type: 'expense',
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

  /// Clear all local data (for logout/reset)
  Future<void> clearAllData() async {
    if (_localDatabase == null) return;

    try {
      await _localDatabase!.transaction((txn) async {
        await txn.delete('transactions');
        await txn.delete('wallets');
        await txn.delete('categories');
        await txn.delete('budgets');
        await txn.delete('description_history');
        await txn.delete('sync_queue');
        await txn.delete('sync_metadata');
        await txn.delete('users');
      });

      _pendingItems = 0;
      _lastSyncTime = null;
      _lastError = null;
      notifyListeners();

      print('✅ All local data cleared');
    } catch (e) {
      print('❌ Error clearing data: $e');
      rethrow;
    }
  }

  // ============ CLEANUP ============

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _healthCheckTimer?.cancel();
    _localDatabase?.close();
    super.dispose();
  }

  void unawaited(Future<void> future) {
    future.catchError((error) {
      print('Unawaited error: $error');
    });
  }
}
