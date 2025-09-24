// lib/presentation/screens/add_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/presentation/widgets/category_widgets.dart';
import 'package:provider/provider.dart';

// Models
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';

// Providers
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/wallet_provider.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/transaction_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';

// Widgets
import 'package:moneysun/presentation/widgets/smart_amount_input.dart';

// Screens
import 'package:moneysun/presentation/screens/transfer_screen.dart';

class AddTransactionScreen extends StatefulWidget {
  final TransactionModel? transactionToEdit;

  const AddTransactionScreen({super.key, this.transactionToEdit});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen>
    with TickerProviderStateMixin {
  // Form and Controllers
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  // Animation Controllers
  late AnimationController _fadeAnimationController;
  late Animation<double> _fadeAnimation;

  // Form State
  TransactionType _selectedType = TransactionType.expense;
  String? _selectedWalletId;
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  DateTime _selectedDate = DateTime.now();

  // UI State
  bool _isLoading = false;
  bool _isInitialized = false;
  List<String> _descriptionHistory = [];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadInitialData();
  }

  @override
  void dispose() {
    _fadeAnimationController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeAnimationController,
      curve: Curves.easeInOut,
    );
  }

  void _loadInitialData() {
    if (widget.transactionToEdit != null) {
      _populateFieldsForEdit();
    }
    _loadDescriptionHistory();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _fadeAnimationController.forward();
        setState(() => _isInitialized = true);
      }
    });
  }

  void _populateFieldsForEdit() {
    final transaction = widget.transactionToEdit!;
    _amountController.text = NumberFormat(
      '#,###',
      'vi_VN',
    ).format(transaction.amount);
    _descriptionController.text = transaction.description;
    _selectedType = transaction.type;
    _selectedWalletId = transaction.walletId;
    _selectedCategoryId = transaction.categoryId;
    _selectedSubCategoryId = transaction.subCategoryId;
    _selectedDate = transaction.date;
  }

  void _loadDescriptionHistory() {
    // TODO: Load from actual data service
    _descriptionHistory = [
      'Ăn trưa',
      'Cà phê',
      'Xăng xe',
      'Siêu thị',
      'Điện thoại',
      'Internet',
      'Thuê nhà',
      'Ăn sáng',
      'Grab',
      'Shopee',
    ];
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child:
            Consumer5<
              UserProvider,
              WalletProvider,
              CategoryProvider,
              TransactionProvider,
              ConnectionStatusProvider
            >(
              builder:
                  (
                    context,
                    userProvider,
                    walletProvider,
                    categoryProvider,
                    transactionProvider,
                    connectionStatus,
                    child,
                  ) {
                    if (!_isInitialized) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    return Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          // Main Content
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.05),
                                    Theme.of(context).scaffoldBackgroundColor,
                                    Theme.of(
                                      context,
                                    ).primaryColor.withOpacity(0.02),
                                  ],
                                  stops: const [0.0, 0.5, 1.0],
                                ),
                              ),
                              child: SingleChildScrollView(
                                physics: const ClampingScrollPhysics(),
                                padding: const EdgeInsets.all(20),
                                child: FadeTransition(
                                  opacity: _fadeAnimation,
                                  child: Column(
                                    children: [
                                      // Transaction Type Selector
                                      _buildTransactionTypeSelector(),
                                      const SizedBox(height: 24),

                                      // Amount Input
                                      _buildAmountInput(),
                                      const SizedBox(height: 20),

                                      // Wallet Selector
                                      _buildWalletSelector(
                                        walletProvider,
                                        userProvider,
                                      ),
                                      const SizedBox(height: 20),

                                      // Category Selector
                                      _buildCategorySelector(
                                        categoryProvider,
                                        userProvider,
                                      ),

                                      // Sub-category Selector (conditional)
                                      if (_selectedCategoryId != null) ...[
                                        const SizedBox(height: 20),
                                        _buildSubCategorySelector(
                                          categoryProvider,
                                        ),
                                      ],

                                      const SizedBox(height: 20),

                                      // Date Selector
                                      _buildDateSelector(),
                                      const SizedBox(height: 20),

                                      // Description Input
                                      _buildDescriptionInput(),
                                      const SizedBox(height: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Submit Button
                          _buildBottomSubmitButton(
                            transactionProvider,
                            connectionStatus,
                          ),
                        ],
                      ),
                    );
                  },
            ),
      ),
    );
  }

  // ============ APP BAR ============
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
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: Row(
        children: [
          Text(
            widget.transactionToEdit != null
                ? 'Sửa giao dịch'
                : 'Thêm giao dịch',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleLarge?.color,
            ),
          ),
          const SizedBox(width: 12),
          Consumer<ConnectionStatusProvider>(
            builder: (context, connectionStatus, child) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
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
            },
          ),
        ],
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
            icon: const Icon(Icons.swap_horiz_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransferScreen()),
              );
            },
            tooltip: 'Chuyển tiền',
          ),
        ),
      ],
    );
  }

  // ============ TRANSACTION TYPE SELECTOR ============
  Widget _buildTransactionTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTypeOption(
              TransactionType.expense,
              Icons.trending_down_rounded,
              'Chi tiêu',
              Colors.red.shade600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTypeOption(
              TransactionType.income,
              Icons.trending_up_rounded,
              'Thu nhập',
              Colors.green.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypeOption(
    TransactionType type,
    IconData icon,
    String label,
    Color color,
  ) {
    final isSelected = _selectedType == type;

    return GestureDetector(
      onTap: () => _safeSetState(() {
        _selectedType = type;
        _selectedCategoryId = null;
        _selectedSubCategoryId = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  colors: [color.withOpacity(0.8), color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : color,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============ AMOUNT INPUT ============
  Widget _buildAmountInput() {
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
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.payments_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Số tiền',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.titleLarge?.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SmartAmountInput(
            controller: _amountController,
            labelText: null,
            hintText: 'Nhập số tiền...',
            categoryType: _selectedType == TransactionType.income
                ? 'income'
                : _selectedType == TransactionType.expense
                ? 'food'
                : 'transfer',
            showQuickButtons: true,
            showSuggestions: true,
            onChanged: (amount) {
              // Handle amount changes if needed
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Vui lòng nhập số tiền';
              }
              final amount = parseAmount(value);
              if (amount <= 0) {
                return 'Số tiền phải lớn hơn 0';
              }
              return null;
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).primaryColor.withOpacity(0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              prefixIcon: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.attach_money_rounded,
                  color: Theme.of(context).primaryColor,
                  size: 18,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ WALLET SELECTOR ============
  Widget _buildWalletSelector(
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
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Chọn ví',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Consumer<WalletProvider>(
            builder: (context, walletProvider, child) {
              if (walletProvider.isLoading) {
                return _buildLoadingState();
              }

              if (walletProvider.hasError) {
                return _buildErrorState(
                  walletProvider.error ?? 'Unknown error',
                );
              }

              final wallets = walletProvider.wallets;
              if (wallets.isEmpty) {
                return _buildEmptyWalletState(walletProvider, userProvider);
              }

              // Validate selected wallet still exists
              if (_selectedWalletId != null &&
                  !wallets.any((w) => w.id == _selectedWalletId)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _safeSetState(() => _selectedWalletId = null);
                });
              }

              return _buildWalletDropdown(wallets, userProvider);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWalletDropdown(List<Wallet> wallets, UserProvider userProvider) {
    return DropdownButtonFormField<String>(
      value: _selectedWalletId,
      isExpanded: true,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.blue.withOpacity(0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.blue, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        hintText: 'Chọn ví của bạn',
        prefixIcon: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.wallet_rounded, color: Colors.blue, size: 18),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 16,
        ),
      ),
      items: wallets.map((wallet) {
        final walletDisplayInfo = _getWalletDisplayInfo(wallet, userProvider);

        return DropdownMenuItem<String>(
          value: wallet.id,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: walletDisplayInfo.iconColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  walletDisplayInfo.icon,
                  color: walletDisplayInfo.iconColor,
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      walletDisplayInfo.displayName,
                      overflow: TextOverflow.ellipsis,
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
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) => _safeSetState(() => _selectedWalletId = value),
      validator: (value) => value == null ? 'Vui lòng chọn ví' : null,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
    );
  }

  Widget _buildEmptyWalletState(
    WalletProvider walletProvider,
    UserProvider userProvider,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          const Text(
            'Chưa có ví nào',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Hãy tạo ví đầu tiên của bạn',
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showQuickCreateWalletDialog(walletProvider),
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

  // ============ CATEGORY SELECTOR ============
  Widget _buildCategorySelector(
    CategoryProvider categoryProvider,
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
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.category_rounded,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _selectedType == TransactionType.income
                    ? 'Nguồn thu nhập'
                    : 'Danh mục chi tiêu',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Consumer<CategoryProvider>(
            builder: (context, categoryProvider, child) {
              if (categoryProvider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              final allCategories = categoryProvider.categories;
              final categories = allCategories
                  .where(
                    (cat) =>
                        cat.type ==
                        (_selectedType == TransactionType.income
                            ? 'income'
                            : 'expense'),
                  )
                  .toList();

              if (categories.isEmpty) {
                return _buildEmptyCategoryState(categoryProvider, userProvider);
              }

              return Column(
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.purple.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.purple,
                          width: 2,
                        ),
                      ),
                      hintText: _selectedType == TransactionType.income
                          ? 'Chọn nguồn thu nhập'
                          : 'Chọn danh mục',
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.category_outlined,
                          color: Colors.purple,
                          size: 18,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    items: categories.map((category) {
                      return DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          category.name,
                          style: const TextStyle(fontSize: 15),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      _safeSetState(() {
                        _selectedCategoryId = value;
                        _selectedSubCategoryId = null;
                      });
                    },
                    validator: _selectedType == TransactionType.expense
                        ? (value) =>
                              value == null ? 'Vui lòng chọn danh mục' : null
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _showAddCategoryDialog(
                        categoryProvider,
                        userProvider,
                      ),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        'Thêm danh mục ${_selectedType == TransactionType.income ? "thu nhập" : "chi tiêu"}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.purple,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCategoryState(
    CategoryProvider categoryProvider,
    UserProvider userProvider,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.purple.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.purple.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(
            Icons.category_outlined,
            size: 48,
            color: Colors.purple.shade300,
          ),
          const SizedBox(height: 12),
          Text(
            'Chưa có danh mục ${_selectedType == TransactionType.income ? "thu nhập" : "chi tiêu"} nào',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () =>
                _showAddCategoryDialog(categoryProvider, userProvider),
            icon: const Icon(Icons.add_rounded),
            label: Text(
              'Tạo danh mục ${_selectedType == TransactionType.income ? "thu nhập" : "chi tiêu"}',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ SUB-CATEGORY SELECTOR ============
  Widget _buildSubCategorySelector(CategoryProvider categoryProvider) {
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
                  color: Colors.indigo.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  color: Colors.indigo,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Danh mục con (tùy chọn)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Consumer<CategoryProvider>(
            builder: (context, categoryProvider, child) {
              final categories = categoryProvider.categories;
              final selectedCategory = categories.firstWhere(
                (cat) => cat.id == _selectedCategoryId,
                orElse: () => const Category(
                  id: '',
                  name: '',
                  ownerId: '',
                  type: 'expense',
                ),
              );

              if (selectedCategory.subCategories.isEmpty) {
                return _buildEmptySubCategoryState(selectedCategory.id);
              }

              return DropdownButtonFormField<String>(
                value: _selectedSubCategoryId,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.indigo.withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Colors.indigo,
                      width: 2,
                    ),
                  ),
                  hintText: 'Chọn danh mục con (tùy chọn)',
                  prefixIcon: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.label_outline_rounded,
                      color: Colors.indigo,
                      size: 18,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
                items: selectedCategory.subCategories.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(
                      entry.value,
                      style: const TextStyle(fontSize: 15),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  _safeSetState(() => _selectedSubCategoryId = value);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySubCategoryState(String parentCategoryId) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: Colors.indigo.shade300,
            size: 20,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Chưa có danh mục con',
              style: TextStyle(
                color: Colors.indigo,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ DATE SELECTOR ============
  Widget _buildDateSelector() {
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
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.schedule_rounded,
                  color: Colors.teal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Thời gian',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _selectDateTime,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.teal.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_today_rounded,
                      color: Colors.teal,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DateFormat(
                            'EEEE, dd MMMM yyyy',
                            'vi_VN',
                          ).format(_selectedDate),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('HH:mm').format(_selectedDate),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: Colors.teal.shade400,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============ DESCRIPTION INPUT ============
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
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Mô tả (tùy chọn)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return _descriptionHistory.take(5);
              }

              return _descriptionHistory
                  .where(
                    (desc) => desc.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  )
                  .take(5);
            },
            onSelected: (String selection) {
              _descriptionController.text = selection;
            },
            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
                  _descriptionController.text = controller.text;

                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.amber.withOpacity(0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Colors.amber,
                          width: 2,
                        ),
                      ),
                      hintText: 'Nhập mô tả cho giao dịch...',
                      hintStyle: TextStyle(color: Colors.grey.shade400),
                      prefixIcon: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.edit_note_rounded,
                          color: Colors.amber,
                          size: 18,
                        ),
                      ),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                controller.clear();
                                _descriptionController.clear();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                    ),
                    maxLines: 2,
                    onChanged: (value) {
                      _descriptionController.text = value;
                    },
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    width: MediaQuery.of(context).size.width - 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          leading: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.history_rounded,
                              size: 16,
                              color: Colors.amber,
                            ),
                          ),
                          title: Text(
                            option,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          if (_descriptionHistory.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: Colors.amber.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  'Gợi ý nhanh:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.amber.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: _descriptionHistory.take(3).map((desc) {
                return ActionChip(
                  avatar: Icon(
                    Icons.history_rounded,
                    size: 16,
                    color: Colors.amber.shade700,
                  ),
                  label: Text(desc, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _descriptionController.text = desc;
                    _safeSetState(() {});
                  },
                  backgroundColor: Colors.amber.withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: Colors.amber.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  side: BorderSide(
                    color: Colors.amber.withOpacity(0.3),
                    width: 1,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ============ BOTTOM SUBMIT BUTTON ============
  Widget _buildBottomSubmitButton(
    TransactionProvider transactionProvider,
    ConnectionStatusProvider connectionStatus,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).primaryColor.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading
                ? null
                : () => _submitForm(transactionProvider, connectionStatus),
            borderRadius: BorderRadius.circular(20),
            child: Center(
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
                          'Đang xử lý...',
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
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          widget.transactionToEdit != null
                              ? 'CẬP NHẬT GIAO DỊCH'
                              : 'HOÀN THÀNH',
                          style: const TextStyle(
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
      ),
    );
  }

  // ============ UTILITY WIDGETS ============
  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
            ),
          ),
          const SizedBox(width: 12),
          const Text('Đang tải...'),
        ],
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
                'Không thể tải dữ liệu',
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
              _safeSetState(() {});
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

  // ============ HELPER METHODS ============
  WalletDisplayInfo _getWalletDisplayInfo(
    Wallet wallet,
    UserProvider userProvider,
  ) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;

    if (wallet.ownerId == userProvider.partnershipId) {
      return WalletDisplayInfo(
        displayName: '${wallet.name} (Chung)',
        icon: Icons.people_rounded,
        iconColor: Colors.orange,
        ownershipType: 'shared',
      );
    } else if (wallet.ownerId == currentUserId) {
      return WalletDisplayInfo(
        displayName: '${wallet.name} (Cá nhân)',
        icon: Icons.person_rounded,
        iconColor: Colors.green,
        ownershipType: 'personal',
      );
    } else if (wallet.ownerId == userProvider.partnerUid) {
      return WalletDisplayInfo(
        displayName: '${wallet.name} (Đối tác)',
        icon: Icons.supervisor_account_rounded,
        iconColor: Colors.purple,
        ownershipType: 'partner',
      );
    } else {
      return WalletDisplayInfo(
        displayName: wallet.name,
        icon: Icons.account_balance_wallet_rounded,
        iconColor: Colors.blue,
        ownershipType: 'unknown',
      );
    }
  }

  // ============ DIALOG METHODS ============
  void _showQuickCreateWalletDialog(WalletProvider walletProvider) {
    final nameController = TextEditingController();
    final balanceController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tạo ví nhanh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Tên ví',
                hintText: 'VD: Tiền mặt, Ngân hàng...',
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

  void _showAddCategoryDialog(
    CategoryProvider categoryProvider,
    UserProvider userProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) => CategoryCreationDialog(
        type: _selectedType == TransactionType.income ? 'income' : 'expense',
        userProvider: userProvider,
        onCreated: (name, ownershipType) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã tạo danh mục "$name" thành công'),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  Future<void> _selectDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
            datePickerTheme: DatePickerThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (date != null) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDate),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: ColorScheme.light(
                primary: Colors.teal,
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black,
              ),
              timePickerTheme: TimePickerThemeData(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            child: child!,
          );
        },
      );

      if (time != null) {
        _safeSetState(() {
          _selectedDate = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          );
        });
      }
    }
  }

  Future<void> _submitForm(
    TransactionProvider transactionProvider,
    ConnectionStatusProvider connectionStatus,
  ) async {
    if (!_formKey.currentState!.validate()) return;

    _safeSetState(() => _isLoading = true);

    try {
      final amount = parseAmount(_amountController.text);
      final transaction = TransactionModel(
        id:
            widget.transactionToEdit?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        amount: amount,
        type: _selectedType,
        categoryId: _selectedCategoryId,
        subCategoryId: _selectedSubCategoryId,
        walletId: _selectedWalletId!,
        date: _selectedDate,
        description: _descriptionController.text.trim(),
        userId: FirebaseAuth.instance.currentUser!.uid,
      );

      final success = await transactionProvider.addTransaction(transaction);

      if (success) {
        final syncMessage = connectionStatus.isOnline
            ? 'Giao dịch đã được lưu và đồng bộ thành công'
            : 'Giao dịch đã được lưu (sẽ đồng bộ khi có mạng)';

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    connectionStatus.isOnline
                        ? Icons.cloud_done_rounded
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

          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Failed to add transaction');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('Có lỗi xảy ra: $e')),
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
      _safeSetState(() => _isLoading = false);
    }
  }
}

// ============ DATA CLASSES ============
class WalletDisplayInfo {
  final String displayName;
  final IconData icon;
  final Color iconColor;
  final String ownershipType;

  const WalletDisplayInfo({
    required this.displayName,
    required this.icon,
    required this.iconColor,
    required this.ownershipType,
  });
}
