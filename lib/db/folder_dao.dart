import 'package:sqflite/sqflite.dart';
import '../utils/log_util.dart';

/// 虚拟文件夹
class VirtualFolder {
  final int? id;
  final String name;
  final int? parentId;

  const VirtualFolder({this.id, required this.name, this.parentId});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'parent': parentId,
      };

  factory VirtualFolder.fromMap(Map<String, dynamic> map) => VirtualFolder(
        id: map['id'] as int?,
        name: map['name'] as String,
        parentId: map['parent'] as int?,
      );
}

/// 文件夹路径映射
class FolderPath {
  final int folderId;
  final String path;
  final bool recursive;

  const FolderPath({
    required this.folderId,
    required this.path,
    this.recursive = true,
  });

  Map<String, dynamic> toMap() => {
        'folder_id': folderId,
        'path': path,
        'recursive': recursive ? 1 : 0,
      };
}

/// 虚拟文件夹 DAO
class FolderDao {
  final Database _db;

  FolderDao(this._db);

  // ═══ 文件夹 CRUD ═══

  Future<VirtualFolder> create(String name, {int? parentId}) async {
    // 根级同名在数据库层拦不住：UNIQUE(name, parent) 里 parent 可空，而 SQLite
    // 把每个 NULL 视为互不相同。所以这里先查后插，命中就复用既有记录。
    final existing = await findByName(name, parentId: parentId);
    if (existing != null) {
      logInfo('FolderDao',
          'Reuse folder: id=${existing.id} name="$name" parent=$parentId');
      return existing;
    }
    try {
      final id = await _db.insert('folders', {
        'name': name,
        'parent': parentId,
      });
      logInfo('FolderDao',
          'Created folder: id=$id name="$name" parent=$parentId');
      return VirtualFolder(id: id, name: name, parentId: parentId);
    } on DatabaseException catch (e) {
      // 唯一约束或并发把插入挡下来了，回读一次拿既有记录
      final again = await findByName(name, parentId: parentId);
      if (again != null) {
        logInfo('FolderDao', 'Reuse folder after conflict: id=${again.id}');
        return again;
      }
      logWarn('FolderDao', 'Create folder failed: name="$name"', e);
      rethrow;
    }
  }

  /// 按名称与父级查找（parentId 为 null 表示根级）
  Future<VirtualFolder?> findByName(String name, {int? parentId}) async {
    final rows = parentId == null
        ? await _db.query('folders',
            where: 'name = ? AND parent IS NULL', whereArgs: [name])
        : await _db.query('folders',
            where: 'name = ? AND parent = ?', whereArgs: [name, parentId]);
    if (rows.isEmpty) return null;
    return VirtualFolder.fromMap(rows.first);
  }

  Future<List<VirtualFolder>> listRoot() async {
    final rows = await _db.query('folders',
        where: 'parent IS NULL', orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  Future<List<VirtualFolder>> listChildren(int parentId) async {
    final rows = await _db.query('folders',
        where: 'parent = ?', whereArgs: [parentId], orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  /// 获取所有文件夹（带 parent 关系，用于构建完整树）
  Future<List<VirtualFolder>> listAll() async {
    final rows = await _db.query('folders', orderBy: 'name');
    return rows.map(VirtualFolder.fromMap).toList();
  }

  /// 重命名。返回 false 表示没改动（同父级下已有同名文件夹）
  ///
  /// 同名检查得自己做：根级文件夹的 parent 是 NULL，而 SQLite 的
  /// `UNIQUE(name, parent)` 认为每个 NULL 互不相同，根级根本拦不住。
  Future<bool> rename(int id, String newName) async {
    final folder = await getById(id);
    if (folder == null) return false;
    if (folder.name == newName) return true;

    final clash = await findByName(newName, parentId: folder.parentId);
    if (clash != null && clash.id != id) {
      logWarn('FolderDao',
          'Rename blocked (名重复): #$id -> "$newName" 已被 #${clash.id} 占用');
      return false;
    }
    try {
      await _db.update('folders', {'name': newName},
          where: 'id = ?', whereArgs: [id]);
      return true;
    } on DatabaseException catch (e) {
      logWarn('FolderDao', 'Rename blocked (唯一约束): #$id -> "$newName"', e);
      return false;
    }
  }

  /// 根据 id 查询文件夹
  Future<VirtualFolder?> getById(int id) async {
    final rows =
        await _db.query('folders', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return VirtualFolder.fromMap(rows.first);
  }

  /// 移动文件夹到新的父级（null 表示移动到根级）。
  /// 返回 false 表示没改动（目标父级下已有同名文件夹）
  Future<bool> move(int id, int? newParentId) async {
    final folder = await getById(id);
    if (folder == null) return false;
    if (folder.parentId == newParentId) return true;

    final clash = await findByName(folder.name, parentId: newParentId);
    if (clash != null && clash.id != id) {
      logWarn('FolderDao',
          'Move blocked (名重复): #$id "${folder.name}" -> parent=$newParentId 已被 #${clash.id} 占用');
      return false;
    }
    try {
      await _db.update('folders', {'parent': newParentId},
          where: 'id = ?', whereArgs: [id]);
      return true;
    } on DatabaseException catch (e) {
      logWarn('FolderDao',
          'Move blocked (唯一约束): #$id -> parent=$newParentId', e);
      return false;
    }
  }

  /// 查询某文件夹的直接子文件夹数量（用于树形 UI 判断是否可展开）
  Future<int> countChildren(int parentId) async {
    final count = Sqflite.firstIntValue(await _db.rawQuery(
        'SELECT COUNT(*) FROM folders WHERE parent = ?', [parentId]));
    return count ?? 0;
  }

  /// 删除文件夹（CASCADE 自动清理 folder_paths；子文件夹上移到根级）
  Future<int> delete(int id) async {
    // 先将其子文件夹上移为根级，避免层级断裂
    await _db.update('folders', {'parent': null},
        where: 'parent = ?', whereArgs: [id]);
    final count = await _db.delete('folders', where: 'id = ?', whereArgs: [id]);
    logInfo('FolderDao', 'Deleted folder id=$id (affected $count row(s))');
    return count;
  }

  // ═══ 路径管理 ═══

  /// 添加文件夹路径
  Future<void> addPath(int folderId, String path,
      {bool recursive = true}) async {
    await _db.insert('folder_paths',
        FolderPath(folderId: folderId, path: path, recursive: recursive)
            .toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  /// 移除文件夹路径
  Future<void> removePath(int folderId, String path) async {
    await _db.delete('folder_paths',
        where: 'folder_id = ? AND path = ?',
        whereArgs: [folderId, path]);
  }

  /// 根据路径查找文件夹
  Future<VirtualFolder?> getByPath(String path) async {
    final rows = await _db.rawQuery('''
      SELECT f.* FROM folders f
      INNER JOIN folder_paths fp ON f.id = fp.folder_id
      WHERE fp.path = ?
    ''', [path]);
    if (rows.isEmpty) return null;
    return VirtualFolder.fromMap(rows.first);
  }

  /// 创建文件夹并关联路径
  Future<VirtualFolder> insert({
    required String name,
    required String path,
  }) async {
    final folder = await create(name);
    await addPath(folder.id!, path);
    logInfo('FolderDao', 'Inserted folder with path: "${name}" → $path');
    return folder;
  }

  /// 获取某文件夹的所有路径
  Future<List<FolderPath>> getPaths(int folderId) async {
    final rows = await _db.query('folder_paths',
        where: 'folder_id = ?', whereArgs: [folderId]);
    return rows.map((r) => FolderPath(
      folderId: r['folder_id'] as int,
      path: r['path'] as String,
      recursive: (r['recursive'] as int) == 1,
    )).toList();
  }

  /// 批量获取多个文件夹的路径（一次查询，避免逐文件夹往返）
  Future<Map<int, List<FolderPath>>> getPathsForFolders(
      List<int> folderIds) async {
    if (folderIds.isEmpty) return {};
    final map = <int, List<FolderPath>>{};
    // SQLite 的变量上限默认 999，分批保证大批子树筛选也能走单次往返
    const batchSize = 500;
    for (var i = 0; i < folderIds.length; i += batchSize) {
      final batch = folderIds.sublist(
          i, i + batchSize > folderIds.length ? folderIds.length : i + batchSize);
      final placeholders = batch.map((_) => '?').join(',');
      final rows = await _db.query('folder_paths',
          where: 'folder_id IN ($placeholders)', whereArgs: batch);
      for (final r in rows) {
        final fid = r['folder_id'] as int;
        map.putIfAbsent(fid, () => []).add(FolderPath(
          folderId: fid,
          path: r['path'] as String,
          recursive: (r['recursive'] as int) == 1,
        ));
      }
    }
    return map;
  }

  /// 获取所有文件夹的所有路径（用于全库扫描去重）
  Future<Map<int, List<FolderPath>>> getAllPaths() async {
    final rows = await _db.query('folder_paths');
    final map = <int, List<FolderPath>>{};
    for (final r in rows) {
      final fid = r['folder_id'] as int;
      map.putIfAbsent(fid, () => []).add(FolderPath(
        folderId: fid,
        path: r['path'] as String,
        recursive: (r['recursive'] as int) == 1,
      ));
    }
    return map;
  }
}
