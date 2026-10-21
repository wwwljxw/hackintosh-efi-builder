# 硬件探测（只读，不修改系统）。输出到 reports\hardware.txt
# 用法：powershell -ExecutionPolicy Bypass -File detect-hardware.ps1 [-OutDir <目录>]
param([string]$OutDir = (Join-Path (Get-Location) 'reports'))

New-Item -ItemType Directory -Force $OutDir | Out-Null
$out = Join-Path $OutDir 'hardware.txt'
$lines = New-Object System.Collections.Generic.List[string]
function Add($t) { $lines.Add($t) | Out-Null }

Add "=== CPU ==="
Get-CimInstance Win32_Processor | ForEach-Object {
    Add "$($_.Name) | cores=$($_.NumberOfCores) threads=$($_.NumberOfLogicalProcessors) | $($_.Manufacturer)"
}

Add "`n=== Mainboard / BIOS ==="
$bb = Get-CimInstance Win32_BaseBoard
Add "$($bb.Manufacturer) $($bb.Product)"
$bios = Get-CimInstance Win32_BIOS
Add "BIOS: $($bios.Manufacturer) $($bios.SMBIOSBIOSVersion)"

Add "`n=== Firmware ==="
try { Add "SecureBoot enabled: $(Confirm-SecureBootUEFI)" } catch { Add "SecureBoot: unknown or Legacy BIOS" }
Add "Firmware type: $env:firmware_type"

Add "`n=== PCI devices (VID:DID) ==="
Get-PnpDevice -PresentOnly -Class Display, Net, Media, Bluetooth, USB, HDC, SCSIAdapter, System -ErrorAction SilentlyContinue |
  Where-Object { $_.InstanceId -like 'PCI\*' -or $_.InstanceId -like 'USB\VID*' } |
  ForEach-Object {
    $id = $_.InstanceId
    $ven = if ($id -match 'VEN_([0-9A-F]{4})') { $matches[1] } elseif ($id -match 'VID_([0-9A-F]{4})') { $matches[1] } else { '' }
    $dev = if ($id -match 'DEV_([0-9A-F]{4})') { $matches[1] } elseif ($id -match 'PID_([0-9A-F]{4})') { $matches[1] } else { '' }
    Add "[$($_.Class)] $($_.FriendlyName) | $ven`:$dev | $id"
  }

Add "`n=== GPU ==="
Get-CimInstance Win32_VideoController | ForEach-Object { Add "$($_.Name) | $($_.PNPDeviceID)" }

Add "`n=== Network adapters ==="
Get-NetAdapter -Physical -ErrorAction SilentlyContinue | ForEach-Object {
    Add "$($_.Name) | $($_.InterfaceDescription) | MAC=$($_.MacAddress) | $($_.LinkSpeed)"
}

Add "`n=== Audio ==="
Get-CimInstance Win32_SoundDevice | ForEach-Object { Add "$($_.Name) | $($_.PNPDeviceID)" }

Add "`n=== Disks / partition style ==="
Get-Disk | ForEach-Object {
    Add "Disk $($_.Number): $($_.FriendlyName) | $([math]::Round($_.Size/1GB)) GB | $($_.PartitionStyle) | Bus=$($_.BusType)"
    Get-Partition -DiskNumber $_.Number -ErrorAction SilentlyContinue | ForEach-Object {
        Add "    Part $($_.PartitionNumber): $($_.Type) | $([math]::Round($_.Size/1MB)) MB | Letter=$($_.DriveLetter)"
    }
}

Add "`n=== USB controllers ==="
Get-PnpDevice -PresentOnly -Class USB -ErrorAction SilentlyContinue |
  Where-Object { $_.FriendlyName -match 'xHCI|Host Controller|eXtensible' } |
  ForEach-Object { Add "$($_.FriendlyName) | $($_.InstanceId)" }

$lines | Set-Content -Path $out -Encoding UTF8
Write-Host "Saved: $out"
