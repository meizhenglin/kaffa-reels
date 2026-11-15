param(
  [string]$WsUrl = 'ws://127.0.0.1:44456/96LMgEODJTU=/ws',
  [string]$OutFile = "$env:TEMP\web_console_log.txt",
  [int]$DurationSec = 900
)

Add-Type -TypeDefinition @'
using System;
using System.Net.WebSockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public static class CdpClient2 {
  public static async Task SendAsync(ClientWebSocket ws, string msg) {
    var bytes = Encoding.UTF8.GetBytes(msg);
    await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, CancellationToken.None);
  }

  public static async Task<string> RecvAsync(ClientWebSocket ws) {
    var buf = new byte[1024 * 512];
    var sb = new StringBuilder();
    while (true) {
      var result = await ws.ReceiveAsync(new ArraySegment<byte>(buf), CancellationToken.None);
      if (result.MessageType == WebSocketMessageType.Close) return null;
      sb.Append(Encoding.UTF8.GetString(buf, 0, result.Count));
      if (result.EndOfMessage) return sb.ToString();
    }
  }
}
'@

$ws = New-Object System.Net.WebSockets.ClientWebSocket
$ws.ConnectAsync([Uri]$WsUrl, [CancellationToken]::None).Wait(10000)
if ($ws.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
  "CONNECT FAILED state=$($ws.State)" | Out-File $OutFile -Encoding utf8; exit 1
}
"C $(Get-Date -Format 'HH:mm:ss') connected to VM service" | Out-File $OutFile -Encoding utf8

[CdpClient2]::SendAsync($ws, '{"jsonrpc":"2.0","id":1,"method":"streamListen","params":{"streamId":"Stdout"}}').Wait(5000) | Out-Null
[CdpClient2]::SendAsync($ws, '{"jsonrpc":"2.0","id":2,"method":"streamListen","params":{"streamId":"Log"}}').Wait(5000) | Out-Null

$deadline = (Get-Date).AddSeconds($DurationSec)
while ((Get-Date) -lt $deadline) {
  $task = [CdpClient2]::RecvAsync($ws)
  if (-not $task.Wait(1000)) { continue }
  $msg = $task.Result
  if ($null -eq $msg) { break }
  try {
    $json = $msg | ConvertFrom-Json
    $ts = Get-Date -Format 'HH:mm:ss'
    if ($json.event -eq 'stdout' -or $json.event -eq 'stderr') {
      $bytes = [Convert]::FromBase64String($json.params.bytes)
      $text = [Text.Encoding]::UTF8.GetString($bytes)
      "$ts $text" | Out-File $OutFile -Append -Encoding utf8
    } elseif ($json.event -eq 'Log') {
      $rec = $json.params.logRecord
      "$ts [Log:$($json.params.kind)] $rec.message" | Out-File $OutFile -Append -Encoding utf8
    }
  } catch {}
}
$ws.Dispose()
