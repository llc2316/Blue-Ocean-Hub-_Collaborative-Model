param(
    [string]$SourceRoot = "",
    [string]$DestinationRoot = ""
)

$ErrorActionPreference = "Stop"
$toolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$v5Root = Split-Path -Parent $toolRoot
$workspaceRoot = [System.IO.Path]::GetFullPath((Split-Path -Parent $v5Root))
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $candidates = Get-ChildItem -LiteralPath $workspaceRoot -Directory |
        Where-Object {
            $_.Name.StartsWith("V4") -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "modules"))
        }
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one V4 directory under $workspaceRoot."
    }
    $SourceRoot = $candidates[0].FullName
}
if ([string]::IsNullOrWhiteSpace($DestinationRoot)) {
    $DestinationRoot = Join-Path $v5Root "foundation"
}
$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)
$DestinationRoot = [System.IO.Path]::GetFullPath($DestinationRoot)

if (-not $SourceRoot.StartsWith($workspaceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "SourceRoot must stay inside the C4 workspace: $SourceRoot"
}
if (-not $DestinationRoot.StartsWith($v5Root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "DestinationRoot must stay inside V5模型: $DestinationRoot"
}
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "Missing V4 source root: $SourceRoot"
}

$libraryRoot = Join-Path $SourceRoot "library"
$boundaryDirectory = Get-ChildItem -LiteralPath $libraryRoot -Directory |
    Where-Object { $_.Name.StartsWith("4.1") }
$interfaceDirectory = Get-ChildItem -LiteralPath $libraryRoot -Directory |
    Where-Object { $_.Name.StartsWith("4.2") }
if (@($boundaryDirectory).Count -ne 1 -or @($interfaceDirectory).Count -ne 1) {
    throw "Could not uniquely resolve V4 4.1 and 4.2 library directories."
}
$copyDirectories = @(
    $boundaryDirectory.FullName,
    $interfaceDirectory.FullName,
    (Join-Path $SourceRoot "modules\4.3_source"),
    (Join-Path $SourceRoot "modules\4.4_bus"),
    (Join-Path $SourceRoot "modules\4.5_storage_hydrogen"),
    (Join-Path $SourceRoot "modules\4.6_compute"),
    (Join-Path $SourceRoot "modules\4.7_outputs"),
    (Join-Path $SourceRoot "modules\4.8_objectives"),
    (Join-Path $SourceRoot "integration\common")
)
$excludedDirectories = @(
    "outputs", "previews", "__pycache__", "node_modules", "inspection", "logs"
)
$excludedExtensions = @(".pyc")

$records = [System.Collections.Generic.List[object]]::new()
foreach ($sourceDirectory in $copyDirectories) {
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Missing required V4 component: $sourceDirectory"
    }
    $relativeRoot = $sourceDirectory.Substring($SourceRoot.Length).TrimStart("\")
    $files = Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File
    foreach ($file in $files) {
        $relativeFromComponent = $file.FullName.Substring($sourceDirectory.Length).TrimStart("\")
        $segments = $relativeFromComponent -split "\\"
        if (@($segments | Where-Object { $excludedDirectories -contains $_ }).Count -gt 0) {
            continue
        }
        if ($excludedExtensions -contains $file.Extension.ToLowerInvariant()) {
            continue
        }
        $destinationFile = Join-Path (Join-Path $DestinationRoot $relativeRoot) $relativeFromComponent
        $destinationDirectory = Split-Path -Parent $destinationFile
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $destinationFile -Force
        $hash = (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $sourceRelative = $file.FullName.Substring($SourceRoot.Length).TrimStart("\")
        $v5Relative = $destinationFile.Substring($v5Root.Length).TrimStart("\")
        $records.Add([pscustomobject]@{
            SourceRelativePath = $sourceRelative
            V5RelativePath = $v5Relative
            Bytes = $file.Length
            SHA256 = $hash
            MigrationStatus = "COPIED_V4_FOUNDATION_NO_V4_4_9"
        })
    }
}

$dataSourceRoot = Join-Path $workspaceRoot "somedata"
$dataDestinationRoot = Join-Path $v5Root "somedata"
$dataFiles = @(
    "nasa_power_hourly_gd_offshore_20250601_20250607.csv",
    "nasa_power_hourly_gd_offshore_20250601_20250607_utc.csv",
    "open_meteo_marine_gd_offshore_20250601_20250607.csv",
    "public_data_manifest.csv",
    "public_reference_parameters.yaml",
    "README.md"
)
foreach ($name in $dataFiles) {
    $sourceFile = Join-Path $dataSourceRoot $name
    if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) {
        throw "Missing required public-resource file: $sourceFile"
    }
    New-Item -ItemType Directory -Path $dataDestinationRoot -Force | Out-Null
    $destinationFile = Join-Path $dataDestinationRoot $name
    Copy-Item -LiteralPath $sourceFile -Destination $destinationFile -Force
    $hash = (Get-FileHash -LiteralPath $destinationFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $records.Add([pscustomobject]@{
        SourceRelativePath = "somedata\$name"
        V5RelativePath = $destinationFile.Substring($v5Root.Length).TrimStart("\")
        Bytes = (Get-Item -LiteralPath $destinationFile).Length
        SHA256 = $hash
        MigrationStatus = "COPIED_PUBLIC_RESOURCE_PROXY"
    })
}

$manifestDirectory = Join-Path $v5Root "manifests"
New-Item -ItemType Directory -Path $manifestDirectory -Force | Out-Null
$manifestPath = Join-Path $manifestDirectory "v5_foundation_manifest.csv"
$records |
    Sort-Object V5RelativePath |
    Export-Csv -LiteralPath $manifestPath -NoTypeInformation -Encoding UTF8

Write-Host "V5 foundation synchronization completed."
Write-Host "Source: $SourceRoot"
Write-Host "Destination: $DestinationRoot"
Write-Host "Copied files: $($records.Count)"
Write-Host "Manifest: $manifestPath"
