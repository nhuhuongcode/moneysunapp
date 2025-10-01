// lib/data/services/partnership_service.dart - Enhanced with comprehensive refresh
import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:moneysun/data/models/partnership_model.dart';
import 'package:moneysun/data/models/user_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/data_service.dart';

class PartnershipService {
  static final PartnershipService _instance = PartnershipService._internal();
  factory PartnershipService() => _instance;
  PartnershipService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DataService _dataService = DataService();

  // ============ INVITE CODE MANAGEMENT ============

  Future<String> generateInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    if (userProvider.hasPartner) {
      throw Exception('Bạn đã có đối tác rồi');
    }

    try {
      debugPrint('🔗 Đang tạo mã mời...');

      await _clearUserInviteCode(userProvider.currentUser!.uid);

      String inviteCode;
      bool isUnique = false;
      int attempts = 0;
      const maxAttempts = 10;

      do {
        inviteCode = _generateRandomCode();
        isUnique = await _checkInviteCodeUniqueness(inviteCode);
        attempts++;

        if (!isUnique && attempts < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 100 * attempts));
        }
      } while (!isUnique && attempts < maxAttempts);

      if (!isUnique) {
        throw Exception('Không thể tạo mã mời duy nhất. Vui lòng thử lại.');
      }

      final expiryTime = DateTime.now().add(const Duration(hours: 24));

      await _dbRef.child('inviteCodes').child(inviteCode).set({
        'userId': userProvider.currentUser!.uid,
        'userDisplayName':
            userProvider.currentUser!.displayName ?? 'Người dùng',
        'userEmail': userProvider.currentUser!.email ?? '',
        'expiryTime': expiryTime.millisecondsSinceEpoch,
        'createdAt': ServerValue.timestamp,
        'isActive': true,
      });

      await _dbRef.child('users').child(userProvider.currentUser!.uid).update({
        'currentInviteCode': inviteCode,
        'inviteCodeExpiry': expiryTime.millisecondsSinceEpoch,
        'updatedAt': ServerValue.timestamp,
      });

      debugPrint(
        '✅ Mã mời đã tạo: $inviteCode (hết hạn: ${expiryTime.toLocal()})',
      );
      return inviteCode;
    } catch (e) {
      debugPrint('❌ Lỗi khi tạo mã mời: $e');
      rethrow;
    }
  }

  /// ✅ FIXED: Accept invitation with comprehensive refresh
  Future<void> acceptInvitation(
    String inviteCode,
    UserProvider userProvider,
  ) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    if (userProvider.hasPartner) {
      throw Exception('Bạn đã có đối tác rồi');
    }

    if (inviteCode.length != 6) {
      throw Exception('Mã mời phải có 6 ký tự');
    }

    try {
      debugPrint('🤝 Đang xử lý mã mời: $inviteCode');

      // Find invite code
      final codeSnapshot = await _dbRef
          .child('inviteCodes')
          .child(inviteCode.toUpperCase())
          .get();

      if (!codeSnapshot.exists) {
        throw Exception('Mã mời không tồn tại hoặc đã hết hạn');
      }

      final codeData = codeSnapshot.value as Map<dynamic, dynamic>;

      // Validate invite code
      await _validateInviteCode(codeData, userProvider);

      final inviterUid = codeData['userId'] as String;

      // Get inviter's data
      final inviterSnapshot = await _dbRef
          .child('users')
          .child(inviterUid)
          .get();

      if (!inviterSnapshot.exists) {
        throw Exception('Người tạo mã mời không tồn tại');
      }

      final inviterData = inviterSnapshot.value as Map<dynamic, dynamic>;

      // Final validation
      await _validateInvitation(inviterUid, inviterData, userProvider);

      // Create partnership
      final partnershipId =
          'partnership_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
      final partnershipCreationTime = DateTime.now();

      final partnership = Partnership(
        id: partnershipId,
        memberIds: [inviterUid, userProvider.currentUser!.uid],
        createdAt: partnershipCreationTime,
        memberNames: {
          inviterUid: inviterData['displayName']?.toString() ?? 'Người dùng',
          userProvider.currentUser!.uid:
              userProvider.currentUser!.displayName ?? 'Người dùng',
        },
        isActive: true,
      );

      // Double-check before proceeding
      final inviterCheck = await _dbRef.child('users/$inviterUid').get();
      final currentUserCheck = await _dbRef
          .child('users/${userProvider.currentUser!.uid}')
          .get();

      final inviterCurrentData =
          inviterCheck.value as Map<dynamic, dynamic>? ?? {};
      final currentUserCurrentData =
          currentUserCheck.value as Map<dynamic, dynamic>? ?? {};

      if (inviterCurrentData['partnershipId'] != null) {
        throw Exception('Người tạo mã mời đã có đối tác');
      }

      if (currentUserCurrentData['partnershipId'] != null) {
        throw Exception('Bạn đã có đối tác');
      }

      // ✅ STEP 1: Execute partnership creation
      debugPrint('🔧 Executing partnership creation...');
      await _executePartnershipCreation(
        partnership,
        inviterUid,
        userProvider,
        inviteCode,
        inviterData,
      );

      // ✅ STEP 2: Force refresh UserProvider and WAIT for completion
      debugPrint('🔄 Force refreshing UserProvider...');
      await _forceRefreshUserProviderAndWait(userProvider, partnershipId);

      // ✅ STEP 3: Force sync DataService
      debugPrint('🔄 Force syncing DataService...');
      await _forceSyncDataService();

      // ✅ STEP 4: Final UI update trigger
      debugPrint('📢 Triggering final UI updates...');
      await Future.delayed(const Duration(milliseconds: 300));

      debugPrint('✅ Partnership acceptance completed successfully');
    } catch (e) {
      debugPrint('❌ Lỗi khi chấp nhận mời: $e');
      rethrow;
    }
  }

  Future<void> _executePartnershipCreation(
    Partnership partnership,
    String inviterUid,
    UserProvider userProvider,
    String inviteCode,
    Map<dynamic, dynamic> inviterData,
  ) async {
    final partnershipId = partnership.id;
    final currentUid = userProvider.currentUser!.uid;
    final timestamp = ServerValue.timestamp;
    final partnershipTimestamp = partnership.createdAt.millisecondsSinceEpoch;

    debugPrint('🔧 Creating partnership: $partnershipId');
    debugPrint('   Inviter: $inviterUid');
    debugPrint('   Accepter: $currentUid');

    try {
      // ✅ STEP 1: Create partnership record with CORRECT structure
      await _dbRef.child('partnerships').child(partnershipId).set({
        'id': partnershipId,
        // ✅ FIX: Use memberIds (not members)
        'memberIds': {inviterUid: true, currentUid: true},
        'createdAt': partnershipTimestamp,
        'memberNames': {
          inviterUid: partnership.memberNames[inviterUid],
          currentUid: partnership.memberNames[currentUid],
        },
        'isActive': true,
        'lastSyncTime': timestamp,
      });
      debugPrint('✅ Partnership record created');

      // ✅ STEP 2: Update both users
      final userUpdates = <String, dynamic>{
        // Inviter updates
        'users/$inviterUid/partnershipId': partnershipId,
        'users/$inviterUid/partnerUid': currentUid,
        'users/$inviterUid/partnerDisplayName':
            userProvider.currentUser!.displayName ?? 'Người dùng',
        'users/$inviterUid/partnerPhotoURL': userProvider.currentUser!.photoURL,
        'users/$inviterUid/partnershipCreatedAt': partnershipTimestamp,
        'users/$inviterUid/currentInviteCode': null,
        'users/$inviterUid/inviteCodeExpiry': null,
        'users/$inviterUid/updatedAt': timestamp,
        'users/$inviterUid/lastPartnerUpdate': timestamp,

        // Accepter updates
        'users/$currentUid/partnershipId': partnershipId,
        'users/$currentUid/partnerUid': inviterUid,
        'users/$currentUid/partnerDisplayName':
            inviterData['displayName']?.toString() ?? 'Người dùng',
        'users/$currentUid/partnerPhotoURL': inviterData['photoURL']
            ?.toString(),
        'users/$currentUid/partnershipCreatedAt': partnershipTimestamp,
        'users/$currentUid/updatedAt': timestamp,
        'users/$currentUid/lastPartnerUpdate': timestamp,

        // Remove invite code
        'inviteCodes/$inviteCode': null,
      };

      await _dbRef.update(userUpdates);
      debugPrint('✅ Both users updated in Firebase');

      // ✅ VERIFY: Check if updates were successful
      final verifyInviter = await _dbRef
          .child('users/$inviterUid/partnershipId')
          .get();
      final verifyAccepter = await _dbRef
          .child('users/$currentUid/partnershipId')
          .get();

      debugPrint('🔍 Verification:');
      debugPrint('   Inviter partnershipId: ${verifyInviter.value}');
      debugPrint('   Accepter partnershipId: ${verifyAccepter.value}');

      // Continue with notifications...
      await _sendRefreshTriggersToUsers(inviterUid, currentUid, partnershipId);
      await _sendPartnershipNotifications(
        inviterUid,
        currentUid,
        userProvider.currentUser!.displayName ?? 'Người dùng',
        inviterData['displayName']?.toString() ?? 'Người dùng',
      );
      await _triggerGlobalPartnershipUpdate(partnershipId, [
        inviterUid,
        currentUid,
      ]);

      debugPrint('✅ Partnership creation completed successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Error in partnership creation: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<void> _sendRefreshTriggersToUsers(
    String inviterUid,
    String currentUid,
    String partnershipId,
  ) async {
    try {
      debugPrint('📤 Sending HIGH PRIORITY refresh triggers to both users...');

      final refreshData = {
        'type': 'partnership_created',
        'partnershipId': partnershipId,
        'timestamp': ServerValue.timestamp,
        'requireRefresh': true,
        'priority': 'high',
        'forceReload': true,
      };

      // Send to both users simultaneously
      await Future.wait([
        _dbRef
            .child('user_refresh_triggers')
            .child(inviterUid)
            .push()
            .set(refreshData),
        _dbRef
            .child('user_refresh_triggers')
            .child(currentUid)
            .push()
            .set(refreshData),
      ]);

      debugPrint('✅ HIGH-PRIORITY refresh triggers sent to both users');
    } catch (e) {
      debugPrint('❌ Error sending refresh triggers: $e');
    }
  }

  /// ✅ NEW: Trigger global partnership update
  Future<void> _triggerGlobalPartnershipUpdate(
    String partnershipId,
    List<String> affectedUsers,
  ) async {
    try {
      debugPrint('🌐 Triggering global partnership update...');

      await _dbRef.child('partnership_updates').push().set({
        'type': 'partnership_created',
        'partnershipId': partnershipId,
        'affectedUsers': affectedUsers,
        'timestamp': ServerValue.timestamp,
        'priority': 'high',
      });

      debugPrint('✅ Global partnership update triggered');
    } catch (e) {
      debugPrint('❌ Error triggering global update: $e');
    }
  }

  /// ✅ ENHANCED: Send notifications with action data
  Future<void> _sendPartnershipNotifications(
    String inviterUid,
    String currentUid,
    String currentUserName,
    String inviterName,
  ) async {
    try {
      final timestamp = ServerValue.timestamp;

      // ✅ High-priority notification for INVITER
      await _dbRef.child('user_notifications').child(inviterUid).push().set({
        'title': 'Kết nối thành công! 🎉',
        'body': '$currentUserName đã chấp nhận lời mời kết nối của bạn.',
        'type': 'partnership_accepted',
        'timestamp': timestamp,
        'isRead': false,
        'priority': 'high',
        'requiresAction': true,
        'actionData': {
          'partnerUid': currentUid,
          'partnerName': currentUserName,
          'action': 'refresh_partnership',
        },
      });

      // Notification for accepter
      await _dbRef.child('user_notifications').child(currentUid).push().set({
        'title': 'Kết nối thành công! 🎉',
        'body': 'Bạn đã kết nối thành công với $inviterName.',
        'type': 'partnership_connected',
        'timestamp': timestamp,
        'isRead': false,
        'priority': 'high',
        'requiresAction': true,
        'actionData': {
          'partnerUid': inviterUid,
          'partnerName': inviterName,
          'action': 'refresh_partnership',
        },
      });

      debugPrint('✅ High-priority notifications sent to both users');
    } catch (e) {
      debugPrint('❌ Error sending notifications: $e');
    }
  }

  /// ✅ NEW: Force refresh UserProvider and WAIT for completion
  Future<void> _forceRefreshUserProviderAndWait(
    UserProvider userProvider,
    String expectedPartnershipId,
  ) async {
    debugPrint('🔄 Force refreshing UserProvider and waiting...');

    // Trigger first refresh
    await userProvider.refreshUser();

    // Wait up to 5 seconds for partnership to be set
    final stopwatch = Stopwatch()..start();
    int refreshCount = 0;

    while (userProvider.partnershipId != expectedPartnershipId &&
        stopwatch.elapsed.inSeconds < 5) {
      await Future.delayed(const Duration(milliseconds: 100));
      await userProvider.refreshUser();
      refreshCount++;
    }

    if (userProvider.partnershipId == expectedPartnershipId) {
      debugPrint(
        '✅ UserProvider updated with partnership after $refreshCount attempts',
      );
    } else {
      debugPrint(
        '⚠️ UserProvider update timeout after $refreshCount attempts - but continuing',
      );
    }
  }

  /// ✅ NEW: Force sync DataService
  Future<void> _forceSyncDataService() async {
    debugPrint('🔄 Force syncing DataService...');

    if (!_dataService.isInitialized || !_dataService.isOnline) {
      debugPrint('⚠️ DataService not ready for sync');
      return;
    }

    try {
      await _dataService.forceSyncNow();

      // Wait for Firebase propagation
      await Future.delayed(const Duration(milliseconds: 500));

      debugPrint('✅ DataService sync completed');
    } catch (e) {
      debugPrint('❌ Error syncing DataService: $e');
    }
  }

  // ============ DISCONNECT PARTNERSHIP ============

  Future<void> disconnectPartnership(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    if (!userProvider.hasPartner) {
      throw Exception('Bạn không có đối tác để ngắt kết nối');
    }

    try {
      debugPrint('💔 Đang ngắt kết nối partnership...');

      final partnershipId = userProvider.partnershipId!;
      final partnerUid = userProvider.partnerUid!;
      final currentUid = userProvider.currentUser!.uid;

      final updates = <String, dynamic>{
        'user_notifications/$partnerUid/${_dbRef.push().key}': {
          'title': 'Kết nối đã bị ngắt',
          'body':
              '${userProvider.currentUser!.displayName ?? "Đối tác"} đã ngắt kết nối với bạn.',
          'timestamp': ServerValue.timestamp,
          'type': 'partnership_disconnected',
          'isRead': false,
        },
        'users/$currentUid/partnershipId': null,
        'users/$currentUid/partnerUid': null,
        'users/$currentUid/partnerDisplayName': null,
        'users/$currentUid/partnershipCreatedAt': null,
        'users/$currentUid/updatedAt': ServerValue.timestamp,
        'users/$partnerUid/partnershipId': null,
        'users/$partnerUid/partnerUid': null,
        'users/$partnerUid/partnerDisplayName': null,
        'users/$partnerUid/partnershipCreatedAt': null,
        'users/$partnerUid/updatedAt': ServerValue.timestamp,
        'partnerships/$partnershipId/isActive': false,
        'partnerships/$partnershipId/disconnectedAt': ServerValue.timestamp,
        'partnerships/$partnershipId/disconnectedBy': currentUid,
      };

      await _dbRef.update(updates);

      if (_dataService.isInitialized && _dataService.isOnline) {
        unawaited(_dataService.forceSyncNow());
      }

      debugPrint('✅ Partnership đã ngắt kết nối thành công');
    } catch (e) {
      debugPrint('❌ Lỗi khi ngắt kết nối partnership: $e');
      rethrow;
    }
  }

  // ============ VALIDATION METHODS ============

  Future<void> _validateInviteCode(
    Map<dynamic, dynamic> codeData,
    UserProvider userProvider,
  ) async {
    if (codeData['isActive'] != true) {
      throw Exception('Mã mời không còn hoạt động');
    }

    final inviterUid = codeData['userId'] as String;
    if (inviterUid == userProvider.currentUser!.uid) {
      throw Exception('Bạn không thể kết nối với chính mình');
    }

    final expiry = codeData['expiryTime'] as int?;
    if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
      final inviteCode = codeData.keys.first;
      unawaited(_clearExpiredInviteCode(inviteCode.toString()));
      throw Exception('Mã mời đã hết hạn');
    }
  }

  Future<void> _validateInvitation(
    String inviterUid,
    Map<dynamic, dynamic> inviterData,
    UserProvider userProvider,
  ) async {
    if (inviterData['partnershipId'] != null) {
      throw Exception('Người tạo mã mời đã có đối tác');
    }

    final displayName = inviterData['displayName']?.toString();
    if (displayName == null || displayName.trim().isEmpty) {
      throw Exception('Tài khoản người mời không hợp lệ');
    }

    final inviterEmail = inviterData['email']?.toString();
    if (inviterEmail == null || inviterEmail.trim().isEmpty) {
      throw Exception('Tài khoản người mời chưa xác minh email');
    }
  }

  // ============ UTILITY METHODS ============

  Future<void> _clearUserInviteCode(String userId) async {
    try {
      final userSnapshot = await _dbRef.child('users').child(userId).get();
      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        final currentCode = userData['currentInviteCode'] as String?;

        if (currentCode != null) {
          await _dbRef.child('inviteCodes').child(currentCode).remove();
        }
      }

      await _dbRef.child('users').child(userId).update({
        'currentInviteCode': null,
        'inviteCodeExpiry': null,
        'updatedAt': ServerValue.timestamp,
      });

      debugPrint('🧹 Đã xóa mã mời cũ của user: $userId');
    } catch (e) {
      debugPrint('⚠️ Lỗi khi xóa mã mời cũ: $e');
    }
  }

  Future<void> _clearExpiredInviteCode(String inviteCode) async {
    try {
      final codeSnapshot = await _dbRef
          .child('inviteCodes')
          .child(inviteCode)
          .get();
      if (codeSnapshot.exists) {
        final codeData = codeSnapshot.value as Map<dynamic, dynamic>;
        final userId = codeData['userId'] as String?;

        if (userId != null) {
          await _dbRef.child('users').child(userId).update({
            'currentInviteCode': null,
            'inviteCodeExpiry': null,
            'updatedAt': ServerValue.timestamp,
          });
        }
      }

      await _dbRef.child('inviteCodes').child(inviteCode).remove();
      debugPrint('🧹 Đã xóa mã mời hết hạn: $inviteCode');
    } catch (e) {
      debugPrint('⚠️ Lỗi khi xóa mã mời hết hạn: $e');
    }
  }

  String _generateRandomCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    return String.fromCharCodes(
      Iterable.generate(
        6,
        (_) => chars.codeUnitAt(random.nextInt(chars.length)),
      ),
    );
  }

  Future<bool> _checkInviteCodeUniqueness(String code) async {
    try {
      final snapshot = await _dbRef
          .child('inviteCodes')
          .child(code.toUpperCase())
          .get();

      if (!snapshot.exists) {
        return true;
      }

      final codeData = snapshot.value as Map<dynamic, dynamic>;
      final expiry = codeData['expiryTime'] as int?;

      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        await _clearExpiredInviteCode(code);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('❌ Lỗi khi kiểm tra unique: $e');
      throw Exception('Không thể kiểm tra tính duy nhất của mã: $e');
    }
  }

  // ============ PUBLIC UTILITY METHODS ============

  Future<void> cancelInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    try {
      await _clearUserInviteCode(userProvider.currentUser!.uid);
      debugPrint('✅ Đã hủy mã mời');
    } catch (e) {
      debugPrint('❌ Lỗi khi hủy mã mời: $e');
      rethrow;
    }
  }

  Future<String?> getActiveInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) return null;

    try {
      final snapshot = await _dbRef
          .child('users')
          .child(userProvider.currentUser!.uid)
          .get();

      if (!snapshot.exists) return null;

      final userData = snapshot.value as Map<dynamic, dynamic>;
      final inviteCode = userData['currentInviteCode'] as String?;
      final expiry = userData['inviteCodeExpiry'] as int?;

      if (inviteCode == null) return null;

      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        await cancelInviteCode(userProvider);
        return null;
      }

      final codeSnapshot = await _dbRef
          .child('inviteCodes')
          .child(inviteCode)
          .get();
      if (!codeSnapshot.exists) {
        await _clearUserInviteCode(userProvider.currentUser!.uid);
        return null;
      }

      return inviteCode;
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy mã mời hoạt động: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> validateInviteCode(String inviteCode) async {
    if (inviteCode.length != 6) {
      return {'valid': false, 'reason': 'Mã mời phải có 6 ký tự'};
    }

    try {
      final codeSnapshot = await _dbRef
          .child('inviteCodes')
          .child(inviteCode.toUpperCase())
          .get();

      if (!codeSnapshot.exists) {
        return {'valid': false, 'reason': 'Mã mời không tồn tại'};
      }

      final codeData = codeSnapshot.value as Map<dynamic, dynamic>;

      if (codeData['isActive'] != true) {
        return {'valid': false, 'reason': 'Mã mời không còn hoạt động'};
      }

      final expiry = codeData['expiryTime'] as int?;
      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        return {'valid': false, 'reason': 'Mã mời đã hết hạn'};
      }

      final inviterUid = codeData['userId'] as String;
      final inviterSnapshot = await _dbRef
          .child('users')
          .child(inviterUid)
          .get();

      if (!inviterSnapshot.exists) {
        return {'valid': false, 'reason': 'Người tạo mã mời không tồn tại'};
      }

      final inviterData = inviterSnapshot.value as Map<dynamic, dynamic>;
      if (inviterData['partnershipId'] != null) {
        return {'valid': false, 'reason': 'Người tạo mã mời đã có đối tác'};
      }

      return {
        'valid': true,
        'inviterName': codeData['userDisplayName'] ?? 'Người dùng',
        'inviterEmail': codeData['userEmail'] ?? '',
      };
    } catch (e) {
      return {'valid': false, 'reason': 'Lỗi khi kiểm tra mã mời'};
    }
  }

  Future<Partnership?> getPartnershipDetails(String partnershipId) async {
    try {
      final snapshot = await _dbRef
          .child('partnerships')
          .child(partnershipId)
          .get();

      if (!snapshot.exists) return null;

      return Partnership.fromSnapshot(snapshot);
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy thông tin partnership: $e');
      return null;
    }
  }

  Future<AppUser?> getPartnerProfile(String partnerUid) async {
    try {
      final snapshot = await _dbRef.child('users').child(partnerUid).get();

      if (!snapshot.exists) return null;

      final userData = snapshot.value as Map<dynamic, dynamic>;
      return AppUser.fromMap(userData, partnerUid);
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy thông tin đối tác: $e');
      return null;
    }
  }

  void unawaited(Future<void> future) {
    future.catchError((error) {
      debugPrint('Unawaited partnership service error: $error');
    });
  }

  Future<Map<String, dynamic>> getPartnershipStatistics(
    UserProvider userProvider,
  ) async {
    if (!userProvider.hasPartner) {
      return {};
    }

    try {
      debugPrint('📊 Đang tính thống kê partnership...');

      final partnership = await getPartnershipDetails(
        userProvider.partnershipId!,
      );
      if (partnership == null) {
        return {};
      }

      // Calculate partnership duration
      final now = DateTime.now();
      final duration = now.difference(partnership.createdAt);

      // Get shared transactions (would need DataService implementation)
      // For now, return basic statistics
      final statistics = {
        'duration': {
          'days': duration.inDays,
          'months': (duration.inDays / 30).round(),
          'years': (duration.inDays / 365).round(),
        },
        'partnership': {
          'createdAt': partnership.createdAt.toIso8601String(),
          'memberCount': partnership.memberIds.length,
          'isActive': partnership.isActive,
        },
        'financial': {
          'totalSharedExpenses': 0.0,
          'totalSharedIncome': 0.0,
          'sharedBalance': 0.0,
          'transactionCount': 0,
        },
      };

      debugPrint('✅ Đã tính thống kê partnership');
      return statistics;
    } catch (e) {
      debugPrint('❌ Lỗi khi tính thống kê partnership: $e');
      return {};
    }
  }

  /// ✅ NEW: Check if partnership already exists between two users
  Future<String?> _findExistingPartnership(String uid1, String uid2) async {
    try {
      debugPrint(
        '🔍 Checking for existing partnership between $uid1 and $uid2',
      );

      final partnershipsSnapshot = await _dbRef.child('partnerships').get();

      if (!partnershipsSnapshot.exists) {
        debugPrint('   No partnerships found');
        return null;
      }

      final partnershipsData =
          partnershipsSnapshot.value as Map<dynamic, dynamic>;

      for (final entry in partnershipsData.entries) {
        final partnershipId = entry.key as String;
        final data = entry.value as Map<dynamic, dynamic>;

        final isActive = data['isActive'] as bool? ?? true;
        if (!isActive) continue;

        final memberIds = data['memberIds'] as Map<dynamic, dynamic>?;
        if (memberIds == null) continue;

        final members = memberIds.keys.toList();

        if (members.contains(uid1) && members.contains(uid2)) {
          debugPrint('   ✅ Found existing partnership: $partnershipId');
          return partnershipId;
        }
      }

      debugPrint('   ℹ️ No existing partnership found');
      return null;
    } catch (e) {
      debugPrint('❌ Error checking existing partnership: $e');
      return null;
    }
  }
}
