import 'package:flutter/material.dart';

/// Catppuccin Mocha — 与 v1 一致的暗色主题色板
class Catppuccin {
  Catppuccin._();

  // ── 基底 ──
  static const Color base = Color(0xFF1E1E2E);
  static const Color mantle = Color(0xFF181825);
  static const Color crust = Color(0xFF11111B);

  // ── 表面 ──
  static const Color surface0 = Color(0xFF313244);
  static const Color surface1 = Color(0xFF45475A);
  static const Color surface2 = Color(0xFF585B70);

  // ── 覆盖层 ──
  static const Color overlay0 = Color(0xFF6C7086);
  static const Color overlay1 = Color(0xFF7F849C);
  static const Color overlay2 = Color(0xFF9399B2);

  // ── 文字 ──
  static const Color text = Color(0xFFCDD6F4);
  static const Color subtext0 = Color(0xFFA6ADC8);
  static const Color subtext1 = Color(0xFFBAC2DE);

  // ── 强调色 ──
  static const Color rosewater = Color(0xFFF5E0DC);
  static const Color flamingo = Color(0xFFF2CDCD);
  static const Color pink = Color(0xFFF5C2E7);
  static const Color mauve = Color(0xFFCBA6F7);
  static const Color red = Color(0xFFF38BA8);
  static const Color maroon = Color(0xFFEBA0AC);
  static const Color peach = Color(0xFFFAB387);
  static const Color yellow = Color(0xFFF9E2AF);
  static const Color green = Color(0xFFA6E3A1);
  static const Color teal = Color(0xFF94E2D5);
  static const Color sky = Color(0xFF89DCEB);
  static const Color sapphire = Color(0xFF74C7EC);
  static const Color blue = Color(0xFF89B4FA);
  static const Color lavender = Color(0xFFB4BEFE);

  /// 标签命名空间对应颜色（用于视觉区分）
  static const Map<String, Color> namespaceColors = {
    'general': lavender,
    'character': green,
    'copyright': yellow,
    'artist': sky,
    'meta': teal,
    'rating': red,
  };

  static Color namespaceColor(String namespace) =>
      namespaceColors[namespace] ?? mauve;

  /// Catppuccin Latte (浅色) 色板
  static ThemeData get lightThemeData => _buildTheme(Brightness.light);
  /// Catppuccin Mocha (暗色) 色板
  static ThemeData get darkThemeData => _buildTheme(Brightness.dark);

  /// 完整 Material 3 暗色主题 (兼容旧代码)
  static ThemeData get themeData => darkThemeData;

  static ThemeData _buildTheme(Brightness brightness) {
    final bool isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorSchemeSeed: isDark ? mauve : const Color(0xFF8839EF),
      scaffoldBackgroundColor: isDark ? base : const Color(0xFFEFF1F5),

      // ── AppBar ──
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? mantle : const Color(0xFFE6E9EF),
        foregroundColor: isDark ? text : const Color(0xFF4C4F69),
        elevation: 0,
        centerTitle: false,
      ),

      // ── 卡片 ──
      cardTheme: CardThemeData(
        color: isDark ? surface0 : const Color(0xFFCCD0DA),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      // ── 分割线 ──
      dividerTheme: DividerThemeData(
        color: isDark ? surface1 : const Color(0xFFBCC0CC),
        thickness: 0.5,
        space: 0,
      ),

      // ── 输入框 ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? surface0 : const Color(0xFFCCD0DA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? surface1 : const Color(0xFFBCC0CC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? surface1 : const Color(0xFFBCC0CC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? mauve : const Color(0xFF8839EF), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        hintStyle: TextStyle(
          color: isDark ? overlay0 : const Color(0xFF9CA0B0)),
      ),

      // ── 浮动按钮 ──
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: isDark ? mauve : const Color(0xFF8839EF),
        foregroundColor: isDark ? base : const Color(0xFFEFF1F5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ── 文字主题 ──
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: isDark ? text : const Color(0xFF4C4F69),
          fontSize: 28, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(
          color: isDark ? text : const Color(0xFF4C4F69),
          fontSize: 22, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(
          color: isDark ? text : const Color(0xFF4C4F69),
          fontSize: 18, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(
          color: isDark ? text : const Color(0xFF4C4F69),
          fontSize: 14, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(
          color: isDark ? text : const Color(0xFF4C4F69), fontSize: 14),
        bodyMedium: TextStyle(
          color: isDark ? subtext0 : const Color(0xFF6C6F85), fontSize: 13),
        bodySmall: TextStyle(
          color: isDark ? subtext1 : const Color(0xFF5C5F77), fontSize: 12),
        labelLarge: TextStyle(
          color: isDark ? text : const Color(0xFF4C4F69),
          fontSize: 14, fontWeight: FontWeight.w500),
        labelMedium: TextStyle(
          color: isDark ? overlay1 : const Color(0xFF8C8FA1), fontSize: 12),
        labelSmall: TextStyle(
          color: isDark ? overlay0 : const Color(0xFF9CA0B0), fontSize: 10),
      ),

      // ── 图标主题 ──
      iconTheme: IconThemeData(
        color: isDark ? overlay1 : const Color(0xFF8C8FA1), size: 20),

      // ── 对话框 ──
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? surface0 : const Color(0xFFCCD0DA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),

      // ── 菜单 ──
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            isDark ? surface0 : const Color(0xFFCCD0DA)),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),

      // ── Tooltip ──
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? surface1 : const Color(0xFFBCC0CC),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: TextStyle(
          color: isDark ? text : const Color(0xFF4C4F69), fontSize: 12),
      ),
    );
  }
}
