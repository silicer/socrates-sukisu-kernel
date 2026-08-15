#!/usr/bin/env bash
# 07_fetch_deps.sh —— 拉取功能集成所需的第三方仓库
# 用法: scripts/07_fetch_deps.sh

source "$(dirname "$0")/common.sh"
setup_proxy

log "拉取 SukiSU_patch (KPM 工具 + ZRAM lz4k) ..."
if [[ ! -d /tmp/SukiSU_patch ]]; then
  git clone --depth=1 https://github.com/ShirkNeko/SukiSU_patch.git /tmp/SukiSU_patch
fi

log "拉取 susfs4ksu (gki-android13-5.15) ..."
if [[ ! -d /tmp/susfs4ksu ]]; then
  git clone --depth=1 -b gki-android13-5.15 https://gitlab.com/simonpunk/susfs4ksu.git /tmp/susfs4ksu
fi

log "拉取 lz4_oplus ..."
if [[ ! -d /tmp/lz4_oplus ]]; then
  git clone --depth=1 https://github.com/Numbersf/lz4_oplus.git /tmp/lz4_oplus
fi

log "拉取 Re-Kernel (LKM-Source) ..."
if [[ ! -d /tmp/Re-Kernel ]]; then
  git clone --depth=1 https://github.com/Sakion-Team/Re-Kernel.git /tmp/Re-Kernel
fi

log "下载 susfs 附加模块 (ksu_module_susfs) ..."
if [[ ! -f /tmp/susfs_module.zip ]]; then
  curl -fL --retry 3 -o /tmp/susfs_module.zip \
    "https://github.com/sidex15/ksu_module_susfs/releases/latest/download/ksu_module_susfs_1.5.2%2B.zip"
fi

ls -d /tmp/SukiSU_patch /tmp/susfs4ksu /tmp/lz4_oplus /tmp/Re-Kernel /tmp/susfs_module.zip
log "✅ 依赖就绪"
