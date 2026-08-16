import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'theme/catppuccin.dart';
import 'pages/home_page.dart';
import 'db/database.dart';
import 'services/data_dir_service.dart';
import 'services/settings_service.dart';
import 'services/thumbnail_cache.dart';
import 'state/app_state.dart';
import 'utils/log_util.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  logInfo('Main', '========== App starting ==========');

  // 初始化数据目录（数据库 / 缩略图 / 设置的统一根目录）
  await DataDirService.instance.init();
  // 初始化设置服务（读取 settings.json）
  await SettingsService.instance.init();
  // 初始化数据库
  await DatabaseManager.instance.init();
  // 初始化缩略图服务（创建缓存目录）
  await ThumbnailService.instance.init();

  // 锁定竖屏（桌面端无影响）
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  logInfo('Main', 'Launching app');
  runApp(const PictureViewerApp());
}

class PictureViewerApp extends StatelessWidget {
  const PictureViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Consumer<AppState>(
        builder: (context, state, _) {
          // 根据主题动态设置系统 UI 样式
          final isDark = state.themeMode == ThemeMode.dark ||
              (state.themeMode == ThemeMode.system &&
                  MediaQuery.of(context).platformBrightness ==
                      Brightness.dark);

          SystemChrome.setSystemUIOverlayStyle(
            SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
              systemNavigationBarColor:
                  isDark ? Catppuccin.mantle : const Color(0xFFE6E9EF),
              systemNavigationBarIconBrightness:
                  isDark ? Brightness.light : Brightness.dark,
            ),
          );

          return MaterialApp(
            title: 'PictureViewer',
            debugShowCheckedModeBanner: false,
            theme: Catppuccin.lightThemeData,
            darkTheme: Catppuccin.darkThemeData,
            themeMode: state.themeMode,
            home: const HomePage(),
          );
        },
      ),
    );
  }
}


