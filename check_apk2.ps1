$apkPath = (Resolve-Path "build\app\outputs\flutter-apk\app-arm64-v8a-google-release.apk").Path
$temp = $env:TEMP
$libappOut = "$temp\libapp.so"

# Reuse previous extraction logic — assuming $libappOut already exists.
if (-not (Test-Path $libappOut)) { Write-Error "Run previous script first"; exit 1 }

$raw = [System.IO.File]::ReadAllBytes($libappOut)
$enc = [System.Text.Encoding]::ASCII

# Count occurrences by scanning byte windows
$markerGoogle = [byte[]]@(0x67,0x6F,0x6F,0x67,0x6C,0x65)  # "google"
$markerPlatform = [byte[]]@(0x70,0x6C,0x61,0x74,0x66,0x6F,0x72,0x6D)  # "platform"

function Count-Occurrences([byte[]]$haystack, [byte[]]$needle) {
    $n = 0; $i = 0
    while ($i -le $haystack.Length - $needle.Length) {
        $match = $true
        for ($j = 0; $j -lt $needle.Length; $j++) {
            if ($haystack[$i + $j] -ne $needle[$j]) { $match = $false; break }
        }
        if ($match) { $n++; $i += $needle.Length } else { $i++ }
    }
    return $n
}

$googleHits = Count-Occurrences $raw $markerGoogle
$platformHits = Count-Occurrences $raw $markerPlatform
Write-Host "byte 'google' anywhere: $googleHits"
Write-Host "byte 'platform' anywhere: $platformHits"

# For each occurrence, show surrounding 80-byte printable context
$ctxLen = 80
Write-Host "`n--- google contexts (showing surrounding 80 bytes as printable) ---"
$idx = 0
while ($idx -le $raw.Length - $markerGoogle.Length -and ($ctx = ([regex]::Matches(($enc.GetString($raw, [Math]::Max(0, $idx - 40), [Math]::Min($ctxLen, $raw.Length - $idx + 40))).ToString().Substring(0, [Math]::Min(120, $raw.Length - $idx + 40)))) -ne $null)) {
    $i = 0
    while ($i -le $raw.Length - $markerGoogle.Length) {
        $match = $true
        for ($j = 0; $j -lt $markerGoogle.Length; $j++) {
            if ($raw[$i + $j] -ne $markerGoogle[$j]) { $match = $false; break }
        }
        if ($match) {
            $start = [Math]::Max(0, $i - 30)
            $end = [Math]::Min($raw.Length, $i + $markerGoogle.Length + 30)
            $sub = $raw[$start..($end-1)] -join ','
            Write-Host "[offset $i] $($enc.GetString($raw, $start, $end - $start))"
            $i += $markerGoogle.Length
        } else {
            $i++
        }
    }
}
