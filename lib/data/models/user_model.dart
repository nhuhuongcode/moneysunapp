class AppUser {
  final String uid;
  final String displayName;
  final String email;
  final String? photoURL; // THÊM MỚI
  String? partnershipId;
  String? inviteCode;
  String? partnerUid; // THÊM MỚI - UID của đối tác
  String? partnerDisplayName; // THÊM MỚI - Tên của đối tác
  DateTime? partnershipCreatedAt; // THÊM MỚI - Thời điểm kết nối

  AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoURL,
    this.partnershipId,
    this.inviteCode,
    this.partnerUid,
    this.partnerDisplayName,
    this.partnershipCreatedAt,
  });

  // THÊM MỚI
  factory AppUser.fromMap(Map<dynamic, dynamic> data, String uid) {
    return AppUser(
      uid: uid,
      displayName: data['displayName'] ?? '',
      email: data['email'] ?? '',
      photoURL: data['photoURL'],
      partnershipId: data['partnershipId'],
      inviteCode: data['inviteCode'],
      partnerUid: data['partnerUid'],
      partnerDisplayName: data['partnerDisplayName'],
      partnershipCreatedAt: data['partnershipCreatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(data['partnershipCreatedAt'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'photoURL': photoURL,
      'partnershipId': partnershipId,
      'inviteCode': inviteCode,
      'partnerUid': partnerUid,
      'partnerDisplayName': partnerDisplayName,
      'partnershipCreatedAt': partnershipCreatedAt?.millisecondsSinceEpoch,
    };
  }
}
