import 'package:firebase_database/firebase_database.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final String type; // 'partnership', 'transaction', 'budget', etc.

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.type = 'general',
  });

  factory AppNotification.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;

    return AppNotification(
      id: snapshot.key!,
      title: data['title'] ?? '',
      body: data['body'] ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] ?? 0),
      isRead: data['isRead'] ?? false,
      type: data['type'] ?? 'general',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'body': body,
      'timestamp': ServerValue.timestamp,
      'isRead': isRead,
      'type': type,
    };
  }
}
