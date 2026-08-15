#!/usr/bin/env bash
# 03_build_kernel.sh —— 编译内核（LLVM 全工具链 + thin LTO）
# 用法: scripts/03_build_kernel.sh [-j N]
# 环境: CCACHE_ENABLE=1 时启用 ccache(编译期) + thinLTO 链接缓存(链接期, ld-wrapper),
#       用于 GitHub Actions 缓存复用 (参考 Action-Build):
#         CCACHE_DIR (默认 $ROOT_DIR/.ccache)  CCACHE_MAX (默认 4G)
#         LDCACHE_DIR (默认 $ROOT_DIR/.thinlto-cache)  THINLTO_CACHE_SIZE (默认 2g)

source "$(dirname "$0")/common.sh"
setup_toolchain

JOBS="${1:-}"
JOBS="${JOBS#-j}"
# 默认留一个核给系统 (4 核机器 = -j3); 可显式传 -jN 覆盖
JOBS="${JOBS:-$(( $(nproc) - 1 ))}"

cd "$KERNEL_DIR"
[[ -f out/.config ]] || die "缺少 out/.config，请先运行 scripts/02_set_config.sh"

CCACHE_ENABLE="${CCACHE_ENABLE:-0}"
MAKE_CC="clang"
MAKE_EXTRA=()

if [[ "$CCACHE_ENABLE" == "1" ]]; then
  command -v ccache >/dev/null || die "需要 ccache (apt install ccache / pacman -S ccache)"
  export CCACHE_DIR="${CCACHE_DIR:-$ROOT_DIR/.ccache}"
  CCACHE_MAX="${CCACHE_MAX:-4G}"
  mkdir -p "$CCACHE_DIR"
  ccache -M "$CCACHE_MAX" >/dev/null
  MAKE_CC="ccache clang"

  # thinLTO 链接缓存: ld-wrapper 给每次 lld 调用附加 --thinlto-cache-dir (参考 Action-Build)
  LDCACHE_DIR="${LDCACHE_DIR:-$ROOT_DIR/.thinlto-cache}"
  mkdir -p "$LDCACHE_DIR"
  LD_WRAPPER="$ROOT_DIR/.ld-wrapper"
  LLD_BIN="$(command -v ld.lld)"
  printf '#!/bin/bash\nexec "%s" "$@" --thinlto-cache-dir="%s" --thinlto-cache-policy=cache_size_bytes=%s --thinlto-jobs=%s\n' \
    "$LLD_BIN" "$LDCACHE_DIR" "${THINLTO_CACHE_SIZE:-2g}" "$(nproc)" > "$LD_WRAPPER"
  chmod +x "$LD_WRAPPER"
  MAKE_EXTRA+=(LD="$LD_WRAPPER")
  log "缓存: ccache=$CCACHE_DIR (max $CCACHE_MAX) + thinLTO=$LDCACHE_DIR (${THINLTO_CACHE_SIZE:-2g})"
fi

log "开始编译 (-j$JOBS, LLVM=1, CC=$MAKE_CC, PAHOLE=$PAHOLE_BIN) ..."
log "预计耗时: 4 核约 60-90 分钟; 16 核约 20-40 分钟 (带缓存二次构建大幅缩短)"
make O=out -j"$JOBS" LLVM=1 ARCH=arm64 CC="$MAKE_CC" HOSTLD=ld.lld PAHOLE="$PAHOLE_BIN" "${MAKE_EXTRA[@]}"

log "编译完成，产物："
ls -la out/arch/arm64/boot/Image 2>/dev/null || die "未找到 Image，构建失败"
if [[ "$CCACHE_ENABLE" == "1" ]]; then
  echo "--- ccache 统计 ---"
  ccache -s | grep -E 'Hits|cache size|files in cache' | head -6
  echo "--- thinLTO cache 大小 ---"
  du -sh "$LDCACHE_DIR" 2>/dev/null || true
fi
