# tools\fetch_client.ps1 -- Tables du CLIENT de jeu (db2) depuis wago.tools, puis le fichier cure
# tools\Curated\client_<Saveur>.lua que gen_flavor.lua et gen_skill_colors.lua relisent.
#
# POURQUOI : depuis le 2026-10-16 wowhead.com refuse nos requetes (pare-feu anti-robot, 403) et on ne
# le contourne pas. wago.tools publie les tables du client Forever build par build (API publique).
# Ce qu'elles valent et ce qu'elles ne donnent JAMAIS (recettes, niveaux) : en-tete de client_data.lua.
#
# Politesse : une requete par seconde, un User-Agent qui se nomme, et le cache se garde
# (tools\db2\<build>\, gitignore) : un build deja telecharge ne se redemande pas.
#
# Usage (cwd = f:\AddonDevellopement\CraftLink) :
#   .\tools\fetch_client.ps1                       # Camelot, dernier build du client
#   .\tools\fetch_client.ps1 -Build 1.60.1.70862   # un build precis
# Puis : .\tools\refresh_flavor.ps1 -SkipFetch [-Apply]

param(
    [string] $Flavor = "Camelot",
    [string] $Build  = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Lua  = Join-Path (Split-Path $Root -Parent) "tools\elune\bin\lua.exe"
if (-not (Test-Path $Lua)) { Write-Host "ERREUR: Elune lua.exe introuvable: $Lua" -ForegroundColor Red; exit 1 }
Set-Location $Root

# Saveur -> produit du client chez wago.tools.
$Products = @{ Camelot = "wowf" }
$product = $Products[$Flavor]
if (-not $product) { Write-Host "ERREUR: pas de produit wago.tools connu pour la saveur $Flavor" -ForegroundColor Red; exit 1 }

$UA = "CraftLink-tools/1.0 (+https://github.com/Wafhi3n/CraftLink)"
# Chaque table, et une colonne de son en-tete : une reponse sans elle n'est pas la table (page d'erreur).
$Tables = @(
    @{ Name = "SkillLineAbility"; Probe = "TrivialSkillLineRankHigh" },
    @{ Name = "SpellEffect";      Probe = "EffectItemType" },
    @{ Name = "SpellReagents";    Probe = "ReagentCount_0" }
)

if (-not $Build) {
    $raw = & curl.exe -s -A $UA "https://wago.tools/api/builds/latest" --max-time 60
    $Build = ($raw | ConvertFrom-Json).$product.version
    if (-not $Build) { Write-Host "ERREUR: build introuvable pour $product chez wago.tools" -ForegroundColor Red; exit 1 }
    Start-Sleep -Seconds 1
}
Write-Host "== Tables du client $product $Build ==" -ForegroundColor Cyan

$dir = Join-Path $Root "tools\db2\$Build"
New-Item -ItemType Directory -Force $dir | Out-Null
foreach ($t in $Tables) {
    $out = Join-Path $dir "$($t.Name).csv"
    if (Test-Path $out) { Write-Host ("  [cache]  {0}" -f $t.Name); continue }
    $tmp = "$out.new"
    & curl.exe -s -A $UA "https://wago.tools/db2/$($t.Name)/csv?build=$Build" -o $tmp --max-time 300
    $head = if (Test-Path $tmp) { Get-Content $tmp -TotalCount 1 } else { "" }
    if ($head -and $head.Contains($t.Probe)) {
        Move-Item $tmp $out -Force
        Write-Host ("  [OK]     {0,-17} {1} Ko" -f $t.Name, [math]::Round((Get-Item $out).Length / 1KB)) -ForegroundColor Green
    } else {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        Write-Host ("  [REFUSE] {0} : reponse invalide, rien d'ecrit" -f $t.Name) -ForegroundColor Red
        exit 1
    }
    Start-Sleep -Seconds 1
}

# Les lignes de competence des metiers : celles de gen_flavor.lua, jamais une seconde liste.
$skills = @(& $Lua "tools\gen_flavor.lua" $Flavor -urls | ForEach-Object { if ($_ -match 'skill=(\d+)') { $Matches[1] } })
if ($skills.Count -eq 0) { Write-Host "ERREUR: gen_flavor.lua -urls n'a rendu aucun metier." -ForegroundColor Red; exit 1 }

& $Lua "tools\import_client.lua" $Flavor "tools\db2\$Build" @skills
if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR: import des tables echoue." -ForegroundColor Red; exit 1 }

Write-Host "`nEnsuite : .\tools\refresh_flavor.ps1 -SkipFetch   (controle), puis -Apply ; relire le diff git." -ForegroundColor Green
