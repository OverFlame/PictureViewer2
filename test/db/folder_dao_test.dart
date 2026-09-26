import 'package:flutter_test/flutter_test.dart';
import 'package:pictureviewer/db/folder_dao.dart';
import 'package:pictureviewer/db/tables.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 回归用例：文件夹重名。
///
/// 旧实现只靠数据库的 `UNIQUE(name, parent)` 挡重名，而根级文件夹的
/// parent 是 NULL，SQLite 认为每个 NULL 互不相同，于是连续建两个「旅行」
/// 都能成功；`folder_paths` 更是一点约束都没有，`addPath` 的
/// conflictAlgorithm.ignore 永不触发。
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

  group('create 遇到同名同父级复用既有记录', () {
    test('根级同名第二次拿到同一个 id，根级也不会多出一行', () async {
      final first = await dao.create('旅行');
      final second = await dao.create('旅行');

      expect(second.id, first.id);
      expect((await dao.listRoot()).length, 1);
    });

    test('父级不同时同名各自成行', () async {
      final parentA = await dao.create('2024');
      final parentB = await dao.create('2025');

      final a = await dao.create('旅行', parentId: parentA.id);
      final a2 = await dao.create('旅行', parentId: parentA.id);
      final b = await dao.create('旅行', parentId: parentB.id);

      expect(a2.id, a.id);
      expect(b.id, isNot(a.id));
    });

    test('findByName 查不到时返回 null', () async {
      expect(await dao.findByName('不存在'), isNull);
    });
  });

  group('rename 撞名不改动数据', () {
    test('改成同层级已有的名字返回 false', () async {
      final keep = await dao.create('旅行');
      final other = await dao.create('工作');

      expect(await dao.rename(other.id!, '旅行'), isFalse);
      expect((await dao.getById(other.id!))!.name, '工作');
      expect((await dao.getById(keep.id!))!.name, '旅行');
    });

    test('改成不冲突的名字返回 true', () async {
      final folder = await dao.create('旅行');

      expect(await dao.rename(folder.id!, '旅行 2024'), isTrue);
      expect((await dao.getById(folder.id!))!.name, '旅行 2024');
    });

    test('改成自己原来的名字视为无改动', () async {
      final folder = await dao.create('旅行');
      expect(await dao.rename(folder.id!, '旅行'), isTrue);
    });
  });

  group('move 撞名不改动数据', () {
    test('移到已有同名子文件夹的位置返回 false', () async {
      final parent = await dao.create('父');
      await dao.create('旅行', parentId: parent.id);
      final loose = await dao.create('旅行');

      expect(await dao.move(loose.id!, parent.id), isFalse);
      expect((await dao.getById(loose.id!))!.parentId, isNull);
    });

    test('移到不冲突的位置返回 true', () async {
      final parent = await dao.create('父');
      final loose = await dao.create('旅行');

      expect(await dao.move(loose.id!, parent.id), isTrue);
      expect((await dao.getById(loose.id!))!.parentId, parent.id);
    });
  });

  group('addPath 有唯一约束兜底', () {
    test('同一个 folder 与 path 写两次只留一行', () async {
      final folder = await dao.create('照片');

      await dao.addPath(folder.id!, '/pics/2024');
      await dao.addPath(folder.id!, '/pics/2024');

      expect((await dao.getPaths(folder.id!)).length, 1);
    });

    test('不同 path 各留一行', () async {
      final folder = await dao.create('照片');

      await dao.addPath(folder.id!, '/pics/2024');
      await dao.addPath(folder.id!, '/pics/2025');

      expect((await dao.getPaths(folder.id!)).length, 2);
    });
  });
}
