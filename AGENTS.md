# AGENTS.md — socrates (Redmi K60 Pro) 内核构建项目

> 给未来 agent/开发者的项目速览。详细方案与历史见 PLAN.md。

## 项目是什么

为 Redmi K60 Pro（socrates, SM8550/kalama, Android 13/HyperOS）编译带 **SukiSU Ultra + SUSFS + KPM** 的内核，本地与 GitHub Actions 双通道构建。

## 技术栈（最终验证状态，勿随意改动）

| 组件 | 值 |
|---|---|
| 内核源码 | ACK kernel/common tag `android13-5.15.211_r00`（纯 GKI，无 vendor 树） |
| 工具链 | clang r450784e (14.0.7)（与官方同款，googlesource 已删，从 GitHub release 下载） |
| Root | SukiSU Ultra **builtin 分支**（b1d534bc）+ SUSFS（susfs4ksu gki-android13-5.15） |
| KPM | CONFIG_KPM + patch_linux |
| 版本机制 | `SUKISU_VERSION` 统一入口（默认 builtin）；KSU_VERSION 自动同步 main 线（`40000+main commits-2815`），与官方 CI 管理器 APK versionCode 同源 |

## 🚨 真机验证的硬约束（bootloop 教训，不可违反）

1. **编译配置必须保持 GKI 官方规范**：
   - `KASAN_HW_TAGS=y`（MTE 硬件标签）、`LTO_CLANG_THIN=y`、`CFI_CLANG=y`、`SHADOW_CALL_STACK=y`、`DEBUG_INFO_BTF=y`
   - **任何"社区优化"（关 KASAN / LTO_NONE / 无 CFI）在 socrates 上必 bootloop**（多轮二分实测）
   - 02_set_config.sh 已固化此配置，不要再"优化"它
2. **ZRAM 第三方算法（lz4k/lz4kd）不可用**：SukiSU_patch 的实现与 KASAN_HW_TAGS(MTE) 不兼容，设为默认即 bootloop。ZRAM 用内核自带算法（lzo/lz4/zstd）
3. **LZ4 升级（Numbersf lz4_oplus）会导致 bootloop**（替换 lib/lz4 基础库），已弃用
4. **版本串**：-dirty 不影响启动（已实测）；注入固定干净串（`5.15.211-00002-g13a57ace02a3`）仅为可复现
5. **KSU_VERSION 数字任意值都能启动**（40796/40856 均验证）——不要把它当 bootloop 怀疑对象

## 构建流程（本地）

```bash
# 1. 准备（源码+工具链+依赖）
bash scripts/01_prepare_ack.sh                    # clang + ACK clone + 依赖

# 2. 集成（SukiSU/SUSFS/KPM/可选功能）
export KERNEL_DIR=$PWD/kernel_source SUKISU_CHECKOUT=/tmp/SukiSU-builtin-full SUKISU_VERSION=builtin
bash scripts/06_integrate_features.sh            # SUSFS_ENABLE/BBR_ENABLE/ZRAM_ENABLE/... 开关

# 3. 配置（KASAN_HW_TAGS + thin LTO + KSU_VERSION 自动同步 + 版本串固化）
export SUKISU_CHECKOUT=/tmp/SukiSU-builtin-full
bash scripts/02_set_config.sh

# 4. 编译（-j 默认 nproc-1；此环境 bash 工具 ~700s 超时，大编译需分段续跑）
bash scripts/03_build_kernel.sh -j3

# 5. 打包
bash scripts/04_make_ak3.sh                       # AnyKernel3 zip（KPM/SUSFS 开关）
bash scripts/05_make_bootimg.sh dist/boot.img out  # fastboot boot 测试镜像（自动 tar.zst 压缩）
```

## 真机验证流程

1. `fastboot boot boot-xxx.img.tar.zst`（解压后）——临时启动，失败自动回落，无风险
2. 验证：启动动画/桌面 + SukiSU 管理器显示版本（40856）+ 功能（指纹/相机/音频）
3. 通过后 AK3 刷入（recovery）
4. 恢复手段：`dist/boot-40796-recovery.img`（40796 内核临时启动）+ `dist/boot.img`（官方原厂）

## 脚本速查

| 脚本 | 作用 |
|---|---|
| `01_prepare_ack.sh` | clang r450784e + ACK clone + 第三方依赖 |
| `02_set_config.sh` | gki_defconfig + thin LTO（保持官方规范）+ KSU_VERSION 自动同步 + 版本串固化 + SUSFS/KPM/BBR/ZRAM 配置块 |
| `03_build_kernel.sh` | 编译（ccache/thinLTO 缓存可选，默认 -j nproc-1） |
| `04_make_ak3.sh` | AK3 打包（WildKernels 模板：block=boot + flash_boot，GKI 专用） |
| `05_make_bootimg.sh` | magiskboot 基于官方 boot.img 打包测试镜像（自动 zst 压缩） |
| `06_integrate_features.sh` | SukiSU/SUSFS/KPM/BBR/ZRAM/Unicode/LZ4 集成（SUSFS 幂等：tag 基线恢复） |
| `07_fetch_deps.sh` | SukiSU_patch/susfs4ksu/lz4_oplus/Re-Kernel/susfs 模块 依赖拉取 |
| `patch_makefile_version.sh` | 版本串注入（幂等） |

## 目录结构

```
socrates_kernel_build/
├── .github/workflows/build.yml   # CI（workflow_dispatch，参数化构建）
├── scripts/                      # 01-07 + common.sh
├── patches/                      # BBRv3 / unicode（可选）
├── anykernel3/                   # AK3 模板（tools 二进制入库，Image 不入库）
├── dist/                         # 产物（gitignore）
│   ├── AnyKernel3_socrates_*.zip # 刷机包
│   ├── boot-*.img(.tar.zst)      # 测试镜像
│   ├── boot.img                  # 官方原厂（打包输入）
│   └── SukiSU_*.apk              # 管理器
├── kernel_source_ack211/         # 本地主力树（独立 git 仓库，gitignore）
├── tools/                        # clang r450784e（gitignore）
└── PLAN.md                       # 完整方案与历史
```

## 环境怪象（本容器）

- **工作区文件可能被外部回滚**（git 仓库完好）——重要变更及时 `git commit`，操作前 `git status` 确认
- 全局 git 配置 `commit.gpgsign=true`（SSH 签名）但 agent 无 key——提交必须带 `-c commit.gpgsign=false`
- bash 工具调用 ~700s 超时——大编译需分段续跑（out/ 保留进度）；`-j3` 留一核
- googlesource 直连失败——走代理 `http://host.containers.internal:15524`（CI 自动跳过）
- `pkill -f` 模式会匹配自身命令行——用 PID 或精确模式
- 分段编译后若链接报 `__crc_*` ABS32 错误 = LTO 配置变化的混合 .o——需 `rm -rf out` 全量重编

## 平台硬知识（socrates 参考）

| 项 | 值 |
|---|---|
| 设备 | Redmi K60 Pro，SoC SM8550（kalama），Android 13/HyperOS |
| boot 格式 | **GKI header v4**，PAGE_SIZE=4096，BASE_ADDRESS=0x80000000，无 ramdisk（initramfs 在 vendor_boot） |
| vendor cmdline | `console=ttyMSM0,115200n8 earlycon=qcom_geni,0x00a9C000` + `bootconfig` |
| 分区 | 非 A/B 单 boot 分区；fastboot boot = 临时（失败静默回落到已装内核） |
| 设备树 | 当前 ACK 纯 GKI 构建**不带 dts**（用手机自带 dtb）；如需 dts 参考：`MiCode/kernel_devicetree@socrates-t-oss`（qcom/socrates-sm8550.dtsi + overlay + pinctrl，设计放 arch/arm64/boot/dts/vendor/） |
| 官方源码参考 | `MiCode/Xiaomi_Kernel_OpenSource@socrates-t-oss`（launch 时代 5.15.41；build.config 系列见其上）——仅参考，构建用 ACK |

## 模块/vermagic 经验

- 系统 vendor_dlkm 模块 vermagic 为官方版本（5.15.194-...）；我们内核 5.15.211 与其不匹配
- **实测**：不匹配时模块不加载，但**系统能正常启动**（真机确认），指纹/相机/音频等功能正常（驱动由系统侧提供或加载机制宽松）
- 版本串（-dirty/格式）不影响启动；KSU_VERSION 数字不影响启动

## 排查技巧

- **提取任意内核 Image 的完整 .config**：`scripts/extract-ikconfig Image`（需 CONFIG_IKCONFIG=y，gki 默认开）——bootloop 排查时用它与当前 .config 做 diff（当时靠它锁定了 KASAN_HW_TAGS 等差异）
- 链接报 `__crc_*` R_AARCH64_ABS32 错误 = LTO 配置切换后的混合 .o——`rm -rf out` 全量重编
- 修改配置后 `olddefconfig` 必须与 make 同环境（`CC=clang HOSTLD=ld.lld`），否则产生 (NEW) 交互

## CI（build.yml）要点

- 手动触发（workflow_dispatch），参数：ACK_TAG / SUKISU_VERSION（默认 builtin）/ SUSFS / KPM / BBR / RESUBLEVEL / SUFFIX / UPLOAD_RELEASE（ZRAM/LZ4/Unicode/Re:Kernel 已移除——lz4k 与 MTE 不兼容、LZ4 升级 bootloop、Re:Kernel 用户自行用成品模块）
- clang 缓存（GitHub cache）；ccache + thinLTO 缓存（编译 step CCACHE_ENABLE=1 + restore/save steps）
- APK：分支→官方 CI artifact；tag→release 资产（过渡方案，TODO: gradle 编译）
- 版本一致性校验 step：内核 KSU_VERSION vs APK versionCode
