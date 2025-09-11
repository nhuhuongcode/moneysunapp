// lib/presentation/widgets/category_ownership_selector.dart
import 'package:flutter/material.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';

class CategoryOwnershipSelector extends StatefulWidget {
  final CategoryOwnershipType selectedType;
  final ValueChanged<CategoryOwnershipType> onChanged;
  final UserProvider userProvider;
  final bool enabled;

  const CategoryOwnershipSelector({
    super.key,
    required this.selectedType,
    required this.onChanged,
    required this.userProvider,
    this.enabled = true,
  });

  @override
  State<CategoryOwnershipSelector> createState() =>
      _CategoryOwnershipSelectorState();
}

class _CategoryOwnershipSelectorState extends State<CategoryOwnershipSelector>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If user doesn't have partner, only show personal option
    if (!widget.userProvider.hasPartner) {
      return _buildPersonalOnlySelector();
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildOwnershipOption(
              CategoryOwnershipType.personal,
              Icons.person_rounded,
              'Cá nhân',
              Colors.blue.shade600,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildOwnershipOption(
              CategoryOwnershipType.shared,
              Icons.people_rounded,
              'Chung',
              Colors.orange.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalOnlySelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.person_rounded,
              color: Colors.blue.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Danh mục cá nhân',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
                Text(
                  'Kết nối với đối tác để tạo danh mục chung',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnershipOption(
    CategoryOwnershipType type,
    IconData icon,
    String label,
    Color color,
  ) {
    final isSelected = widget.selectedType == type;

    return GestureDetector(
      onTap: widget.enabled
          ? () {
              _animationController.forward().then((_) {
                _animationController.reverse();
              });
              widget.onChanged(type);
            }
          : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: isSelected ? _scaleAnimation.value : 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              decoration: BoxDecoration(
                gradient: isSelected
                    ? LinearGradient(
                        colors: [color.withOpacity(0.8), color],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isSelected ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: isSelected ? Colors.white : color,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isSelected ? Colors.white : color,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (type == CategoryOwnershipType.shared && isSelected) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.check_circle, color: Colors.white, size: 16),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// Enhanced Category List Item with Ownership Badge
class CategoryListItemWithOwnership extends StatelessWidget {
  final Category category;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool showActions;
  final Widget? trailing;

  const CategoryListItemWithOwnership({
    super.key,
    required this.category,
    this.onTap,
    this.onEdit,
    this.onDelete,
    this.showActions = true,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: category.isShared
              ? Colors.orange.withOpacity(0.3)
              : Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: (category.isShared ? Colors.orange : Colors.blue)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            category.isShared ? Icons.people_rounded : Icons.person_rounded,
            color: category.isShared
                ? Colors.orange.shade600
                : Colors.blue.shade600,
            size: 20,
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
            _buildOwnershipBadge(),
          ],
        ),
        subtitle: category.subCategories.isNotEmpty
            ? Text(
                '${category.subCategories.length} danh mục con',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              )
            : null,
        trailing:
            trailing ??
            (showActions
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'edit':
                          onEdit?.call();
                          break;
                        case 'delete':
                          onDelete?.call();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 16),
                            SizedBox(width: 8),
                            Text('Chỉnh sửa'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_rounded,
                              size: 16,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text('Xóa', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    icon: const Icon(Icons.more_vert_rounded),
                  )
                : null),
      ),
    );
  }

  Widget _buildOwnershipBadge() {
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
}

// Enhanced Category Creation Dialog
class CategoryCreationDialog extends StatefulWidget {
  final String type; // 'income' or 'expense'
  final UserProvider userProvider;
  final Function(String name, CategoryOwnershipType ownershipType) onCreated;

  const CategoryCreationDialog({
    super.key,
    required this.type,
    required this.userProvider,
    required this.onCreated,
    CategoryOwnershipType? defaultOwnershipType,
  });

  @override
  State<CategoryCreationDialog> createState() => _CategoryCreationDialogState();
}

class _CategoryCreationDialogState extends State<CategoryCreationDialog> {
  final _nameController = TextEditingController();
  CategoryOwnershipType _selectedOwnership = CategoryOwnershipType.personal;
  bool _isLoading = false;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        (widget.type == 'income' ? Colors.green : Colors.purple)
                            .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    widget.type == 'income'
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: widget.type == 'income'
                        ? Colors.green
                        : Colors.purple,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Thêm danh mục ${widget.type == 'income' ? 'thu nhập' : 'chi tiêu'}',
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
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Tên danh mục',
                filled: true,
                fillColor:
                    (widget.type == 'income' ? Colors.green : Colors.purple)
                        .withOpacity(0.05),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: widget.type == 'income'
                        ? Colors.green
                        : Colors.purple,
                    width: 2,
                  ),
                ),
                prefixIcon: const Icon(Icons.category_outlined),
              ),
              autofocus: true,
              enabled: !_isLoading,
            ),

            const SizedBox(height: 20),

            // Ownership Selector
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Loại danh mục:',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                CategoryOwnershipSelector(
                  selectedType: _selectedOwnership,
                  onChanged: (type) {
                    if (!_isLoading) {
                      setState(() => _selectedOwnership = type);
                    }
                  },
                  userProvider: widget.userProvider,
                  enabled: !_isLoading,
                ),
              ],
            ),

            // Partnership Info
            if (_selectedOwnership == CategoryOwnershipType.shared &&
                widget.userProvider.hasPartner) ...[
              const SizedBox(height: 16),
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
                      Icons.info_outline,
                      color: Colors.orange,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Danh mục này sẽ được chia sẻ với ${widget.userProvider.partnerDisplayName ?? "đối tác"}',
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

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
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
                    onPressed: _isLoading ? null : _createCategory,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _selectedOwnership == CategoryOwnershipType.shared
                          ? Colors.orange
                          : (widget.type == 'income'
                                ? Colors.green
                                : Colors.purple),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text(
                            'Tạo danh mục',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _createCategory() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập tên danh mục'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      widget.onCreated(name, _selectedOwnership);
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi khi tạo danh mục: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

// Category Filter Widget
class CategoryFilterWidget extends StatelessWidget {
  final CategoryOwnershipType? selectedOwnership;
  final ValueChanged<CategoryOwnershipType?> onChanged;
  final UserProvider userProvider;

  const CategoryFilterWidget({
    super.key,
    required this.selectedOwnership,
    required this.onChanged,
    required this.userProvider,
  });

  @override
  Widget build(BuildContext context) {
    if (!userProvider.hasPartner) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFilterChip(
            label: 'Tất cả',
            isSelected: selectedOwnership == null,
            onTap: () => onChanged(null),
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 4),
          _buildFilterChip(
            label: 'Cá nhân',
            isSelected: selectedOwnership == CategoryOwnershipType.personal,
            onTap: () => onChanged(CategoryOwnershipType.personal),
            color: Colors.blue.shade600,
          ),
          const SizedBox(width: 4),
          _buildFilterChip(
            label: 'Chung',
            isSelected: selectedOwnership == CategoryOwnershipType.shared,
            onTap: () => onChanged(CategoryOwnershipType.shared),
            color: Colors.orange.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

// Enhanced Category Stats Widget
class CategoryStatsWidget extends StatelessWidget {
  final List<Category> categories;
  final UserProvider userProvider;

  const CategoryStatsWidget({
    super.key,
    required this.categories,
    required this.userProvider,
  });

  @override
  Widget build(BuildContext context) {
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
}

// Category Usage Indicator
class CategoryUsageIndicator extends StatelessWidget {
  final Category category;
  final int usageCount;
  final DateTime? lastUsed;

  const CategoryUsageIndicator({
    super.key,
    required this.category,
    required this.usageCount,
    this.lastUsed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getUsageColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _getUsageColor().withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_getUsageIcon(), size: 12, color: _getUsageColor()),
          const SizedBox(width: 4),
          Text(
            '$usageCount lần',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _getUsageColor(),
            ),
          ),
        ],
      ),
    );
  }

  Color _getUsageColor() {
    if (usageCount == 0) return Colors.grey;
    if (usageCount < 5) return Colors.orange;
    if (usageCount < 15) return Colors.blue;
    return Colors.green;
  }

  IconData _getUsageIcon() {
    if (usageCount == 0) return Icons.radio_button_unchecked;
    if (usageCount < 5) return Icons.circle_outlined;
    if (usageCount < 15) return Icons.adjust_rounded;
    return Icons.check_circle_rounded;
  }
}

// Enhanced Empty Categories State
class EmptyCategoriessState extends StatelessWidget {
  final String type; // 'income' or 'expense'
  final CategoryOwnershipType? filterType;
  final UserProvider userProvider;
  final VoidCallback onCreateCategory;

  const EmptyCategoriessState({
    super.key,
    required this.type,
    this.filterType,
    required this.userProvider,
    required this.onCreateCategory,
  });

  @override
  Widget build(BuildContext context) {
    final isFiltered = filterType != null;
    final isSharedFilter = filterType == CategoryOwnershipType.shared;

    return Container(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: (isSharedFilter ? Colors.orange : Colors.blue).withOpacity(
                0.1,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSharedFilter
                  ? Icons.people_outline_rounded
                  : Icons.category_outlined,
              size: 64,
              color: (isSharedFilter ? Colors.orange : Colors.blue).shade300,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            isFiltered
                ? 'Chưa có danh mục ${isSharedFilter ? "chung" : "cá nhân"} nào'
                : 'Chưa có danh mục ${type == 'income' ? 'thu nhập' : 'chi tiêu'} nào',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            isFiltered && isSharedFilter && !userProvider.hasPartner
                ? 'Kết nối với đối tác để tạo danh mục chung'
                : 'Tạo danh mục để bắt đầu phân loại giao dịch',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (!isFiltered || (isSharedFilter && userProvider.hasPartner))
            ElevatedButton.icon(
              onPressed: onCreateCategory,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Tạo danh mục ${isSharedFilter ? "chung" : (type == 'income' ? 'thu nhập' : 'chi tiêu')}',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSharedFilter ? Colors.orange : Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
