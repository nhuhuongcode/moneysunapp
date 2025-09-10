// lib/data/services/complete_dataservice.dart
// COMPLETE DATASERVICE IMPLEMENTATION - REPLACING DATABASE_SERVICE

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
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA cache_size = 20000');
          await db.execute('PRAGMA synchronous = NORMAL');
        },
      );

      debugPrint('✅ Database initialized: $path');
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow;
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
    // Update wallet balance trigger
    await txn.execute('''
      CREATE TRIGGER update_wallet_balance_insert 
      AFTER INSERT ON transactions
      BEGIN
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
        
        UPDATE wallets 
        SET 
          balance = balance + NEW.amount,
          updated_at = strftime('%s', 'now')
        WHERE id = NEW.transfer_to_wallet_id AND NEW.type = 'transfer';
      END
    ''');

    // Update category usage trigger
    await txn.execute('''
      CREATE TRIGGER update_category_usage 
      AFTER INSERT ON transactions
      WHEN NEW.category_id IS NOT NULL
      BEGIN
        UPDATE categories 
        SET 
          usage_count = usage_count + 1,
          last_used = strftime('%s', 'now')
        WHERE id = NEW.category_id;
      END
    ''');
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint('🔄 Upgrading database from v$oldVersion to v$newVersion');
    // Add migration logic here if needed
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
      // 1. Insert transaction
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
        'wallet_name': transaction.walletName,
        'category_name': transaction.categoryName,
        'sub_category_name': transaction.subCategoryName,
        'transfer_from_wallet_name': transaction.transferFromWalletName,
        'transfer_to_wallet_name': transaction.transferToWalletName,
        'sync_status': 0, // Unsynced
        'version': 1,
        'created_by': currentUserId,
      });

      // 2. Add to sync queue with high priority
      await _addToSyncQueue(
        txn,
        'transactions',
        transaction.id,
        'INSERT',
        transaction.toJson(),
        priority: 2,
      );
    });

    // 3. Try immediate sync if online
    if (_isOnline) {
      unawaited(_syncSingleRecord('transactions', transaction.id));
    }

    notifyListeners();
    debugPrint('✅ Transaction added: ${transaction.description}');
  }

  /// Get wallets with offline-first support
  Future<List<Wallet>> getWallets({bool includeArchived = false}) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include partnership wallets if user has partnership
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
    if (!_isInitialized || _localDatabase == null) {
      throw Exception('Service not initialized');
    }

    final walletId =
        'wallet_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    final finalOwnerId = ownerId ?? currentUserId!;

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
  }

  /// Get categories with offline-first support
  Future<List<Category>> getCategories({bool includeArchived = false}) async {
    if (!_isInitialized || _localDatabase == null || currentUserId == null) {
      return [];
    }

    try {
      String whereClause = 'owner_id = ?';
      List<dynamic> whereArgs = [currentUserId];

      // Include partnership categories if user has partnership
      if (partnershipId != null) {
        whereClause = '(owner_id = ? OR owner_id = ?)';
        whereArgs = [currentUserId, partnershipId!];
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

      return result.map((map) => _categoryFromMap(map)).toList();
    } catch (e) {
      debugPrint('❌ Error getting categories: $e');
      return [];
    }
  }

  // ============ STREAM METHODS FOR UI ============

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

  Future<void> _syncCategoryToFirebase(
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final categoryRef = _firebaseRef.child('categories').child(recordId);

    switch (operation) {
      case 'INSERT':
      case 'UPDATE':
        await categoryRef.set({...data, 'updatedAt': ServerValue.timestamp});
        break;
      case 'DELETE':
        await categoryRef.remove();
        break;
    }

    await _localDatabase!.update(
      'categories',
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

  Future<void> _downloadCategoriesFromFirebase(int? lastSyncTimestamp) async {
    try {
      Query query = _firebaseRef
          .child('categories')
          .orderByChild('ownerId')
          .equalTo(currentUserId);

      final snapshot = await query.get();
      if (!snapshot.exists) return;

      final categoriesMap = snapshot.value as Map<dynamic, dynamic>;

      await _localDatabase!.transaction((txn) async {
        for (final entry in categoriesMap.entries) {
          final firebaseId = entry.key as String;
          final firebaseData = entry.value as Map<dynamic, dynamic>;

          final localRecords = await txn.query(
            'categories',
            where: 'firebase_id = ? OR id = ?',
            whereArgs: [firebaseId, firebaseData['id']],
            limit: 1,
          );

          if (localRecords.isEmpty) {
            await _insertCategoryFromFirebase(txn, firebaseId, firebaseData);
          }
        }
      });

      debugPrint('✅ Downloaded categories from Firebase');
    } catch (e) {
      debugPrint('❌ Error downloading categories: $e');
    }
  }

  // ============ HELPER METHODS ============
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

  Future<void> _insertWalletFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    await txn.insert('wallets', {
      'id': firebaseData['id'] ?? firebaseId,
      'firebase_id': firebaseId,
      'name': firebaseData['name'] ?? '',
      'balance': (firebaseData['balance'] ?? 0).toDouble(),
      'owner_id': firebaseData['ownerId'] ?? '',
      'is_visible_to_partner': (firebaseData['isVisibleToPartner'] ?? true)
          ? 1
          : 0,
      'wallet_type': firebaseData['type'] ?? 'general',
      'sync_status': 1, // Synced
      'version': firebaseData['version'] ?? 1,
    });
  }

  Future<void> _insertCategoryFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    await txn.insert('categories', {
      'id': firebaseData['id'] ?? firebaseId,
      'firebase_id': firebaseId,
      'name': firebaseData['name'] ?? '',
      'owner_id': firebaseData['ownerId'] ?? '',
      'type': firebaseData['type'] ?? 'expense',
      'icon_code_point': firebaseData['iconCodePoint'],
      'sub_categories': jsonEncode(firebaseData['subCategories'] ?? {}),
      'ownership_type': firebaseData['ownershipType'] ?? 'personal',
      'created_by': firebaseData['createdBy'],
      'sync_status': 1, // Synced
      'version': firebaseData['version'] ?? 1,
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
    return Category(
      id: map['id'],
      name: map['name'],
      ownerId: map['owner_id'],
      type: map['type'],
      iconCodePoint: map['icon_code_point'],
      subCategories: map['sub_categories'] != null
          ? Map<String, String>.from(jsonDecode(map['sub_categories']))
          : {},
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == (map['ownership_type'] ?? 'personal'),
        orElse: () => CategoryOwnershipType.personal,
      ),
      createdBy: map['created_by'],
      usageCount: map['usage_count'] ?? 0,
      lastUsed: map['last_used'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_used'])
          : null,
    );
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

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _syncTimer?.cancel();
    _localDatabase?.close();
    super.dispose();
  }
}
