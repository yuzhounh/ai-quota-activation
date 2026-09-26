$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot 'ai-quota-activate.ps1'
$fixture = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'fixtures\weekly-limit.ps1')).Path
$testRoot = Join-Path $PSScriptRoot '.tmp\engine'
$logDirectory = Join-Path $testRoot 'logs'
$stateDirectory = Join-Path $testRoot 'state'
$counterPath = Join-Path $testRoot 'invocations.txt'

Remove-AIQuotaTestDirectory -Path $testRoot
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$env:AI_QUOTA_TEST_COUNTER = $counterPath

$parameters = @{
    AI                 = ' Codex, codex; '
    CodexPath          = $fixture
    LogDirectory       = $logDirectory
    StateDirectory     = $stateDirectory
    NetworkWaitSeconds = 0
    PostWaitSeconds    = 0
    NoSleep            = $true
}

try {
    & $engine @parameters
    $firstExitCode = $LASTEXITCODE
    if ($firstExitCode -ne 1) {
        throw "Expected the quota discovery run to exit 1, got $firstExitCode."
    }

    $statePath = Join-Path $stateDirectory 'codex-weekly-block.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw 'The weekly quota state file was not created.'
    }
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.status -ne 'WeeklyQuotaExhausted' -or
        [DateTimeOffset]$state.blockedUntil -ne [DateTimeOffset]'2099-01-02T05:00:00+08:00') {
        throw 'The weekly quota state file is invalid.'
    }

    & $engine @parameters
    $secondExitCode = $LASTEXITCODE
    if ($secondExitCode -ne 0) {
        throw "Expected the cooldown skip run to exit 0, got $secondExitCode."
    }

    $invocationCount = [int](Get-Content -LiteralPath $counterPath -Raw)
    if ($invocationCount -ne 1) {
        throw "Expected the fake CLI to run once, got $invocationCount invocation(s)."
    }

    $antigravityDryRun = (& $engine `
        -AI Antigravity `
        -AntigravityPath $fixture `
        -LogDirectory $logDirectory `
        -StateDirectory $stateDirectory `
        -DryRun `
        -NoSleep *>&1 | Out-String)
    if ($antigravityDryRun -notmatch '--print=' -or $antigravityDryRun -match '(?m)\s--mode\s') {
        throw 'The Antigravity print-mode arguments are invalid.'
    }

    Write-Host 'PASS: weekly quota cooldown was persisted and the second CLI request was skipped.' -ForegroundColor Green
    Write-Host 'PASS: provider whitespace, duplicate names and trailing delimiters are accepted.' -ForegroundColor Green
    Write-Host 'PASS: Antigravity uses an attached --print prompt without the ineffective --mode flag.' -ForegroundColor Green
}
finally {
    Remove-Item Env:AI_QUOTA_TEST_COUNTER -ErrorAction SilentlyContinue
    Remove-AIQuotaTestDirectory -Path $testRoot
}
