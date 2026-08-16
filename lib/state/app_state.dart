import 'dart:async';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../db/database.dart';
import '../db/image_dao.dart';
import '../db/tag_dao.dart';
import '../db/folder_dao.dart';
import '../services/data_dir_service.dart';
import '../services/import_service.dart';
import '../services/settings_service.dart';
import '../services/thumbnail_cache.dart';
import '../utils/filter_expression.dart';
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

  // ── 选中（单选 + 多选） ──
  int? _selectedId;
  int? get selectedId => _selectedId;
  ImageItem? get selectedImage =>
      _selectedId == null
          ? null
          : _images.cast<ImageItem?>().firstWhere(
                (i) => i?.id == _selectedId,
                orElse: () => null,
              );
  final Set<int> _selectedIds = {};
  Set<int> get selectedIds => _selectedIds;
  bool isSelected(int id) => _selectedIds.contains(id);
  int? _anchorId;

  // ── 搜索 ──
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  // ── 标签筛选 ──
  TagFilter _tagFilter = const TagFilter();
  TagFilter get tagFilter => _tagFilter;
  Set<int> get activeTagIds =>
      {..._tagFilter.andTagIds, ..._tagFilter.orTagIds, ..._tagFilter.notTagIds};

  // ── 高级筛选表达式（与标签筛选互斥，激活后替换之） ──
  String _advancedFilter = '';
  String get advancedFilter => _advancedFilter;
  bool get hasAdvancedFilter => _advancedFilter.trim().isNotEmpty;

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

  // ── 文件夹浏览（资源管理器式） ──
  int? _currentFolderId;
  int? get currentFolderId => _currentFolderId;
  VirtualFolder? _currentFolder;
  VirtualFolder? get currentFolder => _currentFolder;
  String? _currentFolderPath;
  String? get currentFolderPath => _currentFolderPath;
  List<VirtualFolder> _breadcrumb = [];
  List<VirtualFolder> get breadcrumb => _breadcrumb;
  int _folderVersion = 0;
  int get folderVersion => _folderVersion;

  // ── 中间栏文件树（子文件夹 + 直接图片） ──
  List<VirtualFolder> _centerFolders = [];
  List<VirtualFolder> get centerFolders => _centerFolders;

  // ── 设置 ──
  ThemeMode _themeMode = ThemeMode.dark;
  ThemeMode get themeMode => _themeMode;
  int _gridColumns = 5;
  int get gridColumns => _gridColumns;
  int _cacheSizeMB = 2048;
  int get cacheSizeMB => _cacheSizeMB;

  // ── 排序 / 视图 ──
  String _sortKey = 'added_at';
  String get sortKey => _sortKey;
  bool _sortDescending = true;
  bool get sortDescending => _sortDescending;
  String _viewMode = 'grid';
  String get viewMode => _viewMode;

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
    _selectedIds.clear();
    _anchorId = null;
    notifyListeners();
    await _loadCenter();
  }

  /// 加载中间栏内容（资源管理器式：子文件夹 + 直接图片；搜索时扁平）。
  Future<void> _loadCenter() async {
    _loading = true;
    notifyListeners();
    try {
      final search = _searchQuery.trim();
      final filterActive = hasAdvancedFilter || _tagFilter.active;

      // 搜索：扁平结果（匹配文件名或别名）
      if (search.isNotEmpty) {
        _centerFolders = [];
        var list = await _imageDao.searchByName(search);
        if (filterActive) {
          final ids = await _computeMatchingIds();
          list = list.where((i) => ids.contains(i.id)).toList();
        }
        _images = _sortImagesList(list);
        _totalCount = _images.length;
        logInfo('AppState', 'Search "$search": ${_images.length} results');
        return;
      }

      // 文件夹 / 根：子文件夹 + 直接图片
      List<VirtualFolder> folders;
      List<ImageItem> images;
      if (_currentFolderId != null) {
        folders = await _folderDao.listChildren(_currentFolderId!);
        final folderPath = _currentFolderPath;
        images = (folderPath == null || folderPath.isEmpty)
            ? <ImageItem>[]
            : await _imageDao.queryDirectInDir(folderPath, limit: 100000);
      } else {
        folders = await _folderDao.listRoot();
        images = <ImageItem>[];
      }

      if (filterActive) {
        final ids = await _computeMatchingIds();
        images = images.where((i) => ids.contains(i.id)).toList();
        folders = await _filterFolders(folders, ids);
      }

      _centerFolders = _sortFolders(folders);
      _images = _sortImagesList(images);
      _totalCount = _images.length;
      logInfo('AppState',
          'Center loaded: ${_centerFolders.length} folders, ${_images.length} images');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<Set<int>> _computeMatchingIds() async {
    if (hasAdvancedFilter) {
      return _tagDao.getImageIdsByExpression(_advancedFilter, _allTags);
    }
    return _tagDao.getImageIdsByTags(
      andTagIds: _tagFilter.andTagIds,
      orTagIds: _tagFilter.orTagIds,
      notTagIds: _tagFilter.notTagIds,
    );
  }

  /// 过滤子文件夹：保留「递归包含匹配图片」或「直接持有匹配标签」的文件夹
  Future<List<VirtualFolder>> _filterFolders(
      List<VirtualFolder> folders, Set<int> matchingIds) async {
    if (folders.isEmpty) return [];
    final matchingPaths =
        matchingIds.isEmpty ? <String>[] : await _imageDao.pathsByIds(matchingIds);

    // 简单筛选时，文件夹自身持有的标签也参与匹配（高级表达式仅按图片递归判断）
    Map<int, List<Tag>> folderTags = {};
    if (!hasAdvancedFilter && _tagFilter.active) {
      folderTags =
          await _tagDao.getTagsForFolders(folders.map((f) => f.id!).toList());
    }

    final result = <VirtualFolder>[];
    for (final f in folders) {
      final paths = await _folderDao.getPaths(f.id!);
      final containsImage = paths.any(
          (p) => matchingPaths.any((mp) => _isUnderPath(mp, p.path)));
      if (containsImage) {
        result.add(f);
        continue;
      }
      if (!hasAdvancedFilter && _tagFilter.active) {
        final tags = folderTags[f.id] ?? const <Tag>[];
        if (_folderTagsMatch(tags)) result.add(f);
      }
    }
    return result;
  }

  /// 文件夹直接持有的标签是否满足当前简单筛选（AND/OR/NOT 语义）
  bool _folderTagsMatch(List<Tag> tags) {
    final ids = tags.map((t) => t.id).whereType<int>().toSet();
    if (_tagFilter.andTagIds.any((id) => !ids.contains(id))) return false;
    if (_tagFilter.orTagIds.isNotEmpty &&
        !_tagFilter.orTagIds.any((id) => ids.contains(id))) {
      return false;
    }
    if (_tagFilter.notTagIds.any((id) => ids.contains(id))) return false;
    return true;
  }

  bool _isUnderPath(String path, String dir) {
    final a = path.toLowerCase();
    var b = dir.toLowerCase();
    if (b.endsWith('\\') || b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (a == b) return false;
    return a.startsWith('$b\\') || a.startsWith('$b/');
  }

  List<VirtualFolder> _sortFolders(List<VirtualFolder> list) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  List<ImageItem> _sortImagesList(List<ImageItem> list) {
    final dir = _sortDescending ? -1 : 1;
    list.sort((a, b) {
      int cmp;
      switch (_sortKey) {
        case 'filename':
          cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
          break;
        case 'alias':
          cmp = (a.alias ?? '')
              .toLowerCase()
              .compareTo((b.alias ?? '').toLowerCase());
          break;
        case 'file_size':
          cmp = (a.fileSize ?? 0).compareTo(b.fileSize ?? 0);
          break;
        case 'file_mtime':
          cmp = (a.fileMtime ?? 0).compareTo(b.fileMtime ?? 0);
          break;
        default:
          cmp = a.addedAt.compareTo(b.addedAt);
          break;
      }
      if (cmp == 0) {
        cmp = a.filename.toLowerCase().compareTo(b.filename.toLowerCase());
      }
      return cmp * dir;
    });
    return list;
  }

  void setSearchQuery(String q) {
    logInfo('AppState', 'Search query changed: "${q.length > 30 ? '${q.substring(0, 30)}...' : q}"');
    _searchQuery = q;
    refresh();
  }

  /// 单选（普通点击）
  void selectImage(int? id) {
    logDebug('AppState', 'selectImage id=$id');
    _selectedId = id;
    _selectedIds
      ..clear()
      ..addAll({if (id != null) id});
    _anchorId = id;
    notifyListeners();
  }

  /// 切换多选（Ctrl+点击）
  void toggleSelect(int id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    _selectedId = id;
    _anchorId = id;
    notifyListeners();
  }

  /// 区间多选（Shift+点击，按当前列表顺序从锚点到目标）
  void rangeSelect(int id) {
    final list = _images;
    final anchorIdx =
        _anchorId == null ? -1 : list.indexWhere((i) => i.id == _anchorId);
    final curIdx = list.indexWhere((i) => i.id == id);
    if (anchorIdx < 0 || curIdx < 0) {
      toggleSelect(id);
      return;
    }
    final lo = anchorIdx < curIdx ? anchorIdx : curIdx;
    final hi = anchorIdx < curIdx ? curIdx : anchorIdx;
    for (final img in list.sublist(lo, hi + 1)) {
      if (img.id != null) _selectedIds.add(img.id!);
    }
    _selectedId = id;
    notifyListeners();
  }

  void clearSelection() {
    _selectedId = null;
    _selectedIds.clear();
    _anchorId = null;
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
    _advancedFilter = ''; // 与高级筛选互斥
    final list = List<int>.from(_tagFilter.andTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    // 同一标签互斥：从 OR / NOT 中移除，避免矛盾表达式
    final orIds = _tagFilter.orTagIds.where((id) => id != tagId).toList();
    final notIds = _tagFilter.notTagIds.where((id) => id != tagId).toList();
    _tagFilter = TagFilter(
      andTagIds: list, orTagIds: orIds, notTagIds: notIds);
    logInfo('AppState', 'Tag AND filter: $list');
    refresh();
  }

  void toggleOrFilter(int tagId) {
    _advancedFilter = ''; // 与高级筛选互斥
    final list = List<int>.from(_tagFilter.orTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    final andIds = _tagFilter.andTagIds.where((id) => id != tagId).toList();
    final notIds = _tagFilter.notTagIds.where((id) => id != tagId).toList();
    _tagFilter = TagFilter(
      andTagIds: andIds, orTagIds: list, notTagIds: notIds);
    logInfo('AppState', 'Tag OR filter: $list');
    refresh();
  }

  void toggleNotFilter(int tagId) {
    _advancedFilter = ''; // 与高级筛选互斥
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

  // ═══════════════ 高级筛选表达式 ═══════════════

  /// 应用高级筛选表达式（空字符串表示清除）。
  /// 语法错误抛出 [FilterExpressionException]；启用时替换简单标签筛选。
  Future<void> setAdvancedFilter(String expression) async {
    final expr = expression.trim();
    if (expr.isEmpty) {
      await clearAdvancedFilter();
      return;
    }
    FilterExpressionParser.parse(expr); // 仅做语法校验，标签名在查询时解析
    _advancedFilter = expr;
    _tagFilter = const TagFilter();
    logInfo('AppState', 'Advanced filter set: "$expr"');
    await SettingsService.instance.addExpression(expr); // 记录到历史缓存
    await refresh();
  }

  /// 清除高级筛选表达式
  Future<void> clearAdvancedFilter() async {
    if (!hasAdvancedFilter) return;
    _advancedFilter = '';
    logInfo('AppState', 'Advanced filter cleared');
    await refresh();
  }

  // ═══════════════ 文件夹 ═══════════════

  // ═══════════════ 设置操作 ═══════════════

  /// 从设置服务加载已保存的设置（初始化时调用）
  Future<void> loadSettings() async {
    final ss = SettingsService.instance;
    _themeMode = ss.themeMode;
    _gridColumns = ss.gridColumns;
    _cacheSizeMB = ss.cacheSizeMB;
    _sortKey = ss.sortKey;
    _sortDescending = ss.sortDescending;
    _viewMode = ss.viewMode;
    logInfo('AppState',
        'Settings loaded: theme=${_themeMode.name}, grid=$_gridColumns, cache=${_cacheSizeMB}MB, sort=$_sortKey/$_sortDescending, view=$_viewMode');
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

  // ── 排序 / 视图 ──

  Future<void> setSortKey(String key) async {
    _sortKey = key;
    notifyListeners(); // 先刷新 UI，持久化失败也不影响排序生效
    await SettingsService.instance.setSortKey(key);
    await refresh();
  }

  Future<void> setSortDescending(bool desc) async {
    _sortDescending = desc;
    notifyListeners();
    await SettingsService.instance.setSortDescending(desc);
    await refresh();
  }

  Future<void> setViewMode(String mode) async {
    _viewMode = mode == 'list' ? 'list' : 'grid';
    notifyListeners();
    await SettingsService.instance.setViewMode(_viewMode);
  }

  // ═══════════════ 图片别名 ═══════════════

  /// 设置/清除图片别名
  Future<void> setImageAlias(int id, String? alias) async {
    await _imageDao.setAlias(id, alias);
    final updated = await _imageDao.getById(id);
    if (updated != null) {
      _images = _images.map((i) => i.id == id ? updated : i).toList();
    }
    notifyListeners();
  }

  // ═══════════════ 批量标签 ═══════════════

  /// 为一批图片添加标签（幂等）
  Future<void> addTagsToImages(Iterable<int> imageIds, List<Tag> tags) async {
    for (final id in imageIds) {
      for (final tag in tags) {
        await _tagDao.addTagToImage(id, tag.id!);
      }
    }
    _imageTags.clear();
    notifyListeners();
  }

  /// 从一批图片移除标签
  Future<void> removeTagsFromImages(
      Iterable<int> imageIds, List<Tag> tags) async {
    for (final id in imageIds) {
      for (final tag in tags) {
        await _tagDao.removeTagFromImage(id, tag.id!);
      }
    }
    _imageTags.clear();
    notifyListeners();
  }

  /// 返回这批图片上已绑定的标签 id 集合（用于「移除标签」时过滤可选项）
  Future<Set<int>> getTagIdsOnImages(Iterable<int> imageIds) async {
    final ids = imageIds.toList();
    if (ids.isEmpty) return {};
    final map = await _tagDao.getTagsForImages(ids);
    final result = <int>{};
    for (final tags in map.values) {
      for (final t in tags) {
        if (t.id != null) result.add(t.id!);
      }
    }
    return result;
  }

  // ═══════════════ 文件夹标签 ═══════════════

  Future<List<Tag>> getFolderTags(int folderId) =>
      _tagDao.getTagsForFolder(folderId);

  /// 为文件夹添加标签；[recursive] 为真时递归同步到其所有图片及子文件夹图片。
  Future<void> addTagsToFolder(int folderId, List<Tag> tags,
      {bool recursive = false}) async {
    for (final tag in tags) {
      await _tagDao.addTagToFolder(folderId, tag.id!);
    }
    if (recursive) {
      final imageIds = await _collectFolderImageIds(folderId);
      await addTagsToImages(imageIds, tags);
    }
    _folderVersion++;
    notifyListeners();
  }

  /// 从文件夹移除标签；[recursive] 为真时递归同步移除到所有子文件夹与子图片。
  Future<void> removeTagsFromFolder(int folderId, List<Tag> tags,
      {bool recursive = false}) async {
    if (recursive) {
      final folderIds = await _collectDescendantFolderIds(folderId);
      for (final fid in folderIds) {
        for (final tag in tags) {
          await _tagDao.removeTagFromFolder(fid, tag.id!);
        }
      }
      final imageIds = await _collectFolderImageIds(folderId);
      await removeTagsFromImages(imageIds, tags);
    } else {
      for (final tag in tags) {
        await _tagDao.removeTagFromFolder(folderId, tag.id!);
      }
    }
    _folderVersion++;
    notifyListeners();
  }

  /// 收集文件夹及其所有子文件夹下的图片 id（按路径前缀）
  Future<Set<int>> _collectFolderImageIds(int folderId) async {
    final paths = <String>[];
    final queue = <int>[folderId];
    while (queue.isNotEmpty) {
      final fid = queue.removeAt(0);
      for (final fp in await _folderDao.getPaths(fid)) {
        paths.add(fp.path);
      }
      for (final c in await _folderDao.listChildren(fid)) {
        if (c.id != null) queue.add(c.id!);
      }
    }
    if (paths.isEmpty) return {};
    final images = await _imageDao.queryByDirs(paths);
    return images.map((i) => i.id).whereType<int>().toSet();
  }

  /// 收集文件夹及其所有后代文件夹的 id（用于递归移除文件夹标签）
  Future<Set<int>> _collectDescendantFolderIds(int folderId) async {
    final result = <int>{folderId};
    final queue = <int>[folderId];
    while (queue.isNotEmpty) {
      final fid = queue.removeAt(0);
      for (final c in await _folderDao.listChildren(fid)) {
        if (c.id != null && result.add(c.id!)) {
          queue.add(c.id!);
        }
      }
    }
    return result;
  }

  // ═══════════════ 数据目录迁移 ═══════════════

  Future<String> getDataDir() => DataDirService.instance.dataDir;

  /// 迁移数据目录到 [newDir]，随后重开数据库/缩略图并刷新。
  Future<void> migrateDataDir(String newDir) async {
    // 先关闭数据库，确保 WAL 合并后 pv2.db 完整一致
    await DatabaseManager.instance.close();
    await DataDirService.instance.migrateTo(newDir);
    await DatabaseManager.instance.init();
    await ThumbnailService.instance.init();
    await loadSettings();
    await loadTags();
    await loadFolders();
    await refresh();
  }

  // ═══════════════ 表达式历史缓存 ═══════════════

  List<String> get expressionHistory =>
      SettingsService.instance.expressionHistory;
  int get maxExprCacheCount => SettingsService.instance.maxExprCacheCount;

  Future<void> setMaxExprCacheCount(int count) =>
      SettingsService.instance.setMaxExprCacheCount(count);

  Future<void> clearExpressionHistory() =>
      SettingsService.instance.clearExpressionHistory();

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

  /// 加载某文件夹的直接子文件夹（树形懒加载）
  Future<List<VirtualFolder>> loadChildFolders(int parentId) async {
    return _folderDao.listChildren(parentId);
  }

  /// 加载所有文件夹（带 parent 关系，用于移动选择器等完整树场景）
  Future<List<VirtualFolder>> loadAllFolders() async {
    return _folderDao.listAll();
  }

  /// 进入文件夹（资源管理器式浏览）
  Future<void> enterFolder(int folderId) async {
    final folder = await _folderDao.getById(folderId);
    if (folder == null) return;
    logInfo('AppState', 'enterFolder: #$folderId "${folder.name}"');
    _currentFolderId = folderId;
    _currentFolder = folder;
    final paths = await _folderDao.getPaths(folderId);
    _currentFolderPath = paths.isEmpty ? null : paths.first.path;
    _breadcrumb = await _buildBreadcrumb(folder);
    await refresh();
  }

  /// 返回「全部图片」根视图
  Future<void> goRoot() async {
    logInfo('AppState', 'goRoot (all images)');
    _currentFolderId = null;
    _currentFolder = null;
    _currentFolderPath = null;
    _breadcrumb = [];
    await refresh();
  }

  /// 返回上一级文件夹
  Future<void> goUp() async {
    if (_breadcrumb.length <= 1) {
      await goRoot();
      return;
    }
    final parent = _breadcrumb[_breadcrumb.length - 2];
    await enterFolder(parent.id!);
  }

  Future<List<VirtualFolder>> _buildBreadcrumb(VirtualFolder folder) async {
    final chain = <VirtualFolder>[folder];
    var current = folder;
    while (current.parentId != null) {
      final parent = await _folderDao.getById(current.parentId!);
      if (parent == null) break;
      chain.insert(0, parent);
      current = parent;
    }
    return chain;
  }

  /// 新建文件夹（parentId 为空则在根级创建）
  Future<VirtualFolder> createFolder(String name, {int? parentId}) async {
    final folder = await _folderDao.create(name, parentId: parentId);
    logInfo('AppState', 'createFolder: "$name" parent=$parentId');
    await _reloadFolderTree();
    return folder;
  }

  Future<void> renameFolder(int id, String newName) async {
    await _folderDao.rename(id, newName);
    logInfo('AppState', 'renameFolder: #$id -> "$newName"');
    if (_currentFolderId == id) {
      _currentFolder = VirtualFolder(
          id: id, name: newName, parentId: _currentFolder?.parentId);
      _breadcrumb = _breadcrumb
          .map((f) => f.id == id
              ? VirtualFolder(id: f.id, name: newName, parentId: f.parentId)
              : f)
          .toList();
    }
    await _reloadFolderTree();
  }

  Future<void> deleteFolder(int id) async {
    await _folderDao.delete(id);
    logInfo('AppState', 'deleteFolder: #$id');
    if (_currentFolderId == id) {
      await goRoot();
    } else {
      await _reloadFolderTree();
    }
  }

  Future<void> moveFolder(int id, int? newParentId) async {
    await _folderDao.move(id, newParentId);
    logInfo('AppState', 'moveFolder: #$id -> parent=$newParentId');
    await _reloadFolderTree();
  }

  Future<void> _reloadFolderTree() async {
    _folderVersion++;
    await loadFolders();
    await refresh(); // 同步刷新中间栏，反映文件夹增删改
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
      _folderVersion++;
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
