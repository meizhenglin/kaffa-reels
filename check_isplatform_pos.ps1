$libappOut = "$env:TEMP\libapp.so"
$raw = [System.IO.File]::ReadAllBytes($libappOut)
$enc = [System.Text.Encoding]::ASCII

$marker = [byte[]]@(0x69,0x73,0x50,0x6C,0x61,0x74,0x66,0x6F,0x72,0x6D)
$i = 0
while ($i -le $raw.Length - $marker.Length) {
    $match = $true
    for ($j = 0; $j -lt $marker.Length; $j++) {
        if ($raw[$i + $j] -ne $marker[$j]) { $match = $false; break }
    }
    if ($match) {
        $start = [Math]::Max(0, $i - 50)
        $end = [Math]::Min($raw.Length - 1, $i + $marker.Length + 50)
        $context = $enc.GetString($raw, $start, $end - $start + 1) -replace '[\x00-\x1f\x7f]', '.'
        Write-Host "[offset $i]"
        Write-Host $context
        Write-Host "---"
        $i += $marker.Length
    } else {
        $i++
    }
}