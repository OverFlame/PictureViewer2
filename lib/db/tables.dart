/// 数据库 DDL 建表语句 & 迁移
class Tables {
  Tables._();

  static const int version = 4;

  /// 所有建表 SQL（按依赖顺序）
  static const List<String> createStatements = [
    // 图片表
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

    // 图片索引：path 有 UNIQUE 约束，隐式索引已经够用，不再重复建
    'CREATE INDEX IF NOT EXISTS idx_images_hash ON images(hash)',
    'CREATE INDEX IF NOT EXISTS idx_images_added_at ON images(added_at DESC)',

    // 标签表
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

    // 图片↔标签 多对多
    '''
    CREATE TABLE image_tags (
      image_id INTEGER NOT NULL REFERENCES images(id) ON DELETE CASCADE,
      tag_id   INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (image_id, tag_id)
    )
    ''',
    // 主键前导列是 image_id，按标签反查需要这条例外的索引
    'CREATE INDEX IF NOT EXISTS idx_image_tags_tag ON image_tags(tag_id)',

    // 虚拟文件夹
    '''
    CREATE TABLE folders (
      id     INTEGER PRIMARY KEY AUTOINCREMENT,
      name   TEXT    NOT NULL,
      parent INTEGER REFERENCES folders(id),
      UNIQUE(name, parent)
    )
    ''',

    // 文件夹路径映射
    '''
    CREATE TABLE folder_paths (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      path      TEXT    NOT NULL,
      recursive INTEGER NOT NULL DEFAULT 1
    )
    ''',
    // 原先没有 PK/UNIQUE，addPath 的 conflictAlgorithm.ignore 永不触发
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_folder_paths_uniq ON folder_paths(folder_id, path)',

    // 文件夹↔标签 多对多（文件夹可持有标签）
    '''
    CREATE TABLE folder_tags (
      folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
      tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
      PRIMARY KEY (folder_id, tag_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id)',
  ];

  /// 迁移脚本（按 version 递增），未来版本在此追加
  static const Map<int, List<String>> migrations = {
    2: ["ALTER TABLE tags ADD COLUMN color TEXT NOT NULL DEFAULT '#cba6f7'"],
    3: [
      "ALTER TABLE images ADD COLUMN alias TEXT",
      '''
      CREATE TABLE folder_tags (
        folder_id INTEGER NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
        tag_id    INTEGER NOT NULL REFERENCES tags(id)    ON DELETE CASCADE,
        PRIMARY KEY (folder_id, tag_id)
      )
      ''',
      "CREATE INDEX IF NOT EXISTS idx_folder_tags_tag ON folder_tags(tag_id)",
    ],
    // v4：补齐索引。新库与从老库升级的库必须落到同一组索引上，
    // 所以这里的语句与 createStatements 保持一致。
    4: [
      // 建唯一索引前先清历史重复行（没有唯一约束时可能被写进去），
      // 同一 (folder_id, path) 只保留 rowid 最小的那一行。
      '''
      DELETE FROM folder_paths
      WHERE rowid NOT IN (
        SELECT MIN(rowid) FROM folder_paths GROUP BY folder_id, path
      )
      ''',
      // idx_images_path 与 path 的 UNIQUE 隐式索引重复，只增加写入开销
      'DROP INDEX IF EXISTS idx_images_path',
      'CREATE INDEX IF NOT EXISTS idx_image_tags_tag ON image_tags(tag_id)',
      'CREATE INDEX IF NOT EXISTS idx_images_added_at ON images(added_at DESC)',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_folder_paths_uniq ON folder_paths(folder_id, path)',
    ],
  };
}
