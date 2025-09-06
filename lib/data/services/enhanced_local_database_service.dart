// lib/data/services/enhanced_local_database_service.dart
import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/services/local_database_service.dart';

extension EnhancedLocalDatabase on LocalDatabaseService {
  // ============ ENHANCED BUDGETS METHODS ============

  /// Create enhanced budgets table
  Future<void> createEnhancedBudgetsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS enhanced_budgets (
        id TEXT PRIMARY KEY,
        ownerId TEXT NOT NULL,
        month TEXT NOT NULL,
        totalAmount REAL NOT NULL DEFAULT 0,
        categoryAmounts TEXT DEFAULT '{}',
        budgetType TEXT DEFAULT 'personal',
        period TEXT DEFAULT 'monthly',
        createdBy TEXT,
        createdAt INTEGER,
        updatedAt INTEGER,
        startDate INTEGER,
        endDate INTEGER,
        isActive INTEGER DEFAULT 1,
        notes TEXT DEFAULT '{}',
        categoryLimits TEXT DEFAULT '{}',
        version INTEGER DEFAULT 1,
        isDeleted INTEGER DEFAULT 0,
        syncStatus INTEGER DEFAULT 0,
        lastModified INTEGER DEFAULT (strftime('%s', 'now')),
        
        UNIQUE(ownerId, month, budgetType),
        FOREIGN KEY (ownerId) REFERENCES users(id)
      )
    ''');

    // Create indexes for better query performance
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enhanced_budgets_owner_month 
      ON enhanced_budgets(ownerId, month)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enhanced_budgets_type_active 
      ON enhanced_budgets(budgetType, isActive)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enhanced_budgets_sync 
      ON enhanced_budgets(syncStatus, lastModified)
    ''');
  }

  /// Save budget with ownership support
  Future<void> saveBudgetWithOwnership(
    Budget budget, {
    int syncStatus = 0,
  }) async {
    final db = await database;

    await db.insert('enhanced_budgets', {
      'id': budget.id,
      'ownerId': budget.ownerId,
      'month': budget.month,
      'totalAmount': budget.totalAmount,
      'categoryAmounts': jsonEncode(budget.categoryAmounts),
      'budgetType': budget.budgetType.name,
      'period': budget.period.name,
      'createdBy': budget.createdBy,
      'createdAt': budget.createdAt?.millisecondsSinceEpoch,
      'updatedAt':
          budget.updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'startDate': budget.startDate?.millisecondsSinceEpoch,
      'endDate': budget.endDate?.millisecondsSinceEpoch,
      'isActive': budget.isActive ? 1 : 0,
      'notes': jsonEncode(budget.notes ?? {}),
      'categoryLimits': jsonEncode(budget.categoryLimits ?? {}),
      'version': budget.version,
      'isDeleted': budget.isDeleted ? 1 : 0,
      'syncStatus': syncStatus,
      'lastModified': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (syncStatus == 0) {
      await addToSyncQueue(
        'enhanced_budgets',
        budget.id,
        'INSERT',
        budget.toJson(),
      );
    }
  }

  /// Get budgets with ownership filtering
  Future<List<Budget>> getBudgetsWithOwnership(
    String userId,
    String? partnershipId, {
    String? month,
    BudgetType? budgetType,
    bool includeInactive = false,
    bool includeDeleted = false,
  }) async {
    final db = await database;

    String whereClause = '(ownerId = ?';
    List<dynamic> whereArgs = [userId];

    // Include shared budgets if partnership exists
    if (partnershipId != null) {
      whereClause += ' OR ownerId = ?';
      whereArgs.add(partnershipId);
    }
    whereClause += ')';

    // Add additional filters
    if (month != null) {
      whereClause += ' AND month = ?';
      whereArgs.add(month);
    }

    if (budgetType != null) {
      whereClause += ' AND budgetType = ?';
      whereArgs.add(budgetType.name);
    }

    if (!includeInactive) {
      whereClause += ' AND isActive = 1';
    }

    if (!includeDeleted) {
      whereClause += ' AND isDeleted = 0';
    }

    final result = await db.query(
      'enhanced_budgets',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'month DESC, budgetType ASC, updatedAt DESC',
    );

    return result.map((map) => _budgetFromMap(map)).toList();
  }

  /// Get budget by month and type with ownership
  Future<Budget?> getBudgetByMonthAndType(
    String month,
    BudgetType budgetType,
    String userId,
    String? partnershipId,
  ) async {
    final db = await database;

    String ownerId = budgetType == BudgetType.shared
        ? (partnershipId ?? userId)
        : userId;

    final result = await db.query(
      'enhanced_budgets',
      where:
          'ownerId = ? AND month = ? AND budgetType = ? AND isActive = 1 AND isDeleted = 0',
      whereArgs: [ownerId, month, budgetType.name],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return _budgetFromMap(result.first);
    }
    return null;
  }

  /// Update budget locally
  Future<void> updateBudgetWithOwnership(Budget budget) async {
    final db = await database;

    await db.update(
      'enhanced_budgets',
      {
        'totalAmount': budget.totalAmount,
        'categoryAmounts': jsonEncode(budget.categoryAmounts),
        'notes': jsonEncode(budget.notes ?? {}),
        'categoryLimits': jsonEncode(budget.categoryLimits ?? {}),
        'isActive': budget.isActive ? 1 : 0,
        'version': budget.version + 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lastModified': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'syncStatus': 0, // Mark as needing sync
      },
      where: 'id = ?',
      whereArgs: [budget.id],
    );

    // Add to sync queue
    await addToSyncQueue(
      'enhanced_budgets',
      budget.id,
      'UPDATE',
      budget.toJson(),
    );
  }

  /// Soft delete budget
  Future<void> softDeleteBudget(String budgetId) async {
    final db = await database;

    await db.update(
      'enhanced_budgets',
      {
        'isDeleted': 1,
        'isActive': 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lastModified': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'syncStatus': 0,
      },
      where: 'id = ?',
      whereArgs: [budgetId],
    );

    await addToSyncQueue('enhanced_budgets', budgetId, 'DELETE', {
      'id': budgetId,
    });
  }

  /// Get budget recommendations based on historical data
  Future<Map<String, double>> getBudgetRecommendations(
    String userId,
    String month, {
    int lookbackMonths = 3,
  }) async {
    final db = await database;

    try {
      // Get spending data from transactions for the last N months
      final result = await db.rawQuery(
        '''
        SELECT 
          t.categoryId,
          c.name as categoryName,
          AVG(monthly_spending.total) as avgSpending,
          COUNT(monthly_spending.month) as monthCount
        FROM (
          SELECT 
            categoryId,
            strftime('%Y-%m', date) as month,
            SUM(amount) as total
          FROM transactions t
          WHERE userId = ? 
            AND type = 'expense'
            AND categoryId IS NOT NULL
            AND strftime('%Y-%m', date) >= date(?, '-$lookbackMonths months')
            AND strftime('%Y-%m', date) < ?
          GROUP BY categoryId, month
        ) monthly_spending
        JOIN transactions t ON monthly_spending.categoryId = t.categoryId
        LEFT JOIN enhanced_categories c ON t.categoryId = c.id
        WHERE t.userId = ?
        GROUP BY t.categoryId
        HAVING monthCount >= 2
        ORDER BY avgSpending DESC
      ''',
        [userId, month, month, userId],
      );

      final recommendations = <String, double>{};
      for (final row in result) {
        final categoryId = row['categoryId'] as String;
        final avgSpending = (row['avgSpending'] as num).toDouble();

        // Add 15% buffer to average spending
        recommendations[categoryId] = (avgSpending * 1.15).roundToDouble();
      }

      return recommendations;
    } catch (e) {
      print('Error getting budget recommendations: $e');
      return {};
    }
  }

  // ============ ENHANCED CATEGORIES METHODS ============

  /// Create enhanced categories table
  Future<void> createEnhancedCategoriesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS enhanced_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        ownerId TEXT NOT NULL,
        type TEXT NOT NULL,
        iconCodePoint INTEGER,
        subCategories TEXT DEFAULT '{}',
        ownershipType TEXT DEFAULT 'personal',
        createdBy TEXT,
        createdAt INTEGER,
        updatedAt INTEGER,
        isArchived INTEGER DEFAULT 0,
        isActive INTEGER DEFAULT 1,
        usageCount INTEGER DEFAULT 0,
        lastUsed INTEGER,
        version INTEGER DEFAULT 1,
        metadata TEXT DEFAULT '{}',
        syncStatus INTEGER DEFAULT 0,
        lastModified INTEGER DEFAULT (strftime('%s', 'now')),
        
        UNIQUE(ownerId, name, type),
        FOREIGN KEY (ownerId) REFERENCES users(id)
      )
    ''');

    // Create indexes
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enhanced_categories_owner_type 
      ON enhanced_categories(ownerId, type, isActive)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enhanced_categories_ownership 
      ON enhanced_categories(ownershipType, type)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enhanced_categories_usage 
      ON enhanced_categories(usageCount DESC, lastUsed DESC)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_enhanced_categories_sync 
      ON enhanced_categories(syncStatus, lastModified)
    ''');
  }

  /// Save category with ownership support
  Future<void> saveCategoryWithOwnership(
    Category category, {
    int syncStatus = 0,
  }) async {
    final db = await database;

    await db.insert('enhanced_categories', {
      'id': category.id,
      'name': category.name,
      'ownerId': category.ownerId,
      'type': category.type,
      'iconCodePoint': category.iconCodePoint,
      'subCategories': jsonEncode(category.subCategories),
      'ownershipType': category.ownershipType.name,
      'createdBy': category.createdBy,
      'createdAt': category.createdAt?.millisecondsSinceEpoch,
      'updatedAt':
          category.updatedAt?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch,
      'isArchived': category.isArchived ? 1 : 0,
      'isActive': category.isActive ? 1 : 0,
      'usageCount': category.usageCount,
      'lastUsed': category.lastUsed?.millisecondsSinceEpoch,
      'version': category.version,
      'metadata': jsonEncode(category.metadata ?? {}),
      'syncStatus': syncStatus,
      'lastModified': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    if (syncStatus == 0) {
      await addToSyncQueue(
        'enhanced_categories',
        category.id,
        'INSERT',
        category.toJson(),
      );
    }
  }

  /// Get categories with ownership filtering
  Future<List<Category>> getCategoriesWithOwnership(
    String userId,
    String? partnershipId, {
    String? type,
    CategoryOwnershipType? ownershipType,
    bool includeArchived = false,
    bool includeInactive = false,
  }) async {
    final db = await database;

    String whereClause = '(ownerId = ?';
    List<dynamic> whereArgs = [userId];

    // Include shared categories if partnership exists
    if (partnershipId != null) {
      whereClause += ' OR ownerId = ?';
      whereArgs.add(partnershipId);
    }
    whereClause += ')';

    // Add additional filters
    if (type != null) {
      whereClause += ' AND type = ?';
      whereArgs.add(type);
    }

    if (ownershipType != null) {
      whereClause += ' AND ownershipType = ?';
      whereArgs.add(ownershipType.name);
    }

    if (!includeArchived) {
      whereClause += ' AND isArchived = 0';
    }

    if (!includeInactive) {
      whereClause += ' AND isActive = 1';
    }

    final result = await db.query(
      'enhanced_categories',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'ownershipType ASC, usageCount DESC, name ASC',
    );

    return result.map((map) => _categoryFromMap(map)).toList();
  }

  /// Update category usage statistics
  Future<void> updateCategoryUsage(String categoryId) async {
    final db = await database;

    await db.update(
      'enhanced_categories',
      {
        'usageCount': 'usageCount + 1',
        'lastUsed': DateTime.now().millisecondsSinceEpoch,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lastModified': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [categoryId],
    );
  }

  /// Get smart category suggestions
  Future<List<CategorySuggestion>> getSmartCategorySuggestions(
    String description,
    String type,
    double amount,
    String userId,
    String? partnershipId, {
    int limit = 5,
  }) async {
    final categories = await getCategoriesWithOwnership(
      userId,
      partnershipId,
      type: type,
    );

    if (categories.isEmpty) return [];

    final suggestion = CategoryUtils.suggestCategory(
      description,
      categories,
      amount,
    );

    // Get additional suggestions based on usage
    final usageSuggestions = categories
        .where((c) => c.id != suggestion.categoryId)
        .take(limit - 1)
        .map(
          (c) => CategorySuggestion(
            categoryId: c.id,
            categoryName: c.name,
            confidence: c.popularityScore / 10, // Scale down
            reason: 'Thường sử dụng',
            ownershipType: c.ownershipType,
          ),
        )
        .toList();

    return [suggestion, ...usageSuggestions];
  }

  /// Archive category
  Future<void> archiveCategoryWithOwnership(String categoryId) async {
    final db = await database;

    await db.update(
      'enhanced_categories',
      {
        'isArchived': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'lastModified': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'syncStatus': 0,
      },
      where: 'id = ?',
      whereArgs: [categoryId],
    );

    await addToSyncQueue('enhanced_categories', categoryId, 'UPDATE', {
      'id': categoryId,
      'isArchived': true,
    });
  }

  /// Get category usage statistics
  Future<List<CategoryUsage>> getCategoryUsageStatistics(
    String userId, {
    String? type,
    int limit = 10,
  }) async {
    final db = await database;

    String whereClause =
        'c.ownerId = ? AND c.isActive = 1 AND c.isArchived = 0';
    List<dynamic> whereArgs = [userId];

    if (type != null) {
      whereClause += ' AND c.type = ?';
      whereArgs.add(type);
    }

    final result = await db.rawQuery(
      '''
      SELECT 
        c.id as categoryId,
        c.name as categoryName,
        c.usageCount,
        c.lastUsed,
        COALESCE(AVG(t.amount), 0) as averageAmount,
        GROUP_CONCAT(DISTINCT t.description) as descriptions
      FROM enhanced_categories c
      LEFT JOIN transactions t ON c.id = t.categoryId
      WHERE $whereClause
      GROUP BY c.id, c.name, c.usageCount, c.lastUsed
      ORDER BY c.usageCount DESC, c.lastUsed DESC
      LIMIT ?
    ''',
      [...whereArgs, limit],
    );

    return result.map((row) {
      final descriptionsStr = row['descriptions'] as String?;
      final descriptions = descriptionsStr != null
          ? descriptionsStr.split(',').take(5).toList()
          : <String>[];

      return CategoryUsage(
        categoryId: row['categoryId'] as String,
        categoryName: row['categoryName'] as String,
        usageCount: row['usageCount'] as int,
        lastUsed: row['lastUsed'] != null
            ? DateTime.fromMillisecondsSinceEpoch(row['lastUsed'] as int)
            : DateTime.now(),
        averageAmount: (row['averageAmount'] as num).toDouble(),
        commonDescriptions: descriptions,
      );
    }).toList();
  }

  /// Check if category has transactions
  Future<bool> checkCategoryHasTransactions(String categoryId) async {
    final db = await database;

    final result = await db.query(
      'transactions',
      where: 'categoryId = ?',
      whereArgs: [categoryId],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  // ============ SYNC MANAGEMENT ============

  /// Get unsynced records with enhanced filtering
  Future<List<Map<String, dynamic>>> getUnsyncedRecordsEnhanced(
    String tableName, {
    int limit = 50,
    int priority = 1,
  }) async {
    final db = await database;

    return await db.query(
      tableName,
      where: 'syncStatus = 0',
      orderBy: 'lastModified ASC',
      limit: limit,
    );
  }

  /// Mark multiple records as synced
  Future<void> markMultipleAsSynced(
    String tableName,
    List<String> recordIds,
  ) async {
    final db = await database;

    if (recordIds.isEmpty) return;

    final placeholders = recordIds.map((_) => '?').join(',');
    await db.update(
      tableName,
      {
        'syncStatus': 1,
        'lastModified': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id IN ($placeholders)',
      whereArgs: recordIds,
    );
  }

  /// Get enhanced sync status
  Future<Map<String, dynamic>> getEnhancedSyncStatus() async {
    final db = await database;

    final results = await Future.wait([
      db.rawQuery(
        'SELECT COUNT(*) as count FROM enhanced_budgets WHERE syncStatus = 0',
      ),
      db.rawQuery(
        'SELECT COUNT(*) as count FROM enhanced_categories WHERE syncStatus = 0',
      ),
      db.rawQuery(
        'SELECT COUNT(*) as count FROM transactions WHERE syncStatus = 0',
      ),
      db.rawQuery('SELECT COUNT(*) as count FROM wallets WHERE syncStatus = 0'),
      db.rawQuery('SELECT COUNT(*) as count FROM enhanced_budgets'),
      db.rawQuery('SELECT COUNT(*) as count FROM enhanced_categories'),
    ]);

    return {
      'unsyncedBudgets': results[0].first['count'] as int,
      'unsyncedCategories': results[1].first['count'] as int,
      'unsyncedTransactions': results[2].first['count'] as int,
      'unsyncedWallets': results[3].first['count'] as int,
      'totalBudgets': results[4].first['count'] as int,
      'totalCategories': results[5].first['count'] as int,
      'lastUpdate': DateTime.now().toIso8601String(),
    };
  }

  // ============ CONFLICT RESOLUTION ============

  /// Handle budget conflicts
  Future<Budget?> resolveBudgetConflict(
    Budget localBudget,
    Budget remoteBudget,
  ) async {
    // Simple last-write-wins strategy
    // In production, you might want more sophisticated conflict resolution
    if (remoteBudget.version > localBudget.version) {
      await saveBudgetWithOwnership(remoteBudget, syncStatus: 1);
      return remoteBudget;
    } else if (localBudget.version > remoteBudget.version) {
      // Local is newer, mark for sync
      await updateBudgetWithOwnership(localBudget);
      return localBudget;
    } else {
      // Same version, check timestamp
      final localTime =
          localBudget.updatedAt ?? localBudget.createdAt ?? DateTime.now();
      final remoteTime =
          remoteBudget.updatedAt ?? remoteBudget.createdAt ?? DateTime.now();

      final winner = remoteTime.isAfter(localTime) ? remoteBudget : localBudget;
      await saveBudgetWithOwnership(winner, syncStatus: 1);
      return winner;
    }
  }

  /// Handle category conflicts
  Future<Category?> resolveCategoryConflict(
    Category localCategory,
    Category remoteCategory,
  ) async {
    // Similar conflict resolution for categories
    if (remoteCategory.version > localCategory.version) {
      await saveCategoryWithOwnership(remoteCategory, syncStatus: 1);
      return remoteCategory;
    } else if (localCategory.version > remoteCategory.version) {
      await saveCategoryWithOwnership(localCategory, syncStatus: 0);
      return localCategory;
    } else {
      final localTime =
          localCategory.updatedAt ?? localCategory.createdAt ?? DateTime.now();
      final remoteTime =
          remoteCategory.updatedAt ??
          remoteCategory.createdAt ??
          DateTime.now();

      final winner = remoteTime.isAfter(localTime)
          ? remoteCategory
          : localCategory;
      await saveCategoryWithOwnership(winner, syncStatus: 1);
      return winner;
    }
  }

  // ============ DATA MIGRATION ============

  /// Migrate from old category structure to enhanced
  Future<void> migrateToEnhancedCategories() async {
    final db = await database;

    try {
      // Check if migration is needed
      final oldCategories = await db.query('categories');
      if (oldCategories.isEmpty) return;

      print(
        '🔄 Migrating ${oldCategories.length} categories to enhanced structure...',
      );

      for (final oldCategory in oldCategories) {
        final enhancedCategory = Category(
          id: oldCategory['id'] as String,
          name: oldCategory['name'] as String,
          ownerId: oldCategory['ownerId'] as String,
          type: oldCategory['type'] as String,
          iconCodePoint: oldCategory['iconCodePoint'] as int?,
          subCategories: oldCategory['subCategories'] != null
              ? Map<String, String>.from(
                  jsonDecode(oldCategory['subCategories'] as String),
                )
              : {},
          ownershipType: CategoryOwnershipType.personal, // Default to personal
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            oldCategory['createdAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            oldCategory['updatedAt'] as int? ??
                DateTime.now().millisecondsSinceEpoch,
          ),
        );

        await saveCategoryWithOwnership(enhancedCategory, syncStatus: 1);
      }

      print('✅ Category migration completed');
    } catch (e) {
      print('❌ Category migration failed: $e');
    }
  }

  /// Migrate from old budget structure to enhanced
  Future<void> migrateToEnhancedBudgets() async {
    final db = await database;

    try {
      // Check if migration is needed
      final oldBudgets = await db.query('budgets');
      if (oldBudgets.isEmpty) return;

      print(
        '🔄 Migrating ${oldBudgets.length} budgets to enhanced structure...',
      );

      for (final oldBudget in oldBudgets) {
        final enhancedBudget = Budget(
          id: oldBudget['id'] as String,
          ownerId: oldBudget['ownerId'] as String,
          month: oldBudget['month'] as String,
          totalAmount: (oldBudget['totalAmount'] as num).toDouble(),
          categoryAmounts: oldBudget['categoryAmounts'] != null
              ? Map<String, double>.from(
                  jsonDecode(oldBudget['categoryAmounts'] as String),
                )
              : {},
          budgetType: BudgetType.personal, // Default to personal
          createdBy: oldBudget['createdBy'] as String?,
          createdAt: oldBudget['createdAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  oldBudget['createdAt'] as int,
                )
              : null,
          updatedAt: oldBudget['updatedAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  oldBudget['updatedAt'] as int,
                )
              : null,
          isActive: (oldBudget['isActive'] as int? ?? 1) == 1,
        );

        await saveBudgetWithOwnership(enhancedBudget, syncStatus: 1);
      }

      print('✅ Budget migration completed');
    } catch (e) {
      print('❌ Budget migration failed: $e');
    }
  }

  // ============ HELPER METHODS ============

  Budget _budgetFromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'],
      ownerId: map['ownerId'],
      month: map['month'],
      totalAmount: (map['totalAmount'] as num).toDouble(),
      categoryAmounts: map['categoryAmounts'] != null
          ? Map<String, double>.from(jsonDecode(map['categoryAmounts']))
          : {},
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
      notes: map['notes'] != null
          ? Map<String, String>.from(jsonDecode(map['notes']))
          : null,
      categoryLimits: map['categoryLimits'] != null
          ? Map<String, double>.from(jsonDecode(map['categoryLimits']))
          : null,
      version: map['version'] ?? 1,
      isDeleted: (map['isDeleted'] ?? 0) == 1,
    );
  }

  Category _categoryFromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      ownerId: map['ownerId'],
      type: map['type'],
      iconCodePoint: map['iconCodePoint'],
      subCategories: map['subCategories'] != null
          ? Map<String, String>.from(jsonDecode(map['subCategories']))
          : {},
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
      isActive: (map['isActive'] ?? 1) == 1,
      usageCount: map['usageCount'] ?? 0,
      lastUsed: map['lastUsed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['lastUsed'])
          : null,
      version: map['version'] ?? 1,
      metadata: map['metadata'] != null
          ? Map<String, dynamic>.from(jsonDecode(map['metadata']))
          : null,
    );
  }

  // ============ CLEANUP METHODS ============

  /// Clean up old synced data to save space
  Future<void> cleanupOldSyncedData({int keepDays = 30}) async {
    final db = await database;
    final cutoffTime =
        DateTime.now()
            .subtract(Duration(days: keepDays))
            .millisecondsSinceEpoch ~/
        1000;

    try {
      // Clean up old synced budgets
      await db.delete(
        'enhanced_budgets',
        where: 'syncStatus = 1 AND isDeleted = 1 AND lastModified < ?',
        whereArgs: [cutoffTime],
      );

      // Clean up old synced categories
      await db.delete(
        'enhanced_categories',
        where: 'syncStatus = 1 AND isArchived = 1 AND lastModified < ?',
        whereArgs: [cutoffTime],
      );

      print('✅ Cleanup completed');
    } catch (e) {
      print('❌ Cleanup failed: $e');
    }
  }

  /// Vacuum database to reclaim space
  Future<void> optimizeDatabase() async {
    final db = await database;

    try {
      await db.execute('ANALYZE');
      await db.execute('VACUUM');
      print('✅ Database optimized');
    } catch (e) {
      print('❌ Database optimization failed: $e');
    }
  }
}
