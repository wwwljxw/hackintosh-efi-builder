# 下载指定 macOS 版本的恢复镜像，并写入 U 盘根目录 com.apple.recovery.boot。
# 依赖：Python 3、联网、OpenCore 发布包里的 Utilities\macrecovery 目录。
# 用法：
#   powershell -ExecutionPolicy Bypass -File download-recovery.ps1 `
#       -MacRecoveryDir <...\Utilities\macrecovery> -BoardId <board-id> -UsbRoot <U盘根目录，如 E:\>
# BoardId 与 macOS 版本的对应关系请以 Dortania 当期文档为准，不要凭记忆填。
param(
    [Parameter(Mandatory = $true)][string]$MacRecoveryDir,
    [Parameter(Mandatory = $true)][string]$BoardId,
    [Parameter(Mandatory = $true)][string]$UsbRoot,
    [string]$Mlb = '00000000000000000',
    [string]$WorkDir = (Join-Path (Get-Location).Path 'recovery-download')
)
$ErrorActionPreference = 'Stop'

$py = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
if (-not $py) { throw 'Python 3 not found.' }
$script = Join-Path $MacRecoveryDir 'macrecovery.py'
if (-not (Test-Path $script)) { throw "macrecovery.py not found in $MacRecoveryDir" }
if (-not (Test-Path $UsbRoot)) { throw "USB root not found: $UsbRoot" }

$fs = (Get-Volume -DriveLetter ($UsbRoot.Substring(0, 1)) -ErrorAction SilentlyContinue).FileSystem
if ($fs -and $fs -ne 'FAT32') { Write-Warning "USB file system is $fs, expected FAT32." }

New-Item -ItemType Directory -Force $WorkDir | Out-Null
Push-Location $WorkDir
try {
    & $py.Source $script -b $BoardId -m $Mlb download
    if ($LASTEXITCODE -ne 0) { throw "macrecovery failed with exit code $LASTEXITCODE" }
} finally { Pop-Location }

$src = Get-ChildItem -Path $WorkDir -Directory -Recurse -Filter 'com.apple.recovery.boot' | Select-Object -First 1
if (-not $src) { $src = Get-Item (Join-Path $MacRecoveryDir 'com.apple.recovery.boot') -ErrorAction SilentlyContinue }
if (-not $src) { throw 'Downloaded com.apple.recovery.boot folder not found.' }

$dst = Join-Path $UsbRoot 'com.apple.recovery.boot'
New-Item -ItemType Directory -Force $dst | Out-Null
Copy-Item -Force (Join-Path $src.FullName '*') $dst

# 回读校验
$files = Get-ChildItem $dst -File
$dmg = $files | Where-Object { $_.Extension -eq '.dmg' }
$chunk = $files | Where-Object { $_.Extension -eq '.chunklist' }
if (-not $dmg -or -not $chunk -or ($dmg | Where-Object { $_.Length -eq 0 })) { throw 'Verification failed: dmg/chunklist missing or empty.' }
$files | ForEach-Object { Write-Host ("{0}  {1:N0} bytes  SHA256={2}" -f $_.Name, $_.Length, (Get-FileHash $_.FullName).Hash) }
Write-Host "[OK] Recovery image written to $dst. Record BoardId=$BoardId in reports\sources.md"
