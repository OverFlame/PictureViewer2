import 'package:sqflite/sqflite.dart';
import '../utils/log_util.dart';

/// 标签数据类
class Tag {
  final int? id;
  final String namespace;
  final String name;
  final String color;

  const Tag({
    this.id,
    this.namespace = 'general',
    required this.name,
    this.color = '#cba6f7',
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'namespace': namespace,
        'name': name,
        'color': color,
      };

  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
        id: map['id'] as int?,
        namespace: map['namespace'] as String? ?? 'general',
        name: map['name'] as String,
        color: map['color'] as String? ?? '#cba6f7',
      );

  @override
  bool operator ==(Object other) =>
      other is Tag &&
      other.namespace == namespace &&
      other.name == name;

  @override
  int get hashCode => Object.hash(namespace, name);

  @override
  String toString() =>
      namespace == 'general' ? name : '$namespace:$name';
}

/// 标签用于 UI 展示的聚合视图（含数量）
class TagCount {
  final Tag tag;
  final int imageCount;

  const TagCount({required this.tag, required this.imageCount});
}

/// 标签 DAO — CRUD + 多对多关联 + 聚合查询
class TagDao {
  final Database _db;

  TagDao(this._db);

  // ═══ CRUD ═══

  Future<Tag> insert(Tag tag) async {
    final id = await _db.insert('tags', tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    if (id > 0) {
      logInfo('TagDao', 'Inserted tag: id=$id name="${tag.name}"');
      return Tag(id: id, namespace: tag.namespace, name: tag.name);
    }

    // 冲突时查询已有 id
    final rows = await _db.query('tags',
        where: 'namespace = ? AND name = ?',
        whereArgs: [tag.namespace, tag.name]);
    final existing = Tag.fromMap(rows.first);
    logInfo('TagDao', 'Tag already exists: id=${existing.id} name="${existing.name}"');
    return existing;
  }

  Future<Tag?> getById(int id) async {
    final rows = await _db.query('tags', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Tag.fromMap(rows.first);
  }

  Future<Tag?> getByFullName(String namespace, String name) async {
    final rows = await _db.query('tags',
        where: 'namespace = ? AND name = ?',
        whereArgs: [namespace, name]);
    if (rows.isEmpty) return null;
    return Tag.fromMap(rows.first);
  }

  Future<int> update(Tag tag) async {
    if (tag.id == null) return 0;
    return _db.update('tags', tag.toMap(),
        where: 'id = ?', whereArgs: [tag.id]);
  }

  Future<int> delete(int id) async {
    final count = await _db.delete('tags', where: 'id = ?', whereArgs: [id]);
    logInfo('TagDao', 'Deleted tag id=$id (affected $count row(s))');
    return count;
  }

  /// 获取所有标签（简单列表，不带计数）
  Future<List<Tag>> getAll() async {
    final rows = await _db.query('tags', orderBy: 'namespace, name');
    return rows.map(Tag.fromMap).toList();
  }

  // ═══ 查询 ═══

  /// 所有标签（按 namespace + name 排序），可选带计数
  Future<List<TagCount>> listWithCount() async {
    final rows = await _db.rawQuery('''
      SELECT t.*, COUNT(it.image_id) as image_count
      FROM tags t
      LEFT JOIN image_tags it ON t.id = it.tag_id
      GROUP BY t.id
      ORDER BY t.namespace, t.name
    ''');
    return rows.map((r) => TagCount(
      tag: Tag.fromMap(r),
      imageCount: r['image_count'] as int,
    )).toList();
  }

  /// 某个 namespace 下的所有标签
  Future<List<Tag>> listByNamespace(String namespace) async {
    final rows = await _db.query('tags',
        where: 'namespace = ?',
        whereArgs: [namespace],
        orderBy: 'name');
    return rows.map(Tag.fromMap).toList();
  }

  /// 所有不重复的 namespace
  Future<List<String>> listNamespaces() async {
    final rows = await _db.rawQuery(
        'SELECT DISTINCT namespace FROM tags ORDER BY namespace');
    return rows.map((r) => r['namespace'] as String).toList();
  }

  /// 搜索标签（模糊匹配 name）
  Future<List<Tag>> search(String query) async {
    final rows = await _db.query('tags',
        where: 'name LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'name',
        limit: 50);
    return rows.map(Tag.fromMap).toList();
  }

  // ═══ 关联操作 ═══

  /// 为图片添加标签（幂等）
  Future<void> addTagToImage(int imageId, int tagId) async {
    await _db.insert('image_tags', {
      'image_id': imageId,
      'tag_id': tagId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 移除图片的某个标签
  Future<void> removeTagFromImage(int imageId, int tagId) async {
    await _db.delete('image_tags',
        where: 'image_id = ? AND tag_id = ?',
        whereArgs: [imageId, tagId]);
  }

  /// 批量设置图片标签（先删后插，事务包裹）
  Future<void> setImageTags(int imageId, List<int> tagIds) async {
    await _db.transaction((txn) async {
      await txn.delete('image_tags',
          where: 'image_id = ?', whereArgs: [imageId]);
      for (final tagId in tagIds) {
        await txn.insert('image_tags', {
          'image_id': imageId,
          'tag_id': tagId,
        });
      }
    });
  }

  /// 获取某图片的所有标签
  Future<List<Tag>> getTagsForImage(int imageId) async {
    final rows = await _db.rawQuery('''
      SELECT t.* FROM tags t
      INNER JOIN image_tags it ON t.id = it.tag_id
      WHERE it.image_id = ?
      ORDER BY t.namespace, t.name
    ''', [imageId]);
    return rows.map(Tag.fromMap).toList();
  }

  /// 获取带有指定标签的图片 ID（支持多标签 AND/OR/NOT）
  ///
  /// [andTagIds] — 必须同时拥有这些标签 (AND)
  /// [orTagIds]  — 至少拥有其中一个标签 (OR)
  /// [notTagIds] — 排除拥有这些标签的图片 (NOT)
  ///
  /// 组合：先 AND 取交集，再 OR 求并集，再 NOT 排除
  Future<Set<int>> getImageIdsByTags({
    List<int> andTagIds = const [],
    List<int> orTagIds = const [],
    List<int> notTagIds = const [],
  }) async {
    Set<int>? result;

    // 1) AND 交集
    if (andTagIds.isNotEmpty) {
      for (final tagId in andTagIds) {
        final rows = await _db.query('image_tags',
            columns: ['image_id'],
            where: 'tag_id = ?',
            whereArgs: [tagId]);
        final ids = rows.map((r) => r['image_id'] as int).toSet();
        result = result == null ? ids : result.intersection(ids);
        if (result.isEmpty) return {};
      }
    }

    // 2) OR 并集
    if (orTagIds.isNotEmpty) {
      final placeholders = orTagIds.map((_) => '?').join(',');
      final rows = await _db.query('image_tags',
          columns: ['DISTINCT image_id'],
          where: 'tag_id IN ($placeholders)',
          whereArgs: orTagIds);
      final ids = rows.map((r) => r['image_id'] as int).toSet();
      result = result == null ? ids : result.intersection(ids);
      if (result.isEmpty) return {};
    }

    // 无任何筛选 → 返回所有已关联标签的图片 (用 UNION 获取)
    if (result == null) {
      final rows = await _db.rawQuery('SELECT DISTINCT image_id FROM image_tags');
      result = rows.map((r) => r['image_id'] as int).toSet();
    }

    // 3) NOT 排除
    if (notTagIds.isNotEmpty) {
      final placeholders = notTagIds.map((_) => '?').join(',');
      final rows = await _db.query('image_tags',
          columns: ['DISTINCT image_id'],
          where: 'tag_id IN ($placeholders)',
          whereArgs: notTagIds);
      final excluded = rows.map((r) => r['image_id'] as int).toSet();
      result.removeAll(excluded);
    }

    return result;
  }

  /// 批量获取图片的标签（减少 N+1 查询）
  Future<Map<int, List<Tag>>> getTagsForImages(List<int> imageIds) async {
    if (imageIds.isEmpty) return {};
    final placeholders = imageIds.map((_) => '?').join(',');
    final rows = await _db.rawQuery('''
      SELECT it.image_id, t.*
      FROM image_tags it
      INNER JOIN tags t ON t.id = it.tag_id
      WHERE it.image_id IN ($placeholders)
      ORDER BY t.namespace, t.name
    ''', imageIds);

    final map = <int, List<Tag>>{};
    for (final row in rows) {
      final imageId = row['image_id'] as int;
      map.putIfAbsent(imageId, () => []).add(Tag.fromMap(row));
    }
    return map;
  }

  // ═══ 清理 ═══

  /// 删除无图片引用的孤立标签
  Future<int> deleteOrphanTags() async {
    final count = await _db.delete('tags',
        where: '''
      id NOT IN (SELECT DISTINCT tag_id FROM image_tags)
    ''');
    logInfo('TagDao', 'deleteOrphanTags: removed $count orphan(s)');
    return count;
  }
}
