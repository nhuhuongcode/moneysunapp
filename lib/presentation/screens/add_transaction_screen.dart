import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
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
  final OfflineSyncService _offlineSyncService = OfflineSyncService();

  TransactionType _selectedType = TransactionType.expense;
  String? _selectedWalletId;
  String? _selectedCategoryId;
  String? _selectedSubCategoryId;
  DateTime _selectedDate = DateTime.now();

  bool _isOnline = false;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  List<String> _filteredSuggestions = [];

  bool _isLoading = false;
  List<String> _descriptionHistory = [];

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadDescriptionHistory();
    if (widget.transactionToEdit != null) {
      _populateFieldsForEdit();
    }
  }

  Future<void> _initializeServices() async {
    await _offlineSyncService.initialize();
    setState(() {
      _isOnline = _offlineSyncService.isOnline;
    });

    // Listen to connectivity changes
    _offlineSyncService.addListener(() {
      if (mounted) {
        setState(() {
          _isOnline = _offlineSyncService.isOnline;
        });
      }
    });
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
      final history = await _offlineSyncService.getDescriptionSuggestions(
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
            const SizedBox(width: 8),
            // THÊM MỚI: Connection status indicator
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _isOnline ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isOnline ? Icons.cloud_done : Icons.cloud_off,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
              padding: const EdgeInsets.fromLTRB(
                16.0,
                16.0,
                16.0,
                80.0,
              ), // Thêm padding bottom để tránh che khuất
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
          // Nút hoàn thành cố định ở dưới cùng
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

  // Cập nhật style cho transaction type selector
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
                    // TODO: Implement navigation to add wallet screen
                    // Navigator.push(context, MaterialPageRoute(...));
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Tạo ví mới'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            );
          }

          // Main dropdown for wallet selection
          return Column(
            children: [
              DropdownButtonFormField<String>(
                value: _selectedWalletId,
                isExpanded: true, // Ensures the dropdown takes full width
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
                  // Customize display for each wallet type
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
                icon: Icon(
                  Icons.arrow_drop_down,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              // Add wallet button
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    // TODO: Implement navigation to add wallet screen
                    // Navigator.push(context, MaterialPageRoute(...));
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

  // FIX: Category selector riêng biệt cho income và expense
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

          // Nếu là income mà không có category nào
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
                    _selectedSubCategoryId = null; // Reset sub category
                  });
                },
                // FIX: Category không bắt buộc cho income
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
            builder: (context, child) {
              return Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: ColorScheme.light(
                    primary: Theme.of(context).colorScheme.primary,
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
                      primary: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  child: child!,
                );
              },
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
          // THAY ĐỔI: Sử dụng Autocomplete widget
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textEditingValue) async {
              if (textEditingValue.text.isEmpty) {
                return _descriptionHistory.take(5);
              }

              // THÊM MỚI: Search trong local database
              final userId = FirebaseAuth.instance.currentUser?.uid;
              if (userId != null) {
                final suggestions = await _offlineSyncService
                    .searchDescriptionHistory(userId, textEditingValue.text);
                return suggestions;
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
                  // Sync với controller chính
                  _descriptionController.text = controller.text;

                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: InputDecoration(
                      hintText: 'Nhập mô tả...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      prefixIcon: const Icon(Icons.description_outlined),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                controller.clear();
                                _descriptionController.clear();
                              },
                            )
                          : null,
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
                  elevation: 4.0,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    width: MediaQuery.of(context).size.width - 32,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          leading: const Icon(
                            Icons.history,
                            size: 18,
                            color: Colors.grey,
                          ),
                          title: Text(
                            option,
                            style: const TextStyle(fontSize: 14),
                          ),
                          onTap: () => onSelected(option),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),

          // THÊM MỚI: Quick access chips for recent descriptions
          if (_descriptionHistory.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Gợi ý nhanh:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _descriptionHistory.take(3).map((desc) {
                return ActionChip(
                  label: Text(desc, style: const TextStyle(fontSize: 12)),
                  onPressed: () {
                    _descriptionController.text = desc;
                    // Trigger autocomplete update
                    setState(() {});
                  },
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
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
        // CẬP NHẬT: Use online service for updates
        await _databaseService.updateTransaction(
          transaction,
          widget.transactionToEdit!,
        );
      } else {
        // THAY ĐỔI: Use offline-first for new transactions
        await _offlineSyncService.addTransaction(transaction);
      }

      // Hiển thị trạng thái sync
      final syncMessage = _isOnline
          ? 'Đã thêm giao dịch và đồng bộ'
          : 'Đã lưu giao dịch (sẽ đồng bộ khi có mạng)';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                _isOnline ? Icons.cloud_done : Icons.cloud_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(syncMessage),
            ],
          ),
          backgroundColor: _isOnline ? Colors.green : Colors.orange,
        ),
      );

      Navigator.pop(context);
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
