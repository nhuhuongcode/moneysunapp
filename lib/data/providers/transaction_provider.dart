import 'package:flutter/foundation.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/services/data_service.dart'; // ✅ Updated import
import 'package:moneysun/data/providers/user_provider.dart';

class TransactionProvider extends ChangeNotifier {
  final DataService _dataService; // ✅ Using unified service
  final UserProvider _userProvider;

  TransactionProvider(this._dataService, this._userProvider) {
    _dataService.addListener(_onDataServiceChanged);
  }

  // ============ STATE MANAGEMENT ============
  List<TransactionModel> _transactions = [];
  List<TransactionModel> _filteredTransactions = [];
  bool _isLoading = false;
  String? _error;
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String? _filterWalletId;
  String? _filterCategoryId;

  // ============ GETTERS ============
  List<TransactionModel> get transactions => _filteredTransactions;
  List<TransactionModel> get allTransactions => _transactions;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;
  int get transactionCount => _filteredTransactions.length;

  // Filter getters
  DateTime? get filterStartDate => _filterStartDate;
  DateTime? get filterEndDate => _filterEndDate;
  String? get filterWalletId => _filterWalletId;
  String? get filterCategoryId => _filterCategoryId;
  bool get hasActiveFilters =>
      _filterStartDate != null ||
      _filterEndDate != null ||
      _filterWalletId != null ||
      _filterCategoryId != null;

  // ============ PUBLIC METHODS ============

  /// Load transactions - uses offline-first unified service
  Future<void> loadTransactions({
    DateTime? startDate,
    DateTime? endDate,
    String? walletId,
    String? categoryId,
    int? limit,
    bool forceRefresh = false,
  }) async {
    if (_isLoading && !forceRefresh) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📊 Loading transactions from unified service...');

      final loadedTransactions = await _dataService.getTransactions(
        startDate: startDate,
        endDate: endDate,
        walletId: walletId,
        categoryId: categoryId,
        limit: limit,
      );

      _transactions = loadedTransactions;
      _applyCurrentFilters();

      debugPrint('✅ Loaded ${_transactions.length} transactions');
    } catch (e) {
      _setError('Không thể tải giao dịch: $e');
      debugPrint('❌ Error loading transactions: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// Add new transaction - optimistic UI with offline support
  Future<bool> addTransaction(TransactionModel transaction) async {
    _clearError();

    try {
      debugPrint('➕ Adding transaction: ${transaction.description}');

      await _dataService.addTransaction(transaction);

      // Optimistic update - add to local list immediately
      _transactions.insert(0, transaction);
      _applyCurrentFilters();
      notifyListeners();

      debugPrint('✅ Transaction added successfully');
      return true;
    } catch (e) {
      _setError('Không thể thêm giao dịch: $e');
      debugPrint('❌ Error adding transaction: $e');
      return false;
    }
  }

  /// Apply date filter
  void setDateFilter(DateTime? startDate, DateTime? endDate) {
    _filterStartDate = startDate;
    _filterEndDate = endDate;
    _applyCurrentFilters();
    notifyListeners();
    debugPrint('📅 Date filter applied: $startDate to $endDate');
  }

  /// Apply wallet filter
  void setWalletFilter(String? walletId) {
    _filterWalletId = walletId;
    _applyCurrentFilters();
    notifyListeners();
    debugPrint('👛 Wallet filter applied: $walletId');
  }

  /// Apply category filter
  void setCategoryFilter(String? categoryId) {
    _filterCategoryId = categoryId;
    _applyCurrentFilters();
    notifyListeners();
    debugPrint('📂 Category filter applied: $categoryId');
  }

  /// Clear all filters
  void clearFilters() {
    _filterStartDate = null;
    _filterEndDate = null;
    _filterWalletId = null;
    _filterCategoryId = null;
    _applyCurrentFilters();
    notifyListeners();
    debugPrint('🧹 All filters cleared');
  }

  /// Get recent transactions (last 30 days)
  Future<void> loadRecentTransactions({int limit = 100}) async {
    final endDate = DateTime.now();
    final startDate = endDate.subtract(const Duration(days: 30));

    await loadTransactions(
      startDate: startDate,
      endDate: endDate,
      limit: limit,
    );
  }

  /// Search transactions by description
  List<TransactionModel> searchTransactions(String query) {
    if (query.trim().isEmpty) return _filteredTransactions;

    final lowercaseQuery = query.toLowerCase().trim();
    return _filteredTransactions.where((transaction) {
      return transaction.description.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Get transaction statistics
  Map<String, dynamic> getStatistics() {
    if (_filteredTransactions.isEmpty) {
      return {
        'totalIncome': 0.0,
        'totalExpense': 0.0,
        'netAmount': 0.0,
        'transactionCount': 0,
        'averageTransaction': 0.0,
      };
    }

    double totalIncome = 0;
    double totalExpense = 0;

    for (final transaction in _filteredTransactions) {
      switch (transaction.type) {
        case TransactionType.income:
          totalIncome += transaction.amount;
          break;
        case TransactionType.expense:
          totalExpense += transaction.amount;
          break;
        case TransactionType.transfer:
          // Transfers don't affect income/expense totals
          break;
      }
    }

    final netAmount = totalIncome - totalExpense;
    final transactionCount = _filteredTransactions.length;
    final averageTransaction = transactionCount > 0
        ? (totalIncome + totalExpense) / transactionCount
        : 0.0;

    return {
      'totalIncome': totalIncome,
      'totalExpense': totalExpense,
      'netAmount': netAmount,
      'transactionCount': transactionCount,
      'averageTransaction': averageTransaction,
    };
  }

  // ============ PRIVATE METHODS ============

  void _onDataServiceChanged() {
    if (!_isLoading) {
      loadTransactions(forceRefresh: true);
    }
  }

  void _applyCurrentFilters() {
    _filteredTransactions = _transactions.where((transaction) {
      // Date filter
      if (_filterStartDate != null &&
          transaction.date.isBefore(_filterStartDate!)) {
        return false;
      }
      if (_filterEndDate != null && transaction.date.isAfter(_filterEndDate!)) {
        return false;
      }

      // Wallet filter
      if (_filterWalletId != null && transaction.walletId != _filterWalletId) {
        return false;
      }

      // Category filter
      if (_filterCategoryId != null &&
          transaction.categoryId != _filterCategoryId) {
        return false;
      }

      return true;
    }).toList();

    // Sort by date descending
    _filteredTransactions.sort((a, b) => b.date.compareTo(a.date));
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
