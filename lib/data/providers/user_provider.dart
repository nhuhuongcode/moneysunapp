import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:moneysun/data/models/user_model.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider with ChangeNotifier {
  final _dbRef = FirebaseDatabase.instance.ref();
  final _auth = FirebaseAuth.instance;

  // Partnership data
  String? _partnershipId;
  String? _partnerUid;
  String? _partnerDisplayName;
  String? _partnerPhotoURL;
  DataSnapshot? _partnershipData;

  // Stream subscriptions
  StreamSubscription? _userProfileSubscription;
  StreamSubscription? _partnerProfileSubscription;
  StreamSubscription? _partnershipSubscription;
  StreamSubscription? _notificationSubscription;

  StreamSubscription? _refreshTriggerSubscription;
  StreamSubscription? _partnershipUpdateSubscription;

  // State management
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;
  bool _mounted = false;

  // Current user data
  AppUser? _currentUser;
  DateTime? _partnershipCreationDate;

  // ============ GETTERS ============
  User? get currentUser => _auth.currentUser;
  String? get partnershipId => _partnershipId;
  String? get partnerUid => _partnerUid;
  String? get partnerDisplayName => _partnerDisplayName;
  String? get partnerPhotoURL => _partnerPhotoURL;
  bool get hasPartner => _partnershipId != null && _partnerUid != null;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  AppUser? get appUser => _currentUser;

  DateTime? get partnershipCreationDate {
    if (_partnershipData == null) return _partnershipCreationDate;
    final timestamp = _partnershipData!.child('createdAt').value as int?;
    if (timestamp == null) return _partnershipCreationDate;
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }

  // ============ INITIALIZATION ============

  UserProvider() {
    _initializeProvider();
  }

  Future<void> _initializeProvider() async {
    _setLoading(true);

    try {
      // Load cached partnership state
      await _loadPartnershipState();

      // Listen to auth state changes
      _auth.authStateChanges().listen((user) async {
        if (user != null) {
          await _handleUserSignIn(user);
        } else {
          await _handleUserSignOut();
        }
      });
    } catch (e) {
      _setError('Lỗi khởi tạo: $e');
    } finally {
      _isInitialized = true;
      _setLoading(false);
    }
  }

  Future<void> _handleUserSignIn(User user) async {
    try {
      // Setup listeners for user profile and notifications
      _listenToUserProfile(user.uid);
      _listenToNotifications(user.uid);

      // ✅ NEW: Listen to refresh triggers
      _listenToRefreshTriggers(user.uid);

      // ✅ NEW: Listen to partnership updates
      _listenToPartnershipUpdates();

      // Load user data
      await refreshUser();

      // Validate partnership if exists
      if (_partnershipId != null) {
        await _validateAndRefreshPartnership();
      }

      _clearError();
    } catch (e) {
      _setError('Lỗi khi đăng nhập: $e');
    }
  }

  /// ✅ NEW: Listen to partnership updates globally
  void _listenToPartnershipUpdates() {
    _partnershipUpdateSubscription?.cancel();

    _partnershipUpdateSubscription = _dbRef
        .child('partnership_updates')
        .orderByChild('timestamp')
        .limitToLast(10)
        .onChildAdded
        .listen((event) async {
          if (!event.snapshot.exists) return;

          try {
            final updateData = event.snapshot.value as Map<dynamic, dynamic>;
            final affectedUsers = List<String>.from(
              updateData['affectedUsers'] ?? [],
            );
            final updateType = updateData['type'] as String?;

            // Check if current user is affected
            if (currentUser != null &&
                affectedUsers.contains(currentUser!.uid)) {
              debugPrint('🔔 Partnership update received: $updateType');

              // Refresh user data
              await refreshUser();

              if (_partnershipId != null) {
                await _validateAndRefreshPartnership();
              }

              debugPrint('✅ Partnership data refreshed due to update');
            }

            // Clean up old updates (older than 5 minutes)
            final timestamp = updateData['timestamp'] as int?;
            if (timestamp != null) {
              final updateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
              if (DateTime.now().difference(updateTime).inMinutes > 5) {
                await event.snapshot.ref.remove();
              }
            }
          } catch (e) {
            debugPrint('❌ Error processing partnership update: $e');
          }
        });

    debugPrint('👂 Partnership update listener setup');
  }

  Future<void> _handleUserSignOut() async {
    await _clearAllData();
    _clearError();
  }

  // ✅ NEW: Notify all providers about partnership change
  Future<void> _notifyProvidersAboutPartnership() async {
    debugPrint('📢 Notifying all providers about partnership change');

    // This will trigger DataService to refresh
    // Providers will automatically reload via their listeners
    final dataService = DataService();
    if (dataService.isInitialized && dataService.isOnline) {
      await dataService.forceSyncNow();
    }
  }

  Future<void> _handlePartnershipChange(
    String? newPartnershipId,
    Map<dynamic, dynamic> userData,
  ) async {
    final oldPartnershipId = _partnershipId;
    _partnershipId = newPartnershipId;

    if (newPartnershipId != null) {
      // New partnership created - immediately update all partner info
      _partnerUid = userData['partnerUid'] as String?;
      _partnerDisplayName = userData['partnerDisplayName'] as String?;
      _partnerPhotoURL = userData['partnerPhotoURL'] as String?;
      _partnershipCreationDate = userData['partnershipCreatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              userData['partnershipCreatedAt'],
            )
          : null;

      // ✅ IMMEDIATE: Setup listeners for new partner
      if (_partnerUid != null) {
        _listenToPartnerProfile(_partnerUid!);
      }

      if (_partnershipId != null) {
        _listenToPartnership(_partnershipId!);
      }

      // ✅ FORCE NOTIFICATION: Ensure UI updates immediately
      notifyListeners();

      debugPrint('✅ New partnership setup completed: $newPartnershipId');
      debugPrint('   Partner: $_partnerDisplayName ($_partnerUid)');
    } else {
      // Partnership removed
      await _clearPartnershipData();
      debugPrint('💔 Partnership removed');
    }
  }

  Future<void> _setupNewPartnership(Map<dynamic, dynamic> userData) async {
    try {
      _partnerUid = userData['partnerUid'] as String?;
      _partnerDisplayName = userData['partnerDisplayName'] as String?;
      _partnershipCreationDate = userData['partnershipCreatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              userData['partnershipCreatedAt'],
            )
          : null;

      // Listen to partner profile and partnership data
      if (_partnerUid != null) {
        _listenToPartnerProfile(_partnerUid!);
      }

      if (_partnershipId != null) {
        _listenToPartnership(_partnershipId!);
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi setup partnership: $e');
    }
  }

  Future<void> _updatePartnerInfo(Map<dynamic, dynamic> userData) async {
    final newPartnerUid = userData['partnerUid'] as String?;
    final newPartnerDisplayName = userData['partnerDisplayName'] as String?;

    bool hasChanges = false;

    if (_partnerUid != newPartnerUid) {
      _partnerUid = newPartnerUid;
      hasChanges = true;

      // Update partner profile listener
      if (_partnerUid != null) {
        _listenToPartnerProfile(_partnerUid!);
      }
    }

    if (_partnerDisplayName != newPartnerDisplayName) {
      _partnerDisplayName = newPartnerDisplayName;
      hasChanges = true;
    }

    if (hasChanges) {
      await _savePartnershipState();
    }
  }

  void _listenToPartnerProfile(String partnerUid) {
    _partnerProfileSubscription?.cancel();

    final partnerRef = _dbRef.child('users').child(partnerUid);
    _partnerProfileSubscription = partnerRef.onValue.listen((event) async {
      if (!event.snapshot.exists) {
        // Partner account deleted or doesn't exist
        await _handlePartnerAccountIssue();
        return;
      }

      try {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        final newDisplayName = data['displayName'] as String?;
        final newPhotoURL = data['photoURL'] as String?;
        final partnerPartnershipId = data['partnershipId'] as String?;

        // Check if partner still has the same partnership
        if (partnerPartnershipId != _partnershipId) {
          await _handlePartnershipMismatch();
          return;
        }

        // Update partner info if changed
        bool hasChanges = false;

        if (newDisplayName != _partnerDisplayName) {
          _partnerDisplayName = newDisplayName;
          hasChanges = true;
        }

        if (newPhotoURL != _partnerPhotoURL) {
          _partnerPhotoURL = newPhotoURL;
          hasChanges = true;
        }

        if (hasChanges) {
          await _savePartnershipState();
          notifyListeners();
        }
      } catch (e) {
        debugPrint('❌ Lỗi khi cập nhật thông tin partner: $e');
      }
    });
  }

  void _listenToPartnership(String partnershipId) {
    _partnershipSubscription?.cancel();

    _partnershipSubscription = _dbRef
        .child('partnerships')
        .child(partnershipId)
        .onValue
        .listen((event) async {
          if (!event.snapshot.exists) {
            // Partnership deleted
            await _handlePartnershipDeleted();
            return;
          }

          try {
            _partnershipData = event.snapshot;
            final partnershipData =
                event.snapshot.value as Map<dynamic, dynamic>;

            // Check if partnership is still active
            final isActive = partnershipData['isActive'] ?? true;
            if (!isActive) {
              await _handlePartnershipDeactivated();
              return;
            }

            // Check if current user is still in the partnership
            final members =
                partnershipData['members'] as Map<dynamic, dynamic>?;
            if (members == null || !members.containsKey(currentUser?.uid)) {
              await _handleUserRemovedFromPartnership();
              return;
            }

            notifyListeners();
          } catch (e) {
            debugPrint('❌ Lỗi khi cập nhật partnership: $e');
          }
        });
  }

  // ============ NOTIFICATION HANDLING ============

  void _listenToNotifications(String uid) {
    _notificationSubscription?.cancel();

    _notificationSubscription = _dbRef
        .child('user_notifications')
        .child(uid)
        .orderByChild('timestamp')
        .limitToLast(5) // Only listen to recent notifications
        .onChildAdded
        .listen((event) {
          if (!event.snapshot.exists) return;

          try {
            final data = event.snapshot.value as Map<dynamic, dynamic>;
            final type = data['type'] as String?;
            final isRead = data['isRead'] as bool? ?? false;

            // Only process unread partnership-related notifications
            if (!isRead && type != null && type.startsWith('partnership')) {
              _handlePartnershipNotification(data, event.snapshot.ref);
            }
          } catch (e) {
            debugPrint('❌ Lỗi khi xử lý notification: $e');
          }
        });
  }

  void _handlePartnershipNotification(
    Map<dynamic, dynamic> data,
    DatabaseReference ref,
  ) {
    final type = data['type'] as String;

    switch (type) {
      case 'partnership_accepted':
      case 'partnership_connected':
        // Refresh partnership data
        refreshPartnershipData();
        break;
      case 'partnership_disconnected':
        // Partner disconnected - clear local data
        _clearPartnershipData();
        break;
    }

    // Mark as read
    ref.update({'isRead': true}).catchError((e) {
      debugPrint('❌ Lỗi khi đánh dấu notification đã đọc: $e');
    });
  }

  // ============ PARTNERSHIP ISSUE HANDLERS ============

  Future<void> _handlePartnerAccountIssue() async {
    debugPrint('⚠️ Partner account issue detected');
    await _clearPartnershipData();
    _setError('Tài khoản đối tác không tồn tại');
  }

  Future<void> _handlePartnershipMismatch() async {
    debugPrint('⚠️ Partnership mismatch detected');
    await _clearPartnershipData();
    _setError('Kết nối partnership không đồng bộ');
  }

  Future<void> _handlePartnershipDeleted() async {
    debugPrint('⚠️ Partnership deleted');
    await _clearPartnershipData();
    notifyListeners();
  }

  Future<void> _handlePartnershipDeactivated() async {
    debugPrint('⚠️ Partnership deactivated');
    await _clearPartnershipData();
    notifyListeners();
  }

  Future<void> _handleUserRemovedFromPartnership() async {
    debugPrint('⚠️ User removed from partnership');
    await _clearPartnershipData();
    notifyListeners();
  }

  // ============ VALIDATION AND REFRESH ============

  Future<void> _validateAndRefreshPartnership() async {
    if (_partnershipId == null) return;

    try {
      final partnershipSnapshot = await _dbRef
          .child('partnerships')
          .child(_partnershipId!)
          .get();

      if (!partnershipSnapshot.exists) {
        debugPrint('Partnership không tồn tại, clearing data...');
        await _clearPartnershipData();
        return;
      }

      final partnershipData =
          partnershipSnapshot.value as Map<dynamic, dynamic>;
      final isActive = partnershipData['isActive'] ?? true;

      if (!isActive) {
        debugPrint('Partnership không hoạt động, clearing data...');
        await _clearPartnershipData();
        return;
      }

      final membersData = partnershipData['members'] as Map<dynamic, dynamic>?;
      if (membersData == null || !membersData.containsKey(currentUser!.uid)) {
        debugPrint('User không còn trong partnership, clearing data...');
        await _clearPartnershipData();
        return;
      }

      // Update partnership data
      _partnershipData = partnershipSnapshot;

      // Update partner info from partnership
      final memberNames =
          partnershipData['memberNames'] as Map<dynamic, dynamic>? ?? {};
      final validPartnerUid = membersData.keys.firstWhere(
        (key) => key != currentUser!.uid,
        orElse: () => null,
      );

      if (validPartnerUid != null) {
        _partnerUid = validPartnerUid;
        _partnerDisplayName = memberNames[validPartnerUid]?.toString();
        _listenToPartnerProfile(_partnerUid!);
      }

      await _savePartnershipState();
      notifyListeners();
    } catch (e) {
      debugPrint('Error validating partnership: $e');
      await _clearPartnershipData();
    }
  }

  // ============ PUBLIC METHODS ============

  Future<void> refreshUser() async {
    if (_auth.currentUser == null) return;

    _setLoading(true);

    try {
      final snapshot = await _dbRef
          .child('users')
          .child(_auth.currentUser!.uid)
          .get();

      if (snapshot.exists) {
        final userData = snapshot.value as Map<dynamic, dynamic>;
        _currentUser = AppUser.fromMap(userData, _auth.currentUser!.uid);

        // Update partnership info
        _partnershipId = userData['partnershipId'] as String?;
        _partnerUid = userData['partnerUid'] as String?;
        _partnerDisplayName = userData['partnerDisplayName'] as String?;
        _partnershipCreationDate = userData['partnershipCreatedAt'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                userData['partnershipCreatedAt'],
              )
            : null;

        await _savePartnershipState();
        _clearError();
      }
    } catch (e) {
      _setError('Lỗi khi refresh user: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> refreshPartnershipData() async {
    if (_partnershipId != null) {
      await _validateAndRefreshPartnership();
    } else {
      await refreshUser();
    }
  }

  Future<void> disconnectPartnership() async {
    if (_partnershipId == null || currentUser == null) return;

    _setLoading(true);

    try {
      // This method should typically be called through PartnershipService
      // but we can provide basic cleanup here
      await _clearPartnershipData();
      _clearError();
    } catch (e) {
      _setError('Lỗi khi ngắt kết nối: $e');
    } finally {
      _setLoading(false);
    }
  }

  // ============ UTILITY METHODS ============

  Map<String, dynamic>? get partnerInfo {
    if (!hasPartner) return null;

    return {
      'uid': _partnerUid,
      'displayName': _partnerDisplayName ?? 'Đối tác',
      'photoURL': _partnerPhotoURL,
      'partnershipCreatedAt': _partnershipCreationDate?.toIso8601String(),
    };
  }

  bool get canCreatePartnership => _partnershipId == null;
  bool get hasActivePartnership =>
      _partnershipId != null && _partnerUid != null;

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
      debugPrint("Lỗi khi lấy invite code: $e");
      return null;
    }
  }

  Future<void> updateUserProfile({
    String? displayName,
    String? photoURL,
  }) async {
    if (currentUser == null) return;

    _setLoading(true);

    try {
      final updates = <String, dynamic>{};
      if (displayName != null) updates['displayName'] = displayName;
      if (photoURL != null) updates['photoURL'] = photoURL;

      if (updates.isNotEmpty) {
        updates['updatedAt'] = ServerValue.timestamp;
        await _dbRef.child('users').child(currentUser!.uid).update(updates);
        await refreshUser();
      }
    } catch (e) {
      _setError('Lỗi khi cập nhật profile: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<Map<String, dynamic>?> fetchUser(String uid) async {
    try {
      final snapshot = await _dbRef.child('users').child(uid).get();
      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      debugPrint('Error fetching user: $e');
      return null;
    }
  }

  // ============ PERSISTENCE METHODS ============

  Future<void> _loadPartnershipState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _partnershipId = prefs.getString('partnershipId');
      _partnerUid = prefs.getString('partnerUid');
      _partnerDisplayName = prefs.getString('partnerDisplayName');
      _partnerPhotoURL = prefs.getString('partnerPhotoURL');

      final partnershipTimestamp = prefs.getInt('partnershipCreatedAt');
      if (partnershipTimestamp != null) {
        _partnershipCreationDate = DateTime.fromMillisecondsSinceEpoch(
          partnershipTimestamp,
        );
      }

      debugPrint('Loaded partnership state: $_partnershipId, $_partnerUid');
    } catch (e) {
      debugPrint('Error loading partnership state: $e');
    }
  }

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

      if (_partnershipCreationDate != null) {
        await prefs.setInt(
          'partnershipCreatedAt',
          _partnershipCreationDate!.millisecondsSinceEpoch,
        );
      } else {
        await prefs.remove('partnershipCreatedAt');
      }

      debugPrint('Saved partnership state: $_partnershipId, $_partnerUid');
    } catch (e) {
      debugPrint('Error saving partnership state: $e');
    }
  }

  Future<void> _clearPartnershipData() async {
    _partnerProfileSubscription?.cancel();
    _partnershipSubscription?.cancel();

    _partnerUid = null;
    _partnerDisplayName = null;
    _partnerPhotoURL = null;
    _partnershipData = null;
    _partnershipId = null;
    _partnershipCreationDate = null;

    await _savePartnershipState();
  }

  Future<void> _clearAllData() async {
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel();
    _partnershipSubscription?.cancel();
    _notificationSubscription?.cancel();

    _currentUser = null;
    await _clearPartnershipData();

    _clearError();
    notifyListeners();
  }

  // ============ STATE MANAGEMENT HELPERS ============

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String? error) {
    if (_error != error) {
      _error = error;
      notifyListeners();
    }
  }

  void _clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  void _listenToRefreshTriggers(String uid) {
    _refreshTriggerSubscription?.cancel();

    debugPrint('👂 Setting up refresh trigger listener for: $uid');

    _refreshTriggerSubscription = _dbRef
        .child('user_refresh_triggers')
        .child(uid)
        .onChildAdded // ← Listen to NEW triggers
        .listen((event) async {
          if (!event.snapshot.exists) return;

          try {
            final triggerData = event.snapshot.value as Map<dynamic, dynamic>;
            final triggerType = triggerData['type'] as String?;
            final requireRefresh =
                triggerData['requireRefresh'] as bool? ?? false;
            final priority = triggerData['priority'] as String?;

            debugPrint(
              '🔔 Refresh trigger received: $triggerType (priority: $priority)',
            );

            if (requireRefresh) {
              // ✅ CRITICAL: Force multiple refreshes for high-priority triggers
              if (priority == 'high') {
                debugPrint('⚡ HIGH PRIORITY - Force refresh cycle starting...');

                // Refresh immediately
                await refreshUser();

                // Wait and refresh again (ensure data propagated)
                await Future.delayed(const Duration(milliseconds: 300));
                await refreshUser();

                // Final refresh after longer delay
                await Future.delayed(const Duration(milliseconds: 700));
                await refreshUser();

                debugPrint('✅ HIGH PRIORITY refresh cycle completed');
              } else {
                // Normal priority - single refresh
                await refreshUser();
              }

              // Re-validate partnership if exists
              if (_partnershipId != null) {
                await _validateAndRefreshPartnership();
              }

              // ✅ FORCE multiple UI updates
              notifyListeners();
              await Future.delayed(const Duration(milliseconds: 100));
              notifyListeners();
              await Future.delayed(const Duration(milliseconds: 300));
              notifyListeners();

              debugPrint('✅ User data refreshed due to trigger');
            }

            // Clean up the trigger after processing
            await event.snapshot.ref.remove();
          } catch (e) {
            debugPrint('❌ Error processing refresh trigger: $e');
          }
        });

    debugPrint('✅ Refresh trigger listener active');
  }

  // ✅ ENHANCED: _listenToUserProfile with better detection
  void _listenToUserProfile(String uid) {
    _userProfileSubscription?.cancel();

    final userRef = _dbRef.child('users').child(uid);

    debugPrint('👂 Setting up user profile listener for: $uid');

    _userProfileSubscription = userRef.onValue.listen((event) async {
      if (!event.snapshot.exists) return;

      try {
        final userData = event.snapshot.value as Map<dynamic, dynamic>;

        // ✅ DETECT: Partnership-related updates
        final newPartnershipId = userData['partnershipId'] as String?;
        final lastPartnerUpdate = userData['lastPartnerUpdate'];

        // Check if this is a recent partnership update
        final isRecentPartnershipUpdate =
            lastPartnerUpdate != null &&
            (DateTime.now().millisecondsSinceEpoch -
                    (lastPartnerUpdate as int)) <
                5000;

        if (isRecentPartnershipUpdate) {
          debugPrint('🔔 RECENT PARTNERSHIP UPDATE DETECTED (within 5s)');
        }

        // Update current user data
        _currentUser = AppUser.fromMap(userData, uid);

        // ✅ CRITICAL: Handle partnership changes
        if (newPartnershipId != _partnershipId) {
          debugPrint(
            '🔄 Partnership ID changed: $_partnershipId -> $newPartnershipId',
          );
          await _handlePartnershipChange(newPartnershipId, userData);

          // ✅ FORCE immediate UI update for partnership changes
          notifyListeners();

          if (isRecentPartnershipUpdate) {
            // Multiple notifications for recent updates
            await Future.delayed(const Duration(milliseconds: 100));
            notifyListeners();
            await Future.delayed(const Duration(milliseconds: 300));
            notifyListeners();

            debugPrint('🎯 Forced multiple UI updates for partnership change');
          }
        } else if (newPartnershipId != null) {
          // Update partner info if partnership exists but data changed
          await _updatePartnerInfo(userData);
        }

        await _savePartnershipState();
        notifyListeners();
      } catch (e) {
        _setError('Lỗi cập nhật profile: $e');
      }
    });

    debugPrint('✅ User profile listener active');
  }

  @override
  void dispose() {
    _mounted = false;
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel();
    _partnershipSubscription?.cancel();
    _notificationSubscription?.cancel();
    _refreshTriggerSubscription?.cancel(); // ✅ NEW
    _partnershipUpdateSubscription?.cancel(); // ✅ NEW
    super.dispose();
  }
}
