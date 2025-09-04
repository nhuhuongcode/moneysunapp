// lib/data/services/local_database_service.dart - ENHANCED VERSION
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'dart:convert';

class LocalDatabaseService {
  static Database? _database;
  static const String _databaseName = 'moneysun_local.db';
  static const int _databaseVersion = 2; // Increased version

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

      // Enhanced description_history table
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

      // Sync queue table
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

      // Sync metadata table
      await db.execute('''
        CREATE TABLE sync_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at INTEGER DEFAULT (strftime('%s', 'now'))
        )
      ''');

      // Change log table
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

  Future<void> _createIndexes(Database db) async {
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_transactions_sync_status ON transactions(sync_status, last_modified)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_user_date ON transactions(user_id, date)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_firebase_id ON transactions(firebase_id)',
      'CREATE INDEX IF NOT EXISTS idx_transactions_checksum ON transactions(checksum)',
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

  Future<void> _upgradeToVersion2(Database db) async {
    try {
      // Add missing columns to description_history if they don't exist
      final columns = await db.rawQuery(
        'PRAGMA table_info(description_history)',
      );
      final columnNames = columns.map((col) => col['name'] as String).toSet();

      final newColumns = {
        'type': 'TEXT',
        'categoryId': 'TEXT',
        'amount': 'REAL',
        'updatedAt': 'INTEGER DEFAULT (strftime(\'%s\', \'now\'))',
      };

      for (final entry in newColumns.entries) {
        if (!columnNames.contains(entry.key)) {
          await db.execute(
            'ALTER TABLE description_history ADD COLUMN ${entry.key} ${entry.value}',
          );
          print('✅ Added column: ${entry.key}');
        }
      }

      await _createIndexes(db);
      print('✅ Successfully upgraded to version 2');
    } catch (e) {
      print('❌ Error upgrading database: $e');
      rethrow;
    }
  }

  // ============ ENHANCED TRANSACTIONS METHODS ============

  Future<void> saveTransactionLocally(
    TransactionModel transaction, {
    int syncStatus = 0,
  }) async {
    final db = await database;

    try {
      // Generate unique ID if not provided
      final transactionId = transaction.id.isEmpty
          ? DateTime.now().millisecondsSinceEpoch.toString()
          : transaction.id;

      await db.insert('transactions', {
        'id': transactionId,
        'amount': transaction.amount,
        'type': transaction.type.name,
        'category_id': transaction.categoryId,
        'wallet_id': transaction.walletId,
        'date': transaction.date.toIso8601String(),
        'description': transaction.description,
        'user_id': transaction.userId,
        'sub_category_id': transaction.subCategoryId,
        'transfer_to_wallet_id': transaction.transferToWalletId,
        'sync_status': syncStatus,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      // Add to sync queue if not synced
      if (syncStatus == 0) {
        final transactionWithId = TransactionModel(
          id: transactionId,
          amount: transaction.amount,
          type: transaction.type,
          categoryId: transaction.categoryId,
          walletId: transaction.walletId,
          date: transaction.date,
          description: transaction.description,
          userId: transaction.userId,
          subCategoryId: transaction.subCategoryId,
          transferToWalletId: transaction.transferToWalletId,
        );

        await addToSyncQueue(
          'transactions',
          transactionId,
          'INSERT',
          transactionWithId.toJson(),
        );
      }

      print('✅ Transaction saved locally: $transactionId');
    } catch (e) {
      print('❌ Error saving transaction locally: $e');
      rethrow;
    }
  }

  Future<List<TransactionModel>> getLocalTransactions({
    String? userId,
    DateTime? startDate,
    DateTime? endDate,
    int? limit,
  }) async {
    final db = await database;

    try {
      String whereClause = '1=1';
      List<dynamic> whereArgs = [];

      if (userId != null) {
        whereClause += ' AND user_id = ?';
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

      final transactions = result
          .map((map) => _transactionFromMap(map))
          .toList();
      print('✅ Retrieved ${transactions.length} local transactions');

      return transactions;
    } catch (e) {
      print('❌ Error getting local transactions: $e');
      return [];
    }
  }

  TransactionModel _transactionFromMap(Map<String, dynamic> map) {
    try {
      return TransactionModel(
        id: map['id'] ?? '',
        amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
        type: TransactionType.values.firstWhere(
          (e) => e.name == map['type'],
          orElse: () => TransactionType.expense,
        ),
        categoryId: map['category_id'],
        walletId: map['wallet_id'] ?? '',
        date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
        description: map['description'] ?? '',
        userId: map['user_id'] ?? '',
        subCategoryId: map['sub_category_id'],
        transferToWalletId: map['transfer_to_wallet_id'],
      );
    } catch (e) {
      print('⚠️ Error parsing transaction: $e');
      // Return a default transaction to prevent crashes
      return TransactionModel(
        id: map['id'] ?? 'error_${DateTime.now().millisecondsSinceEpoch}',
        amount: 0.0,
        type: TransactionType.expense,
        walletId: '',
        date: DateTime.now(),
        description: 'Error loading transaction',
        userId: map['user_id'] ?? '',
      );
    }
  }

  // ============ ENHANCED WALLETS METHODS ============

  Future<void> saveWalletLocally(Wallet wallet, {int syncStatus = 0}) async {
    final db = await database;

    try {
      await db.insert('wallets', {
        'id': wallet.id.isEmpty
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : wallet.id,
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

      print('✅ Wallet saved locally: ${wallet.id}');
    } catch (e) {
      print('❌ Error saving wallet locally: $e');
      rethrow;
    }
  }

  Future<List<Wallet>> getLocalWallets(String ownerId) async {
    final db = await database;

    try {
      final result = await db.query(
        'wallets',
        where: 'ownerId = ?',
        whereArgs: [ownerId],
        orderBy: 'name ASC',
      );

      final wallets = result.map((map) => _walletFromMap(map)).toList();
      print('✅ Retrieved ${wallets.length} local wallets for owner: $ownerId');

      return wallets;
    } catch (e) {
      print('❌ Error getting local wallets: $e');
      return [];
    }
  }

  Wallet _walletFromMap(Map<String, dynamic> map) {
    try {
      return Wallet(
        id: map['id'] ?? '',
        name: map['name'] ?? 'Unknown Wallet',
        balance: (map['balance'] as num?)?.toDouble() ?? 0.0,
        ownerId: map['ownerId'] ?? '',
        isVisibleToPartner: (map['isVisibleToPartner'] as int?) == 1,
      );
    } catch (e) {
      print('⚠️ Error parsing wallet: $e');
      return Wallet(
        id: map['id'] ?? 'error_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Error Loading Wallet',
        balance: 0.0,
        ownerId: map['ownerId'] ?? '',
      );
    }
  }

  // ============ ENHANCED CATEGORIES METHODS ============

  Future<void> saveCategoryLocally(
    Category category, {
    int syncStatus = 0,
  }) async {
    final db = await database;

    try {
      await db.insert('categories', {
        'id': category.id.isEmpty
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : category.id,
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

      print('✅ Category saved locally: ${category.id}');
    } catch (e) {
      print('❌ Error saving category locally: $e');
      rethrow;
    }
  }

  Future<List<Category>> getLocalCategories({
    String? ownerId,
    String? type,
  }) async {
    final db = await database;

    try {
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

      final categories = result.map((map) => _categoryFromMap(map)).toList();
      print('✅ Retrieved ${categories.length} local categories');

      return categories;
    } catch (e) {
      print('❌ Error getting local categories: $e');
      return [];
    }
  }

  Category _categoryFromMap(Map<String, dynamic> map) {
    try {
      final subCategoriesJson = map['subCategories'] as String?;
      Map<String, String> subCategories = {};

      if (subCategoriesJson != null && subCategoriesJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(subCategoriesJson);
          if (decoded is Map) {
            subCategories = Map<String, String>.from(decoded);
          }
        } catch (e) {
          print('⚠️ Error decoding subCategories: $e');
        }
      }

      return Category(
        id: map['id'] ?? '',
        name: map['name'] ?? 'Unknown Category',
        ownerId: map['ownerId'] ?? '',
        type: map['type'] ?? 'expense',
        iconCodePoint: map['iconCodePoint'] as int?,
        subCategories: subCategories,
      );
    } catch (e) {
      print('⚠️ Error parsing category: $e');
      return Category(
        id: map['id'] ?? 'error_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Error Loading Category',
        ownerId: map['ownerId'] ?? '',
        type: 'expense',
      );
    }
  }

  // ============ ENHANCED DESCRIPTION HISTORY METHODS ============

  Future<void> saveDescriptionToHistory(
    String userId,
    String description,
  ) async {
    if (description.trim().isEmpty) return;

    final db = await database;

    try {
      final existing = await db.query(
        'description_history',
        where: 'userId = ? AND description = ?',
        whereArgs: [userId, description.trim()],
        limit: 1,
      );

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (existing.isNotEmpty) {
        await db.update(
          'description_history',
          {
            'usageCount': (existing.first['usageCount'] as int? ?? 0) + 1,
            'lastUsed': now,
            'updatedAt': now,
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await db.insert('description_history', {
          'userId': userId,
          'description': description.trim(),
          'usageCount': 1,
          'lastUsed': now,
          'createdAt': now,
          'updatedAt': now,
        });
      }

      print('✅ Description saved to history: $description');
    } catch (e) {
      print('❌ Error saving description to history: $e');
    }
  }

  Future<List<String>> getDescriptionSuggestions(
    String userId, {
    int limit = 10,
  }) async {
    final db = await database;

    try {
      final result = await db.query(
        'description_history',
        where: 'userId = ?',
        whereArgs: [userId],
        orderBy: 'usageCount DESC, lastUsed DESC',
        limit: limit,
      );

      return result.map((map) => map['description'] as String).toList();
    } catch (e) {
      print('❌ Error getting description suggestions: $e');
      return [];
    }
  }

  Future<void> saveDescriptionWithContext(
    String userId,
    String description, {
    String? type,
    String? categoryId,
    double? amount,
  }) async {
    if (description.trim().isEmpty) return;

    final db = await database;

    try {
      final existing = await db.query(
        'description_history',
        where: 'userId = ? AND description = ?',
        whereArgs: [userId, description.trim()],
        limit: 1,
      );

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (existing.isNotEmpty) {
        await db.update(
          'description_history',
          {
            'usageCount': (existing.first['usageCount'] as int? ?? 0) + 1,
            'lastUsed': now,
            'type': type,
            'categoryId': categoryId,
            'amount': amount,
            'updatedAt': now,
          },
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await db.insert('description_history', {
          'userId': userId,
          'description': description.trim(),
          'usageCount': 1,
          'lastUsed': now,
          'type': type,
          'categoryId': categoryId,
          'amount': amount,
          'createdAt': now,
          'updatedAt': now,
        });
      }
    } catch (e) {
      print('❌ Error saving description with context: $e');
    }
  }

  Future<List<String>> getSmartDescriptionSuggestions(
    String userId, {
    int limit = 10,
    String? query,
    String? type,
  }) async {
    final db = await database;

    try {
      String whereClause = 'userId = ?';
      List<dynamic> whereArgs = [userId];

      if (type != null) {
        whereClause += ' AND (type = ? OR type IS NULL)';
        whereArgs.add(type);
      }

      if (query != null && query.isNotEmpty) {
        whereClause += ' AND description LIKE ?';
        whereArgs.add('%$query%');
      }

      final result = await db.query(
        'description_history',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy:
            '''
          CASE 
            WHEN lastUsed > ${DateTime.now().subtract(const Duration(days: 7)).millisecondsSinceEpoch ~/ 1000} THEN usageCount * 2
            WHEN lastUsed > ${DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000} THEN usageCount * 1.5
            ELSE usageCount 
          END DESC, 
          lastUsed DESC
        ''',
        limit: limit,
      );

      return result.map((map) => map['description'] as String).toList();
    } catch (e) {
      print('❌ Error getting smart description suggestions: $e');
      return [];
    }
  }

  Future<List<String>> searchDescriptionHistory(
    String userId,
    String query, {
    int limit = 5,
    String? type,
    bool fuzzySearch = true,
  }) async {
    if (query.trim().isEmpty) return [];

    final db = await database;

    try {
      String whereClause = 'userId = ?';
      List<dynamic> whereArgs = [userId];

      if (type != null) {
        whereClause += ' AND (type = ? OR type IS NULL)';
        whereArgs.add(type);
      }

      List<String> results = [];

      if (fuzzySearch) {
        // Exact matches first
        final exactMatches = await db.query(
          'description_history',
          where: '$whereClause AND description LIKE ?',
          whereArgs: [...whereArgs, '$query%'],
          orderBy: 'usageCount DESC, lastUsed DESC',
          limit: limit,
        );
        results.addAll(exactMatches.map((m) => m['description'] as String));

        // Contains matches
        if (results.length < limit) {
          final containsMatches = await db.query(
            'description_history',
            where:
                '$whereClause AND description LIKE ? AND description NOT LIKE ?',
            whereArgs: [...whereArgs, '%$query%', '$query%'],
            orderBy: 'usageCount DESC, lastUsed DESC',
            limit: limit - results.length,
          );
          results.addAll(
            containsMatches.map((m) => m['description'] as String),
          );
        }
      } else {
        final simpleMatches = await db.query(
          'description_history',
          where: '$whereClause AND description LIKE ?',
          whereArgs: [...whereArgs, '%$query%'],
          orderBy: 'usageCount DESC, lastUsed DESC',
          limit: limit,
        );
        results.addAll(simpleMatches.map((m) => m['description'] as String));
      }

      return results.toSet().toList().take(limit).toList();
    } catch (e) {
      print('❌ Error in description search: $e');
      return [];
    }
  }

  Future<List<String>> getContextualSuggestions(
    String userId, {
    String? type,
    String? categoryId,
    double? amount,
    int limit = 5,
  }) async {
    final db = await database;

    try {
      String whereClause = 'userId = ?';
      List<dynamic> whereArgs = [userId];

      List<String> conditions = [];

      if (type != null) {
        conditions.add('type = ?');
        whereArgs.add(type);
      }

      if (categoryId != null) {
        conditions.add('categoryId = ?');
        whereArgs.add(categoryId);
      }

      if (amount != null) {
        final minAmount = amount * 0.8;
        final maxAmount = amount * 1.2;
        conditions.add('amount BETWEEN ? AND ?');
        whereArgs.addAll([minAmount, maxAmount]);
      }

      if (conditions.isNotEmpty) {
        whereClause += ' AND (${conditions.join(' OR ')})';
      }

      String orderByClause = 'usageCount DESC, lastUsed DESC';
      if (type != null && categoryId != null) {
        orderByClause = '''
          CASE
            WHEN type = ? AND categoryId = ? THEN usageCount * 3
            WHEN type = ? THEN usageCount * 2
            WHEN categoryId = ? THEN usageCount * 1.5
            ELSE usageCount
          END DESC,
          lastUsed DESC
        ''';
        whereArgs.addAll([type, categoryId, type, categoryId]);
      }

      final result = await db.query(
        'description_history',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: orderByClause,
        limit: limit,
      );

      return result.map((map) => map['description'] as String).toList();
    } catch (e) {
      print('❌ Error getting contextual suggestions: $e');
      return [];
    }
  }

  // ============ SYNC QUEUE MANAGEMENT ============

  Future<void> addToSyncQueue(
    String tableName,
    String recordId,
    String operation,
    Map<String, dynamic> data,
  ) async {
    final db = await database;

    try {
      await db.insert('sync_queue', {
        'tableName': tableName,
        'recordId': recordId,
        'operation': operation,
        'data': jsonEncode(data),
        'priority': _getSyncPriority(operation),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print('❌ Error adding to sync queue: $e');
    }
  }

  int _getSyncPriority(String operation) {
    switch (operation) {
      case 'DELETE':
        return 3;
      case 'UPDATE':
        return 2;
      case 'INSERT':
        return 1;
      default:
        return 1;
    }
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems({
    int limit = 50,
  }) async {
    final db = await database;

    try {
      return await db.query(
        'sync_queue',
        where: 'retry_count < max_retries',
        orderBy: 'priority DESC, created_at ASC',
        limit: limit,
      );
    } catch (e) {
      print('❌ Error getting pending sync items: $e');
      return [];
    }
  }

  Future<void> removeSyncItem(int syncId) async {
    final db = await database;

    try {
      await db.delete('sync_queue', where: 'id = ?', whereArgs: [syncId]);
    } catch (e) {
      print('❌ Error removing sync item: $e');
    }
  }

  Future<void> incrementRetryCount(int syncId) async {
    final db = await database;

    try {
      await db.execute(
        'UPDATE sync_queue SET retry_count = retry_count + 1 WHERE id = ?',
        [syncId],
      );
    } catch (e) {
      print('❌ Error incrementing retry count: $e');
    }
  }

  // ============ SYNC STATUS MANAGEMENT ============

  Future<void> markAsSynced(String tableName, String recordId) async {
    final db = await database;

    try {
      await db.update(
        tableName,
        {
          'sync_status': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [recordId],
      );
    } catch (e) {
      print('❌ Error marking as synced: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getUnsyncedRecords(
    String tableName,
  ) async {
    final db = await database;

    try {
      return await db.query(
        tableName,
        where: 'sync_status = 0',
        orderBy: 'updated_at ASC',
      );
    } catch (e) {
      print('❌ Error getting unsynced records: $e');
      return [];
    }
  }

  // ============ METADATA MANAGEMENT ============

  Future<Map<String, String?>> getSyncMetadata() async {
    final db = await database;

    try {
      final result = await db.query('sync_metadata');
      final Map<String, String?> metadata = {};

      for (final row in result) {
        metadata[row['key'] as String] = row['value'] as String?;
      }

      return metadata;
    } catch (e) {
      print('❌ Error getting sync metadata: $e');
      return {};
    }
  }

  Future<void> setSyncMetadata(String key, String value) async {
    final db = await database;

    try {
      await db.insert('sync_metadata', {
        'key': key,
        'value': value,
        'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      print('❌ Error setting sync metadata: $e');
    }
  }

  Future<void> logSyncOperation({
    required String operation,
    required String tableName,
    required bool success,
    String? error,
  }) async {
    final db = await database;

    try {
      await db.insert('change_log', {
        'table_name': tableName,
        'record_id': 'sync_log',
        'operation': operation,
        'changes': jsonEncode({
          'success': success,
          'error': error,
          'timestamp': DateTime.now().toIso8601String(),
        }),
        'user_id': 'system',
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
    } catch (e) {
      print('❌ Error logging sync operation: $e');
    }
  }

  // ============ UTILITY METHODS ============

  Future<void> clearAllData() async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        await txn.delete('transactions');
        await txn.delete('wallets');
        await txn.delete('categories');
        await txn.delete('description_history');
        await txn.delete('sync_queue');
        await txn.delete('sync_metadata');
        await txn.delete('change_log');
      });

      print('✅ All data cleared successfully');
    } catch (e) {
      print('❌ Error clearing all data: $e');
      rethrow;
    }
  }

  Future<void> clearSyncedData() async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        await txn.delete('transactions', where: 'sync_status = 1');
        await txn.delete('wallets', where: 'syncStatus = 1');
        await txn.delete('categories', where: 'syncStatus = 1');
        // Don't clear description_history as it's useful offline
      });

      print('✅ Synced data cleared successfully');
    } catch (e) {
      print('❌ Error clearing synced data: $e');
      rethrow;
    }
  }

  Future<Map<String, int>> getDatabaseStats() async {
    final db = await database;

    try {
      final transactions = await db.rawQuery(
        'SELECT COUNT(*) as count FROM transactions',
      );
      final wallets = await db.rawQuery(
        'SELECT COUNT(*) as count FROM wallets',
      );
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
    } catch (e) {
      print('❌ Error getting database stats: $e');
      return {
        'transactions': 0,
        'wallets': 0,
        'categories': 0,
        'descriptions': 0,
        'pendingSync': 0,
      };
    }
  }

  // ============ ADVANCED DESCRIPTION METHODS ============

  Future<List<String>> getTrendingDescriptions(
    String userId, {
    int days = 30,
    int limit = 10,
    String? type,
  }) async {
    final db = await database;

    try {
      final cutoffTime =
          DateTime.now()
              .subtract(Duration(days: days))
              .millisecondsSinceEpoch ~/
          1000;

      String whereClause = 'userId = ? AND lastUsed > ?';
      List<dynamic> whereArgs = [userId, cutoffTime];

      if (type != null) {
        whereClause += ' AND (type = ? OR type IS NULL)';
        whereArgs.add(type);
      }

      final result = await db.query(
        'description_history',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'usageCount DESC, lastUsed DESC',
        limit: limit,
      );

      return result.map((map) => map['description'] as String).toList();
    } catch (e) {
      print('❌ Error getting trending descriptions: $e');
      return [];
    }
  }

  Future<void> cleanupDescriptionHistory(
    String userId, {
    int keepDays = 365,
  }) async {
    final db = await database;

    try {
      final cutoffTime =
          DateTime.now()
              .subtract(Duration(days: keepDays))
              .millisecondsSinceEpoch ~/
          1000;

      final deletedCount = await db.delete(
        'description_history',
        where: 'userId = ? AND lastUsed < ? AND usageCount < 5',
        whereArgs: [userId, cutoffTime],
      );

      print('✅ Cleaned up $deletedCount old description entries');
    } catch (e) {
      print('❌ Error cleaning up description history: $e');
    }
  }

  Future<Map<String, dynamic>> getDescriptionStats(String userId) async {
    final db = await database;

    try {
      final totalCount = await db.query(
        'description_history',
        where: 'userId = ?',
        whereArgs: [userId],
      );

      final recentCount = await db.query(
        'description_history',
        where: 'userId = ? AND lastUsed > ?',
        whereArgs: [
          userId,
          DateTime.now()
                  .subtract(const Duration(days: 30))
                  .millisecondsSinceEpoch ~/
              1000,
        ],
      );

      final topUsed = await db.query(
        'description_history',
        where: 'userId = ?',
        whereArgs: [userId],
        orderBy: 'usageCount DESC',
        limit: 5,
      );

      return {
        'totalDescriptions': totalCount.length,
        'recentDescriptions': recentCount.length,
        'topUsedDescriptions': topUsed
            .map(
              (m) => {
                'description': m['description'],
                'count': m['usageCount'],
              },
            )
            .toList(),
      };
    } catch (e) {
      print('❌ Error getting description stats: $e');
      return {};
    }
  }

  // ============ DATABASE HEALTH & MAINTENANCE ============

  Future<void> vacuum() async {
    final db = await database;

    try {
      await db.execute('VACUUM');
      print('✅ Database vacuumed successfully');
    } catch (e) {
      print('❌ Error vacuuming database: $e');
    }
  }

  Future<void> analyze() async {
    final db = await database;

    try {
      await db.execute('ANALYZE');
      print('✅ Database analyzed successfully');
    } catch (e) {
      print('❌ Error analyzing database: $e');
    }
  }

  Future<Map<String, dynamic>> getDatabaseInfo() async {
    final db = await database;

    try {
      final version = await db.getVersion();

      final tables = await db.query(
        'sqlite_master',
        where: 'type = ?',
        whereArgs: ['table'],
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();

      final stats = await getDatabaseStats();

      return {
        'version': version,
        'path': db.path,
        'tables': tableNames,
        'stats': stats,
      };
    } catch (e) {
      print('❌ Error getting database info: $e');
      return {'error': e.toString()};
    }
  }

  // ============ BACKUP & RESTORE ============

  Future<Map<String, dynamic>> exportUserData(String userId) async {
    final db = await database;

    try {
      final transactions = await db.query(
        'transactions',
        where: 'user_id = ?',
        whereArgs: [userId],
      );

      final wallets = await db.query(
        'wallets',
        where: 'ownerId = ?',
        whereArgs: [userId],
      );

      final categories = await db.query(
        'categories',
        where: 'ownerId = ?',
        whereArgs: [userId],
      );

      final descriptions = await db.query(
        'description_history',
        where: 'userId = ?',
        whereArgs: [userId],
      );

      return {
        'exportDate': DateTime.now().toIso8601String(),
        'userId': userId,
        'transactions': transactions,
        'wallets': wallets,
        'categories': categories,
        'descriptions': descriptions,
      };
    } catch (e) {
      print('❌ Error exporting user data: $e');
      rethrow;
    }
  }

  Future<void> importUserData(Map<String, dynamic> data) async {
    final db = await database;

    try {
      await db.transaction((txn) async {
        // Import transactions
        final transactions = data['transactions'] as List? ?? [];
        for (final transaction in transactions) {
          await txn.insert(
            'transactions',
            transaction as Map<String, dynamic>,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Import wallets
        final wallets = data['wallets'] as List? ?? [];
        for (final wallet in wallets) {
          await txn.insert(
            'wallets',
            wallet as Map<String, dynamic>,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Import categories
        final categories = data['categories'] as List? ?? [];
        for (final category in categories) {
          await txn.insert(
            'categories',
            category as Map<String, dynamic>,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Import descriptions
        final descriptions = data['descriptions'] as List? ?? [];
        for (final description in descriptions) {
          await txn.insert(
            'description_history',
            description as Map<String, dynamic>,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      print('✅ User data imported successfully');
    } catch (e) {
      print('❌ Error importing user data: $e');
      rethrow;
    }
  }

  // ============ ERROR RECOVERY ============

  Future<bool> isHealthy() async {
    try {
      final db = await database;
      await db.query('sqlite_master', limit: 1);
      return true;
    } catch (e) {
      print('❌ Database health check failed: $e');
      return false;
    }
  }

  Future<void> repair() async {
    try {
      print('🔧 Attempting database repair...');

      // Close current database
      await close();

      // Reinitialize
      _database = await _initDatabase();

      print('✅ Database repair completed');
    } catch (e) {
      print('❌ Database repair failed: $e');
      rethrow;
    }
  }

  // ============ RESOURCE MANAGEMENT ============

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
      print('✅ Database closed successfully');
    }
  }

  Future<void> optimize() async {
    try {
      await analyze();
      await vacuum();
      print('✅ Database optimization completed');
    } catch (e) {
      print('❌ Database optimization failed: $e');
    }
  }
}
