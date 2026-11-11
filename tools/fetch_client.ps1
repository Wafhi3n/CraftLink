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
#   .\tools\fetch_client.ps1 -NoHotfixes           # la table du build seule (hors ligne, comparaison)
# Puis : .\tools\refresh_flavor.ps1 -SkipFetch [-Apply]
#
# HOTFIXES (2026-11-11) : le CSV est la table telle que le BUILD la livre ; le serveur la corrige ensuite
# sans nouveau build, et le jeu applique ces hotfixes (Coarse Grinding Stone grise a 90 en jeu, 75 dans le
# CSV). wago.tools les publie sur sa page /hotfixes. Ils sont RELUS a chaque passage, cache ou pas, dans
# tools\db2\<build>\<Table>.hotfixes.csv ; import_client.lua les applique (client_data.lua, applyHotfixes).

param(
    [string] $Flavor = "Camelot",
    [string] $Build  = "",
    [switch] $NoHotfixes
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

# --- Hotfixes du serveur ---------------------------------------------------------------------------
# La page /hotfixes porte ses donnees dans l'attribut data-page (JSON). Recherche "<n de build> <table>",
# 25 entrees par page, une entree par (region, langue, poussee) : on garde la DERNIERE poussee par
# enregistrement. data = les colonnes du CSV dans son ordre, tableaux a plat (verifie : meme nombre).
function Get-HotfixRows([string] $table, [string] $buildNo) {
    $search = [uri]::EscapeDataString("$buildNo $($table.ToLower())")
    $tmp = Join-Path $dir "hotfixes.page.tmp"
    $latest = @{}; $page = 1; $last = 1
    while ($page -le $last) {
        & curl.exe -s -A $UA "https://wago.tools/hotfixes?product=$product&search=$search&page=$page" -o $tmp --max-time 120
        $html = if (Test-Path $tmp) { Get-Content $tmp -Raw -Encoding UTF8 } else { "" }
        $m = [regex]::Match($html, 'data-page="([^"]*)"')
        if (-not $m.Success) { throw "hotfixes $table : page $page illisible" }
        $hf = ([System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) | ConvertFrom-Json).props.hotfixes
        $last = [math]::Max(1, [int]$hf.last_page)
        foreach ($r in $hf.data) {
            if ($r.table_name -ne $table) { continue }
            $k = [string]$r.record_id
            if (-not $latest.ContainsKey($k) -or [long]$r.push_id -gt [long]$latest[$k].push_id) { $latest[$k] = $r }
        }
        Write-Host ("`r  [hotfix] {0,-17} page {1}/{2}" -f $table, $page, $last) -NoNewline
        $page++
        Start-Sleep -Seconds 1
    }
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    Write-Host ""
    return $latest
}

function Format-CsvField($v) {
    if ($null -eq $v) { return "" }
    $s = if ($v -is [double] -or $v -is [single] -or $v -is [decimal]) { $v.ToString([cultureinfo]::InvariantCulture) } else { [string]$v }
    if ($s -match '[",\r\n]') { return '"' + $s.Replace('"', '""') + '"' }
    return $s
}

# <Table>.hotfixes.csv : HotfixStatus + les colonnes du CSV. Un enregistrement retire (statut 2) ou
# invalide (3) n'a pas de donnees : seule sa colonne ID est remplie.
function Write-HotfixCsv([string] $table, $latest) {
    $head = (Get-Content (Join-Path $dir "$table.csv") -TotalCount 1).Split(',')
    $idIdx = [array]::IndexOf($head, "ID")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("HotfixStatus," + ($head -join ","))
    foreach ($k in ($latest.Keys | Sort-Object { [long]$_ })) {
        $r = $latest[$k]
        $vals = New-Object System.Collections.Generic.List[string]
        if ([int]$r.status -eq 1 -and $null -ne $r.data) {
            foreach ($v in $r.data) {
                if ($v -is [array]) { foreach ($x in $v) { $vals.Add((Format-CsvField $x)) } } else { $vals.Add((Format-CsvField $v)) }
            }
            if ($vals.Count -ne $head.Count) { throw "hotfix $table #$k : $($vals.Count) champs pour $($head.Count) colonnes" }
        } else {
            for ($i = 0; $i -lt $head.Count; $i++) { $vals.Add($(if ($i -eq $idIdx) { $k } else { "" })) }
        }
        $lines.Add("$($r.status)," + ($vals -join ","))
    }
    [System.IO.File]::WriteAllLines((Join-Path $dir "$table.hotfixes.csv"), $lines, (New-Object System.Text.UTF8Encoding($false)))
    return $lines.Count - 1
}

if (-not $NoHotfixes) {
    $buildNo = $Build.Split('.')[-1]
    foreach ($t in $Tables) {
        $n = Write-HotfixCsv $t.Name (Get-HotfixRows $t.Name $buildNo)
        Write-Host ("  [hotfix] {0,-17} {1} enregistrement(s)" -f $t.Name, $n) -ForegroundColor Green
    }
} else {
    foreach ($t in $Tables) { $p = Join-Path $dir "$($t.Name).hotfixes.csv"; if (Test-Path $p) { Remove-Item $p -Force } }
    Write-Host "  [hotfix] ignores (-NoHotfixes) : la table du build seule" -ForegroundColor Yellow
}

# Les lignes de competence des metiers : celles de gen_flavor.lua, jamais une seconde liste.
$skills = @(& $Lua "tools\gen_flavor.lua" $Flavor -urls | ForEach-Object { if ($_ -match 'skill=(\d+)') { $Matches[1] } })
if ($skills.Count -eq 0) { Write-Host "ERREUR: gen_flavor.lua -urls n'a rendu aucun metier." -ForegroundColor Red; exit 1 }

& $Lua "tools\import_client.lua" $Flavor "tools\db2\$Build" @skills
if ($LASTEXITCODE -ne 0) { Write-Host "ERREUR: import des tables echoue." -ForegroundColor Red; exit 1 }

Write-Host "`nEnsuite : .\tools\refresh_flavor.ps1 -SkipFetch   (controle), puis -Apply ; relire le diff git." -ForegroundColor Green
