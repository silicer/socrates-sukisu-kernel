#!/usr/bin/env bash
# 01_prepare_ack.sh —— 准备 ACK GKI 源码 + 工具链 + 第三方依赖
# 流程: 下载 clang r450784e → clone ACK kernel/common (android13-5.15.211_r00) → 07_fetch_deps.sh
# 环境变量: ACK_TAG (默认 android13-5.15.211_r00), KERNEL_DIR (默认 $ROOT_DIR/kernel_source)

source "$(dirname "$0")/common.sh"
setup_proxy

# ---------- 1. clang 工具链 ----------
# CI: 由 build.yml 的 cache/下载 step 解压到 tools/; 本地: 自行下载
if [[ ! -f "$TOOLS_DIR/bin/clang" ]]; then
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "诊断: ROOT_DIR=$ROOT_DIR TOOLS_DIR=$TOOLS_DIR pwd=$(pwd)"
    ls -la "$ROOT_DIR/tools/" 2>/dev/null | head -5
    ls -la "$ROOT_DIR/tools/bin/clang" 2>/dev/null || echo "tools/bin/clang 不存在"
    die "clang 未就绪: $TOOLS_DIR/bin/clang (CI 下载 step 应已解压到 tools/)"
  fi
  log "下载 clang $CLANG_VERSION ($CLANG_TARBALL_URL) ..."
  mkdir -p "$TOOLS_DIR"
  curl -fL --retry 3 --retry-delay 5 -o /tmp/clang.tar.gz "$CLANG_TARBALL_URL" || die "clang 下载失败"
  tar -xzf /tmp/clang.tar.gz -C "$TOOLS_DIR" --strip-components=1 --overwrite || die "clang 解压失败"
  rm -f /tmp/clang.tar.gz
fi
"$TOOLS_DIR/bin/clang" --version | head -1

# ---------- 2. ACK kernel/common ----------
if [[ ! -d "$KERNEL_DIR" ]]; then
  log "clone ACK kernel/common @ $ACK_TAG ..."
  mkdir -p "$(dirname "$KERNEL_DIR")"
  git clone --depth 1 --branch "$ACK_TAG" "$ACK_REPO" "$KERNEL_DIR" || die "ACK clone 失败"
elif [[ ! -f "$KERNEL_DIR/Makefile" ]]; then
  die "$KERNEL_DIR 存在但不是内核树，请清理后重试"
else
  log "使用现有源码树: $KERNEL_DIR"
fi
grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' "$KERNEL_DIR/Makefile" | awk '{print $2, $3}' | tr '\n' ' '; echo

# ---------- 3. 第三方依赖 (SukiSU_patch / susfs4ksu / susfs 模块) ----------
bash "$ROOT_DIR/scripts/07_fetch_deps.sh"

log "✅ 源码与依赖就绪: KERNEL_DIR=$KERNEL_DIR TOOLS_DIR=$TOOLS_DIR"
