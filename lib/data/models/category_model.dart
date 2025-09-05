// lib/data/models/category_model.dart - Enhanced with shared category support

import 'package:firebase_database/firebase_database.dart';
import 'package:equatable/equatable.dart';

enum CategoryOwnershipType { personal, shared }

class Category extends Equatable {
  final String id;
  final String name;
  final String ownerId; // For personal: userId, For shared: partnershipId
  final String type; // 'income' or 'expense'
  final int? iconCodePoint;
  final Map<String, String> subCategories;
  final CategoryOwnershipType ownershipType;
  final String? createdBy; // Who created this category
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool isArchived;

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
  });

  factory Category.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    final subs = data['subCategories'] as Map<dynamic, dynamic>? ?? {};

    return Category(
      id: snapshot.key!,
      name: data['name'] ?? 'Không tên',
      ownerId: data['ownerId'] ?? '',
      type: data['type'] ?? 'expense',
      iconCodePoint: data['iconCodePoint'] as int?,
      subCategories: subs.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'ownerId': ownerId,
      'type': type,
      'iconCodePoint': iconCodePoint,
      'subCategories': subCategories,
      'ownershipType': ownershipType.name,
      'createdBy': createdBy,
      'createdAt': createdAt?.millisecondsSinceEpoch ?? ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      'isArchived': isArchived,
    };
  }

  // Helper methods
  bool get isShared => ownershipType == CategoryOwnershipType.shared;
  bool get isPersonal => ownershipType == CategoryOwnershipType.personal;
  bool get isActive => !isArchived;

  String get displayName {
    String suffix = '';
    if (isShared) {
      suffix = ' (Chung)';
    } else if (isArchived) {
      suffix = ' (Đã lưu trữ)';
    }
    return name + suffix;
  }

  // Copy with method
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
    );
  }

  @override
  List<Object?> get props => [id];

  @override
  String toString() {
    return 'Category(id: $id, name: $name, ownerId: $ownerId, type: $type, ownershipType: $ownershipType)';
  }
}

// Category validation utilities
class CategoryValidator {
  static String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Tên danh mục không được để trống';
    }
    if (name.trim().length < 2) {
      return 'Tên danh mục phải có ít nhất 2 ký tự';
    }
    if (name.trim().length > 50) {
      return 'Tên danh mục không được vượt quá 50 ký tự';
    }
    return null;
  }

  static String? validateType(String? type) {
    if (type == null || (type != 'income' && type != 'expense')) {
      return 'Loại danh mục không hợp lệ';
    }
    return null;
  }

  static bool canDelete(Category category, int transactionCount) {
    return transactionCount == 0;
  }

  static bool canEdit(Category category, String currentUserId) {
    return category.createdBy == currentUserId || category.isShared;
  }

  static bool canArchive(Category category) {
    return !category.isArchived;
  }
}

// Category statistics model
class CategoryStatistics {
  final String categoryId;
  final String categoryName;
  final double totalAmount;
  final int transactionCount;
  final double averageAmount;
  final DateTime firstTransaction;
  final DateTime lastTransaction;
  final Map<String, double> monthlyTrends;

  CategoryStatistics({
    required this.categoryId,
    required this.categoryName,
    required this.totalAmount,
    required this.transactionCount,
    required this.averageAmount,
    required this.firstTransaction,
    required this.lastTransaction,
    required this.monthlyTrends,
  });

  double get averageMonthlyAmount => monthlyTrends.values.isNotEmpty
      ? monthlyTrends.values.reduce((a, b) => a + b) / monthlyTrends.length
      : 0;
}

// Category usage model for smart suggestions
class CategoryUsage {
  final String categoryId;
  final String categoryName;
  final int usageCount;
  final DateTime lastUsed;
  final double averageAmount;
  final List<String> commonDescriptions;

  CategoryUsage({
    required this.categoryId,
    required this.categoryName,
    required this.usageCount,
    required this.lastUsed,
    required this.averageAmount,
    required this.commonDescriptions,
  });
}
