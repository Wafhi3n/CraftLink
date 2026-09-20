# tools\fetch_items.ps1 — Telecharge les pages Wowhead des OBJETS-RECETTE d'une saveur.
#
# POURQUOI une page par objet, et pas la page de metier. La page de metier ne donne qu'UN nom de
# PNJ (`sourcemore`) et jamais sa faction : « Recipe: Gingerbread Cookie » y rend Wulmort
# Jinglepocket, a Forgefer, ce qui envoyait un joueur de la Horde en territoire allie. La page de
# l'OBJET porte la liste complete -- les 6 marchands, leur zone, leur camp et le prix.
#
# C'est long (une requete par objet) mais ca ne se refait pas souvent : le cache est conserve et
# les pages deja presentes sont SAUTEES. -Force pour tout reprendre.
#
# /!\ WOWHEAD RATIONNE, ET LE BLOCAGE EST BRUTAL. Mesure le 2026-09-20 : a 0,35 s d'intervalle, 144
# pages passent puis CloudFront rend 403 « Request blocked » sur TOUT, et ca ne se debloque pas de
# sitot. D'ou deux garde-fous : un intervalle par defaut bien plus large, et un ARRET AUTOMATIQUE au
# bout de quelques refus consecutifs. Sans ce second, le script a enchaine 630 requetes contre un mur
# -- inutiles, et exactement le genre d'acharnement qui allonge un bannissement.
# Il n'y a rien a rattraper dans l'urgence : les pages manquantes retombent sur le nom que la page de
# metier donnait, et une relance plus tard reprend la ou on en etait (les pages en cache sont sautees).
#
# Usage (cwd = f:\AddonDevellopement\CraftLink) :
#   .\tools\fetch_items.ps1                    # Camelot, ce qui manque au cache
#   .\tools\fetch_items.ps1 -Max 20            # les 20 premieres seulement (essai)
#   .\tools\fetch_items.ps1 -Force             # re-telecharge meme ce qui est deja la
#   .\tools\fetch_items.ps1 -Flavor Vanilla

param(
    [string] $Flavor = "Camelot",
    [int]    $Max    = 0,
    [double] $Delay  = 2.0,
    [int]    $StopAfter = 5,     # refus CONSECUTIFS avant d'abandonner (0 = ne jamais abandonner)
    [switch] $Force
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Lua  = Join-Path (Split-Path $Root -Parent) "tools\elune\bin\lua.exe"

if (-not (Test-Path $Lua)) { Write-Host "ERREUR: Elune lua.exe introuvable: $Lua" -ForegroundColor Red; exit 1 }
Set-Location $Root

$lines = & $Lua "tools\gen_origins.lua" $Flavor -urls
if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR: gen_origins -urls a echoue." -ForegroundColor Red; exit 1 }

New-Item -ItemType Directory -Force "tools\wh\items" | Out-Null

$todo = @()
foreach ($line in $lines) {
    if (-not $line) { continue }
    $parts = $line -split "`t", 2
    if ($parts.Count -ne 2) { continue }
    if ((-not $Force) -and (Test-Path $parts[0])) { continue }
    $todo += ,@($parts[0], $parts[1])
}
if ($Max -gt 0 -and $todo.Count -gt $Max) { $todo = $todo[0..($Max - 1)] }

Write-Host ("== Pages d'objet ({0}) : {1} a telecharger ==" -f $Flavor, $todo.Count) -ForegroundColor Cyan
if ($todo.Count -eq 0) { Write-Host "Cache deja complet." -ForegroundColor Green; exit 0 }

$ok = 0; $ko = 0; $i = 0; $streak = 0
foreach ($entry in $todo) {
    $out, $url = $entry[0], $entry[1]
    $tmp = "$out.new"
    $i++

    # curl.exe, PAS curl : sous PowerShell 5.1 `curl` est un ALIAS d'Invoke-WebRequest.
    # -L : l'URL canonique redirige vers item=<id>/<slug>, sans quoi on recupere une page vide.
    & curl.exe -sSL -A "Mozilla/5.0" $url -o $tmp --max-time 60 2>$null

    # On n'ECRASE le cache que si la page ressemble a une vraie page d'objet. Sans ce garde, une
    # reponse d'erreur ou tronquee remplacerait une bonne page, et on perdrait la reference au
    # moment meme ou on en a besoin. Meme discipline que refresh_flavor.ps1.
    $good = $false
    if (Test-Path $tmp) {
        $len = (Get-Item $tmp).Length
        if ($len -gt 5000) {
            $body = Get-Content $tmp -Raw -ErrorAction SilentlyContinue
            if ($body -and $body.Contains("new Listview(")) { $good = $true }
        }
    }
    if ($good) { Move-Item $tmp $out -Force; $ok++; $streak = 0 }
    else { if (Test-Path $tmp) { Remove-Item $tmp -Force }; $ko++; $streak++ }

    # Un refus isole = une page cassee, on passe. Une SERIE = le site nous a ferme la porte, et
    # insister ne la rouvrira pas.
    if ($StopAfter -gt 0 -and $streak -ge $StopAfter) {
        Write-Host ""
        Write-Host ("ARRET : {0} refus consecutifs -- Wowhead nous rationne (403 CloudFront)." -f $streak) -ForegroundColor Yellow
        Write-Host ("  {0} page(s) prises avant le blocage. Relancer plus tard : le cache est garde." -f $ok) -ForegroundColor Yellow
        break
    }

    if (($i % 25) -eq 0 -or $i -eq $todo.Count) {
        Write-Host ("  {0,5}/{1}  ok={2} refus={3}" -f $i, $todo.Count, $ok, $ko)
    }
    Start-Sleep -Seconds $Delay
}

Write-Host ""
Write-Host ("Termine : {0} page(s) en cache, {1} refusee(s)." -f $ok, $ko) -ForegroundColor Green
Write-Host "Ensuite : lua tools\gen_origins.lua $Flavor -check   (puis sans -check pour ecrire)"
