import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:moneysun/data/models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider with ChangeNotifier {
  final _dbRef = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;

  String? _partnershipId;
  String? _partnerUid;
  String? _partnerDisplayName;
  String? _partnerPhotoURL;
  DataSnapshot? _partnershipData;
  StreamSubscription? _userProfileSubscription;
  StreamSubscription? _partnerProfileSubscription;
  StreamSubscription? _notificationSubscription;
  bool _isInitialized = false;

  // Add missing fields
  AppUser? _currentUser;
  DateTime? _partnershipCreationDate;

  // Getters
  User? get currentUser => _auth.currentUser;
  String? get partnershipId => _partnershipId;
  String? get partnerUid => _partnerUid;
  String? get partnerDisplayName => _partnerDisplayName;
  String? get partnerPhotoURL => _partnerPhotoURL;
  bool get hasPartner => _partnershipId != null && _partnerUid != null;
  bool get isInitialized => _isInitialized;
  AppUser? get appUser => _currentUser;
  DateTime? get partnershipCreationDate {
    if (_partnershipData == null) return null;
    final timestamp = _partnershipData!.child('createdAt').value as int?;
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  UserProvider() {
    _initializeProvider();
  }

  // THÊM MỚI: Khởi tạo provider với persistence
  Future<void> _initializeProvider() async {
    await _loadPartnershipState();

    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        _listenToUserProfile(user.uid);
        _listenToNotifications(user.uid);
        if (_partnershipId != null) {
          await _validatePartnershipData();
        }
      } else {
        await _clearAllData();
      }
      _isInitialized = true;
      notifyListeners();
    });
  }

  Future<void> _validatePartnershipData() async {
    if (_partnershipId == null || currentUser == null) return;

    try {
      final partnershipSnapshot = await _dbRef
          .child('partnerships')
          .child(_partnershipId!)
          .get();

      if (!partnershipSnapshot.exists) {
        print('Partnership không tồn tại, clearing data...');
        await _clearPartnershipData();
        return;
      }

      final partnershipData =
          partnershipSnapshot.value as Map<dynamic, dynamic>;
      final membersData = partnershipData['members'] as Map<dynamic, dynamic>?;

      if (membersData == null || !membersData.containsKey(currentUser!.uid)) {
        print('User không còn trong partnership, clearing data...');
        await _clearPartnershipData();
        return;
      }

      // Update partner info from partnership data
      final memberNames =
          partnershipData['memberNames'] as Map<dynamic, dynamic>? ?? {};
      final validPartnerUid = membersData.keys.firstWhere(
        (key) => key != currentUser!.uid,
        orElse: () => null,
      );

      if (validPartnerUid != null) {
        final bool shouldUpdate =
            _partnerUid != validPartnerUid ||
            _partnerDisplayName != memberNames[validPartnerUid];

        if (shouldUpdate) {
          _partnerUid = validPartnerUid;
          _partnerDisplayName = memberNames[validPartnerUid];

          // Listen to partner profile updates
          _listenToPartnerProfile(_partnerUid!);
          await _savePartnershipState();
        }
      }

      _partnershipData = partnershipSnapshot;
      notifyListeners();
    } catch (e) {
      print('Error validating partnership data: $e');
      await _clearPartnershipData();
    }
  }

  void _listenToNotifications(String uid) {
    _notificationSubscription?.cancel();

    _notificationSubscription = _dbRef
        .child('user_notifications')
        .child(uid)
        .orderByChild('type')
        .equalTo('partnership')
        .onChildAdded
        .listen((event) {
          if (event.snapshot.exists) {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            final title = data['title'] ?? '';
            final body = data['body'] ?? '';

            print('Partnership notification received: $title - $body');

            // Refresh partnership data when notification received
            if (_partnershipId != null) {
              _fetchPartnershipDetails(_partnershipId!);
            }

            // Mark notification as read after processing
            event.snapshot.ref.update({'isRead': true});
          }
        });
  }

  void _fetchPartnershipDetails(String pId) async {
    try {
      final partnershipRef = _dbRef.child('partnerships').child(pId);
      _partnershipData = await partnershipRef.get();

      if (_partnershipData != null && _partnershipData!.exists) {
        final partnershipData =
            _partnershipData!.value as Map<dynamic, dynamic>;
        final membersData =
            partnershipData['members'] as Map<dynamic, dynamic>?;
        final memberNames =
            partnershipData['memberNames'] as Map<dynamic, dynamic>? ?? {};

        if (membersData != null && membersData.containsKey(currentUser!.uid)) {
          final newPartnerUid = membersData.keys.firstWhere(
            (key) => key != currentUser!.uid,
            orElse: () => null,
          );

          if (newPartnerUid != _partnerUid) {
            _partnerUid = newPartnerUid;
            _partnerDisplayName = memberNames[newPartnerUid];

            if (_partnerUid != null) {
              _listenToPartnerProfile(_partnerUid!);
            }
            await _savePartnershipState();
          }
        } else {
          await _clearPartnershipData();
        }
      } else {
        await _clearInvalidPartnership();
      }
      notifyListeners();
    } catch (e) {
      print("Lỗi khi fetch partnership details: $e");
      await _clearPartnershipData();
      notifyListeners();
    }
  }

  // THÊM MỚI: Load partnership state từ SharedPreferences
  Future<void> _loadPartnershipState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _partnershipId = prefs.getString('partnershipId');
      _partnerUid = prefs.getString('partnerUid');
      _partnerDisplayName = prefs.getString('partnerDisplayName');
      _partnerPhotoURL = prefs.getString('partnerPhotoURL');

      print('Loaded partnership state: $_partnershipId, $_partnerUid');
    } catch (e) {
      print('Error loading partnership state: $e');
    }
  }

  // THÊM MỚI: Save partnership state vào SharedPreferences
  Future<void> _savePartnershipState() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (_partnershipId != null) {
        await prefs.setString('partnershipId', _partnershipId!);
      } else {
        await prefs.remove('partnershipId');
      }

      if (_partnerUid != null) {
        await prefs.setString('partnerUid', _partnerUid!);
      } else {
        await prefs.remove('partnerUid');
      }

      if (_partnerDisplayName != null) {
        await prefs.setString('partnerDisplayName', _partnerDisplayName!);
      } else {
        await prefs.remove('partnerDisplayName');
      }

      if (_partnerPhotoURL != null) {
        await prefs.setString('partnerPhotoURL', _partnerPhotoURL!);
      } else {
        await prefs.remove('partnerPhotoURL');
      }

      print('Saved partnership state: $_partnershipId, $_partnerUid');
    } catch (e) {
      print('Error saving partnership state: $e');
    }
  }

  void _listenToUserProfile(String uid) {
    _userProfileSubscription?.cancel();

    final userRef = _dbRef.child('users').child(uid);

    _userProfileSubscription = userRef.onValue.listen((event) async {
      if (event.snapshot.exists) {
        final userData = event.snapshot.value as Map<dynamic, dynamic>;
        final newPartnershipId = userData['partnershipId'] as String?;

        // FIX: Only update if partnershipId actually changed
        if (newPartnershipId != _partnershipId) {
          _partnershipId = newPartnershipId;

          if (_partnershipId != null) {
            _fetchPartnershipDetails(_partnershipId!);
          } else {
            await _clearPartnershipData();
            notifyListeners();
          }
          await _savePartnershipState();
        }
      }
    });
  }

  void _listenToPartnerProfile(String partnerUid) {
    _partnerProfileSubscription?.cancel();

    final partnerRef = _dbRef.child('users').child(partnerUid);
    _partnerProfileSubscription = partnerRef.onValue.listen((event) async {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final newDisplayName = data['displayName'] as String?;
        final newPhotoURL = data['photoURL'] as String?;

        // FIX: Only update if data actually changed
        if (newDisplayName != _partnerDisplayName ||
            newPhotoURL != _partnerPhotoURL) {
          _partnerDisplayName = newDisplayName;
          _partnerPhotoURL = newPhotoURL;
          await _savePartnershipState();
          notifyListeners();
        }
      }
    });
  }

  Future<void> _clearPartnershipData() async {
    _partnerProfileSubscription?.cancel();
    _partnerUid = null;
    _partnerDisplayName = null;
    _partnerPhotoURL = null;
    _partnershipData = null;
    await _savePartnershipState();
  }

  Future<void> _clearAllData() async {
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel();
    _notificationSubscription?.cancel();
    _partnershipId = null;
    await _clearPartnershipData();
    await _savePartnershipState();
    notifyListeners();
  }

  // FIX: Enhanced disconnect with proper cleanup
  Future<void> disconnectPartnership() async {
    if (_partnershipId == null || currentUser == null) return;

    try {
      // Remove partnership notifications
      if (_partnerUid != null) {
        await _dbRef.child('users').child(_partnerUid!).update({
          'partnershipId': null,
          'partnerUid': null,
          'partnerDisplayName': null,
          'partnershipCreatedAt': null,
        });
      }

      await _dbRef.child('users').child(currentUser!.uid).update({
        'partnershipId': null,
        'partnerUid': null,
        'partnerDisplayName': null,
        'partnershipCreatedAt': null,
      });

      // Delete partnership record
      await _dbRef.child('partnerships').child(_partnershipId!).remove();

      // Send disconnect notifications
      if (_partnerUid != null) {
        await _sendDisconnectNotification(_partnerUid!);
      }

      // Clear local data
      await _clearPartnershipData();
      _partnershipId = null;
      await _savePartnershipState();
      notifyListeners();
    } catch (e) {
      print("Lỗi khi ngắt kết nối partnership: $e");
      rethrow;
    }
  }

  // FIX: Send disconnect notification
  Future<void> _sendDisconnectNotification(String partnerUid) async {
    try {
      await _dbRef.child('user_notifications').child(partnerUid).push().set({
        'title': 'Kết nối đã bị ngắt',
        'body':
            '${currentUser?.displayName ?? "Đối tác"} đã ngắt kết nối với bạn',
        'timestamp': ServerValue.timestamp,
        'type': 'partnership',
        'isRead': false,
      });
    } catch (e) {
      print('Error sending disconnect notification: $e');
    }
  }

  Map<String, dynamic>? get partnerInfo {
    if (!hasPartner) return null;

    return {
      'uid': _partnerUid,
      'displayName': _partnerDisplayName ?? 'Đối tác',
      'photoURL': _partnerPhotoURL,
    };
  }

  Future<void> refreshPartnershipData() async {
    if (_partnershipId != null) {
      _fetchPartnershipDetails(_partnershipId!);
    }
  }

  bool get canCreatePartnership => _partnershipId == null;

  Future<String?> getCurrentUserInviteCode() async {
    if (currentUser == null) return null;

    try {
      final snapshot = await _dbRef
          .child('users')
          .child(currentUser!.uid)
          .child('inviteCode')
          .get();

      return snapshot.value as String?;
    } catch (e) {
      print("Lỗi khi lấy invite code: $e");
      return null;
    }
  }

  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
  }) async {
    if (currentUser == null) return;

    try {
      final updates = <String, dynamic>{};
      if (displayName != null) updates['displayName'] = displayName;
      if (photoURL != null) updates['photoURL'] = photoURL;

      if (updates.isNotEmpty) {
        await _dbRef.child('users').child(currentUser!.uid).update(updates);
      }
    } catch (e) {
      print("Lỗi khi cập nhật profile: $e");
      rethrow;
    }
  }

  Future<void> _clearInvalidPartnership() async {
    if (currentUser != null) {
      try {
        await _dbRef.child('users').child(currentUser!.uid).update({
          'partnershipId': null,
          'partnerUid': null,
          'partnerDisplayName': null,
          'partnershipCreatedAt': null,
        });
      } catch (e) {
        print("Lỗi khi xóa partnership không hợp lệ: $e");
      }
    }
    await _clearPartnershipData();
  }

  Future<Map<String, dynamic>?> fetchUser(String uid) async {
    try {
      final snapshot = await _dbRef.child('users').child(uid).get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      print('Error fetching user: $e');
      return null;
    }
  }

  Future<void> refreshUser() async {
    if (_auth.currentUser == null) return;

    try {
      final snapshot = await _dbRef
          .child('users')
          .child(_auth.currentUser!.uid)
          .get();

      if (snapshot.exists) {
        final userData = snapshot.value as Map<dynamic, dynamic>;
        _currentUser = AppUser.fromMap(userData, _auth.currentUser!.uid);
        _partnershipId = userData['partnershipId'];
        _partnerUid = userData['partnerUid'];
        _partnershipCreationDate = userData['partnershipCreatedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                userData['partnershipCreatedAt'],
              )
            : null;

        notifyListeners();
      }
    } catch (e) {
      print('Error refreshing user data: $e');
    }
  }

  // Add a method to check partnership status
  bool get hasActivePartnership =>
      _partnershipId != null && _partnerUid != null;

  @override
  void dispose() {
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }
}
