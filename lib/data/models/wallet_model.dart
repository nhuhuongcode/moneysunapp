// lib/data/models/wallet_model.dart - Enhanced version

import 'package:firebase_database/firebase_database.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class Wallet extends Equatable {
  final String id;
  final String name;
  double balance;
  final String ownerId;
  bool isVisibleToPartner;

  // Enhanced fields for better wallet management
  final bool isArchived;
  final DateTime? archivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? lastAdjustment;
  final String? currency;
  final WalletType type;

  Wallet({
    required this.id,
    required this.name,
    required this.balance,
    required this.ownerId,
    this.isVisibleToPartner = true,
    this.isArchived = false,
    this.archivedAt,
    this.createdAt,
    this.updatedAt,
    this.lastAdjustment,
    this.currency = 'VND',
    this.type = WalletType.general,
  });

  // Enhanced factory constructor with all fields
  factory Wallet.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;

    return Wallet(
      id: snapshot.key!,
      name: data['name'] ?? 'Không tên',
      balance: (data['balance'] ?? 0).toDouble(),
      ownerId: data['ownerId'] ?? '',
      isVisibleToPartner: data['isVisibleToPartner'] ?? true,
      isArchived: data['isArchived'] ?? false,
      archivedAt: data['archivedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['archivedAt'])
          : null,
      createdAt: data['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['createdAt'])
          : null,
      updatedAt: data['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['updatedAt'])
          : null,
      lastAdjustment: data['lastAdjustment'] != null
          ? Map<String, dynamic>.from(data['lastAdjustment'])
          : null,
      currency: data['currency'] ?? 'VND',
      type: WalletType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => WalletType.general,
      ),
    );
  }

  // Enhanced JSON conversion
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'balance': balance,
      'ownerId': ownerId,
      'isVisibleToPartner': isVisibleToPartner,
      'isArchived': isArchived,
      'archivedAt': archivedAt?.millisecondsSinceEpoch,
      'createdAt': createdAt?.millisecondsSinceEpoch ?? ServerValue.timestamp,
      'updatedAt': ServerValue.timestamp,
      'lastAdjustment': lastAdjustment,
      'currency': currency,
      'type': type.name,
    };
  }

  // Copy with method for easy updates
  Wallet copyWith({
    String? id,
    String? name,
    double? balance,
    String? ownerId,
    bool? isVisibleToPartner,
    bool? isArchived,
    DateTime? archivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? lastAdjustment,
    String? currency,
    WalletType? type,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      ownerId: ownerId ?? this.ownerId,
      isVisibleToPartner: isVisibleToPartner ?? this.isVisibleToPartner,
      isArchived: isArchived ?? this.isArchived,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAdjustment: lastAdjustment ?? this.lastAdjustment,
      currency: currency ?? this.currency,
      type: type ?? this.type,
    );
  }

  // Helper methods
  bool get isShared => ownerId.contains('partnership_');
  bool get hasBeenAdjusted => lastAdjustment != null;
  bool get isActive => !isArchived;

  String get formattedBalance {
    // Format based on currency
    switch (currency) {
      case 'VND':
        return '${balance.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}₫';
      case 'USD':
        return '\$${balance.toStringAsFixed(2)}';
      case 'EUR':
        return '€${balance.toStringAsFixed(2)}';
      default:
        return balance.toStringAsFixed(2);
    }
  }

  String get displayName {
    String suffix = '';
    if (isShared) {
      suffix = ' (Chung)';
    } else if (isArchived) {
      suffix = ' (Đã lưu trữ)';
    }
    return name + suffix;
  }

  @override
  List<Object?> get props => [id];

  @override
  String toString() {
    return 'Wallet(id: $id, name: $name, balance: $balance, ownerId: $ownerId)';
  }
}

// Wallet types for better categorization
enum WalletType {
  general('Tổng quát', Icons.account_balance_wallet),
  cash('Tiền mặt', Icons.money),
  bank('Ngân hàng', Icons.account_balance),
  credit('Thẻ tín dụng', Icons.credit_card),
  investment('Đầu tư', Icons.trending_up),
  savings('Tiết kiệm', Icons.savings),
  digital('Ví điện tử', Icons.smartphone);

  const WalletType(this.displayName, this.icon);

  final String displayName;
  final IconData icon;
}

// Wallet statistics model
class WalletStatistics {
  final double totalBalance;
  final double monthlyIncome;
  final double monthlyExpense;
  final double averageTransactionAmount;
  final int transactionCount;
  final List<TransactionTrend> trends;

  WalletStatistics({
    required this.totalBalance,
    required this.monthlyIncome,
    required this.monthlyExpense,
    required this.averageTransactionAmount,
    required this.transactionCount,
    required this.trends,
  });

  double get monthlyNet => monthlyIncome - monthlyExpense;
  bool get isPositiveTrend => monthlyNet > 0;
}

class TransactionTrend {
  final DateTime date;
  final double amount;
  final String type;

  TransactionTrend({
    required this.date,
    required this.amount,
    required this.type,
  });
}

// Wallet validation utilities
class WalletValidator {
  static String? validateName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return 'Tên ví không được để trống';
    }
    if (name.trim().length < 2) {
      return 'Tên ví phải có ít nhất 2 ký tự';
    }
    if (name.trim().length > 50) {
      return 'Tên ví không được vượt quá 50 ký tự';
    }
    return null;
  }

  static String? validateBalance(double? balance) {
    if (balance == null) {
      return 'Số dư không hợp lệ';
    }
    if (balance < 0) {
      return 'Số dư không được âm';
    }
    if (balance > 999999999999) {
      return 'Số dư quá lớn';
    }
    return null;
  }

  static bool canDelete(Wallet wallet, int transactionCount) {
    return transactionCount == 0 && !wallet.isShared;
  }

  static bool canArchive(Wallet wallet) {
    return !wallet.isArchived;
  }

  static bool canEdit(Wallet wallet, String currentUserId) {
    return wallet.ownerId == currentUserId || wallet.isShared;
  }
}
