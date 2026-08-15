#!/usr/bin/env bash
# 公共函数与常量 —— socrates (Redmi K60 Pro) ACK GKI 内核构建
# 用法: source scripts/common.sh

set -euo pipefail

# ---------- 常量 ----------
KERNEL_VERSION="5.15.211"
ANDROID_VERSION="android13-5.15"
ACK_TAG="android13-5.15.211_r00"
ACK_REPO="https://android.googlesource.com/kernel/common"

# clang r450784e (14.0.7, 与官方内核同款工具链) —— googlesource 已删旧分支头,
# 从 GitHub release 资产获取 (ravindu644/Android-Kernel-Tutorials tag=toolchains)
CLANG_VERSION="r450784e"
CLANG_TARBALL_URL="https://github.com/ravindu644/Android-Kernel-Tutorials/releases/download/toolchains/clang-r450784e.tar.gz"

# 版本串注入 (干净可复现; 注: 真机验证 -dirty 也能启动, 配置才是关键, 见 PLAN.md)
# 默认后缀 = 已验证的 40796 版本串 (无 dirty, 任何构建可复现)
OFFICIAL_VERSION_SUFFIX="${OFFICIAL_VERSION_SUFFIX:--00002-g13a57ace02a3}"
# 可选 SUBLEVEL 伪装 (默认不启用, 用 SUSFS 运行时伪装)
SPOOF_SUBLEVEL="${SPOOF_SUBLEVEL:-194}"

GITHUB_PROXY="${GITHUB_PROXY:-http://host.containers.internal:15524}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/kernel_source}"
TOOLS_DIR="${TOOLS_DIR:-$ROOT_DIR/tools}"
OUT_DIR="${OUT_DIR:-$KERNEL_DIR/out}"

log()  { echo -e "\033[1;32m[$(date '+%H:%M:%S')]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
die()  { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

setup_proxy() {
  # CI (GitHub Actions) 上不需要代理
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then return 0; fi
  if curl -s --max-time 3 -o /dev/null https://github.com 2>/dev/null; then
    return 0
  fi
  export https_proxy="$GITHUB_PROXY" http_proxy="$GITHUB_PROXY"
  git config --global http.proxy "$GITHUB_PROXY" || true
  git config --global https.proxy "$GITHUB_PROXY" || true
}

setup_toolchain() {
  export PATH="$TOOLS_DIR/bin:$PATH"
  command -v clang >/dev/null || die "clang 未找到，请先准备工具链: $TOOLS_DIR/bin (见 01_prepare_ack.sh)"
  export ARCH=arm64
  export LLVM=1
  export PAHOLE_BIN="${PAHOLE_BIN:-$(command -v pahole || echo /usr/bin/pahole)}"
}

# 从 GitHub raw 下载（走代理）
fetch_raw() { # $1=url  $2=输出文件
  local url="$1" out="$2"
  curl -fL --retry 3 --retry-delay 2 -o "$out" "$url" || die "下载失败: $url"
}
