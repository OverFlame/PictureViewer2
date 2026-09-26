#!/usr/bin/env bash
#
# PictureViewer2 — Linux 构建脚本
#
# 用法：
#   scripts/build_linux.sh [选项]
#
# 选项：
#   --mode <release|debug|profile>  构建模式，默认 release
#   --sqlite <system|download>      sqlite3 来源，默认 system（用系统 libsqlite3，不访问 GitHub）；
#                                   download 会把仓库 pubspec 里 linux 那一行临时改成 download
#   --clean                         构建前执行 flutter clean
#   --no-pub                        跳过 flutter pub get
#   -h, --help                      显示本帮助
#
# 产物：build/linux/<架构>/<模式>/bundle/
# 日志：<应用根>/logs/build_linux_<时间戳>.log（可用 APP_LOG_DIR 覆盖）
#
# 环境变量覆盖：FLUTTER_BIN、APP_LOG_DIR、FLUTTER_STORAGE_BASE_URL、PUB_HOSTED_URL
#   把 FLUTTER_STORAGE_BASE_URL / PUB_HOSTED_URL 设为空字符串可关闭镜像。
#
# 本脚本的工作记录见同目录 build_linux.sh.projectlog.md。

set -euo pipefail

MODULE="build_linux"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

MODE="release"
SQLITE_SOURCE="system"
DO_CLEAN=0
DO_PUB=1

usage() {
  sed -n '3,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)    MODE="${2:?--mode 需要取值}"; shift 2 ;;
    --mode=*)  MODE="${1#*=}"; shift ;;
    --sqlite)    SQLITE_SOURCE="${2:?--sqlite 需要取值}"; shift 2 ;;
    --sqlite=*)  SQLITE_SOURCE="${1#*=}"; shift ;;
    --clean)   DO_CLEAN=1; shift ;;
    --no-pub)  DO_PUB=0; shift ;;
    -h|--help) usage ;;
    *) printf '未知参数：%s\n' "$1" >&2; usage ;;
  esac
done

case "$MODE" in
  release|debug|profile) ;;
  *) printf '非法 --mode：%s（可选 release/debug/profile）\n' "$MODE" >&2; exit 2 ;;
esac
case "$SQLITE_SOURCE" in
  system|download) ;;
  *) printf '非法 --sqlite：%s（可选 system/download）\n' "$SQLITE_SOURCE" >&2; exit 2 ;;
esac

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

run() {  # 执行外部命令，输出同时进终端与日志文件
  log_info "执行：$*"
  local status=0
  set +e
  "$@" 2>&1 | tee -a "$LOG_FILE"
  status=${PIPESTATUS[0]}
  set -e
  if [ "$status" -ne 0 ]; then
    log_error "命令失败（退出码 ${status}）：$*"
    return "$status"
  fi
  return 0
}

# ------------------------------------------------- 临时改写 pubspec.yaml

PUBSPEC="${APP_ROOT}/pubspec.yaml"
LOCKFILE="${APP_ROOT}/pubspec.lock"
BACKUP_DIR=""
PATCHED=0

restore_pubspec() {
  local code=$?
  if [ "$PATCHED" -eq 1 ] && [ -n "$BACKUP_DIR" ]; then
    if cp -f "${BACKUP_DIR}/pubspec.yaml" "$PUBSPEC"; then
      log_info "已还原 pubspec.yaml"
    else
      log_error "还原 pubspec.yaml 失败，备份留在 ${BACKUP_DIR}"
    fi
    if [ -f "${BACKUP_DIR}/pubspec.lock" ]; then
      if cp -f "${BACKUP_DIR}/pubspec.lock" "$LOCKFILE"; then
        log_info "已还原 pubspec.lock"
      else
        log_error "还原 pubspec.lock 失败，备份留在 ${BACKUP_DIR}"
      fi
    fi
    rm -rf "$BACKUP_DIR"
  fi
  log_info "构建结束：退出码 ${code}，耗时 ${SECONDS}s，日志 ${LOG_FILE}"
  exit "$code"
}
trap restore_pubspec EXIT
trap 'log_warn "收到中断信号，准备回滚"; exit 130' INT TERM HUP

find_libsqlite3_so() {  # 打印 dlopen("libsqlite3.so") 能命中的路径
  local dir
  local -a dirs
  IFS=':' read -r -a dirs <<< "${LD_LIBRARY_PATH:-}:${HOME}/.local/lib:/usr/lib/x86_64-linux-gnu:/usr/lib:/usr/lib/aarch64-linux-gnu:/lib"
  for dir in "${dirs[@]}"; do
    if [ -n "$dir" ] && [ -e "${dir}/libsqlite3.so" ]; then
      printf '%s\n' "${dir}/libsqlite3.so"
      return 0
    fi
  done
  return 1
}

patch_pubspec_for_sqlite() {
  if [ "$SQLITE_SOURCE" = "system" ]; then
    local found=""
    if found="$(find_libsqlite3_so)"; then
      log_info "系统 sqlite3：${found}"
    else
      log_error "找不到可被 dlopen(\"libsqlite3.so\") 命中的系统库。"
      log_error "处置：安装 libsqlite3-dev，或改用 --sqlite download（需要能访问 GitHub）。"
      exit 3
    fi
  fi
  if grep -qE '^hooks:' "$PUBSPEC"; then
    if [ "$SQLITE_SOURCE" != "download" ]; then
      log_info "pubspec.yaml 已有 hooks 段，沿用其中的 sqlite3 配置"
      return 0
    fi
    # 仓库里的 hooks 段按平台写，linux 那一行是 system。显式要 download 时把它临时改成 download。
    if ! grep -qE '^[[:space:]]+linux:[[:space:]]*system[[:space:]]*$' "$PUBSPEC"; then
      log_error "pubspec.yaml 有 hooks 段，但没找到 'linux: system' 那一行，无法临时切成 download。"
      log_error "处置：手工把 hooks.user_defines.sqlite3.source 里的 linux 改成 download，或删掉整个 hooks 段后重试。"
      exit 2
    fi
    BACKUP_DIR="$(mktemp -d)"
    cp -f "$PUBSPEC" "${BACKUP_DIR}/pubspec.yaml"
    if [ -f "$LOCKFILE" ]; then
      cp -f "$LOCKFILE" "${BACKUP_DIR}/pubspec.lock"
    fi
    sed -i -E 's/^([[:space:]]*)linux:[[:space:]]*system[[:space:]]*$/\1linux: download/' "$PUBSPEC"
    PATCHED=1
    log_warn "已临时把 pubspec.yaml hooks 段里的 linux 来源改为 download，构建结束后还原 pubspec.yaml 与 pubspec.lock"
    return 0
  fi
  BACKUP_DIR="$(mktemp -d)"
  cp -f "$PUBSPEC" "${BACKUP_DIR}/pubspec.yaml"
  if [ -f "$LOCKFILE" ]; then
    cp -f "$LOCKFILE" "${BACKUP_DIR}/pubspec.lock"
  fi
  {
    printf '\n# 以下 hooks 段由 scripts/build_linux.sh 临时追加，构建结束后自动还原。\n'
    printf 'hooks:\n  user_defines:\n    sqlite3:\n      source: %s\n' "$SQLITE_SOURCE"
  } >> "$PUBSPEC"
  PATCHED=1
  log_warn "已临时写入 hooks.user_defines.sqlite3.source=${SQLITE_SOURCE}，构建结束后还原 pubspec.yaml 与 pubspec.lock"
}

# ---------------------------------------------------------------- 环境准备

if [ -x "${HOME}/flutter/bin/flutter" ]; then
  export PATH="${HOME}/flutter/bin:${PATH}"
  log_info "已把 ${HOME}/flutter/bin 加入 PATH"
fi

if [ -e "${HOME}/.local/lib/libsqlite3.so" ]; then
  export LD_LIBRARY_PATH="${HOME}/.local/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
  log_info "已把 ${HOME}/.local/lib 加入 LD_LIBRARY_PATH（运行时定位 libsqlite3.so）"
fi

if [ -z "${FLUTTER_STORAGE_BASE_URL+x}" ]; then
  export FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
fi
if [ -z "${PUB_HOSTED_URL+x}" ]; then
  export PUB_HOSTED_URL="https://pub.flutter-io.cn"
fi
log_info "FLUTTER_STORAGE_BASE_URL=${FLUTTER_STORAGE_BASE_URL:-（已关闭）}"
log_info "PUB_HOSTED_URL=${PUB_HOSTED_URL:-（已关闭）}"

FLUTTER="${FLUTTER_BIN:-$(command -v flutter || true)}"
if [ -z "$FLUTTER" ] || [ ! -x "$FLUTTER" ]; then
  log_error "找不到可执行的 flutter。用法：FLUTTER_BIN=/path/to/flutter $0"
  exit 4
fi
log_info "flutter：${FLUTTER}"
log_info "应用根目录：${APP_ROOT}"
log_info "构建模式：${MODE}；sqlite3 来源：${SQLITE_SOURCE}"

cd "$APP_ROOT"
run "$FLUTTER" --version

if [ "$DO_CLEAN" -eq 1 ]; then
  run "$FLUTTER" clean
fi

patch_pubspec_for_sqlite

if [ "$DO_PUB" -eq 1 ]; then
  run "$FLUTTER" pub get
fi

run "$FLUTTER" build linux "--${MODE}"

# ---------------------------------------------------------------- 产物检查

BUNDLE="$(find "${APP_ROOT}/build/linux" -maxdepth 3 -type d -name bundle -print -quit 2>/dev/null || true)"
if [ -z "$BUNDLE" ]; then
  log_error "构建命令成功，但没找到 build/linux/<架构>/<模式>/bundle 目录"
  exit 5
fi
BINARY="${BUNDLE}/pictureviewer"
if [ ! -x "$BINARY" ]; then
  log_error "bundle 里没有可执行文件：${BINARY}"
  exit 5
fi
log_info "产物：${BUNDLE}（$(du -sh "$BUNDLE" | cut -f1)）"
log_info "可执行文件：${BINARY}"

if [ "$SQLITE_SOURCE" = "system" ]; then
  SYS_SQLITE="$(find_libsqlite3_so)"
  install -D -m 0755 "$SYS_SQLITE" "${BUNDLE}/lib/libsqlite3.so"
  log_info "已把 ${SYS_SQLITE} 复制为 ${BUNDLE}/lib/libsqlite3.so（随包分发，运行时无需 LD_LIBRARY_PATH）"
fi

MISSING="$(ldd "$BINARY" 2>/dev/null | grep 'not found' || true)"
if [ -n "$MISSING" ]; then
  log_warn "ldd 报告缺失的动态库："
  while IFS= read -r line; do log_warn "  ${line}"; done <<< "$MISSING"
else
  log_info "ldd 未报告缺失的动态库"
fi

log_info "运行：${BINARY}"
log_info "构建成功"
