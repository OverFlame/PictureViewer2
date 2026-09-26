import 'package:flutter_test/flutter_test.dart';
import 'package:pictureviewer/db/image_dao.dart';
import 'package:pictureviewer/db/tables.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 回归用例：排序下推到 SQL（原先 DAO 写死 `added_at DESC`，
/// 页面拿到列表后在 Dart 侧整表重排）。
///
/// 排序键来自持久化设置，必须走白名单——否则就是注入面。
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

  Future<int> add(String filename,
          {String dir = '/pics',
          int? fileSize,
          int? fileMtime,
          String? alias,
          int addedAt = 0}) =>
      dao.insert(ImageItem(
        path: '$dir/$filename',
        filename: filename,
        fileSize: fileSize,
        fileMtime: fileMtime,
        alias: alias,
        addedAt: addedAt,
      ));

  group('orderByClause', () {
    test('已知键映到白名单列并带同向 tie-break', () {
      expect(ImageDao.orderByClause(sortKey: 'filename'),
          'filename COLLATE NOCASE DESC, filename COLLATE NOCASE DESC');
      expect(ImageDao.orderByClause(sortKey: 'filename', descending: false),
          'filename COLLATE NOCASE ASC, filename COLLATE NOCASE ASC');
      expect(ImageDao.orderByClause(sortKey: 'added_at', descending: false),
          'added_at ASC, filename COLLATE NOCASE ASC');
      expect(ImageDao.orderByClause(sortKey: 'file_size'),
          'COALESCE(file_size, 0) DESC, filename COLLATE NOCASE DESC');
      expect(ImageDao.orderByClause(sortKey: 'alias'),
          "COALESCE(alias, '') COLLATE NOCASE DESC, filename COLLATE NOCASE DESC");
    });

    test('未知键回退到 added_at，不把输入拼进 SQL', () {
      final sql = ImageDao.orderByClause(sortKey: 'id; DROP TABLE images');
      expect(sql, 'added_at DESC, filename COLLATE NOCASE DESC');
    });
  });

  group('queryPage 排序', () {
    setUp(() async {
      await add('b.jpg', fileSize: 300, addedAt: 2);
      await add('a.jpg', fileSize: 100, addedAt: 3);
      await add('c.jpg', fileSize: 200, addedAt: 1);
    });

    test('默认按 added_at 倒序', () async {
      final rows = await dao.queryPage();
      expect(rows.map((r) => r.filename).toList(), ['a.jpg', 'b.jpg', 'c.jpg']);
    });

    test('added_at 升序', () async {
      final rows = await dao.queryPage(descending: false);
      expect(rows.map((r) => r.filename).toList(), ['c.jpg', 'b.jpg', 'a.jpg']);
    });

    test('按文件名不区分大小写排序', () async {
      await add('B2.jpg');

      final rows = await dao.queryPage(sortKey: 'filename', descending: false);
      expect(rows.map((r) => r.filename).toList(),
          ['a.jpg', 'b.jpg', 'B2.jpg', 'c.jpg']);
    });

    test('按文件大小排序，NULL 当 0', () async {
      await add('d.jpg');

      final rows = await dao.queryPage(sortKey: 'file_size', descending: false);
      expect(rows.first.filename, 'd.jpg');
      expect(rows.map((r) => r.filename).toList().sublist(1),
          ['a.jpg', 'c.jpg', 'b.jpg']);
    });

    test('按别名排序，NULL 当空串', () async {
      await add('z1.jpg', alias: 'Zebra');
      await add('z2.jpg', alias: 'apple');

      final rows = await dao.queryPage(sortKey: 'alias', descending: false);
      // 前三个没有别名（空串）排在字母前面，组内按文件名
      expect(rows.map((r) => r.filename).toList().sublist(0, 3),
          ['a.jpg', 'b.jpg', 'c.jpg']);
      expect(rows.map((r) => r.filename).toList().sublist(3), ['z2.jpg', 'z1.jpg']);
    });
  });

  group('queryDirectInDir 排序', () {
    test('排序键生效且子目录不参与', () async {
      await add('b.jpg', dir: '/pics');
      await add('a.jpg', dir: '/pics');
      await add('zz.jpg', dir: '/pics/sub');

      final rows =
          await dao.queryDirectInDir('/pics', sortKey: 'filename', descending: false);
      expect(rows.map((r) => r.filename).toList(), ['a.jpg', 'b.jpg']);
    });
  });

  group('searchByName 排序', () {
    test('搜索结果的排序同样下推', () async {
      await add('IMG_2.jpg', fileSize: 200);
      await add('IMG_1.jpg', fileSize: 100);
      await add('other.png');

      final byName = await dao.searchByName('IMG_', descending: false);
      expect(byName.map((r) => r.filename).toList(), ['IMG_1.jpg', 'IMG_2.jpg']);

      final bySize =
          await dao.searchByName('IMG_', sortKey: 'file_size', descending: false);
      expect(bySize.map((r) => r.filename).toList(), ['IMG_1.jpg', 'IMG_2.jpg']);
    });
  });

  group('queryByIds 排序', () {
    test('id 过滤后仍按指定键排序', () async {
      final a = await add('c.jpg', addedAt: 1);
      final b = await add('a.jpg', addedAt: 2);

      final rows = await dao.queryByIds({a, b}, sortKey: 'added_at');
      expect(rows.map((r) => r.filename).toList(), ['a.jpg', 'c.jpg']);
    });
  });

  test('分页排序稳定：同一键的多行按 added_at 分页不重不漏', () async {
    for (var i = 0; i < 10; i++) {
      await add('same.jpg', dir: '/pics/d$i', addedAt: i);
    }

    final page1 = await dao.queryPage(limit: 4, sortKey: 'filename');
    final page2 = await dao.queryPage(offset: 4, limit: 4, sortKey: 'filename');
    final page3 = await dao.queryPage(offset: 8, limit: 4, sortKey: 'filename');

    final ids = [...page1, ...page2, ...page3].map((r) => r.id).toList();
    expect(ids.length, 10);
    expect(ids.toSet().length, 10);
  });
}
