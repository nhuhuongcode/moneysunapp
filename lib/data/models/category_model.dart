import 'package:firebase_database/firebase_database.dart';
import 'package:equatable/equatable.dart';

class Category extends Equatable {
  final String id;
  final String name;
  final String ownerId;
  final String type;
  final int? iconCodePoint;
  final Map<String, String> subCategories;

  const Category({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.type,
    this.iconCodePoint,
    this.subCategories = const {},
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'ownerId': ownerId,
      'type': type,
      'iconCodePoint': iconCodePoint,
      'subCategories': subCategories,
    };
  }

  @override
  List<Object?> get props => [id];
}
