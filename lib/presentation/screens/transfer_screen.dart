import 'package:flutter/material.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final _formKey = GlobalKey<FormState>();
  final _databaseService = DatabaseService();

  // Controllers và State
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  Wallet? _fromWallet;
  Wallet? _toWallet;

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Tạo Giao Dịch Chuyển Tiền')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sử dụng StreamBuilder để lấy danh sách ví một lần và dùng cho cả hai Dropdown
              StreamBuilder<List<Wallet>>(
                stream: _databaseService.getWalletsStream(userProvider),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final wallets = snapshot.data!;
                  final userProvider = Provider.of<UserProvider>(
                    context,
                    listen: false,
                  );
                  final eligibleWallets = wallets
                      .where(
                        (w) =>
                            w.ownerId == userProvider.currentUser!.uid ||
                            w.ownerId == userProvider.partnershipId,
                      )
                      .toList();

                  return Column(
                    children: [
                      // Dropdown Chọn "Ví đi"
                      _buildWalletDropdown(
                        label: 'Từ ví',
                        hint: 'Chọn ví nguồn',
                        items: eligibleWallets,
                        selectedValue: _fromWallet,
                        onChanged: (wallet) =>
                            setState(() => _fromWallet = wallet),
                      ),
                      const SizedBox(height: 16),
                      // Dropdown Chọn "Ví đến"
                      _buildWalletDropdown(
                        label: 'Đến ví',
                        hint: 'Chọn ví đích',
                        items: eligibleWallets,
                        selectedValue: _toWallet,
                        onChanged: (wallet) =>
                            setState(() => _toWallet = wallet),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 16),
              // Nhập số tiền
              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Số tiền',
                  prefixIcon: Icon(Icons.paid),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Vui lòng nhập số tiền';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Số tiền không hợp lệ';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Nhập mô tả (tùy chọn)
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (tùy chọn)',
                  prefixIcon: Icon(Icons.description),
                ),
              ),
              const SizedBox(height: 32),
              // Nút thực hiện
              ElevatedButton.icon(
                onPressed: _submitTransfer,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Thực hiện Chuyển tiền'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget tái sử dụng để xây dựng Dropdown chọn ví
  Widget _buildWalletDropdown({
    required String label,
    required String hint,
    required List<Wallet> items,
    required Wallet? selectedValue,
    required ValueChanged<Wallet?> onChanged,
  }) {
    return DropdownButtonFormField<Wallet>(
      value: selectedValue,
      isExpanded: true,
      hint: Text(hint),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.account_balance_wallet),
      ),
      items: items.map((wallet) {
        // SỬA LỖI: Logic thêm nhãn phụ cho các loại ví
        // Cần truy cập userProvider, vậy chúng ta sẽ truyền nó vào
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        String walletDisplayName = wallet.name;
        if (wallet.ownerId == userProvider.partnershipId) {
          walletDisplayName += " (Chung)";
        } else if (wallet.ownerId != userProvider.currentUser!.uid) {
          walletDisplayName += " (Partner)";
        }
        return DropdownMenuItem<Wallet>(
          value: wallet,
          child: Text(walletDisplayName),
        );
      }).toList(),
      onChanged: onChanged,
      validator: (value) => value == null ? 'Vui lòng chọn ví' : null,
    );
  }

  // Logic xử lý khi nhấn nút lưu
  void _submitTransfer() {
    if (_formKey.currentState!.validate()) {
      // Kiểm tra logic nghiệp vụ bổ sung
      if (_fromWallet == null || _toWallet == null) return;

      if (_fromWallet!.id == _toWallet!.id) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ví nguồn và ví đích không được trùng nhau.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final amount = double.parse(_amountController.text);

      // Gọi hàm service đã viết sẵn
      _databaseService.addTransferTransaction(
        fromWalletId: _fromWallet!.id,
        toWalletId: _toWallet!.id,
        amount: amount,
        fromWalletName: _fromWallet!.name, // <-- Truyền tên
        toWalletName: _toWallet!.name,
      );

      // Thông báo thành công và quay về màn hình trước
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chuyển tiền thành công!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    }
  }
}
