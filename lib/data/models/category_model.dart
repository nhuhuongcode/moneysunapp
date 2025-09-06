// lib/data/models/enhanced_category_model.dart
import 'package:firebase_database/firebase_database.dart';

enum CategoryOwnershipType { personal, shared }

class Category {
  final String id;
  final String name;
  final String ownerId; // userId for personal, partnershipId for shared
  final String type; // 'income' or 'expense'
  final int? iconCodePoint; // For custom icons
  final Map<String, String> subCategories;
  final CategoryOwnershipType ownershipType;
  final String? createdBy; // Always the actual user who created it
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isArchived;
  final bool isActive;
  final int usageCount; // For smart suggestions
  final DateTime? lastUsed;
  final int version; // For conflict resolution
  final Map<String, dynamic>? metadata; // Additional data

  const Category({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.type,
    this.iconCodePoint,
    this.subCategories = const {},
    this.ownershipType = CategoryOwnershipType.personal,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.isArchived = false,
    this.isActive = true,
    this.usageCount = 0,
    this.lastUsed,
    this.version = 1,
    this.metadata,
  });

  // Computed properties
  bool get isShared => ownershipType == CategoryOwnershipType.shared;
  bool get hasSubCategories => subCategories.isNotEmpty;
  bool get isIncome => type == 'income';
  bool get isExpense => type == 'expense';

  String get displayName {
    final typeStr = isShared ? ' (Chung)' : '';
    return '$name$typeStr';
  }

  // Smart suggestions based on usage
  double get popularityScore {
    if (usageCount == 0) return 0.0;

    final daysSinceLastUse = lastUsed != null
        ? DateTime.now().difference(lastUsed!).inDays
        : 30;

    // Popularity decreases over time but usage count matters more
    return usageCount / (1 + daysSinceLastUse * 0.1);
  }

  Category copyWith({
    String? id,
    String? name,
    String? ownerId,
    String? type,
    int? iconCodePoint,
    Map<String, String>? subCategories,
    CategoryOwnershipType? ownershipType,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isArchived,
    bool? isActive,
    int? usageCount,
    DateTime? lastUsed,
    int? version,
    Map<String, dynamic>? metadata,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      type: type ?? this.type,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      subCategories: subCategories ?? this.subCategories,
      ownershipType: ownershipType ?? this.ownershipType,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isArchived: isArchived ?? this.isArchived,
      isActive: isActive ?? this.isActive,
      usageCount: usageCount ?? this.usageCount,
      lastUsed: lastUsed ?? this.lastUsed,
      version: version ?? this.version,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ownerId': ownerId,
      'type': type,
      'iconCodePoint': iconCodePoint,
      'subCategories': subCategories,
      'ownershipType': ownershipType.name,
      'createdBy': createdBy,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'isArchived': isArchived,
      'isActive': isActive,
      'usageCount': usageCount,
      'lastUsed': lastUsed?.millisecondsSinceEpoch,
      'version': version,
      'metadata': metadata,
    };
  }

  factory Category.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    return Category.fromMap(data, snapshot.key!);
  }

  factory Category.fromMap(Map<dynamic, dynamic> data, String id) {
    return Category(
      id: id,
      name: data['name'] ?? '',
      ownerId: data['ownerId'] ?? '',
      type: data['type'] ?? 'expense',
      iconCodePoint: data['iconCodePoint'],
      subCategories: Map<String, String>.from(data['subCategories'] ?? {}),
      ownershipType: CategoryOwnershipType.values.firstWhere(
        (e) => e.name == data['ownershipType'],
        orElse: () => CategoryOwnershipType.personal,
      ),
      createdBy: data['createdBy'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : null,
      updatedAt: data['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['updatedAt'])
          : null,
      isArchived: data['isArchived'] ?? false,
      isActive: data['isActive'] ?? true,
      usageCount: data['usageCount'] ?? 0,
      lastUsed: data['lastUsed'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['lastUsed'])
          : null,
      version: data['version'] ?? 1,
      metadata: data['metadata'] != null
          ? Map<String, dynamic>.from(data['metadata'])
          : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Category &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'Category{id: $id, name: $name, type: $type, ownership: $ownershipType, version: $version}';
  }
}

// Category Usage Analytics
class CategoryUsage {
  final String categoryId;
  final String categoryName;
  final int usageCount;
  final DateTime lastUsed;
  final double averageAmount;
  final List<String> commonDescriptions;
  final Map<String, int> subCategoryUsage;

  const CategoryUsage({
    required this.categoryId,
    required this.categoryName,
    required this.usageCount,
    required this.lastUsed,
    required this.averageAmount,
    required this.commonDescriptions,
    this.subCategoryUsage = const {},
  });

  double get recencyScore {
    final daysSinceLastUse = DateTime.now().difference(lastUsed).inDays;
    return usageCount / (1 + daysSinceLastUse * 0.1);
  }
}

// Category Suggestion Engine
class CategorySuggestion {
  final String categoryId;
  final String categoryName;
  final double confidence; // 0.0 to 1.0
  final String reason; // Why this was suggested
  final CategoryOwnershipType ownershipType;
  final String? suggestedSubCategory;

  const CategorySuggestion({
    required this.categoryId,
    required this.categoryName,
    required this.confidence,
    required this.reason,
    required this.ownershipType,
    this.suggestedSubCategory,
  });

  bool get isHighConfidence => confidence >= 0.8;
  bool get isMediumConfidence => confidence >= 0.5;
}

// Category Validator
class CategoryValidator {
  static bool canEdit(Category category, String currentUserId) {
    // Personal categories: only creator can edit
    if (category.ownershipType == CategoryOwnershipType.personal) {
      return category.ownerId == currentUserId;
    }

    // Shared categories: both partners can edit
    return category.createdBy == currentUserId || category.isShared;
  }

  static bool canDelete(Category category, String currentUserId) {
    // Only creator can delete
    return category.createdBy == currentUserId;
  }

  static bool isValidName(String name) {
    return name.trim().isNotEmpty && name.length <= 50;
  }

  static bool isValidType(String type) {
    return ['income', 'expense'].contains(type);
  }

  static String? validateCategory(Category category) {
    if (category.ownerId.isEmpty) return 'Owner ID không được trống';
    if (!isValidName(category.name)) return 'Tên danh mục không hợp lệ';
    if (!isValidType(category.type)) return 'Loại danh mục không hợp lệ';

    // Validate subcategories
    for (final subCat in category.subCategories.values) {
      if (!isValidName(subCat)) return 'Tên danh mục con không hợp lệ';
    }

    return null; // Valid
  }
}

// Category Utils
class CategoryUtils {
  // Default icons for common categories
  static final Map<String, int> defaultIcons = {
    // Expense categories
    'ăn uống': 0xe554, // Icons.restaurant
    'thực phẩm': 0xe554,
    'di chuyển': 0xe539, // Icons.directions_car
    'xe cộ': 0xe539,
    'giao thông': 0xe539,
    'mua sắm': 0xe59c, // Icons.shopping_bag
    'quần áo': 0xe59c,
    'giải trí': 0xe01d, // Icons.movie
    'vui chơi': 0xe01d,
    'hóa đơn': 0xe0c3, // Icons.receipt
    'tiện ích': 0xe0c3,
    'y tế': 0xe2bf, // Icons.local_hospital
    'sức khỏe': 0xe2bf,
    'học tập': 0xe80c, // Icons.school
    'giáo dục': 0xe80c,
    'nhà cửa': 0xe88a, // Icons.home
    'du lịch': 0xe539, // Icons.flight
    // Income categories
    'lương': 0xe2c8, // Icons.work
    'thưởng': 0xe263, // Icons.card_giftcard
    'đầu tư': 0xe1db, // Icons.trending_up
    'kinh doanh': 0xe1a4, // Icons.business
    'freelance': 0xe30a, // Icons.computer
    'khác': 0xe94f, // Icons.more_horiz
  };

  static int? getDefaultIcon(String categoryName) {
    final name = categoryName.toLowerCase().trim();
    for (final entry in defaultIcons.entries) {
      if (name.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }

  static List<String> getCommonSubCategories(String categoryName, String type) {
    final name = categoryName.toLowerCase();

    if (type == 'expense') {
      switch (name) {
        case 'ăn uống':
        case 'thực phẩm':
          return ['Ăn sáng', 'Ăn trưa', 'Ăn tối', 'Đồ uống', 'Ăn vặt'];
        case 'di chuyển':
        case 'giao thông':
          return ['Xăng xe', 'Taxi/Grab', 'Xe bus', 'Xe máy', 'Bảo trì xe'];
        case 'mua sắm':
          return ['Quần áo', 'Giày dép', 'Mỹ phẩm', 'Điện tử', 'Gia dụng'];
        case 'giải trí':
          return ['Phim ảnh', 'Game', 'Sách báo', 'Thể thao', 'Cafe'];
        case 'hóa đơn':
          return ['Điện', 'Nước', 'Internet', 'Điện thoại', 'Gas'];
        case 'y tế':
          return ['Khám bệnh', 'Thuốc men', 'Bảo hiểm', 'Nha khoa'];
        default:
          return [];
      }
    } else {
      switch (name) {
        case 'lương':
          return ['Lương cơ bản', 'Thưởng hiệu suất', 'Phụ cấp'];
        case 'đầu tư':
          return ['Cổ phiếu', 'Trái phiếu', 'Bất động sản', 'Cryptocurrency'];
        case 'kinh doanh':
          return ['Bán hàng', 'Dịch vụ', 'Hoa hồng'];
        default:
          return [];
      }
    }
  }

  static CategorySuggestion suggestCategory(
    String description,
    List<Category> availableCategories,
    double amount,
  ) {
    final desc = description.toLowerCase();

    // Score each category based on keyword matching
    final scores = <Category, double>{};

    for (final category in availableCategories) {
      if (!category.isActive || category.isArchived) continue;

      double score = 0.0;
      final categoryName = category.name.toLowerCase();

      // Direct name match (highest score)
      if (desc.contains(categoryName)) {
        score += 0.8;
      }

      // Keyword matching based on category type
      final keywords = _getCategoryKeywords(categoryName);
      for (final keyword in keywords) {
        if (desc.contains(keyword)) {
          score += 0.3;
        }
      }

      // Usage-based scoring (more used = higher score)
      score += category.popularityScore * 0.2;

      // Amount-based scoring for common patterns
      score += _getAmountScore(amount, categoryName) * 0.1;

      if (score > 0) {
        scores[category] = score;
      }
    }

    if (scores.isEmpty) {
      // Return default suggestion
      final defaultCategory = availableCategories.firstWhere(
        (c) => c.name.toLowerCase() == 'khác',
        orElse: () => availableCategories.first,
      );

      return CategorySuggestion(
        categoryId: defaultCategory.id,
        categoryName: defaultCategory.name,
        confidence: 0.1,
        reason: 'Danh mục mặc định',
        ownershipType: defaultCategory.ownershipType,
      );
    }

    // Get best match
    final bestMatch = scores.entries.reduce(
      (a, b) => a.value > b.value ? a : b,
    );

    final confidence = (bestMatch.value).clamp(0.0, 1.0);
    String reason = 'Từ khóa phù hợp';

    if (bestMatch.key.usageCount > 5) {
      reason = 'Thường dùng + từ khóa phù hợp';
    }

    return CategorySuggestion(
      categoryId: bestMatch.key.id,
      categoryName: bestMatch.key.name,
      confidence: confidence,
      reason: reason,
      ownershipType: bestMatch.key.ownershipType,
    );
  }

  static List<String> _getCategoryKeywords(String categoryName) {
    switch (categoryName) {
      case 'ăn uống':
        return [
          'cơm',
          'phở',
          'bún',
          'bánh',
          'quán',
          'nhà hàng',
          'cafe',
          'đồ ăn',
        ];
      case 'di chuyển':
        return ['grab', 'taxi', 'xăng', 'xe', 'bus', 'tàu', 'máy bay'];
      case 'mua sắm':
        return ['mua', 'shop', 'áo', 'quần', 'giày', 'túi', 'mỹ phẩm'];
      case 'giải trí':
        return ['phim', 'game', 'karaoke', 'bar', 'pub', 'massage'];
      case 'hóa đơn':
        return ['điện', 'nước', 'internet', 'wifi', 'gas', 'cước'];
      case 'y tế':
        return ['bác sĩ', 'thuốc', 'bệnh viện', 'khám', 'nha khoa'];
      case 'học tập':
        return ['học', 'sách', 'khóa học', 'đại học', 'trường'];
      case 'lương':
        return ['salary', 'lương', 'công ty', 'work'];
      case 'đầu tư':
        return ['cổ phiếu', 'stock', 'bitcoin', 'crypto', 'lãi'];
      default:
        return [categoryName];
    }
  }

  static double _getAmountScore(double amount, String categoryName) {
    // Common amount ranges for different categories
    switch (categoryName) {
      case 'ăn uống':
        if (amount >= 20000 && amount <= 200000) return 0.5;
        break;
      case 'di chuyển':
        if (amount >= 10000 && amount <= 500000) return 0.5;
        break;
      case 'mua sắm':
        if (amount >= 50000 && amount <= 2000000) return 0.5;
        break;
      case 'hóa đơn':
        if (amount >= 100000 && amount <= 1000000) return 0.5;
        break;
      case 'lương':
        if (amount >= 5000000 && amount <= 50000000) return 0.5;
        break;
    }
    return 0.0;
  }

  static List<Category> sortCategoriesByRelevance(
    List<Category> categories,
    String searchQuery,
  ) {
    if (searchQuery.isEmpty) {
      // Sort by usage and recency
      return categories..sort((a, b) {
        final scoreA = a.popularityScore;
        final scoreB = b.popularityScore;
        return scoreB.compareTo(scoreA);
      });
    }

    // Sort by search relevance
    final scored = categories.map((category) {
      final suggestion = suggestCategory(searchQuery, [category], 0);
      return MapEntry(category, suggestion.confidence);
    }).toList();

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  static Map<CategoryOwnershipType, List<Category>> groupByOwnership(
    List<Category> categories,
  ) {
    final groups = <CategoryOwnershipType, List<Category>>{
      CategoryOwnershipType.personal: [],
      CategoryOwnershipType.shared: [],
    };

    for (final category in categories) {
      groups[category.ownershipType]!.add(category);
    }

    return groups;
  }

  static List<Category> filterByOwnership(
    List<Category> categories,
    CategoryOwnershipType? ownershipType,
  ) {
    if (ownershipType == null) return categories;
    return categories.where((c) => c.ownershipType == ownershipType).toList();
  }

  static bool isDuplicateName(
    String name,
    List<Category> existingCategories,
    String? excludeId,
  ) {
    return existingCategories.any(
      (c) => c.name.toLowerCase() == name.toLowerCase() && c.id != excludeId,
    );
  }
}

// Category Statistics
class CategoryStatistics {
  final Map<CategoryOwnershipType, int> countByOwnership;
  final Map<String, int> countByType;
  final int totalCategories;
  final int activeCategories;
  final int archivedCategories;
  final double averageUsage;
  final Category? mostUsedCategory;
  final Category? leastUsedCategory;

  const CategoryStatistics({
    required this.countByOwnership,
    required this.countByType,
    required this.totalCategories,
    required this.activeCategories,
    required this.archivedCategories,
    required this.averageUsage,
    this.mostUsedCategory,
    this.leastUsedCategory,
  });

  factory CategoryStatistics.fromCategories(List<Category> categories) {
    final countByOwnership = <CategoryOwnershipType, int>{
      CategoryOwnershipType.personal: 0,
      CategoryOwnershipType.shared: 0,
    };

    final countByType = <String, int>{'income': 0, 'expense': 0};

    int activeCount = 0;
    int archivedCount = 0;
    int totalUsage = 0;
    Category? mostUsed;
    Category? leastUsed;

    for (final category in categories) {
      countByOwnership[category.ownershipType] =
          (countByOwnership[category.ownershipType] ?? 0) + 1;
      countByType[category.type] = (countByType[category.type] ?? 0) + 1;

      if (category.isActive && !category.isArchived) {
        activeCount++;
      } else {
        archivedCount++;
      }

      totalUsage += category.usageCount;

      if (mostUsed == null || category.usageCount > mostUsed.usageCount) {
        mostUsed = category;
      }

      if (leastUsed == null || category.usageCount < leastUsed.usageCount) {
        leastUsed = category;
      }
    }

    final avgUsage = categories.isNotEmpty
        ? totalUsage / categories.length
        : 0.0;

    return CategoryStatistics(
      countByOwnership: countByOwnership,
      countByType: countByType,
      totalCategories: categories.length,
      activeCategories: activeCount,
      archivedCategories: archivedCount,
      averageUsage: avgUsage,
      mostUsedCategory: mostUsed,
      leastUsedCategory: leastUsed,
    );
  }
}

// Category Factory for creating default categories
class CategoryFactory {
  static List<Category> createDefaultExpenseCategories(
    String userId,
    CategoryOwnershipType ownershipType,
  ) {
    final categories = <Category>[];
    final defaultExpenses = [
      'Ăn uống',
      'Di chuyển',
      'Mua sắm',
      'Giải trí',
      'Hóa đơn',
      'Y tế',
      'Học tập',
      'Khác',
    ];

    for (int i = 0; i < defaultExpenses.length; i++) {
      final name = defaultExpenses[i];
      categories.add(
        Category(
          id: 'default_expense_${i}_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          ownerId: ownershipType == CategoryOwnershipType.shared
              ? userId // Will be updated to partnershipId when saved
              : userId,
          type: 'expense',
          ownershipType: ownershipType,
          createdBy: userId,
          iconCodePoint: CategoryUtils.getDefaultIcon(name),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    return categories;
  }

  static List<Category> createDefaultIncomeCategories(
    String userId,
    CategoryOwnershipType ownershipType,
  ) {
    final categories = <Category>[];
    final defaultIncomes = [
      'Lương',
      'Thưởng',
      'Đầu tư',
      'Kinh doanh',
      'Freelance',
      'Khác',
    ];

    for (int i = 0; i < defaultIncomes.length; i++) {
      final name = defaultIncomes[i];
      categories.add(
        Category(
          id: 'default_income_${i}_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          ownerId: ownershipType == CategoryOwnershipType.shared
              ? userId // Will be updated to partnershipId when saved
              : userId,
          type: 'income',
          ownershipType: ownershipType,
          createdBy: userId,
          iconCodePoint: CategoryUtils.getDefaultIcon(name),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }

    return categories;
  }
}
