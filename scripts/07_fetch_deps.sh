#!/usr/bin/env bash
# 07_fetch_deps.sh —— 拉取功能集成所需的第三方仓库
# 用法: scripts/07_fetch_deps.sh
# 环境开关:
#   SUSFS_ENABLE=1 (默认)  拉取 susfs4ksu 与 susfs 附加模块
#   LZ4_UPDATE=0   (默认)  拉取 lz4_oplus（已知 bootloop，仅显式启用才拉）
#   RE_KERNEL_ENABLE=0 (默认) 拉取 Re-Kernel
# SukiSU_patch 始终拉取（KPM 工具 / ZRAM 补丁来源）。

source "$(dirname "$0")/common.sh"
setup_proxy

SUSFS_ENABLE="${SUSFS_ENABLE:-1}"
LZ4_UPDATE="${LZ4_UPDATE:-0}"
RE_KERNEL_ENABLE="${RE_KERNEL_ENABLE:-0}"

# 若目录已存在且是有效 git 仓库则跳过；否则删除半成品重新 clone
ensure_git_clone() {
  local dir="$1" url="$2" branch="${3:-}"
  if git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    log "已存在: $dir"
    return 0
  fi
  if [[ -e "$dir" ]]; then
    warn "$dir 已存在但不是有效 git 仓库，删除后重新 clone"
    rm -rf "$dir"
  fi
  if [[ -n "$branch" ]]; then
    git clone --depth=1 -b "$branch" "$url" "$dir"
  else
    git clone --depth=1 "$url" "$dir"
  fi
}

# 下载到临时文件再 mv，避免半成品文件被后续步骤误用
ensure_download() {
  local out="$1" url="$2"
  if [[ -s "$out" ]]; then
    log "已存在: $out"
    return 0
  fi
  local tmp="$out.tmp.$$"
  curl -fL --retry 3 --retry-delay 2 -o "$tmp" "$url" || { rm -f "$tmp"; die "下载失败: $url"; }
  mv -f "$tmp" "$out"
}

log "拉取 SukiSU_patch (KPM 工具 + ZRAM lz4k) ..."
ensure_git_clone /tmp/SukiSU_patch https://github.com/ShirkNeko/SukiSU_patch.git

if [[ "$SUSFS_ENABLE" == "1" ]]; then
  log "拉取 susfs4ksu (gki-android13-5.15) ..."
  ensure_git_clone /tmp/susfs4ksu https://gitlab.com/simonpunk/susfs4ksu.git gki-android13-5.15

  log "下载 susfs 附加模块 (ksu_module_susfs) ..."
  ensure_download /tmp/susfs_module.zip \
    "https://github.com/sidex15/ksu_module_susfs/releases/latest/download/ksu_module_susfs_1.5.2%2B.zip"
fi

if [[ "$LZ4_UPDATE" == "1" ]]; then
  log "拉取 lz4_oplus ..."
  ensure_git_clone /tmp/lz4_oplus https://github.com/Numbersf/lz4_oplus.git
fi

if [[ "$RE_KERNEL_ENABLE" == "1" ]]; then
  log "拉取 Re-Kernel (LKM-Source) ..."
  ensure_git_clone /tmp/Re-Kernel https://github.com/Sakion-Team/Re-Kernel.git
fi

log "✅ 依赖就绪"
