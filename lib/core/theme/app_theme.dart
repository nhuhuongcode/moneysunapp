import 'package:flutter/material.dart';

class AppTheme {
  // Định nghĩa màu chủ đạo - Xanh mint pastel
  static const Color _primaryColor = Color(0xFFA8E6CF);
  static const Color _scaffoldBackgroundColor = Color(0xFFF0FDF4);
  static const Color _textColor = Color(0xFF333333);
  static const Color _primaryColorDark = Color(0xFF63B497);

  static final ThemeData lightTheme = ThemeData(
    primaryColor: _primaryColor,
    scaffoldBackgroundColor: _scaffoldBackgroundColor,
    fontFamily: 'Roboto', // Bạn có thể chọn font khác nếu muốn
    colorScheme: const ColorScheme.light(
      primary: _primaryColor,
      secondary: Color(0xFFFFD3B6), // Một màu pastel khác để bổ trợ
      onPrimary: Colors.white,
      onSecondary: _textColor,
      surface: Colors.white,
      background: _scaffoldBackgroundColor,
      error: Colors.redAccent,
      onSurface: _textColor,
      onBackground: _textColor,
      onError: Colors.white,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: _primaryColor,
      elevation: 0,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        // SỬA LỖI: Dùng màu đậm hơn cho nút
        backgroundColor: _primaryColorDark,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      ),
    ),

    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _primaryColorDark, // Áp dụng cho cả FAB
      foregroundColor: Colors.white,
    ),
  );
}
