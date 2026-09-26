import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pictureviewer/db/image_dao.dart';
import 'package:pictureviewer/db/tables.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 回归用例：按目录递归查询必须带上目录分隔符。
///
/// 旧实现用 `'$dirPath%'` 拼前缀，`D:\Photos%` 会连 `D:\Photos2024\a.jpg`
/// 一起命中。递归给文件夹加标签走的正是这条查询，等于把标签写到同前缀的
/// 兄弟目录的图片上。
///
/// 这里直接开一个内存库，绕开 `DatabaseManager`（它只能经 `DataDirService`
/// 取目录，没有测试注入口）。
void main() {
  sqfliteFfiInit();

  late Database db;
  late ImageDao dao;

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
    dao = ImageDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> add(String path) => dao.insert(ImageItem(
        path: path,
        filename: p.basename(path),
        addedAt: 0,
      ));

  group('queryByDir', () {
    test('不把同前缀的兄弟目录算进来', () async {
      await add(r'D:\Photos\a.jpg');
      await add(r'D:\Photos\2024\b.jpg');
      await add(r'D:\Photos2024\c.jpg');
      await add(r'D:\Photos2024_old\d.jpg');
      await add(r'D:\Other\e.jpg');

      final rows = await dao.queryByDir(r'D:\Photos');
      expect(rows.map((r) => r.path).toSet(), {
        r'D:\Photos\a.jpg',
        r'D:\Photos\2024\b.jpg',
      });
    });

    test('目录名带尾分隔符时结果一致', () async {
      await add(r'D:\Photos\a.jpg');
      await add(r'D:\Photos2024\c.jpg');

      final rows = await dao.queryByDir(r'D:\Photos\');
      expect(rows.map((r) => r.path).toList(), [r'D:\Photos\a.jpg']);
    });

    test('正斜杠路径同样只命中本目录', () async {
      await add('/pics/2024/x.jpg');
      await add('/pics/2024-06/y.jpg');

      final rows = await dao.queryByDir('/pics/2024');
      expect(rows.map((r) => r.path).toList(), ['/pics/2024/x.jpg']);
    });
  });

  group('queryByDirs', () {
    test('多个前缀各自带分隔符', () async {
      await add(r'D:\Photos\a.jpg');
      await add(r'D:\Photos2024\c.jpg');
      await add('/pics/2024/x.jpg');
      await add('/pics/2024-06/y.jpg');
      await add(r'D:\Other\e.jpg');

      final rows = await dao.queryByDirs([r'D:\Photos', '/pics/2024']);
      expect(rows.map((r) => r.path).toSet(), {
        r'D:\Photos\a.jpg',
        '/pics/2024/x.jpg',
      });
    });

    test('空列表返回空结果', () async {
      await add(r'D:\Photos\a.jpg');
      expect(await dao.queryByDirs(const []), isEmpty);
    });
  });

  group('insert 命中既有路径', () {
    test('同路径插入两次返回同一个非 0 id', () async {
      final first = await add(r'D:\Photos\a.jpg');
      expect(first, greaterThan(0));

      final second = await add(r'D:\Photos\a.jpg');
      expect(second, first);
    });

    test('重复插入不会多出一行', () async {
      await add('/pics/a.jpg');
      await add('/pics/a.jpg');

      final rows = await dao.queryByDir('/pics');
      expect(rows.length, 1);
    });
  });
}
