import 'dart:ui';

/// 解析十六进制颜色字符串，支持 `#RGB` / `#RGBA` / `#RRGGBB` / `#RRGGBBAA`
/// （可带或不带 `#`）。解析失败返回 [fallback]。
Color parseHexColor(String? hex, {Color fallback = const Color(0xFFCBA6F7)}) {
  if (hex == null) return fallback;
  var s = hex.trim();
  if (s.isEmpty) return fallback;
  if (s.startsWith('#')) s = s.substring(1);

  // 展开短格式 #RGB / #RGBA
  if (s.length == 3 || s.length == 4) {
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      buf.write(ch);
      buf.write(ch);
    }
    s = buf.toString();
  }

  if (s.length == 6) {
    final v = int.tryParse(s, radix: 16);
    if (v == null) return fallback;
    return Color.fromARGB(255, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
  }
  if (s.length == 8) {
    final v = int.tryParse(s, radix: 16);
    if (v == null) return fallback;
    return Color.fromARGB(
        (v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
  }
  return fallback;
}

/// 颜色转十六进制字符串；alpha=255 时输出 `#RRGGBB`，否则 `#RRGGBBAA`。
String colorToHex(Color color) {
  String h(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
  final argb = color.toARGB32();
  final a = (argb >> 24) & 0xFF;
  final r = (argb >> 16) & 0xFF;
  final g = (argb >> 8) & 0xFF;
  final b = argb & 0xFF;
  if (a == 255) return '#${h(r)}${h(g)}${h(b)}';
  return '#${h(r)}${h(g)}${h(b)}${h(a)}';
}
