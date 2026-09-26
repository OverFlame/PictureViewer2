import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pictureviewer/db/database.dart';
import 'package:pictureviewer/db/folder_dao.dart';
import 'package:pictureviewer/db/image_dao.dart';
import 'package:pictureviewer/db/tables.dart';
import 'package:pictureviewer/db/tag_dao.dart';
import 'package:pictureviewer/services/data_dir_service.dart';
import 'package:pictureviewer/services/settings_service.dart';
import 'package:pictureviewer/services/thumbnail_cache.dart';
import 'package:pictureviewer/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 规模基线：约 2 万张图的库，一个目录里直接放 1.2 万张，另有 150 个子目录。
///
/// 这条用例把真实的 `AppState` 拉起来（只把 path_provider 指到临时目录），
/// 量四条用户可见路径：切文件夹、搜索、按标签筛选、访问选中项。
/// 数字用 stdout 打印，断言只留宽松上限，避免在慢机器上误报。
const int _bigDirImages = 12000;
const int _subDirs = 150;
const int _perSubDir = 53;
const int _tags = 20;
const int _taggedSubDirs = 20;

const List<String> _exts = [
  '.jpg',
  '.jpeg',
  '.png',
  '.heic',
  '.webp',
  '.gif',
  '.bmp',
  '.tif',
];

const List<List<int>> _sizes = [
  [1920, 1080],
  [4032, 3024],
  [6000, 4000],
  [8000, 6000],
];

String _dirName(int i) => 'd${i.toString().padLeft(3, '0')}';

Future<void> _waitIdle(AppState state) {
  if (!state.loading) return Future<void>.value();
  final done = Completer<void>();
  void listener() {
    if (!state.loading) {
      state.removeListener(listener);
      if (!done.isCompleted) done.complete();
    }
  }

  state.addListener(listener);
  return done.future;
}

Future<void> _seed(Directory dataDir, Directory pics) async {
  final db = await databaseFactoryFfi.openDatabase(
    p.join(dataDir.path, 'pv2.db'),
    options: OpenDatabaseOptions(
      version: Tables.version,
      onCreate: (d, v) async {
        for (final sql in Tables.createStatements) {
          await d.execute(sql);
        }
      },
    ),
  );

  await db.transaction((txn) async {
    await txn.insert('folders', {'id': 1, 'name': '全部图片', 'parent': null});
    await txn.insert(
        'folder_paths', {'folder_id': 1, 'path': pics.path, 'recursive': 1});
    for (var i = 0; i < _subDirs; i++) {
      await txn.insert(
          'folders', {'id': 2 + i, 'name': _dirName(i), 'parent': 1});
      await txn.insert('folder_paths', {
        'folder_id': 2 + i,
        'path': p.join(pics.path, _dirName(i)),
        'recursive': 1,
      });
    }
    for (var t = 1; t <= _tags; t++) {
      await txn.insert('tags', {
        'namespace': 'perf',
        'name': 'tag${t.toString().padLeft(2, '0')}',
        'color': '#cba6f7',
      });
    }
  });

  final images = db.batch();
  var nextId = 0;
  int addImage(String dir, int index, int mtime) {
    nextId++;
    final size = _sizes[index % _sizes.length];
    final ext = _exts[index % _exts.length];
    final name = 'IMG_${nextId.toString().padLeft(6, '0')}$ext';
    images.insert('images', {
      'id': nextId,
      'path': p.join(dir, name),
      'filename': name,
      'width': size[0],
      'height': size[1],
      'format': ext.substring(1),
      'file_size': size[0] * size[1] ~/ 8,
      'file_mtime': mtime,
      'hash': null,
      'added_at': 1700000000000 + nextId,
      'note': null,
      'alias': null,
    });
    return nextId;
  }

  // 大目录：1.2 万张直接放在 pics 下
  for (var i = 0; i < _bigDirImages; i++) {
    addImage(pics.path, i, 1600000000000 + i);
  }
  // 150 个子目录：每个 53 张
  final subDirIds = <int, List<int>>{};
  for (var d = 0; d < _subDirs; d++) {
    final dir = p.join(pics.path, _dirName(d));
    final ids = <int>[];
    for (var i = 0; i < _perSubDir; i++) {
      ids.add(addImage(dir, i, 1610000000000 + d * 1000 + i));
    }
    subDirIds[d] = ids;
  }
  await images.commit(noResult: true);

  // 标签 1：大目录里每 4 张挂 1 张，外加前 20 个子目录整目录
  final tagBatch = db.batch();
  for (var i = 1; i <= _bigDirImages; i += 4) {
    tagBatch.insert('image_tags', {'image_id': i, 'tag_id': 1});
  }
  var tagged = _bigDirImages ~/ 4;
  for (var d = 0; d < _taggedSubDirs; d++) {
    for (final id in subDirIds[d]!) {
      tagBatch.insert('image_tags', {'image_id': id, 'tag_id': 1});
      tagged++;
    }
  }
  await tagBatch.commit(noResult: true);
  stdout.writeln('── 播种：$nextId 张图片，带标签 1 的 $tagged 张，'
      '$_subDirs 个子目录 $_perSubDir 张/个 ──');
  await db.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late Directory pics;
  late AppState state;
  final results = <String, int>{};

  Future<void> measure(String label, Future<void> Function() body) async {
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    results[label] = sw.elapsedMilliseconds;
  }

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pv2scale');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );

    await DataDirService.instance.init();
    final dataDir = Directory(await DataDirService.instance.dataDir);
    pics = Directory(p.join(tmp.path, 'pics'))..createSync(recursive: true);
    for (var i = 0; i < _subDirs; i++) {
      Directory(p.join(pics.path, _dirName(i))).createSync(recursive: true);
    }
    await _seed(dataDir, pics);

    await SettingsService.instance.init();
    await DatabaseManager.instance.init();
    await ThumbnailService.instance.init();
    state = AppState();
    await _waitIdle(state);
    await state.loadFolders();
  });

  tearDownAll(() async {
    state.dispose();
    await DatabaseManager.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    stdout.writeln('── 规模基线（毫秒） ──');
    for (final entry in results.entries) {
      stdout.writeln('  ${entry.key}: ${entry.value}');
    }
    stdout.writeln('── 库规模：${_bigDirImages + _subDirs * _perSubDir} 张，'
        '${_subDirs + 1} 个文件夹，$_tags 个标签 ──');
  });

  test('切进大目录（1.2 万张直接图片 + 150 个子目录）', () async {
    await measure('enterFolder(1.2 万张)', () => state.enterFolder(1));
    expect(state.images.length, _bigDirImages);
    expect(state.centerFolders.length, _subDirs);
    expect(results['enterFolder(1.2 万张)']!, lessThan(20000));
  });

  test('搜索全库', () async {
    state.setSearchQuery('IMG_');
    await measure('searchByName(全库 2 万张)', () => _waitIdle(state));
    expect(state.images.length, _bigDirImages + _subDirs * _perSubDir);
    state.setSearchQuery('');
    await _waitIdle(state);
  });

  test('文件夹内按标签筛选', () async {
    await state.enterFolder(1);
    state.toggleAndFilter(1);
    await measure('toggleAndFilter(150 个子目录)', () => _waitIdle(state));
    // 标签 1 播种在「大目录里每 4 张」+「前 20 个子目录整目录」上：
    // 当前目录的直接子图命中 _bigDirImages ~/ 4 张，可见子文件夹只剩
    // 命中路径的祖先那 20 个（其余 130 个要被过滤掉）。
    expect(state.images.length, _bigDirImages ~/ 4);
    expect(state.centerFolders.length, _taggedSubDirs);
    state.clearTagFilters();
    await _waitIdle(state);
  });

  test('分层计时：DAO 单条查询各占多少', () async {
    final db = DatabaseManager.instance.db;
    final imageDao = ImageDao(db);
    final tagDao = TagDao(db);
    final folderDao = FolderDao(db);
    final picsPath = p.join(tmp.path, 'pics');

    await measure('  └ queryDirectInDir(1.2 万)', () async {
      final rows = await imageDao.queryDirectInDir(picsPath, limit: 100000);
      expect(rows.length, _bigDirImages);
    });
    await measure('  └ searchByName(全库 2 万)', () async {
      final rows = await imageDao.searchByName('IMG_', limit: 100000);
      expect(rows.length, _bigDirImages + _subDirs * _perSubDir);
    });
    late Set<int> ids;
    await measure('  └ getImageIdsByTags(标签 1)', () async {
      ids = await tagDao.getImageIdsByTags(andTagIds: const [1]);
      expect(ids.length, _bigDirImages ~/ 4 + _taggedSubDirs * _perSubDir);
    });
    await measure('  └ pathsByIds(4060 个 id)', () async {
      final paths = await imageDao.pathsByIds(ids);
      expect(paths.length, ids.length);
    });
    await measure('  └ getPaths x150（逐文件夹，改造前的路径）', () async {
      for (var i = 0; i < _subDirs; i++) {
        await folderDao.getPaths(2 + i);
      }
    });
    await measure('  └ getPathsForFolders x150（一次往返）', () async {
      final map = await folderDao
          .getPathsForFolders([for (var i = 0; i < _subDirs; i++) 2 + i]);
      expect(map.length, _subDirs);
    });
  });

  test('反复访问选中项（1.2 万项列表，末尾项）', () async {
    await state.enterFolder(1);
    final images = state.images;
    state.selectImage(images.last.id);
    final sw = Stopwatch()..start();
    var found = 0;
    for (var i = 0; i < 1000; i++) {
      if (state.selectedImage != null) found++;
    }
    sw.stop();
    results['selectedImage x1000（1.2 万项）'] = sw.elapsedMilliseconds;
    expect(found, 1000);
    expect(sw.elapsedMilliseconds, lessThan(20000));
  });
}
