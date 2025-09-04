import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/app.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  // Đảm bảo các binding của Flutter đã được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo Firebase với cấu hình cho platform hiện tại
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable offline support
  await DatabaseService.enableOfflineSupport();
  FirebaseDatabase.instance.setPersistenceEnabled(true);

  // Initialize date formatting
  await initializeDateFormatting('vi_VN', null);

  // Initialize enhanced sync service
  final syncService = OfflineSyncService();
  await syncService.initialize();

  runApp(const MoneySunApp());
}
