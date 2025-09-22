// lib/data/providers/budget_provider_enhanced.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';

class BudgetProvider extends ChangeNotifier {
  final DataService _dataService;
  final UserProvider _userProvider;
  final TransactionProvider _transactionProvider;
  final CategoryProvider _categoryProvider;

  BudgetProvider(
    this._dataService,
    this._userProvider,
    this._transactionProvider,
    this._categoryProvider,
  ) {
    _dataService.addListener(_onDataServiceChanged);
    _scheduleInitialLoad();
  }

  // ============ STATE MANAGEMENT ============
  List<Budget> _budgets = [];
  List<Budget> _filteredBudgets = [];
  bool _isLoading = false;
  String? _error;
  BudgetType? _filterType;
  String? _filterMonth;
  bool _isInitialized = false;
  bool _mounted = true;

  // ✅ NEW: Analytics cache for performance
  final Map<String, BudgetAnalytics> _analyticsCache = {};
  final Map<String, DateTime> _analyticsCacheTime = {};

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
  bool get isInitialized => _isInitialized;
  bool get mounted => _mounted;

  // Filter getters
  BudgetType? get filterType => _filterType;
  String? get filterMonth => _filterMonth;
  bool get hasActiveFilters => _filterType != null || _filterMonth != null;

  // ✅ NEW: Quick access getters
  Budget? get currentPersonalBudget =>
      getCurrentMonthBudget(BudgetType.personal);
  Budget? get currentSharedBudget => getCurrentMonthBudget(BudgetType.shared);

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
      loadBudgets();
    }
  }

  /// ✅ ENHANCED: Load budgets with better filtering
  Future<void> loadBudgets({bool forceRefresh = false}) async {
    if (!_mounted || (_isLoading && !forceRefresh)) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📊 Loading budgets from DataService...');

      final loadedBudgets = await _dataService.getBudgets();

      if (!_mounted) return;

      _budgets = loadedBudgets;
      _applyCurrentFilters();

      // ✅ NEW: Clear analytics cache when budgets change
      if (forceRefresh) {
        _clearAnalyticsCache();
      }

      debugPrint('✅ Loaded ${_budgets.length} budgets');
    } catch (e) {
      if (!_mounted) return;
      _setError('Không thể tải ngân sách: $e');
      debugPrint('❌ Error loading budgets: $e');
    } finally {
      if (_mounted) {
        _setLoading(false);
      }
    }
  }

  /// ✅ ENHANCED: Add budget with comprehensive validation
  Future<bool> addBudget({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    BudgetType budgetType = BudgetType.personal,
    BudgetPeriod period = BudgetPeriod.monthly,
    String? ownerId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    if (!_mounted) return false;

    _clearError();

    // ✅ ENHANCED: Comprehensive validation
    final validationError = await _validateBudgetInput(
      month,
      totalAmount,
      categoryAmounts,
      budgetType,
    );
    if (validationError != null) {
      _setError(validationError);
      return false;
    }

    // Check for existing budget
    final existing = getBudgetForMonth(month, budgetType);
    if (existing != null && !existing.isDeleted) {
      _setError(
        'Ngân sách ${budgetType == BudgetType.shared ? "chung" : "cá nhân"} cho tháng $month đã tồn tại',
      );
      return false;
    }

    try {
      debugPrint('➕ Adding budget: $month (${budgetType.name})');

      // ✅ ENHANCED: Create optimistic update
      final tempBudget = _createTempBudget(
        month: month,
        totalAmount: totalAmount,
        categoryAmounts: categoryAmounts,
        budgetType: budgetType,
        period: period,
        ownerId: ownerId,
        startDate: startDate,
        endDate: endDate,
      );

      // Add to local list immediately
      _budgets.add(tempBudget);
      _applyCurrentFilters();
      notifyListeners();

      try {
        await _dataService.addBudget(
          month: month,
          totalAmount: totalAmount,
          categoryAmounts: categoryAmounts,
          budgetType: budgetType,
          period: period,
          ownerId: ownerId,
          startDate: startDate,
          endDate: endDate,
        );

        // Remove temp and reload real data
        _budgets.removeWhere((b) => b.id == tempBudget.id);
        await loadBudgets(forceRefresh: true);

        debugPrint('✅ Budget added successfully');
        return true;
      } catch (e) {
        // Rollback optimistic update
        _budgets.removeWhere((b) => b.id == tempBudget.id);
        _applyCurrentFilters();
        notifyListeners();
        throw e;
      }
    } catch (e) {
      _setError('Không thể thêm ngân sách: $e');
      debugPrint('❌ Error adding budget: $e');
      return false;
    }
  }

  /// ✅ ENHANCED: Update budget with validation
  Future<bool> updateBudget(Budget budget) async {
    if (!_mounted) return false;

    _clearError();

    // Validate permissions
    if (!canEditBudget(budget)) {
      _setError('Bạn không có quyền chỉnh sửa ngân sách này');
      return false;
    }

    try {
      debugPrint('📝 Updating budget: ${budget.id}');

      // Optimistic update
      final oldBudget = _budgets.firstWhere((b) => b.id == budget.id);
      final index = _budgets.indexOf(oldBudget);

      final updatedBudget = budget.copyWith(
        updatedAt: DateTime.now(),
        version: budget.version + 1,
      );

      _budgets[index] = updatedBudget;
      _applyCurrentFilters();

      // Clear analytics cache for this budget
      _clearBudgetAnalyticsCache(budget.id);
      notifyListeners();

      try {
        await _dataService.updateBudget(updatedBudget);

        // Reload to get server state
        await loadBudgets(forceRefresh: true);

        debugPrint('✅ Budget updated successfully');
        return true;
      } catch (e) {
        // Rollback
        _budgets[index] = oldBudget;
        _applyCurrentFilters();
        notifyListeners();
        throw e;
      }
    } catch (e) {
      _setError('Không thể cập nhật ngân sách: $e');
      debugPrint('❌ Error updating budget: $e');
      return false;
    }
  }

  /// ✅ ENHANCED: Delete budget with dependency checking
  Future<bool> deleteBudget(String budgetId) async {
    if (!_mounted) return false;

    _clearError();

    final budget = getBudgetById(budgetId);
    if (budget == null) {
      _setError('Không tìm thấy ngân sách');
      return false;
    }

    if (!canDeleteBudget(budget)) {
      _setError('Bạn không có quyền xóa ngân sách này');
      return false;
    }

    try {
      debugPrint('🗑️ Deleting budget: $budgetId');

      // Optimistic removal
      final removedBudget = _budgets.firstWhere((b) => b.id == budgetId);
      _budgets.removeWhere((b) => b.id == budgetId);
      _applyCurrentFilters();
      _clearBudgetAnalyticsCache(budgetId);
      notifyListeners();

      try {
        await _dataService.deleteBudget(budgetId);

        debugPrint('✅ Budget deleted successfully');
        return true;
      } catch (e) {
        // Rollback
        _budgets.add(removedBudget);
        _applyCurrentFilters();
        notifyListeners();
        throw e;
      }
    } catch (e) {
      _setError('Không thể xóa ngân sách: $e');
      debugPrint('❌ Error deleting budget: $e');
      return false;
    }
  }

  /// ✅ ENHANCED: Set category budget with validation
  Future<bool> setCategoryBudget(
    String budgetId,
    String categoryId,
    double amount,
  ) async {
    if (!_mounted) return false;

    _clearError();

    final budget = getBudgetById(budgetId);
    if (budget == null) {
      _setError('Không tìm thấy ngân sách');
      return false;
    }

    if (!canEditBudget(budget)) {
      _setError('Bạn không có quyền chỉnh sửa ngân sách này');
      return false;
    }

    // Validate category exists and is appropriate type
    final category = _categoryProvider.getCategoryById(categoryId);
    if (category == null) {
      _setError('Không tìm thấy danh mục');
      return false;
    }

    if (category.type != 'expense') {
      _setError('Chỉ có thể đặt ngân sách cho danh mục chi tiêu');
      return false;
    }

    if (amount < 0) {
      _setError('Số tiền ngân sách không được âm');
      return false;
    }

    try {
      debugPrint('💰 Setting category budget: $categoryId = $amount');

      // Update category amounts
      final updatedCategoryAmounts = Map<String, double>.from(
        budget.categoryAmounts,
      );

      if (amount > 0) {
        updatedCategoryAmounts[categoryId] = amount;
      } else {
        updatedCategoryAmounts.remove(categoryId);
      }

      // Calculate new total
      final newTotal = updatedCategoryAmounts.values.fold(
        0.0,
        (sum, val) => sum + val,
      );

      final updatedBudget = budget.copyWith(
        categoryAmounts: updatedCategoryAmounts,
        totalAmount: newTotal,
        updatedAt: DateTime.now(),
        version: budget.version + 1,
      );

      return await updateBudget(updatedBudget);
    } catch (e) {
      _setError('Không thể đặt ngân sách danh mục: $e');
      debugPrint('❌ Error setting category budget: $e');
      return false;
    }
  }

  /// ✅ NEW: Get real-time budget analytics
  Future<BudgetAnalytics?> getBudgetAnalytics(
    String budgetId, {
    bool useCache = true,
  }) async {
    if (!_mounted) return null;

    // Check cache first
    if (useCache && _analyticsCache.containsKey(budgetId)) {
      final cacheTime = _analyticsCacheTime[budgetId];
      if (cacheTime != null &&
          DateTime.now().difference(cacheTime).inMinutes < 5) {
        return _analyticsCache[budgetId];
      }
    }

    try {
      final budget = getBudgetById(budgetId);
      if (budget == null) return null;

      // Get transactions for budget period
      final (startDate, endDate) = budget.effectiveDateRange;
      final transactions = await _dataService.getTransactions(
        startDate: startDate,
        endDate: endDate,
      );

      // Filter transactions based on budget type
      final relevantTransactions = _filterTransactionsByBudgetType(
        transactions,
        budget.budgetType,
      );

      // Calculate analytics
      final analytics = await _calculateBudgetAnalytics(
        budget,
        relevantTransactions,
      );

      // Cache the result
      _analyticsCache[budgetId] = analytics;
      _analyticsCacheTime[budgetId] = DateTime.now();

      return analytics;
    } catch (e) {
      debugPrint('❌ Error calculating budget analytics: $e');
      return null;
    }
  }

  /// ✅ NEW: Copy budget from previous month
  Future<bool> copyBudgetFromMonth(
    String sourceMonth,
    String targetMonth,
    BudgetType budgetType,
  ) async {
    if (!_mounted) return false;

    _clearError();

    try {
      debugPrint('📋 Copying budget from $sourceMonth to $targetMonth');

      final sourceBudget = getBudgetForMonth(sourceMonth, budgetType);
      if (sourceBudget == null) {
        _setError('Không tìm thấy ngân sách nguồn cho tháng $sourceMonth');
        return false;
      }

      // Check if target month already has budget
      final existingBudget = getBudgetForMonth(targetMonth, budgetType);
      if (existingBudget != null && !existingBudget.isDeleted) {
        _setError(
          'Tháng $targetMonth đã có ngân sách ${budgetType == BudgetType.shared ? "chung" : "cá nhân"}',
        );
        return false;
      }

      return await addBudget(
        month: targetMonth,
        totalAmount: sourceBudget.totalAmount,
        categoryAmounts: Map<String, double>.from(sourceBudget.categoryAmounts),
        budgetType: budgetType,
        period: sourceBudget.period,
      );
    } catch (e) {
      _setError('Không thể sao chép ngân sách: $e');
      debugPrint('❌ Error copying budget: $e');
      return false;
    }
  }

  /// ✅ NEW: Get budget for current month
  Budget? getCurrentMonthBudget(BudgetType budgetType) {
    final currentMonth = DateTime.now().toIso8601String().substring(
      0,
      7,
    ); // YYYY-MM
    return getBudgetForMonth(currentMonth, budgetType);
  }

  /// ✅ ENHANCED: Get budgets stream
  Stream<List<Budget>> getBudgetsStream({
    BudgetType? budgetType,
    String? month,
  }) {
    return _dataService.getBudgetsStream(budgetType: budgetType, month: month);
  }

  /// ✅ ENHANCED: Get budget by ID
  Budget? getBudgetById(String budgetId) {
    try {
      return _budgets.firstWhere((b) => b.id == budgetId);
    } catch (e) {
      return null;
    }
  }

  /// ✅ ENHANCED: Get budget for specific month and type
  Budget? getBudgetForMonth(String month, BudgetType budgetType) {
    try {
      return _budgets.firstWhere(
        (b) => b.month == month && b.budgetType == budgetType && !b.isDeleted,
      );
    } catch (e) {
      return null;
    }
  }

  /// ✅ NEW: Get budget spending summary
  Future<Map<String, dynamic>> getBudgetSpendingSummary(String budgetId) async {
    final analytics = await getBudgetAnalytics(budgetId);
    if (analytics == null) return {};

    return {
      'totalBudget': analytics.totalBudget,
      'totalSpent': analytics.totalSpent,
      'totalRemaining': analytics.totalRemaining,
      'spentPercentage': analytics.spentPercentage,
      'isOverBudget': analytics.isOverBudget,
      'isNearLimit': analytics.isNearLimit,
      'categoryBreakdown': analytics.categoryAnalytics.map(
        (key, value) => MapEntry(key, {
          'budgetAmount': value.budgetAmount,
          'spentAmount': value.spentAmount,
          'remainingAmount': value.remainingAmount,
          'spentPercentage': value.spentPercentage,
          'isOverBudget': value.isOverBudget,
        }),
      ),
      'alerts': analytics.alerts
          .map(
            (alert) => {
              'type': alert.type.toString(),
              'severity': alert.severity.toString(),
              'message': alert.message,
              'categoryId': alert.categoryId,
            },
          )
          .toList(),
    };
  }

  /// ✅ NEW: Get monthly budget comparison
  Future<Map<String, dynamic>> getMonthlyComparison(
    String currentMonth,
    String previousMonth,
    BudgetType budgetType,
  ) async {
    final currentBudget = getBudgetForMonth(currentMonth, budgetType);
    final previousBudget = getBudgetForMonth(previousMonth, budgetType);

    if (currentBudget == null && previousBudget == null) {
      return {};
    }

    final currentAnalytics = currentBudget != null
        ? await getBudgetAnalytics(currentBudget.id)
        : null;
    final previousAnalytics = previousBudget != null
        ? await getBudgetAnalytics(previousBudget.id)
        : null;

    return {
      'current': {
        'month': currentMonth,
        'budget': currentBudget?.totalAmount ?? 0,
        'spent': currentAnalytics?.totalSpent ?? 0,
        'remaining': currentAnalytics?.totalRemaining ?? 0,
        'spentPercentage': currentAnalytics?.spentPercentage ?? 0,
      },
      'previous': {
        'month': previousMonth,
        'budget': previousBudget?.totalAmount ?? 0,
        'spent': previousAnalytics?.totalSpent ?? 0,
        'remaining': previousAnalytics?.totalRemaining ?? 0,
        'spentPercentage': previousAnalytics?.spentPercentage ?? 0,
      },
      'comparison': _calculateComparison(currentAnalytics, previousAnalytics),
    };
  }

  /// ✅ NEW: Apply budget type filter
  void setBudgetTypeFilter(BudgetType? budgetType) {
    if (_filterType != budgetType) {
      _filterType = budgetType;
      _applyCurrentFilters();
      notifyListeners();
      debugPrint('🔍 Budget type filter applied: $budgetType');
    }
  }

  /// ✅ NEW: Apply month filter
  void setMonthFilter(String? month) {
    if (_filterMonth != month) {
      _filterMonth = month;
      _applyCurrentFilters();
      notifyListeners();
      debugPrint('🔍 Month filter applied: $month');
    }
  }

  /// ✅ NEW: Clear all filters
  void clearFilters() {
    bool changed = false;

    if (_filterType != null) {
      _filterType = null;
      changed = true;
    }

    if (_filterMonth != null) {
      _filterMonth = null;
      changed = true;
    }

    if (changed) {
      _applyCurrentFilters();
      notifyListeners();
      debugPrint('🧹 Budget filters cleared');
    }
  }

  /// ✅ NEW: Search budgets
  List<Budget> searchBudgets(String query) {
    if (query.trim().isEmpty) return _filteredBudgets;

    final lowercaseQuery = query.toLowerCase().trim();
    return _filteredBudgets.where((budget) {
      return budget.month.toLowerCase().contains(lowercaseQuery) ||
          budget.displayName.toLowerCase().contains(lowercaseQuery) ||
          budget.budgetType.name.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// ✅ ENHANCED: Check if budget can be edited
  bool canEditBudget(Budget budget) {
    final currentUserId = _userProvider.currentUser?.uid ?? '';

    if (budget.budgetType == BudgetType.personal) {
      return budget.ownerId == currentUserId;
    } else {
      // Shared budgets can be edited by both partners
      return budget.ownerId == _userProvider.partnershipId ||
          budget.createdBy == currentUserId;
    }
  }

  /// ✅ ENHANCED: Check if budget can be deleted
  bool canDeleteBudget(Budget budget) {
    return canEditBudget(budget);
  }

  /// ✅ NEW: Get budget statistics
  Map<String, dynamic> getBudgetStatistics() {
    if (_filteredBudgets.isEmpty) {
      return {
        'totalBudgets': 0,
        'totalAmount': 0.0,
        'averageAmount': 0.0,
        'personalBudgets': 0,
        'sharedBudgets': 0,
        'activeBudgets': 0,
      };
    }

    final totalAmount = _filteredBudgets.fold(
      0.0,
      (sum, b) => sum + b.totalAmount,
    );
    final personalCount = _filteredBudgets
        .where((b) => b.budgetType == BudgetType.personal)
        .length;
    final sharedCount = _filteredBudgets
        .where((b) => b.budgetType == BudgetType.shared)
        .length;
    final activeCount = _filteredBudgets.where((b) => b.isActive).length;

    return {
      'totalBudgets': _filteredBudgets.length,
      'totalAmount': totalAmount,
      'averageAmount': totalAmount / _filteredBudgets.length,
      'personalBudgets': personalCount,
      'sharedBudgets': sharedCount,
      'activeBudgets': activeCount,
    };
  }

  // ============ PRIVATE HELPER METHODS ============

  /// ✅ FIXED: Safe data service change handling
  void _onDataServiceChanged() {
    if (!_mounted) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_mounted && !_isLoading && _dataService.isInitialized) {
        loadBudgets(forceRefresh: true);
      }
    });
  }

  Future<String?> _validateBudgetInput(
    String month,
    double totalAmount,
    Map<String, double> categoryAmounts,
    BudgetType budgetType,
  ) async {
    // Basic validation
    if (month.trim().isEmpty) {
      return 'Tháng không được để trống';
    }

    if (totalAmount <= 0) {
      return 'Tổng ngân sách phải lớn hơn 0';
    }

    if (categoryAmounts.isEmpty) {
      return 'Phải có ít nhất một danh mục ngân sách';
    }

    // Validate month format (YYYY-MM)
    if (!RegExp(r'^\d{4}-\d{2}').hasMatch(month)) {
      return 'Định dạng tháng không hợp lệ (phải là YYYY-MM)';
    }

    // Validate category amounts
    for (final entry in categoryAmounts.entries) {
      if (entry.value < 0) {
        return 'Số tiền ngân sách danh mục không được âm';
      }

      // Check if category exists
      final category = _categoryProvider.getCategoryById(entry.key);
      if (category == null) {
        return 'Danh mục không tồn tại: ${entry.key}';
      }

      // Check if category type is appropriate
      if (category.type != 'expense') {
        return 'Chỉ có thể đặt ngân sách cho danh mục chi tiêu';
      }
    }

    // Check partnership requirements
    if (budgetType == BudgetType.shared && !_userProvider.hasPartner) {
      return 'Không thể tạo ngân sách chung khi chưa có đối tác';
    }

    return null;
  }

  Budget _createTempBudget({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    required BudgetType budgetType,
    required BudgetPeriod period,
    String? ownerId,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return Budget(
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
      startDate: startDate,
      endDate: endDate,
      isActive: true,
      isDeleted: false,
      version: 1,
    );
  }

  Future<BudgetAnalytics> _calculateBudgetAnalytics(
    Budget budget,
    List<TransactionModel> transactions,
  ) async {
    double totalSpent = 0;
    final categorySpending = <String, double>{};
    final categoryAnalytics = <String, CategoryBudgetAnalytics>{};

    // Calculate spending by category
    for (final transaction in transactions) {
      if (transaction.type == TransactionType.expense &&
          transaction.categoryId != null &&
          budget.categoryAmounts.containsKey(transaction.categoryId)) {
        totalSpent += transaction.amount;
        categorySpending[transaction.categoryId!] =
            (categorySpending[transaction.categoryId!] ?? 0) +
            transaction.amount;
      }
    }

    // Build category analytics
    for (final entry in budget.categoryAmounts.entries) {
      final categoryId = entry.key;
      final budgetAmount = entry.value;
      final spentAmount = categorySpending[categoryId] ?? 0;
      final remainingAmount = budgetAmount - spentAmount;
      final spentPercentage = budgetAmount > 0
          ? (spentAmount / budgetAmount * 100)
          : 0.0;

      final category = _categoryProvider.getCategoryById(categoryId);

      categoryAnalytics[categoryId] = CategoryBudgetAnalytics(
        categoryId: categoryId,
        categoryName: category?.name ?? 'Danh mục không tồn tại',
        budgetAmount: budgetAmount,
        spentAmount: spentAmount,
        remainingAmount: remainingAmount,
        spentPercentage: spentPercentage,
        isOverBudget: spentAmount > budgetAmount,
        isNearLimit: spentPercentage >= 80,
        dailySpending: _calculateDailySpending(categoryId, transactions),
        weeklyAverage: _calculateWeeklyAverage(categoryId, transactions),
        projectedSpending: _calculateProjectedSpending(
          categoryId,
          transactions,
          budget,
        ),
      );
    }

    final totalRemaining = budget.totalAmount - totalSpent;
    final spentPercentage = budget.totalAmount > 0
        ? (totalSpent / budget.totalAmount * 100)
        : 0.0;

    return BudgetAnalytics(
      budgetId: budget.id,
      totalBudget: budget.totalAmount,
      totalSpent: totalSpent,
      totalRemaining: totalRemaining,
      spentPercentage: spentPercentage,
      isOverBudget: totalSpent > budget.totalAmount,
      isNearLimit: spentPercentage >= 80,
      categoryAnalytics: categoryAnalytics,
      alerts: _generateBudgetAlerts(categoryAnalytics, spentPercentage, budget),
      trend: _calculateBudgetTrend(budget, transactions),
      lastUpdated: DateTime.now(),
    );
  }

  List<TransactionModel> _filterTransactionsByBudgetType(
    List<TransactionModel> transactions,
    BudgetType budgetType,
  ) {
    if (budgetType == BudgetType.personal) {
      // Filter personal transactions based on user ID and wallet ownership
      return transactions
          .where((t) => t.userId == _userProvider.currentUser?.uid)
          .toList();
    } else {
      // For shared budgets, include transactions from both partners
      // This would need wallet ownership information
      return transactions; // Simplified for now
    }
  }

  List<BudgetAlert> _generateBudgetAlerts(
    Map<String, CategoryBudgetAnalytics> categoryAnalytics,
    double totalSpentPercentage,
    Budget budget,
  ) {
    final alerts = <BudgetAlert>[];

    // Overall budget alerts
    if (totalSpentPercentage > 100) {
      alerts.add(
        BudgetAlert(
          id: '${budget.id}_over_budget',
          type: BudgetAlertType.overBudget,
          severity: BudgetAlertSeverity.high,
          message:
              'Bạn đã vượt ngân sách ${(totalSpentPercentage - 100).toStringAsFixed(1)}%',
          budgetId: budget.id,
          threshold: 100,
          currentValue: totalSpentPercentage,
        ),
      );
    } else if (totalSpentPercentage >= 90) {
      alerts.add(
        BudgetAlert(
          id: '${budget.id}_near_limit',
          type: BudgetAlertType.nearLimit,
          severity: BudgetAlertSeverity.medium,
          message:
              'Bạn đã sử dụng ${totalSpentPercentage.toStringAsFixed(1)}% ngân sách',
          budgetId: budget.id,
          threshold: 90,
          currentValue: totalSpentPercentage,
        ),
      );
    }

    // Category-specific alerts
    for (final entry in categoryAnalytics.entries) {
      final categoryId = entry.key;
      final analytics = entry.value;

      if (analytics.isOverBudget) {
        alerts.add(
          BudgetAlert(
            id: '${budget.id}_${categoryId}_over',
            type: BudgetAlertType.categoryOverBudget,
            severity: BudgetAlertSeverity.high,
            message: 'Danh mục "${analytics.categoryName}" đã vượt ngân sách',
            budgetId: budget.id,
            categoryId: categoryId,
            threshold: 100,
            currentValue: analytics.spentPercentage,
          ),
        );
      } else if (analytics.isNearLimit) {
        alerts.add(
          BudgetAlert(
            id: '${budget.id}_${categoryId}_near',
            type: BudgetAlertType.categoryNearLimit,
            severity: BudgetAlertSeverity.medium,
            message: 'Danh mục "${analytics.categoryName}" sắp hết ngân sách',
            budgetId: budget.id,
            categoryId: categoryId,
            threshold: 80,
            currentValue: analytics.spentPercentage,
          ),
        );
      }

      // Projected overspending alert
      if (analytics.projectedSpending > analytics.budgetAmount * 1.1) {
        alerts.add(
          BudgetAlert(
            id: '${budget.id}_${categoryId}_projected',
            type: BudgetAlertType.projectedOverspend,
            severity: BudgetAlertSeverity.low,
            message:
                'Danh mục "${analytics.categoryName}" có thể vượt ngân sách cuối tháng',
            budgetId: budget.id,
            categoryId: categoryId,
            threshold: analytics.budgetAmount,
            currentValue: analytics.projectedSpending,
          ),
        );
      }
    }

    return alerts;
  }

  BudgetTrend _calculateBudgetTrend(
    Budget budget,
    List<TransactionModel> transactions,
  ) {
    // Group transactions by week
    final weeklySpending = <int, double>{};
    final now = DateTime.now();

    for (final transaction in transactions) {
      if (transaction.type == TransactionType.expense) {
        final weeksDiff = now.difference(transaction.date).inDays ~/ 7;
        weeklySpending[weeksDiff] =
            (weeklySpending[weeksDiff] ?? 0) + transaction.amount;
      }
    }

    // Calculate trend
    final weeks = weeklySpending.keys.toList()..sort();
    if (weeks.length < 2) {
      return BudgetTrend(
        direction: BudgetTrendDirection.stable,
        changePercentage: 0,
        description: 'Chưa đủ dữ liệu để phân tích xu hướng',
        weeklySpending: [],
        isAccelerating: false,
      );
    }

    final recentWeek = weeklySpending[weeks.first] ?? 0;
    final previousWeek = weeklySpending[weeks[1]] ?? 0;

    final changePercentage = previousWeek > 0
        ? ((recentWeek - previousWeek) / previousWeek * 100)
        : 0.0;

    BudgetTrendDirection direction;
    String description;

    if (changePercentage > 10) {
      direction = BudgetTrendDirection.increasing;
      description =
          'Chi tiêu đang tăng ${changePercentage.toStringAsFixed(1)}%';
    } else if (changePercentage < -10) {
      direction = BudgetTrendDirection.decreasing;
      description =
          'Chi tiêu đang giảm ${changePercentage.abs().toStringAsFixed(1)}%';
    } else {
      direction = BudgetTrendDirection.stable;
      description = 'Chi tiêu tương đối ổn định';
    }

    return BudgetTrend(
      direction: direction,
      changePercentage: changePercentage,
      description: description,
      weeklySpending: weeklySpending.values.toList(),
      isAccelerating: changePercentage > 20,
    );
  }

  List<DailySpending> _calculateDailySpending(
    String categoryId,
    List<TransactionModel> transactions,
  ) {
    final dailySpending = <DateTime, double>{};

    for (final transaction in transactions) {
      if (transaction.type == TransactionType.expense &&
          transaction.categoryId == categoryId) {
        final date = DateTime(
          transaction.date.year,
          transaction.date.month,
          transaction.date.day,
        );
        dailySpending[date] = (dailySpending[date] ?? 0) + transaction.amount;
      }
    }

    return dailySpending.entries
        .map((entry) => DailySpending(date: entry.key, amount: entry.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  double _calculateWeeklyAverage(
    String categoryId,
    List<TransactionModel> transactions,
  ) {
    final categoryTransactions = transactions
        .where(
          (t) =>
              t.type == TransactionType.expense && t.categoryId == categoryId,
        )
        .toList();

    if (categoryTransactions.isEmpty) return 0.0;

    final totalAmount = categoryTransactions.fold(
      0.0,
      (sum, t) => sum + t.amount,
    );
    final daySpan = DateTime.now()
        .difference(categoryTransactions.last.date)
        .inDays;
    final weekSpan = (daySpan / 7).ceil();

    return weekSpan > 0 ? totalAmount / weekSpan : 0.0;
  }

  double _calculateProjectedSpending(
    String categoryId,
    List<TransactionModel> transactions,
    Budget budget,
  ) {
    final weeklyAverage = _calculateWeeklyAverage(categoryId, transactions);

    // Calculate remaining weeks in budget period
    final (startDate, endDate) = budget.effectiveDateRange;
    final remainingDays = endDate.difference(DateTime.now()).inDays;
    final remainingWeeks = (remainingDays / 7).ceil();

    if (remainingWeeks <= 0) return 0.0;

    // Current spending + projected future spending
    final currentSpending = transactions
        .where(
          (t) =>
              t.type == TransactionType.expense && t.categoryId == categoryId,
        )
        .fold(0.0, (sum, t) => sum + t.amount);

    return currentSpending + (weeklyAverage * remainingWeeks);
  }

  Map<String, dynamic> _calculateComparison(
    BudgetAnalytics? current,
    BudgetAnalytics? previous,
  ) {
    if (current == null || previous == null) {
      return {
        'budgetChange': 0.0,
        'spendingChange': 0.0,
        'efficiencyChange': 0.0,
        'trend': 'insufficient_data',
      };
    }

    final budgetChange = previous.totalBudget > 0
        ? ((current.totalBudget - previous.totalBudget) /
              previous.totalBudget *
              100)
        : 0.0;

    final spendingChange = previous.totalSpent > 0
        ? ((current.totalSpent - previous.totalSpent) /
              previous.totalSpent *
              100)
        : 0.0;

    final efficiencyChange = current.spentPercentage - previous.spentPercentage;

    String trend;
    if (efficiencyChange < -10) {
      trend = 'improving';
    } else if (efficiencyChange > 10) {
      trend = 'worsening';
    } else {
      trend = 'stable';
    }

    return {
      'budgetChange': budgetChange,
      'spendingChange': spendingChange,
      'efficiencyChange': efficiencyChange,
      'trend': trend,
    };
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

  void _clearAnalyticsCache() {
    _analyticsCache.clear();
    _analyticsCacheTime.clear();
  }

  void _clearBudgetAnalyticsCache(String budgetId) {
    _analyticsCache.remove(budgetId);
    _analyticsCacheTime.remove(budgetId);
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
    _clearAnalyticsCache();
    super.dispose();
  }
}

// ============ BUDGET ANALYTICS MODELS ============

class BudgetAnalytics {
  final String budgetId;
  final double totalBudget;
  final double totalSpent;
  final double totalRemaining;
  final double spentPercentage;
  final bool isOverBudget;
  final bool isNearLimit;
  final Map<String, CategoryBudgetAnalytics> categoryAnalytics;
  final List<BudgetAlert> alerts;
  final BudgetTrend trend;
  final DateTime lastUpdated;

  const BudgetAnalytics({
    required this.budgetId,
    required this.totalBudget,
    required this.totalSpent,
    required this.totalRemaining,
    required this.spentPercentage,
    required this.isOverBudget,
    required this.isNearLimit,
    required this.categoryAnalytics,
    required this.alerts,
    required this.trend,
    required this.lastUpdated,
  });

  int get highPriorityAlerts =>
      alerts.where((a) => a.severity == BudgetAlertSeverity.high).length;

  bool get hasAlerts => alerts.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'budgetId': budgetId,
      'totalBudget': totalBudget,
      'totalSpent': totalSpent,
      'totalRemaining': totalRemaining,
      'spentPercentage': spentPercentage,
      'isOverBudget': isOverBudget,
      'isNearLimit': isNearLimit,
      'categoryAnalytics': categoryAnalytics.map(
        (k, v) => MapEntry(k, v.toJson()),
      ),
      'alerts': alerts.map((a) => a.toJson()).toList(),
      'trend': trend.toJson(),
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}

class CategoryBudgetAnalytics {
  final String categoryId;
  final String categoryName;
  final double budgetAmount;
  final double spentAmount;
  final double remainingAmount;
  final double spentPercentage;
  final bool isOverBudget;
  final bool isNearLimit;
  final List<DailySpending> dailySpending;
  final double weeklyAverage;
  final double projectedSpending;

  const CategoryBudgetAnalytics({
    required this.categoryId,
    required this.categoryName,
    required this.budgetAmount,
    required this.spentAmount,
    required this.remainingAmount,
    required this.spentPercentage,
    required this.isOverBudget,
    required this.isNearLimit,
    required this.dailySpending,
    required this.weeklyAverage,
    required this.projectedSpending,
  });

  Map<String, dynamic> toJson() {
    return {
      'categoryId': categoryId,
      'categoryName': categoryName,
      'budgetAmount': budgetAmount,
      'spentAmount': spentAmount,
      'remainingAmount': remainingAmount,
      'spentPercentage': spentPercentage,
      'isOverBudget': isOverBudget,
      'isNearLimit': isNearLimit,
      'dailySpending': dailySpending.map((d) => d.toJson()).toList(),
      'weeklyAverage': weeklyAverage,
      'projectedSpending': projectedSpending,
    };
  }
}

class BudgetAlert {
  final String id;
  final BudgetAlertType type;
  final BudgetAlertSeverity severity;
  final String message;
  final String budgetId;
  final String? categoryId;
  final double threshold;
  final double currentValue;
  final DateTime createdAt;

  BudgetAlert({
    required this.id,
    required this.type,
    required this.severity,
    required this.message,
    required this.budgetId,
    this.categoryId,
    required this.threshold,
    required this.currentValue,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.toString(),
      'severity': severity.toString(),
      'message': message,
      'budgetId': budgetId,
      'categoryId': categoryId,
      'threshold': threshold,
      'currentValue': currentValue,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class BudgetTrend {
  final BudgetTrendDirection direction;
  final double changePercentage;
  final String description;
  final List<double> weeklySpending;
  final bool isAccelerating;

  const BudgetTrend({
    required this.direction,
    required this.changePercentage,
    required this.description,
    required this.weeklySpending,
    required this.isAccelerating,
  });

  Map<String, dynamic> toJson() {
    return {
      'direction': direction.toString(),
      'changePercentage': changePercentage,
      'description': description,
      'weeklySpending': weeklySpending,
      'isAccelerating': isAccelerating,
    };
  }
}

class DailySpending {
  final DateTime date;
  final double amount;

  const DailySpending({required this.date, required this.amount});

  Map<String, dynamic> toJson() {
    return {'date': date.toIso8601String(), 'amount': amount};
  }
}

enum BudgetAlertType {
  overBudget,
  nearLimit,
  categoryOverBudget,
  categoryNearLimit,
  projectedOverspend,
  unusualSpending,
}

enum BudgetAlertSeverity { low, medium, high, critical }

enum BudgetTrendDirection { increasing, decreasing, stable }
