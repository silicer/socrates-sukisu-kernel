#!/usr/bin/env bash
# 04_make_ak3.sh —— 用 AnyKernel3 打包刷机 zip
# socrates: boot 分区, 无 A/B, header v4, page 4096, base 0x80000000
# 只替换 Image（GKI: dtb/dtbo 保持原样，仅替换内核段）
#
# 使用临时 staging 目录打包，不修改 anykernel3/ 下的 tracked 文件；
# 每次打包前清理可能残留的 Image / ksu_module_susfs.zip，避免旧产物混入。

source "$(dirname "$0")/common.sh"

AK3_DIR="${AK3_DIR:-$ROOT_DIR/anykernel3}"
IMAGE_PATH="${IMAGE_PATH:-$KERNEL_DIR/out/arch/arm64/boot/Image}"
VERSION_STR="${VERSION_STR:-$(grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL)' "$KERNEL_DIR/Makefile" | awk '{print $3}' | tr '\n' '.' | sed 's/\.$//')}"
SUKISU_PATCH_DIR="${SUKISU_PATCH_DIR:-/tmp/SukiSU_patch}"

# 未显式指定时，从实际 .config 自动推断，避免“配置关了但打包还标/加 SUSFS/KPM”
if [[ -z "${KPM_ENABLE:-}" && -f "$KERNEL_DIR/out/.config" ]]; then
  if grep -q '^CONFIG_KPM=y' "$KERNEL_DIR/out/.config"; then
    KPM_ENABLE=1
  else
    KPM_ENABLE=0
  fi
fi
KPM_ENABLE="${KPM_ENABLE:-1}"

if [[ -z "${SUSFS_ENABLE:-}" && -f "$KERNEL_DIR/out/.config" ]]; then
  if grep -q '^CONFIG_KSU_SUSFS=y' "$KERNEL_DIR/out/.config"; then
    SUSFS_ENABLE=1
  else
    SUSFS_ENABLE=0
  fi
fi
SUSFS_ENABLE="${SUSFS_ENABLE:-1}"

[[ -f "$IMAGE_PATH" ]] || die "未找到 Image: $IMAGE_PATH"
[[ -d "$AK3_DIR" ]] || die "未找到 AK3 模板: $AK3_DIR"

log "使用 Image: $IMAGE_PATH"
log "内核版本: $VERSION_STR"
log "功能: KPM=$KPM_ENABLE SUSFS=$SUSFS_ENABLE"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# 复制模板到临时目录（会连旧 Image/模块一起复制，随后统一清理）
cp -a "$AK3_DIR/." "$STAGE/"
rm -f "$STAGE/Image" "$STAGE/Image.gz" "$STAGE/Image.lz4" \
      "$STAGE/dtb" "$STAGE/dtbo.img" "$STAGE/ksu_module_susfs.zip" \
      "$STAGE/.gitignore"

# ---------- KPM patch (Image 需先经 patch_linux 处理才能加载 .kpm 模块) ----------
WORK_IMAGE="$IMAGE_PATH"
KPM_WORK=""
if [[ "$KPM_ENABLE" == "1" ]]; then
  log "KPM: 使用 patch_linux 处理 Image ..."
  KPM_WORK="$STAGE/.kpm-work"
  mkdir -p "$KPM_WORK"
  cp "$IMAGE_PATH" "$KPM_WORK/Image"
  cp "$SUKISU_PATCH_DIR/kpm/patch_linux" "$KPM_WORK/"
  ( cd "$KPM_WORK" && chmod +x patch_linux && ./patch_linux 2>&1 | tail -1 && mv -f oImage Image )
  WORK_IMAGE="$KPM_WORK/Image"
fi

cp "$WORK_IMAGE" "$STAGE/Image"
# KPM 工作目录不需要进 zip
rm -rf "$KPM_WORK"

# ---------- SUSFS 附加模块 ----------
FEATURE_TAG=""
if [[ "$SUSFS_ENABLE" == "1" ]]; then
  if [[ -f /tmp/susfs_module.zip ]]; then
    cp /tmp/susfs_module.zip "$STAGE/ksu_module_susfs.zip"
    FEATURE_TAG="${FEATURE_TAG}_SUSFS"
    log "已加入 susfs 附加模块 (刷入重启前安装)"
  else
    warn "SUSFS_ENABLE=1 但 /tmp/susfs_module.zip 不存在，zip 中将不包含 susfs 附加模块"
  fi
fi
[[ "$KPM_ENABLE" == "1" ]] && FEATURE_TAG="${FEATURE_TAG}_KPM"
[[ -n "${FEATURE_TAG}" ]] && FEATURE_TAG="${FEATURE_TAG:1}"

# 写入 anykernel.sh（WildKernels 风格: block=boot + split_boot/flash_boot, GKI 无 ramdisk 用 flash_boot）
cat > "$STAGE/anykernel.sh" <<EOF
### AnyKernel3 Ramdisk Mod Script
## socrates (Redmi K60 Pro) kernel build $VERSION_STR

### AnyKernel setup
properties() { '
kernel.string=socrates (Redmi K60 Pro) $VERSION_STR kernel
do.devicecheck=0
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0
do.check_boot_version=0
device.name1=
device.name2=
device.name3=
device.name4=
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
keycheck.timeout=10
'; } # end properties

### AnyKernel install
## boot shell variables
block=boot
is_slot_device=auto
ramdisk_compression=auto
patch_vbmeta_flag=auto
no_magisk_check=1

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh

# GKI check
kernel_version=\$(cat /proc/version | awk -F '-' '{print \$1}' | awk '{print \$3}')
case \$kernel_version in
    5.10*) ksu_supported=true ;;
    5.15*) ksu_supported=true ;;
    6.1*) ksu_supported=true ;;
    6.6*) ksu_supported=true ;;
    6.12*) ksu_supported=true ;;
    *) ksu_supported=false ;;
esac
ui_print " " "  -> GKI Supported: \$ksu_supported"
\$ksu_supported || abort "  -> Non-GKI device, abort."

# boot install
split_boot

if [ -f "\$SPLITIMG/ramdisk.cpio" ]; then
    unpack_ramdisk
    write_boot
else
    flash_boot
fi
ui_print " " "Flash done. Reboot and enjoy!"
## end boot install
EOF

mkdir -p "$ROOT_DIR/dist"
cd "$STAGE"
ZIP_NAME="${ZIP_NAME:-AnyKernel3_socrates_${VERSION_STR}${FEATURE_TAG:+_${FEATURE_TAG}}.zip}"
rm -f "$ROOT_DIR/dist/$ZIP_NAME"
log "打包: $ZIP_NAME"
zip -r9q "$ROOT_DIR/dist/$ZIP_NAME" . -x '*.git*' -x '.kpm-work/*'
log "完成: $ROOT_DIR/dist/$ZIP_NAME ($(du -h "$ROOT_DIR/dist/$ZIP_NAME" | cut -f1))"
