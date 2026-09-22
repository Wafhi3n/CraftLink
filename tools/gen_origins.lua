---@diagnostic disable: undefined-global
-- tools/gen_origins.lua — QUI est derrière un plan, lu sur la page de l'OBJET.
--
-- POURQUOI UN SECOND OUTIL. `gen_sources.lua` lit la page de MÉTIER : une ligne par objet-recette,
-- avec sa nature (`source`) et, quand la page veut bien, UN nom dans `sourcemore`. Sur Camelot ça
-- laisse 457 recettes avec une nature et personne en face -- « Vendeur », point. Or la page de
-- l'OBJET, elle, porte la liste complète : `sold-by`, `dropped-by`, `reward-from-q`, chacune avec
-- l'identifiant du PNJ, son AreaID, son nom et sa FACTION.
--
-- LA FACTION EST LA VRAIE RAISON, plus encore que la couverture. `sourcemore` rend le premier PNJ
-- venu, sans dire de quel camp il est : pour « Recipe: Gingerbread Cookie » c'est Wulmort
-- Jinglepocket, à Forgefer. Un joueur de la Horde était donc envoyé en territoire allié, avec
-- aplomb. C'est exactement le défaut qui avait déjà été corrigé du temps de MTSL ; la page de métier
-- seule ne permet pas de ne pas le refaire.
--
-- CE QU'ON PREND, ET RIEN DE PLUS :
--   · `sold-by`       -> npcID, AreaID, nom anglais, faction, et le PRIX (`cost`) ;
--   · `dropped-by`    -> npcID, AreaID, nom, et le taux (`count`/`outof`) pour trier les meilleurs ;
--   · `reward-from-q` -> questID, nom, côté. Pas de zone : Wowhead n'en attache pas à une quête.
--
-- ⚠️ `recipeOrigin` APPARTIENT À CET OUTIL, plus à gen_sources. Deux outils qui écrivent la même
-- table finissent par se contredire, et le perdant est toujours celui qui tourne en premier.
-- gen_sources ne garde que `recipeSource` (la NATURE) ; ici c'est QUI. Quand la page d'un objet
-- manque du cache, on retombe sur ce que la page de métier savait : un nom sans faction vaut mieux
-- que rien, et il est marqué comme tel (faction nil = on ne sait pas, pas « neutre »).
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_origins.lua Camelot -urls    # les pages à télécharger (cf. fetch_items.ps1)
--   lua tools\gen_origins.lua Camelot -urls-stale  # les pages MUETTES ou absentes, à reprendre
--   lua tools\gen_origins.lua Camelot -check   # mesurer la couverture, ne rien écrire
--   lua tools\gen_origins.lua Camelot          # écrire recipeOrigin + recipePrice

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local ITEM_DIR  = [[tools\wh\items\]]

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
    Camelot = { domain = "forever", profs = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting",
                "Engineering", "FirstAid", "Leatherworking", "Mining", "Tailoring" } },
}

-- Combien de PNJ on garde PAR CAMP. Deux suffisent : le joueur en veut un, le second couvre le cas
-- où le premier a été déplacé ou tué par un patch. Au-delà on gonfle les fichiers de données pour
-- une infobulle qui n'affiche qu'une ligne.
local KEEP_PER_SIDE = 2
local KEEP_DROPS    = 3   -- triés par taux : les trois meilleurs, pas les trois premiers venus

local MARK_OPEN  = "    -- >>> gen_origins.lua"
local MARK_CLOSE = "    -- <<< gen_origins.lua"

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function writeFile(p, c)
    local f = assert(io.open(p, "wb")); f:write(c); f:close()
end

-- ------------------------------------------------------------------
-- Lecture des fichiers de données
-- ------------------------------------------------------------------

local function block(content, name)
    return content:match(name .. "%s*=%s*(%b{})") or ""
end

-- sort -> objet-recette (inverse de taughtBy, qui va de l'objet vers le sort).
local function itemOf(content)
    local out = {}
    for item, spell in block(content, "taughtBy"):gmatch("%[(%d+)%]%s*=%s*(%d+)") do
        out[tonumber(spell)] = tonumber(item)
    end
    return out
end

-- Tous les sorts du fichier, objet-recette ou non : c'est sur eux qu'on travaille.
local function allRecipes(content)
    local out = {}
    for id in block(content, "recipes"):gmatch("%d+") do out[#out + 1] = tonumber(id) end
    return out
end

local function kinds(content)
    local out = {}
    for sid, k in block(content, "recipeSource"):gmatch("%[(%d+)%]%s*=%s*\"(%w+)\"") do
        out[tonumber(sid)] = k
    end
    return out
end

-- Le repli : ce que la page de MÉTIER savait déjà (un PNJ, sans faction). Lu dans le bloc que
-- gen_sources écrivait avant que cette table ne change de propriétaire -- il peut donc être absent.
local function legacyOrigin(content)
    local out = {}
    for sid, body in block(content, "recipeOrigin"):gmatch("%[(%d+)%]%s*=%s*(%b{})") do
        local id, area, name = body:match("{%s*(%d+)%s*,%s*([%d]*n?i?l?)%s*,%s*\"([^\"]*)\"")
        if id then out[tonumber(sid)] = { tonumber(id), tonumber(area), name } end
    end
    return out
end

-- Les parseurs de pages vivent a part (tools/wh_pages.lua) : ils ne savent rien de nos fichiers
-- de donnees, et gen_origins lit desormais TROIS sortes de pages -- objet, sort, PNJ.
local WH = dofile("tools/wh_pages.lua")

-- ------------------------------------------------------------------
-- Choix des entrées gardées
-- ------------------------------------------------------------------

-- Au plus KEEP_PER_SIDE par CAMP, dans l'ordre de la page. Garder les N premiers tout court
-- renverrait les deux factions chez les mêmes PNJ alliés quand la page les liste d'abord.
local function keepBothSides(list)
    local seen, out = { A = 0, H = 0, N = 0 }, {}
    for _, e in ipairs(list) do
        local bucket = e[4] or "N"
        if seen[bucket] < KEEP_PER_SIDE then
            seen[bucket] = seen[bucket] + 1
            out[#out + 1] = e
        end
    end
    return out
end

-- Ce qu'on retient pour UNE recette. Rend `liste, prix, nature`.
--
-- ⚠️ LA NATURE PEUT VENIR D'ICI, et c'est le point. La page de MÉTIER laisse 933 objets-recette
-- sans champ `source` sur Camelot -- mais leur propre page porte souvent l'onglet qui répond
-- (mesuré sur « Recipe: Venomous Smoothie » : `sold-by` présent, `"source":[5]`, alors que la page
-- de métier se taisait). On ne demandait jamais ces pages-là : il fallait une nature pour décider
-- d'aller la chercher, et la nature était justement ce qui manquait. Boucle fermée, trou permanent.
--
-- Quand `recipeSource` sait, il commande (ses codes sont ÉTALONNÉS). Quand il se tait, on sonde les
-- onglets dans l'ordre de ce sur quoi le joueur peut agir tout de suite : acheter, puis tuer, puis
-- faire une quête.
local function fromItem(kind, html)
    if kind == "vendor" or (not kind and #WH.rows(html, "sold-by") > 0) then
        local list, price = WH.soldBy(html)
        if #list > 0 or kind then return keepBothSides(list), price, "vendor" end
    end
    if kind == "drop" or (not kind and #WH.rows(html, "dropped-by") > 0) then
        local list, cut = WH.droppedBy(html), {}
        for i = 1, math.min(#list, KEEP_DROPS) do cut[i] = list[i] end
        if #cut > 0 or kind then return cut, nil, "drop" end
    end
    if kind == "quest" or (not kind and #WH.rows(html, "reward-from-q") > 0) then
        local list = keepBothSides(WH.quests(html))
        if #list > 0 or kind then return list, nil, "quest" end
    end
    return {}, nil, nil
end

-- LA PAGE DE SORT, pour les recettes SANS objet -- le seau entier du « Formateur ? ». Un plan de
-- formateur ne laisse aucun objet, donc aucune page d'objet : on en a conclu à tort que Wowhead ne
-- le savait pas. Il le sait, ailleurs (`taught-by-npc`), et c'est un FAIT, plus une déduction.
local function fromSpell(html)
    local list = keepBothSides(WH.trainers(html))
    if #list == 0 then return {}, nil, nil end
    return list, nil, "trainer"
end

-- CE QU'ON A VU EN JEU (tools/Curated/observed_<Saveur>.lua, tenu par import_observed.ps1). Il ne
-- sert QUE là où Wowhead se tait : une personne sur un serveur de bêta ne réécrit pas ce que des
-- milliers d'observations ont établi. Rend `liste, prix, nature, conflit`.
--
-- ⚠️ LA NATURE DOIT CONCORDER. Au runtime `recipeSource` fait foi et `kind` ne sert que quand il
-- se tait (lib:RecipeOriginKind) : un marchand vu, écrit sous une nature « drop » étalonnée, serait
-- présenté comme une créature à tuer. Dans ce cas on n'écrit RIEN et on le dit -- à un humain de
-- trancher entre la page de métier et ce qu'il a vu.
local function observedPrice(obs, itemID)
    local best
    for _, e in ipairs((itemID and obs.vendor[itemID]) or {}) do
        if e[5] and (not best or e[5] < best) then best = e[5] end
    end
    return best
end

-- `observed` marque l'entrée VUE en jeu (non rendu) : elle seule peut recevoir la zone ou le camp
-- que Wowhead donne pour le même PNJ ailleurs -- une entrée Wowhead sans camp, elle, dit « neutre ».
local function copyEntries(list)
    local out = {}
    for i, e in ipairs(list) do out[i] = { e[1], e[2], e[3], e[4], observed = true } end
    return out
end

-- Ce que Wowhead dit d'un PNJ AILLEURS dans le métier (zone, camp) complète son entrée VUE en jeu,
-- et elle seule : une entrée Wowhead sans camp dit « neutre », pas « inconnu ». Les QUÊTES sont
-- exclues des deux côtés : leurs identifiants recoupent ceux des PNJ -- la quête 2763 « The Art of
-- the Imbue » a hérité de la zone du PNJ 2763 au premier essai.
local function fillObserved(origins, kind, pageArea)
    local function each(fn)
        for sid, list in pairs(origins) do
            if kind[sid] ~= "quest" and list.kind ~= "quest" then
                for _, e in ipairs(list) do fn(e) end
            end
        end
    end
    local known = {}
    each(function(e)
        if e.observed then return end
        local k = known[e[1]] or {}
        k.area, k.side = k.area or e[2], k.side or e[4]
        known[e[1]] = k
    end)
    each(function(e)
        if not e.observed then return end
        local k = known[e[1]] or {}
        e[2] = e[2] or k.area or pageArea[e[1]]
        e[4] = e[4] or k.side
    end)
end

local function fromObserved(obs, sid, itemID, k)
    local seenT = obs.trainer[sid]
    if seenT and #seenT > 0 then
        if not k then return keepBothSides(copyEntries(seenT)), nil, "trainer" end
        return {}, nil, nil, "formateur vu en jeu, la page de metier dit " .. k
    end
    local seenV = itemID and obs.vendor[itemID]
    if seenV and #seenV > 0 then
        if k and k ~= "vendor" then return {}, nil, nil, "marchand vu en jeu, la page de metier dit " .. k end
        return keepBothSides(copyEntries(seenV)), observedPrice(obs, itemID), "vendor"
    end
    return {}, nil, nil
end

-- ------------------------------------------------------------------
-- Rendu
-- ------------------------------------------------------------------

-- La nature est portée par la LISTE elle-même (`kind = "vendor"`), pas par une seconde table.
-- Elle est inséparable de l'indice qui l'a produite -- c'est l'onglet de la page qui a répondu --
-- et deux tables de nature finiraient par se contredire, comme l'ont fait les deux tables d'origine.
local function renderEntry(e)
    return string.format("{ %d, %s, %q, %s }", e[1],
        e[2] and tostring(e[2]) or "nil", e[3], e[4] and string.format("%q", e[4]) or "nil")
end

local function renderUnit(origins, prices, spots, note)
    local sids = {}
    for sid in pairs(origins) do sids[#sids + 1] = sid end
    table.sort(sids)
    local out = { MARK_OPEN .. " (généré — " .. note .. " ; ne pas éditer à la main)" }
    out[#out + 1] = "    -- QUI est derrière le plan : [spellID] = { { id, areaID, \"nom\", faction }, ... }"
    out[#out + 1] = "    -- faction \"A\"/\"H\" = ce camp SEULEMENT ; nil = les deux, ou inconnue."
    out[#out + 1] = "    -- Le SENS des entrées vient de `recipeSource` ; `kind =` ne figure que quand"
    out[#out + 1] = "    -- la nature a été DÉDUITE de la page d'objet, faute de réponse de la page de métier."
    out[#out + 1] = "    recipeOrigin = {"
    for _, sid in ipairs(sids) do
        local rec, parts = origins[sid], {}
        for _, e in ipairs(rec) do parts[#parts + 1] = renderEntry(e) end
        -- `kind` n'est écrit que s'il a été DÉDUIT de la page : quand `recipeSource` le donne déjà,
        -- le répéter créerait deux vérités à tenir d'accord.
        local k = rec.kind and string.format("kind = %q, ", rec.kind) or ""
        out[#out + 1] = string.format("        [%d] = { %s%s },", sid, k, table.concat(parts, ", "))
    end
    out[#out + 1] = "    },"
    local psids = {}
    for sid in pairs(prices) do psids[#psids + 1] = sid end
    table.sort(psids)
    out[#out + 1] = "    -- PRIX du plan chez son marchand, en cuivre. Absent = inconnu, JAMAIS zéro."
    out[#out + 1] = "    recipePrice = {"
    for _, sid in ipairs(psids) do
        out[#out + 1] = string.format("        [%d] = %d,", sid, prices[sid])
    end
    out[#out + 1] = "    },"
    -- OU SE TIENT CHAQUE PNJ : [npcID] = { uiMapID, x, y } en 0-100. Cle par PNJ et pas par
    -- recette -- un marchand sert des dizaines de plans -- et `uiMapID` est l'identifiant de
    -- carte du JEU, donc le repere se pose sans passer par la resolution d'un nom de zone.
    out[#out + 1] = "    npcSpot = {"
    local nids = {}
    for id in pairs(spots) do nids[#nids + 1] = id end
    table.sort(nids)
    for _, id in ipairs(nids) do
        local sp = spots[id]
        out[#out + 1] = string.format("        [%d] = { %d, %.1f, %.1f },", id, sp[1], sp[2], sp[3])
    end
    out[#out + 1] = "    },"
    out[#out + 1] = MARK_CLOSE
    return table.concat(out, "\n")
end

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

local flavor, mode = "Camelot", nil
for i = 1, #(arg or {}) do
    if arg[i] == "-urls" or arg[i] == "-check" or arg[i] == "-urls-spells"
        or arg[i] == "-urls-npcs" or arg[i] == "-urls-stale" then mode = arg[i]
    elseif arg[i] then flavor = arg[i] end
end
local cfg = FLAVORS[flavor] or error("saveur inconnue : " .. tostring(flavor))
-- Relu à CHAQUE passe : c'est ce qui fait qu'aucune régénération ne perd ce qu'on a vu en jeu.
local obs = dofile("tools/observed.lua").load([[tools\Curated\observed_]] .. flavor .. ".lua")

local tot = { want = 0, have = 0, named = 0, legacy = 0, price = 0, empty = 0, spot = 0, trainer = 0,
              observed = 0 }
local SPELL_DIR = [[tools\wh\spells\]]
local NPC_DIR   = [[tools\wh\npcs\]]
local urls = (mode or ""):find("^%-urls")

for _, prof in ipairs(cfg.profs) do
    local path    = DATA_ROOT .. flavor .. [[\]] .. prof .. ".lua"
    local content = readFile(path)
    if not content then
        if not urls then print("SKIP " .. prof .. " (fichier data absent)") end
    else
        local items, kind, legacy = itemOf(content), kinds(content), legacyOrigin(content)
        local origins, prices, spots = {}, {}, {}
        local have, named, fromLegacy, empty, nTrainer, nObs = 0, 0, 0, 0, 0, 0
        -- /!\ ON PARCOURT TOUTES LES RECETTES, pas seulement celles qui ont deja une nature ou
        -- un objet. N'aller chercher que les pages des recettes classees fermait la boucle : il
        -- fallait une nature pour decider d'ouvrir la page, et la page etait le seul endroit ou
        -- la trouver. Recette AVEC objet -> sa page d'objet ; SANS objet -> sa page de SORT, la
        -- seule qui nomme les formateurs.
        for _, sid in ipairs(allRecipes(content)) do
            local itemID, k = items[sid], kind[sid]
            local cache = itemID and (ITEM_DIR .. cfg.domain .. "_" .. itemID .. ".html")
                                  or (SPELL_DIR .. cfg.domain .. "_" .. sid .. ".html")
            tot.want = tot.want + 1
            if mode == "-urls" and itemID then
                print(cache .. "\t" .. "https://www.wowhead.com/" .. cfg.domain .. "/item=" .. itemID)
            elseif mode == "-urls-spells" and not itemID then
                print(cache .. "\t" .. "https://www.wowhead.com/" .. cfg.domain .. "/spell=" .. sid)
            elseif mode == "-urls-stale" then
                -- Les pages MUETTES, a reprendre. Une page en cache n'est pas une page a jour :
                -- Wowhead se remplit par observation, et une page vide le 20 cite un formateur le
                -- 22 (mesure sur 1244431). Sans ce mode, fetch_items sautait toute page deja
                -- presente, et le seul autre choix etait -Force sur les 2500.
                local html = readFile(cache)
                local list = {}
                if html then
                    if itemID then list = fromItem(k, html) else list = fromSpell(html) end
                end
                if #list == 0 then
                    local what = itemID and ("item=" .. itemID) or ("spell=" .. sid)
                    print(cache .. "\t" .. "https://www.wowhead.com/" .. cfg.domain .. "/" .. what)
                end
            elseif (not urls) or mode == "-urls-npcs" then
                -- `-urls-npcs` doit LIRE les pages deja prises pour savoir QUELS PNJ citer :
                -- la liste des PNJ n'existe nulle part ailleurs que dans les origines.
                local html = readFile(cache)
                if html then
                    have = have + 1
                    local list, price, found
                    if itemID then list, price, found = fromItem(k, html)
                    else list, price, found = fromSpell(html) end
                    if #list > 0 then
                        -- La nature n'est notee QUE si elle a ete DEDUITE de la page : quand
                        -- `recipeSource` la donne deja, la repeter creerait deux verites a tenir.
                        if not k then list.kind = found end
                        if found == "trainer" then nTrainer = nTrainer + 1 end
                        origins[sid] = list; named = named + 1
                    else empty = empty + 1 end
                    if price then prices[sid] = price end
                elseif legacy[sid] then
                    origins[sid] = { legacy[sid] }; fromLegacy = fromLegacy + 1
                end
                -- Wowhead s'est tu : ce qu'on a vu en jeu, si la nature concorde.
                if not origins[sid] then
                    local list, price, found, clash = fromObserved(obs, sid, itemID, k)
                    if #list > 0 then
                        if not k then list.kind = found end
                        origins[sid] = list; nObs = nObs + 1
                        if price and not prices[sid] then prices[sid] = price end
                    elseif clash and not urls then
                        print(string.format("  CONFLIT %s %d : %s -- rien ecrit", prof, sid, clash))
                    end
                elseif itemID and not prices[sid] and (k or origins[sid].kind) == "vendor" then
                    prices[sid] = observedPrice(obs, itemID)   -- nil si jamais vu en rayon
                end
            end
        end
        -- Les POSITIONS, une page par PNJ cite : un marchand sert des dizaines de plans, il ne
        -- se telecharge qu'une fois. Les quetes n'ont pas de page de PNJ, on les saute.
        if mode == "-urls-npcs" or not urls then
            local seen, pageArea = {}, {}
            for sid, list in pairs(origins) do
                local isQuest = (kind[sid] == "quest") or (list.kind == "quest")
                if not isQuest then
                    for _, e in ipairs(list) do
                        local id = e[1]
                        if not seen[id] then
                            seen[id] = true
                            local c = NPC_DIR .. cfg.domain .. "_" .. id .. ".html"
                            if mode == "-urls-npcs" then
                                print(c .. "\t" .. "https://www.wowhead.com/" .. cfg.domain .. "/npc=" .. id)
                            else
                                -- Sans AreaID (entrée VUE en jeu), la page ne sait pas quel spawn
                                -- choisir : la relève prime, et la page ne donne que l'AreaID --
                                -- à condition que son spawn soit sur la même carte.
                                local o = obs.spot[id]
                                local h = readFile(c)
                                local sp, area
                                if h then sp, area = WH.spot(h, e[2], o and o[1]) end
                                if o and (not e[2] or not sp) then
                                    if area and sp and sp[1] ~= o[1] then area = nil end
                                    sp = { o[1], o[2], o[3] }
                                end
                                if sp then spots[id] = sp end
                                -- L'AreaID de la page ne sert qu'à un PNJ VU (même carte, vérifié
                                -- ci-dessus) : sans relève, ce serait le premier spawn venu.
                                if o and area then pageArea[id] = area end
                            end
                        end
                    end
                end
            end
            if not urls then fillObserved(origins, kind, pageArea) end
        end
        tot.trainer, tot.observed = tot.trainer + nTrainer, tot.observed + nObs
        for _ in pairs(spots) do tot.spot = tot.spot + 1 end
        if not urls then
            tot.have, tot.named = tot.have + have, tot.named + named
            tot.legacy, tot.empty = tot.legacy + fromLegacy, tot.empty + empty
            for _ in pairs(prices) do tot.price = tot.price + 1 end
            if mode ~= "-check" then writeFile(path, upsertUnit(content, renderUnit(origins,
                prices, spots, "Wowhead " .. cfg.domain .. ", pages objet/sort/PNJ"))) end
            local nSpot = 0; for _ in pairs(spots) do nSpot = nSpot + 1 end
            local nPrice = 0; for _ in pairs(prices) do nPrice = nPrice + 1 end
            print(string.format("%-16s pages=%-4d nommees=%-4d (formateur=%-3d repli=%-3d muettes=%-3d) vues-en-jeu=%-3d prix=%-3d positions=%d",
                prof, have, named, nTrainer, fromLegacy, empty, nObs, nPrice, nSpot))
        end
    end
end

if not urls then
    print(string.format("%s (%s) : %d recettes, %d pages lues -> %d nommees (dont %d formateur), %d repli, %d muettes dont %d comblees par ce qu'on a vu en jeu, %d prix, %d positions%s",
        (mode == "-check") and "Mesure" or "Termine", flavor, tot.want, tot.have, tot.named,
        tot.trainer, tot.legacy, tot.empty, tot.observed, tot.price, tot.spot,
        (mode == "-check") and " (rien ecrit)" or ""))
end
