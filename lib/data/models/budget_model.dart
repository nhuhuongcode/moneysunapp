// lib/data/models/enhanced_budget_model.dart
import 'package:firebase_database/firebase_database.dart';

enum BudgetType { personal, shared }

enum BudgetPeriod { weekly, monthly, quarterly, yearly, custom }

enum BudgetAlertType { nearLimit, overBudget, weeklyReminder, monthlyReport }

enum BudgetTrendDirection { increasing, decreasing, stable }

class Budget {
  final String id;
  final String ownerId; // userId for personal, partnershipId for shared
  final String month; // Format: 'yyyy-MM'
  final double totalAmount;
  final Map<String, double> categoryAmounts;
  final BudgetType budgetType;
  final BudgetPeriod period;
  final String? createdBy; // Always the actual user who created it
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? startDate; // For custom periods
  final DateTime? endDate; // For custom periods
  final bool isActive;
  final Map<String, String>? notes; // Category-specific notes
  final Map<String, double>? categoryLimits; // Warning limits per category
  final int version; // For conflict resolution
  final bool isDeleted; // Soft delete

  const Budget({
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
    this.version = 1,
    this.isDeleted = false,
  });

  // Computed properties
  bool get isShared => budgetType == BudgetType.shared;
  bool get hasCategories => categoryAmounts.isNotEmpty;

  String get displayName {
    final typeStr = isShared ? 'Chung' : 'Cá nhân';
    return 'Ngân sách $typeStr - $month';
  }

  (DateTime, DateTime) get effectiveDateRange {
    if (startDate != null && endDate != null) {
      return (startDate!, endDate!);
    }

    final date = DateTime.parse('$month-01');
    final start = DateTime(date.year, date.month, 1);
    final end = DateTime(date.year, date.month + 1, 0);
    return (start, end);
  }

  double get usedAmount {
    return categoryAmounts.values.fold(0.0, (sum, amount) => sum + amount);
  }

  double get remainingAmount => totalAmount - usedAmount;
  double get usagePercentage =>
      totalAmount > 0 ? (usedAmount / totalAmount * 100) : 0.0;

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
    int? version,
    bool? isDeleted,
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
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerId': ownerId,
      'month': month,
      'totalAmount': totalAmount,
      'categoryAmounts': categoryAmounts,
      'budgetType': budgetType.name,
      'period': period.name,
      'createdBy': createdBy,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'updatedAt': updatedAt?.millisecondsSinceEpoch,
      'startDate': startDate?.millisecondsSinceEpoch,
      'endDate': endDate?.millisecondsSinceEpoch,
      'isActive': isActive,
      'notes': notes,
      'categoryLimits': categoryLimits,
      'version': version,
      'isDeleted': isDeleted,
    };
  }

  factory Budget.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    return Budget.fromMap(data, snapshot.key!);
  }

  factory Budget.fromMap(Map<dynamic, dynamic> data, String id) {
    return Budget(
      id: id,
      ownerId: data['ownerId'] ?? '',
      month: data['month'] ?? '',
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      categoryAmounts: Map<String, double>.from(data['categoryAmounts'] ?? {}),
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
      notes: data['notes'] != null
          ? Map<String, String>.from(data['notes'])
          : null,
      categoryLimits: data['categoryLimits'] != null
          ? Map<String, double>.from(data['categoryLimits'])
          : null,
      version: data['version'] ?? 1,
      isDeleted: data['isDeleted'] ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Budget &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          version == other.version;

  @override
  int get hashCode => id.hashCode ^ version.hashCode;

  @override
  String toString() {
    return 'Budget{id: $id, ownerId: $ownerId, month: $month, type: $budgetType, total: $totalAmount, version: $version}';
  }
}

// Budget Analytics Classes
class BudgetAnalytics {
  final String budgetId;
  final double totalBudget;
  final double totalSpent;
  final double totalRemaining;
  final double spentPercentage;
  final Map<String, CategoryBudgetAnalytics> categoryAnalytics;
  final List<BudgetAlert> alerts;
  final BudgetTrend trend;

  const BudgetAnalytics({
    required this.budgetId,
    required this.totalBudget,
    required this.totalSpent,
    required this.totalRemaining,
    required this.spentPercentage,
    required this.categoryAnalytics,
    required this.alerts,
    required this.trend,
  });

  bool get isOverBudget => totalSpent > totalBudget;
  bool get isNearLimit => spentPercentage >= 80;
  int get highPriorityAlerts => alerts.where((a) => a.isHighPriority).length;
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
  final List<double> dailySpending; // For trend analysis

  const CategoryBudgetAnalytics({
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

class BudgetAlert {
  final BudgetAlertType type;
  final String categoryId;
  final String categoryName;
  final String message;
  final double amount;
  final DateTime timestamp;
  final bool isRead;

  const BudgetAlert({
    required this.type,
    required this.categoryId,
    required this.categoryName,
    required this.message,
    required this.amount,
    required this.timestamp,
    this.isRead = false,
  });

  bool get isHighPriority => type == BudgetAlertType.overBudget;
}

class BudgetTrend {
  final BudgetTrendDirection direction;
  final double changePercentage;
  final String description;
  final List<double> monthlySpending; // Historical data

  const BudgetTrend({
    required this.direction,
    required this.changePercentage,
    required this.description,
    required this.monthlySpending,
  });
}

// Budget Template for reusing budgets
class BudgetTemplate {
  final String id;
  final String name;
  final String createdBy;
  final Map<String, double> categoryAmounts;
  final double totalAmount;
  final DateTime createdAt;
  final BudgetType budgetType;

  const BudgetTemplate({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.categoryAmounts,
    required this.totalAmount,
    required this.createdAt,
    required this.budgetType,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdBy': createdBy,
      'categoryAmounts': categoryAmounts,
      'totalAmount': totalAmount,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'budgetType': budgetType.name,
    };
  }

  factory BudgetTemplate.fromBudget(Budget budget, String templateName) {
    return BudgetTemplate(
      id: 'template_${DateTime.now().millisecondsSinceEpoch}',
      name: templateName,
      createdBy: budget.createdBy ?? '',
      categoryAmounts: budget.categoryAmounts,
      totalAmount: budget.totalAmount,
      createdAt: DateTime.now(),
      budgetType: budget.budgetType,
    );
  }
}

// Budget Validator
class BudgetValidator {
  static bool canEdit(Budget budget, String currentUserId) {
    // Personal budgets: only creator can edit
    if (budget.budgetType == BudgetType.personal) {
      return budget.ownerId == currentUserId;
    }

    // Shared budgets: both partners can edit
    return budget.createdBy == currentUserId || budget.isShared;
  }

  static bool canDelete(Budget budget, String currentUserId) {
    // Only creator can delete
    return budget.createdBy == currentUserId;
  }

  static bool isValidAmount(double amount) {
    return amount >= 0 && amount <= 999999999999; // Max 999 billion
  }

  static bool isValidMonth(String month) {
    try {
      DateTime.parse('$month-01');
      return true;
    } catch (e) {
      return false;
    }
  }

  static String? validateBudget(Budget budget) {
    if (budget.ownerId.isEmpty) return 'Owner ID không được trống';
    if (budget.month.isEmpty) return 'Tháng không được trống';
    if (!isValidMonth(budget.month)) return 'Tháng không hợp lệ';
    if (!isValidAmount(budget.totalAmount)) return 'Số tiền không hợp lệ';

    // Validate category amounts
    for (final amount in budget.categoryAmounts.values) {
      if (!isValidAmount(amount)) return 'Số tiền danh mục không hợp lệ';
    }

    return null; // Valid
  }
}

// Budget Helper Functions
class BudgetUtils {
  static String formatMonth(String month) {
    try {
      final date = DateTime.parse('$month-01');
      return 'Tháng ${date.month}/${date.year}';
    } catch (e) {
      return month;
    }
  }

  static String getNextMonth(String currentMonth) {
    try {
      final date = DateTime.parse('$currentMonth-01');
      final nextMonth = DateTime(date.year, date.month + 1, 1);
      return '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}';
    } catch (e) {
      return currentMonth;
    }
  }

  static String getPreviousMonth(String currentMonth) {
    try {
      final date = DateTime.parse('$currentMonth-01');
      final prevMonth = DateTime(date.year, date.month - 1, 1);
      return '${prevMonth.year}-${prevMonth.month.toString().padLeft(2, '0')}';
    } catch (e) {
      return currentMonth;
    }
  }

  static double calculateDailyBudget(Budget budget) {
    final (startDate, endDate) = budget.effectiveDateRange;
    final days = endDate.difference(startDate).inDays + 1;
    return budget.totalAmount / days;
  }

  static List<Budget> sortBudgets(List<Budget> budgets) {
    return budgets..sort((a, b) {
      // Sort by month (newest first), then by type (shared first)
      final monthComparison = b.month.compareTo(a.month);
      if (monthComparison != 0) return monthComparison;

      if (a.isShared && !b.isShared) return -1;
      if (!a.isShared && b.isShared) return 1;
      return 0;
    });
  }

  static Map<String, List<Budget>> groupBudgetsByMonth(List<Budget> budgets) {
    final grouped = <String, List<Budget>>{};
    for (final budget in budgets) {
      grouped.putIfAbsent(budget.month, () => []).add(budget);
    }
    return grouped;
  }
}
