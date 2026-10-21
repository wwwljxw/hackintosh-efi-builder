# 症状 → 原因 → 动作 速查

| 症状 | 常见原因 | 动作（一次只做一项） |
|---|---|---|
| OpenCore 菜单都不出现，直接进 Windows | 固件启动项丢失（Reset NVRAM / BIOS 更新 / 换盘） | 重跑 ESP 部署脚本（重建固件启动项）；确认 `LauncherOption=Full`；BIOS 里把 OpenCore/磁盘设首位 |
| 卡 `EXITBS:START` | Booter quirks 不匹配 | 依次试：`SetupVirtualMap`、`DevirtualiseMmio`、`RebuildAppleMemoryMap`/`EnableWriteUnprotector`（二选一不要同开）、`ProvideCustomSlide` |
| 卡 `PCI configuration begin` | ReBAR/大 BAR、`ResizeAppleGpuBars` | `ResizeAppleGpuBars=0`，BIOS 关 Above 4G/ReBAR 对比测试 |
| 卡 `AppleACPICPU` / `ACPI` 阶段重启 | CPU 补丁/核心数不对（AMD） | 核对 `cpuid_cores_per_package` 与实际核数；`ProvideCurrentCpuInfo=true` |
| 卡 `[EB|...]`/`Waiting for root device` | 磁盘/NVMe 驱动、USB 映射 | 加 NVMeFix；换到 SATA/其他 NVMe 测试；检查 USB 映射 |
| 卡 `AssertMacros: consoleUsersPropertyObject ... Users() -> 0x0` | 无帧缓冲：屏蔽了 `IONDRVSupport` 但第三方显卡驱动未生效 | 关闭 `Kernel→Block` 中 `com.apple.iokit.IONDRVSupport`，用原生 UEFI GOP 进系统后再装/修驱动 |
| `Kernel trap type = 13 (general protection)` / `14 (page fault)`，nested panic，刚加了 SMC 相关 kext | 可能原因（未逐一证实）：AMD 上加了 Intel 专用的 `SMCProcessor`；`SMCSuperIO` 与 VirtualSMC 版本不一致；`SMCSuperIO` 对该主板芯片的访问异常 | 移除新加的 SMC 插件，只留 `VirtualSMC` 本体复测；确认恢复后再按"版本一致"重新单独加入，逐个定位 |
| panic 里 backtrace 指向某 kext | 该 kext 冲突/版本不匹配 | 日志里确认其注入；禁用它（`Enabled=false`）二分定位 |
| 安装器/恢复镜像打不开、`Failed to load image` | `DmgLoading=Disabled` | 设 `Signed` |
| 键盘灯不亮/USB 无响应 | USB 映射缺失或端口超限 | USBToolBox 重新映射；临时用 `XhciPortLimit`（仅 macOS 11.3 以下有效） |
| 进系统后无硬件加速/分辨率低 | 独显无驱动 | 回到兼容性判定，确认原生支持或第三方驱动是否已装并启用 |
| iServices 登录失败 | SMBIOS 无效/重复 | 本地重新生成序列号/MLB/UUID/ROM，确保 en0 内建 |
| Wi-Fi/蓝牙不工作 | 版本与 macOS 不匹配 | 对照 kext 支持矩阵；AirportItlwm 与 itlwm 二选一 |
| 睡眠后黑屏/掉卡 | USB/显卡驱动限制 | 先禁用睡眠（`pmset -a sleep 0 hibernatemode 0`）保稳定 |

## 取证清单（请用户提供）
1. 屏幕照片（完整 panic 或最后 20 行 verbose）。
2. ESP 根目录 `opencore-*.txt`。
3. 最近一次改了什么（kext/配置/驱动安装）。

## 日志判读小抄
- `Prelinked injection X.kext () - Success`：X 真的被注入。没出现 = 没加载。
- `Should boot from N. <名称>`：用户选了哪个菜单项（`Reset NVRAM` 会清固件变量）。
- `Deleting ...:BootOrder... OK`：固件启动顺序被清空。
- 日志末行为 `EXITBS:START`：OpenCore 已交棒给内核，后续问题在 macOS 内核/kext 阶段。
