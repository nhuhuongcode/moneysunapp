// lib/data/services/enhanced_local_database_service.dart - FIXED & UNIFIED
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/budget_model.dart';

/// Enhanced Local Database Service - Replaces LocalDatabaseService
/// Fixes all database inconsistencies and implements proper offline-first storage
class EnhancedLocalDatabaseService {
  static Database? _database;
  static const String _databaseName = 'moneysun_unified.db';
  static const int _databaseVersion = 3; // Incremented for unified schema

  static final EnhancedLocalDatabaseService _instance =
      EnhancedLocalDatabaseService._internal();
  factory EnhancedLocalDatabaseService() => _instance;
  EnhancedLocalDatabaseService._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      String path = join(await getDatabasesPath(), _databaseName);
      print('📁 Enhanced Database path: $path');

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _createUnifiedTables,
        onUpgrade: _upgradeDatabase,
        onOpen: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          print('✅ Enhanced database opened successfully');
        },
      );
    } catch (e) {
      print('❌ Error initializing enhanced database: $e');
      rethrow;
    }
  }

  // ============ UNIFIED TABLE CREATION ============

  Future<void> _createUnifiedTables(Database db, int version) async {
    print('🔨 Creating unified database tables v$version...');

    try {
      // Users table for sync metadata
      await db.execute('''
        CREATE TABLE users (
          id TEXT PRIMARY KEY,
          displayName TEXT,
          email TEXT,
          partnershipId TEXT,
          lastSyncTime INTEGER,
          createdAt INTEGER DEFAULT (strftime('%s', 'now')),
          updatedAt INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Unified Transactions table
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
          sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1)),
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          conflict_data TEXT,
          
          -- Timestamps  
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          deleted_at INTEGER,
          
          FOREIGN KEY (wallet_id) REFERENCES wallets(id),
          FOREIGN KEY (category_id) REFERENCES categories(id),
          FOREIGN KEY (user_id) REFERENCES users(id)
        )
      ''');

      // Unified Wallets table
      await db.execute('''
        CREATE TABLE wallets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL,
          balance REAL NOT NULL DEFAULT 0,
          ownerId TEXT NOT NULL,
          isVisibleToPartner INTEGER DEFAULT 1 CHECK (isVisibleToPartner IN (0, 1)),
          type TEXT DEFAULT 'general' CHECK (type IN ('general', 'cash', 'bank', 'credit', 'investment', 'savings', 'digital')),
          currency TEXT DEFAULT 'VND',
          
          -- Enhanced fields
          isArchived INTEGER DEFAULT 0 CHECK (isArchived IN (0, 1)),
          archivedAt INTEGER,
          lastAdjustment TEXT, -- JSON for adjustment data
          
          -- Sync metadata
          sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1)),
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          
          -- Timestamps
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          FOREIGN KEY (ownerId) REFERENCES users(id)
        )
      ''');

      // Unified Categories table
      await db.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          name TEXT NOT NULL,
          ownerId TEXT NOT NULL,
          type TEXT NOT NULL CHECK (type IN ('income', 'expense')),
          iconCodePoint INTEGER,
          subCategories TEXT DEFAULT '{}', -- JSON
          
          -- Enhanced fields
          ownershipType TEXT DEFAULT 'personal' CHECK (ownershipType IN ('personal', 'shared')),
          createdBy TEXT,
          isArchived INTEGER DEFAULT 0 CHECK (isArchived IN (0, 1)),
          isActive INTEGER DEFAULT 1 CHECK (isActive IN (0, 1)),
          usageCount INTEGER DEFAULT 0,
          lastUsed INTEGER,
          metadata TEXT DEFAULT '{}', -- JSON
          
          -- Sync metadata
          sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1)),
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          
          -- Timestamps
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(ownerId, name, type),
          FOREIGN KEY (ownerId) REFERENCES users(id),
          FOREIGN KEY (createdBy) REFERENCES users(id)
        )
      ''');

      // Unified Budgets table
      await db.execute('''
        CREATE TABLE budgets (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          ownerId TEXT NOT NULL,
          month TEXT NOT NULL,
          totalAmount REAL NOT NULL DEFAULT 0,
          categoryAmounts TEXT DEFAULT '{}', -- JSON
          
          -- Enhanced fields
          budgetType TEXT DEFAULT 'personal' CHECK (budgetType IN ('personal', 'shared')),
          period TEXT DEFAULT 'monthly' CHECK (period IN ('weekly', 'monthly', 'quarterly', 'yearly', 'custom')),
          createdBy TEXT,
          startDate INTEGER,
          endDate INTEGER,
          isActive INTEGER DEFAULT 1 CHECK (isActive IN (0, 1)),
          notes TEXT DEFAULT '{}', -- JSON
          categoryLimits TEXT DEFAULT '{}', -- JSON
          isDeleted INTEGER DEFAULT 0 CHECK (isDeleted IN (0, 1)),
          
          -- Sync metadata
          sync_status INTEGER DEFAULT 0 CHECK (sync_status IN (0, 1)),
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          
          -- Timestamps
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(ownerId, month, budgetType),
          FOREIGN KEY (ownerId) REFERENCES users(id),
          FOREIGN KEY (createdBy) REFERENCES users(id)
        )
      ''');

      // Enhanced Description History table
      await db.execute('''
        CREATE TABLE description_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId TEXT NOT NULL,
          description TEXT NOT NULL,
          usageCount INTEGER DEFAULT 1,
          lastUsed INTEGER DEFAULT (strftime('%s', 'now')),
          createdAt INTEGER DEFAULT (strftime('%s', 'now')),
          updatedAt INTEGER DEFAULT (strftime('%s', 'now')),
          
          -- Context for smart suggestions
          type TEXT CHECK (type IN ('income', 'expense', 'transfer')),
          categoryId TEXT,
          amount REAL,
          confidence REAL DEFAULT 0, -- AI confidence score
          
          UNIQUE(userId, description),
          FOREIGN KEY (userId) REFERENCES users(id),
          FOREIGN KEY (categoryId) REFERENCES categories(id)
        )
      ''');

      // Sync Queue table for offline operations
      await db.execute('''
        CREATE TABLE sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tableName TEXT NOT NULL,
          recordId TEXT NOT NULL,
          firebase_id TEXT,
          operation TEXT NOT NULL CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE')),
          data TEXT NOT NULL, -- JSON
          priority INTEGER DEFAULT 1 CHECK (priority IN (1, 2, 3)),
          retry_count INTEGER DEFAULT 0,
          max_retries INTEGER DEFAULT 3,
          last_error TEXT,
          scheduled_at INTEGER DEFAULT (strftime('%s', 'now')),
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(tableName, recordId, operation)
        )
      ''');

      // Sync Metadata table
      await db.execute('''
        CREATE TABLE sync_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Change Log table for audit trail
      await db.execute('''
        CREATE TABLE change_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          changes TEXT, -- JSON diff
          user_id TEXT NOT NULL,
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          FOREIGN KEY (user_id) REFERENCES users(id)
        )
      ''');

      // Create all indexes
      await _createOptimizedIndexes(db);

      print('✅ Unified database tables created successfully');
    } catch (e) {
      print('❌ Error creating unified tables: $e');
      rethrow;
    }
  }

  Future<void> _createOptimizedIndexes(Database db) async {
    final indexes = [
      // Transaction indexes
      'CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date DESC)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_wallet_date ON transactions(wallet_id, date DESC)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_category ON transactions(category_id)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_sync ON transactions(sync_status, last_modified)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_type_date ON transactions(type, date DESC)',

      // Wallet indexes
      'CREATE INDEX IF NOT EXISTS idx_wallets_owner ON wallets(ownerId, isArchived)',
      'CREATE INDEX IF NOT EXISTS idx_wallets_sync ON wallets(sync_status, last_modified)',
      'CREATE INDEX IF NOT EXISTS idx_wallets_type ON wallets(type)',

      // Category indexes
      'CREATE INDEX IF NOT EXISTS idx_categories_owner_type ON categories(ownerId, type, isArchived)',
      'CREATE INDEX IF NOT EXISTS idx_categories_ownership ON categories(ownershipType, isActive)',
      'CREATE INDEX IF NOT EXISTS idx_categories_usage ON categories(usageCount DESC, lastUsed DESC)',
      'CREATE INDEX IF NOT EXISTS idx_categories_sync ON categories(sync_status, last_modified)',

      // Budget indexes
      'CREATE INDEX IF NOT EXISTS idx_budgets_owner_month ON budgets(ownerId, month, budgetType)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_type_active ON budgets(budgetType, isActive, isDeleted)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_sync ON budgets(sync_status, last_modified)',

      // Description history indexes
      'CREATE INDEX IF NOT EXISTS idx_description_user_usage ON description_history(userId, usageCount DESC)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_lastused ON description_history(userId, lastUsed DESC)',
      'CREATE INDEX IF NOT EXISTS idx_description_text_search ON description_history(description)',
      'CREATE INDEX IF NOT EXISTS idx_description_context ON description_history(userId, type, categoryId)',

      // Sync queue indexes
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_priority ON sync_queue(priority DESC, created_at ASC)',
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON sync_queue(retry_count, scheduled_at)',

      // Change log indexes
      'CREATE INDEX IF NOT EXISTS idx_change_log_user_time ON change_log(user_id, created_at DESC)',
      'CREATE INDEX IF NOT EXISTS idx_change_log_table_record ON change_log(table_name, record_id)',
    ];

    for (final indexSql in indexes) {
      try {
        await db.execute(indexSql);
      } catch (e) {
        print('⚠️ Warning: Could not create index: $e');
      }
    }
  }

  // ============ DATABASE UPGRADE LOGIC ============

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    print('🔄 Upgrading database from v$oldVersion to v$newVersion');

    try {
      if (oldVersion < 3) {
        // Major upgrade - recreate with unified schema
        await _migrateToUnifiedSchema(db, oldVersion);
      }
    } catch (e) {
      print('❌ Database upgrade failed: $e');
      // Emergency reset if upgrade fails
      await _emergencyReset();
      rethrow;
    }
  }

  Future<void> _migrateToUnifiedSchema(Database db, int oldVersion) async {
    print('🔧 Migrating to unified schema...');

    try {
      // Backup existing data
      Map<String, List<Map<String, dynamic>>> backup = {};

      final tables = [
        'transactions',
        'wallets',
        'categories',
        'budgets',
        'description_history',
      ];
      for (final table in tables) {
        try {
          backup[table] = await db.query(table);
          print('📦 Backed up ${backup[table]!.length} records from $table');
        } catch (e) {
          print('⚠️ Could not backup $table: $e');
          backup[table] = [];
        }
      }

      // Drop existing tables
      for (final table in tables) {
        try {
          await db.execute('DROP TABLE IF EXISTS $table');
        } catch (e) {
          print('⚠️ Could not drop $table: $e');
        }
      }

      // Create new unified tables
      await _createUnifiedTables(db, 3);

      // Restore data with new schema
      await _restoreBackupData(db, backup);

      print('✅ Migration to unified schema completed');
    } catch (e) {
      print('❌ Migration failed: $e');
      rethrow;
    }
  }

  Future<void> _restoreBackupData(
    Database db,
    Map<String, List<Map<String, dynamic>>> backup,
  ) async {
    print('📥 Restoring backup data...');

    try {
      // Restore transactions
      final transactions = backup['transactions'] ?? [];
      for (final transaction in transactions) {
        try {
          await db.insert('transactions', _migrateTransactionData(transaction));
        } catch (e) {
          print('⚠️ Could not restore transaction: $e');
        }
      }

      // Restore wallets
      final wallets = backup['wallets'] ?? [];
      for (final wallet in wallets) {
        try {
          await db.insert('wallets', _migrateWalletData(wallet));
        } catch (e) {
          print('⚠️ Could not restore wallet: $e');
        }
      }

      // Restore categories
      final categories = backup['categories'] ?? [];
      for (final category in categories) {
        try {
          await db.insert('categories', _migrateCategoryData(category));
        } catch (e) {
          print('⚠️ Could not restore category: $e');
        }
      }

      // Restore budgets
      final budgets = backup['budgets'] ?? [];
      for (final budget in budgets) {
        try {
          await db.insert('budgets', _migrateBudgetData(budget));
        } catch (e) {
          print('⚠️ Could not restore budget: $e');
        }
      }

      // Restore description history
      final descriptions = backup['description_history'] ?? [];
      for (final desc in descriptions) {
        try {
          await db.insert('description_history', _migrateDescriptionData(desc));
        } catch (e) {
          print('⚠️ Could not restore description: $e');
        }
      }

      print('✅ Backup data restored successfully');
    } catch (e) {
      print('❌ Restore failed: $e');
      rethrow;
    }
  }

  // ============ DATA MIGRATION HELPERS ============

  Map<String, dynamic> _migrateTransactionData(Map<String, dynamic> old) {
    return {
      'id': old['id'],
      'amount': old['amount'],
      'type': old['type'],
      'category_id': old['categoryId'] ?? old['category_id'],
      'wallet_id': old['walletId'] ?? old['wallet_id'],
      'date': old['date'],
      'description': old['description'] ?? '',
      'user_id': old['userId'] ?? old['user_id'],
      'sub_category_id': old['subCategoryId'] ?? old['sub_category_id'],
      'transfer_to_wallet_id':
          old['transferToWalletId'] ?? old['transfer_to_wallet_id'],
      'sync_status': old['syncStatus'] ?? old['sync_status'] ?? 0,
      'created_at':
          old['createdAt'] ??
          old['created_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'updated_at':
          old['updatedAt'] ??
          old['updated_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
    };
  }

  Map<String, dynamic> _migrateWalletData(Map<String, dynamic> old) {
    return {
      'id': old['id'],
      'name': old['name'],
      'balance': old['balance'],
      'ownerId': old['ownerId'],
      'isVisibleToPartner': old['isVisibleToPartner'] ?? 1,
      'type': old['type'] ?? 'general',
      'currency': old['currency'] ?? 'VND',
      'isArchived': old['isArchived'] ?? 0,
      'sync_status': old['syncStatus'] ?? old['sync_status'] ?? 0,
      'created_at':
          old['createdAt'] ??
          old['created_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'updated_at':
          old['updatedAt'] ??
          old['updated_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
    };
  }

  Map<String, dynamic> _migrateCategoryData(Map<String, dynamic> old) {
    return {
      'id': old['id'],
      'name': old['name'],
      'ownerId': old['ownerId'],
      'type': old['type'],
      'iconCodePoint': old['iconCodePoint'],
      'subCategories': old['subCategories'] ?? '{}',
      'ownershipType': old['ownershipType'] ?? 'personal',
      'createdBy': old['createdBy'],
      'isArchived': old['isArchived'] ?? 0,
      'isActive': old['isActive'] ?? 1,
      'usageCount': old['usageCount'] ?? 0,
      'sync_status': old['syncStatus'] ?? old['sync_status'] ?? 0,
      'created_at':
          old['createdAt'] ??
          old['created_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'updated_at':
          old['updatedAt'] ??
          old['updated_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
    };
  }

  Map<String, dynamic> _migrateBudgetData(Map<String, dynamic> old) {
    return {
      'id': old['id'],
      'ownerId': old['ownerId'],
      'month': old['month'],
      'totalAmount': old['totalAmount'],
      'categoryAmounts': old['categoryAmounts'] ?? '{}',
      'budgetType': old['budgetType'] ?? 'personal',
      'period': old['period'] ?? 'monthly',
      'createdBy': old['createdBy'],
      'isActive': old['isActive'] ?? 1,
      'notes': old['notes'] ?? '{}',
      'categoryLimits': old['categoryLimits'] ?? '{}',
      'sync_status': old['syncStatus'] ?? old['sync_status'] ?? 0,
      'created_at':
          old['createdAt'] ??
          old['created_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'updated_at':
          old['updatedAt'] ??
          old['updated_at'] ??
          (DateTime.now().millisecondsSinceEpoch ~/ 1000),
    };
  }

  Map<String, dynamic> _migrateDescriptionData(Map<String, dynamic> old) {
    return {
      'userId': old['userId'],
      'description': old['description'],
      'usageCount': old['usageCount'] ?? 1,
      'lastUsed':
          old['lastUsed'] ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'createdAt':
          old['createdAt'] ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'updatedAt':
          old['updatedAt'] ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000),
      'type': old['type'],
      'categoryId': old['categoryId'],
      'amount': old['amount'],
    };
  }

  // ============ EMERGENCY RESET ============

  Future<void> _emergencyReset() async {
    try {
      print('🚨 Performing emergency database reset...');

      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      String path = join(await getDatabasesPath(), _databaseName);
      await deleteDatabase(path);

      print('✅ Emergency reset completed');
    } catch (e) {
      print('❌ Emergency reset failed: $e');
      rethrow;
    }
  }

  /// Emergency reset - can be called externally
  static Future<void> emergencyDatabaseReset() async {
    final instance = EnhancedLocalDatabaseService();
    await instance._emergencyReset();
  }

  /// Check if database is healthy
  Future<bool> isDatabaseHealthy() async {
    try {
      final db = await database;

      // Test basic query
      await db.rawQuery('SELECT sqlite_version()');

      // Check critical tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      final tableNames = tables.map((t) => t['name'] as String).toSet();
      final requiredTables = {
        'transactions',
        'wallets',
        'categories',
        'budgets',
        'description_history',
        'sync_queue',
        'users',
      };

      final hasAllTables = requiredTables.every(
        (table) => tableNames.contains(table),
      );

      if (!hasAllTables) {
        print(
          '❌ Missing required tables: ${requiredTables.difference(tableNames)}',
        );
        return false;
      }

      print('✅ Database health check passed');
      return true;
    } catch (e) {
      print('❌ Database health check failed: $e');
      return false;
    }
  }

  // ============ CRUD OPERATIONS ============
  // All CRUD operations will be implemented here...
  // This is the foundation - specific operations will be added in next step

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Get database statistics
  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;

    try {
      final results = await Future.wait([
        db.rawQuery('SELECT COUNT(*) as count FROM transactions'),
        db.rawQuery('SELECT COUNT(*) as count FROM wallets'),
        db.rawQuery('SELECT COUNT(*) as count FROM categories'),
        db.rawQuery('SELECT COUNT(*) as count FROM budgets'),
        db.rawQuery('SELECT COUNT(*) as count FROM description_history'),
        db.rawQuery('SELECT COUNT(*) as count FROM sync_queue'),
        db.rawQuery(
          'SELECT COUNT(*) as count FROM sync_queue WHERE retry_count = 0',
        ),
      ]);

      return {
        'transactions': results[0].first['count'] as int,
        'wallets': results[1].first['count'] as int,
        'categories': results[2].first['count'] as int,
        'budgets': results[3].first['count'] as int,
        'descriptions': results[4].first['count'] as int,
        'pendingSync': results[5].first['count'] as int,
        'failedSync': results[6].first['count'] as int,
      };
    } catch (e) {
      print('❌ Error getting database stats: $e');
      return {
        'transactions': 0,
        'wallets': 0,
        'categories': 0,
        'budgets': 0,
        'descriptions': 0,
        'pendingSync': 0,
        'failedSync': 0,
      };
    }
  }

  /// Optimize database performance
  Future<void> optimizeDatabase() async {
    final db = await database;

    try {
      print('🔧 Optimizing database...');

      // Analyze tables for better query performance
      await db.execute('ANALYZE');

      // Vacuum to reclaim space
      await db.execute('VACUUM');

      // Update statistics
      await db.execute('PRAGMA optimize');

      print('✅ Database optimization completed');
    } catch (e) {
      print('❌ Database optimization failed: $e');
    }
  }

  /// Clean up old synced data
  Future<void> cleanupOldData({int keepDays = 30}) async {
    final db = await database;
    final cutoffTime =
        DateTime.now()
            .subtract(Duration(days: keepDays))
            .millisecondsSinceEpoch ~/
        1000;

    try {
      await db.transaction((txn) async {
        // Clean up old change logs
        await txn.delete(
          'change_log',
          where: 'created_at < ?',
          whereArgs: [cutoffTime],
        );

        // Clean up successful sync queue items
        await txn.delete(
          'sync_queue',
          where: 'created_at < ? AND retry_count = 0',
          whereArgs: [cutoffTime],
        );

        // Clean up old description history (keep frequently used ones)
        await txn.delete(
          'description_history',
          where: 'lastUsed < ? AND usageCount <= 1',
          whereArgs: [cutoffTime],
        );
      });

      print('✅ Old data cleanup completed');
    } catch (e) {
      print('❌ Cleanup failed: $e');
    }
  }
}
