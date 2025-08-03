import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

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
    final notificationRef = _dbRef.child('user_notifications').child(uid);
    // Lắng nghe sự kiện "child_added", chỉ kích hoạt khi có một thông báo MỚI được thêm vào
    _notificationSubscription = notificationRef.onChildAdded.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final title = data['title'] ?? 'Thông báo';
        final body = data['body'] ?? 'Bạn có thông báo mới.';

        // Hiển thị SnackBar
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(body),
              ],
            ),
            backgroundColor: Theme.of(context).primaryColor,
            duration: const Duration(seconds: 5),
          ),
        );

        // Sau khi hiển thị, xóa thông báo khỏi database để không hiển thị lại
        event.snapshot.ref.remove();
      }
    });
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
