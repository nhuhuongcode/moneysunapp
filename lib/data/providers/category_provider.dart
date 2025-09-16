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
    // ✅ Fix: Defer initial load to avoid setState during build
    _scheduleInitialLoad();
  }

  // ============ STATE MANAGEMENT ============
  List<Category> _categories = [];
  bool _isLoading = false;
  String? _error;
  bool _includeArchived = false;
  bool _isInitialized = false;

  // ============ GETTERS ============
  List<Category> get categories => _categories;
  List<Category> get activeCategories =>
      _categories.where((c) => !c.isArchived).toList();

  List<Category> get incomeCategories =>
      activeCategories.where((c) => c.type == 'income').toList();
  List<Category> get expenseCategories =>
      activeCategories.where((c) => c.type == 'expense').toList();

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

  // ============ PUBLIC METHODS ============

  /// ✅ Fix: Safe initial load scheduling
  void _scheduleInitialLoad() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadInitialDataSafely();
    });
  }

  void _loadInitialDataSafely() {
    if (_dataService.isInitialized && !_isInitialized) {
      _isInitialized = true;
      loadCategories();
    }
  }

  /// Load all categories using DataService
  Future<void> loadCategories({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📂 Loading categories from DataService...');

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

  Future<bool> addCategory({
    required String name,
    required String type,
    required CategoryOwnershipType ownershipType,
    int? iconCodePoint,
    Map<String, String>? subCategories,
    String? ownerId,
  }) async {
    _clearError();

    // Validation
    if (name.trim().isEmpty) {
      _setError('Tên danh mục không được để trống');
      return false;
    }

    if (!['income', 'expense'].contains(type)) {
      _setError('Loại danh mục không hợp lệ');
      return false;
    }

    // Check for duplicate names
    final existingCategory = _categories
        .where(
          (c) =>
              c.name.toLowerCase() == name.trim().toLowerCase() &&
              c.type == type &&
              c.ownershipType == ownershipType &&
              !c.isArchived,
        )
        .firstOrNull;

    if (existingCategory != null) {
      _setError('Danh mục "$name" đã tồn tại');
      return false;
    }

    try {
      debugPrint('➕ Adding category: $name ($type, ${ownershipType.name})');

      // ✅ FIXED: Use real DataService method instead of simulation
      await _dataService.addCategory(
        name: name.trim(),
        type: type,
        ownershipType: ownershipType,
        iconCodePoint: iconCodePoint,
        subCategories: subCategories,
        ownerId: ownerId,
      );

      // Reload categories from database
      await loadCategories(forceRefresh: true);

      debugPrint('✅ Category added successfully');
      return true;
    } catch (e) {
      _setError('Không thể thêm danh mục: $e');
      debugPrint('❌ Error adding category: $e');
      return false;
    }
  }

  /// ✅ FIXED: Update category with real implementation
  Future<bool> updateCategory(Category category) async {
    _clearError();

    try {
      debugPrint('📝 Updating category: ${category.id}');

      await _dataService.updateCategory(category);
      await loadCategories(forceRefresh: true);

      debugPrint('✅ Category updated successfully');
      return true;
    } catch (e) {
      _setError('Không thể cập nhật danh mục: $e');
      debugPrint('❌ Error updating category: $e');
      return false;
    }
  }

  /// ✅ FIXED: Delete category with real implementation
  Future<bool> deleteCategory(String categoryId) async {
    _clearError();

    try {
      debugPrint('🗑️ Deleting category: $categoryId');

      await _dataService.deleteCategory(categoryId);
      await loadCategories(forceRefresh: true);

      debugPrint('✅ Category deleted successfully');
      return true;
    } catch (e) {
      _setError('Không thể xóa danh mục: $e');
      debugPrint('❌ Error deleting category: $e');
      return false;
    }
  }

  /// Get categories stream using DataService
  Stream<List<Category>> getCategoriesStream({bool includeArchived = false}) {
    return _dataService.getCategoriesStream(includeArchived: includeArchived);
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
      return category.name.toLowerCase().contains(lowercaseQuery) ||
          category.subCategories.values.any(
            (sub) => sub.toLowerCase().contains(lowercaseQuery),
          );
    }).toList();
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

  /// ✅ Fix: Safe data service change handling
  void _onDataServiceChanged() {
    // Use postFrameCallback to avoid setState during build
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_isLoading && _dataService.isInitialized) {
        loadCategories(forceRefresh: true);
      }
    });
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

  String _getCurrentOwnerId(CategoryOwnershipType ownershipType) {
    if (ownershipType == CategoryOwnershipType.shared &&
        _userProvider.partnershipId != null) {
      return _userProvider.partnershipId!;
    }
    return _userProvider.currentUser?.uid ?? '';
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
