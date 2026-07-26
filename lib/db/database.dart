import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../utils/log_util.dart';
import 'tables.dart';

/// 数据库管理器 — 初始化、打开、迁移、单例
class DatabaseManager {
  static DatabaseManager? _instance;
  static Database? _db;

  DatabaseManager._();

  static DatabaseManager get instance {
    _instance ??= DatabaseManager._();
    return _instance!;
  }

  Database get db {
    if (_db == null) throw StateError('Database not initialized. Call init() first.');
    return _db!;
  }

  /// 初始化：注册 FFI、打开数据库、建表/迁移
  Future<void> init() async {
    logInfo('Database', 'Initializing...');
    // Windows 桌面使用 FFI
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    final dir = await _dbDir();
    final dbPath = p.join(dir, 'pv2.db');
    logInfo('Database', 'DB path: $dbPath');

    _db = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: Tables.version,
        onCreate: (db, version) async {
          logInfo('Database', 'Creating tables (v$version)');
          for (final sql in Tables.createStatements) {
            await db.execute(sql);
          }
          logInfo('Database', 'Tables created (${Tables.createStatements.length} statements)');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          logInfo('Database', 'Migrating v$oldVersion -> v$newVersion');
          for (int v = oldVersion + 1; v <= newVersion; v++) {
            final migrations = Tables.migrations[v];
            if (migrations == null) continue;
            logInfo('Database', 'Running migration v$v (${migrations.length} stmts)');
            for (final sql in migrations) {
              await db.execute(sql);
            }
          }
          logInfo('Database', 'Migration complete');
        },
      ),
    );

    // 开启 WAL 模式以提升并发性能
    await _db!.execute('PRAGMA journal_mode=WAL');
    // 外键约束
    await _db!.execute('PRAGMA foreign_keys=ON');
    logInfo('Database', 'Initialized OK (WAL+FK enabled)');
  }

  Future<String> _dbDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = p.join(appDir.path, 'PictureViewer');
    // 确保目录存在（path_provider 不一定自动创建子目录）
    await Directory(dir).create(recursive: true);
    return dir;
  }

  /// 关闭数据库
  Future<void> close() async {
    logInfo('Database', 'Closing connection');
    await _db?.close();
    _db = null;
    logInfo('Database', 'Closed');
  }
}
