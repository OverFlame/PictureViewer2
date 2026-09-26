# PictureViewer

基于 Flutter 的现代化桌面图片浏览器，支持标签管理、EXIF 查看、全屏预览与主题切换。主要面向 **Windows / Linux**，macOS 亦可构建运行。

## 特性

- **缩略图网格浏览** — 可调节列数（2~10）的自适应网格布局
- **文件夹管理** — 多文件夹导入 / 删除，动态扫描，资源管理器式树形浏览
- **标签系统** — 多命名空间标签，AND / OR / NOT 三维筛选，及自定义布尔表达式高级筛选
- **全屏查看器** — 缩放/平移、键盘导航、Ctrl+滚轮定点缩放、EXIF 面板
- **EXIF 元数据** — 光圈、快门、ISO、焦距、尺寸等详细信息
- **深色 / 浅色主题** — Catppuccin Mocha & Latte 色板，支持跟随系统
- **导出分享** — 另存为、打开文件位置（跨平台文件管理器定位）
- **缩略图缓存** — 三层缓存（内存 LRU → 磁盘 → 原图生成），可调磁盘缓存上限

## 技术栈

| 层 | 技术 |
|----|------|
| 框架 | Flutter 3.x（桌面：Windows / Linux / macOS） |
| 语言 | Dart |
| 状态管理 | Provider + ChangeNotifier |
| 数据库 | SQLite（sqflite + sqflite_common_ffi） |
| 图片解码 | dart:ui（`instantiateImageCodec`） |
| EXIF 读取 | exif |
| 主题 | Catppuccin |
| 持久化 | shared_preferences |
| 文件选择 | file_picker |
| 拖拽 | desktop_drop |
| 路径 / 哈希 | path / crypto |

## 开始

### 环境要求

- Flutter SDK ≥ 3.44，Dart ≥ 3.12（见 `pubspec.yaml` 的 `environment` 约束）
- **Windows** 10/11（x64）：已启用桌面开发，Visual Studio 2022（含「使用 C++ 的桌面开发」）
- **Linux**：`clang`、`cmake`、`ninja-build`、`pkg-config` 及 GTK 3 开发库

  ```bash
  # Debian / Ubuntu
  sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
  ```

### 构建

用仓库自带的脚本构建，脚本会处理 sqlite3 原生库的来源（见下）。

```bash
# Linux：产物在 build/linux/<架构>/release/bundle/
scripts/build_linux.sh                  # 发布构建
scripts/build_linux.sh --mode debug     # 调试构建
scripts/build_linux.sh --clean          # 先执行 flutter clean

# Windows：产物在 build\windows\<架构>\runner\Release\
pwsh -File scripts\build_windows.ps1
```

开发运行仍用 `flutter run -d linux` / `flutter run -d windows`。

两个脚本的日志写在 `<仓库根>/logs/`（可用环境变量 `APP_LOG_DIR` 改位置），
全部参数见 `scripts/build_linux.sh --help` 与 `scripts/build_windows.ps1` 头部注释。

#### 关于 sqlite3 原生库

`sqlite3` 包的构建钩子默认从 GitHub Releases 下载预编译库，网络不通时报
`SocketException: Connection timed out ... address = github.com` 并让整个构建失败。因此：

- **Linux** 脚本默认 `--sqlite system`：构建时临时往 `pubspec.yaml` 追加
  `hooks.user_defines.sqlite3.source: system`，构建结束（含被中断）后自动还原。
  这条路径要求系统里存在可被 `dlopen("libsqlite3.so")` 命中的库
  （Debian / Ubuntu 上装 `libsqlite3-dev`），脚本会把它复制进产物 `bundle/lib/`，
  目标机不需要再装。想走下载则加 `--sqlite download`。
- **Windows** 脚本默认 `-Sqlite download`：Windows 没有系统 `sqlite3.dll`，仍走下载。
  先配好代理再重试，或自备 `sqlite3.dll` 并把 `hooks` 段的 `source` 写成 `windows: sqlite3`。

## 项目结构

```
lib/
├── main.dart                  # 入口，初始化服务 & 主题
├── db/                        # 数据库 DAO 层（模型内嵌于各 DAO 文件）
│   ├── database.dart          # DatabaseManager 单例（WAL + 外键 + 迁移）
│   ├── tables.dart            # 建表 DDL + 版本迁移框架
│   ├── image_dao.dart         # ImageItem 模型 + 图片 DAO
│   ├── tag_dao.dart           # Tag / TagCount 模型 + 标签 DAO
│   └── folder_dao.dart        # VirtualFolder / FolderPath 模型 + 文件夹 DAO
├── state/
│   └── app_state.dart         # 全局状态管理（ChangeNotifier）
├── services/                  # 业务服务
│   ├── file_scanner.dart      # 文件系统递归扫描 + 增量对比
│   ├── import_service.dart    # 批量导入 + 目录树镜像
│   ├── thumbnail_cache.dart   # 三层缩略图缓存
│   ├── exif_service.dart      # EXIF 读取（ExifData 模型）
│   └── settings_service.dart  # 设置持久化（SharedPreferences）
├── theme/
│   └── catppuccin.dart        # Catppuccin 色板 + ThemeData
├── pages/
│   ├── home_page.dart         # 主页面（三栏布局）
│   ├── settings_page.dart     # 设置对话框
│   └── about_page.dart        # 关于页
├── widgets/
│   ├── folder_panel.dart      # 文件夹面板（树形浏览 + 导入）
│   ├── tag_panel.dart         # 标签面板（分组 + 筛选）
│   ├── image_grid.dart        # 缩略图网格
│   ├── image_detail.dart      # 图片详情面板
│   ├── image_viewer.dart      # 全屏查看器
│   ├── export_actions.dart    # 导出操作（另存为 / 打开文件位置）
│   ├── filter_dialog.dart     # 高级筛选表达式对话框
│   └── move_folder_dialog.dart # 移动文件夹选择器
└── utils/
    ├── log_util.dart          # 日志工具
    └── filter_expression.dart # 布尔表达式解析 + SQL 编译
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

## 高级筛选表达式

顶部工具栏的「高级筛选」支持自定义布尔表达式（激活后替换左侧标签筛选）：

| 语法 | 含义 |
|------|------|
| `风景` | 按标签名匹配（不区分大小写，跨命名空间，同名取并集） |
| `地点:风景` | 指定命名空间 `地点` 下的标签 `风景` |
| `"带 空格 名字"` | 引号内按名称精确匹配（含空格/特殊字符） |
| `!` | 非（NOT） |
| `&&` / `&` | 与（AND） |
| `||` / `|` | 或（OR） |
| `()` | 改变优先级 |

优先级：`!` > `&&` > `||`。示例：`((风景||人像)&&!私密)||收藏`。

## 许可证

BSD 3-Clause License
