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
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        categoryId TEXT,
        walletId TEXT NOT NULL,
        date TEXT NOT NULL,
        description TEXT,
        userId TEXT NOT NULL,
        subCategoryId TEXT,
        transferToWalletId TEXT,
        syncStatus INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s', 'now')),
        updatedAt INTEGER DEFAULT (strftime('%s', 'now'))
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
        tableName TEXT NOT NULL,
        recordId TEXT NOT NULL,
        operation TEXT NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
        data TEXT, -- JSON data
        priority INTEGER DEFAULT 1,
        retryCount INTEGER DEFAULT 0,
        createdAt INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');

    // Index cho performance
    await db.execute(
      'CREATE INDEX idx_transactions_date ON transactions(date)',
    );
    await db.execute(
      'CREATE INDEX idx_transactions_user ON transactions(userId)',
    );
    await db.execute(
      'CREATE INDEX idx_description_history_user ON description_history(userId)',
    );
    await db.execute(
      'CREATE INDEX idx_sync_queue_priority ON sync_queue(priority, createdAt)',
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
}
