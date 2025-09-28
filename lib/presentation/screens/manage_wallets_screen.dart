// lib/presentation/screens/manage_wallets_screen_fixed.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';
import 'package:moneysun/presentation/widgets/connection_status_banner.dart';

class ManageWalletsScreen extends StatefulWidget {
  const ManageWalletsScreen({super.key});

  @override
  State<ManageWalletsScreen> createState() => _ManageWalletsScreenState();
}

class _ManageWalletsScreenState extends State<ManageWalletsScreen>
    with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;
  late AnimationController _refreshController;

  bool _showArchived = false;
  String _selectedWalletFilter = 'all';

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );
    _refreshController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _slideController.forward();

    // ✅ Fix: Safe initial data loading
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final walletProvider = context.read<WalletProvider>();
      if (!walletProvider.isInitialized) {
        walletProvider.loadWallets();
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    _refreshController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          const ConnectionStatusBanner(),
          Expanded(
            child: AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) => _buildMainContent(),
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: const Text(
        'Quản lý Nguồn tiền',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
      ),
      actions: [_buildSyncStatusIndicator(), _buildFilterMenu()],
    );
  }

  Widget _buildSyncStatusIndicator() {
    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                connectionStatus.isSyncing
                    ? Icons.sync
                    : connectionStatus.isOnline
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                key: ValueKey(connectionStatus.isSyncing),
                color: connectionStatus.isSyncing
                    ? Colors.orange
                    : connectionStatus.isOnline
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            onPressed: () => _showSyncStatusDialog(),
            tooltip: connectionStatus.statusMessage,
          ),
        );
      },
    );
  }

  Widget _buildFilterMenu() {
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Consumer2<UserProvider, WalletProvider>(
        builder: (context, userProvider, walletProvider, child) {
          return PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) {
              if (value == 'archive_toggle') {
                walletProvider.toggleIncludeArchived();
              } else {
                setState(() => _selectedWalletFilter = value);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'all',
                child: Row(
                  children: [
                    Icon(
                      Icons.all_inclusive,
                      size: 18,
                      color: _selectedWalletFilter == 'all'
                          ? Colors.blue
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Tất cả ví',
                      style: TextStyle(
                        fontWeight: _selectedWalletFilter == 'all'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'personal',
                child: Row(
                  children: [
                    Icon(
                      Icons.person_rounded,
                      size: 18,
                      color: _selectedWalletFilter == 'personal'
                          ? Colors.green
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Ví cá nhân',
                      style: TextStyle(
                        fontWeight: _selectedWalletFilter == 'personal'
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              if (userProvider.hasPartner)
                PopupMenuItem(
                  value: 'shared',
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_rounded,
                        size: 18,
                        color: _selectedWalletFilter == 'shared'
                            ? Colors.orange
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Ví chung',
                        style: TextStyle(
                          fontWeight: _selectedWalletFilter == 'shared'
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'archive_toggle',
                child: Row(
                  children: [
                    Icon(
                      walletProvider.includeArchived
                          ? Icons.visibility_off
                          : Icons.visibility,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      walletProvider.includeArchived
                          ? 'Ẩn đã lưu trữ'
                          : 'Hiện đã lưu trữ',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainContent() {
    return Column(
      children: [
        // Header Card
        FadeTransition(
          opacity: _slideAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.3),
              end: Offset.zero,
            ).animate(_slideAnimation),
            child: _buildHeaderCard(),
          ),
        ),

        // Filter chips
        FadeTransition(opacity: _slideAnimation, child: _buildFilterChips()),

        // Wallets List
        Expanded(
          child: FadeTransition(
            opacity: _slideAnimation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.3),
                end: Offset.zero,
              ).animate(_slideAnimation),
              child: _buildWalletsList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return Consumer2<WalletProvider, UserProvider>(
      builder: (context, walletProvider, userProvider, child) {
        final wallets = _getFilteredWallets(
          walletProvider.wallets,
          userProvider,
        );
        final totalBalance = wallets.fold(
          0.0,
          (sum, wallet) => sum + wallet.balance,
        );

        return Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade600, Colors.blue.shade400],
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.account_balance_wallet_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getBalanceTitle(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          NumberFormat.currency(
                            locale: 'vi_VN',
                            symbol: '₫',
                          ).format(totalBalance),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildStatsRow(wallets, userProvider),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatsRow(List<Wallet> wallets, UserProvider userProvider) {
    return Row(
      children: [
        _buildStatItem('Số ví', '${wallets.length}', Icons.wallet_rounded),
        const SizedBox(width: 16),
        if (_selectedWalletFilter == 'all') ...[
          _buildStatItem(
            'Cá nhân',
            '${wallets.where((w) => w.ownerId == userProvider.currentUser?.uid).length}',
            Icons.person_rounded,
          ),
          if (userProvider.hasPartner) ...[
            const SizedBox(width: 16),
            _buildStatItem(
              'Chung',
              '${wallets.where((w) => w.ownerId == userProvider.partnershipId).length}',
              Icons.people_rounded,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        if (!userProvider.hasPartner) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          height: 50,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildFilterChip(
                'all',
                'Tất cả',
                Icons.all_inclusive,
                Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                'personal',
                'Cá nhân',
                Icons.person_rounded,
                Colors.green,
              ),
              const SizedBox(width: 8),
              _buildFilterChip(
                'shared',
                'Chung',
                Icons.people_rounded,
                Colors.orange,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(
    String value,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedWalletFilter == value;

    return FilterChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : color),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      onSelected: (selected) {
        setState(() => _selectedWalletFilter = value);
      },
      selectedColor: color,
      checkmarkColor: Colors.white,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : color,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildWalletsList() {
    return Consumer2<WalletProvider, UserProvider>(
      builder: (context, walletProvider, userProvider, child) {
        if (walletProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (walletProvider.hasError) {
          return _buildErrorState(walletProvider.error!, walletProvider);
        }

        final filteredWallets = _getFilteredWallets(
          walletProvider.wallets,
          userProvider,
        );

        if (filteredWallets.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          onRefresh: () async {
            _refreshController.forward().then((_) {
              _refreshController.reset();
            });
            await walletProvider.loadWallets(forceRefresh: true);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: filteredWallets.length,
            itemBuilder: (context, index) {
              final wallet = filteredWallets[index];
              return _buildWalletCard(wallet, userProvider, index);
            },
          ),
        );
      },
    );
  }

  Widget _buildWalletCard(Wallet wallet, UserProvider userProvider, int index) {
    final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    final walletConfig = _getWalletConfig(wallet, userProvider);

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 100)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: walletConfig.color.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.all(20),
          leading: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: walletConfig.color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(walletConfig.icon, color: walletConfig.color, size: 24),
          ),
          title: Text(
            wallet.displayName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                formatter.format(wallet.balance),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: walletConfig.color,
                ),
              ),
            ],
          ),
          trailing: PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
            onSelected: (action) => _handleWalletAction(action, wallet),
            itemBuilder: (context) => [
              if (context.read<WalletProvider>().canEditWallet(wallet)) ...[
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Chỉnh sửa'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Xóa ví'),
                    ],
                  ),
                ),
              ] else ...[
                const PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      Icon(Icons.info_rounded, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('Xem chi tiết'),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.account_balance_wallet_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _getEmptyStateTitle(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getEmptyStateSubtitle(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddWalletDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tạo ví mới'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error, WalletProvider walletProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            const Text(
              'Có lỗi xảy ra',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => walletProvider.loadWallets(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: _showAddWalletDialog,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Thêm ví'),
      tooltip: 'Tạo ví mới',
    );
  }

  // ============ DIALOG METHODS ============

  /// ✅ Fix: Enhanced wallet creation dialog with proper amount handling
  void _showAddWalletDialog() {
    final userProvider = context.read<UserProvider>();
    final nameController = TextEditingController();
    final balanceController = TextEditingController();
    String ownerType = 'personal';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.add_card_rounded,
                            color: Colors.blue,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Tạo ví mới',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Thêm nguồn tiền mới để quản lý',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Wallet Name
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Tên ví *',
                        hintText: 'Ví dụ: Tiền mặt, Ngân hàng...',
                        prefixIcon: const Icon(Icons.wallet_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                    ),

                    const SizedBox(height: 16),

                    // ✅ Fix: Enhanced amount input with better parsing
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Số dư ban đầu',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SmartAmountInput(
                          controller: balanceController,
                          labelText: null,
                          hintText: 'Nhập số dư hiện tại...',
                          showQuickButtons: true,
                          showSuggestions: true,
                          customSuggestions: [
                            0,
                            100000,
                            500000,
                            1000000,
                            5000000,
                            10000000,
                          ],
                          onChanged: (amount) {
                            // Debug logging
                            debugPrint('💰 Amount changed: $amount');
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.attach_money_rounded),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.green.withOpacity(0.05),
                          ),
                        ),
                      ],
                    ),

                    // Owner Type Selection
                    if (userProvider.partnershipId != null) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Loại ví:',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Column(
                        children: [
                          RadioListTile<String>(
                            title: const Row(
                              children: [
                                Icon(Icons.person_rounded, size: 20),
                                SizedBox(width: 8),
                                Text('Cá nhân'),
                              ],
                            ),
                            subtitle: const Text('Chỉ bạn có thể sử dụng'),
                            value: 'personal',
                            groupValue: ownerType,
                            onChanged: (value) =>
                                setDialogState(() => ownerType = value!),
                          ),
                          RadioListTile<String>(
                            title: const Row(
                              children: [
                                Icon(Icons.people_rounded, size: 20),
                                SizedBox(width: 8),
                                Text('Chung'),
                              ],
                            ),
                            subtitle: const Text('Cả hai cùng sử dụng'),
                            value: 'shared',
                            groupValue: ownerType,
                            onChanged: (value) =>
                                setDialogState(() => ownerType = value!),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _createWallet(
                              nameController.text.trim(),
                              balanceController.text,
                              ownerType,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Tạo ví',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============ HELPER METHODS ============

  /// ✅ Fix: Enhanced wallet creation with better error handling
  Future<void> _createWallet(
    String name,
    String balanceText,
    String ownerType,
  ) async {
    // Validate input
    if (name.isEmpty) {
      _showErrorSnackBar('Vui lòng nhập tên ví');
      return;
    }

    Navigator.pop(context);

    try {
      // ✅ Fix: Better amount parsing with debug logging
      debugPrint('🔍 Parsing amount from: "$balanceText"');

      final balance = _parseAmountSafely(balanceText);

      final userProvider = context.read<UserProvider>();
      final String? ownerId =
          ownerType == 'shared' && userProvider.partnershipId != null
          ? userProvider.partnershipId
          : null;

      final success = await context.read<WalletProvider>().addWallet(
        name: name,
        initialBalance: balance,
        ownerId: ownerId,
      );

      if (success) {
        _showSuccessSnackBar(
          'Tạo ví "$name" thành công với số dư ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(balance)}',
        );
      } else {
        _showErrorSnackBar('Không thể tạo ví. Vui lòng thử lại.');
      }
    } catch (e) {
      debugPrint('❌ Error creating wallet: $e');
      _showErrorSnackBar('Lỗi khi tạo ví: $e');
    }
  }

  /// ✅ Fix: Enhanced amount parsing function
  double _parseAmountSafely(String text) {
    if (text.trim().isEmpty) {
      debugPrint('⚠️ Empty amount text, returning 0');
      return 0.0;
    }

    // Remove all non-digit characters except decimal point
    String cleanText = text.replaceAll(RegExp(r'[^0-9]'), '');
    debugPrint('🧹 Cleaned text: "$cleanText"');

    if (cleanText.isEmpty) {
      debugPrint('⚠️ No digits found, returning 0');
      return 0.0;
    }

    try {
      final amount = double.parse(cleanText);
      debugPrint('✅ Successfully parsed: $amount');
      return amount;
    } catch (e) {
      debugPrint('❌ Parse error: $e, returning 0');
      return 0.0;
    }
  }

  List<Wallet> _getFilteredWallets(
    List<Wallet> wallets,
    UserProvider userProvider,
  ) {
    switch (_selectedWalletFilter) {
      case 'personal':
        return wallets
            .where((w) => w.ownerId == userProvider.currentUser?.uid)
            .toList();
      case 'shared':
        return wallets
            .where((w) => w.ownerId == userProvider.partnershipId)
            .toList();
      default:
        return wallets;
    }
  }

  WalletConfig _getWalletConfig(Wallet wallet, UserProvider userProvider) {
    if (wallet.ownerId == userProvider.partnershipId) {
      return WalletConfig(
        color: Colors.orange,
        icon: Icons.people_rounded,
        label: 'Chung',
      );
    } else if (wallet.ownerId == userProvider.currentUser?.uid) {
      return WalletConfig(
        color: Colors.green,
        icon: Icons.person_rounded,
        label: 'Cá nhân',
      );
    }
    return WalletConfig(
      color: Colors.blue,
      icon: Icons.account_balance_wallet_rounded,
      label: 'Khác',
    );
  }

  String _getBalanceTitle() {
    switch (_selectedWalletFilter) {
      case 'personal':
        return 'Tổng tài sản cá nhân';
      case 'shared':
        return 'Tổng tài sản chung';
      default:
        return 'Tổng tài sản';
    }
  }

  String _getEmptyStateTitle() {
    switch (_selectedWalletFilter) {
      case 'personal':
        return 'Chưa có ví cá nhân nào';
      case 'shared':
        return 'Chưa có ví chung nào';
      default:
        return 'Chưa có ví nào';
    }
  }

  String _getEmptyStateSubtitle() {
    switch (_selectedWalletFilter) {
      case 'personal':
        return 'Tạo ví cá nhân để quản lý tài chính riêng';
      case 'shared':
        return 'Tạo ví chung để quản lý tài chính với đối tác';
      default:
        return 'Tạo ví đầu tiên để bắt đầu quản lý tài chính';
    }
  }

  void _handleWalletAction(String action, Wallet wallet) {
    switch (action) {
      case 'edit':
        _showEditWalletDialog(wallet);
        break;
      case 'delete':
        _showDeleteWalletDialog(wallet);
        break;
      case 'view':
        _showWalletDetailsDialog(wallet);
        break;
    }
  }

  void _showEditWalletDialog(Wallet wallet) {
    final nameController = TextEditingController(text: wallet.name);
    final balanceController = TextEditingController(
      text: NumberFormat.decimalPattern('vi_VN').format(wallet.balance),
    );
    bool isVisibleToPartner = wallet.isVisibleToPartner;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxWidth: 500),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            color: Colors.orange,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Chỉnh sửa ví',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Ví: ${wallet.name}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Wallet Name
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Tên ví *',
                        prefixIcon: const Icon(Icons.wallet_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),

                    const SizedBox(height: 16),

                    // Balance (read-only or editable based on business logic)
                    SmartAmountInput(
                      controller: balanceController,
                      labelText: 'Số dư hiện tại',
                      hintText: 'Nhập số dư...',
                      showQuickButtons: true,
                      enabled:
                          false, // Usually balance should not be directly edited
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.attach_money_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey.withOpacity(0.05),
                      ),
                    ),

                    // Visibility to partner
                    if (context.read<UserProvider>().hasPartner &&
                        wallet.ownerId ==
                            context.read<UserProvider>().currentUser?.uid) ...[
                      const SizedBox(height: 20),
                      SwitchListTile(
                        title: const Text('Hiển thị với đối tác'),
                        subtitle: Text(
                          isVisibleToPartner
                              ? 'Đối tác có thể thấy ví này'
                              : 'Chỉ bạn thấy ví này',
                        ),
                        value: isVisibleToPartner,
                        onChanged: (value) {
                          setDialogState(() => isVisibleToPartner = value);
                        },
                        activeColor: Colors.blue,
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('Hủy'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) {
                                _showErrorSnackBar('Vui lòng nhập tên ví');
                                return;
                              }

                              Navigator.pop(context);

                              // Create updated wallet
                              final updatedWallet = wallet.copyWith(
                                name: name,
                                isVisibleToPartner: isVisibleToPartner,
                              );

                              // Update wallet
                              final success = await context
                                  .read<WalletProvider>()
                                  .updateWallet(updatedWallet);

                              if (success) {
                                _showSuccessSnackBar('Đã cập nhật ví "$name"');
                              } else {
                                _showErrorSnackBar('Không thể cập nhật ví');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Lưu thay đổi',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Show delete wallet confirmation dialog
  void _showDeleteWalletDialog(Wallet wallet) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.delete_rounded,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text('Xác nhận xóa ví'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bạn có chắc muốn xóa ví "${wallet.name}"?',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_rounded,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Lưu ý: Ví phải không có giao dịch mới có thể xóa.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Số dư hiện tại: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(wallet.balance)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);

                // Delete wallet
                final success = await context
                    .read<WalletProvider>()
                    .deleteWallet(wallet.id);

                if (success) {
                  _showSuccessSnackBar('Đã xóa ví "${wallet.name}"');
                } else {
                  _showErrorSnackBar(
                    context.read<WalletProvider>().error ??
                        'Không thể xóa ví. Vui lòng kiểm tra lại.',
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Xóa ví'),
            ),
          ],
        );
      },
    );
  }

  /// Show wallet details dialog (read-only)
  void _showWalletDetailsDialog(Wallet wallet) {
    final walletConfig = _getWalletConfig(wallet, context.read<UserProvider>());

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon and title
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: walletConfig.color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    walletConfig.icon,
                    color: walletConfig.color,
                    size: 40,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  wallet.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: walletConfig.color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    walletConfig.label,
                    style: TextStyle(
                      color: walletConfig.color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Balance
                Text(
                  NumberFormat.currency(
                    locale: 'vi_VN',
                    symbol: '₫',
                  ).format(wallet.balance),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: walletConfig.color,
                  ),
                ),
                const Text(
                  'Số dư hiện tại',
                  style: TextStyle(color: Colors.grey),
                ),

                const SizedBox(height: 24),

                // Additional info
                _buildInfoRow('Loại ví', wallet.type.displayName),
                _buildInfoRow(
                  'Hiển thị với đối tác',
                  wallet.isVisibleToPartner ? 'Có' : 'Không',
                ),
                _buildInfoRow(
                  'Trạng thái',
                  wallet.isArchived ? 'Đã lưu trữ' : 'Đang hoạt động',
                ),

                const SizedBox(height: 24),

                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  void _showSyncStatusDialog() {
    // Implementation for sync status
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}

class WalletConfig {
  final Color color;
  final IconData icon;
  final String label;

  WalletConfig({required this.color, required this.icon, required this.label});
}
