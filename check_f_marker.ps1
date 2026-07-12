$libappOut = "$env:TEMP\libapp.so"
$raw = [System.IO.File]::ReadAllBytes($libappOut)
$enc = [System.Text.Encoding]::ASCII

# Search for the F= marker and surrounding context
$marker = [byte[]]@(0x46,0x3D)  # "F="

$i = 0
$count = 0
while ($i -le $raw.Length - $marker.Length) {
    $match = $true
    for ($j = 0; $j -lt $marker.Length; $j++) {
        if ($raw[$i + $j] -ne $marker[$j]) { $match = $false; break }
    }
    if ($match) {
        $start = [Math]::Max(0, $i - 5)
        $end = [Math]::Min($raw.Length - 1, $i + 80)
        $context = $enc.GetString($raw, $start, $end - $start + 1) -replace '[\x00-\x1f\x7f]', '.'
        if ($context -match 'F=google|F=platform|F=|isG|isP') {
            Write-Host "[offset $i] $context"
            $count++
        }
        $i += $marker.Length
    } else {
        $i++
    }
}
if ($count -eq 0) { Write-Host "No 'F=' marker found in libapp.so" }