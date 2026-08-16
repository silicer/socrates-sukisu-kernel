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

# 2) filechk 统一为简化版 (去掉 setlocalversion, 防 UTS_RELEASE 超 64 字符)
if grep -q 'setlocalversion' "$MF"; then
  python3 - "$MF" <<'PYEOF'
import sys
mf = sys.argv[1]
s = open(mf).read()
lines = s.split('\n')
for i, l in enumerate(lines):
    if l.startswith('filechk_kernel.release = \\'):
        j = i + 1
        while j < len(lines) and lines[j].endswith('\\'):
            j += 1
        new_block = ['filechk_kernel.release = \\', '\techo "$(KERNELVERSION)$(OFFICIAL_VERSION_SUFFIX)"']
        lines[i:j+1] = new_block
        break
open(mf, 'w').write('\n'.join(lines))
print("filechk 已简化为 KERNELVERSION+后缀")
PYEOF
else
  echo "filechk 已是简化版"
fi

grep -n 'OFFICIAL_VERSION_SUFFIX' "$MF" | head -3
