import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:moneysun/features/auth/presentation/screens/login_screen.dart';
import 'package:moneysun/presentation/screens/main_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      // Lắng nghe sự thay đổi trạng thái đăng nhập từ Firebase
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Nếu chưa có dữ liệu, hiển thị màn hình chờ
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // Nếu đã có dữ liệu (user đã đăng nhập), chuyển đến màn hình chính
        // Ta sẽ tạo HomeScreen ở bước tiếp theo
        return const MainScreen();
      },
    );
  }
}
