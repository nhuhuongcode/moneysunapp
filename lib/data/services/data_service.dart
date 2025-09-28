import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' hide Transaction;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// Models
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';

/// COMPLETE DATASERVICE - SINGLE SOURCE OF TRUTH
class DataService extends ChangeNotifier {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  // ============ CORE DEPENDENCIES ============
  final DatabaseReference _firebaseRef = FirebaseDatabase.instance.ref();
  final Connectivity _connectivity = Connectivity();
  Database? _localDatabase;
  UserProvider? _userProvider;

  // ============ SERVICE STATE ============
  bool _isOnline = false;
  bool _isSyncing = false;
  bool _isInitialized = false;
  DateTime? _lastSyncTime;
  int _pendingItems = 0;
  String? _lastError;

  // ============ SYNC MANAGEMENT ============
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _syncTimer;
  final Map<String, Completer<void>> _activeSyncs = {};

  // ============ PERFORMANCE TRACKING ============
  final Map<String, List<Duration>> _operationTimes = {};
  int _totalOperations = 0;
  int _failedOperations = 0;

  // ============ GETTERS ============
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  bool get isInitialized => _isInitialized;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingItems => _pendingItems;
  String? get lastError => _lastError;
  String? get currentUserId => _userProvider?.currentUser?.uid;
  String? get partnershipId => _userProvider?.partnershipId;

  // ============ INITIALIZATION ============
  Future<void> initialize(UserProvider userProvider) async {
    if (_isInitialized) {
      debugPrint('⚠️ DataService already initialized');
      return;
    }

    _userProvider = userProvider;

    try {
      debugPrint('🚀 Initializing Complete DataService...');

      // 1. Initialize local database
      await _initializeDatabase();

      // 2. Setup connectivity monitoring
      await _setupConnectivityMonitoring();

      // 3. Start background services
      _startBackgroundServices();

      // 4. Initial sync if online
      if (_isOnline && currentUserId != null) {
        unawaited(_performInitialSync());
      }

      _isInitialized = true;
      notifyListeners();

      debugPrint('✅ DataService initialized successfully');
    } catch (e) {
      _lastError = 'Initialization failed: $e';
      debugPrint('❌ DataService initialization failed: $e');
      _isInitialized = true;
      notifyListeners();
      rethrow;
    }
  }

  // ============ DATABASE INITIALIZATION ============
  Future<void> _initializeDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'moneysun_complete.db');

      _localDatabase = await openDatabase(
        path,
        version: 2,
        onCreate: _createDatabaseTables,
        onUpgrade: _upgradeDatabase,
        onOpen: _onDatabaseOpen,
      );

      debugPrint('✅ Database initialized: $path');
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow;
    }
  }

  // FIXED: Separate onOpen handler with proper PRAGMA setup
  Future<void> _onDatabaseOpen(Database db) async {
    try {
      debugPrint('🔧 Setting up database PRAGMA...');

      // FIXED: Use rawQuery instead of execute for PRAGMA statements
      await db.rawQuery('PRAGMA foreign_keys = ON');
      debugPrint('✅ Foreign keys enabled');

      await db.rawQuery('PRAGMA journal_mode = WAL');
      debugPrint('✅ WAL mode enabled');

      await db.rawQuery('PRAGMA cache_size = 20000');
      debugPrint('✅ Cache size set');

      await db.rawQuery('PRAGMA synchronous = NORMAL');
      debugPrint('✅ Synchronous mode set');

      debugPrint('✅ All PRAGMA settings applied successfully');
    } catch (e) {
      debugPrint(
        '⚠️ PRAGMA setup failed, continuing with default settings: $e',
      );
      // Don't rethrow - database can work without these optimizations
    }
  }

  Future<void> _createDatabaseTables(Database db, int version) async {
    debugPrint('🔨 Creating database tables v$version...');

    await db.transaction((txn) async {
      // Users table
      await txn.execute('''
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          display_name TEXT,
          email TEXT,
          photo_url TEXT,
          partnership_id TEXT,
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Transactions table
      await txn.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          amount REAL NOT NULL CHECK (amount >= 0),
          type TEXT NOT NULL CHECK (type IN ('income', 'expense', 'transfer')),
          category_id TEXT,
          wallet_id TEXT NOT NULL,
          date TEXT NOT NULL,
          description TEXT DEFAULT '',
          user_id TEXT NOT NULL,
          sub_category_id TEXT,
          transfer_to_wallet_id TEXT,
          wallet_name TEXT DEFAULT '',
          category_name TEXT DEFAULT '',
          sub_category_name TEXT DEFAULT '',
          transfer_from_wallet_name TEXT DEFAULT '',
          transfer_to_wallet_name TEXT DEFAULT '',
          
          sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1, 2)),
          version INTEGER DEFAULT 1,
          created_by TEXT,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          FOREIGN KEY (wallet_id) REFERENCES wallets(id) ON DELETE CASCADE,
          FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
        )
      ''');

      // Wallets table
      await txn.execute('''
        CREATE TABLE wallets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL CHECK (length(name) > 0),
          balance REAL NOT NULL DEFAULT 0,
          owner_id TEXT NOT NULL,
          is_visible_to_partner INTEGER DEFAULT 1,
          wallet_type TEXT DEFAULT 'general',
          currency TEXT DEFAULT 'VND',
          is_archived INTEGER DEFAULT 0,
          
          sync_status INTEGER DEFAULT 0,
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Categories table
      await txn.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL CHECK (length(name) > 0),
          owner_id TEXT NOT NULL,
          type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
          icon_code_point INTEGER,
          sub_categories TEXT DEFAULT '{}',
          ownership_type TEXT DEFAULT 'personal',
          created_by TEXT,
          is_archived INTEGER DEFAULT 0,
          usage_count INTEGER DEFAULT 0,
          last_used INTEGER,
          
          sync_status INTEGER DEFAULT 0,
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(owner_id, name, type)
        )
      ''');

      // Sync Queue table
      await txn.execute('''
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
          processed_at INTEGER,
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          UNIQUE(table_name, record_id, operation) ON CONFLICT REPLACE
        )
      ''');

      // System metadata table
      await txn.execute('''
        CREATE TABLE system_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      await txn.execute('''
        CREATE TABLE budgets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          owner_id TEXT NOT NULL,
          month TEXT NOT NULL,
          total_amount REAL NOT NULL DEFAULT 0,
          category_amounts TEXT DEFAULT '{}',
          budget_type TEXT DEFAULT 'personal' CHECK (budget_type IN ('personal', 'shared')),
          period TEXT DEFAULT 'monthly' CHECK (period IN ('weekly', 'monthly', 'quarterly', 'yearly', 'custom')),
          created_by TEXT,
          start_date INTEGER,
          end_date INTEGER,
          is_active INTEGER DEFAULT 1,
          notes TEXT,
          category_limits TEXT,
          is_deleted INTEGER DEFAULT 0,
          
          sync_status INTEGER DEFAULT 0,
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(owner_id, month, budget_type)
        )
      ''');

      // Create indexes
      await _createIndexes(txn);

      // Create triggers
      await _createTriggers(txn);
    });

    debugPrint('✅ Database tables created successfully');
  }

  Future<void> _createIndexes(Transaction txn) async {
    final indexes = [
      'CREATE INDEX idx_transactions_user_date ON transactions(user_id, date DESC)',
      'CREATE INDEX idx_transactions_wallet ON transactions(wallet_id)',
      'CREATE INDEX idx_transactions_sync ON transactions(sync_status)',
      'CREATE INDEX idx_wallets_owner ON wallets(owner_id)',
      'CREATE INDEX idx_categories_owner_type ON categories(owner_id, type)',
      'CREATE INDEX idx_sync_queue_priority ON sync_queue(priority DESC, scheduled_at ASC)',
      'CREATE INDEX idx_budgets_owner_month ON budgets(owner_id, month DESC)',
      'CREATE INDEX idx_budgets_sync ON budgets(sync_status)',
      'CREATE INDEX idx_budgets_type ON budgets(budget_type)',
    ];

    for (final index in indexes) {
      try {
        await txn.execute(index);
      } catch (e) {
        debugPrint('⚠️ Warning creating index: $e');
      }
    }
  }

  Future<void> _createTriggers(Transaction txn) async {
    // Update wallet balance trigger - INSERT
    await txn.execute('''
        CREATE TRIGGER update_wallet_balance_insert 
        AFTER INSERT ON transactions
        BEGIN
          -- Update source wallet
          UPDATE wallets 
          SET 
            balance = balance + 
              CASE NEW.type
                WHEN 'income' THEN NEW.amount
                WHEN 'expense' THEN -NEW.amount
                WHEN 'transfer' THEN -NEW.amount
              END,
            updated_at = strftime('%s', 'now')
          WHERE id = NEW.wallet_id;
          
          -- Update destination wallet for transfers
          UPDATE wallets 
          SET 
            balance = balance + NEW.amount,
            updated_at = strftime('%s', 'now')
          WHERE id = NEW.transfer_to_wallet_id AND NEW.type = 'transfer';
        END
      ''');

    // Update wallet balance trigger - UPDATE (when transaction is modified)
    await txn.execute('''
        CREATE TRIGGER update_wallet_balance_update 
        AFTER UPDATE ON transactions
        BEGIN
          -- Revert old transaction effect
          UPDATE wallets 
          SET 
            balance = balance - 
              CASE OLD.type
                WHEN 'income' THEN OLD.amount
                WHEN 'expense' THEN -OLD.amount
                WHEN 'transfer' THEN -OLD.amount
              END,
            updated_at = strftime('%s', 'now')
          WHERE id = OLD.wallet_id;
          
          -- Revert old transfer destination
          UPDATE wallets 
          SET 
            balance = balance - OLD.amount,
            updated_at = strftime('%s', 'now')
          WHERE id = OLD.transfer_to_wallet_id AND OLD.type = 'transfer';
          
          -- Apply new transaction effect
          UPDATE wallets 
          SET 
            balance = balance + 
              CASE NEW.type
                WHEN 'income' THEN NEW.amount
                WHEN 'expense' THEN -NEW.amount
                WHEN 'transfer' THEN -NEW.amount
              END,
            updated_at = strftime('%s', 'now')
          WHERE id = NEW.wallet_id;
          
          -- Apply new transfer destination
          UPDATE wallets 
          SET 
            balance = balance + NEW.amount,
            updated_at = strftime('%s', 'now')
          WHERE id = NEW.transfer_to_wallet_id AND NEW.type = 'transfer';
        END
      ''');

    // Update wallet balance trigger - DELETE
    await txn.execute('''
        CREATE TRIGGER update_wallet_balance_delete 
        AFTER DELETE ON transactions
        BEGIN
          -- Revert transaction effect
          UPDATE wallets 
          SET 
            balance = balance - 
              CASE OLD.type
                WHEN 'income' THEN OLD.amount
                WHEN 'expense' THEN -OLD.amount
                WHEN 'transfer' THEN -OLD.amount
              END,
            updated_at = strftime('%s', 'now')
          WHERE id = OLD.wallet_id;
          
          -- Revert transfer destination
          UPDATE wallets 
          SET 
            balance = balance - OLD.amount,
            updated_at = strftime('%s', 'now')
          WHERE id = OLD.transfer_to_wallet_id AND OLD.type = 'transfer';
        END
      ''');

    // ✅ NEW: Update category usage trigger
    await txn.execute('''
        CREATE TRIGGER update_category_usage 
        AFTER INSERT ON transactions
        WHEN NEW.category_id IS NOT NULL
        BEGIN
          UPDATE categories 
          SET 
            usage_count = usage_count + 1,
            last_used = strftime('%s', 'now'),
            updated_at = strftime('%s', 'now')
          WHERE id = NEW.category_id;
        END
      ''');

    debugPrint('✅ Database triggers created successfully');
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint('🔄 Upgrading database from v$oldVersion to v$newVersion');
  }

  // ============ CONNECTIVITY MANAGEMENT ============
  Future<void> _setupConnectivityMonitoring() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = result.isNotEmpty && !result.contains(ConnectivityResult.none);

    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final wasOnline = _isOnline;
      _isOnline =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);

      if (_isOnline && !wasOnline) {
        debugPrint('📶 Connection restored - starting sync...');
        _lastError = null;
        unawaited(_performIntelligentSync());
      } else if (!_isOnline && wasOnline) {
        debugPrint('📵 Connection lost - switching to offline mode');
      }

      notifyListeners();
    });

    debugPrint('👂 Connectivity monitoring setup');
  }

  // ============ BACKGROUND SERVICES ============
  void _startBackgroundServices() {
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_isOnline && !_isSyncing && _pendingItems > 0) {
        unawaited(_performIntelligentSync());
      }
    });

    debugPrint('🤖 Background services started');
  }

  // ============ PUBLIC API METHODS ============

  /// Get transactions with offline-first support
  Future<List<TransactionModel>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    int? limit = 50,
    int? offset = 0,
    String? walletId,
    String? categoryId,
  }) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
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

      final result = await _localDatabase!.query(
        'transactions',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'date DESC, created_at DESC',
        limit: limit,
        offset: offset,
      );

      final transactions = result
          .map((map) => _transactionFromMap(map))
          .toList();

      // Background refresh if needed and online
      if (_isOnline && transactions.isNotEmpty) {
        unawaited(_refreshTransactionsIfNeeded());
      }

      return transactions;
    } catch (e) {
      debugPrint('❌ Error getting transactions: $e');
      return [];
    }
  }

  /// Add new transaction with offline-first support
  Future<void> addTransaction(TransactionModel transaction) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    await _localDatabase!.transaction((txn) async {
      // ✅ FIX: Validate category exists (if provided)
      if (transaction.categoryId != null &&
          transaction.categoryId!.isNotEmpty) {
        final categoryExists = await txn.query(
          'categories',
          where: 'id = ? OR firebase_id = ?',
          whereArgs: [transaction.categoryId!, transaction.categoryId!],
          limit: 1,
        );

        if (categoryExists.isEmpty) {
          debugPrint(
            '⚠️ Category ${transaction.categoryId} not found, creating placeholder',
          );
          await txn.insert('categories', {
            'id': transaction.categoryId!,
            'firebase_id': transaction.categoryId!,
            'name': transaction.categoryName ?? 'Danh mục khác',
            'owner_id': currentUserId ?? 'unknown',
            'type': 'expense',
            'icon_code_point': 0xe94f,
            'sub_categories': '{}',
            'ownership_type': 'personal',
            'created_by': currentUserId,
            'is_archived': 0,
            'usage_count': 0,
            'sync_status': 2, // Placeholder status
            'version': 1,
          });
        }
      }

      final walletExists = await txn.query(
        'wallets',
        where: 'id = ? OR firebase_id = ?',
        whereArgs: [transaction.walletId, transaction.walletId],
        limit: 1,
      );

      if (walletExists.isEmpty) {
        debugPrint(
          '⚠️ Wallet ${transaction.walletId} not found, creating placeholder',
        );
        await txn.insert('wallets', {
          'id': transaction.walletId,
          'firebase_id': transaction.walletId,
          'name': transaction.walletName ?? 'Ví khác',
          'balance': 0.0,
          'owner_id': currentUserId ?? 'unknown',
          'is_visible_to_partner': 1,
          'wallet_type': 'general',
          'currency': 'VND',
          'is_archived': 0,
          'sync_status': 2, // Placeholder status
          'version': 1,
        });
      }

      // ✅ FIX: Validate transfer wallet if applicable
      if (transaction.transferToWalletId != null &&
          transaction.transferToWalletId!.isNotEmpty) {
        final transferWalletExists = await txn.query(
          'wallets',
          where: 'id = ? OR firebase_id = ?',
          whereArgs: [
            transaction.transferToWalletId!,
            transaction.transferToWalletId!,
          ],
          limit: 1,
        );

        if (transferWalletExists.isEmpty) {
          await txn.insert('wallets', {
            'id': transaction.transferToWalletId!,
            'firebase_id': transaction.transferToWalletId!,
            'name': transaction.transferToWalletName ?? 'Ví chuyển đến',
            'balance': 0.0,
            'owner_id': currentUserId ?? 'unknown',
            'is_visible_to_partner': 1,
            'wallet_type': 'general',
            'currency': 'VND',
            'is_archived': 0,
            'sync_status': 2,
            'version': 1,
          });
        }
      }

      // ✅ FIX: Insert transaction with null safety
      await txn.insert('transactions', {
        'id': transaction.id,
        'amount': transaction.amount,
        'type': transaction.type.name,
        'category_id': (transaction.categoryId?.isNotEmpty == true)
            ? transaction.categoryId
            : null,
        'wallet_id': transaction.walletId,
        'date': transaction.date.toIso8601String(),
        'description': transaction.description,
        'user_id': transaction.userId,
        'sub_category_id': (transaction.subCategoryId?.isNotEmpty == true)
            ? transaction.subCategoryId
            : null,
        'transfer_to_wallet_id':
            (transaction.transferToWalletId?.isNotEmpty == true)
            ? transaction.transferToWalletId
            : null,
        'wallet_name': transaction.walletName ?? '',
        'category_name': transaction.categoryName ?? '',
        'sub_category_name': transaction.subCategoryName ?? '',
        'transfer_from_wallet_name': transaction.transferFromWalletName ?? '',
        'transfer_to_wallet_name': transaction.transferToWalletName ?? '',
        'sync_status': 0, // Unsynced
        'version': 1,
        'created_by': currentUserId,
      });

      // Increment category usage if category provided
      if (transaction.categoryId != null &&
          transaction.categoryId!.isNotEmpty) {
        await txn.update(
          'categories',
          {
            'usage_count': 'usage_count + 1',
            'last_used': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ? OR firebase_id = ?',
          whereArgs: [transaction.categoryId!, transaction.categoryId!],
        );
      }

      // Add to sync queue
      await _addToSyncQueue(
        txn,
        'transactions',
        transaction.id,
        'INSERT',
        transaction.toJson(),
        priority: 2,
      );
    });

    // Try immediate sync if online
    if (_isOnline) {
      unawaited(_syncSingleRecord('transactions', transaction.id));
    }

    notifyListeners();
    debugPrint('✅ Transaction added safely: ${transaction.description}');
  }

  Future<List<Wallet>> getWallets({bool includeArchived = false}) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      if (partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, partnershipId!];
      }

      if (!includeArchived) {
        whereClause += ' AND is_archived = 0';
      }

      final result = await _localDatabase!.query(
        'wallets',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'balance DESC, name ASC',
      );

      return result.map((map) => _walletFromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Error getting wallets: $e');
      return [];
    }
  }

  /// Add new wallet with offline-first support
  Future<void> addWallet({
    required String name,
    required double initialBalance,
    WalletType type = WalletType.general,
    bool isVisibleToPartner = true,
    String? ownerId,
  }) async {
    if (!_isInitialized) {
      debugPrint('❌ DataService not initialized, attempting to initialize...');
      throw Exception('Service not initialized');
      if (_userProvider != null) {
        await initialize(_userProvider!);
      } else {
        throw Exception('UserProvider not set, cannot initialize DataService');
      }
    }

    if (_localDatabase == null) {
      throw Exception(' localDatabase is null, cannot add wallet');
    }

    final walletId =
        'wallet_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final finalOwnerId = ownerId ?? currentUserId;

    if (finalOwnerId == null) {
      throw Exception('No valid owner ID available');
    }

    try {
      debugPrint('➕ Adding wallet: $name');

      await _localDatabase!.transaction((txn) async {
        await txn.insert('wallets', {
          'id': walletId,
          'name': name,
          'balance': initialBalance,
          'owner_id': finalOwnerId,
          'is_visible_to_partner': isVisibleToPartner ? 1 : 0,
          'wallet_type': type.name,
          'currency': 'VND',
          'sync_status': 0, // Unsynced
          'version': 1,
        });

        await _addToSyncQueue(txn, 'wallets', walletId, 'INSERT', {
          'name': name,
          'balance': initialBalance,
          'ownerId': finalOwnerId,
          'isVisibleToPartner': isVisibleToPartner,
          'type': type.name,
        }, priority: 2);
      });

      if (_isOnline) {
        unawaited(_syncSingleRecord('wallets', walletId));
      }

      notifyListeners();
      debugPrint('✅ Wallet added: $name');
    } catch (e) {
      debugPrint('❌ Error adding wallet: $e');
      rethrow;
    }
  }

  Future<List<Category>> getCategories({bool includeArchived = false}) async {
    if (!isInitialized || _localDatabase == null) {
      debugPrint('⚠️ DataService not initialized, returning empty list');
      return [];
    }

    if (currentUserId == null) {
      debugPrint('⚠️ No current user, returning empty list');
      return [];
    }

    try {
      String whereClause = '(owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include partnership categories if user has partnership
      if (partnershipId != null) {
        whereClause += ' OR owner_id = ?';
        whereArgs.add(partnershipId!);
      }

      whereClause += ')';

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

      debugPrint('✅ Retrieved ${categories.length} categories');
      return categories;
    } catch (e) {
      debugPrint('❌ Error getting categories: $e');
      return [];
    }
  }

  /// Get transactions stream for real-time updates
  Stream<List<TransactionModel>> getTransactionsStream({
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
    String? categoryId,
  }) async* {
    // Initial data from local database
    yield await getTransactions(
      startDate: startDate,
      endDate: endDate,
      walletId: walletId,
      categoryId: categoryId,
    );

    // Listen to changes and refresh
    await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
      yield await getTransactions(
        startDate: startDate,
        endDate: endDate,
        walletId: walletId,
        categoryId: categoryId,
      );
    }
  }

  /// Get wallets stream for real-time updates
  Stream<List<Wallet>> getWalletsStream({bool includeArchived = false}) async* {
    yield await getWallets(includeArchived: includeArchived);

    await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
      yield await getWallets(includeArchived: includeArchived);
    }
  }

  /// Get categories stream for real-time updates
  Stream<List<Category>> getCategoriesStream({
    bool includeArchived = false,
  }) async* {
    yield await getCategories(includeArchived: includeArchived);

    await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
      yield await getCategories(includeArchived: includeArchived);
    }
  }

  // ============ SYNC OPERATIONS ============
  Future<void> _performInitialSync() async {
    debugPrint('🔄 Performing initial sync...');
    await _performIntelligentSync(isInitialSync: true);
  }

  Future<void> _performIntelligentSync({bool isInitialSync = false}) async {
    if (_isSyncing ||
        !_isOnline ||
        _localDatabase == null ||
        currentUserId == null) {
      return;
    }

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      // 1. Upload pending changes
      await _uploadPendingChanges();

      // 2. Download changes from Firebase
      await _downloadChangesFromFirebase();

      // 3. Update sync metadata
      _lastSyncTime = DateTime.now();
      await _updateSyncMetadata();

      debugPrint('✅ Intelligent sync completed successfully');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('❌ Intelligent sync failed: $e');
    } finally {
      _isSyncing = false;
      await _updatePendingItemsCount();
      notifyListeners();
    }
  }

  Future<void> _uploadPendingChanges() async {
    final pendingItems = await _localDatabase!.query(
      'sync_queue',
      where: 'processed_at IS NULL',
      orderBy: 'priority DESC, scheduled_at ASC',
      limit: 50,
    );

    for (final item in pendingItems) {
      try {
        await _processSyncItem(item);

        await _localDatabase!.update(
          'sync_queue',
          {'processed_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
          where: 'id = ?',
          whereArgs: [item['id']],
        );
      } catch (e) {
        await _handleSyncItemError(item, e);
      }
    }
  }

  Future<void> _processSyncItem(Map<String, dynamic> item) async {
    final tableName = item['table_name'] as String;
    final recordId = item['record_id'] as String;
    final operation = item['operation'] as String;
    final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;

    switch (tableName) {
      case 'transactions':
        await _syncTransactionToFirebase(recordId, operation, data);
        break;
      case 'wallets':
        await _syncWalletToFirebase(recordId, operation, data);
        break;
      case 'categories':
        await _syncCategoryToFirebase(recordId, operation, data);
        break;
    }
  }

  Future<void> _syncTransactionToFirebase(
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final transactionRef = _firebaseRef.child('transactions').child(recordId);

    switch (operation) {
      case 'INSERT':
      case 'UPDATE':
        await transactionRef.set({...data, 'updatedAt': ServerValue.timestamp});
        break;
      case 'DELETE':
        await transactionRef.remove();
        break;
    }

    // Mark as synced in local database
    await _localDatabase!.update(
      'transactions',
      {'sync_status': 1, 'firebase_id': recordId},
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> _syncWalletToFirebase(
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final walletRef = _firebaseRef.child('wallets').child(recordId);

    switch (operation) {
      case 'INSERT':
      case 'UPDATE':
        await walletRef.set({...data, 'updatedAt': ServerValue.timestamp});
        break;
      case 'DELETE':
        await walletRef.remove();
        break;
    }

    await _localDatabase!.update(
      'wallets',
      {'sync_status': 1, 'firebase_id': recordId},
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> _downloadChangesFromFirebase() async {
    // Download changes since last sync
    final lastSyncTimestamp = await _getLastSyncTimestamp();

    await Future.wait([
      _downloadTransactionsFromFirebase(lastSyncTimestamp),
      _downloadWalletsFromFirebase(lastSyncTimestamp),
      _downloadCategoriesFromFirebase(lastSyncTimestamp),
    ]);
  }

  Future<void> _downloadTransactionsFromFirebase(int? lastSyncTimestamp) async {
    try {
      Query query = _firebaseRef
          .child('transactions')
          .orderByChild('userId')
          .equalTo(currentUserId);

      final snapshot = await query.get();
      if (!snapshot.exists) return;

      final transactionsMap = snapshot.value as Map<dynamic, dynamic>;

      await _localDatabase!.transaction((txn) async {
        for (final entry in transactionsMap.entries) {
          final firebaseId = entry.key as String;
          final firebaseData = entry.value as Map<dynamic, dynamic>;

          final localRecords = await txn.query(
            'transactions',
            where: 'firebase_id = ? OR id = ?',
            whereArgs: [firebaseId, firebaseData['id']],
            limit: 1,
          );

          if (localRecords.isEmpty) {
            await _insertTransactionFromFirebase(txn, firebaseId, firebaseData);
          }
        }
      });

      debugPrint('✅ Downloaded transactions from Firebase');
    } catch (e) {
      debugPrint('❌ Error downloading transactions: $e');
    }
  }

  Future<void> _downloadWalletsFromFirebase(int? lastSyncTimestamp) async {
    try {
      Query query = _firebaseRef
          .child('wallets')
          .orderByChild('ownerId')
          .equalTo(currentUserId);

      final snapshot = await query.get();
      if (!snapshot.exists) return;

      final walletsMap = snapshot.value as Map<dynamic, dynamic>;

      await _localDatabase!.transaction((txn) async {
        for (final entry in walletsMap.entries) {
          final firebaseId = entry.key as String;
          final firebaseData = entry.value as Map<dynamic, dynamic>;

          final localRecords = await txn.query(
            'wallets',
            where: 'firebase_id = ? OR id = ?',
            whereArgs: [firebaseId, firebaseData['id']],
            limit: 1,
          );

          if (localRecords.isEmpty) {
            await _insertWalletFromFirebase(txn, firebaseId, firebaseData);
          }
        }
      });

      debugPrint('✅ Downloaded wallets from Firebase');
    } catch (e) {
      debugPrint('❌ Error downloading wallets: $e');
    }
  }

  Future<void> _insertTransactionFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    await txn.insert('transactions', {
      'id': firebaseData['id'] ?? firebaseId,
      'firebase_id': firebaseId,
      'amount': (firebaseData['amount'] ?? 0).toDouble(),
      'type': firebaseData['type'] ?? 'expense',
      'category_id': firebaseData['categoryId'],
      'wallet_id': firebaseData['walletId'] ?? '',
      'date': firebaseData['date'] ?? DateTime.now().toIso8601String(),
      'description': firebaseData['description'] ?? '',
      'user_id': firebaseData['userId'] ?? '',
      'sub_category_id': firebaseData['subCategoryId'],
      'transfer_to_wallet_id': firebaseData['transferToWalletId'],
      'sync_status': 1, // Synced
      'version': firebaseData['version'] ?? 1,
      'created_by': firebaseData['createdBy'],
    });
  }

  Future<void> _addToSyncQueue(
    Transaction txn,
    String tableName,
    String recordId,
    String operation,
    Map<String, dynamic> data, {
    int priority = 1,
  }) async {
    await txn.insert('sync_queue', {
      'table_name': tableName,
      'record_id': recordId,
      'operation': operation,
      'data': jsonEncode(data),
      'priority': priority,
    });
  }

  Future<void> _handleSyncItemError(
    Map<String, dynamic> item,
    dynamic error,
  ) async {
    final retryCount = (item['retry_count'] as int) + 1;
    final maxRetries = item['max_retries'] as int;

    if (retryCount >= maxRetries) {
      await _localDatabase!.delete(
        'sync_queue',
        where: 'id = ?',
        whereArgs: [item['id']],
      );
    } else {
      await _localDatabase!.update(
        'sync_queue',
        {'retry_count': retryCount, 'last_error': error.toString()},
        where: 'id = ?',
        whereArgs: [item['id']],
      );
    }
  }

  Future<void> _syncSingleRecord(String tableName, String recordId) async {
    // Immediate sync for high-priority items
    final items = await _localDatabase!.query(
      'sync_queue',
      where: 'table_name = ? AND record_id = ? AND processed_at IS NULL',
      whereArgs: [tableName, recordId],
      limit: 1,
    );

    if (items.isNotEmpty) {
      await _processSyncItem(items.first);
    }
  }

  Future<void> _refreshTransactionsIfNeeded() async {
    // Background refresh logic
    if (_lastSyncTime == null ||
        DateTime.now().difference(_lastSyncTime!).inMinutes > 5) {
      unawaited(_performIntelligentSync());
    }
  }

  Future<int?> _getLastSyncTimestamp() async {
    try {
      final result = await _localDatabase!.query(
        'system_metadata',
        where: 'key = ?',
        whereArgs: ['last_sync_timestamp'],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return int.tryParse(result.first['value'] as String);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  Future<void> _updateSyncMetadata() async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      await _localDatabase!.insert('system_metadata', {
        'key': 'last_sync_timestamp',
        'value': timestamp.toString(),
        'updated_at': timestamp ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint('⚠️ Error updating sync metadata: $e');
    }
  }

  Future<void> _updatePendingItemsCount() async {
    try {
      final result = await _localDatabase!.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE processed_at IS NULL',
      );
      _pendingItems = result.first['count'] as int;
    } catch (e) {
      _pendingItems = 0;
    }
  }

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
      walletName: map['wallet_name'] ?? '',
      categoryName: map['category_name'] ?? '',
      subCategoryName: map['sub_category_name'] ?? '',
      transferFromWalletName: map['transfer_from_wallet_name'] ?? '',
      transferToWalletName: map['transfer_to_wallet_name'] ?? '',
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
    );
  }

  Category _categoryFromMap(Map<String, dynamic> map) {
    try {
      return Category(
        id: map['id']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Unknown',
        ownerId: map['owner_id']?.toString() ?? '',
        type: map['type']?.toString() ?? 'expense',
        iconCodePoint: map['icon_code_point'] as int?,
        subCategories: map['sub_categories'] != null
            ? Map<String, String>.from(jsonDecode(map['sub_categories']))
            : {},
        ownershipType: CategoryOwnershipType.values.firstWhere(
          (e) => e.name == (map['ownership_type']?.toString() ?? 'personal'),
          orElse: () => CategoryOwnershipType.personal,
        ),
        createdBy: map['created_by']?.toString(),
        isArchived: (map['is_archived'] ?? 0) == 1,
        usageCount: map['usage_count'] as int? ?? 0,
        lastUsed: map['last_used'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['last_used'])
            : null,
        createdAt: map['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] * 1000)
            : DateTime.now(),
        updatedAt: map['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] * 1000)
            : DateTime.now(),
        version: map['version'] as int? ?? 1,
      );
    } catch (e) {
      debugPrint('❌ Error parsing category from map: $e, map: $map');

      // Return a safe default category
      return Category(
        id: map['id']?.toString() ?? 'unknown',
        name: 'Lỗi danh mục',
        ownerId: currentUserId ?? '',
        type: 'expense',
        ownershipType: CategoryOwnershipType.personal,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Force immediate sync
  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      throw Exception('No internet connection available');
    }
    await _performIntelligentSync();
  }

  /// Get health status for debugging
  Future<Map<String, dynamic>> getHealthStatus() async {
    final stats = <String, dynamic>{};

    if (_localDatabase != null) {
      try {
        final pendingSync = await _localDatabase!.rawQuery(
          'SELECT COUNT(*) as count FROM sync_queue WHERE processed_at IS NULL',
        );
        stats['pendingSync'] = pendingSync.first['count'];

        final lastSync = await _getLastSyncTimestamp();
        stats['lastSyncTime'] = lastSync != null
            ? DateTime.fromMillisecondsSinceEpoch(lastSync).toIso8601String()
            : 'never';

        stats['lastError'] = _lastError;
        stats['isOnline'] = _isOnline;
        stats['isSyncing'] = _isSyncing;
      } catch (e) {
        stats['error'] = e.toString();
      }
    }

    return stats;
  }

  // Utility method for unawaited futures
  void unawaited(Future<void> future) {
    future.catchError((error) {
      debugPrint('Unawaited error: $error');
    });
  }

  Future<List<Budget>> getBudgets({
    BudgetType? budgetType,
    String? month,
    bool includeDeleted = false,
  }) async {
    if (!isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include partnership budgets if user has partnership
      if (partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, partnershipId!];
      }

      // Budget type filter
      if (budgetType != null) {
        whereClause += ' AND budget_type = ?';
        whereArgs.add(budgetType.name);
      }

      // Month filter
      if (month != null) {
        whereClause += ' AND month = ?';
        whereArgs.add(month);
      }

      // Exclude deleted budgets unless requested
      if (!includeDeleted) {
        whereClause += ' AND is_deleted = 0';
      }

      final result = await _localDatabase!.query(
        'budgets',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'month DESC, created_at DESC',
      );

      final budgets = result.map((map) => _budgetFromMap(map)).toList();

      // Background refresh if needed and online
      if (isOnline && budgets.isNotEmpty) {
        unawaited(_refreshBudgetsIfNeeded());
      }

      return budgets;
    } catch (e) {
      debugPrint('❌ Error getting budgets: $e');
      return [];
    }
  }

  Future<void> addBudget({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    BudgetType budgetType = BudgetType.personal,
    BudgetPeriod period = BudgetPeriod.monthly,
    String? ownerId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    final budgetId =
        'budget_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final finalOwnerId = ownerId ?? _getCurrentOwnerId(budgetType);

    await _localDatabase!.transaction((txn) async {
      await txn.insert('budgets', {
        'id': budgetId,
        'owner_id': finalOwnerId,
        'month': month,
        'total_amount': totalAmount,
        'category_amounts': jsonEncode(categoryAmounts),
        'budget_type': budgetType.name,
        'period': period.name,
        'start_date': startDate?.millisecondsSinceEpoch,
        'end_date': endDate?.millisecondsSinceEpoch,
        'created_by': currentUserId,
        'is_active': 1,
        'is_deleted': 0,
        'sync_status': 0, // Unsynced
        'version': 1,
      });

      await _addToSyncQueue(txn, 'budgets', budgetId, 'INSERT', {
        'ownerId': finalOwnerId,
        'month': month,
        'totalAmount': totalAmount,
        'categoryAmounts': categoryAmounts,
        'budgetType': budgetType.name,
        'period': period.name,
        'startDate': startDate?.millisecondsSinceEpoch,
        'endDate': endDate?.millisecondsSinceEpoch,
        'createdBy': currentUserId,
      }, priority: 2);
    });

    if (isOnline) {
      unawaited(_syncSingleRecord('budgets', budgetId));
    }

    notifyListeners();
  }

  /// ✅ ENHANCED: Update budget with version control
  Future<void> updateBudget(Budget budget) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    await _localDatabase!.transaction((txn) async {
      await txn.update(
        'budgets',
        {
          'month': budget.month,
          'total_amount': budget.totalAmount,
          'category_amounts': jsonEncode(budget.categoryAmounts),
          'budget_type': budget.budgetType.name,
          'period': budget.period.name,
          'start_date': budget.startDate?.millisecondsSinceEpoch,
          'end_date': budget.endDate?.millisecondsSinceEpoch,
          'is_active': budget.isActive ? 1 : 0,
          'notes': budget.notes != null ? jsonEncode(budget.notes) : null,
          'category_limits': budget.categoryLimits != null
              ? jsonEncode(budget.categoryLimits)
              : null,
          'sync_status': 0, // Mark as unsynced
          'version': budget.version + 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [budget.id],
      );

      await _addToSyncQueue(
        txn,
        'budgets',
        budget.id,
        'UPDATE',
        budget.toJson(),
        priority: 2,
      );
    });

    if (isOnline) {
      unawaited(_syncSingleRecord('budgets', budget.id));
    }

    notifyListeners();
  }

  /// ✅ ENHANCED: Delete budget (soft delete)
  Future<void> deleteBudget(String budgetId) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    await _localDatabase!.transaction((txn) async {
      // Soft delete
      await txn.update(
        'budgets',
        {
          'is_deleted': 1,
          'sync_status': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [budgetId],
      );

      await _addToSyncQueue(txn, 'budgets', budgetId, 'DELETE', {
        'id': budgetId,
      }, priority: 2);
    });

    if (isOnline) {
      unawaited(_syncSingleRecord('budgets', budgetId));
    }

    notifyListeners();
  }

  /// Set category budget amount
  Future<void> setCategoryBudget(
    String budgetId,
    String categoryId,
    double amount,
  ) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    // Get current budget
    final budgetResult = await _localDatabase!.query(
      'budgets',
      where: 'id = ?',
      whereArgs: [budgetId],
      limit: 1,
    );

    if (budgetResult.isEmpty) {
      throw Exception('Budget not found');
    }

    final budgetData = budgetResult.first;
    final categoryAmounts = Map<String, double>.from(
      jsonDecode(budgetData['category_amounts'] as String),
    );

    // Update category amount
    if (amount > 0) {
      categoryAmounts[categoryId] = amount;
    } else {
      categoryAmounts.remove(categoryId);
    }

    // Calculate new total amount
    final newTotalAmount = categoryAmounts.values.fold(
      0.0,
      (sum, val) => sum + val,
    );

    await _localDatabase!.transaction((txn) async {
      await txn.update(
        'budgets',
        {
          'category_amounts': jsonEncode(categoryAmounts),
          'total_amount': newTotalAmount,
          'sync_status': 0,
          'version': (budgetData['version'] as int) + 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [budgetId],
      );

      await _addToSyncQueue(txn, 'budgets', budgetId, 'UPDATE', {
        'categoryAmounts': categoryAmounts,
        'totalAmount': newTotalAmount,
      }, priority: 2);
    });

    if (isOnline) {
      unawaited(_syncSingleRecord('budgets', budgetId));
    }

    notifyListeners();
  }

  /// Copy budget from another month
  Future<void> copyBudgetFromMonth(
    String sourceMonth,
    String targetMonth,
    BudgetType budgetType,
  ) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    // Find source budget
    final sourceBudgets = await _localDatabase!.query(
      'budgets',
      where:
          'month = ? AND budget_type = ? AND owner_id = ? AND is_deleted = 0',
      whereArgs: [sourceMonth, budgetType.name, _getCurrentOwnerId(budgetType)],
      limit: 1,
    );

    if (sourceBudgets.isEmpty) {
      throw Exception('Source budget not found');
    }

    final sourceBudget = sourceBudgets.first;
    final categoryAmounts = Map<String, double>.from(
      jsonDecode(sourceBudget['category_amounts'] as String),
    );

    // Create new budget for target month
    await addBudget(
      month: targetMonth,
      totalAmount: sourceBudget['total_amount'] as double,
      categoryAmounts: categoryAmounts,
      budgetType: budgetType,
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == sourceBudget['period'],
        orElse: () => BudgetPeriod.monthly,
      ),
    );
  }

  /// Get budget analytics
  Future<BudgetAnalytics> getBudgetAnalytics(String budgetId) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    // Get budget data
    final budgetResult = await _localDatabase!.query(
      'budgets',
      where: 'id = ?',
      whereArgs: [budgetId],
      limit: 1,
    );

    if (budgetResult.isEmpty) {
      throw Exception('Budget not found');
    }

    final budget = _budgetFromMap(budgetResult.first);

    // Get transactions for this budget period
    final (startDate, endDate) = budget.effectiveDateRange;
    final transactions = await getTransactions(
      startDate: startDate,
      endDate: endDate,
    );

    // Calculate analytics
    double totalSpent = 0;
    final categorySpending = <String, double>{};

    for (final transaction in transactions) {
      if (transaction.type == TransactionType.expense &&
          transaction.categoryId != null) {
        totalSpent += transaction.amount;
        categorySpending[transaction.categoryId!] =
            (categorySpending[transaction.categoryId!] ?? 0) +
            transaction.amount;
      }
    }

    // Build category analytics
    final categoryAnalytics = <String, CategoryBudgetAnalytics>{};
    for (final entry in budget.categoryAmounts.entries) {
      final categoryId = entry.key;
      final budgetAmount = entry.value;
      final spentAmount = categorySpending[categoryId] ?? 0;
      final remainingAmount = budgetAmount - spentAmount;
      final spentPercentage = budgetAmount > 0
          ? (spentAmount / budgetAmount * 100)
          : 0;

      categoryAnalytics[categoryId] = CategoryBudgetAnalytics(
        categoryId: categoryId,
        categoryName:
            'Category $categoryId', // Would need to fetch from categories table
        budgetAmount: budgetAmount,
        spentAmount: spentAmount,
        remainingAmount: remainingAmount,
        spentPercentage: spentPercentage as double,
        isOverBudget: spentAmount > budgetAmount,
        isNearLimit: spentPercentage >= 80,
        dailySpending: [], // Would need to calculate daily breakdown
      );
    }

    final totalRemaining = budget.totalAmount - totalSpent;
    final spentPercentage = budget.totalAmount > 0
        ? (totalSpent / budget.totalAmount * 100)
        : 0;

    return BudgetAnalytics(
      budgetId: budgetId,
      totalBudget: budget.totalAmount,
      totalSpent: totalSpent,
      totalRemaining: totalRemaining,
      spentPercentage: spentPercentage as double,
      categoryAnalytics: categoryAnalytics,
      alerts: [], // Would generate based on thresholds
      trend: BudgetTrend(
        direction: BudgetTrendDirection.stable,
        changePercentage: 0,
        description: 'Stable spending',
        monthlySpending: [],
      ),
    );
  }

  // ============ STREAM METHODS FOR UI ============

  /// Get budgets stream for real-time updates
  Stream<List<Budget>> getBudgetsStream({
    BudgetType? budgetType,
    String? month,
    bool includeDeleted = false,
  }) async* {
    yield await getBudgets(
      budgetType: budgetType,
      month: month,
      includeDeleted: includeDeleted,
    );

    await for (final _ in Stream.periodic(const Duration(seconds: 2))) {
      yield await getBudgets(
        budgetType: budgetType,
        month: month,
        includeDeleted: includeDeleted,
      );
    }
  }

  Future<Budget?> getBudgetById(String budgetId) async {
    if (!isInitialized || _localDatabase == null) return null;

    try {
      final result = await _localDatabase!.query(
        'budgets',
        where: 'id = ? AND is_deleted = 0',
        whereArgs: [budgetId],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return _budgetFromMap(result.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting budget by ID: $e');
      return null;
    }
  }

  /// ✅ NEW: Get budget for specific month and type
  Future<Budget?> getBudgetForMonth(String month, BudgetType budgetType) async {
    if (!isInitialized || _localDatabase == null || currentUserId == null) {
      return null;
    }

    try {
      String whereClause =
          'month = ? AND budget_type = ? AND is_deleted = 0 AND (owner_id = ?';
      List<dynamic> whereArgs = [month, budgetType.name, currentUserId];

      // Include partnership budgets if user has partnership
      if (partnershipId != null) {
        whereClause += ' OR owner_id = ?';
        whereArgs.add(partnershipId!);
      }

      whereClause += ')';

      final result = await _localDatabase!.query(
        'budgets',
        where: whereClause,
        whereArgs: whereArgs,
        limit: 1,
        orderBy: 'created_at DESC',
      );

      if (result.isNotEmpty) {
        return _budgetFromMap(result.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting budget for month: $e');
      return null;
    }
  }

  /// ✅ NEW: Get budgets by type and date range
  Future<List<Budget>> getBudgetsByDateRange(
    DateTime startDate,
    DateTime endDate, {
    BudgetType? budgetType,
  }) async {
    if (!isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      String whereClause = 'is_deleted = 0 AND (owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include partnership budgets if user has partnership
      if (partnershipId != null) {
        whereClause += ' OR owner_id = ?';
        whereArgs.add(partnershipId!);
      }

      whereClause += ')';

      // Apply budget type filter
      if (budgetType != null) {
        whereClause += ' AND budget_type = ?';
        whereArgs.add(budgetType.name);
      }

      // Apply date range filter (using month field as YYYY-MM format)
      final startMonth = startDate.toIso8601String().substring(0, 7);
      final endMonth = endDate.toIso8601String().substring(0, 7);
      whereClause += ' AND month >= ? AND month <= ?';
      whereArgs.addAll([startMonth, endMonth]);

      final result = await _localDatabase!.query(
        'budgets',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'month DESC, created_at DESC',
      );

      return result.map((map) => _budgetFromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Error getting budgets by date range: $e');
      return [];
    }
  }

  Future<void> _refreshBudgetsIfNeeded() async {
    // Background refresh logic
    if (lastSyncTime == null ||
        DateTime.now().difference(lastSyncTime!).inMinutes > 5) {
      unawaited(_performIntelligentSync());
    }
  }

  // ============ HELPER METHODS ============

  Budget _budgetFromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'],
      ownerId: map['owner_id'],
      month: map['month'],
      totalAmount: (map['total_amount'] as num).toDouble(),
      categoryAmounts: Map<String, double>.from(
        jsonDecode(map['category_amounts'] ?? '{}'),
      ),
      budgetType: BudgetType.values.firstWhere(
        (e) => e.name == (map['budget_type'] ?? 'personal'),
        orElse: () => BudgetType.personal,
      ),
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == (map['period'] ?? 'monthly'),
        orElse: () => BudgetPeriod.monthly,
      ),
      createdBy: map['created_by'],
      createdAt: map['created_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['created_at'] * 1000)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updated_at'] * 1000)
          : null,
      startDate: map['start_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['start_date'])
          : null,
      endDate: map['end_date'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_date'])
          : null,
      isActive: (map['is_active'] ?? 1) == 1,
      isDeleted: (map['is_deleted'] ?? 0) == 1,
      notes: map['notes'] != null
          ? Map<String, String>.from(jsonDecode(map['notes']))
          : null,
      categoryLimits: map['category_limits'] != null
          ? Map<String, double>.from(jsonDecode(map['category_limits']))
          : null,
      version: map['version'] ?? 1,
    );
  }

  String _getCurrentOwnerId(dynamic type) {
    if (type is CategoryOwnershipType) {
      if (type == CategoryOwnershipType.shared && partnershipId != null) {
        return partnershipId!;
      }
    } else if (type is BudgetType) {
      if (type == BudgetType.shared && partnershipId != null) {
        return partnershipId!;
      }
    }
    return currentUserId ?? '';
  }

  /// Increment category usage count
  Future<void> incrementCategoryUsage(String categoryId) async {
    if (!isInitialized || _localDatabase == null) return;

    try {
      await _localDatabase!.update(
        'categories',
        {
          'usage_count': 'usage_count + 1',
          'last_used': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'sync_status': 0, // Mark for sync
        },
        where: 'id = ?',
        whereArgs: [categoryId],
      );

      // Queue for sync
      await _localDatabase!.insert('sync_queue', {
        'table_name': 'categories',
        'record_id': categoryId,
        'operation': 'UPDATE',
        'data': jsonEncode({'usageIncrement': true}),
        'priority': 3, // Low priority
      });

      if (isOnline) {
        unawaited(_syncSingleRecord('categories', categoryId));
      }
    } catch (e) {
      debugPrint('❌ Error incrementing category usage: $e');
    }
  }

  Future<Category?> getCategoryById(String categoryId) async {
    if (!isInitialized || _localDatabase == null) return null;

    try {
      final result = await _localDatabase!.query(
        'categories',
        where: 'id = ? AND is_archived = 0',
        whereArgs: [categoryId],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return _categoryFromMap(result.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting category by ID: $e');
      return null;
    }
  }

  Future<List<Category>> getCategoriesByType(
    String type, {
    CategoryOwnershipType? ownershipType,
    bool includeArchived = false,
  }) async {
    if (!isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      String whereClause = 'type = ? AND (owner_id = ?';
      List<dynamic> whereArgs = [type, currentUserId];

      // Include partnership categories if user has partnership
      if (partnershipId != null) {
        whereClause += ' OR owner_id = ?';
        whereArgs.add(partnershipId!);
      }

      whereClause += ')';

      // Apply ownership filter
      if (ownershipType != null) {
        whereClause += ' AND ownership_type = ?';
        whereArgs.add(ownershipType.name);
      }

      // Apply archived filter
      if (!includeArchived) {
        whereClause += ' AND is_archived = 0';
      }

      final result = await _localDatabase!.query(
        'categories',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'usage_count DESC, name ASC',
      );

      return result.map((map) => _categoryFromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Error getting categories by type: $e');
      return [];
    }
  }

  Future<List<Category>> searchCategories(
    String query, {
    String? type,
    CategoryOwnershipType? ownershipType,
  }) async {
    if (query.trim().isEmpty) return [];

    final allCategories = await getCategories(includeArchived: false);
    final results = <Category>[];
    final scores = <Category, int>{};

    final lowercaseQuery = query.toLowerCase().trim();

    for (final category in allCategories) {
      // Apply type filter
      if (type != null && category.type != type) continue;

      // Apply ownership filter
      if (ownershipType != null && category.ownershipType != ownershipType)
        continue;

      int score = 0;

      // Exact name match gets highest score
      if (category.name.toLowerCase() == lowercaseQuery) {
        score += 100;
      }
      // Name starts with query
      else if (category.name.toLowerCase().startsWith(lowercaseQuery)) {
        score += 50;
      }
      // Name contains query
      else if (category.name.toLowerCase().contains(lowercaseQuery)) {
        score += 25;
      }

      // Sub-category matches
      for (final subCategory in category.subCategories.values) {
        if (subCategory.toLowerCase().contains(lowercaseQuery)) {
          score += 10;
        }
      }

      // Usage count boost
      score += (category.usageCount * 0.1).round();

      if (score > 0) {
        results.add(category);
        scores[category] = score;
      }
    }

    // Sort by relevance score
    results.sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return results;
  }

  Future<void> addCategory({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    int? iconCodePoint,
    Map<String, String>? subCategories,
    String? ownerId,
  }) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('DataService chưa được khởi tạo');
    }

    if (currentUserId == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    // ✅ VALIDATION: Comprehensive input validation
    final validationError = _validateCategoryInput(name, type, ownershipType);
    if (validationError != null) {
      throw Exception(validationError);
    }

    // ✅ CHECK DUPLICATES: Check for existing categories
    final existingCategories = await getCategories();
    final isDuplicate = existingCategories.any(
      (c) =>
          c.name.toLowerCase() == name.trim().toLowerCase() &&
          c.type == type &&
          c.ownershipType == ownershipType &&
          !c.isArchived,
    );

    if (isDuplicate) {
      throw Exception('Danh mục "$name" đã tồn tại');
    }

    final categoryId =
        'cat_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final finalOwnerId = ownerId ?? _getCurrentOwnerId(ownershipType);

    try {
      debugPrint('➕ Adding category: $name (${ownershipType.name})');

      await _localDatabase!.transaction((txn) async {
        // ✅ INSERT: Add category to local database
        await txn.insert('categories', {
          'id': categoryId,
          'name': name.trim(),
          'owner_id': finalOwnerId,
          'type': type,
          'icon_code_point': iconCodePoint,
          'sub_categories': jsonEncode(subCategories ?? {}),
          'ownership_type': ownershipType.name,
          'created_by': currentUserId,
          'is_archived': 0,
          'usage_count': 0,
          'sync_status': 0, // Unsynced - will be synced later
          'version': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });

        // ✅ QUEUE FOR SYNC: Add to sync queue for online sync
        await _addToSyncQueue(txn, 'categories', categoryId, 'INSERT', {
          'id': categoryId,
          'name': name.trim(),
          'ownerId': finalOwnerId,
          'type': type,
          'iconCodePoint': iconCodePoint,
          'subCategories': subCategories ?? {},
          'ownershipType': ownershipType.name,
          'createdBy': currentUserId,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        }, priority: 2);
      });

      // ✅ IMMEDIATE SYNC: Try to sync immediately if online
      if (isOnline) {
        unawaited(_syncSingleRecord('categories', categoryId));
      }

      notifyListeners();
      debugPrint('✅ Category added successfully: $name');
    } catch (e) {
      debugPrint('❌ Error adding category: $e');
      rethrow;
    }
  }

  String? _validateCategoryInput(
    String name,
    String type,
    CategoryOwnershipType ownershipType,
  ) {
    // Name validation
    if (name.trim().isEmpty) {
      return 'Tên danh mục không được để trống';
    }

    if (name.trim().length > 50) {
      return 'Tên danh mục không được dài quá 50 ký tự';
    }

    // Check for invalid characters
    if (name.contains(RegExp(r'[<>"/\\|?*]'))) {
      return 'Tên danh mục chứa ký tự không hợp lệ';
    }

    // Type validation
    if (!['income', 'expense'].contains(type)) {
      return 'Loại danh mục không hợp lệ (phải là income hoặc expense)';
    }

    // Partnership validation
    if (ownershipType == CategoryOwnershipType.shared &&
        (_userProvider?.hasPartner != true)) {
      return 'Không thể tạo danh mục chung khi chưa có đối tác';
    }

    return null; // Valid
  }

  /// ✅ ENHANCED: Sync category to Firebase with conflict resolution
  Future<void> _syncCategoryToFirebase(
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    try {
      final categoryRef = _firebaseRef.child('categories').child(recordId);

      switch (operation) {
        case 'INSERT':
          // For new categories, just insert
          await categoryRef.set({
            ...data,
            'updatedAt': ServerValue.timestamp,
            'createdAt': data['createdAt'] ?? ServerValue.timestamp,
          });
          debugPrint('✅ Category synced to Firebase: INSERT $recordId');
          break;

        case 'UPDATE':
          // ✅ CONFLICT RESOLUTION: Check for version conflicts
          final snapshot = await categoryRef.get();
          if (snapshot.exists) {
            final serverData = snapshot.value as Map<dynamic, dynamic>;
            final serverVersion = serverData['version'] as int? ?? 1;
            final localVersion = data['version'] as int? ?? 1;

            if (serverVersion > localVersion) {
              // Server version is newer - merge or use server version
              debugPrint('⚠️ Version conflict detected for category $recordId');
              await _handleCategoryVersionConflict(recordId, data, serverData);
              return;
            }
          }

          await categoryRef.update({
            ...data,
            'version': (data['version'] as int? ?? 1) + 1,
            'updatedAt': ServerValue.timestamp,
          });
          debugPrint('✅ Category synced to Firebase: UPDATE $recordId');
          break;

        case 'DELETE':
          // Soft delete by archiving
          await categoryRef.update({
            'isArchived': true,
            'archivedAt': ServerValue.timestamp,
            'updatedAt': ServerValue.timestamp,
          });
          debugPrint('✅ Category synced to Firebase: DELETE $recordId');
          break;
      }

      // ✅ UPDATE LOCAL STATUS: Mark as synced in local database
      await _localDatabase!.update(
        'categories',
        {
          'sync_status': 1, // Synced
          'firebase_id': recordId,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );
    } catch (e) {
      debugPrint('❌ Error syncing category to Firebase: $e');

      // Update sync status to indicate error
      await _localDatabase!.update(
        'categories',
        {'sync_status': 3}, // Error status
        where: 'id = ?',
        whereArgs: [recordId],
      );

      rethrow;
    }
  }

  Future<void> _handleCategoryVersionConflict(
    String recordId,
    Map<String, dynamic> localData,
    Map<dynamic, dynamic> serverData,
  ) async {
    try {
      debugPrint('🔄 Resolving category version conflict for $recordId');

      // Simple resolution strategy: Use server version and update local
      final resolvedCategory = Category(
        id: recordId,
        name: serverData['name']?.toString() ?? localData['name'],
        ownerId: serverData['ownerId']?.toString() ?? localData['ownerId'],
        type: serverData['type']?.toString() ?? localData['type'],
        iconCodePoint: serverData['iconCodePoint'] as int?,
        subCategories: Map<String, String>.from(
          serverData['subCategories'] ?? localData['subCategories'] ?? {},
        ),
        ownershipType: CategoryOwnershipType.values.firstWhere(
          (e) =>
              e.name ==
              (serverData['ownershipType'] ?? localData['ownershipType']),
          orElse: () => CategoryOwnershipType.personal,
        ),
        createdBy: serverData['createdBy']?.toString(),
        isArchived: serverData['isArchived'] == true,
        usageCount: serverData['usageCount'] as int? ?? 0,
        lastUsed: serverData['lastUsed'] != null
            ? DateTime.fromMillisecondsSinceEpoch(serverData['lastUsed'])
            : null,
        createdAt: serverData['createdAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(serverData['createdAt'])
            : DateTime.now(),
        updatedAt: DateTime.now(),
        version: serverData['version'] as int? ?? 1,
      );

      // Update local database with resolved version
      await _localDatabase!.update(
        'categories',
        {
          'name': resolvedCategory.name,
          'owner_id': resolvedCategory.ownerId,
          'type': resolvedCategory.type,
          'icon_code_point': resolvedCategory.iconCodePoint,
          'sub_categories': jsonEncode(resolvedCategory.subCategories),
          'ownership_type': resolvedCategory.ownershipType.name,
          'is_archived': resolvedCategory.isArchived ? 1 : 0,
          'usage_count': resolvedCategory.usageCount,
          'last_used': resolvedCategory.lastUsed?.millisecondsSinceEpoch,
          'sync_status': 1, // Resolved and synced
          'version': resolvedCategory.version,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );

      debugPrint('✅ Category conflict resolved: $recordId');
    } catch (e) {
      debugPrint('❌ Error resolving category conflict: $e');
      rethrow;
    }
  }

  /// Update category with offline-first support
  Future<void> updateCategory(Category category) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    await _localDatabase!.transaction((txn) async {
      await txn.update(
        'categories',
        {
          'name': category.name,
          'type': category.type,
          'icon_code_point': category.iconCodePoint,
          'sub_categories': jsonEncode(category.subCategories),
          'ownership_type': category.ownershipType.name,
          'is_archived': category.isArchived ? 1 : 0,
          'usage_count': category.usageCount,
          'last_used': category.lastUsed?.millisecondsSinceEpoch,
          'sync_status': 0, // Mark as unsynced
          'version': category.version + 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [category.id],
      );

      await _addToSyncQueue(
        txn,
        'categories',
        category.id,
        'UPDATE',
        category.toJson(),
        priority: 2,
      );
    });

    if (isOnline) {
      unawaited(_syncSingleRecord('categories', category.id));
    }

    notifyListeners();
  }

  /// Delete category with offline-first support (soft delete)
  Future<void> deleteCategory(String categoryId) async {
    if (!isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    await _localDatabase!.transaction((txn) async {
      // Soft delete by archiving
      await txn.update(
        'categories',
        {
          'is_archived': 1,
          'sync_status': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [categoryId],
      );

      await _addToSyncQueue(txn, 'categories', categoryId, 'DELETE', {
        'id': categoryId,
      }, priority: 2);
    });

    if (isOnline) {
      unawaited(_syncSingleRecord('categories', categoryId));
    }

    notifyListeners();
  }

  /// Get dashboard summary data
  Future<Map<String, dynamic>> getDashboardSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!isInitialized || _localDatabase == null) {
      return {};
    }

    final start =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();

    try {
      // Get transactions for period
      final transactions = await getTransactions(
        startDate: start,
        endDate: end,
      );

      // Calculate totals
      double totalIncome = 0;
      double totalExpense = 0;
      int incomeTransactionCount = 0;
      int expenseTransactionCount = 0;

      for (final transaction in transactions) {
        if (transaction.type == TransactionType.income) {
          totalIncome += transaction.amount;
          incomeTransactionCount++;
        } else if (transaction.type == TransactionType.expense) {
          totalExpense += transaction.amount;
          expenseTransactionCount++;
        }
      }

      // Get wallet balances
      final wallets = await getWallets();
      final totalBalance = wallets.fold(0.0, (sum, w) => sum + w.balance);

      // Get budget info for current month
      final currentMonth = DateTime.now().toIso8601String().substring(0, 7);
      final budgets = await getBudgets(month: currentMonth);
      final totalBudget = budgets.fold(0.0, (sum, b) => sum + b.totalAmount);

      // Calculate budget used from current month expenses
      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
      final monthTransactions = await getTransactions(
        startDate: monthStart,
        endDate: DateTime.now(),
      );
      final monthlyExpense = monthTransactions
          .where((t) => t.type == TransactionType.expense)
          .fold(0.0, (sum, t) => sum + t.amount);

      return {
        'period': {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
          'days': end.difference(start).inDays,
        },
        'totals': {
          'income': totalIncome,
          'expense': totalExpense,
          'netAmount': totalIncome - totalExpense,
          'balance': totalBalance,
        },
        'transactions': {
          'total': transactions.length,
          'income': incomeTransactionCount,
          'expense': expenseTransactionCount,
        },
        'budget': {
          'total': totalBudget,
          'used': monthlyExpense,
          'remaining': totalBudget - monthlyExpense,
          'usagePercentage': totalBudget > 0
              ? (monthlyExpense / totalBudget * 100)
              : 0,
        },
        'averages': {
          'dailyIncome': totalIncome / end.difference(start).inDays,
          'dailyExpense': totalExpense / end.difference(start).inDays,
          'transactionAmount': transactions.isNotEmpty
              ? (totalIncome + totalExpense) / transactions.length
              : 0,
        },
      };
    } catch (e) {
      debugPrint('❌ Error getting dashboard summary: $e');
      return {};
    }
  }

  /// Get expense breakdown by category
  Future<Map<String, double>> getExpenseByCategory({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!isInitialized || _localDatabase == null) {
      return {};
    }

    final start =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();

    try {
      final query = '''
        SELECT 
          COALESCE(c.name, t.category_name, 'Khác') as category_name,
          SUM(t.amount) as total
        FROM transactions t
        LEFT JOIN categories c ON t.category_id = c.id
        WHERE t.type = 'expense' 
          AND t.date >= ? AND t.date <= ?
          AND t.user_id = ?
        GROUP BY COALESCE(c.name, t.category_name, 'Khác')
        ORDER BY total DESC
      ''';

      final result = await _localDatabase!.rawQuery(query, [
        start.toIso8601String(),
        end.toIso8601String(),
        currentUserId,
      ]);

      final expenseMap = <String, double>{};
      for (final row in result) {
        expenseMap[row['category_name'] as String] = (row['total'] as num)
            .toDouble();
      }

      return expenseMap;
    } catch (e) {
      debugPrint('❌ Error getting expense by category: $e');
      return {};
    }
  }

  /// Get income breakdown by category
  Future<Map<String, double>> getIncomeByCategory({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!isInitialized || _localDatabase == null) {
      return {};
    }

    final start =
        startDate ?? DateTime.now().subtract(const Duration(days: 30));
    final end = endDate ?? DateTime.now();

    try {
      final query = '''
        SELECT 
          COALESCE(c.name, t.category_name, 'Khác') as category_name,
          SUM(t.amount) as total
        FROM transactions t
        LEFT JOIN categories c ON t.category_id = c.id
        WHERE t.type = 'income' 
          AND t.date >= ? AND t.date <= ?
          AND t.user_id = ?
        GROUP BY COALESCE(c.name, t.category_name, 'Khác')
        ORDER BY total DESC
      ''';

      final result = await _localDatabase!.rawQuery(query, [
        start.toIso8601String(),
        end.toIso8601String(),
        currentUserId,
      ]);

      final incomeMap = <String, double>{};
      for (final row in result) {
        incomeMap[row['category_name'] as String] = (row['total'] as num)
            .toDouble();
      }

      return incomeMap;
    } catch (e) {
      debugPrint('❌ Error getting income by category: $e');
      return {};
    }
  }

  /// Get monthly trends
  Future<List<Map<String, dynamic>>> getMonthlyTrends({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!isInitialized || _localDatabase == null) {
      return [];
    }

    final start =
        startDate ??
        DateTime.now().subtract(const Duration(days: 180)); // 6 months
    final end = endDate ?? DateTime.now();

    try {
      final query = '''
        SELECT 
          strftime('%Y-%m', date) as month,
          type,
          SUM(amount) as total,
          COUNT(*) as count
        FROM transactions
        WHERE date >= ? AND date <= ? AND user_id = ?
        GROUP BY strftime('%Y-%m', date), type
        ORDER BY month ASC
      ''';

      final result = await _localDatabase!.rawQuery(query, [
        start.toIso8601String(),
        end.toIso8601String(),
        currentUserId,
      ]);

      final trendsMap = <String, Map<String, dynamic>>{};

      for (final row in result) {
        final month = row['month'] as String;
        final type = row['type'] as String;
        final amount = (row['total'] as num).toDouble();
        final count = row['count'] as int;

        if (!trendsMap.containsKey(month)) {
          trendsMap[month] = {
            'month': month,
            'income': 0.0,
            'expense': 0.0,
            'incomeCount': 0,
            'expenseCount': 0,
          };
        }

        trendsMap[month]![type] = amount;
        trendsMap[month]!['${type}Count'] = count;
      }

      // Add calculated fields
      for (final trend in trendsMap.values) {
        trend['netAmount'] = trend['income'] - trend['expense'];
        trend['totalTransactions'] =
            trend['incomeCount'] + trend['expenseCount'];
      }

      final trends = trendsMap.values.toList();
      trends.sort(
        (a, b) => (a['month'] as String).compareTo(b['month'] as String),
      );

      return trends;
    } catch (e) {
      debugPrint('❌ Error getting monthly trends: $e');
      return [];
    }
  }

  Future<void> _insertWalletFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    try {
      // ✅ FIX: Validate required fields
      final name = (firebaseData['name'] as String?)?.trim();
      final ownerId = (firebaseData['ownerId'] as String?)?.trim();

      // Skip invalid data
      if (name == null || name.isEmpty) {
        debugPrint('⚠️ Skipping wallet with empty name: $firebaseId');
        return;
      }

      if (ownerId == null || ownerId.isEmpty) {
        debugPrint('⚠️ Skipping wallet with empty ownerId: $firebaseId');
        return;
      }

      // Check if already exists
      final existing = await txn.query(
        'wallets',
        where: 'firebase_id = ? OR id = ?',
        whereArgs: [firebaseId, firebaseData['id']],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        // Update existing
        await txn.update(
          'wallets',
          {
            'name': name,
            'balance': (firebaseData['balance'] ?? 0).toDouble(),
            'owner_id': ownerId,
            'is_visible_to_partner':
                (firebaseData['isVisibleToPartner'] ?? true) ? 1 : 0,
            'wallet_type': firebaseData['type'] ?? 'general',
            'is_archived': (firebaseData['isArchived'] ?? false) ? 1 : 0,
            'sync_status': 1, // Synced
            'version': firebaseData['version'] ?? 1,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'firebase_id = ?',
          whereArgs: [firebaseId],
        );
        debugPrint('✅ Updated existing wallet: $name');
        return;
      }

      // Insert new wallet with validated data
      await txn.insert('wallets', {
        'id': firebaseData['id'] ?? firebaseId,
        'firebase_id': firebaseId,
        'name': name, // ✅ VALIDATED: Non-empty
        'balance': (firebaseData['balance'] ?? 0).toDouble(),
        'owner_id': ownerId, // ✅ VALIDATED: Non-empty
        'is_visible_to_partner': (firebaseData['isVisibleToPartner'] ?? true)
            ? 1
            : 0,
        'wallet_type': firebaseData['type'] ?? 'general',
        'currency': 'VND',
        'is_archived': (firebaseData['isArchived'] ?? false) ? 1 : 0,
        'sync_status': 1, // Synced
        'version': firebaseData['version'] ?? 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      debugPrint('✅ Inserted valid wallet from Firebase: $name');
    } catch (e) {
      debugPrint('❌ Error inserting wallet from Firebase ($firebaseId): $e');
    }
  }

  // 🔥 PRIORITY 5: Add helper method for ownership
  String _getCurrentOwnerCateId(CategoryOwnershipType ownershipType) {
    if (ownershipType == CategoryOwnershipType.shared &&
        partnershipId != null) {
      return partnershipId!;
    }
    return currentUserId ?? '';
  }

  // 🔥 PRIORITY 6: Add basic smart suggestions (ADD new methods)

  /// Get transaction suggestions based on history
  Future<List<Map<String, dynamic>>> getTransactionSuggestions({
    int limit = 10,
  }) async {
    if (!isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      final query = '''
        SELECT 
          description, 
          category_id, 
          category_name,
          AVG(amount) as avg_amount, 
          COUNT(*) as frequency,
          MAX(date) as last_used
        FROM transactions
        WHERE user_id = ? AND date >= date('now', '-30 days')
        GROUP BY LOWER(description), category_id
        HAVING frequency >= 2
        ORDER BY frequency DESC, avg_amount DESC
        LIMIT ?
      ''';

      final result = await _localDatabase!.rawQuery(query, [
        currentUserId,
        limit,
      ]);

      final suggestions = <Map<String, dynamic>>[];
      for (final row in result) {
        final frequency = row['frequency'] as int;
        final confidence = (frequency / 10).clamp(0.1, 1.0);

        suggestions.add({
          'description': row['description'] as String,
          'categoryId': row['category_id'] as String?,
          'categoryName': row['category_name'] as String?,
          'suggestedAmount': (row['avg_amount'] as num).toDouble(),
          'frequency': frequency,
          'confidence': confidence,
          'lastUsed': row['last_used'] as String?,
          'reason': frequency > 5
              ? 'Thường xuyên sử dụng'
              : 'Đã sử dụng gần đây',
        });
      }

      return suggestions;
    } catch (e) {
      debugPrint('❌ Error getting transaction suggestions: $e');
      return [];
    }
  }

  /// Get amount suggestions for a description
  Future<List<double>> getAmountSuggestions(String description) async {
    if (!isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      final query = '''
        SELECT amount, COUNT(*) as frequency
        FROM transactions
        WHERE user_id = ? AND LOWER(description) LIKE LOWER(?) 
          AND date >= date('now', '-90 days')
        GROUP BY amount
        ORDER BY frequency DESC, amount DESC
        LIMIT 5
      ''';

      final result = await _localDatabase!.rawQuery(query, [
        currentUserId,
        '%${description.toLowerCase()}%',
      ]);

      return result.map((row) => (row['amount'] as num).toDouble()).toList();
    } catch (e) {
      debugPrint('❌ Error getting amount suggestions: $e');
      return [];
    }
  }

  /// Get description suggestions based on category
  Future<List<String>> getDescriptionSuggestions(String? categoryId) async {
    if (!isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      String query;
      List<dynamic> args;

      if (categoryId != null && categoryId.isNotEmpty) {
        query = '''
          SELECT description, COUNT(*) as frequency
          FROM transactions
          WHERE user_id = ? AND category_id = ?
            AND date >= date('now', '-60 days')
            AND description != ''
          GROUP BY LOWER(description)
          ORDER BY frequency DESC
          LIMIT 10
        ''';
        args = [currentUserId, categoryId];
      } else {
        query = '''
          SELECT description, COUNT(*) as frequency
          FROM transactions
          WHERE user_id = ? AND date >= date('now', '-60 days')
            AND description != ''
          GROUP BY LOWER(description)
          ORDER BY frequency DESC
          LIMIT 15
        ''';
        args = [currentUserId];
      }

      final result = await _localDatabase!.rawQuery(query, args);
      return result.map((row) => row['description'] as String).toList();
    } catch (e) {
      debugPrint('❌ Error getting description suggestions: $e');
      return [];
    }
  }

  Future<void> _syncBudgetToFirebase(
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final budgetRef = _firebaseRef.child('budgets').child(recordId);

    switch (operation) {
      case 'INSERT':
      case 'UPDATE':
        await budgetRef.set({...data, 'updatedAt': ServerValue.timestamp});
        break;
      case 'DELETE':
        // For budgets, we do soft delete
        await budgetRef.update({
          'isDeleted': true,
          'updatedAt': ServerValue.timestamp,
        });
        break;
    }

    await _localDatabase!.update(
      'budgets',
      {'sync_status': 1, 'firebase_id': recordId},
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<void> _downloadCategoriesFromFirebase(int? lastSyncTimestamp) async {
    try {
      debugPrint('⬇️ Downloading categories from Firebase...');

      // Query for user's categories
      final queries = <Future<DataSnapshot>>[];

      // Personal categories
      queries.add(
        _firebaseRef
            .child('categories')
            .orderByChild('ownerId')
            .equalTo(currentUserId)
            .get(),
      );

      // Shared categories if user has partnership
      if (partnershipId != null) {
        queries.add(
          _firebaseRef
              .child('categories')
              .orderByChild('ownerId')
              .equalTo(partnershipId!)
              .get(),
        );
      }

      final snapshots = await Future.wait(queries);

      int insertedCount = 0;
      int updatedCount = 0;

      for (final snapshot in snapshots) {
        if (!snapshot.exists) continue;

        final categoriesMap = snapshot.value as Map<dynamic, dynamic>;

        await _localDatabase!.transaction((txn) async {
          for (final entry in categoriesMap.entries) {
            final firebaseId = entry.key as String;
            final firebaseData = entry.value as Map<dynamic, dynamic>;

            // Check if category already exists locally
            final localRecords = await txn.query(
              'categories',
              where: 'firebase_id = ? OR id = ?',
              whereArgs: [firebaseId, firebaseData['id'] ?? firebaseId],
              limit: 1,
            );

            if (localRecords.isEmpty) {
              // Insert new category
              await _insertCategoryFromFirebase(txn, firebaseId, firebaseData);
              insertedCount++;
            } else {
              // Update existing category if server version is newer
              final localRecord = localRecords.first;
              final localVersion = localRecord['version'] as int? ?? 1;
              final firebaseVersion = firebaseData['version'] as int? ?? 1;

              if (firebaseVersion > localVersion) {
                await _updateCategoryFromFirebase(
                  txn,
                  firebaseId,
                  firebaseData,
                );
                updatedCount++;
              }
            }
          }
        });
      }

      debugPrint(
        '✅ Categories downloaded: $insertedCount inserted, $updatedCount updated',
      );
    } catch (e) {
      debugPrint('❌ Error downloading categories from Firebase: $e');
      rethrow;
    }
  }

  /// ✅ ENHANCED: Download budgets from Firebase
  Future<void> _downloadBudgetsFromFirebase(int? lastSyncTimestamp) async {
    try {
      Query query = _firebaseRef
          .child('budgets')
          .orderByChild('ownerId')
          .equalTo(currentUserId);

      final snapshot = await query.get();
      if (!snapshot.exists) return;

      final budgetsMap = snapshot.value as Map<dynamic, dynamic>;

      await _localDatabase!.transaction((txn) async {
        for (final entry in budgetsMap.entries) {
          final firebaseId = entry.key as String;
          final firebaseData = entry.value as Map<dynamic, dynamic>;

          final localRecords = await txn.query(
            'budgets',
            where: 'firebase_id = ? OR id = ?',
            whereArgs: [firebaseId, firebaseData['id']],
            limit: 1,
          );

          if (localRecords.isEmpty) {
            await _insertBudgetFromFirebase(txn, firebaseId, firebaseData);
          } else {
            // Update existing record if Firebase version is newer
            final localRecord = localRecords.first;
            final localVersion = localRecord['version'] as int? ?? 1;
            final firebaseVersion = firebaseData['version'] as int? ?? 1;

            if (firebaseVersion > localVersion) {
              await _updateBudgetFromFirebase(txn, firebaseId, firebaseData);
            }
          }
        }
      });

      debugPrint('✅ Downloaded budgets from Firebase');
    } catch (e) {
      debugPrint('❌ Error downloading budgets: $e');
    }
  }

  /// ✅ ENHANCED: Insert category from Firebase with validation
  Future<void> _insertCategoryFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    try {
      // Validate required fields
      final name = (firebaseData['name'] as String?)?.trim();
      final ownerId = (firebaseData['ownerId'] as String?)?.trim();
      final type = (firebaseData['type'] as String?)?.trim();

      // Skip invalid data
      if (name == null ||
          name.isEmpty ||
          ownerId == null ||
          ownerId.isEmpty ||
          type == null ||
          !['income', 'expense'].contains(type)) {
        debugPrint('⚠️ Skipping invalid category from Firebase: $firebaseId');
        return;
      }

      // Check if already exists to prevent duplicates
      final existing = await txn.query(
        'categories',
        where: 'firebase_id = ? OR id = ?',
        whereArgs: [firebaseId, firebaseData['id']],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        await _updateCategoryFromFirebase(txn, firebaseId, firebaseData);
        return;
      }

      await txn.insert('categories', {
        'id': firebaseData['id'] ?? firebaseId,
        'firebase_id': firebaseId,
        'name': name,
        'owner_id': ownerId,
        'type': type,
        'icon_code_point': firebaseData['iconCodePoint'],
        'sub_categories': jsonEncode(firebaseData['subCategories'] ?? {}),
        'ownership_type': firebaseData['ownershipType'] ?? 'personal',
        'created_by': firebaseData['createdBy'],
        'is_archived': (firebaseData['isArchived'] ?? false) ? 1 : 0,
        'usage_count': firebaseData['usageCount'] ?? 0,
        'last_used': firebaseData['lastUsed'],
        'sync_status': 1, // Synced
        'version': firebaseData['version'] ?? 1,
        'created_at':
            firebaseData['createdAt'] ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'updated_at':
            firebaseData['updatedAt'] ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      debugPrint('✅ Inserted category from Firebase: $name');
    } catch (e) {
      debugPrint('❌ Error inserting category from Firebase ($firebaseId): $e');
    }
  }

  /// ✅ NEW: Update category from Firebase
  Future<void> _updateCategoryFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    try {
      await txn.update(
        'categories',
        {
          'name': (firebaseData['name'] as String?)?.trim() ?? '',
          'owner_id': (firebaseData['ownerId'] as String?)?.trim() ?? '',
          'type': firebaseData['type'] ?? 'expense',
          'icon_code_point': firebaseData['iconCodePoint'],
          'sub_categories': jsonEncode(firebaseData['subCategories'] ?? {}),
          'ownership_type': firebaseData['ownershipType'] ?? 'personal',
          'is_archived': (firebaseData['isArchived'] ?? false) ? 1 : 0,
          'usage_count': firebaseData['usageCount'] ?? 0,
          'last_used': firebaseData['lastUsed'],
          'sync_status': 1, // Synced
          'version': firebaseData['version'] ?? 1,
          'updated_at':
              firebaseData['updatedAt'] ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'firebase_id = ? OR id = ?',
        whereArgs: [firebaseId, firebaseData['id']],
      );

      debugPrint('✅ Updated category from Firebase: ${firebaseData['name']}');
    } catch (e) {
      debugPrint('❌ Error updating category from Firebase ($firebaseId): $e');
    }
  }

  /// ✅ NEW: Insert budget from Firebase with validation
  Future<void> _insertBudgetFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    try {
      // Validate required fields
      final ownerId = (firebaseData['ownerId'] as String?)?.trim();
      final month = (firebaseData['month'] as String?)?.trim();

      // Skip invalid data
      if (ownerId == null ||
          ownerId.isEmpty ||
          month == null ||
          month.isEmpty) {
        debugPrint('⚠️ Skipping invalid budget from Firebase: $firebaseId');
        return;
      }

      await txn.insert('budgets', {
        'id': firebaseData['id'] ?? firebaseId,
        'firebase_id': firebaseId,
        'owner_id': ownerId,
        'month': month,
        'total_amount': (firebaseData['totalAmount'] ?? 0).toDouble(),
        'category_amounts': jsonEncode(firebaseData['categoryAmounts'] ?? {}),
        'budget_type': firebaseData['budgetType'] ?? 'personal',
        'period': firebaseData['period'] ?? 'monthly',
        'start_date': firebaseData['startDate'],
        'end_date': firebaseData['endDate'],
        'created_by': firebaseData['createdBy'],
        'is_active': firebaseData['isActive'] == true ? 1 : 0,
        'is_deleted': firebaseData['isDeleted'] == true ? 1 : 0,
        'notes': firebaseData['notes'] != null
            ? jsonEncode(firebaseData['notes'])
            : null,
        'category_limits': firebaseData['categoryLimits'] != null
            ? jsonEncode(firebaseData['categoryLimits'])
            : null,
        'sync_status': 1, // Synced
        'version': firebaseData['version'] ?? 1,
        'created_at':
            firebaseData['createdAt'] ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'updated_at':
            firebaseData['updatedAt'] ??
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      debugPrint('✅ Inserted budget from Firebase: $month');
    } catch (e) {
      debugPrint('❌ Error inserting budget from Firebase ($firebaseId): $e');
    }
  }

  /// ✅ NEW: Update budget from Firebase
  Future<void> _updateBudgetFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    try {
      await txn.update(
        'budgets',
        {
          'owner_id': (firebaseData['ownerId'] as String?)?.trim() ?? '',
          'month': (firebaseData['month'] as String?)?.trim() ?? '',
          'total_amount': (firebaseData['totalAmount'] ?? 0).toDouble(),
          'category_amounts': jsonEncode(firebaseData['categoryAmounts'] ?? {}),
          'budget_type': firebaseData['budgetType'] ?? 'personal',
          'period': firebaseData['period'] ?? 'monthly',
          'start_date': firebaseData['startDate'],
          'end_date': firebaseData['endDate'],
          'is_active': firebaseData['isActive'] == true ? 1 : 0,
          'is_deleted': firebaseData['isDeleted'] == true ? 1 : 0,
          'notes': firebaseData['notes'] != null
              ? jsonEncode(firebaseData['notes'])
              : null,
          'category_limits': firebaseData['categoryLimits'] != null
              ? jsonEncode(firebaseData['categoryLimits'])
              : null,
          'sync_status': 1, // Synced
          'version': firebaseData['version'] ?? 1,
          'updated_at':
              firebaseData['updatedAt'] ??
              DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'firebase_id = ? OR id = ?',
        whereArgs: [firebaseId, firebaseData['id']],
      );

      debugPrint('✅ Updated budget from Firebase: ${firebaseData['month']}');
    } catch (e) {
      debugPrint('❌ Error updating budget from Firebase ($firebaseId): $e');
    }
  }

  // ============ ENHANCED OFFLINE QUEUE MANAGEMENT ============

  /// ✅ NEW: Priority sync for critical operations
  Future<void> _syncCriticalOperations() async {
    if (!isOnline) return;

    try {
      // Get high priority items first
      final criticalItems = await _localDatabase!.query(
        'sync_queue',
        where: 'processed_at IS NULL AND priority >= 2',
        orderBy: 'priority DESC, scheduled_at ASC',
        limit: 10,
      );

      for (final item in criticalItems) {
        try {
          await _processSyncItemEnhanced(item);

          await _localDatabase!.update(
            'sync_queue',
            {'processed_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
            where: 'id = ?',
            whereArgs: [item['id']],
          );

          debugPrint(
            '✅ Synced critical item: ${item['table_name']}/${item['record_id']}',
          );
        } catch (e) {
          await _handleSyncItemError(item, e);
          debugPrint(
            '❌ Failed to sync critical item: ${item['table_name']}/${item['record_id']} - $e',
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Error in critical sync: $e');
    }
  }

  /// ✅ ENHANCED: Process sync items with better error handling
  Future<void> _processSyncItemEnhanced(Map<String, dynamic> item) async {
    final tableName = item['table_name'] as String;
    final recordId = item['record_id'] as String;
    final operation = item['operation'] as String;
    final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;

    switch (tableName) {
      case 'transactions':
        await _syncTransactionToFirebase(recordId, operation, data);
        break;
      case 'wallets':
        await _syncWalletToFirebase(recordId, operation, data);
        break;
      case 'categories':
        await _syncCategoryToFirebase(recordId, operation, data);
        break;
      case 'budgets':
        await _syncBudgetToFirebase(recordId, operation, data);
        break;
      default:
        throw Exception('Unknown table: $tableName');
    }
  }

  /// ✅ NEW: Batch sync for better performance
  Future<void> _batchSyncOperations() async {
    if (!isOnline) return;

    try {
      // Group sync items by table and operation for batch processing
      final pendingItems = await _localDatabase!.query(
        'sync_queue',
        where: 'processed_at IS NULL',
        orderBy: 'table_name, operation, priority DESC',
        limit: 50,
      );

      final batchGroups = <String, List<Map<String, dynamic>>>{};

      for (final item in pendingItems) {
        final key = '${item['table_name']}_${item['operation']}';
        batchGroups[key] ??= [];
        batchGroups[key]!.add(item);
      }

      // Process each batch
      for (final entry in batchGroups.entries) {
        try {
          await _processBatchSync(entry.key, entry.value);

          // Mark all items in batch as processed
          final itemIds = entry.value.map((item) => item['id'] as int).toList();
          await _markBatchAsProcessed(itemIds);

          debugPrint(
            '✅ Processed batch: ${entry.key} (${entry.value.length} items)',
          );
        } catch (e) {
          debugPrint('❌ Batch sync failed: ${entry.key} - $e');

          // Handle individual items in failed batch
          for (final item in entry.value) {
            await _handleSyncItemError(item, e);
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Error in batch sync: $e');
    }
  }

  /// ✅ NEW: Process batch sync operations
  Future<void> _processBatchSync(
    String batchKey,
    List<Map<String, dynamic>> items,
  ) async {
    final parts = batchKey.split('_');
    final tableName = parts[0];
    final operation = parts[1];

    switch (tableName) {
      case 'categories':
        await _batchSyncCategories(items, operation);
        break;
      case 'budgets':
        await _batchSyncBudgets(items, operation);
        break;
      case 'transactions':
        // Process individually for transactions due to complexity
        for (final item in items) {
          await _processSyncItemEnhanced(item);
        }
        break;
      case 'wallets':
        // Process individually for wallets due to balance calculations
        for (final item in items) {
          await _processSyncItemEnhanced(item);
        }
        break;
      default:
        throw Exception('Unknown table for batch sync: $tableName');
    }
  }

  /// ✅ NEW: Batch sync categories
  Future<void> _batchSyncCategories(
    List<Map<String, dynamic>> items,
    String operation,
  ) async {
    final batchData = <String, Map<String, dynamic>>{};

    for (final item in items) {
      final recordId = item['record_id'] as String;
      final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;
      batchData[recordId] = {...data, 'updatedAt': ServerValue.timestamp};
    }

    // Use Firebase batch operations
    final batchRef = _firebaseRef.child('categories');
    await batchRef.update(batchData);

    // Update local sync status
    for (final item in items) {
      await _localDatabase!.update(
        'categories',
        {'sync_status': 1, 'firebase_id': item['record_id']},
        where: 'id = ?',
        whereArgs: [item['record_id']],
      );
    }
  }

  /// ✅ NEW: Batch sync budgets
  Future<void> _batchSyncBudgets(
    List<Map<String, dynamic>> items,
    String operation,
  ) async {
    final batchData = <String, Map<String, dynamic>>{};

    for (final item in items) {
      final recordId = item['record_id'] as String;
      final data = jsonDecode(item['data'] as String) as Map<String, dynamic>;
      batchData[recordId] = {...data, 'updatedAt': ServerValue.timestamp};
    }

    // Use Firebase batch operations
    final batchRef = _firebaseRef.child('budgets');
    await batchRef.update(batchData);

    // Update local sync status
    for (final item in items) {
      await _localDatabase!.update(
        'budgets',
        {'sync_status': 1, 'firebase_id': item['record_id']},
        where: 'id = ?',
        whereArgs: [item['record_id']],
      );
    }
  }

  /// ✅ NEW: Mark batch items as processed
  Future<void> _markBatchAsProcessed(List<int> itemIds) async {
    if (itemIds.isEmpty) return;

    final placeholders = itemIds.map((_) => '?').join(',');
    await _localDatabase!.update(
      'sync_queue',
      {'processed_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
      where: 'id IN ($placeholders)',
      whereArgs: itemIds,
    );
  }

  // ============ HELPER METHODS ============

  /// ✅ NEW: Helper to get current owner ID for categories
  String _getCurrentOwnerCategoryId(CategoryOwnershipType ownershipType) {
    if (ownershipType == CategoryOwnershipType.shared &&
        partnershipId != null) {
      return partnershipId!;
    }
    return currentUserId ?? '';
  }

  /// ✅ NEW: Validate category-budget relationships
  Future<void> _validateCategoryBudgetRelationships() async {
    try {
      final budgets = await getBudgets();

      for (final budget in budgets) {
        bool needsUpdate = false;
        final validCategoryAmounts = <String, double>{};

        for (final entry in budget.categoryAmounts.entries) {
          final categoryId = entry.key;
          final amount = entry.value;

          // Check if category still exists and is valid
          final category = await getCategoryById(categoryId);
          if (category != null &&
              !category.isArchived &&
              category.type == 'expense') {
            validCategoryAmounts[categoryId] = amount;
          } else {
            needsUpdate = true;
            debugPrint('⚠️ Removing invalid category from budget: $categoryId');
          }
        }

        if (needsUpdate && validCategoryAmounts.isNotEmpty) {
          final newTotal = validCategoryAmounts.values.fold(
            0.0,
            (sum, val) => sum + val,
          );
          final updatedBudget = budget.copyWith(
            categoryAmounts: validCategoryAmounts,
            totalAmount: newTotal,
            version: budget.version + 1,
            updatedAt: DateTime.now(),
          );

          await updateBudget(updatedBudget);
        } else if (needsUpdate && validCategoryAmounts.isEmpty) {
          // Delete budget if no valid categories remain
          await deleteBudget(budget.id);
        }
      }

      debugPrint('✅ Category-budget relationships validated');
    } catch (e) {
      debugPrint('❌ Error validating category-budget relationships: $e');
    }
  }

  Future<void> forceUploadAllLocalData() async {
    if (!_isOnline || _localDatabase == null || currentUserId == null) {
      throw Exception('Cannot sync: offline or not initialized');
    }

    debugPrint('🔄 Force uploading ALL local data to Firebase...');

    try {
      _isSyncing = true;
      _lastError = null;
      notifyListeners();

      // 1. Upload transactions
      await _forceUploadTransactions();

      // 2. Upload wallets
      await _forceUploadWallets();

      // 3. Upload categories
      await _forceUploadCategories();

      // 4. Upload budgets
      await _forceUploadBudgets();

      // 5. Update sync metadata
      _lastSyncTime = DateTime.now();
      await _updateSyncMetadata();

      debugPrint('✅ Force upload completed successfully');
    } catch (e) {
      _lastError = 'Force upload failed: $e';
      debugPrint('❌ Force upload failed: $e');
      rethrow;
    } finally {
      _isSyncing = false;
      await _updatePendingItemsCount();
      notifyListeners();
    }
  }

  /// ✅ NEW: Force upload all transactions
  Future<void> _forceUploadTransactions() async {
    try {
      debugPrint('📤 Force uploading transactions...');

      final transactions = await _localDatabase!.query(
        'transactions',
        where: 'user_id = ?',
        whereArgs: [currentUserId],
        orderBy: 'created_at ASC',
      );

      if (transactions.isEmpty) {
        debugPrint('ℹ️ No transactions to upload');
        return;
      }

      int uploadedCount = 0;
      final batchUpdates = <String, dynamic>{};

      for (final txnData in transactions) {
        final txnId = txnData['id'] as String;
        final firebaseId = txnData['firebase_id'] as String? ?? txnId;

        // Convert local data to Firebase format
        final firebaseData = _convertTransactionToFirebaseFormat(txnData);

        batchUpdates['transactions/$firebaseId'] = firebaseData;
        uploadedCount++;

        // Update local record with Firebase ID
        await _localDatabase!.update(
          'transactions',
          {
            'firebase_id': firebaseId,
            'sync_status': 1, // Synced
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [txnId],
        );
      }

      // Batch upload to Firebase
      if (batchUpdates.isNotEmpty) {
        await _firebaseRef.update(batchUpdates);
        debugPrint('✅ Uploaded $uploadedCount transactions');
      }
    } catch (e) {
      debugPrint('❌ Error force uploading transactions: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Force upload all wallets
  Future<void> _forceUploadWallets() async {
    try {
      debugPrint('📤 Force uploading wallets...');

      // Get user's wallets (personal + partnership)
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      if (partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, partnershipId!];
      }

      final wallets = await _localDatabase!.query(
        'wallets',
        where: whereClause,
        whereArgs: whereArgs,
      );

      if (wallets.isEmpty) {
        debugPrint('ℹ️ No wallets to upload');
        return;
      }

      int uploadedCount = 0;
      final batchUpdates = <String, dynamic>{};

      for (final walletData in wallets) {
        final walletId = walletData['id'] as String;
        final firebaseId = walletData['firebase_id'] as String? ?? walletId;

        // Convert local data to Firebase format
        final firebaseData = _convertWalletToFirebaseFormat(walletData);

        batchUpdates['wallets/$firebaseId'] = firebaseData;
        uploadedCount++;

        // Update local record
        await _localDatabase!.update(
          'wallets',
          {
            'firebase_id': firebaseId,
            'sync_status': 1, // Synced
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [walletId],
        );
      }

      // Batch upload to Firebase
      if (batchUpdates.isNotEmpty) {
        await _firebaseRef.update(batchUpdates);
        debugPrint('✅ Uploaded $uploadedCount wallets');
      }
    } catch (e) {
      debugPrint('❌ Error force uploading wallets: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Force upload all categories
  Future<void> _forceUploadCategories() async {
    try {
      debugPrint('📤 Force uploading categories...');

      // Get user's categories (personal + partnership)
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      if (partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, partnershipId!];
      }

      final categories = await _localDatabase!.query(
        'categories',
        where: whereClause,
        whereArgs: whereArgs,
      );

      if (categories.isEmpty) {
        debugPrint('ℹ️ No categories to upload');
        return;
      }

      int uploadedCount = 0;
      final batchUpdates = <String, dynamic>{};

      for (final categoryData in categories) {
        final categoryId = categoryData['id'] as String;
        final firebaseId = categoryData['firebase_id'] as String? ?? categoryId;

        // Convert local data to Firebase format
        final firebaseData = _convertCategoryToFirebaseFormat(categoryData);

        batchUpdates['categories/$firebaseId'] = firebaseData;
        uploadedCount++;

        // Update local record
        await _localDatabase!.update(
          'categories',
          {
            'firebase_id': firebaseId,
            'sync_status': 1, // Synced
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [categoryId],
        );
      }

      // Batch upload to Firebase
      if (batchUpdates.isNotEmpty) {
        await _firebaseRef.update(batchUpdates);
        debugPrint('✅ Uploaded $uploadedCount categories');
      }
    } catch (e) {
      debugPrint('❌ Error force uploading categories: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Force upload all budgets
  Future<void> _forceUploadBudgets() async {
    try {
      debugPrint('📤 Force uploading budgets...');

      // Get user's budgets (personal + partnership)
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      if (partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, partnershipId!];
      }

      final budgets = await _localDatabase!.query(
        'budgets',
        where: whereClause,
        whereArgs: whereArgs,
      );

      if (budgets.isEmpty) {
        debugPrint('ℹ️ No budgets to upload');
        return;
      }

      int uploadedCount = 0;
      final batchUpdates = <String, dynamic>{};

      for (final budgetData in budgets) {
        final budgetId = budgetData['id'] as String;
        final firebaseId = budgetData['firebase_id'] as String? ?? budgetId;

        // Convert local data to Firebase format
        final firebaseData = _convertBudgetToFirebaseFormat(budgetData);

        batchUpdates['budgets/$firebaseId'] = firebaseData;
        uploadedCount++;

        // Update local record
        await _localDatabase!.update(
          'budgets',
          {
            'firebase_id': firebaseId,
            'sync_status': 1, // Synced
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [budgetId],
        );
      }

      // Batch upload to Firebase
      if (batchUpdates.isNotEmpty) {
        await _firebaseRef.update(batchUpdates);
        debugPrint('✅ Uploaded $uploadedCount budgets');
      }
    } catch (e) {
      debugPrint('❌ Error force uploading budgets: $e');
      rethrow;
    }
  }

  // ============ DATA CONVERSION METHODS ============

  Map<String, dynamic> _convertTransactionToFirebaseFormat(
    Map<String, dynamic> localData,
  ) {
    return {
      'id': localData['id'],
      'amount': localData['amount'],
      'type': localData['type'],
      'categoryId': localData['category_id'],
      'walletId': localData['wallet_id'],
      'date': localData['date'],
      'description': localData['description'],
      'userId': localData['user_id'],
      'subCategoryId': localData['sub_category_id'],
      'transferToWalletId': localData['transfer_to_wallet_id'],
      'createdBy': localData['created_by'],
      'version': localData['version'] ?? 1,
      'createdAt': (localData['created_at'] as int?) != null
          ? localData['created_at'] *
                1000 // Convert to milliseconds
          : DateTime.now().millisecondsSinceEpoch,
      'updatedAt': ServerValue.timestamp,
    };
  }

  Map<String, dynamic> _convertWalletToFirebaseFormat(
    Map<String, dynamic> localData,
  ) {
    return {
      'id': localData['id'],
      'name': localData['name'],
      'balance': localData['balance'],
      'ownerId': localData['owner_id'],
      'isVisibleToPartner': (localData['is_visible_to_partner'] ?? 1) == 1,
      'type': localData['wallet_type'] ?? 'general',
      'currency': localData['currency'] ?? 'VND',
      'isArchived': (localData['is_archived'] ?? 0) == 1,
      'version': localData['version'] ?? 1,
      'createdAt': (localData['created_at'] as int?) != null
          ? localData['created_at'] * 1000
          : DateTime.now().millisecondsSinceEpoch,
      'updatedAt': ServerValue.timestamp,
    };
  }

  Map<String, dynamic> _convertCategoryToFirebaseFormat(
    Map<String, dynamic> localData,
  ) {
    Map<String, String> subCategories = {};
    try {
      final subCatsJson = localData['sub_categories'] as String?;
      if (subCatsJson != null && subCatsJson.isNotEmpty) {
        subCategories = Map<String, String>.from(jsonDecode(subCatsJson));
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing subcategories: $e');
    }

    return {
      'id': localData['id'],
      'name': localData['name'],
      'ownerId': localData['owner_id'],
      'type': localData['type'],
      'iconCodePoint': localData['icon_code_point'],
      'subCategories': subCategories,
      'ownershipType': localData['ownership_type'] ?? 'personal',
      'createdBy': localData['created_by'],
      'isArchived': (localData['is_archived'] ?? 0) == 1,
      'usageCount': localData['usage_count'] ?? 0,
      'lastUsed': localData['last_used'],
      'version': localData['version'] ?? 1,
      'createdAt': (localData['created_at'] as int?) != null
          ? localData['created_at'] * 1000
          : DateTime.now().millisecondsSinceEpoch,
      'updatedAt': ServerValue.timestamp,
    };
  }

  Map<String, dynamic> _convertBudgetToFirebaseFormat(
    Map<String, dynamic> localData,
  ) {
    Map<String, double> categoryAmounts = {};
    try {
      final categoryJson = localData['category_amounts'] as String?;
      if (categoryJson != null && categoryJson.isNotEmpty) {
        categoryAmounts = Map<String, double>.from(jsonDecode(categoryJson));
      }
    } catch (e) {
      debugPrint('⚠️ Error parsing category amounts: $e');
    }

    return {
      'id': localData['id'],
      'ownerId': localData['owner_id'],
      'month': localData['month'],
      'totalAmount': localData['total_amount'],
      'categoryAmounts': categoryAmounts,
      'budgetType': localData['budget_type'] ?? 'personal',
      'period': localData['period'] ?? 'monthly',
      'createdBy': localData['created_by'],
      'startDate': localData['start_date'],
      'endDate': localData['end_date'],
      'isActive': (localData['is_active'] ?? 1) == 1,
      'isDeleted': (localData['is_deleted'] ?? 0) == 1,
      'version': localData['version'] ?? 1,
      'createdAt': (localData['created_at'] as int?) != null
          ? localData['created_at'] * 1000
          : DateTime.now().millisecondsSinceEpoch,
      'updatedAt': ServerValue.timestamp,
    };
  }

  /// ✅ NEW: Check if Firebase has data for current user
  Future<bool> checkFirebaseHasUserData() async {
    if (!_isOnline || currentUserId == null) {
      return false;
    }

    try {
      // Check if user has any data in Firebase
      final checks = await Future.wait([
        _firebaseRef
            .child('transactions')
            .orderByChild('userId')
            .equalTo(currentUserId)
            .limitToFirst(1)
            .get(),
        _firebaseRef
            .child('wallets')
            .orderByChild('ownerId')
            .equalTo(currentUserId)
            .limitToFirst(1)
            .get(),
        _firebaseRef
            .child('categories')
            .orderByChild('ownerId')
            .equalTo(currentUserId)
            .limitToFirst(1)
            .get(),
      ]);

      final hasTransactions = checks[0].exists;
      final hasWallets = checks[1].exists;
      final hasCategories = checks[2].exists;

      debugPrint(
        'Firebase data check: transactions=$hasTransactions, wallets=$hasWallets, categories=$hasCategories',
      );

      return hasTransactions || hasWallets || hasCategories;
    } catch (e) {
      debugPrint('❌ Error checking Firebase data: $e');
      return false;
    }
  }

  /// ✅ ENHANCED: Smart sync that detects data state
  Future<void> performSmartSync() async {
    if (!_isOnline || currentUserId == null) {
      debugPrint('⚠️ Cannot perform smart sync: offline or no user');
      return;
    }

    try {
      debugPrint('🧠 Performing smart sync...');

      // 1. Check if Firebase has user data
      final firebaseHasData = await checkFirebaseHasUserData();

      // 2. Check if local database has data
      final localHasData = await _checkLocalHasUserData();

      debugPrint(
        'Smart sync analysis: Firebase=$firebaseHasData, Local=$localHasData',
      );

      if (!firebaseHasData && localHasData) {
        // Firebase is empty but local has data - force upload all local data
        debugPrint('🔄 Firebase empty, uploading all local data...');
        await forceUploadAllLocalData();
      } else if (firebaseHasData && !localHasData) {
        // Firebase has data but local is empty - download from Firebase
        debugPrint('🔄 Local empty, downloading from Firebase...');
        await _downloadChangesFromFirebase();
      } else if (firebaseHasData && localHasData) {
        // Both have data - perform normal sync
        debugPrint('🔄 Both have data, performing normal sync...');
        await _performIntelligentSync();
      } else {
        // Both are empty - nothing to sync
        debugPrint('ℹ️ Both Firebase and local are empty');
      }
    } catch (e) {
      debugPrint('❌ Error in smart sync: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Check if local database has user data
  Future<bool> _checkLocalHasUserData() async {
    if (_localDatabase == null || currentUserId == null) {
      return false;
    }

    try {
      final checks = await Future.wait([
        _localDatabase!.query(
          'transactions',
          where: 'user_id = ?',
          whereArgs: [currentUserId],
          limit: 1,
        ),
        _localDatabase!.query(
          'wallets',
          where: 'owner_id = ?',
          whereArgs: [currentUserId],
          limit: 1,
        ),
        _localDatabase!.query(
          'categories',
          where: 'owner_id = ?',
          whereArgs: [currentUserId],
          limit: 1,
        ),
      ]);

      final hasTransactions = checks[0].isNotEmpty;
      final hasWallets = checks[1].isNotEmpty;
      final hasCategories = checks[2].isNotEmpty;

      return hasTransactions || hasWallets || hasCategories;
    } catch (e) {
      debugPrint('❌ Error checking local data: $e');
      return false;
    }
  }

  // Addition to lib/data/services/data_service.dart - Data Deletion Methods

  // ============ DATA DELETION METHODS ============

  /// ✅ NEW: Delete all user data (both local and Firebase)
  Future<bool> deleteAllUserData({
    required String userId,
    String? partnershipId,
    Function(String message, double progress)? onProgress,
  }) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('DataService not initialized');
    }

    try {
      debugPrint('🗑️ Starting complete data deletion for user: $userId');
      onProgress?.call('Bắt đầu xóa dữ liệu...', 0.0);

      // Step 1: Delete from Firebase if online
      if (_isOnline) {
        await _deleteFirebaseUserData(userId, partnershipId, onProgress);
      } else {
        onProgress?.call('Chế độ offline - chỉ xóa local...', 0.3);
      }

      // Step 2: Delete all local data
      await _deleteAllLocalData(userId, partnershipId, onProgress);

      // Step 3: Clear sync queue
      await _clearSyncQueue();
      onProgress?.call('Dọn dẹp hoàn tất!', 1.0);

      debugPrint('✅ All user data deleted successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting all user data: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Delete user data from Firebase
  Future<void> _deleteFirebaseUserData(
    String userId,
    String? partnershipId,
    Function(String message, double progress)? onProgress,
  ) async {
    try {
      onProgress?.call('Xóa dữ liệu online...', 0.1);

      final Map<String, dynamic> updates = {};

      // Delete transactions
      onProgress?.call('Xóa giao dịch online...', 0.2);
      final transactionsSnapshot = await _firebaseRef
          .child('transactions')
          .orderByChild('userId')
          .equalTo(userId)
          .get();

      if (transactionsSnapshot.exists) {
        final transactions =
            transactionsSnapshot.value as Map<dynamic, dynamic>;
        for (final transactionId in transactions.keys) {
          updates['transactions/$transactionId'] = null;
        }
        debugPrint(
          '🗑️ Queued ${transactions.length} transactions for deletion',
        );
      }

      // Delete wallets (personal)
      onProgress?.call('Xóa ví cá nhân online...', 0.3);
      final walletsSnapshot = await _firebaseRef
          .child('wallets')
          .orderByChild('ownerId')
          .equalTo(userId)
          .get();

      if (walletsSnapshot.exists) {
        final wallets = walletsSnapshot.value as Map<dynamic, dynamic>;
        for (final walletId in wallets.keys) {
          updates['wallets/$walletId'] = null;
        }
        debugPrint(
          '🗑️ Queued ${wallets.length} personal wallets for deletion',
        );
      }

      // Delete categories (personal)
      onProgress?.call('Xóa danh mục cá nhân online...', 0.4);
      final categoriesSnapshot = await _firebaseRef
          .child('categories')
          .orderByChild('ownerId')
          .equalTo(userId)
          .get();

      if (categoriesSnapshot.exists) {
        final categories = categoriesSnapshot.value as Map<dynamic, dynamic>;
        for (final categoryId in categories.keys) {
          updates['categories/$categoryId'] = null;
        }
        debugPrint(
          '🗑️ Queued ${categories.length} personal categories for deletion',
        );
      }

      // Delete budgets (personal)
      onProgress?.call('Xóa ngân sách cá nhân online...', 0.5);
      final budgetsSnapshot = await _firebaseRef
          .child('budgets')
          .orderByChild('ownerId')
          .equalTo(userId)
          .get();

      if (budgetsSnapshot.exists) {
        final budgets = budgetsSnapshot.value as Map<dynamic, dynamic>;
        for (final budgetId in budgets.keys) {
          updates['budgets/$budgetId'] = null;
        }
        debugPrint(
          '🗑️ Queued ${budgets.length} personal budgets for deletion',
        );
      }

      // Delete shared data if partnership exists
      if (partnershipId != null) {
        await _deleteSharedFirebaseData(partnershipId, updates, onProgress);
      }

      // Delete user profile and related data
      onProgress?.call('Xóa thông tin tài khoản online...', 0.7);
      updates['users/$userId'] = null;
      updates['user_notifications/$userId'] = null;
      updates['user_refresh_triggers/$userId'] = null;

      // Execute all deletions in one batch
      if (updates.isNotEmpty) {
        onProgress?.call('Thực hiện xóa online...', 0.75);
        await _firebaseRef.update(updates);
        debugPrint('✅ Deleted ${updates.length} items from Firebase');
      }
    } catch (e) {
      debugPrint('❌ Error deleting Firebase data: $e');
      throw Exception('Failed to delete online data: $e');
    }
  }

  /// ✅ NEW: Delete shared data from Firebase
  Future<void> _deleteSharedFirebaseData(
    String partnershipId,
    Map<String, dynamic> updates,
    Function(String message, double progress)? onProgress,
  ) async {
    try {
      onProgress?.call('Xóa dữ liệu chung online...', 0.55);

      // Delete shared wallets
      final sharedWalletsSnapshot = await _firebaseRef
          .child('wallets')
          .orderByChild('ownerId')
          .equalTo(partnershipId)
          .get();

      if (sharedWalletsSnapshot.exists) {
        final sharedWallets =
            sharedWalletsSnapshot.value as Map<dynamic, dynamic>;
        for (final walletId in sharedWallets.keys) {
          updates['wallets/$walletId'] = null;
        }
        debugPrint(
          '🗑️ Queued ${sharedWallets.length} shared wallets for deletion',
        );
      }

      // Delete shared categories
      final sharedCategoriesSnapshot = await _firebaseRef
          .child('categories')
          .orderByChild('ownerId')
          .equalTo(partnershipId)
          .get();

      if (sharedCategoriesSnapshot.exists) {
        final sharedCategories =
            sharedCategoriesSnapshot.value as Map<dynamic, dynamic>;
        for (final categoryId in sharedCategories.keys) {
          updates['categories/$categoryId'] = null;
        }
        debugPrint(
          '🗑️ Queued ${sharedCategories.length} shared categories for deletion',
        );
      }

      // Delete shared budgets
      final sharedBudgetsSnapshot = await _firebaseRef
          .child('budgets')
          .orderByChild('ownerId')
          .equalTo(partnershipId)
          .get();

      if (sharedBudgetsSnapshot.exists) {
        final sharedBudgets =
            sharedBudgetsSnapshot.value as Map<dynamic, dynamic>;
        for (final budgetId in sharedBudgets.keys) {
          updates['budgets/$budgetId'] = null;
        }
        debugPrint(
          '🗑️ Queued ${sharedBudgets.length} shared budgets for deletion',
        );
      }

      // Delete partnership record
      updates['partnerships/$partnershipId'] = null;
    } catch (e) {
      debugPrint('❌ Error preparing shared data deletion: $e');
    }
  }

  /// ✅ NEW: Delete all local data from SQLite
  Future<void> _deleteAllLocalData(
    String userId,
    String? partnershipId,
    Function(String message, double progress)? onProgress,
  ) async {
    try {
      onProgress?.call('Xóa dữ liệu local...', 0.8);

      await _localDatabase!.transaction((txn) async {
        // Delete transactions
        onProgress?.call('Xóa giao dịch local...', 0.81);
        int deletedTransactions = await txn.delete(
          'transactions',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
        debugPrint('🗑️ Deleted $deletedTransactions local transactions');

        // Delete wallets (personal and shared)
        onProgress?.call('Xóa ví local...', 0.83);
        String walletWhereClause = 'owner_id = ?';
        List<dynamic> walletWhereArgs = [userId];

        if (partnershipId != null) {
          walletWhereClause = 'owner_id = ? OR owner_id = ?';
          walletWhereArgs = [userId, partnershipId];
        }

        int deletedWallets = await txn.delete(
          'wallets',
          where: walletWhereClause,
          whereArgs: walletWhereArgs,
        );
        debugPrint('🗑️ Deleted $deletedWallets local wallets');

        // Delete categories (personal and shared)
        onProgress?.call('Xóa danh mục local...', 0.85);
        int deletedCategories = await txn.delete(
          'categories',
          where: walletWhereClause, // Same logic as wallets
          whereArgs: walletWhereArgs,
        );
        debugPrint('🗑️ Deleted $deletedCategories local categories');

        // Delete budgets (personal and shared)
        onProgress?.call('Xóa ngân sách local...', 0.87);
        int deletedBudgets = await txn.delete(
          'budgets',
          where: walletWhereClause, // Same logic as wallets
          whereArgs: walletWhereArgs,
        );
        debugPrint('🗑️ Deleted $deletedBudgets local budgets');

        // Clear system metadata
        onProgress?.call('Dọn dẹp metadata...', 0.89);
        await txn.delete('system_metadata');
        debugPrint('🗑️ Cleared system metadata');
      });

      debugPrint('✅ All local data deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting local data: $e');
      throw Exception('Failed to delete local data: $e');
    }
  }

  /// ✅ NEW: Clear sync queue
  Future<void> _clearSyncQueue() async {
    try {
      if (_localDatabase != null) {
        int deletedItems = await _localDatabase!.delete('sync_queue');
        debugPrint('🗑️ Cleared $deletedItems items from sync queue');
      }
    } catch (e) {
      debugPrint('⚠️ Error clearing sync queue: $e');
    }
  }

  /// ✅ NEW: Reset DataService state
  Future<void> resetDataServiceState() async {
    try {
      debugPrint('🔄 Resetting DataService state...');

      // Clear cached data
      _clearAnalyticsCache();

      // Reset counters
      _pendingItems = 0;
      _lastSyncTime = null;
      _lastError = null;

      // Cancel active operations
      for (final completer in _activeSyncs.values) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      _activeSyncs.clear();

      // Reset sync timer
      _syncTimer?.cancel();
      if (_isOnline) {
        _startBackgroundServices();
      }

      // Notify listeners
      notifyListeners();

      debugPrint('✅ DataService state reset complete');
    } catch (e) {
      debugPrint('❌ Error resetting DataService state: $e');
    }
  }

  /// ✅ NEW: Clear analytics cache (if exists)
  void _clearAnalyticsCache() {
    try {
      // Clear any cached analytics data
      // Note: This method assumes there might be analytics caching in the future
      // For now, it's a placeholder that can be extended
      debugPrint('🧹 Analytics cache cleared (placeholder)');
    } catch (e) {
      debugPrint('⚠️ Error clearing analytics cache: $e');
    }
  }

  /// ✅ NEW: Clear all caches and temporary data
  void clearAllCaches() {
    try {
      debugPrint('🧹 Clearing all caches...');

      // Clear analytics cache
      _clearAnalyticsCache();

      // Clear any other caches that might exist
      // This is extensible for future cache implementations

      debugPrint('✅ All caches cleared');
    } catch (e) {
      debugPrint('❌ Error clearing caches: $e');
    }
  }

  /// ✅ NEW: Get data deletion statistics (for debugging)
  Future<Map<String, dynamic>> getDataDeletionStats() async {
    if (!_isInitialized || _localDatabase == null) {
      return {};
    }

    try {
      final stats = <String, dynamic>{};

      // Count remaining local data
      final transactionsCount =
          Sqflite.firstIntValue(
            await _localDatabase!.rawQuery('SELECT COUNT(*) FROM transactions'),
          ) ??
          0;

      final walletsCount =
          Sqflite.firstIntValue(
            await _localDatabase!.rawQuery('SELECT COUNT(*) FROM wallets'),
          ) ??
          0;

      final categoriesCount =
          Sqflite.firstIntValue(
            await _localDatabase!.rawQuery('SELECT COUNT(*) FROM categories'),
          ) ??
          0;

      final budgetsCount =
          Sqflite.firstIntValue(
            await _localDatabase!.rawQuery('SELECT COUNT(*) FROM budgets'),
          ) ??
          0;

      final syncQueueCount =
          Sqflite.firstIntValue(
            await _localDatabase!.rawQuery('SELECT COUNT(*) FROM sync_queue'),
          ) ??
          0;

      stats['local_data'] = {
        'transactions': transactionsCount,
        'wallets': walletsCount,
        'categories': categoriesCount,
        'budgets': budgetsCount,
        'sync_queue': syncQueueCount,
        'total':
            transactionsCount + walletsCount + categoriesCount + budgetsCount,
      };

      stats['service_state'] = {
        'is_initialized': _isInitialized,
        'is_online': _isOnline,
        'is_syncing': _isSyncing,
        'pending_items': _pendingItems,
        'last_sync_time': _lastSyncTime?.toIso8601String(),
        'last_error': _lastError,
      };

      return stats;
    } catch (e) {
      debugPrint('❌ Error getting deletion stats: $e');
      return {'error': e.toString()};
    }
  }

  /// ✅ NEW: Force clear all local database tables (nuclear option)
  Future<void> forceNukeLocalDatabase() async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Database not available');
    }

    try {
      debugPrint('💥 NUCLEAR OPTION: Force clearing all local data...');

      await _localDatabase!.transaction((txn) async {
        // Get all table names
        final tables = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        );

        // Delete all data from each table
        for (final table in tables) {
          final tableName = table['name'] as String;
          try {
            int deletedRows = await txn.delete(tableName);
            debugPrint('💥 Nuked $deletedRows rows from $tableName');
          } catch (e) {
            debugPrint('⚠️ Could not nuke table $tableName: $e');
          }
        }
      });

      // Reset all counters
      _pendingItems = 0;
      _lastSyncTime = null;
      _lastError = null;

      notifyListeners();
      debugPrint('✅ Nuclear database clearing completed');
    } catch (e) {
      debugPrint('❌ Nuclear option failed: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Verify data deletion completion
  Future<bool> verifyDeletionComplete(
    String userId,
    String? partnershipId,
  ) async {
    try {
      final stats = await getDataDeletionStats();
      final localData = stats['local_data'] as Map<String, dynamic>? ?? {};
      final totalLocalItems = localData['total'] as int? ?? 0;

      if (totalLocalItems > 0) {
        debugPrint('⚠️ Deletion incomplete: $totalLocalItems items remaining');
        debugPrint('Remaining items: $localData');
        return false;
      }

      debugPrint('✅ Deletion verification: All local data cleared');
      return true;
    } catch (e) {
      debugPrint('❌ Error verifying deletion: $e');
      return false;
    }
  }

  /// ✅ NEW: Emergency data recovery check (in case user wants to undo)
  Future<Map<String, dynamic>> getRecoveryInfo() async {
    if (!_isInitialized || _localDatabase == null) {
      return {};
    }

    try {
      // Check if there's any data that could potentially be recovered
      final recoveryInfo = <String, dynamic>{};

      // Check sync queue for any pending uploads (data that might be lost)
      final pendingSyncItems = await _localDatabase!.query(
        'sync_queue',
        where: 'processed_at IS NULL',
      );

      recoveryInfo['pending_sync_items'] = pendingSyncItems.length;
      recoveryInfo['has_recoverable_data'] = pendingSyncItems.isNotEmpty;
      recoveryInfo['last_sync_time'] = _lastSyncTime?.toIso8601String();
      recoveryInfo['is_online'] = _isOnline;

      if (pendingSyncItems.isNotEmpty) {
        final syncTypes = <String, int>{};
        for (final item in pendingSyncItems) {
          final tableName = item['table_name'] as String;
          syncTypes[tableName] = (syncTypes[tableName] ?? 0) + 1;
        }
        recoveryInfo['pending_by_type'] = syncTypes;
      }

      return recoveryInfo;
    } catch (e) {
      debugPrint('❌ Error getting recovery info: $e');
      return {'error': e.toString()};
    }
  }

  /// ✅ NEW: Create a backup of critical data before deletion
  Future<Map<String, dynamic>> createDataBackup(
    String userId,
    String? partnershipId,
  ) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('DataService not initialized');
    }

    try {
      debugPrint('💾 Creating data backup before deletion...');
      final backup = <String, dynamic>{};

      // Backup transactions
      final transactions = await _localDatabase!.query(
        'transactions',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      backup['transactions'] = transactions;

      // Backup wallets
      String walletWhereClause = 'owner_id = ?';
      List<dynamic> walletWhereArgs = [userId];

      if (partnershipId != null) {
        walletWhereClause = 'owner_id = ? OR owner_id = ?';
        walletWhereArgs = [userId, partnershipId];
      }

      final wallets = await _localDatabase!.query(
        'wallets',
        where: walletWhereClause,
        whereArgs: walletWhereArgs,
      );
      backup['wallets'] = wallets;

      // Backup categories
      final categories = await _localDatabase!.query(
        'categories',
        where: walletWhereClause, // Same logic as wallets
        whereArgs: walletWhereArgs,
      );
      backup['categories'] = categories;

      // Backup budgets
      final budgets = await _localDatabase!.query(
        'budgets',
        where: walletWhereClause, // Same logic as wallets
        whereArgs: walletWhereArgs,
      );
      backup['budgets'] = budgets;

      // Add metadata
      backup['backup_info'] = {
        'created_at': DateTime.now().toIso8601String(),
        'user_id': userId,
        'partnership_id': partnershipId,
        'version': '1.0',
        'total_items':
            transactions.length +
            wallets.length +
            categories.length +
            budgets.length,
      };

      debugPrint(
        '💾 Backup created: ${backup['backup_info']['total_items']} items',
      );
      return backup;
    } catch (e) {
      debugPrint('❌ Error creating backup: $e');
      rethrow;
    }
  }

  /// ✅ NEW: Restore data from backup (if needed)
  Future<bool> restoreFromBackup(Map<String, dynamic> backup) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('DataService not initialized');
    }

    try {
      debugPrint('🔄 Restoring data from backup...');

      await _localDatabase!.transaction((txn) async {
        // Restore transactions
        final transactions = backup['transactions'] as List<dynamic>? ?? [];
        for (final transaction in transactions) {
          await txn.insert(
            'transactions',
            Map<String, dynamic>.from(transaction),
          );
        }

        // Restore wallets
        final wallets = backup['wallets'] as List<dynamic>? ?? [];
        for (final wallet in wallets) {
          await txn.insert('wallets', Map<String, dynamic>.from(wallet));
        }

        // Restore categories
        final categories = backup['categories'] as List<dynamic>? ?? [];
        for (final category in categories) {
          await txn.insert('categories', Map<String, dynamic>.from(category));
        }

        // Restore budgets
        final budgets = backup['budgets'] as List<dynamic>? ?? [];
        for (final budget in budgets) {
          await txn.insert('budgets', Map<String, dynamic>.from(budget));
        }
      });

      final backupInfo = backup['backup_info'] as Map<String, dynamic>? ?? {};
      final totalItems = backupInfo['total_items'] as int? ?? 0;

      debugPrint('✅ Restored $totalItems items from backup');
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('❌ Error restoring from backup: $e');
      return false;
    }
  }

  /// ✅ NEW: Get detailed deletion progress info
  Map<String, dynamic> getDeletionProgressInfo() {
    return {
      'is_online': _isOnline,
      'is_syncing': _isSyncing,
      'pending_items': _pendingItems,
      'last_sync_time': _lastSyncTime?.toIso8601String(),
      'last_error': _lastError,
      'active_syncs': _activeSyncs.length,
      'service_initialized': _isInitialized,
    };
  }

  /// ✅ NEW: Prepare for shutdown (cleanup before app closes)
  Future<void> prepareForShutdown() async {
    try {
      debugPrint('🔌 Preparing DataService for shutdown...');

      // Cancel all active operations
      _syncTimer?.cancel();
      _connectivitySubscription?.cancel();

      for (final completer in _activeSyncs.values) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }
      _activeSyncs.clear();

      // Close database connection
      await _localDatabase?.close();
      _localDatabase = null;

      _isInitialized = false;
      debugPrint('✅ DataService shutdown complete');
    } catch (e) {
      debugPrint('❌ Error during shutdown: $e');
    }
  }

  Future<void> updateWallet(Wallet wallet) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      debugPrint('📝 Updating wallet: ${wallet.name}');

      await _localDatabase!.transaction((txn) async {
        // Update wallet in local database
        await txn.update(
          'wallets',
          {
            'name': wallet.name,
            'balance': wallet.balance,
            'is_visible_to_partner': wallet.isVisibleToPartner ? 1 : 0,
            'wallet_type': wallet.type.name,
            'is_archived': wallet.isArchived ? 1 : 0,
            'sync_status': 0, // Mark as unsynced
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [wallet.id],
        );

        // Add to sync queue for online sync
        await _addToSyncQueue(
          txn,
          'wallets',
          wallet.id,
          'UPDATE',
          wallet.toJson(),
          priority: 2,
        );
      });

      // Try immediate sync if online
      if (_isOnline) {
        unawaited(_syncSingleRecord('wallets', wallet.id));
      }

      notifyListeners();
      debugPrint('✅ Wallet updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating wallet: $e');
      rethrow;
    }
  }

  /// Delete wallet with offline-first support (soft delete)
  Future<void> deleteWallet(String walletId) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      debugPrint('🗑️ Deleting wallet: $walletId');

      // Check if wallet has transactions
      final hasTransactions = await _checkWalletHasTransactions(walletId);
      if (hasTransactions) {
        throw Exception(
          'Không thể xóa ví đang có giao dịch. Vui lòng chuyển hoặc xóa các giao dịch trước.',
        );
      }

      await _localDatabase!.transaction((txn) async {
        // Soft delete by archiving
        await txn.update(
          'wallets',
          {
            'is_archived': 1,
            'sync_status': 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [walletId],
        );

        // Add to sync queue
        await _addToSyncQueue(txn, 'wallets', walletId, 'DELETE', {
          'id': walletId,
        }, priority: 2);
      });

      // Try immediate sync if online
      if (_isOnline) {
        unawaited(_syncSingleRecord('wallets', walletId));
      }

      notifyListeners();
      debugPrint('✅ Wallet deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting wallet: $e');
      rethrow;
    }
  }

  /// Check if wallet has transactions
  Future<bool> _checkWalletHasTransactions(String walletId) async {
    try {
      final result = await _localDatabase!.query(
        'transactions',
        where: 'wallet_id = ? OR transfer_to_wallet_id = ?',
        whereArgs: [walletId, walletId],
        limit: 1,
      );
      return result.isNotEmpty;
    } catch (e) {
      debugPrint('❌ Error checking wallet transactions: $e');
      return true; // Assume has transactions to be safe
    }
  }

  /// Archive wallet
  Future<void> archiveWallet(String walletId) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.transaction((txn) async {
        await txn.update(
          'wallets',
          {
            'is_archived': 1,
            'sync_status': 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [walletId],
        );

        await _addToSyncQueue(txn, 'wallets', walletId, 'UPDATE', {
          'isArchived': true,
        }, priority: 3);
      });

      if (_isOnline) {
        unawaited(_syncSingleRecord('wallets', walletId));
      }

      notifyListeners();
      debugPrint('✅ Wallet archived successfully');
    } catch (e) {
      debugPrint('❌ Error archiving wallet: $e');
      rethrow;
    }
  }

  /// Restore archived wallet
  Future<void> restoreWallet(String walletId) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.transaction((txn) async {
        await txn.update(
          'wallets',
          {
            'is_archived': 0,
            'sync_status': 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [walletId],
        );

        await _addToSyncQueue(txn, 'wallets', walletId, 'UPDATE', {
          'isArchived': false,
        }, priority: 3);
      });

      if (_isOnline) {
        unawaited(_syncSingleRecord('wallets', walletId));
      }

      notifyListeners();
      debugPrint('✅ Wallet restored successfully');
    } catch (e) {
      debugPrint('❌ Error restoring wallet: $e');
      rethrow;
    }
  }

  /// Get wallet by ID
  Future<Wallet?> getWalletById(String walletId) async {
    if (!_isInitialized || _localDatabase == null) return null;

    try {
      final result = await _localDatabase!.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (result.isNotEmpty) {
        return _walletFromMap(result.first);
      }
      return null;
    } catch (e) {
      debugPrint('❌ Error getting wallet by ID: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _localDatabase?.close();
    super.dispose();
  }
}

class ReportData {
  final double totalIncome;
  final double totalExpense;
  final double personalIncome;
  final double personalExpense;
  final double sharedIncome;
  final double sharedExpense;
  final Map<String, double> expenseByCategory; // Simplified to String keys
  final Map<String, double> incomeByCategory; // Simplified to String keys
  final List<TransactionModel> rawTransactions;

  ReportData({
    this.totalIncome = 0.0,
    this.totalExpense = 0.0,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.rawTransactions,
    this.personalIncome = 0.0,
    this.personalExpense = 0.0,
    this.sharedIncome = 0.0,
    this.sharedExpense = 0.0,
  });
}
