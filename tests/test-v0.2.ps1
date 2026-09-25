$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$engine = Join-Path $projectRoot 'ai-quota-activate.ps1'
$fixture = Join-Path $PSScriptRoot 'fixtures\weekly-limit.ps1'
$testRoot = Join-Path $PSScriptRoot '.tmp'
$logDirectory = Join-Path $testRoot 'logs'
$stateDirectory = Join-Path $testRoot 'state'
$counterPath = Join-Path $testRoot 'invocations.txt'

if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$env:AI_QUOTA_TEST_COUNTER = $counterPath

$parameters = @{
    AI                 = 'Codex'
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
    if ($state.status -ne 'WeeklyQuotaExhausted' -or [DateTimeOffset]$state.blockedUntil -le [DateTimeOffset]::Now) {
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

    Write-Host 'PASS: weekly quota cooldown was persisted and the second CLI request was skipped.' -ForegroundColor Green
}
finally {
    Remove-Item Env:AI_QUOTA_TEST_COUNTER -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
