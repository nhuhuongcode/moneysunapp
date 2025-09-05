import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/app.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // CRITICAL: Database initialization with emergency recovery
  await initializeDatabaseWithRecovery();

  // Initialize other services
  await DatabaseService.enableOfflineSupport();
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  await initializeDateFormatting('vi_VN', null);

  final syncService = OfflineSyncService();
  await syncService.initialize();

  runApp(const MoneySunApp());
}

Future<void> initializeDatabaseWithRecovery() async {
  try {
    // Try to initialize database normally
    final localDb = LocalDatabaseService();
    final isHealthy = await localDb.isDatabaseHealthy();

    if (!isHealthy) {
      print('⚠️ Database is not healthy, performing reset...');
      await LocalDatabaseService.emergencyDatabaseReset();
    }

    print('✅ Database initialization completed');
  } catch (e) {
    print('❌ Database initialization failed: $e');

    try {
      // Emergency reset
      print('🚨 Attempting emergency database recovery...');
      await LocalDatabaseService.emergencyDatabaseReset();

      // Try to initialize again
      final localDb = LocalDatabaseService();
      await localDb.database; // This will trigger onCreate

      print('✅ Emergency recovery completed');
    } catch (recoveryError) {
      print('❌ Emergency recovery failed: $recoveryError');
      // App can still start, but with limited offline functionality
    }
  }
}
