import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/app.dart';
import 'package:moneysun/data/services/database_service.dart';
<<<<<<< Updated upstream
=======
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
>>>>>>> Stashed changes
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  // Đảm bảo các binding của Flutter đã được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();

  // Kích hoạt tính năng lưu trữ offline cho Realtime Database
  // FirebaseDatabase.instance.setPersistenceEnabled(true);

  // Khởi tạo Firebase với cấu hình cho platform hiện tại
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
<<<<<<< Updated upstream
=======

  // CRITICAL: Database initialization with emergency recovery
  await initializeDatabaseWithRecovery();

  // Initialize other services
>>>>>>> Stashed changes
  await DatabaseService.enableOfflineSupport();
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  await initializeDateFormatting('vi_VN', null);
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
