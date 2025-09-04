// lib/presentation/screens/manage_wallets_screen.dart - ENHANCED VERSION
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/sync_status_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'package:moneysun/presentation/widgets/connection_status_banner.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManageWalletsScreen extends StatefulWidget {
  const ManageWalletsScreen({super.key});

  @override
  State<ManageWalletsScreen> createState() => _ManageWalletsScreenState();
}

class _ManageWalletsScreenState extends State<ManageWalletsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final OfflineSyncService _syncService = OfflineSyncService();

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final syncProvider = Provider.of<SyncStatusProvider>(context);
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Nguồn tiền (Ví)'),
        actions: [
          // Sync status indicator
          if (syncProvider.pendingCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sync, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 4),
                  Text(
                    '${syncProvider.pendingCount}',
                    style: TextStyle(
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          IconButton(
            icon: const Icon(Icons.add_card),
            onPressed: () => _showAddWalletDialog(),
            tooltip: 'Thêm ví',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner
          const EnhancedConnectionStatusBanner(
            showWhenOnline: false,
            showDetailedInfo: false,
          ),

          // Wallets list
          Expanded(
            child: StreamBuilder<List<Wallet>>(
              stream: _databaseService.getWalletsStream(userProvider),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.red.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Lỗi tải dữ liệu ví',
                          style: TextStyle(color: Colors.red.shade600),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 80,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có ví nào',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Hãy tạo ví đầu tiên để bắt đầu quản lý tài chính',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: () => _showAddWalletDialog(),
                            icon: const Icon(Icons.add),
                            label: const Text('Tạo ví mới'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final wallets = snapshot.data!;
                final totalBalance = wallets.fold(
                  0.0,
                  (sum, wallet) => sum + wallet.balance,
                );

                return RefreshIndicator(
                  onRefresh: () async {
                    if (syncProvider.isOnline) {
                      try {
                        await syncProvider.forceSyncNow();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Lỗi đồng bộ: $e')),
                        );
                      }
                    }
                    setState(() {});
                  },
                  child: Column(
                    children: [
                      // Total balance card
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).primaryColor,
                              Theme.of(context).primaryColor.withOpacity(0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Tổng tài sản',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Icon(
                                  Icons.account_balance_wallet,
                                  color: Colors.white.withOpacity(0.8),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              currencyFormatter.format(totalBalance),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${wallets.length} ví',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Wallets list
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: wallets.length,
                          itemBuilder: (context, index) {
                            final wallet = wallets[index];
                            return _buildWalletCard(
                              wallet,
                              userProvider,
                              currencyFormatter,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletCard(
    Wallet wallet,
    UserProvider userProvider,
    NumberFormat currencyFormatter,
  ) {
    // Determine wallet type and permissions
    final isOwner = wallet.ownerId == FirebaseAuth.instance.currentUser?.uid;
    final isSharedWallet = wallet.ownerId == userProvider.partnershipId;
    final isPartnerWallet = wallet.ownerId == userProvider.partnerUid;

    String walletTypeLabel = '';
    IconData walletIcon = Icons.account_balance_wallet;
    Color walletColor = Colors.blue;

    if (isSharedWallet) {
      walletTypeLabel = 'Ví chung';
      walletIcon = Icons.people;
      walletColor = Colors.green;
    } else if (isPartnerWallet) {
      walletTypeLabel = 'Ví đối tác';
      walletIcon = Icons.person;
      walletColor = Colors.orange;
    } else if (isOwner) {
      walletTypeLabel = 'Ví cá nhân';
      walletIcon = Icons.person;
      walletColor = Colors.blue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showWalletDetailsDialog(wallet, userProvider),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  // Wallet icon
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: walletColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(walletIcon, color: walletColor, size: 24),
                  ),
                  const SizedBox(width: 16),

                  // Wallet info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                wallet.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (walletTypeLabel.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: walletColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  walletTypeLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: walletColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currencyFormatter.format(wallet.balance),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: wallet.balance >= 0
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action buttons
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Visibility toggle (only for owned wallets)
                      if (isOwner && userProvider.hasPartner)
                        IconButton(
                          icon: Icon(
                            wallet.isVisibleToPartner
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: wallet.isVisibleToPartner
                                ? Colors.green
                                : Colors.grey,
                          ),
                          onPressed: () => _toggleWalletVisibility(wallet),
                          tooltip: wallet.isVisibleToPartner
                              ? 'Ẩn khỏi đối tác'
                              : 'Hiện với đối tác',
                        ),

                      // Edit button (only for owned wallets or shared wallets)
                      if (isOwner || isSharedWallet)
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showEditWalletDialog(wallet),
                          tooltip: 'Chỉnh sửa ví',
                        ),

                      // Delete button (only for owned wallets)
                      if (isOwner)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _showDeleteWalletDialog(wallet),
                          tooltip: 'Xóa ví',
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_card, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Thêm ví mới'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên ví',
                        prefixIcon: Icon(Icons.account_balance_wallet),
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: balanceController,
                      decoration: const InputDecoration(
                        labelText: 'Số dư ban đầu',
                        prefixIcon: Icon(Icons.attach_money),
                        suffixText: '₫',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),

                    if (userProvider.partnershipId != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Loại ví:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      RadioListTile<String>(
                        title: const Row(
                          children: [
                            Icon(Icons.person, size: 20),
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
                            Icon(Icons.people, size: 20),
                            SizedBox(width: 8),
                            Text('Ví chung'),
                          ],
                        ),
                        subtitle: const Text('Cả hai cùng quản lý'),
                        value: 'shared',
                        groupValue: ownerType,
                        onChanged: (value) =>
                            setDialogState(() => ownerType = value!),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () => _createWallet(
                    nameController.text,
                    balanceController.text,
                    ownerType,
                    userProvider,
                  ),
                  child: const Text('Tạo ví'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditWalletDialog(Wallet wallet) {
    final nameController = TextEditingController(text: wallet.name);
    final balanceController = TextEditingController(
      text: wallet.balance.toString(),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.edit, color: Colors.blue),
              const SizedBox(width: 8),
              Text('Chỉnh sửa "${wallet.name}"'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên ví',
                  prefixIcon: Icon(Icons.account_balance_wallet),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: balanceController,
                decoration: const InputDecoration(
                  labelText: 'Số dư hiện tại',
                  prefixIcon: Icon(Icons.attach_money),
                  suffixText: '₫',
                  border: OutlineInputBorder(),
                  helperText: 'Chỉnh sửa cẩn thận để tránh sai lệch dữ liệu',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => _updateWallet(
                wallet,
                nameController.text,
                balanceController.text,
              ),
              child: const Text('Cập nhật'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteWalletDialog(Wallet wallet) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('Xác nhận xóa ví'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bạn có chắc chắn muốn xóa ví "${wallet.name}" không?'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info, color: Colors.red, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Lưu ý quan trọng:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '• Tất cả giao dịch liên quan sẽ bị ảnh hưởng',
                      style: TextStyle(fontSize: 12),
                    ),
                    const Text(
                      '• Hành động này không thể hoàn tác',
                      style: TextStyle(fontSize: 12),
                    ),
                    Text(
                      '• Số dư hiện tại: ${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(wallet.balance)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Xóa ví',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showWalletDetailsDialog(Wallet wallet, UserProvider userProvider) {
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                wallet.ownerId == userProvider.partnershipId
                    ? Icons.people
                    : Icons.account_balance_wallet,
                color: Theme.of(context).primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(wallet.name, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Số dư hiện tại',
                currencyFormatter.format(wallet.balance),
              ),
              _buildDetailRow(
                'Loại ví',
                wallet.ownerId == userProvider.partnershipId
                    ? 'Ví chung'
                    : wallet.ownerId == FirebaseAuth.instance.currentUser?.uid
                    ? 'Ví cá nhân'
                    : 'Ví đối tác',
              ),
              if (userProvider.hasPartner &&
                  wallet.ownerId == FirebaseAuth.instance.currentUser?.uid)
                _buildDetailRow(
                  'Hiển thị với đối tác',
                  wallet.isVisibleToPartner ? 'Có' : 'Không',
                ),
              _buildDetailRow('ID ví', wallet.id),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
            if (wallet.ownerId == FirebaseAuth.instance.currentUser?.uid ||
                wallet.ownerId == userProvider.partnershipId)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showEditWalletDialog(wallet);
                },
                child: const Text('Chỉnh sửa'),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Future<void> _createWallet(
    String name,
    String balanceText,
    String ownerType,
    UserProvider userProvider,
  ) async {
    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên ví')));
      return;
    }

    final balance = double.tryParse(balanceText) ?? 0.0;
    final String ownerId;

    if (ownerType == 'shared' && userProvider.partnershipId != null) {
      ownerId = userProvider.partnershipId!;
    } else {
      ownerId = FirebaseAuth.instance.currentUser!.uid;
    }

    try {
      await _databaseService.addWalletOffline(name.trim(), balance, ownerId);

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã tạo ví "${name.trim()}"'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi tạo ví: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _updateWallet(
    Wallet wallet,
    String name,
    String balanceText,
  ) async {
    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Vui lòng nhập tên ví')));
      return;
    }

    final newBalance = double.tryParse(balanceText) ?? wallet.balance;

    try {
      // Create updated wallet
      final updatedWallet = Wallet(
        id: wallet.id,
        name: name.trim(),
        balance: newBalance,
        ownerId: wallet.ownerId,
        isVisibleToPartner: wallet.isVisibleToPartner,
      );

      // Update using Firebase directly for immediate effect
      await FirebaseDatabase.instance
          .ref()
          .child('wallets')
          .child(wallet.id)
          .update({
            'name': updatedWallet.name,
            'balance': updatedWallet.balance,
          });

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã cập nhật ví "${name.trim()}"'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Fallback to offline sync
      try {
        final updatedWallet = Wallet(
          id: wallet.id,
          name: name.trim(),
          balance: newBalance,
          ownerId: wallet.ownerId,
          isVisibleToPartner: wallet.isVisibleToPartner,
        );

        await _syncService.addWalletOffline(updatedWallet);

        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '💾 Đã lưu cập nhật ví "${name.trim()}" (sẽ đồng bộ khi có mạng)',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (offlineError) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi cập nhật ví: $offlineError'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteWallet(Wallet wallet) async {
    try {
      // Delete from Firebase
      await FirebaseDatabase.instance
          .ref()
          .child('wallets')
          .child(wallet.id)
          .remove();

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Đã xóa ví "${wallet.name}"'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi xóa ví: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _toggleWalletVisibility(Wallet wallet) async {
    try {
      await _databaseService.updateWalletVisibility(
        wallet.id,
        !wallet.isVisibleToPartner,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wallet.isVisibleToPartner
                ? '👁️‍🗨️ Đã ẩn ví "${wallet.name}" khỏi đối tác'
                : '👁️ Đã hiện ví "${wallet.name}" với đối tác',
          ),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi thay đổi hiển thị: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
