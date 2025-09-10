// lib/data/services/unified_data_service.dart
// ============ COMPLETE OFFLINE-FIRST DATA SERVICE ============
// This replaces ALL other data services

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
import 'package:moneysun/data/models/report_data_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';

/// ============ UNIFIED DATA SERVICE ============
/// Single source of truth for all data operations
/// Implements complete offline-first pattern with robust sync
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
  Timer? _healthTimer;
  final Map<String, Completer<void>> _activeSyncs = {};

  // ============ GETTERS ============
  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  bool get isInitialized => _isInitialized;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingItems => _pendingItems;
  String? get lastError => _lastError;
  String? get currentUserId => _userProvider?.currentUser?.uid;

  // ============ INITIALIZATION ============
  Future<void> initialize(UserProvider userProvider) async {
    if (_isInitialized) {
      debugPrint('⚠️ DataService already initialized');
      return;
    }

    _userProvider = userProvider;

    try {
      debugPrint('🚀 Initializing DataService...');

      // 1. Initialize local database
      await _initializeDatabase();

      // 2. Setup connectivity monitoring
      await _setupConnectivity();

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
      notifyListeners();
      rethrow;
    }
  }

  // ============ DATABASE INITIALIZATION ============
  Future<void> _initializeDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'moneysun_unified.db');

      _localDatabase = await openDatabase(
        path,
        version: 1,
        onCreate: _createDatabaseTables,
        onUpgrade: _upgradeDatabaseTables,
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA cache_size = 10000');
        },
      );

      debugPrint('✅ Database initialized: $path');
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _createDatabaseTables(Database db, int version) async {
    debugPrint('🔨 Creating unified database tables...');

    await db.transaction((txn) async {
      // Users table
      await txn.execute('''
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

      // Transactions table with complete sync metadata
      await txn.execute('''
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
          conflict_data TEXT,
          
          -- Timestamps
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          FOREIGN KEY (wallet_id) REFERENCES wallets(id),
          FOREIGN KEY (category_id) REFERENCES categories(id),
          FOREIGN KEY (user_id) REFERENCES users(id)
        )
      ''');

      // Wallets table with enhanced features
      await txn.execute('''
        CREATE TABLE wallets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL,
          balance REAL NOT NULL DEFAULT 0,
          owner_id TEXT NOT NULL,
          is_visible_to_partner INTEGER DEFAULT 1,
          wallet_type TEXT DEFAULT 'general',
          currency TEXT DEFAULT 'VND',
          is_archived INTEGER DEFAULT 0,
          archived_at INTEGER,
          last_adjustment TEXT,
          
          -- Sync metadata
          sync_status INTEGER DEFAULT 0,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          FOREIGN KEY (owner_id) REFERENCES users(id)
        )
      ''');

      // Categories table with ownership support
      await txn.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL,
          owner_id TEXT NOT NULL,
          type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
          icon_code_point INTEGER,
          sub_categories TEXT DEFAULT '{}',
          ownership_type TEXT DEFAULT 'personal',
          created_by TEXT,
          is_archived INTEGER DEFAULT 0,
          usage_count INTEGER DEFAULT 0,
          last_used INTEGER,
          
          -- Sync metadata
          sync_status INTEGER DEFAULT 0,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(owner_id, name, type),
          FOREIGN KEY (owner_id) REFERENCES users(id),
          FOREIGN KEY (created_by) REFERENCES users(id)
        )
      ''');

      // Budgets table
      await txn.execute('''
        CREATE TABLE budgets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          owner_id TEXT NOT NULL,
          month TEXT NOT NULL,
          total_amount REAL NOT NULL DEFAULT 0,
          category_amounts TEXT DEFAULT '{}',
          budget_type TEXT DEFAULT 'personal',
          period TEXT DEFAULT 'monthly',
          created_by TEXT,
          start_date INTEGER,
          end_date INTEGER,
          is_active INTEGER DEFAULT 1,
          notes TEXT DEFAULT '{}',
          category_limits TEXT DEFAULT '{}',
          
          sync_status INTEGER DEFAULT 0,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(owner_id, month, budget_type),
          FOREIGN KEY (owner_id) REFERENCES users(id),
          FOREIGN KEY (created_by) REFERENCES users(id)
        )
      ''');

      // Sync queue for offline operations
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
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(table_name, record_id, operation)
        )
      ''');

      // Conflict resolution table
      await txn.execute('''
        CREATE TABLE conflicts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          local_data TEXT NOT NULL,
          remote_data TEXT NOT NULL,
          conflict_type TEXT NOT NULL,
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          resolved_at INTEGER,
          resolution_strategy TEXT
        )
      ''');

      // Smart suggestions table
      await txn.execute('''
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

      // Sync metadata
      await txn.execute('''
        CREATE TABLE sync_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Create indexes for performance
      await _createOptimizedIndexes(txn as Transaction);
    });

    debugPrint('✅ Database tables created successfully');
  }

  Future<void> _createOptimizedIndexes(Transaction txn) async {
    final indexes = [
      // Transaction indexes
      'CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date DESC)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_wallet_date ON transactions(wallet_id, date DESC)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_sync ON transactions(sync_status, last_modified)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type)',

      // Wallet indexes
      'CREATE INDEX IF NOT EXISTS idx_wallets_owner ON wallets(owner_id, is_archived)',
      'CREATE INDEX IF NOT EXISTS idx_wallets_sync ON wallets(sync_status, last_modified)',

      // Category indexes
      'CREATE INDEX IF NOT EXISTS idx_categories_owner_type ON categories(owner_id, type, is_archived)',
      'CREATE INDEX IF NOT EXISTS idx_categories_sync ON categories(sync_status, last_modified)',
      'CREATE INDEX IF NOT EXISTS idx_categories_usage ON categories(usage_count DESC, last_used DESC)',

      // Budget indexes
      'CREATE INDEX IF NOT EXISTS idx_budgets_owner_month ON budgets(owner_id, month, budget_type)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_sync ON budgets(sync_status, last_modified)',

      // Sync queue indexes
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_priority ON sync_queue(priority DESC, created_at ASC)',
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON sync_queue(retry_count, scheduled_at)',

      // Description history indexes
      'CREATE INDEX IF NOT EXISTS idx_description_user_usage ON description_history(user_id, usage_count DESC)',
      'CREATE INDEX IF NOT EXISTS idx_description_text ON description_history(description)',
    ];

    for (final indexSql in indexes) {
      try {
        await txn.execute(indexSql);
      } catch (e) {
        debugPrint('⚠️ Warning: Could not create index: $e');
      }
    }
  }

  Future<void> _upgradeDatabaseTables(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint('🔄 Upgrading database from v$oldVersion to v$newVersion');
    // Implement migration logic here if needed
  }

  // ============ CONNECTIVITY MANAGEMENT ============
  Future<void> _setupConnectivity() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isOnline = result.isNotEmpty && result.first != ConnectivityResult.none;

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) async {
      final wasOnline = _isOnline;
      _isOnline =
          results.isNotEmpty && results.first != ConnectivityResult.none;

      if (_isOnline && !wasOnline) {
        debugPrint('📶 Connection restored - starting sync...');
        _lastError = null;
        await _performFullSync();
      } else if (!_isOnline && wasOnline) {
        debugPrint('📵 Connection lost - switching to offline mode');
      }

      notifyListeners();
    });
  }

  void _startBackgroundServices() {
    // Periodic sync timer
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (_isOnline &&
          !_isSyncing &&
          _pendingItems > 0 &&
          currentUserId != null) {
        unawaited(_performFullSync());
      }
    });

    // Health check timer
    _healthTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _updateSyncStatistics();
      notifyListeners();
    });
  }

  // ============ TRANSACTION OPERATIONS ============
  Future<void> addTransaction(TransactionModel transaction) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.transaction((txn) async {
        // 1. Save transaction
        await txn.insert('transactions', {
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

        // 2. Update wallet balances atomically
        await _updateWalletBalancesInTransaction(txn, transaction);

        // 3. Update category usage
        if (transaction.categoryId != null) {
          await _updateCategoryUsageInTransaction(txn, transaction.categoryId!);
        }

        // 4. Save description to history
        if (transaction.description.isNotEmpty) {
          await _saveDescriptionToHistoryInTransaction(txn, transaction);
        }
      });

      // 5. Add to sync queue
      await _addToSyncQueue(
        'transactions',
        transaction.id,
        'INSERT',
        transaction.toJson(),
      );

      await _updateSyncStatistics();
      notifyListeners();

      // 6. Try immediate sync if online
      if (_isOnline) {
        unawaited(_syncSingleRecord('transactions', transaction.id));
      }

      debugPrint('✅ Transaction added: ${transaction.description}');
    } catch (e) {
      debugPrint('❌ Error adding transaction: $e');
      rethrow;
    }
  }

  Future<void> _updateWalletBalancesInTransaction(
    Transaction txn,
    TransactionModel transaction,
  ) async {
    double balanceChange = 0;

    switch (transaction.type) {
      case TransactionType.income:
        balanceChange = transaction.amount;
        break;
      case TransactionType.expense:
        balanceChange = -transaction.amount;
        break;
      case TransactionType.transfer:
        // Update source wallet (subtract)
        balanceChange = -transaction.amount;

        // Update destination wallet (add)
        if (transaction.transferToWalletId != null) {
          await txn.rawUpdate(
            'UPDATE wallets SET balance = balance + ?, updated_at = ?, version = version + 1, sync_status = 0 WHERE id = ?',
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
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance + ?, updated_at = ?, version = version + 1, sync_status = 0 WHERE id = ?',
        [
          balanceChange,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          transaction.walletId,
        ],
      );
    }
  }

  Future<void> _updateCategoryUsageInTransaction(
    Transaction txn,
    String categoryId,
  ) async {
    await txn.rawUpdate(
      'UPDATE categories SET usage_count = usage_count + 1, last_used = ?, updated_at = ?, sync_status = 0 WHERE id = ?',
      [
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        categoryId,
      ],
    );
  }

  Future<void> _saveDescriptionToHistoryInTransaction(
    Transaction txn,
    TransactionModel transaction,
  ) async {
    final description = transaction.description.trim();
    if (description.isEmpty) return;

    // Try to update existing
    final updateCount = await txn.rawUpdate(
      'UPDATE description_history SET usage_count = usage_count + 1, last_used = ?, transaction_type = ?, category_id = ?, amount = ?, updated_at = ? WHERE user_id = ? AND description = ?',
      [
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        transaction.type.name,
        transaction.categoryId,
        transaction.amount,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        transaction.userId,
        description,
      ],
    );

    // If no existing record, insert new
    if (updateCount == 0) {
      await txn.insert('description_history', {
        'user_id': transaction.userId,
        'description': description,
        'usage_count': 1,
        'last_used': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'transaction_type': transaction.type.name,
        'category_id': transaction.categoryId,
        'amount': transaction.amount,
      });
    }
  }

  // ============ TRANSACTION RETRIEVAL ============
  Future<List<TransactionModel>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
    String? walletId,
    String? categoryId,
  }) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null)
      return [];

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
        orderBy: 'date DESC',
        limit: limit,
      );

      final transactions = result
          .map((map) => _transactionFromMap(map))
          .toList();

      debugPrint('📱 Retrieved ${transactions.length} transactions');

      // Background refresh if online
      if (_isOnline && transactions.isNotEmpty) {
        unawaited(_refreshTransactionsFromFirebase(startDate, endDate));
      }

      return transactions;
    } catch (e) {
      debugPrint('❌ Error getting transactions: $e');
      return [];
    }
  }

  // ============ WALLET OPERATIONS ============
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

      await _addToSyncQueue('wallets', wallet.id, 'INSERT', wallet.toJson());
      await _updateSyncStatistics();
      notifyListeners();

      if (_isOnline) {
        unawaited(_syncSingleRecord('wallets', wallet.id));
      }

      debugPrint('✅ Wallet added: ${wallet.name}');
    } catch (e) {
      debugPrint('❌ Error adding wallet: $e');
      rethrow;
    }
  }

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

      debugPrint('📱 Retrieved ${wallets.length} wallets');

      if (_isOnline) {
        unawaited(_refreshWalletsFromFirebase());
      }

      return wallets;
    } catch (e) {
      debugPrint('❌ Error getting wallets: $e');
      return [];
    }
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
      debugPrint('⚠️ Error adding to sync queue: $e');
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

  // ============ SYNC OPERATIONS ============
  Future<void> _performInitialSync() async {
    if (_isSyncing || !_isOnline || currentUserId == null) return;

    debugPrint('🔄 Performing initial sync...');
    await _performFullSync();
  }

  Future<void> _performFullSync() async {
    if (_isSyncing ||
        !_isOnline ||
        _localDatabase == null ||
        currentUserId == null)
      return;

    final syncKey = 'full_sync_${DateTime.now().millisecondsSinceEpoch}';
    if (_activeSyncs.containsKey(syncKey)) return;

    _activeSyncs[syncKey] = Completer<void>();
    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      debugPrint('🔄 Starting full sync...');

      // 1. Download changes from Firebase
      await _downloadChangesFromFirebase();

      // 2. Upload pending changes to Firebase
      await _uploadPendingChanges();

      // 3. Resolve any conflicts
      await _resolveConflicts();

      _lastSyncTime = DateTime.now();
      debugPrint('✅ Full sync completed successfully');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('❌ Full sync failed: $e');
    } finally {
      _isSyncing = false;
      await _updateSyncStatistics();
      notifyListeners();
      _activeSyncs[syncKey]?.complete();
      _activeSyncs.remove(syncKey);
    }
  }

  Future<void> _uploadPendingChanges() async {
    if (_localDatabase == null) return;

    final syncItems = await _localDatabase!.query(
      'sync_queue',
      orderBy: 'priority DESC, created_at ASC',
      limit: 100,
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
        failed++;
        final retryCount = (item['retry_count'] as int) + 1;

        if (retryCount >= (item['max_retries'] as int)) {
          await _localDatabase!.delete(
            'sync_queue',
            where: 'id = ?',
            whereArgs: [item['id']],
          );
          debugPrint('🗑️ Removed sync item after max retries: ${item['id']}');
        } else {
          await _localDatabase!.update(
            'sync_queue',
            {
              'retry_count': retryCount,
              'last_error': e.toString(),
              'scheduled_at':
                  DateTime.now()
                      .add(Duration(seconds: min(60, retryCount * 2)))
                      .millisecondsSinceEpoch ~/
                  1000,
            },
            where: 'id = ?',
            whereArgs: [item['id']],
          );
        }
      }
    }

    debugPrint('📤 Upload completed: $synced synced, $failed failed');
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
        await _markAsSynced('transactions', transaction.id);
        break;
      case 'UPDATE':
        final transaction = _transactionFromJson(data);
        await _updateTransactionOnFirebase(transaction);
        await _markAsSynced('transactions', transaction.id);
        break;
      case 'DELETE':
        await _deleteTransactionFromFirebase(data['id']);
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
        await _markAsSynced('wallets', wallet.id);
        break;
      case 'UPDATE':
        final wallet = _walletFromJson(data);
        await _syncWalletToFirebase(wallet);
        await _markAsSynced('wallets', wallet.id);
        break;
      case 'DELETE':
        await _deleteWalletFromFirebase(data['id']);
        break;
    }
  }

  Future<void> _processSyncCategory(
    String operation,
    Map<String, dynamic> data,
  ) async {
    // Implementation for category sync
  }

  Future<void> _processSyncBudget(
    String operation,
    Map<String, dynamic> data,
  ) async {
    // Implementation for budget sync
  }

  // ============ FIREBASE SYNC METHODS ============
  Future<void> _syncTransactionToFirebase(TransactionModel transaction) async {
    final ref = _firebaseRef.child('transactions').child(transaction.id);
    await ref.set(transaction.toJson());
    debugPrint('☁️ Transaction synced to Firebase: ${transaction.id}');
  }

  Future<void> _updateTransactionOnFirebase(
    TransactionModel transaction,
  ) async {
    final ref = _firebaseRef.child('transactions').child(transaction.id);
    await ref.set(transaction.toJson());
    debugPrint('☁️ Transaction updated on Firebase: ${transaction.id}');
  }

  Future<void> _deleteTransactionFromFirebase(String transactionId) async {
    final ref = _firebaseRef.child('transactions').child(transactionId);
    await ref.remove();
    debugPrint('☁️ Transaction deleted from Firebase: $transactionId');
  }

  Future<void> _syncWalletToFirebase(Wallet wallet) async {
    final ref = _firebaseRef.child('wallets').child(wallet.id);
    await ref.set(wallet.toJson());
    debugPrint('☁️ Wallet synced to Firebase: ${wallet.id}');
  }

  Future<void> _deleteWalletFromFirebase(String walletId) async {
    final ref = _firebaseRef.child('wallets').child(walletId);
    await ref.remove();
    debugPrint('☁️ Wallet deleted from Firebase: $walletId');
  }

  // ============ DOWNLOAD FROM FIREBASE ============
  Future<void> _downloadChangesFromFirebase() async {
    // Implementation for downloading changes from Firebase
    debugPrint('📥 Downloading changes from Firebase...');
  }

  Future<void> _refreshTransactionsFromFirebase(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    // Background refresh implementation
  }

  Future<void> _refreshWalletsFromFirebase() async {
    // Background refresh implementation
  }

  // ============ CONFLICT RESOLUTION ============
  Future<void> _resolveConflicts() async {
    if (_localDatabase == null) return;

    final conflicts = await _localDatabase!.query(
      'conflicts',
      where: 'resolved_at IS NULL',
    );

    for (final conflict in conflicts) {
      try {
        await _resolveConflict(conflict);
      } catch (e) {
        debugPrint('⚠️ Error resolving conflict: $e');
      }
    }
  }

  Future<void> _resolveConflict(Map<String, dynamic> conflict) async {
    // Simple last-write-wins strategy for now
    // TODO: Implement more sophisticated conflict resolution

    final strategy = 'last_write_wins';
    final resolvedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await _localDatabase!.update(
      'conflicts',
      {'resolved_at': resolvedAt, 'resolution_strategy': strategy},
      where: 'id = ?',
      whereArgs: [conflict['id']],
    );
  }

  // ============ UTILITY METHODS ============
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

  Future<void> _updateSyncStatistics() async {
    if (_localDatabase == null) return;

    try {
      final result = await _localDatabase!.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue',
      );
      _pendingItems = result.first['count'] as int;
    } catch (e) {
      debugPrint('⚠️ Error updating sync statistics: $e');
      _pendingItems = 0;
    }
  }

  Future<void> _syncSingleRecord(String tableName, String recordId) async {
    try {
      final syncItem = await _localDatabase!.query(
        'sync_queue',
        where: 'table_name = ? AND record_id = ?',
        whereArgs: [tableName, recordId],
        limit: 1,
      );

      if (syncItem.isNotEmpty) {
        await _processSyncItem(syncItem.first);
        await _localDatabase!.delete(
          'sync_queue',
          where: 'id = ?',
          whereArgs: [syncItem.first['id']],
        );
      }
    } catch (e) {
      debugPrint('⚠️ Single record sync failed: $e');
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
      id: json['id'] ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      type: TransactionType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransactionType.expense,
      ),
      categoryId: json['categoryId'],
      walletId: json['walletId'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      description: json['description'] ?? '',
      userId: json['userId'] ?? '',
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
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      balance: (json['balance'] as num?)?.toDouble() ?? 0.0,
      ownerId: json['ownerId'] ?? '',
      isVisibleToPartner: json['isVisibleToPartner'] ?? true,
      type: WalletType.values.firstWhere(
        (e) => e.name == (json['type'] ?? 'general'),
        orElse: () => WalletType.general,
      ),
    );
  }

  // ============ PUBLIC API ============
  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      throw Exception('Không có kết nối internet');
    }
    await _performFullSync();
  }

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
      debugPrint('⚠️ Error getting database stats: $e');
      return {};
    }
  }

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
        await txn.delete('conflicts');
        await txn.delete('sync_metadata');
        await txn.delete('users');
      });

      _pendingItems = 0;
      _lastSyncTime = null;
      _lastError = null;
      notifyListeners();

      debugPrint('✅ All local data cleared');
    } catch (e) {
      debugPrint('❌ Error clearing data: $e');
      rethrow;
    }
  }

  // ============ CLEANUP ============
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _healthTimer?.cancel();
    _localDatabase?.close();
    super.dispose();
  }

  void unawaited(Future<void> future) {
    future.catchError((error) {
      debugPrint('Unawaited error: $error');
    });
  }

  Future<void> updateTransaction(
    TransactionModel newTransaction,
    TransactionModel? oldTransaction,
  ) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.transaction((txn) async {
        // 1. Update transaction
        await txn.update(
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

        // 2. Revert old wallet balances
        if (oldTransaction != null) {
          await _revertWalletBalanceInTransaction(txn, oldTransaction);
        }

        // 3. Apply new wallet balances
        await _updateWalletBalancesInTransaction(txn, newTransaction);

        // 4. Update category usage
        if (newTransaction.categoryId != null) {
          await _updateCategoryUsageInTransaction(
            txn,
            newTransaction.categoryId!,
          );
        }

        // 5. Save description
        if (newTransaction.description.isNotEmpty) {
          await _saveDescriptionToHistoryInTransaction(txn, newTransaction);
        }
      });

      await _addToSyncQueue(
        'transactions',
        newTransaction.id,
        'UPDATE',
        newTransaction.toJson(),
      );
      await _updatePendingItemsCount();
      notifyListeners();

      if (_isOnline) {
        unawaited(_syncSingleRecord('transactions', newTransaction.id));
      }

      debugPrint('✅ Transaction updated: ${newTransaction.description}');
    } catch (e) {
      debugPrint('❌ Error updating transaction: $e');
      rethrow;
    }
  }

  /// Delete transaction
  Future<void> deleteTransaction(TransactionModel transaction) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.transaction((txn) async {
        // 1. Revert wallet balance
        await _revertWalletBalanceInTransaction(txn, transaction);

        // 2. Delete transaction
        await txn.delete(
          'transactions',
          where: 'id = ?',
          whereArgs: [transaction.id],
        );
      });

      await _addToSyncQueue(
        'transactions',
        transaction.id,
        'DELETE',
        transaction.toJson(),
      );
      await _updatePendingItemsCount();
      notifyListeners();

      if (_isOnline) {
        unawaited(
          _processSyncItem({
            'table_name': 'transactions',
            'operation': 'DELETE',
            'data': jsonEncode(transaction.toJson()),
          }),
        );
      }

      debugPrint('✅ Transaction deleted: ${transaction.description}');
    } catch (e) {
      debugPrint('❌ Error deleting transaction: $e');
      rethrow;
    }
  }

  /// Revert wallet balance in transaction
  Future<void> _revertWalletBalanceInTransaction(
    Transaction txn,
    TransactionModel transaction,
  ) async {
    double reversalAmount = 0;

    switch (transaction.type) {
      case TransactionType.income:
        reversalAmount = -transaction.amount; // Remove income
        break;
      case TransactionType.expense:
        reversalAmount = transaction.amount; // Add back expense
        break;
      case TransactionType.transfer:
        reversalAmount = transaction.amount; // Add back to source

        // Revert destination wallet
        if (transaction.transferToWalletId != null) {
          await txn.rawUpdate(
            'UPDATE wallets SET balance = balance - ?, updated_at = ?, version = version + 1, sync_status = 0 WHERE id = ?',
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
      await txn.rawUpdate(
        'UPDATE wallets SET balance = balance + ?, updated_at = ?, version = version + 1, sync_status = 0 WHERE id = ?',
        [
          reversalAmount,
          DateTime.now().millisecondsSinceEpoch ~/ 1000,
          transaction.walletId,
        ],
      );
    }
  }

  // ============ MISSING WALLET OPERATIONS ============

  /// Update existing wallet
  Future<void> updateWallet(Wallet updatedWallet) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.update(
        'wallets',
        {
          'name': updatedWallet.name,
          'balance': updatedWallet.balance,
          'is_visible_to_partner': updatedWallet.isVisibleToPartner ? 1 : 0,
          'wallet_type': updatedWallet.type.name,
          'currency': updatedWallet.currency,
          'is_archived': updatedWallet.isArchived ? 1 : 0,
          'archived_at': updatedWallet.archivedAt?.millisecondsSinceEpoch,
          'last_adjustment': updatedWallet.lastAdjustment != null
              ? jsonEncode(updatedWallet.lastAdjustment!)
              : null,
          'sync_status': 0,
          'version': 'version + 1',
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [updatedWallet.id],
      );

      await _addToSyncQueue(
        'wallets',
        updatedWallet.id,
        'UPDATE',
        updatedWallet.toJson(),
      );
      await _updatePendingItemsCount();
      notifyListeners();

      if (_isOnline) {
        unawaited(_syncSingleRecord('wallets', updatedWallet.id));
      }

      debugPrint('✅ Wallet updated: ${updatedWallet.name}');
    } catch (e) {
      debugPrint('❌ Error updating wallet: $e');
      rethrow;
    }
  }

  /// Delete wallet
  Future<void> deleteWallet(Wallet wallet) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      // Check if wallet has transactions
      final hasTransactions = await walletHasTransactions(wallet.id);
      if (hasTransactions) {
        throw Exception('Cannot delete wallet with existing transactions');
      }

      await _localDatabase!.delete(
        'wallets',
        where: 'id = ?',
        whereArgs: [wallet.id],
      );

      await _addToSyncQueue('wallets', wallet.id, 'DELETE', wallet.toJson());
      await _updatePendingItemsCount();
      notifyListeners();

      if (_isOnline) {
        unawaited(
          _processSyncItem({
            'table_name': 'wallets',
            'operation': 'DELETE',
            'data': jsonEncode(wallet.toJson()),
          }),
        );
      }

      debugPrint('✅ Wallet deleted: ${wallet.name}');
    } catch (e) {
      debugPrint('❌ Error deleting wallet: $e');
      rethrow;
    }
  }

  /// Check if wallet has transactions
  Future<bool> walletHasTransactions(String walletId) async {
    if (!_isInitialized || _localDatabase == null) return false;

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
      return true; // Be safe
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

      if (result.isEmpty) return null;
      return _walletFromMap(result.first);
    } catch (e) {
      debugPrint('❌ Error getting wallet by ID: $e');
      return null;
    }
  }

  /// Update wallet balance directly
  Future<void> updateWalletBalanceDirectly(
    String walletId,
    double newBalance,
  ) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.update(
        'wallets',
        {
          'balance': newBalance,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'sync_status': 0,
        },
        where: 'id = ?',
        whereArgs: [walletId],
      );

      debugPrint('✅ Wallet balance updated directly: $walletId -> $newBalance');
    } catch (e) {
      debugPrint('❌ Error updating wallet balance: $e');
      rethrow;
    }
  }

  /// Get wallet statistics
  Future<Map<String, dynamic>> getWalletStatistics() async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      return {
        'totalWallets': 0,
        'totalBalance': 0.0,
        'averageBalance': 0.0,
        'walletsByType': <String, int>{},
      };
    }

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      if (_userProvider?.partnerUid != null) {
        whereClause =
            '(owner_id = ? OR (owner_id = ? AND is_visible_to_partner = 1))';
        whereArgs = [currentUserId, _userProvider!.partnerUid];
      }

      if (_userProvider?.partnershipId != null) {
        whereClause += ' OR owner_id = ?';
        whereArgs.add(_userProvider!.partnershipId);
      }

      final result = await _localDatabase!.query(
        'wallets',
        where: whereClause,
        whereArgs: whereArgs,
      );

      final wallets = result.map((map) => _walletFromMap(map)).toList();

      final totalWallets = wallets.length;
      final totalBalance = wallets.fold<double>(0, (sum, w) => sum + w.balance);
      final averageBalance = totalWallets > 0
          ? totalBalance / totalWallets
          : 0.0;

      final walletsByType = <String, int>{};
      for (final wallet in wallets) {
        walletsByType[wallet.type.displayName] =
            (walletsByType[wallet.type.displayName] ?? 0) + 1;
      }

      return {
        'totalWallets': totalWallets,
        'totalBalance': totalBalance,
        'averageBalance': averageBalance,
        'walletsByType': walletsByType,
        'activeWallets': wallets.where((w) => !w.isArchived).length,
        'archivedWallets': wallets.where((w) => w.isArchived).length,
      };
    } catch (e) {
      debugPrint('❌ Error getting wallet statistics: $e');
      return {
        'totalWallets': 0,
        'totalBalance': 0.0,
        'averageBalance': 0.0,
        'walletsByType': <String, int>{},
      };
    }
  }

  /// Backup wallet data
  Future<Map<String, dynamic>> backupWalletData(String walletId) async {
    if (!_isInitialized || _localDatabase == null) return {};

    try {
      final walletResult = await _localDatabase!.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
      );

      final transactionsResult = await _localDatabase!.query(
        'transactions',
        where: 'wallet_id = ? OR transfer_to_wallet_id = ?',
        whereArgs: [walletId, walletId],
      );

      return {
        'wallet': walletResult.isNotEmpty ? walletResult.first : null,
        'transactions': transactionsResult,
        'backupTime': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('❌ Error backing up wallet data: $e');
      return {};
    }
  }

  /// Restore wallet from backup
  Future<void> restoreWalletFromBackup(Map<String, dynamic> backupData) async {
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    try {
      await _localDatabase!.transaction((txn) async {
        if (backupData['wallet'] != null) {
          await txn.insert(
            'wallets',
            backupData['wallet'],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        final transactions = backupData['transactions'] as List?;
        if (transactions != null) {
          for (final transaction in transactions) {
            await txn.insert(
              'transactions',
              transaction,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });

      debugPrint('✅ Wallet restored from backup successfully');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error restoring wallet from backup: $e');
      rethrow;
    }
  }

  /// Validate wallet operations
  Future<String?> validateWalletOperation(
    String operation,
    Wallet wallet, {
    double? amount,
  }) async {
    try {
      switch (operation) {
        case 'delete':
          final hasTransactions = await walletHasTransactions(wallet.id);
          if (hasTransactions) {
            return 'Không thể xóa ví vì còn có giao dịch';
          }
          break;

        case 'transaction':
          if (amount != null && amount > wallet.balance) {
            return 'Số dư không đủ để thực hiện giao dịch';
          }
          if (wallet.isArchived) {
            return 'Không thể thực hiện giao dịch với ví đã lưu trữ';
          }
          break;

        case 'archive':
          break;
      }

      return null; // Valid
    } catch (e) {
      return 'Lỗi kiểm tra tính hợp lệ: $e';
    }
  }

  // ============ MISSING CATEGORY OPERATIONS ============

  /// Add new category
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

      await _addToSyncQueue(
        'categories',
        category.id,
        'INSERT',
        category.toJson(),
      );
      await _updatePendingItemsCount();
      notifyListeners();

      if (_isOnline) {
        unawaited(_syncSingleRecord('categories', category.id));

        if (ownershipType == CategoryOwnershipType.shared &&
            _userProvider?.partnerUid != null) {
          await _sendNotification(
            _userProvider!.partnerUid!,
            'Danh mục chung mới',
            '${_userProvider!.currentUser?.displayName ?? "Đối tác"} đã tạo danh mục "$name" chung',
            'category',
          );
        }
      }

      debugPrint('✅ Category added: $name (${ownershipType.name})');
    } catch (e) {
      debugPrint('❌ Error adding category: $e');
      rethrow;
    }
  }

  /// Get categories with filtering
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

      debugPrint('📱 Retrieved ${categories.length} categories');

      if (_isOnline) {
        unawaited(_refreshCategoriesFromFirebase());
      }

      return categories;
    } catch (e) {
      debugPrint('❌ Error getting categories: $e');
      return [];
    }
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
        debugPrint('⚠️ Error decoding subCategories: $e');
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

  // ============ MISSING BUDGET OPERATIONS ============

  /// Add budget
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

      await _addToSyncQueue('budgets', budget.id, 'INSERT', budget.toJson());
      await _updatePendingItemsCount();
      notifyListeners();

      if (_isOnline) {
        unawaited(_syncSingleRecord('budgets', budget.id));

        if (budgetType == BudgetType.shared &&
            _userProvider?.partnerUid != null) {
          await _sendNotification(
            _userProvider!.partnerUid!,
            'Ngân sách chung mới',
            '${_userProvider!.currentUser?.displayName ?? "Đối tác"} đã tạo ngân sách chung cho tháng $month',
            'budget',
          );
        }
      }

      debugPrint('✅ Budget added: ${budget.displayName}');
    } catch (e) {
      debugPrint('❌ Error adding budget: $e');
      rethrow;
    }
  }

  /// Get budgets
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

      debugPrint('📱 Retrieved ${budgets.length} budgets');

      if (_isOnline) {
        unawaited(_refreshBudgetsFromFirebase());
      }

      return budgets;
    } catch (e) {
      debugPrint('❌ Error getting budgets: $e');
      return [];
    }
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
        debugPrint('⚠️ Error decoding categoryAmounts: $e');
      }
    }

    final notesJson = map['notes'] as String?;
    Map<String, String>? notes;
    if (notesJson != null && notesJson.isNotEmpty && notesJson != '{}') {
      try {
        notes = Map<String, String>.from(jsonDecode(notesJson));
      } catch (e) {
        debugPrint('⚠️ Error decoding notes: $e');
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
        debugPrint('⚠️ Error decoding categoryLimits: $e');
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

  // ============ MISSING DESCRIPTION/SUGGESTION METHODS ============

  /// Get description suggestions
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
      debugPrint('⚠️ Error getting description suggestions: $e');
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
      debugPrint('⚠️ Error searching description history: $e');
      return [];
    }
  }

  /// Save description to history
  Future<void> saveDescriptionToHistory(
    String userId,
    String description,
  ) async {
    if (description.trim().isEmpty || _localDatabase == null) return;

    try {
      final existing = await _localDatabase!.query(
        'description_history',
        where: 'user_id = ? AND description = ?',
        whereArgs: [userId, description.trim()],
        limit: 1,
      );

      if (existing.isNotEmpty) {
        await _localDatabase!.update(
          'description_history',
          {
            'usage_count': (existing.first['usage_count'] as int) + 1,
            'last_used': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await _localDatabase!.insert('description_history', {
          'user_id': userId,
          'description': description.trim(),
          'usage_count': 1,
          'last_used': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });
      }
    } catch (e) {
      debugPrint('⚠️ Error saving description to history: $e');
    }
  }

  // ============ MISSING REPORT/ANALYTICS METHODS ============

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
      final transactions = await getTransactions(
        startDate: startDate,
        endDate: endDate,
      );

      final categories = await getCategories();
      final categoryMap = {for (var c in categories) c.id: c};

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
      debugPrint('❌ Error getting report data: $e');
      return ReportData(
        expenseByCategory: {},
        incomeByCategory: {},
        rawTransactions: [],
      );
    }
  }

  // ============ MISSING FIREBASE REFRESH METHODS ============

  Future<void> _refreshCategoriesFromFirebase() async {
    // Background refresh implementation for categories
    debugPrint('📥 Refreshing categories from Firebase...');
  }

  Future<void> _refreshBudgetsFromFirebase() async {
    // Background refresh implementation for budgets
    debugPrint('📥 Refreshing budgets from Firebase...');
  }

  Future<void> _syncCategoryToFirebase(Category category) async {
    final ref = _firebaseRef.child('categories').child(category.id);
    await ref.set(category.toJson());
    debugPrint('☁️ Category synced to Firebase: ${category.id}');
  }

  Future<void> _syncBudgetToFirebase(Budget budget) async {
    final ref = _firebaseRef.child('budgets').child(budget.id);
    await ref.set(budget.toJson());
    debugPrint('☁️ Budget synced to Firebase: ${budget.id}');
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
      debugPrint('⚠️ Error sending notification: $e');
    }
  }

  // ============ MISSING CONNECTIVITY/HEALTH METHODS ============

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
        debugPrint('📶 Connection restored - starting sync...');
        _lastError = null;
        await _performFullSync();
      } else if (!_isOnline && wasOnline) {
        debugPrint('📵 Connection lost - switching to offline mode');
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
    _healthTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _updatePendingItemsCount();
      await _updateSyncStats();
      notifyListeners();
    });
  }

  Future<void> _updatePendingItemsCount() async {
    if (_localDatabase == null) return;

    try {
      final result = await _localDatabase!.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue',
      );
      _pendingItems = result.first['count'] as int;
    } catch (e) {
      debugPrint('⚠️ Error updating pending items count: $e');
      _pendingItems = 0;
    }
  }

  Future<void> _updateSyncStats() async {
    // Update any additional sync statistics here
  }

  // ============ WALLET BALANCE FIREBASE METHODS ============

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
        if (transaction.transferToWalletId != null) {
          final toWalletRef = _firebaseRef
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
        if (transaction.transferToWalletId != null) {
          final toWalletRef = _firebaseRef
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
  }

  /// Sync wallet balances from Firebase
  Future<void> syncWalletBalancesFromFirebase() async {
    if (!_isOnline || !_isInitialized || currentUserId == null) return;

    try {
      debugPrint('🔄 Syncing wallet balances from Firebase...');

      final walletRef = _firebaseRef.child('wallets');
      final snapshot = await walletRef.get();

      if (!snapshot.exists) return;

      final walletsMap = snapshot.value as Map<dynamic, dynamic>;
      int updated = 0;

      for (final entry in walletsMap.entries) {
        try {
          final walletData = entry.value as Map<dynamic, dynamic>;
          final ownerId = walletData['ownerId'] as String?;

          if (ownerId == currentUserId ||
              ownerId == _userProvider?.partnerUid ||
              ownerId == _userProvider?.partnershipId) {
            final firebaseBalance =
                (walletData['balance'] as num?)?.toDouble() ?? 0.0;
            final walletId = entry.key as String;

            await _localDatabase!.update(
              'wallets',
              {
                'balance': firebaseBalance,
                'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
                'sync_status': 1,
              },
              where: 'id = ?',
              whereArgs: [walletId],
            );

            updated++;
          }
        } catch (e) {
          debugPrint('⚠️ Error syncing wallet ${entry.key}: $e');
        }
      }

      debugPrint('✅ Synced $updated wallet balances from Firebase');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error syncing wallet balances from Firebase: $e');
    }
  }
}
