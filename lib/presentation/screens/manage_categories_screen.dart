// lib/presentation/screens/manage_categories_screen.dart - Enhanced with Edit/Delete functionality
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

          // Filter Section
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
      child: Consumer<CategoryProvider>(
        builder: (context, categoryProvider, child) {
          return PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (context) {
              final List<PopupMenuEntry<String>> items = [];

              // Toggle archived categories
              items.add(
                PopupMenuItem<String>(
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
                  onTap: () => categoryProvider.toggleIncludeArchived(),
                ),
              );

              items.add(const PopupMenuDivider());

              // Create default categories
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
    final categoryProvider = context.read<CategoryProvider>();

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
    final canDelete = categoryProvider.canDeleteCategory(category);

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
          if (canDelete)
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
    }
  }

  void _handleCategoryAction(String action, Category category) async {
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
        await _archiveCategory(category);
        break;
      case 'restore':
        await _restoreCategory(category);
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
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
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
                          : Icons.category_rounded,
                      color: category.isShared
                          ? Colors.orange.shade600
                          : Colors.blue.shade600,
                      size: 28,
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
                        const SizedBox(height: 4),
                        _buildOwnershipBadge(category),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Details
              _buildDetailRow(
                'Loại',
                category.type == 'income' ? 'Thu nhập' : 'Chi tiêu',
                Icons.trending_up_rounded,
              ),
              _buildDetailRow(
                'Số lần sử dụng',
                '${category.usageCount} lần',
                Icons.analytics_rounded,
              ),
              if (category.lastUsed != null)
                _buildDetailRow(
                  'Sử dụng gần nhất',
                  _formatLastUsed(category.lastUsed),
                  Icons.access_time_rounded,
                ),

              // Sub-categories
              if (category.subCategories.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Danh mục con (${category.subCategories.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: category.subCategories.values.map((sub) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(sub),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng'),
                  ),
                  const SizedBox(width: 8),
                  if (context.read<CategoryProvider>().canEditCategory(
                    category,
                  ))
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditCategoryDialog(category);
                      },
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Chỉnh sửa'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditCategoryDialog(Category category) {
    final nameController = TextEditingController(text: category.name);
    final categoryProvider = context.read<CategoryProvider>();
    final connectionStatus = context.read<ConnectionStatusProvider>();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 500),
          child: StatefulBuilder(
            builder: (context, setState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.edit_rounded,
                          color: Colors.orange,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Chỉnh sửa danh mục',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  // Connection status indicator
                  if (!connectionStatus.isOnline) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cloud_off_rounded,
                            size: 18,
                            color: Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Chế độ offline - Thay đổi sẽ được đồng bộ khi có mạng',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Name field
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Tên danh mục *',
                      hintText: 'Nhập tên danh mục',
                      prefixIcon: const Icon(Icons.label_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                    ),
                    autofocus: true,
                  ),

                  const SizedBox(height: 16),

                  // Category info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Thông tin danh mục',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Loại: ${category.type == "income" ? "Thu nhập" : "Chi tiêu"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        Text(
                          'Quyền: ${category.isShared ? "Chung" : "Cá nhân"}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (category.usageCount > 0)
                          Text(
                            'Đã sử dụng: ${category.usageCount} lần',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final newName = nameController.text.trim();

                          if (newName.isEmpty) {
                            _showErrorSnackBar(
                              'Tên danh mục không được để trống',
                            );
                            return;
                          }

                          if (newName == category.name) {
                            Navigator.pop(context);
                            return;
                          }

                          // Show loading
                          Navigator.pop(context);
                          _showLoadingDialog('Đang cập nhật...');

                          try {
                            final updatedCategory = category.copyWith(
                              name: newName,
                              updatedAt: DateTime.now(),
                            );

                            final success = await categoryProvider
                                .updateCategory(updatedCategory);

                            Navigator.pop(context); // Close loading

                            if (success) {
                              _showSuccessSnackBar(
                                'Đã cập nhật danh mục thành công',
                              );
                            } else {
                              _showErrorSnackBar(
                                categoryProvider.error ??
                                    'Không thể cập nhật danh mục',
                              );
                            }
                          } catch (e) {
                            Navigator.pop(context); // Close loading
                            _showErrorSnackBar('Lỗi: $e');
                          }
                        },
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Lưu thay đổi'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showAddSubCategoryDialog(Category category) {
    final subCategoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_rounded,
                      color: Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Thêm danh mục con',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'cho "${category.name}"',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Sub-category name field
              TextField(
                controller: subCategoryController,
                decoration: InputDecoration(
                  labelText: 'Tên danh mục con *',
                  hintText: 'Ví dụ: Quần áo, Thực phẩm...',
                  prefixIcon: const Icon(Icons.subdirectory_arrow_right),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                ),
                autofocus: true,
              ),

              // Existing sub-categories
              if (category.subCategories.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  'Danh mục con hiện tại (${category.subCategories.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: category.subCategories.entries.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(entry.value),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              // Remove sub-category
                              final updatedSubCategories =
                                  Map<String, String>.from(
                                    category.subCategories,
                                  )..remove(entry.key);

                              final updatedCategory = category.copyWith(
                                subCategories: updatedSubCategories,
                                updatedAt: DateTime.now(),
                              );

                              context.read<CategoryProvider>().updateCategory(
                                updatedCategory,
                              );
                            },
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.red.shade400,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 24),

              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final subCategoryName = subCategoryController.text.trim();

                      if (subCategoryName.isEmpty) {
                        _showErrorSnackBar(
                          'Tên danh mục con không được để trống',
                        );
                        return;
                      }

                      // Check for duplicates
                      if (category.subCategories.values.contains(
                        subCategoryName,
                      )) {
                        _showErrorSnackBar('Danh mục con này đã tồn tại');
                        return;
                      }

                      Navigator.pop(context);
                      _showLoadingDialog('Đang thêm...');

                      try {
                        final newSubCategories = Map<String, String>.from(
                          category.subCategories,
                        );
                        final subCategoryId =
                            'sub_${DateTime.now().millisecondsSinceEpoch}';
                        newSubCategories[subCategoryId] = subCategoryName;

                        final updatedCategory = category.copyWith(
                          subCategories: newSubCategories,
                          updatedAt: DateTime.now(),
                        );

                        final success = await context
                            .read<CategoryProvider>()
                            .updateCategory(updatedCategory);

                        Navigator.pop(context); // Close loading

                        if (success) {
                          _showSuccessSnackBar(
                            'Đã thêm danh mục con "$subCategoryName"',
                          );
                        } else {
                          _showErrorSnackBar('Không thể thêm danh mục con');
                        }
                      } catch (e) {
                        Navigator.pop(context);
                        _showErrorSnackBar('Lỗi: $e');
                      }
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Thêm'),
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
    final categoryProvider = context.read<CategoryProvider>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.delete_rounded,
                color: Colors.red,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Xóa danh mục?', style: TextStyle(fontSize: 20)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn có chắc muốn xóa danh mục "${category.name}"?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (category.usageCount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Danh mục này đã được sử dụng ${category.usageCount} lần. Không thể xóa danh mục đang được sử dụng.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Hành động này không thể hoàn tác!',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
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
          if (category.usageCount == 0)
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                _showLoadingDialog('Đang xóa...');

                try {
                  final success = await categoryProvider.deleteCategory(
                    category.id,
                  );

                  Navigator.pop(context); // Close loading

                  if (success) {
                    _showSuccessSnackBar('Đã xóa danh mục "${category.name}"');
                  } else {
                    _showErrorSnackBar(
                      categoryProvider.error ?? 'Không thể xóa danh mục',
                    );
                  }
                } catch (e) {
                  Navigator.pop(context);
                  _showErrorSnackBar('Lỗi: $e');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.delete_rounded, size: 18),
              label: const Text('Xóa'),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _archiveCategory(category);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.archive_rounded, size: 18),
              label: const Text('Lưu trữ thay thế'),
            ),
        ],
      ),
    );
  }

  void _showCreateDefaultCategoriesDialog() {
    // Implementation for creating default categories
  }

  void _showSyncStatusDialog() {
    final connectionStatus = context.read<ConnectionStatusProvider>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              connectionStatus.isOnline
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_off_rounded,
              color: connectionStatus.statusColor,
            ),
            const SizedBox(width: 12),
            const Text('Trạng thái đồng bộ'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusRow(
              'Kết nối',
              connectionStatus.isOnline ? 'Online' : 'Offline',
              connectionStatus.isOnline ? Colors.green : Colors.red,
            ),
            _buildStatusRow(
              'Đang đồng bộ',
              connectionStatus.isSyncing ? 'Có' : 'Không',
              connectionStatus.isSyncing ? Colors.orange : Colors.grey,
            ),
            _buildStatusRow(
              'Mục chưa đồng bộ',
              '${connectionStatus.pendingItems}',
              connectionStatus.pendingItems > 0 ? Colors.blue : Colors.green,
            ),
            if (connectionStatus.lastSyncTime != null)
              _buildStatusRow(
                'Lần cuối',
                _formatLastUsed(connectionStatus.lastSyncTime!),
                Colors.grey,
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
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

  Future<void> _archiveCategory(Category category) async {
    _showLoadingDialog('Đang lưu trữ...');

    try {
      final categoryProvider = context.read<CategoryProvider>();
      final success = await categoryProvider.archiveCategory(category.id);

      Navigator.pop(context); // Close loading

      if (success) {
        _showSuccessSnackBar('Đã lưu trữ danh mục "${category.name}"');
      } else {
        _showErrorSnackBar(
          categoryProvider.error ?? 'Không thể lưu trữ danh mục',
        );
      }
    } catch (e) {
      Navigator.pop(context);
      _showErrorSnackBar('Lỗi: $e');
    }
  }

  Future<void> _restoreCategory(Category category) async {
    _showLoadingDialog('Đang khôi phục...');

    try {
      final categoryProvider = context.read<CategoryProvider>();
      final success = await categoryProvider.restoreCategory(category.id);

      Navigator.pop(context); // Close loading

      if (success) {
        _showSuccessSnackBar('Đã khôi phục danh mục "${category.name}"');
      } else {
        _showErrorSnackBar(
          categoryProvider.error ?? 'Không thể khôi phục danh mục',
        );
      }
    } catch (e) {
      Navigator.pop(context);
      _showErrorSnackBar('Lỗi: $e');
    }
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
    if (!mounted) return;

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
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

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
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Đóng',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}

// ============ EMPTY STATE WIDGET ============

class EmptyCategoriesState extends StatelessWidget {
  final String type;
  final CategoryOwnershipType? filterType;
  final UserProvider userProvider;
  final VoidCallback onCreateCategory;

  const EmptyCategoriesState({
    super.key,
    required this.type,
    required this.filterType,
    required this.userProvider,
    required this.onCreateCategory,
  });

  @override
  Widget build(BuildContext context) {
    String title;
    String subtitle;
    IconData icon;

    if (filterType != null) {
      // Filtered empty state
      title = 'Không tìm thấy danh mục';
      subtitle = filterType == CategoryOwnershipType.personal
          ? 'Chưa có danh mục cá nhân nào trong mục ${type == "income" ? "thu nhập" : "chi tiêu"}'
          : 'Chưa có danh mục chung nào trong mục ${type == "income" ? "thu nhập" : "chi tiêu"}';
      icon = Icons.filter_list_off;
    } else {
      // Normal empty state
      title = 'Chưa có danh mục nào';
      subtitle =
          'Tạo danh mục ${type == "income" ? "thu nhập" : "chi tiêu"} đầu tiên của bạn';
      icon = Icons.category_rounded;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: onCreateCategory,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Tạo danh mục ${type == "income" ? "thu nhập" : "chi tiêu"}',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ CATEGORY FILTER WIDGET ============

class CategoryFilterWidget extends StatelessWidget {
  final CategoryOwnershipType? selectedOwnership;
  final Function(CategoryOwnershipType?) onChanged;
  final UserProvider userProvider;

  const CategoryFilterWidget({
    super.key,
    required this.selectedOwnership,
    required this.onChanged,
    required this.userProvider,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _buildFilterChip(
            context,
            'Tất cả',
            null,
            Icons.category_rounded,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildFilterChip(
            context,
            'Cá nhân',
            CategoryOwnershipType.personal,
            Icons.person_rounded,
          ),
        ),
        if (userProvider.hasPartner) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _buildFilterChip(
              context,
              'Chung',
              CategoryOwnershipType.shared,
              Icons.people_rounded,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterChip(
    BuildContext context,
    String label,
    CategoryOwnershipType? type,
    IconData icon,
  ) {
    final isSelected = selectedOwnership == type;

    Color getColor() {
      if (type == null) return Colors.grey.shade600;
      if (type == CategoryOwnershipType.personal) return Colors.blue.shade600;
      return Colors.orange.shade600;
    }

    return InkWell(
      onTap: () => onChanged(type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? getColor().withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? getColor() : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? getColor() : Colors.grey.shade600,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? getColor() : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============ CATEGORY CREATION DIALOG (Placeholder) ============

class CategoryCreationDialog extends StatefulWidget {
  final String type;
  final UserProvider userProvider;
  final CategoryOwnershipType? defaultOwnershipType;
  final Function(String name, CategoryOwnershipType ownershipType) onCreated;

  const CategoryCreationDialog({
    super.key,
    required this.type,
    required this.userProvider,
    this.defaultOwnershipType,
    required this.onCreated,
  });

  @override
  State<CategoryCreationDialog> createState() => _CategoryCreationDialogState();
}

class _CategoryCreationDialogState extends State<CategoryCreationDialog> {
  final _nameController = TextEditingController();
  late CategoryOwnershipType _selectedOwnership;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedOwnership =
        widget.defaultOwnershipType ?? CategoryOwnershipType.personal;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.green,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tạo danh mục ${widget.type == "income" ? "thu nhập" : "chi tiêu"}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Name field
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Tên danh mục *',
                hintText: 'Ví dụ: Ăn uống, Lương...',
                prefixIcon: const Icon(Icons.label_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              autofocus: true,
            ),

            const SizedBox(height: 16),

            // Ownership type
            if (widget.userProvider.hasPartner) ...[
              const Text(
                'Loại danh mục:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildOwnershipOption(
                      CategoryOwnershipType.personal,
                      'Cá nhân',
                      Icons.person_rounded,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildOwnershipOption(
                      CategoryOwnershipType.shared,
                      'Chung',
                      Icons.people_rounded,
                      Colors.orange,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _createCategory,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Tạo danh mục'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnershipOption(
    CategoryOwnershipType type,
    String label,
    IconData icon,
    Color color,
  ) {
    final isSelected = _selectedOwnership == type;

    return InkWell(
      onTap: () => setState(() => _selectedOwnership = type),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? color : Colors.grey.shade600,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? color : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCategory() async {
    final name = _nameController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tên danh mục không được để trống'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final categoryProvider = context.read<CategoryProvider>();

      final success = await categoryProvider.addCategory(
        name: name,
        type: widget.type,
        ownershipType: _selectedOwnership,
      );

      if (!mounted) return;

      if (success) {
        Navigator.pop(context);
        widget.onCreated(name, _selectedOwnership);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(categoryProvider.error ?? 'Không thể tạo danh mục'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
