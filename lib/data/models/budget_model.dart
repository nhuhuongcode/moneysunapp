// lib/data/models/budget_model.dart - Enhanced with shared budget support

import 'package:firebase_database/firebase_database.dart';

enum BudgetType { personal, shared }

enum BudgetPeriod { monthly, yearly, custom }

class Budget {
  final String id;
  final String ownerId; // For personal: userId, For shared: partnershipId
  final String month; // Format: yyyy-MM
  final double totalAmount;
  final Map<String, double> categoryAmounts; // categoryId -> amount
  final BudgetType budgetType;
  final BudgetPeriod period;
  final String? createdBy; // Who created this budget
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startDate; // For custom period
  final DateTime? endDate; // For custom period
  final bool isActive;
  final Map<String, String>? notes; // categoryId -> note
  final Map<String, double>? categoryLimits; // categoryId -> warning limit (%)

  Budget({
    required this.id,
    required this.ownerId,
    required this.month,
    required this.totalAmount,
    required this.categoryAmounts,
    this.budgetType = BudgetType.personal,
    this.period = BudgetPeriod.monthly,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.startDate,
    this.endDate,
    this.isActive = true,
    this.notes,
    this.categoryLimits,
  });

  factory Budget.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    final sourceCategoryMap = data['categoryAmounts'] as Map? ?? {};
    final sourceNotesMap = data['notes'] as Map? ?? {};
    final sourceLimitsMap = data['categoryLimits'] as Map? ?? {};

    final Map<String, double> targetCategoryMap = sourceCategoryMap.map(
      (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
    );

    final Map<String, String> targetNotesMap = sourceNotesMap.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );

    final Map<String, double> targetLimitsMap = sourceLimitsMap.map(
      (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
    );

    return Budget(
      id: snapshot.key!,
      ownerId: data['ownerId'] ?? '',
      month: data['month'] ?? '',
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      categoryAmounts: targetCategoryMap,
      budgetType: BudgetType.values.firstWhere(
        (e) => e.name == data['budgetType'],
        orElse: () => BudgetType.personal,
      ),
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == data['period'],
        orElse: () => BudgetPeriod.monthly,
      ),
      createdBy: data['createdBy'],
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : null,
      updatedAt: data['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['updatedAt'])
          : null,
      startDate: data['startDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['startDate'])
          : null,
      endDate: data['endDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['endDate'])
          : null,
      isActive: data['isActive'] ?? true,
      notes: targetNotesMap.isNotEmpty ? targetNotesMap : null,
      categoryLimits: targetLimitsMap.isNotEmpty ? targetLimitsMap : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'month': month,
      'totalAmount': totalAmount,
      'categoryAmounts': categoryAmounts,
      'budgetType': budgetType.name,
      'period': period.name,
      'createdBy': createdBy,
      'createdAt': createdAt?.millisecondsSinceEpoch ?? ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      'startDate': startDate?.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'isActive': isActive,
      'notes': notes,
      'categoryLimits': categoryLimits,
    };
  }

  // Helper methods
  bool get isShared => budgetType == BudgetType.shared;
  bool get isPersonal => budgetType == BudgetType.personal;
  bool get isMonthly => period == BudgetPeriod.monthly;
  bool get isCustomPeriod => period == BudgetPeriod.custom;

  String get displayName {
    String suffix = '';
    if (isShared) {
      suffix = ' (Chung)';
    }
    return 'Ngân sách $month$suffix';
  }

  // Get effective date range
  (DateTime start, DateTime end) get effectiveDateRange {
    if (isCustomPeriod && startDate != null && endDate != null) {
      return (startDate!, endDate!);
    }

    // Default to monthly
    final monthDate = DateTime.parse('$month-01');
    final start = DateTime(monthDate.year, monthDate.month, 1);
    final end = DateTime(monthDate.year, monthDate.month + 1, 0);
    return (start, end);
  }

  // Calculate remaining amount for a category
  double getCategoryRemaining(String categoryId, double spent) {
    final budgetAmount = categoryAmounts[categoryId] ?? 0;
    return budgetAmount - spent;
  }

  // Get category spending percentage
  double getCategoryPercentage(String categoryId, double spent) {
    final budgetAmount = categoryAmounts[categoryId] ?? 0;
    if (budgetAmount <= 0) return 0;
    return (spent / budgetAmount * 100).clamp(0, double.infinity);
  }

  // Check if category is over budget
  bool isCategoryOverBudget(String categoryId, double spent) {
    final budgetAmount = categoryAmounts[categoryId] ?? 0;
    return spent > budgetAmount;
  }

  // Get warning threshold for category (default 80%)
  double getCategoryWarningThreshold(String categoryId) {
    final limit = categoryLimits?[categoryId] ?? 80.0;
    final budgetAmount = categoryAmounts[categoryId] ?? 0;
    return budgetAmount * (limit / 100);
  }

  // Check if category spending is near limit
  bool isCategoryNearLimit(String categoryId, double spent) {
    final threshold = getCategoryWarningThreshold(categoryId);
    return spent >= threshold;
  }

  // Copy with method
  Budget copyWith({
    String? id,
    String? ownerId,
    String? month,
    double? totalAmount,
    Map<String, double>? categoryAmounts,
    BudgetType? budgetType,
    BudgetPeriod? period,
    String? createdBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
    Map<String, String>? notes,
    Map<String, double>? categoryLimits,
  }) {
    return Budget(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      month: month ?? this.month,
      totalAmount: totalAmount ?? this.totalAmount,
      categoryAmounts: categoryAmounts ?? this.categoryAmounts,
      budgetType: budgetType ?? this.budgetType,
      period: period ?? this.period,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isActive: isActive ?? this.isActive,
      notes: notes ?? this.notes,
      categoryLimits: categoryLimits ?? this.categoryLimits,
    );
  }

  @override
  String toString() {
    return 'Budget(id: $id, ownerId: $ownerId, month: $month, budgetType: $budgetType, totalAmount: $totalAmount)';
  }
}

// Budget analytics model
class BudgetAnalytics {
  final String budgetId;
  final double totalBudget;
  final double totalSpent;
  final double totalRemaining;
  final double spentPercentage;
  final Map<String, CategoryBudgetAnalytics> categoryAnalytics;
  final List<BudgetAlert> alerts;
  final BudgetTrend trend;

  BudgetAnalytics({
    required this.budgetId,
    required this.totalBudget,
    required this.totalSpent,
    required this.totalRemaining,
    required this.spentPercentage,
    required this.categoryAnalytics,
    required this.alerts,
    required this.trend,
  });

  bool get isOverBudget => spentPercentage > 100;
  bool get isNearLimit => spentPercentage >= 80;
  bool get isOnTrack => spentPercentage <= 80;
}

class CategoryBudgetAnalytics {
  final String categoryId;
  final String categoryName;
  final double budgetAmount;
  final double spentAmount;
  final double remainingAmount;
  final double spentPercentage;
  final bool isOverBudget;
  final bool isNearLimit;
  final List<double> dailySpending;

  CategoryBudgetAnalytics({
    required this.categoryId,
    required this.categoryName,
    required this.budgetAmount,
    required this.spentAmount,
    required this.remainingAmount,
    required this.spentPercentage,
    required this.isOverBudget,
    required this.isNearLimit,
    required this.dailySpending,
  });
}

enum BudgetAlertType { overBudget, nearLimit, unusualSpending }

class BudgetAlert {
  final BudgetAlertType type;
  final String categoryId;
  final String categoryName;
  final String message;
  final double amount;
  final DateTime timestamp;
  final bool isRead;

  BudgetAlert({
    required this.type,
    required this.categoryId,
    required this.categoryName,
    required this.message,
    required this.amount,
    required this.timestamp,
    this.isRead = false,
  });
}

enum BudgetTrendDirection { improving, stable, declining }

class BudgetTrend {
  final BudgetTrendDirection direction;
  final double changePercentage;
  final String description;
  final List<double> monthlySpending;

  BudgetTrend({
    required this.direction,
    required this.changePercentage,
    required this.description,
    required this.monthlySpending,
  });
}
