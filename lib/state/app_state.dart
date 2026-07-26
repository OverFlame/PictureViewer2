import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/image_dao.dart';
import '../db/tag_dao.dart';
import '../db/folder_dao.dart';
import '../services/import_service.dart';
import '../services/settings_service.dart';
import '../services/thumbnail_cache.dart';
import '../utils/log_util.dart';

/// 标签筛选规则
class TagFilter {
  final List<int> andTagIds;
  final List<int> orTagIds;
  final List<int> notTagIds;

  const TagFilter({
    this.andTagIds = const [],
    this.orTagIds = const [],
    this.notTagIds = const [],
  });

  bool get active =>
      andTagIds.isNotEmpty || orTagIds.isNotEmpty || notTagIds.isNotEmpty;
}

class AppState extends ChangeNotifier {
  // ── 图片列表 ──
  List<ImageItem> _images = [];
  List<ImageItem> get images => _images;
  int _totalCount = 0;
  int get totalCount => _totalCount;
  bool _loading = false;
  bool get loading => _loading;

  // ── 选中 ──
  int? _selectedId;
  int? get selectedId => _selectedId;
  ImageItem? get selectedImage =>
      _selectedId == null
          ? null
          : _images.cast<ImageItem?>().firstWhere(
                (i) => i?.id == _selectedId,
                orElse: () => null,
              );

  // ── 搜索 ──
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // ── 标签筛选 ──
  TagFilter _tagFilter = const TagFilter();
  TagFilter get tagFilter => _tagFilter;
  Set<int> get activeTagIds =>
      {..._tagFilter.andTagIds, ..._tagFilter.orTagIds, ..._tagFilter.notTagIds};

  // ── 标签缓存 ──
  List<Tag> _allTags = [];
  List<Tag> get allTags => _allTags;
  final Map<int, List<Tag>> _imageTags = {};

  // ── 导入状态 ──
  bool _importing = false;
  bool get importing => _importing;
  double _importProgress = 0;
  double get importProgress => _importProgress;

  // ── 文件夹 ──
  List<VirtualFolder> _folders = [];
  List<VirtualFolder> get folders => _folders;

  // ── 设置 ──
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  int _gridColumns = 5;
  int get gridColumns => _gridColumns;
  int _cacheSizeMB = 2048;
  int get cacheSizeMB => _cacheSizeMB;

  // ── 全屏查看器 ──
  List<ImageItem> _viewerImages = [];
  List<ImageItem> get viewerImages => _viewerImages;
  int _viewerIndex = 0;
  int get viewerIndex => _viewerIndex;
  bool _showViewer = false;
  bool get showViewer => _showViewer;

  ImageItem? get viewerImage =>
      _viewerIndex >= 0 && _viewerIndex < _viewerImages.length
          ? _viewerImages[_viewerIndex]
          : null;

  /// 打开查看器 — 传入可导航的图片列表和起始索引
  void openViewer(List<ImageItem> images, int startIndex) {
    logInfo('AppState',
        'openViewer: ${images.length} images, start=$startIndex');
    _viewerImages = List.from(images);
    _viewerIndex = startIndex.clamp(0, _viewerImages.length - 1);
    _showViewer = true;
    notifyListeners();
  }

  /// 关闭查看器
  void closeViewer() {
    logInfo('AppState', 'closeViewer');
    _showViewer = false;
    _viewerImages = [];
    _viewerIndex = 0;
    notifyListeners();
  }

  /// 查看器中导航（方向：-1=上一张, 1=下一张）
  void navigateViewer(int direction) {
    final newIndex = _viewerIndex + direction;
    if (newIndex >= 0 && newIndex < _viewerImages.length) {
      _viewerIndex = newIndex;
      logDebug('AppState',
          'navigateViewer: ${_viewerIndex + 1}/${_viewerImages.length}');
      notifyListeners();
    }
  }

  // ═══════════════ 便捷访问 ═══════════════
  TagDao get _tagDao => TagDao(DatabaseManager.instance.db);
  ImageDao get _imageDao => ImageDao(DatabaseManager.instance.db);
  FolderDao get _folderDao => FolderDao(DatabaseManager.instance.db);

  // ═══════════════ 生命周期 ═══════════════

  AppState() {
    _init();
  }

  Future<void> _init() async {
    logInfo('AppState', 'Initializing (settings + tags + folders + refresh)');
    await loadSettings();
    await loadTags();
    await loadFolders();
    await refresh();
    logInfo('AppState', 'Initialized OK');
  }

  // ═══════════════ 图片加载 ═══════════════

  Future<void> refresh() async {
    logInfo('AppState', 'refresh() — clearing cache, reloading page 0');
    _imageTags.clear();
    _images.clear();
    _selectedId = null;
    notifyListeners();
    await _loadPage(offset: 0);
  }

  Future<void> _loadPage({int offset = 0, bool append = false}) async {
    _loading = true;
    notifyListeners();
    try {
      Set<int>? filteredIds;
      if (_tagFilter.active) {
        logInfo('AppState',
            'Loading page with tag filter: AND=${_tagFilter.andTagIds.length} OR=${_tagFilter.orTagIds.length} NOT=${_tagFilter.notTagIds.length}');
        filteredIds = await _tagDao.getImageIdsByTags(
          andTagIds: _tagFilter.andTagIds,
          orTagIds: _tagFilter.orTagIds,
          notTagIds: _tagFilter.notTagIds,
        );
        if (filteredIds.isEmpty) {
          logInfo('AppState', 'Tag filter returned 0 images');
          _totalCount = 0;
          _images = [];
          return;
        }
        logInfo('AppState', 'Tag filter matched ${filteredIds.length} images');
      }

      if (filteredIds != null) {
        final page = await _imageDao.queryByIds(
          filteredIds,
          offset: offset,
          limit: 100,
          search: _searchQuery.isEmpty ? null : _searchQuery,
        );
        _totalCount = await _imageDao.count(idFilter: filteredIds);
        _images = append ? [..._images, ...page] : page;
      } else {
        final page = await _imageDao.queryPage(
          offset: offset,
          limit: 100,
          search: _searchQuery.isEmpty ? null : _searchQuery,
        );
        _totalCount = await _imageDao.count();
        _images = append ? [..._images, ...page] : page;
      }
      logInfo('AppState',
          'Page loaded: ${_images.length}/$_totalCount (offset=$offset, append=$append)');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _images.length >= _totalCount) return;
    logDebug('AppState', 'loadMore (${_images.length}/$_totalCount)');
    await _loadPage(offset: _images.length, append: true);
  }

  void setSearchQuery(String q) {
    logInfo('AppState', 'Search query changed: "${q.length > 30 ? '${q.substring(0, 30)}...' : q}"');
    _searchQuery = q;
    refresh();
  }

  void selectImage(int? id) {
    logDebug('AppState', 'selectImage id=$id');
    _selectedId = id;
    notifyListeners();
  }

  // ═══════════════ 标签操作 ═══════════════

  Future<void> loadTags() async {
    _allTags = await _tagDao.getAll();
    logDebug('AppState', 'loadTags: ${_allTags.length} tags');
    notifyListeners();
  }

  Future<List<Tag>> getImageTags(int imageId) async {
    if (_imageTags.containsKey(imageId)) {
      return _imageTags[imageId]!;
    }
    final tags = await _tagDao.getTagsForImage(imageId);
    _imageTags[imageId] = tags;
    return tags;
  }

  Future<void> toggleTagOnSelected(Tag tag) async {
    final imageId = _selectedId;
    if (imageId == null) return;
    final current =
        _imageTags[imageId] ?? await _tagDao.getTagsForImage(imageId);
    final has = current.any((t) => t.id == tag.id);

    if (has) {
      logInfo('AppState', 'Removing tag "${tag}" from image $imageId');
      await _tagDao.removeTagFromImage(imageId, tag.id!);
      current.removeWhere((t) => t.id == tag.id);
    } else {
      logInfo('AppState', 'Adding tag "${tag}" to image $imageId');
      await _tagDao.addTagToImage(imageId, tag.id!);
      current.add(tag);
    }
    _imageTags[imageId] = current;
    notifyListeners();
  }

  Future<Tag> createTag(String name,
      {String namespace = '', String color = '#cba6f7'}) async {
    // 在已加载的标签中查找
    final match = _allTags.where(
        (t) => t.name.toLowerCase() == name.toLowerCase() &&
                t.namespace == (namespace.isEmpty ? 'general' : namespace));
    if (match.isNotEmpty) return match.first;

    logInfo('AppState', 'Creating tag: "$name" (ns=${namespace.isEmpty ? "general" : namespace})');
    final tag = await _tagDao.insert(Tag(
      name: name,
      namespace: namespace.isEmpty ? 'general' : namespace,
      color: color,
    ));
    await loadTags();
    return tag;
  }

  Future<void> deleteTag(int tagId) async {
    logInfo('AppState', 'Deleting tag id=$tagId');
    await _tagDao.delete(tagId);
    _imageTags.clear();
    _removeFromFilter(tagId);
    await loadTags();
  }

  void _removeFromFilter(int tagId) {
    _tagFilter = TagFilter(
      andTagIds: _tagFilter.andTagIds.where((id) => id != tagId).toList(),
      orTagIds: _tagFilter.orTagIds.where((id) => id != tagId).toList(),
      notTagIds: _tagFilter.notTagIds.where((id) => id != tagId).toList(),
    );
  }

  // ── 标签筛选切换 ──

  void toggleAndFilter(int tagId) {
    final list = List<int>.from(_tagFilter.andTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    final orIds = _tagFilter.orTagIds.where((id) => id != tagId).toList();
    _tagFilter = TagFilter(
      andTagIds: list, orTagIds: orIds, notTagIds: _tagFilter.notTagIds);
    logInfo('AppState', 'Tag AND filter: $list');
    refresh();
  }

  void toggleOrFilter(int tagId) {
    final list = List<int>.from(_tagFilter.orTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    final andIds = _tagFilter.andTagIds.where((id) => id != tagId).toList();
    _tagFilter = TagFilter(
      andTagIds: andIds, orTagIds: list, notTagIds: _tagFilter.notTagIds);
    logInfo('AppState', 'Tag OR filter: $list');
    refresh();
  }

  void toggleNotFilter(int tagId) {
    final list = List<int>.from(_tagFilter.notTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    final andIds = _tagFilter.andTagIds.where((id) => id != tagId).toList();
    final orIds = _tagFilter.orTagIds.where((id) => id != tagId).toList();
    _tagFilter = TagFilter(
      andTagIds: andIds, orTagIds: orIds, notTagIds: list);
    logInfo('AppState', 'Tag NOT filter: $list');
    refresh();
  }

  void clearTagFilters() {
    logInfo('AppState', 'Clearing all tag filters');
    _tagFilter = const TagFilter();
    refresh();
  }

  // ═══════════════ 文件夹 ═══════════════

  // ═══════════════ 设置操作 ═══════════════

  /// 从 SharedPreferences 加载已保存的设置（初始化时调用）
  Future<void> loadSettings() async {
    final ss = SettingsService.instance;
    _themeMode = ss.themeMode;
    _gridColumns = ss.gridColumns;
    _cacheSizeMB = ss.cacheSizeMB;
    logInfo('AppState',
        'Settings loaded: theme=${_themeMode.name}, grid=$_gridColumns, cache=${_cacheSizeMB}MB');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await SettingsService.instance.setThemeMode(mode);
    logInfo('AppState', 'Theme set to ${mode.name}');
    notifyListeners();
  }

  Future<void> setGridColumns(int cols) async {
    _gridColumns = cols.clamp(2, 10);
    await SettingsService.instance.setGridColumns(_gridColumns);
    notifyListeners();
  }

  Future<void> setCacheSizeMB(int mb) async {
    _cacheSizeMB = mb.clamp(256, 8192);
    await SettingsService.instance.setCacheSizeMB(_cacheSizeMB);
    notifyListeners();
  }

  // ═══════════════ 导出 / 分享 ═══════════════

  /// 拷贝当前选中图片到指定目录
  Future<String?> copySelectedImageTo(String destDir) async {
    final img = selectedImage;
    if (img == null) return null;
    final src = io.File(img.path);
    if (!await src.exists()) return null;

    final name = img.filename;
    final destPath = '$destDir${io.Platform.pathSeparator}$name';
    final dest = io.File(destPath);

    // 如果存在同名文件，自动加序号
    int counter = 1;
    String finalPath = destPath;
    while (await dest.exists()) {
      final dot = name.lastIndexOf('.');
      final base = dot > 0 ? name.substring(0, dot) : name;
      final ext = dot > 0 ? name.substring(dot) : '';
      finalPath = '$destDir${io.Platform.pathSeparator}${base}_($counter)$ext';
      counter++;
    }

    await src.copy(finalPath);
    logInfo('AppState', 'Copied to $finalPath');
    return finalPath;
  }

  /// 拷贝当前选中图片到系统剪贴板（Windows）
  Future<void> copyImageToClipboard() async {
    final img = selectedImage;
    if (img == null) return;
    final file = io.File(img.path);
    if (!await file.exists()) return;
    // 通过文件路径传递，具体剪贴板操作在 widget 层用 platform channel 实现
    logInfo('AppState', 'Copy image to clipboard requested: ${img.path}');
  }

  // ═══════════════ 文件夹 ═══════════════

  Future<void> loadFolders() async {
    _folders = await _folderDao.listRoot();
    logDebug('AppState', 'loadFolders: ${_folders.length} folders');
    notifyListeners();
  }

  Future<void> importDirectory(String dirPath) async {
    logInfo('AppState', 'importDirectory: $dirPath');
    await importPaths([dirPath]);
  }

  Future<void> importPaths(List<String> paths) async {
    logInfo('AppState', 'importPaths: ${paths.length} path(s)');
    _importing = true;
    _importProgress = 0;
    notifyListeners();

    try {
      final importService = ImportService.fromDB();
      final stream = importService.importPaths(paths);

      await for (final progress in stream) {
        _importProgress = progress.percent;
        notifyListeners();
      }
      logInfo('AppState', 'Import complete');

      unawaited(_generateThumbnailsForPaths(paths));
    } catch (e) {
      logError('AppState', 'Import failed', e.toString());
    } finally {
      _importing = false;
      _importProgress = 0;
      notifyListeners();
      await loadFolders();
      await refresh();
    }
  }

  Future<void> _generateThumbnailsForPaths(List<String> paths) async {
    // 对于目录，按目录前缀查询；对于文件路径，直接生成缩略图
    final thumbnailService = ThumbnailService.instance;
    for (final path in paths) {
      final stat = io.FileSystemEntity.typeSync(path);
      if (stat == io.FileSystemEntityType.directory) {
        final images = await _imageDao.queryByDir(path);
        for (final img in images) {
          try {
            await thumbnailService.ensureThumbnail(img.path, size: 300);
          } catch (_) {}
        }
      } else if (stat == io.FileSystemEntityType.file) {
        try {
          await thumbnailService.ensureThumbnail(path, size: 300);
        } catch (_) {}
      }
    }
  }

  // ═══════════════ 缩略图 ──

  String thumbPath(String originalPath) {
    return ThumbnailService.instance.thumbPath(originalPath);
  }

  @override
  void dispose() {
    super.dispose();
  }
}
