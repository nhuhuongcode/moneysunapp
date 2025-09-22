import 'package:flutter/material.dart';

class AppTheme {
  //0xFFA8E6CF, fromRGBO(168, 230, 207, 1)
  // Định nghĩa màu chủ đạo - Xanh mint pastel
  static const Color _primaryColor = Color(0xFF75CBAC);
  static const Color _scaffoldBackgroundColor = Color(0xFFF0FDF4);
  static const Color _textColor = Color(0xFF333333);
  static const Color _primaryColorDark = Color(0xFF63B497);

  static const TextStyle _titleLarge = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: _textColor,
    letterSpacing: 0.15,
  );

  static const TextStyle _titleMedium = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: _textColor,
    letterSpacing: 0.15,
  );

  static const TextStyle _titleSmall = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: _textColor,
    letterSpacing: 0.1,
  );

  static const TextStyle _bodyLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: _textColor,
    letterSpacing: 0.5,
  );

  static const TextStyle _bodyMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: _textColor,
    letterSpacing: 0.25,
  );

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

    textTheme: const TextTheme(
      // Titles
      titleLarge: _titleLarge, // Use for main headers
      titleMedium: _titleMedium, // Use for section headers
      titleSmall: _titleSmall, // Use for card titles
      // Body text
      bodyLarge: _bodyLarge, // Use for important content
      bodyMedium: _bodyMedium, // Use for regular content
      // Amount display
      displayLarge: TextStyle(
        // Use for large amounts
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: _textColor,
      ),
      displayMedium: TextStyle(
        // Use for medium amounts
        fontSize: 24,
        fontWeight: FontWeight.w600,
        color: _textColor,
      ),

      // Labels
      labelLarge: TextStyle(
        // Use for button text
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        // Use for input labels
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    ),
  );
}
