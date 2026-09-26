# pack_for_windows.sh 工作记录

本文件是 `scripts/pack_for_windows.sh` 的工作记录，只追加不重写。
每条记「日期 / 目标 / 动作（改了哪些文件）/ 验证（命令与结果）」，未完成项与已知缺口写在当条末尾。

## 2026-09-26 首次实现

- 目标：把仓库在某个提交上的完整内容打成一个 zip，供转移到 Windows 机器上构建，替代容易丢文件的逐个复制。
- 背景：逐个复制会丢的东西有四类。隐藏文件与目录（`.git`、`.metadata`、`.gitignore`）在图形界面里默认不显示；
  生成目录混在一起带过去（`.dart_tool/` 77M、`build/` 35M、`linux/flutter/ephemeral/` 18M），
  它们内部记的是打包机器的绝对路径，到了 Windows 上会失效；深层路径在中途失败后难以判断缺了哪些文件；
  拷完没有任何完整性凭据，出问题只能重来。
- 动作：新增 `scripts/pack_for_windows.sh` 与本文件；`.gitignore` 追加 `dist/`（归档输出目录）。
  脚本按提交打包（`git archive`），额外补入 `.git/` 与本地 `docs/`，生成包内 `TRANSFER-README.md`、
  条目清单 `*.manifest.txt` 与哈希文件 `*.zip.sha256`。打包前拦截未提交改动，避免把工作区改动误当已带上；
  打包后做四类自检：`unzip -t` 的 CRC 校验、非 `.git` 文件数与「跟踪数 + docs 数 + 1」比对、
  关键文件逐个命中、排除目录逐个缺席。日志走统一入口，落 `<应用根>/logs/`。
- 验证：2026-09-26 首次运行成功，退出码 0。归档 1008K，条目总 372（文件 240，非 `.git` 文件 166 =
  跟踪 164 + `docs/` 1 + `TRANSFER-README.md` 1），`unzip -t` 报全部条目 CRC 正常。
  另在脚本自检之外做了独立复核：解压到 `/tmp/xfer-verify-final` 后，164 个跟踪文件逐个比对 sha256 与源一致；
  `docs/` 内容一致；解压树里 `git config core.autocrlf false` 之后 `git status --short` 只有
  `?? docs/` 与 `?? TRANSFER-README.md` 两行；两个 shell 脚本的 755 可执行位保留；
  `.dart_tool/`、`build/`、`logs/`、`dist/`、各平台 `ephemeral/` 确认缺席。
- 运行中发现并修掉的两处自身缺陷。第一处：最初把归档基名同时当作包内顶层目录名，解压出来的目录叫
  `PictureViewer2-src-20260926`，与说明里写的 `C:\dev\PictureViewer2` 不符；改成包内固定用 `PictureViewer2`，
  日期只留在归档文件名。第二处：排除目录自检的正则漏掉 `.git` 内部的 reflog 目录（`.git/logs/`），
  首次运行误报 `logs/` 命中并以退出码 7 中止；改成先过滤掉 `.git` 前缀再匹配。
- 未提交改动拦截已实地生效：改动脚本后第一次重跑被脚本自己拦下，退出码 6，并在日志里打印
  `M scripts/pack_for_windows.sh`。
- 已知缺口：包内不含 `.dart_tool/`、`build/`、各平台 `ephemeral/` 与 `logs/`，这些需要在 Windows 上由
  `flutter pub get` 与构建重新生成；本机无法验证 Windows 侧的解压行为，那一步要在目标机器上做。
