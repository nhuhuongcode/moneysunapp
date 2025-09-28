// lib/data/providers/wallet_provider_fixed.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/services/data_service.dart';
import 'package:moneysun/data/providers/user_provider.dart';

class WalletProvider extends ChangeNotifier {
  final DataService _dataService;
  final UserProvider _userProvider;

  WalletProvider(this._dataService, this._userProvider) {
    _dataService.addListener(_onDataServiceChanged);
    // ✅ Fix: Defer initial load to avoid setState during build
    _scheduleInitialLoad();
  }

  // ============ STATE MANAGEMENT ============
  List<Wallet> _wallets = [];
  List<Wallet> _filteredWallets = [];
  bool _isLoading = false;
  String? _error;
  bool _includeArchived = false;
  bool _isInitialized = false;

  // ============ GETTERS ============
  List<Wallet> get wallets => _filteredWallets;
  List<Wallet> get allWallets => _wallets;
  List<Wallet> get activeWallets =>
      _wallets.where((w) => !w.isArchived).toList();

  List<Wallet> get personalWallets => activeWallets
      .where((w) => w.ownerId == _userProvider.currentUser?.uid)
      .toList();

  List<Wallet> get sharedWallets => activeWallets
      .where((w) => w.ownerId == _userProvider.partnershipId)
      .toList();

  List<Wallet> get partnerWallets => activeWallets
      .where(
        (w) => w.ownerId == _userProvider.partnerUid && w.isVisibleToPartner,
      )
      .toList();

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasError => _error != null;
  int get walletCount => _filteredWallets.length;
  bool get includeArchived => _includeArchived;
  bool get isInitialized => _isInitialized;

  // Financial overview
  double get totalBalance =>
      _filteredWallets.fold(0, (sum, w) => sum + w.balance);
  double get personalBalance =>
      personalWallets.fold(0, (sum, w) => sum + w.balance);
  double get sharedBalance =>
      sharedWallets.fold(0, (sum, w) => sum + w.balance);

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
      loadWallets();
    }
  }

  /// Load all wallets using DataService
  Future<void> loadWallets({bool forceRefresh = false}) async {
    if (_isLoading && !forceRefresh) return;

    _setLoading(true);
    _clearError();

    try {
      debugPrint('📂 Loading wallets from DataService...');

      final loadedWallets = await _dataService.getWallets(
        includeArchived: _includeArchived,
      );

      _wallets = loadedWallets;
      _applyCurrentFilters();

      debugPrint('✅ Loaded ${_wallets.length} wallets');
    } catch (e) {
      _setError('Không thể tải ví: $e');
      debugPrint('❌ Error loading wallets: $e');
    } finally {
      _setLoading(false);
    }
  }

  /// ✅ Fix: Enhanced addWallet with proper amount parsing
  Future<bool> addWallet({
    required String name,
    required double initialBalance,
    WalletType type = WalletType.general,
    bool isVisibleToPartner = true,
    String? ownerId,
  }) async {
    _clearError();

    // ✅ Validate input parameters
    if (name.trim().isEmpty) {
      _setError('Tên ví không được để trống');
      return false;
    }

    if (initialBalance < 0) {
      _setError('Số dư ban đầu không được âm');
      return false;
    }

    // Create temporary wallet for optimistic update
    final tempWallet = Wallet(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      balance: initialBalance,
      ownerId: ownerId ?? _userProvider.currentUser?.uid ?? '',
      isVisibleToPartner: isVisibleToPartner,
      type: type,
    );

    try {
      debugPrint('➕ Adding wallet: $name with balance: $initialBalance');

      // Optimistic update - add to local list immediately
      _wallets.add(tempWallet);
      _applyCurrentFilters();
      notifyListeners();

      await _dataService.addWallet(
        name: name.trim(),
        initialBalance: initialBalance,
        type: type,
        isVisibleToPartner: isVisibleToPartner,
        ownerId: ownerId,
      );

      // Remove temp wallet and reload from database
      _wallets.removeWhere((w) => w.id == tempWallet.id);
      await loadWallets(forceRefresh: true);

      debugPrint('✅ Wallet added successfully');
      return true;
    } catch (e) {
      // Revert optimistic update
      _wallets.removeWhere((w) => w.id == tempWallet.id);
      _applyCurrentFilters();

      _setError('Không thể thêm ví: $e');
      debugPrint('❌ Error adding wallet: $e');
      notifyListeners();
      return false;
    }
  }

  /// Get wallets stream using DataService
  Stream<List<Wallet>> getWalletsStream({bool includeArchived = false}) {
    return _dataService.getWalletsStream(includeArchived: includeArchived);
  }

  /// Get wallet by ID
  Wallet? getWalletById(String walletId) {
    try {
      return _wallets.firstWhere((w) => w.id == walletId);
    } catch (e) {
      return null;
    }
  }

  /// Get wallets suitable for transaction source
  List<Wallet> getTransactionSourceWallets() {
    return activeWallets.where((w) => canEditWallet(w)).toList();
  }

  /// Get wallets suitable for transfer destination
  List<Wallet> getTransferDestinationWallets(String sourceWalletId) {
    return activeWallets
        .where((w) => w.id != sourceWalletId && canEditWallet(w))
        .toList();
  }

  /// Check if wallet can be edited by current user
  bool canEditWallet(Wallet wallet) {
    final currentUserId = _userProvider.currentUser?.uid;

    // Personal wallets: only owner can edit
    if (wallet.ownerId == currentUserId) return true;

    // Shared wallets: both partners can edit
    if (wallet.isShared && _userProvider.partnershipId != null) {
      return wallet.ownerId == _userProvider.partnershipId;
    }

    return false;
  }

  /// Search wallets
  List<Wallet> searchWallets(String query) {
    if (query.trim().isEmpty) return _filteredWallets;

    final lowercaseQuery = query.toLowerCase().trim();
    return _filteredWallets.where((wallet) {
      return wallet.name.toLowerCase().contains(lowercaseQuery);
    }).toList();
  }

  /// Toggle include archived
  void toggleIncludeArchived() {
    _includeArchived = !_includeArchived;
    loadWallets(forceRefresh: true);
    debugPrint('📦 Include archived wallets toggled: $_includeArchived');
  }

  // ============ PRIVATE METHODS ============

  /// ✅ Fix: Safe data service change handling
  void _onDataServiceChanged() {
    // Use postFrameCallback to avoid setState during build
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_isLoading && _dataService.isInitialized) {
        loadWallets(forceRefresh: true);
      }
    });
  }

  void _applyCurrentFilters() {
    _filteredWallets = _wallets.where((wallet) {
      // Archive filter
      if (!_includeArchived && wallet.isArchived) return false;
      return true;
    }).toList();

    // Sort wallets
    _filteredWallets.sort((a, b) {
      // Archived wallets go to bottom
      if (a.isArchived != b.isArchived) {
        return a.isArchived ? 1 : -1;
      }

      // Then by balance descending
      final balanceComparison = b.balance.compareTo(a.balance);
      if (balanceComparison != 0) return balanceComparison;

      // Finally by name
      return a.name.compareTo(b.name);
    });
  }

  Future<bool> updateWallet(Wallet wallet) async {
    _clearError();

    try {
      debugPrint('📝 Updating wallet: ${wallet.name}');

      // Optimistic update
      final index = _wallets.indexWhere((w) => w.id == wallet.id);
      if (index != -1) {
        final oldWallet = _wallets[index];
        _wallets[index] = wallet;
        _applyCurrentFilters();
        notifyListeners();

        try {
          await _dataService.updateWallet(wallet);
          debugPrint('✅ Wallet updated successfully');
          return true;
        } catch (e) {
          // Rollback on error
          _wallets[index] = oldWallet;
          _applyCurrentFilters();
          notifyListeners();
          throw e;
        }
      }

      throw Exception('Wallet not found');
    } catch (e) {
      _setError('Không thể cập nhật ví: $e');
      debugPrint('❌ Error updating wallet: $e');
      return false;
    }
  }

  /// Delete wallet
  Future<bool> deleteWallet(String walletId) async {
    _clearError();

    try {
      debugPrint('🗑️ Deleting wallet: $walletId');

      // Check if wallet can be deleted
      final wallet = getWalletById(walletId);
      if (wallet == null) {
        throw Exception('Ví không tồn tại');
      }

      if (!canEditWallet(wallet)) {
        throw Exception('Bạn không có quyền xóa ví này');
      }

      // Optimistic removal
      final removedWallet = _wallets.firstWhere((w) => w.id == walletId);
      _wallets.removeWhere((w) => w.id == walletId);
      _applyCurrentFilters();
      notifyListeners();

      try {
        await _dataService.deleteWallet(walletId);
        debugPrint('✅ Wallet deleted successfully');
        return true;
      } catch (e) {
        // Rollback on error
        _wallets.add(removedWallet);
        _applyCurrentFilters();
        notifyListeners();
        throw e;
      }
    } catch (e) {
      _setError('Không thể xóa ví: $e');
      debugPrint('❌ Error deleting wallet: $e');
      return false;
    }
  }

  /// Archive wallet
  Future<bool> archiveWallet(String walletId) async {
    _clearError();

    try {
      final wallet = getWalletById(walletId);
      if (wallet == null) {
        throw Exception('Ví không tồn tại');
      }

      await _dataService.archiveWallet(walletId);
      await loadWallets(forceRefresh: true);

      debugPrint('✅ Wallet archived successfully');
      return true;
    } catch (e) {
      _setError('Không thể lưu trữ ví: $e');
      debugPrint('❌ Error archiving wallet: $e');
      return false;
    }
  }

  /// Restore archived wallet
  Future<bool> restoreWallet(String walletId) async {
    _clearError();

    try {
      await _dataService.restoreWallet(walletId);
      await loadWallets(forceRefresh: true);

      debugPrint('✅ Wallet restored successfully');
      return true;
    } catch (e) {
      _setError('Không thể khôi phục ví: $e');
      debugPrint('❌ Error restoring wallet: $e');
      return false;
    }
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
