import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pictureviewer/db/image_dao.dart';
import 'package:pictureviewer/db/tables.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 回归用例：LIKE 查询里的 `_` / `%` / `\` 必须按字面量匹配。
///
/// 旧实现直接把用户输入拼进模式串，`searchByName('2024_06')` 会把
/// `2024-06` 也搜出来，按目录前缀查询遇到含 `_` 的目录名同样会串目录。
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

  Future<int> add(String path, {String? filename, String? alias, int addedAt = 0}) =>
      dao.insert(ImageItem(
        path: path,
        filename: filename ?? p.basename(path),
        alias: alias,
        addedAt: addedAt,
      ));

  group('searchByName', () {
    test('下划线不当通配符', () async {
      await add('/pics/2024_06.jpg');
      await add('/pics/2024-06.jpg');

      final rows = await dao.searchByName('2024_06');
      expect(rows.map((r) => r.filename).toList(), ['2024_06.jpg']);
    });

    test('百分号不当通配符', () async {
      await add('/pics/a%b.jpg');
      await add('/pics/aXXb.jpg');

      final rows = await dao.searchByName('a%b');
      expect(rows.map((r) => r.filename).toList(), ['a%b.jpg']);
    });

    test('别名命中同样转义', () async {
      await add('/pics/1.jpg', filename: '1.jpg', alias: '2024_06 家庭');
      await add('/pics/2.jpg', filename: '2.jpg', alias: '2024-06 旅行');

      final rows = await dao.searchByName('2024_06');
      expect(rows.map((r) => r.alias).toList(), ['2024_06 家庭']);
    });

    test('仍能命中含下划线的正常输入', () async {
      await add('/pics/IMG_000001.jpg');
      await add('/pics/other.png');

      final rows = await dao.searchByName('IMG_');
      expect(rows.map((r) => r.filename).toList(), ['IMG_000001.jpg']);
    });
  });

  group('count 与 queryPage 的 search', () {
    test('count 与命中结果一致', () async {
      await add('/pics/2024_06.jpg');
      await add('/pics/2024-06.jpg');

      expect(await dao.count(search: '2024_06'), 1);
      expect(await dao.count(search: '2024'), 2);
    });

    test('queryPage 的 search 同样转义', () async {
      await add('/pics/2024_06.jpg');
      await add('/pics/2024-06.jpg');

      final rows = await dao.queryPage(search: '2024_06');
      expect(rows.map((r) => r.filename).toList(), ['2024_06.jpg']);
    });
  });

  group('目录前缀查询', () {
    test('目录名含下划线时不串到同前缀目录', () async {
      await add('/pics/2024_06/a.jpg');
      await add('/pics/2024-06/b.jpg');
      await add('/pics/2024_06_old/c.jpg');

      final direct = await dao.queryDirectInDir('/pics/2024_06');
      expect(direct.map((r) => r.path).toList(), ['/pics/2024_06/a.jpg']);

      expect(await dao.countDirectInDir('/pics/2024_06'), 1);
    });

    test('路径里含百分号时 pathsInDirectory 不匹配任意串', () async {
      await add('/pics/50%/a.jpg');
      await add('/pics/50kg/b.jpg');

      final paths = await dao.pathsInDirectory('/pics/50%');
      expect(paths, ['/pics/50%/a.jpg']);
    });

    test('Windows 路径同样转义', () async {
      await add(r'D:\Photos_2024\a.jpg');
      await add(r'D:\Photos-2024\b.jpg');

      final rows = await dao.queryDirectInDir(r'D:\Photos_2024');
      expect(rows.map((r) => r.path).toList(), [r'D:\Photos_2024\a.jpg']);
    });
  });

  group('queryByIds 的 search', () {
    test('按 id 过滤的同时转义搜索词', () async {
      final a = await add('/pics/2024_06.jpg');
      final b = await add('/pics/2024-06.jpg');
      await add('/pics/other.png');

      final rows = await dao.queryByIds({a, b}, search: '2024_06');
      expect(rows.map((r) => r.path).toList(), ['/pics/2024_06.jpg']);
    });
  });
}
