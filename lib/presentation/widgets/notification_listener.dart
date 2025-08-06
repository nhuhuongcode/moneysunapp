import 'dart:async';

import 'package:async/async.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';

class NotificationListener extends StatefulWidget {
  final Widget child;
  const NotificationListener({super.key, required this.child});

  @override
  State<NotificationListener> createState() => _NotificationListenerState();
}

class _NotificationListenerState extends State<NotificationListener> {
  StreamSubscription? _notificationSubscription;
  final _dbRef = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;
  final _databaseService = DatabaseService();

  @override
  void initState() {
    super.initState();
    _auth.authStateChanges().listen((user) {
      _notificationSubscription?.cancel(); // Hủy lắng nghe cũ
      if (user != null) {
        _setupNotificationListener(user.uid);
        _syncPartnershipOnStartup(user.uid);
      }
    });
  }

  void _setupNotificationListener(String uid) {
    final userRef = _dbRef.child('users').child(uid);

    _notificationSubscription = userRef.onChildChanged.listen((event) {
      if (event.snapshot.key == 'partnershipId' ||
          event.snapshot.key == 'partnerUid') {
        _handlePartnershipUpdate();
      }
    });
  }

  void _syncPartnershipOnStartup(String uid) async {
    final partnershipId = await _databaseService.getPartnershipId(uid);
    if (partnershipId != null) {
      // Lắng nghe thông báo cho partnership
      _listenForNotifications(partnershipId);
    } else {
      // Nếu không có partnership, lắng nghe thông báo cá nhân
      _listenForNotifications(uid);
    }
  }

  void _handlePartnershipUpdate() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    userProvider.refreshUser();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thông tin kết nối đã được cập nhật'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _listenForNotifications(String uid) {
    // Lắng nghe thông báo chung
    final notificationRef = _dbRef.child('user_notifications').child(uid);

    // Thêm lắng nghe partnership updates
    final partnershipRef = _dbRef.child('users').child(uid);

    _notificationSubscription =
        StreamGroup.merge([
          notificationRef.onChildAdded,
          partnershipRef.onChildChanged,
        ]).listen((event) {
          if (event.snapshot.exists) {
            if (event.snapshot.key == 'partnerUid' ||
                event.snapshot.key == 'partnershipId') {
              // Refresh user provider để cập nhật partnership state
              if (mounted) {
                context.read<UserProvider>().fetchUser(uid);
              }
              return;
            }

            // Xử lý thông báo thông thường
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            _showNotification(data, event);
          }
        });
  }

  void _showNotification(Map<dynamic, dynamic> data, dynamic event) {
    final title = data['title'] ?? 'Thông báo';
    final body = data['body'] ?? 'Bạn có thông báo mới.';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(body),
          ],
        ),
        backgroundColor: Theme.of(context).primaryColor,
        duration: const Duration(seconds: 5),
      ),
    );

    // Xóa thông báo sau khi hiển thị
    if (data['type'] != 'partnership') {
      event.snapshot.ref.remove();
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
