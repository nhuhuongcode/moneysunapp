import 'package:firebase_database/firebase_database.dart';
import 'package:equatable/equatable.dart';

class Wallet extends Equatable {
  final String id;
  final String name;
  double balance;
  final String ownerId;
  bool isVisibleToPartner;

  Wallet({
    required this.id,
    required this.name,
    required this.balance,
    required this.ownerId,
    this.isVisibleToPartner = true,
  });

  // Factory constructor để tạo Wallet từ dữ liệu Firebase
  factory Wallet.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    return Wallet(
      id: snapshot.key!,
      name: data['name'] ?? 'Không tên',
      balance: (data['balance'] ?? 0).toDouble(),
      ownerId: data['ownerId'] ?? '',
      isVisibleToPartner: data['isVisibleToPartner'] ?? true,
    );
  }

  // Chuyển đổi Wallet thành một Map để lưu vào Firebase
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'balance': balance,
      'ownerId': ownerId,
      'isVisibleToPartner': isVisibleToPartner,
    };
  }

  @override
  List<Object?> get props => [id];
}
