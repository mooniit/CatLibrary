$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
$config = (& .tooling/supabase-cli/node_modules/.bin/supabase.cmd status -o json 2>$null | Out-String | ConvertFrom-Json)
$base = $config.API_URL
$public = @{ apikey=$config.ANON_KEY }
$a=Invoke-RestMethod "$base/auth/v1/signup" -Method Post -Headers $public -ContentType 'application/json' -Body '{}'
$b=Invoke-RestMethod "$base/auth/v1/signup" -Method Post -Headers $public -ContentType 'application/json' -Body '{}'
if ($a.user.id -eq $b.user.id) { throw 'Independent sessions received the same identity' }
$ha=@{apikey=$config.ANON_KEY; Authorization="Bearer $($a.access_token)"}
$hb=@{apikey=$config.ANON_KEY; Authorization="Bearer $($b.access_token)"}
$body=@{owner_id=$a.user.id; note='M0 local HTTP probe'} | ConvertTo-Json
Invoke-RestMethod "$base/rest/v1/m0_probe_notes" -Method Post -Headers $ha -ContentType 'application/json' -Body $body | Out-Null
$own=Invoke-RestMethod "$base/rest/v1/m0_probe_notes?select=*" -Headers $ha
$other=Invoke-RestMethod "$base/rest/v1/m0_probe_notes?select=*" -Headers $hb
if (@($own).Count -ne 1 -or @($other).Count -ne 0) { throw 'Row isolation failed' }
function Assert-Denied([scriptblock]$Action) {
  try { & $Action | Out-Null } catch {
    $status=[int]$_.Exception.Response.StatusCode
    if ($status -in @(400,401,403,404)) { return }
    throw
  }
  throw 'Unauthorized request unexpectedly succeeded'
}
Assert-Denied { Invoke-RestMethod "$base/rest/v1/m0_probe_notes" -Method Post -Headers $hb -ContentType 'application/json' -Body $body }
$bytes=[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
$object="m0-probe-private/$($a.user.id)/probe.png"
Invoke-RestMethod "$base/storage/v1/object/$object" -Method Post -Headers $ha -ContentType 'image/png' -Body $bytes | Out-Null
$response=Invoke-WebRequest "$base/storage/v1/object/authenticated/$object" -Headers $ha
if ([Convert]::ToBase64String($response.Content) -ne [Convert]::ToBase64String($bytes)) { throw 'Image roundtrip mismatch' }
Assert-Denied { Invoke-WebRequest "$base/storage/v1/object/authenticated/$object" -Headers $hb }
Assert-Denied { Invoke-WebRequest "$base/storage/v1/object/public/$object" -Headers $public }
[PSCustomObject]@{environment='local Docker Supabase'; time=(Get-Date).ToString('o'); checks=7; result='PASS'; scope='two independent HTTP sessions, own read/write, forged owner rejected, private PNG roundtrip, other-user and public download denied; NOT mobile devices or cloud'} | ConvertTo-Json
