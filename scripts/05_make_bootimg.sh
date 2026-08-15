#!/usr/bin/env bash
# 05_make_bootimg.sh —— 基于 stock boot.img 生成可 fastboot boot 的 boot.img
# 原理: magiskboot 解包 stock boot → 替换 kernel 段 → repack
#       header/ramdisk/dtb 全部保留官方原件, 只有内核被替换 (与 AK3 刷入完全同构)
# 用法: scripts/05_make_bootimg.sh <stock_boot.img> [输出名]

source "$(dirname "$0")/common.sh"

STOCK_IMG="${1:?用法: 05_make_bootimg.sh <stock_boot.img>}"
OUT_IMG="${2:-boot-$(basename "${STOCK_IMG%.img}").custom.img}"
IMAGE_PATH="${IMAGE_PATH:-$KERNEL_DIR/out/arch/arm64/boot/Image}"
MAGISKBOOT="${MAGISKBOOT:-$(command -v magiskboot || echo /tmp/magiskboot)}"

[[ -f "$STOCK_IMG" ]] || die "未找到 stock boot.img: $STOCK_IMG"
[[ -f "$IMAGE_PATH" ]] || die "未找到编译产物 Image: $IMAGE_PATH"
[[ -x "$MAGISKBOOT" ]] || die "未找到 magiskboot: $MAGISKBOOT (可从 github.com/Uevo001/magiskboot-linux 获取)"

mkdir -p "$ROOT_DIR/dist"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "1/3 解包 stock boot.img ..."
cp "$STOCK_IMG" "$WORK/stock.img"
( cd "$WORK" && "$MAGISKBOOT" unpack stock.img )

log "2/3 替换 kernel 段 (Image: $IMAGE_PATH)"
cp "$IMAGE_PATH" "$WORK/kernel"
echo "  新内核: $(strings "$WORK/kernel" | grep -m1 'Linux version 5' | cut -c1-80)"

log "3/3 repack -> $OUT_IMG"
( cd "$WORK" && "$MAGISKBOOT" repack stock.img )
cp "$WORK/new-boot.img" "$ROOT_DIR/dist/$OUT_IMG"
log "完成: $ROOT_DIR/dist/$OUT_IMG"

# 压缩归档 (tar --zstd)
tar --zstd -cf "$ROOT_DIR/dist/$OUT_IMG.tar.zst" "$OUT_IMG" 2>/dev/null && \
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
