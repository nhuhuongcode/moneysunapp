import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
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
  bool _isInitialized = false;

  // Getters
  User? get currentUser => _auth.currentUser;
  String? get partnershipId => _partnershipId;
  String? get partnerUid => _partnerUid;
  String? get partnerDisplayName => _partnerDisplayName;
  String? get partnerPhotoURL => _partnerPhotoURL;
  bool get hasPartner => _partnershipId != null && _partnerUid != null;
  bool get isInitialized => _isInitialized;

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
        // Validate saved partnership data
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

  // THÊM MỚI: Validate partnership data when app starts
  Future<void> _validatePartnershipData() async {
    if (_partnershipId == null || currentUser == null) return;

    try {
      final partnershipSnapshot = await _dbRef
          .child('partnerships')
          .child(_partnershipId!)
          .get();

      if (!partnershipSnapshot.exists) {
        // Partnership không tồn tại, clear data
        print('Partnership không tồn tại, clearing data...');
        await _clearPartnershipData();
        return;
      }

      final membersData = partnershipSnapshot.child('members').value;
      if (membersData == null) {
        await _clearPartnershipData();
        return;
      }

      final members = membersData as Map<dynamic, dynamic>;
      if (!members.containsKey(currentUser!.uid)) {
        // User không còn trong partnership
        await _clearPartnershipData();
        return;
      }

      // Cập nhật partner info
      final validPartnerUid = members.keys.firstWhere(
        (key) => key != currentUser!.uid,
        orElse: () => null,
      );

      if (validPartnerUid != _partnerUid) {
        _partnerUid = validPartnerUid;
        if (_partnerUid != null) {
          _listenToPartnerProfile(_partnerUid!);
        }
        await _savePartnershipState();
      }

      _partnershipData = partnershipSnapshot;
      notifyListeners();
    } catch (e) {
      print('Error validating partnership data: $e');
      await _clearPartnershipData();
    }
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
            await _savePartnershipState(); // THÊM: Save state
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

  void _listenToUserProfile(String uid) {
    _userProfileSubscription?.cancel();

    final userRef = _dbRef.child('users').child(uid);

    _userProfileSubscription = userRef.child('partnershipId').onValue.listen((
      event,
    ) async {
      final pId = event.snapshot.value as String?;
      if (pId != _partnershipId) {
        _partnershipId = pId;
        if (pId != null) {
          _fetchPartnershipDetails(pId);
        } else {
          await _clearPartnershipData();
          notifyListeners();
        }
        await _savePartnershipState(); // THÊM: Save state
      }
    });
  }

  void _listenToPartnerProfile(String partnerUid) {
    _partnerProfileSubscription?.cancel();

    final partnerRef = _dbRef.child('users').child(partnerUid);
    _partnerProfileSubscription = partnerRef.onValue.listen((event) async {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        _partnerDisplayName = data['displayName'];
        _partnerPhotoURL = data['photoURL'];
        await _savePartnershipState(); // THÊM: Save state
        notifyListeners();
      }
    });
  }

  Future<void> _clearPartnershipData() async {
    _partnerProfileSubscription?.cancel();
    _partnerUid = null;
    _partnerDisplayName = null;
    _partnerPhotoURL = null;
    _partnershipData = null;
    await _savePartnershipState(); // THÊM: Save state
  }

  Future<void> _clearAllData() async {
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel();
    _partnershipId = null;
    await _clearPartnershipData();
    await _savePartnershipState(); // THÊM: Save state
    notifyListeners();
  }

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
      await _clearPartnershipData();
      _partnershipId = null;
      await _savePartnershipState(); // THÊM: Save state
      notifyListeners();
    } catch (e) {
      print("Lỗi khi ngắt kết nối partnership: $e");
      rethrow;
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

  @override
  void dispose() {
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel();
    super.dispose();
  }
}
