// lib/presentation/screens/_manage_categories_screen.dart
import 'package:flutter/material.dart';
import 'package:moneysun/presentation/widgets/category_widgets.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/providers/connection_status_provider.dart';
import 'package:moneysun/presentation/widgets/connection_status_banner.dart';

class ManageCategoriesScreen extends StatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  State<ManageCategoriesScreen> createState() => _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState extends State<ManageCategoriesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _filterAnimationController;
  late Animation<double> _filterAnimation;

  // Filter states
  CategoryOwnershipType? _selectedOwnershipFilter;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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

    // Load categories when screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CategoryProvider>().loadCategories();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _filterAnimationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // Connection Status Banner
          const ConnectionStatusBanner(),

          //  Filter Section
          _buildFilterSection(),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCategoryList('expense'),
                _buildCategoryList('income'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _buildFloatingActionButton(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
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
      title: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          return Row(
            children: [
              const Text(
                'Quản lý danh mục',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
              ),
              if (userProvider.hasPartner) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
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
          );
        },
      ),
      actions: [_buildSyncStatusIndicator(), _buildOptionsMenu()],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: _buildTabBar(),
      ),
    );
  }

  Widget _buildSyncStatusIndicator() {
    return Consumer<ConnectionStatusProvider>(
      builder: (context, connectionStatus, child) {
        return Container(
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
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Icon(
                connectionStatus.isSyncing
                    ? Icons.sync
                    : connectionStatus.isOnline
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                key: ValueKey(connectionStatus.isSyncing),
                color: connectionStatus.isSyncing
                    ? Colors.orange
                    : connectionStatus.isOnline
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            onPressed: () => _showSyncStatusDialog(),
            tooltip: connectionStatus.statusMessage,
          ),
        );
      },
    );
  }

  Widget _buildOptionsMenu() {
    return Container(
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
      // Bọc PopupMenuButton trong Consumer để lấy CategoryProvider
      child: Consumer<CategoryProvider>(
        builder: (context, categoryProvider, child) {
          return PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            // xử lý chọn các mục khác ngoài toggle
            onSelected: (value) => _handleMenuAction(value),
            // Danh sách các item
            itemBuilder: (context) {
              final List<PopupMenuEntry<String>> items = [];

              // Item toggle ẩn/hiện danh mục lưu trữ
              items.add(
                PopupMenuItem<String>(
                  // không cần value vì onTap xử lý trực tiếp
                  child: Row(
                    children: [
                      Icon(
                        categoryProvider.includeArchived
                            ? Icons.visibility_off
                            : Icons.visibility,
                        size: 18,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        categoryProvider.includeArchived
                            ? 'Ẩn đã lưu trữ'
                            : 'Hiện đã lưu trữ',
                      ),
                    ],
                  ),
                  // toggle ngay khi bấm
                  onTap: () => categoryProvider.toggleIncludeArchived(),
                ),
              );

              // Divider
              items.add(const PopupMenuDivider());

              // Tạo danh mục mặc định
              items.add(
                const PopupMenuItem<String>(
                  value: 'create_defaults',
                  child: Row(
                    children: [
                      Icon(Icons.auto_fix_high, size: 18),
                      SizedBox(width: 12),
                      Text('Tạo danh mục mặc định'),
                    ],
                  ),
                ),
              );

              // Xuất danh mục
              items.add(
                const PopupMenuItem<String>(
                  value: 'export',
                  child: Row(
                    children: [
                      Icon(Icons.upload_rounded, size: 18),
                      SizedBox(width: 12),
                      Text('Xuất danh mục'),
                    ],
                  ),
                ),
              );

              // Nhập danh mục
              items.add(
                const PopupMenuItem<String>(
                  value: 'import',
                  child: Row(
                    children: [
                      Icon(Icons.download_rounded, size: 18),
                      SizedBox(width: 12),
                      Text('Nhập danh mục'),
                    ],
                  ),
                ),
              );

              return items;
            },
          );
        },
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
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
          unselectedLabelColor: Theme.of(context).primaryColor.withOpacity(0.7),
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
    );
  }

  Widget _buildFilterSection() {
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
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.search_rounded,
                          color: Colors.indigo,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Tìm kiếm & lọc',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Search Bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm danh mục...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Ownership Filter
                  Consumer<UserProvider>(
                    builder: (context, userProvider, child) {
                      if (!userProvider.hasPartner)
                        return const SizedBox.shrink();

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Lọc theo loại:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          CategoryFilterWidget(
                            selectedOwnership: _selectedOwnershipFilter,
                            onChanged: (type) {
                              setState(() => _selectedOwnershipFilter = type);
                            },
                            userProvider: userProvider,
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryList(String type) {
    return Consumer2<CategoryProvider, UserProvider>(
      builder: (context, categoryProvider, userProvider, child) {
        if (categoryProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (categoryProvider.hasError) {
          return _buildErrorState(categoryProvider.error!, categoryProvider);
        }

        List<Category> categories = type == 'expense'
            ? categoryProvider.expenseCategories
            : categoryProvider.incomeCategories;

        // Apply filters
        categories = _applyFilters(categories);

        if (categories.isEmpty) {
          return _buildEmptyState(type, userProvider);
        }

        return RefreshIndicator(
          onRefresh: () => categoryProvider.loadCategories(forceRefresh: true),
          child: Column(
            children: [
              // Statistics Card
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: _buildStatsCard(categories, userProvider),
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
                      child: _buildCategoryCard(category, userProvider),
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

  Widget _buildCategoryCard(Category category, UserProvider userProvider) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: category.isShared
              ? Colors.orange.withOpacity(0.3)
              : Colors.blue.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main content
          ListTile(
            onTap: () => _showCategoryDetailDialog(category),
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (category.isShared ? Colors.orange : Colors.blue)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                category.iconCodePoint != null
                    ? IconData(
                        category.iconCodePoint!,
                        fontFamily: 'MaterialIcons',
                      )
                    : (category.isShared
                          ? Icons.people_rounded
                          : Icons.person_rounded),
                color: category.isShared
                    ? Colors.orange.shade600
                    : Colors.blue.shade600,
                size: 24,
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                _buildOwnershipBadge(category),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (category.subCategories.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${category.subCategories.length} danh mục con',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildUsageIndicator(category),
                    const Spacer(),
                    Text(
                      _formatLastUsed(category.lastUsed),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            trailing: _buildCategoryActions(category, userProvider),
          ),

          // Sub-categories preview
          if (category.subCategories.isNotEmpty)
            _buildSubCategoriesPreview(category),
        ],
      ),
    );
  }

  Widget _buildOwnershipBadge(Category category) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: category.isShared
            ? Colors.orange.withOpacity(0.1)
            : Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: category.isShared
              ? Colors.orange.withOpacity(0.3)
              : Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Text(
        category.isShared ? 'CHUNG' : 'CÁ NHÂN',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: category.isShared
              ? Colors.orange.shade700
              : Colors.blue.shade700,
        ),
      ),
    );
  }

  Widget _buildUsageIndicator(Category category) {
    Color color;
    IconData icon;
    String text;

    if (category.usageCount == 0) {
      color = Colors.grey;
      icon = Icons.radio_button_unchecked;
      text = 'Chưa dùng';
    } else if (category.usageCount < 5) {
      color = Colors.orange;
      icon = Icons.circle_outlined;
      text = '${category.usageCount} lần';
    } else if (category.usageCount < 15) {
      color = Colors.blue;
      icon = Icons.adjust_rounded;
      text = '${category.usageCount} lần';
    } else {
      color = Colors.green;
      icon = Icons.check_circle_rounded;
      text = '${category.usageCount} lần';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubCategoriesPreview(Category category) {
    final subCategories = category.subCategories.values.take(3).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.subdirectory_arrow_right,
                size: 16,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Danh mục con:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ...subCategories.map(
                (sub) => Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    sub,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ),
              ),
              if (category.subCategories.length > 3)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '+${category.subCategories.length - 3}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryActions(Category category, UserProvider userProvider) {
    final categoryProvider = context.read<CategoryProvider>();
    final canEdit = categoryProvider.canEditCategory(category);

    return PopupMenuButton<String>(
      onSelected: (action) => _handleCategoryAction(action, category),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'view',
          child: Row(
            children: [
              Icon(Icons.info_rounded, size: 16, color: Colors.blue),
              SizedBox(width: 8),
              Text('Xem chi tiết'),
            ],
          ),
        ),
        if (canEdit) ...[
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_rounded, size: 16, color: Colors.orange),
                SizedBox(width: 8),
                Text('Chỉnh sửa'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'add_sub',
            child: Row(
              children: [
                Icon(Icons.add_rounded, size: 16, color: Colors.green),
                SizedBox(width: 8),
                Text('Thêm danh mục con'),
              ],
            ),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: category.isArchived ? 'restore' : 'archive',
            child: Row(
              children: [
                Icon(
                  category.isArchived ? Icons.unarchive : Icons.archive,
                  size: 16,
                  color: Colors.purple,
                ),
                const SizedBox(width: 8),
                Text(category.isArchived ? 'Khôi phục' : 'Lưu trữ'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_rounded, size: 16, color: Colors.red),
                SizedBox(width: 8),
                Text('Xóa', style: TextStyle(color: Colors.red)),
              ],
            ),
          ),
        ],
      ],
      icon: const Icon(Icons.more_vert_rounded),
    );
  }

  Widget _buildStatsCard(List<Category> categories, UserProvider userProvider) {
    final personalCategories = categories
        .where((cat) => cat.ownershipType == CategoryOwnershipType.personal)
        .length;
    final sharedCategories = categories
        .where((cat) => cat.ownershipType == CategoryOwnershipType.shared)
        .length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Thống kê danh mục',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_searchQuery.isNotEmpty || _selectedOwnershipFilter != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Đã lọc',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  'Tổng cộng',
                  '${categories.length}',
                  Colors.grey.shade600,
                  Icons.category_rounded,
                ),
              ),
              if (userProvider.hasPartner) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    'Cá nhân',
                    '$personalCategories',
                    Colors.blue.shade600,
                    Icons.person_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatItem(
                    'Chung',
                    '$sharedCategories',
                    Colors.orange.shade600,
                    Icons.people_rounded,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String type, UserProvider userProvider) {
    return EmptyCategoriesState(
      type: type,
      filterType: _selectedOwnershipFilter,
      userProvider: userProvider,
      onCreateCategory: () => _showCreateCategoryDialog(type),
    );
  }

  Widget _buildErrorState(String error, CategoryProvider categoryProvider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            const Text(
              'Có lỗi xảy ra',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  categoryProvider.loadCategories(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton() {
    return FloatingActionButton.extended(
      onPressed: () {
        final currentType = _tabController.index == 0 ? 'expense' : 'income';
        _showCreateCategoryDialog(currentType);
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
    );
  }

  // ============ ACTION HANDLERS ============

  void _handleMenuAction(String action) {
    switch (action) {
      case 'create_defaults':
        _showCreateDefaultCategoriesDialog();
        break;
      case 'export':
        _exportCategories();
        break;
      case 'import':
        _importCategories();
        break;
    }
  }

  void _handleCategoryAction(String action, Category category) {
    switch (action) {
      case 'view':
        _showCategoryDetailDialog(category);
        break;
      case 'edit':
        _showEditCategoryDialog(category);
        break;
      case 'add_sub':
        _showAddSubCategoryDialog(category);
        break;
      case 'archive':
        _archiveCategory(category);
        break;
      case 'restore':
        _restoreCategory(category);
        break;
      case 'delete':
        _showDeleteCategoryDialog(category);
        break;
    }
  }

  // ============ DIALOG METHODS ============

  void _showCreateCategoryDialog(String type) {
    showDialog(
      context: context,
      builder: (context) => CategoryCreationDialog(
        type: type,
        userProvider: context.read<UserProvider>(),
        defaultOwnershipType: _selectedOwnershipFilter,
        onCreated: (name, ownershipType) =>
            _showSuccessSnackBar('Đã tạo danh mục "$name" thành công'),
      ),
    );
  }

  void _showCategoryDetailDialog(Category category) {
    // Implementation for category detail dialog
  }

  void _showEditCategoryDialog(Category category) {
    // Implementation for edit category dialog
  }

  void _showAddSubCategoryDialog(Category category) {
    // Implementation for add sub-category dialog
  }

  void _showDeleteCategoryDialog(Category category) {
    // Implementation for delete category confirmation dialog
  }

  void _showCreateDefaultCategoriesDialog() {
    // Implementation for creating default categories
  }

  void _showSyncStatusDialog() {
    // Implementation for sync status dialog
  }

  // ============ BUSINESS LOGIC ============

  List<Category> _applyFilters(List<Category> categories) {
    var filtered = categories;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((category) {
        return category.name.toLowerCase().contains(
              _searchQuery.toLowerCase(),
            ) ||
            category.subCategories.values.any(
              (sub) => sub.toLowerCase().contains(_searchQuery.toLowerCase()),
            );
      }).toList();
    }

    // Apply ownership filter
    if (_selectedOwnershipFilter != null) {
      filtered = filtered
          .where(
            (category) => category.ownershipType == _selectedOwnershipFilter,
          )
          .toList();
    }

    return filtered;
  }

  void _archiveCategory(Category category) {
    // Implementation for archiving category
  }

  void _restoreCategory(Category category) {
    // Implementation for restoring category
  }

  void _exportCategories() {
    // Implementation for exporting categories
  }

  void _importCategories() {
    // Implementation for importing categories
  }

  String _formatLastUsed(DateTime? lastUsed) {
    if (lastUsed == null) return 'Chưa dùng';

    final now = DateTime.now();
    final difference = now.difference(lastUsed);

    if (difference.inDays > 30) {
      return 'Hơn 1 tháng trước';
    } else if (difference.inDays > 7) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} giờ trước';
    } else {
      return 'Vừa xong';
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_rounded, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}
