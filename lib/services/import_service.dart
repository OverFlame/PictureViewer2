import 'dart:io';

import 'package:path/path.dart' as p;

import '../db/database.dart';
import '../db/image_dao.dart';
import '../db/folder_dao.dart';
import '../utils/log_util.dart';
import 'file_scanner.dart';
import 'thumbnail_cache.dart';

/// 导入进度事件
class ImportProgress {
  final int current;
  final int total;
  final String currentFile;
  final int? imageId;

  ImportProgress({
    required this.current,
    required this.total,
    required this.currentFile,
    this.imageId,
  });

  double get percent => total > 0 ? current / total : 0;
}

/// 批量导入服务
/// 流程：扫描目录 → 事务写入 DB → 后台生成缩略图
class ImportService {
  final ImageDao _imageDao;
  final FolderDao _folderDao;
  final ThumbnailService _thumbnailService;

  bool _isImporting = false;
  bool get isImporting => _isImporting;

  ImportService({
    required ImageDao imageDao,
    required FolderDao folderDao,
    required ThumbnailService thumbnailService,
  })  : _imageDao = imageDao,
        _folderDao = folderDao,
        _thumbnailService = thumbnailService;

  /// 工厂：从 DatabaseManager 创建
  factory ImportService.fromDB() {
    final db = DatabaseManager.instance.db;
    return ImportService(
      imageDao: ImageDao(db),
      folderDao: FolderDao(db),
      thumbnailService: ThumbnailService.instance,
    );
  }

  /// 扫描并导入混合路径（目录 + 单文件）
  Stream<ImportProgress> importPaths(List<String> paths) async* {
    if (_isImporting) return;
    _isImporting = true;

    try {
      // 1. 扫描所有路径：目录递归扫描，文件直接检查
      final allPaths = <String>{};
      final rootDirs = <String>[];

      for (final path in paths) {
        final stat = FileSystemEntity.typeSync(path);
        if (stat == FileSystemEntityType.directory) {
          final scanned = await FileScanner.scanDirectory(path);
          allPaths.addAll(scanned);
          rootDirs.add(path);
        } else if (stat == FileSystemEntityType.file && isImageFile(path)) {
          allPaths.add(path);
          rootDirs.add(p.dirname(path));
        }
      }

      if (allPaths.isEmpty) {
        logInfo('Import', 'importPaths: no image files found');
        _isImporting = false;
        return;
      }

      final imagePaths = allPaths.toList();
      final existing = await _imageDao.existingPaths(imagePaths);
      final newPaths = imagePaths.where((p) => !existing.contains(p)).toList();
      final total = newPaths.length;
      logInfo('Import', 'importPaths: scanned ${imagePaths.length} total, $total new, ${imagePaths.length - total} dupes');

      if (total == 0) {
        logInfo('Import', 'importPaths: all files already indexed');
        _isImporting = false;
        return;
      }

      // 2. 逐条写入数据库
      final imageIds = <({int id, String path})>[];
      for (int i = 0; i < newPaths.length; i++) {
        final fp = newPaths[i];
        final file = File(fp);

        int sizeBytes = 0;
        try { sizeBytes = await file.length(); } catch (_) {}

        final ext = p.extension(fp).toLowerCase();
        final filename = p.basename(fp);
        final now = DateTime.now().millisecondsSinceEpoch;

        final item = ImageItem(
          path: fp,
          filename: filename,
          format: ext.isNotEmpty ? ext.substring(1) : 'unknown',
          fileSize: sizeBytes > 0 ? sizeBytes : null,
          addedAt: now,
        );

        final fid = await _imageDao.insert(item);
        imageIds.add((id: fid, path: fp));

        yield ImportProgress(
          current: i + 1,
          total: total,
          currentFile: fp,
          imageId: fid,
        );
      }

      // 3. 镜像物理目录，建立文件夹层级
      await _mirrorFolderTree(rootDirs, imagePaths);
      logInfo('Import', 'importPaths: folder tree mirrored for ${rootDirs.length} root(s)');
    } finally {
      _isImporting = false;
    }
  }

  /// 扫描并导入目录中的所有图片
  Stream<ImportProgress> importDirectory(String dirPath) async* {
    if (_isImporting) return;
    _isImporting = true;

    try {
      // 1. 扫描文件系统
      final imagePaths = await FileScanner.scanDirectory(dirPath);
      logInfo('Import',
          'importDirectory: ${imagePaths.length} images in "$dirPath"');
      if (imagePaths.isEmpty) {
        _isImporting = false;
        return;
      }

      // 2. 获取已知路径去重
      final existing = await _imageDao.existingPaths(imagePaths);

      // 3. 过滤出新文件
      final newPaths = imagePaths.where((p) => !existing.contains(p)).toList();
      final total = newPaths.length;

      if (total == 0) {
        _isImporting = false;
        return; // 全部已索引
      }

      // 4. 批量写入数据库
      final imageIds = <({int id, String path})>[];

      for (int i = 0; i < newPaths.length; i++) {
        final path = newPaths[i];
        final file = File(path);

        int sizeBytes = 0;
        try {
          sizeBytes = await file.length();
        } catch (_) {}

        final ext = p.extension(path).toLowerCase();
        final filename = p.basename(path);
        final now = DateTime.now().millisecondsSinceEpoch;

        final item = ImageItem(
          path: path,
          filename: filename,
          format: ext.isNotEmpty ? ext.substring(1) : 'unknown',
          fileSize: sizeBytes > 0 ? sizeBytes : null,
          addedAt: now,
        );

        final fid = await _imageDao.insert(item);
        imageIds.add((id: fid, path: path));

        yield ImportProgress(
          current: i + 1,
          total: total,
          currentFile: path,
          imageId: fid,
        );
      }

      // 5. 镜像物理目录，建立文件夹层级
      await _mirrorFolderTree([dirPath], imagePaths);
      logInfo('Import', 'importDirectory: folder tree mirrored for "$dirPath"');
    } finally {
      _isImporting = false;
    }
  }

  /// 为新导入的图片生成缩略图
  Stream<ImportProgress> generateThumbnails(
      List<({int id, String path})> images) async* {
    final total = images.length;

    for (int i = 0; i < images.length; i++) {
      final img = images[i];
      try {
        await _thumbnailService.ensureThumbnail(img.path, size: 300);
      } catch (_) {
        // 单张缩略图失败不中断整体流程
      }

      yield ImportProgress(
        current: i + 1,
        total: total,
        currentFile: img.path,
        imageId: img.id,
      );
    }
  }

  /// 重新扫描指定目录（增量更新）
  Stream<String> rescanDirectory(String dirPath) async* {
    if (_isImporting) return;
    _isImporting = true;

    try {
      final known = await _imageDao.pathsInDirectory(dirPath);
      final result = await FileScanner.rescanDirectory(dirPath, known.toSet());

      // 删除失效索引
      if (result.removed.isNotEmpty) {
        await _imageDao.deleteByPaths(result.removed);
        for (final rp in result.removed) {
          await _thumbnailService.deleteThumbnails(rp);
          yield 'removed: $rp';
        }
      }

      // 导入新文件
      for (final ap in result.added) {
        final file = File(ap);
        int sizeBytes = 0;
        try {
          sizeBytes = await file.length();
        } catch (_) {}

        final ext = p.extension(ap).toLowerCase();
        final filename = p.basename(ap);
        final now = DateTime.now().millisecondsSinceEpoch;

        await _imageDao.insert(ImageItem(
          path: ap,
          filename: filename,
          format: ext.isNotEmpty ? ext.substring(1) : 'unknown',
          fileSize: sizeBytes > 0 ? sizeBytes : null,
          addedAt: now,
        ));
        yield 'added: $ap';
      }
    } finally {
      _isImporting = false;
    }
  }

  // ═══ 文件夹层级镜像 ═══

  /// 按物理磁盘目录镜像建立文件夹父子层级（类似 Windows 资源管理器）。
  /// 对每个 [roots] 根目录，扫描其下图片所在的目录链，为每个目录创建
  /// 文件夹节点并建立 parent 关系；已存在的节点则修正其 parent。
  Future<void> _mirrorFolderTree(
      List<String> roots, List<String> imagePaths) async {
    for (final root in roots) {
      final rootNorm = _normPath(root);
      if (rootNorm.isEmpty) continue;

      // 收集该根目录下涉及的所有目录（图片父目录及其祖先）
      final dirs = <String>{};
      for (final img in imagePaths) {
        final imgNorm = _normPath(img);
        if (!_isUnder(imgNorm, rootNorm)) continue;
        var dir = p.dirname(imgNorm);
        while (true) {
          dir = _normPath(dir);
          dirs.add(dir);
          if (dir == rootNorm) break;
          final parent = p.dirname(dir);
          if (_normPath(parent) == dir) break; // 到达文件系统根
          dir = parent;
        }
      }

      // 按目录深度从浅到深排序，保证父目录先创建
      final sorted = dirs.toList()
        ..sort((a, b) => _dirDepth(a).compareTo(_dirDepth(b)));

      final map = <String, VirtualFolder>{};
      for (final dir in sorted) {
        final parentDir = _normPath(p.dirname(dir));
        final expectedParentId = map[parentDir]?.id;

        var folder = await _folderDao.getByPath(dir);
        if (folder == null) {
          final name = p.basename(dir);
          final displayName = name.isEmpty ? dir : name;
          folder = await _folderDao.create(displayName,
              parentId: expectedParentId);
          await _folderDao.addPath(folder.id!, dir, recursive: false);
        } else if (folder.parentId != expectedParentId) {
          // 已存在但层级不符，修正 parent（重新导入时渐进修复旧扁平结构）
          await _folderDao.move(folder.id!, expectedParentId);
          folder = VirtualFolder(
              id: folder.id, name: folder.name, parentId: expectedParentId);
        }
        map[dir] = folder;
      }
    }
  }

  /// 归一化路径：去掉末尾分隔符
  static String _normPath(String s) {
    var x = s;
    while (x.endsWith('\\') || x.endsWith('/')) {
      x = x.substring(0, x.length - 1);
    }
    return x;
  }

  /// 判断 [path] 是否位于 [dir] 之下（大小写不敏感，兼容 / 与 \）
  static bool _isUnder(String path, String dir) {
    final a = path.toLowerCase();
    final b = dir.toLowerCase();
    if (a == b) return false;
    return a.startsWith('$b\\') || a.startsWith('$b/');
  }

  /// 目录深度（按分隔符数量）
  static int _dirDepth(String dir) {
    return dir.split(RegExp(r'[\\/]')).length;
  }
}
