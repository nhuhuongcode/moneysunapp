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
        .map((event) {});
  }
}
