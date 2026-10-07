param([string]$DefinesFile = '.tooling/local-phone-defines.json')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
if (-not (Test-Path -LiteralPath $DefinesFile)) {
  throw "Missing phone configuration: $DefinesFile. Refusing to build a preview-only APK."
}
& node (Join-Path $PSScriptRoot 'cloud-config.cjs') $DefinesFile
if ($LASTEXITCODE -ne 0) { throw 'Phone configuration validation failed; no APK was built.' }
$phoneConfig = Get-Content -LiteralPath $DefinesFile -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($phoneConfig.SUPABASE_URL) -or
    [string]::IsNullOrWhiteSpace($phoneConfig.SUPABASE_ANON_KEY)) {
  throw 'Phone configuration must contain SUPABASE_URL and SUPABASE_ANON_KEY.'
}
$env:ANDROID_HOME = Join-Path $projectRoot '.tooling/android-sdk'
$env:GRADLE_USER_HOME = Join-Path $projectRoot '.tooling/gradle-cache'
$env:PUB_CACHE = Join-Path $projectRoot '.tooling/pub-cache'
$flutterSdk = Join-Path $projectRoot '.tooling/flutter'
& "$flutterSdk/bin/cache/dart-sdk/bin/dart.exe" "$flutterSdk/bin/cache/flutter_tools.snapshot" --no-version-check build apk --debug --target-platform android-arm64,android-x64 --no-pub "--dart-define-from-file=$DefinesFile"
if ($LASTEXITCODE -ne 0) { throw "APK build failed: $LASTEXITCODE" }
Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-debug.apk' -Destination 'build/app/outputs/flutter-apk/catlibrary-lunar-native-debug.apk' -Force
