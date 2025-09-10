import 'package:flutter/foundation.dart' hide Category;
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/services/data_service.dart'; // ✅ Updated import
import 'package:moneysun/data/providers/user_provider.dart';

class CategoryProvider extends ChangeNotifier {
  final DataService _dataService; // ✅ Using unified service
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

  // ============ PUBLIC METHODS ============

  /// Load all categories - uses offline-first unified service
  Future<void> loadCategories({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📂 Loading categories from unified service...');

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
