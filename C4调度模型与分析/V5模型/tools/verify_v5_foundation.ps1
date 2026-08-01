param(
    [string]$V5Root = ""
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($V5Root)) {
    $V5Root = Split-Path -Parent $toolRoot
}
$V5Root = [System.IO.Path]::GetFullPath($V5Root)
$manifestPath = Join-Path $V5Root "manifests\v5_foundation_manifest.csv"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "Missing V5 foundation manifest: $manifestPath"
}

$rows = Import-Csv -LiteralPath $manifestPath
$errors = [System.Collections.Generic.List[object]]::new()
foreach ($row in $rows) {
    $path = Join-Path $V5Root $row.V5RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $errors.Add([pscustomobject]@{Path=$row.V5RelativePath;Status="MISSING"})
        continue
    }
    $item = Get-Item -LiteralPath $path
    if ([long]$row.Bytes -ne $item.Length) {
        $errors.Add([pscustomobject]@{Path=$row.V5RelativePath;Status="SIZE_MISMATCH"})
        continue
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $row.SHA256.ToLowerInvariant()) {
        $errors.Add([pscustomobject]@{Path=$row.V5RelativePath;Status="HASH_MISMATCH"})
    }
}

if ($errors.Count -gt 0) {
    $errors | Format-Table -AutoSize
    throw "V5 foundation verification failed: $($errors.Count) file(s)."
}
Write-Host "V5 FOUNDATION VERIFICATION: PASSED ($($rows.Count) files)"
