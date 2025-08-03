import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
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
    final history = await _databaseService.getDescriptionHistory();
    setState(() {
      _descriptionHistory = history;
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.transactionToEdit != null ? 'Sửa giao dịch' : 'Thêm giao dịch',
        ),
        actions: [
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else
            TextButton(onPressed: _submitForm, child: const Text('LƯU')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // Transaction Type Selector
            _buildTransactionTypeSelector(),
            const SizedBox(height: 16),

            // Amount Input
            _buildAmountInput(),
            const SizedBox(height: 16),

            // Wallet Selector - FIX: Chỉ hiển thị ví có thể chọn
            _buildWalletSelector(userProvider),
            const SizedBox(height: 16),

            // Category Selector - FIX: Khác nhau cho income và expense
            _buildCategorySelector(),
            const SizedBox(height: 16),

            // Sub Category Selector (chỉ hiển thị khi có category được chọn)
            if (_selectedCategoryId != null) ...[
              _buildSubCategorySelector(),
              const SizedBox(height: 16),
            ],

            // Date Picker
            _buildDateSelector(),
            const SizedBox(height: 16),

            // Description Input với suggestions
            _buildDescriptionInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTypeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Loại giao dịch',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<TransactionType>(
                    title: const Text('Chi tiêu'),
                    value: TransactionType.expense,
                    groupValue: _selectedType,
                    onChanged: (value) {
                      setState(() {
                        _selectedType = value!;
                        // Reset category khi đổi type
                        _selectedCategoryId = null;
                        _selectedSubCategoryId = null;
                      });
                    },
                  ),
                ),
                Expanded(
                  child: RadioListTile<TransactionType>(
                    title: const Text('Thu nhập'),
                    value: TransactionType.income,
                    groupValue: _selectedType,
                    onChanged: (value) {
                      setState(() {
                        _selectedType = value!;
                        // Reset category khi đổi type
                        _selectedCategoryId = null;
                        _selectedSubCategoryId = null;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextFormField(
          controller: _amountController,
          decoration: const InputDecoration(
            labelText: 'Số tiền *',
            border: OutlineInputBorder(),
            suffixText: '₫',
          ),
          keyboardType: TextInputType.number,
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
      ),
    );
  }

  // FIX: Wallet selector chỉ hiển thị ví có thể chọn
  Widget _buildWalletSelector(UserProvider userProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chọn ví *',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Wallet>>(
              // FIX: Sử dụng getSelectableWalletsStream thay vì getWalletsStream
              stream: _databaseService.getSelectableWalletsStream(userProvider),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                final wallets = snapshot.data!;
                if (wallets.isEmpty) {
                  return const Text('Không có ví nào. Hãy tạo ví trước!');
                }

                return DropdownButtonFormField<String>(
                  value: _selectedWalletId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Chọn ví'),
                  items: wallets.map((wallet) {
                    String displayName = wallet.name;

                    // Thêm tag để phân biệt loại ví
                    if (wallet.ownerId == userProvider.partnershipId) {
                      displayName += ' (Chung)';
                    } else if (wallet.ownerId ==
                        FirebaseAuth.instance.currentUser?.uid) {
                      displayName += ' (Cá nhân)';
                    }

                    return DropdownMenuItem(
                      value: wallet.id,
                      child: Text(displayName),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedWalletId = value;
                    });
                  },
                  validator: (value) {
                    if (value == null) {
                      return 'Vui lòng chọn ví';
                    }
                    return null;
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // FIX: Category selector riêng biệt cho income và expense
  Widget _buildCategorySelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _selectedType == TransactionType.income
                  ? 'Nguồn thu nhập'
                  : 'Danh mục chi tiêu',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Category>>(
              // FIX: Lấy categories theo type
              stream: _databaseService.getCategoriesByTypeStream(
                _selectedType == TransactionType.income ? 'income' : 'expense',
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                final categories = snapshot.data!;

                // Nếu là income mà không có category nào
                if (_selectedType == TransactionType.income &&
                    categories.isEmpty) {
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
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
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
          ],
        ),
      ),
    );
  }

  Widget _buildSubCategorySelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Danh mục con (tùy chọn)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<Category>>(
              stream: _databaseService.getCategoriesStream(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }

                final categories = snapshot.data!;
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
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                      ),
                      hint: const Text('Chọn danh mục con (tùy chọn)'),
                      items: selectedCategory.subCategories.entries.map((
                        entry,
                      ) {
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
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ngày giao dịch',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            InkWell(
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today),
                    const SizedBox(width: 8),
                    Text(DateFormat('dd/MM/yyyy, HH:mm').format(_selectedDate)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mô tả (tùy chọn)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Nhập mô tả...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            // FIX: Gợi ý mô tả từ lịch sử
            if (_descriptionHistory.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Gợi ý từ lịch sử:',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: _descriptionHistory.take(5).map((desc) {
                  return ActionChip(
                    label: Text(desc),
                    onPressed: () {
                      _descriptionController.text = desc;
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ),
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
        id: widget.transactionToEdit?.id ?? '',
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
        // Sửa giao dịch
        await _databaseService.updateTransaction(
          transaction,
          widget.transactionToEdit!,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã cập nhật giao dịch')));
      } else {
        // Thêm giao dịch mới
        await _databaseService.addTransaction(transaction);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Đã thêm giao dịch')));
      }

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
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
