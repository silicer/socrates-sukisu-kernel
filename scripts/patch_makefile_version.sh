#!/usr/bin/env bash
# patch_makefile_version.sh —— 给内核 Makefile 注入伪官方版本后缀（幂等）
# 兼容两种 filechk_kernel.release 写法: 简版(echo KERNELVERSION) / 完整版(setlocalversion --save-tag)
# 用法: patch_makefile_version.sh <kernel_dir> [OFFICIAL_VERSION_SUFFIX]
set -euo pipefail

KERNEL_DIR="${1:?用法: patch_makefile_version.sh <kernel_dir> [suffix]}"
SUFFIX="${2:--android13-8-00019-gf4321180a397-ab15212794}"
MF="$KERNEL_DIR/Makefile"
[[ -f "$MF" ]] || { echo "Makefile 不存在: $MF" >&2; exit 1; }

# 1) 变量定义（不存在才插入）
if ! grep -q 'OFFICIAL_VERSION_SUFFIX' "$MF"; then
  sed -i "s|^filechk_kernel.release = \\\\|BRANCH ?= android13-5.15\nKMI_GENERATION ?= 8\nOFFICIAL_VERSION_SUFFIX ?= $SUFFIX\nfilechk_kernel.release = \\\\|" "$MF"
  echo "已注入 OFFICIAL_VERSION_SUFFIX 变量"
else
  echo "OFFICIAL_VERSION_SUFFIX 已存在，跳过"
fi

# 2) echo 行末尾注入 $(OFFICIAL_VERSION_SUFFIX)（末尾还是 KMI_GENERATION))" 时才注入）
if grep -q 'KMI_GENERATION))"$\|KMI_GENERATION))"' "$MF" && ! grep -q 'KMI_GENERATION))\$(OFFICIAL_VERSION_SUFFIX)' "$MF"; then
  sed -i 's|$(KMI_GENERATION))"|$(KMI_GENERATION))$(OFFICIAL_VERSION_SUFFIX)"|' "$MF"
  echo "已注入后缀引用"
else
  echo "后缀引用已存在，跳过"
fi

grep -n 'OFFICIAL_VERSION_SUFFIX' "$MF" | head -3
