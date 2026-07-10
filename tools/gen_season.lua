---@diagnostic disable: undefined-global
-- tools/gen_season.lua — Génère une COUCHE SAISONNIÈRE additive : Data/<Season>/<Métier>.lua.
--
-- Une saison (Saison de la Découverte, et demain Camelot) ajoute des recettes à un set de base
-- SANS le remplacer. Les fichiers produits appellent `CraftLink:ExtendProfession` (append-only)
-- et s'auto-désactivent hors de leur saison (`CraftLink:ActiveSeason() ~= <seasonId>`).
--
-- INVARIANT CAPITAL : le set de base (Vanilla, dataVersion figée 1792301894) n'est JAMAIS touché.
-- Les recettes saisonnières sont AJOUTÉES EN FIN de `recipes`, donc les positions 1..N des recettes
-- de base — et donc les bitfields du registre déjà diffusés chez les joueurs — restent valides bit
-- pour bit. Seule la dataVersion change, et seulement pour les clients dans la saison.
-- Vérifier avec `lua tools\check_dataversion.lua` AVANT et APRÈS toute génération.
--
-- Source UNIQUE : cache HTML Wowhead tools/wh/<domaine>_<Métier>.html (cf. tools/README.md).
-- Une ligne du Listview `spells` taguée `"seasonId":<N>` = recette saisonnière. Champs exploités :
--   "id" (spellID), "creates":[itemID,...] (produit ; absent = service, ex. enchantements),
--   "reagents":[[itemID,qty],...], "learnedat":N, "name".
-- `taughtBy` = jointure par NOM avec le Listview `recipe-items` (`"classs":9`, « Recipe: X »),
-- comme gen_metadata.lua : Wowhead n'expose pas le lien plan->sort.
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_season.lua SoD          # saison 2, domaine classic, base Vanilla

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local WH_DIR    = [[tools\wh\]]

-- Ajouter ici une saison future (Camelot) : domaine Wowhead, seasonId, set de base à étendre.
local SEASONS = {
    SoD = {
        seasonId = 2, domain = "classic", base = "Vanilla",
        label = "Saison de la Découverte",
        profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering",
                  "FirstAid", "Leatherworking", "Mining", "Poisons", "Tailoring" },
    },
}

-- Nom de fichier -> clé canonique du métier (le Secourisme s'écrit « First Aid » partout).
local CANON = { FirstAid = "First Aid" }

local function read(p) local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c end
local function write(p, c) local f = assert(io.open(p, "wb")); f:write(c); f:close() end

-- Set des spellID du bloc `recipes` du set de BASE : garde anti-collision (une recette saisonnière
-- déjà présente dans la base ne doit JAMAIS être ré-appondue — elle décalerait les positions).
local function baseRecipes(base, prof)
    local c = read(DATA_ROOT .. base .. [[\]] .. prof .. ".lua")
    if not c then return nil end
    local block = c:match("recipes%s*=%s*(%b{})")
    if not block then return nil end
    local set = {}
    for id in block:gmatch("%d+") do set[tonumber(id)] = true end
    return set
end

-- Les lignes du Listview n'ont PAS d'accolade imbriquée (creates/reagents sont des `[]`) : on
-- découpe sur les accolades. Un `%b{}` attraperait l'accolade externe de `Listview({...})`.
local function rows(html)
    local out = {}
    for chunk in html:gmatch("[^{}]+") do
        if chunk:find('"id":', 1, true) then out[#out + 1] = chunk end
    end
    return out
end

local function parseReagents(row)
    local block = row:match('"reagents":%[(.-)%]%]')
    if not block then return nil end
    local out = {}
    for item, qty in (block .. "]"):gmatch("%[(%d+),(%d+)%]") do
        out[#out + 1] = { tonumber(item), tonumber(qty) }
    end
    return (#out > 0) and out or nil
end

-- Recettes saisonnières d'une page : { spellID -> { produces, reagents, learnedAt, name } }.
local function parseSeason(html, seasonId, base)
    local tag, out = '"seasonId":' .. seasonId, {}
    for _, row in ipairs(rows(html)) do
        if row:find(tag, 1, true) and row:find('"skill":', 1, true)
           and not row:find('"classs":9', 1, true) then
            local id = tonumber(row:match('"id":(%d+)'))
            if id and not out[id] and not base[id] then
                out[id] = {
                    produces  = tonumber(row:match('"creates":%[(%d+)')),
                    reagents  = parseReagents(row),
                    learnedAt = tonumber(row:match('"learnedat":(%d+)')),
                    name      = row:match('"name":"([^"]*)"'),
                }
            end
        end
    end
    return out
end

-- Objets-plans saisonniers -> spellID enseigné, par jointure sur le NOM (préfixe « Xxx: » retiré).
-- Les plans portent EUX AUSSI le tag `seasonId` : on s'y restreint. Sans ce filtre, un plan de BASE
-- dont le nom coïncide avec un sort saisonnier lui serait rattaché à tort (mesuré : 18 faux
-- appariements en Forge) → `RecipeFromPlanItem` mentirait sur l'alerte « plan looté ».
local function parseTaughtBy(html, seasonId, season)
    local tag, byName = '"seasonId":' .. seasonId, {}
    for sid, e in pairs(season) do
        if e.name then
            local k = e.name:lower()
            if byName[k] ~= nil then byName[k] = false   -- nom ambigu : on ne joint pas dessus
            else byName[k] = sid end
        end
    end
    local out = {}
    for _, row in ipairs(rows(html)) do
        if row:find('"classs":9', 1, true) and row:find(tag, 1, true) then
            local id   = tonumber(row:match('"id":(%d+)'))
            local name = row:match('"name":"([^"]*)"')
            local taught = name and name:match("^[^:]+:%s*(.+)$")
            local sid = taught and byName[taught:lower()]
            if id and sid then out[id] = sid end
        end
    end
    return out
end

-- ------------------------------------------------------------------
-- Rendu du fichier Lua
-- ------------------------------------------------------------------
local function sortedKeys(t)
    local k = {}; for id in pairs(t) do k[#k + 1] = id end; table.sort(k); return k
end

local function renderList(ids)
    local lines, buf = {}, {}
    for i, id in ipairs(ids) do
        buf[#buf + 1] = tostring(id)
        if #buf == 12 or i == #ids then lines[#lines + 1] = "        " .. table.concat(buf, ", ") .. ","; buf = {} end
    end
    return table.concat(lines, "\n")
end

local function renderMap(name, pairsList, fmt)
    if #pairsList == 0 then return nil end
    local out = { "    " .. name .. " = {" }
    for _, p in ipairs(pairsList) do out[#out + 1] = fmt(p) end
    out[#out + 1] = "    },"
    return table.concat(out, "\n")
end

local function renderProf(cfg, profFile, season, taughtBy)
    local canon = CANON[profFile] or profFile
    local ids   = sortedKeys(season)

    local produces, i2s, reag, la = {}, {}, {}, {}
    for _, sid in ipairs(ids) do
        local e = season[sid]
        if e.produces then produces[#produces + 1] = { sid, e.produces }; i2s[#i2s + 1] = { e.produces, sid } end
        if e.reagents then reag[#reag + 1] = { sid, e.reagents } end
        if e.learnedAt then la[#la + 1] = { sid, e.learnedAt } end
    end
    table.sort(i2s, function(a, b) return a[1] < b[1] end)
    local tb = {}
    for itemID, sid in pairs(taughtBy) do tb[#tb + 1] = { itemID, sid } end
    table.sort(tb, function(a, b) return a[1] < b[1] end)

    local blocks = {
        string.format([[
-- Data/%s/%s.lua — couche saisonnière « %s » (seasonId %d).
-- GÉNÉRÉ par tools/gen_season.lua — NE PAS ÉDITER À LA MAIN.
-- Source : Wowhead (domaine « %s », lignes taguées seasonId:%d).
--
-- ADDITIF : ces recettes sont AJOUTÉES EN FIN du set %s, dont les positions de bits (donc les
-- bitfields du registre déjà diffusés) restent intactes. Le fichier s'auto-désactive hors saison.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end
if CraftLink:ActiveSeason() ~= %d then return end   -- couche inerte hors de sa saison

CraftLink:ExtendProfession("%s", {
    -- recettes saisonnières (appondues à la suite du set de base, jamais insérées)
    recipes = {]], cfg.name, profFile, cfg.label, cfg.seasonId, cfg.domain, cfg.seasonId,
                cfg.base, cfg.seasonId, canon),
        renderList(ids),
        "    },",
    }

    local function push(s) if s then blocks[#blocks + 1] = s end end
    push(renderMap("itemToSpell", i2s, function(p) return string.format("        [%d] = %d,", p[1], p[2]) end))
    push(renderMap("produces", produces, function(p) return string.format("        [%d] = %d,", p[1], p[2]) end))
    push(renderMap("reagents", reag, function(p)
        local parts = {}
        for _, r in ipairs(p[2]) do parts[#parts + 1] = string.format("{%d,%d}", r[1], r[2]) end
        return string.format("        [%d] = { %s },", p[1], table.concat(parts, ", "))
    end))
    push(renderMap("learnedAt", la, function(p) return string.format("        [%d] = %d,", p[1], p[2]) end))
    push(renderMap("taughtBy", tb, function(p) return string.format("        [%d] = %d,", p[1], p[2]) end))
    blocks[#blocks + 1] = "})\n"
    return table.concat(blocks, "\n"), #ids, #produces, #reag, #la, #tb
end

-- ------------------------------------------------------------------
-- Main
-- ------------------------------------------------------------------
local name = arg and arg[1] or "SoD"
local cfg  = SEASONS[name] or error("saison inconnue : " .. tostring(name))
cfg.name = name

os.execute('mkdir "' .. DATA_ROOT .. name .. '" 2>nul')

local total, files = 0, {}
for _, profFile in ipairs(cfg.profs) do
    local html = read(WH_DIR .. cfg.domain .. "_" .. profFile .. ".html")
    local base = baseRecipes(cfg.base, profFile)
    if not html then print("SKIP " .. profFile .. " (cache HTML absent)")
    elseif not base then print("SKIP " .. profFile .. " (set de base " .. cfg.base .. " introuvable)")
    else
        local season = parseSeason(html, cfg.seasonId, base)
        local n = 0; for _ in pairs(season) do n = n + 1 end
        if n == 0 then
            print(string.format("%-16s aucune recette seasonId:%d — pas de fichier", profFile, cfg.seasonId))
        else
            local taughtBy = parseTaughtBy(html, cfg.seasonId, season)
            local body, nr, np, nrg, nla, ntb = renderProf(cfg, profFile, season, taughtBy)
            write(DATA_ROOT .. name .. [[\]] .. profFile .. ".lua", body)
            files[#files + 1] = profFile
            total = total + nr
            print(string.format("%-16s recettes=%-4d produces=%-4d reagents=%-4d learnedAt=%-4d taughtBy=%d",
                profFile, nr, np, nrg, nla, ntb))
        end
    end
end

-- XML de la saison (inclus par le .toc de base, APRÈS le XML du set de base).
local xml = { '<Ui xmlns="http://www.blizzard.com/wow/ui/">',
    string.format('    <!-- Couche saisonnière « %s » (seasonId %d) — GÉNÉRÉ par tools/gen_season.lua.', cfg.label, cfg.seasonId),
    string.format('         À inclure APRÈS %s.xml : ces fichiers ÉTENDENT les métiers déjà enregistrés.', cfg.base),
    '         Chaque fichier est inerte hors de sa saison (garde CraftLink:ActiveSeason()). -->' }
for _, p in ipairs(files) do xml[#xml + 1] = string.format('    <Script file="%s\\%s.lua"/>', name, p) end
xml[#xml + 1] = "</Ui>\n"
write(DATA_ROOT .. name .. ".xml", table.concat(xml, "\n"))

print(string.format("\nTerminé (%s) : %d recettes saisonnières sur %d métiers. %s.xml écrit.",
    name, total, #files, name))
