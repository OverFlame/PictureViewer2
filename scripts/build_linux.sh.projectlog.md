# build_linux.sh 工作记录

本文件是 `scripts/build_linux.sh` 的工作记录，只追加不重写。
每条记「日期 / 目标 / 动作（改了哪些文件）/ 验证（命令与结果）」，未完成项与已知缺口写在当条末尾。

## 2026-09-26 首次实现

- 目标：一条命令在本机产出可运行的 Linux 发布包，且不访问 GitHub 下载 sqlite3 预编译产物。
- 背景（实测）：本机 `flutter build linux --release` 在没有 `hooks` 段时失败，输出
  `Original cause: SocketException: Connection timed out (OS Error: Connection timed out, errno = 110), address = github.com`
  与 `ERROR: Building assets for package:sqlite3 failed.`，最后 `Build process failed`。
  根因是 `sqlite3` 包的构建钩子默认从 GitHub Releases 取预编译库（见 `sqlite3-3.6.0/lib/src/hook/compile/description.dart`）。
- 动作：新增 `scripts/build_linux.sh`。脚本默认 `--sqlite system`：在 `pubspec.yaml` 末尾临时追加
  `hooks: user_defines: sqlite3: source: system`，用 `EXIT/INT/TERM/HUP` trap 在构建结束后还原
  `pubspec.yaml` 与 `pubspec.lock`（flutter 在本机会因镜像变量重写 lock）。
  `--sqlite download` 可退回默认下载路径，`--mode` 可选 release/debug/profile，另有 `--clean`、`--no-pub`。
  同时新增本文件，并在 `.gitignore` 加入 `logs/`。
- 验证：
  - `bash -n scripts/build_linux.sh` 通过；`--help` 正常输出；`--mode banana` 打印错误并以退出码 2 结束。
  - 端到端（干净副本 `/tmp/pv2build2`，无 `hooks` 段）：`bash scripts/build_linux.sh --mode release`
    退出码 0，耗时 22s，产物 `build/linux/x64/release/bundle`（25M），日志写在副本的 `logs/build_linux_20260926_164405.log`。
  - 还原校验：构建后 `grep -c '^hooks:' pubspec.yaml` 得 0；`pubspec.lock` 与构建前 `cmp` 一致。
  - 对照实验：同一个干净副本直接 `flutter build linux --release` 失败，报
    `Original cause: SocketException: Connection timed out ... address = github.com` 与
    `ERROR: Building assets for package:sqlite3 failed.`，即脚本修的正是这条路径。
  - 运行时定位：引擎库 `bundle/lib/libflutter_linux_gtk.so` 的 RUNPATH 是 `$ORIGIN`，
    Dart 侧 `dlopen("libsqlite3.so")` 因此命中 `bundle/lib/libsqlite3.so`。
    用 `clang -ldl` 写的小工具验证：`LD_LIBRARY_PATH=<bundle>/lib` 时 `dlopen("libsqlite3.so")` 成功
    （SQLite 3.46.1），不给搜索路径时失败；所以把库复制进 `bundle/lib/` 是必需的，不是冗余步骤。
  - `ldd bundle/pictureviewer` 未报告缺失的动态库。
- 已知缺口：
  - 没有在真机上启动过 GUI。启动会写入用户真实的 `<文档>/PictureViewer/pv2.db`，所以没做这一步。
  - `--sqlite download` 分支未验证（本机到 github.com 不通，正是它要走的路径）。
  - `--mode debug`、`--mode profile`、`--clean`、`--no-pub` 没有逐一跑过，只跑了 release。
  - 构建期 `flutter` 会因镜像变量改写 `pubspec.lock`（本次解析出 85 个依赖版本变动），
    脚本在退出时还原，所以构建实际用的版本与仓库 lock 固定的版本可能不同。
  - `--sqlite system` 要求系统里有 `libsqlite3.so`；本机靠 `~/.local/lib/libsqlite3.so` 软链，
    干净的 Debian/Ubuntu 需要装 `libsqlite3-dev`。
