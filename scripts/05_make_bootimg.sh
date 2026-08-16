#!/usr/bin/env bash
# 05_make_bootimg.sh —— 基于 stock boot.img 生成可 fastboot boot 的 boot.img
# 原理: magiskboot 解包 stock boot → 替换 kernel 段 → repack
#       header/ramdisk/dtb 全部保留官方原件, 只有内核被替换 (与 AK3 刷入完全同构)
# 用法: scripts/05_make_bootimg.sh <stock_boot.img> [输出名或输出目录]
#
# 注意: 若启用 KPM，会像 04_make_ak3.sh 一样先用 patch_linux 处理 Image，
#       保证 fastboot 测试镜像与最终 AK3 刷机包行为一致。

source "$(dirname "$0")/common.sh"

STOCK_IMG="${1:?用法: 05_make_bootimg.sh <stock_boot.img>}"
OUT_IMG="${2:-boot-$(basename "${STOCK_IMG%.img}").custom.img}"
# 如果第二个参数是已存在的目录，则在该目录下生成默认文件名
if [[ -n "${2:-}" && -d "$2" ]]; then
  OUT_IMG="$2/boot-$(basename "${STOCK_IMG%.img}").custom.img"
fi
# 兼容用户习惯写 dist/xxx.img：脚本固定输出到 $ROOT_DIR/dist 下，去掉 dist/ 前缀
if [[ "$OUT_IMG" == dist/* ]]; then
  OUT_IMG="${OUT_IMG#dist/}"
fi
IMAGE_PATH="${IMAGE_PATH:-$KERNEL_DIR/out/arch/arm64/boot/Image}"
SUKISU_PATCH_DIR="${SUKISU_PATCH_DIR:-/tmp/SukiSU_patch}"

# 优先使用仓库内 AK3 自带的 magiskboot，避免额外下载
if [[ -z "${MAGISKBOOT:-}" && -x "$ROOT_DIR/anykernel3/tools/magiskboot" ]]; then
  MAGISKBOOT="$ROOT_DIR/anykernel3/tools/magiskboot"
else
  MAGISKBOOT="${MAGISKBOOT:-$(command -v magiskboot || echo /tmp/magiskboot)}"
fi

# 未显式指定时，从实际 .config 自动推断 KPM
if [[ -z "${KPM_ENABLE:-}" && -f "$KERNEL_DIR/out/.config" ]]; then
  if grep -q '^CONFIG_KPM=y' "$KERNEL_DIR/out/.config"; then
    KPM_ENABLE=1
  else
    KPM_ENABLE=0
  fi
fi
KPM_ENABLE="${KPM_ENABLE:-1}"

[[ -f "$STOCK_IMG" ]] || die "未找到 stock boot.img: $STOCK_IMG"
[[ -f "$IMAGE_PATH" ]] || die "未找到编译产物 Image: $IMAGE_PATH"
[[ -x "$MAGISKBOOT" ]] || die "未找到 magiskboot: $MAGISKBOOT (可使用 anykernel3/tools/magiskboot 或从 github.com/Uevo001/magiskboot-linux 获取)"

mkdir -p "$ROOT_DIR/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ---------- KPM patch（与 04 保持一致） ----------
WORK_IMAGE="$IMAGE_PATH"
if [[ "$KPM_ENABLE" == "1" ]]; then
  log "KPM: 使用 patch_linux 处理 Image ..."
  KPM_WORK="$WORK/kpm-work"
  mkdir -p "$KPM_WORK"
  cp "$IMAGE_PATH" "$KPM_WORK/Image"
  cp "$SUKISU_PATCH_DIR/kpm/patch_linux" "$KPM_WORK/"
  ( cd "$KPM_WORK" && chmod +x patch_linux && ./patch_linux 2>&1 | tail -1 && mv -f oImage Image )
  WORK_IMAGE="$KPM_WORK/Image"
fi

log "1/3 解包 stock boot.img ..."
cp "$STOCK_IMG" "$WORK/stock.img"
( cd "$WORK" && "$MAGISKBOOT" unpack stock.img )

log "2/3 替换 kernel 段 (Image: $WORK_IMAGE)"
cp "$WORK_IMAGE" "$WORK/kernel"
echo "  新内核: $(strings "$WORK/kernel" | grep -m1 'Linux version 5' | cut -c1-80)"

log "3/3 repack -> $OUT_IMG"
( cd "$WORK" && "$MAGISKBOOT" repack stock.img )
mkdir -p "$(dirname "$ROOT_DIR/dist/$OUT_IMG")"
cp "$WORK/new-boot.img" "$ROOT_DIR/dist/$OUT_IMG"
log "完成: $ROOT_DIR/dist/$OUT_IMG"

# 压缩归档 (tar --zstd) —— 必须在 dist 目录内执行，否则找不到输入文件
( cd "$ROOT_DIR/dist" && tar --zstd -cf "$OUT_IMG.tar.zst" "$OUT_IMG" )
log "压缩: $OUT_IMG.tar.zst ($(du -h "$ROOT_DIR/dist/$OUT_IMG.tar.zst" | cut -f1))"

cat <<EOF

========== fastboot 临时引导测试 (不写入任何分区) ==========
1. 手机进入 fastboot 模式:  关机后 长按 电源+音量下
2. 连接电脑后执行:
   fastboot boot $ROOT_DIR/dist/$OUT_IMG

   - 若正常: 手机会用临时内核启动, 重启后自动恢复原系统
   - 若卡屏/无法开机: 长按电源键 10 秒强制重启即可恢复 (boot 未写入)
3. 启动后检查模块是否正常:
   adb shell dmesg | grep -E 'vermagic|module|fail'
   adb shell ls /vendor/lib/modules   # 确认驱动加载
   adb shell getprop ro.kernel.version 2>/dev/null
============================================================
EOF
