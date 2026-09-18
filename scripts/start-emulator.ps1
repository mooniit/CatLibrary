param([switch]$Headless)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$env:ANDROID_HOME = Join-Path $projectRoot '.tooling/android-sdk'
$env:ANDROID_AVD_HOME = Join-Path $projectRoot '.tooling/avd'
$emulator = Join-Path $env:ANDROID_HOME 'emulator/emulator.exe'
$adb = Join-Path $env:ANDROID_HOME 'platform-tools/adb.exe'
if (!(Test-Path $emulator) -or !(Test-Path $adb)) {
    throw 'Android SDK emulator/platform-tools are missing. See docs/Android模拟器.md.'
}
foreach ($line in (& $adb devices)) {
    if ($line -match '^(emulator-\d+)\s+device') {
        $deviceId = $Matches[1]
        $avdName = & $adb -s $deviceId emu avd name
        if ($avdName -contains 'catlibrary_m0') {
            Write-Output "catlibrary_m0 is already running: $deviceId"
            return
        }
    }
}
if (!((& $emulator -list-avds) -contains 'catlibrary_m0')) {
    throw 'catlibrary_m0 AVD is missing. See docs/Android模拟器.md.'
}
& $emulator -accel-check
if ($LASTEXITCODE -ne 0) { throw 'Android emulator hardware acceleration is unavailable.' }
$launchArgs = @('-avd', 'catlibrary_m0', '-memory', '1536', '-cores', '2',
    '-gpu', 'software', '-no-audio', '-no-boot-anim', '-no-snapshot')
if ($Headless) { $launchArgs += '-no-window' }
$processOptions = @{
    FilePath = $emulator
    ArgumentList = $launchArgs
    RedirectStandardOutput = Join-Path $projectRoot '.tooling/emulator-run.log'
    RedirectStandardError = Join-Path $projectRoot '.tooling/emulator-error.log'
    PassThru = $true
}
if ($Headless) { $processOptions.WindowStyle = 'Hidden' }
$launched = Start-Process @processOptions
Write-Output "Started catlibrary_m0 (launcher PID $($launched.Id)). Check readiness with:"
Write-Output "& '$adb' devices -l"
Write-Output 'Once online, use adb -s <device-id> shell getprop sys.boot_completed; 1 means boot completed.'
