import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/log_util.dart';

/// 持久化设置服务（基于 SharedPreferences）
class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  SharedPreferences? _prefs;

  // ── Keys ──
  static const _kThemeMode = 'theme_mode';
  static const _kGridColumns = 'grid_columns';
  static const _kCacheMB = 'cache_mb';

  /// 初始化（App 启动时调用一次）
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    logInfo('Settings', 'Initialized OK');
  }

  // ═══════════════ 主题 ═══════════════

  ThemeMode get themeMode {
    final v = _prefs?.getString(_kThemeMode) ?? 'dark';
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final v = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await _prefs?.setString(_kThemeMode, v);
    logInfo('Settings', 'Theme mode set to $v');
  }

  // ═══════════════ 网格 ═══════════════

  int get gridColumns => _prefs?.getInt(_kGridColumns) ?? 5;

  Future<void> setGridColumns(int cols) async {
    await _prefs?.setInt(_kGridColumns, cols.clamp(2, 10));
  }

  // ═══════════════ 缓存 ═══════════════

  int get cacheSizeMB => _prefs?.getInt(_kCacheMB) ?? 2048;

  Future<void> setCacheSizeMB(int mb) async {
    await _prefs?.setInt(_kCacheMB, mb.clamp(256, 8192));
  }
}
