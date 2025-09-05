import 'package:moneysun/data/models/budget_model.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'dart:convert';

class LocalDatabaseService {
  static Database? _database;
  static const String _databaseName = 'moneysun_local.db';
  static const int _databaseVersion = 2;

  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    try {
      String path = join(await getDatabasesPath(), _databaseName);
      print('📁 Database path: $path');

      return await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _createTables,
        onUpgrade: _upgradeDatabase,
        onOpen: (db) async {
          print('✅ Database opened successfully');
        },
      );
    } catch (e) {
      print('❌ Error initializing database: $e');
      rethrow;
    }
  }

  Future<void> _createTables(Database db, int version) async {
    print('🔨 Creating database tables...');

    try {
      // Transactions table
      await db.execute('''
        CREATE TABLE transactions (
          id TEXT PRIMARY KEY,
          firebase_id TEXT UNIQUE,
          amount REAL NOT NULL,
          type TEXT NOT NULL,
          category_id TEXT,
          wallet_id TEXT NOT NULL,
          date TEXT NOT NULL,
          description TEXT,
          user_id TEXT NOT NULL,
          sub_category_id TEXT,
          transfer_to_wallet_id TEXT,
          
          sync_status INTEGER DEFAULT 0,
          last_modified INTEGER DEFAULT (strftime('%s', 'now')),
          version INTEGER DEFAULT 1,
          checksum TEXT,
          
          conflict_data TEXT, 
          resolved_at INTEGER,
          
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          updated_at INTEGER DEFAULT (strftime('%s', 'now')),
          deleted_at INTEGER, 
          
          FOREIGN KEY (wallet_id) REFERENCES wallets(id),
          FOREIGN KEY (category_id) REFERENCES categories(id)
        )
      ''');

      // Wallets table
      await db.execute('''
        CREATE TABLE wallets (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          balance REAL NOT NULL,
          ownerId TEXT NOT NULL,
          isVisibleToPartner INTEGER DEFAULT 1,
          syncStatus INTEGER DEFAULT 0,
          createdAt INTEGER DEFAULT (strftime('%s', 'now')),
          updatedAt INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Categories table
      await db.execute('''
        CREATE TABLE categories (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          ownerId TEXT NOT NULL,
          type TEXT NOT NULL,
          iconCodePoint INTEGER,
          subCategories TEXT,
          syncStatus INTEGER DEFAULT 0,
          createdAt INTEGER DEFAULT (strftime('%s', 'now')),
          updatedAt INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // FIXED: Enhanced description_history table with proper defaults
      await db.execute('''
        CREATE TABLE description_history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          userId TEXT NOT NULL,
          description TEXT NOT NULL,
          usageCount INTEGER DEFAULT 1,
          lastUsed INTEGER DEFAULT (strftime('%s', 'now')),
          createdAt INTEGER DEFAULT (strftime('%s', 'now')),
          updatedAt INTEGER DEFAULT (strftime('%s', 'now')),
          
          -- Context information for smart suggestions
          type TEXT,
          categoryId TEXT,
          amount REAL,
          
          UNIQUE(userId, description)
        )
      ''');

      // Other tables remain the same...
      await db.execute('''
        CREATE TABLE sync_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          tableName TEXT NOT NULL,
          recordId TEXT NOT NULL,
          firebase_id TEXT,
          operation TEXT NOT NULL,
          data TEXT NOT NULL,
          priority INTEGER DEFAULT 1,
          retry_count INTEGER DEFAULT 0,
          max_retries INTEGER DEFAULT 3,
          last_error TEXT,
          scheduled_at INTEGER DEFAULT (strftime('%s', 'now')),
          created_at INTEGER DEFAULT (strftime('%s', 'now')),
          
          UNIQUE(tableName, recordId, operation)
        )
      ''');

      await db.execute('''
        CREATE TABLE sync_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      await db.execute('''
        CREATE TABLE change_log (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          table_name TEXT NOT NULL,
          record_id TEXT NOT NULL,
          operation TEXT NOT NULL,
          changes TEXT,
          user_id TEXT NOT NULL,
          created_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Create indexes for performance
      await _createIndexes(db);

      print('✅ Database tables created successfully');
    } catch (e) {
      print('❌ Error creating tables: $e');
      rethrow;
    }
  }

  // CRITICAL FIX: Completely rewritten upgrade logic
  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    print('🔄 Upgrading database from version $oldVersion to $newVersion');

    if (oldVersion < 2) {
      await _upgradeToVersion2(db);
    }
  }

  // CRITICAL FIX: Safe upgrade to version 2
  Future<void> _upgradeToVersion2(Database db) async {
    try {
      print('📝 Upgrading to version 2...');

      // Check if description_history table exists
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='description_history'",
      );

      if (tables.isEmpty) {
        // Table doesn't exist, create it
        await db.execute('''
          CREATE TABLE description_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            userId TEXT NOT NULL,
            description TEXT NOT NULL,
            usageCount INTEGER DEFAULT 1,
            lastUsed INTEGER DEFAULT (strftime('%s', 'now')),
            createdAt INTEGER DEFAULT (strftime('%s', 'now')),
            updatedAt INTEGER DEFAULT (strftime('%s', 'now')),
            type TEXT,
            categoryId TEXT,
            amount REAL,
            UNIQUE(userId, description)
          )
        ''');
        print('✅ Created description_history table');
      } else {
        // Table exists, check and add missing columns
        final columns = await db.rawQuery(
          'PRAGMA table_info(description_history)',
        );
        final columnNames = columns.map((col) => col['name'] as String).toSet();

        // Add missing columns one by one with SAFE defaults
        final missingColumns = <String, String>{
          'type': 'TEXT',
          'categoryId': 'TEXT',
          'amount': 'REAL',
        };

        for (final entry in missingColumns.entries) {
          if (!columnNames.contains(entry.key)) {
            try {
              await db.execute(
                'ALTER TABLE description_history ADD COLUMN ${entry.key} ${entry.value}',
              );
              print('✅ Added column: ${entry.key}');
            } catch (e) {
              print('⚠️ Warning: Could not add column ${entry.key}: $e');
            }
          }
        }

        // Handle updatedAt column separately with special logic
        if (!columnNames.contains('updatedAt')) {
          try {
            // CRITICAL FIX: Use constant default, then update
            await db.execute(
              'ALTER TABLE description_history ADD COLUMN updatedAt INTEGER DEFAULT 0',
            );

            // Update all existing records with current timestamp
            final currentTime = (DateTime.now().millisecondsSinceEpoch / 1000)
                .round();
            await db.execute(
              'UPDATE description_history SET updatedAt = ? WHERE updatedAt = 0',
              [currentTime],
            );

            print('✅ Added and initialized updatedAt column');
          } catch (e) {
            print('⚠️ Warning: Could not add updatedAt column: $e');
            // This is not critical, continue without it
          }
        }
      }

      // Create indexes
      await _createIndexes(db);

      print('✅ Successfully upgraded to version 2');
    } catch (e) {
      print('❌ Error upgrading to version 2: $e');
      rethrow;
    }
  }

  Future<void> _createIndexes(Database db) async {
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_transactions_sync_status ON transactions(sync_status, last_modified)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_firebase_id ON transactions(firebase_id)',
      'CREATE INDEX IF NOT EXISTS idx_wallets_owner ON wallets(ownerId)',
      'CREATE INDEX IF NOT EXISTS idx_categories_owner_type ON categories(ownerId, type)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_type ON description_history(userId, type)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_category ON description_history(userId, categoryId)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_lastused ON description_history(userId, lastUsed)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_usage ON description_history(userId, usageCount)',
      'CREATE INDEX IF NOT EXISTS idx_description_text ON description_history(description)',
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_priority ON sync_queue(priority, created_at)',
      'CREATE INDEX IF NOT EXISTS idx_change_log_user_time ON change_log(user_id, created_at)',
    ];

    for (final indexSql in indexes) {
      try {
        await db.execute(indexSql);
      } catch (e) {
        print('⚠️ Warning: Could not create index: $e');
      }
    }
  }

  // ========================================================================
  // EMERGENCY DATABASE RESET METHODS
  // ========================================================================

  /// CRITICAL: Emergency database reset when migration fails
  static Future<void> emergencyDatabaseReset() async {
    try {
      print('🚨 Performing emergency database reset...');

      // Close existing database
      if (_database != null) {
        await _database!.close();
        _database = null;
      }

      // Delete the database file
      String path = join(await getDatabasesPath(), _databaseName);
      await deleteDatabase(path);

      print('✅ Database reset completed - will recreate on next access');
    } catch (e) {
      print('❌ Emergency reset failed: $e');
      rethrow;
    }
  }

  /// Check if database is corrupted
  Future<bool> isDatabaseHealthy() async {
    try {
      final db = await database;

      // Try a simple query
      await db.rawQuery('SELECT sqlite_version()');

      // Check if critical tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      final tableNames = tables.map((t) => t['name'] as String).toSet();
      final requiredTables = {
        'transactions',
        'wallets',
        'categories',
        'description_history',
      };

      return requiredTables.every((table) => tableNames.contains(table));
    } catch (e) {
      print('❌ Database health check failed: $e');
      return false;
    }
  }

  Future<void> saveTransactionLocally(
    TransactionModel transaction, {
    int syncStatus = 0,
  }) async {
    final db = await database;

    await db.insert('transactions', {
      'id': transaction.id,
      'amount': transaction.amount,
      'type': transaction.type.name,
      'categoryId': transaction.categoryId,
      'walletId': transaction.walletId,
      'date': transaction.date.toIso8601String(),
      'description': transaction.description,
      'userId': transaction.userId,
      'subCategoryId': transaction.subCategoryId,
      'transferToWalletId': transaction.transferToWalletId,
      'syncStatus': syncStatus,
      'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Add to sync queue if not synced
    if (syncStatus == 0) {
      await addToSyncQueue(
        'transactions',
        transaction.id,
        'INSERT',
        transaction.toJson(),
      );
    }
  }

  Future<List<TransactionModel>> getLocalTransactions({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final db = await database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (userId != null) {
      whereClause += ' AND userId = ?';
      whereArgs.add(userId);
    }

    if (startDate != null) {
      whereClause += ' AND date >= ?';
      whereArgs.add(startDate.toIso8601String());
    }

    if (endDate != null) {
      whereClause += ' AND date <= ?';
      whereArgs.add(endDate.toIso8601String());
    }

    final result = await db.query(
      'transactions',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'date DESC',
      limit: limit,
    );

    return result.map((map) => _transactionFromMap(map)).toList();
  }

  TransactionModel _transactionFromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'],
      amount: map['amount'],
      type: TransactionType.values.firstWhere((e) => e.name == map['type']),
      categoryId: map['categoryId'],
      walletId: map['walletId'],
      date: DateTime.parse(map['date']),
      description: map['description'] ?? '',
      userId: map['userId'],
      subCategoryId: map['subCategoryId'],
      transferToWalletId: map['transferToWalletId'],
    );
  }

  // ============ WALLETS ============
  Future<void> saveWalletLocally(Wallet wallet, {int syncStatus = 0}) async {
    final db = await database;

    await db.insert('wallets', {
      'id': wallet.id,
      'name': wallet.name,
      'balance': wallet.balance,
      'ownerId': wallet.ownerId,
      'isVisibleToPartner': wallet.isVisibleToPartner ? 1 : 0,
      'syncStatus': syncStatus,
      'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (syncStatus == 0) {
      await addToSyncQueue('wallets', wallet.id, 'INSERT', wallet.toJson());
    }
  }

  Future<List<Wallet>> getLocalWallets(String ownerId) async {
    final db = await database;

    final result = await db.query(
      'wallets',
      where: 'ownerId = ?',
      whereArgs: [ownerId],
      orderBy: 'name ASC',
    );

    return result.map((map) => _walletFromMap(map)).toList();
  }

  Wallet _walletFromMap(Map<String, dynamic> map) {
    return Wallet(
      id: map['id'],
      name: map['name'],
      balance: map['balance'],
      ownerId: map['ownerId'],
      isVisibleToPartner: map['isVisibleToPartner'] == 1,
    );
  }

  // ============ CATEGORIES ============
  Future<void> saveCategoryLocally(
    Category category, {
    int syncStatus = 0,
  }) async {
    final db = await database;

    await db.insert('categories', {
      'id': category.id,
      'name': category.name,
      'ownerId': category.ownerId,
      'type': category.type,
      'iconCodePoint': category.iconCodePoint,
      'subCategories': jsonEncode(category.subCategories),
      'syncStatus': syncStatus,
      'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (syncStatus == 0) {
      await addToSyncQueue(
        'categories',
        category.id,
        'INSERT',
        category.toJson(),
      );
    }
  }

  Future<List<Category>> getLocalCategories({
    String? ownerId,
    String? type,
  }) async {
    final db = await database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (ownerId != null) {
      whereClause += ' AND ownerId = ?';
      whereArgs.add(ownerId);
    }

    if (type != null) {
      whereClause += ' AND type = ?';
      whereArgs.add(type);
    }

    final result = await db.query(
      'categories',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    return result.map((map) => _categoryFromMap(map)).toList();
  }

  Category _categoryFromMap(Map<String, dynamic> map) {
    final subCategoriesJson = map['subCategories'] as String?;
    Map<String, String> subCategories = {};

    if (subCategoriesJson != null && subCategoriesJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(subCategoriesJson);
        subCategories = Map<String, String>.from(decoded);
      } catch (e) {
        print('Error decoding subCategories: $e');
      }
    }

    return Category(
      id: map['id'],
      name: map['name'],
      ownerId: map['ownerId'],
      type: map['type'],
      iconCodePoint: map['iconCodePoint'],
      subCategories: subCategories,
    );
  }

  // ============ DESCRIPTION HISTORY - V7 Feature ============
  Future<void> saveDescriptionToHistory(
    String userId,
    String description,
  ) async {
    if (description.trim().isEmpty) return;

    final db = await database;

    // Check if description already exists
    final existing = await db.query(
      'description_history',
      where: 'userId = ? AND description = ?',
      whereArgs: [userId, description.trim()],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      // Update usage count and last used
      await db.update(
        'description_history',
        <String, Object?>{
          'usageCount': (existing.first['usageCount'] as int? ?? 0) + 1,
          'lastUsed': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      // Insert new description
      await db.insert('description_history', {
        'userId': userId,
        'description': description.trim(),
        'usageCount': 1,
        'lastUsed': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
    }
  }

  Future<List<String>> getDescriptionSuggestions(
    String userId, {
    int limit = 10,
  }) async {
    final db = await database;

    final result = await db.query(
      'description_history',
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'usageCount DESC, lastUsed DESC',
      limit: limit,
    );

    return result.map((map) => map['description'] as String).toList();
  }

  Future<List<String>> searchDescriptionHistory(
    String userId,
    String query, {
    int limit = 5,
  }) async {
    final db = await database;

    final result = await db.query(
      'description_history',
      where: 'userId = ? AND description LIKE ?',
      whereArgs: [userId, '%$query%'],
      orderBy: 'usageCount DESC, lastUsed DESC',
      limit: limit,
    );

    return result.map((map) => map['description'] as String).toList();
  }

  // ============ SYNC QUEUE MANAGEMENT ============
  Future<void> addToSyncQueue(
    String tableName,
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    await db.insert('sync_queue', {
      'tableName': tableName,
      'recordId': recordId,
      'operation': operation,
      'data': jsonEncode(data),
      'priority': _getSyncPriority(operation),
    });
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

  Future<List<Map<String, dynamic>>> getPendingSyncItems({
    int limit = 50,
  }) async {
    final db = await database;

    return await db.query(
      'sync_queue',
      orderBy: 'priority DESC, createdAt ASC',
      limit: limit,
    );
  }

  Future<void> removeSyncItem(int syncId) async {
    final db = await database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [syncId]);
  }

  Future<void> incrementRetryCount(int syncId) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'retryCount': 'retryCount + 1'},
      where: 'id = ?',
      whereArgs: [syncId],
    );
  }

  // ============ SYNC STATUS MANAGEMENT ============
  Future<void> markAsSynced(String tableName, String recordId) async {
    final db = await database;

    await db.update(
      tableName,
      {'syncStatus': 1},
      where: 'id = ?',
      whereArgs: [recordId],
    );
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRecords(
    String tableName,
  ) async {
    final db = await database;

    return await db.query(
      tableName,
      where: 'syncStatus = 0',
      orderBy: 'updatedAt ASC',
    );
  }

  // ============ UTILITY METHODS ============
  Future<void> clearAllData() async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('wallets');
      await txn.delete('categories');
      await txn.delete('description_history');
      await txn.delete('sync_queue');
    });
  }

  Future<void> clearSyncedData() async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete('transactions', where: 'syncStatus = 1');
      await txn.delete('wallets', where: 'syncStatus = 1');
      await txn.delete('categories', where: 'syncStatus = 1');
    });
  }

  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;

    final transactions = await db.rawQuery(
      'SELECT COUNT(*) as count FROM transactions',
    );
    final wallets = await db.rawQuery('SELECT COUNT(*) as count FROM wallets');
    final categories = await db.rawQuery(
      'SELECT COUNT(*) as count FROM categories',
    );
    final descriptions = await db.rawQuery(
      'SELECT COUNT(*) as count FROM description_history',
    );
    final syncQueue = await db.rawQuery(
      'SELECT COUNT(*) as count FROM sync_queue',
    );

    return {
      'transactions': transactions.first['count'] as int,
      'wallets': wallets.first['count'] as int,
      'categories': categories.first['count'] as int,
      'descriptions': descriptions.first['count'] as int,
      'pendingSync': syncQueue.first['count'] as int,
    };
  }

  // Close database
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  Future<void> deleteWalletLocally(String walletId) async {
    final db = await database;

    try {
      await db.delete('wallets', where: 'id = ?', whereArgs: [walletId]);

      print('✅ Wallet deleted from local database: $walletId');
    } catch (e) {
      print('❌ Error deleting wallet locally: $e');
      rethrow;
    }
  }

  /// Update wallet in local database
  Future<void> updateWalletLocally(Wallet wallet, {int syncStatus = 1}) async {
    final db = await database;

    try {
      await db.update(
        'wallets',
        {
          'name': wallet.name,
          'balance': wallet.balance,
          'ownerId': wallet.ownerId,
          'isVisibleToPartner': wallet.isVisibleToPartner ? 1 : 0,
          'syncStatus': syncStatus,
          'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [wallet.id],
      );

      print('✅ Wallet updated in local database: ${wallet.name}');
    } catch (e) {
      print('❌ Error updating wallet locally: $e');
      rethrow;
    }
  }

  Future<Wallet?> getWalletById(String walletId) async {
    final db = await database;

    try {
      final result = await db.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      if (result.isEmpty) return null;

      return _walletFromMap(result.first);
    } catch (e) {
      print('❌ Error getting wallet by ID: $e');
      return null;
    }
  }

  /// Check if wallet has transactions locally
  Future<bool> checkWalletHasTransactionsLocally(String walletId) async {
    final db = await database;

    try {
      final result = await db.query(
        'transactions',
        where: 'walletId = ?',
        whereArgs: [walletId],
        limit: 1,
      );

      return result.isNotEmpty;
    } catch (e) {
      print('❌ Error checking wallet transactions locally: $e');
      return true; // Be safe
    }
  }

  /// Get wallet count for user
  Future<int> getWalletCountForUser(String ownerId) async {
    final db = await database;

    try {
      final result = await db.query(
        'wallets',
        columns: ['COUNT(*) as count'],
        where: 'ownerId = ?',
        whereArgs: [ownerId],
      );

      if (result.isEmpty) return 0;

      return result.first['count'] as int;
    } catch (e) {
      print('❌ Error getting wallet count: $e');
      return 0;
    }
  }

  /// Archive wallet locally
  Future<void> archiveWalletLocally(String walletId) async {
    final db = await database;

    try {
      await db.update(
        'wallets',
        {
          'isArchived': 1,
          'archivedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [walletId],
      );

      print('✅ Wallet archived locally: $walletId');
    } catch (e) {
      print('❌ Error archiving wallet locally: $e');
      rethrow;
    }
  }

  /// Get wallets with archive status
  Future<List<Wallet>> getLocalWalletsWithArchive(
    String ownerId, {
    bool includeArchived = false,
  }) async {
    final db = await database;

    try {
      String whereClause = 'ownerId = ?';
      List<dynamic> whereArgs = [ownerId];

      if (!includeArchived) {
        whereClause += ' AND (isArchived IS NULL OR isArchived = 0)';
      }

      final result = await db.query(
        'wallets',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'name ASC',
      );

      return result.map((map) => _walletFromMap(map)).toList();
    } catch (e) {
      print('❌ Error getting wallets with archive status: $e');
      return [];
    }
  }

  /// Enhanced wallet from map with archive support
  Wallet _walletFromMapEnhanced(Map<String, dynamic> map) {
    return Wallet(
      id: map['id'],
      name: map['name'],
      balance: map['balance'],
      ownerId: map['ownerId'],
      isVisibleToPartner: map['isVisibleToPartner'] == 1,
    );
  }

  /// Backup wallet data before operations
  Future<Map<String, dynamic>> backupWalletData(String walletId) async {
    final db = await database;

    try {
      // Backup wallet info
      final walletResult = await db.query(
        'wallets',
        where: 'id = ?',
        whereArgs: [walletId],
      );

      // Backup related transactions
      final transactionsResult = await db.query(
        'transactions',
        where: 'walletId = ?',
        whereArgs: [walletId],
      );

      return {
        'wallet': walletResult.isNotEmpty ? walletResult.first : null,
        'transactions': transactionsResult,
        'backupTime': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error backing up wallet data: $e');
      return {};
    }
  }

  /// Restore wallet data from backup
  Future<void> restoreWalletData(Map<String, dynamic> backupData) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        // Restore wallet
        if (backupData['wallet'] != null) {
          await txn.insert(
            'wallets',
            backupData['wallet'],
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Restore transactions
        final transactions =
            backupData['transactions'] as List<Map<String, dynamic>>?;
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

      print('✅ Wallet data restored successfully');
    } catch (e) {
      print('❌ Error restoring wallet data: $e');
      rethrow;
    }
  }
}

extension LocalDatabaseServiceEnhanced on LocalDatabaseService {
  // ============ ENHANCED CATEGORIES METHODS ============

  /// Save category locally with ownership support
  Future<void> saveCategoryLocallyEnhanced(
    Category category, {
    int syncStatus = 0,
  }) async {
    final db = await database;

    await db.insert('categories', {
      'id': category.id,
      'name': category.name,
      'ownerId': category.ownerId,
      'type': category.type,
      'iconCodePoint': category.iconCodePoint,
      'subCategories': jsonEncode(category.subCategories),
      'ownershipType': category.ownershipType.name,
      'createdBy': category.createdBy,
      'createdAt':
          category.createdAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'updatedAt':
          category.updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'isArchived': category.isArchived ? 1 : 0,
      'syncStatus': syncStatus,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (syncStatus == 0) {
      await addToSyncQueue(
        'categories',
        category.id,
        'INSERT',
        category.toJson(),
      );
    }
  }

  /// Get local categories with ownership filtering
  Future<List<Category>> getLocalCategoriesEnhanced({
    String? ownerId,
    String? type,
    CategoryOwnershipType? ownershipType,
    bool includeArchived = false,
  }) async {
    final db = await database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (ownerId != null) {
      whereClause += ' AND ownerId = ?';
      whereArgs.add(ownerId);
    }

    if (type != null) {
      whereClause += ' AND type = ?';
      whereArgs.add(type);
    }

    if (ownershipType != null) {
      whereClause += ' AND ownershipType = ?';
      whereArgs.add(ownershipType.name);
    }

    if (!includeArchived) {
      whereClause += ' AND (isArchived IS NULL OR isArchived = 0)';
    }

    final result = await db.query(
      'categories',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
    );

    return result.map((map) => _categoryFromMapEnhanced(map)).toList();
  }

  /// Get categories by ownership type
  Future<List<Category>> getCategoriesByOwnership(
    String userId,
    String? partnershipId,
    String type,
  ) async {
    final db = await database;

    String whereClause =
        'type = ? AND (isArchived IS NULL OR isArchived = 0) AND (';
    List<dynamic> whereArgs = [type];

    // Personal categories
    whereClause += 'ownerId = ?';
    whereArgs.add(userId);

    // Shared categories if partnership exists
    if (partnershipId != null) {
      whereClause += ' OR ownerId = ?';
      whereArgs.add(partnershipId);
    }

    whereClause += ')';

    final result = await db.query(
      'categories',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'ownershipType ASC, name ASC',
    );

    return result.map((map) => _categoryFromMapEnhanced(map)).toList();
  }

  /// Update category locally
  Future<void> updateCategoryLocally(Category category) async {
    final db = await database;

    await db.update(
      'categories',
      {
        'name': category.name,
        'iconCodePoint': category.iconCodePoint,
        'subCategories': jsonEncode(category.subCategories),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'isArchived': category.isArchived ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  /// Delete category locally
  Future<void> deleteCategoryLocally(String categoryId) async {
    final db = await database;

    try {
      await db.delete('categories', where: 'id = ?', whereArgs: [categoryId]);
      print('✅ Category deleted from local database: $categoryId');
    } catch (e) {
      print('❌ Error deleting category locally: $e');
      rethrow;
    }
  }

  /// Archive category locally
  Future<void> archiveCategoryLocally(String categoryId) async {
    final db = await database;

    try {
      await db.update(
        'categories',
        {'isArchived': 1, 'updatedAt': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [categoryId],
      );

      print('✅ Category archived locally: $categoryId');
    } catch (e) {
      print('❌ Error archiving category locally: $e');
      rethrow;
    }
  }

  /// Enhanced category from map
  Category _categoryFromMapEnhanced(Map<String, dynamic> map) {
    final subCategoriesJson = map['subCategories'] as String?;
    Map<String, String> subCategories = {};

    if (subCategoriesJson != null && subCategoriesJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(subCategoriesJson);
        subCategories = Map<String, String>.from(decoded);
      } catch (e) {
        print('Error decoding subCategories: $e');
      }
    }

    return Category(
      id: map['id'],
      name: map['name'],
      ownerId: map['ownerId'],
      type: map['type'],
      iconCodePoint: map['iconCodePoint'],
      subCategories: subCategories,
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == (map['ownershipType'] ?? 'personal'),
        orElse: () => CategoryOwnershipType.personal,
      ),
      createdBy: map['createdBy'],
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : null,
      isArchived: (map['isArchived'] ?? 0) == 1,
    );
  }

  // ============ BUDGETS METHODS ============

  /// Save budget locally
  Future<void> saveBudgetLocally(Budget budget, {int syncStatus = 0}) async {
    final db = await database;

    await db.insert('budgets', {
      'id': budget.id,
      'ownerId': budget.ownerId,
      'month': budget.month,
      'totalAmount': budget.totalAmount,
      'categoryAmounts': jsonEncode(budget.categoryAmounts),
      'budgetType': budget.budgetType.name,
      'period': budget.period.name,
      'createdBy': budget.createdBy,
      'createdAt':
          budget.createdAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'updatedAt':
          budget.updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'startDate': budget.startDate?.millisecondsSinceEpoch,
      'endDate': budget.endDate?.millisecondsSinceEpoch,
      'isActive': budget.isActive ? 1 : 0,
      'notes': jsonEncode(budget.notes ?? {}),
      'categoryLimits': jsonEncode(budget.categoryLimits ?? {}),
      'syncStatus': syncStatus,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (syncStatus == 0) {
      await addToSyncQueue('budgets', budget.id, 'INSERT', budget.toJson());
    }
  }

  /// Get local budgets
  Future<List<Budget>> getLocalBudgets({
    String? ownerId,
    BudgetType? budgetType,
    String? month,
    bool includeInactive = false,
  }) async {
    final db = await database;

    String whereClause = '1=1';
    List<dynamic> whereArgs = [];

    if (ownerId != null) {
      whereClause += ' AND ownerId = ?';
      whereArgs.add(ownerId);
    }

    if (budgetType != null) {
      whereClause += ' AND budgetType = ?';
      whereArgs.add(budgetType.name);
    }

    if (month != null) {
      whereClause += ' AND month = ?';
      whereArgs.add(month);
    }

    if (!includeInactive) {
      whereClause += ' AND (isActive IS NULL OR isActive = 1)';
    }

    final result = await db.query(
      'budgets',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'month DESC, budgetType ASC',
    );

    return result.map((map) => _budgetFromMap(map)).toList();
  }

  /// Get budget by ownership
  Future<List<Budget>> getBudgetsByOwnership(
    String userId,
    String? partnershipId,
    String month,
  ) async {
    final db = await database;

    String whereClause =
        'month = ? AND (isActive IS NULL OR isActive = 1) AND (';
    List<dynamic> whereArgs = [month];

    // Personal budgets
    whereClause += 'ownerId = ?';
    whereArgs.add(userId);

    // Shared budgets if partnership exists
    if (partnershipId != null) {
      whereClause += ' OR ownerId = ?';
      whereArgs.add(partnershipId);
    }

    whereClause += ')';

    final result = await db.query(
      'budgets',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'budgetType ASC',
    );

    return result.map((map) => _budgetFromMap(map)).toList();
  }

  /// Update budget locally
  Future<void> updateBudgetLocally(Budget budget) async {
    final db = await database;

    await db.update(
      'budgets',
      {
        'totalAmount': budget.totalAmount,
        'categoryAmounts': jsonEncode(budget.categoryAmounts),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'isActive': budget.isActive ? 1 : 0,
        'notes': jsonEncode(budget.notes ?? {}),
        'categoryLimits': jsonEncode(budget.categoryLimits ?? {}),
      },
      where: 'id = ?',
      whereArgs: [budget.id],
    );
  }

  /// Delete budget locally
  Future<void> deleteBudgetLocally(String budgetId) async {
    final db = await database;

    try {
      await db.delete('budgets', where: 'id = ?', whereArgs: [budgetId]);
      print('✅ Budget deleted from local database: $budgetId');
    } catch (e) {
      print('❌ Error deleting budget locally: $e');
      rethrow;
    }
  }

  /// Budget from map
  Budget _budgetFromMap(Map<String, dynamic> map) {
    final categoryAmountsJson = map['categoryAmounts'] as String?;
    Map<String, double> categoryAmounts = {};

    if (categoryAmountsJson != null && categoryAmountsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(categoryAmountsJson);
        categoryAmounts = Map<String, double>.from(decoded);
      } catch (e) {
        print('Error decoding categoryAmounts: $e');
      }
    }

    final notesJson = map['notes'] as String?;
    Map<String, String>? notes;
    if (notesJson != null && notesJson.isNotEmpty && notesJson != '{}') {
      try {
        notes = Map<String, String>.from(jsonDecode(notesJson));
      } catch (e) {
        print('Error decoding notes: $e');
      }
    }

    final categoryLimitsJson = map['categoryLimits'] as String?;
    Map<String, double>? categoryLimits;
    if (categoryLimitsJson != null &&
        categoryLimitsJson.isNotEmpty &&
        categoryLimitsJson != '{}') {
      try {
        categoryLimits = Map<String, double>.from(
          jsonDecode(categoryLimitsJson),
        );
      } catch (e) {
        print('Error decoding categoryLimits: $e');
      }
    }

    return Budget(
      id: map['id'],
      ownerId: map['ownerId'],
      month: map['month'],
      totalAmount: map['totalAmount'],
      categoryAmounts: categoryAmounts,
      budgetType: BudgetType.values.firstWhere(
        (e) => e.name == (map['budgetType'] ?? 'personal'),
        orElse: () => BudgetType.personal,
      ),
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == (map['period'] ?? 'monthly'),
        orElse: () => BudgetPeriod.monthly,
      ),
      createdBy: map['createdBy'],
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : null,
      startDate: map['startDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['startDate'])
          : null,
      endDate: map['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['endDate'])
          : null,
      isActive: (map['isActive'] ?? 1) == 1,
      notes: notes,
      categoryLimits: categoryLimits,
    );
  }

  // ============ ENHANCED DATABASE CREATION ============

  /// Enhanced table creation with budget and category support
  Future<void> createEnhancedTables(Database db, int version) async {
    print('🔨 Creating enhanced database tables...');

    try {
      // Enhanced categories table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          ownerId TEXT NOT NULL,
          type TEXT NOT NULL,
          iconCodePoint INTEGER,
          subCategories TEXT DEFAULT '{}',
          ownershipType TEXT DEFAULT 'personal',
          createdBy TEXT,
          createdAt INTEGER DEFAULT (strftime('%s', 'now')),
          updatedAt INTEGER DEFAULT (strftime('%s', 'now')),
          isArchived INTEGER DEFAULT 0,
          syncStatus INTEGER DEFAULT 0
        )
      ''');

      // Enhanced budgets table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS budgets (
          id TEXT PRIMARY KEY,
          ownerId TEXT NOT NULL,
          month TEXT NOT NULL,
          totalAmount REAL NOT NULL DEFAULT 0,
          categoryAmounts TEXT DEFAULT '{}',
          budgetType TEXT DEFAULT 'personal',
          period TEXT DEFAULT 'monthly',
          createdBy TEXT,
          createdAt INTEGER DEFAULT (strftime('%s', 'now')),
          updatedAt INTEGER DEFAULT (strftime('%s', 'now')),
          startDate INTEGER,
          endDate INTEGER,
          isActive INTEGER DEFAULT 1,
          notes TEXT DEFAULT '{}',
          categoryLimits TEXT DEFAULT '{}',
          syncStatus INTEGER DEFAULT 0
        )
      ''');

      // Create enhanced indexes
      await _createEnhancedIndexes(db);

      print('✅ Enhanced database tables created successfully');
    } catch (e) {
      print('❌ Error creating enhanced tables: $e');
      rethrow;
    }
  }

  /// Create enhanced indexes for better performance
  Future<void> _createEnhancedIndexes(Database db) async {
    final indexes = [
      // Category indexes
      'CREATE INDEX IF NOT EXISTS idx_categories_owner_type ON categories(ownerId, type)',
      'CREATE INDEX IF NOT EXISTS idx_categories_ownership ON categories(ownershipType)',
      'CREATE INDEX IF NOT EXISTS idx_categories_archived ON categories(isArchived)',
      'CREATE INDEX IF NOT EXISTS idx_categories_sync ON categories(syncStatus)',

      // Budget indexes
      'CREATE INDEX IF NOT EXISTS idx_budgets_owner_month ON budgets(ownerId, month)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_type ON budgets(budgetType)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_active ON budgets(isActive)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_period ON budgets(period)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_sync ON budgets(syncStatus)',

      // Composite indexes for efficient queries
      'CREATE INDEX IF NOT EXISTS idx_categories_owner_type_archived ON categories(ownerId, type, isArchived)',
      'CREATE INDEX IF NOT EXISTS idx_budgets_owner_month_type ON budgets(ownerId, month, budgetType)',
    ];

    for (final indexSql in indexes) {
      try {
        await db.execute(indexSql);
      } catch (e) {
        print('⚠️ Warning: Could not create index: $e');
      }
    }
  }

  // ============ STATISTICS AND ANALYTICS ============

  /// Get category usage statistics
  Future<List<CategoryUsage>> getCategoryUsageStats(
    String userId, {
    int limit = 10,
  }) async {
    final db = await database;

    try {
      final result = await db.rawQuery(
        '''
        SELECT 
          c.id as categoryId,
          c.name as categoryName,
          COUNT(t.id) as usageCount,
          MAX(t.date) as lastUsed,
          AVG(t.amount) as averageAmount
        FROM categories c
        LEFT JOIN transactions t ON c.id = t.category_id
        WHERE c.ownerId = ? AND c.isArchived = 0
        GROUP BY c.id, c.name
        HAVING usageCount > 0
        ORDER BY usageCount DESC, lastUsed DESC
        LIMIT ?
      ''',
        [userId, limit],
      );

      return result.map((row) {
        return CategoryUsage(
          categoryId: row['categoryId'] as String,
          categoryName: row['categoryName'] as String,
          usageCount: row['usageCount'] as int,
          lastUsed: DateTime.parse(row['lastUsed'] as String),
          averageAmount: (row['averageAmount'] as num).toDouble(),
          commonDescriptions: [], // TODO: Implement common descriptions
        );
      }).toList();
    } catch (e) {
      print('❌ Error getting category usage stats: $e');
      return [];
    }
  }

  /// Get budget statistics
  Future<Map<String, dynamic>> getBudgetStats(String userId) async {
    final db = await database;

    try {
      // Get total budgets count
      final budgetCount = await db.rawQuery(
        '''
        SELECT COUNT(*) as count 
        FROM budgets 
        WHERE ownerId = ? AND isActive = 1
      ''',
        [userId],
      );

      // Get categories with budgets
      final categoryCount = await db.rawQuery(
        '''
        SELECT COUNT(DISTINCT json_each.key) as count
        FROM budgets, json_each(budgets.categoryAmounts)
        WHERE budgets.ownerId = ? AND budgets.isActive = 1
      ''',
        [userId],
      );

      // Get average budget amount
      final avgBudget = await db.rawQuery(
        '''
        SELECT AVG(totalAmount) as average
        FROM budgets 
        WHERE ownerId = ? AND isActive = 1
      ''',
        [userId],
      );

      return {
        'totalBudgets': (budgetCount.first['count'] as int?) ?? 0,
        'categoriesWithBudgets': (categoryCount.first['count'] as int?) ?? 0,
        'averageBudgetAmount':
            (avgBudget.first['average'] as num?)?.toDouble() ?? 0.0,
      };
    } catch (e) {
      print('❌ Error getting budget stats: $e');
      return {
        'totalBudgets': 0,
        'categoriesWithBudgets': 0,
        'averageBudgetAmount': 0.0,
      };
    }
  }

  /// Get offline sync status for categories and budgets
  Future<Map<String, int>> getOfflineSyncStatus() async {
    final db = await database;

    try {
      // Get unsynced categories
      final unsyncedCategories = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM categories 
        WHERE syncStatus = 0
      ''');

      // Get unsynced budgets
      final unsyncedBudgets = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM budgets 
        WHERE syncStatus = 0
      ''');

      // Get total categories
      final totalCategories = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM categories
      ''');

      // Get total budgets
      final totalBudgets = await db.rawQuery('''
        SELECT COUNT(*) as count 
        FROM budgets
      ''');

      return {
        'unsyncedCategories': (unsyncedCategories.first['count'] as int?) ?? 0,
        'unsyncedBudgets': (unsyncedBudgets.first['count'] as int?) ?? 0,
        'totalCategories': (totalCategories.first['count'] as int?) ?? 0,
        'totalBudgets': (totalBudgets.first['count'] as int?) ?? 0,
      };
    } catch (e) {
      print('❌ Error getting offline sync status: $e');
      return {
        'unsyncedCategories': 0,
        'unsyncedBudgets': 0,
        'totalCategories': 0,
        'totalBudgets': 0,
      };
    }
  }

  // ============ ENHANCED SEARCH AND FILTERING ============

  /// Search categories locally
  Future<List<Category>> searchCategoriesLocally(
    String query,
    String userId, {
    CategoryOwnershipType? ownershipType,
  }) async {
    final db = await database;

    String whereClause = 'ownerId = ? AND name LIKE ? AND isArchived = 0';
    List<dynamic> whereArgs = [userId, '%$query%'];

    if (ownershipType != null) {
      whereClause += ' AND ownershipType = ?';
      whereArgs.add(ownershipType.name);
    }

    final result = await db.query(
      'categories',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'name ASC',
      limit: 20,
    );

    return result.map((map) => _categoryFromMapEnhanced(map)).toList();
  }

  /// Get categories by spending amount (most used first)
  Future<List<Category>> getCategoriesBySpending(
    String userId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    final db = await database;

    try {
      final result = await db.rawQuery(
        '''
        SELECT 
          c.*,
          COALESCE(SUM(t.amount), 0) as totalSpent,
          COUNT(t.id) as transactionCount
        FROM categories c
        LEFT JOIN transactions t ON c.id = t.category_id 
          AND t.date >= ? AND t.date <= ?
          AND t.user_id = ?
        WHERE c.ownerId = ? AND c.isArchived = 0
        GROUP BY c.id
        ORDER BY totalSpent DESC, transactionCount DESC
      ''',
        [
          startDate.toIso8601String(),
          endDate.toIso8601String(),
          userId,
          userId,
        ],
      );

      return result.map((row) {
        // Convert row to category map format
        final categoryMap = Map<String, dynamic>.from(row);
        categoryMap.remove('totalSpent');
        categoryMap.remove('transactionCount');
        return _categoryFromMapEnhanced(categoryMap);
      }).toList();
    } catch (e) {
      print('❌ Error getting categories by spending: $e');
      return [];
    }
  }

  // ============ BACKUP AND RESTORE ============

  /// Backup categories and budgets data
  Future<Map<String, dynamic>> backupCategoriesAndBudgets(String userId) async {
    final db = await database;

    try {
      // Backup categories
      final categories = await db.query(
        'categories',
        where: 'ownerId = ?',
        whereArgs: [userId],
      );

      // Backup budgets
      final budgets = await db.query(
        'budgets',
        where: 'ownerId = ?',
        whereArgs: [userId],
      );

      return {
        'categories': categories,
        'budgets': budgets,
        'backupTime': DateTime.now().toIso8601String(),
        'version': '1.0',
      };
    } catch (e) {
      print('❌ Error backing up categories and budgets: $e');
      return {};
    }
  }

  /// Restore categories and budgets from backup
  Future<void> restoreCategoriesAndBudgets(
    Map<String, dynamic> backupData,
  ) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        // Restore categories
        final categories = backupData['categories'] as List<dynamic>?;
        if (categories != null) {
          for (final categoryData in categories) {
            await txn.insert(
              'categories',
              Map<String, dynamic>.from(categoryData),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        // Restore budgets
        final budgets = backupData['budgets'] as List<dynamic>?;
        if (budgets != null) {
          for (final budgetData in budgets) {
            await txn.insert(
              'budgets',
              Map<String, dynamic>.from(budgetData),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      });

      print('✅ Categories and budgets restored successfully');
    } catch (e) {
      print('❌ Error restoring categories and budgets: $e');
      rethrow;
    }
  }

  // ============ SMART SUGGESTIONS ============

  /// Get smart category suggestions based on description
  Future<List<Category>> getSmartCategorySuggestions(
    String description,
    String userId,
    String type,
  ) async {
    final db = await database;

    try {
      // First, try to find categories that have been used with similar descriptions
      final result = await db.rawQuery(
        '''
        SELECT DISTINCT c.*, COUNT(t.id) as usage_count
        FROM categories c
        INNER JOIN transactions t ON c.id = t.category_id
        WHERE c.ownerId = ? AND c.type = ? AND c.isArchived = 0
          AND (t.description LIKE ? OR t.description LIKE ?)
        GROUP BY c.id
        ORDER BY usage_count DESC, c.name ASC
        LIMIT 5
      ''',
        [userId, type, '%$description%', '%${description.toLowerCase()}%'],
      );

      List<Category> suggestions = result.map((row) {
        final categoryMap = Map<String, dynamic>.from(row);
        categoryMap.remove('usage_count');
        return _categoryFromMapEnhanced(categoryMap);
      }).toList();

      // If no suggestions from transactions, get most used categories
      if (suggestions.isEmpty) {
        final fallbackResult = await db.rawQuery(
          '''
          SELECT c.*, COUNT(t.id) as usage_count
          FROM categories c
          LEFT JOIN transactions t ON c.id = t.category_id
          WHERE c.ownerId = ? AND c.type = ? AND c.isArchived = 0
          GROUP BY c.id
          ORDER BY usage_count DESC, c.name ASC
          LIMIT 3
        ''',
          [userId, type],
        );

        suggestions = fallbackResult.map((row) {
          final categoryMap = Map<String, dynamic>.from(row);
          categoryMap.remove('usage_count');
          return _categoryFromMapEnhanced(categoryMap);
        }).toList();
      }

      return suggestions;
    } catch (e) {
      print('❌ Error getting smart category suggestions: $e');
      return [];
    }
  }

  /// Get budget recommendations based on historical spending
  Future<Map<String, double>> getBudgetRecommendations(
    String userId,
    String month,
  ) async {
    final db = await database;

    try {
      // Get average spending for each category over the last 3 months
      final result = await db.rawQuery(
        '''
        SELECT 
          t.category_id,
          c.name as category_name,
          AVG(monthly_spending.total) as avg_spending
        FROM (
          SELECT 
            category_id,
            strftime('%Y-%m', date) as month,
            SUM(amount) as total
          FROM transactions
          WHERE user_id = ? AND type = 'expense'
            AND strftime('%Y-%m', date) >= date(?, '-3 months')
            AND strftime('%Y-%m', date) < ?
          GROUP BY category_id, month
        ) monthly_spending
        JOIN transactions t ON monthly_spending.category_id = t.category_id
        JOIN categories c ON t.category_id = c.id
        WHERE c.ownerId = ?
        GROUP BY t.category_id, c.name
        HAVING COUNT(monthly_spending.month) >= 2
        ORDER BY avg_spending DESC
      ''',
        [userId, month, month, userId],
      );

      Map<String, double> recommendations = {};
      for (final row in result) {
        final categoryId = row['category_id'] as String;
        final avgSpending = (row['avg_spending'] as num).toDouble();

        // Add 10% buffer to average spending
        recommendations[categoryId] = (avgSpending * 1.1).roundToDouble();
      }

      return recommendations;
    } catch (e) {
      print('❌ Error getting budget recommendations: $e');
      return {};
    }
  }
}
