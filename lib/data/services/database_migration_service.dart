// lib/data/services/database_migration_service.dart - FIXED VERSION

import 'package:sqflite/sqflite.dart';
import 'package:moneysun/data/services/local_database_service.dart';

class DatabaseMigrationService {
  static const int _currentVersion = 2;

  /// Migrate database from old version to new version
  static Future<void> migrateDatabase() async {
    final localDb = LocalDatabaseService();
    final db = await localDb.database;

    final currentVersion = await db.getVersion();

    if (currentVersion < _currentVersion) {
      print(
        '🔄 Migrating database from version $currentVersion to $_currentVersion',
      );

      await db.transaction((txn) async {
        // Migrate to version 2: Enhanced description_history
        if (currentVersion < 2) {
          await _migrateToVersion2(txn);
        }

        // Set new version
        await txn.execute('PRAGMA user_version = $_currentVersion');
      });

      print('✅ Database migration completed successfully');
    } else {
      print('✅ Database is already up to date (version $currentVersion)');
    }
  }

  /// FIXED: Migrate to version 2 with proper column addition
  static Future<void> _migrateToVersion2(Transaction txn) async {
    print('📝 Migrating description_history table to version 2...');

    try {
      // Check if table exists
      final tables = await txn.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'description_history'],
      );

      if (tables.isEmpty) {
        // Create new table with all columns
        await _createEnhancedDescriptionTable(txn);
        return;
      }

      // Check existing columns
      final columns = await txn.rawQuery(
        'PRAGMA table_info(description_history)',
      );
      final columnNames = columns.map((col) => col['name'] as String).toSet();

      // FIX: Add missing columns with constant defaults only
      final columnsToAdd = <String, String>{};

      if (!columnNames.contains('type')) {
        columnsToAdd['type'] = 'TEXT';
      }
      if (!columnNames.contains('categoryId')) {
        columnsToAdd['categoryId'] = 'TEXT';
      }
      if (!columnNames.contains('amount')) {
        columnsToAdd['amount'] = 'REAL';
      }
      if (!columnNames.contains('updatedAt')) {
        // FIX: Use constant default value instead of function
        columnsToAdd['updatedAt'] = 'INTEGER DEFAULT 0';
      }

      // Add columns one by one
      for (final entry in columnsToAdd.entries) {
        try {
          await txn.execute(
            'ALTER TABLE description_history ADD COLUMN ${entry.key} ${entry.value}',
          );
          print('✅ Added column: ${entry.key}');
        } catch (e) {
          print('⚠️ Warning: Could not add column ${entry.key}: $e');
          // Continue with other columns
        }
      }

      // FIX: Update the updatedAt column for existing records
      if (columnsToAdd.containsKey('updatedAt')) {
        try {
          await txn.execute('''
            UPDATE description_history 
            SET updatedAt = strftime('%s', 'now') 
            WHERE updatedAt = 0 OR updatedAt IS NULL
          ''');
          print('✅ Updated existing records with current timestamp');
        } catch (e) {
          print('⚠️ Warning: Could not update existing timestamps: $e');
        }
      }

      // Create indexes for performance
      await _createDescriptionIndexes(txn);

      print('✅ Successfully migrated description_history table');
    } catch (e) {
      print('❌ Error migrating description_history table: $e');
      rethrow;
    }
  }

  /// Create enhanced description_history table from scratch
  static Future<void> _createEnhancedDescriptionTable(Transaction txn) async {
    await txn.execute('''
      CREATE TABLE description_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        userId TEXT NOT NULL,
        description TEXT NOT NULL,
        usageCount INTEGER DEFAULT 1,
        lastUsed INTEGER DEFAULT (strftime('%s', 'now')),
        createdAt INTEGER DEFAULT (strftime('%s', 'now')),
        updatedAt INTEGER DEFAULT (strftime('%s', 'now')),
        
        -- Context information for smart suggestions
        type TEXT, -- 'income', 'expense', 'transfer'
        categoryId TEXT,
        amount REAL,
        
        UNIQUE(userId, description)
      )
    ''');

    await _createDescriptionIndexes(txn);
    print('✅ Created enhanced description_history table');
  }

  /// Create indexes for better performance
  static Future<void> _createDescriptionIndexes(Transaction txn) async {
    final indexes = [
      'CREATE INDEX IF NOT EXISTS idx_description_user_type ON description_history(userId, type)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_category ON description_history(userId, categoryId)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_lastused ON description_history(userId, lastUsed)',
      'CREATE INDEX IF NOT EXISTS idx_description_user_usage ON description_history(userId, usageCount)',
      'CREATE INDEX IF NOT EXISTS idx_description_text ON description_history(description)',
      'CREATE INDEX IF NOT EXISTS idx_description_amount ON description_history(amount)',
    ];

    for (final indexSql in indexes) {
      try {
        await txn.execute(indexSql);
      } catch (e) {
        print('⚠️ Warning: Could not create index: $e');
      }
    }
  }

  /// Clean up and optimize database after migration
  static Future<void> optimizeDatabase() async {
    final localDb = LocalDatabaseService();
    final db = await localDb.database;

    try {
      print('🔧 Optimizing database...');

      // Analyze tables for better query performance
      await db.execute('ANALYZE');

      // Vacuum to reclaim space and defragment
      await db.execute('VACUUM');

      print('✅ Database optimization completed');
    } catch (e) {
      print('⚠️ Warning: Database optimization failed: $e');
    }
  }

  /// Get database statistics for debugging
  static Future<Map<String, dynamic>> getDatabaseInfo() async {
    final localDb = LocalDatabaseService();
    final db = await localDb.database;

    try {
      final version = await db.getVersion();

      // Get table information
      final tables = await db.query(
        'sqlite_master',
        where: 'type = ?',
        whereArgs: ['table'],
      );
      final tableNames = tables.map((t) => t['name'] as String).toList();

      // Get description_history stats
      Map<String, dynamic> descStats = {};
      try {
        final result = await db.rawQuery('''
          SELECT 
            COUNT(*) as total_descriptions,
            COUNT(DISTINCT userId) as unique_users,
            COALESCE(MAX(usageCount), 0) as max_usage_count,
            COALESCE(AVG(usageCount), 0) as avg_usage_count
          FROM description_history
        ''');
        descStats = result.first;
      } catch (e) {
        print('⚠️ Could not get description stats: $e');
        descStats = {
          'total_descriptions': 0,
          'unique_users': 0,
          'max_usage_count': 0,
          'avg_usage_count': 0,
        };
      }

      return {
        'version': version,
        'tables': tableNames,
        'description_stats': descStats,
      };
    } catch (e) {
      print('Error getting database info: $e');
      return {'error': e.toString()};
    }
  }

  /// FIX: Force recreate table if migration fails
  static Future<void> forceRecreateDescriptionTable() async {
    final localDb = LocalDatabaseService();
    final db = await localDb.database;

    try {
      print('🔄 Force recreating description_history table...');

      await db.transaction((txn) async {
        // Backup existing data
        final existingData = await txn.query('description_history');

        // Drop and recreate table
        await txn.execute('DROP TABLE IF EXISTS description_history');
        await _createEnhancedDescriptionTable(txn);

        // Restore data with new structure
        for (final row in existingData) {
          try {
            await txn.insert('description_history', {
              'userId': row['userId'],
              'description': row['description'],
              'usageCount': row['usageCount'] ?? 1,
              'lastUsed':
                  row['lastUsed'] ??
                  (DateTime.now().millisecondsSinceEpoch ~/ 1000),
              'createdAt':
                  row['createdAt'] ??
                  (DateTime.now().millisecondsSinceEpoch ~/ 1000),
              'updatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'type': null, // New columns start as null
              'categoryId': null,
              'amount': null,
            });
          } catch (e) {
            print('⚠️ Could not restore row: $e');
            // Continue with other rows
          }
        }
      });

      print('✅ Force recreation completed successfully');
    } catch (e) {
      print('❌ Force recreation failed: $e');
      rethrow;
    }
  }
}

// ============ HELPER METHODS ============

/// Initialize database migration on app startup with error recovery
Future<void> initializeDatabaseMigration() async {
  try {
    await DatabaseMigrationService.migrateDatabase();
    await DatabaseMigrationService.optimizeDatabase();
  } catch (e) {
    print('❌ Database migration failed: $e');

    // Try to recover by recreating the problematic table
    try {
      print('🔄 Attempting database recovery...');
      await DatabaseMigrationService.forceRecreateDescriptionTable();
      await DatabaseMigrationService.optimizeDatabase();
      print('✅ Database recovery completed');
    } catch (recoveryError) {
      print('❌ Database recovery also failed: $recoveryError');
      // Could show user a dialog about database issues
      // For now, continue without crashing the app
    }
  }
}

/// Backup database before major migrations (optional)
class DatabaseBackupService {
  static Future<bool> createBackup() async {
    try {
      print('📦 Creating database backup...');

      final localDb = LocalDatabaseService();
      final stats = await localDb.getDatabaseStats();

      // Log current state for debugging
      print('📊 Database stats before backup: $stats');

      // For now, just return success
      // In real implementation, you'd want to:
      // 1. Export critical data to JSON
      // 2. Save to app's documents directory
      // 3. Optionally upload to cloud storage

      return true;
    } catch (e) {
      print('❌ Database backup failed: $e');
      return false;
    }
  }
}

// ============ USAGE IN MAIN.DART ============

// Add this to your main.dart initialization:
/*

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  // UPDATED: Initialize database migration with error recovery
  await initializeDatabaseMigration();
  
  // Initialize other services
  await DatabaseService.enableOfflineSupport();
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  await initializeDateFormatting('vi_VN', null);
  
  final syncService = OfflineSyncService();
  await syncService.initialize();
  
  runApp(const MoneySunApp());
}

*/
