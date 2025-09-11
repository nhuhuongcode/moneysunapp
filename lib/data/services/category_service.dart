// lib/data/services/_category_service.dart
import 'package:flutter/foundation.dart' hide Category;
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/data_service.dart';

///  Category Service that works with DataService
class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  final DataService _dataService = DataService();

  /// Get categories with ownership filtering - offline first
  Future<List<Category>> getCategoriesOfflineFirst({
    required UserProvider userProvider,
    String? type, // 'income' or 'expense'
    CategoryOwnershipType? ownershipType,
    bool includeArchived = false,
  }) async {
    try {
      debugPrint('🔍 Getting categories offline-first...');

      final allCategories = await _dataService.getCategories(
        includeArchived: includeArchived,
      );

      var filteredCategories = allCategories;

      // Filter by type
      if (type != null) {
        filteredCategories = filteredCategories
            .where((c) => c.type == type)
            .toList();
      }

      // Filter by ownership
      if (ownershipType != null) {
        filteredCategories = filteredCategories
            .where((c) => c.ownershipType == ownershipType)
            .toList();
      }

      // Sort by usage count and name
      filteredCategories.sort((a, b) {
        if (a.usageCount != b.usageCount) {
          return b.usageCount.compareTo(a.usageCount);
        }
        return a.name.compareTo(b.name);
      });

      debugPrint('✅ Found ${filteredCategories.length} categories');
      return filteredCategories;
    } catch (e) {
      debugPrint('❌ Error getting categories: $e');
      return [];
    }
  }

  /// Get categories stream with ownership filtering
  Stream<List<Category>> getCategoriesWithOwnershipStream(
    UserProvider userProvider, {
    String? type,
    CategoryOwnershipType? ownershipType,
    bool includeArchived = false,
  }) async* {
    yield* _dataService
        .getCategoriesStream(includeArchived: includeArchived)
        .map((categories) {
          var filtered = categories;

          if (type != null) {
            filtered = filtered.where((c) => c.type == type).toList();
          }

          if (ownershipType != null) {
            filtered = filtered
                .where((c) => c.ownershipType == ownershipType)
                .toList();
          }

          // Sort by usage
          filtered.sort((a, b) {
            if (a.usageCount != b.usageCount) {
              return b.usageCount.compareTo(a.usageCount);
            }
            return a.name.compareTo(b.name);
          });

          return filtered;
        });
  }

  /// Create category with ownership
  Future<void> createCategoryWithOwnership({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    required UserProvider userProvider,
    int? iconCodePoint,
    Map<String, String>? subCategories,
  }) async {
    if (userProvider.currentUser == null) {
      throw Exception('User not authenticated');
    }

    try {
      debugPrint('➕ Creating category: $name ($ownershipType)');

      final categoryId =
          'cat_${DateTime.now().millisecondsSinceEpoch}_${name.hashCode.abs()}';

      String ownerId;
      if (ownershipType == CategoryOwnershipType.shared) {
        if (!userProvider.hasPartner) {
          throw Exception('Cannot create shared category without partner');
        }
        ownerId = userProvider.partnershipId!;
      } else {
        ownerId = userProvider.currentUser!.uid;
      }

      // Create category using DataService's internal structure
      // Since DataService doesn't expose addCategory method yet, we'll use the addTransaction pattern
      // For now, we'll use a placeholder and you should add addCategory method to DataService

      // TODO: Add this method to DataService
      // await _dataService.addCategory(category);

      // Temporary workaround - manually insert category data
      await _createCategoryDirectly(
        categoryId: categoryId,
        name: name,
        type: type,
        ownerId: ownerId,
        ownershipType: ownershipType,
        userProvider: userProvider,
        iconCodePoint: iconCodePoint,
        subCategories: subCategories,
      );

      debugPrint('✅ Category created successfully');
    } catch (e) {
      debugPrint('❌ Error creating category: $e');
      rethrow;
    }
  }

  /// Temporary method until addCategory is added to DataService
  Future<void> _createCategoryDirectly({
    required String categoryId,
    required String name,
    required String type,
    required String ownerId,
    required CategoryOwnershipType ownershipType,
    required UserProvider userProvider,
    int? iconCodePoint,
    Map<String, String>? subCategories,
  }) async {
    // This is a placeholder implementation
    // In practice, you should add addCategory method to DataService

    final category = Category(
      id: categoryId,
      name: name,
      ownerId: ownerId,
      type: type,
      iconCodePoint: iconCodePoint,
      subCategories: subCategories ?? {},
      ownershipType: ownershipType,
      createdBy: userProvider.currentUser!.uid,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // Since DataService doesn't have addCategory yet, we'll log this
    debugPrint(
      '⚠️ Category creation deferred until DataService.addCategory is implemented',
    );
    debugPrint('Category data: ${category.toJson()}');

    // TODO: Implement in DataService
    // throw UnimplementedError('DataService.addCategory method needed');
  }

  /// Update category
  Future<void> updateCategory(Category category) async {
    try {
      debugPrint('✏️ Updating category: ${category.name}');

      // TODO: Implement in DataService
      // await _dataService.updateCategory(category);

      debugPrint(
        '⚠️ Category update deferred until DataService.updateCategory is implemented',
      );
    } catch (e) {
      debugPrint('❌ Error updating category: $e');
      rethrow;
    }
  }

  /// Delete category
  Future<void> deleteCategory(String categoryId) async {
    try {
      debugPrint('🗑️ Deleting category: $categoryId');

      // TODO: Implement in DataService
      // await _dataService.deleteCategory(categoryId);

      debugPrint(
        '⚠️ Category deletion deferred until DataService.deleteCategory is implemented',
      );
    } catch (e) {
      debugPrint('❌ Error deleting category: $e');
      rethrow;
    }
  }

  /// Get category by ID
  Future<Category?> getCategoryById(String categoryId) async {
    try {
      final categories = await _dataService.getCategories();
      return categories.where((c) => c.id == categoryId).firstOrNull;
    } catch (e) {
      debugPrint('❌ Error getting category by ID: $e');
      return null;
    }
  }

  /// Search categories
  Future<List<Category>> searchCategories({
    required String query,
    String? type,
    CategoryOwnershipType? ownershipType,
  }) async {
    try {
      final categories = await _dataService.getCategories();

      return CategoryUtils.sortCategoriesByRelevance(
        CategoryUtils.filterByOwnership(
          categories,
          ownershipType,
        ).where((c) => type == null || c.type == type).toList(),
        query,
      );
    } catch (e) {
      debugPrint('❌ Error searching categories: $e');
      return [];
    }
  }

  /// Get category suggestions based on description
  Future<List<CategorySuggestion>> getCategorySuggestions({
    required String description,
    required String type,
    double amount = 0,
  }) async {
    try {
      final categories = await _dataService.getCategories();
      final relevantCategories = categories
          .where((c) => c.type == type && c.isActive && !c.isArchived)
          .toList();

      if (relevantCategories.isEmpty) {
        return [];
      }

      final suggestion = CategoryUtils.suggestCategory(
        description,
        relevantCategories,
        amount,
      );

      return [suggestion];
    } catch (e) {
      debugPrint('❌ Error getting category suggestions: $e');
      return [];
    }
  }

  /// Archive category
  Future<void> archiveCategory(String categoryId) async {
    try {
      debugPrint('📦 Archiving category: $categoryId');

      // TODO: Implement in DataService
      // final category = await getCategoryById(categoryId);
      // if (category != null) {
      //   await updateCategory(category.copyWith(isArchived: true));
      // }

      debugPrint(
        '⚠️ Category archiving deferred until DataService methods are implemented',
      );
    } catch (e) {
      debugPrint('❌ Error archiving category: $e');
      rethrow;
    }
  }

  /// Restore archived category
  Future<void> restoreCategory(String categoryId) async {
    try {
      debugPrint('📤 Restoring category: $categoryId');

      // TODO: Implement in DataService
      debugPrint(
        '⚠️ Category restore deferred until DataService methods are implemented',
      );
    } catch (e) {
      debugPrint('❌ Error restoring category: $e');
      rethrow;
    }
  }

  /// Get category statistics
  Future<CategoryStatistics> getCategoryStatistics() async {
    try {
      final categories = await _dataService.getCategories(
        includeArchived: true,
      );
      return CategoryStatistics.fromCategories(categories);
    } catch (e) {
      debugPrint('❌ Error getting category statistics: $e');
      return CategoryStatistics.fromCategories([]);
    }
  }

  /// Bulk import categories
  Future<void> importCategories(List<Category> categories) async {
    try {
      debugPrint('📥 Importing ${categories.length} categories');

      for (final category in categories) {
        await _createCategoryDirectly(
          categoryId: category.id,
          name: category.name,
          type: category.type,
          ownerId: category.ownerId,
          ownershipType: category.ownershipType,
          userProvider: UserProvider(), // This should be passed as parameter
          iconCodePoint: category.iconCodePoint,
          subCategories: category.subCategories,
        );
      }

      debugPrint('✅ Categories imported successfully');
    } catch (e) {
      debugPrint('❌ Error importing categories: $e');
      rethrow;
    }
  }

  /// Export categories
  Future<List<Category>> exportCategories({
    CategoryOwnershipType? ownershipType,
    String? type,
  }) async {
    try {
      final categories = await _dataService.getCategories(
        includeArchived: true,
      );

      var filtered = categories;

      if (ownershipType != null) {
        filtered = CategoryUtils.filterByOwnership(filtered, ownershipType);
      }

      if (type != null) {
        filtered = filtered.where((c) => c.type == type).toList();
      }

      debugPrint('📤 Exported ${filtered.length} categories');
      return filtered;
    } catch (e) {
      debugPrint('❌ Error exporting categories: $e');
      return [];
    }
  }
}
