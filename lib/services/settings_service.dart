import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../utils/file_io.dart';
import '../utils/log_util.dart';
import 'data_dir_service.dart';

/// 持久化设置服务（JSON 文件，位于数据目录 settings.json）。
///
/// 存储位置跟随 [DataDirService]，因此「数据位置迁移」会一并迁移设置。
/// 写入统一走 [AtomicFileWriter]：并发调用按顺序排队，每次原子替换，
/// 不会写出半截 JSON；上一份内容保留为 `settings.json.bak` 作为回退点。
class SettingsService {
  SettingsService._();

  static final SettingsService instance = SettingsService._();

  Map<String, dynamic> _data = {};

  AtomicFileWriter? _writer;

  Future<File> _file() async {
    return File(p.join(await DataDirService.instance.dataDir, 'settings.json'));
  }

  /// 初始化（App 启动时调用一次）
  ///
  /// 主文件读不出来时回退到 `settings.json.bak`，两者都不可用才使用默认值。
  Future<void> init() async {
    final f = await _file();
    final data = await _readJson(f) ??
        await _readJson(File('${f.path}.bak')) ??
        <String, dynamic>{};
    _data = data;
    logInfo('Settings', 'Initialized OK (${data.length} keys)');
  }

  /// 读取并解析 JSON 对象，任何异常都只记日志并返回 null。
  Future<Map<String, dynamic>?> _readJson(File f) async {
    if (!f.existsSync()) return null;
    try {
      final decoded = jsonDecode(await f.readAsString());
      if (decoded is Map<String, dynamic>) return decoded;
      logWarn('Settings', '内容不是 JSON 对象: ${f.path}');
    } catch (e) {
      logWarn('Settings', '解析失败: ${f.path} ($e)');
    }
    return null;
  }

  /// 保存设置。
  ///
  /// 数据目录迁移后目标路径会变，路径不同就换一个写入器，
  /// 同时意味着从一条新的排队链条开始。
  Future<void> _save() async {
    final f = await _file();
    var writer = _writer;
    if (writer == null || writer.path != f.path) {
      writer = AtomicFileWriter(f.path);
      _writer = writer;
    }
    await writer.write(jsonEncode(_data));
  }

  // ═══════════════ 主题 ═══════════════

  ThemeMode get themeMode {
    final v = _data['theme_mode'] as String? ?? 'dark';
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _data['theme_mode'] = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      _ => 'system',
    };
    await _save();
    logInfo('Settings', 'Theme mode set to ${_data['theme_mode']}');
  }

  // ═══════════════ 网格 ═══════════════

  int get gridColumns => (_data['grid_columns'] as int?) ?? 5;

  Future<void> setGridColumns(int cols) async {
    _data['grid_columns'] = cols.clamp(2, 10);
    await _save();
  }

  // ═══════════════ 缓存 ═══════════════

  int get cacheSizeMB => (_data['cache_mb'] as int?) ?? 2048;

  Future<void> setCacheSizeMB(int mb) async {
    _data['cache_mb'] = mb.clamp(256, 8192);
    await _save();
  }

  // ═══════════════ 排序 ═══════════════

  /// 排序键：added_at / filename / alias / file_size / file_mtime
  String get sortKey => (_data['sort_key'] as String?) ?? 'added_at';

  Future<void> setSortKey(String key) async {
    _data['sort_key'] = key;
    await _save();
  }

  bool get sortDescending => (_data['sort_desc'] as bool?) ?? true;

  Future<void> setSortDescending(bool desc) async {
    _data['sort_desc'] = desc;
    await _save();
  }

  // ═══════════════ 视图模式 ═══════════════

  /// 'grid' 或 'list'
  String get viewMode => (_data['view_mode'] as String?) ?? 'grid';

  Future<void> setViewMode(String mode) async {
    _data['view_mode'] = mode == 'list' ? 'list' : 'grid';
    await _save();
  }

  // ═══════════════ 表达式历史缓存 ═══════════════

  /// 高级筛选表达式历史（最新在前）
  List<String> get expressionHistory {
    final raw = _data['expr_history'];
    if (raw is List) {
      return raw.whereType<String>().toList();
    }
    return const [];
  }

  /// 历史缓存最大条数（0 表示关闭缓存）
  int get maxExprCacheCount => (_data['expr_cache_count'] as int?) ?? 10;

  Future<void> setMaxExprCacheCount(int count) async {
    _data['expr_cache_count'] = count.clamp(0, 100);
    await _save();
    // 立即裁剪超出的历史
    final list = expressionHistory;
    final cap = _data['expr_cache_count'] as int;
    if (list.length > cap) {
      _data['expr_history'] = list.sublist(0, cap);
      await _save();
    }
  }

  /// 记录一条表达式到历史（去重、前置、按上限裁剪）
  Future<void> addExpression(String expression) async {
    final expr = expression.trim();
    if (expr.isEmpty) return;
    final list = expressionHistory.where((e) => e != expr).toList();
    list.insert(0, expr);
    final cap = maxExprCacheCount;
    if (cap <= 0) {
      _data['expr_history'] = const <String>[];
    } else {
      _data['expr_history'] = list.take(cap).toList();
    }
    await _save();
  }

  Future<void> clearExpressionHistory() async {
    _data['expr_history'] = const <String>[];
    await _save();
  }
}
