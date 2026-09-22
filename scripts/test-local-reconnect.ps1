$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$config = (& .tooling/supabase-cli/node_modules/.bin/supabase.cmd status -o json 2>$null | Out-String | ConvertFrom-Json)
$base = $config.API_URL
if ($base -ne 'http://127.0.0.1:54321') { throw 'This probe only supports the project local backend.' }
$gateway = 'supabase_kong_CatLibrary'
if ((docker inspect --format '{{.State.Running}}' $gateway) -ne 'true') { throw 'Local gateway is not running' }
$session = Invoke-RestMethod "$base/auth/v1/signup" -Method Post -Headers @{apikey=$config.ANON_KEY} -ContentType 'application/json' -Body '{}'
$headers = @{apikey=$config.ANON_KEY; Authorization="Bearer $($session.access_token)"}
$marker = [guid]::NewGuid().ToString()
$body = @{owner_id=$session.user.id; note=$marker} | ConvertTo-Json
Invoke-RestMethod "$base/rest/v1/m0_probe_notes" -Method Post -Headers $headers -ContentType 'application/json' -Body $body | Out-Null
try {
    docker stop --time 2 $gateway | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Cannot stop local gateway'}
    $failed = $false
    try {Invoke-RestMethod "$base/rest/v1/m0_probe_notes?select=*" -Headers $headers -TimeoutSec 3 | Out-Null} catch {$failed=$true}
    if (!$failed) {throw 'Request unexpectedly succeeded while gateway was stopped'}
} finally {
    docker start $gateway | Out-Null
    if ($LASTEXITCODE -ne 0) {throw 'Cannot restart local gateway'}
}
$ready = $false
for ($attempt=0; $attempt -lt 20; $attempt++) {
    try {
        $user = Invoke-RestMethod "$base/auth/v1/user" -Headers $headers -TimeoutSec 3
        $ready = $true
        break
    } catch {Start-Sleep -Seconds 1}
}
if (!$ready) {throw 'Gateway did not recover in the bounded retry window'}
if ($user.id -ne $session.user.id) {throw 'Identity changed on recovery'}
$rows = @(Invoke-RestMethod "$base/rest/v1/m0_probe_notes?select=*" -Headers $headers -TimeoutSec 3)
if ($rows.Count -ne 1 -or $rows[0].note -ne $marker) {throw 'Durable row changed during gateway outage'}
$evidence = @{time=(Get-Date).ToString('o'); result='PASS'; checks=3; scope='Local Docker gateway stopped/restarted; HTTP failure observed, same session identity and row recovered; NOT free cloud suspension, mobile reconnect, token expiry or reward settlement'}
$evidence | ConvertTo-Json | Set-Content docs/evidence/m0-local-reconnect.json -Encoding utf8
$evidence | ConvertTo-Json
