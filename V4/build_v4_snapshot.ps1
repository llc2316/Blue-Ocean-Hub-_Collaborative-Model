param(
    [switch]$VerifyOnly,
    [string]$SourceRoot=''
)
$ErrorActionPreference='Stop'
$v4Root=Split-Path -Parent $MyInvocation.MyCommand.Path
$manifestDir=Join-Path $v4Root 'manifests'
$packageManifest=Join-Path $manifestDir 'v4_package_manifest.csv'

$exclude='\\(__pycache__|outputs|输出|previews|render|inspection|运行结果|\.git|node_modules|\.uv-cache)(\\|$)'
$packageExclude='\\(manifests|outputs|输出|previews|render|inspection|运行结果|\.git|node_modules|\.uv-cache|__pycache__)(\\|$)'

function Test-PortablePackage {
    if(-not (Test-Path -LiteralPath $packageManifest -PathType Leaf)){
        throw "Missing package manifest relative to V4 root: manifests\v4_package_manifest.csv"
    }
    $expected=@(Import-Csv -LiteralPath $packageManifest)
    if($expected.Count -eq 0){throw 'Package manifest is empty.'}
    $checked=@()
    foreach($row in $expected){
        $target=Join-Path $v4Root $row.RelativePath
        $exists=Test-Path -LiteralPath $target -PathType Leaf
        $hash=if($exists){(Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash}else{''}
        $bytes=if($exists){(Get-Item -LiteralPath $target).Length}else{-1}
        $checked += [pscustomobject]@{
            RelativePath=$row.RelativePath
            Status=if(-not $exists){'MISSING'}elseif($hash -ne $row.SHA256){'HASH_MISMATCH'}elseif([long]$bytes -ne [long]$row.Bytes){'SIZE_MISMATCH'}else{'MATCH'}
        }
    }
    $bad=@($checked|Where-Object Status -ne 'MATCH')
    if($bad.Count -gt 0){$bad|Format-Table -AutoSize;throw "V4 portable-package verification failed: $($bad.Count) file(s)."}
    Write-Host "V4 PORTABLE PACKAGE VERIFIED: $($checked.Count) files; root=$v4Root"
}

if($VerifyOnly){
    Test-PortablePackage
    exit 0
}

if([string]::IsNullOrWhiteSpace($SourceRoot)){
    $projectRoot=Split-Path -Parent $v4Root
}else{
    $projectRoot=(Resolve-Path -LiteralPath $SourceRoot).Path
}
New-Item -ItemType Directory -Force -Path $manifestDir | Out-Null

$mappings=@(
    [pscustomobject]@{Module='4.1';Source='4.1边界与口径';Snapshot='library\4.1边界与口径'},
    [pscustomobject]@{Module='4.2';Source='4.2变量与接口';Snapshot='library\4.2变量与接口'},
    [pscustomobject]@{Module='4.8_4.9_DOC';Source='08_4.8-4.9目标架构.md';Snapshot='modules\4.8_objectives\docs\08_4.8-4.9目标架构.md'},
    [pscustomobject]@{Module='4.4';Source='4.4PowerSubModel\energy_island_model';Snapshot='modules\4.4_bus\reference_model'},
    [pscustomobject]@{Module='4.5';Source='4.5制氢与电池氢储';Snapshot='modules\4.5_storage_hydrogen\reference_model'},
    [pscustomobject]@{Module='4.6_DOC';Source='4.6算力负荷\绿色算力负荷模型(1).md';Snapshot='modules\4.6_compute\docs\绿色算力负荷模型(1).md'},
    [pscustomobject]@{Module='4.6';Source='4.6算力负荷\DC_model_v2_1';Snapshot='modules\4.6_compute\DC_model_v2_1'},
    [pscustomobject]@{Module='4.7_DOC';Source='4.7用能与外送\工程使用说明.md';Snapshot='modules\4.7_outputs\docs\工程使用说明.md'},
    [pscustomobject]@{Module='4.7';Source='4.7用能与外送\submodules';Snapshot='modules\4.7_outputs\delivery_model'}
)
$curatedExclusions=@{
    '4.4'=@('builder.py','fix_imports.py','gen_all.py','report_gen.py','run_model.py')
    '4.6'=@('UDC_data\01_Workload\trace_seren.csv','UDC_data\05_Optional\EQCAM_Dataset.csv','UDC_data\data_stream-oper_stepType-instant.nc')
}

function Get-ScopeFiles([string]$sourcePath,[string]$module){
    if(Test-Path -LiteralPath $sourcePath -PathType Leaf){return ,(Get-Item -LiteralPath $sourcePath)}
    $skip=@();if($curatedExclusions.ContainsKey($module)){$skip=$curatedExclusions[$module]}
    return @(Get-ChildItem -LiteralPath $sourcePath -Recurse -File|Where-Object{
        $relative=$_.FullName.Substring($sourcePath.Length).TrimStart('\')
        $_.FullName -notmatch $exclude -and $relative -notin $skip
    })
}

foreach($map in $mappings){
    $sourcePath=Join-Path $projectRoot $map.Source
    if(-not (Test-Path -LiteralPath $sourcePath)){throw "Missing source scope below SourceRoot: $($map.Source)"}
    foreach($file in Get-ScopeFiles $sourcePath $map.Module){
        if(Test-Path -LiteralPath $sourcePath -PathType Leaf){$tail=Split-Path -Leaf $sourcePath}
        else{$tail=$file.FullName.Substring($sourcePath.Length).TrimStart('\')}
        $targetBase=Join-Path $v4Root $map.Snapshot
        if(Test-Path -LiteralPath $sourcePath -PathType Leaf){$target=Join-Path (Split-Path -Parent $targetBase) $tail}
        else{$target=Join-Path $targetBase $tail}
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target)|Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    }
}

$rows=@()
foreach($map in $mappings){
    $sourcePath=Join-Path $projectRoot $map.Source
    foreach($file in Get-ScopeFiles $sourcePath $map.Module){
        if(Test-Path -LiteralPath $sourcePath -PathType Leaf){$tail=Split-Path -Leaf $sourcePath}
        else{$tail=$file.FullName.Substring($sourcePath.Length).TrimStart('\')}
        $targetBase=Join-Path $v4Root $map.Snapshot
        if(Test-Path -LiteralPath $sourcePath -PathType Leaf){$target=Join-Path (Split-Path -Parent $targetBase) $tail}
        else{$target=Join-Path $targetBase $tail}
        $srcHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
        $dstHash=(Get-FileHash -Algorithm SHA256 -LiteralPath $target).Hash
        $rows += [pscustomobject]@{
            Module=$map.Module
            SourceRelative=$file.FullName.Substring($projectRoot.Length).TrimStart('\')
            SnapshotRelative=$target.Substring($v4Root.Length).TrimStart('\')
            Bytes=$file.Length
            SourceSHA256=$srcHash
            SnapshotSHA256=$dstHash
            Status=if($srcHash -eq $dstHash){'MATCH'}else{'HASH_MISMATCH'}
        }
    }
}
$rows|Sort-Object Module,SourceRelative|Export-Csv -LiteralPath (Join-Path $manifestDir 'v4_snapshot_manifest.csv') -NoTypeInformation -Encoding UTF8
$mappings|Export-Csv -LiteralPath (Join-Path $manifestDir 'v4_snapshot_scope.csv') -NoTypeInformation -Encoding UTF8
$summary=$rows|Group-Object Module|ForEach-Object{
    [pscustomobject]@{Module=$_.Name;Files=$_.Count;Bytes=($_.Group|Measure-Object Bytes -Sum).Sum;Matched=@($_.Group|Where-Object Status -eq 'MATCH').Count;Failed=@($_.Group|Where-Object Status -ne 'MATCH').Count}
}
$summary|Export-Csv -LiteralPath (Join-Path $manifestDir 'v4_snapshot_summary.csv') -NoTypeInformation -Encoding UTF8
$bad=@($rows|Where-Object Status -ne 'MATCH')
if($bad.Count -gt 0){$bad|Format-Table -AutoSize;throw "V4 source-snapshot build failed: $($bad.Count) file(s)."}

$snapshotIndex=@{};foreach($row in $rows){$snapshotIndex[$row.SnapshotRelative]=$true}
$modulesRoot=Join-Path $v4Root 'modules'
$curated=@(Get-ChildItem -LiteralPath $modulesRoot -Recurse -File|Where-Object{$_.FullName -notmatch $exclude}|ForEach-Object{
    $relative=$_.FullName.Substring($v4Root.Length).TrimStart('\')
    [pscustomobject]@{RelativePath=$relative;Bytes=$_.Length;SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash;Origin=if($snapshotIndex.ContainsKey($relative)){'SOURCE_SNAPSHOT'}else{'V4_INTEGRATION_OR_GUIDE'}}
})
$curated|Sort-Object RelativePath|Export-Csv -LiteralPath (Join-Path $manifestDir 'v4_modules_curated_manifest.csv') -NoTypeInformation -Encoding UTF8
$curated|Group-Object{($_.RelativePath -split '\\')[1]}|ForEach-Object{
    [pscustomobject]@{ModuleDirectory=$_.Name;Files=$_.Count;Bytes=($_.Group|Measure-Object Bytes -Sum).Sum;SourceSnapshot=@($_.Group|Where-Object Origin -eq 'SOURCE_SNAPSHOT').Count;V4Owned=@($_.Group|Where-Object Origin -eq 'V4_INTEGRATION_OR_GUIDE').Count}
}|Sort-Object ModuleDirectory|Export-Csv -LiteralPath (Join-Path $manifestDir 'v4_modules_curated_summary.csv') -NoTypeInformation -Encoding UTF8

$package=@(Get-ChildItem -LiteralPath $v4Root -Recurse -File|Where-Object{$_.FullName -notmatch $packageExclude}|ForEach-Object{
    [pscustomobject]@{
        RelativePath=$_.FullName.Substring($v4Root.Length).TrimStart('\')
        Bytes=$_.Length
        SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash
    }
})
$package|Sort-Object RelativePath|Export-Csv -LiteralPath $packageManifest -NoTypeInformation -Encoding UTF8
Write-Host "V4 SOURCE SNAPSHOT BUILT: $($rows.Count) files"
Test-PortablePackage


