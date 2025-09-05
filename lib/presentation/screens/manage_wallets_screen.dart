// lib/presentation/screens/manage_wallets_screen.dart - Complete implementation

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManageWalletsScreen extends StatefulWidget {
  const ManageWalletsScreen({super.key});

  @override
  State<ManageWalletsScreen> createState() => _ManageWalletsScreenState();
}

class _ManageWalletsScreenState extends State<ManageWalletsScreen>
    with TickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  bool _showArchived = false;
  bool _isLoading = false;

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
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: AnimatedBuilder(
        animation: _slideAnimation,
        builder: (context, child) {
          return Stack(
            children: [
              // Gradient Background
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.blue.withOpacity(0.05),
                      Theme.of(context).scaffoldBackgroundColor,
                      Colors.green.withOpacity(0.03),
                    ],
                  ),
                ),
              ),

              // Main Content
              Column(
                children: [
                  // Header Card
                  FadeTransition(
                    opacity: _slideAnimation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.3),
                        end: Offset.zero,
                      ).animate(_slideAnimation),
                      child: _buildHeaderCard(userProvider),
                    ),
                  ),

                  // Archive Toggle
                  FadeTransition(
                    opacity: _slideAnimation,
                    child: _buildArchiveToggle(),
                  ),

                  // Wallets List
                  Expanded(
                    child: FadeTransition(
                      opacity: _slideAnimation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.3),
                          end: Offset.zero,
                        ).animate(_slideAnimation),
                        child: _buildWalletsList(
                          userProvider,
                          currencyFormatter,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Loading Overlay
              if (_isLoading) _buildLoadingOverlay(),
            ],
          );
        },
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
      actions: [
        Container(
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
            icon: const Icon(Icons.analytics_rounded),
            onPressed: _showWalletAnalytics,
            tooltip: 'Phân tích ví',
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderCard(UserProvider userProvider) {
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
      child: StreamBuilder<List<Wallet>>(
        stream: _databaseService.getWalletsStream(userProvider),
        builder: (context, snapshot) {
          final wallets = snapshot.data ?? [];
          final totalBalance = wallets.fold(
            0.0,
            (sum, wallet) => sum + wallet.balance,
          );

          return Column(
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
                        const Text(
                          'Tổng tài sản',
                          style: TextStyle(
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

              // Stats Row
              Row(
                children: [
                  _buildStatItem(
                    'Số ví',
                    '${wallets.length}',
                    Icons.wallet_rounded,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    'Ví cá nhân',
                    '${wallets.where((w) => w.ownerId == userProvider.currentUser?.uid).length}',
                    Icons.person_rounded,
                  ),
                  if (userProvider.hasPartner) ...[
                    const SizedBox(width: 24),
                    _buildStatItem(
                      'Ví chung',
                      '${wallets.where((w) => w.ownerId == userProvider.partnershipId).length}',
                      Icons.people_rounded,
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
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

  Widget _buildArchiveToggle() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          const Text(
            'Hiển thị ví đã lưu trữ',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Switch(
            value: _showArchived,
            onChanged: (value) {
              setState(() {
                _showArchived = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWalletsList(UserProvider userProvider, NumberFormat formatter) {
    return StreamBuilder<List<Wallet>>(
      stream: _databaseService.getWalletsStream(userProvider),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _buildEmptyState();
        }

        final wallets = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: wallets.length,
            itemBuilder: (context, index) {
              final wallet = wallets[index];
              return _buildEnhancedWalletCard(
                wallet,
                formatter,
                userProvider,
                index,
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEnhancedWalletCard(
    Wallet wallet,
    NumberFormat formatter,
    UserProvider userProvider,
    int index,
  ) {
    // Determine wallet type and styling
    String walletType = '';
    IconData walletIcon = Icons.account_balance_wallet_rounded;
    Color iconColor = Colors.blue;
    Color cardColor = Colors.blue.withOpacity(0.05);

    if (wallet.ownerId == userProvider.partnershipId) {
      walletType = ' (Chung)';
      walletIcon = Icons.people_rounded;
      iconColor = Colors.orange;
      cardColor = Colors.orange.withOpacity(0.05);
    } else if (wallet.ownerId == userProvider.currentUser?.uid) {
      walletType = ' (Cá nhân)';
      walletIcon = Icons.person_rounded;
      iconColor = Colors.green;
      cardColor = Colors.green.withOpacity(0.05);
    } else if (wallet.ownerId == userProvider.partnerUid) {
      walletType = ' (Đối tác)';
      walletIcon = Icons.supervisor_account_rounded;
      iconColor = Colors.purple;
      cardColor = Colors.purple.withOpacity(0.05);
    }

    return AnimatedContainer(
      duration: Duration(milliseconds: 300 + (index * 100)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: iconColor.withOpacity(0.2), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Main Wallet Info
            ListTile(
              contentPadding: const EdgeInsets.all(20),
              leading: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(walletIcon, color: iconColor, size: 24),
              ),
              title: Text(
                '${wallet.name}$walletType',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
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
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        wallet.isVisibleToPartner
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                        size: 16,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        wallet.isVisibleToPartner
                            ? 'Hiển thị với đối tác'
                            : 'Ẩn với đối tác',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: _buildWalletActions(wallet, userProvider),
            ),

            // Visibility Toggle (if applicable)
            if (wallet.ownerId == userProvider.currentUser?.uid &&
                userProvider.hasPartner) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(Icons.visibility_rounded, size: 18, color: iconColor),
                    const SizedBox(width: 8),
                    const Text(
                      'Hiển thị với đối tác',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Switch(
                      value: wallet.isVisibleToPartner,
                      onChanged: (value) => _toggleVisibility(wallet, value),
                      activeColor: iconColor,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWalletActions(Wallet wallet, UserProvider userProvider) {
    final isOwner =
        wallet.ownerId == userProvider.currentUser?.uid ||
        wallet.ownerId == userProvider.partnershipId;

    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: Colors.grey.shade600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (action) => _handleWalletAction(action, wallet),
      itemBuilder: (context) => [
        if (isOwner) ...[
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
            value: 'adjust',
            child: Row(
              children: [
                Icon(Icons.tune_rounded, size: 18, color: Colors.orange),
                SizedBox(width: 8),
                Text('Điều chỉnh số dư'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'archive',
            child: Row(
              children: [
                Icon(Icons.archive_rounded, size: 18, color: Colors.purple),
                SizedBox(width: 8),
                Text('Lưu trữ'),
              ],
            ),
          ),
          const PopupMenuDivider(),
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
            const Text(
              'Chưa có ví nào',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tạo ví đầu tiên để bắt đầu quản lý tài chính',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddWalletDialog,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tạo ví đầu tiên'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Đang xử lý...'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============ ACTION HANDLERS ============

  void _handleWalletAction(String action, Wallet wallet) {
    switch (action) {
      case 'edit':
        _showEditWalletDialog(wallet);
        break;
      case 'adjust':
        _showAdjustBalanceDialog(wallet);
        break;
      case 'archive':
        _showArchiveWalletDialog(wallet);
        break;
      case 'delete':
        _showDeleteWalletDialog(wallet);
        break;
      case 'view':
        _showWalletDetails(wallet);
        break;
    }
  }

  void _toggleVisibility(Wallet wallet, bool isVisible) async {
    try {
      await _databaseService.updateWalletVisibility(wallet.id, isVisible);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isVisible
                ? 'Ví đã được hiển thị với đối tác'
                : 'Ví đã được ẩn khỏi đối tác',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Lỗi khi cập nhật: $e');
    }
  }

  // ============ DIALOGS ============

  void _showAddWalletDialog() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
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
                        const Text(
                          'Tạo ví mới',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Wallet Name
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Tên ví',
                        hintText: 'Ví dụ: Tiền mặt, Ngân hàng...',
                        prefixIcon: const Icon(Icons.wallet_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      autofocus: true,
                    ),

                    const SizedBox(height: 16),

                    // Initial Balance
                    SmartAmountInput(
                      controller: balanceController,
                      labelText: 'Số dư ban đầu',
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
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.attach_money_rounded),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
                              userProvider,
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

  void _showEditWalletDialog(Wallet wallet) {
    final nameController = TextEditingController(text: wallet.name);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  const Text(
                    'Chỉnh sửa ví',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Tên ví',
                  prefixIcon: const Icon(Icons.wallet_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                autofocus: true,
              ),

              const SizedBox(height: 24),

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
                      onPressed: () =>
                          _updateWallet(wallet, nameController.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cập nhật'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAdjustBalanceDialog(Wallet wallet) {
    final balanceController = TextEditingController(
      text: NumberFormat('#,###', 'vi_VN').format(wallet.balance),
    );
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Colors.purple,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Điều chỉnh số dư\n${wallet.name}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Current Balance Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text(
                      'Số dư hiện tại: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(wallet.balance)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // New Balance
              SmartAmountInput(
                controller: balanceController,
                labelText: 'Số dư mới',
                hintText: 'Nhập số dư thực tế...',
                showQuickButtons: false,
                showSuggestions: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.account_balance_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Reason
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Lý do điều chỉnh',
                  hintText: 'Ví dụ: Cập nhật theo số dư thực tế...',
                  prefixIcon: const Icon(Icons.note_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 2,
              ),

              const SizedBox(height: 24),

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
                      onPressed: () => _adjustBalance(
                        wallet,
                        balanceController.text,
                        reasonController.text.trim(),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Điều chỉnh'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteWalletDialog(Wallet wallet) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: Colors.red,
                size: 20,
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
            Text('Bạn có chắc chắn muốn xóa ví "${wallet.name}" không?'),
            const SizedBox(height: 8),
            const Text(
              'Lưu ý: Ví chỉ có thể xóa khi không còn giao dịch nào. Nếu có giao dịch, ví sẽ được lưu trữ thay vì xóa.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontStyle: FontStyle.italic,
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
            onPressed: () => _deleteWallet(wallet),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Xóa ví'),
          ),
        ],
      ),
    );
  }

  void _showArchiveWalletDialog(Wallet wallet) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Lưu trữ ví'),
        content: Text(
          'Bạn có muốn lưu trữ ví "${wallet.name}" không?\n\nVí đã lưu trữ sẽ không hiển thị trong danh sách chính nhưng vẫn giữ nguyên dữ liệu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => _archiveWallet(wallet),
            child: const Text('Lưu trữ'),
          ),
        ],
      ),
    );
  }

  void _showWalletDetails(Wallet wallet) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(wallet.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            _buildDetailRow(
              'Số dư',
              NumberFormat.currency(
                locale: 'vi_VN',
                symbol: '₫',
              ).format(wallet.balance),
            ),
            _buildDetailRow(
              'Trạng thái',
              wallet.isVisibleToPartner
                  ? 'Hiển thị với đối tác'
                  : 'Ẩn với đối tác',
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }

  void _showWalletAnalytics() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Phân tích ví'),
        content: const Text('Tính năng phân tích chi tiết sẽ sớm ra mắt!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  // ============ BUSINESS LOGIC ============

  Future<void> _createWallet(
    String name,
    String balanceText,
    String ownerType,
    UserProvider userProvider,
  ) async {
    if (name.isEmpty) {
      _showErrorSnackBar('Vui lòng nhập tên ví');
      return;
    }

    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      final balance = parseAmount(balanceText);
      final String ownerId;

      if (ownerType == 'shared' && userProvider.partnershipId != null) {
        ownerId = userProvider.partnershipId!;
      } else {
        ownerId = FirebaseAuth.instance.currentUser!.uid;
      }

      await _databaseService.addWallet(name, balance, ownerId);

      _showSuccessSnackBar('Tạo ví "$name" thành công');
    } catch (e) {
      _showErrorSnackBar('Lỗi khi tạo ví: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateWallet(Wallet wallet, String newName) async {
    if (newName.isEmpty) {
      _showErrorSnackBar('Tên ví không được để trống');
      return;
    }

    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      final updatedWallet = Wallet(
        id: wallet.id,
        name: newName,
        balance: wallet.balance,
        ownerId: wallet.ownerId,
        isVisibleToPartner: wallet.isVisibleToPartner,
      );

      await _databaseService.updateWallet(updatedWallet);
      _showSuccessSnackBar('Cập nhật ví thành công');
    } catch (e) {
      _showErrorSnackBar('Lỗi khi cập nhật: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteWallet(Wallet wallet) async {
    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      await _databaseService.deleteWallet(wallet.id);
      _showSuccessSnackBar('Xóa ví "${wallet.name}" thành công');
    } catch (e) {
      if (e.toString().contains('giao dịch')) {
        // If wallet has transactions, offer to archive instead
        _showArchiveInsteadDialog(wallet);
      } else {
        _showErrorSnackBar('Lỗi khi xóa: $e');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _archiveWallet(Wallet wallet) async {
    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      await _databaseService.archiveWallet(wallet.id);
      _showSuccessSnackBar('Đã lưu trữ ví "${wallet.name}"');
    } catch (e) {
      _showErrorSnackBar('Lỗi khi lưu trữ: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _adjustBalance(
    Wallet wallet,
    String newBalanceText,
    String reason,
  ) async {
    if (reason.isEmpty) {
      _showErrorSnackBar('Vui lòng nhập lý do điều chỉnh');
      return;
    }

    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      final newBalance = parseAmount(newBalanceText);
      await _databaseService.adjustWalletBalance(wallet.id, newBalance, reason);

      final difference = newBalance - wallet.balance;
      final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

      _showSuccessSnackBar(
        'Điều chỉnh thành công: ${difference >= 0 ? '+' : ''}${formatter.format(difference)}',
      );
    } catch (e) {
      _showErrorSnackBar('Lỗi khi điều chỉnh: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showArchiveInsteadDialog(Wallet wallet) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.info_rounded,
                color: Colors.orange,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Không thể xóa ví'),
          ],
        ),
        content: Text(
          'Ví "${wallet.name}" đang có giao dịch nên không thể xóa.\n\n'
          'Bạn có muốn lưu trữ ví này thay thế? Ví sẽ được ẩn khỏi danh sách chính.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _archiveWallet(wallet);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Lưu trữ'),
          ),
        ],
      ),
    );
  }

  // ============ HELPER METHODS ============

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
