// lib/main.dart - FIXED INITIALIZATION
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/app.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/services/enhanced_local_database_service.dart';
import 'firebase_options.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  print('🚀 Starting MoneySun app initialization...');

  try {
    // Step 1: Initialize Firebase
    print('🔥 Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Step 2: Initialize Local Database with Recovery
    print('🗄️ Initializing local database...');
    await initializeDatabaseWithRecovery();

    // Step 3: Configure Firebase Database
    print('☁️ Configuring Firebase Database...');
    FirebaseDatabase.instance.setPersistenceEnabled(true);
    FirebaseDatabase.instance.setPersistenceCacheSizeBytes(
      20 * 1024 * 1024,
    ); // 20MB cache

    // Step 4: Initialize Localization
    print('🌍 Initializing localization...');
    await initializeDateFormatting('vi_VN', null);

    // Step 5: Pre-initialize DataService (will be properly initialized in app with UserProvider)
    print('📡 Pre-initializing DataService...');
    final dataService = DataService();
    // Note: Full initialization happens in app.dart with UserProvider

    print('✅ All services initialized successfully');

    // Step 6: Run the app
    runApp(const MoneySunApp());
  } catch (e, stackTrace) {
    print('❌ Critical initialization error: $e');
    print('Stack trace: $stackTrace');

    // Show error app instead of crashing
    runApp(InitializationErrorApp(error: e.toString()));
  }
}

/// Initialize database with comprehensive error recovery
Future<void> initializeDatabaseWithRecovery() async {
  try {
    // Try to initialize enhanced database
    final enhancedDb = EnhancedLocalDatabaseService();
    final isHealthy = await enhancedDb.isDatabaseHealthy();

    if (!isHealthy) {
      print('⚠️ Database is not healthy, performing recovery...');
      await _performDatabaseRecovery();
    } else {
      print('✅ Database is healthy');
    }

    // Optimize database performance
    await enhancedDb.optimizeDatabase();

    print('✅ Database initialization completed successfully');
  } catch (e) {
    print('❌ Database initialization failed: $e');
    await _handleDatabaseFailure(e);
  }
}

/// Perform database recovery steps
Future<void> _performDatabaseRecovery() async {
  try {
    print('🔧 Starting database recovery process...');

    // Step 1: Try emergency reset
    await EnhancedLocalDatabaseService.emergencyDatabaseReset();
    print('✅ Emergency reset completed');

    // Step 2: Verify new database is working
    final enhancedDb = EnhancedLocalDatabaseService();
    final isHealthyAfterReset = await enhancedDb.isDatabaseHealthy();

    if (!isHealthyAfterReset) {
      throw Exception('Database still unhealthy after reset');
    }

    print('✅ Database recovery completed successfully');
  } catch (e) {
    print('❌ Database recovery failed: $e');
    rethrow;
  }
}

/// Handle critical database failures
Future<void> _handleDatabaseFailure(dynamic error) async {
  print('🚨 Critical database failure: $error');

  try {
    // Last resort: clean slate
    print('🧹 Attempting clean slate initialization...');

    await EnhancedLocalDatabaseService.emergencyDatabaseReset();

    // Test basic functionality
    final testDb = EnhancedLocalDatabaseService();
    await testDb.database; // This will trigger onCreate

    final stats = await testDb.getDatabaseStats();
    print('📊 Clean database stats: $stats');

    print('✅ Clean slate initialization successful');
  } catch (cleanSlateError) {
    print('❌ Clean slate initialization failed: $cleanSlateError');

    // At this point, we continue without local database
    // App will work in online-only mode
    print('⚠️ Continuing without local database - online-only mode');
  }
}

/// Error app shown when initialization fails completely
class InitializationErrorApp extends StatelessWidget {
  final String error;

  const InitializationErrorApp({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneySun - Initialization Error',
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
                const SizedBox(height: 24),
                Text(
                  'Lỗi Khởi Tạo Ứng Dụng',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  'Ứng dụng gặp lỗi khi khởi tạo. Vui lòng thử lại hoặc liên hệ hỗ trợ.',
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
                        'Chi tiết lỗi:',
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
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // Restart the app
                          main();
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('Thử Lại'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // You could navigate to a support page or email
                          debugPrint('Support requested');
                        },
                        icon: const Icon(Icons.help_outline),
                        label: const Text('Hỗ Trợ'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Mã lỗi: INIT_${DateTime.now().millisecondsSinceEpoch}',
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

/// App health checker for monitoring
class AppHealthChecker {
  static Future<Map<String, dynamic>> checkAppHealth() async {
    final results = <String, dynamic>{};

    try {
      // Check Firebase connection
      results['firebase'] = await _checkFirebaseConnection();

      // Check local database
      results['database'] = await _checkDatabaseHealth();

      // Check data service
      results['dataService'] = await _checkDataServiceHealth();

      results['overall'] = _calculateOverallHealth(results);
      results['timestamp'] = DateTime.now().toIso8601String();
    } catch (e) {
      results['error'] = e.toString();
      results['overall'] = 'unhealthy';
    }

    return results;
  }

  static Future<String> _checkFirebaseConnection() async {
    try {
      // Simple Firebase connection test
      final testRef = FirebaseDatabase.instance.ref('health_check');
      await testRef.set(ServerValue.timestamp);
      return 'healthy';
    } catch (e) {
      return 'unhealthy: $e';
    }
  }

  static Future<String> _checkDatabaseHealth() async {
    try {
      final db = EnhancedLocalDatabaseService();
      final isHealthy = await db.isDatabaseHealthy();
      return isHealthy ? 'healthy' : 'unhealthy';
    } catch (e) {
      return 'unhealthy: $e';
    }
  }

  static Future<String> _checkDataServiceHealth() async {
    try {
      final dataService = DataService();
      // Basic health check - ensure service is accessible
      final isOnline = dataService.isOnline;
      return 'healthy (online: $isOnline)';
    } catch (e) {
      return 'unhealthy: $e';
    }
  }

  static String _calculateOverallHealth(Map<String, dynamic> results) {
    final healthyServices = results.values
        .where((status) => status.toString().startsWith('healthy'))
        .length;

    final totalServices =
        results.length - 2; // Exclude 'overall' and 'timestamp'

    if (healthyServices == totalServices) {
      return 'healthy';
    } else if (healthyServices > totalServices / 2) {
      return 'degraded';
    } else {
      return 'unhealthy';
    }
  }
}

/// Development helper for debugging initialization
class InitializationLogger {
  static final List<String> _logs = [];

  static void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message';
    _logs.add(logMessage);
    print(logMessage);
  }

  static List<String> getLogs() => List.unmodifiable(_logs);

  static void clearLogs() => _logs.clear();

  static String getLogsAsString() => _logs.join('\n');
}
