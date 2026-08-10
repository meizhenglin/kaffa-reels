$path = 'C:\Users\admin\arab_drama_app\_head.txt'
$bytes = [System.IO.File]::ReadAllBytes($path)
Write-Host ('size: ' + $bytes.Length)
# Find the marker [MembershipPage] ===== VIP
$marker = [byte[]] @(91, 77, 101, 109, 98, 101, 114, 115, 104, 105, 112, 80, 97, 103, 101, 93, 32, 61, 61, 61, 61, 61, 32, 86, 73, 80)
$idx = -1
for ($i = 0; $i -lt $bytes.Length - $marker.Length; $i++) {
  $match = $true
  for ($j = 0; $j -lt $marker.Length; $j++) {
    if ($bytes[$i + $j] -ne $marker[$j]) { $match = $false; break }
  }
  if ($match) { $idx = $i; break }
}
Write-Host ('marker found at byte: ' + $idx)
if ($idx -ge 0) {
  $slice = $bytes[($idx)..($idx + 100)]
  Write-Host '--- bytes ---'
  Write-Host ([BitConverter]::ToString($slice))
}