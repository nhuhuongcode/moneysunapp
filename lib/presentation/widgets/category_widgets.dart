// lib/presentation/widgets/category_widgets.dart - UNIFIED VERSION

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/providers/category_provider.dart';
import 'package:moneysun/data/providers/user_provider.dart';

// ============ CATEGORY OWNERSHIP SELECTOR ============
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
                    const Icon(
                      Icons.check_circle,
                      color: Colors.white,
                      size: 16,
                    ),
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

// ============ CATEGORY CREATION DIALOG ============
class CategoryCreationDialog extends StatefulWidget {
  final String type; // 'income' or 'expense'
  final UserProvider userProvider;
  final Function(String name, CategoryOwnershipType ownershipType) onCreated;
  final CategoryOwnershipType? defaultOwnershipType;

  const CategoryCreationDialog({
    super.key,
    required this.type,
    required this.userProvider,
    required this.onCreated,
    this.defaultOwnershipType,
  });

  @override
  State<CategoryCreationDialog> createState() => _CategoryCreationDialogState();
}

class _CategoryCreationDialogState extends State<CategoryCreationDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late CategoryOwnershipType _selectedOwnership;
  int? _selectedIconCodePoint;
  List<String> _subCategories = [];
  bool _isLoading = false;
  bool _showAdvancedOptions = false;

  // Predefined icons for categories
  static const Map<String, List<int>> _categoryIcons = {
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
        child: Form(
          key: _formKey,
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
        TextFormField(
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
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.red, width: 2),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Vui lòng nhập tên danh mục';
            }
            if (value.trim().length < 2) {
              return 'Tên danh mục phải có ít nhất 2 ký tự';
            }
            if (value.trim().length > 50) {
              return 'Tên danh mục không được dài quá 50 ký tự';
            }
            if (value.contains(RegExp(r'[<>"/\\|?*]'))) {
              return 'Tên danh mục chứa ký tự không hợp lệ';
            }
            return null;
          },
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

  Map<String, String> _mapSubCategories() {
    final subCategoriesMap = <String, String>{};
    for (int i = 0; i < _subCategories.length; i++) {
      subCategoriesMap['sub_$i'] = _subCategories[i];
    }
    return subCategoriesMap;
  }

  void _createCategory() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final name = _nameController.text.trim();
    setState(() => _isLoading = true);

    try {
      debugPrint('🔄 Creating category: $name');

      final categoryProvider = Provider.of<CategoryProvider>(
        context,
        listen: false,
      );

      final success = await categoryProvider.addCategory(
        name: name,
        type: widget.type,
        ownershipType: _selectedOwnership,
        iconCodePoint: _selectedIconCodePoint,
        subCategories: _subCategories.isNotEmpty ? _mapSubCategories() : null,
      );

      if (success) {
        debugPrint('✅ Category created successfully: $name');

        widget.onCreated(name, _selectedOwnership);
        _showSuccessSnackBar('Đã tạo danh mục "$name" thành công');

        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        final error = categoryProvider.error ?? 'Không thể tạo danh mục';
        _showErrorSnackBar(error);
        debugPrint('❌ Category creation failed: $error');
      }
    } catch (e) {
      debugPrint('❌ Exception creating category: $e');
      _showErrorSnackBar('Lỗi khi tạo danh mục: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      ),
    );
  }
}

// ============ CATEGORY FILTER WIDGET ============
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

// ============ CATEGORY LIST ITEM WIDGET ============
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
            category.iconCodePoint != null
                ? IconData(category.iconCodePoint!, fontFamily: 'MaterialIcons')
                : (category.isShared
                      ? Icons.people_rounded
                      : Icons.person_rounded),
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
        trailing: trailing ?? (showActions ? _buildActionMenu() : null),
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

  Widget _buildActionMenu() {
    return PopupMenuButton<String>(
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
              Icon(Icons.delete_rounded, size: 16, color: Colors.red),
              SizedBox(width: 8),
              Text('Xóa', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
      icon: const Icon(Icons.more_vert_rounded),
    );
  }
}

// ============ CATEGORY USAGE INDICATOR ============
class CategoryUsageIndicator extends StatelessWidget {
  final Category category;

  const CategoryUsageIndicator({super.key, required this.category});

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
            '${category.usageCount} lần',
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
    if (category.usageCount == 0) return Colors.grey;
    if (category.usageCount < 5) return Colors.orange;
    if (category.usageCount < 15) return Colors.blue;
    return Colors.green;
  }

  IconData _getUsageIcon() {
    if (category.usageCount == 0) return Icons.radio_button_unchecked;
    if (category.usageCount < 5) return Icons.circle_outlined;
    if (category.usageCount < 15) return Icons.adjust_rounded;
    return Icons.check_circle_rounded;
  }
}

// ============ CATEGORY STATS WIDGET ============
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

// ============ EMPTY CATEGORIES STATE WIDGET ============
class EmptyCategoriesState extends StatelessWidget {
  final String type; // 'income' or 'expense'
  final CategoryOwnershipType? filterType;
  final UserProvider userProvider;
  final VoidCallback onCreateCategory;

  const EmptyCategoriesState({
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
      builder: (context) => CategoryCreationDialog(
        type: type,
        userProvider: userProvider,
        defaultOwnershipType: ownershipType,
        onCreated: (name, ownership) => onCreated(),
      ),
    );
  }
}
