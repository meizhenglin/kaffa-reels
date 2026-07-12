$libappOut = "$env:TEMP\libapp.so"
$raw = [System.IO.File]::ReadAllBytes($libappOut)
$enc = [System.Text.Encoding]::ASCII

# Search for build_flavor class member names — they get inlined but the
# referenced string constants remain. Check for ['google', 'platform']
# both as standalone and near "FLAVOR".

# 1) Look for 'FLAVOR' string anywhere (env var name constant)
$flavor = [byte[]]@(0x46,0x4C,0x41,0x56,0x4F,0x52)
$positions = @()
$i = 0
while ($i -le $raw.Length - $flavor.Length) {
    $match = $true
    for ($j = 0; $j -lt $flavor.Length; $j++) {
        if ($raw[$i + $j] -ne $flavor[$j]) { $match = $false; break }
    }
    if ($match) { $positions += $i; $i += $flavor.Length } else { $i++ }
}
Write-Host "'FLAVOR' positions: $($positions.Count)"

# 2) Search 'google' and 'platform' exact substrings (these survive even if isolated)
$markerGoogle = [byte[]]@(0x67,0x6F,0x6F,0x67,0x6C,0x65)
$markerPlatform = [byte[]]@(0x70,0x6C,0x61,0x74,0x66,0x6F,0x72,0x6D)

function CountExact([byte[]]$haystack, [byte[]]$needle) {
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

$googleExact = CountExact $raw $markerGoogle
$platformExact = CountExact $raw $markerPlatform
Write-Host "'google' substring count: $googleExact"
Write-Host "'platform' substring count: $platformExact"

# 3) Check for isGoogle / isPlatform source code text — these were IN the BuildFlavor
#    const class so they might be preserved as field names somewhere
$markerIsGoogle = [byte[]]@(0x69,0x73,0x47,0x6F,0x6F,0x67,0x6C,0x65)
$markerIsPlatform = [byte[]]@(0x69,0x73,0x50,0x6C,0x61,0x74,0x66,0x6F,0x72,0x6D)
$isGoogleCount = CountExact $raw $markerIsGoogle
$isPlatformCount = CountExact $raw $markerIsPlatform
Write-Host "'isGoogle' substring count: $isGoogleCount"
Write-Host "'isPlatform' substring count: $isPlatformCount"