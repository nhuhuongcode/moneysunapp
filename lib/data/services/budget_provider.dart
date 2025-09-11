// lib/data/providers/budget_provider.dart
import 'package:flutter/foundation.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/providers/user_provider.dart';

class BudgetProvider extends ChangeNotifier {
  final DataService _dataService;
  final UserProvider _userProvider;

  BudgetProvider(this._dataService, this._userProvider) {
    _dataService.addListener(_onDataServiceChanged);
    _loadInitialData();
  }

  // ============ STATE MANAGEMENT ============
  List<Budget> _budgets = [];
  List<Budget> _filteredBudgets = [];
  bool _isLoading = false;
  String? _error;
  BudgetType? _filterType;
  String? _filterMonth;

  // ============ GETTERS ============
  List<Budget> get budgets => _filteredBudgets;
  List<Budget> get allBudgets => _budgets;
  List<Budget> get activeBudgets =>
      _budgets.where((b) => !b.isDeleted && b.isActive).toList();

  List<Budget> get personalBudgets =>
      activeBudgets.where((b) => b.budgetType == BudgetType.personal).toList();

  List<Budget> get sharedBudgets =>
      activeBudgets.where((b) => b.budgetType == BudgetType.shared).toList();

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;
  int get budgetCount => _filteredBudgets.length;

  // Filter getters
  BudgetType? get filterType => _filterType;
  String? get filterMonth => _filterMonth;
  bool get hasActiveFilters => _filterType != null || _filterMonth != null;

  // ============ PUBLIC METHODS ============

  /// Load all budgets using DataService
  Future<void> loadBudgets({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📊 Loading budgets from DataService...');

      final loadedBudgets = await _dataService.getBudgets();
      _budgets = loadedBudgets;
      _applyCurrentFilters();

      debugPrint('✅ Loaded ${_budgets.length} budgets');
    } catch (e) {
      _setError('Không thể tải ngân sách: $e');
      debugPrint('❌ Error loading budgets: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Add new budget using DataService with optimistic updates
  Future<bool> addBudget({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    BudgetType budgetType = BudgetType.personal,
    BudgetPeriod period = BudgetPeriod.monthly,
    String? ownerId,
  }) async {
    _clearError();

    // Create temporary budget for optimistic update
    final tempBudget = Budget(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      ownerId: ownerId ?? _getCurrentOwnerId(budgetType),
      month: month,
      totalAmount: totalAmount,
      categoryAmounts: categoryAmounts,
      budgetType: budgetType,
      period: period,
      createdBy: _userProvider.currentUser?.uid,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    try {
      debugPrint('➕ Adding budget: $month (${budgetType.name})');

      // Optimistic update - add to local list immediately
      _budgets.add(tempBudget);
      _applyCurrentFilters();
      notifyListeners();

      await _dataService.addBudget(
        month: month,
        totalAmount: totalAmount,
        categoryAmounts: categoryAmounts,
        budgetType: budgetType,
        period: period,
        ownerId: ownerId,
      );

      // Remove temp budget and reload from database
      _budgets.removeWhere((b) => b.id == tempBudget.id);
      await loadBudgets(forceRefresh: true);

      debugPrint('✅ Budget added successfully');
      return true;
    } catch (e) {
      // Revert optimistic update
      _budgets.removeWhere((b) => b.id == tempBudget.id);
      _applyCurrentFilters();

      _setError('Không thể thêm ngân sách: $e');
      debugPrint('❌ Error adding budget: $e');
      notifyListeners();
      return false;
    }
  }

  /// Update budget using DataService
  Future<bool> updateBudget(Budget budget) async {
    _clearError();

    try {
      debugPrint('📝 Updating budget: ${budget.id}');

      // Optimistic update
      final index = _budgets.indexWhere((b) => b.id == budget.id);
      if (index != -1) {
        _budgets[index] = budget.copyWith(updatedAt: DateTime.now());
        _applyCurrentFilters();
        notifyListeners();
      }

      await _dataService.updateBudget(budget);

      debugPrint('✅ Budget updated successfully');
      return true;
    } catch (e) {
      // Revert optimistic update if needed
      await loadBudgets(forceRefresh: true);

      _setError('Không thể cập nhật ngân sách: $e');
      debugPrint('❌ Error updating budget: $e');
      return false;
    }
  }

  /// Delete budget using DataService
  Future<bool> deleteBudget(String budgetId) async {
    _clearError();

    try {
      debugPrint('🗑️ Deleting budget: $budgetId');

      // Optimistic update
      _budgets.removeWhere((b) => b.id == budgetId);
      _applyCurrentFilters();
      notifyListeners();

      await _dataService.deleteBudget(budgetId);

      debugPrint('✅ Budget deleted successfully');
      return true;
    } catch (e) {
      // Revert optimistic update
      await loadBudgets(forceRefresh: true);

      _setError('Không thể xóa ngân sách: $e');
      debugPrint('❌ Error deleting budget: $e');
      return false;
    }
  }

  /// Set category budget amount
  Future<bool> setCategoryBudget(
    String budgetId,
    String categoryId,
    double amount,
  ) async {
    _clearError();

    try {
      debugPrint('💰 Setting category budget: $categoryId = $amount');

      await _dataService.setCategoryBudget(budgetId, categoryId, amount);
      await loadBudgets(forceRefresh: true);

      debugPrint('✅ Category budget set successfully');
      return true;
    } catch (e) {
      _setError('Không thể đặt ngân sách danh mục: $e');
      debugPrint('❌ Error setting category budget: $e');
      return false;
    }
  }

  /// Copy budget from another month
  Future<bool> copyBudgetFromMonth(
    String sourceMonth,
    String targetMonth,
    BudgetType budgetType,
  ) async {
    _clearError();

    try {
      debugPrint('📋 Copying budget from $sourceMonth to $targetMonth');

      await _dataService.copyBudgetFromMonth(
        sourceMonth,
        targetMonth,
        budgetType,
      );
      await loadBudgets(forceRefresh: true);

      debugPrint('✅ Budget copied successfully');
      return true;
    } catch (e) {
      _setError('Không thể sao chép ngân sách: $e');
      debugPrint('❌ Error copying budget: $e');
      return false;
    }
  }

  /// Get budgets stream using DataService
  Stream<List<Budget>> getBudgetsStream({
    BudgetType? budgetType,
    String? month,
  }) {
    return _dataService.getBudgetsStream(budgetType: budgetType, month: month);
  }

  /// Get budget by ID
  Budget? getBudgetById(String budgetId) {
    try {
      return _budgets.firstWhere((b) => b.id == budgetId);
    } catch (e) {
      return null;
    }
  }

  /// Get budget for specific month and type
  Budget? getBudgetForMonth(String month, BudgetType budgetType) {
    try {
      return _budgets.firstWhere(
        (b) => b.month == month && b.budgetType == budgetType && !b.isDeleted,
      );
    } catch (e) {
      return null;
    }
  }

  /// Get budget analytics for a budget
  Future<BudgetAnalytics?> getBudgetAnalytics(String budgetId) async {
    try {
      return await _dataService.getBudgetAnalytics(budgetId);
    } catch (e) {
      debugPrint('❌ Error getting budget analytics: $e');
      return null;
    }
  }

  /// Apply budget type filter
  void setBudgetTypeFilter(BudgetType? budgetType) {
    _filterType = budgetType;
    _applyCurrentFilters();
    notifyListeners();
    debugPrint('🔍 Budget type filter applied: $budgetType');
  }

  /// Apply month filter
  void setMonthFilter(String? month) {
    _filterMonth = month;
    _applyCurrentFilters();
    notifyListeners();
    debugPrint('🔍 Month filter applied: $month');
  }

  /// Clear all filters
  void clearFilters() {
    _filterType = null;
    _filterMonth = null;
    _applyCurrentFilters();
    notifyListeners();
    debugPrint('🧹 Budget filters cleared');
  }

  /// Search budgets
  List<Budget> searchBudgets(String query) {
    if (query.trim().isEmpty) return _filteredBudgets;

    final lowercaseQuery = query.toLowerCase().trim();
    return _filteredBudgets.where((budget) {
      return budget.month.toLowerCase().contains(lowercaseQuery) ||
          budget.displayName.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Check if budget can be edited by current user
  bool canEditBudget(Budget budget) {
    return BudgetValidator.canEdit(
      budget,
      _userProvider.currentUser?.uid ?? '',
    );
  }

  /// Check if budget can be deleted by current user
  bool canDeleteBudget(Budget budget) {
    return BudgetValidator.canDelete(
      budget,
      _userProvider.currentUser?.uid ?? '',
    );
  }

  /// Get budget statistics
  Map<String, dynamic> getBudgetStatistics() {
    if (_filteredBudgets.isEmpty) {
      return {
        'totalBudgets': 0,
        'totalAmount': 0.0,
        'totalUsed': 0.0,
        'averageUsage': 0.0,
        'overBudgetCount': 0,
      };
    }

    double totalAmount = 0;
    double totalUsed = 0;
    int overBudgetCount = 0;

    for (final budget in _filteredBudgets) {
      totalAmount += budget.totalAmount;
      totalUsed += budget.usedAmount;
      if (budget.usedAmount > budget.totalAmount) {
        overBudgetCount++;
      }
    }

    final averageUsage = totalAmount > 0 ? (totalUsed / totalAmount * 100) : 0;

    return {
      'totalBudgets': _filteredBudgets.length,
      'totalAmount': totalAmount,
      'totalUsed': totalUsed,
      'averageUsage': averageUsage,
      'overBudgetCount': overBudgetCount,
    };
  }

  // ============ PRIVATE METHODS ============

  void _loadInitialData() {
    if (_dataService.isInitialized) {
      loadBudgets();
    }
  }

  void _onDataServiceChanged() {
    if (!_isLoading && _dataService.isInitialized) {
      loadBudgets(forceRefresh: true);
    }
  }

  void _applyCurrentFilters() {
    _filteredBudgets = _budgets.where((budget) {
      // Type filter
      if (_filterType != null && budget.budgetType != _filterType) {
        return false;
      }

      // Month filter
      if (_filterMonth != null && budget.month != _filterMonth) {
        return false;
      }

      // Exclude deleted budgets
      if (budget.isDeleted) {
        return false;
      }

      return true;
    }).toList();

    // Sort budgets (newest first, then by type)
    _filteredBudgets.sort((a, b) {
      final monthComparison = b.month.compareTo(a.month);
      if (monthComparison != 0) return monthComparison;

      if (a.budgetType == BudgetType.shared &&
          b.budgetType == BudgetType.personal) {
        return -1;
      }
      if (a.budgetType == BudgetType.personal &&
          b.budgetType == BudgetType.shared) {
        return 1;
      }
      return 0;
    });
  }

  String _getCurrentOwnerId(BudgetType budgetType) {
    if (budgetType == BudgetType.shared &&
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
