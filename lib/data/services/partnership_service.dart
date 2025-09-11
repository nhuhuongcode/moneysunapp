// lib/data/services/_partnership_service.dart
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

///  Partnership Service that works with DataService
class PartnershipService {
  static final PartnershipService _instance = PartnershipService._internal();
  factory PartnershipService() => _instance;
  PartnershipService._internal();

  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DataService _dataService = DataService();

  /// Generate invite code for partnership
  Future<String> generateInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('User not authenticated');
    }

    if (userProvider.hasPartner) {
      throw Exception('User already has a partner');
    }

    try {
      debugPrint('🔗 Generating invite code...');

      // Generate unique 6-digit code
      String inviteCode;
      bool isUnique = false;
      int attempts = 0;
      const maxAttempts = 10;

      do {
        inviteCode = _generateRandomCode();
        isUnique = await _checkInviteCodeUniqueness(inviteCode);
        attempts++;
      } while (!isUnique && attempts < maxAttempts);

      if (!isUnique) {
        throw Exception('Failed to generate unique invite code');
      }

      // Save invite code to user profile
      await _dbRef.child('users').child(userProvider.currentUser!.uid).update({
        'inviteCode': inviteCode,
        'inviteCodeExpiry': DateTime.now()
            .add(const Duration(hours: 24))
            .millisecondsSinceEpoch,
        'updatedAt': ServerValue.timestamp,
      });

      debugPrint('✅ Invite code generated: $inviteCode');
      return inviteCode;
    } catch (e) {
      debugPrint('❌ Error generating invite code: $e');
      rethrow;
    }
  }

  /// Accept partnership invitation
  Future<void> acceptInvitation(
    String inviteCode,
    UserProvider userProvider,
  ) async {
    if (userProvider.currentUser == null) {
      throw Exception('User not authenticated');
    }

    if (userProvider.hasPartner) {
      throw Exception('User already has a partner');
    }

    try {
      debugPrint('🤝 Accepting invitation: $inviteCode');

      // Find user with this invite code
      final usersQuery = await _dbRef
          .child('users')
          .orderByChild('inviteCode')
          .equalTo(inviteCode)
          .get();

      if (!usersQuery.exists) {
        throw Exception('Invalid invite code');
      }

      final usersData = usersQuery.value as Map<dynamic, dynamic>;
      final inviterEntry = usersData.entries.first;
      final inviterUid = inviterEntry.key as String;
      final inviterData = inviterEntry.value as Map<dynamic, dynamic>;

      // Check if inviter is current user
      if (inviterUid == userProvider.currentUser!.uid) {
        throw Exception('Cannot accept your own invitation');
      }

      // Check invite code expiry
      final expiry = inviterData['inviteCodeExpiry'] as int?;
      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        throw Exception('Invite code has expired');
      }

      // Check if inviter already has partner
      if (inviterData['partnershipId'] != null) {
        throw Exception('Inviter already has a partner');
      }

      // Create partnership
      final partnershipId =
          'partnership_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

      final partnership = Partnership(
        id: partnershipId,
        memberIds: [inviterUid, userProvider.currentUser!.uid],
        createdAt: DateTime.now(),
        memberNames: {
          inviterUid: inviterData['displayName'] ?? 'Unknown',
          userProvider.currentUser!.uid:
              userProvider.currentUser!.displayName ?? 'Unknown',
        },
      );

      // Create partnership record
      await _dbRef
          .child('partnerships')
          .child(partnershipId)
          .set(partnership.toJson());

      // Update both users with partnership info
      final batch = <String, Map<String, dynamic>>{
        'users/${inviterUid}': {
          'partnershipId': partnershipId,
          'partnerUid': userProvider.currentUser!.uid,
          'partnerDisplayName': userProvider.currentUser!.displayName,
          'partnershipCreatedAt': DateTime.now().millisecondsSinceEpoch,
          'inviteCode': null, // Clear invite code
          'inviteCodeExpiry': null,
          'updatedAt': ServerValue.timestamp,
        },
        'users/${userProvider.currentUser!.uid}': {
          'partnershipId': partnershipId,
          'partnerUid': inviterUid,
          'partnerDisplayName': inviterData['displayName'],
          'partnershipCreatedAt': DateTime.now().millisecondsSinceEpoch,
          'updatedAt': ServerValue.timestamp,
        },
      };

      await _dbRef.update(batch);

      // Send notification to inviter
      await _sendPartnershipNotification(
        inviterUid,
        'Partnership Accepted',
        '${userProvider.currentUser!.displayName} has accepted your partnership invitation!',
        'partnership_accepted',
      );

      // Trigger DataService sync to update local data
      if (_dataService.isOnline) {
        await _dataService.forceSyncNow();
      }

      debugPrint('✅ Partnership created successfully: $partnershipId');
    } catch (e) {
      debugPrint('❌ Error accepting invitation: $e');
      rethrow;
    }
  }

  /// Disconnect partnership
  Future<void> disconnectPartnership(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('User not authenticated');
    }

    if (!userProvider.hasPartner) {
      throw Exception('User has no partner to disconnect');
    }

    try {
      debugPrint('💔 Disconnecting partnership...');

      final partnershipId = userProvider.partnershipId!;
      final partnerUid = userProvider.partnerUid!;

      // Send notification to partner before disconnecting
      await _sendPartnershipNotification(
        partnerUid,
        'Partnership Disconnected',
        '${userProvider.currentUser!.displayName} has ended the partnership.',
        'partnership_disconnected',
      );

      // Remove partnership data from both users
      final batch = <String, Map<String, dynamic>>{
        'users/${userProvider.currentUser!.uid}': {
          'partnershipId': null,
          'partnerUid': null,
          'partnerDisplayName': null,
          'partnershipCreatedAt': null,
          'updatedAt': ServerValue.timestamp,
        },
        'users/$partnerUid': {
          'partnershipId': null,
          'partnerUid': null,
          'partnerDisplayName': null,
          'partnershipCreatedAt': null,
          'updatedAt': ServerValue.timestamp,
        },
      };

      await _dbRef.update(batch);

      // Delete partnership record
      await _dbRef.child('partnerships').child(partnershipId).remove();

      // Trigger DataService sync
      if (_dataService.isOnline) {
        await _dataService.forceSyncNow();
      }

      debugPrint('✅ Partnership disconnected successfully');
    } catch (e) {
      debugPrint('❌ Error disconnecting partnership: $e');
      rethrow;
    }
  }

  /// Get partnership details
  Future<Partnership?> getPartnershipDetails(String partnershipId) async {
    try {
      debugPrint('📋 Getting partnership details: $partnershipId');

      final snapshot = await _dbRef
          .child('partnerships')
          .child(partnershipId)
          .get();

      if (!snapshot.exists) {
        debugPrint('⚠️ Partnership not found: $partnershipId');
        return null;
      }

      final partnership = Partnership.fromSnapshot(snapshot);
      debugPrint('✅ Partnership details retrieved');
      return partnership;
    } catch (e) {
      debugPrint('❌ Error getting partnership details: $e');
      return null;
    }
  }

  /// Get partner profile
  Future<AppUser?> getPartnerProfile(String partnerUid) async {
    try {
      debugPrint('👤 Getting partner profile: $partnerUid');

      final snapshot = await _dbRef.child('users').child(partnerUid).get();

      if (!snapshot.exists) {
        debugPrint('⚠️ Partner profile not found: $partnerUid');
        return null;
      }

      final userData = snapshot.value as Map<dynamic, dynamic>;
      final partner = AppUser.fromMap(userData, partnerUid);

      debugPrint('✅ Partner profile retrieved');
      return partner;
    } catch (e) {
      debugPrint('❌ Error getting partner profile: $e');
      return null;
    }
  }

  /// Validate partnership status
  Future<bool> validatePartnershipStatus(UserProvider userProvider) async {
    if (!userProvider.hasPartner) {
      return true; // No partnership to validate
    }

    try {
      debugPrint('🔍 Validating partnership status...');

      final partnershipId = userProvider.partnershipId!;
      final partnership = await getPartnershipDetails(partnershipId);

      if (partnership == null) {
        debugPrint('⚠️ Partnership not found, clearing local data');
        await _clearPartnershipData(userProvider);
        return false;
      }

      if (!partnership.isActive) {
        debugPrint('⚠️ Partnership is inactive, clearing local data');
        await _clearPartnershipData(userProvider);
        return false;
      }

      if (!partnership.memberIds.contains(userProvider.currentUser!.uid)) {
        debugPrint('⚠️ User not in partnership, clearing local data');
        await _clearPartnershipData(userProvider);
        return false;
      }

      debugPrint('✅ Partnership status valid');
      return true;
    } catch (e) {
      debugPrint('❌ Error validating partnership: $e');
      return false;
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
      debugPrint('📊 Getting partnership statistics...');

      final partnership = await getPartnershipDetails(
        userProvider.partnershipId!,
      );
      if (partnership == null) {
        return {};
      }

      // Calculate partnership duration
      final now = DateTime.now();
      final duration = now.difference(partnership.createdAt);

      // Get shared transactions (this would need implementation in DataService)
      final sharedTransactions = await _dataService.getTransactions(
        startDate: partnership.createdAt,
        endDate: now,
      );

      final sharedExpenses = sharedTransactions
          .where((t) => t.type == TransactionType.expense)
          .fold(0.0, (sum, t) => sum + t.amount);

      final sharedIncome = sharedTransactions
          .where((t) => t.type == TransactionType.income)
          .fold(0.0, (sum, t) => sum + t.amount);

      final statistics = {
        'duration': {
          'days': duration.inDays,
          'months': (duration.inDays / 30).round(),
          'years': (duration.inDays / 365).round(),
        },
        'financial': {
          'totalSharedExpenses': sharedExpenses,
          'totalSharedIncome': sharedIncome,
          'sharedBalance': sharedIncome - sharedExpenses,
          'transactionCount': sharedTransactions.length,
        },
        'partnership': {
          'createdAt': partnership.createdAt.toIso8601String(),
          'memberCount': partnership.memberIds.length,
          'isActive': partnership.isActive,
        },
      };

      debugPrint('✅ Partnership statistics calculated');
      return statistics;
    } catch (e) {
      debugPrint('❌ Error getting partnership statistics: $e');
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
      return Partnership.fromSnapshot(event.snapshot);
    });
  }

  /// Clear partnership data locally
  Future<void> _clearPartnershipData(UserProvider userProvider) async {
    try {
      await _dbRef.child('users').child(userProvider.currentUser!.uid).update({
        'partnershipId': null,
        'partnerUid': null,
        'partnerDisplayName': null,
        'partnershipCreatedAt': null,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('❌ Error clearing partnership data: $e');
    }
  }

  /// Generate random 6-digit code
  String _generateRandomCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  /// Check if invite code is unique
  Future<bool> _checkInviteCodeUniqueness(String code) async {
    try {
      final query = await _dbRef
          .child('users')
          .orderByChild('inviteCode')
          .equalTo(code)
          .get();

      return !query.exists;
    } catch (e) {
      debugPrint('❌ Error checking invite code uniqueness: $e');
      return false;
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
    } catch (e) {
      debugPrint('❌ Error sending partnership notification: $e');
    }
  }

  /// Cancel invite code
  Future<void> cancelInviteCode(UserProvider userProvider) async {
    if (userProvider.currentUser == null) {
      throw Exception('User not authenticated');
    }

    try {
      debugPrint('🚫 Canceling invite code...');

      await _dbRef.child('users').child(userProvider.currentUser!.uid).update({
        'inviteCode': null,
        'inviteCodeExpiry': null,
        'updatedAt': ServerValue.timestamp,
      });

      debugPrint('✅ Invite code canceled');
    } catch (e) {
      debugPrint('❌ Error canceling invite code: $e');
      rethrow;
    }
  }

  /// Get active invite code
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
      final inviteCode = userData['inviteCode'] as String?;
      final expiry = userData['inviteCodeExpiry'] as int?;

      if (inviteCode == null) {
        return null;
      }

      // Check if expired
      if (expiry != null && DateTime.now().millisecondsSinceEpoch > expiry) {
        // Clear expired code
        await cancelInviteCode(userProvider);
        return null;
      }

      return inviteCode;
    } catch (e) {
      debugPrint('❌ Error getting active invite code: $e');
      return null;
    }
  }

  /// Update partnership settings
  Future<void> updatePartnershipSettings(
    String partnershipId,
    Map<String, dynamic> settings,
  ) async {
    try {
      debugPrint('⚙️ Updating partnership settings...');

      await _dbRef.child('partnerships').child(partnershipId).update({
        ...settings,
        'updatedAt': ServerValue.timestamp,
      });

      debugPrint('✅ Partnership settings updated');
    } catch (e) {
      debugPrint('❌ Error updating partnership settings: $e');
      rethrow;
    }
  }
}
