#!/usr/bin/env bash
# 06_integrate_features.sh —— 集成 SukiSU Ultra + SUSFS + KPM + ZRAM + BBRv3 + Unicode + LZ4
# 用法: scripts/06_integrate_features.sh   (在 kernel_source 上就地修改, 可重复执行)
# 依赖: /tmp/SukiSU_patch /tmp/susfs4ksu /tmp/lz4_oplus (见 07_fetch_deps.sh)

source "$(dirname "$0")/common.sh"
setup_proxy

cd "$KERNEL_DIR"
[[ -f Makefile ]] || die "未找到内核源码: $KERNEL_DIR"

# ---------- 0. 参数 ----------
# 统一版本入口: SUKISU_VERSION + SUKISU_CHECKOUT (见步骤 1)
SUSFS_ENABLE="${SUSFS_ENABLE:-1}"
ZRAM_ENABLE="${ZRAM_ENABLE:-0}"
BBR_ENABLE="${BBR_ENABLE:-0}"
UNICODE_ENABLE="${UNICODE_ENABLE:-0}"
LZ4_UPDATE="${LZ4_UPDATE:-0}"
SUKISU_PATCH_DIR="${SUKISU_PATCH_DIR:-/tmp/SukiSU_patch}"
SUSFS_DIR="${SUSFS_DIR:-/tmp/susfs4ksu}"
LZ4_OPLUS_DIR="${LZ4_OPLUS_DIR:-/tmp/lz4_oplus}"
RE_KERNEL_DIR="${RE_KERNEL_DIR:-/tmp/Re-Kernel}"
RE_KERNEL_ENABLE="${RE_KERNEL_ENABLE:-0}"

# ---------- 1. SukiSU Ultra (统一版本: SUKISU_VERSION 决定版本号与源码) ----------
# 输入:
#   SUKISU_CHECKOUT: SukiSU 源码 checkout 目录 (需含 .git, full clone) —— 版本唯一入口
#   SUKISU_VERSION:  ref 名 (tag/分支/commit), 用于版本号来源标注
# 兼容旧输入: KSU_MANAGER_BRANCH/KSU_BUILTIN_BRANCH 不再使用 (由 SUKISU_VERSION 取代)
[[ -n "${SUKISU_CHECKOUT:-}" ]] || die "缺少 SUKISU_CHECKOUT (SukiSU 源码 checkout 目录, 见 build.yml 的 checkout 步骤)"
[[ -d "$SUKISU_CHECKOUT/.git" ]] || die "SUKISU_CHECKOUT 不是 git 仓库: $SUKISU_CHECKOUT (commit count 需要完整历史, 不要 --depth 浅克隆)"

log "1/7 集成 SukiSU Ultra (ref=$SUKISU_VERSION, checkout=$SUKISU_CHECKOUT) ..."

# 版本号: 与官方 manager APK versionCode 对齐 (Numbersf 方案) ——
# KSU_VERSION 永远基于 main 线 (官方 APK 构建基线) 的最新 commit 数,
# 与内置源码分支无关: 源码用 SUKISU_VERSION ref, 版本号跟 main 线
# 算法复刻 getVersionCode() = VERSION_BASE + commits - VERSION_OFFSET
# 常量来源双兼容: builtin 分支在 kernel/Makefile (VERSION_BASE/VERSION_OFFSET),
# main/tag 分支在 manager/build.gradle.kts (val major / val end)
COMMITS=$(git -C "$SUKISU_CHECKOUT" rev-list --count origin/main 2>/dev/null || git -C "$SUKISU_CHECKOUT" rev-list --count HEAD)
VERSION_BASE=$(grep -oP '^VERSION_BASE[[:space:]]*:=[[:space:]]*\K\d+' "$SUKISU_CHECKOUT/kernel/Makefile" || true)
VERSION_OFFSET=$(grep -oP '^VERSION_OFFSET[[:space:]]*:=[[:space:]]*\K\d+' "$SUKISU_CHECKOUT/kernel/Makefile" || true)
if [[ -z "$VERSION_BASE" ]]; then
  MAJOR=$(grep -oP 'val major = \K\d+' "$SUKISU_CHECKOUT/manager/build.gradle.kts" || true)
  END=$(grep -oP 'val end = \K\d+' "$SUKISU_CHECKOUT/manager/build.gradle.kts" || true)
  VERSION_BASE=$((MAJOR * 10000))
  VERSION_OFFSET="$END"
fi
KSU_VERSION=$((VERSION_BASE + COMMITS - VERSION_OFFSET))
# versionName: 优先 API 最新 release tag (Numbersf 同款), 失败回退 checkout describe
VERSION_TAG=$(curl -fsSL --max-time 30 https://api.github.com/repos/SukiSU-Ultra/SukiSU-Ultra/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
[[ -n "$VERSION_TAG" ]] || VERSION_TAG=$(git -C "$SUKISU_CHECKOUT" describe --tags --always --abbrev=0 | sed 's/^v//')
GIT_HASH=$(git -C "$SUKISU_CHECKOUT" rev-parse --short=8 HEAD)
KSU_VERSION_FULL="v$VERSION_TAG-$GIT_HASH@$SUKISU_VERSION"
log "  versionCode=$KSU_VERSION (main线 commits=$COMMITS, $VERSION_BASE+$COMMITS-$VERSION_OFFSET) | tag=v$VERSION_TAG | $KSU_VERSION_FULL"

# 内置集成 (复刻 setup.sh: 复制 kernel/ + symlink + Makefile/Kconfig 条目, 幂等)
# 注意: main/tag 分支的 kernel/ 无 SUSFS 接口 (KSU_SUSFS 仅 builtin 分支有),
# 若 SUSFS_ENABLE=1 且当前 ref 缺接口, 自动回退 builtin 分支源码 (版本号仍用本 ref 计算值)
SUSFS_IN_KERNEL=$(grep -c 'KSU_SUSFS' "$SUKISU_CHECKOUT/kernel/Kconfig" || true)
KSU_SRC_DIR="$SUKISU_CHECKOUT/kernel"
if [[ "$SUSFS_ENABLE" == "1" && "$SUSFS_IN_KERNEL" == "0" ]]; then
  log "  ⚠️ ref $SUKISU_VERSION 的 kernel/ 无 KSU_SUSFS 接口 (仅 builtin 分支带), 内置源码回退 builtin 分支, 版本号仍用 ref 计算值 $KSU_VERSION"
  if [[ ! -d /tmp/SukiSU-builtin/.git ]]; then
    git clone --branch builtin --depth 1 https://github.com/SukiSU-Ultra/SukiSU-Ultra.git /tmp/SukiSU-builtin || die "builtin 分支拉取失败 (检查网络/代理)"
  fi
  KSU_SRC_DIR="/tmp/SukiSU-builtin/kernel"
fi
rm -rf KernelSU
mkdir -p KernelSU
cp -r "$KSU_SRC_DIR" KernelSU/kernel
DRIVER_DIR="$KERNEL_DIR/drivers"
ln -sfn "$(realpath --relative-to="$DRIVER_DIR" "$KERNEL_DIR/KernelSU/kernel")" "$DRIVER_DIR/kernelsu"
grep -q 'kernelsu' "$DRIVER_DIR/Makefile" || printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >> "$DRIVER_DIR/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig" || sed -i '/endmenu/i\source "drivers/kernelsu/Kconfig"' "$DRIVER_DIR/Kconfig"
log "  内置集成完成: KernelSU/kernel <- $KSU_SRC_DIR"

# 注入版本号到 kernel/Makefile (有则替换, 无则追加)
KSU_MK="$KERNEL_DIR/KernelSU/kernel/Makefile"
if grep -q '^KSU_VERSION ' "$KSU_MK"; then
  sed -i "s|^KSU_VERSION[[:space:]]*:=.*|KSU_VERSION     := $KSU_VERSION|" "$KSU_MK"
else
  printf '\nKSU_VERSION     := %s\n' "$KSU_VERSION" >> "$KSU_MK"
fi
if grep -q '^KSU_VERSION_FULL ' "$KSU_MK"; then
  sed -i "s|^KSU_VERSION_FULL[[:space:]]*:=.*|KSU_VERSION_FULL := $KSU_VERSION_FULL|" "$KSU_MK"
else
  printf 'KSU_VERSION_FULL := %s\n' "$KSU_VERSION_FULL" >> "$KSU_MK"
fi
log "  KSU_VERSION=$KSU_VERSION (与 manager APK versionCode 对齐)"

# ---------- 2. SUSFS ----------
if [[ "$SUSFS_ENABLE" == "1" ]]; then
  log "2/7 集成 SUSFS ..."
  cp "$SUSFS_DIR/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch" ./
  cp "$SUSFS_DIR"/kernel_patches/fs/* fs/
  cp "$SUSFS_DIR"/kernel_patches/include/linux/* include/linux/

  # 幂等基线: 先把补丁涉及的文件恢复到 tag 原版 (git describe 取最近 tag),
  # 保证每次从同一基线打补丁, 结果可复现; 非 git 树或无 tag 时跳过 (警告)
  SUSFS_BASE_TAG=$(git describe --tags --abbrev=0 2>/dev/null || true)
  if [[ -n "$SUSFS_BASE_TAG" ]]; then
    for f in $(grep '^diff --git' 50_add_susfs_in_gki-android13-5.15.patch | awk '{print $3}' | cut -c3-); do
      git show "$SUSFS_BASE_TAG:$f" > "$f" 2>/dev/null || true
    done
  else
    log "  ⚠️ 无法确定 git tag (非 git 树?), 跳过幂等恢复 — 重复执行可能重复插入补丁"
  fi
  patch -p1 --forward < 50_add_susfs_in_gki-android13-5.15.patch 2>&1 | tail -1 || true

  # 手动修复 reject (补丁基线与目标内核差异: task_mmu.c 缺 susfs_def include, namespace.c 缺挂载钩子声明)
  # 注意: ACK 5.15.194 零冲突, 5.15.211 有这两个文件的小差异, 需手动补
  python3 - <<'PYEOF'
import os
# task_mmu.c: susfs_def include
p='fs/proc/task_mmu.c'
s=open(p).read()
if 'susfs_def.h' not in s:
    s=s.replace('#include <linux/pkeys.h>\n','#include <linux/pkeys.h>\n#if defined(CONFIG_KSU_SUSFS_SUS_KSTAT) || defined(CONFIG_KSU_SUSFS_SUS_MAP) || defined(CONFIG_KSU_SUSFS_OPEN_REDIRECT)\n#include <linux/susfs_def.h>\n#endif\n',1)
    open(p,'w').write(s)
# namespace.c: susfs include + extern
p='fs/namespace.c'
s=open(p).read()
if 'susfs_def.h' not in s:
    s=s.replace('#include <linux/mnt_idmapping.h>\n','#include <linux/mnt_idmapping.h>\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n#include <linux/susfs_def.h>\n#endif\n',1)
    s=s.replace('#include "pnode.h"\n','#include "pnode.h"\n\n#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\nextern bool susfs_is_current_ksu_domain(void);\nextern struct static_key_true susfs_is_sdcard_android_data_not_decrypted;\n\n#define CL_COPY_MNT_NS BIT(25) /* used by copy_mnt_ns() */\n\n#endif\n',1)
    open(p,'w').write(s)
PYEOF
  # 清理 reject/orig (补丁冲突残留; fts_521 等设备专属 Makefile.rej 对小米设备无意义, 丢弃)
  find . -name '*.rej' -o -name '*.orig' | grep -v '^./out/' | xargs -r rm -f || true
else
  log "2/7 跳过 SUSFS"
fi

# ---------- 3. KPM 工具 (不修改源码, 打包时使用) ----------
log "3/7 KPM 工具准备 (patch_linux 在 $SUKISU_PATCH_DIR/kpm/)"
# git clone 可能丢失可执行位, 自动修复
chmod +x "$SUKISU_PATCH_DIR"/kpm/* 2>/dev/null || true
[[ -x "$SUKISU_PATCH_DIR/kpm/patch_linux" ]] || die "缺少 patch_linux"

# ---------- 4. ZRAM (lz4k 算法) ----------
if [[ "$ZRAM_ENABLE" == "1" ]]; then
  log "4/7 集成 ZRAM (lz4k/lz4kd) ..."
  cp -r "$SUKISU_PATCH_DIR"/other/zram/lz4k/include/linux/* include/linux/
  cp -r "$SUKISU_PATCH_DIR"/other/zram/lz4k/lib/* lib/
  cp -r "$SUKISU_PATCH_DIR"/other/zram/lz4k/crypto/* crypto/
  cp -r "$SUKISU_PATCH_DIR"/other/zram/lz4k_oplus lib/
  patch -p1 -F 3 < "$SUKISU_PATCH_DIR/other/zram/zram_patch/5.15/lz4kd.patch" 2>&1 | tail -1 || true
  patch -p1 -F 3 < "$SUKISU_PATCH_DIR/other/zram/zram_patch/5.15/lz4k_oplus.patch" 2>&1 | tail -1 || true
  find . -name '*.rej' | grep -v '^./out/' | xargs -r rm -f || true
else
  log "4/7 跳过 ZRAM"
fi

# ---------- 5. BBRv3 ----------
if [[ "$BBR_ENABLE" == "1" ]]; then
  log "5/7 应用 BBRv3 backport (android13-5.15) ..."
  patch -p1 < "$ROOT_DIR/patches/bbrv3/0001-net-tcp-backport-BBRv3-to-android13-5.15.patch" 2>&1 | tail -30 || true
  REJS=$(find . -name '*.rej' | grep -v '^./out/' || true)
  if [ -n "$REJS" ]; then
    echo "⚠️ BBR 补丁 reject 文件:"; echo "$REJS"
    for r in $REJS; do echo "--- $r ---"; head -10 "$r"; done
  fi
  find . -name '*.rej' | grep -v '^./out/' | xargs -r rm -f || true
  # ACK 211 适配: Numbersf 补丁基于 OnePlus 树, 部分 hunk 与 ACK 原版不匹配, 手动补必需项
  # 1) tcp_sock 位域: fast_ack_mode/tlp_orig_data_app_limited (tcp_bbr3.c 必需, ACK 211 无)
  if ! grep -q 'fast_ack_mode' "$KERNEL_DIR/include/linux/tcp.h"; then
    python3 - "$KERNEL_DIR/include/linux/tcp.h" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''\tu8\tcompressed_ack;
\tu8\tdup_ack_counter:2,
\t\ttlp_retrans:1,\t/* TLP is a retransmission */
\t\tunused:5;
\tu32\tchrono_start;'''
new = '''\tu8\tcompressed_ack;
\tu8\tdup_ack_counter:2,
\t\ttlp_retrans:1,\t/* TLP is a retransmission */
#ifndef __GENKSYMS__
\t\tfast_ack_mode:2, /* which fast ack mode ? */
\t\ttlp_orig_data_app_limited:1, /* app-limited before TLP rtx? */
\t\tunused:2;
#else
\t\tunused:5;
#endif
\tu32\tchrono_start;'''
assert old in s, "tcp.h 位域锚点未找到"
s = s.replace(old, new)
open(p, 'w').write(s)
PYEOF
    log "  tcp.h: 补 fast_ack_mode/tlp_orig_data_app_limited 位域"
  fi
  # 2) netdevice.h: GSO_LEGACY_MAX_SIZE (tcp_bbr3.c 引用, ACK 211 无)
  if ! grep -q 'GSO_LEGACY_MAX_SIZE' "$KERNEL_DIR/include/linux/netdevice.h"; then
    python3 - "$KERNEL_DIR/include/linux/netdevice.h" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
old = '''struct net_device {'''
new = '''#define GSO_LEGACY_MAX_SIZE\t65536u

struct net_device {'''
assert old in s, "netdevice.h 锚点未找到"
s = s.replace(old, new)
open(p, 'w').write(s)
PYEOF
    log "  netdevice.h: 补 GSO_LEGACY_MAX_SIZE"
  fi
else
  log "5/7 跳过 BBRv3"
fi

# ---------- 6. Unicode 绕过补丁 ----------
if [[ "$UNICODE_ENABLE" == "1" ]]; then
  log "6/7 应用 Unicode 绕过补丁 ..."
  patch -p1 --forward < "$ROOT_DIR/patches/unicode/unicode_bypass_fix_6.1-.patch" 2>&1 | tail -1 || true
  find . -name '*.rej' | grep -v '^./out/' | xargs -r rm -f || true
else
  log "6/7 跳过 Unicode 补丁"
fi

# ---------- 7. LZ4 升级 ----------
if [[ "$LZ4_UPDATE" == "1" && -f "$LZ4_OPLUS_DIR/apply_lz4_oplus.sh" ]]; then
  log "7/7 升级 LZ4 ..."
  source "$LZ4_OPLUS_DIR/apply_lz4_oplus.sh" 2>&1 | tail -2
else
  log "7/7 跳过 LZ4 升级"
fi

# ---------- 8. Re:Kernel (Sakion-Team, LKM; 需要 KPM 的 kprobe 接口) ----------
if [[ "$RE_KERNEL_ENABLE" == "1" ]]; then
  log "8/8 集成 Re:Kernel ..."
  [[ -f "$RE_KERNEL_DIR/LKM-Source/Kconfig" ]] || die "缺少 Re-Kernel 源码: $RE_KERNEL_DIR (见 07_fetch_deps.sh)"
  # drivers/Kconfig: 注册 Kconfig (幂等)
  grep -q 'drivers/rekernel/Kconfig' drivers/Kconfig || \
    sed -i '/endmenu/i source "drivers/rekernel/Kconfig"' drivers/Kconfig
  # drivers/Makefile: 注册编译目标 (幂等)
  grep -q 'obj-\$(CONFIG_REKERNEL)' drivers/Makefile || \
    printf '\n# Re-Kernel Support\nobj-$(CONFIG_REKERNEL) += rekernel/\n' >> drivers/Makefile
  # 拷贝 LKM 源码 (覆盖式更新)
  rm -rf drivers/rekernel
  mkdir -p drivers/rekernel
  cp -r "$RE_KERNEL_DIR/LKM-Source/"* drivers/rekernel/
  log "  Re:Kernel LKM 已复制到 drivers/rekernel (CONFIG_REKERNEL 在 02 中开启)"
else
  log "8/8 跳过 Re:Kernel"
fi

log "✅ 集成完成。下一步: scripts/02_set_config.sh 生成配置 (含 KSU/SUSFS/KPM/ZRAM/BBR/NETFILTER/REKERNEL)"
