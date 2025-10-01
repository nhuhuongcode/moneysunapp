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
      // Setup listeners
      _listenToUserProfile(user.uid);
      _listenToNotifications(user.uid);
      _listenToRefreshTriggers(user.uid);
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

  Future<void> _handleUserSignOut() async {
    await _clearAllData();
    _clearError();
  }

  // ============ PARTNERSHIP CHANGE HANDLING ============

  /// ✅ FIXED: Complete partnership change handler with listener setup
  Future<void> _handlePartnershipChange(
    String? newPartnershipId,
    Map<dynamic, dynamic> userData,
  ) async {
    final oldPartnershipId = _partnershipId;

    debugPrint('🔄 Partnership change detected:');
    debugPrint('   Old: $oldPartnershipId');
    debugPrint('   New: $newPartnershipId');

    _partnershipId = newPartnershipId;

    if (newPartnershipId != null) {
      // ✅ STEP 1: Update ALL partner info IMMEDIATELY
      _partnerUid = userData['partnerUid'] as String?;
      _partnerDisplayName = userData['partnerDisplayName'] as String?;
      _partnerPhotoURL = userData['partnerPhotoURL'] as String?;
      _partnershipCreationDate = userData['partnershipCreatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              userData['partnershipCreatedAt'],
            )
          : null;

      debugPrint('✅ Partner info updated:');
      debugPrint('   Partner UID: $_partnerUid');
      debugPrint('   Partner Name: $_partnerDisplayName');
      debugPrint('   Partnership ID: $_partnershipId');

      // ✅ STEP 2: Setup listeners for partner and partnership
      if (_partnerUid != null) {
        debugPrint('👂 Setting up partner profile listener...');
        _listenToPartnerProfile(_partnerUid!);
      }

      if (_partnershipId != null) {
        debugPrint('👂 Setting up partnership listener...');
        _listenToPartnership(_partnershipId!);
      }

      // ✅ STEP 3: Save to cache
      await _savePartnershipState();

      // ✅ STEP 4: Force MULTIPLE UI updates to ensure all widgets refresh
      debugPrint('📢 Triggering UI updates...');
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 100));
      notifyListeners();

      await Future.delayed(const Duration(milliseconds: 300));
      notifyListeners();

      debugPrint('✅ Partnership setup completed successfully');
    } else {
      // Partnership removed
      debugPrint('💔 Partnership removed - cleaning up...');
      await _clearPartnershipData();
    }
  }

  void _listenToUserProfile(String uid) {
    _userProfileSubscription?.cancel();

    final userRef = _dbRef.child('users').child(uid);

    debugPrint('👂 Setting up user profile listener for: $uid');

    _userProfileSubscription = userRef.onValue.listen((event) async {
      if (!event.snapshot.exists) return;

      try {
        final userData = event.snapshot.value as Map<dynamic, dynamic>;

        // Detect partnership-related updates
        final newPartnershipId = userData['partnershipId'] as String?;
        final lastPartnerUpdate = userData['lastPartnerUpdate'] as int?;

        // Check if this is a recent partnership update (within 5 seconds)
        final isRecentPartnershipUpdate =
            lastPartnerUpdate != null &&
            (DateTime.now().millisecondsSinceEpoch - lastPartnerUpdate) < 5000;

        if (isRecentPartnershipUpdate) {
          debugPrint('🔔 RECENT PARTNERSHIP UPDATE DETECTED (within 5s)');
        }

        // Update current user data
        _currentUser = AppUser.fromMap(userData, uid);

        // ✅ CRITICAL FIX: Only handle partnership change if there's actually a change
        if (newPartnershipId != _partnershipId) {
          debugPrint(
            '🔄 Partnership ID changed: $_partnershipId -> $newPartnershipId',
          );

          // ✅ NEW: Additional validation before clearing partnership
          if (newPartnershipId == null && _partnershipId != null) {
            // Partnership is being removed - verify this is intentional
            debugPrint('⚠️ Partnership removal detected - verifying...');

            // ✅ Check if partnership still exists in Firebase
            final partnershipCheck = await _dbRef
                .child('partnerships')
                .child(_partnershipId!)
                .get();

            if (partnershipCheck.exists) {
              final partnershipData =
                  partnershipCheck.value as Map<dynamic, dynamic>;
              final isActive = partnershipData['isActive'] as bool? ?? true;

              if (isActive) {
                debugPrint(
                  '⚠️ Partnership still exists in Firebase but missing from user data',
                );
                debugPrint(
                  '   This might be a partial update - NOT clearing partnership',
                );

                // ✅ CRITICAL: Restore partnership data from Firebase
                final memberIds =
                    partnershipData['memberIds'] as Map<dynamic, dynamic>?;
                if (memberIds != null && memberIds.containsKey(uid)) {
                  debugPrint('🔄 Restoring partnership data from Firebase...');

                  // Find partner UID
                  final partnerUid = memberIds.keys.firstWhere(
                    (key) => key != uid,
                    orElse: () => null,
                  );

                  if (partnerUid != null) {
                    // Update user data in Firebase to restore partnership
                    final memberNames =
                        partnershipData['memberNames']
                            as Map<dynamic, dynamic>? ??
                        {};

                    await _dbRef.child('users').child(uid).update({
                      'partnershipId': _partnershipId,
                      'partnerUid': partnerUid,
                      'partnerDisplayName': memberNames[partnerUid]?.toString(),
                      'updatedAt': ServerValue.timestamp,
                    });

                    debugPrint('✅ Partnership data restored in Firebase');

                    // Don't call _handlePartnershipChange - data is already correct
                    await _savePartnershipState();
                    notifyListeners();
                    return;
                  }
                }
              } else {
                debugPrint(
                  'ℹ️ Partnership is inactive - proceeding with removal',
                );
              }
            } else {
              debugPrint(
                'ℹ️ Partnership no longer exists in Firebase - proceeding with removal',
              );
            }
          }

          // Call the handler to update partnership state
          await _handlePartnershipChange(newPartnershipId, userData);

          // Extra UI updates for recent changes
          if (isRecentPartnershipUpdate) {
            await Future.delayed(const Duration(milliseconds: 100));
            notifyListeners();
            await Future.delayed(const Duration(milliseconds: 300));
            notifyListeners();

            debugPrint(
              '🎯 Forced multiple UI updates for recent partnership change',
            );
          }
        } else if (newPartnershipId != null) {
          // Partnership ID hasn't changed but other data might have
          await _updatePartnerInfo(userData);
        }

        await _savePartnershipState();
        notifyListeners();
      } catch (e, stackTrace) {
        debugPrint('❌ Error in _listenToUserProfile: $e');
        debugPrint('Stack trace: $stackTrace');
        _setError('Lỗi cập nhật profile: $e');
      }
    });

    debugPrint('✅ User profile listener active');
  }

  // ✅ ENHANCED: Refresh trigger listener with high-priority handling
  void _listenToRefreshTriggers(String uid) {
    _refreshTriggerSubscription?.cancel();

    debugPrint(
      '👂 Setting up HIGH PRIORITY refresh trigger listener for: $uid',
    );

    _refreshTriggerSubscription = _dbRef
        .child('user_refresh_triggers')
        .child(uid)
        .onChildAdded
        .listen((event) async {
          if (!event.snapshot.exists) return;

          try {
            final triggerData = event.snapshot.value as Map<dynamic, dynamic>;
            final triggerType = triggerData['type'] as String?;
            final requireRefresh =
                triggerData['requireRefresh'] as bool? ?? false;
            final priority = triggerData['priority'] as String?;
            final forceReload = triggerData['forceReload'] as bool? ?? false;

            debugPrint(
              '🔔 Refresh trigger received: $triggerType (priority: $priority)',
            );

            if (requireRefresh || forceReload) {
              // ✅ HIGH PRIORITY: Execute multiple refreshes
              if (priority == 'high' || forceReload) {
                debugPrint('⚡ HIGH PRIORITY - Starting refresh cycle...');

                // First refresh
                await refreshUser();

                // Wait and refresh again to ensure Firebase data propagated
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

              // ✅ Force MULTIPLE UI updates
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

    debugPrint('✅ High-priority refresh trigger listener active');
  }

  // ✅ ENHANCED: Partnership update listener
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

  void _listenToPartnerProfile(String partnerUid) {
    _partnerProfileSubscription?.cancel();

    final partnerRef = _dbRef.child('users').child(partnerUid);

    debugPrint('👂 Setting up partner profile listener for: $partnerUid');

    _partnerProfileSubscription = partnerRef.onValue.listen((event) async {
      if (!event.snapshot.exists) {
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

    debugPrint('✅ Partner profile listener active');
  }

  void _listenToPartnership(String partnershipId) {
    _partnershipSubscription?.cancel();

    debugPrint('👂 Setting up partnership listener for: $partnershipId');

    _partnershipSubscription = _dbRef
        .child('partnerships')
        .child(partnershipId)
        .onValue
        .listen((event) async {
          if (!event.snapshot.exists) {
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

    debugPrint('✅ Partnership listener active');
  }

  void _listenToNotifications(String uid) {
    _notificationSubscription?.cancel();

    debugPrint('👂 Setting up notifications listener for: $uid');

    _notificationSubscription = _dbRef
        .child('user_notifications')
        .child(uid)
        .orderByChild('timestamp')
        .limitToLast(5)
        .onChildAdded
        .listen((event) {
          if (!event.snapshot.exists) return;

          try {
            final data = event.snapshot.value;

            if (data == null) {
              debugPrint('⚠️ Notification data is null');
              return;
            }

            // ✅ Skip if data is bool (Firebase marker)
            if (data is bool) {
              debugPrint('⚠️ Notification data is bool: $data - skipping');
              return;
            }

            if (data is! Map) {
              debugPrint(
                '⚠️ Notification data is not a Map: ${data.runtimeType}',
              );
              return;
            }

            final notificationData = Map<dynamic, dynamic>.from(data as Map);

            final type = notificationData['type'] as String?;
            final isRead = notificationData['isRead'] as bool? ?? false;

            debugPrint('📬 Notification received: $type (read: $isRead)');

            if (!isRead && type != null && type.startsWith('partnership')) {
              _handlePartnershipNotification(
                notificationData,
                event.snapshot.ref,
              );
            }

            // ✅ NEW: Auto-cleanup old read notifications
            if (isRead) {
              final timestamp = notificationData['timestamp'] as int?;
              if (timestamp != null) {
                final notifTime = DateTime.fromMillisecondsSinceEpoch(
                  timestamp,
                );
                if (DateTime.now().difference(notifTime).inDays > 7) {
                  event.snapshot.ref.remove().catchError((e) {
                    debugPrint('Error cleaning up old notification: $e');
                  });
                }
              }
            }
          } catch (e, stackTrace) {
            debugPrint('❌ Lỗi khi xử lý notification: $e');
            debugPrint('Stack trace: $stackTrace');
          }
        });

    debugPrint('✅ Notifications listener active');
  }

  void _handlePartnershipNotification(
    Map<dynamic, dynamic> data,
    DatabaseReference ref,
  ) {
    final type = data['type'] as String;

    switch (type) {
      case 'partnership_accepted':
      case 'partnership_connected':
        refreshPartnershipData();
        break;
      case 'partnership_disconnected':
        _clearPartnershipData();
        break;
    }

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

  Future<void> _validateAndRefreshPartnership() async {
    if (_partnershipId == null) {
      debugPrint(
        '⚠️ _validateAndRefreshPartnership: partnershipId is null, skipping',
      );
      return;
    }

    try {
      debugPrint('🔍 Validating partnership: $_partnershipId');

      final partnershipSnapshot = await _dbRef
          .child('partnerships')
          .child(_partnershipId!)
          .get();

      if (!partnershipSnapshot.exists) {
        debugPrint(
          '❌ Partnership does not exist in Firebase, clearing data...',
        );
        await _clearPartnershipData();
        return;
      }

      final partnershipData =
          partnershipSnapshot.value as Map<dynamic, dynamic>;
      debugPrint('✅ Partnership data found: ${partnershipData.keys.toList()}');

      final isActive = partnershipData['isActive'] ?? true;
      debugPrint('   isActive: $isActive');

      if (!isActive) {
        debugPrint('❌ Partnership is not active, clearing data...');
        await _clearPartnershipData();
        return;
      }

      final membersData = partnershipData['members'] as Map<dynamic, dynamic>?;
      final memberIds = partnershipData['memberIds'] as Map<dynamic, dynamic>?;
      final members = membersData ?? memberIds;

      debugPrint('   Members: ${members?.keys.toList()}');
      debugPrint('   Current user: ${currentUser?.uid}');

      if (members == null || !members.containsKey(currentUser!.uid)) {
        debugPrint('❌ User not in partnership members, clearing data...');
        await _clearPartnershipData();
        return;
      }

      _partnershipData = partnershipSnapshot;

      final memberNames =
          partnershipData['memberNames'] as Map<dynamic, dynamic>? ?? {};
      final validPartnerUid = members.keys.firstWhere(
        (key) => key != currentUser!.uid,
        orElse: () => null,
      );

      debugPrint('   Partner UID found: $validPartnerUid');

      if (validPartnerUid != null) {
        _partnerUid = validPartnerUid;
        _partnerDisplayName = memberNames[validPartnerUid]?.toString();

        debugPrint('   Partner name: $_partnerDisplayName');

        // ✅ CRITICAL: Setup listener for partner
        _listenToPartnerProfile(_partnerUid!);
      }

      // ✅ FIX: Save partnership state BEFORE notifyListeners
      debugPrint('💾 Saving partnership state before notify...');
      debugPrint('   Partnership ID: $_partnershipId');
      debugPrint('   Partner UID: $_partnerUid');
      debugPrint('   Partner Name: $_partnerDisplayName');

      await _savePartnershipState();

      // ✅ Verify save was successful
      debugPrint('✅ Partnership state saved successfully');

      notifyListeners();

      debugPrint('✅ Partnership validation completed successfully');
    } catch (e, stackTrace) {
      debugPrint('❌ Error validating partnership: $e');
      debugPrint('Stack trace: $stackTrace');
      await _clearPartnershipData();
    }
  }

  Future<void> refreshUser() async {
    if (_auth.currentUser == null) return;

    _setLoading(true);

    try {
      debugPrint('🔄 Refreshing user data...');

      final snapshot = await _dbRef
          .child('users')
          .child(_auth.currentUser!.uid)
          .get();

      if (snapshot.exists) {
        final userData = snapshot.value as Map<dynamic, dynamic>;
        _currentUser = AppUser.fromMap(userData, _auth.currentUser!.uid);

        final newPartnershipId = userData['partnershipId'] as String?;

        debugPrint('   Current partnership: $_partnershipId');
        debugPrint('   New partnership: $newPartnershipId');

        // ✅ CRITICAL: Detect partnership change during refresh
        if (newPartnershipId != _partnershipId) {
          debugPrint('🔄 Partnership detected during refreshUser');

          // ✅ NEW: If removing partnership, verify it's intentional
          if (newPartnershipId == null && _partnershipId != null) {
            debugPrint('⚠️ Partnership removal in refreshUser - verifying...');

            final partnershipCheck = await _dbRef
                .child('partnerships')
                .child(_partnershipId!)
                .get();

            if (partnershipCheck.exists) {
              final partnershipData =
                  partnershipCheck.value as Map<dynamic, dynamic>;
              final isActive = partnershipData['isActive'] as bool? ?? true;

              if (isActive) {
                debugPrint(
                  '⚠️ Partnership still active in Firebase - NOT removing',
                );

                // Keep existing partnership data
                await _savePartnershipState();
                _clearError();
                _setLoading(false);
                return;
              }
            }
          }

          // Call handler to setup listeners
          await _handlePartnershipChange(newPartnershipId, userData);
        } else {
          // Just update the data without calling handler
          _partnershipId = userData['partnershipId'] as String?;
          _partnerUid = userData['partnerUid'] as String?;
          _partnerDisplayName = userData['partnerDisplayName'] as String?;
          _partnerPhotoURL = userData['partnerPhotoURL'] as String?;
          _partnershipCreationDate = userData['partnershipCreatedAt'] != null
              ? DateTime.fromMillisecondsSinceEpoch(
                  userData['partnershipCreatedAt'],
                )
              : null;

          debugPrint('   Partnership data updated (no change in ID)');
        }

        await _savePartnershipState();
        _clearError();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error in refreshUser: $e');
      debugPrint('Stack trace: $stackTrace');
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
      await _clearPartnershipData();
      _clearError();
    } catch (e) {
      _setError('Lỗi khi ngắt kết nối: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _updatePartnerInfo(Map<dynamic, dynamic> userData) async {
    final newPartnerUid = userData['partnerUid'] as String?;
    final newPartnerDisplayName = userData['partnerDisplayName'] as String?;

    bool hasChanges = false;

    if (_partnerUid != newPartnerUid) {
      _partnerUid = newPartnerUid;
      hasChanges = true;

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
      debugPrint('💾 _savePartnershipState called with:');
      debugPrint('   _partnershipId: $_partnershipId');
      debugPrint('   _partnerUid: $_partnerUid');
      debugPrint('   _partnerDisplayName: $_partnerDisplayName');
      debugPrint('   _partnerPhotoURL: $_partnerPhotoURL');
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
    debugPrint('🧹 _clearPartnershipData called!');
    debugPrint('Stack trace: ${StackTrace.current}');
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

  @override
  void dispose() {
    _mounted = false;
    _userProfileSubscription?.cancel();
    _partnerProfileSubscription?.cancel();
    _partnershipSubscription?.cancel();
    _notificationSubscription?.cancel();
    _refreshTriggerSubscription?.cancel();
    _partnershipUpdateSubscription?.cancel();
    super.dispose();
  }
}
