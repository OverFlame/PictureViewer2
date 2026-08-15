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
    final id = await _db.insert('folders', {
      'name': name,
      'parent': parentId,
    });
    logInfo('FolderDao', 'Created folder: id=$id name="$name" parent=$parentId');
    return VirtualFolder(id: id, name: name, parentId: parentId);
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

  Future<int> rename(int id, String newName) async {
    return _db.update('folders', {'name': newName},
        where: 'id = ?', whereArgs: [id]);
  }

  /// 根据 id 查询文件夹
  Future<VirtualFolder?> getById(int id) async {
    final rows =
        await _db.query('folders', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return VirtualFolder.fromMap(rows.first);
  }

  /// 移动文件夹到新的父级（null 表示移动到根级）
  Future<int> move(int id, int? newParentId) async {
    return _db.update('folders', {'parent': newParentId},
        where: 'id = ?', whereArgs: [id]);
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
