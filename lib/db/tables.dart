/// 数据库 DDL 建表语句 & 迁移
class Tables {
  Tables._();

  static const int version = 1;

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
      note        TEXT
    )
    ''',

    // 图片路径索引
    'CREATE INDEX IF NOT EXISTS idx_images_path ON images(path)',
    'CREATE INDEX IF NOT EXISTS idx_images_hash ON images(hash)',

    // 标签表
    '''
    CREATE TABLE tags (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      namespace  TEXT    NOT NULL DEFAULT 'general',
      name       TEXT    NOT NULL,
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
  ];

  /// 迁移脚本（按 version 递增），未来版本在此追加
  static const Map<int, List<String>> migrations = {
    // version 2 示例：
    // 2: ['ALTER TABLE images ADD COLUMN color_palette TEXT'],
  };
}
