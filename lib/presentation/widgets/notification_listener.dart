import 'dart:async';

import 'package:async/async.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/data/providers/user_provider.dart';
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

  @override
  void initState() {
    super.initState();
    _auth.authStateChanges().listen((user) {
      _notificationSubscription?.cancel(); // Hủy lắng nghe cũ
      if (user != null) {
        _listenForNotifications(user.uid);
      }
    });
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
                context.read<UserProvider>().fetchUser();
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
