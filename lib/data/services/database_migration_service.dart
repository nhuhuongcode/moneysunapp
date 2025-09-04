// lib/data/services/database_migration_service.dart

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

  /// Migrate to version 2: Add context columns to description_history
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

      // Add missing columns
      final newColumns = {
        'type': 'TEXT',
        'categoryId': 'TEXT',
        'amount': 'REAL',
        'updatedAt': 'INTEGER DEFAULT (strftime(\'%s\', \'now\'))',
      };

      for (final entry in newColumns.entries) {
        if (!columnNames.contains(entry.key)) {
          await txn.execute(
            'ALTER TABLE description_history ADD COLUMN ${entry.key} ${entry.value}',
          );
          print('✅ Added column: ${entry.key}');
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
      final descStats = await db.rawQuery('''
        SELECT 
          COUNT(*) as total_descriptions,
          COUNT(DISTINCT userId) as unique_users,
          MAX(usageCount) as max_usage_count,
          AVG(usageCount) as avg_usage_count
        FROM description_history
      ''');

      return {
        'version': version,
        'tables': tableNames,
        'description_stats': descStats.first,
      };
    } catch (e) {
      print('Error getting database info: $e');
      return {'error': e.toString()};
    }
  }
}

// ============ MIGRATION HELPER METHODS ============

/// Initialize database migration on app startup
Future<void> initializeDatabaseMigration() async {
  try {
    await DatabaseMigrationService.migrateDatabase();
    await DatabaseMigrationService.optimizeDatabase();
  } catch (e) {
    print('❌ Database migration failed: $e');
    // Could show user a dialog about database issues
  }
}

/// Backup database before major migrations (optional)
class DatabaseBackupService {
  static Future<bool> createBackup() async {
    try {
      // Implementation would depend on your backup strategy
      // Could export to JSON, copy database file, etc.
      print('📦 Creating database backup...');

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
  
  // NEW: Initialize database migration
  await initializeDatabaseMigration();
  
  // Initialize other services
  await DatabaseService.enableOfflineSupport();
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  await initializeDateFormatting('vi_VN', null);
  
  final syncService = EnhancedOfflineSyncService();
  await syncService.initialize();
  
  runApp(const MoneySunApp());
}

*/
