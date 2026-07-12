$libappOut = "$env:TEMP\libapp.so"
$raw = [System.IO.File]::ReadAllBytes($libappOut)
$enc = [System.Text.Encoding]::ASCII

$markerPlatform = [byte[]]@(0x70,0x6C,0x61,0x74,0x66,0x6F,0x72,0x6D)

$i = 0
$count = 0
while ($i -le $raw.Length - $markerPlatform.Length) {
    $match = $true
    for ($j = 0; $j -lt $markerPlatform.Length; $j++) {
        if ($raw[$i + $j] -ne $markerPlatform[$j]) { $match = $false; break }
    }
    if ($match) {
        # Print context: 60 bytes
        $start = [Math]::Max(0, $i - 30)
        $end = [Math]::Min($raw.Length - 1, $i + $markerPlatform.Length + 30)
        $context = $enc.GetString($raw, $start, $end - $start + 1) -replace '[\x00-\x1f]', '.'
        Write-Host "[offset $i] $context"
        $count++
        if ($count -ge 30) { break }
        $i += $markerPlatform.Length
    } else {
        $i++
    }
}
