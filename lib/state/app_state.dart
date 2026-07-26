import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../db/image_dao.dart';
import '../db/tag_dao.dart';
import '../db/folder_dao.dart';
import '../services/import_service.dart';
import '../services/thumbnail_cache.dart';

/// 应用全局状态
class AppState extends ChangeNotifier {
  // ---- 数据层 ----
  late final ImageDao imageDao;
  late final TagDao tagDao;
  late final FolderDao folderDao;
  late final ImportService importService;
  late final ThumbnailService thumbnailService;

  // ---- 图片列表 ----
  List<ImageItem> _images = [];
  List<ImageItem> get images => _images;
  int _totalCount = 0;
  int get totalCount => _totalCount;

  // ---- 加载状态 ----
  bool _loading = false;
  bool get loading => _loading;

  // ---- 导入状态 ----
  bool _importing = false;
  bool get importing => _importing;
  double _importProgress = 0;
  double get importProgress => _importProgress;
  String _importStatus = '';
  String get importStatus => _importStatus;

  // ---- 筛选 ----
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // ---- 选中 ----
  ImageItem? _selectedImage;
  ImageItem? get selectedImage => _selectedImage;

  AppState() {
    final db = DatabaseManager.instance.db;
    imageDao = ImageDao(db);
    tagDao = TagDao(db);
    folderDao = FolderDao(db);
    thumbnailService = ThumbnailService.instance;
    importService = ImportService(
      imageDao: imageDao,
      folderDao: folderDao,
      thumbnailService: thumbnailService,
    );

    // 启动时加载已有图片
    loadImages();
  }

  /// 加载图片列表（分页首屏）
  Future<void> loadImages() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();

    try {
      _totalCount = await imageDao.count();
      _images = await imageDao.queryPage(limit: 200);
    } catch (e) {
      debugPrint('loadImages error: $e');
    }

    _loading = false;
    notifyListeners();
  }

  /// 加载更多（滚动翻页）
  Future<void> loadMore() async {
    if (_loading || _images.length >= _totalCount) return;
    _loading = true;
    notifyListeners();

    try {
      final more = await imageDao.queryPage(
        offset: _images.length,
        limit: 100,
      );
      _images.addAll(more);
    } catch (e) {
      debugPrint('loadMore error: $e');
    }

    _loading = false;
    notifyListeners();
  }

  /// 选中图片
  void selectImage(ImageItem? image) {
    _selectedImage = image;
    notifyListeners();
  }

  /// 导入目录
  Future<void> importDirectory(String dirPath) async {
    if (_importing) return;
    _importing = true;
    _importProgress = 0;
    _importStatus = '正在扫描文件...';
    notifyListeners();

    try {
      await for (final p in importService.importDirectory(dirPath)) {
        _importProgress = p.percent;
        _importStatus = '正在索引 ${p.current}/${p.total}: ${p.currentFile}';
        notifyListeners();
      }

      _importStatus = '导入完成，重新加载...';
      notifyListeners();

      // 重新加载列表
      await loadImages();

      _importStatus = '完成';
      notifyListeners();
    } catch (e) {
      _importStatus = '导入出错: $e';
      notifyListeners();
    }

    _importing = false;
    notifyListeners();
  }

  /// 刷新（重新扫描）
  Future<void> refresh() async {
    await loadImages();
  }

  /// 获取缩略图（ui.Image），带三层缓存
  Future<dynamic> getThumbnail(String path) async {
    return thumbnailService.loadThumbnail(path);
  }

  /// 缩略图缓存路径
  String thumbPath(String path) => thumbnailService.thumbPath(path);

  /// 搜索
  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }
}
