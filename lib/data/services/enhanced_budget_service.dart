// lib/data/services/enhanced_budget_service.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:moneysun/data/models/budget_model.dart';
import 'package:moneysun/data/models/category_model.dart';
import 'package:moneysun/data/models/transaction_model.dart';
import 'package:moneysun/data/providers/user_provider.dart';
import 'package:moneysun/data/services/local_database_service.dart';
import 'package:moneysun/data/services/offline_sync_service.dart';
import 'package:moneysun/data/services/enhanced_category_service.dart';

class EnhancedBudgetService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final OfflineSyncService _offlineSync = OfflineSyncService();
  final EnhancedCategoryService _categoryService = EnhancedCategoryService();
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  // ============ BUDGET MANAGEMENT WITH OWNERSHIP ============

  /// Get budgets with ownership filtering (personal + shared)
  Stream<List<Budget>> getBudgetsWithOwnershipStream(
    UserProvider userProvider, {
    String? month,
    BudgetType? budgetType,
  }) async* {
    if (_uid == null) {
      yield [];
      return;
    }

    // Try offline first
    try {
      final localBudgets = await _localDb.getBudgetsByOwnership(
        _uid!,
        userProvider.partnershipId,
        month ?? '',
      );

      if (localBudgets.isNotEmpty) {
        yield _filterBudgetsByOwnership(localBudgets, userProvider, budgetType);
      }
    } catch (e) {
      print('Error getting local budgets: $e');
    }

    // Firebase stream
    yield* _dbRef
        .child('budgets')
        .onValue
        .map((event) {
          final List<Budget> budgets = [];

          if (event.snapshot.exists) {
            final allBudgetsMap = event.snapshot.value as Map<dynamic, dynamic>;

            allBudgetsMap.forEach((key, value) {
              final budgetSnapshot = event.snapshot.child(key);
              final budget = Budget.fromSnapshot(budgetSnapshot);

              if (_shouldIncludeBudget(
                budget,
                userProvider,
                month,
                budgetType,
              )) {
                budgets.add(budget);
              }
            });
          }

          return budgets..sort((a, b) => b.month.compareTo(a.month));
        })
        .handleError((error) {
          print('Firebase budget stream error: $error');
          return <Budget>[];
        });
  }

  /// Check if budget should be included based on ownership
  bool _shouldIncludeBudget(
    Budget budget,
    UserProvider userProvider,
    String? month,
    BudgetType? budgetType,
  ) {
    // Filter by month if specified
    if (month != null && budget.month != month) return false;

    // Filter by budget type if specified
    if (budgetType != null && budget.budgetType != budgetType) return false;

    // Filter by active status
    if (!budget.isActive) return false;

    // Include personal budgets
    if (budget.ownerId == _uid) return true;

    // Include shared budgets if user has partnership
    if (userProvider.partnershipId != null &&
        budget.ownerId == userProvider.partnershipId) {
      return true;
    }

    return false;
  }

  /// Filter budgets by ownership for offline data
  List<Budget> _filterBudgetsByOwnership(
    List<Budget> budgets,
    UserProvider userProvider,
    BudgetType? budgetType,
  ) {
    return budgets.where((budget) {
      return _shouldIncludeBudget(budget, userProvider, null, budgetType);
    }).toList();
  }

  // ============ CREATE BUDGETS WITH OWNERSHIP ============

  /// Create budget with ownership type selection
  Future<void> createBudgetWithOwnership({
    required String month,
    required double totalAmount,
    required Map<String, double> categoryAmounts,
    required BudgetType budgetType,
    required UserProvider userProvider,
    BudgetPeriod period = BudgetPeriod.monthly,
    DateTime? startDate,
    DateTime? endDate,
    Map<String, String>? notes,
    Map<String, double>? categoryLimits,
  }) async {
    if (_uid == null) throw Exception('User not authenticated');

    try {
      // Determine ownerId based on budget type
      String ownerId;
      if (budgetType == BudgetType.shared) {
        if (userProvider.partnershipId == null) {
          throw Exception('Không thể tạo ngân sách chung khi chưa có đối tác');
        }
        ownerId = userProvider.partnershipId!;
      } else {
        ownerId = _uid!;
      }

      // Create budget
      final budgetRef = _dbRef.child('budgets').push();
      final budget = Budget(
        id: budgetRef.key!,
        ownerId: ownerId,
        month: month,
        totalAmount: totalAmount,
        categoryAmounts: categoryAmounts,
        budgetType: budgetType,
        period: period,
        createdBy: _uid,
        startDate: startDate,
        endDate: endDate,
        notes: notes,
        categoryLimits: categoryLimits,
        createdAt: DateTime.now(),
      );

      // Save offline first
      await _localDb.saveBudgetLocally(budget, syncStatus: 0);

      // Try to sync online
      if (_offlineSync.isOnline) {
        try {
          await budgetRef.set(budget.toJson());
          await _localDb.markAsSynced('budgets', budget.id);

          // Send notification if shared budget
          if (budgetType == BudgetType.shared &&
              userProvider.partnerUid != null) {
            await _sendBudgetNotification(
              userProvider.partnerUid!,
              'Ngân sách chung mới',
              '${userProvider.currentUser?.displayName ?? "Đối tác"} đã tạo ngân sách chung cho tháng $month',
            );
          }
        } catch (e) {
          print('Failed to sync budget immediately: $e');
          // Will be synced later by offline sync service
        }
      }

      print('✅ Budget created: $month (${budgetType.name})');
    } catch (e) {
      print('❌ Error creating budget: $e');
      rethrow;
    }
  }

  // ============ BUDGET ACTIONS ============

  /// Update budget
  Future<void> updateBudget(Budget budget) async {
    if (_uid == null) return;

    try {
      // Check permissions
      if (!_canEditBudget(budget, _uid!)) {
        throw Exception('Bạn không có quyền chỉnh sửa ngân sách này');
      }

      // Update locally first
      await _localDb.updateBudgetLocally(budget);

      // Try to sync online
      if (_offlineSync.isOnline) {
        try {
          await _dbRef.child('budgets').child(budget.id).update({
            'totalAmount': budget.totalAmount,
            'categoryAmounts': budget.categoryAmounts,
            'notes': budget.notes,
            'categoryLimits': budget.categoryLimits,
            'updatedAt': ServerValue.timestamp,
          });
          await _localDb.markAsSynced('budgets', budget.id);
        } catch (e) {
          print('Failed to sync budget update: $e');
        }
      }

      print('✅ Budget updated: ${budget.displayName}');
    } catch (e) {
      print('❌ Error updating budget: $e');
      rethrow;
    }
  }

  /// Delete budget with safety checks
  Future<void> deleteBudget(String budgetId) async {
    if (_uid == null) return;

    try {
      // Delete locally first
      await _localDb.deleteBudgetLocally(budgetId);

      // Try to sync online
      if (_offlineSync.isOnline) {
        try {
          await _dbRef.child('budgets').child(budgetId).remove();
        } catch (e) {
          print('Failed to sync budget deletion: $e');
        }
      }

      print('✅ Budget deleted');
    } catch (e) {
      print('❌ Error deleting budget: $e');
      rethrow;
    }
  }

  /// Set category budget with ownership awareness
  Future<void> setCategoryBudgetWithOwnership(
    String budgetId,
    String categoryId,
    double amount,
    UserProvider userProvider,
  ) async {
    if (_uid == null) return;

    try {
      // Update locally first
      final budgets = await _localDb.getLocalBudgets();
      final budget = budgets.firstWhere(
        (b) => b.id == budgetId,
        orElse: () => throw Exception('Budget not found'),
      );

      final updatedCategoryAmounts = Map<String, double>.from(
        budget.categoryAmounts,
      );
      if (amount > 0) {
        updatedCategoryAmounts[categoryId] = amount;
      } else {
        updatedCategoryAmounts.remove(categoryId);
      }

      final updatedBudget = budget.copyWith(
        categoryAmounts: updatedCategoryAmounts,
        updatedAt: DateTime.now(),
      );

      await updateBudget(updatedBudget);

      print('✅ Category budget updated successfully');
    } catch (e) {
      print('❌ Error updating category budget: $e');
      rethrow;
    }
  }

  // ============ BUDGET ANALYTICS WITH OWNERSHIP ============

  /// Get budget analytics with ownership awareness
  Future<BudgetAnalytics> getBudgetAnalyticsWithOwnership(
    String budgetId,
    UserProvider userProvider,
  ) async {
    try {
      // Get budget data from local first
      final budgets = await _localDb.getLocalBudgets();
      final budget = budgets.firstWhere(
        (b) => b.id == budgetId,
        orElse: () => throw Exception('Budget not found'),
      );

      // Get categories with ownership filtering
      final categories = await _categoryService.getCategoriesOfflineFirst(
        type: 'expense',
        userProvider: userProvider,
      );

      // Calculate spending for each category
      double totalSpent = 0;
      Map<String, CategoryBudgetAnalytics> categoryAnalytics = {};
      List<BudgetAlert> alerts = [];

      for (final entry in budget.categoryAmounts.entries) {
        final categoryId = entry.key;
        final budgetAmount = entry.value;

        // Find category
        final category = categories.firstWhere(
          (c) => c.id == categoryId,
          orElse: () => Category(
            id: categoryId,
            name: 'Unknown Category',
            ownerId: '',
            type: 'expense',
          ),
        );

        // Get actual spending (this would need to be implemented based on transactions)
        final categorySpent = await _getCategorySpending(
          categoryId,
          budget.effectiveDateRange.$1,
          budget.effectiveDateRange.$2,
          userProvider,
        );

        totalSpent += categorySpent;

        final percentage = budgetAmount > 0
            ? (categorySpent / budgetAmount * 100)
            : 0.0;
        final isOverBudget = categorySpent > budgetAmount;
        final isNearLimit = percentage >= 80;

        categoryAnalytics[categoryId] = CategoryBudgetAnalytics(
          categoryId: categoryId,
          categoryName: category.name,
          budgetAmount: budgetAmount,
          spentAmount: categorySpent,
          remainingAmount: budgetAmount - categorySpent,
          spentPercentage: percentage,
          isOverBudget: isOverBudget,
          isNearLimit: isNearLimit,
          dailySpending: [], // TODO: Implement daily spending calculation
        );

        // Generate alerts
        if (isOverBudget) {
          alerts.add(
            BudgetAlert(
              type: BudgetAlertType.overBudget,
              categoryId: categoryId,
              categoryName: category.name,
              message:
                  'Đã vượt ngân sách ${_formatCurrency(budgetAmount - categorySpent)}',
              amount: categorySpent - budgetAmount,
              timestamp: DateTime.now(),
            ),
          );
        } else if (isNearLimit) {
          alerts.add(
            BudgetAlert(
              type: BudgetAlertType.nearLimit,
              categoryId: categoryId,
              categoryName: category.name,
              message:
                  'Sắp đạt giới hạn ngân sách (${percentage.toStringAsFixed(1)}%)',
              amount: categorySpent,
              timestamp: DateTime.now(),
            ),
          );
        }
      }

      final totalPercentage = budget.totalAmount > 0
          ? (totalSpent / budget.totalAmount * 100)
          : 0.0;

      return BudgetAnalytics(
        budgetId: budgetId,
        totalBudget: budget.totalAmount,
        totalSpent: totalSpent,
        totalRemaining: budget.totalAmount - totalSpent,
        spentPercentage: totalPercentage,
        categoryAnalytics: categoryAnalytics,
        alerts: alerts,
        trend: _calculateBudgetTrend([]), // TODO: Implement trend calculation
      );
    } catch (e) {
      print('❌ Error getting budget analytics: $e');
      rethrow;
    }
  }

  // ============ SMART BUDGET FEATURES ============

  /// Get budget recommendations based on historical spending
  Future<Map<String, double>> getBudgetRecommendations(
    String month,
    BudgetType budgetType,
    UserProvider userProvider,
  ) async {
    try {
      // Get historical spending data from local database
      return await _localDb.getBudgetRecommendations(_uid!, month);
    } catch (e) {
      print('❌ Error getting budget recommendations: $e');
      return {};
    }
  }

  /// Copy budget from previous month
  Future<void> copyBudgetFromPreviousMonth(
    String currentMonth,
    BudgetType budgetType,
    UserProvider userProvider,
  ) async {
    try {
      // Find previous month's budget
      final previousMonth = _getPreviousMonth(currentMonth);
      final budgets = await _localDb.getBudgetsByOwnership(
        _uid!,
        userProvider.partnershipId,
        previousMonth,
      );

      final previousBudget = budgets
          .where((b) => b.budgetType == budgetType)
          .firstOrNull;

      if (previousBudget == null) {
        throw Exception('Không tìm thấy ngân sách tháng trước để sao chép');
      }

      // Create new budget with same category amounts
      await createBudgetWithOwnership(
        month: currentMonth,
        totalAmount: previousBudget.totalAmount,
        categoryAmounts: previousBudget.categoryAmounts,
        budgetType: budgetType,
        userProvider: userProvider,
        period: previousBudget.period,
        notes: previousBudget.notes,
        categoryLimits: previousBudget.categoryLimits,
      );

      print('✅ Budget copied from previous month');
    } catch (e) {
      print('❌ Error copying budget: $e');
      rethrow;
    }
  }

  /// Create budget template
  Future<void> createBudgetTemplate(Budget budget, String templateName) async {
    try {
      // Save template to local database
      final template = budget.copyWith(
        id: 'template_${DateTime.now().millisecondsSinceEpoch}',
        month: templateName,
        isActive: false,
      );

      await _localDb.saveBudgetLocally(template, syncStatus: 0);

      print('✅ Budget template created: $templateName');
    } catch (e) {
      print('❌ Error creating budget template: $e');
      rethrow;
    }
  }

  // ============ HELPER METHODS ============

  Future<double> _getCategorySpending(
    String categoryId,
    DateTime startDate,
    DateTime endDate,
    UserProvider userProvider,
  ) async {
    try {
      // Get transactions from local database
      final transactions = await _localDb.getLocalTransactions(
        userId: _uid,
        startDate: startDate,
        endDate: endDate,
      );

      return transactions
          .where(
            (t) =>
                t.categoryId == categoryId && t.type == TransactionType.expense,
          )
          .fold<double>(0.0, (sum, t) => sum + (t.amount ?? 0.0));
    } catch (e) {
      print('Error getting category spending: $e');
      return 0.0;
    }
  }

  bool _canEditBudget(Budget budget, String currentUserId) {
    return budget.createdBy == currentUserId || budget.isShared;
  }

  String _formatCurrency(double amount) {
    return '${amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}₫';
  }

  String _getPreviousMonth(String currentMonth) {
    final date = DateTime.parse('$currentMonth-01');
    final previousDate = DateTime(date.year, date.month - 1, 1);
    return '${previousDate.year}-${previousDate.month.toString().padLeft(2, '0')}';
  }

  BudgetTrend _calculateBudgetTrend(List<double> monthlySpending) {
    // TODO: Implement proper trend calculation
    return BudgetTrend(
      direction: BudgetTrendDirection.stable,
      changePercentage: 0,
      description: 'Xu hướng ổn định',
      monthlySpending: monthlySpending,
    );
  }

  Future<void> _sendBudgetNotification(
    String userId,
    String title,
    String body,
  ) async {
    try {
      await _dbRef.child('user_notifications').child(userId).push().set({
        'title': title,
        'body': body,
        'timestamp': ServerValue.timestamp,
        'type': 'budget',
        'isRead': false,
      });
    } catch (e) {
      print('Error sending budget notification: $e');
    }
  }

  // ============ SYNC MANAGEMENT ============

  /// Sync budgets when coming online
  Future<void> syncBudgetsToFirebase() async {
    if (_uid == null) return;

    try {
      final unsyncedBudgets = await _localDb.getUnsyncedRecords('budgets');
      print('🔄 Syncing ${unsyncedBudgets.length} unsynced budgets...');

      for (final record in unsyncedBudgets) {
        try {
          final budget = _budgetFromMap(record);
          await _dbRef.child('budgets').child(budget.id).set(budget.toJson());

          await _localDb.markAsSynced('budgets', budget.id);
          print('✅ Synced budget: ${budget.displayName}');
        } catch (e) {
          print('❌ Failed to sync budget ${record['id']}: $e');
        }
      }

      print('🎉 Budgets sync completed');
    } catch (e) {
      print('❌ Error syncing budgets: $e');
    }
  }

  Budget _budgetFromMap(Map<String, dynamic> map) {
    return Budget(
      id: map['id'],
      ownerId: map['ownerId'],
      month: map['month'],
      totalAmount: map['totalAmount'],
      categoryAmounts: Map<String, double>.from(
        map['categoryAmounts'] != null ? map['categoryAmounts'] : {},
      ),
      budgetType: BudgetType.values.firstWhere(
        (e) => e.name == (map['budgetType'] ?? 'personal'),
        orElse: () => BudgetType.personal,
      ),
      period: BudgetPeriod.values.firstWhere(
        (e) => e.name == (map['period'] ?? 'monthly'),
        orElse: () => BudgetPeriod.monthly,
      ),
      createdBy: map['createdBy'],
      isActive: (map['isActive'] ?? 1) == 1,
      createdAt: map['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : null,
      updatedAt: map['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['updatedAt'])
          : null,
    );
  }

  // ============ OFFLINE-FIRST HELPERS ============

  /// Get budgets offline-first
  Future<List<Budget>> getBudgetsOfflineFirst({
    String? month,
    BudgetType? budgetType,
    UserProvider? userProvider,
  }) async {
    try {
      // Try local database first
      final localBudgets = await _localDb.getLocalBudgets(
        ownerId: _uid,
        budgetType: budgetType,
        month: month,
      );

      if (localBudgets.isNotEmpty && userProvider != null) {
        return _filterBudgetsByOwnership(
          localBudgets,
          userProvider,
          budgetType,
        );
      }

      return localBudgets;
    } catch (e) {
      print('❌ Error getting budgets offline-first: $e');
      return [];
    }
  }

  /// Get database health for budgets
  Future<Map<String, dynamic>> getBudgetDatabaseHealth() async {
    try {
      final syncStatus = await _localDb.getOfflineSyncStatus();

      return {
        'totalBudgets': syncStatus['totalBudgets'],
        'unsyncedBudgets': syncStatus['unsyncedBudgets'],
        'lastUpdate': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }
}
