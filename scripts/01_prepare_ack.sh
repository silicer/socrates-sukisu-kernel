#!/usr/bin/env bash
# 01_prepare_ack.sh —— 准备 ACK GKI 源码 + 工具链 + 第三方依赖
# 流程: 下载 clang r450784e → clone ACK kernel/common (android13-5.15.211_r00) → 07_fetch_deps.sh
# 环境变量: ACK_TAG (默认 android13-5.15.211_r00), KERNEL_DIR (默认 $ROOT_DIR/kernel_source)

source "$(dirname "$0")/common.sh"
setup_proxy

# ---------- 1. clang 工具链 ----------
# CI: 由 build.yml 的 cache/下载 step 解压到 tools/; 若 tools 不完整 (bin/clang 缺失) 则重新下载
if [[ ! -f "$TOOLS_DIR/bin/clang" ]]; then
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    log "CI: tools/ 不完整 (bin/clang 缺失), 重新下载解压 ..."
    rm -rf "$TOOLS_DIR"
    mkdir -p "$TOOLS_DIR"
    curl -fL --retry 3 --retry-delay 5 -o /tmp/clang.tar.gz "$CLANG_TARBALL_URL" || die "clang 下载失败"
    tar -xzf /tmp/clang.tar.gz -C "$TOOLS_DIR" || die "clang 解压失败"
    rm -f /tmp/clang.tar.gz
  else
    log "下载 clang $CLANG_VERSION ($CLANG_TARBALL_URL) ..."
    mkdir -p "$TOOLS_DIR"
    curl -fL --retry 3 --retry-delay 5 -o /tmp/clang.tar.gz "$CLANG_TARBALL_URL" || die "clang 下载失败"
    tar -xzf /tmp/clang.tar.gz -C "$TOOLS_DIR" || die "clang 解压失败"
    rm -f /tmp/clang.tar.gz
  fi
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
