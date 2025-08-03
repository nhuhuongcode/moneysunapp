import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/app.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  // Đảm bảo các binding của Flutter đã được khởi tạo
  WidgetsFlutterBinding.ensureInitialized();

  // Kích hoạt tính năng lưu trữ offline cho Realtime Database
  // FirebaseDatabase.instance.setPersistenceEnabled(true);

  // Khởi tạo Firebase với cấu hình cho platform hiện tại
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseDatabase.instance.setPersistenceEnabled(true);
  await initializeDateFormatting('vi_VN', null);
  runApp(const MoneySunApp());
}
