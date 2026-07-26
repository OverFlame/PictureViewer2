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
      final folderNames = <String>[];

      for (final path in paths) {
        final stat = FileSystemEntity.typeSync(path);
        if (stat == FileSystemEntityType.directory) {
          final scanned = await FileScanner.scanDirectory(path);
          allPaths.addAll(scanned);
          folderNames.add(p.basename(path));
        } else if (stat == FileSystemEntityType.file && isImageFile(path)) {
          allPaths.add(path);
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

      // 3. 创建文件夹记录
      final folderDirs = FileScanner.collectFolders(newPaths);
      logInfo('Import', 'importPaths: creating ${folderDirs.length} folder record(s)');
      for (final d in folderDirs) {
        final folderName = p.basename(d);
        final found = await _folderDao.getByPath(d);
        if (found == null) {
          await _folderDao.insert(name: folderName, path: d);
        }
      }

      // 4. 如果只拖入了单文件（无文件夹记录），创建手动导入记录
      if (folderDirs.isEmpty) {
        final now = DateTime.now();
        final importName = '手动导入 '
            '${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')} '
            '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        await _folderDao.insert(name: importName, path: '');
      }
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

      // 5. 创建文件夹记录
      final folderDirs = FileScanner.collectFolders(newPaths);
      for (final d in folderDirs) {
        final folderName = p.basename(d);
        final found = await _folderDao.getByPath(d);
        if (found == null) {
          await _folderDao.insert(name: folderName, path: d);
        }
      }
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
}
