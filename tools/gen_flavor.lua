---@diagnostic disable: undefined-global
-- tools/gen_flavor.lua — Génère un set de recettes COMPLET pour une saveur : Data/<Saveur>/<Métier>.lua.
--
-- DIFFÉRENCE CAPITALE avec gen_season.lua, et c'est la raison d'être de cet outil : une SAISON
-- s'AJOUTE à un set de base (`ExtendProfession`, append-only) alors qu'une SAVEUR le REMPLACE
-- (`RegisterProfession`). Camelot/Forever ne fait pas qu'ajouter, il RETIRE — mesuré le 2026-09-18 :
-- les six potions de soin ont quitté l'Alchimie pour Premiers soins avec de NOUVEAUX spellID
-- (1244431..1244436), et les six sorts vanilla (118, 858, 929, 1710, 3928, 13446) ne figurent plus
-- dans les 197 recettes de la page forever/ d'Alchimie. Une couche additive ne sait pas retirer :
-- elle laisserait six recettes fantômes, commandables, pointant sur des sorts qui n'existent plus.
--
-- Le tri se fait par DOMAINE Wowhead, jamais par tag : les pages forever/ ne portent AUCUN
-- "seasonId" (vérifié, 0 occurrence). C'est le .toc de l'hôte qui choisit la saveur en incluant
-- Data/<Saveur>.xml, donc AUCUN garde-fou runtime n'est nécessaire — contrairement à une saison,
-- qui doit s'auto-désactiver. `C_Seasons` n'existe d'ailleurs pas sur Forever : une garde de saison
-- y serait non seulement inutile mais toujours fausse.
--
-- PRÉREQUIS : cache HTML Wowhead dans tools/wh/<domaine>_<Métier>.html. WebFetch ne convient pas
-- (il jette la table JS) — curl obligatoire, comme pour gen_wowhead.lua. Lancer `-fetch` pour
-- obtenir les commandes exactes de la saveur.
--
-- SECONDE PASSE : enchaîner gen_skill_colors.lua (les pages forever/ portent bien
-- "colors":[o,j,v,g]) puis gen_enchant_names.lua, puis check_dataversion.lua. Les deux premiers
-- injectent un bloc sentinelle que CET outil efface en réécrivant le fichier : refresh_flavor.ps1
-- -Apply les rejoue, dans cet ordre. L'ordre inverse donnerait le même contenu mais un autre
-- fichier — donc un faux diff à la prochaine relecture.
--
-- `disenchant` n'est PAS une seconde passe : il est émis ici même, depuis tools/Curated/.
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_flavor.lua Camelot -fetch          # imprime les commandes curl, n'écrit rien
--   lua tools\gen_flavor.lua Camelot                 # tous les métiers de la config
--   lua tools\gen_flavor.lua Camelot Alchemy FirstAid  # sous-ensemble (pilote)

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local WH_DIR    = [[tools\wh\]]

-- Produits de DÉSENCHANTEMENT (poussières, essences, éclats) : ce ne sont pas des recettes, aucune
-- page Wowhead de métier ne les liste. On lit la MÊME source curatée que gen_professions.lua pour
-- Vanilla — une liste pour deux générateurs, sinon elles finissent par diverger. Émis ICI et pas par
-- un outil de seconde passe : ce fichier réécrit Data/<Saveur>/*.lua de zéro, un bloc sentinelle
-- devrait donc être rejoué après chaque application, et un oubli le perdrait en silence.
local CURATED_DE = [[tools\Curated\disenchant.lua]]

local FLAVORS = {
    Camelot = {
        domain = "forever", base = "Vanilla",
        label  = "WoW: Forever (Camelot)",
        -- `skill` + `slug` servent UNIQUEMENT à imprimer les commandes curl (-fetch) : l'outil ne
        -- va jamais sur le réseau lui-même, pour que la génération reste rejouable hors ligne.
        profs = {
            { file = "Alchemy",        skill = 171, slug = "alchemy" },
            { file = "Blacksmithing",  skill = 164, slug = "blacksmithing" },
            { file = "Cooking",        skill = 185, slug = "cooking" },
            { file = "Enchanting",     skill = 333, slug = "enchanting" },
            { file = "Engineering",    skill = 202, slug = "engineering" },
            { file = "FirstAid",       skill = 129, slug = "first-aid" },
            { file = "Leatherworking", skill = 165, slug = "leatherworking" },
            { file = "Mining",         skill = 186, slug = "mining" },
            { file = "Poisons",        skill = 40,  slug = "poisons" },
            { file = "Tailoring",      skill = 197, slug = "tailoring" },
        },
    },
}

-- Nom de fichier -> clé canonique du métier (le Secourisme s'écrit « First Aid » partout).
local CANON = { FirstAid = "First Aid" }

local function read(p) local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c end
local function write(p, c) local f = assert(io.open(p, "wb")); f:write(c); f:close() end

-- ------------------------------------------------------------------
-- Parsing du cache Wowhead (mêmes primitives que gen_season.lua)
-- ------------------------------------------------------------------

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

-- TOUTES les recettes d'une page : { spellID -> { produces, reagents, learnedAt, name } }.
-- Le discriminant est `creates` OU `reagents`, et non `"skill":` seul : les sorts de RANG du métier
-- (« Secourisme » apprenti/compagnon…) portent eux aussi `"skill":` et pollueraient `recipes` —
-- 58 lignes en portent sur la page Premiers soins, dont 32 seulement sont de vraies recettes.
-- `reagents` d'abord car un service sans objet (les enchantements) n'a pas de `creates`.
local function parseAll(html)
    local out, n = {}, 0
    for _, row in ipairs(rows(html)) do
        local isRecipe = row:find('"reagents":', 1, true) or row:find('"creates":', 1, true)
        if isRecipe and not row:find('"classs":9', 1, true) then
            local id = tonumber(row:match('"id":(%d+)'))
            if id and not out[id] then
                out[id] = {
                    produces  = tonumber(row:match('"creates":%[(%d+)')),
                    reagents  = parseReagents(row),
                    learnedAt = tonumber(row:match('"learnedat":(%d+)')),
                    name      = row:match('"name":"([^"]*)"'),
                }
                n = n + 1
            end
        end
    end
    return out, n
end

-- Objets-plans -> spellID enseigné, par jointure sur le NOM (préfixe « Xxx: » retiré — le motif
-- coupe au premier `:` donc « Manual: », « Plans: » et « Pattern: » marchent comme « Recipe: »).
-- Pas de filtre par saison ici, contrairement à gen_season : sur une page de saveur, TOUTE la page
-- est la saveur. La garde anti-ambiguïté reste, elle : deux sorts de même nom ⇒ on ne joint pas.
local function parseTaughtBy(html, recipes)
    local byName = {}
    for sid, e in pairs(recipes) do
        if e.name then
            local k = e.name:lower()
            if byName[k] ~= nil then byName[k] = false   -- nom ambigu : on ne joint pas dessus
            else byName[k] = sid end
        end
    end
    local out = {}
    for _, row in ipairs(rows(html)) do
        if row:find('"classs":9', 1, true) then
            local id     = tonumber(row:match('"id":(%d+)'))
            local name   = row:match('"name":"([^"]*)"')
            local taught = name and name:match("^[^:]+:%s*(.+)$")
            local sid    = taught and byName[taught:lower()]
            if id and sid then out[id] = sid end
        end
    end
    return out
end

-- Les alias sont des noms LOCALISÉS du métier : ils ne dépendent pas de la saveur. On les reprend
-- du set de base plutôt que de les réécrire — deux listes divergentes casseraient ResolveProfession
-- sur une seule saveur, et ça ne se verrait qu'en jeu, dans cette langue-là.
local function baseAliases(base, profFile)
    local c = read(DATA_ROOT .. base .. [[\]] .. profFile .. ".lua")
    if not c then return nil end
    return c:match("(aliases%s*=%s*%b{})")
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

local function renderMap(name, list, fmt)
    if #list == 0 then return nil end
    local out = { "    " .. name .. " = {" }
    for _, p in ipairs(list) do out[#out + 1] = fmt(p) end
    out[#out + 1] = "    },"
    return table.concat(out, "\n")
end

-- { [métier canonique] = { disenchant = { [itemID] = "Nom" } } }, chargé une fois.
local curatedDE = dofile(CURATED_DE)

-- Bloc `disenchant` d'un métier, trié par itemID — même forme que Data/Vanilla/Enchanting.lua, que
-- lisent ProfessionCatalogue et le panneau Commande (ces objets n'ont pas de spellID : sans ce
-- bloc, le filtre « craftable uniquement » les écarte, et on ne peut plus en commander).
local function renderDisenchant(canon)
    local de = curatedDE[canon] and curatedDE[canon].disenchant
    if not de then return nil, 0 end
    local list = {}
    for _, id in ipairs(sortedKeys(de)) do list[#list + 1] = { id, de[id] } end
    return renderMap("disenchant", list, function(p) return string.format("        [%d] = %q,", p[1], p[2]) end), #list
end

-- Éclate le set parsé en les tables associatives du format Data. Extrait de renderProf pour tenir
-- sous le plafond de 60 lignes/fonction de l'écosystème.
local function collate(recipes, ids)
    local produces, i2s, reag, la = {}, {}, {}, {}
    for _, sid in ipairs(ids) do
        local e = recipes[sid]
        if e.produces then produces[#produces + 1] = { sid, e.produces }; i2s[#i2s + 1] = { e.produces, sid } end
        if e.reagents then reag[#reag + 1] = { sid, e.reagents } end
        if e.learnedAt then la[#la + 1] = { sid, e.learnedAt } end
    end
    table.sort(i2s, function(a, b) return a[1] < b[1] end)
    return produces, i2s, reag, la
end

local HEADER = [[
-- Data/%s/%s.lua — set COMPLET de la saveur « %s ».
-- GÉNÉRÉ par tools/gen_flavor.lua depuis Wowhead (domaine « %s/ »). NE PAS ÉDITER À LA MAIN.
-- Noms résolus au runtime (GetItemInfo/GetSpellInfo) — multilingue.
--
-- REMPLACE le set de base (RegisterProfession), il ne l'étend pas : cette saveur RETIRE des
-- recettes en plus d'en ajouter, ce qu'une couche additive ne sait pas faire. Sélectionné par le
-- .toc de l'hôte via Data/%s.xml — aucune garde runtime, le .toc est le seul aiguillage.

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not CraftLink then return end

CraftLink:RegisterProfession("%s", {
    %s,

    recipes = {]]

local function renderProf(cfg, profFile, recipes, taughtBy, aliases)
    local canon = CANON[profFile] or profFile
    local ids   = sortedKeys(recipes)
    local produces, i2s, reag, la = collate(recipes, ids)

    local tb = {}
    for itemID, sid in pairs(taughtBy) do tb[#tb + 1] = { itemID, sid } end
    table.sort(tb, function(a, b) return a[1] < b[1] end)

    local blocks = {
        string.format(HEADER, cfg.name, profFile, cfg.label, cfg.domain, cfg.name, canon, aliases),
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
    local deBlock, nde = renderDisenchant(canon)
    push(deBlock)
    blocks[#blocks + 1] = "})\n"
    return table.concat(blocks, "\n"), #ids, #produces, #reag, #la, #tb, nde
end

-- ------------------------------------------------------------------
-- Main
-- ------------------------------------------------------------------
local name = arg and arg[1] or "Camelot"
local cfg  = FLAVORS[name] or error("saveur inconnue : " .. tostring(name))
cfg.name = name

-- Drapeaux et sous-ensemble de métiers (pilote), sinon toute la config.
local flags, only = {}, {}
for i = 2, (arg and #arg or 0) do
    local a = arg[i]
    if a:sub(1, 1) == "-" then flags[a] = true else only[a] = true end
end
local subset = next(only) ~= nil

-- Recettes déjà COMMITÉES pour cette saveur (le set de référence du mode -check).
local function committedRecipes(profFile)
    local c = read(DATA_ROOT .. name .. [[\]] .. profFile .. ".lua")
    if not c then return nil end
    local block = c:match("recipes%s*=%s*(%b{})")
    if not block then return nil end
    local set, n = {}, 0
    for id in block:gmatch("%d+") do
        local v = tonumber(id)
        if not set[v] then set[v] = true; n = n + 1 end
    end
    return set, n
end

-- Mode -check : compare le cache HTML au set COMMITÉ, et n'écrit RIEN.
--
-- Pensé pour tourner souvent : le jeu est en bêta (niveau plafonné à 30 jusqu'au 4 novembre 2026) et
-- la base Wowhead se remplit par OBSERVATION des joueurs — Blizzard offusque les données client, donc
-- rien n'y arrive par datamining. Conséquence directe sur la sûreté, et c'est TOUTE la règle de ce
-- mode : une recette qui DISPARAÎT d'une page est presque toujours un trou de collecte, une page
-- tronquée ou un fetch raté — pas un vrai retrait. Une perte ne doit donc JAMAIS s'appliquer toute
-- seule : elle retirerait des recettes réelles de l'addon des joueurs sur la foi d'une page incomplète.
-- Les ajouts, eux, sont le cas normal pendant la bêta : on les signale, on ne s'en alarme pas.
--
-- Codes de sortie, pour qu'un job puisse trancher sans lire la sortie :
--   0 = identique     2 = ajouts seuls (dérive à appliquer)     1 = PERTE ou cache manquant (humain)
local function runCheck()
    local drift, lost, broken = 0, 0, 0
    for _, prof in ipairs(cfg.profs) do
        local f = prof.file
        if not (subset and not only[f]) then
            local html = read(WH_DIR .. cfg.domain .. "_" .. f .. ".html")
            local have, nHave = committedRecipes(f)
            local live, nLive = nil, 0
            if html then live, nLive = parseAll(html) end
            if not html then
                print(string.format("  [CACHE ABSENT] %-16s %s%s_%s.html", f, WH_DIR, cfg.domain, f))
                broken = broken + 1
            elseif not have and nLive == 0 then
                -- Absent des DEUX côtés : état stable et voulu, pas une panne. C'est le cas de Poisons,
                -- dont Forever a fait des sorts SANS réactif — il n'y a aucune recette à modéliser.
                -- Le compter en échec ferait échouer CHAQUE passage, et un contrôle qui crie au loup
                -- à tous les coups finit par n'être plus lu.
                print(string.format("  [sans recette] %-16s ni sur la page, ni commité (attendu)", f))
            elseif not have then
                -- La page en a, nous pas : un métier apparaît. C'est de la dérive à appliquer, pas une
                -- erreur — typiquement un métier que Wowhead vient de commencer à documenter.
                print(string.format("  [NOUVEAU]      %-16s %d recette(s) sur la page, aucun set commité", f, nLive))
                drift = drift + nLive
            else
                local add, del = 0, 0
                for id in pairs(live) do if not have[id] then add = add + 1 end end
                for id in pairs(have) do if not live[id] then del = del + 1 end end
                if del > 0 then
                    print(string.format("  [PERTE]        %-16s commitées=%-5d ajouts=%-4d PERTES=%d",
                        f, nHave, add, del))
                    lost = lost + del
                elseif add > 0 then
                    print(string.format("  [ajouts]       %-16s commitées=%-5d ajouts=%d", f, nHave, add))
                    drift = drift + add
                else
                    print(string.format("  [identique]    %-16s commitées=%d", f, nHave))
                end
            end
        end
    end
    print()
    if broken > 0 or lost > 0 then
        print(string.format("ÉCHEC : %d perte(s) de recette, %d problème(s) de cache. RIEN n'a été écrit.", lost, broken))
        print("Une perte vient presque toujours d'une page incomplète : refaire le fetch AVANT de conclure.")
        os.exit(1)
    elseif drift > 0 then
        print(string.format("DÉRIVE : %d recette(s) en plus sur Wowhead. Relancer sans -check pour les appliquer.", drift))
        os.exit(2)
    end
    print("Aucune dérive : le set commité correspond au cache.")
    os.exit(0)
end

if flags["-check"] then
    print("Contrôle de dérive — saveur " .. name .. " (domaine " .. cfg.domain .. "/), aucune écriture :")
    runCheck()
end

-- `-urls` : une ligne « <fichier de cache><TAB><url> » par métier, pour qu'un script enveloppe le
-- téléchargement sans RE-DÉCLARER la liste des métiers de son côté. Deux listes finissent toujours
-- par diverger, et celle qui se tait est la pire (cf. bump_version.ps1 et sa liste de .toc en dur).
if flags["-urls"] then
    for _, p in ipairs(cfg.profs) do
        if not (subset and not only[p.file]) then
            print(string.format("%s%s_%s.html	https://www.wowhead.com/%s/skill=%d/%s",
                WH_DIR, cfg.domain, p.file, cfg.domain, p.skill, p.slug))
        end
    end
    return
end

if flags["-fetch"] then
    print("# Cache HTML Wowhead pour la saveur " .. name .. " (cwd = CraftLink) :")
    for _, p in ipairs(cfg.profs) do
        print(string.format('curl -s -A "Mozilla/5.0" "https://www.wowhead.com/%s/skill=%d/%s" -o "%s%s_%s.html"',
            cfg.domain, p.skill, p.slug, WH_DIR:gsub("\\", "/"), cfg.domain, p.file))
    end
    return
end

os.execute('mkdir "' .. DATA_ROOT .. name .. '" 2>nul')

local total, files, missing = 0, {}, {}
for _, p in ipairs(cfg.profs) do
    local profFile = p.file
    if subset and not only[profFile] then
        -- ignoré : génération partielle demandée
    else
        local html    = read(WH_DIR .. cfg.domain .. "_" .. profFile .. ".html")
        local aliases = baseAliases(cfg.base, profFile)
        if not html then
            missing[#missing + 1] = profFile
            print(string.format("SKIP %-16s cache HTML absent (%s%s_%s.html)", profFile, WH_DIR, cfg.domain, profFile))
        elseif not aliases then
            print(string.format("SKIP %-16s alias introuvables dans le set de base %s", profFile, cfg.base))
        else
            local recipes, n = parseAll(html)
            if n == 0 then
                print(string.format("SKIP %-16s aucune recette trouvée sur la page", profFile))
            else
                local taughtBy = parseTaughtBy(html, recipes)
                local body, nr, np, nrg, nla, ntb, nde = renderProf(cfg, profFile, recipes, taughtBy, aliases)
                write(DATA_ROOT .. name .. [[\]] .. profFile .. ".lua", body)
                files[#files + 1] = profFile
                total = total + nr
                print(string.format("%-16s recettes=%-4d produces=%-4d reagents=%-4d learnedAt=%-4d taughtBy=%d%s",
                    profFile, nr, np, nrg, nla, ntb, nde > 0 and ("  disenchant=" .. nde) or ""))
            end
        end
    end
end

-- XML de la saveur. N'est RÉÉCRIT qu'en génération complète : sur un pilote partiel il listerait
-- deux métiers et le .toc perdrait silencieusement les huit autres.
if subset then
    print("\nGénération PARTIELLE : " .. name .. ".xml NON réécrit (il listerait un set incomplet).")
else
    local xml = { '<Ui xmlns="http://www.blizzard.com/wow/ui/">',
        string.format('    <!-- Données de recettes « %s » — GÉNÉRÉ par tools/gen_flavor.lua.', cfg.label),
        string.format('         Set COMPLET (RegisterProfession) : REMPLACE %s.xml, ne s\'y ajoute pas.', cfg.base),
        '         Inclus par le .toc flavor _Camelot de chaque addon hôte, à la place du XML de base. -->' }
    for _, f in ipairs(files) do xml[#xml + 1] = string.format('    <Script file="%s\\%s.lua"/>', name, f) end
    for _, shared in ipairs({ "Gathering", "Smelting", "Cooldowns", "Disenchant" }) do
        xml[#xml + 1] = string.format('    <Script file="%s.lua"/>', shared)
    end
    xml[#xml + 1] = "</Ui>\n"
    write(DATA_ROOT .. name .. ".xml", table.concat(xml, "\n"))
end

print(string.format("\nTerminé (%s) : %d recettes sur %d métiers.", name, total, #files))
if #missing > 0 then
    print("Caches HTML manquants (" .. #missing .. ") : " .. table.concat(missing, ", "))
    print("Lance `lua tools\\gen_flavor.lua " .. name .. " -fetch` pour les commandes curl.")
end
