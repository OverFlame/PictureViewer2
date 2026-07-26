import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/catppuccin.dart';
import 'pages/home_page.dart';
import 'db/database.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化数据库
  await DatabaseManager.instance.init();

  // 锁定竖屏（桌面端无影响）
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 设置系统 UI 为暗色
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Catppuccin.mantle,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const PictureViewerApp());
}

class PictureViewerApp extends StatelessWidget {
  const PictureViewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PictureViewer',
      debugShowCheckedModeBanner: false,
      theme: Catppuccin.themeData,
      darkTheme: Catppuccin.themeData,
      themeMode: ThemeMode.dark,
      home: const HomePage(),
    );
  }
}
