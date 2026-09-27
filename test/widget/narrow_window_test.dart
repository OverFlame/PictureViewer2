import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pictureviewer/db/database.dart';
import 'package:pictureviewer/db/folder_dao.dart';
import 'package:pictureviewer/db/image_dao.dart';
import 'package:pictureviewer/pages/home_page.dart';
import 'package:pictureviewer/services/data_dir_service.dart';
import 'package:pictureviewer/services/settings_service.dart';
import 'package:pictureviewer/services/thumbnail_cache.dart';
import 'package:pictureviewer/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 窄窗口回归。
///
/// 主界面是「固定宽度左面板 280 + 固定宽度右面板 320 + 中央自适应」的布局，
/// 窗口一窄中央就只剩几十像素，几栏里的 `Row` 会报 RenderFlex overflow
/// （真实窗口小到 900px 上下就能看到，不用改代码就能复现）。
/// 这里按一批真实窗口宽度逐个渲染，把溢出的尺寸与像素数收成一张表。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late AppState state;

  /// 等 AppState 的异步初始化落地（与 app_smoke_test.dart 同一套：等「连续 100ms 无通知」）。
  Future<void> settle(AppState s) async {
    var notifications = 0;
    void listener() => notifications++;
    s.addListener(listener);
    try {
      var quiet = 0;
      for (var i = 0; i < 150; i++) {
        final before = notifications;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        if (notifications == before) {
          quiet++;
          if (quiet >= 5) return;
        } else {
          quiet = 0;
        }
      }
    } finally {
      s.removeListener(listener);
    }
  }

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('pv2_narrow');
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
    state = AppState();
    await settle(state);
  });

  tearDown(() async {
    await settle(state);
    state.dispose();
  });

  Widget wrap(AppState s, Size size) => ChangeNotifierProvider<AppState>.value(
        value: s,
        // 每个尺寸给一棵全新的树。RenderFlex 的同一条溢出只报一次
        // （RenderFlex._overflowReportNeeded），复用同一棵树的话，
        // 只有第一个出问题的尺寸会被报出来，后面的都看不见。
        child: MaterialApp(home: HomePage(key: ValueKey('page_${size.width}'))),
      );

  /// 把窗口设成 [size] 渲染一棵新树，返回这一帧里的布局错误（含出错控件）。
  Future<List<String>> renderAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final collected = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      // informationCollector 里才有「The relevant error-causing widget was: Row …home_page.dart:296」
      final where = (details.informationCollector?.call() ?? const <DiagnosticsNode>[])
          .map((node) => node.toString().trim())
          .where((line) => line.contains('widget was') || line.contains('.dart:'))
          .join(' ');
      collected.add('${details.exceptionAsString()}${where.isEmpty ? '' : ' ← $where'}');
    };
    try {
      await tester.pumpWidget(wrap(state, size));
      await tester.pump();
    } finally {
      FlutterError.onError = previous;
    }
    // 自己接管了 onError，框架不会记异常；顺手抽干，免得漏到别处
    while (tester.takeException() != null) {}
    return collected;
  }

  String sizeLabel(Size s) => '${s.width.toInt()}×${s.height.toInt()}';

  testWidgets('空库时：各种窗口宽度下都不溢出', (tester) async {
    const sizes = <Size>[
      Size(1600, 1000),
      Size(1280, 800),
      Size(1024, 768),
      Size(900, 700),
      Size(800, 600),
      Size(700, 600),
      Size(600, 520),
      Size(480, 640),
      Size(380, 640),
      Size(300, 520),
    ];

    final failures = <String>[];
    for (final size in sizes) {
      for (final msg in await renderAt(tester, size)) {
        failures.add('${sizeLabel(size)}: $msg');
      }
    }

    expect(failures, isEmpty, reason: '窄窗口布局溢出：\n${failures.join('\n')}');
  });

  testWidgets('进入文件夹 + 选中图片 + 高级筛选：顶部几栏同时出现也不溢出', (tester) async {
    // 垫数据：一个名字很长的文件夹 + 几张图。落库是真实 I/O，得放进 runAsync。
    await tester.runAsync(() async {
      final db = DatabaseManager.instance.db;
      await FolderDao(db).create('一个名字很长的文件夹用来撑宽度');

      final imageDao = ImageDao(db);
      for (var i = 0; i < 5; i++) {
        await imageDao.insert(ImageItem(
          path: '${tmp.path}/窄窗口_$i.png',
          filename: '窄窗口_$i.png',
          width: 1920,
          height: 1080,
          format: 'png',
          fileSize: 1024,
          addedAt: DateTime.now().millisecondsSinceEpoch,
        ));
      }
      await state.loadFolders();
    });

    const size = Size(600, 520);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final collected = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final where = (details.informationCollector?.call() ?? const <DiagnosticsNode>[])
          .map((node) => node.toString().trim())
          .where((line) => line.contains('widget was') || line.contains('.dart:'))
          .join(' ');
      collected.add('${details.exceptionAsString()}${where.isEmpty ? '' : ' ← $where'}');
    };

    await tester.pumpWidget(wrap(state, size));
    await tester.pump();

    // 进入文件夹 → 出现面包屑；选中一张 → 出现多选操作条；设筛选 → 出现筛选提示条
    await tester.runAsync(() async {
      final folder = state.folders.first;
      await state.enterFolder(folder.id!);
      await state.setAdvancedFilter('tag:旅行');
    });
    await tester.pump();

    if (state.images.isNotEmpty) {
      state.selectImage(state.images.first.id);
      await tester.pump();
    }

    FlutterError.onError = previous;
    while (tester.takeException() != null) {}

    expect(collected, isEmpty,
        reason: '${sizeLabel(size)} 下带面包屑/多选/筛选时溢出：\n${collected.join('\n')}');
  });

  /// 垫一个长名字文件夹 + 几张图（真实 I/O，得放进 runAsync）
  Future<void> seedFolderAndImages(WidgetTester tester) async {
    await tester.runAsync(() async {
      final db = DatabaseManager.instance.db;
      await FolderDao(db).create('一个名字很长的文件夹用来撑宽度');
      final imageDao = ImageDao(db);
      for (var i = 0; i < 5; i++) {
        await imageDao.insert(ImageItem(
          path: '${tmp.path}/窄窗口_$i.png',
          filename: '窄窗口_$i.png',
          width: 1920,
          height: 1080,
          format: 'png',
          fileSize: 1024,
          addedAt: DateTime.now().millisecondsSinceEpoch,
          alias: '一个很长很长的别名，用来把详情栏撑满',
          note: '备注文字也不短，用来验证窄面板下的换行与省略',
        ));
      }
      await state.loadFolders();
    });
  }

  /// 接管 onError 收集一段渲染里的布局错误（带出错控件线索）
  Future<List<String>> collectErrors(
      WidgetTester tester, Future<void> Function() body) async {
    final collected = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final where = (details.informationCollector?.call() ?? const <DiagnosticsNode>[])
          .map((node) => node.toString().trim())
          .where((line) => line.contains('widget was') || line.contains('.dart:'))
          .join(' ');
      collected.add('${details.exceptionAsString()}${where.isEmpty ? '' : ' ← $where'}');
    };
    try {
      await body();
    } finally {
      FlutterError.onError = previous;
    }
    while (tester.takeException() != null) {}
    return collected;
  }

  testWidgets('窄窗口下两侧面板被压缩后，带内容的详情栏也不溢出', (tester) async {
    await seedFolderAndImages(tester);

    for (final size in const [Size(800, 700), Size(700, 600)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final collected = await collectErrors(tester, () async {
        await tester.pumpWidget(wrap(state, size));
        await tester.pump();
        await tester.runAsync(() async {
          await state.enterFolder(state.folders.first.id!);
        });
        await tester.pump();
        state.selectImage(state.images.isNotEmpty ? state.images.first.id : null);
        await tester.pump();
      });

      expect(collected, isEmpty,
          reason: '${sizeLabel(size)} 下压窄的详情栏溢出：\n${collected.join('\n')}');
    }
  });

  testWidgets('工具栏：宽窗口行内铺开，中央不够宽就收进「更多」菜单且动作仍可用', (tester) async {
    // 宽：1400 时中央有 792，排序/视图/筛选等都是行内按钮
    const wide = Size(1400, 900);
    tester.view.physicalSize = wide;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(state, wide));
    await tester.pump();
    expect(find.byIcon(Icons.sort), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);

    // 窄：900 时左右面板都在（各压到 267/305），中央只剩 320 → 全收进一个菜单
    const narrow = Size(900, 700);
    tester.view.physicalSize = narrow;
    await tester.pumpWidget(wrap(state, narrow));
    await tester.pump();
    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
    expect(find.byIcon(Icons.sort), findsNothing);

    // 菜单路由动画没走完时 route 会忽略点击，所以多推几帧再点
    Future<void> settleFrames() async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await tester.tap(find.byIcon(Icons.more_horiz));
    await settleFrames();
    expect(find.text('文件大小'), findsOneWidget);
    expect(find.text('高级筛选'), findsOneWidget);

    await tester.tap(find.text('文件名'));
    await settleFrames();
    expect(state.sortKey, 'filename', reason: '窄窗口下菜单里的排序要真的生效');
  });
}
