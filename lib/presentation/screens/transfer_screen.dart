// lib/presentation/screens/transfer_screen_.dart
import 'package:flutter/material.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  // State
  Wallet? _fromWallet;
  Wallet? _toWallet;
  bool _isLoading = false;

  // Animations
  late AnimationController _slideController;
  late AnimationController _swapController;
  late Animation<double> _slideAnimation;
  late Animation<double> _swapAnimation;

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _swapController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    );
    _swapAnimation = CurvedAnimation(
      parent: _swapController,
      curve: Curves.elasticOut,
    );

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    _swapController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _swapWallets() {
    if (_fromWallet != null && _toWallet != null) {
      _swapController.forward().then((_) {
        setState(() {
          final temp = _fromWallet;
          _fromWallet = _toWallet;
          _toWallet = temp;
        });
        _swapController.reverse();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<
      UserProvider,
      WalletProvider,
      TransactionProvider,
      ConnectionStatusProvider
    >(
      builder:
          (
            context,
            userProvider,
            walletProvider,
            transactionProvider,
            connectionStatus,
            child,
          ) {
            return Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              appBar: _buildAppBar(connectionStatus),
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
                              Colors.blue.withOpacity(0.1),
                              Theme.of(context).scaffoldBackgroundColor,
                              Colors.green.withOpacity(0.05),
                            ],
                          ),
                        ),
                      ),

                      // Main Content
                      Form(
                        key: _formKey,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                          children: [
                            // Transfer Header Card
                            FadeTransition(
                              opacity: _slideAnimation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, -0.3),
                                  end: Offset.zero,
                                ).animate(_slideAnimation),
                                child: _buildTransferHeaderCard(
                                  connectionStatus,
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Smart Amount Input
                            FadeTransition(
                              opacity: _slideAnimation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(-0.3, 0),
                                  end: Offset.zero,
                                ).animate(_slideAnimation),
                                child: _buildSmartAmountInput(),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Transfer Flow Visualization
                            FadeTransition(
                              opacity: _slideAnimation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(_slideAnimation),
                                child: _buildTransferFlowCard(
                                  walletProvider,
                                  userProvider,
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Description Input
                            FadeTransition(
                              opacity: _slideAnimation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0.3, 0),
                                  end: Offset.zero,
                                ).animate(_slideAnimation),
                                child: _buildDescriptionInput(),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Floating Submit Button
                      _buildFloatingSubmitButton(
                        transactionProvider,
                        connectionStatus,
                      ),
                    ],
                  );
                },
              ),
            );
          },
    );
  }

  PreferredSizeWidget _buildAppBar(ConnectionStatusProvider connectionStatus) {
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
      title: Row(
        children: [
          const Text(
            'Chuyển tiền',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          const SizedBox(width: 12),
          _buildConnectionStatusBadge(connectionStatus),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusBadge(
    ConnectionStatusProvider connectionStatus,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: connectionStatus.isOnline
            ? Colors.green.withOpacity(0.15)
            : Colors.orange.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connectionStatus.isOnline
              ? Colors.green.withOpacity(0.3)
              : Colors.orange.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (connectionStatus.isSyncing)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  connectionStatus.isOnline
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
              ),
            )
          else
            Icon(
              connectionStatus.isOnline
                  ? Icons.wifi_rounded
                  : Icons.wifi_off_rounded,
              size: 14,
              color: connectionStatus.isOnline
                  ? Colors.green.shade700
                  : Colors.orange.shade700,
            ),
          const SizedBox(width: 6),
          Text(
            connectionStatus.isSyncing
                ? 'Syncing'
                : (connectionStatus.isOnline ? 'Online' : 'Offline'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: connectionStatus.isOnline
                  ? Colors.green.shade800
                  : Colors.orange.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferHeaderCard(ConnectionStatusProvider connectionStatus) {
    return Container(
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Chuyển tiền giữa các ví',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Di chuyển tiền từ ví này sang ví khác một cách dễ dàng',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
            ),
          ),

          // Sync status indicator
          if (!connectionStatus.isOnline) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chuyển tiền sẽ được lưu và đồng bộ khi có mạng',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSmartAmountInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade400, Colors.green.shade600],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.payments_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Số tiền chuyển',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SmartAmountInput(
            controller: _amountController,
            labelText: null,
            hintText: 'Nhập số tiền cần chuyển...',
            categoryType: 'transfer',
            showQuickButtons: true,
            showSuggestions: true,
            customSuggestions: [
              100000,
              200000,
              500000,
              1000000,
              2000000,
              5000000,
            ],
            onChanged: (amount) {
              // Update validation or other logic if needed
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Vui lòng nhập số tiền cần chuyển';
              }
              final amount = parseAmount(value);
              if (amount <= 0) {
                return 'Số tiền phải lớn hơn 0';
              }
              if (_fromWallet != null && amount > _fromWallet!.balance) {
                return 'Số dư không đủ (${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(_fromWallet!.balance)})';
              }
              return null;
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.green.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.green, width: 2),
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.attach_money_rounded,
                  color: Colors.green,
                  size: 18,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),

          // Balance Information
          if (_fromWallet != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.blue.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.blue.shade600,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Số dư hiện tại: ',
                    style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    NumberFormat.currency(
                      locale: 'vi_VN',
                      symbol: '₫',
                    ).format(_fromWallet!.balance),
                    style: TextStyle(
                      color: Colors.blue.shade800,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransferFlowCard(
    WalletProvider walletProvider,
    UserProvider userProvider,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.orange,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Chọn ví chuyển tiền',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              // Swap Button
              AnimatedBuilder(
                animation: _swapAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _swapAnimation.value * 3.14159,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: IconButton(
                        onPressed: _swapWallets,
                        icon: const Icon(
                          Icons.swap_vert_rounded,
                          color: Colors.orange,
                        ),
                        tooltip: 'Hoán đổi ví',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          StreamBuilder<List<Wallet>>(
            stream: walletProvider.getWalletsStream(),
            builder: (context, snapshot) {
              if (walletProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (walletProvider.hasError) {
                return _buildErrorState(
                  walletProvider.error ?? 'Unknown error',
                );
              }

              final wallets = walletProvider.wallets;
              final eligibleWallets = wallets
                  .where((w) => walletProvider.canEditWallet(w))
                  .toList();

              if (eligibleWallets.length < 2) {
                return _buildInsufficientWalletsState(walletProvider);
              }

              return Column(
                children: [
                  // From Wallet
                  _buildWalletSelector(
                    title: 'Từ ví',
                    selectedWallet: _fromWallet,
                    wallets: eligibleWallets,
                    onChanged: (wallet) => setState(() => _fromWallet = wallet),
                    icon: Icons.call_made_rounded,
                    color: Colors.red,
                    excludeWallet: _toWallet,
                    userProvider: userProvider,
                  ),

                  const SizedBox(height: 20),

                  // Transfer Arrow
                  _buildTransferArrow(),

                  const SizedBox(height: 20),

                  // To Wallet
                  _buildWalletSelector(
                    title: 'Đến ví',
                    selectedWallet: _toWallet,
                    wallets: eligibleWallets,
                    onChanged: (wallet) => setState(() => _toWallet = wallet),
                    icon: Icons.call_received_rounded,
                    color: Colors.green,
                    excludeWallet: _fromWallet,
                    userProvider: userProvider,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWalletSelector({
    required String title,
    required Wallet? selectedWallet,
    required List<Wallet> wallets,
    required Function(Wallet?) onChanged,
    required IconData icon,
    required Color color,
    Wallet? excludeWallet,
    required UserProvider userProvider,
  }) {
    final availableWallets = wallets.where((w) => w != excludeWallet).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<Wallet>(
            value: selectedWallet,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 2),
              ),
              hintText: 'Chọn ví',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            items: availableWallets.map((wallet) {
              return DropdownMenuItem<Wallet>(
                value: wallet,
                child: _buildWalletItem(wallet, userProvider),
              );
            }).toList(),
            onChanged: onChanged,
            validator: (value) => value == null ? 'Vui lòng chọn ví' : null,
          ),
        ],
      ),
    );
  }

  Widget _buildWalletItem(Wallet wallet, UserProvider userProvider) {
    String walletType = '';
    IconData walletIcon = Icons.account_balance_wallet_rounded;
    Color iconColor = Colors.blue;

    if (wallet.ownerId == userProvider.partnershipId) {
      walletType = ' (Chung)';
      walletIcon = Icons.people_rounded;
      iconColor = Colors.orange;
    } else if (wallet.ownerId == userProvider.currentUser?.uid) {
      walletType = ' (Cá nhân)';
      walletIcon = Icons.person_rounded;
      iconColor = Colors.green;
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(walletIcon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${wallet.name}$walletType',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                NumberFormat.currency(
                  locale: 'vi_VN',
                  symbol: '₫',
                ).format(wallet.balance),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransferArrow() {
    return Container(
      height: 60,
      child: Stack(
        children: [
          // Dashed Line
          Positioned.fill(
            child: CustomPaint(
              painter: DashedLinePainter(color: Colors.orange.withOpacity(0.3)),
            ),
          ),
          // Arrow Container
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade400, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.south_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsufficientWalletsState(WalletProvider walletProvider) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          const Text(
            'Cần ít nhất 2 ví để chuyển tiền',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Hãy tạo thêm ví để sử dụng tính năng chuyển tiền',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showCreateWalletDialog(walletProvider),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Tạo ví mới'),
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateWalletDialog(WalletProvider walletProvider) {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo ví mới'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Tên ví',
                hintText: 'VD: Tiết kiệm, Đầu tư...',
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: balanceController,
              decoration: const InputDecoration(
                labelText: 'Số dư ban đầu (₫)',
                hintText: '0',
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
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                try {
                  final balance =
                      double.tryParse(balanceController.text) ?? 0.0;

                  await walletProvider.addWallet(
                    name: name,
                    initialBalance: balance,
                  );

                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Đã tạo ví "$name" thành công'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Lỗi khi tạo ví: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.note_add_rounded,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Ghi chú (tùy chọn)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.purple.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.purple, width: 2),
              ),
              hintText: 'Nhập ghi chú cho giao dịch chuyển tiền...',
              hintStyle: TextStyle(color: Colors.grey.shade400),
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Colors.purple,
                  size: 18,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
            maxLines: 3,
          ),

          // Quick Description Options
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: Colors.purple.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Gợi ý nhanh:',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.purple.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children:
                [
                  'Chuyển tiền tạm ứng',
                  'Hoàn trả tiền',
                  'Dự phòng khẩn cấp',
                ].map((desc) {
                  return ActionChip(
                    label: Text(desc, style: const TextStyle(fontSize: 12)),
                    onPressed: () {
                      _descriptionController.text = desc;
                    },
                    backgroundColor: Colors.purple.withOpacity(0.1),
                    labelStyle: TextStyle(
                      color: Colors.purple.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: Colors.purple.withOpacity(0.3),
                      width: 1,
                    ),
                  );
                }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingSubmitButton(
    TransactionProvider transactionProvider,
    ConnectionStatusProvider connectionStatus,
  ) {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 20,
      child: AnimatedScale(
        scale: _isLoading ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue.shade600, Colors.green.shade500],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.4),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ElevatedButton(
            onPressed: _isLoading
                ? null
                : () => _submitTransfer(transactionProvider, connectionStatus),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Đang chuyển...',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'THỰC HIỆN CHUYỂN TIỀN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _submitTransfer(
    TransactionProvider transactionProvider,
    ConnectionStatusProvider connectionStatus,
  ) async {
    if (!_formKey.currentState!.validate()) return;

    if (_fromWallet == null || _toWallet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Vui lòng chọn đầy đủ ví nguồn và ví đích'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    if (_fromWallet!.id == _toWallet!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.warning_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Ví nguồn và ví đích không được trùng nhau'),
              ),
            ],
          ),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final amount = parseAmount(_amountController.text);

      // Check balance again before transfer
      if (amount > _fromWallet!.balance) {
        throw Exception('Số dư không đủ để thực hiện giao dịch');
      }

      final description = _descriptionController.text.trim().isEmpty
          ? 'Chuyển tiền'
          : _descriptionController.text.trim();

      // Create transfer transaction using TransactionProvider
      final transferTransaction = TransactionModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        amount: amount,
        type: TransactionType.transfer,
        walletId: _fromWallet!.id,
        transferToWalletId: _toWallet!.id,
        date: DateTime.now(),
        description: description,
        userId: FirebaseAuth.instance.currentUser!.uid,
        walletName: _fromWallet!.name,
        transferFromWalletName: _fromWallet!.name,
        transferToWalletName: _toWallet!.name,
      );

      final success = await transactionProvider.addTransaction(
        transferTransaction,
      );

      if (success) {
        if (mounted) {
          // Success animation and navigation
          await _showSuccessAnimation();

          final syncMessage = connectionStatus.isOnline
              ? 'Chuyển tiền thành công và đã đồng bộ!'
              : 'Chuyển tiền thành công (sẽ đồng bộ khi có mạng)';

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    connectionStatus.isOnline
                        ? Icons.check_circle_rounded
                        : Icons.cloud_off_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(syncMessage)),
                ],
              ),
              backgroundColor: connectionStatus.isOnline
                  ? Colors.green
                  : Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );

          Navigator.pop(context);
        }
      } else {
        throw Exception('Failed to create transfer transaction');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Lỗi: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showSuccessAnimation() async {
    // Show a simple success dialog with animation
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                const Text(
                  'Chuyển tiền thành công!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tiền đã được chuyển từ ${_fromWallet?.name} sang ${_toWallet?.name}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Không thể tải danh sách ví',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Vui lòng kiểm tra kết nối mạng và thử lại',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              setState(() {});
            },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Thử lại'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Painter for Dashed Line
class DashedLinePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  DashedLinePainter({
    required this.color,
    this.strokeWidth = 2,
    this.dashWidth = 5,
    this.dashSpace = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final path = Path();
    final centerY = size.height / 2;

    double startX = 0;
    while (startX < size.width) {
      path.moveTo(startX, centerY);
      path.lineTo((startX + dashWidth).clamp(0, size.width), centerY);
      startX += dashWidth + dashSpace;
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
