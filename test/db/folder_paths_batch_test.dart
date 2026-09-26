import 'package:flutter_test/flutter_test.dart';
import 'package:pictureviewer/db/folder_dao.dart';
import 'package:pictureviewer/db/tables.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 回归用例：一次拿多个文件夹的路径。
///
/// 标签筛选要按「标签命中的图片所属文件夹」过滤文件夹树，旧实现每个
/// 子文件夹各自 `getPaths` 往返一次（150 个子目录 = 150 次查询）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late FolderDao dao;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: Tables.version,
        onCreate: (d, v) async {
          for (final sql in Tables.createStatements) {
            await d.execute(sql);
          }
        },
      ),
    );
    dao = FolderDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('空入参不查库，直接返回空表', () async {
    expect(await dao.getPathsForFolders([]), isEmpty);
  });

  test('返回每个文件夹自己的路径', () async {
    final a = await dao.create('a');
    final b = await dao.create('b');
    await dao.addPath(a.id!, '/pics/a');
    await dao.addPath(b.id!, '/pics/b');

    final map = await dao.getPathsForFolders([a.id!, b.id!]);
    expect(map[a.id!]!.map((p) => p.path).toList(), ['/pics/a']);
    expect(map[b.id!]!.map((p) => p.path).toList(), ['/pics/b']);
    expect(map[a.id!]!.first.recursive, true);
  });

  test('一个文件夹挂多条路径时全部返回', () async {
    final a = await dao.create('multi');
    await dao.addPath(a.id!, '/pics/one');
    await dao.addPath(a.id!, '/pics/two', recursive: false);

    final map = await dao.getPathsForFolders([a.id!]);
    expect(map[a.id!]!.map((p) => p.path).toSet(), {'/pics/one', '/pics/two'});
    final second = map[a.id!]!.firstWhere((p) => p.path == '/pics/two');
    expect(second.recursive, false);
  });

  test('不在入参里的文件夹不出现', () async {
    final a = await dao.create('a');
    final b = await dao.create('b');
    await dao.addPath(a.id!, '/pics/a');
    await dao.addPath(b.id!, '/pics/b');

    final map = await dao.getPathsForFolders([a.id!]);
    expect(map.keys.toList(), [a.id!]);
  });

  test('没有路径的文件夹不出现在结果里', () async {
    final a = await dao.create('empty');

    final map = await dao.getPathsForFolders([a.id!]);
    expect(map.containsKey(a.id!), isFalse);
  });

  test('超过 500 个文件夹时分批查询仍然全返回', () async {
    const count = 620;
    final ids = <int>[];
    for (var i = 0; i < count; i++) {
      final f = await dao.create('f$i');
      await dao.addPath(f.id!, '/pics/f$i');
      ids.add(f.id!);
    }

    final map = await dao.getPathsForFolders(ids);
    expect(map.length, count);
    for (var i = 0; i < count; i++) {
      expect(map[ids[i]]!.single.path, '/pics/f$i');
    }
  });
}
