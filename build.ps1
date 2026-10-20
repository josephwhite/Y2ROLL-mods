<#
    .SYNOPSIS
    Simple packager for Y2ROLL mods.
    .DESCRIPTION
    Packages each Y2ROLL mod, the patcher script, and license into a single zip archive for GitHub Releases.
#>

[CmdletBinding()]
param()

$dest_folder = [System.IO.Path]::Combine($PSScriptRoot, "dist")
if (!(Test-Path -Path $dest_folder)) {
    Write-Debug -Message "Creating distribution folder: $dest_folder"
    New-Item $dest_folder -ItemType Directory
}

$dist_files = @()
# Mods
$dist_files += Get-Item -Path $([System.IO.Path]::Combine($PSScriptRoot, "josephwhite-ArchipelagoRandomizer"))
$dist_files += Get-Item -Path $([System.IO.Path]::Combine($PSScriptRoot, "josephwhite-mod_manager"))
$dist_files += Get-Item -Path $([System.IO.Path]::Combine($PSScriptRoot, "josephwhite-player_skins"))
# Scripts
$dist_files += Get-Item -Path $([System.IO.Path]::Combine($PSScriptRoot, "patch_pck.py"))
$dist_files += Get-Item -Path $([System.IO.Path]::Combine($PSScriptRoot, "LICENSE.md"))
# Etc.
$dest_output = [System.IO.Path]::Combine($dest_folder, "Y2ROLL-mods.zip")

$dist_files | Compress-Archive -DestinationPath $dest_output -CompressionLevel "Optimal" -Update
Write-Debug -Message "Mods packaged: $dest_output"

exit 0
