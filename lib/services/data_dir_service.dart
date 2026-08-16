import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/log_util.dart';

/// 数据目录服务：统一管理数据库 / 缩略图 / 设置文件的根目录。
///
/// 目录结构：
/// ```
/// <dataDir>/pv2.db
/// <dataDir>/thumbnails/
/// <dataDir>/settings.json
/// ```
///
/// 位置覆盖：默认位置下的 `.datadir` 指针文件记录实际数据目录；
/// 未覆盖时使用默认位置 `<应用文档目录>/PictureViewer`。
class DataDirService {
  DataDirService._();

  static final DataDirService instance = DataDirService._();

  String? _dataDir;

  /// 默认数据目录（未覆盖时使用）
  Future<String> defaultDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return p.join(docs.path, 'PictureViewer');
  }

  /// 指针文件路径（始终位于默认位置）
  Future<String> _pointerFile() async {
    return p.join(await defaultDir(), '.datadir');
  }

  /// 当前数据目录（覆盖则用覆盖，否则默认），并确保其存在
  Future<String> get dataDir async {
    if (_dataDir != null) return _dataDir!;

    final def = await defaultDir();
    var result = def;
    try {
      final pf = await _pointerFile();
      final f = File(pf);
      if (f.existsSync()) {
        final content = f.readAsStringSync().trim();
        if (content.isNotEmpty) {
          result = content;
        }
      }
    } catch (e) {
      logWarn('DataDir', '读取指针文件失败: $e');
    }

    _dataDir = result;
    await Directory(result).create(recursive: true);
    return result;
  }

  /// 初始化：解析数据目录并确保存在
  Future<void> init() async {
    final dir = await dataDir;
    logInfo('DataDir', 'Data dir: $dir');
  }

  /// 更换数据目录并迁移现有数据（数据库 / 缩略图 / 设置）。
  /// 旧目录保留（不删除），返回新目录路径。
  Future<String> migrateTo(String newDir) async {
    final oldDir = await dataDir;
    final newD = p.normalize(newDir);
    await Directory(newD).create(recursive: true);

    // 迁移文件（copy 而非 move，旧数据保留，避免迁移失败丢数据）
    await _copyFileIfExists(p.join(oldDir, 'pv2.db'), p.join(newD, 'pv2.db'));
    await _copyFileIfExists(
        p.join(oldDir, 'settings.json'), p.join(newD, 'settings.json'));
    await _copyDir(
        p.join(oldDir, 'thumbnails'), p.join(newD, 'thumbnails'));

    // 写入指针
    final def = await defaultDir();
    await Directory(def).create(recursive: true);
    await File(p.join(def, '.datadir')).writeAsString(newD);

    _dataDir = newD;
    logInfo('DataDir', 'Migrated data dir: $oldDir -> $newD');
    return newD;
  }

  Future<void> _copyFileIfExists(String src, String dst) async {
    final s = File(src);
    if (!s.existsSync()) return;
    await File(dst).parent.create(recursive: true);
    await s.copy(dst);
  }

  Future<void> _copyDir(String src, String dst) async {
    final s = Directory(src);
    if (!s.existsSync()) return;
    await for (final entity in s.list(recursive: true)) {
      if (entity is File) {
        final rel = p.relative(entity.path, from: src);
        final target = File(p.join(dst, rel));
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    }
  }
}
