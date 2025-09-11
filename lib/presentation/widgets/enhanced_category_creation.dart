// lib/presentation/widgets/enhanced_category_creation.dart
import 'package:flutter/material.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/category_service.dart';
import 'package:moneysun/presentation/widgets/category_ownership_selector.dart';

// ============ ENHANCED CATEGORY CREATION DIALOG ============
class EnhancedCategoryCreationDialog extends StatefulWidget {
  final String type; // 'income' or 'expense'
  final UserProvider userProvider;
  final Function(String name, CategoryOwnershipType ownershipType) onCreated;
  final CategoryOwnershipType? defaultOwnershipType;

  const EnhancedCategoryCreationDialog({
    super.key,
    required this.type,
    required this.userProvider,
    required this.onCreated,
    this.defaultOwnershipType,
  });

  @override
  State<EnhancedCategoryCreationDialog> createState() =>
      _EnhancedCategoryCreationDialogState();
}

class _EnhancedCategoryCreationDialogState
    extends State<EnhancedCategoryCreationDialog> {
  final _nameController = TextEditingController();
  final _categoryService = CategoryService();

  late CategoryOwnershipType _selectedOwnership;
  int? _selectedIconCodePoint;
  List<String> _subCategories = [];
  bool _isLoading = false;
  bool _showAdvancedOptions = false;

  // Predefined icons for categories
  final Map<String, List<int>> _categoryIcons = {
    'expense': [
      0xe554, // restaurant
      0xe539, // directions_car
      0xe59c, // shopping_bag
      0xe01d, // movie
      0xe0c3, // receipt
      0xe2bf, // local_hospital
      0xe80c, // school
      0xe88a, // home
      0xe263, // card_giftcard
      0xe94f, // more_horiz
    ],
    'income': [
      0xe2c8, // work
      0xe263, // card_giftcard
      0xe1db, // trending_up
      0xe1a4, // business
      0xe30a, // computer
      0xe2bc, // savings
      0xe263, // money
      0xe94f, // more_horiz
    ],
  };

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
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            _buildHeader(),

            const SizedBox(height: 24),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Name Input
                    _buildNameInput(),

                    const SizedBox(height: 20),

                    // Ownership Selector
                    _buildOwnershipSelector(),

                    const SizedBox(height: 20),

                    // Advanced Options Toggle
                    _buildAdvancedOptionsToggle(),

                    if (_showAdvancedOptions) ...[
                      const SizedBox(height: 20),

                      // Icon Selector
                      _buildIconSelector(),

                      const SizedBox(height: 20),

                      // Sub-categories
                      _buildSubCategoriesSection(),
                    ],

                    const SizedBox(height: 20),

                    // Partnership Info
                    if (_selectedOwnership == CategoryOwnershipType.shared &&
                        widget.userProvider.hasPartner)
                      _buildPartnershipInfo(),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action Buttons
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (widget.type == 'income' ? Colors.green : Colors.purple)
                .withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            widget.type == 'income'
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            color: widget.type == 'income' ? Colors.green : Colors.purple,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Thêm danh mục ${widget.type == 'income' ? 'thu nhập' : 'chi tiêu'}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Tạo danh mục mới để phân loại giao dịch',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNameInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tên danh mục *',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _nameController,
          decoration: InputDecoration(
            hintText: widget.type == 'income'
                ? 'VD: Lương, Thưởng, Đầu tư...'
                : 'VD: Ăn uống, Di chuyển, Mua sắm...',
            filled: true,
            fillColor: (widget.type == 'income' ? Colors.green : Colors.purple)
                .withOpacity(0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: widget.type == 'income' ? Colors.green : Colors.purple,
                width: 2,
              ),
            ),
            prefixIcon: const Icon(Icons.category_outlined),
          ),
          autofocus: true,
          enabled: !_isLoading,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }

  Widget _buildOwnershipSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Loại danh mục *',
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
    );
  }

  Widget _buildAdvancedOptionsToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showAdvancedOptions = !_showAdvancedOptions),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(
              _showAdvancedOptions ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey.shade600,
            ),
            const SizedBox(width: 12),
            Text(
              'Tùy chọn nâng cao',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
            const Spacer(),
            if (_showAdvancedOptions) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Mở rộng',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIconSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Chọn biểu tượng',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              if (_selectedIconCodePoint != null) ...[
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            (widget.type == 'income'
                                    ? Colors.green
                                    : Colors.purple)
                                .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        IconData(
                          _selectedIconCodePoint!,
                          fontFamily: 'MaterialIcons',
                        ),
                        color: widget.type == 'income'
                            ? Colors.green
                            : Colors.purple,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Biểu tượng đã chọn'),
                    const Spacer(),
                    TextButton(
                      onPressed: () =>
                          setState(() => _selectedIconCodePoint = null),
                      child: const Text('Xóa'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Icon Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: _categoryIcons[widget.type]?.length ?? 0,
                itemBuilder: (context, index) {
                  final iconCode = _categoryIcons[widget.type]![index];
                  final isSelected = _selectedIconCodePoint == iconCode;

                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedIconCodePoint = iconCode),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (widget.type == 'income'
                                      ? Colors.green
                                      : Colors.purple)
                                  .withOpacity(0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? (widget.type == 'income'
                                    ? Colors.green
                                    : Colors.purple)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Icon(
                        IconData(iconCode, fontFamily: 'MaterialIcons'),
                        color: isSelected
                            ? (widget.type == 'income'
                                  ? Colors.green
                                  : Colors.purple)
                            : Colors.grey.shade600,
                        size: 24,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Danh mục con',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _addSubCategory,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Thêm'),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_subCategories.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
                const SizedBox(width: 12),
                Text(
                  'Chưa có danh mục con nào',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ] else ...[
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _subCategories.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: Colors.grey.shade200),
              itemBuilder: (context, index) {
                final subCategory = _subCategories[index];
                return ListTile(
                  dense: true,
                  leading: const Icon(Icons.subdirectory_arrow_right, size: 16),
                  title: Text(subCategory),
                  trailing: IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Colors.red,
                    ),
                    onPressed: () => _removeSubCategory(index),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPartnershipInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.people_rounded, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Danh mục chung',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade700,
                  ),
                ),
                Text(
                  'Danh mục này sẽ được chia sẻ với ${widget.userProvider.partnerDisplayName ?? "đối tác"}',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
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
                  : (widget.type == 'income' ? Colors.green : Colors.purple),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Tạo danh mục',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ),
      ],
    );
  }

  // Helper methods
  void _addSubCategory() {
    showDialog(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Thêm danh mục con'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Tên danh mục con',
              hintText: 'VD: Ăn sáng, Ăn trưa...',
            ),
            autofocus: true,
            textCapitalization: TextCapitalization.words,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty && !_subCategories.contains(name)) {
                  setState(() => _subCategories.add(name));
                  Navigator.pop(context);
                }
              },
              child: const Text('Thêm'),
            ),
          ],
        );
      },
    );
  }

  void _removeSubCategory(int index) {
    setState(() => _subCategories.removeAt(index));
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
      // Convert subCategories list to map
      final subCategoriesMap = <String, String>{};
      for (int i = 0; i < _subCategories.length; i++) {
        subCategoriesMap['sub_$i'] = _subCategories[i];
      }

      await _categoryService.createCategoryWithOwnership(
        name: name,
        type: widget.type,
        ownershipType: _selectedOwnership,
        userProvider: widget.userProvider,
        iconCodePoint: _selectedIconCodePoint,
        subCategories: subCategoriesMap.isNotEmpty ? subCategoriesMap : null,
      );

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

// ============ CATEGORY QUICK CREATE WIDGET ============
class CategoryQuickCreateWidget extends StatelessWidget {
  final String type;
  final UserProvider userProvider;
  final VoidCallback onCreated;

  const CategoryQuickCreateWidget({
    super.key,
    required this.type,
    required this.userProvider,
    required this.onCreated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (type == 'income' ? Colors.green : Colors.purple).withOpacity(
            0.2,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            type == 'income'
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 48,
            color: (type == 'income' ? Colors.green : Colors.purple)
                .withOpacity(0.6),
          ),
          const SizedBox(height: 16),
          Text(
            'Tạo danh mục ${type == 'income' ? 'thu nhập' : 'chi tiêu'} đầu tiên',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Danh mục giúp bạn phân loại và theo dõi ${type == 'income' ? 'thu nhập' : 'chi tiêu'} hiệu quả hơn',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showQuickCreateDialog(
                    context,
                    CategoryOwnershipType.personal,
                  ),
                  icon: const Icon(Icons.person_rounded, size: 18),
                  label: const Text('Cá nhân'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                  ),
                ),
              ),
              if (userProvider.hasPartner) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showQuickCreateDialog(
                      context,
                      CategoryOwnershipType.shared,
                    ),
                    icon: const Icon(Icons.people_rounded, size: 18),
                    label: const Text('Chung'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  void _showQuickCreateDialog(
    BuildContext context,
    CategoryOwnershipType ownershipType,
  ) {
    showDialog(
      context: context,
      builder: (context) => EnhancedCategoryCreationDialog(
        type: type,
        userProvider: userProvider,
        defaultOwnershipType: ownershipType,
        onCreated: (name, ownership) => onCreated(),
      ),
    );
  }
}

// ============ DEFAULT CATEGORIES CREATOR ============
class DefaultCategoriesCreator {
  static final CategoryService _categoryService = CategoryService();

  static Future<void> createDefaultCategories(
    UserProvider userProvider, {
    bool createShared = false,
  }) async {
    if (userProvider.currentUser == null) return;

    try {
      final ownershipType = createShared
          ? CategoryOwnershipType.shared
          : CategoryOwnershipType.personal;

      // Default expense categories
      final expenseCategories = [
        'Ăn uống',
        'Di chuyển',
        'Mua sắm',
        'Giải trí',
        'Hóa đơn',
        'Y tế',
        'Khác',
      ];

      // Default income categories
      final incomeCategories = [
        'Lương',
        'Thưởng',
        'Đầu tư',
        'Kinh doanh',
        'Khác',
      ];

      // Create expense categories
      for (final categoryName in expenseCategories) {
        await _categoryService.createCategoryWithOwnership(
          name: categoryName,
          type: 'expense',
          ownershipType: ownershipType,
          userProvider: userProvider,
          iconCodePoint: CategoryUtils.getDefaultIcon(categoryName),
        );
      }

      // Create income categories
      for (final categoryName in incomeCategories) {
        await _categoryService.createCategoryWithOwnership(
          name: categoryName,
          type: 'income',
          ownershipType: ownershipType,
          userProvider: userProvider,
          iconCodePoint: CategoryUtils.getDefaultIcon(categoryName),
        );
      }

      print('✅ Created default ${ownershipType.name} categories');
    } catch (e) {
      print('❌ Error creating default categories: $e');
    }
  }

  static Future<void> createDefaultCategoriesIfNeeded(
    UserProvider userProvider,
  ) async {
    try {
      // Check if user has any categories
      final personalCategories = await _categoryService
          .getCategoriesOfflineFirst(
            userProvider: userProvider,
            ownershipType: CategoryOwnershipType.personal,
          );

      if (personalCategories.isEmpty) {
        await createDefaultCategories(userProvider, createShared: false);
      }

      // If user has partner, check shared categories
      if (userProvider.hasPartner) {
        final sharedCategories = await _categoryService
            .getCategoriesOfflineFirst(
              userProvider: userProvider,
              ownershipType: CategoryOwnershipType.shared,
            );

        if (sharedCategories.isEmpty) {
          await createDefaultCategories(userProvider, createShared: true);
        }
      }
    } catch (e) {
      print('❌ Error checking/creating default categories: $e');
    }
  }
}
