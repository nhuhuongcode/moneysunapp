// lib/data/services/partnership_service.dart - FIXED VERSION

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';

class PartnershipService {
  final _dbRef = FirebaseDatabase.instance.ref();
  final _currentUser = FirebaseAuth.instance.currentUser;

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
      // Lưu mã vào cả 2 nơi với proper structure
      await userRef.update({'inviteCode': newCode});
      await _dbRef.child('inviteCodes').child(newCode).set({
        'userId': _currentUser!.uid,
        'createdAt': ServerValue.timestamp,
        'expiresAt': ServerValue.timestamp, // Could add expiration logic
      });
      return newCode;
    }
  }

  // FIX: Sử dụng handlePartnershipInvite từ DatabaseService
  Future<bool> acceptInvite(String code) async {
    if (_currentUser == null) return false;

    try {
      final inviteRef = _dbRef.child('inviteCodes').child(code.toUpperCase());
      final snapshot = await inviteRef.get();

      if (!snapshot.exists) {
        throw Exception("Mã mời không hợp lệ hoặc đã hết hạn.");
      }

      // FIX: Get partnerId from structured data
      final inviteData = snapshot.value as Map<dynamic, dynamic>;
      final partnerUid = inviteData['userId'] as String;

      if (partnerUid == _currentUser!.uid) {
        throw Exception("Bạn không thể mời chính mình.");
      }

      // Check if either user already has a partner
      final currentUserSnapshot = await _dbRef
          .child('users')
          .child(_currentUser!.uid)
          .get();
      final partnerSnapshot = await _dbRef
          .child('users')
          .child(partnerUid)
          .get();

      final currentUserData =
          currentUserSnapshot.value as Map<dynamic, dynamic>?;
      final partnerData = partnerSnapshot.value as Map<dynamic, dynamic>?;

      if (currentUserData?['partnershipId'] != null ||
          partnerData?['partnershipId'] != null) {
        throw Exception("Một trong hai người dùng đã có đối tác.");
      }

      // FIX: Create partnership with proper structure
      final newPartnershipRef = _dbRef.child('partnerships').push();
      final partnershipId = newPartnershipRef.key!;

      final partnershipData = {
        'members': {_currentUser!.uid: true, partnerUid: true},
        'memberNames': {
          _currentUser!.uid: _currentUser!.displayName ?? 'User',
          partnerUid: partnerData?['displayName'] ?? 'Partner',
        },
        'createdAt': ServerValue.timestamp,
        'isActive': true,
        'lastSyncTime': ServerValue.timestamp,
      };

      // FIX: Use transaction to ensure atomicity
      await _dbRef.runTransaction(
        (mutableData) async {
              // Create partnership
              mutableData.child('partnerships').child(partnershipId).value =
                  partnershipData;

              // Update both users
              mutableData
                      .child('users')
                      .child(_currentUser!.uid)
                      .child('partnershipId')
                      .value =
                  partnershipId;
              mutableData
                      .child('users')
                      .child(_currentUser!.uid)
                      .child('partnerUid')
                      .value =
                  partnerUid;
              mutableData
                      .child('users')
                      .child(_currentUser!.uid)
                      .child('partnerDisplayName')
                      .value =
                  partnerData?['displayName'];
              mutableData
                      .child('users')
                      .child(_currentUser!.uid)
                      .child('partnershipCreatedAt')
                      .value =
                  ServerValue.timestamp;

              mutableData
                      .child('users')
                      .child(partnerUid)
                      .child('partnershipId')
                      .value =
                  partnershipId;
              mutableData
                      .child('users')
                      .child(partnerUid)
                      .child('partnerUid')
                      .value =
                  _currentUser!.uid;
              mutableData
                      .child('users')
                      .child(partnerUid)
                      .child('partnerDisplayName')
                      .value =
                  _currentUser!.displayName;
              mutableData
                      .child('users')
                      .child(partnerUid)
                      .child('partnershipCreatedAt')
                      .value =
                  ServerValue.timestamp;

              return mutableData;
            }
            as TransactionHandler,
      );

      // FIX: Send notifications to both users
      await Future.wait([
        _sendNotificationToUser(
          _currentUser!.uid,
          'Kết nối thành công!',
          'Bạn đã kết nối thành công với ${partnerData?['displayName'] ?? 'đối tác'}.',
        ),
        _sendNotificationToUser(
          partnerUid,
          'Có người kết nối với bạn!',
          '${_currentUser!.displayName ?? 'Ai đó'} đã chấp nhận lời mời của bạn.',
        ),
      ]);

      // Clean up invite code
      await inviteRef.remove();

      return true;
    } catch (e) {
      print('Error in acceptInvite: $e');
      rethrow;
    }
  }

  // FIX: Helper method to send notifications
  Future<void> _sendNotificationToUser(
    String userId,
    String title,
    String body,
  ) async {
    try {
      final notificationRef = _dbRef
          .child('user_notifications')
          .child(userId)
          .push();

      await notificationRef.set({
        'title': title,
        'body': body,
        'timestamp': ServerValue.timestamp,
        'type': 'partnership',
        'isRead': false,
      });
    } catch (e) {
      print('Error sending notification to $userId: $e');
    }
  }

  // FIX: Sync partnership data on app start
  Future<void> syncPartnership(String partnershipId) async {
    if (_currentUser == null) return;

    try {
      final partnershipRef = _dbRef.child('partnerships').child(partnershipId);
      final partnershipSnapshot = await partnershipRef.get();

      if (!partnershipSnapshot.exists) {
        // Partnership doesn't exist, clean up user data
        await _dbRef.child('users').child(_currentUser!.uid).update({
          'partnershipId': null,
          'partnerUid': null,
          'partnerDisplayName': null,
          'partnershipCreatedAt': null,
        });
        return;
      }

      // Update last sync time
      await partnershipRef.update({
        'lastSyncTime': ServerValue.timestamp,
        'isActive': true,
      });

      // Update user sync time
      await _dbRef.child('users').child(_currentUser!.uid).update({
        'lastSync': ServerValue.timestamp,
      });
    } catch (e) {
      print('Error syncing partnership: $e');
    }
  }

  // FIX: Check partnership status
  Future<bool> isPartnershipValid(String partnershipId) async {
    try {
      final snapshot = await _dbRef
          .child('partnerships')
          .child(partnershipId)
          .get();

      if (!snapshot.exists) return false;

      final data = snapshot.value as Map<dynamic, dynamic>;
      final members = data['members'] as Map<dynamic, dynamic>?;

      return members?.containsKey(_currentUser?.uid) == true;
    } catch (e) {
      print('Error checking partnership validity: $e');
      return false;
    }
  }
}
