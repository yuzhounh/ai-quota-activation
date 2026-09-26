function Remove-AIQuotaTestDirectory {
    param([Parameter(Mandatory)][string]$Path)

    $allowedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '.tmp'))
    $allowedPrefix = $allowedRoot + [IO.Path]::DirectorySeparatorChar
    $targetPath = [IO.Path]::GetFullPath($Path)
    if (-not $targetPath.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a directory outside tests/.tmp: $targetPath"
    }
    if (Test-Path -LiteralPath $targetPath) {
        $targetPath = (Resolve-Path -LiteralPath $targetPath).Path
        if (-not $targetPath.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Resolved test directory is outside tests/.tmp: $targetPath"
        }
        foreach ($directory in @($allowedRoot, $targetPath)) {
            if ((Get-Item -LiteralPath $directory).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Refusing to remove a linked test directory: $directory"
            }
        }
        Remove-Item -LiteralPath $targetPath -Recurse -Force
    }
}
