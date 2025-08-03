import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class UserProvider with ChangeNotifier {
  final _dbRef = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;

  String? _partnershipId;
  String? _partnerUid;
  String? _partnerDisplayName; // THÊM MỚI
  String? _partnerPhotoURL; // THÊM MỚI
  DataSnapshot? _partnershipData;
  StreamSubscription? _userProfileSubscription;
  StreamSubscription? _partnerProfileSubscription; // THÊM MỚI

  // Getters
  User? get currentUser => _auth.currentUser;
  String? get partnershipId => _partnershipId;
  String? get partnerUid => _partnerUid;
  String? get partnerDisplayName => _partnerDisplayName; // THÊM MỚI
  String? get partnerPhotoURL => _partnerPhotoURL; // THÊM MỚI

  // Kiểm tra có partner không
  bool get hasPartner =>
      _partnershipId != null && _partnerUid != null; // THÊM MỚI

  DateTime? get partnershipCreationDate {
    if (_partnershipData == null) return null;
    final timestamp = _partnershipData!.child('createdAt').value as int?;
    if (timestamp == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  UserProvider() {
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        _listenToUserProfile(user.uid);
      } else {
        _clearData();
      }
    });
  }

  void _fetchPartnershipDetails(String pId) async {
    try {
      final partnershipRef = _dbRef.child('partnerships').child(pId);
      _partnershipData = await partnershipRef.get();

      if (_partnershipData != null && _partnershipData!.exists) {
        final membersData = _partnershipData!.child('members').value;
        if (membersData != null) {
          final members = membersData as Map<dynamic, dynamic>;
          final newPartnerUid = members.keys.firstWhere(
            (key) => key != currentUser!.uid,
            orElse: () => null,
          );

          if (newPartnerUid != _partnerUid) {
            _partnerUid = newPartnerUid;
            if (_partnerUid != null) {
              _listenToPartnerProfile(_partnerUid!);
            }
          }
        } else {
          _clearPartnerData();
        }
      } else {
        // Partnership không tồn tại, xóa reference
        _clearInvalidPartnership();
      }
      notifyListeners();
    } catch (e) {
      print("Lỗi khi fetch partnership details: $e");
      _clearPartnerData();
      notifyListeners();
    }
  }

  void _listenToUserProfile(String uid) {
    _userProfileSubscription?.cancel();

    final userRef = _dbRef.child('users').child(uid);

    _userProfileSubscription = userRef.child('partnershipId').onValue.listen((
      event,
    ) {
      final pId = event.snapshot.value as String?;
      if (pId != _partnershipId) {
        _partnershipId = pId;
        if (pId != null) {
          _fetchPartnershipDetails(pId);
        } else {
          _clearPartnerData(); // THAY ĐỔI
          notifyListeners();
        }
      }
    });
  }

  // THÊM MỚI - Lắng nghe thông tin partner
  void _listenToPartnerProfile(String partnerUid) {
    _partnerProfileSubscription?.cancel();

    final partnerRef = _dbRef.child('users').child(partnerUid);
    _partnerProfileSubscription = partnerRef.onValue.listen((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        _partnerDisplayName = data['displayName'];
        _partnerPhotoURL = data['photoURL'];
        notifyListeners();
      }
    });
  }

  // THÊM MỚI - Xóa dữ liệu partner
  void _clearPartnerData() {
    _partnerProfileSubscription?.cancel();
    _partnerUid = null;
    _partnerDisplayName = null;
    _partnerPhotoURL = null;
    _partnershipData = null;
  }

  void _clearData() {
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel(); // THÊM MỚI
    _partnershipId = null;
    _clearPartnerData();
    notifyListeners();
  }

  // THÊM MỚI - Method để ngắt kết nối partnership
  Future<void> disconnectPartnership() async {
    if (_partnershipId == null || currentUser == null) return;

    try {
      // Xóa partnershipId từ cả hai user
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

      // Xóa partnership record
      await _dbRef.child('partnerships').child(_partnershipId!).remove();

      // Clear local data
      _clearPartnerData();
      _partnershipId = null;
      notifyListeners();
    } catch (e) {
      print("Lỗi khi ngắt kết nối partnership: $e");
      rethrow;
    }
  }

  // THÊM MỚI - Lấy thông tin partner đầy đủ
  Map<String, dynamic>? get partnerInfo {
    if (!hasPartner) return null;

    return {
      'uid': _partnerUid,
      'displayName': _partnerDisplayName ?? 'Đối tác',
      'photoURL': _partnerPhotoURL,
    };
  }

  // THÊM VÀO UserProvider class

  // Refresh partnership data manually nếu cần
  Future<void> refreshPartnershipData() async {
    if (_partnershipId != null) {
      _fetchPartnershipDetails(_partnershipId!);
    }
  }

  // Kiểm tra xem user có thể tạo partnership không
  bool get canCreatePartnership => _partnershipId == null;

  // Lấy invite code của user hiện tại
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

  // Update user profile trong database
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

  // THAY ĐỔI method _fetchPartnershipDetails

  // THÊM MỚI - Xóa partnership không hợp lệ
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
    _clearPartnerData();
  }

  @override
  void dispose() {
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel(); // THÊM MỚI
    super.dispose();
  }
}
