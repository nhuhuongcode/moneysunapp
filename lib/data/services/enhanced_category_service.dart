// lib/data/services/enhanced_category_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';

class EnhancedCategoryService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final OfflineSyncService _offlineSync = OfflineSyncService();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  // ============ CATEGORY MANAGEMENT WITH OWNERSHIP ============

  /// Get categories with ownership filtering (personal + shared)
  Stream<List<Category>> getCategoriesWithOwnershipStream(
    UserProvider userProvider, {
    String? type,
  }) async* {
    if (_uid == null) {
      yield [];
      return;
    }

    // Try offline first
    try {
      final localCategories = await _localDb.getLocalCategoriesEnhanced(
        ownerId: _uid,
        type: type,
        includeArchived: false,
      );

      if (localCategories.isNotEmpty) {
        yield _filterCategoriesByOwnership(localCategories, userProvider);
      }
    } catch (e) {
      print('Error getting local categories: $e');
    }

    // Firebase stream
    yield* _dbRef
        .child('categories')
        .onValue
        .map((event) {
          final List<Category> categories = [];

          if (event.snapshot.exists) {
            final allCategoriesMap =
                event.snapshot.value as Map<dynamic, dynamic>;

            allCategoriesMap.forEach((key, value) {
              final categorySnapshot = event.snapshot.child(key);
              final category = Category.fromSnapshot(categorySnapshot);

              // Filter by ownership and type
              if (_shouldIncludeCategory(category, userProvider, type)) {
                categories.add(category);
              }
            });
          }

          return categories..sort((a, b) => a.name.compareTo(b.name));
        })
        .handleError((error) {
          print('Firebase category stream error: $error');
          return <Category>[];
        });
  }

  /// Check if category should be included based on ownership
  bool _shouldIncludeCategory(
    Category category,
    UserProvider userProvider,
    String? type,
  ) {
    // Filter by type if specified
    if (type != null && category.type != type) return false;

    // Filter by archived status
    if (category.isArchived) return false;

    // Include personal categories
    if (category.ownerId == _uid) return true;

    // Include shared categories if user has partnership
    if (userProvider.partnershipId != null &&
        category.ownerId == userProvider.partnershipId) {
      return true;
    }

    return false;
  }

  /// Filter categories by ownership for offline data
  List<Category> _filterCategoriesByOwnership(
    List<Category> categories,
    UserProvider userProvider,
  ) {
    return categories.where((category) {
      return _shouldIncludeCategory(category, userProvider, null);
    }).toList();
  }

  // ============ CREATE CATEGORIES WITH OWNERSHIP ============

  /// Create category with ownership type selection
  Future<void> createCategoryWithOwnership({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    required UserProvider userProvider,
    int? iconCodePoint,
    Map<String, String>? subCategories,
  }) async {
    if (_uid == null) throw Exception('User not authenticated');

    try {
      // Determine ownerId based on ownership type
      String ownerId;
      if (ownershipType == CategoryOwnershipType.shared) {
        if (userProvider.partnershipId == null) {
          throw Exception('Không thể tạo danh mục chung khi chưa có đối tác');
        }
        ownerId = userProvider.partnershipId!;
      } else {
        ownerId = _uid!;
      }

      // Create category
      final categoryRef = _dbRef.child('categories').push();
      final category = Category(
        id: categoryRef.key!,
        name: name,
        ownerId: ownerId,
        type: type,
        ownershipType: ownershipType,
        createdBy: _uid,
        iconCodePoint: iconCodePoint,
        subCategories: subCategories ?? {},
        createdAt: DateTime.now(),
      );

      // Save offline first
      await _localDb.saveCategoryLocallyEnhanced(category, syncStatus: 0);

      // Try to sync online
      if (_offlineSync.isOnline) {
        try {
          await categoryRef.set(category.toJson());
          await _localDb.markAsSynced('categories', category.id);

          // Send notification if shared category
          if (ownershipType == CategoryOwnershipType.shared &&
              userProvider.partnerUid != null) {
            await _sendCategoryNotification(
              userProvider.partnerUid!,
              'Danh mục chung mới',
              '${userProvider.currentUser?.displayName ?? "Đối tác"} đã tạo danh mục "$name" chung',
            );
          }
        } catch (e) {
          print('Failed to sync category immediately: $e');
          // Will be synced later by offline sync service
        }
      }

      print('✅ Category created: $name (${ownershipType.name})');
    } catch (e) {
      print('❌ Error creating category: $e');
      rethrow;
    }
  }

  // ============ CATEGORY SUGGESTIONS & SMART FEATURES ============

  /// Get smart category suggestions based on usage
  Future<List<Category>> getSmartCategorySuggestions({
    required String type,
    required UserProvider userProvider,
    String? searchQuery,
    int limit = 5,
  }) async {
    try {
      // Get from local database first
      final localCategories = await _localDb.getCategoriesByOwnership(
        _uid!,
        userProvider.partnershipId,
        type,
      );

      List<Category> suggestions = localCategories;

      // Filter by search query if provided
      if (searchQuery != null && searchQuery.isNotEmpty) {
        suggestions = suggestions
            .where(
              (cat) =>
                  cat.name.toLowerCase().contains(searchQuery.toLowerCase()),
            )
            .toList();
      }

      // Sort by usage frequency (implement usage tracking)
      suggestions.sort((a, b) => a.name.compareTo(b.name));

      return suggestions.take(limit).toList();
    } catch (e) {
      print('Error getting smart category suggestions: $e');
      return [];
    }
  }

  /// Get category usage statistics
  Future<List<CategoryUsage>> getCategoryUsageStats(
    UserProvider userProvider, {
    String? type,
    int limit = 10,
  }) async {
    if (_uid == null) return [];

    try {
      return await _localDb.getCategoryUsageStats(_uid!, limit: limit);
    } catch (e) {
      print('Error getting category usage stats: $e');
      return [];
    }
  }

  // ============ CATEGORY ACTIONS ============

  /// Update category
  Future<void> updateCategory(Category category) async {
    if (_uid == null) return;

    try {
      // Check permissions
      if (!CategoryValidator.canEdit(category, _uid!)) {
        throw Exception('Bạn không có quyền chỉnh sửa danh mục này');
      }

      // Update locally first
      await _localDb.updateCategoryLocally(category);

      // Try to sync online
      if (_offlineSync.isOnline) {
        try {
          await _dbRef.child('categories').child(category.id).update({
            'name': category.name,
            'iconCodePoint': category.iconCodePoint,
            'subCategories': category.subCategories,
            'updatedAt': ServerValue.timestamp,
          });
          await _localDb.markAsSynced('categories', category.id);
        } catch (e) {
          print('Failed to sync category update: $e');
        }
      }

      print('✅ Category updated: ${category.name}');
    } catch (e) {
      print('❌ Error updating category: $e');
      rethrow;
    }
  }

  /// Archive category (safer than delete)
  Future<void> archiveCategory(String categoryId) async {
    if (_uid == null) return;

    try {
      // Archive locally first
      await _localDb.archiveCategoryLocally(categoryId);

      // Try to sync online
      if (_offlineSync.isOnline) {
        try {
          await _dbRef.child('categories').child(categoryId).update({
            'isArchived': true,
            'updatedAt': ServerValue.timestamp,
          });
          await _localDb.markAsSynced('categories', categoryId);
        } catch (e) {
          print('Failed to sync category archive: $e');
        }
      }

      print('✅ Category archived');
    } catch (e) {
      print('❌ Error archiving category: $e');
      rethrow;
    }
  }

  /// Delete category with safety checks
  Future<void> deleteCategory(String categoryId) async {
    if (_uid == null) return;

    try {
      // Check if category has transactions
      final hasTransactions = await _checkCategoryHasTransactions(categoryId);

      if (hasTransactions) {
        throw Exception(
          'Không thể xóa danh mục này vì đang có giao dịch. Hãy lưu trữ thay vì xóa.',
        );
      }

      // Delete locally first
      await _localDb.deleteCategoryLocally(categoryId);

      // Try to sync online
      if (_offlineSync.isOnline) {
        try {
          await _dbRef.child('categories').child(categoryId).remove();
        } catch (e) {
          print('Failed to sync category deletion: $e');
        }
      }

      print('✅ Category deleted');
    } catch (e) {
      print('❌ Error deleting category: $e');
      rethrow;
    }
  }

  // ============ SUB-CATEGORIES ============

  /// Add sub-category
  Future<void> addSubCategory(
    String parentCategoryId,
    String subCategoryName,
  ) async {
    if (_uid == null) return;

    try {
      // Get parent category
      final categories = await _localDb.getLocalCategoriesEnhanced();
      final parentCategory = categories.firstWhere(
        (cat) => cat.id == parentCategoryId,
        orElse: () => throw Exception('Parent category not found'),
      );

      // Add sub-category locally
      final updatedSubCategories = Map<String, String>.from(
        parentCategory.subCategories,
      );
      final subCategoryId = DateTime.now().millisecondsSinceEpoch.toString();
      updatedSubCategories[subCategoryId] = subCategoryName;

      final updatedCategory = parentCategory.copyWith(
        subCategories: updatedSubCategories,
        updatedAt: DateTime.now(),
      );

      await updateCategory(updatedCategory);

      print('✅ Sub-category added: $subCategoryName');
    } catch (e) {
      print('❌ Error adding sub-category: $e');
      rethrow;
    }
  }

  /// Delete sub-category
  Future<void> deleteSubCategory(
    String parentCategoryId,
    String subCategoryId,
  ) async {
    if (_uid == null) return;

    try {
      // Get parent category
      final categories = await _localDb.getLocalCategoriesEnhanced();
      final parentCategory = categories.firstWhere(
        (cat) => cat.id == parentCategoryId,
        orElse: () => throw Exception('Parent category not found'),
      );

      // Remove sub-category locally
      final updatedSubCategories = Map<String, String>.from(
        parentCategory.subCategories,
      );
      updatedSubCategories.remove(subCategoryId);

      final updatedCategory = parentCategory.copyWith(
        subCategories: updatedSubCategories,
        updatedAt: DateTime.now(),
      );

      await updateCategory(updatedCategory);

      print('✅ Sub-category deleted');
    } catch (e) {
      print('❌ Error deleting sub-category: $e');
      rethrow;
    }
  }

  // ============ HELPER METHODS ============

  Future<bool> _checkCategoryHasTransactions(String categoryId) async {
    try {
      // Check locally first
      final hasLocal = await _localDb.checkCategoryHasTransactionsLocally(
        categoryId,
      );
      if (hasLocal) return true;

      // Check Firebase if online
      if (_offlineSync.isOnline) {
        final snapshot = await _dbRef
            .child('transactions')
            .orderByChild('categoryId')
            .equalTo(categoryId)
            .limitToFirst(1)
            .get();

        return snapshot.exists && snapshot.children.isNotEmpty;
      }

      return false;
    } catch (e) {
      print('Error checking category transactions: $e');
      return true; // Be safe and assume it has transactions
    }
  }

  Future<void> _sendCategoryNotification(
    String userId,
    String title,
    String body,
  ) async {
    try {
      await _dbRef.child('user_notifications').child(userId).push().set({
        'title': title,
        'body': body,
        'timestamp': ServerValue.timestamp,
        'type': 'category',
        'isRead': false,
      });
    } catch (e) {
      print('Error sending category notification: $e');
    }
  }

  // ============ SYNC MANAGEMENT ============

  /// Sync categories when coming online
  Future<void> syncCategoriesToFirebase() async {
    if (_uid == null) return;

    try {
      final unsyncedCategories = await _localDb.getUnsyncedRecords(
        'categories',
      );
      print('🔄 Syncing ${unsyncedCategories.length} unsynced categories...');

      for (final record in unsyncedCategories) {
        try {
          final category = _categoryFromMap(record);
          await _dbRef
              .child('categories')
              .child(category.id)
              .set(category.toJson());

          await _localDb.markAsSynced('categories', category.id);
          print('✅ Synced category: ${category.name}');
        } catch (e) {
          print('❌ Failed to sync category ${record['id']}: $e');
        }
      }

      print('🎉 Categories sync completed');
    } catch (e) {
      print('❌ Error syncing categories: $e');
    }
  }

  Category _categoryFromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      ownerId: map['ownerId'],
      type: map['type'],
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == (map['ownershipType'] ?? 'personal'),
        orElse: () => CategoryOwnershipType.personal,
      ),
      iconCodePoint: map['iconCodePoint'],
      subCategories: Map<String, String>.from(
        map['subCategories'] != null ? map['subCategories'] : {},
      ),
      createdBy: map['createdBy'],
      isArchived: (map['isArchived'] ?? 0) == 1,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : null,
    );
  }

  // ============ OFFLINE-FIRST HELPERS ============

  /// Get categories offline-first
  Future<List<Category>> getCategoriesOfflineFirst({
    String? type,
    CategoryOwnershipType? ownershipType,
    UserProvider? userProvider,
  }) async {
    try {
      // Try local database first
      final localCategories = await _localDb.getLocalCategoriesEnhanced(
        ownerId: _uid,
        type: type,
        ownershipType: ownershipType,
      );

      if (localCategories.isNotEmpty && userProvider != null) {
        return _filterCategoriesByOwnership(localCategories, userProvider);
      }

      return localCategories;
    } catch (e) {
      print('❌ Error getting categories offline-first: $e');
      return [];
    }
  }

  /// Get database health for categories
  Future<Map<String, dynamic>> getCategoryDatabaseHealth() async {
    try {
      final syncStatus = await _localDb.getOfflineSyncStatus();

      return {
        'totalCategories': syncStatus['totalCategories'],
        'unsyncedCategories': syncStatus['unsyncedCategories'],
        'lastUpdate': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
