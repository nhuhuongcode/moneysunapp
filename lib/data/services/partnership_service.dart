// lib/data/services/partnership_service.dart - Enhanced version with separate inviteCodes collection
import 'dart:async';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:moneysun/data/models/partnership_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
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

  /// Generate invite code for partnership
  Future<String> generateInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    if (userProvider.hasPartner) {
      throw Exception('Bạn đã có đối tác rồi');
    }

    try {
      debugPrint('🔗 Đang tạo mã mời...');

      // Xóa mã mời cũ nếu có
      await _clearUserInviteCode(userProvider.currentUser!.uid);

      // Generate unique 6-digit code
      String inviteCode;
      bool isUnique = false;
      int attempts = 0;
      const maxAttempts = 10;

      do {
        inviteCode = _generateRandomCode();
        isUnique = await _checkInviteCodeUniqueness(inviteCode);
        attempts++;

        if (!isUnique && attempts < maxAttempts) {
          // Wait a bit before retrying
          await Future.delayed(Duration(milliseconds: 100 * attempts));
        }
      } while (!isUnique && attempts < maxAttempts);

      if (!isUnique) {
        throw Exception('Không thể tạo mã mời duy nhất. Vui lòng thử lại.');
      }

      // Set expiry time (24 hours from now)
      final expiryTime = DateTime.now().add(const Duration(hours: 24));

      // Save invite code to separate collection
      await _dbRef.child('inviteCodes').child(inviteCode).set({
        'userId': userProvider.currentUser!.uid,
        'userDisplayName':
            userProvider.currentUser!.displayName ?? 'Người dùng',
        'userEmail': userProvider.currentUser!.email ?? '',
        'expiryTime': expiryTime.millisecondsSinceEpoch,
        'createdAt': ServerValue.timestamp,
        'isActive': true,
      });

      // Also save reference in user profile for easy lookup
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

  /// Accept partnership invitation
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

    // Validate invite code format
    if (inviteCode.length != 6) {
      throw Exception('Mã mời phải có 6 ký tự');
    }

    try {
      debugPrint('🤝 Đang xử lý mã mời: $inviteCode');

      // Find invite code in separate collection
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

      // Get inviter's current data
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

      // Convert memberIds list to object format for Firebase
      final memberIdsObject = <String, dynamic>{};
      for (int i = 0; i < partnership.memberIds.length; i++) {
        memberIdsObject[partnership.memberIds[i]] = true;
      }

      // Double-check users don't have partners before proceeding
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

      // Use batch updates for atomic operations
      final timestamp = ServerValue.timestamp;
      final partnershipTimestamp =
          partnershipCreationTime.millisecondsSinceEpoch;

      final updates = <String, dynamic>{
        // Create partnership record with proper memberIds format
        'partnerships/$partnershipId/id': partnershipId,
        'partnerships/$partnershipId/memberIds': memberIdsObject,
        'partnerships/$partnershipId/createdAt': partnershipTimestamp,
        'partnerships/$partnershipId/memberNames': partnership.memberNames,
        'partnerships/$partnershipId/isActive': true,

        // Update inviter
        'users/$inviterUid/partnershipId': partnershipId,
        'users/$inviterUid/partnerUid': userProvider.currentUser!.uid,
        'users/$inviterUid/partnerDisplayName':
            userProvider.currentUser!.displayName ?? 'Người dùng',
        'users/$inviterUid/partnershipCreatedAt': partnershipTimestamp,
        'users/$inviterUid/currentInviteCode': null,
        'users/$inviterUid/inviteCodeExpiry': null,
        'users/$inviterUid/updatedAt': timestamp,

        // Update current user
        'users/${userProvider.currentUser!.uid}/partnershipId': partnershipId,
        'users/${userProvider.currentUser!.uid}/partnerUid': inviterUid,
        'users/${userProvider.currentUser!.uid}/partnerDisplayName':
            inviterData['displayName']?.toString() ?? 'Người dùng',
        'users/${userProvider.currentUser!.uid}/partnershipCreatedAt':
            partnershipTimestamp,
        'users/${userProvider.currentUser!.uid}/updatedAt': timestamp,

        // Remove invite code
        'inviteCodes/$inviteCode': null,
      };

      // Execute atomic batch update
      await _dbRef.update(updates).then((_) async {
        // Send success notifications after transaction completes
        await Future.wait([
          _sendPartnershipNotification(
            inviterUid,
            'Kết nối thành công!',
            '${userProvider.currentUser!.displayName ?? "Người dùng"} đã chấp nhận lời mời kết nối của bạn.',
            'partnership_accepted',
          ),
          _sendPartnershipNotification(
            userProvider.currentUser!.uid,
            'Kết nối thành công!',
            'Bạn đã kết nối thành công với ${inviterData['displayName']?.toString() ?? "người dùng"}.',
            'partnership_connected',
          ),
        ]);

        // Trigger DataService sync to update local data
        if (_dataService.isInitialized && _dataService.isOnline) {
          unawaited(_dataService.forceSyncNow());
        }

        debugPrint('✅ Partnership đã tạo thành công: $partnershipId');
      });
    } catch (e) {
      debugPrint('❌ Lỗi khi chấp nhận mời: $e');
      rethrow;
    }
  }

  /// Disconnect partnership
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

      // Use batch updates for atomic operations
      final updates = <String, dynamic>{
        // Send notification to partner before disconnecting
        'user_notifications/$partnerUid/${_dbRef.push().key}': {
          'title': 'Kết nối đã bị ngắt',
          'body':
              '${userProvider.currentUser!.displayName ?? "Đối tác"} đã ngắt kết nối với bạn.',
          'timestamp': ServerValue.timestamp,
          'type': 'partnership_disconnected',
          'isRead': false,
        },

        // Clear partnership data from both users
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

        // Mark partnership as inactive instead of deleting
        'partnerships/$partnershipId/isActive': false,
        'partnerships/$partnershipId/disconnectedAt': ServerValue.timestamp,
        'partnerships/$partnershipId/disconnectedBy': currentUid,
      };

      // Execute batch update
      await _dbRef.update(updates);

      // Trigger DataService sync
      if (_dataService.isInitialized && _dataService.isOnline) {
        unawaited(_dataService.forceSyncNow());
      }

      debugPrint('✅ Partnership đã ngắt kết nối thành công');
    } catch (e) {
      debugPrint('❌ Lỗi khi ngắt kết nối partnership: $e');
      rethrow;
    }
  }

  // ============ INVITE CODE VALIDATION ============

  /// Validate invite code data
  Future<void> _validateInviteCode(
    Map<dynamic, dynamic> codeData,
    UserProvider userProvider,
  ) async {
    // Check if invite code is active
    if (codeData['isActive'] != true) {
      throw Exception('Mã mời không còn hoạt động');
    }

    // Check if inviter is current user
    final inviterUid = codeData['userId'] as String;
    if (inviterUid == userProvider.currentUser!.uid) {
      throw Exception('Bạn không thể kết nối với chính mình');
    }

    // Check invite code expiry
    final expiry = codeData['expiryTime'] as int?;
    if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
      // Auto-clear expired invite code
      final inviteCode = codeData.keys.first;
      unawaited(_clearExpiredInviteCode(inviteCode.toString()));
      throw Exception('Mã mời đã hết hạn');
    }
  }

  /// Validate invitation before accepting
  Future<void> _validateInvitation(
    String inviterUid,
    Map<dynamic, dynamic> inviterData,
    UserProvider userProvider,
  ) async {
    // Check if inviter already has partner
    if (inviterData['partnershipId'] != null) {
      throw Exception('Người tạo mã mời đã có đối tác');
    }

    // Additional validation - check if inviter account is valid
    final displayName = inviterData['displayName']?.toString();
    if (displayName == null || displayName.trim().isEmpty) {
      throw Exception('Tài khoản người mời không hợp lệ');
    }

    // Check if both users have valid email
    final inviterEmail = inviterData['email']?.toString();
    if (inviterEmail == null || inviterEmail.trim().isEmpty) {
      throw Exception('Tài khoản người mời chưa xác minh email');
    }
  }

  /// Clear user's invite code
  Future<void> _clearUserInviteCode(String userId) async {
    try {
      // Get user's current invite code
      final userSnapshot = await _dbRef.child('users').child(userId).get();
      if (userSnapshot.exists) {
        final userData = userSnapshot.value as Map<dynamic, dynamic>;
        final currentCode = userData['currentInviteCode'] as String?;

        if (currentCode != null) {
          // Remove from inviteCodes collection
          await _dbRef.child('inviteCodes').child(currentCode).remove();
        }
      }

      // Clear from user profile
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

  /// Clear expired invite code
  Future<void> _clearExpiredInviteCode(String inviteCode) async {
    try {
      // Get invite code data to find user
      final codeSnapshot = await _dbRef
          .child('inviteCodes')
          .child(inviteCode)
          .get();
      if (codeSnapshot.exists) {
        final codeData = codeSnapshot.value as Map<dynamic, dynamic>;
        final userId = codeData['userId'] as String?;

        if (userId != null) {
          // Clear from user profile
          await _dbRef.child('users').child(userId).update({
            'currentInviteCode': null,
            'inviteCodeExpiry': null,
            'updatedAt': ServerValue.timestamp,
          });
        }
      }

      // Remove from inviteCodes collection
      await _dbRef.child('inviteCodes').child(inviteCode).remove();

      debugPrint('🧹 Đã xóa mã mời hết hạn: $inviteCode');
    } catch (e) {
      debugPrint('⚠️ Lỗi khi xóa mã mời hết hạn: $e');
    }
  }

  // ============ UTILITY METHODS ============

  /// Generate random 6-character code
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

  /// Check if invite code is unique
  Future<bool> _checkInviteCodeUniqueness(String code) async {
    try {
      debugPrint('🔍 Kiểm tra mã: $code');

      final snapshot = await _dbRef
          .child('inviteCodes')
          .child(code.toUpperCase())
          .get();

      if (!snapshot.exists) {
        debugPrint('✅ Mã $code có thể sử dụng');
        return true; // Unique - can use
      }

      // Check if existing code is expired
      final codeData = snapshot.value as Map<dynamic, dynamic>;
      final expiry = codeData['expiryTime'] as int?;

      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        // Clear expired code and return true
        await _clearExpiredInviteCode(code);
        debugPrint('✅ Mã $code đã hết hạn, có thể tái sử dụng');
        return true;
      }

      debugPrint('❌ Mã $code đã tồn tại và còn hiệu lực');
      return false; // Not unique
    } catch (e) {
      debugPrint('❌ Lỗi khi kiểm tra unique: $e');
      throw Exception('Không thể kiểm tra tính duy nhất của mã: $e');
    }
  }

  /// Send partnership notification
  Future<void> _sendPartnershipNotification(
    String recipientUid,
    String title,
    String body,
    String type,
  ) async {
    try {
      await _dbRef.child('user_notifications').child(recipientUid).push().set({
        'title': title,
        'body': body,
        'timestamp': ServerValue.timestamp,
        'type': type,
        'isRead': false,
      });
      debugPrint('📬 Đã gửi thông báo partnership đến: $recipientUid');
    } catch (e) {
      debugPrint('❌ Lỗi khi gửi thông báo partnership: $e');
    }
  }

  // ============ INVITE CODE MANAGEMENT METHODS ============

  /// Cancel invite code
  Future<void> cancelInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('Người dùng chưa đăng nhập');
    }

    try {
      debugPrint('🚫 Đang hủy mã mời...');

      await _clearUserInviteCode(userProvider.currentUser!.uid);

      debugPrint('✅ Đã hủy mã mời');
    } catch (e) {
      debugPrint('❌ Lỗi khi hủy mã mời: $e');
      rethrow;
    }
  }

  /// Get active invite code with validation
  Future<String?> getActiveInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      return null;
    }

    try {
      final snapshot = await _dbRef
          .child('users')
          .child(userProvider.currentUser!.uid)
          .get();

      if (!snapshot.exists) {
        return null;
      }

      final userData = snapshot.value as Map<dynamic, dynamic>;
      final inviteCode = userData['currentInviteCode'] as String?;
      final expiry = userData['inviteCodeExpiry'] as int?;

      if (inviteCode == null) {
        return null;
      }

      // Check if expired
      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        // Auto-clear expired code
        await cancelInviteCode(userProvider);
        return null;
      }

      // Double-check in inviteCodes collection
      final codeSnapshot = await _dbRef
          .child('inviteCodes')
          .child(inviteCode)
          .get();
      if (!codeSnapshot.exists) {
        // Code doesn't exist in collection, clear from user
        await _clearUserInviteCode(userProvider.currentUser!.uid);
        return null;
      }

      return inviteCode;
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy mã mời hoạt động: $e');
      return null;
    }
  }

  /// Check if invite code is valid (for UI validation)
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

      // Check if active
      if (codeData['isActive'] != true) {
        return {'valid': false, 'reason': 'Mã mời không còn hoạt động'};
      }

      // Check expiry
      final expiry = codeData['expiryTime'] as int?;
      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        return {'valid': false, 'reason': 'Mã mời đã hết hạn'};
      }

      // Check if inviter still exists and doesn't have partner
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

  // ============ PARTNERSHIP INFORMATION METHODS ============

  /// Get partnership details
  Future<Partnership?> getPartnershipDetails(String partnershipId) async {
    try {
      debugPrint('📋 Đang lấy thông tin partnership: $partnershipId');

      final snapshot = await _dbRef
          .child('partnerships')
          .child(partnershipId)
          .get();

      if (!snapshot.exists) {
        debugPrint('⚠️ Không tìm thấy partnership: $partnershipId');
        return null;
      }

      final partnership = Partnership.fromSnapshot(snapshot);
      debugPrint('✅ Đã lấy thông tin partnership');
      return partnership;
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy thông tin partnership: $e');
      return null;
    }
  }

  /// Get partner profile
  Future<AppUser?> getPartnerProfile(String partnerUid) async {
    try {
      debugPrint('👤 Đang lấy thông tin đối tác: $partnerUid');

      final snapshot = await _dbRef.child('users').child(partnerUid).get();

      if (!snapshot.exists) {
        debugPrint('⚠️ Không tìm thấy thông tin đối tác: $partnerUid');
        return null;
      }

      final userData = snapshot.value as Map<dynamic, dynamic>;
      final partner = AppUser.fromMap(userData, partnerUid);

      debugPrint('✅ Đã lấy thông tin đối tác');
      return partner;
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy thông tin đối tác: $e');
      return null;
    }
  }

  /// Validate partnership status
  Future<bool> validatePartnershipStatus(UserProvider userProvider) async {
    if (!userProvider.hasPartner) {
      return true; // No partnership to validate
    }

    try {
      debugPrint('🔍 Đang kiểm tra trạng thái partnership...');

      final partnershipId = userProvider.partnershipId!;
      final partnership = await getPartnershipDetails(partnershipId);

      if (partnership == null) {
        debugPrint('⚠️ Partnership không tồn tại, xóa dữ liệu local');
        await _clearLocalPartnershipData(userProvider);
        return false;
      }

      if (!partnership.isActive) {
        debugPrint('⚠️ Partnership không hoạt động, xóa dữ liệu local');
        await _clearLocalPartnershipData(userProvider);
        return false;
      }

      if (!partnership.memberIds.contains(userProvider.currentUser!.uid)) {
        debugPrint('⚠️ User không trong partnership, xóa dữ liệu local');
        await _clearLocalPartnershipData(userProvider);
        return false;
      }

      debugPrint('✅ Trạng thái partnership hợp lệ');
      return true;
    } catch (e) {
      debugPrint('❌ Lỗi khi kiểm tra partnership: $e');
      return false;
    }
  }

  /// Clear local partnership data when invalid
  Future<void> _clearLocalPartnershipData(UserProvider userProvider) async {
    try {
      await _dbRef.child('users').child(userProvider.currentUser!.uid).update({
        'partnershipId': null,
        'partnerUid': null,
        'partnerDisplayName': null,
        'partnershipCreatedAt': null,
        'updatedAt': ServerValue.timestamp,
      });
      debugPrint('🧹 Đã xóa dữ liệu partnership local');
    } catch (e) {
      debugPrint('❌ Lỗi khi xóa dữ liệu partnership: $e');
    }
  }

  /// Get partnership statistics
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

  /// Stream partnership updates
  Stream<Partnership?> streamPartnershipUpdates(String partnershipId) {
    return _dbRef.child('partnerships').child(partnershipId).onValue.map((
      event,
    ) {
      if (!event.snapshot.exists) {
        return null;
      }
      try {
        return Partnership.fromSnapshot(event.snapshot);
      } catch (e) {
        debugPrint('❌ Lỗi khi parse partnership data: $e');
        return null;
      }
    });
  }

  // ============ CLEANUP METHODS ============

  /// Clean up expired invite codes (can be called periodically)
  Future<void> cleanupExpiredInviteCodes() async {
    try {
      debugPrint('🧹 Đang dọn dẹp mã mời hết hạn...');

      final cutoffTime = DateTime.now().millisecondsSinceEpoch;

      // Get all invite codes (Firebase doesn't support orderByChild on nested data easily)
      final snapshot = await _dbRef.child('inviteCodes').get();

      if (snapshot.exists) {
        final inviteCodes = snapshot.value as Map<dynamic, dynamic>;
        final updates = <String, dynamic>{};
        int expiredCount = 0;

        for (final entry in inviteCodes.entries) {
          final code = entry.key as String;
          final codeData = entry.value as Map<dynamic, dynamic>;
          final expiry = codeData['expiryTime'] as int?;
          final userId = codeData['userId'] as String?;

          if (expiry != null && expiry <= cutoffTime) {
            // Mark invite code for removal
            updates['inviteCodes/$code'] = null;

            // Clear from user profile if exists
            if (userId != null) {
              updates['users/$userId/currentInviteCode'] = null;
              updates['users/$userId/inviteCodeExpiry'] = null;
              updates['users/$userId/updatedAt'] = ServerValue.timestamp;
            }

            expiredCount++;
          }
        }

        if (updates.isNotEmpty) {
          await _dbRef.update(updates);
          debugPrint('✅ Đã dọn dẹp $expiredCount mã mời hết hạn');
        } else {
          debugPrint('ℹ️ Không có mã mời hết hạn nào cần dọn dẹp');
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi dọn dẹp mã mời hết hạn: $e');
    }
  }

  /// Clean up inactive partnerships (optional maintenance)
  Future<void> cleanupInactivePartnerships() async {
    try {
      debugPrint('🧹 Đang dọn dẹp partnerships không hoạt động...');

      final snapshot = await _dbRef.child('partnerships').get();

      if (snapshot.exists) {
        final partnerships = snapshot.value as Map<dynamic, dynamic>;
        final updates = <String, dynamic>{};
        int cleanedCount = 0;

        for (final entry in partnerships.entries) {
          final partnershipId = entry.key as String;
          final partnershipData = entry.value as Map<dynamic, dynamic>;

          final isActive = partnershipData['isActive'] as bool? ?? true;
          final disconnectedAt = partnershipData['disconnectedAt'] as int?;

          // Clean up partnerships that have been inactive for more than 30 days
          if (!isActive && disconnectedAt != null) {
            final disconnectedTime = DateTime.fromMillisecondsSinceEpoch(
              disconnectedAt,
            );
            final daysSinceDisconnection = DateTime.now()
                .difference(disconnectedTime)
                .inDays;

            if (daysSinceDisconnection > 30) {
              // Archive instead of delete for data integrity
              updates['archived_partnerships/$partnershipId'] = partnershipData;
              updates['partnerships/$partnershipId'] = null;
              cleanedCount++;
            }
          }
        }

        if (updates.isNotEmpty) {
          await _dbRef.update(updates);
          debugPrint('✅ Đã archive $cleanedCount partnerships cũ');
        } else {
          debugPrint('ℹ️ Không có partnerships nào cần dọn dẹp');
        }
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi dọn dẹp partnerships: $e');
    }
  }

  /// Get invite code statistics (for admin/debug purposes)
  Future<Map<String, dynamic>> getInviteCodeStatistics() async {
    try {
      final snapshot = await _dbRef.child('inviteCodes').get();

      if (!snapshot.exists) {
        return {'totalActiveCodes': 0, 'expiredCodes': 0, 'validCodes': 0};
      }

      final inviteCodes = snapshot.value as Map<dynamic, dynamic>;
      int totalCodes = inviteCodes.length;
      int expiredCodes = 0;
      int validCodes = 0;

      final now = DateTime.now().millisecondsSinceEpoch;

      for (final codeData in inviteCodes.values) {
        final data = codeData as Map<dynamic, dynamic>;
        final expiry = data['expiryTime'] as int?;
        final isActive = data['isActive'] as bool? ?? true;

        if (!isActive || (expiry != null && expiry <= now)) {
          expiredCodes++;
        } else {
          validCodes++;
        }
      }

      return {
        'totalActiveCodes': totalCodes,
        'expiredCodes': expiredCodes,
        'validCodes': validCodes,
        'lastChecked': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy thống kê invite codes: $e');
      return {};
    }
  }

  /// Force sync all partnership data
  Future<void> forceSyncPartnershipData(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      return;
    }

    try {
      debugPrint('🔄 Force sync partnership data...');

      // Validate current partnership status
      if (userProvider.hasPartner) {
        await validatePartnershipStatus(userProvider);
      }

      // Trigger DataService sync if available
      if (_dataService.isInitialized && _dataService.isOnline) {
        await _dataService.forceSyncNow();
      }

      debugPrint('✅ Partnership data sync completed');
    } catch (e) {
      debugPrint('❌ Lỗi khi sync partnership data: $e');
    }
  }

  /// Get all user's partnership history
  Future<List<Map<String, dynamic>>> getPartnershipHistory(
    UserProvider userProvider,
  ) async {
    if (userProvider.currentUser == null) {
      return [];
    }

    try {
      debugPrint('📜 Đang lấy lịch sử partnerships...');

      final userId = userProvider.currentUser!.uid;
      final history = <Map<String, dynamic>>[];

      // Get active partnerships
      final activeSnapshot = await _dbRef
          .child('partnerships')
          .orderByChild('memberIds')
          .get();

      if (activeSnapshot.exists) {
        final partnerships = activeSnapshot.value as Map<dynamic, dynamic>;

        for (final entry in partnerships.entries) {
          final partnershipData = entry.value as Map<dynamic, dynamic>;
          final memberIds = List<String>.from(
            partnershipData['memberIds'] ?? [],
          );

          if (memberIds.contains(userId)) {
            history.add({
              'id': entry.key,
              'type': 'active',
              'data': partnershipData,
            });
          }
        }
      }

      // Get archived partnerships
      final archivedSnapshot = await _dbRef
          .child('archived_partnerships')
          .get();

      if (archivedSnapshot.exists) {
        final archivedPartnerships =
            archivedSnapshot.value as Map<dynamic, dynamic>;

        for (final entry in archivedPartnerships.entries) {
          final partnershipData = entry.value as Map<dynamic, dynamic>;
          final memberIds = List<String>.from(
            partnershipData['memberIds'] ?? [],
          );

          if (memberIds.contains(userId)) {
            history.add({
              'id': entry.key,
              'type': 'archived',
              'data': partnershipData,
            });
          }
        }
      }

      // Sort by creation date (newest first)
      history.sort((a, b) {
        final aCreated = a['data']['createdAt'] as int? ?? 0;
        final bCreated = b['data']['createdAt'] as int? ?? 0;
        return bCreated.compareTo(aCreated);
      });

      debugPrint('✅ Đã lấy ${history.length} partnerships từ lịch sử');
      return history;
    } catch (e) {
      debugPrint('❌ Lỗi khi lấy lịch sử partnerships: $e');
      return [];
    }
  }

  // Utility method for unawaited futures
  void unawaited(Future<void> future) {
    future.catchError((error) {
      debugPrint('Unawaited partnership service error: $error');
    });
  }
}
