import 'dart:collection';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../utils/log_util.dart';

/// 缩略图内存 LRU 缓存
class ThumbnailMemoryCache {
  static const _maxEntries = 200;

  final _map = LinkedHashMap<String, ui.Image>();

  ui.Image? get(String key) {
    final img = _map.remove(key);
    if (img != null) {
      _map[key] = img; // 移到末尾 → LRU
    }
    return img;
  }

  void put(String key, ui.Image img) {
    _map.remove(key);
    _map[key] = img;
    while (_map.length > _maxEntries) {
      final oldest = _map.keys.first;
      _map.remove(oldest)?.dispose(); // 释放 GPU 纹理
    }
  }

  void clear() {
    for (final img in _map.values) {
      img.dispose();
    }
    _map.clear();
  }
}

/// 缩略图服务 — 三层缓存（内存 LRU → 磁盘 → 原图生成）
class ThumbnailService {
  static ThumbnailService? _instance;
  final ThumbnailMemoryCache _memoryCache = ThumbnailMemoryCache();
  late String _cacheDir;

  ThumbnailService._();

  static ThumbnailService get instance {
    _instance ??= ThumbnailService._();
    return _instance!;
  }

  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = p.join(appDir.path, 'PictureViewer', 'thumbnails');
    await Directory(_cacheDir).create(recursive: true);
    logInfo('Thumbnail', 'Cache dir: $_cacheDir');
  }

  /// 获取缩略图路径（不生成，仅返回路径）
  String thumbPath(String originalPath, {int size = 300}) {
    final hash = sha256.convert(originalPath.codeUnits).toString();
    final subDir = hash.substring(0, 2);
    return p.join(_cacheDir, subDir, '$hash.t$size');
  }

  /// 确保磁盘缓存目录存在
  Future<void> _ensureSubDir(String subDir) async {
    await Directory(p.join(_cacheDir, subDir)).create(recursive: true);
  }

  /// 生成缩略图并写入磁盘缓存
  /// 只有磁盘缓存未命中时才真正解码原图
  /// [size] 是目标长边像素
  Future<String> ensureThumbnail(String originalPath, {int size = 300}) async {
    final targetPath = thumbPath(originalPath, size: size);

    // 磁盘缓存命中 → 直接返回路径
    if (File(targetPath).existsSync()) {
      return targetPath;
    }

    // 检查原图是否存在
    final originalFile = File(originalPath);
    if (!originalFile.existsSync()) {
      throw FileSystemException('Original image not found', originalPath);
    }

    // 原图解码 → 缩放 → 编码 → 写入磁盘
    logDebug('Thumbnail', 'Generating: ${p.basename(originalPath)} (${size}px)');
    final rawBytes = await originalFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(
      rawBytes,
      targetWidth: size,
      targetHeight: size,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;

    // 写入 PNG 缩略图
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('Failed to encode thumbnail for $originalPath');
    }

    final hash = sha256.convert(originalPath.codeUnits).toString();
    final subDir = hash.substring(0, 2);
    await _ensureSubDir(subDir);
    await File(targetPath).writeAsBytes(byteData.buffer.asUint8List());

    image.dispose();
    logDebug('Thumbnail', 'Saved: ${p.basename(targetPath)}');
    return targetPath;
  }

  /// 解码缩略图为 ui.Image 并放入内存缓存
  Future<ui.Image> loadThumbnail(String originalPath, {int size = 300}) async {
    final cacheKey = '$originalPath::$size';

    // L1: 内存
    final cached = _memoryCache.get(cacheKey);
    if (cached != null) return cached;

    // L2+L3: 磁盘 / 原图生成
    final diskPath = await ensureThumbnail(originalPath, size: size);
    final bytes = await File(diskPath).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    _memoryCache.put(cacheKey, image);
    return image;
  }

  /// 删除原图对应的所有缩略图缓存
  Future<void> deleteThumbnails(String originalPath) async {
    for (final size in [300, 800]) {
      final targetPath = thumbPath(originalPath, size: size);
      final file = File(targetPath);
      if (file.existsSync()) {
        await file.delete();
      }
    }
    // 同时清理内存缓存
    for (final size in [300, 800]) {
      _memoryCache.get('$originalPath::$size')?.dispose();
    }
  }

  /// 磁盘缓存按 LRU 淘汰（超出上限时清理最旧文件）
  Future<int> evictDiskCache({int maxSizeMB = 2048}) async {
    final dir = Directory(_cacheDir);
    if (!dir.existsSync()) return 0;

    final files = <_FileEntry>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final stat = entity.statSync();
        files.add(_FileEntry(entity, stat.size, stat.accessed));
      }
    }

    var totalSize = files.fold<int>(0, (s, f) => s + f.size);
    final maxBytes = maxSizeMB * 1024 * 1024;
    var removed = 0;

    // 按最后访问时间升序排列，优先删最旧的
    files.sort((a, b) => a.accessed.compareTo(b.accessed));

    for (final entry in files) {
      if (totalSize <= maxBytes) break;
      entry.file.deleteSync();
      totalSize -= entry.size;
      removed++;
    }

    return removed;
  }

  /// 清空全部内存缓存（GPU 纹理）
  void clearMemoryCache() {
    _memoryCache.clear();
  }
}

class _FileEntry {
  final File file;
  final int size;
  final DateTime accessed;
  _FileEntry(this.file, this.size, this.accessed);
}
