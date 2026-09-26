import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pictureviewer/services/thumbnail_cache.dart';

Future<ui.Image> _tinyImage() async {
  final raw = img.encodePng(img.Image(width: 2, height: 2));
  final codec = await ui.instantiateImageCodec(raw);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailMemoryCache', () {
    test('removeWhere 移除匹配项并释放纹理', () async {
      final cache = ThumbnailMemoryCache();
      final a = await _tinyImage();
      final b = await _tinyImage();
      cache.put('/p/a.jpg::300::1', a);
      cache.put('/p/b.jpg::300::1', b);

      cache.removeWhere((key) => key.startsWith('/p/a.jpg::'));

      expect(cache.get('/p/a.jpg::300::1'), isNull);
      expect(a.debugDisposed, isTrue);
      expect(cache.get('/p/b.jpg::300::1'), isNotNull);
      expect(b.debugDisposed, isFalse);
      b.dispose();
    });
  });

  group('ThumbnailService', () {
    late Directory cacheDir;
    late Directory srcDir;
    final service = ThumbnailService.instance;

    setUp(() async {
      cacheDir = await Directory.systemTemp.createTemp('pv2_thumbs');
      srcDir = await Directory.systemTemp.createTemp('pv2_src');
      await service.init(cacheDir: cacheDir.path);
    });

    tearDown(() async {
      if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
      if (srcDir.existsSync()) await srcDir.delete(recursive: true);
    });

    File writeImage(String name, {int size = 8, int r = 255}) {
      final image = img.Image(width: size, height: size);
      img.fill(image, color: img.ColorRgb8(r, 0, 0));
      return File('${srcDir.path}/$name')
        ..writeAsBytesSync(img.encodePng(image));
    }

    /// 把 mtime 推到未来，躲开「同一毫秒内写两次」的粒度问题
    void touch(File f, {int seconds = 5}) {
      f.setLastModifiedSync(DateTime.now().add(Duration(seconds: seconds)));
    }

    test('thumbPath 把 mtime 与尺寸编进文件名', () {
      final f = writeImage('a.png');
      final auto = service.thumbPath(f.path, size: 300);
      final older = service.thumbPath(f.path, size: 300, mtimeMs: 1);
      final bigger = service.thumbPath(f.path, size: 800, mtimeMs: 1);

      expect(older, isNot(auto));
      expect(older, isNot(bigger));
      expect(auto.endsWith('.t300'), isTrue);
      expect(bigger.endsWith('.t800'), isTrue);
    });

    test('非 ASCII 路径不按 UTF-16 码元低 8 位截断', () {
      // 0x7167 与 0x7267 的低字节相同，用 codeUnits 当字节会算出同一个哈希
      final a = '${srcDir.path}/${String.fromCharCode(0x7167)}.jpg';
      final b = '${srcDir.path}/${String.fromCharCode(0x7267)}.jpg';

      expect(
        service.thumbPath(a, size: 300, mtimeMs: 1),
        isNot(service.thumbPath(b, size: 300, mtimeMs: 1)),
      );
    });

    test('原图内容变化后生成到新路径，旧缩略图被清掉', () async {
      final f = writeImage('a.png', r: 255);
      final first = await service.ensureThumbnail(f.path, size: 300);
      expect(File(first).existsSync(), isTrue);

      writeImage('a.png', r: 0);
      touch(f);
      final second = await service.ensureThumbnail(f.path, size: 300);

      expect(second, isNot(first));
      expect(File(second).existsSync(), isTrue);
      expect(File(first).existsSync(), isFalse, reason: '旧时间戳的缩略图应当被删掉');
    });

    test('重扫时命中磁盘缓存不重复生成', () async {
      final f = writeImage('a.png');
      final first = await service.ensureThumbnail(f.path, size: 300);
      final before = File(first).statSync().modified;

      final again = await service.ensureThumbnail(f.path, size: 300);

      expect(again, first);
      expect(File(again).statSync().modified, before);
    });

    test('deleteThumbnails 清掉所有尺寸，原图已删也能调用', () async {
      final f = writeImage('b.png', size: 16);
      final p300 = await service.ensureThumbnail(f.path, size: 300);
      final p800 = await service.ensureThumbnail(f.path, size: 800);
      expect(File(p300).existsSync(), isTrue);
      expect(File(p800).existsSync(), isTrue);

      await service.deleteThumbnails(f.path);

      expect(File(p300).existsSync(), isFalse);
      expect(File(p800).existsSync(), isFalse);

      await f.delete();
      await service.deleteThumbnails(f.path); // 不该抛
    });

    test('原图不存在时生成抛 FileSystemException', () async {
      expect(
        () => service.ensureThumbnail('${srcDir.path}/missing.png'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('loadThumbnail 的内存键跟着 mtime 走', () async {
      final f = writeImage('c.png', r: 10);
      final first = await service.loadThumbnail(f.path, size: 300);

      writeImage('c.png', r: 200);
      touch(f);
      final second = await service.loadThumbnail(f.path, size: 300);

      expect(identical(first, second), isFalse, reason: '内容变了不该命中旧解码结果');
      first.dispose();
      second.dispose();
    });
  });
}
