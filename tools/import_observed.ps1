# tools\import_observed.ps1 — Verse la recolte en jeu (COCScout + formateurs COC) de TOUS les
# comptes du client dans tools\Curated\observed_<Saveur>.lua, que gen_origins.lua relit a chaque
# passe.
#
# POURQUOI tous les comptes : les SavedVariables sont PAR COMPTE, et le banc de test en a deux. Un
# import qui n'en lirait qu'un perdrait en silence ce que l'autre a vu.
#
# A lancer AVANT gen_origins.lua, idealement apres chaque session de jeu : une SavedVariable
# s'efface a la reinstallation, le fichier cure est commite.
#
# Usage (cwd = f:\AddonDevellopement\CraftLink) :
#   .\tools\import_observed.ps1                          # Camelot, client _classic_beta_
#   .\tools\import_observed.ps1 -WowRoot "E:\WoW\_classic_beta_"

param(
    [string] $Flavor  = "Camelot",
    # Meme client que la cible `camelot` de deploy.ps1 (qui pointe sur ...\Interface\AddOns).
    [string] $WowRoot = "D:\Jeux\World of Warcraft\_classic_beta_"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Lua  = Join-Path (Split-Path $Root -Parent) "tools\elune\bin\lua.exe"

if (-not (Test-Path $Lua)) { Write-Host "ERREUR: Elune lua.exe introuvable: $Lua" -ForegroundColor Red; exit 1 }
Set-Location $Root

$accounts = Join-Path $WowRoot "WTF\Account"
if (-not (Test-Path $accounts)) { Write-Host "ERREUR: pas de dossier WTF\Account sous $WowRoot" -ForegroundColor Red; exit 1 }

# Un dossier ne compte que s'il porte AU MOINS une des deux SavedVariables lues.
$dirs = @(Get-ChildItem $accounts -Directory | ForEach-Object { Join-Path $_.FullName "SavedVariables" } |
    Where-Object { (Test-Path (Join-Path $_ "COCScout.lua")) -or (Test-Path (Join-Path $_ "CraftingOrderClassic.lua")) })
if ($dirs.Count -eq 0) { Write-Host "Aucune SavedVariable COCScout/COC trouvee sous $accounts." -ForegroundColor Yellow; exit 0 }

Write-Host ("== Import de la recolte ({0}) : {1} compte(s) ==" -f $Flavor, $dirs.Count) -ForegroundColor Cyan
& $Lua "tools\import_observed.lua" $Flavor @dirs
if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR: import echoue." -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "Ensuite : lua tools\gen_origins.lua $Flavor   puis relire le diff git (fichier cure + Data)." -ForegroundColor Green
