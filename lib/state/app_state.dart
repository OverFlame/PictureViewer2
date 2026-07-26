import 'dart:async';
import 'package:flutter/foundation.dart';

import '../db/database.dart';
import '../db/image_dao.dart';
import '../db/tag_dao.dart';
import '../db/folder_dao.dart';
import '../services/import_service.dart';
import '../services/thumbnail_cache.dart';

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

  // ═══════════════ 便捷访问 ═══════════════
  TagDao get _tagDao => TagDao(DatabaseManager.instance.db);
  ImageDao get _imageDao => ImageDao(DatabaseManager.instance.db);
  FolderDao get _folderDao => FolderDao(DatabaseManager.instance.db);

  // ═══════════════ 生命周期 ═══════════════

  AppState() {
    _init();
  }

  Future<void> _init() async {
    await loadTags();
    await loadFolders();
    await refresh();
  }

  // ═══════════════ 图片加载 ═══════════════

  Future<void> refresh() async {
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
        filteredIds = await _tagDao.getImageIdsByTags(
          andTagIds: _tagFilter.andTagIds,
          orTagIds: _tagFilter.orTagIds,
          notTagIds: _tagFilter.notTagIds,
        );
        if (filteredIds.isEmpty) {
          _totalCount = 0;
          _images = [];
          return;
        }
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
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loading || _images.length >= _totalCount) return;
    await _loadPage(offset: _images.length, append: true);
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    refresh();
  }

  void selectImage(int? id) {
    _selectedId = id;
    notifyListeners();
  }

  // ═══════════════ 标签操作 ═══════════════

  Future<void> loadTags() async {
    _allTags = await _tagDao.getAll();
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
      await _tagDao.removeTagFromImage(imageId, tag.id!);
      current.removeWhere((t) => t.id == tag.id);
    } else {
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

    final tag = await _tagDao.insert(Tag(
      name: name,
      namespace: namespace.isEmpty ? 'general' : namespace,
      color: color,
    ));
    await loadTags();
    return tag;
  }

  Future<void> deleteTag(int tagId) async {
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
    refresh();
  }

  void toggleOrFilter(int tagId) {
    final list = List<int>.from(_tagFilter.orTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    final andIds = _tagFilter.andTagIds.where((id) => id != tagId).toList();
    _tagFilter = TagFilter(
      andTagIds: andIds, orTagIds: list, notTagIds: _tagFilter.notTagIds);
    refresh();
  }

  void toggleNotFilter(int tagId) {
    final list = List<int>.from(_tagFilter.notTagIds);
    list.contains(tagId) ? list.remove(tagId) : list.add(tagId);
    final andIds = _tagFilter.andTagIds.where((id) => id != tagId).toList();
    final orIds = _tagFilter.orTagIds.where((id) => id != tagId).toList();
    _tagFilter = TagFilter(
      andTagIds: andIds, orTagIds: orIds, notTagIds: list);
    refresh();
  }

  void clearTagFilters() {
    _tagFilter = const TagFilter();
    refresh();
  }

  // ═══════════════ 文件夹 ═══════════════

  Future<void> loadFolders() async {
    _folders = await _folderDao.listRoot();
    notifyListeners();
  }

  Future<void> importDirectory(String dirPath) async {
    _importing = true;
    _importProgress = 0;
    notifyListeners();

    try {
      final importService = ImportService.fromDB();
      final stream = importService.importDirectory(dirPath);

      await for (final progress in stream) {
        _importProgress = progress.percent;
        notifyListeners();
      }

      unawaited(_generateThumbnails(dirPath));
    } finally {
      _importing = false;
      _importProgress = 0;
      notifyListeners();
      await loadFolders();
      await refresh();
    }
  }

  Future<void> _generateThumbnails(String dirPath) async {
    final images = await _imageDao.queryByDir(dirPath);
    final thumbnailService = ThumbnailService.instance;
    for (final img in images) {
      try {
        await thumbnailService.ensureThumbnail(img.path, size: 300);
      } catch (_) {}
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
