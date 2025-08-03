import 'package:flutter/material.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/partnership_service.dart';
import 'package:moneysun/presentation/screens/manage_categories_screen.dart'; // Import màn hình mới
import 'package:moneysun/presentation/screens/manage_wallets_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final PartnershipService _partnershipService = PartnershipService();
  final AuthService _authService = AuthService();
  final _codeController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân & Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Quản lý Nguồn tiền'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageWalletsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.category_outlined),
                  title: const Text('Quản lý Danh mục'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ManageCategoriesScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Phần mời partner
          _buildPartnershipSection(),
          const Divider(height: 32),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Đăng xuất'),
            onTap: () async {
              await _authService.signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPartnershipSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quản lý chung',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text('Gửi mã này cho người bạn muốn cùng quản lý chi tiêu:'),
            FutureBuilder<String>(
              future: _partnershipService.getOrCreateInviteCode(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                return SelectableText(
                  snapshot.data!,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('Hoặc nhập mã của partner:'),
            TextField(
              controller: _codeController,
              decoration: InputDecoration(
                hintText: 'Nhập mã mời',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_circle),
                  onPressed: _acceptInvite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _acceptInvite() async {
    if (_codeController.text.isEmpty) return;
    try {
      final success = await _partnershipService.acceptInvite(
        _codeController.text,
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kết nối thành công!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
