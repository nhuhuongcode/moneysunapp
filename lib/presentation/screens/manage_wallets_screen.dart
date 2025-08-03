import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:moneysun/data/models/wallet_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ManageWalletsScreen extends StatefulWidget {
  const ManageWalletsScreen({super.key});

  @override
  State<ManageWalletsScreen> createState() => _ManageWalletsScreenState();
}

class _ManageWalletsScreenState extends State<ManageWalletsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final _nameController = TextEditingController();
  final _balanceController = TextEditingController();

  void _showAddWalletDialog() {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    _nameController.clear();
    _balanceController.clear();

    String ownerType = 'personal';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Thêm ví mới'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Tên ví'),
                    autofocus: true,
                  ),
                  TextField(
                    controller: _balanceController,
                    decoration: const InputDecoration(
                      labelText: 'Số dư ban đầu',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  if (userProvider.partnershipId != null) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Tạo cho:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    RadioListTile<String>(
                      title: const Text('Cá nhân'),
                      value: 'personal',
                      groupValue: ownerType,
                      onChanged: (value) =>
                          setDialogState(() => ownerType = value!),
                    ),
                    RadioListTile<String>(
                      title: const Text('Chung (Cả hai cùng xem)'),
                      value: 'shared',
                      groupValue: ownerType,
                      onChanged: (value) =>
                          setDialogState(() => ownerType = value!),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = _nameController.text;
                    final balance =
                        double.tryParse(_balanceController.text) ?? 0.0;

                    final String ownerId;
                    if (ownerType == 'shared') {
                      ownerId = userProvider.partnershipId!;
                    } else {
                      ownerId = FirebaseAuth.instance.currentUser!.uid;
                    }

                    if (name.isNotEmpty) {
                      _databaseService.addWallet(name, balance, ownerId);
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Thêm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final currencyFormatter = NumberFormat.currency(
      locale: 'vi_VN',
      symbol: '₫',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Nguồn tiền (Ví)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_card),
            onPressed: _showAddWalletDialog,
            tooltip: 'Thêm ví',
          ),
        ],
      ),
      body: StreamBuilder<List<Wallet>>(
        stream: _databaseService.getWalletsStream(userProvider),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Chưa có ví nào.'));
          }
          final wallets = snapshot.data!;
          return ListView.builder(
            itemCount: wallets.length,
            itemBuilder: (context, index) {
              final wallet = wallets[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: ListTile(
                  leading: const Icon(Icons.wallet_outlined),
                  title: Text(
                    wallet.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(currencyFormatter.format(wallet.balance)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          /* Logic sửa */
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          /* Logic xóa */
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
