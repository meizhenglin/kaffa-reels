try {
  $r = Invoke-WebRequest -Uri 'https://tvapi.qahwatv.com/v3/api-docs' -UseBasicParsing -TimeoutSec 40
  $r.Content | Out-File -FilePath 'C:\Users\admin\arab_drama_app\api-docs.json' -Encoding utf8
  Write-Output ('saved bytes: ' + $r.Content.Length)
} catch {
  Write-Output ('ERR ' + $_.Exception.Message)
}
