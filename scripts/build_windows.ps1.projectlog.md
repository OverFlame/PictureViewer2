# build_windows.ps1 工作记录

本文件是 `scripts/build_windows.ps1` 的工作记录，只追加不重写。
每条记「日期 / 目标 / 动作（改了哪些文件）/ 验证（命令与结果）」，未完成项与已知缺口写在当条末尾。

## 2026-09-26 首次实现

- 目标：在 Windows 上一条命令产出 `build\windows\<架构>\runner\<模式>\pictureviewer.exe`。
- 背景：Windows 不带系统 `sqlite3.dll`，所以不能用 `source: system`；默认 `source: sqlite3`
  会从 GitHub Releases 下载预编译 `sqlite3.dll`。因此脚本默认 `-Sqlite download`，
  并在 `pubspec.yaml` 的 `hooks` 段把 `source` 写成标量 `system` 时给出警告（这会让 Windows 构建也去找系统库）。
- 动作：新增 `scripts/build_windows.ps1` 与本文件。
  脚本提供 `-Mode`、`-Sqlite`、`-Clean`、`-NoPub`、`-FlutterBin`；
  日志走 `Write-Log`（时间戳 + 级别 + 模块名），文件写到 `<应用根>\logs\build_windows_<时间戳>.log`；
  失败时用 catch 打完整异常与三步排查顺序；产物检查包含 `sqlite3.dll` 是否随包落地。
- 验证：**未执行**。本机（Linux）没有 PowerShell（`pwsh`、`powershell` 都不存在），
  只做了人工通读；语法与行为需要在 Windows 机器上第一次运行时确认。
- 已知缺口：未在 Windows 上运行过；`Tee-Object` 与 `$LASTEXITCODE` 的组合依赖 PowerShell 5.1 及以上；
  未处理 MSBuild 路径过长以外的构建环境问题（例如缺 Windows SDK）。
