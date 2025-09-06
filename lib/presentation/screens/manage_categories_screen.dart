import 'package:flutter/material.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/database_service.dart';
import 'package:moneysun/data/services/enhanced_category_service.dart';
import 'package:moneysun/presentation/widgets/category_ownership_selector.dart';
import 'package:provider/provider.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final EnhancedCategoryService _categoryService = EnhancedCategoryService();
  final DatabaseService _databaseService = DatabaseService();

  // Filter states
  CategoryOwnershipType? _selectedOwnershipFilter;
  bool _showArchived = false;

  // Animation controllers
  late AnimationController _filterAnimationController;
  late Animation<double> _filterAnimation;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _filterAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _filterAnimation = CurvedAnimation(
      parent: _filterAnimationController,
      curve: Curves.easeInOut,
    );

    _filterAnimationController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _filterAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(userProvider),
      body: Column(
        children: [
          // Enhanced Filter Section
          _buildFilterSection(userProvider),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCategoryList('expense', userProvider),
                _buildCategoryList('income', userProvider),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(userProvider),
    );
  }

  PreferredSizeWidget _buildAppBar(UserProvider userProvider) {
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
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      title: Row(
        children: [
          const Text(
            'Quản lý danh mục',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          if (userProvider.hasPartner) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_rounded,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Có đối tác',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
          child: PopupMenuButton(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                child: Row(
                  children: [
                    Icon(
                      _showArchived ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    const SizedBox(width: 12),
                    Text(_showArchived ? 'Ẩn đã lưu trữ' : 'Hiện đã lưu trữ'),
                  ],
                ),
                onTap: () => setState(() => _showArchived = !_showArchived),
              ),
              const PopupMenuItem(
                child: Row(
                  children: [
                    Icon(Icons.import_export_rounded, size: 18),
                    SizedBox(width: 12),
                    Text('Xuất/Nhập danh mục'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).primaryColor,
                    Theme.of(context).primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: Theme.of(
                context,
              ).primaryColor.withOpacity(0.7),
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              dividerColor: Colors.transparent,
              indicatorPadding: const EdgeInsets.all(6),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.trending_down_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Chi tiêu'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.trending_up_rounded, size: 18),
                      SizedBox(width: 8),
                      Text('Thu nhập'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(UserProvider userProvider) {
    return AnimatedBuilder(
      animation: _filterAnimation,
      builder: (context, child) {
        return FadeTransition(
          opacity: _filterAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, -0.5),
              end: Offset.zero,
            ).animate(_filterAnimation),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 12,
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
                          Icons.filter_list_rounded,
                          color: Colors.indigo,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Bộ lọc danh mục',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Ownership Filter
                  if (userProvider.hasPartner)
                    CategoryFilterWidget(
                      selectedOwnership: _selectedOwnershipFilter,
                      onChanged: (type) {
                        setState(() => _selectedOwnershipFilter = type);
                      },
                      userProvider: userProvider,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryList(String type, UserProvider userProvider) {
    return StreamBuilder<List<Category>>(
      stream: _categoryService.getCategoriesWithOwnershipStream(
        userProvider,
        type: type,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return const Center(child: Text('Lỗi khi tải danh mục'));
        }

        List<Category> categories = snapshot.data!;

        // Apply filters
        if (_selectedOwnershipFilter != null) {
          categories = categories
              .where((cat) => cat.ownershipType == _selectedOwnershipFilter)
              .toList();
        }

        if (!_showArchived) {
          categories = categories.where((cat) => !cat.isArchived).toList();
        }

        if (categories.isEmpty) {
          return EmptyCategoriessState(
            type: type,
            filterType: _selectedOwnershipFilter,
            userProvider: userProvider,
            onCreateCategory: () =>
                _showCreateCategoryDialog(type, userProvider),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {}); // Trigger rebuild
          },
          child: Column(
            children: [
              // Statistics Card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: CategoryStatsWidget(
                  categories: categories,
                  userProvider: userProvider,
                ),
              ),

              // Categories List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    return AnimatedContainer(
                      duration: Duration(milliseconds: 300 + (index * 50)),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: CategoryListItemWithOwnership(
                        category: category,
                        onTap: () =>
                            _showCategoryDetailDialog(category, userProvider),
                        onEdit: () =>
                            _showEditCategoryDialog(category, userProvider),
                        onDelete: () => _showDeleteCategoryDialog(category),
                        trailing: CategoryUsageIndicator(
                          category: category,
                          usageCount: 0, // TODO: Implement usage tracking
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFloatingActionButton(UserProvider userProvider) {
    return AnimatedScale(
      scale: 1.0,
      duration: const Duration(milliseconds: 200),
      child: FloatingActionButton.extended(
        onPressed: () {
          final currentType = _tabController.index == 0 ? 'expense' : 'income';
          _showCreateCategoryDialog(currentType, userProvider);
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'Thêm ${_tabController.index == 0 ? "chi tiêu" : "thu nhập"}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        extendedPadding: const EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }

  // Dialog Methods
  void _showCreateCategoryDialog(String type, UserProvider userProvider) {
    showDialog(
      context: context,
      builder: (context) => CategoryCreationDialog(
        type: type,
        userProvider: userProvider,
        onCreated: (name, ownershipType) async {
          try {
            await _categoryService.createCategoryWithOwnership(
              name: name,
              type: type,
              ownershipType: ownershipType,
              userProvider: userProvider,
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text('Đã tạo danh mục "$name" thành công'),
                    ],
                  ),
                  backgroundColor: Colors.green,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Lỗi khi tạo danh mục: $e'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        },
      ),
    );
  }

  void _showEditCategoryDialog(Category category, UserProvider userProvider) {
    final nameController = TextEditingController(text: category.name);

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (category.isShared ? Colors.orange : Colors.blue)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Icons.edit_rounded,
                      color: category.isShared ? Colors.orange : Colors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Chỉnh sửa danh mục',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Category Name Input
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Tên danh mục',
                  filled: true,
                  fillColor: (category.isShared ? Colors.orange : Colors.blue)
                      .withOpacity(0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(
                      color: category.isShared ? Colors.orange : Colors.blue,
                      width: 2,
                    ),
                  ),
                  prefixIcon: const Icon(Icons.category_outlined),
                ),
                autofocus: true,
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Hủy'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final name = nameController.text.trim();
                        if (name.isNotEmpty && name != category.name) {
                          try {
                            final updatedCategory = category.copyWith(
                              name: name,
                            );
                            await _categoryService.updateCategory(
                              updatedCategory,
                            );
                            Navigator.pop(context);

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Đã cập nhật danh mục thành công',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Lỗi khi cập nhật: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: category.isShared
                            ? Colors.orange
                            : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Lưu',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteCategoryDialog(Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_rounded,
                color: Colors.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Xác nhận xóa', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn có chắc chắn muốn xóa danh mục "${category.name}" không?',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nếu danh mục đang có giao dịch, nó sẽ được lưu trữ thay vì xóa.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
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
              try {
                await _categoryService.deleteCategory(category.id);
                Navigator.pop(context);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Đã xóa danh mục thành công'),
                    backgroundColor: Colors.orange,
                  ),
                );
              } catch (e) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$e'), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Xóa danh mục'),
          ),
        ],
      ),
    );
  }

  void _showCategoryDetailDialog(Category category, UserProvider userProvider) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (category.isShared ? Colors.orange : Colors.blue)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      category.isShared
                          ? Icons.people_rounded
                          : Icons.person_rounded,
                      color: category.isShared ? Colors.orange : Colors.blue,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          category.isShared
                              ? 'Danh mục chung'
                              : 'Danh mục cá nhân',
                          style: TextStyle(
                            color: category.isShared
                                ? Colors.orange
                                : Colors.blue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Sub-categories section
              if (category.subCategories.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.subdirectory_arrow_right, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Danh mục con (${category.subCategories.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: category.subCategories.length,
                    itemBuilder: (context, index) {
                      final entry = category.subCategories.entries.elementAt(
                        index,
                      );
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.label_outline, size: 16),
                        title: Text(entry.value),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16),
                          onPressed: () {
                            // TODO: Implement delete sub-category
                          },
                        ),
                      );
                    },
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey),
                      SizedBox(width: 12),
                      Text('Chưa có danh mục con nào'),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditCategoryDialog(category, userProvider);
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Chỉnh sửa'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () =>
                          _showAddSubCategoryDialog(category.id, category.type),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Thêm con'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: category.isShared
                            ? Colors.orange
                            : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

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
}
