// lib/presentation/screens/add_transaction_screen.dart - UPDATED VERSION

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/sync_status_provider.dart'; // NEW
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart'; // NEW
import 'package:moneysun/presentation/screens/transfer_screen.dart';
import 'package:provider/provider.dart';

class AddTransactionScreen extends StatefulWidget {
  final TransactionModel? transactionToEdit;

  const AddTransactionScreen({super.key, this.transactionToEdit});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();
  final OfflineSyncService _syncService = OfflineSyncService(); // NEW

  TransactionType _selectedType = TransactionType.expense;
  String? _selectedWalletId;
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = false;
  List<String> _descriptionHistory = [];

  @override
  void initState() {
    super.initState();
    _loadDescriptionHistory();
    if (widget.transactionToEdit != null) {
      _populateFieldsForEdit();
    }
  }

  void _populateFieldsForEdit() {
    final transaction = widget.transactionToEdit!;
    _amountController.text = transaction.amount.toString();
    _descriptionController.text = transaction.description;
    _selectedType = transaction.type;
    _selectedWalletId = transaction.walletId;
    _selectedCategoryId = transaction.categoryId;
    _selectedSubCategoryId = transaction.subCategoryId;
    _selectedDate = transaction.date;
  }

  Future<void> _loadDescriptionHistory() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      // NEW: Use sync service for offline-first description history
      final history = await _syncService.getDescriptionSuggestions(
        userId,
        limit: 10,
      );
      setState(() {
        _descriptionHistory = history;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final syncProvider = Provider.of<SyncStatusProvider>(context); // NEW

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.primary,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(
              widget.transactionToEdit != null
                  ? 'Sửa giao dịch'
                  : 'Thêm giao dịch',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),

            // NEW: Enhanced connection status with sync provider
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: syncProvider.isOnline ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    syncProvider.isOnline ? Icons.cloud_done : Icons.cloud_off,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    syncProvider.isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // NEW: Show pending count when offline
                  if (!syncProvider.isOnline &&
                      syncProvider.pendingCount > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(${syncProvider.pendingCount})',
                      style: const TextStyle(fontSize: 10, color: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TransferScreen()),
              );
            },
            tooltip: 'Chuyển tiền',
          ),
        ],
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
              children: [
                _buildTransactionTypeSelector(),
                const SizedBox(height: 16),
                _buildAmountInput(),
                const SizedBox(height: 16),
                _buildWalletSelector(userProvider),
                const SizedBox(height: 16),
                _buildCategorySelector(),
                if (_selectedCategoryId != null) ...[
                  const SizedBox(height: 16),
                  _buildSubCategorySelector(),
                ],
                const SizedBox(height: 16),
                _buildDateSelector(),
                const SizedBox(height: 16),
                _buildDescriptionInput(),
              ],
            ),
          ),

          // Fixed bottom button
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitForm,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text(
                        'HOÀN THÀNH',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ... (Giữ nguyên tất cả các build methods khác: _buildCard, _buildTransactionTypeSelector, etc.)

  Widget _buildCard({required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTypeSelector() {
    return _buildCard(
      title: 'Loại giao dịch',
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedType = TransactionType.expense;
                _selectedCategoryId = null;
                _selectedSubCategoryId = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedType == TransactionType.expense
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedType == TransactionType.expense
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.remove_circle_outline,
                      color: _selectedType == TransactionType.expense
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Chi tiêu',
                      style: TextStyle(
                        color: _selectedType == TransactionType.expense
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedType = TransactionType.income;
                _selectedCategoryId = null;
                _selectedSubCategoryId = null;
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _selectedType == TransactionType.income
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _selectedType == TransactionType.income
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_circle_outline,
                      color: _selectedType == TransactionType.income
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Thu nhập',
                      style: TextStyle(
                        color: _selectedType == TransactionType.income
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountInput() {
    return _buildCard(
      title: 'Số tiền',
      child: TextFormField(
        controller: _amountController,
        decoration: InputDecoration(
          hintText: '0đ',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          suffixText: '₫',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        keyboardType: TextInputType.number,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return 'Vui lòng nhập số tiền';
          }
          final amount = double.tryParse(value);
          if (amount == null || amount <= 0) {
            return 'Số tiền phải lớn hơn 0';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildWalletSelector(UserProvider userProvider) {
    return _buildCard(
      title: 'Chọn ví',
      child: StreamBuilder<List<Wallet>>(
        stream: _databaseService.getSelectableWalletsStream(userProvider),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final wallets = snapshot.data!;
          if (wallets.isEmpty) {
            return Column(
              children: [
                const Text(
                  'Chưa có ví nào',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    // Navigate to add wallet screen
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo ví mới'),
                ),
              ],
            );
          }

          return Column(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedWalletId,
                isExpanded: true,
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.05),
                  hintText: 'Chọn ví',
                ),
                items: wallets.map((wallet) {
                  String displayName = wallet.name;
                  IconData icon;
                  Widget? trailing;

                  if (wallet.ownerId == userProvider.partnershipId) {
                    displayName += ' (Chung)';
                    icon = Icons.people_outline;
                    trailing = const Icon(Icons.group, size: 16);
                  } else if (wallet.ownerId ==
                      FirebaseAuth.instance.currentUser?.uid) {
                    displayName += ' (Cá nhân)';
                    icon = Icons.person_outline;
                    trailing = const Icon(Icons.person, size: 16);
                  } else {
                    icon = Icons.account_balance_wallet_outlined;
                  }

                  return DropdownMenuItem<String>(
                    value: wallet.id,
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        if (trailing != null) trailing,
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() => _selectedWalletId = value);
                },
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng chọn ví';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    // Navigate to add wallet screen
                  },
                  icon: Icon(
                    Icons.add,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  label: Text(
                    'Thêm ví mới',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCategorySelector() {
    return _buildCard(
      title: _selectedType == TransactionType.income
          ? 'Nguồn thu nhập'
          : 'Danh mục chi tiêu',
      child: StreamBuilder<List<Category>>(
        stream: _databaseService.getCategoriesByTypeStream(
          _selectedType == TransactionType.income ? 'income' : 'expense',
        ),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const CircularProgressIndicator();
          }

          final categories = snapshot.data!;

          if (_selectedType == TransactionType.income && categories.isEmpty) {
            return Column(
              children: [
                const Text(
                  'Chưa có danh mục thu nhập. Hãy tạo danh mục trước!',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _showAddCategoryDialog(),
                  child: const Text('Tạo danh mục thu nhập'),
                ),
              ],
            );
          }

          return Column(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedCategoryId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: Text(
                  _selectedType == TransactionType.income
                      ? 'Chọn nguồn thu nhập'
                      : 'Chọn danh mục',
                ),
                items: categories.map((category) {
                  return DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategoryId = value;
                    _selectedSubCategoryId = null;
                  });
                },
                validator: _selectedType == TransactionType.expense
                    ? (value) {
                        if (value == null) {
                          return 'Vui lòng chọn danh mục';
                        }
                        return null;
                      }
                    : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _showAddCategoryDialog(),
                  icon: const Icon(Icons.add),
                  label: Text(
                    'Thêm danh mục ${_selectedType == TransactionType.income ? "thu nhập" : "chi tiêu"}',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSubCategorySelector() {
    return _buildCard(
      title: 'Danh mục con (tùy chọn)',
      child: StreamBuilder<List<Category>>(
        stream: _databaseService.getCategoriesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const CircularProgressIndicator();
          }

          final categories = snapshot.data!;
          final selectedCategory = categories.firstWhere(
            (cat) => cat.id == _selectedCategoryId,
            orElse: () =>
                const Category(id: '', name: '', ownerId: '', type: 'expense'),
          );

          if (selectedCategory.subCategories.isEmpty) {
            return Column(
              children: [
                const Text(
                  'Chưa có danh mục con',
                  style: TextStyle(color: Colors.grey),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _showAddSubCategoryDialog(selectedCategory.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm danh mục con'),
                ),
              ],
            );
          }

          return Column(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedSubCategoryId,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                hint: const Text('Chọn danh mục con (tùy chọn)'),
                items: selectedCategory.subCategories.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedSubCategoryId = value;
                  });
                },
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () =>
                      _showAddSubCategoryDialog(selectedCategory.id),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm danh mục con'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDateSelector() {
    return _buildCard(
      title: 'Thời gian',
      child: InkWell(
        onTap: () async {
          final date = await showDatePicker(
            context: context,
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 365)),
          );
          if (date != null) {
            final time = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(_selectedDate),
            );
            setState(() {
              _selectedDate = DateTime(
                date.year,
                date.month,
                date.day,
                time?.hour ?? _selectedDate.hour,
                time?.minute ?? _selectedDate.minute,
              );
            });
          }
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
            color: Theme.of(context).colorScheme.primary.withOpacity(0.05),
          ),
          child: Row(
            children: [
              Icon(
                Icons.event_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('dd/MM/yyyy').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    DateFormat('HH:mm').format(_selectedDate),
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionInput() {
    return _buildCard(
      title: 'Mô tả (tùy chọn)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Smart Autocomplete với enhanced features
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) async {
              final userId = FirebaseAuth.instance.currentUser?.uid;
              if (userId == null) return <String>[];

              if (textEditingValue.text.isEmpty) {
                // Return contextual and recent suggestions when empty
                final contextualSuggestions = await _syncService
                    .getContextualSuggestions(
                      userId,
                      type: _selectedType,
                      categoryId: _selectedCategoryId,
                      amount: double.tryParse(_amountController.text),
                      limit: 3,
                    );

                final recentSuggestions = await _syncService
                    .getDescriptionSuggestions(
                      userId,
                      limit: 5,
                      type: _selectedType,
                    );

                // Combine and deduplicate
                final combined = <String>{
                  ...contextualSuggestions,
                  ...recentSuggestions,
                }.toList();

                return combined.take(8);
              }

              // Advanced search with fuzzy matching
              final searchResults = await _syncService.searchDescriptionHistory(
                userId,
                textEditingValue.text,
                limit: 6,
                type: _selectedType,
                fuzzySearch: true,
              );

              return searchResults;
            },
            onSelected: (String selection) {
              _descriptionController.text = selection;

              // Save usage for learning (async without blocking UI)
              _saveDescriptionUsage(selection);
            },
            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
                  // Sync với controller chính
                  controller.text = _descriptionController.text;
                  controller.selection = _descriptionController.selection;

                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: InputDecoration(
                      hintText: _getHintTextByType(),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        ),
                      ),
                      prefixIcon: Icon(
                        _getIconByType(),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      suffixIcon: controller.text.isNotEmpty
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Smart learning indicator
                                Tooltip(
                                  message:
                                      'Mô tả này sẽ được học để gợi ý tương lai',
                                  child: Icon(
                                    Icons.psychology,
                                    color: Colors.purple.shade400,
                                    size: 18,
                                  ),
                                ),
                                // Clear button
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    controller.clear();
                                    _descriptionController.clear();
                                    setState(() {});
                                  },
                                  tooltip: 'Xóa',
                                ),
                              ],
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surface.withOpacity(0.5),
                    ),
                    maxLines: 2,
                    maxLength: 100,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onChanged: (value) {
                      // Sync với external controller
                      _descriptionController.text = value;
                      _descriptionController.selection = controller.selection;
                      setState(() {}); // Rebuild để update character count
                    },
                    onFieldSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        _saveDescriptionUsage(value.trim());
                      }
                    },
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              return _buildAdvancedOptionsView(context, onSelected, options);
            },
          ),

          const SizedBox(height: 12),

          // Context indicator và quick suggestions
          _buildContextualInfo(),

          const SizedBox(height: 12),

          // Quick suggestion chips
          _buildQuickSuggestionChips(),

          const SizedBox(height: 8),

          // Statistics row
          _buildStatisticsRow(),
        ],
      ),
    );
  }

  // Helper method để get hint text dựa trên transaction type
  String _getHintTextByType() {
    switch (_selectedType) {
      case TransactionType.income:
        return 'VD: Lương tháng 11, Thưởng dự án, Bán hàng online...';
      case TransactionType.expense:
        return 'VD: Ăn trưa, Xăng xe, Mua quần áo...';
      case TransactionType.transfer:
        return 'VD: Chuyển tiền tiết kiệm, Nạp ví điện tử...';
    }
  }

  // Helper method để get icon dựa trên transaction type
  IconData _getIconByType() {
    switch (_selectedType) {
      case TransactionType.income:
        return Icons.trending_up;
      case TransactionType.expense:
        return Icons.trending_down;
      case TransactionType.transfer:
        return Icons.swap_horiz;
    }
  }

  // Advanced options view với visual indicators
  Widget _buildAdvancedOptionsView(
    BuildContext context,
    Function(String) onSelected,
    Iterable<String> options,
  ) {
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 8.0,
        borderRadius: BorderRadius.circular(12),
        shadowColor: Colors.black.withOpacity(0.1),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 320),
          width: MediaQuery.of(context).size.width - 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            color: Colors.white,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: Theme.of(context).colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Gợi ý thông minh',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${options.length} kết quả',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),

              // Options list
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shrinkWrap: true,
                  itemCount: options.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: Colors.grey.shade100,
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    final isContextual = _isContextualSuggestion(option);
                    final isRecent = _isRecentSuggestion(option);

                    return ListTile(
                      dense: true,
                      leading: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: _getSuggestionColor(
                            isContextual,
                            isRecent,
                          ).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getSuggestionIcon(isContextual, isRecent),
                          color: _getSuggestionColor(isContextual, isRecent),
                          size: 16,
                        ),
                      ),
                      title: Text(
                        option,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _buildSuggestionBadge(isContextual, isRecent),
                      onTap: () => onSelected(option),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Context info hiển thị thông tin về transaction hiện tại
  Widget _buildContextualInfo() {
    if (_selectedType == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getTypeColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getTypeColor().withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(_getIconByType(), color: _getTypeColor(), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _getContextInfo(),
              style: TextStyle(
                fontSize: 13,
                color: _getTypeColor().withOpacity(0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (_descriptionController.text.isNotEmpty)
            Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
        ],
      ),
    );
  }

  String _getContextInfo() {
    final parts = <String>[];

    switch (_selectedType) {
      case TransactionType.income:
        parts.add('Thu nhập');
        break;
      case TransactionType.expense:
        parts.add('Chi tiêu');
        break;
      case TransactionType.transfer:
        parts.add('Chuyển tiền');
        break;
    }

    if (_selectedCategoryId != null) {
      // You would get the actual category name here
      parts.add('có danh mục');
    }

    final amount = double.tryParse(_amountController.text);
    if (amount != null) {
      parts.add(
        '${NumberFormat.currency(locale: 'vi_VN', symbol: '₫').format(amount)}',
      );
    }

    return 'AI đang gợi ý cho: ${parts.join(' • ')}';
  }

  Color _getTypeColor() {
    switch (_selectedType) {
      case TransactionType.income:
        return Colors.green;
      case TransactionType.expense:
        return Colors.red;
      case TransactionType.transfer:
        return Colors.orange;
    }
  }

  // Quick suggestion chips dựa trên context
  Widget _buildQuickSuggestionChips() {
    return FutureBuilder<List<String>>(
      future: _loadQuickSuggestions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final suggestions = snapshot.data!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flash_on, size: 16, color: Colors.amber.shade600),
                const SizedBox(width: 6),
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
              spacing: 6,
              runSpacing: 4,
              children: suggestions.take(4).map((suggestion) {
                return ActionChip(
                  label: Text(suggestion, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _descriptionController.text = suggestion;
                    _saveDescriptionUsage(suggestion);
                    setState(() {});

                    // Dismiss keyboard
                    FocusScope.of(context).unfocus();
                  },
                  backgroundColor: Colors.amber.shade50,
                  labelStyle: TextStyle(
                    color: Colors.amber.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  side: BorderSide(color: Colors.amber.shade200, width: 0.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  // Statistics row hiển thị thống kê
  Widget _buildStatisticsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Character count
        if (_descriptionController.text.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200, width: 0.5),
            ),
            child: Text(
              '${_descriptionController.text.length}/100',
              style: TextStyle(
                fontSize: 11,
                color: Colors.blue.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          const SizedBox.shrink(),

        // AI learning indicator
        if (_descriptionController.text.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.purple.shade200, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.psychology, color: Colors.purple.shade600, size: 12),
                const SizedBox(width: 4),
                Text(
                  'AI đang học',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.purple.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // Helper methods
  Future<List<String>> _loadQuickSuggestions() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return [];

    try {
      return await _syncService.getContextualSuggestions(
        userId,
        type: _selectedType,
        categoryId: _selectedCategoryId,
        amount: double.tryParse(_amountController.text),
        limit: 4,
      );
    } catch (e) {
      return [];
    }
  }

  bool _isContextualSuggestion(String suggestion) {
    // This would check if suggestion is from contextual suggestions
    // For now, simple heuristic
    return suggestion.length > 5; // Contextual suggestions tend to be longer
  }

  bool _isRecentSuggestion(String suggestion) {
    // This would check if suggestion is from recent suggestions
    return !_isContextualSuggestion(suggestion);
  }

  Color _getSuggestionColor(bool isContextual, bool isRecent) {
    if (isContextual) return Colors.purple;
    if (isRecent) return Colors.blue;
    return Colors.grey;
  }

  IconData _getSuggestionIcon(bool isContextual, bool isRecent) {
    if (isContextual) return Icons.auto_awesome;
    if (isRecent) return Icons.history;
    return Icons.description;
  }

  Widget? _buildSuggestionBadge(bool isContextual, bool isRecent) {
    if (isContextual) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.purple.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.purple.shade200, width: 0.5),
        ),
        child: Text(
          'Smart',
          style: TextStyle(
            fontSize: 10,
            color: Colors.purple.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (isRecent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blue.shade200, width: 0.5),
        ),
        child: Text(
          'Gần đây',
          style: TextStyle(
            fontSize: 10,
            color: Colors.blue.shade700,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return null;
  }

  // Save description usage for AI learning
  Future<void> _saveDescriptionUsage(String description) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || description.trim().isEmpty) return;

    try {
      await _syncService.saveDescriptionWithContext(
        userId,
        description.trim(),
        type: _selectedType,
        categoryId: _selectedCategoryId,
        amount: double.tryParse(_amountController.text),
      );

      print('💾 Saved description with context for learning: $description');
    } catch (e) {
      print('⚠️ Failed to save description usage: $e');
    }
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Thêm ${_selectedType == TransactionType.income ? "nguồn thu nhập" : "danh mục chi tiêu"}',
        ),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Tên danh mục',
            border: OutlineInputBorder(),
          ),
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
                await _databaseService.addCategory(
                  name,
                  _selectedType == TransactionType.income
                      ? 'income'
                      : 'expense',
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showAddSubCategoryDialog(String parentCategoryId) {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm danh mục con'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Tên danh mục con',
            border: OutlineInputBorder(),
          ),
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
                await _databaseService.addSubCategory(parentCategoryId, name);
                Navigator.pop(context);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final amount = double.parse(_amountController.text);
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

      if (widget.transactionToEdit != null) {
        // For updates, use DatabaseService (requires online)
        await _databaseService.updateTransaction(
          transaction,
          widget.transactionToEdit!,
        );
      } else {
        // NEW: For new transactions, use offline-first approach
        await _syncService.addTransactionOffline(transaction);
      }

      // NEW: Save description with context for smart suggestions
      if (_descriptionController.text.trim().isNotEmpty) {
        await _syncService.saveDescriptionWithContext(
          FirebaseAuth.instance.currentUser!.uid,
          _descriptionController.text.trim(),
          type: _selectedType,
          categoryId: _selectedCategoryId,
          amount: amount,
        );
      }

      // Show appropriate message based on sync status
      final syncProvider = Provider.of<SyncStatusProvider>(
        context,
        listen: false,
      );
      final syncMessage = syncProvider.isOnline
          ? 'Đã thêm giao dịch và đồng bộ'
          : 'Đã lưu giao dịch (sẽ đồng bộ khi có mạng)';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                syncProvider.isOnline ? Icons.cloud_done : Icons.cloud_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(syncMessage)),
              // NEW: Show smart learning indicator
              if (_descriptionController.text.trim().isNotEmpty)
                Icon(
                  Icons.psychology,
                  color: Colors.white.withOpacity(0.8),
                  size: 16,
                ),
            ],
          ),
          backgroundColor: syncProvider.isOnline ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );

      // Return success flag to parent screen for UI refresh
      Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }
}
