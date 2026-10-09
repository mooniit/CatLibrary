param(
  [Parameter(Mandatory = $true)][string]$Serial,
  [string]$DefinesFile = '.tooling/local-phone-defines.json',
  [switch]$Physical
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
if ($Serial -notmatch '^[a-zA-Z0-9._:-]+$') { throw 'Invalid ADB serial.' }
if ($Physical) {
  if ($Serial -match '^emulator-') { throw 'Physical requires a real device.' }
} elseif ($Serial -notmatch '^emulator-\d+$') {
  throw 'For a physical phone, specify -Physical explicitly.'
}
& node (Join-Path $PSScriptRoot 'cloud-config.cjs') $DefinesFile | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Configuration validation failed.' }
$localConfig = Get-Content -LiteralPath $DefinesFile -Raw | ConvertFrom-Json
$endpoint = [Uri]$localConfig.SUPABASE_URL
if ($endpoint.Scheme -ne 'http' -or $endpoint.Host -notin @('127.0.0.1', 'localhost')) {
  throw 'This helper only connects loopback HTTP development services; do not use it for cloud configuration.'
}
$adb = Join-Path $projectRoot '.tooling/android-sdk/platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw 'Project ADB is unavailable.' }
$deviceState = & $adb -s $Serial get-state 2>$null
if ($LASTEXITCODE -ne 0 -or $deviceState -ne 'device') {
  throw 'The specified device is absent or USB debugging is not authorized.'
}
# Check the existing service before altering the selected device's mapping.
$health = Invoke-WebRequest -Uri ($endpoint.GetLeftPart([UriPartial]::Authority) + '/auth/v1/health') -UseBasicParsing -TimeoutSec 5
if ($health.StatusCode -ne 200) { throw 'Local authentication service is not healthy.' }
$portMapping = 'tcp:' + $endpoint.Port
& $adb -s $Serial reverse $portMapping $portMapping
if ($LASTEXITCODE -ne 0) { throw 'ADB reverse failed.' }
$mappings = & $adb -s $Serial reverse --list
if ($LASTEXITCODE -ne 0 -or -not ($mappings | Where-Object {
  $_ -match ('\s' + [Regex]::Escape($portMapping) + '\s+' + [Regex]::Escape($portMapping) + '$')
})) { throw 'ADB reverse mapping was not verified.' }
Write-Output "Connected $Serial to the existing local service on port $($endpoint.Port)."
Write-Output 'In the app, open Settings and tap Reconnect. No installation, identity creation, settlement or data clearing was performed.'
Write-Output 'This is a USB/emulator development connection; it does not enable Internet access away from the computer.'
