import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class NotificationService {
  final _dbRef = FirebaseDatabase.instance.ref();
  final _currentUser = FirebaseAuth.instance.currentUser;

  Stream<List<Map<String, dynamic>>> getNotificationsStream() {
    if (_currentUser == null) return Stream.value([]);

    return _dbRef
        .child('notifications')
        .child(_currentUser!.uid)
        .orderByChild('timestamp')
        .onValue
        .map((event) {
          final List<Map<String, dynamic>> notifications = [];
          if (event.snapshot.exists) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            data.forEach((key, value) {
              final notifData = value as Map<dynamic, dynamic>;
              notifications.add({
                'id': key,
                'title': notifData['title'] ?? '',
                'body': notifData['body'] ?? '',
                'timestamp': notifData['timestamp'] ?? 0,
                'type': notifData['type'] ?? 'general',
                'isRead': notifData['isRead'] ?? false,
              });
            });
          }
          return notifications
            ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
        });
  }
}
