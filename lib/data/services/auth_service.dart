import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:firebase_database/firebase_database.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // Đăng nhập bằng Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // Người dùng đã hủy quá trình đăng nhập
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      // Sau khi đăng nhập thành công, lưu thông tin user vào Realtime Database
      if (userCredential.user != null) {
        _saveUserToDatabase(userCredential.user!);
      }

      return userCredential;
    } catch (e) {
      print("Lỗi khi đăng nhập bằng Google: $e");
      return null;
    }
  }

  // Lưu thông tin người dùng vào Realtime Database
  void _saveUserToDatabase(User user) {
    _dbRef.child('users').child(user.uid).set({
      'displayName': user.displayName,
      'email': user.email,
      'photoURL': user.photoURL,
      'createdAt': ServerValue.timestamp,
      'partnershipId': null, // THÊM MỚI
      'inviteCode': null,
    });
  }

  // Đăng xuất
  Future<void> signOut() async {
    await _auth.signOut();
    await _googleSignIn.signOut();
  }
}
