import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import '../utils/log_util.dart';
import 'data_dir_service.dart';

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

  /// 按条件移除（原图内容变化或删除时用），移除时释放 GPU 纹理
  void removeWhere(bool Function(String key) test) {
    for (final key in _map.keys.where(test).toList()) {
      _map.remove(key)?.dispose();
    }
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

  /// 缓存根目录路径
  String get cacheDir => _cacheDir;

  /// [cacheDir] 只给测试用：跳过 DataDirService 直接指定缓存根目录
  Future<void> init({String? cacheDir}) async {
    // 缩略图随数据目录走（可迁移）
    _cacheDir =
        cacheDir ?? p.join(await DataDirService.instance.dataDir, 'thumbnails');
    await Directory(_cacheDir).create(recursive: true);
    logInfo('Thumbnail', 'Cache dir: $_cacheDir');
  }

  /// 获取缩略图路径（不生成，仅返回路径）。
  ///
  /// 文件名里带源文件的 mtime：源文件内容一变，缩略图就落到新的文件名上，
  /// 旧缩略图不会被命中。不带 mtime 的话，同一个路径换了内容仍会读到旧缩略图，
  /// 而 [Image.file] 的缓存键只有路径，界面也就跟着一直显示旧图。
  ///
  /// [mtimeMs] 只给「调用方已经 stat 过」的场景用，缺省时自己 stat。
  String thumbPath(String originalPath, {int size = 300, int? mtimeMs}) {
    final stamp = mtimeMs ?? _mtimeMs(originalPath);
    final hash = _hashKey(originalPath);
    final subDir = hash.substring(0, 2);
    return p.join(_cacheDir, subDir, '$hash.$stamp.t$size');
  }

  /// 原图路径的哈希（不含 mtime，用于按前缀清理）
  ///
  /// 用 utf8 编码而不是 `codeUnits`：`codeUnits` 是 UTF-16 码元，值可以超过
  /// 255，塞进 typed_data 时高位被截掉，只在码元高位上不同的两条路径会算出
  /// 同一个文件名，表现为缩略图串图。
  String _hashKey(String originalPath) =>
      sha256.convert(utf8.encode(originalPath)).toString();

  /// 源文件的 mtime（毫秒）；文件不存在返回 0
  int _mtimeMs(String originalPath) {
    final f = File(originalPath);
    if (!f.existsSync()) return 0;
    return f.statSync().modified.millisecondsSinceEpoch;
  }

  /// 缩略图缓存目录下，该原图所属的子目录
  Directory _subDirOf(String originalPath) =>
      Directory(p.join(_cacheDir, _hashKey(originalPath).substring(0, 2)));

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

    final hash = _hashKey(originalPath);
    final subDir = hash.substring(0, 2);
    await _ensureSubDir(subDir);
    await File(targetPath).writeAsBytes(byteData.buffer.asUint8List());

    image.dispose();
    // 清掉同一原图同一尺寸的旧时间戳版本，否则每换一次内容就留一份孤儿
    await _removeOtherVariants(hash, size, keepName: p.basename(targetPath));
    logDebug('Thumbnail', 'Saved: ${p.basename(targetPath)}');
    return targetPath;
  }

  /// 删除 [_subDirOf] 里同一原图、同一尺寸、非 [keepName] 的历史缩略图
  Future<void> _removeOtherVariants(String hash, int size,
      {required String keepName}) async {
    final dir = Directory(p.join(_cacheDir, hash.substring(0, 2)));
    if (!dir.existsSync()) return;
    final suffix = '.t$size';
    // 先收名字再删，避免边遍历目录流边删文件
    final victims = <File>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == keepName || !name.startsWith('$hash.')) continue;
      if (!name.endsWith(suffix)) continue;
      victims.add(entity);
    }
    for (final file in victims) {
      try {
        await file.delete();
      } catch (e) {
        logDebug('Thumbnail', 'Old thumbnail not removed: ${file.path} ($e)');
      }
    }
  }

  /// 解码缩略图为 ui.Image 并放入内存缓存
  Future<ui.Image> loadThumbnail(String originalPath, {int size = 300}) async {
    // 内存键也要带 mtime，不然原图换了内容还是拿到旧的 ui.Image
    final cacheKey = '$originalPath::$size::${_mtimeMs(originalPath)}';

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
  ///
  /// 文件名带 mtime，删的时候算不出当时的时间戳，所以按哈希前缀扫子目录。
  /// 原图已经删掉的情况也走这条路（那种情况下 stat 不出 mtime）。
  Future<void> deleteThumbnails(String originalPath) async {
    final hash = _hashKey(originalPath);
    final dir = _subDirOf(originalPath);
    if (dir.existsSync()) {
      // 先收名字再删，避免边遍历目录流边删文件
      final victims = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && p.basename(entity.path).startsWith('$hash.')) {
          victims.add(entity);
        }
      }
      for (final file in victims) {
        await file.delete();
      }
    }
    // 同时清理内存缓存（键里带 mtime，只能按前缀删）
    _memoryCache.removeWhere((key) => key.startsWith('$originalPath::'));
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
