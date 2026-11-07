---@diagnostic disable: undefined-global
-- tools/gen_skill_colors.lua — Ajoute les SEUILS DE DIFFICULTÉ réels aux Data/<flavor>/*.lua :
--   skillColors : spellID -> { orange, jaune, vert, gris }
--   (gris = rang à partir duquel la recette ne rapporte PLUS de point de compétence)
--
-- POURQUOI : la couleur live de l'API du jeu n'existe que pour les recettes APPRISES et au rang
-- COURANT. Les seuils par recette permettent (1) la couleur exacte d'une recette MANQUANTE
-- (« va acheter ce plan » — sans eux, un plan niv. 55 était conseillé à un rang 244), et
-- (2) le futur plan de route 1→300 (prédire la couleur à un rang futur).
--
-- Source UNIQUE : cache HTML Wowhead tools/wh/<domaine>_<Métier>.html — le Listview `spells`
-- porte "colors":[o,j,v,g] sur chaque ligne (cf. tools/README.md). Restreint au set `recipes`
-- du fichier Data (même garde que gen_metadata.lua).
--
-- IDEMPOTENT : bloc sentinellisé `-- >>> gen_skill_colors.lua` remplacé à chaque relance ;
-- coexiste avec le bloc gen_metadata (chaque outil ne touche que SES sentinelles). NE TOUCHE
-- JAMAIS `recipes` : la dataVersion (Vanilla figée 1792301894) reste intacte — vérifier avec
-- check_dataversion.lua avant/après. ⚠️ gen_season.lua RÉGÉNÈRE les fichiers de saison :
-- relancer cet outil (saveur SoD) après lui.
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_skill_colors.lua            # Vanilla (cache tools\wh\classic_*.html)
--   lua tools\gen_skill_colors.lua TBC
--   lua tools\gen_skill_colors.lua Wrath
--   lua tools\gen_skill_colors.lua SoD        # couche saisonnière (Data\SoD\, pages classic)

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local WH_DIR    = [[tools\wh\]]

-- Métiers par saveur = exactement les fichiers présents dans Data/<flavor>/ (SoD = couche
-- additive sur Vanilla : mêmes pages Wowhead `classic`, set restreint aux recettes de saison).
local FLAVORS = {
    Vanilla = { domain = "classic", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Leatherworking", "Mining", "Poisons", "Tailoring" } },
    TBC     = { domain = "tbc", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Jewelcrafting", "Leatherworking", "Mining", "Tailoring" } },
    Wrath   = { domain = "wotlk", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Inscription", "Jewelcrafting", "Leatherworking",
                "Mining", "Tailoring" } },
    SoD     = { domain = "classic", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Leatherworking", "Mining", "Tailoring" } },
    -- Camelot = saveur COMPLETE (gen_flavor.lua), pages forever/. Pas de Poisons : Forever en a fait
    -- des sorts sans reactif (verifie 2026-09-18), il n'y a donc aucune recette a colorer.
    Camelot = { domain = "forever", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Leatherworking", "Mining", "Tailoring" } },
}

-- Les tables du CLIENT de jeu (tools\fetch_client.ps1) donnent une ligne aux recettes que Wowhead ne
-- colore pas : jaune et gris de SkillLineAbility, vert au milieu, calés sur learnedAt comme le fait
-- Wowhead. Une ligne de Wowhead n'est jamais réécrite (ses zéros sont des couleurs ABSENTES, pas des
-- trous) ; un désaccord est compté et listé (cf. tools/client_data.lua). Sans fichier curé : rien ne change.
local Client = dofile([[tools\client_data.lua]])
local CURATED_CLIENT = [[tools\Curated\client_%s.lua]]

local MARK_OPEN  = "    -- >>> gen_skill_colors.lua"
local MARK_CLOSE = "    -- <<< gen_skill_colors.lua"

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function writeFile(p, c)
    local f = assert(io.open(p, "wb")); f:write(c); f:close()
end

-- Set des spellID du bloc `recipes` du fichier (garde : on n'annote QUE le catalogue).
local function recipesSet(content)
    local block = content:match("recipes%s*=%s*(%b{})")
    if not block then return nil end
    local set, n = {}, 0
    for id in block:gmatch("%d+") do set[tonumber(id)] = true; n = n + 1 end
    return set, n
end

-- Listview `spells` : colors[spellID] = {o,j,v,g}. Les clés JSON sont triées ("colors" < "id"),
-- [^{}]- reste dans l'objet courant. Garde de cohérence : j <= v <= g et g > 0 (une ligne
-- dégénérée est ignorée — le runtime retombera sur l'heuristique).
local function parseColors(html)
    local out = {}
    for o, j, v, g, id in html:gmatch('"colors":%[(%d+),(%d+),(%d+),(%d+)%][^{}]-"id":(%d+)') do
        o, j, v, g, id = tonumber(o), tonumber(j), tonumber(v), tonumber(g), tonumber(id)
        if g > 0 and j <= v and v <= g then out[id] = { o, j, v, g } end
    end
    return out
end

-- learnedAt du fichier (bloc de PREMIER niveau) : l'orange d'une ligne que le client crée.
local function learnedAtOf(content)
    local out = {}
    local block = content:match("\n    learnedAt%s*=%s*(%b{})")
    if block then
        for k, v in block:gmatch("%[(%d+)%]%s*=%s*(%d+)") do out[tonumber(k)] = tonumber(v) end
    end
    return out
end

-- Bloc sentinellisé prêt à insérer + nb d'entrées gardées (restreintes au set recipes).
local function renderUnit(colors, recipes, sourceNote)
    local ids = {}
    for sid in pairs(colors) do
        if recipes[sid] then ids[#ids + 1] = sid end
    end
    table.sort(ids)
    local out = { MARK_OPEN .. " (généré — " .. sourceNote .. " ; ne pas éditer à la main)" }
    out[#out + 1] = "    -- seuils de difficulté : [spellID] = { orange, jaune, vert, gris }"
    out[#out + 1] = "    -- (gris = rang où la recette ne rapporte plus de point)"
    out[#out + 1] = "    skillColors = {"
    for _, sid in ipairs(ids) do
        local c = colors[sid]
        out[#out + 1] = string.format("        [%d] = { %d, %d, %d, %d },", sid, c[1], c[2], c[3], c[4])
    end
    out[#out + 1] = "    },"
    out[#out + 1] = MARK_CLOSE
    return table.concat(out, "\n"), #ids
end

-- Remplace le bloc existant (entre SES sentinelles) ou insère avant le "})" final. Coexiste
-- avec le bloc gen_metadata : chaque outil ne cherche que ses propres marqueurs.
local function upsertUnit(content, unit)
    local s = content:find(MARK_OPEN, 1, true)
    if s then
        local e = content:find(MARK_CLOSE, s, true)
        assert(e, "sentinelle ouvrante sans fermante — fichier à réparer à la main")
        local rest = content:sub(e + #MARK_CLOSE):gsub("^\n?", "")
        return content:sub(1, s - 1) .. unit .. "\n" .. rest
    end
    content = content:gsub("%s*$", "")
    assert(content:sub(-2) == "})", "le fichier ne se termine pas par '})'")
    return content:sub(1, -3) .. "\n" .. unit .. "\n})\n"
end

-- ------------------------------------------------------------------
-- Main
-- ------------------------------------------------------------------
local flavor = arg and arg[1] or "Vanilla"
local cfg = FLAVORS[flavor] or error("saveur inconnue : " .. tostring(flavor) .. " (Vanilla|TBC|Wrath|SoD)")

local total, totalMissing = 0, 0
local clientData, clientStat = Client.load(string.format(CURATED_CLIENT, flavor)), Client.newStat()
local sourceNote = "Wowhead " .. cfg.domain
if clientData then sourceNote = sourceNote .. " + client " .. clientData.build end

for _, prof in ipairs(cfg.profs) do
    local path     = DATA_ROOT .. flavor .. [[\]] .. prof .. ".lua"
    local content  = readFile(path)
    local htmlPath = WH_DIR .. cfg.domain .. "_" .. prof .. ".html"
    local html     = readFile(htmlPath)
    if not content then print("SKIP " .. prof .. " (fichier data absent : " .. path .. ")")
    elseif not html then print("SKIP " .. prof .. " (cache " .. htmlPath .. " manquant)")
    else
        local recipes, nRec = recipesSet(content)
        if not recipes then print("SKIP " .. prof .. " (bloc recipes introuvable)") else
            local colors = parseColors(html)
            Client.fillColors(colors, recipes, clientData, learnedAtOf(content), clientStat)
            local unit, n = renderUnit(colors, recipes, sourceNote)
            writeFile(path, upsertUnit(content, unit))
            total = total + n; totalMissing = totalMissing + (nRec - n)
            print(string.format("%-16s recettes=%-4d colors=%-4d sans-colors=%d",
                prof, nRec, n, nRec - n))
        end
    end
end

print(string.format("Terminé (%s) : %d skillColors (%d recettes sans seuils -> heuristique runtime).",
    flavor, total, totalMissing))

-- Corrections et conflits ne s'impriment pas un par un (des dizaines quand le client a changé des
-- seuils depuis la page) : ils vont dans le cache, à côté des CSV, pour relecture et vérif en jeu.
local s = clientData and Client.summary(clientStat, clientData.build)
if s then
    print(s)
    if #clientStat.conflicts > 0 then
        local path = [[tools\db2\conflits_couleurs_]] .. flavor .. ".txt"
        local f = io.open(path, "wb")
        if f then
            f:write("# nature\tspellID\tWowhead {orange, jaune, vert, gris}\tclient calé sur learnedAt {orange, jaune, vert, gris}\n")
            f:write("# corrige = le client remplace la ligne ; conflit = niveau inconnu, Wowhead gardé\n")
            for _, c in ipairs(clientStat.conflicts) do
                f:write(string.format("%s\t%d\t{ %s }\t{ %s }\n", c[5], c[2], table.concat(c[3], ", "),
                    table.concat(c[4], ", ")))
            end
            f:close()
            print(string.format("  %d ligne(s) corrigée(s) ou en conflit, listées dans %s", #clientStat.conflicts, path))
        end
    end
end
