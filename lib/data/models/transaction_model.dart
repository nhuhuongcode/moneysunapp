import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

enum TransactionType { expense, income, transfer }

class TransactionModel {
  final String id;
  final double amount;
  final TransactionType type; // Kiểu enum trong ứng dụng
  final String? categoryId;
  final String walletId;
  final DateTime date; // <-- Phải là DateTime
  final String description;
  final String userId;
  final String? subCategoryId;
  final String walletName;
  final String categoryName;
  final String subCategoryName;
  final String? transferToWalletId;
  final String? transferFromWalletName; // For display
  final String? transferToWalletName;

  TransactionModel({
    required this.id,
    required this.amount,
    required this.type,
    this.categoryId,
    required this.walletId,
    required this.date,
    required this.description,
    required this.userId,
    this.subCategoryId,
    this.walletName = '',
    this.categoryName = '',
    this.subCategoryName = '',
    this.transferToWalletId = '',
    this.transferFromWalletName = '',
    this.transferToWalletName = '',
  });

  TransactionModel copyWith({
    String? walletName,
    String? categoryName,
    String? subCategoryName,
    String? transferFromWalletName,
    String? transferToWalletName,
  }) {
    return TransactionModel(
      id: id,
      amount: amount,
      type: type,
      categoryId: categoryId,
      subCategoryId: subCategoryId,
      walletId: walletId,
      date: date,
      description: description,
      userId: userId,
      walletName: walletName ?? this.walletName,
      categoryName: categoryName ?? this.categoryName,
      subCategoryName: subCategoryName ?? this.subCategoryName,
      transferToWalletId: transferToWalletId,
      transferFromWalletName:
          transferFromWalletName ?? this.transferFromWalletName,
      transferToWalletName: transferToWalletName ?? this.transferToWalletId,
    );
  }

  factory TransactionModel.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;

    TransactionType transactionType = TransactionType.values.firstWhere(
      (e) => e.name == data['type'],
      orElse: () => TransactionType.expense,
    );

    return TransactionModel(
      id: snapshot.key!,
      amount: (data['amount'] ?? 0).toDouble(),
      type: transactionType,
      categoryId: data['categoryId'],
      walletId: data['walletId'] ?? '',
      // Đảm bảo parse từ String thành DateTime
      date: DateTime.parse(data['date'] ?? DateTime.now().toIso8601String()),
      description: data['description'] ?? '',
      userId: data['userId'] ?? '',
      subCategoryId: data['subCategoryId'],
      transferToWalletId: data['transferToWalletId'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'type': type.name,
      'categoryId': categoryId,
      'walletId': walletId,
      'date': date.toIso8601String(),
      'description': description,
      'userId': userId,
      'subCategoryId': subCategoryId,
      'transferToWalletId': transferToWalletId,
    };
  }

  @override
  List<Object?> get props => [id, amount, type, date, description];
}
