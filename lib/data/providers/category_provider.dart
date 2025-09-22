// lib/data/providers/category_provider_fixed.dart
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/scheduler.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/providers/user_provider.dart';

class CategoryProvider extends ChangeNotifier {
  final DataService _dataService;
  final UserProvider _userProvider;

  CategoryProvider(this._dataService, this._userProvider) {
    _dataService.addListener(_onDataServiceChanged);
    _scheduleInitialLoad();
  }

  // ============ STATE MANAGEMENT ============
  List<Category> _categories = [];
  bool _isLoading = false;
  String? _error;
  bool _includeArchived = false;
  bool _isInitialized = false;
  bool _mounted = true;

  // Cache for performance
  final Map<String, Category> _categoryCache = {};
  final Map<String, List<Category>> _categoryTypeCache = {};

  // ============ GETTERS ============
  List<Category> get categories => _categories;
  List<Category> get activeCategories =>
      _categories.where((c) => !c.isArchived).toList();

  List<Category> get incomeCategories => _getCachedCategoriesByType('income');
  List<Category> get expenseCategories => _getCachedCategoriesByType('expense');

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
  bool get isInitialized => _isInitialized;
  bool get mounted => _mounted;

  // ============ ENHANCED PUBLIC METHODS ============

  /// ✅ FIXED: Safe initial load scheduling
  void _scheduleInitialLoad() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadInitialDataSafely();
    });
  }

  void _loadInitialDataSafely() {
    if (!_mounted) return;

    if (_dataService.isInitialized && !_isInitialized) {
      _isInitialized = true;
      loadCategories();
    }
  }

  /// ✅ ENHANCED: Load categories with better error handling
  Future<void> loadCategories({bool forceRefresh = false}) async {
    if (!_mounted || (_isLoading && !forceRefresh)) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📂 Loading categories from DataService...');

      final loadedCategories = await _dataService.getCategories(
        includeArchived: _includeArchived,
      );

      if (!_mounted) return;

      _categories = loadedCategories;
      _updateCache();
      _sortCategories();

      debugPrint('✅ Loaded ${_categories.length} categories');
    } catch (e) {
      if (!_mounted) return;
      _setError('Không thể tải danh mục: $e');
      debugPrint('❌ Error loading categories: $e');
    } finally {
      if (_mounted) {
        _setLoading(false);
      }
    }
  }

  /// ✅ ENHANCED: Add category with comprehensive validation
  Future<bool> addCategory({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    int? iconCodePoint,
    Map<String, String>? subCategories,
    String? ownerId,
  }) async {
    if (!_mounted) return false;

    _clearError();

    // ✅ ENHANCED: Comprehensive validation
    final validationError = _validateCategoryInput(name, type, ownershipType);
    if (validationError != null) {
      _setError(validationError);
      return false;
    }

    // ✅ ENHANCED: Check for duplicate names with better logic
    if (_isDuplicateName(name, type, ownershipType)) {
      _setError(
        'Danh mục "$name" đã tồn tại trong ${ownershipType == CategoryOwnershipType.shared ? "danh mục chung" : "danh mục cá nhân"}',
      );
      return false;
    }

    try {
      debugPrint('➕ Adding category: $name ($type, ${ownershipType.name})');

      // ✅ ENHANCED: Optimistic update with rollback capability
      final tempCategory = _createTempCategory(
        name: name,
        type: type,
        ownershipType: ownershipType,
        iconCodePoint: iconCodePoint,
        subCategories: subCategories,
        ownerId: ownerId,
      );

      // Add to local list immediately for UI responsiveness
      _categories.add(tempCategory);
      _updateCache();
      _sortCategories();
      notifyListeners();

      try {
        // Call DataService
        await _dataService.addCategory(
          name: name.trim(),
          type: type,
          ownershipType: ownershipType,
          iconCodePoint: iconCodePoint,
          subCategories: subCategories,
          ownerId: ownerId,
        );

        // ✅ ENHANCED: Remove temp and reload real data
        _categories.removeWhere((c) => c.id == tempCategory.id);
        await loadCategories(forceRefresh: true);

        debugPrint('✅ Category added successfully');
        return true;
      } catch (e) {
        // ✅ ENHANCED: Rollback optimistic update
        _categories.removeWhere((c) => c.id == tempCategory.id);
        _updateCache();
        _sortCategories();
        notifyListeners();
        throw e;
      }
    } catch (e) {
      _setError('Không thể thêm danh mục: $e');
      debugPrint('❌ Error adding category: $e');
      return false;
    }
  }

  /// ✅ ENHANCED: Update category with validation
  Future<bool> updateCategory(Category category) async {
    if (!_mounted) return false;

    _clearError();

    // ✅ ENHANCED: Validate permissions
    if (!canEditCategory(category)) {
      _setError('Bạn không có quyền chỉnh sửa danh mục này');
      return false;
    }

    try {
      debugPrint('📝 Updating category: ${category.id}');

      // ✅ ENHANCED: Optimistic update with versioning
      final oldCategory = _categories.firstWhere((c) => c.id == category.id);
      final index = _categories.indexOf(oldCategory);

      final updatedCategory = category.copyWith(
        updatedAt: DateTime.now(),
        version: category.version + 1,
      );

      _categories[index] = updatedCategory;
      _updateCache();
      _sortCategories();
      notifyListeners();

      try {
        await _dataService.updateCategory(updatedCategory);

        // Reload to get server state
        await loadCategories(forceRefresh: true);

        debugPrint('✅ Category updated successfully');
        return true;
      } catch (e) {
        // Rollback
        _categories[index] = oldCategory;
        _updateCache();
        notifyListeners();
        throw e;
      }
    } catch (e) {
      _setError('Không thể cập nhật danh mục: $e');
      debugPrint('❌ Error updating category: $e');
      return false;
    }
  }

  /// ✅ ENHANCED: Delete category with dependency checking
  Future<bool> deleteCategory(String categoryId) async {
    if (!_mounted) return false;

    _clearError();

    final category = getCategoryById(categoryId);
    if (category == null) {
      _setError('Không tìm thấy danh mục');
      return false;
    }

    if (!canDeleteCategory(category)) {
      _setError('Bạn không có quyền xóa danh mục này');
      return false;
    }

    // ✅ ENHANCED: Check for dependencies
    final hasDependencies = await _checkCategoryDependencies(categoryId);
    if (hasDependencies) {
      _setError(
        'Không thể xóa danh mục đang được sử dụng. Vui lòng archive thay thế.',
      );
      return false;
    }

    try {
      debugPrint('🗑️ Deleting category: $categoryId');

      // Optimistic removal
      final removedCategory = _categories.firstWhere((c) => c.id == categoryId);
      _categories.removeWhere((c) => c.id == categoryId);
      _updateCache();
      notifyListeners();

      try {
        await _dataService.deleteCategory(categoryId);

        debugPrint('✅ Category deleted successfully');
        return true;
      } catch (e) {
        // Rollback
        _categories.add(removedCategory);
        _updateCache();
        _sortCategories();
        notifyListeners();
        throw e;
      }
    } catch (e) {
      _setError('Không thể xóa danh mục: $e');
      debugPrint('❌ Error deleting category: $e');
      return false;
    }
  }

  /// ✅ NEW: Archive category (safer than delete)
  Future<bool> archiveCategory(String categoryId) async {
    final category = getCategoryById(categoryId);
    if (category == null) return false;

    return updateCategory(category.copyWith(isArchived: true));
  }

  /// ✅ NEW: Restore archived category
  Future<bool> restoreCategory(String categoryId) async {
    final category = getCategoryById(categoryId);
    if (category == null) return false;

    return updateCategory(category.copyWith(isArchived: false));
  }

  /// ✅ NEW: Increment usage count
  Future<void> incrementUsage(String categoryId) async {
    final category = getCategoryById(categoryId);
    if (category == null) return;

    // Update locally immediately
    final index = _categories.indexOf(category);
    if (index != -1) {
      _categories[index] = category.copyWith(
        usageCount: category.usageCount + 1,
        lastUsed: DateTime.now(),
      );
      _updateCache();
      notifyListeners();
    }

    // Update in database asynchronously
    try {
      await _dataService.incrementCategoryUsage(categoryId);
    } catch (e) {
      debugPrint('❌ Error incrementing category usage: $e');
    }
  }

  /// ✅ ENHANCED: Get categories stream
  Stream<List<Category>> getCategoriesStream({bool includeArchived = false}) {
    return _dataService.getCategoriesStream(includeArchived: includeArchived);
  }

  /// ✅ ENHANCED: Get category by ID with cache
  Category? getCategoryById(String categoryId) {
    return _categoryCache[categoryId];
  }

  /// ✅ ENHANCED: Search categories with relevance scoring
  List<Category> searchCategories(String query) {
    if (query.trim().isEmpty) return activeCategories;

    final lowercaseQuery = query.toLowerCase().trim();
    final results = <Category>[];
    final scores = <Category, int>{};

    for (final category in activeCategories) {
      int score = 0;

      // Exact name match gets highest score
      if (category.name.toLowerCase() == lowercaseQuery) {
        score += 100;
      }
      // Name starts with query
      else if (category.name.toLowerCase().startsWith(lowercaseQuery)) {
        score += 50;
      }
      // Name contains query
      else if (category.name.toLowerCase().contains(lowercaseQuery)) {
        score += 25;
      }

      // Sub-category matches
      for (final subCategory in category.subCategories.values) {
        if (subCategory.toLowerCase().contains(lowercaseQuery)) {
          score += 10;
        }
      }

      // Usage count boost
      score += (category.usageCount * 0.1).round();

      if (score > 0) {
        results.add(category);
        scores[category] = score;
      }
    }

    // Sort by relevance score
    results.sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return results;
  }

  /// ✅ ENHANCED: Check if category can be edited
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

  /// ✅ ENHANCED: Check if category can be deleted
  bool canDeleteCategory(Category category) {
    return canEditCategory(category) && category.usageCount == 0;
  }

  /// ✅ NEW: Get category suggestions based on description
  List<Category> getCategorySuggestions(String description, String type) {
    if (description.trim().isEmpty) return [];

    final relevantCategories = _getCachedCategoriesByType(type);
    final suggestions = <Category>[];
    final scores = <Category, int>{};

    for (final category in relevantCategories) {
      int score = 0;

      // Check if description contains category name or sub-categories
      final desc = description.toLowerCase();

      if (desc.contains(category.name.toLowerCase())) {
        score += 50;
      }

      for (final subCategory in category.subCategories.values) {
        if (desc.contains(subCategory.toLowerCase())) {
          score += 30;
        }
      }

      // Boost frequently used categories
      score += category.usageCount;

      if (score > 0) {
        suggestions.add(category);
        scores[category] = score;
      }
    }

    suggestions.sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return suggestions.take(5).toList();
  }

  /// ✅ NEW: Toggle include archived
  void toggleIncludeArchived() {
    _includeArchived = !_includeArchived;
    loadCategories(forceRefresh: true);
    debugPrint('📦 Include archived categories toggled: $_includeArchived');
  }

  /// ✅ NEW: Get category statistics
  Map<String, dynamic> getCategoryStatistics() {
    final stats = {
      'total': _categories.length,
      'active': activeCategories.length,
      'archived': _categories.where((c) => c.isArchived).length,
      'personal': personalCategories.length,
      'shared': sharedCategories.length,
      'income': incomeCategories.length,
      'expense': expenseCategories.length,
      'mostUsed': _getMostUsedCategory(),
      'leastUsed': _getLeastUsedCategory(),
      'averageUsage': _getAverageUsage(),
    };

    return stats;
  }

  // ============ PRIVATE HELPER METHODS ============

  /// ✅ FIXED: Safe data service change handling
  void _onDataServiceChanged() {
    if (!_mounted) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_mounted && !_isLoading && _dataService.isInitialized) {
        loadCategories(forceRefresh: true);
      }
    });
  }

  String? _validateCategoryInput(
    String name,
    String type,
    CategoryOwnershipType ownershipType,
  ) {
    if (name.trim().isEmpty) {
      return 'Tên danh mục không được để trống';
    }

    if (name.trim().length > 50) {
      return 'Tên danh mục không được dài quá 50 ký tự';
    }

    if (!['income', 'expense'].contains(type)) {
      return 'Loại danh mục không hợp lệ';
    }

    if (ownershipType == CategoryOwnershipType.shared &&
        !_userProvider.hasPartner) {
      return 'Không thể tạo danh mục chung khi chưa có đối tác';
    }

    return null;
  }

  bool _isDuplicateName(
    String name,
    String type,
    CategoryOwnershipType ownershipType,
  ) {
    return _categories.any(
      (c) =>
          c.name.toLowerCase() == name.trim().toLowerCase() &&
          c.type == type &&
          c.ownershipType == ownershipType &&
          !c.isArchived,
    );
  }

  Category _createTempCategory({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    int? iconCodePoint,
    Map<String, String>? subCategories,
    String? ownerId,
  }) {
    return Category(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      ownerId: ownerId ?? _getCurrentOwnerId(ownershipType),
      type: type,
      iconCodePoint: iconCodePoint,
      subCategories: subCategories ?? {},
      ownershipType: ownershipType,
      createdBy: _userProvider.currentUser?.uid,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<bool> _checkCategoryDependencies(String categoryId) async {
    try {
      // Check if category is used in any transactions
      final transactions = await _dataService.getTransactions(
        categoryId: categoryId,
        limit: 1,
      );

      if (transactions.isNotEmpty) {
        return true;
      }

      // Check if category is used in any budgets
      final budgets = await _dataService.getBudgets();
      for (final budget in budgets) {
        if (budget.categoryAmounts.containsKey(categoryId)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      debugPrint('❌ Error checking category dependencies: $e');
      return true; // Assume it has dependencies to be safe
    }
  }

  void _updateCache() {
    _categoryCache.clear();
    _categoryTypeCache.clear();

    for (final category in _categories) {
      _categoryCache[category.id] = category;
    }
  }

  List<Category> _getCachedCategoriesByType(String type) {
    if (!_categoryTypeCache.containsKey(type)) {
      _categoryTypeCache[type] = activeCategories
          .where((c) => c.type == type)
          .toList();
    }
    return _categoryTypeCache[type]!;
  }

  void _sortCategories() {
    _categories.sort((a, b) {
      // Archived categories go to bottom
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }

      // Then by usage count (descending)
      if (a.usageCount != b.usageCount) {
        return b.usageCount.compareTo(a.usageCount);
      }

      // Then by last used (most recent first)
      if (a.lastUsed != null && b.lastUsed != null) {
        return b.lastUsed!.compareTo(a.lastUsed!);
      }

      if (a.lastUsed != null) return -1;
      if (b.lastUsed != null) return 1;

      // Finally by name
      return a.name.compareTo(b.name);
    });
  }

  String _getCurrentOwnerId(CategoryOwnershipType ownershipType) {
    if (ownershipType == CategoryOwnershipType.shared &&
        _userProvider.partnershipId != null) {
      return _userProvider.partnershipId!;
    }
    return _userProvider.currentUser?.uid ?? '';
  }

  Category? _getMostUsedCategory() {
    if (activeCategories.isEmpty) return null;

    return activeCategories.reduce(
      (a, b) => a.usageCount > b.usageCount ? a : b,
    );
  }

  Category? _getLeastUsedCategory() {
    if (activeCategories.isEmpty) return null;

    return activeCategories.reduce(
      (a, b) => a.usageCount < b.usageCount ? a : b,
    );
  }

  double _getAverageUsage() {
    if (activeCategories.isEmpty) return 0.0;

    final totalUsage = activeCategories.fold(0, (sum, c) => sum + c.usageCount);
    return totalUsage / activeCategories.length;
  }

  void _setLoading(bool loading) {
    if (!_mounted || _isLoading == loading) return;

    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    if (!_mounted) return;

    _error = error;
    notifyListeners();
  }

  void _clearError() {
    if (!_mounted || _error == null) return;

    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _mounted = false;
    _dataService.removeListener(_onDataServiceChanged);
    _categoryCache.clear();
    _categoryTypeCache.clear();
    super.dispose();
  }
}
