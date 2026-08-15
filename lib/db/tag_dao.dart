import 'package:sqflite/sqflite.dart';
import '../utils/filter_expression.dart';
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

  /// 获取满足标签逻辑表达式的图片 ID（单条 SQL 完成）。
  ///
  /// 语义（各条件之间为「与」关系）：
  ///   AND 组：必须同时拥有全部标签（交集）
  ///   OR  组：至少拥有其中一个标签（并集）
  ///   NOT 组：不得拥有其中任意标签（排除）
  ///
  /// 无任何约束时返回全部图片（含未打标签的图片），保证纯 NOT 筛选正确。
  Future<Set<int>> getImageIdsByTags({
    List<int> andTagIds = const [],
    List<int> orTagIds = const [],
    List<int> notTagIds = const [],
  }) async {
    final and = andTagIds.toSet();
    final or = orTagIds.toSet();
    final not = notTagIds.toSet();

    if (and.isEmpty && or.isEmpty && not.isEmpty) {
      final rows = await _db.query('images', columns: ['id']);
      return rows.map((r) => r['id'] as int).toSet();
    }

    final conds = <String>[];
    final args = <Object?>[];

    // AND：必须同时拥有全部（HAVING COUNT = N 保证交集语义）
    if (and.isNotEmpty) {
      final ph = and.map((_) => '?').join(',');
      conds.add('''
        id IN (
          SELECT image_id FROM image_tags
          WHERE tag_id IN ($ph)
          GROUP BY image_id
          HAVING COUNT(DISTINCT tag_id) = ${and.length}
        )
      ''');
      args.addAll(and);
    }

    // OR：至少拥有其中一个（并集）
    if (or.isNotEmpty) {
      final ph = or.map((_) => '?').join(',');
      conds.add(
          'id IN (SELECT DISTINCT image_id FROM image_tags WHERE tag_id IN ($ph))');
      args.addAll(or);
    }

    // NOT：不得拥有其中任意一个
    if (not.isNotEmpty) {
      final ph = not.map((_) => '?').join(',');
      conds.add(
          'id NOT IN (SELECT DISTINCT image_id FROM image_tags WHERE tag_id IN ($ph))');
      args.addAll(not);
    }

    final rows = await _db.rawQuery(
      'SELECT id FROM images WHERE ${conds.join(' AND ')}',
      args,
    );
    return rows.map((r) => r['id'] as int).toSet();
  }

  /// 根据布尔表达式筛选图片，返回匹配的图片 id 集合。
  ///
  /// [expression] 形如 `((A||B)&&!C)||C`；[allTags] 用于把标签名解析为 id。
  /// 语法错误抛出 [FilterExpressionException]。
  Future<Set<int>> getImageIdsByExpression(
      String expression, List<Tag> allTags) async {
    final ast = FilterExpressionParser.parse(expression);
    final sub = buildImageIdSubquery(ast, (ref) => _resolveTagRef(ref, allTags));
    final rows = await _db.rawQuery('SELECT id FROM images WHERE id IN ($sub)');
    return rows.map((r) => r['id'] as int).toSet();
  }

  /// 把表达式中的标签引用解析为 tag id 列表。
  ///
  /// 规则：
  /// - 引号内：按名称精确匹配（不区分大小写），忽略命名空间
  /// - 含 `:`：按 `命名空间:名称` 匹配（不区分大小写）
  /// - 否则：按名称跨命名空间匹配（不区分大小写），同名标签取并集
  List<int> _resolveTagRef(TagRef ref, List<Tag> allTags) {
    final target = ref.text.toLowerCase();
    final Iterable<Tag> matches;
    if (ref.quoted) {
      matches = allTags.where((t) => t.name.toLowerCase() == target);
    } else {
      final ci = ref.text.indexOf(':');
      if (ci > 0) {
        final ns = ref.text.substring(0, ci).toLowerCase();
        final name = ref.text.substring(ci + 1).toLowerCase();
        matches = allTags.where(
            (t) => t.namespace.toLowerCase() == ns && t.name.toLowerCase() == name);
      } else {
        matches = allTags.where((t) => t.name.toLowerCase() == target);
      }
    }
    return matches.where((t) => t.id != null).map((t) => t.id!).toList();
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
