// lib/presentation/screens/profile_screen.dart - Updated

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:moneysun/data/services/auth_service.dart';
import 'package:moneysun/data/services/partnership_service.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/presentation/screens/manage_categories_screen.dart';
import 'package:moneysun/presentation/screens/manage_wallets_screen.dart';
import 'package:provider/provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final PartnershipService _partnershipService = PartnershipService();
  final DatabaseService _databaseService = DatabaseService();
  final AuthService _authService = AuthService();
  final _codeController = TextEditingController();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cá nhân & Cài đặt')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Management section
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

          // FIX: Enhanced Partnership section
          Consumer<UserProvider>(
            builder: (context, userProvider, child) {
              return _buildPartnershipSection(userProvider);
            },
          ),

          const Divider(height: 32),

          // Logout
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

  // FIX: Enhanced partnership section with better UI
  Widget _buildPartnershipSection(UserProvider userProvider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.people_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Quản lý chung',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),

            const SizedBox(height: 16),

            if (userProvider.hasPartner) ...[
              // FIX: Show current partnership info
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Đang kết nối với:',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      userProvider.partnerDisplayName ?? 'Đối tác',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                    if (userProvider.partnershipCreationDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Kết nối từ: ${_formatDate(userProvider.partnershipCreationDate!)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Disconnect button
              OutlinedButton.icon(
                onPressed: _isLoading
                    ? null
                    : () => _showDisconnectDialog(userProvider),
                icon: const Icon(Icons.link_off, color: Colors.red),
                label: const Text(
                  'Ngắt kết nối',
                  style: TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ] else ...[
              // FIX: Show invite code and accept invite UI
              const Text(
                'Gửi mã này cho người bạn muốn cùng quản lý chi tiêu:',
              ),
              const SizedBox(height: 12),

              FutureBuilder<String>(
                future: _partnershipService.getOrCreateInviteCode(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Text(
                      'Lỗi: ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    );
                  }

                  final inviteCode = snapshot.data!;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Mã mời của bạn:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              SelectableText(
                                inviteCode,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: inviteCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Đã sao chép mã mời!'),
                                backgroundColor: Colors.green,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          tooltip: 'Sao chép mã',
                        ),
                      ],
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              const Text('Hoặc nhập mã của đối tác:'),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      decoration: const InputDecoration(
                        hintText: 'Nhập mã mời (6 ký tự)',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 6,
                      onChanged: (value) {
                        _codeController.value = _codeController.value.copyWith(
                          text: value.toUpperCase(),
                          selection: TextSelection.collapsed(
                            offset: value.length,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isLoading || _codeController.text.length < 6
                        ? null
                        : _acceptInvite,
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kết nối'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // FIX: Enhanced accept invite with better error handling
  void _acceptInvite() async {
    if (_codeController.text.isEmpty || _codeController.text.length < 6) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // FIX: Use DatabaseService method for proper handling
      await _databaseService.handlePartnershipInvite(_codeController.text);

      _codeController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kết nối thành công!'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh UserProvider
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      await userProvider.refreshPartnershipData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // FIX: Show disconnect confirmation dialog
  void _showDisconnectDialog(UserProvider userProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ngắt kết nối'),
        content: Text(
          'Bạn có chắc chắn muốn ngắt kết nối với ${userProvider.partnerDisplayName}?\n\n'
          'Sau khi ngắt kết nối, bạn sẽ không còn thấy dữ liệu của đối tác và ngược lại.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _disconnectPartnership(userProvider);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Ngắt kết nối',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectPartnership(UserProvider userProvider) async {
    setState(() {
      _isLoading = true;
    });

    try {
      await userProvider.disconnectPartnership();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã ngắt kết nối thành công'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi ngắt kết nối: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }
}
