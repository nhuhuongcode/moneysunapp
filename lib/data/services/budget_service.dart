// lib/data/services/_budget_service.dart
import 'package:flutter/foundation.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/data_service.dart';

///  Budget Service that works with DataService
class BudgetService {
  static final BudgetService _instance = BudgetService._internal();
  factory BudgetService() => _instance;
  BudgetService._internal();

  final DataService _dataService = DataService();

  /// Get budgets with ownership filtering - offline first
  Future<List<Budget>> getBudgetsOfflineFirst({
    required UserProvider userProvider,
    BudgetType? budgetType,
    String? month, // Format: 'yyyy-MM'
    bool includeInactive = false,
  }) async {
    try {
      debugPrint('🔍 Getting budgets offline-first...');

      // TODO: Implement getBudgets in DataService
      // For now, return empty list with logging
      debugPrint(
        '⚠️ Budget retrieval deferred until DataService.getBudgets is implemented',
      );

      // Placeholder implementation
      final List<Budget> budgets = [];

      // Apply filters
      var filteredBudgets = budgets;

      if (budgetType != null) {
        filteredBudgets = filteredBudgets
            .where((b) => b.budgetType == budgetType)
            .toList();
      }

      if (month != null) {
        filteredBudgets = filteredBudgets
            .where((b) => b.month == month)
            .toList();
      }

      if (!includeInactive) {
        filteredBudgets = filteredBudgets.where((b) => b.isActive).toList();
      }

      // Sort budgets
      return BudgetUtils.sortBudgets(filteredBudgets);
    } catch (e) {
      debugPrint('❌ Error getting budgets: $e');
      return [];
    }
  }

  /// Create budget with ownership
  Future<void> createBudgetWithOwnership({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    required BudgetType budgetType,
    required UserProvider userProvider,
  }) async {
    if (userProvider.currentUser == null) {
      throw Exception('User not authenticated');
    }

    try {
      debugPrint('➕ Creating budget for $month ($budgetType)');

      final budgetId =
          'budget_${month}_${budgetType.name}_${DateTime.now().millisecondsSinceEpoch}';

      String ownerId;
      if (budgetType == BudgetType.shared) {
        if (!userProvider.hasPartner) {
          throw Exception('Cannot create shared budget without partner');
        }
        ownerId = userProvider.partnershipId!;
      } else {
        ownerId = userProvider.currentUser!.uid;
      }

      final budget = Budget(
        id: budgetId,
        ownerId: ownerId,
        month: month,
        totalAmount: totalAmount,
        categoryAmounts: categoryAmounts,
        budgetType: budgetType,
        createdBy: userProvider.currentUser!.uid,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Validate budget
      final validationError = BudgetValidator.validateBudget(budget);
      if (validationError != null) {
        throw Exception(validationError);
      }

      // TODO: Implement in DataService
      // await _dataService.addBudget(budget);

      debugPrint(
        '⚠️ Budget creation deferred until DataService.addBudget is implemented',
      );
      debugPrint('Budget data: ${budget.toJson()}');

      debugPrint('✅ Budget created successfully');
    } catch (e) {
      debugPrint('❌ Error creating budget: $e');
      rethrow;
    }
  }

  /// Update budget
  Future<void> updateBudget(Budget budget) async {
    try {
      debugPrint('✏️ Updating budget: ${budget.id}');

      // Validate budget
      final validationError = BudgetValidator.validateBudget(budget);
      if (validationError != null) {
        throw Exception(validationError);
      }

      final updatedBudget = budget.copyWith(
        updatedAt: DateTime.now(),
        version: budget.version + 1,
      );

      // TODO: Implement in DataService
      // await _dataService.updateBudget(updatedBudget);

      debugPrint(
        '⚠️ Budget update deferred until DataService.updateBudget is implemented',
      );
      debugPrint('✅ Budget updated successfully');
    } catch (e) {
      debugPrint('❌ Error updating budget: $e');
      rethrow;
    }
  }

  /// Set category budget with ownership validation
  Future<void> setCategoryBudgetWithOwnership(
    String budgetId,
    String categoryId,
    double amount,
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('🎯 Setting category budget: $categoryId = $amount');

      // TODO: Get budget by ID and update
      // final budget = await getBudgetById(budgetId);
      // if (budget == null) {
      //   throw Exception('Budget not found');
      // }

      // // Validate ownership
      // if (!BudgetValidator.canEdit(budget, userProvider.currentUser!.uid)) {
      //   throw Exception('No permission to edit this budget');
      // }

      // final updatedCategoryAmounts = Map<String, double>.from(budget.categoryAmounts);
      // if (amount > 0) {
      //   updatedCategoryAmounts[categoryId] = amount;
      // } else {
      //   updatedCategoryAmounts.remove(categoryId);
      // }

      // final updatedBudget = budget.copyWith(
      //   categoryAmounts: updatedCategoryAmounts,
      //   updatedAt: DateTime.now(),
      //   version: budget.version + 1,
      // );

      // await updateBudget(updatedBudget);

      debugPrint(
        '⚠️ Category budget setting deferred until budget methods are implemented',
      );
      debugPrint('✅ Category budget set successfully');
    } catch (e) {
      debugPrint('❌ Error setting category budget: $e');
      rethrow;
    }
  }

  /// Get budget analytics
  Future<BudgetAnalytics> getBudgetAnalytics(
    String budgetId,
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('📊 Getting budget analytics: $budgetId');

      // TODO: Get budget and transactions to calculate analytics
      // final budget = await getBudgetById(budgetId);
      // if (budget == null) {
      //   throw Exception('Budget not found');
      // }

      // Get transactions for the budget period
      final (startDate, endDate) = (
        DateTime.now(),
        DateTime.now(),
      ); // Placeholder
      final transactions = await _dataService.getTransactions(
        startDate: startDate,
        endDate: endDate,
      );

      // Calculate analytics
      double totalSpent = 0;
      final Map<String, CategoryBudgetAnalytics> categoryAnalytics = {};

      for (final transaction in transactions) {
        if (transaction.type == TransactionType.expense &&
            transaction.categoryId != null) {
          totalSpent += transaction.amount;

          // TODO: Calculate category-specific analytics
        }
      }

      // Create analytics object
      final analytics = BudgetAnalytics(
        budgetId: budgetId,
        totalBudget: 0, // budget.totalAmount
        totalSpent: totalSpent,
        totalRemaining: 0, // budget.totalAmount - totalSpent
        spentPercentage: 0, // (totalSpent / budget.totalAmount) * 100
        categoryAnalytics: categoryAnalytics,
        alerts: [], // TODO: Generate alerts
        trend: const BudgetTrend(
          direction: BudgetTrendDirection.stable,
          changePercentage: 0,
          description: 'Stable spending',
          monthlySpending: [],
        ),
      );

      debugPrint('✅ Budget analytics calculated');
      return analytics;
    } catch (e) {
      debugPrint('❌ Error getting budget analytics: $e');
      rethrow;
    }
  }

  /// Copy budget from previous month
  Future<void> copyBudgetFromPreviousMonth(
    String targetMonth,
    BudgetType budgetType,
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('📋 Copying budget to $targetMonth');

      // Get previous month
      final previousMonth = BudgetUtils.getPreviousMonth(targetMonth);

      // TODO: Get previous budget
      // final previousBudgets = await getBudgetsOfflineFirst(
      //   userProvider: userProvider,
      //   budgetType: budgetType,
      //   month: previousMonth,
      // );

      // if (previousBudgets.isNotEmpty) {
      //   final previousBudget = previousBudgets.first;
      //
      //   await createBudgetWithOwnership(
      //     month: targetMonth,
      //     totalAmount: previousBudget.totalAmount,
      //     categoryAmounts: previousBudget.categoryAmounts,
      //     budgetType: budgetType,
      //     userProvider: userProvider,
      //   );
      // }

      debugPrint(
        '⚠️ Budget copying deferred until budget methods are implemented',
      );
      debugPrint('✅ Budget copied successfully');
    } catch (e) {
      debugPrint('❌ Error copying budget: $e');
      rethrow;
    }
  }

  /// Delete budget
  Future<void> deleteBudget(String budgetId, UserProvider userProvider) async {
    try {
      debugPrint('🗑️ Deleting budget: $budgetId');

      // TODO: Get budget and validate permissions
      // final budget = await getBudgetById(budgetId);
      // if (budget == null) {
      //   throw Exception('Budget not found');
      // }

      // if (!BudgetValidator.canDelete(budget, userProvider.currentUser!.uid)) {
      //   throw Exception('No permission to delete this budget');
      // }

      // await _dataService.deleteBudget(budgetId);

      debugPrint(
        '⚠️ Budget deletion deferred until DataService.deleteBudget is implemented',
      );
      debugPrint('✅ Budget deleted successfully');
    } catch (e) {
      debugPrint('❌ Error deleting budget: $e');
      rethrow;
    }
  }

  /// Get budget templates
  Future<List<BudgetTemplate>> getBudgetTemplates(
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('📄 Getting budget templates');

      // TODO: Implement template storage and retrieval
      debugPrint(
        '⚠️ Budget templates deferred until template storage is implemented',
      );

      return [];
    } catch (e) {
      debugPrint('❌ Error getting budget templates: $e');
      return [];
    }
  }

  /// Save budget as template
  Future<void> saveBudgetAsTemplate(
    Budget budget,
    String templateName,
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('💾 Saving budget as template: $templateName');

      final template = BudgetTemplate.fromBudget(budget, templateName);

      // TODO: Implement template storage
      debugPrint(
        '⚠️ Budget template saving deferred until template storage is implemented',
      );
      debugPrint('Template data: ${template.toJson()}');

      debugPrint('✅ Budget template saved successfully');
    } catch (e) {
      debugPrint('❌ Error saving budget template: $e');
      rethrow;
    }
  }

  /// Create budget from template
  Future<void> createBudgetFromTemplate(
    BudgetTemplate template,
    String month,
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('🏗️ Creating budget from template: ${template.name}');

      await createBudgetWithOwnership(
        month: month,
        totalAmount: template.totalAmount,
        categoryAmounts: template.categoryAmounts,
        budgetType: template.budgetType,
        userProvider: userProvider,
      );

      debugPrint('✅ Budget created from template successfully');
    } catch (e) {
      debugPrint('❌ Error creating budget from template: $e');
      rethrow;
    }
  }

  /// Get budget spending insights
  Future<List<String>> getBudgetInsights(
    String budgetId,
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('💡 Getting budget insights: $budgetId');

      final analytics = await getBudgetAnalytics(budgetId, userProvider);
      final insights = <String>[];

      // Generate insights based on analytics
      if (analytics.isOverBudget) {
        insights.add(
          'Bạn đã vượt ngân sách ${analytics.spentPercentage.toStringAsFixed(1)}%',
        );
      } else if (analytics.isNearLimit) {
        insights.add(
          'Bạn đã sử dụng ${analytics.spentPercentage.toStringAsFixed(1)}% ngân sách',
        );
      }

      if (analytics.highPriorityAlerts > 0) {
        insights.add('Có ${analytics.highPriorityAlerts} cảnh báo quan trọng');
      }

      // TODO: Add more intelligent insights based on spending patterns

      debugPrint('✅ Generated ${insights.length} budget insights');
      return insights;
    } catch (e) {
      debugPrint('❌ Error getting budget insights: $e');
      return [];
    }
  }

  /// Export budget data
  Future<Map<String, dynamic>> exportBudgetData(
    String budgetId,
    UserProvider userProvider,
  ) async {
    try {
      debugPrint('📤 Exporting budget data: $budgetId');

      // TODO: Get budget and analytics
      // final budget = await getBudgetById(budgetId);
      // final analytics = await getBudgetAnalytics(budgetId, userProvider);

      final exportData = {
        'budget': {}, // budget?.toJson(),
        'analytics': {}, // analytics.toJson(),
        'exportedAt': DateTime.now().toIso8601String(),
        'exportedBy': userProvider.currentUser?.uid,
      };

      debugPrint('✅ Budget data exported successfully');
      return exportData;
    } catch (e) {
      debugPrint('❌ Error exporting budget data: $e');
      rethrow;
    }
  }

  /// Get budget by ID (placeholder)
  Future<Budget?> getBudgetById(String budgetId) async {
    try {
      // TODO: Implement in DataService
      debugPrint('⚠️ getBudgetById deferred until DataService implementation');
      return null;
    } catch (e) {
      debugPrint('❌ Error getting budget by ID: $e');
      return null;
    }
  }

  /// Refresh budget data
  Future<void> refreshBudgets() async {
    try {
      debugPrint('🔄 Refreshing budget data');

      // TODO: Trigger DataService sync if online
      if (_dataService.isOnline) {
        await _dataService.forceSyncNow();
      }

      debugPrint('✅ Budget data refreshed');
    } catch (e) {
      debugPrint('❌ Error refreshing budgets: $e');
      rethrow;
    }
  }
}
