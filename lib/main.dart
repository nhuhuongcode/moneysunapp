import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/app.dart';
import 'package:moneysun/data/services/database_migration_service.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

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

  final syncService = OfflineSyncService();
  await syncService.initialize();

  runApp(const MoneySunApp());
}
