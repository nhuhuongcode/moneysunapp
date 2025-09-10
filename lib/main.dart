import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/app.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 Starting MoneySun app with DataService...');

  try {
    // Step 1: Initialize Firebase
    print('🔥 Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Step 2: Configure Firebase Database for DataService
    print('☁️ Configuring Firebase Database for DataService...');
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    FirebaseDatabase.instance.setPersistenceCacheSizeBytes(
      20 * 1024 * 1024,
    ); // 20MB cache

    // Step 3: Initialize Localization
    print('🌍 Initializing localization...');
    await initializeDateFormatting('vi_VN', null);

    print('✅ All services initialized successfully for DataService');

    // Step 4: Run the app with DataService
    runApp(const MoneySunApp());
  } catch (e, stackTrace) {
    print('❌ Critical initialization error with DataService: $e');
    print('Stack trace: $stackTrace');

    // Show error app instead of crashing
    runApp(DataServiceInitializationErrorApp(error: e.toString()));
  }
}

/// Error app shown when DataService initialization fails
class DataServiceInitializationErrorApp extends StatelessWidget {
  final String error;

  const DataServiceInitializationErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneySun - DataService Error',
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.storage_sharp, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 24),
                Text(
                  'Lỗi Khởi Tạo DataService',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'DataService gặp lỗi khi khởi tạo. Vui lòng thử lại hoặc liên hệ hỗ trợ.',
                  style: TextStyle(fontSize: 16, color: Colors.red.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chi tiết lỗi DataService:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        error,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Restart the app with DataService
                      main();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Thử Lại DataService'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Mã lỗi DataService: DS_${DateTime.now().millisecondsSinceEpoch}',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
