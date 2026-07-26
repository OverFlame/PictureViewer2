import 'package:sqflite/sqflite.dart';

/// 图片数据类
class ImageItem {
  final int? id;
  final String path;
  final String filename;
  final int? width;
  final int? height;
  final String? format;
  final int? fileSize;
  final int? fileMtime;
  final String? hash;
  final int addedAt;
  final String? note;

  const ImageItem({
    this.id,
    required this.path,
    required this.filename,
    this.width,
    this.height,
    this.format,
    this.fileSize,
    this.fileMtime,
    this.hash,
    required this.addedAt,
    this.note,
  });

  ImageItem copyWith({
    int? id,
    String? path,
    String? filename,
    int? width,
    int? height,
    String? format,
    int? fileSize,
    int? fileMtime,
    String? hash,
    int? addedAt,
    String? note,
  }) {
    return ImageItem(
      id: id ?? this.id,
      path: path ?? this.path,
      filename: filename ?? this.filename,
      width: width ?? this.width,
      height: height ?? this.height,
      format: format ?? this.format,
      fileSize: fileSize ?? this.fileSize,
      fileMtime: fileMtime ?? this.fileMtime,
      hash: hash ?? this.hash,
      addedAt: addedAt ?? this.addedAt,
      note: note ?? this.note,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'path': path,
        'filename': filename,
        'width': width,
        'height': height,
        'format': format,
        'file_size': fileSize,
        'file_mtime': fileMtime,
        'hash': hash,
        'added_at': addedAt,
        'note': note,
      };

  factory ImageItem.fromMap(Map<String, dynamic> map) => ImageItem(
        id: map['id'] as int?,
        path: map['path'] as String,
        filename: map['filename'] as String,
        width: map['width'] as int?,
        height: map['height'] as int?,
        format: map['format'] as String?,
        fileSize: map['file_size'] as int?,
        fileMtime: map['file_mtime'] as int?,
        hash: map['hash'] as String?,
        addedAt: map['added_at'] as int,
        note: map['note'] as String?,
      );
}

/// 图片 DAO — CRUD + 批量操作 + 筛选
class ImageDao {
  final Database _db;

  ImageDao(this._db);

  // ═══ 单条操作 ═══

  /// 插入一张图片（存在则忽略），返回 id
  Future<int> insert(ImageItem image) async {
    final id = await _db.insert('images', image.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    return id;
  }

  /// 根据 id 查询
  Future<ImageItem?> getById(int id) async {
    final rows = await _db.query('images', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return ImageItem.fromMap(rows.first);
  }

  /// 根据 path 查询
  Future<ImageItem?> getByPath(String path) async {
    final rows =
        await _db.query('images', where: 'path = ?', whereArgs: [path]);
    if (rows.isEmpty) return null;
    return ImageItem.fromMap(rows.first);
  }

  /// 更新单条记录
  Future<int> update(ImageItem image) async {
    if (image.id == null) return 0;
    return _db.update('images', image.toMap(),
        where: 'id = ?', whereArgs: [image.id]);
  }

  /// 删除单条（CASCADE 自动清理 image_tags）
  Future<int> delete(int id) async {
    return _db.delete('images', where: 'id = ?', whereArgs: [id]);
  }

  // ═══ 批量操作 ═══

  /// 批量插入（事务包裹），跳过已存在的路径
  /// 返回 (成功数, 跳过数)
  Future<({int inserted, int skipped})> insertBatch(
      List<ImageItem> images) async {
    int inserted = 0;
    int skipped = 0;

    await _db.transaction((txn) async {
      for (final img in images) {
        final id = await txn.insert('images', img.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id > 0) {
          inserted++;
        } else {
          skipped++;
        }
      }
    });

    return (inserted: inserted, skipped: skipped);
  }

  /// 批量删除
  Future<int> deleteBatch(List<int> ids) async {
    if (ids.isEmpty) return 0;
    final placeholders = ids.map((_) => '?').join(',');
    return _db.delete('images',
        where: 'id IN ($placeholders)', whereArgs: ids);
  }

  // ═══ 查询 ═══

  /// 分页查询（按录入时间倒序，可选搜索过滤）
  Future<List<ImageItem>> queryPage({
    int offset = 0,
    int limit = 100,
    String? search,
  }) async {
    String? where;
    List<dynamic>? whereArgs;
    if (search != null && search.isNotEmpty) {
      where = 'filename LIKE ?';
      whereArgs = ['%$search%'];
    }
    final rows = await _db.query(
      'images',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'added_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(ImageItem.fromMap).toList();
  }

  /// 查询某路径前缀下的所有图片
  Future<List<ImageItem>> queryByDir(String dirPath) async {
    final rows = await _db.query('images',
        where: 'path LIKE ?', whereArgs: ['$dirPath%']);
    return rows.map(ImageItem.fromMap).toList();
  }

  /// 匹配多个路径前缀中的图片（用于虚拟文件夹）
  Future<List<ImageItem>> queryByDirs(List<String> dirPaths) async {
    if (dirPaths.isEmpty) return [];
    final conditions = dirPaths.map((_) => 'path LIKE ?').join(' OR ');
    final args = dirPaths.map((p) => '$p%').toList();
    final rows =
        await _db.query('images', where: conditions, whereArgs: args);
    return rows.map(ImageItem.fromMap).toList();
  }

  /// 总数（可选按 ID 集合或搜索过滤）
  Future<int> count({Set<int>? idFilter, String? search}) async {
    if (idFilter != null && idFilter.isEmpty) return 0;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (idFilter != null) {
      conditions.add('id IN (${idFilter.map((_) => '?').join(',')})');
      args.addAll(idFilter);
    }
    if (search != null && search.isNotEmpty) {
      conditions.add('filename LIKE ?');
      args.add('%$search%');
    }

    final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as cnt FROM images $where',
      args.isEmpty ? null : args,
    );
    return result.first['cnt'] as int;
  }

  /// 按 ID 集合分页查询（支持 search 模糊过滤）
  Future<List<ImageItem>> queryByIds(Set<int> ids, {
    int offset = 0,
    int limit = 100,
    String? search,
  }) async {
    if (ids.isEmpty) return [];
    final placeholders = ids.map((_) => '?').join(',');
    final conditions = StringBuffer('id IN ($placeholders)');
    final args = <dynamic>[...ids];

    if (search != null && search.isNotEmpty) {
      conditions.write(' AND filename LIKE ?');
      args.add('%$search%');
    }

    final rows = await _db.query(
      'images',
      where: conditions.toString(),
      whereArgs: args,
      orderBy: 'added_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(ImageItem.fromMap).toList();
  }

  /// 根据 hash 去重查询
  Future<ImageItem?> getByHash(String hash) async {
    final rows =
        await _db.query('images', where: 'hash = ?', whereArgs: [hash]);
    if (rows.isEmpty) return null;
    return ImageItem.fromMap(rows.first);
  }

  /// 检查文件是否已索引（通过 path）
  Future<bool> exists(String path) async {
    final count = Sqflite.firstIntValue(
      await _db.rawQuery(
          'SELECT COUNT(*) FROM images WHERE path = ?', [path]),
    );
    return (count ?? 0) > 0;
  }

  /// 给定一批路径，返回已在数据库中的路径集合（用于导入去重）
  Future<Set<String>> existingPaths(List<String> paths) async {
    if (paths.isEmpty) return {};
    // 分批查询避免 SQL 过长
    const batchSize = 500;
    final existing = <String>{};
    for (int i = 0; i < paths.length; i += batchSize) {
      final batch = paths.sublist(i,
          i + batchSize > paths.length ? paths.length : i + batchSize);
      final placeholders = batch.map((_) => '?').join(',');
      final rows = await _db.rawQuery(
        'SELECT path FROM images WHERE path IN ($placeholders)',
        batch,
      );
      for (final row in rows) {
        existing.add(row['path'] as String);
      }
    }
    return existing;
  }

  /// 获取某目录下已索引的路径列表
  Future<List<String>> pathsInDirectory(String dirPath) async {
    final normalized = dirPath.endsWith('/') || dirPath.endsWith('\\')
        ? dirPath
        : '$dirPath${dirPath.contains('\\') ? '\\' : '/'}';
    final rows = await _db.rawQuery(
      'SELECT path FROM images WHERE path LIKE ?',
      ['$normalized%'],
    );
    return rows.map((r) => r['path'] as String).toList();
  }

  /// 根据路径批量删除
  Future<int> deleteByPaths(List<String> paths) async {
    if (paths.isEmpty) return 0;
    const batchSize = 500;
    int deleted = 0;
    for (int i = 0; i < paths.length; i += batchSize) {
      final batch = paths.sublist(i,
          i + batchSize > paths.length ? paths.length : i + batchSize);
      final placeholders = batch.map((_) => '?').join(',');
      deleted += await _db.delete(
        'images',
        where: 'path IN ($placeholders)',
        whereArgs: batch,
      );
    }
    return deleted;
  }

  // ═══ 死索引清理 ═══

  /// 删除所有 path 不在给定列表中的记录
  /// 返回删除条数
  Future<int> purgeDead(List<String> alivePaths) async {
    if (alivePaths.isEmpty) {
      // 没有存活路径 → 清空全部图片
      final count = await _db.delete('images');
      return count;
    }

    // SQLite 的 IN 有参数上限，分批处理
    const batchSize = 500;
    int totalDeleted = 0;

    // 先查出所有 id + path
    final all = await _db.query('images', columns: ['id', 'path']);
    final aliveSet = alivePaths.toSet();
    final deadIds = <int>[];

    for (final row in all) {
      if (!aliveSet.contains(row['path'] as String)) {
        deadIds.add(row['id'] as int);
      }
    }

    // 分批删除
    for (int i = 0; i < deadIds.length; i += batchSize) {
      final batch =
          deadIds.sublist(i, i + batchSize > deadIds.length ? deadIds.length : i + batchSize);
      final placeholders = batch.map((_) => '?').join(',');
      totalDeleted += await _db.delete('images',
          where: 'id IN ($placeholders)', whereArgs: batch);
    }

    return totalDeleted;
  }
}
