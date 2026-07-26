import 'dart:io';

/// 支持的图片格式
const _imageExtensions = {
  '.jpg', '.jpeg', '.png', '.gif', '.bmp',
  '.webp', '.tiff', '.tif', '.ico',
};

bool isImageFile(String path) {
  final ext = path.toLowerCase();
  return _imageExtensions.any((e) => ext.endsWith(e));
}

/// 扫描结果
class ScanResult {
  final List<String> added;
  final List<String> removed;
  final int totalFiles;

  ScanResult({
    required this.added,
    required this.removed,
    required this.totalFiles,
  });
}

/// 文件系统扫描器 — 递归遍历目录，返回图片文件列表
class FileScanner {
  /// 扫描单个目录，返回所有图片路径
  static Future<List<String>> scanDirectory(String dirPath) async {
    final result = <String>[];
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return result;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && isImageFile(entity.path)) {
        result.add(entity.path);
      }
    }
    return result;
  }

  /// 增量扫描：与已知路径列表对比，返回 (新增, 已失效)
  static Future<ScanResult> rescanDirectory(
    String dirPath,
    Set<String> knownPaths,
  ) async {
    final fsPaths = (await scanDirectory(dirPath)).toSet();

    final added = fsPaths.difference(knownPaths).toList()..sort();
    final removed = knownPaths.difference(fsPaths).toList()..sort();

    return ScanResult(
      added: added,
      removed: removed,
      totalFiles: fsPaths.length,
    );
  }

  /// 收集一组路径中的所有唯一目录
  static Set<String> collectFolders(List<String> paths) {
    final dirs = <String>{};
    for (final p in paths) {
      final parent = Directory(p).parent.path;
      dirs.add(parent);
    }
    return dirs;
  }
}
