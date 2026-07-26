# PictureViewer

基于 Flutter 的现代化桌面图片浏览器，支持标签管理、EXIF 查看、全屏预览与主题切换。

## 特性

- **缩略图网格浏览** — 可调节列数（2~10）的自适应网格布局
- **文件夹管理** — 多文件夹导入 / 删除，动态扫描
- **标签系统** — 自定义标签，按标签筛选图片
- **全屏查看器** — 缩放/平移、键盘导航、Ctrl+滚轮定点缩放、EXIF 面板
- **EXIF 元数据** — 光圈、快门、ISO、焦距、尺寸等详细信息
- **深色 / 浅色主题** — Catppuccin Mocha & Latte 色板，支持跟随系统
- **导出分享** — 另存为、打开文件位置
- **缩略图缓存** — 像素级去重，LRU 内存缓存，可调磁盘缓存

## 技术栈

| 层 | 技术 |
|----|------|
| 框架 | Flutter 3.x (Desktop Windows) |
| 语言 | Dart |
| 状态管理 | Provider + ChangeNotifier |
| 数据库 | SQLite (sqflite + ffi) |
| 图片处理 | image |
| EXIF 读取 | exif |
| 主题 | Catppuccin |
| 持久化 | shared_preferences |
| 文件选择 | file_picker |
| 拖拽 | desktop_drop |

## 开始

### 环境要求

- Flutter SDK ≥ 3.29，Dart ≥ 3.5
- Windows 10/11 (x64)，已启用桌面开发
- Visual Studio 2022 (含「使用 C++ 的桌面开发」)

### 构建

```bash
# 安装依赖
flutter pub get

# 开发运行
flutter run -d windows

# 发布构建
flutter build windows
```

构建产物位于 `build/windows/x64/runner/Release/`。

## 项目结构

```
lib/
├── main.dart                  # 入口，初始化服务 & 主题
├── db/                        # 数据库 DAO 层
│   ├── database.dart
│   ├── image_dao.dart
│   └── tag_dao.dart
├── models/                    # 数据模型
│   ├── image_item.dart
│   ├── tag.dart
│   └── exif_data.dart
├── state/
│   └── app_state.dart         # 全局状态管理
├── services/                  # 业务服务
│   ├── database_service.dart
│   ├── import_service.dart
│   ├── library_service.dart
│   ├── exif_service.dart
│   ├── settings_service.dart
│   └── thumbnail_cache.dart
├── theme/
│   └── catppuccin.dart        # Catppuccin 色板 + ThemeData
├── pages/
│   ├── home_page.dart         # 主页面（三栏布局）
│   ├── settings_page.dart     # 设置对话框
│   └── about_page.dart        # 关于页
├── widgets/
│   ├── folder_panel.dart      # 文件夹面板
│   ├── tag_panel.dart         # 标签面板
│   ├── image_grid.dart        # 缩略图网格
│   ├── image_detail.dart      # 图片详情面板
│   ├── image_viewer.dart      # 全屏查看器
│   └── export_actions.dart    # 导出操作
└── utils/
    └── log_util.dart          # 日志工具
```

## 快捷键

| 键 | 功能 |
|----|------|
| `←` / `→` | 上一张 / 下一张图片 |
| `Esc` | 关闭查看器 / 取消选择 |
| `+` / `-` | 放大 / 缩小 |
| `0` | 适应窗口 |
| `I` | 切换 EXIF 面板 |
| `F` | 切换全屏 UI |
| `Ctrl` + 滚轮 | 定点缩放 |

## 许可证

BSD 3-Clause License
