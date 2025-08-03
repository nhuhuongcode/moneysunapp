import 'package:flutter/material.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/models/transaction_model.dart'; // Đảm bảo import này
import 'package:intl/intl.dart'; // Đảm bảo import này

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseService _databaseService = DatabaseService();

  // SỬA LỖI: Không cần controller ở cấp độ state nữa
  // final _textController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Hàm để thêm danh mục CHA
  void _showAddCategoryDialog(String type) {
    // SỬA LỖI: Tạo controller mới ngay tại đây
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          type == 'expense' ? 'Thêm Danh mục Chi' : 'Thêm Danh mục Thu',
        ),
        content: TextField(
          controller: textController, // Dùng controller cục bộ
          decoration: const InputDecoration(labelText: 'Tên danh mục'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                _databaseService.addCategory(textController.text, type);
                Navigator.pop(context);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  // Hàm để thêm danh mục CON
  void _showAddSubCategoryDialog(
    String parentCategoryId,
    String parentCategoryType,
  ) {
    // SỬA LỖI: Tạo controller mới ngay tại đây
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm Danh mục con'),
        content: TextField(
          controller: textController, // Dùng controller cục bộ
          decoration: const InputDecoration(labelText: 'Tên danh mục con'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.isNotEmpty) {
                _databaseService.addSubCategory(
                  parentCategoryId,
                  textController.text,
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

  // (Hàm build và _buildCategoryList giữ nguyên không đổi)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Danh mục'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle),
            onPressed: () {
              // Xác định type dựa trên tab đang mở
              final type = _tabController.index == 0 ? 'expense' : 'income';
              _showAddCategoryDialog(type);
            },
            tooltip: 'Thêm danh mục cha',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'CHI TIÊU'),
            Tab(text: 'THU NHẬP'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab cho danh mục chi tiêu
          _buildCategoryList('expense'),
          // Tab cho danh mục thu nhập
          _buildCategoryList('income'),
        ],
      ),
      // Di chuyển FAB vào actions của AppBar để tránh lỗi scope
    );
  }

  Widget _buildCategoryList(String type) {
    return StreamBuilder<List<Category>>(
      stream: _databaseService.getCategoriesStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());

        final categories = snapshot.data!
            .where((cat) => cat.type == type)
            .toList();

        if (categories.isEmpty) {
          return Center(child: Text('Chưa có danh mục nào thuộc loại này.'));
        }

        return ListView(
          children: categories.map((category) {
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ExpansionTile(
                leading: const Icon(Icons.category),
                title: Text(
                  category.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children: [
                  ...category.subCategories.entries.map((subEntry) {
                    return ListTile(
                      leading: const SizedBox(width: 24),
                      title: Text(subEntry.value),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          _databaseService.deleteSubCategory(
                            category.id,
                            subEntry.key,
                          );
                        },
                      ),
                    );
                  }).toList(),
                  ListTile(
                    leading: const Icon(Icons.add, color: Colors.blue),
                    title: const Text(
                      'Thêm danh mục con',
                      style: TextStyle(color: Colors.blue),
                    ),
                    onTap: () =>
                        _showAddSubCategoryDialog(category.id, category.type),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
