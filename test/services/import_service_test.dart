import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pictureviewer/db/database.dart';
import 'package:pictureviewer/db/folder_dao.dart';
import 'package:pictureviewer/db/image_dao.dart';
import 'package:pictureviewer/services/data_dir_service.dart';
import 'package:pictureviewer/services/import_service.dart';
import 'package:pictureviewer/services/settings_service.dart';
import 'package:pictureviewer/services/thumbnail_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// P2-15 的验收：同一路径重复导入两次，两次的 imageId 相同且非 0。
///
/// 直接落在 DAO 的冲突分支上（`insert` 命中唯一约束回读真实 id），
/// 再从服务层确认「已索引的路径不再产生事件、库里只有一行」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late Directory srcDir;
  late ImageDao imageDao;
  late FolderDao folderDao;
  late ImportService service;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pv2_import');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    await DataDirService.instance.init();
    await SettingsService.instance.init();
    await DatabaseManager.instance.init();
    await ThumbnailService.instance.init();
  });

  tearDownAll(() async {
    await DatabaseManager.instance.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  setUp(() async {
    final db = DatabaseManager.instance.db;
    for (final table in ['image_tags', 'images', 'folder_tags', 'folder_paths', 'folders']) {
      await db.delete(table);
    }
    // 每个用例一个干净的源目录，否则上一个用例写的 png 会漏进来
    srcDir = Directory(p.join(tmp.path, 'src'));
    if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
    srcDir.createSync(recursive: true);
    imageDao = ImageDao(db);
    folderDao = FolderDao(db);
    service = ImportService.fromDB();
  });

  File writePng(String name) {
    final image = img.Image(width: 4, height: 4);
    img.fill(image, color: img.ColorRgb8(10, 20, 30));
    return File(p.join(srcDir.path, name))..writeAsBytesSync(img.encodePng(image));
  }

  test('ImageDao.insert 同路径两次：第二次回读同一个非 0 id', () async {
    final file = writePng('a.png');
    final first = await imageDao.insert(ImageItem(
      path: file.path,
      filename: 'a.png',
      format: 'png',
      addedAt: 1700000000000,
    ));
    expect(first, isNot(0));

    final second = await imageDao.insert(ImageItem(
      path: file.path,
      filename: 'a.png',
      format: 'png',
      addedAt: 1700000000001,
    ));

    expect(second, first, reason: '命中唯一约束时要回读真实 id，不能把 0 当 id');
    expect(await imageDao.count(), 1);
  });

  test('importPaths 重复导入同一文件：第一次 imageId 非 0，第二次不再产生事件', () async {
    final file = writePng('b.png');

    final first = await service.importPaths([file.path]).toList();
    expect(first, hasLength(1));
    expect(first.single.imageId, isNot(0));
    expect(first.single.imageId, isNotNull);

    final second = await service.importPaths([file.path]).toList();

    expect(second, isEmpty, reason: '已索引的路径不该再写一次，也不该再报一条进度');
    expect(await imageDao.count(), 1);
  });

  test('importDirectory 导入 3 张图：id 互不相同且非 0，并镜像出根文件夹', () async {
    writePng('c1.png');
    writePng('c2.png');
    writePng('c3.png');

    final events = await service.importDirectory(srcDir.path).toList();

    expect(events, hasLength(3));
    final ids = events.map((e) => e.imageId).toList();
    expect(ids.every((id) => id != null && id != 0), isTrue);
    expect(ids.toSet(), hasLength(3), reason: '三张图要拿到三个不同的真实 id');

    final roots = await folderDao.listRoot();
    expect(roots.map((f) => f.name), contains(p.basename(srcDir.path)));
  });
}
