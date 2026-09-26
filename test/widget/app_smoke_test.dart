import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pictureviewer/db/database.dart';
import 'package:pictureviewer/db/folder_dao.dart';
import 'package:pictureviewer/main.dart';
import 'package:pictureviewer/pages/home_page.dart';
import 'package:pictureviewer/services/data_dir_service.dart';
import 'package:pictureviewer/services/settings_service.dart';
import 'package:pictureviewer/services/thumbnail_cache.dart';
import 'package:pictureviewer/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 真实主界面的冒烟测试：不再用 Flutter 计数器模板。
///
/// 覆盖三件靠手工点才看得见的事：空库的空状态、搜索框的 250ms 防抖、
/// 以及「新建同名根文件夹」走 get-or-create 而不是建出第二个。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tmp;
  late AppState state;

  /// 等 AppState 的异步初始化落地。
  ///
  /// 不能只看 `loading`：`_init()` 里 loadSettings → loadTags → loadFolders
  /// 都跑完了才会进 refresh()，那之前 loading 一直是 false。
  /// 这里等「连续 100ms 没有任何通知」。
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
    tmp = await Directory.systemTemp.createTemp('pv2_widget');
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
    // 初始化是 fire-and-forget 的，dispose 前先让它彻底停下来
    await settle(state);
    state.dispose();
  });

  Widget wrap(AppState s) => ChangeNotifierProvider<AppState>.value(
        value: s,
        child: const MaterialApp(home: HomePage()),
      );

  /// 默认 800×600 的测试窗口撑不下「左面板 280 + 右面板 320」，
  /// 中央工具栏会报 RenderFlex overflow（真实窗口小到 900px 以下同样会）。
  void useDesktopSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Finder textFieldWithHint(String hint) => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == hint,
      );

  testWidgets('空库时主界面显示空状态与导入入口', (tester) async {
    useDesktopSurface(tester);
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    expect(find.text('这里还没有内容'), findsOneWidget);
    // 「添加文件夹」在空状态和左面板都有入口，所以只要求至少一个
    expect(find.text('添加文件夹'), findsWidgets);
    expect(find.text('搜索文件名...'), findsOneWidget);
  });

  testWidgets('搜索框 250ms 防抖：窗口内不发查询，窗口后发出', (tester) async {
    useDesktopSurface(tester);
    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();

    await tester.enterText(textFieldWithHint('搜索文件名...'), 'IMG');

    // 防抖窗口内：输入框已有字，但 AppState 还没收到查询
    await tester.pump(const Duration(milliseconds: 100));
    expect(state.searchQuery, isEmpty);

    // 越过 250ms 窗口后计时器才触发，查询词同步写进 AppState
    await tester.pump(const Duration(milliseconds: 200));
    expect(state.searchQuery, 'IMG');

    // 真正的 SQLite 查询是真实 I/O，FakeAsync 里不会自己跑完
    await tester.runAsync(() => settle(state));
    await tester.pump();
    expect(state.loading, isFalse);
  });

  testWidgets('新建同名根文件夹：第二次走既有文件夹并给出提示', (tester) async {
    useDesktopSurface(tester);
    // 树标题行（含「新建根文件夹」）只在已有文件夹时出现，先垫一个。
    // 落库是真实 I/O，FakeAsync 里必须放进 runAsync，否则永远等不到
    await tester.runAsync(() async {
      await FolderDao(DatabaseManager.instance.db).create('已有的');
      await state.loadFolders();
    });

    await tester.pumpWidget(wrap(state));
    await tester.pumpAndSettle();
    expect(find.byTooltip('新建根文件夹'), findsOneWidget);

    Future<void> createRootFolder(String name) async {
      await tester.tap(find.byTooltip('新建根文件夹'));
      await tester.pumpAndSettle();
      await tester.enterText(textFieldWithHint('文件夹名称'), name);
      await tester.tap(find.text('确定'));
      await tester.pump();
      // 建文件夹要落库，真实 I/O 得靠 runAsync 推着走
      await tester.runAsync(() => settle(state));
      await tester.pump();
    }

    await createRootFolder('旅行');
    expect(state.folders.map((f) => f.name), contains('旅行'));
    expect(state.folders, hasLength(2));

    await createRootFolder('旅行');

    expect(state.folders, hasLength(2), reason: '同名的根文件夹不该建出第二个');
    expect(find.textContaining('已有同名文件夹'), findsOneWidget);

    // 让 SnackBar 自身 4s 的计时器走完，否则测试结束时会报 pending timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('完整应用（main.dart 连线）能启动并渲染 HomePage', (tester) async {
    useDesktopSurface(tester);
    await tester.pumpWidget(const PictureViewerApp());
    await tester.pumpAndSettle();

    expect(find.byType(HomePage), findsOneWidget);
    expect(tester.takeException(), isNull);

    // PictureViewerApp 自己 create 的 AppState 也在 fire-and-forget 地初始化，
    // 等它落地再结束用例，否则树被销毁后它还会 notifyListeners
    final appState = Provider.of<AppState>(
      tester.element(find.byType(HomePage)),
      listen: false,
    );
    await tester.runAsync(() => settle(appState));
    await tester.pump();
  });
}
