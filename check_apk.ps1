Add-Type -AssemblyName "System.IO.Compression"
$apkPath = (Resolve-Path "build\app\outputs\flutter-apk\app-arm64-v8a-google-release.apk").Path
$temp = $env:TEMP
$libappOut = "$temp\libapp.so"

# Find libapp.so entry manually by scanning for PK signature at end of file
$bytes = [System.IO.File]::ReadAllBytes($apkPath)
$size = $bytes.Length

# Locate end-of-central-directory
$eocdOffset = -1
for ($i = $size - 22; $i -gt $size - 65557 -and $i -gt 0; $i--) {
    if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x05 -and $bytes[$i+3] -eq 0x06) {
        $eocdOffset = $i; break
    }
}
if ($eocdOffset -lt 0) { Write-Error "no EOCD"; exit 1 }
Write-Host "EOCD at $eocdOffset"
$cdSize  = [System.BitConverter]::ToInt32($bytes, $eocdOffset + 12)
$cdOff   = [System.BitConverter]::ToInt32($bytes, $eocdOffset + 16)
Write-Host "Central dir offset=$cdOff size=$cdSize"

# Walk central directory entries
$pos = $cdOff
$found = $false
while ($pos -lt $cdOff + $cdSize) {
    if ($bytes[$pos] -ne 0x50 -or $bytes[$pos+1] -ne 0x4B -or $bytes[$pos+2] -ne 0x01 -or $bytes[$pos+3] -ne 0x02) { break }
    $nameLen = [System.BitConverter]::ToInt16($bytes, $pos + 28)
    $extraLen = [System.BitConverter]::ToInt16($bytes, $pos + 30)
    $commLen  = [System.BitConverter]::ToInt16($bytes, $pos + 32)
    $localHdr = [System.BitConverter]::ToInt32($bytes, $pos + 42)
    $name = [System.Text.Encoding]::UTF8.GetString($bytes, $pos + 46, $nameLen)
    if ($name -eq 'lib/arm64-v8a/libapp.so') {
        Write-Host "FOUND libapp.so at CD pos=$pos, local header at $localHdr"
        # Parse local header
        $method = [System.BitConverter]::ToInt16($bytes, $localHdr + 8)
        $compSize = [System.BitConverter]::ToInt32($bytes, $localHdr + 18)
        $localNameLen = [System.BitConverter]::ToInt16($bytes, $localHdr + 26)
        $localExtraLen = [System.BitConverter]::ToInt16($bytes, $localHdr + 28)
        $dataOff = $localHdr + 30 + $localNameLen + $localExtraLen
        Write-Host "method=$method compSize=$compSize dataOff=$dataOff"

        $compressed = $bytes[$dataOff..($dataOff + $compSize - 1)]
        $ms = New-Object System.IO.MemoryStream (,[byte[]]$compressed)
        if ($method -eq 0) {
            $raw = $compressed
        } elseif ($method -eq 8) {
            $ds = New-Object System.IO.Compression.DeflateStream $ms, ([System.IO.Compression.CompressionMode]::Decompress)
            $outMs = New-Object System.IO.MemoryStream
            $ds.CopyTo($outMs)
            $ds.Dispose()
            $raw = $outMs.ToArray()
        } else {
            Write-Error "unsupported method $method"; exit 1
        }
        Write-Host "libapp.so raw size: $($raw.Length)"
        [System.IO.File]::WriteAllBytes($libappOut, $raw)

        # Now do strings search
        $all = [System.Text.Encoding]::ASCII.GetString($raw)
        $matches = [regex]::Matches($all, '[ -~]{6,}')
        $googleCount = 0
        $platformCount = 0
        foreach ($m in $matches) {
            if ($m.Value -eq 'google') { $googleCount++ }
            if ($m.Value -eq 'platform') { $platformCount++ }
        }
        Write-Host "literal 'google' exact word: $googleCount"
        Write-Host "literal 'platform' exact word: $platformCount"

        Write-Host "--- 20 short lines containing platform ---"
        $printed = 0
        foreach ($m in $matches) {
            if ($printed -ge 20) { break }
            if ($m.Value.Length -lt 200 -and $m.Value.Contains('platform')) {
                Write-Host $m.Value
                $printed++
            }
        }
        $found = $true
        break
    }
    $pos += 46 + $nameLen + $extraLen + $commLen
}
if (-not $found) { Write-Error "libapp.so not in archive" }
