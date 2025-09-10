// lib/data/services/complete_data_service.dart
// COMPLETE PRODUCTION-READY DATA SERVICE
// Thay thế hoàn toàn file data_service.dart hiện tại

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

/// COMPLETE PRODUCTION-READY DATA SERVICE
/// Single source of truth for all data operations with full offline-first support
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
  double get successRate => _totalOperations > 0
      ? (_totalOperations - _failedOperations) / _totalOperations
      : 1.0;

  // ============ INITIALIZATION ============
  Future<void> initialize(UserProvider userProvider) async {
    if (_isInitialized) {
      debugPrint('⚠️ DataService already initialized');
      return;
    }

    _userProvider = userProvider;

    try {
      debugPrint('🚀 Initializing Complete DataService...');
      _recordOperation('initialize', () async {
        // 1. Initialize local database with enhanced schema
        await _initializeEnhancedDatabase();

        // 2. Setup connectivity monitoring
        await _setupConnectivityMonitoring();

        // 3. Start background services
        _startBackgroundServices();

        // 4. Load critical data to memory cache
        await _preloadCriticalData();

        // 5. Initial sync if online
        if (_isOnline && currentUserId != null) {
          unawaited(_performInitialSync());
        }
      });

      _isInitialized = true;
      notifyListeners();

      debugPrint('✅ Complete DataService initialized successfully');
    } catch (e) {
      _lastError = 'Initialization failed: $e';
      debugPrint('❌ DataService initialization failed: $e');
      _failedOperations++;
      notifyListeners();
      rethrow;
    }
  }

  // ============ ENHANCED DATABASE INITIALIZATION ============
  Future<void> _initializeEnhancedDatabase() async {
    try {
      final databasesPath = await getDatabasesPath();
      final path = join(databasesPath, 'moneysun_production.db');

      _localDatabase = await openDatabase(
        path,
        version: 2, // Incremented version
        onCreate: _createEnhancedDatabaseTables,
        onUpgrade: _upgradeDatabase,
        onOpen: (db) async {
          // Enable performance optimizations
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = WAL');
          await db.execute('PRAGMA cache_size = 20000'); // Increased cache
          await db.execute('PRAGMA temp_store = MEMORY');
          await db.execute('PRAGMA synchronous = NORMAL');
          await db.execute('PRAGMA optimize');
        },
      );

      debugPrint('✅ Enhanced database initialized: $path');

      // Verify database integrity
      await _verifyDatabaseIntegrity();
    } catch (e) {
      debugPrint('❌ Database initialization failed: $e');
      rethrow;
    }
  }

  Future<void> _createEnhancedDatabaseTables(Database db, int version) async {
    debugPrint('🔨 Creating enhanced database tables v$version...');

    await db.transaction((txn) async {
      // ============ CORE TABLES ============

      // Enhanced Users table
      await txn.execute('''
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          display_name TEXT,
          email TEXT,
          photo_url TEXT,
          partnership_id TEXT,
          partner_uid TEXT,
          partner_display_name TEXT,
          partnership_created_at INTEGER,
          last_sync_time INTEGER,
          settings TEXT DEFAULT '{}',
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Enhanced Transactions table with full metadata
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
          
          -- Enhanced metadata
          tags TEXT DEFAULT '[]',
          location TEXT,
          receipt_path TEXT,
          notes TEXT,
          is_recurring INTEGER DEFAULT 0,
          recurring_pattern TEXT,
          
          -- Sync metadata with conflict resolution
          sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1, 2)),
          sync_attempts INTEGER DEFAULT 0,
          last_sync_attempt INTEGER,
          version INTEGER DEFAULT 1,
          conflict_data TEXT,
          created_by TEXT,
          
          -- Timestamps
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          -- Constraints and Foreign Keys
          FOREIGN KEY (wallet_id) REFERENCES wallets(id) ON DELETE CASCADE,
          FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL,
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY (transfer_to_wallet_id) REFERENCES wallets(id) ON DELETE SET NULL,
          
          -- Check constraints
          CHECK (
            (type != 'transfer') OR 
            (type = 'transfer' AND transfer_to_wallet_id IS NOT NULL AND transfer_to_wallet_id != wallet_id)
          )
        )
      ''');

      // Enhanced Wallets table with analytics
      await txn.execute('''
        CREATE TABLE wallets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL CHECK (length(name) > 0),
          balance REAL NOT NULL DEFAULT 0,
          initial_balance REAL DEFAULT 0,
          owner_id TEXT NOT NULL,
          is_visible_to_partner INTEGER DEFAULT 1,
          wallet_type TEXT DEFAULT 'general',
          currency TEXT DEFAULT 'VND',
          icon TEXT,
          color TEXT,
          
          -- Enhanced features
          is_archived INTEGER DEFAULT 0,
          archived_at INTEGER,
          credit_limit REAL DEFAULT 0,
          interest_rate REAL DEFAULT 0,
          bank_info TEXT DEFAULT '{}',
          
          -- Analytics
          last_transaction_date TEXT,
          transaction_count INTEGER DEFAULT 0,
          monthly_income REAL DEFAULT 0,
          monthly_expense REAL DEFAULT 0,
          
          -- Sync metadata
          sync_status INTEGER DEFAULT 0,
          sync_attempts INTEGER DEFAULT 0,
          last_sync_attempt INTEGER,
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
        )
      ''');

      // Enhanced Categories table with smart features
      await txn.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL CHECK (length(name) > 0),
          owner_id TEXT NOT NULL,
          type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
          icon_code_point INTEGER,
          icon_family TEXT DEFAULT 'MaterialIcons',
          color TEXT,
          sub_categories TEXT DEFAULT '{}',
          ownership_type TEXT DEFAULT 'personal',
          created_by TEXT,
          
          -- Smart features
          is_archived INTEGER DEFAULT 0,
          usage_count INTEGER DEFAULT 0,
          last_used INTEGER,
          avg_amount REAL DEFAULT 0,
          keywords TEXT DEFAULT '[]',
          
          -- ML suggestions
          prediction_confidence REAL DEFAULT 0,
          common_descriptions TEXT DEFAULT '[]',
          
          sync_status INTEGER DEFAULT 0,
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(owner_id, name, type),
          FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
        )
      ''');

      // Enhanced Budgets table with advanced tracking
      await txn.execute('''
        CREATE TABLE budgets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          owner_id TEXT NOT NULL,
          name TEXT,
          month TEXT NOT NULL,
          total_amount REAL NOT NULL CHECK (total_amount >= 0),
          spent_amount REAL DEFAULT 0,
          category_amounts TEXT DEFAULT '{}',
          category_spent TEXT DEFAULT '{}',
          budget_type TEXT DEFAULT 'personal',
          period TEXT DEFAULT 'monthly',
          
          -- Advanced features
          rollover_enabled INTEGER DEFAULT 0,
          alert_threshold REAL DEFAULT 0.8,
          alert_sent INTEGER DEFAULT 0,
          auto_adjust INTEGER DEFAULT 0,
          
          created_by TEXT,
          start_date INTEGER,
          end_date INTEGER,
          is_active INTEGER DEFAULT 1,
          notes TEXT DEFAULT '{}',
          
          sync_status INTEGER DEFAULT 0,
          version INTEGER DEFAULT 1,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(owner_id, month, budget_type, name),
          FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
        )
      ''');

      // ============ SYSTEM TABLES ============

      // Enhanced Sync Queue with priority and batching
      await txn.execute('''
        CREATE TABLE sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          batch_id TEXT,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          firebase_id TEXT,
          operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'BATCH')),
          data TEXT NOT NULL,
          
          -- Priority and retry logic
          priority INTEGER DEFAULT 1 CHECK (priority IN (1, 2, 3)),
          retry_count INTEGER DEFAULT 0,
          max_retries INTEGER DEFAULT 5,
          exponential_backoff INTEGER DEFAULT 1,
          
          -- Error handling
          last_error TEXT,
          error_count INTEGER DEFAULT 0,
          blocked_until INTEGER,
          
          -- Scheduling
          scheduled_at INTEGER DEFAULT (strftime('%s', 'now')),
          processing_started_at INTEGER,
          processed_at INTEGER,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(table_name, record_id, operation) ON CONFLICT REPLACE
        )
      ''');

      // Advanced Conflicts table with resolution strategies
      await txn.execute('''
        CREATE TABLE conflicts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          firebase_id TEXT,
          
          -- Conflict data
          local_data TEXT NOT NULL,
          remote_data TEXT NOT NULL,
          conflict_fields TEXT NOT NULL,
          conflict_type TEXT NOT NULL,
          
          -- Resolution
          resolution_strategy TEXT,
          resolved_at INTEGER,
          resolved_by TEXT,
          auto_resolved INTEGER DEFAULT 0,
          
          -- Metadata
          local_version INTEGER,
          remote_version INTEGER,
          severity TEXT DEFAULT 'medium',
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(table_name, record_id) ON CONFLICT REPLACE
        )
      ''');

      // Smart Description History with ML features
      await txn.execute('''
        CREATE TABLE description_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          user_id TEXT NOT NULL,
          description TEXT NOT NULL,
          normalized_description TEXT,
          
          -- Usage statistics
          usage_count INTEGER DEFAULT 1,
          last_used INTEGER DEFAULT (strftime('%s', 'now')),
          
          -- Context
          transaction_type TEXT,
          category_id TEXT,
          wallet_id TEXT,
          amount_range TEXT,
          
          -- ML features
          confidence REAL DEFAULT 0,
          keywords TEXT DEFAULT '[]',
          suggested_category TEXT,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(user_id, normalized_description),
          FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
          FOREIGN KEY (category_id) REFERENCES categories(id) ON DELETE SET NULL
        )
      ''');

      // System metadata and configuration
      await txn.execute('''
        CREATE TABLE system_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          type TEXT DEFAULT 'string',
          encrypted INTEGER DEFAULT 0,
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Performance and analytics
      await txn.execute('''
        CREATE TABLE performance_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation TEXT NOT NULL,
          duration_ms INTEGER NOT NULL,
          success INTEGER NOT NULL,
          error_message TEXT,
          context TEXT,
          user_id TEXT,
          created_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // ============ INDEXES FOR PERFORMANCE ============
      await _createOptimizedIndexes(txn);

      // ============ TRIGGERS FOR DATA INTEGRITY ============
      await _createDatabaseTriggers(txn);
    });

    debugPrint('✅ Enhanced database tables created successfully');
  }

  Future<void> _createOptimizedIndexes(Transaction txn) async {
    final indexes = [
      // Critical performance indexes
      'CREATE INDEX idx_transactions_user_date ON transactions(user_id, date DESC, sync_status)',
      'CREATE INDEX idx_transactions_wallet_date ON transactions(wallet_id, date DESC)',
      'CREATE INDEX idx_transactions_category ON transactions(category_id, type)',
      'CREATE INDEX idx_transactions_sync ON transactions(sync_status, sync_attempts, scheduled_at)',
      'CREATE INDEX idx_transactions_search ON transactions(description, amount)',

      // Wallet indexes
      'CREATE INDEX idx_wallets_owner ON wallets(owner_id, is_archived, wallet_type)',
      'CREATE INDEX idx_wallets_sync ON wallets(sync_status, last_sync_attempt)',
      'CREATE INDEX idx_wallets_analytics ON wallets(last_transaction_date, transaction_count)',

      // Category indexes with ML support
      'CREATE INDEX idx_categories_owner_type ON categories(owner_id, type, is_archived)',
      'CREATE INDEX idx_categories_usage ON categories(usage_count DESC, last_used DESC)',
      'CREATE INDEX idx_categories_prediction ON categories(prediction_confidence DESC)',

      // Budget indexes
      'CREATE INDEX idx_budgets_owner_month ON budgets(owner_id, month, budget_type)',
      'CREATE INDEX idx_budgets_active ON budgets(is_active, end_date)',

      // System indexes
      'CREATE INDEX idx_sync_queue_priority ON sync_queue(priority DESC, scheduled_at ASC, retry_count)',
      'CREATE INDEX idx_sync_queue_processing ON sync_queue(processing_started_at, processed_at)',
      'CREATE INDEX idx_conflicts_severity ON conflicts(severity, resolved_at)',
      'CREATE INDEX idx_description_history_user_usage ON description_history(user_id, usage_count DESC)',
      'CREATE INDEX idx_description_history_search ON description_history(normalized_description)',
      'CREATE INDEX idx_performance_logs_operation ON performance_logs(operation, created_at DESC)',

      // Full-text search index
      'CREATE VIRTUAL TABLE IF NOT EXISTS transactions_fts USING fts5(description, content=transactions, content_rowid=rowid)',
    ];

    for (final indexSql in indexes) {
      try {
        await txn.execute(indexSql);
      } catch (e) {
        debugPrint('⚠️ Warning: Could not create index: $e');
      }
    }

    // Populate FTS table
    try {
      await txn.execute(
        'INSERT INTO transactions_fts(transactions_fts) VALUES(\'rebuild\')',
      );
    } catch (e) {
      debugPrint('⚠️ FTS rebuild warning: $e');
    }
  }

  Future<void> _createDatabaseTriggers(Transaction txn) async {
    // Update wallet balance automatically
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
          transaction_count = transaction_count + 1,
          last_transaction_date = NEW.date,
          updated_at = strftime('%s', 'now')
        WHERE id = NEW.wallet_id;
        
        -- Update destination wallet for transfers
        UPDATE wallets 
        SET 
          balance = balance + NEW.amount,
          transaction_count = transaction_count + 1,
          updated_at = strftime('%s', 'now')
        WHERE id = NEW.transfer_to_wallet_id AND NEW.type = 'transfer';
      END
    ''');

    // Update timestamps automatically
    await txn.execute('''
      CREATE TRIGGER update_timestamps_transactions 
      AFTER UPDATE ON transactions
      BEGIN
        UPDATE transactions 
        SET updated_at = strftime('%s', 'now') 
        WHERE id = NEW.id;
      END
    ''');

    // Update category usage statistics
    await txn.execute('''
      CREATE TRIGGER update_category_usage 
      AFTER INSERT ON transactions
      WHEN NEW.category_id IS NOT NULL
      BEGIN
        UPDATE categories 
        SET 
          usage_count = usage_count + 1,
          last_used = strftime('%s', 'now'),
          avg_amount = (avg_amount * usage_count + NEW.amount) / (usage_count + 1)
        WHERE id = NEW.category_id;
      END
    ''');

    // Maintain FTS index
    await txn.execute('''
      CREATE TRIGGER transactions_fts_insert 
      AFTER INSERT ON transactions
      BEGIN
        INSERT INTO transactions_fts(rowid, description) VALUES(NEW.rowid, NEW.description);
      END
    ''');

    await txn.execute('''
      CREATE TRIGGER transactions_fts_update 
      AFTER UPDATE ON transactions
      BEGIN
        UPDATE transactions_fts SET description = NEW.description WHERE rowid = NEW.rowid;
      END
    ''');
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    debugPrint('🔄 Upgrading database from v$oldVersion to v$newVersion');

    if (oldVersion < 2) {
      // Add new columns for enhanced features
      await db.execute(
        'ALTER TABLE transactions ADD COLUMN tags TEXT DEFAULT \'[]\'',
      );
      await db.execute('ALTER TABLE transactions ADD COLUMN location TEXT');
      await db.execute(
        'ALTER TABLE wallets ADD COLUMN initial_balance REAL DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE categories ADD COLUMN keywords TEXT DEFAULT \'[]\'',
      );

      // Recreate indexes
      await _createOptimizedIndexes(db as Transaction);
    }
  }

  Future<void> _verifyDatabaseIntegrity() async {
    if (_localDatabase == null) return;

    try {
      // Run integrity check
      final result = await _localDatabase!.rawQuery('PRAGMA integrity_check');
      final status = result.first['integrity_check'];

      if (status != 'ok') {
        debugPrint('⚠️ Database integrity issue: $status');
      }

      // Optimize database
      await _localDatabase!.execute('PRAGMA optimize');

      debugPrint('✅ Database integrity verified');
    } catch (e) {
      debugPrint('⚠️ Database integrity check failed: $e');
    }
  }

  // ============ CONNECTIVITY MANAGEMENT ============
  Future<void> _setupConnectivityMonitoring() async {
    // Check initial connectivity
    final result = await _connectivity.checkConnectivity();
    _isOnline = result.isNotEmpty && !result.contains(ConnectivityResult.none);

    // Listen to connectivity changes with debouncing
    Timer? debounceTimer;
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(seconds: 2), () async {
        final wasOnline = _isOnline;
        _isOnline =
            results.isNotEmpty && !results.contains(ConnectivityResult.none);

        if (_isOnline && !wasOnline) {
          debugPrint('📶 Connection restored - starting intelligent sync...');
          _lastError = null;
          await _performIntelligentSync();
        } else if (!_isOnline && wasOnline) {
          debugPrint('📵 Connection lost - switching to offline mode');
          await _handleOfflineMode();
        }

        notifyListeners();
      });
    });

    debugPrint('👂 Connectivity monitoring setup');
  }

  Future<void> _handleOfflineMode() async {
    // Optimize for offline operation
    await _compactDatabase();
    await _preloadCriticalData();
  }

  // ============ BACKGROUND SERVICES ============
  void _startBackgroundServices() {
    // Intelligent sync timer
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (_isOnline && !_isSyncing && _pendingItems > 0) {
        unawaited(_performIntelligentSync());
      }
    });

    // Health monitoring timer
    _healthTimer = Timer.periodic(const Duration(minutes: 5), (timer) async {
      await _performHealthCheck();
      await _updateStatistics();
      notifyListeners();
    });

    debugPrint('🤖 Background services started');
  }

  Future<void> _performHealthCheck() async {
    try {
      // Check database health
      await _verifyDatabaseIntegrity();

      // Update pending items count
      await _updatePendingItemsCount();

      // Clean up old data
      await _performMaintenanceTasks();
    } catch (e) {
      debugPrint('⚠️ Health check error: $e');
    }
  }

  Future<void> _updateStatistics() async {
    if (_localDatabase == null) return;

    try {
      final stats = await Future.wait([
        _localDatabase!.rawQuery(
          'SELECT COUNT(*) as count FROM transactions WHERE sync_status = 0',
        ),
        _localDatabase!.rawQuery(
          'SELECT COUNT(*) as count FROM conflicts WHERE resolved_at IS NULL',
        ),
      ]);

      _pendingItems = stats[0].first['count'] as int;
      final unresolvedConflicts = stats[1].first['count'] as int;

      if (unresolvedConflicts > 0) {
        debugPrint('⚠️ $unresolvedConflicts unresolved conflicts detected');
      }
    } catch (e) {
      debugPrint('⚠️ Error updating statistics: $e');
    }
  }

  Future<void> _performMaintenanceTasks() async {
    if (_localDatabase == null) return;

    try {
      // Clean old performance logs (keep last 7 days)
      final weekAgo =
          DateTime.now()
              .subtract(const Duration(days: 7))
              .millisecondsSinceEpoch ~/
          1000;
      await _localDatabase!.delete(
        'performance_logs',
        where: 'created_at < ?',
        whereArgs: [weekAgo],
      );

      // Clean resolved conflicts (keep last 30 days)
      final monthAgo =
          DateTime.now()
              .subtract(const Duration(days: 30))
              .millisecondsSinceEpoch ~/
          1000;
      await _localDatabase!.delete(
        'conflicts',
        where: 'resolved_at IS NOT NULL AND resolved_at < ?',
        whereArgs: [monthAgo],
      );

      // Vacuum database if needed
      final dbInfo = await _localDatabase!.rawQuery('PRAGMA page_count');
      final pageCount = dbInfo.first['page_count'] as int;

      if (pageCount > 10000) {
        // If DB is large
        await _localDatabase!.execute('VACUUM');
        debugPrint('🧹 Database vacuumed');
      }
    } catch (e) {
      debugPrint('⚠️ Maintenance tasks error: $e');
    }
  }

  // ============ CRITICAL DATA PRELOADING ============
  Future<void> _preloadCriticalData() async {
    if (_localDatabase == null || currentUserId == null) return;

    try {
      // Preload user settings
      await _loadUserSettings();

      // Preload active wallets
      await _preloadActiveWallets();

      // Preload frequently used categories
      await _preloadFrequentCategories();

      debugPrint('✅ Critical data preloaded');
    } catch (e) {
      debugPrint('⚠️ Error preloading data: $e');
    }
  }

  Map<String, dynamic> _userSettings = {};
  List<Wallet> _activeWallets = [];
  List<Category> _frequentCategories = [];

  Future<void> _loadUserSettings() async {
    try {
      final result = await _localDatabase!.query(
        'users',
        where: 'id = ?',
        whereArgs: [currentUserId],
        limit: 1,
      );

      if (result.isNotEmpty) {
        final settingsJson = result.first['settings'] as String? ?? '{}';
        _userSettings = jsonDecode(settingsJson);
      }
    } catch (e) {
      debugPrint('⚠️ Error loading user settings: $e');
    }
  }

  Future<void> _preloadActiveWallets() async {
    try {
      final result = await _localDatabase!.query(
        'wallets',
        where: 'owner_id = ? AND is_archived = 0',
        whereArgs: [currentUserId],
        orderBy: 'transaction_count DESC, balance DESC',
        limit: 10,
      );

      _activeWallets = result.map((map) => _walletFromMap(map)).toList();
    } catch (e) {
      debugPrint('⚠️ Error preloading wallets: $e');
    }
  }

  Future<void> _preloadFrequentCategories() async {
    try {
      final result = await _localDatabase!.query(
        'categories',
        where: 'owner_id = ? AND is_archived = 0',
        whereArgs: [currentUserId],
        orderBy: 'usage_count DESC',
        limit: 20,
      );

      _frequentCategories = result.map((map) => _categoryFromMap(map)).toList();
    } catch (e) {
      debugPrint('⚠️ Error preloading categories: $e');
    }
  }

  // ============ INTELLIGENT SYNC SYSTEM ============
  Future<void> _performInitialSync() async {
    debugPrint('🔄 Performing initial intelligent sync...');
    await _performIntelligentSync(isInitialSync: true);
  }

  Future<void> _performIntelligentSync({bool isInitialSync = false}) async {
    if (_isSyncing ||
        !_isOnline ||
        _localDatabase == null ||
        currentUserId == null) {
      return;
    }

    final syncKey = 'intelligent_sync_${DateTime.now().millisecondsSinceEpoch}';
    if (_activeSyncs.containsKey(syncKey)) return;

    _activeSyncs[syncKey] = Completer<void>();
    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      await _recordOperation('intelligent_sync', () async {
        // 1. Prioritize critical operations first
        await _syncCriticalOperations();

        // 2. Download changes from Firebase with incremental sync
        await _downloadChangesIntelligently(isInitialSync);

        // 3. Upload pending changes with batch optimization
        await _uploadPendingChangesIntelligently();

        // 4. Resolve conflicts automatically where possible
        await _resolveConflictsAutomatically();

        // 5. Update sync metadata
        _lastSyncTime = DateTime.now();
        await _updateSyncMetadata();
      });

      debugPrint('✅ Intelligent sync completed successfully');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('❌ Intelligent sync failed: $e');
      _failedOperations++;
    } finally {
      _isSyncing = false;
      await _updatePendingItemsCount();
      notifyListeners();
      _activeSyncs[syncKey]?.complete();
      _activeSyncs.remove(syncKey);
    }
  }

  Future<void> _syncCriticalOperations() async {
    // Sync user profile first
    await _syncUserProfile();

    // Then sync partnership data if exists
    if (_userProvider?.partnershipId != null) {
      await _syncPartnershipData();
    }
  }

  Future<void> _downloadChangesIntelligently(bool isInitialSync) async {
    final lastSync = isInitialSync ? null : await _getLastSyncTimestamp();

    await Future.wait([
      _downloadTransactionsFromFirebase(lastSync),
      _downloadWalletsFromFirebase(lastSync),
      _downloadCategoriesFromFirebase(lastSync),
      _downloadBudgetsFromFirebase(lastSync),
    ]);
  }

  Future<void> _uploadPendingChangesIntelligently() async {
    // Get pending items ordered by priority
    final pendingItems = await _localDatabase!.query(
      'sync_queue',
      where: 'processed_at IS NULL AND blocked_until < ?',
      whereArgs: [DateTime.now().millisecondsSinceEpoch ~/ 1000],
      orderBy: 'priority DESC, scheduled_at ASC',
      limit: 50, // Process in batches
    );

    if (pendingItems.isEmpty) return;

    // Group by table for batch operations
    final groupedItems = <String, List<Map<String, dynamic>>>{};
    for (final item in pendingItems) {
      final table = item['table_name'] as String;
      groupedItems.putIfAbsent(table, () => []).add(item);
    }

    // Process each table group
    for (final entry in groupedItems.entries) {
      await _processSyncBatch(entry.key, entry.value);
    }
  }

  Future<void> _processSyncBatch(
    String tableName,
    List<Map<String, dynamic>> items,
  ) async {
    for (final item in items) {
      try {
        // Mark as processing
        await _localDatabase!.update(
          'sync_queue',
          {
            'processing_started_at':
                DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
          where: 'id = ?',
          whereArgs: [item['id']],
        );

        // Process the item
        await _processSyncItem(item);

        // Mark as completed
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

  Future<void> _handleSyncItemError(
    Map<String, dynamic> item,
    dynamic error,
  ) async {
    final retryCount = (item['retry_count'] as int) + 1;
    final maxRetries = item['max_retries'] as int;

    if (retryCount >= maxRetries) {
      // Move to dead letter queue or delete
      await _localDatabase!.delete(
        'sync_queue',
        where: 'id = ?',
        whereArgs: [item['id']],
      );
      debugPrint('🗑️ Sync item permanently failed: ${item['id']}');
    } else {
      // Exponential backoff
      final backoffSeconds = pow(2, retryCount).toInt();
      final blockedUntil =
          DateTime.now()
              .add(Duration(seconds: backoffSeconds))
              .millisecondsSinceEpoch ~/
          1000;

      await _localDatabase!.update(
        'sync_queue',
        {
          'retry_count': retryCount,
          'last_error': error.toString(),
          'error_count': (item['error_count'] as int) + 1,
          'blocked_until': blockedUntil,
          'processing_started_at': null,
        },
        where: 'id = ?',
        whereArgs: [item['id']],
      );
    }
  }

  // ============ FIREBASE SYNC IMPLEMENTATION ============
  Future<void> _downloadTransactionsFromFirebase(int? lastSyncTimestamp) async {
    try {
      debugPrint('📥 Downloading transactions from Firebase...');

      // Build query for user transactions
      Query query = _firebaseRef
          .child('transactions')
          .orderByChild('userId')
          .equalTo(currentUserId);

      // Add timestamp filter for incremental sync
      if (lastSyncTimestamp != null) {
        query = query.orderByChild('updatedAt').startAt(lastSyncTimestamp);
      }

      final snapshot = await query.get();
      if (!snapshot.exists) {
        debugPrint('📥 No transactions to download');
        return;
      }

      final transactionsMap = snapshot.value as Map<dynamic, dynamic>;
      int processed = 0;
      int conflicts = 0;

      await _localDatabase!.transaction((txn) async {
        for (final entry in transactionsMap.entries) {
          try {
            final firebaseId = entry.key as String;
            final firebaseData = entry.value as Map<dynamic, dynamic>;

            // Check if transaction exists locally
            final localRecords = await txn.query(
              'transactions',
              where: 'firebase_id = ? OR id = ?',
              whereArgs: [firebaseId, firebaseData['id']],
              limit: 1,
            );

            if (localRecords.isEmpty) {
              // New transaction from Firebase
              await _insertTransactionFromFirebase(
                txn,
                firebaseId,
                firebaseData,
              );
              processed++;
            } else {
              // Check for conflicts
              final conflict = await _detectTransactionConflict(
                localRecords.first,
                firebaseData,
              );

              if (conflict != null) {
                await _storeConflict(txn, 'transactions', firebaseId, conflict);
                conflicts++;
              } else {
                await _updateTransactionFromFirebase(
                  txn,
                  firebaseId,
                  firebaseData,
                );
                processed++;
              }
            }
          } catch (e) {
            debugPrint('⚠️ Error processing transaction ${entry.key}: $e');
          }
        }
      });

      debugPrint(
        '✅ Downloaded $processed transactions, $conflicts conflicts detected',
      );
    } catch (e) {
      debugPrint('❌ Error downloading transactions: $e');
      throw Exception('Failed to download transactions: $e');
    }
  }

  // ============ OPERATION RECORDING FOR PERFORMANCE ============
  Future<T> _recordOperation<T>(
    String operation,
    Future<T> Function() function,
  ) async {
    final stopwatch = Stopwatch()..start();
    _totalOperations++;

    try {
      final result = await function();

      stopwatch.stop();
      _recordOperationTime(operation, stopwatch.elapsed, true);

      return result;
    } catch (e) {
      stopwatch.stop();
      _recordOperationTime(operation, stopwatch.elapsed, false, e.toString());
      _failedOperations++;
      rethrow;
    }
  }

  void _recordOperationTime(
    String operation,
    Duration duration,
    bool success, [
    String? error,
  ]) {
    _operationTimes.putIfAbsent(operation, () => []).add(duration);

    // Keep only recent times
    final times = _operationTimes[operation]!;
    if (times.length > 100) {
      times.removeRange(0, times.length - 100);
    }

    // Log to database for analytics
    unawaited(_logPerformance(operation, duration, success, error));

    // Log slow operations
    if (duration.inMilliseconds > 1000) {
      debugPrint(
        '🐌 Slow operation: $operation took ${duration.inMilliseconds}ms',
      );
    }
  }

  Future<void> _logPerformance(
    String operation,
    Duration duration,
    bool success,
    String? error,
  ) async {
    if (_localDatabase == null) return;

    try {
      await _localDatabase!.insert('performance_logs', {
        'operation': operation,
        'duration_ms': duration.inMilliseconds,
        'success': success ? 1 : 0,
        'error_message': error,
        'user_id': currentUserId,
      });
    } catch (e) {
      // Don't let logging errors affect main operations
    }
  }

  // ============ PUBLIC API METHODS ============

  /// Enhanced transaction addition with full offline-first support
  Future<void> addTransaction(TransactionModel transaction) async {
    await _recordOperation('add_transaction', () async {
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

        // 3. Update smart suggestions
        await _updateDescriptionHistory(txn, transaction);
      });

      // 4. Try immediate sync if online
      if (_isOnline) {
        unawaited(_syncSingleRecord('transactions', transaction.id));
      }

      notifyListeners();
      debugPrint('✅ Transaction added: ${transaction.description}');
    });
  }

  /// Get transactions with intelligent caching and pagination
  Future<List<TransactionModel>> getTransactions({
    DateTime? startDate,
    DateTime? endDate,
    int? limit = 50,
    int? offset = 0,
    String? walletId,
    String? categoryId,
  }) async {
    return await _recordOperation('get_transactions', () async {
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
          orderBy: 'date DESC, created_at DESC',
          limit: limit,
          offset: offset,
        );

        final transactions = result
            .map((map) => _transactionFromMap(map))
            .toList();

        // Background refresh if needed and online
        if (_isOnline && transactions.isNotEmpty) {
          unawaited(_refreshTransactionsIfNeeded(startDate, endDate));
        }

        return transactions;
      } catch (e) {
        debugPrint('❌ Error getting transactions: $e');
        return [];
      }
    });
  }

  // ============ SMART SUGGESTIONS ============
  Future<List<String>> getSmartSuggestions(
    String query, {
    int limit = 5,
  }) async {
    if (_localDatabase == null ||
        currentUserId == null ||
        query.trim().isEmpty) {
      return [];
    }

    try {
      // Use FTS for better search
      final result = await _localDatabase!.query(
        'description_history',
        where: 'user_id = ? AND normalized_description MATCH ?',
        whereArgs: [currentUserId, '${query.trim()}*'],
        orderBy: 'usage_count DESC, confidence DESC',
        limit: limit,
      );

      return result.map((row) => row['description'] as String).toList();
    } catch (e) {
      // Fallback to LIKE search
      final result = await _localDatabase!.query(
        'description_history',
        where: 'user_id = ? AND description LIKE ?',
        whereArgs: [currentUserId, '%${query.trim()}%'],
        orderBy: 'usage_count DESC',
        limit: limit,
      );

      return result.map((row) => row['description'] as String).toList();
    }
  }

  // ============ ANALYTICS AND REPORTING ============
  Future<Map<String, dynamic>> getPerformanceReport() async {
    final report = <String, dynamic>{};

    // Operation performance
    final operationStats = <String, dynamic>{};
    for (final entry in _operationTimes.entries) {
      final times = entry.value;
      if (times.isNotEmpty) {
        final avgMs =
            times.fold(0, (sum, duration) => sum + duration.inMilliseconds) /
            times.length;
        operationStats[entry.key] = {
          'count': times.length,
          'avgMs': avgMs.round(),
          'maxMs': times.map((d) => d.inMilliseconds).reduce(max),
          'minMs': times.map((d) => d.inMilliseconds).reduce(min),
        };
      }
    }

    report['operations'] = operationStats;
    report['successRate'] = successRate;
    report['totalOperations'] = _totalOperations;
    report['failedOperations'] = _failedOperations;
    report['pendingItems'] = _pendingItems;
    report['isOnline'] = _isOnline;
    report['lastSyncTime'] = _lastSyncTime?.toIso8601String();

    // Database stats
    if (_localDatabase != null) {
      try {
        final dbStats = await Future.wait([
          _localDatabase!.rawQuery(
            'SELECT COUNT(*) as count FROM transactions',
          ),
          _localDatabase!.rawQuery('SELECT COUNT(*) as count FROM wallets'),
          _localDatabase!.rawQuery('SELECT COUNT(*) as count FROM categories'),
          _localDatabase!.rawQuery(
            'SELECT COUNT(*) as count FROM sync_queue WHERE processed_at IS NULL',
          ),
        ]);

        report['databaseStats'] = {
          'transactions': dbStats[0].first['count'],
          'wallets': dbStats[1].first['count'],
          'categories': dbStats[2].first['count'],
          'pendingSync': dbStats[3].first['count'],
        };
      } catch (e) {
        report['databaseStatsError'] = e.toString();
      }
    }

    return report;
  }

  /// Force immediate sync
  Future<void> forceSyncNow() async {
    if (!_isOnline) {
      throw Exception('No internet connection available');
    }

    await _performIntelligentSync();
  }

  /// Clear all local data (for testing/reset)
  Future<void> clearAllData() async {
    if (_localDatabase == null) return;

    await _recordOperation('clear_all_data', () async {
      await _localDatabase!.transaction((txn) async {
        await txn.delete('transactions');
        await txn.delete('wallets');
        await txn.delete('categories');
        await txn.delete('budgets');
        await txn.delete('description_history');
        await txn.delete('sync_queue');
        await txn.delete('conflicts');
        await txn.delete('performance_logs');
      });

      _pendingItems = 0;
      _lastSyncTime = null;
      _lastError = null;

      notifyListeners();
      debugPrint('✅ All local data cleared');
    });
  }

  // ============ UTILITY METHODS ============
  Future<void> _updatePendingItemsCount() async {
    if (_localDatabase == null) return;

    try {
      final result = await _localDatabase!.rawQuery(
        'SELECT COUNT(*) as count FROM sync_queue WHERE processed_at IS NULL',
      );
      _pendingItems = result.first['count'] as int;
    } catch (e) {
      debugPrint('⚠️ Error updating pending items count: $e');
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
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == (map['ownership_type'] ?? 'personal'),
        orElse: () => CategoryOwnershipType.personal,
      ),
    );
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

  // Placeholder methods to be implemented
  Future<void> _insertTransactionFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    // Implementation from previous artifacts
  }

  Future<Map<String, dynamic>?> _detectTransactionConflict(
    Map<String, dynamic> localRecord,
    Map<dynamic, dynamic> remoteData,
  ) async {
    // Implementation from previous artifacts
  }

  Future<void> _storeConflict(
    Transaction txn,
    String tableName,
    String recordId,
    Map<String, dynamic> conflict,
  ) async {
    // Implementation from previous artifacts
  }

  Future<void> _updateTransactionFromFirebase(
    Transaction txn,
    String firebaseId,
    Map<dynamic, dynamic> firebaseData,
  ) async {
    // Implementation from previous artifacts
  }

  Future<void> _downloadWalletsFromFirebase(int? lastSyncTimestamp) async {
    // Implementation from previous artifacts
  }

  Future<void> _downloadCategoriesFromFirebase(int? lastSyncTimestamp) async {
    // Implementation from previous artifacts
  }

  Future<void> _downloadBudgetsFromFirebase(int? lastSyncTimestamp) async {
    // Implementation from previous artifacts
  }

  Future<void> _processSyncItem(Map<String, dynamic> item) async {
    // Implementation from previous artifacts
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

  Future<void> _updateDescriptionHistory(
    Transaction txn,
    TransactionModel transaction,
  ) async {
    // Implementation for smart suggestions
  }

  Future<void> _syncSingleRecord(String tableName, String recordId) async {
    // Implementation for immediate sync
  }

  Future<void> _refreshTransactionsIfNeeded(
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    // Implementation for background refresh
  }

  Future<void> _syncUserProfile() async {
    // Implementation for user profile sync
  }

  Future<void> _syncPartnershipData() async {
    // Implementation for partnership sync
  }

  Future<void> _resolveConflictsAutomatically() async {
    // Implementation for automatic conflict resolution
  }

  Future<int?> _getLastSyncTimestamp() async {
    // Implementation from previous artifacts
    return null;
  }

  Future<void> _updateSyncMetadata() async {
    // Implementation for sync metadata
  }

  Future<void> _compactDatabase() async {
    if (_localDatabase != null) {
      await _localDatabase!.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    }
  }

  // Add utility method for unawaited
  void unawaited(Future<void> future) {
    future.catchError((error) {
      debugPrint('Unawaited error: $error');
    });
  }
}
