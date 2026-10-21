---
name: hackintosh-efi-builder
description: 在任意 Windows 电脑上，从零探测硬件 → 判定兼容性 → 生成/调试 OpenCore EFI → 部署到 U 盘或内置硬盘 ESP → 根据启动日志与 panic 画面排障。适用于用户要求"做黑苹果 EFI / 配 OpenCore / 黑苹果启动报错 / EFI 转移到硬盘 / NVIDIA 第三方驱动"。所有步骤硬件无关，不含任何固定机型数据。
---

# 黑苹果 EFI 构建与排障流程（硬件无关版）

> 给执行者（含较弱的 AI）的总原则：**一次只改一件事；每次改动前备份；每次改动后让用户重启并回传证据（照片/日志）；不凭记忆编造 kext 版本、哈希、序列号。**

## 0. 铁律（先读）

1. **永远先备份**：改 `config.plist`、覆盖 ESP 前，整份 `EFI\OC` 复制到 `backups\<时间戳>\`。
2. **以"目标机上真实运行过的 EFI"为准**。用户可能在 macOS 里改过 EFI（挂载 ESP 改的）。部署前先从 ESP/U 盘**拉回**当前版本，与工作区做 diff，**严禁用工作区旧文件盲目覆盖**。
3. **不修改 `EFI\Microsoft`**（Windows 引导），不动用户其他分区。
4. **不编造数据**：SMBIOS 序列号/MLB/UUID 用 `macserial`/GenSMBIOS 本地生成；kext/驱动只从官方 release 下载并核对 SHA256。
5. **一次一个变量**：同时改多项会无法归因。
6. 只读审查日志优先于猜测；日志在 `ESP根目录\opencore-*.txt`（需 `Misc→Debug→Target` 开启文件日志）。
7. 部署脚本若需管理员权限，让用户双击 `.bat`（UAC），完成后读取脚本日志回读校验，不信"已完成"自述。

## 1. 采集硬件（脚本：`scripts/detect-hardware.ps1`）

运行后得到：CPU 型号/代际、主板、显卡（含 PCI VID:DID）、声卡、网卡（有线/无线 VID:DID）、蓝牙、NVMe/SATA 控制器、USB 控制器数量、固件模式（UEFI/Legacy）、Secure Boot、磁盘分区表（需 GPT + ESP）。把输出存入 `reports\hardware.txt`。

## 2. 兼容性判定（逐项给结论，用表格）

| 部件 | 判定要点 |
|---|---|
| CPU | Intel：按代际选 SMBIOS 与 SSDT-PLUG；AMD：需 AMD_Vanilla 内核补丁（核心数补丁须按**实际核数**改）、`ProvideCurrentCpuInfo=true`、`DummyPowerManagement=true`、AppleMCEReporterDisabler |
| 显卡 | 查 macOS 原生支持表（AMD Polaris/Navi 免驱；NVIDIA Kepler 老系统；Maxwell 及以后在新系统无官方驱动）。**无原生支持 = 必须换卡或走第三方驱动（实验级，须告知风险）**；无核显的 CPU 必须有受支持独显 |
| 网卡 | Intel I225/I226、Realtek RTL8125/8111 等各有对应 kext；Intel 无线用 itlwm(+HeliPort) 或 AirportItlwm（版本要匹配 macOS） |
| 蓝牙 | Intel：IntelBluetoothFirmware+IntelBTPatcher+BlueToolFixup |
| 声卡 | AppleALC + layout-id（按 codec 查），AMD 麦克风常不可用 |
| NVMe | 加 NVMeFix；个别主控兼容性差，作为排查对象 |
| USB | 必须做端口映射（USBToolBox Windows 工具），单控制器 >15 口需映射 |

不可行项直说，不要含糊。**唯一推荐方案 + 最小第一步**，不要给用户一堆选项。

## 3. 准备文件

1. 取最新**正式版** OpenCore（官方 GitHub release，核对版本号确实存在）。使用其中 `X64\EFI`、`Utilities\ocvalidate`、`Utilities\macserial`。
2. 从官方 release 下载所需 kext：Lilu（必须第一个）、VirtualSMC、WhateverGreen（有独显修补需求时）、AppleALC、NVMeFix、RestrictEvents、网卡/蓝牙/USB 相关。每个记录版本与 SHA256 到 `reports\sources.md`。
3. ACPI：桌面通用必备 `SSDT-EC-USBX`（或分开的 EC、USBX）；Intel 加 `SSDT-PLUG`；AMD 不要 SSDT-PLUG；其它 SSDT 仅在出现对应症状时再加。
4. Drivers：`OpenRuntime.efi`、`HfsPlus.efi`、`ResetNvramEntry.efi`（可选 `ToggleSipEntry.efi`）。
5. 目录结构：
```
EFI\BOOT\BOOTx64.efi
EFI\OC\{OpenCore.efi, config.plist, ACPI\, Drivers\, Kexts\, Tools\}
```

## 4. 编写 config.plist

- 以官方 `Sample.plist` 为底，**只改必要键**；不要整份复制网上 config。
- Kext 加载顺序 = `Kernel→Add` 顺序：Lilu → 其余依赖它的 → VirtualSMC → 其它。
- **SMC 传感器插件规则（血泪教训）**：
  - `SMCProcessor`：**仅 Intel 可用**，AMD 上不要加。
  - `SMCSuperIO`：读主板 Super I/O 芯片（风扇/电压），Intel 与 AMD 都能用；但**依赖具体芯片型号支持**，且版本必须与 VirtualSMC 完全一致。它是可选件，默认不加。
  - `AMDRyzenCPUPowerManagement`/`SMCAMDProcessor`：新平台上不稳定，默认不启用。
  - **任何 SMC 插件都只能在系统已稳定后单独加入**。加入后若出现 `Kernel trap`（13/14）panic，立刻移除该插件复测，以复测结果为准，不要凭"某 kext 是某平台专用"下结论。
- 启动调试：`Misc→Debug→Target` 开文件日志（如 67）、`AppleDebug=true`、`DisableWatchDog=true`；boot-args 含 `-v debug=0x100 keepsyms=1`。
- `Misc→Boot`：`LauncherOption=Full`（OpenCore 自行向固件注册第一启动项，防 Reset NVRAM 后启动项丢失）。
- `ResetNvramEntry.efi` 的 `Arguments` 设为 `--preserve-boot`（Reset NVRAM 不清启动项）。
- `Misc→Security`：`DmgLoading` 若需用安装器/恢复镜像应为 `Signed`（设 `Disabled` 会导致安装器无法加载）；`SecureBootModel` 通常 `Disabled`。
- SMBIOS：按 CPU 代际选机型；序列号等用 `macserial` 本地生成，**不可留空也不可抄别人**。
- 每次修改后运行 `ocvalidate config.plist`，必须 `No issues found`。

### AMD 专项
- 内核补丁来自 AMD-OSX/AMD_Vanilla 对应分支；`cpuid_cores_per_package` 四条按实际核数修改。
- 新平台（AM5 等）常需：`DevirtualiseMmio`/`SetupVirtualMap`/`AllowRelocationBlock` 组合、IOPCIFamily probeBusGated 补丁。以 Dortania 指南与对应主板社区 EFI 为准，不确定处标"未证实"。
- PAT 补丁：N 卡选 Algrey/Zormeister 版；Shaneee 版会让 NVIDIA 卡无法启动。

### NVIDIA 第三方驱动（如 nullmoth/nvidia-macos-driver，实验级）
两阶段：
1. **安装期**：`Booter→ResizeAppleGpuBars=0`；不加 Block；用原生 UEFI GOP 帧缓冲进系统。
2. **驱动装好后**：`ResizeAppleGpuBars=-1`，按作者文档加入所需 boot-args（如 `gfxrst=4`、`amfi_get_out_of_my_way=0x1`、`nvfb/nvaccel` 等）。
- 驱动本体装到 `/Library/Extensions`，**不要**放进 `EFI\OC\Kexts`。
- `Kernel→Block` 屏蔽 `com.apple.iokit.IONDRVSupport` **仅在驱动已装好且 NVRMFB 已批准之后**才启用；过早启用会让系统失去帧缓冲，表现为 verbose 末尾卡在 `consoleUsersPropertyObject`/`Users() -> 0x0`（黑屏卡住）。排障时先关掉此 Block 试。
- 驱动官方 App 若会改写 `config.plist`，运行前先备份，运行后 diff 看它改了什么。

## 5. 部署

### 5.1 U 盘（EFI + 对应版本的恢复镜像，两者缺一不可）
U 盘要做成"能安装 macOS"的启动盘，必须同时有：
1. `EFI\`（OpenCore）
2. `com.apple.recovery.boot\`（目标 macOS 版本的恢复镜像：`BaseSystem.dmg` + `BaseSystem.chunklist`，或 `RecoveryImage.dmg` + `.chunklist`）

步骤（脚本：`scripts/download-recovery.ps1`，封装 OpenCore 自带 `Utilities\macrecovery`，需 Python 3 与联网）：
- **先确定目标 macOS 版本**，并与 EFI 的 kext/补丁适配范围一致。恢复镜像版本 ≠ 目标版本会导致装出别的系统或安装失败。
- 选对应的 board-id（`-b`）下载，常见对应（**执行前以 Dortania 当期文档核对**）：
  - Ventura 13：`Mac-B4831CEBD52A0C4C`
  - Sonoma 14：`Mac-827FAC58A8FDFA22`
  - Sequoia 15：`Mac-7BA5B2D9E42DDD94`
  - `-m 00000000000000000` 为通用写法。
- U 盘：**GPT + FAT32**（大 U 盘需用工具格式化为 FAT32），根目录放 `EFI` 与 `com.apple.recovery.boot`。
- `config.plist` 必须 `Misc→Security→DmgLoading = Signed`，`SecureBootModel = Disabled`；`UEFI→Drivers` 含 `HfsPlus.efi`。
- 校验：下载后 `.dmg` 与 `.chunklist` 大小非 0；启动 OpenCore 菜单应出现 `macOS Base System (External)`（或 `Install macOS ...`）项。
- 在 `reports\sources.md` 记录：目标版本、board-id、下载时间、文件大小/SHA256。
- 该 U 盘仅用于安装；装好后按 5.2 把 EFI 迁到内置硬盘。
- 首次进恢复环境后，先在"磁盘工具"里把目标盘抹成 APFS（GUID），再安装。

BIOS 选 U 盘的 UEFI 项启动。

### 5.2 迁移到内置硬盘 ESP（脚本：`scripts/deploy-to-esp.ps1`）
- 挂载 ESP（`mountvol S: /S`），**只写 `S:\EFI\OC` 与 `S:\EFI\BOOT\BOOTx64.efi`**，不碰 `S:\EFI\Microsoft`。
- 首次部署前整份备份 `S:\EFI`。
- 用 `bcdedit` 注册固件启动项：先**删除旧的同名 `OpenCore` 条目**再新建（Windows BCD 缓存可能残留已被 Reset NVRAM 清掉的假条目，只检查"名字存在"会误判），路径 `\EFI\OC\OpenCore.efi`，`displayorder ... /addfirst`。
- 脚本结束把 `opencore-*.txt` 日志回收到工作区 `logs\`。
- 若重启直接进了 Windows 桌面：多半是 NVRAM 被重置、固件回退 Windows → 重新跑脚本即可，并确认 `LauncherOption=Full`。

## 6. 排障循环

每轮：**拿证据 → 定位 → 单点修改 → ocvalidate → 部署 → 重启验证**。

证据来源（让用户提供）：
1. 卡住/panic 屏幕**照片**（verbose 最后 20 行、panic 的 `Kernel trap`、`type =`、`RIP`、`Backtrace`/`Kernel Extensions in backtrace`）。
2. ESP 里的 `opencore-*.txt`（看 `Prelinked injection ... Success` 列表确认实际注入了哪些 kext；看最后一行是否到 `EXITBS:START`）。
3. 对比"最后一次成功日志"与"失败日志"的差异（kext 列表、补丁、Block）。

常见症状速查见 `references/troubleshooting.md`。

## 7. 交付物清单

- `EFI\`（最终可启动版）
- `backups\`（每次改动前快照）
- `reports\hardware.txt`、`reports\sources.md`（来源+SHA256）、`reports\ocvalidate-*.txt`
- `logs\`（回收的启动日志）
- `docs\交接.md`：当前状态、已验证项、未解决项、下一步唯一动作

## 8. 与用户沟通

结论先行；表格；明确指出风险与不可达项；每轮只给**一个**下一步动作。不要让用户做选择题。
