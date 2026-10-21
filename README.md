# Hackintosh EFI Builder (AI Skill) 🍏💻

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![OpenCore](https://img.shields.io/badge/OpenCore-1.0.8+-blue.svg)](https://github.com/acidanthera/OpenCorePkg)
[![Platform](https://img.shields.io/badge/Platform-Windows-0078D6.svg)](https://microsoft.com/windows)

专为 AI 编程助手（Google Antigravity、Claude Code、Cursor、GitHub Copilot、GPT 等）设计的**全自动化黑苹果 OpenCore EFI 构建、部署与排障 Skill**。

无论在何种 x86 电脑上运行，该 Skill 均采用**硬件无关（Hardware-Agnostic）**的方法论，杜绝硬编码，由 AI 引导或全自动完成从硬件探测、兼容性判定、EFI 组配、U 盘恢复镜像制作，到硬盘 ESP 迁移与 Panic 排障的全流程。

---

## 🌟 核心特性

- **🔍 纯净硬件探测 (`scripts/detect-hardware.ps1`)**：只读扫描 CPU（代际/核心）、主板、显卡（PCI VID:DID）、声卡、网卡、NVMe/SATA 控制器及 USB xHCI 拓扑，输出结构化硬件报告。
- **📋 严谨兼容性判定逻辑**：涵盖 Intel 各代与 AMD Ryzen（Zen 1-5）、原生免驱 A 卡、老 N 卡与实验性第三方显卡驱动链路。
- **🛠️ 避坑与排障字典 (`references/troubleshooting.md`)**：汇总内核 Panic、`EXITBS:START`、PCI 挂死、`IONDRVSupport` 帧缓冲冲突、SMC 传感器错误等经典问题的取证与单变量归因方法。
- **💾 恢复镜像一键部署 (`scripts/download-recovery.ps1`)**：结合 OpenCore `macrecovery` 自动化下载目标 macOS 官方恢复环境（BaseSystem）写入 FAT32 U 盘。
- **🚀 内置硬盘 ESP 安全迁移 (`scripts/deploy-to-esp.ps1`)**：全自动挂载 ESP、留存快照备份、迁移 `EFI\OC` 与 `BOOTx64.efi`（绝不触碰 `EFI\Microsoft`），并利用 `bcdedit` 写入主板 UEFI NVRAM 第一启动项。

---

## 📂 仓库结构

```text
hackintosh-efi-builder/
├── SKILL.md                          # AI Agent 执行主提示词与核心工作流规范
├── README.md                         # 仓库说明文档
├── LICENSE                           # 开源许可 (MIT)
├── scripts/
│   ├── detect-hardware.ps1           # 硬件配置与 PCI VID:DID 自动化提取脚本
│   ├── download-recovery.ps1         # 官方 macOS 恢复镜像下载与 U 盘写入脚本
│   └── deploy-to-esp.ps1             # 内置硬盘 ESP 部署与固件启动项刷新脚本
└── references/
    └── troubleshooting.md            # 现象 → 根因 → 单变量动作 速查手册与日志判读法
```

---

## 🚀 如何在 AI Agent 中使用

### 1. 配合 Google Antigravity / Claude Code
将本仓库克隆或复制到 Agent 的 skills 目录下：
- **Antigravity 全局目录**：`~/.gemini/config/skills/hackintosh-efi-builder`
- **项目工作区目录**：`<Your-Project>/.gemini/skills/hackintosh-efi-builder`

或者在对话中直接引用 `SKILL.md`：
> *"请阅读 hackintosh-efi-builder/SKILL.md，帮我分析本机硬件并构建对应的 OpenCore 引导配置。"*

### 2. 人工手动运行
各 PowerShell 脚本均可独立脱离 AI 运行（以管理员身份启动 PowerShell）：
```powershell
# 1. 导出本机硬件信息
.\scripts\detect-hardware.ps1

# 2. 下载 macOS Sequoia 恢复镜像并写入 U 盘 (如 E 盘)
.\scripts\download-recovery.ps1 -MacRecoveryDir "D:\OpenCore\Utilities\macrecovery" -BoardId "Mac-7BA5B2D9E42DDD94" -UsbRoot "E:\"

# 3. 部署测试通过的 EFI 到本机内置固态硬盘 ESP
.\scripts\deploy-to-esp.ps1 -SourceEfi "D:\my-efi\EFI"
```

---

## ⚠️ 免责声明 (Disclaimer)

1. 本项目仅供技术交流与计算机架构学习使用。
2. macOS 是 Apple Inc. 在美国及其他国家/地区注册的商标。
3. 请严格遵守当地法律法规及相关最终用户许可协议（EULA）。
