# 把 EFI\OC 与 EFI\BOOT\BOOTx64.efi 部署到本机内置硬盘 ESP，并重建 OpenCore 固件启动项。
# 需管理员权限。绝不修改 S:\EFI\Microsoft。
# 用法：powershell -ExecutionPolicy Bypass -File deploy-to-esp.ps1 -SourceEfi <含 OC 与 BOOT 的 EFI 目录> [-WorkDir <工作目录>]
param(
    [Parameter(Mandatory = $true)][string]$SourceEfi,
    [string]$WorkDir = (Get-Location).Path,
    [string]$Letter = 'S'
)
$ErrorActionPreference = 'Stop'
$logFile = Join-Path $WorkDir 'esp-install-log.txt'
function Log($m) { $l = "[$(Get-Date -Format 'HH:mm:ss')] $m"; Write-Host $l; Add-Content -Path $logFile -Value $l -Encoding UTF8 }
Remove-Item -Force $logFile -ErrorAction SilentlyContinue

$drive = "${Letter}:"
try {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "Need Administrator."
    }
    if (-not (Test-Path "$SourceEfi\OC\OpenCore.efi") -or -not (Test-Path "$SourceEfi\OC\config.plist")) {
        throw "SourceEfi must contain OC\OpenCore.efi and OC\config.plist: $SourceEfi"
    }
    if (-not (Test-Path "$drive\")) { mountvol $drive /S | Out-Null }
    if (-not (Test-Path "$drive\EFI\Microsoft\Boot\bootmgfw.efi")) {
        throw "Windows Boot Manager not found on ESP; aborting to stay safe."
    }
    Log "[OK] ESP mounted at $drive"

    # 首次完整备份
    $bk = Join-Path $WorkDir 'ESP-Backup'
    if (-not (Test-Path $bk)) { Copy-Item -Recurse -Force "$drive\EFI" $bk; Log "[OK] Backed up original ESP EFI -> $bk" }

    # 回收启动日志
    $logsDir = Join-Path $WorkDir 'logs'
    New-Item -ItemType Directory -Force $logsDir | Out-Null
    Get-ChildItem "$drive\" -Filter 'opencore-*.txt' -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -Force $_.FullName (Join-Path $logsDir $_.Name); Log "[OK] Collected log $($_.Name)"
    }

    # 覆盖前保存 ESP 上现有 OC（可能含用户在 macOS 里做的改动）
    if (Test-Path "$drive\EFI\OC") {
        $snap = Join-Path $logsDir ("esp-oc-before-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Copy-Item -Recurse -Force "$drive\EFI\OC" $snap
        Log "[OK] Snapshot of existing ESP OC -> $snap"
        Remove-Item -Recurse -Force "$drive\EFI\OC"
    }
    Copy-Item -Recurse -Force "$SourceEfi\OC" "$drive\EFI\OC"
    New-Item -ItemType Directory -Force "$drive\EFI\BOOT" | Out-Null
    if (Test-Path "$SourceEfi\BOOT\BOOTx64.efi") {
        Copy-Item -Force "$SourceEfi\BOOT\BOOTx64.efi" "$drive\EFI\BOOT\BOOTx64.efi"
    }
    Log "[OK] Copied OC and BOOT"

    if (-not (Test-Path "$drive\EFI\OC\OpenCore.efi") -or -not (Test-Path "$drive\EFI\Microsoft\Boot\bootmgfw.efi")) {
        throw "Verification failed after copy."
    }

    # 重建固件启动项：先删旧的同名条目，再新建
    $fw = bcdedit /enum firmware | Out-String
    foreach ($blk in ($fw -split "(?m)^(?=[^\r\n]+\r?\n-{5,})")) {
        if ($blk -match 'OpenCore' -and $blk -match '(\{[0-9a-fA-F\-]+\})') {
            bcdedit /delete $matches[1] | Out-Null; Log "[INFO] Removed stale entry $($matches[1])"
        }
    }
    $cp = bcdedit /copy '{bootmgr}' /d 'OpenCore' | Out-String
    if ($cp -match '(\{[0-9a-fA-F\-]+\})') {
        $g = $matches[1]
        bcdedit /set $g path '\EFI\OC\OpenCore.efi' | Out-Null
        bcdedit /set '{fwbootmgr}' displayorder $g /addfirst | Out-Null
        Log "[OK] Registered firmware entry OpenCore $g as first"
    } else {
        Log "[WARN] bcdedit copy failed ($cp). Fallback: EFI\BOOT\BOOTx64.efi / set boot order in BIOS."
    }
    Log (bcdedit /enum '{fwbootmgr}' | Out-String)

    mountvol $drive /D | Out-Null
    Log "=== DONE ==="
} catch {
    Log "[ERROR] $($_.Exception.Message)"
    exit 1
}
