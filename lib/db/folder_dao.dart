import 'package:sqflite/sqflite.dart';

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

  /// 删除文件夹（CASCADE 自动清理 folder_paths）
  Future<int> delete(int id) async {
    return _db.delete('folders', where: 'id = ?', whereArgs: [id]);
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
