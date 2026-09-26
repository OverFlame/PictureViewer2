import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pictureviewer/db/tables.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// v3 的建表语句快照（逐字取自 lib/db/tables.dart 在 v4 改动之前的内容）。
///
/// 迁移用例必须拿真实的老库结构来跑，所以这里固定一份快照，不跟着
/// `Tables.createStatements` 一起漂。
const List<String> _v3CreateStatements = [
  '''
    CREATE TABLE images (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      path        TEXT    NOT NULL UNIQUE,
      filename    TEXT    NOT NULL,
      width       INTEGER,
      height      INTEGER,
      format      TEXT,
      file_size   INTEGER,
      file_mtime  INTEGER,
      hash        TEXT,
      added_at    INTEGER NOT NULL,
      note        TEXT,
      alias       TEXT
    )
    ''',
  'CREATE INDEX IF NOT EXISTS idx_images_path ON images(path)',
  'CREATE INDEX IF NOT EXISTS idx_images_hash ON images(hash)',
  '''
    CREATE TABLE tags (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      namespace  TEXT    NOT NULL DEFAULT 'general',
      name       TEXT    NOT NULL,
      color      TEXT    NOT NULL DEFAULT '#cba6f7',
      UNIQUE(namespace, name)
    )
    ''',
  'CREATE INDEX IF NOT EXISTS idx_tags_namespace ON tags(namespace)',
  'CREATE INDEX IF NOT EXISTS idx_tags_name ON tags(name)',
  '''
    CREATE TABLE image_tags (
      image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (image_id, tag_id)
    )
    ''',
  '''
    CREATE TABLE folders (
      id     INTEGER PRIMARY KEY AUTOINCREMENT,
      name   TEXT    NOT NULL,
      parent INTEGER REFERENCES folders(id),
      UNIQUE(name, parent)
    )
    ''',
  '''
    CREATE TABLE folder_paths (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      path      TEXT    NOT NULL,
      recursive INTEGER NOT NULL DEFAULT 1
    )
    ''',
  '''
    CREATE TABLE folder_tags (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (folder_id, tag_id)
    )
    ''',
  'CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id)',
];

/// 回归用例：从 v3 老库升级到当前版本后，索引集合必须和新库一致。
///
/// 旧版只在 `createStatements` 里建索引，`migrations` 里只出现了一条，
/// 于是老库升级后永远缺另外几条；`idx_images_path` 又和 path 的 UNIQUE
/// 隐式索引重复，白担写入开销。
void main() {
  sqfliteFfiInit();

  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pv2_migration');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Set<String>> indexNames(Database db) async {
    final rows = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'");
    return rows.map((r) => r['name'] as String).toSet();
  }

  /// 建一个 v3 老库（已关闭）
  Future<void> createV3() async {
    final db = await databaseFactoryFfi.openDatabase(
      p.join(tmp.path, 'legacy.db'),
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (d, v) async {
          for (final sql in _v3CreateStatements) {
            await d.execute(sql);
          }
        },
      ),
    );
    await db.insert('folders', {'name': '照片'});
    await db.close();
  }

  /// 用当前版本打开它，走与 DatabaseManager 相同的 onUpgrade 循环
  Future<Database> openCurrent() => databaseFactoryFfi.openDatabase(
        p.join(tmp.path, 'legacy.db'),
        options: OpenDatabaseOptions(
          version: Tables.version,
          onCreate: (d, v) async {
            for (final sql in Tables.createStatements) {
              await d.execute(sql);
            }
          },
          onUpgrade: (d, from, to) async {
            for (int v = from + 1; v <= to; v++) {
              for (final sql in Tables.migrations[v] ?? const <String>[]) {
                await d.execute(sql);
              }
            }
          },
        ),
      );

  Future<Database> createFresh() => databaseFactoryFfi.openDatabase(
        p.join(tmp.path, 'fresh.db'),
        options: OpenDatabaseOptions(
          version: Tables.version,
          onCreate: (d, v) async {
            for (final sql in Tables.createStatements) {
              await d.execute(sql);
            }
          },
        ),
      );

  test('升级后的索引集合与新库一致', () async {
    await createV3();

    final upgraded = await openCurrent();
    final upgradedIndexes = await indexNames(upgraded);
    await upgraded.close();

    final fresh = await createFresh();
    final freshIndexes = await indexNames(fresh);
    await fresh.close();

    expect(upgradedIndexes, freshIndexes);
    expect(upgradedIndexes, contains('idx_image_tags_tag'));
    expect(upgradedIndexes, contains('idx_images_added_at'));
    expect(upgradedIndexes, contains('idx_folder_paths_uniq'));
    expect(upgradedIndexes, isNot(contains('idx_images_path')));
  });

  test('升级时清掉历史重复的 folder_paths 行', () async {
    await createV3();

    // 老结构没有约束，重复行能写进去
    final legacy = await databaseFactoryFfi.openDatabase(
      p.join(tmp.path, 'legacy.db'),
    );
    await legacy.insert('folder_paths', {'folder_id': 1, 'path': '/pics'});
    await legacy.insert('folder_paths', {'folder_id': 1, 'path': '/pics'});
    await legacy.insert('folder_paths', {'folder_id': 1, 'path': '/other'});
    expect((await legacy.query('folder_paths')).length, 3);
    await legacy.close();

    final upgraded = await openCurrent();
    final rows = await upgraded.query('folder_paths');
    expect(rows.length, 2);
    expect(rows.map((r) => r['path']).toSet(), {'/pics', '/other'});

    // 唯一索引确实生效：再插重复行不会多出来
    await upgraded.insert(
      'folder_paths',
      {'folder_id': 1, 'path': '/pics'},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    expect((await upgraded.query('folder_paths')).length, 2);
    await upgraded.close();
  });

  test('老库的数据在升级后还在', () async {
    await createV3();
    final legacy = await databaseFactoryFfi.openDatabase(
      p.join(tmp.path, 'legacy.db'),
    );
    await legacy.insert('images', {
      'path': '/pics/a.jpg',
      'filename': 'a.jpg',
      'added_at': 1,
    });
    await legacy.close();

    final upgraded = await openCurrent();
    final images = await upgraded.query('images');
    expect(images.length, 1);
    expect(images.first['path'], '/pics/a.jpg');
    expect((await upgraded.query('folders')).length, 1);
    await upgraded.close();
  });
}
