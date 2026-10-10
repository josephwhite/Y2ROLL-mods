<#
    .SYNOPSIS
    patch_pck.py PowerShell wrapper
#>
param(
    [string]$Pck,
    [string]$ModloaderDir,
    [string]$GameDir
)

$scriptDir = $PSScriptRoot
$patchScript = Join-Path $scriptDir "patch_pck.py"

$my_args = @()
if ($Pck) {
    $my_args += "--pck"; $my_args += $Pck 
}
if ($ModloaderDir) {
    $my_args += "--modloader-dir"; $my_args += $ModloaderDir 
}
if ($GameDir) {
    $my_args += "--game-dir"; $my_args += $GameDir 
}

& python $patchScript --restore @my_args
& python $patchScript @my_args

exit $LASTEXITCODE
