#!/usr/bin/env bash
# 02_set_config.sh —— 生成 ACK gki_defconfig + 功能配置
# 用法: scripts/02_set_config.sh
# 环境开关 (与 06_integrate_features.sh 一一对应, 需先运行 06 应用对应补丁):
#   SUSFS_ENABLE=1 (默认)  SUSFS 配置块, 依赖 susfs4ksu 补丁
#   BBR_ENABLE=1  (默认)  BBRv3/ECN/NETFILTER/IP_SET 配置块, 依赖 BBRv3 补丁
#   ZRAM_ENABLE=1  (默认)  ZRAM lz4k 配置块, 依赖 lz4k 补丁
#   KPM_ENABLE=1   (默认)  CONFIG_KPM
#   RE_KERNEL_ENABLE=0 (默认)  Re:Kernel (LKM, 需 KPM 的 kprobe 接口)
#   SPOOF_VERSION=0 (默认) 版本伪装开关, 1=编译期伪装 (默认 0, 用 SUSFS 运行时伪装)

source "$(dirname "$0")/common.sh"
setup_toolchain

cd "$KERNEL_DIR"

SUSFS_ENABLE="${SUSFS_ENABLE:-1}"
BBR_ENABLE="${BBR_ENABLE:-1}"
ZRAM_ENABLE="${ZRAM_ENABLE:-1}"
KPM_ENABLE="${KPM_ENABLE:-1}"
RE_KERNEL_ENABLE="${RE_KERNEL_ENABLE:-0}"

log "1/4 生成 gki_defconfig ..."
make O=out gki_defconfig >/dev/null 2>&1 || make O=out gki_defconfig

log "2/4 社区优化：关 KASAN / 开 thin LTO / 关 BTF ..."
# ACK gki_defconfig 自带 KASAN (gki-debug 配置); KASAN 与 LTO 互斥, 社区构建关闭
# 3/4 编译配置: 保持 GKI 官方规范 (真机验证结论! socrates 只能启动官方规范配置):
#   KASAN_HW_TAGS + LTO_CLANG_THIN + CFI_CLANG + SHADOW_CALL_STACK + DEBUG_INFO_BTF
#   —— 任何"社区优化"(关 KASAN / LTO_NONE / 无 CFI) 都会 bootloop, 不要改!
# 只显式切 thin LTO (gki_defconfig 默认 FULL, 40796 验证配置是 THIN)
scripts/config --file out/.config \
  -e LTO_CLANG -e LTO_CLANG_THIN \
  -d LTO_CLANG_NONE -d LTO_CLANG_FULL

make O=out olddefconfig >/dev/null 2>&1 || make O=out olddefconfig

log "3/4 功能配置 (KSU 常开; SUSFS=$SUSFS_ENABLE BBR=$BBR_ENABLE ZRAM=$ZRAM_ENABLE KPM=$KPM_ENABLE RE_KERNEL=$RE_KERNEL_ENABLE) ..."
# SukiSU 核心 (builtin 集成后 Kconfig 默认开启, 这里确保)
scripts/config --file out/.config -e KSU

# KPM (Kernel Patch Module)
[[ "$KPM_ENABLE" == "1" ]] && scripts/config --file out/.config -e KPM

# SUSFS (addon: 接口在 SukiSU kernel/Kconfig, 代码来自 susfs4ksu 补丁)
# 检测: 接口仅 builtin 分支带 (06 在 ref 缺接口时会自动回退 builtin), 无接口时降级关闭
if [[ "$SUSFS_ENABLE" == "1" && -f drivers/kernelsu/Kconfig && $(grep -c 'KSU_SUSFS' drivers/kernelsu/Kconfig) -gt 0 ]]; then
  scripts/config --file out/.config \
    -e KSU_SUSFS -e KSU_SUSFS_SUS_PATH -e KSU_SUSFS_SUS_MAP -e KSU_SUSFS_SUS_MOUNT -e KSU_SUSFS_SUS_KSTAT \
    -e KSU_SUSFS_SPOOF_UNAME -e KSU_SUSFS_ENABLE_LOG -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
    -e KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG -e KSU_SUSFS_OPEN_REDIRECT
else
  if [[ "$SUSFS_ENABLE" == "1" ]]; then
    log "  ⚠️ 当前 SukiSU kernel/ 无 KSU_SUSFS 接口 (06 未回退 builtin), SUSFS 配置跳过"
  fi
  # SukiSU builtin 的 Kconfig 默认开启 SUSFS, 关闭时必须连同子项一起关
  scripts/config --file out/.config \
    -d KSU_SUSFS -d KSU_SUSFS_SUS_PATH -d KSU_SUSFS_SUS_MAP -d KSU_SUSFS_SUS_MOUNT -d KSU_SUSFS_SUS_KSTAT \
    -d KSU_SUSFS_SPOOF_UNAME -d KSU_SUSFS_ENABLE_LOG -d KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
    -d KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG -d KSU_SUSFS_OPEN_REDIRECT
fi

# 网络增强 (BBRv3 + ECN + NETFILTER/IP_SET) —— 参考 Action-Build; BBRv3 依赖 06 的补丁
if [[ "$BBR_ENABLE" == "1" ]]; then
  scripts/config --file out/.config \
    -e TMPFS_XATTR -e TMPFS_POSIX_ACL \
    -e TCP_CONG_ADVANCED -e TCP_CONG_BBR -e TCP_CONG_BBR3 -e NET_SCH_FQ \
    -d TCP_CONG_BIC -d TCP_CONG_WESTWOOD -d TCP_CONG_HTCP \
    -e IP_ECN -e TCP_ECN -e IPV6_ECN -e IP_NF_TARGET_ECN \
    -e NETFILTER_XT_TARGET_REJECT -e NETFILTER_XT_TARGET_LOG -e NETFILTER_XT_MATCH_RECENT \
    -e BPF_STREAM_PARSER -e NETFILTER_XT_MATCH_ADDRTYPE -e NETFILTER_XT_SET \
    -e IP_SET -e IP_SET_BITMAP_IP -e IP_SET_BITMAP_IPMAC -e IP_SET_BITMAP_PORT \
    -e IP_SET_HASH_IP -e IP_SET_HASH_IPMARK -e IP_SET_HASH_IPPORT -e IP_SET_HASH_IPPORTIP \
    -e IP_SET_HASH_IPPORTNET -e IP_SET_HASH_IPMAC -e IP_SET_HASH_MAC -e IP_SET_HASH_NETPORTNET \
    -e IP_SET_HASH_NET -e IP_SET_HASH_NETNET -e IP_SET_HASH_NETPORT -e IP_SET_HASH_NETIFACE -e IP_SET_LIST_SET \
    -e IP6_NF_NAT -e IP6_NF_TARGET_MASQUERADE \
    -e NETFILTER_XT_TARGET_HL -e IP_NF_TARGET_TTL -e IP6_NF_TARGET_HL -e NETFILTER_XT_MATCH_HL \
    -e IP_NF_MATCH_TTL -e IP6_NF_MATCH_HL -e IP_NF_MANGLE -e IP6_NF_MANGLE
  scripts/config --file out/.config --set-str IP_SET_MAX "65534"
else
  scripts/config --file out/.config \
    -e TMPFS_XATTR -e TMPFS_POSIX_ACL \
    -d TCP_CONG_BBR3 -d TCP_CONG_ADVANCED
fi

# ZRAM lz4k (依赖 06 的 lz4k/lz4kd 补丁; 只开 config 不开补丁会导致缺源码编译失败)
if [[ "$ZRAM_ENABLE" == "1" ]]; then
  scripts/config --file out/.config \
    -e CRYPTO_LZ4HC -e CRYPTO_LZ4K -e CRYPTO_LZ4KD -e CRYPTO_842 -e CRYPTO_LZ4K_OPLUS -e ZRAM_WRITEBACK
else
  scripts/config --file out/.config \
    -d CRYPTO_LZ4K -d CRYPTO_LZ4KD -d CRYPTO_LZ4K_OPLUS -d ZRAM_WRITEBACK
fi

# Re:Kernel (Sakion-Team, 编为模块 rekernel.ko, 依赖 06 已复制 LKM 源码; 运行时需 kprobe 接口即 CONFIG_KPM)
if [[ "$RE_KERNEL_ENABLE" == "1" ]]; then
  scripts/config --file out/.config -e REKERNEL -e REKERNEL_NETWORK
else
  scripts/config --file out/.config -d REKERNEL -d REKERNEL_NETWORK
fi

make O=out olddefconfig >/dev/null 2>&1 || make O=out olddefconfig

log "4/4 配置完成，关键项："
grep -E '^CONFIG_(CC_IS_CLANG|LTO_CLANG_THIN|KASAN|DEBUG_INFO_BTF|LOCALVERSION|KSU|KSU_SUSFS|KPM|TCP_CONG_BBR3|CRYPTO_LZ4K)' out/.config

# ---------- KSU_VERSION 自动同步 main 线 (匹配 CI 管理器 versionCode) ----------
# 每次构建自动计算: KSU_VERSION = main 线 commit 数 + (VERSION_BASE - VERSION_OFFSET),
# 与 SukiSU 官方 CI 构建 manager APK 的 versionCode 同源, 保证内核与管理器版本一致。
# 需要 SUKISU_CHECKOUT (SukiSU 源码 checkout, 含 .git); 未提供时跳过 (用现有值)。
# KSU_VERSION_AUTO=0 可关闭 (固定使用 Makefile 现有值)
KSU_VERSION_AUTO="${KSU_VERSION_AUTO:-1}"
if [[ "$KSU_VERSION_AUTO" == "1" && -n "${SUKISU_CHECKOUT:-}" && -d "$SUKISU_CHECKOUT/.git" ]]; then
  COMMITS=$(git -C "$SUKISU_CHECKOUT" rev-list --count origin/main 2>/dev/null || git -C "$SUKISU_CHECKOUT" rev-list --count HEAD)
  VB=$(grep -oP '^VERSION_BASE[[:space:]]*:=[[:space:]]*\K\d+' "$SUKISU_CHECKOUT/kernel/Makefile" || true)
  VO=$(grep -oP '^VERSION_OFFSET[[:space:]]*:=[[:space:]]*\K\d+' "$SUKISU_CHECKOUT/kernel/Makefile" || true)
  [[ -n "$VB" ]] || VB=40000
  [[ -n "$VO" ]] || VO=2815
  KSU_VER=$((VB + COMMITS - VO))
  KSU_MK="$KERNEL_DIR/KernelSU/kernel/Makefile"
  if [[ -f "$KSU_MK" ]]; then
    sed -i "s|^KSU_VERSION[[:space:]]*:=.*|KSU_VERSION     := $KSU_VER|" "$KSU_MK"
    log "KSU_VERSION 自动同步 main 线: $KSU_VER (commits=$COMMITS, $VB+$COMMITS-$VO)"
  fi
else
  log "KSU_VERSION 自动同步跳过 (KSU_VERSION_AUTO=$KSU_VERSION_AUTO, SUKISU_CHECKOUT=${SUKISU_CHECKOUT:-空})"
fi

# ---------- 版本串固化（干净串, 可复现） ----------
# 注: 真机验证 -dirty 也能启动 (配置才是 bootloop 根源), 这里注入固定干净串仅为
# 可复现与整洁 (任何构建得到相同 UTS_RELEASE), 非启动必需。
# VERSION_FIX=0 可关闭
VERSION_FIX="${VERSION_FIX:-1}"
if [[ "$VERSION_FIX" == "1" ]]; then
  log "5/5 版本串固化: 后缀=$OFFICIAL_VERSION_SUFFIX (无 dirty)"
  bash "$ROOT_DIR/scripts/patch_makefile_version.sh" "$KERNEL_DIR" "$OFFICIAL_VERSION_SUFFIX"
  scripts/config --file out/.config --set-str CONFIG_LOCALVERSION ""
  make O=out olddefconfig >/dev/null 2>&1 || make O=out olddefconfig
  make O=out prepare >/dev/null 2>&1 || make O=out prepare
  log "UTS_RELEASE: $(grep UTS_RELEASE out/include/generated/utsrelease.h)"
else
  log "5/5 跳过版本串固化 (VERSION_FIX=0) ⚠️ 版本串将带 -dirty, 真机可能 bootloop"
fi
# 可选: 编译期伪装 SUBLEVEL (如伪装成官方 5.15.194), 默认不启用 (用 SUSFS 运行时伪装)
SPOOF_SUBLEVEL_ENABLE="${SPOOF_SUBLEVEL_ENABLE:-0}"
if [[ "$SPOOF_SUBLEVEL_ENABLE" == "1" ]]; then
  log "5.5/5 SUBLEVEL 伪装: $SPOOF_SUBLEVEL"
  sed -i "s/^SUBLEVEL[[:space:]]*=[[:space:]]*.*/SUBLEVEL = $SPOOF_SUBLEVEL/" Makefile
  make O=out prepare >/dev/null 2>&1 || make O=out prepare
fi
