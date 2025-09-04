// lib/data/services/local_database_service.dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'dart:convert';

class LocalDatabaseService {
  static Database? _database;
  static const String _databaseName = 'moneysun_local.db';
  static const int _databaseVersion = 1;

  // Singleton pattern
  static final LocalDatabaseService _instance =
      LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createTables,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createTables(Database db, int version) async {
    // Bảng transactions
    await db.execute('''
      CREATE TABLE transactions (
      id TEXT PRIMARY KEY,
      firebase_id TEXT UNIQUE, -- Firebase document ID
      amount REAL NOT NULL,
      type TEXT NOT NULL,
      category_id TEXT,
      wallet_id TEXT NOT NULL,
      date TEXT NOT NULL,
      description TEXT,
      user_id TEXT NOT NULL,
      sub_category_id TEXT,
      transfer_to_wallet_id TEXT,
      
      sync_status INTEGER DEFAULT 0, -- 0: pending, 1: synced, 2: conflict, 3: error
      last_modified INTEGER DEFAULT (strftime('%s', 'now')),
      version INTEGER DEFAULT 1,
      checksum TEXT, -- For conflict detection
      
      conflict_data TEXT, 
      resolved_at INTEGER,
      
      created_at INTEGER DEFAULT (strftime('%s', 'now')),
      updated_at INTEGER DEFAULT (strftime('%s', 'now')),
      deleted_at INTEGER, 
      
      FOREIGN KEY (wallet_id) REFERENCES wallets(id),
      FOREIGN KEY (category_id) REFERENCES categories(id)
    )
    ''');

    // Bảng wallets
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

    // Bảng categories
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

    // Bảng description_history - V7 requirement
    await db.execute('''
      CREATE TABLE description_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL,
        description TEXT NOT NULL,
        usageCount INTEGER DEFAULT 1,
        lastUsed INTEGER DEFAULT (strftime('%s', 'now')),
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Bảng sync_queue để quản lý offline sync
    await db.execute('''
      CREATE TABLE sync_queue (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      table_name TEXT NOT NULL,
      record_id TEXT NOT NULL,
      firebase_id TEXT,
      operation TEXT NOT NULL,
      data TEXT NOT NULL,
      priority INTEGER DEFAULT 1,
      retry_count INTEGER DEFAULT 0,
      max_retries INTEGER DEFAULT 3,
      last_error TEXT,
      scheduled_at INTEGER DEFAULT (strftime('%s', 'now')),
      created_at INTEGER DEFAULT (strftime('%s', 'now')),
      
      UNIQUE(table_name, record_id, operation)
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
      operation TEXT NOT NULL, -- INSERT, UPDATE, DELETE
      changes TEXT, -- JSON of changed fields
      user_id TEXT NOT NULL,
      created_at INTEGER DEFAULT (strftime('%s', 'now'))
    )
    ''');

    // Index cho performance
    await db.execute(
      'CREATE INDEX idx_transactions_sync_status ON transactions(sync_status, last_modified)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_user_date ON transactions(user_id, date)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_firebase_id ON transactions(firebase_id)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_checksum ON transactions(checksum)',
    );
    await db.execute(
      'CREATE INDEX idx_change_log_user_time ON change_log(user_id, created_at);',
    );
  }

  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // Handle database upgrades if needed in future versions
    if (oldVersion < 2) {
      // Example upgrade logic for future versions
    }
  }

  // ============ TRANSACTIONS ============
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

  Future<Map<String, String?>> getSyncMetadata() async {
    final db = await database;

    final result = await db.query('sync_metadata');
    final Map<String, String?> metadata = {};

    for (final row in result) {
      metadata[row['key'] as String] = row['value'] as String?;
    }

    return metadata;
  }

  // Thêm method để set sync metadata
  Future<void> setSyncMetadata(String key, String value) async {
    final db = await database;

    await db.insert('sync_metadata', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Thêm method để track sync performance
  Future<void> logSyncOperation({
    required String operation,
    required String tableName,
    required bool success,
    String? error,
  }) async {
    final db = await database;

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
    });
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
      // Check if description exists
      final existing = await db.query(
        'description_history',
        where: 'userId = ? AND description = ?',
        whereArgs: [userId, description.trim()],
        limit: 1,
      );

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      if (existing.isNotEmpty) {
        // Update existing entry
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
        // Insert new entry
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
      print('Error saving description with context: $e');
      rethrow;
    }
  }

  /// Get smart description suggestions based on usage patterns
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

      // Filter by transaction type if provided
      if (type != null) {
        whereClause += ' AND (type = ? OR type IS NULL)';
        whereArgs.add(type);
      }

      // Filter by query if provided
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
      print('Error getting smart description suggestions: $e');
      return [];
    }
  }

  /// Advanced search with fuzzy matching and context awareness
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

      // Add type filter
      if (type != null) {
        whereClause += ' AND (type = ? OR type IS NULL)';
        whereArgs.add(type);
      }

      List<String> results = [];

      if (fuzzySearch) {
        // First: Exact matches
        final exactMatches = await db.query(
          'description_history',
          where: '$whereClause AND description LIKE ?',
          whereArgs: [...whereArgs, '$query%'],
          orderBy: 'usageCount DESC, lastUsed DESC',
          limit: limit,
        );
        results.addAll(exactMatches.map((m) => m['description'] as String));

        // Second: Contains matches (if we need more results)
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

        // Third: Fuzzy matches using SOUNDEX or similar words
        if (results.length < limit && query.length >= 3) {
          final fuzzyMatches = await db.query(
            'description_history',
            where:
                '''
              $whereClause AND 
              description NOT LIKE ? AND 
              (
                LENGTH(description) - LENGTH(REPLACE(LOWER(description), LOWER(?), '')) > 0 OR
                SUBSTR(description, 1, 3) = SUBSTR(?, 1, 3)
              )
            ''',
            whereArgs: [...whereArgs, '%$query%', query, query],
            orderBy: 'usageCount DESC, lastUsed DESC',
            limit: limit - results.length,
          );
          results.addAll(fuzzyMatches.map((m) => m['description'] as String));
        }
      } else {
        // Simple search
        final simpleMatches = await db.query(
          'description_history',
          where: '$whereClause AND description LIKE ?',
          whereArgs: [...whereArgs, '%$query%'],
          orderBy: 'usageCount DESC, lastUsed DESC',
          limit: limit,
        );
        results.addAll(simpleMatches.map((m) => m['description'] as String));
      }

      // Remove duplicates while preserving order
      return results.toSet().toList().take(limit).toList();
    } catch (e) {
      print('Error in advanced description search: $e');
      return [];
    }
  }

  /// Get contextual suggestions based on similar transactions
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

      // Build context-aware query
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
        // Find descriptions used for similar amounts (within 20% range)
        final minAmount = amount * 0.8;
        final maxAmount = amount * 1.2;
        conditions.add('amount BETWEEN ? AND ?');
        whereArgs.addAll([minAmount, maxAmount]);
      }

      if (conditions.isNotEmpty) {
        whereClause += ' AND (${conditions.join(' OR ')})';
      }

      // FIX: Use proper SQL query without orderByArgs
      String orderByClause;
      if (type != null && categoryId != null) {
        orderByClause =
            '''
          CASE
            WHEN type = '$type' AND categoryId = '$categoryId' THEN usageCount * 3
            WHEN type = '$type' THEN usageCount * 2
            WHEN categoryId = '$categoryId' THEN usageCount * 1.5
            ELSE usageCount
          END DESC,
          lastUsed DESC
        ''';
      } else if (type != null) {
        orderByClause =
            '''
          CASE
            WHEN type = '$type' THEN usageCount * 2
            ELSE usageCount
          END DESC,
          lastUsed DESC
        ''';
      } else if (categoryId != null) {
        orderByClause =
            '''
          CASE
            WHEN categoryId = '$categoryId' THEN usageCount * 2
            ELSE usageCount
          END DESC,
          lastUsed DESC
        ''';
      } else {
        orderByClause = 'usageCount DESC, lastUsed DESC';
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
      print('Error getting contextual suggestions: $e');
      return [];
    }
  }

  /// Get trending descriptions (most used in recent period)
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
      print('Error getting trending descriptions: $e');
      return [];
    }
  }

  /// Clean up old description entries to maintain performance
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

      // Keep frequently used descriptions even if old
      await db.delete(
        'description_history',
        where: 'userId = ? AND lastUsed < ? AND usageCount < 5',
        whereArgs: [userId, cutoffTime],
      );

      print('✅ Cleaned up old description history');
    } catch (e) {
      print('Error cleaning up description history: $e');
    }
  }

  /// Get description statistics for debugging/analytics
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
      print('Error getting description stats: $e');
      return {};
    }
  }

  // ============ ENHANCED DATABASE SCHEMA ============

  // Update the _createTables method to include new columns
  Future<void> _createEnhancedDescriptionTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS description_history_enhanced (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL,
        description TEXT NOT NULL,
        usageCount INTEGER DEFAULT 1,
        lastUsed INTEGER DEFAULT (strftime('%s', 'now')),
        createdAt INTEGER DEFAULT (strftime('%s', 'now')),
        updatedAt INTEGER DEFAULT (strftime('%s', 'now')),
        
        -- Context information
        type TEXT, -- 'income', 'expense', 'transfer'
        categoryId TEXT,
        amount REAL,
        
        -- Performance indexes
        UNIQUE(userId, description),
        INDEX(userId, type),
        INDEX(userId, categoryId),
        INDEX(userId, lastUsed),
        INDEX(userId, usageCount),
        INDEX(description)
      )
    ''');
  }

  // Migrate existing data if needed
  Future<void> migrateDescriptionHistory() async {
    final db = await database;

    try {
      // Check if old table exists
      final tables = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'description_history'],
      );

      if (tables.isNotEmpty) {
        // Check if new columns exist
        final columns = await db.rawQuery(
          'PRAGMA table_info(description_history)',
        );
        final hasTypeColumn = columns.any((col) => col['name'] == 'type');

        if (!hasTypeColumn) {
          // Add new columns to existing table
          await db.execute(
            'ALTER TABLE description_history ADD COLUMN type TEXT',
          );
          await db.execute(
            'ALTER TABLE description_history ADD COLUMN categoryId TEXT',
          );
          await db.execute(
            'ALTER TABLE description_history ADD COLUMN amount REAL',
          );
          await db.execute(
            'ALTER TABLE description_history ADD COLUMN updatedAt INTEGER DEFAULT (strftime(\'%s\', \'now\'))',
          );

          print('✅ Migrated description_history table with new columns');
        }
      }
    } catch (e) {
      print('Error migrating description history: $e');
    }
  }
}
