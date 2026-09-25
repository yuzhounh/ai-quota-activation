[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(ValueFromPipeline = $true)]
    [AllowNull()]
    [object]$InputObject,

    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

if ($env:AI_QUOTA_TEST_COUNTER) {
    $count = 0
    if (Test-Path -LiteralPath $env:AI_QUOTA_TEST_COUNTER -PathType Leaf) {
        $count = [int](Get-Content -LiteralPath $env:AI_QUOTA_TEST_COUNTER -Raw)
    }
    [IO.File]::WriteAllText($env:AI_QUOTA_TEST_COUNTER, [string]($count + 1))
}

Write-Output 'Weekly quota exhausted. Usage resets at 2099-01-02T05:00:00+08:00.'
exit 17
