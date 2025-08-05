import 'package:firebase_database/firebase_database.dart';

class Partnership {
  final String id;
  final List<String> memberIds;
  final DateTime createdAt;
  final Map<String, String> memberNames; // uid -> displayName
  final bool isActive;
  final DateTime? lastSyncTime;

  Partnership({
    required this.id,
    required this.memberIds,
    required this.createdAt,
    required this.memberNames,
    this.isActive = true,
    this.lastSyncTime,
  });

  factory Partnership.fromSnapshot(DataSnapshot snapshot) {
    final data = snapshot.value as Map<dynamic, dynamic>;
    final members = data['members'] as Map<dynamic, dynamic>? ?? {};
    final memberNames = data['memberNames'] as Map<dynamic, dynamic>? ?? {};

    return Partnership(
      id: snapshot.key!,
      memberIds: members.keys.map((key) => key.toString()).toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(data['createdAt'] ?? 0),
      memberNames: memberNames.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      isActive: data['isActive'] ?? true,
      lastSyncTime: data['lastSyncTime'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['lastSyncTime'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'members': {for (var id in memberIds) id: true},
      'memberNames': memberNames,
      'createdAt': ServerValue.timestamp,
      'isActive': isActive,
      'lastSyncTime': ServerValue.timestamp,
    };
  }
}
