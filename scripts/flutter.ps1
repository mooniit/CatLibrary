$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sdk = Join-Path $projectRoot '.tooling/flutter'
$env:ANDROID_HOME = Join-Path $projectRoot '.tooling/android-sdk'
$env:GRADLE_USER_HOME = Join-Path $projectRoot '.tooling/gradle-cache'
$env:PUB_CACHE = Join-Path $projectRoot '.tooling/pub-cache'
$env:Path = "$sdk/bin;$env:ANDROID_HOME/platform-tools;$env:Path"
& "$sdk/bin/flutter.bat" @args
exit $LASTEXITCODE
