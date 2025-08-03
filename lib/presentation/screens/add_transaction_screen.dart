import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart'; // <-- THÊM MỚI
import 'package:moneysun/data/services/database_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart'; // <-- THÊM MỚI
import 'package:collection/collection.dart';

class AddTransactionScreen extends StatefulWidget {
  final TransactionModel? transactionToEdit;
  const AddTransactionScreen({super.key, this.transactionToEdit});

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _databaseService = DatabaseService();
  final _auth = FirebaseAuth.instance;

  // Controllers
  final _amountController = TextEditingController();

  // SỬA LỖI: Đổi kiểu của biến trạng thái từ String thành TransactionType
  TransactionType _transactionType = TransactionType.expense;

  DateTime _selectedDate = DateTime.now();
  Wallet? _selectedWallet;
  Category? _selectedCategory;

  String? _selectedSubCategoryId;
  List<MapEntry<String, String>> _subCategoryItems = [];
  List<String> _descriptionSuggestions = [];
  final TextEditingController _descriptionController = TextEditingController();
  bool get _isEditing => widget.transactionToEdit != null;

  @override
  void initState() {
    super.initState();
    // THÊM MỚI: Tải danh sách gợi ý khi màn hình được khởi tạo
    _loadDescriptionHistory();

    if (_isEditing) {
      final trans = widget.transactionToEdit!;
      _amountController.text = trans.amount.toString();
      _descriptionController.text = trans.description;
      _transactionType = trans.type;
      _selectedDate = trans.date;
      // Việc lấy _selectedWallet và _selectedCategory sẽ phức tạp hơn một chút
      // vì chúng là các đối tượng. Chúng ta sẽ lấy chúng từ Stream.
    }
  }

  // HÀM MỚI: để tải lịch sử mô tả từ service
  Future<void> _loadDescriptionHistory() async {
    final history = await _databaseService.getDescriptionHistory();
    if (mounted) {
      setState(() {
        _descriptionSuggestions = history;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Sửa Giao Dịch' : 'Thêm Giao Dịch Mới'),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Số tiền',
                  prefixIcon: Icon(Icons.money),
                ),
                keyboardType: TextInputType.number,
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Vui lòng nhập số tiền'
                    : null,
              ),
              const SizedBox(height: 16),

              SegmentedButton<TransactionType>(
                segments: const <ButtonSegment<TransactionType>>[
                  ButtonSegment<TransactionType>(
                    value: TransactionType.expense,
                    label: Text('Chi phí'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                  ButtonSegment<TransactionType>(
                    value: TransactionType.income,
                    label: Text('Thu nhập'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                ],
                selected: {_transactionType},
                onSelectionChanged: (Set<TransactionType> newSelection) {
                  setState(() {
                    _transactionType = newSelection.first;
                  });
                },
              ),
              const SizedBox(height: 16),

              _buildWalletsDropdown(userProvider),
              const SizedBox(height: 16),

              // SỬA LỖI: Điều kiện if giờ so sánh với enum
              if (_transactionType == TransactionType.expense)
                _buildCategoriesDropdown(),

              const SizedBox(height: 16),
              if (_subCategoryItems
                  .isNotEmpty) // Chỉ hiển thị nếu có sub-category
                _buildSubCategoriesDropdown(),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(
                  'Ngày: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                ),
                onTap: _pickDate,
              ),
              Autocomplete<String>(
                // `optionsBuilder` được gọi mỗi khi người dùng gõ
                optionsBuilder: (TextEditingValue textEditingValue) {
                  // Nếu người dùng chưa gõ gì, không hiển thị gợi ý
                  if (textEditingValue.text == '') {
                    return const Iterable<String>.empty();
                  }
                  // Lọc danh sách gợi ý để tìm những mục chứa nội dung đang gõ
                  return _descriptionSuggestions.where((String option) {
                    return option.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    );
                  });
                },
                // `onSelected` được gọi khi người dùng chọn một gợi ý
                onSelected: (String selection) {
                  // Cập nhật text trong ô nhập liệu
                  _descriptionController.text = selection;
                },
                // `fieldViewBuilder` để tùy chỉnh giao diện của ô nhập liệu
                fieldViewBuilder:
                    (
                      BuildContext context,
                      TextEditingController fieldController,
                      FocusNode fieldFocusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      // Gán controller của chúng ta cho controller của Autocomplete
                      // Điều này quan trọng để có thể lấy giá trị khi submit form
                      _descriptionController.text = fieldController.text;

                      return TextFormField(
                        controller: fieldController,
                        focusNode: fieldFocusNode,
                        decoration: const InputDecoration(
                          labelText: 'Mô tả',
                          prefixIcon: Icon(Icons.description),
                        ),
                      );
                    },
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitForm,
                  child: const Text('Lưu Giao Dịch'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalletsDropdown(UserProvider userProvider) {
    return StreamBuilder<List<Wallet>>(
      stream: _databaseService.getWalletsStream(userProvider),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const CircularProgressIndicator();
        final wallets = snapshot.data!.where((wallet) {
          // Chỉ giữ lại ví của chính mình HOẶC ví chung
          return wallet.ownerId == userProvider.currentUser!.uid ||
              wallet.ownerId == userProvider.partnershipId;
        }).toList();
        if (_selectedWallet != null &&
            !wallets.any((w) => w.id == _selectedWallet!.id)) {
          _selectedWallet = null;
        }

        if (_isEditing &&
            widget.transactionToEdit!.walletId.isNotEmpty &&
            _selectedWallet == null) {
          _selectedWallet = wallets.firstWhereOrNull(
            (w) => w.id == widget.transactionToEdit!.walletId,
          );
        }
        return DropdownButtonFormField<Wallet>(
          value: _selectedWallet,
          isExpanded: true,
          hint: const Text('Chọn ví'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.wallet)),
          items: wallets.map((wallet) {
            String walletDisplayName = wallet.name;
            // Logic thêm nhãn "Chung" giờ sẽ luôn đúng
            if (wallet.ownerId == userProvider.partnershipId) {
              walletDisplayName += " (Chung)";
            }
            return DropdownMenuItem<Wallet>(
              value: wallet,
              child: Text(walletDisplayName),
            );
          }).toList(),
          onChanged: (wallet) => setState(() => _selectedWallet = wallet),
          validator: (value) => value == null ? 'Vui lòng chọn ví' : null,
        );
      },
    );
  }

  Widget _buildCategoriesDropdown() {
    return StreamBuilder<List<Category>>(
      stream: _databaseService.getCategoriesStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final String requiredCategoryType =
            _transactionType == TransactionType.income ? 'income' : 'expense';

        final transactionTypeString =
            _transactionType.name; // 'expense' hoặc 'income'
        final categories = snapshot.data!
            .where((cat) => cat.type == requiredCategoryType)
            .toList();
        if (_selectedCategory != null &&
            !categories.any((c) => c.id == _selectedCategory!.id)) {
          _selectedCategory = null;
          _selectedSubCategoryId = null;
          _subCategoryItems = [];
        }

        if (_isEditing &&
            widget.transactionToEdit!.categoryId != null &&
            _selectedCategory == null) {
          _selectedCategory = categories.firstWhereOrNull(
            (c) => c.id == widget.transactionToEdit!.categoryId,
          );
          // Cập nhật danh sách sub-category nếu tìm thấy category cha
          if (_selectedCategory != null) {
            _subCategoryItems = _selectedCategory!.subCategories.entries
                .toList();
            _selectedSubCategoryId = widget.transactionToEdit!.subCategoryId;
          }
        }
        return DropdownButtonFormField<Category>(
          value: _selectedCategory,
          hint: Text(
            requiredCategoryType == 'income'
                ? 'Chọn danh mục thu'
                : 'Chọn danh mục chi',
          ),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.category)),
          items: categories.map((cat) {
            return DropdownMenuItem<Category>(
              value: cat,
              child: Text(cat.name),
            );
          }).toList(),
          onChanged: (cat) {
            setState(() {
              _selectedCategory = cat;
              // KHI CHỌN CATEGORY CHA, CẬP NHẬT DANH SÁCH SUB-CATEGORY
              _selectedSubCategoryId = null; // Reset lựa chọn cũ
              if (cat != null && cat.subCategories.isNotEmpty) {
                _subCategoryItems = cat.subCategories.entries.toList();
              } else {
                _subCategoryItems = [];
              }
            });
          },
          validator: (value) =>
              (_transactionType == TransactionType.expense && value == null)
              ? 'Vui lòng chọn danh mục'
              : null,
        );
      },
    );
  }

  Widget _buildSubCategoriesDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedSubCategoryId,
      hint: const Text('Chọn danh mục con (tùy chọn)'),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.label_important_outline),
      ),
      items: _subCategoryItems.map((sub) {
        // sub.key là ID, sub.value là tên
        return DropdownMenuItem<String>(value: sub.key, child: Text(sub.value));
      }).toList(),
      onChanged: (subId) => setState(() => _selectedSubCategoryId = subId),
      // Không cần validator vì đây là tùy chọn
    );
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  void _submitForm() {
    if (_formKey.currentState!.validate()) {
      final transaction = TransactionModel(
        id: _isEditing ? widget.transactionToEdit!.id : '',
        amount: double.parse(_amountController.text),
        type: _transactionType,
        walletId: _selectedWallet!.id,
        categoryId: _selectedCategory?.id,
        subCategoryId: _selectedSubCategoryId,
        date: _selectedDate,
        description: _descriptionController.text,
        userId: _auth.currentUser!.uid,
      );
      if (_isEditing) {
        // Gọi hàm sửa (cần tạo trong DatabaseService)
        _databaseService.updateTransaction(
          transaction,
          widget.transactionToEdit!,
        );
      } else {
        // Gọi hàm thêm như cũ
        _databaseService.addTransaction(transaction);
      }
      Navigator.pop(context);
    }
  }
}
