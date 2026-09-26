#!/usr/bin/env bash
#
# PictureViewer2 — 打包成 Windows 可直接解压的单文件归档
#
# 用途：把仓库在某个提交上的完整内容（含 .git）打成一个 zip，
#       避免用「逐个文件复制」搬运时丢掉隐藏文件、生成目录混进去、路径过长等问题。
#
# 用法：
#   scripts/pack_for_windows.sh [选项]
#
# 选项：
#   --out-dir <目录>   归档输出目录，默认 <应用根>/dist
#   --name <基名>      归档基名，默认 PictureViewer2-src-<年月日>
#   --ref <提交>       打包哪个提交，默认 HEAD
#   --no-git           不把 .git 放进包（包会小一些，但失去历史与 git status 校验能力）
#   -h, --help         显示本帮助
#
# 产物：<out-dir>/<基名>.zip、<基名>.zip.sha256、<基名>.manifest.txt、TRANSFER-README.md
# 日志：<应用根>/logs/pack_for_windows_<时间戳>.log（可用 APP_LOG_DIR 覆盖）
#
# 本脚本的工作记录见同目录 pack_for_windows.sh.projectlog.md。

set -euo pipefail

MODULE="pack_for_windows"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

REF="HEAD"
PKG_NAME=""
OUT_DIR="${APP_ROOT}/dist"
INCLUDE_GIT=1

usage() {
  sed -n '3,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --out-dir)  OUT_DIR="${2:?--out-dir 需要取值}"; shift 2 ;;
    --out-dir=*) OUT_DIR="${1#*=}"; shift ;;
    --name)     PKG_NAME="${2:?--name 需要取值}"; shift 2 ;;
    --name=*)   PKG_NAME="${1#*=}"; shift ;;
    --ref)      REF="${2:?--ref 需要取值}"; shift 2 ;;
    --ref=*)    REF="${1#*=}"; shift ;;
    --no-git)   INCLUDE_GIT=0; shift ;;
    -h|--help)  usage ;;
    *) printf '未知参数：%s\n' "$1" >&2; usage ;;
  esac
done

if [ -z "$PKG_NAME" ]; then
  PKG_NAME="PictureViewer2-src-$(date '+%Y%m%d')"
fi

# ---------------------------------------------------------------- 日志入口

LOG_DIR="${APP_LOG_DIR:-${APP_ROOT}/logs}"
LOG_FILE="${LOG_DIR}/${MODULE}_$(date '+%Y%m%d_%H%M%S').log"
mkdir -p "$LOG_DIR"
: > "$LOG_FILE"

_emit() {  # _emit <级别> <消息>
  local line
  line="$(printf '[%s] [%-5s] [%s] %s' \
    "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$MODULE" "$2")"
  printf '%s\n' "$line"
  if [ -n "${LOG_FILE:-}" ]; then
    printf '%s\n' "$line" >> "$LOG_FILE"
  fi
}
log_info()  { _emit INFO  "$*"; }
log_warn()  { _emit WARN  "$*"; }
log_error() { _emit ERROR "$*"; }

STAGE=""
cleanup() {
  local code=$?
  if [ -n "$STAGE" ] && [ -d "$STAGE" ]; then
    rm -rf "$STAGE"
  fi
  log_info "结束：退出码 ${code}，耗时 ${SECONDS}s，日志 ${LOG_FILE}"
  exit "$code"
}
trap cleanup EXIT
trap 'log_warn "收到中断信号，准备清理临时目录"; exit 130' INT TERM HUP

# ---------------------------------------------------------------- 前置检查

cd "$APP_ROOT"
log_info "应用根目录：${APP_ROOT}"

for tool in git zip unzip sha256sum; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log_error "缺少命令：${tool}"
    exit 4
  fi
done

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log_error "${APP_ROOT} 不是 git 仓库。本脚本按提交打包，需要 git。"
  exit 4
fi

COMMIT_SHA="$(git rev-parse --short "$REF")"
COMMIT_SUBJECT="$(git log -1 --pretty=%s "$REF")"
log_info "打包提交：${REF} → ${COMMIT_SHA} ${COMMIT_SUBJECT}"

# 打包的是提交内容，工作区里没提交的改动不会进包。这里明确拦住，避免「以为带上了」。
DIRTY="$(git status --porcelain --untracked-files=no)"
if [ -n "$DIRTY" ]; then
  log_error "工作区有未提交的改动，打包的是提交内容，这些改动会丢："
  while IFS= read -r line; do log_error "  ${line}"; done <<< "$DIRTY"
  log_error "处置：先提交（或 git stash），再重跑本脚本。"
  exit 6
fi

TRACKED_COUNT="$(git ls-files | wc -l | tr -d ' ')"
log_info "跟踪文件数：${TRACKED_COUNT}"

# ---------------------------------------------------------------- 组装内容

STAGE="$(mktemp -d)"
# 包内顶层目录用固定短名，日期只出现在归档文件名里，解压后就是 <目标根>/PictureViewer2。
PKG_DIR_NAME="PictureViewer2"
PKG_DIR="${STAGE}/${PKG_DIR_NAME}"
OUT_DIR_ABS="$OUT_DIR"
case "$OUT_DIR_ABS" in
  /*) ;;
  *) OUT_DIR_ABS="${APP_ROOT}/${OUT_DIR}" ;;
esac
mkdir -p "$OUT_DIR_ABS"
mkdir -p "$PKG_DIR"

log_info "导出提交内容：git archive ${COMMIT_SHA} | tar -x"
git archive --format=tar "$REF" | tar -x -C "$PKG_DIR"

DOCS_COUNT=0
if [ -d "${APP_ROOT}/docs" ]; then
  cp -a "${APP_ROOT}/docs" "${PKG_DIR}/docs"
  DOCS_COUNT="$(find "${PKG_DIR}/docs" -type f | wc -l | tr -d ' ')"
  log_info "补入本地目录 docs/（未入库的审查报告）：${DOCS_COUNT} 个文件"
else
  log_warn "没有 docs/ 目录，跳过"
fi

GIT_FILES=0
if [ "$INCLUDE_GIT" -eq 1 ]; then
  cp -a "${APP_ROOT}/.git" "${PKG_DIR}/.git"
  GIT_FILES="$(find "${PKG_DIR}/.git" -type f | wc -l | tr -d ' ')"
  log_info "补入 .git/：${GIT_FILES} 个文件，解压后可用 git status 校验完整性"
else
  log_warn "--no-git：包里没有 .git，解压后无法用 git status 校验"
fi

# 包内说明：解压、核对、构建三步，随包一起走。
sed -e "s|@@PKG_NAME@@|${PKG_NAME}|g" \
    -e "s|@@COMMIT_SHA@@|${COMMIT_SHA}|g" \
    -e "s|@@COMMIT_SUBJECT@@|${COMMIT_SUBJECT}|g" \
    -e "s|@@DATE@@|$(date '+%Y-%m-%d')|g" \
    > "${PKG_DIR}/TRANSFER-README.md" <<'PV2_TRANSFER_README'
# PictureViewer2 转移到 Windows 的说明

本包由 `scripts/pack_for_windows.sh` 生成。包内是提交 `@@COMMIT_SHA@@`（@@COMMIT_SUBJECT@@）
的完整内容，额外带了 `.git/`（历史与校验用）与 `docs/`（本地审查报告，未入库）。

## 一、解压

1. 把整份 zip 拷到目标机器，不要用「逐个文件复制」的方式搬运。
2. 留出至少 1 GB 空间：依赖下载与构建产物会占用数百 MB。
3. 解压到短路径下，例如 `C:\dev\`，解压后目录是 `C:\dev\PictureViewer2`。
   Flutter 的构建路径很深，根目录越短越不容易撞上 Windows 的 260 字符路径上限。

## 二、核对完整性

1. 哈希比对。PowerShell 里执行：
   `Get-FileHash .\@@PKG_NAME@@.zip -Algorithm SHA256`
   结果与随包的 `@@PKG_NAME@@.zip.sha256` 文件里的值一致即可。
2. 文件数比对。解压后进入 `PictureViewer2` 目录，依次执行：
   `git config core.autocrlf false`
   `git status --short`
   除了 `?? docs/` 与 `?? TRANSFER-README.md`，不应出现其他行。
   出现其他行说明解压丢过文件，重新解压一次再比对。
3. 条目清单。随包的 `@@PKG_NAME@@.manifest.txt` 列出包内每个文件与大小，可逐条对照。

## 三、构建

```powershell
cd C:\dev\PictureViewer2
pwsh -File scripts\build_windows.ps1
```

产物在 `build\windows\x64\runner\release\pictureviewer.exe`。
脚本默认先跑 `flutter pub get`，再构建；首次运行需要能访问 pub 与 GitHub Releases。
如果公司网络不通，先配置代理，或给脚本加 `-Sqlite download` 之外的处置见脚本头部注释。

## 四、包里没有的东西

包里没有的都可由一条命令重新生成：

| 目录 | 为什么不带 | 怎么回来 |
|---|---|---|
| `.dart_tool/` | 依赖缓存，里面是打包机器的绝对路径 | `flutter pub get` |
| `build/` | 打包机器的构建产物 | `flutter build windows` |
| `linux/flutter/ephemeral/`、`windows/flutter/ephemeral/` | 按平台生成的插件注册文件 | `flutter pub get` |
| `logs/` | 打包机器的脚本日志 | 下次构建时自动生成 |
| `.flutter-plugins-dependencies` | 生成文件，内容含打包机器绝对路径；包内保留的是入库版本 | `flutter pub get` 会重写 |

打包时间：@@DATE@@
PV2_TRANSFER_README

# ---------------------------------------------------------------- 生成归档

ZIP_PATH="${OUT_DIR_ABS}/${PKG_NAME}.zip"
rm -f "$ZIP_PATH"
log_info "压缩：${ZIP_PATH}"
( cd "$STAGE" && zip -qr "$ZIP_PATH" "$PKG_DIR_NAME" )

ZIP_SIZE="$(du -h "$ZIP_PATH" | cut -f1)"
log_info "压缩完成：${ZIP_SIZE}"

# 清单与哈希
MANIFEST="${OUT_DIR_ABS}/${PKG_NAME}.manifest.txt"
{
  printf '# PictureViewer2 转移包条目清单\n'
  printf '# 生成时间：%s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '# 归档：%s\n' "$(basename "$ZIP_PATH")"
  printf '# 提交：%s %s\n' "$COMMIT_SHA" "$COMMIT_SUBJECT"
  printf '# 归档大小：%s\n' "$ZIP_SIZE"
  printf '# 字段：字节数 <TAB> 包内相对路径\n'
} > "$MANIFEST"
find "$STAGE" -type f -printf '%s\t%P\n' | sort -k2 >> "$MANIFEST"

SHA_FILE="${ZIP_PATH}.sha256"
( cd "$OUT_DIR_ABS" && sha256sum "$(basename "$ZIP_PATH")" > "$(basename "$SHA_FILE")" )
cp -f "${PKG_DIR}/TRANSFER-README.md" "${OUT_DIR_ABS}/TRANSFER-README.md"

# ---------------------------------------------------------------- 自检

log_info "自检：zip 完整性（unzip -t）"
if unzip -tq "$ZIP_PATH" >/dev/null; then
  log_info "自检通过：所有条目 CRC 校验正常"
else
  log_error "自检失败：unzip -t 报错，归档可能损坏"
  exit 7
fi

ENTRIES_TOTAL="$(unzip -Z1 "$ZIP_PATH" | wc -l | tr -d ' ')"
ENTRIES_FILE="$(unzip -Z1 "$ZIP_PATH" | grep -v '/$' | wc -l | tr -d ' ')"
ENTRIES_FILE_NOGIT="$(unzip -Z1 "$ZIP_PATH" | grep -v '/$' | grep -v "^${PKG_DIR_NAME}/\.git/" | wc -l | tr -d ' ')"
EXPECT_NOGIT=$(( TRACKED_COUNT + DOCS_COUNT + 1 ))
log_info "条目：总 ${ENTRIES_TOTAL}；文件 ${ENTRIES_FILE}；非 .git 文件 ${ENTRIES_FILE_NOGIT}（期望 ${EXPECT_NOGIT} = 跟踪 ${TRACKED_COUNT} + docs ${DOCS_COUNT} + TRANSFER-README 1）"
if [ "$ENTRIES_FILE_NOGIT" -ne "$EXPECT_NOGIT" ]; then
  log_error "自检失败：非 .git 文件数与期望不符，检查上面的条目清单"
  exit 7
fi

for f in .metadata .gitignore pubspec.yaml pubspec.lock analysis_options.yaml README.md LICENSE \
         windows/CMakeLists.txt linux/CMakeLists.txt \
         scripts/build_windows.ps1 scripts/build_linux.sh scripts/pack_for_windows.sh \
         lib/main.dart lib/utils/path_util.dart lib/utils/file_io.dart \
         test/utils/file_io_test.dart docs/code-review-2026-09-26.md TRANSFER-README.md; do
  if unzip -Z1 "$ZIP_PATH" | grep -qx "${PKG_DIR_NAME}/${f}"; then
    log_info "自检命中：${f}"
  else
    log_error "自检失败：包内缺少 ${f}"
    exit 7
  fi
done

for pat in '\.dart_tool' 'build' 'ephemeral' 'logs' 'dist'; do
  if unzip -Z1 "$ZIP_PATH" | grep -v "^${PKG_DIR_NAME}/\.git/" | grep -qE "(^|/)${pat}/"; then
    log_error "自检失败：包内不该出现 ${pat}/"
    exit 7
  fi
done
log_info "自检通过：包内没有 .dart_tool、build、ephemeral、logs、dist（.git 内的 reflog 目录不计）"

log_info "产物："
log_info "  ${ZIP_PATH}（${ZIP_SIZE}）"
log_info "  ${SHA_FILE}"
log_info "  ${MANIFEST}"
log_info "  ${OUT_DIR_ABS}/TRANSFER-README.md"
log_info "校验哈希：$(cut -d' ' -f1 "$SHA_FILE")"
log_info "打包成功"
