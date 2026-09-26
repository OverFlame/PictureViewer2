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
- 验证：待首次运行后补记。
- 已知缺口：包内不含 `.dart_tool/`、`build/`、各平台 `ephemeral/` 与 `logs/`，这些需要在 Windows 上由
  `flutter pub get` 与构建重新生成；本机无法验证 Windows 侧的解压行为，那一步要在目标机器上做。
