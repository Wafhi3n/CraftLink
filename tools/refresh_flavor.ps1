# tools\refresh_flavor.ps1 — Rafraichit le cache Wowhead d'une saveur, puis signale la derive.
#
# POURQUOI cet outil existe : WoW: Forever est en BETA (niveau plafonne a 30 jusqu'au 4 nov. 2026)
# et Blizzard OFFUSQUE les donnees client pour empecher le datamining. La base Wowhead ne se remplit
# donc pas d'un coup a partir des fichiers du jeu : elle se construit par OBSERVATION des joueurs,
# progressivement, et elle bouge a chaque patch de beta. Il faut donc repasser souvent.
#
# CONSEQUENCE SUR LA SURETE, et c'est toute la raison d'etre du mode -check : une recette qui
# DISPARAIT d'une page est presque toujours un trou de collecte, une page tronquee ou un fetch rate
# -- pas un vrai retrait. Ce script DETECTE et n'applique jamais tout seul. L'application reste un
# geste explicite (-Apply), parce qu'appliquer une perte retirerait des recettes reelles de l'addon
# des joueurs sur la foi d'une page incomplete.
#
# La liste des metiers n'est PAS redeclaree ici : elle vient de gen_flavor.lua -urls. Deux listes
# finissent toujours par diverger, et celle qui se tait est la pire (cf. la liste de .toc ecrite en
# dur dans bump_version.ps1, qui a ignore _Camelot.toc pendant tout le portage).
#
# Usage (cwd = f:\AddonDevellopement\CraftLink) :
#   .\tools\refresh_flavor.ps1                 # Camelot : fetch + controle, n'ecrit aucune donnee
#   .\tools\refresh_flavor.ps1 -Apply          # + regenere si (et seulement si) la derive est SAINE
#   .\tools\refresh_flavor.ps1 -SkipFetch      # controle sur le cache deja present

param(
    [string] $Flavor = "Camelot",
    [switch] $Apply,
    [switch] $SkipFetch
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Lua  = Join-Path (Split-Path $Root -Parent) "tools\elune\bin\lua.exe"
$Gen  = "tools\gen_flavor.lua"

if (-not (Test-Path $Lua)) { Write-Host "ERREUR: Elune lua.exe introuvable: $Lua" -ForegroundColor Red; exit 1 }
Set-Location $Root

# ---------------------------------------------------------------- Fetch
if (-not $SkipFetch) {
    Write-Host "== Cache Wowhead ($Flavor) ==" -ForegroundColor Cyan
    $lines = & $Lua $Gen $Flavor -urls
    if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR: gen_flavor -urls a echoue." -ForegroundColor Red; exit 1 }

    foreach ($line in $lines) {
        if (-not $line) { continue }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) { continue }
        $out, $url = $parts[0], $parts[1]
        $tmp = "$out.new"

        # curl.exe, PAS curl : sous PowerShell 5.1 `curl` est un ALIAS d'Invoke-WebRequest, qui ne
        # comprend aucun de ces arguments et echouerait sur une erreur cryptique.
        & curl.exe -s -A "Mozilla/5.0" $url -o $tmp --max-time 60

        # On n'ECRASE le cache que si la page telechargee ressemble a une vraie page de metier.
        # Sans ce garde, une reponse d'erreur ou tronquee remplacerait un bon cache, et la reference
        # serait perdue au moment meme ou on en a le plus besoin pour juger la derive.
        $ok = $false
        if (Test-Path $tmp) {
            $head = Get-Content $tmp -Raw -ErrorAction SilentlyContinue
            if ($head -and $head.Contains("id: 'spells'")) { $ok = $true }
        }
        $leaf = Split-Path $out -Leaf
        if ($ok) {
            Move-Item $tmp $out -Force
            $kb = [math]::Round((Get-Item $out).Length / 1KB)
            Write-Host ("  [OK]     {0,-34} {1} Ko" -f $leaf, $kb) -ForegroundColor Green
        } else {
            if (Test-Path $tmp) { Remove-Item $tmp -Force }
            Write-Host ("  [REFUSE] {0,-34} page invalide, ancien cache conserve" -f $leaf) -ForegroundColor Yellow
        }
    }
    Write-Host ""
}

# ---------------------------------------------------------------- Controle
Write-Host "== Controle de derive ==" -ForegroundColor Cyan
& $Lua $Gen $Flavor -check
$drift = $LASTEXITCODE

# 0 = identique, 2 = ajouts seuls, 1 = perte ou cache manquant (cf. l'en-tete de gen_flavor.lua).
if ($drift -eq 0) { Write-Host "`nRien a faire." -ForegroundColor Green; exit 0 }

if ($drift -eq 1) {
    Write-Host "`nPERTE ou cache manquant : NE PAS appliquer." -ForegroundColor Red
    Write-Host "Refaire le fetch, puis regarder la page en cause a la main avant de conclure a un vrai retrait." -ForegroundColor Red
    exit 1
}

if (-not $Apply) {
    Write-Host "`nDerive SAINE (ajouts seuls). Relancer avec -Apply pour la prendre." -ForegroundColor Yellow
    exit 2
}

# ---------------------------------------------------------------- Application
Write-Host "`n== Application ==" -ForegroundColor Cyan
& $Lua $Gen $Flavor
if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR: generation echouee." -ForegroundColor Red; exit 1 }

& $Lua "tools\gen_skill_colors.lua" $Flavor
if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR: seuils de difficulte echoues." -ForegroundColor Red; exit 1 }

& $Lua "tools\check_dataversion.lua"

Write-Host "`nApplique. Reste a faire, dans l'ordre :" -ForegroundColor Green
Write-Host "  1. .\sync-libs.ps1            (pousser la lib dans les addons hotes)"
Write-Host "  2. ..\scripts\check_lua.ps1   (parite des .toc + Lua 5.1)"
Write-Host "  3. relire le diff git AVANT de commiter -- ces donnees viennent d'un site tiers."
Write-Host "  ATTENTION : un .lua de donnees EN PLUS = redemarrage complet du client, pas un /reload."
