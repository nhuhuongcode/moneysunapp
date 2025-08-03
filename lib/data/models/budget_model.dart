import 'package:firebase_database/firebase_database.dart';

class Budget {
  final String id;
  final String ownerId;
  final String month;
  final double totalAmount;
  final Map<String, double> categoryAmounts;
  final bool isShared; // THÊM MỚI - Ngân sách chung hay cá nhân

  Budget({
    required this.id,
    required this.ownerId,
    required this.month,
    required this.totalAmount,
    required this.categoryAmounts,
    this.isShared = false, // THÊM MỚI
  });

  factory Budget.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    final sourceCategoryMap = data['categoryAmounts'] as Map? ?? {};

    final Map<String, double> targetCategoryMap = sourceCategoryMap.map(
      (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
    );

    return Budget(
      id: snapshot.key!,
      ownerId: data['ownerId'] ?? '',
      month: data['month'] ?? '',
      totalAmount: (data['totalAmount'] ?? 0).toDouble(),
      categoryAmounts: targetCategoryMap,
      isShared: data['isShared'] ?? false, // THÊM MỚI
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ownerId': ownerId,
      'month': month,
      'totalAmount': totalAmount,
      'categoryAmounts': categoryAmounts,
      'isShared': isShared, // THÊM MỚI
    };
  }
}
