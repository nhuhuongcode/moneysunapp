import 'package:flutter/foundation.dart' hide Category;
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/providers/user_provider.dart';

class CategoryProvider extends ChangeNotifier {
  final DataService _dataService;
  final UserProvider _userProvider;

  CategoryProvider(this._dataService, this._userProvider) {
    _dataService.addListener(_onDataServiceChanged);
  }

  // ============ STATE MANAGEMENT ============
  List<Category> _categories = [];
  bool _isLoading = false;
  String? _error;
  bool _includeArchived = false;

  // ============ GETTERS ============
  List<Category> get categories => _categories;
  List<Category> get activeCategories =>
      _categories.where((c) => !c.isArchived).toList();

  List<Category> get incomeCategories => activeCategories
      .where((c) => c.type == CategoryType.income.name)
      .toList();
  List<Category> get expenseCategories => activeCategories
      .where((c) => c.type == CategoryType.expense.name)
      .toList();

  List<Category> get personalCategories => activeCategories
      .where((c) => c.ownershipType == CategoryOwnershipType.personal)
      .toList();
  List<Category> get sharedCategories => activeCategories
      .where((c) => c.ownershipType == CategoryOwnershipType.shared)
      .toList();

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;
  bool get includeArchived => _includeArchived;

  // ============ PUBLIC METHODS ============

  /// Load all categories
  Future<void> loadCategories({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📂 Loading categories...');

      final loadedCategories = await _dataService.getCategories(
        includeArchived: _includeArchived,
      );

      _categories = loadedCategories;
      _sortCategories();

      debugPrint('✅ Loaded ${_categories.length} categories');
    } catch (e) {
      _setError('Không thể tải danh mục: $e');
      debugPrint('❌ Error loading categories: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Add new category
  Future<bool> addCategory({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    int? iconCodePoint,
    Map<String, String>? subCategories,
  }) async {
    _clearError();

    try {
      debugPrint('➕ Adding category: $name ($ownershipType)');

      await _dataService.addCategory(
        name: name,
        type: type,
        ownershipType: ownershipType,
        iconCodePoint: iconCodePoint,
        subCategories: subCategories,
      );

      // Reload categories to get the new one
      await loadCategories(forceRefresh: true);

      debugPrint('✅ Category added successfully');
      return true;
    } catch (e) {
      _setError('Không thể thêm danh mục: $e');
      debugPrint('❌ Error adding category: $e');
      return false;
    }
  }

  /// Update category
  Future<bool> updateCategory(Category updatedCategory) async {
    _clearError();

    try {
      debugPrint('🔄 Updating category: ${updatedCategory.name}');

      // Note: Will implement updateCategory in UnifiedDataService
      // await _dataService.updateCategory(updatedCategory);

      // Optimistic update
      final index = _categories.indexWhere((c) => c.id == updatedCategory.id);
      if (index != -1) {
        _categories[index] = updatedCategory;
        _sortCategories();
        notifyListeners();
      }

      debugPrint('✅ Category updated successfully');
      return true;
    } catch (e) {
      _setError('Không thể cập nhật danh mục: $e');
      debugPrint('❌ Error updating category: $e');
      return false;
    }
  }

  /// Archive/unarchive category
  Future<bool> toggleCategoryArchiveStatus(Category category) async {
    final updatedCategory = category.copyWith(isArchived: !category.isArchived);
    return await updateCategory(updatedCategory);
  }

  /// Get categories by type
  List<Category> getCategoriesByType(String type) {
    return activeCategories.where((c) => c.type == type).toList();
  }

  /// Get category by ID
  Category? getCategoryById(String categoryId) {
    try {
      return _categories.firstWhere((c) => c.id == categoryId);
    } catch (e) {
      return null;
    }
  }

  /// Search categories
  List<Category> searchCategories(String query) {
    if (query.trim().isEmpty) return activeCategories;

    final lowercaseQuery = query.toLowerCase().trim();
    return activeCategories.where((category) {
      return category.name.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Get popular categories (by usage)
  List<Category> getPopularCategories({int limit = 10}) {
    final sorted = List<Category>.from(activeCategories);
    sorted.sort((a, b) => b.usageCount.compareTo(a.usageCount));
    return sorted.take(limit).toList();
  }

  /// Check if category can be edited
  bool canEditCategory(Category category) {
    final currentUserId = _userProvider.currentUser?.uid;

    if (category.ownershipType == CategoryOwnershipType.personal) {
      return category.ownerId == currentUserId;
    } else {
      // Shared categories can be edited by both partners
      return category.ownerId == _userProvider.partnershipId ||
          category.createdBy == currentUserId;
    }
  }

  /// Get category ownership label
  String getCategoryOwnershipLabel(Category category) {
    if (category.ownershipType == CategoryOwnershipType.personal) {
      return category.ownerId == _userProvider.currentUser?.uid
          ? 'Cá nhân'
          : 'Đối tác';
    } else {
      return 'Chung';
    }
  }

  /// Toggle include archived
  void toggleIncludeArchived() {
    _includeArchived = !_includeArchived;
    loadCategories(forceRefresh: true);
    debugPrint('📦 Include archived categories toggled: $_includeArchived');
  }

  // ============ PRIVATE METHODS ============

  void _onDataServiceChanged() {
    if (!_isLoading) {
      loadCategories(forceRefresh: true);
    }
  }

  void _sortCategories() {
    _categories.sort((a, b) {
      // Sort by archived status first
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }
      // Then by usage count (descending)
      if (a.usageCount != b.usageCount) {
        return b.usageCount.compareTo(a.usageCount);
      }
      // Finally by name
      return a.name.compareTo(b.name);
    });
  }

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String error) {
    _error = error;
    notifyListeners();
  }

  void _clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _dataService.removeListener(_onDataServiceChanged);
    super.dispose();
  }
}
