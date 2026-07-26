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

  /// 完整 Material 3 暗色主题
  static ThemeData get themeData => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: mauve,
        scaffoldBackgroundColor: base,

        // ── AppBar ──
        appBarTheme: const AppBarTheme(
          backgroundColor: mantle,
          foregroundColor: text,
          elevation: 0,
          centerTitle: false,
        ),

        // ── 卡片 ──
        cardTheme: CardThemeData(
          color: surface0,
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),

        // ── 分割线 ──
        dividerTheme: const DividerThemeData(
          color: surface1,
          thickness: 0.5,
          space: 0,
        ),

        // ── 输入框 ──
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface0,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: surface1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: surface1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: mauve, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          hintStyle: const TextStyle(color: overlay0),
        ),

        // ── 浮动按钮 ──
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: mauve,
          foregroundColor: base,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // ── 文字主题 ──
        textTheme: const TextTheme(
          headlineLarge: TextStyle(
            color: text, fontSize: 28, fontWeight: FontWeight.bold),
          headlineMedium: TextStyle(
            color: text, fontSize: 22, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(
            color: text, fontSize: 18, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(
            color: text, fontSize: 14, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: text, fontSize: 14),
          bodyMedium: TextStyle(color: subtext0, fontSize: 13),
          bodySmall: TextStyle(color: subtext1, fontSize: 12),
          labelLarge: TextStyle(
            color: text, fontSize: 14, fontWeight: FontWeight.w500),
          labelMedium: TextStyle(color: overlay1, fontSize: 12),
          labelSmall: TextStyle(color: overlay0, fontSize: 10),
        ),

        // ── 图标主题 ──
        iconTheme: const IconThemeData(color: overlay1, size: 20),

        // ── 对话框 ──
        dialogTheme: DialogThemeData(
          backgroundColor: surface0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),

        // ── 菜单 ──
        menuTheme: MenuThemeData(
          style: MenuStyle(
            backgroundColor: WidgetStateProperty.all(surface0),
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
            color: surface1,
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(color: text, fontSize: 12),
        ),
      );
}
