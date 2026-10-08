param([Parameter(Mandatory = $true)][ValidatePattern('^[a-z]{20}$')][string]$ProjectRef)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location -LiteralPath $projectRoot
$configFile = Join-Path $projectRoot '.tooling/cloud-phone-defines.json'
$cli = Join-Path $projectRoot '.tooling/supabase-cli/node_modules/@supabase/cli-windows-x64/bin/supabase.exe'
if (!(Test-Path -LiteralPath $cli)) { throw 'Bundled Supabase CLI is missing.' }
& node (Join-Path $PSScriptRoot 'cloud-config.cjs') $configFile --remote
if ($LASTEXITCODE -ne 0) { throw 'Public cloud configuration is invalid.' }
$config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
if (([uri]$config.SUPABASE_URL).Host -ne "$ProjectRef.supabase.co") {
    throw 'Requested project does not match the configured cloud endpoint.'
}
function Write-CloudStage([string]$Stage, [string]$Status, [int]$ExitCode = 0) {
    @{
        updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
        projectRef = $ProjectRef
        stage = $Stage
        status = $Status
        exitCode = $ExitCode
        migrationsApplied = $false
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot '.tooling/cloud-connect-status.json') -Encoding utf8
}
Write-CloudStage 'login' 'waiting'
Write-Host 'Login in your own browser. Enter its verification code only in this terminal, not in chat.'
& $cli --agent no --output-format text login
if ($LASTEXITCODE -ne 0) {
    Write-CloudStage 'login' 'failed' $LASTEXITCODE
    throw 'CLI login did not complete. No migrations were applied.'
}
Write-CloudStage 'login' 'completed'
Write-Host 'Linking the specified project. If asked for the database password, enter it only in this terminal.'
Write-CloudStage 'link' 'waiting'
& $cli --agent no --output-format text link --project-ref $ProjectRef
if ($LASTEXITCODE -ne 0) {
    Write-CloudStage 'link' 'failed' $LASTEXITCODE
    throw 'Project link did not complete. No migrations were applied.'
}
Write-CloudStage 'link' 'completed'
$stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$reportFile = Join-Path $projectRoot ".tooling/cloud-link-dry-run-$stamp.txt"
Write-CloudStage 'dry-run' 'running'
& $cli --agent no --output-format text db push --linked --skip-vault --dry-run 2>&1 | Tee-Object -FilePath $reportFile
if ($LASTEXITCODE -ne 0) {
    Write-CloudStage 'dry-run' 'failed' $LASTEXITCODE
    throw 'Migration dry run failed. No migrations were applied.'
}
Write-CloudStage 'dry-run' 'completed'
@{
    completedAt = [DateTimeOffset]::UtcNow.ToString('o')
    projectRef = $ProjectRef
    dryRunReport = $reportFile
    migrationsApplied = $false
    seedImported = $false
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $projectRoot '.tooling/cloud-link-ready.json') -Encoding utf8
Write-Host 'Login, link and dry run completed. Return to the chat; deployment has not run yet.'
