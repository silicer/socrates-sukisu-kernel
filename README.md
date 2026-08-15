# socrates (Redmi K60 Pro) 内核构建

为 **Redmi K60 Pro（socrates, SM8550 / kalama, Android 13 / HyperOS）** 编译带 **SukiSU Ultra + SUSFS + KPM** 的 GKI 内核。支持本地构建与 GitHub Actions 一键构建，产出 AnyKernel3 刷机包。

## ✨ 特性

- **ACK 官方 GKI 内核**：kernel/common `android13-5.15.211_r00`（纯 GKI，最新 5.15）
- **SukiSU Ultra**（builtin 分支内置）+ **SUSFS**（隐藏/伪装/防检测）
- **KPM**（内核补丁模块，支持 .kpm 模块加载）
- **KSU_VERSION 自动同步**：每次构建自动计算 SukiSU main 线版本号，与官方管理器 APK 永远一致（当前 40856）
- **可选优化**：BBRv3 + ECN + NETFILTER/IP_SET 网络增强、ZRAM lz4k
- **配置保持 GKI 官方规范**（KASAN_HW_TAGS + LTO_THIN + CFI + SCS）——真机验证，保证可启动

## 🚀 快速开始（本地）

```bash
# 依赖: Linux + clang 工具链（脚本自动下载 r450784e）+ pahole + cpio

# 1. 准备源码与工具链
bash scripts/01_prepare_ack.sh

# 2. 集成 SukiSU/SUSFS/KPM（可选开关见 AGENTS.md）
export KERNEL_DIR=$PWD/kernel_source SUKISU_CHECKOUT=/tmp/SukiSU-builtin-full
bash scripts/06_integrate_features.sh

# 3. 生成配置（官方规范 + KSU_VERSION 自动同步）
bash scripts/02_set_config.sh

# 4. 编译（-jN 可选，默认留一核）
bash scripts/03_build_kernel.sh

# 5. 打包
bash scripts/04_make_ak3.sh                    # AnyKernel3 刷机包
bash scripts/05_make_bootimg.sh dist/boot.img  # fastboot boot 测试镜像
```

## 🤖 GitHub Actions 一键构建

仓库 Actions 页 → **Run workflow**，参数：

| 参数 | 说明 | 默认 |
|---|---|---|
| `ACK_TAG` | ACK 内核 tag | `android13-5.15.211_r00` |
| `SUKISU_VERSION` | SukiSU 版本（tag/分支/commit/`latest`） | `builtin` |
| `SUSFS` / `KPM` | 功能开关 | 开 |
| `BBR` / `ZRAM` | 网络 / 内存优化（可选） | 关 |
| `LZ4_UPDATE` / `UNICODE_BYPASS` / `RE_KERNEL` | 实验功能 | 关 |
| `RESUBLEVEL` / `SUFFIX` | 版本伪装 / 自定义后缀 | 关 |
| `UPLOAD_RELEASE` | 上传 GitHub Release | 关 |

产物：AnyKernel3 zip + manager APK（自动下载与内核版本匹配的官方 APK）+ 版本一致性校验。

## 📱 刷机

```bash
# 测试（临时启动，失败自动回落，无风险）
fastboot boot boot-xxx.img

# 正式刷入（recovery 里刷 AnyKernel3 zip）
# 刷入后: SukiSU 管理器装 susfs 模块 → 配置 SUSFS
```

**恢复手段**（刷坏不怕）：`fastboot boot` 官方 boot.img 即可恢复。

## ⚠️ 已知限制（真机验证结论）

1. **配置不可偏离 GKI 官方规范**（关 KASAN / LTO_NONE / 无 CFI 会 bootloop）——脚本已固化
2. **ZRAM lz4k/lz4kd 不可用**（第三方实现与 MTE 不兼容，会 bootloop）——用内核自带算法
3. **LZ4 升级补丁会导致 bootloop**——已弃用
4. **vendor 模块 vermagic 不匹配**：不加载但系统正常启动（实测），指纹/相机/音频正常

## 📚 文档

- [`AGENTS.md`](AGENTS.md) —— 开发/维护速览（构建流程、硬约束、环境陷阱、排查技巧）
- `scripts/` —— 01-07 构建脚本链（见 AGENTS.md 速查表）

## 🙏 致谢

- [Numbersf/Action-Build](https://github.com/Numbersf/Action-Build)（流程参考）
- [ShirkNeko/GKI_KernelSU_SUSFS](https://github.com/ShirkNeko/GKI_KernelSU_SUSFS)（GKI 构建参考）
- [SukiSU-Ultra](https://github.com/SukiSU-Ultra/SukiSU-Ultra)（Root 方案）
- [simonpunk/susfs4ksu](https://gitlab.com/simonpunk/susfs4ksu)（SUSFS）
- [WildKernels/AnyKernel3](https://github.com/WildKernels/AnyKernel3)（刷机模板）
- [Sakion-Team/Re-Kernel](https://github.com/Sakion-Team/Re-Kernel)（Re:Kernel）

## 📄 License

内核部分遵循 GPL-2.0（Linux 内核许可证）；脚本与配置遵循 GPL-2.0（参考项目均为 GPL）。
