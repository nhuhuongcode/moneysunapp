import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';

class PartnershipService {
  final _dbRef = FirebaseDatabase.instance.ref();
  final _currentUser = FirebaseAuth.instance.currentUser;

  // Tạo mã mời ngẫu nhiên
  String _generateCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        6,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  Future<String> getOrCreateInviteCode() async {
    if (_currentUser == null) throw Exception("Chưa đăng nhập");
    final userRef = _dbRef.child('users').child(_currentUser!.uid);
    final snapshot = await userRef.child('inviteCode').get();

    if (snapshot.exists && snapshot.value != null) {
      return snapshot.value as String;
    } else {
      final newCode = _generateCode();
      // Lưu mã vào cả 2 nơi
      await userRef.update({'inviteCode': newCode});
      await _dbRef
          .child('inviteCodes')
          .child(newCode)
          .set(_currentUser!.uid); // <-- THÊM MỚI
      return newCode;
    }
  }

  Future<bool> acceptInvite(String code) async {
    if (_currentUser == null) return false;

    final inviteRef = _dbRef
        .child('inviteCodes')
        .child(code.toUpperCase()); // Chuyển sang chữ hoa để không phân biệt
    final snapshot = await inviteRef.get();

    if (!snapshot.exists || snapshot.value == null) {
      throw Exception("Mã mời không hợp lệ hoặc đã hết hạn.");
    }

    // Lấy partnerUid trực tiếp từ giá trị của snapshot
    final partnerUid = snapshot.value as String;

    if (partnerUid == _currentUser.uid) {
      throw Exception("Bạn không thể mời chính mình.");
    }

    // Kiểm tra xem một trong hai người đã có partner chưa
    final currentUserPartnerId =
        (await _dbRef
                .child('users')
                .child(_currentUser!.uid)
                .child('partnershipId')
                .get())
            .value;
    final partnerUserPartnerId =
        (await _dbRef
                .child('users')
                .child(partnerUid)
                .child('partnershipId')
                .get())
            .value;

    if (currentUserPartnerId != null || partnerUserPartnerId != null) {
      throw Exception(
        "Một trong hai người dùng đã ở trong một mối quan- hệ đối tác.",
      );
    }

    // (Phần logic tạo partnership ở dưới giữ nguyên)
    final newPartnershipRef = _dbRef.child('partnerships').push();
    final partnershipId = newPartnershipRef.key!;

    final partnershipData = {
      'members': {_currentUser.uid: true, partnerUid: true},
      'createdAt': ServerValue.timestamp,
    };
    await newPartnershipRef.set(partnershipData);

    // Cập nhật partnershipId cho cả hai user
    await _dbRef.child('users').child(_currentUser!.uid).update({
      'partnershipId': partnershipId,
    });
    await _dbRef.child('users').child(partnerUid).update({
      'partnershipId': partnershipId,
    });

    final currentUserNotificationRef = _dbRef
        .child('notifications')
        .child(_currentUser!.uid)
        .push();
    await currentUserNotificationRef.set({
      'title': 'Kết nối thành công!',
      'body': 'Bạn đã kết nối thành công với đối tác.',
      'timestamp': ServerValue.timestamp,
    });

    await inviteRef.remove();

    final notificationRef = _dbRef
        .child('notifications')
        .child(partnerUid)
        .push();
    await notificationRef.set({
      'title': 'Kết nối thành công!',
      'body': '${_currentUser.displayName} đã chấp nhận lời mời của bạn.',
      'timestamp': ServerValue.timestamp,
    });

    return true;
  }
}
