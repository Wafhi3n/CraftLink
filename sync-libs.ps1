# sync-libs.ps1 — Synchronise la lib CraftLink (source canonique) dans le Libs/ de chaque addon hôte.
#
# CraftLink est EMBARQUÉE : sa source de vérité vit ici (repo CraftLink), et chaque addon en a
# une copie dans Addon\Libs\. Ce script recopie CraftLink-1.0\ + LibStub\ depuis ce repo vers
# les addons listés. À lancer après chaque modif de la lib, avant deploy.ps1.
#
# Usage : .\sync-libs.ps1                  (tous les addons hôtes)
#         .\sync-libs.ps1 TradeScanner     (un seul)

$LibRoot = $PSScriptRoot                       # repo CraftLink
$DevRoot = Split-Path $LibRoot -Parent         # F:\AddonDevellopement

# Addons qui embarquent CraftLink (chemins relatifs à $DevRoot).
$Hosts = @("TradeScanner", "CraftingOrderClassic")
if ($args.Count -gt 0) { $Hosts = $args }

# Dossiers de lib à recopier (depuis le repo CraftLink vers Addon\Libs\).
$LibFolders = @("CraftLink-1.0", "LibStub")

$ok = 0; $total = 0
foreach ($addon in $Hosts) {
    $addonPath = Join-Path $DevRoot $addon
    if (-not (Test-Path $addonPath)) {
        Write-Host "  [SKIP] $addon - dossier addon introuvable" -ForegroundColor Yellow
        continue
    }
    $total++
    $libsDst = Join-Path $addonPath "Libs"
    if (-not (Test-Path $libsDst)) { New-Item -ItemType Directory -Path $libsDst | Out-Null }

    foreach ($folder in $LibFolders) {
        $src = Join-Path $LibRoot $folder
        $dst = Join-Path $libsDst $folder
        if (Test-Path $dst) { Remove-Item $dst -Recurse -Force }
        Copy-Item $src $dst -Recurse -Force
    }
    Write-Host "  [OK] $addon - CraftLink + LibStub synchronisés" -ForegroundColor Green
    $ok++
}

Write-Host ""
if ($ok -eq $total -and $total -gt 0) {
    Write-Host "Lib synchronisee ($ok/$total)." -ForegroundColor Cyan
} elseif ($total -eq 0) {
    Write-Host "Aucun addon hote a synchroniser." -ForegroundColor Yellow
} else {
    Write-Host "Synchronisation partielle ($ok/$total)." -ForegroundColor Yellow
}
