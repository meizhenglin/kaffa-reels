$f = "build\apk_contents\classes.dex"
$b = [IO.File]::ReadAllBytes($f)
$t = [Text.Encoding]::ASCII.GetString($b)
Write-Output "registrant: $($t.Contains('registrant'))"
Write-Output "SharedPreferencesApi: $($t.Contains('SharedPreferencesApi'))"
Write-Output "flutter_secure: $($t.Contains('flutter_secure'))"
