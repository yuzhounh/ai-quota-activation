$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'test-helpers.ps1')

$projectRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $projectRoot 'install-ai-quota-schedule.ps1'
$fixture = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'fixtures\weekly-limit.ps1')).Path
$fixturePaths = @{ CodexPath = $fixture; ClaudePath = $fixture; AntigravityPath = $fixture }
$testRoot = Join-Path $PSScriptRoot '.tmp\installer'
$originalLocalAppData = $env:LOCALAPPDATA
$global:AIQuotaTestRegistrations = [Collections.Generic.List[object]]::new()
$global:AIQuotaTestDisabledTasks = [Collections.Generic.List[string]]::new()
$global:AIQuotaTestExistingTasks = @{}

function New-ScheduledTaskAction {
    param($Execute, $Argument, $WorkingDirectory)
    [pscustomobject]@{ Execute = $Execute; Argument = $Argument; WorkingDirectory = $WorkingDirectory }
}

function New-ScheduledTaskTrigger {
    param([switch]$Daily, [switch]$Weekly, $WeeksInterval, $DaysOfWeek, $At)
    [pscustomobject]@{
        Daily      = $Daily.IsPresent
        Weekly     = $Weekly.IsPresent
        DaysOfWeek = $DaysOfWeek
        At         = $At
    }
}

function New-ScheduledTaskSettingsSet {
    param(
        [switch]$WakeToRun,
        [switch]$StartWhenAvailable,
        [switch]$AllowStartIfOnBatteries,
        [switch]$DontStopIfGoingOnBatteries,
        $MultipleInstances,
        $ExecutionTimeLimit
    )
    [pscustomobject]@{ WakeToRun = $WakeToRun.IsPresent }
}

function Register-ScheduledTask {
    param($TaskName, $Action, $Trigger, $Settings, $Description, $User, $Password, [switch]$Force)
    $global:AIQuotaTestRegistrations.Add([pscustomobject]@{
        TaskName = $TaskName
        Action   = $Action
        Triggers = @($Trigger)
    })
}

function Get-ScheduledTask {
    param($TaskName)
    if ($global:AIQuotaTestExistingTasks.ContainsKey($TaskName)) {
        return $global:AIQuotaTestExistingTasks[$TaskName]
    }
    return $null
}

function Disable-ScheduledTask {
    param($InputObject)
    $global:AIQuotaTestDisabledTasks.Add([string]$InputObject.TaskName)
}

function Get-ScheduledTaskInfo {
    param($TaskName)
    [pscustomobject]@{ LastRunTime = [datetime]::MinValue; NextRunTime = (Get-Date).AddDays(1); LastTaskResult = 0 }
}

function Read-Host {
    param($Prompt, [switch]$AsSecureString)
    ConvertTo-SecureString 'mock-password' -AsPlainText -Force
}

function powercfg {
    param([Parameter(ValueFromRemainingArguments = $true)]$RemainingArguments)
    'MOCK powercfg /waketimers'
}

try {
    Remove-AIQuotaTestDirectory -Path $testRoot
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    $env:LOCALAPPDATA = $testRoot

    & $installer -FiveHourAI Codex,Claude -WeeklyOnlyAI Antigravity @fixturePaths

    if ($global:AIQuotaTestRegistrations.Count -ne 2) {
        throw "Expected two scheduled tasks, got $($global:AIQuotaTestRegistrations.Count)."
    }
    $fiveHourTask = $global:AIQuotaTestRegistrations | Where-Object TaskName -eq 'AI Quota 5h Activation'
    $weeklyTask = $global:AIQuotaTestRegistrations | Where-Object TaskName -eq 'AI Quota Weekly Activation'
    if ($null -eq $fiveHourTask -or $fiveHourTask.Triggers.Count -ne 4 -or
        $fiveHourTask.Action.Argument -notmatch '-AI "Codex,Claude"' -or
        $fiveHourTask.Action.Argument -match '-(?:Codex|Claude|Antigravity)Model') {
        throw 'The five-hour task definition is invalid.'
    }
    if ($null -eq $weeklyTask -or $weeklyTask.Triggers.Count -ne 1 -or -not $weeklyTask.Triggers[0].Weekly -or
        $weeklyTask.Action.Argument -notmatch '-AI "Antigravity"' -or
        $weeklyTask.Action.Argument -match '-(?:Codex|Claude|Antigravity)Model') {
        throw 'The weekly-only task definition is invalid.'
    }

    $global:AIQuotaTestRegistrations.Clear()
    & $installer @fixturePaths
    if ($global:AIQuotaTestRegistrations.Count -ne 2) {
        throw "Expected two scheduled tasks by default, got $($global:AIQuotaTestRegistrations.Count)."
    }
    $defaultFiveHour = $global:AIQuotaTestRegistrations | Where-Object TaskName -eq 'AI Quota 5h Activation'
    $defaultWeekly = $global:AIQuotaTestRegistrations | Where-Object TaskName -eq 'AI Quota Weekly Activation'
    if ($null -eq $defaultFiveHour -or $defaultFiveHour.Action.Argument -notmatch '-AI "Claude,Antigravity"') {
        throw 'Default five-hour task must activate Claude,Antigravity.'
    }
    if ($null -eq $defaultWeekly -or $defaultWeekly.Action.Argument -notmatch '-AI "Codex"') {
        throw 'Default weekly task must activate Codex.'
    }

    $global:AIQuotaTestRegistrations.Clear()
    $global:AIQuotaTestExistingTasks['AI Quota Weekly Activation'] = [pscustomobject]@{
        TaskName = 'AI Quota Weekly Activation'
        State    = 'Ready'
    }
    & $installer -FiveHourAI Codex -WeeklyOnlyAI '' @fixturePaths
    if ($global:AIQuotaTestRegistrations.Count -ne 1 -or
        $global:AIQuotaTestDisabledTasks -notcontains 'AI Quota Weekly Activation') {
        throw 'An obsolete weekly task was not disabled when only five-hour activation was selected.'
    }

    $global:AIQuotaTestRegistrations.Clear()
    Push-Location -LiteralPath $projectRoot
    try {
        & $installer -CodexPath '.\tests\fixtures\weekly-limit.ps1' `
            -ClaudePath '.\tests\fixtures\weekly-limit.ps1' `
            -AntigravityPath '.\tests\fixtures\weekly-limit.ps1'
    }
    finally {
        Pop-Location
    }
    if ($global:AIQuotaTestRegistrations.Count -ne 2) {
        throw 'Expected two tasks for the relative CLI path test.'
    }
    foreach ($task in $global:AIQuotaTestRegistrations) {
        foreach ($provider in @('Codex', 'Claude', 'Antigravity')) {
            if (-not $task.Action.Argument.Contains("-$($provider)Path `"$fixture`"")) {
                throw "The $provider CLI path was not persisted as an absolute path."
            }
        }
    }

    Write-Host 'PASS: mutually exclusive task definitions were registered and an obsolete weekly task was disabled.' -ForegroundColor Green
    Write-Host 'PASS: relative CLI paths are stored as absolute paths for the task working directory.' -ForegroundColor Green
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    Remove-Variable -Name AIQuotaTestRegistrations -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name AIQuotaTestDisabledTasks -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name AIQuotaTestExistingTasks -Scope Global -ErrorAction SilentlyContinue
    Remove-AIQuotaTestDirectory -Path $testRoot
}
