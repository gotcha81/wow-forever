<#
.SYNOPSIS
    Copies one addon folder from this repo into the local WoW Forever AddOns folder.

.DESCRIPTION
    The game path is read from tools/deploy.local.json, which is git-ignored and
    must never be committed. Copy tools/deploy.example.json to deploy.local.json
    and edit the path to set it up on a new machine.

    The target addon folder is mirrored: files removed from the repo are removed
    from the game copy too. Only <AddOns>\<AddonName> is touched. SavedVariables
    live under WTF\ and are never affected.

.EXAMPLE
    .\tools\deploy.ps1 -Addon ForeverQuestLineNavigator
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Addon
)

$ErrorActionPreference = 'Stop'

$repoRoot   = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $PSScriptRoot 'deploy.local.json'

if (-not (Test-Path $configPath)) {
    throw "Missing tools\deploy.local.json. Copy tools\deploy.example.json to tools\deploy.local.json and set gamePath."
}

# Only plain folder names, no paths: prevents deploying outside AddOns.
if ($Addon -notmatch '^[A-Za-z0-9_]+$') {
    throw "Addon name must be a plain folder name (letters, digits, underscore)."
}

$source = Join-Path $repoRoot $Addon
if (-not (Test-Path (Join-Path $source "$Addon.toc")) -and
    -not (Get-ChildItem -Path $source -Filter "${Addon}_*.toc" -ErrorAction SilentlyContinue)) {
    throw "No $Addon.toc (or ${Addon}_<flavor>.toc) found in repo folder '$Addon'."
}

$config   = Get-Content $configPath -Raw | ConvertFrom-Json
$addOns   = Join-Path $config.gamePath 'Interface\AddOns'
if (-not (Test-Path $addOns)) {
    throw "AddOns folder not found. Check gamePath in tools\deploy.local.json."
}
$target = Join-Path $addOns $Addon

# /MIR mirrors the single addon folder; /XD .git excludes stray git metadata.
robocopy $source $target /MIR /XD .git /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy failed with exit code $LASTEXITCODE." }

# Print only the addon name, never the full local path.
Write-Host "Deployed '$Addon' to the game AddOns folder. Type /reload in game to load changes."
