// lib/presentation/widgets/notification_listener.dart
import 'dart:async';
import 'package:async/async.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/data_service.dart';

class NotificationListener extends StatefulWidget {
  final Widget child;

  const NotificationListener({super.key, required this.child});

  @override
  State<NotificationListener> createState() => _NotificationListenerState();
}

class _NotificationListenerState extends State<NotificationListener> {
  StreamSubscription? _notificationSubscription;
  StreamSubscription? _partnershipSubscription;
  final _dbRef = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _initializeListeners();
  }

  void _initializeListeners() {
    // Listen to auth state changes
    _auth.authStateChanges().listen((user) {
      _clearSubscriptions();

      if (user != null) {
        _setupNotificationListeners(user.uid);
        _syncDataOnStartup(user.uid);
      }
    });
  }

  void _clearSubscriptions() {
    _notificationSubscription?.cancel();
    _partnershipSubscription?.cancel();
  }

  void _setupNotificationListeners(String uid) {
    // Listen for user profile changes (partnership updates)
    _partnershipSubscription = _dbRef
        .child('users')
        .child(uid)
        .onChildChanged
        .listen((event) {
          if (event.snapshot.key == 'partnershipId' ||
              event.snapshot.key == 'partnerUid' ||
              event.snapshot.key == 'partnerDisplayName') {
            _handlePartnershipUpdate();
          }
        });

    // Listen for notifications
    _notificationSubscription = _dbRef
        .child('user_notifications')
        .child(uid)
        .orderByChild('timestamp')
        .limitToLast(10)
        .onChildAdded
        .listen((event) {
          if (event.snapshot.exists) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            _handleNotification(data, event.snapshot.ref);
          }
        });

    // Also listen for partnership-specific notifications
    _listenForPartnershipNotifications(uid);
  }

  void _listenForPartnershipNotifications(String uid) {
    // This could be expanded to listen for specific partnership events
    // such as shared wallet updates, shared category changes, etc.
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    if (userProvider.partnershipId != null) {
      _dbRef
          .child('partnerships')
          .child(userProvider.partnershipId!)
          .onChildChanged
          .listen((event) {
            _handlePartnershipDataChange(event);
          });
    }
  }

  void _syncDataOnStartup(String uid) async {
    try {
      // Trigger data sync when user starts the app
      final dataService = Provider.of<DataService>(context, listen: false);

      if (dataService.isInitialized && dataService.isOnline) {
        // Force a sync to ensure we have the latest data
        await dataService.forceSyncNow();
      }

      // Refresh user data
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      await userProvider.refreshUser();
    } catch (e) {
      debugPrint('Error during startup sync: $e');
    }
  }

  void _handlePartnershipUpdate() {
    if (!mounted) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);

    // Refresh user data to get latest partnership info
    userProvider.refreshPartnershipData();

    // Show notification to user
    _showInAppNotification(
      'Kết nối cập nhật',
      'Thông tin kết nối đã được cập nhật',
      Colors.blue,
      Icons.people_rounded,
    );

    // Trigger data sync to get shared data
    _triggerDataSync();
  }

  void _handlePartnershipDataChange(DatabaseEvent event) {
    if (!mounted) return;

    // Handle specific partnership data changes
    switch (event.snapshot.key) {
      case 'memberNames':
        _showInAppNotification(
          'Cập nhật thành viên',
          'Thông tin thành viên đã được cập nhật',
          Colors.orange,
          Icons.people,
        );
        break;
      case 'lastSyncTime':
        // Partner synced data - we might want to refresh our data too
        _triggerDataSync();
        break;
    }
  }

  void _handleNotification(Map<dynamic, dynamic> data, DatabaseReference ref) {
    if (!mounted) return;

    final title = data['title'] ?? 'Thông báo';
    final body = data['body'] ?? 'Bạn có thông báo mới.';
    final type = data['type'] ?? 'general';
    final isRead = data['isRead'] ?? false;

    // Don't show if already read
    if (isRead) return;

    // Show different notifications based on type
    switch (type) {
      case 'partnership':
        _handlePartnershipNotification(title, body, data);
        break;
      case 'data_sync':
        _handleDataSyncNotification(title, body, data);
        break;
      case 'budget':
        _handleBudgetNotification(title, body, data);
        break;
      default:
        _showInAppNotification(title, body, Colors.blue, Icons.notifications);
    }

    // Mark notification as read
    ref.update({'isRead': true});

    // Auto-remove old notifications
    _cleanupOldNotifications(ref.parent!);
  }

  void _handlePartnershipNotification(
    String title,
    String body,
    Map<dynamic, dynamic> data,
  ) {
    _showInAppNotification(
      title,
      body,
      Colors.orange,
      Icons.people_rounded,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Xem',
        textColor: Colors.white,
        onPressed: () {
          // Navigate to partnership/profile screen
          // This would need to be implemented based on your navigation structure
        },
      ),
    );

    // If it's a partnership request or update, refresh user data
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    userProvider.refreshPartnershipData();
  }

  void _handleDataSyncNotification(
    String title,
    String body,
    Map<dynamic, dynamic> data,
  ) {
    // These are usually for sync conflicts or sync completion
    _showInAppNotification(
      title,
      body,
      Colors.green,
      Icons.sync,
      duration: const Duration(seconds: 3),
    );

    // Trigger a data refresh
    _triggerDataSync();
  }

  void _handleBudgetNotification(
    String title,
    String body,
    Map<dynamic, dynamic> data,
  ) {
    _showInAppNotification(
      title,
      body,
      Colors.purple,
      Icons.account_balance_wallet,
      duration: const Duration(seconds: 5),
    );
  }

  void _showInAppNotification(
    String title,
    String body,
    Color color,
    IconData icon, {
    Duration duration = const Duration(seconds: 4),
    SnackBarAction? action,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (body.isNotEmpty)
                    Text(body, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
        backgroundColor: color,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        action: action,
      ),
    );
  }

  void _triggerDataSync() async {
    try {
      final dataService = Provider.of<DataService>(context, listen: false);

      if (dataService.isOnline) {
        await dataService.forceSyncNow();
      }
    } catch (e) {
      debugPrint('Error triggering data sync: $e');
    }
  }

  void _cleanupOldNotifications(DatabaseReference notificationsRef) {
    // Remove notifications older than 7 days
    final cutoffTime = DateTime.now()
        .subtract(const Duration(days: 7))
        .millisecondsSinceEpoch;

    notificationsRef
        .orderByChild('timestamp')
        .endAt(cutoffTime)
        .once()
        .then((snapshot) {
          if (snapshot.snapshot.exists) {
            final data = snapshot.snapshot.value as Map<dynamic, dynamic>;
            for (final key in data.keys) {
              notificationsRef.child(key.toString()).remove();
            }
          }
        })
        .catchError((e) {
          debugPrint('Error cleaning up notifications: $e');
        });
  }

  @override
  void dispose() {
    _clearSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataService>(
      builder: (context, dataService, child) {
        // We can add data service status indicators here if needed
        return Stack(
          children: [
            widget.child,

            // Show sync status overlay when needed
            if (dataService.isSyncing)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Đang đồng bộ dữ liệu...',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// Enhanced notification service for creating notifications
class NotificationService {
  static final _dbRef = FirebaseDatabase.instance.ref();

  static Future<void> sendPartnershipNotification(
    String targetUserId,
    String title,
    String body, {
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      await _dbRef.child('user_notifications').child(targetUserId).push().set({
        'title': title,
        'body': body,
        'type': 'partnership',
        'timestamp': ServerValue.timestamp,
        'isRead': false,
        ...?additionalData,
      });
    } catch (e) {
      debugPrint('Error sending partnership notification: $e');
    }
  }

  static Future<void> sendDataSyncNotification(
    String targetUserId,
    String title,
    String body,
  ) async {
    try {
      await _dbRef.child('user_notifications').child(targetUserId).push().set({
        'title': title,
        'body': body,
        'type': 'data_sync',
        'timestamp': ServerValue.timestamp,
        'isRead': false,
      });
    } catch (e) {
      debugPrint('Error sending data sync notification: $e');
    }
  }

  static Future<void> sendBudgetNotification(
    String targetUserId,
    String title,
    String body, {
    String? budgetId,
    String? categoryId,
  }) async {
    try {
      await _dbRef.child('user_notifications').child(targetUserId).push().set({
        'title': title,
        'body': body,
        'type': 'budget',
        'timestamp': ServerValue.timestamp,
        'isRead': false,
        if (budgetId != null) 'budgetId': budgetId,
        if (categoryId != null) 'categoryId': categoryId,
      });
    } catch (e) {
      debugPrint('Error sending budget notification: $e');
    }
  }
}
