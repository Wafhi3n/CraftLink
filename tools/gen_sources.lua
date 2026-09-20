---@diagnostic disable: undefined-global
-- tools/gen_sources.lua — Ajoute la NATURE DE LA SOURCE aux Data/<flavor>/*.lua :
--   recipeSource : spellID -> "vendor" | "drop" | "quest"
--
-- POURQUOI. « Où j'obtiens ce plan ? » ne venait jusqu'ici que de MTSL, un addon Classic Era qui
-- n'est plus maintenu et qui n'existe pas sur Forever. Trois fonctionnalités en dépendaient : le
-- mode Manquantes, les icônes de source de la liste de recettes, et les « plans à acheter » du
-- Plan de route. Les mêmes pages Wowhead qui nous donnent déjà les recettes portent l'information
-- — il suffisait de la lire. Aucun fetch supplémentaire : on relit le cache existant.
--
-- LES CODES NE SONT PAS DEVINÉS, ILS SONT ÉTALONNÉS. Wowhead expose `"source":[n,...]` sur chaque
-- ligne d'objet, avec un enum non documenté. Le mapping ci-dessous a été DÉRIVÉ en croisant les
-- pages `classic` avec la base de MTSL (661 objets de vérité terrain, 2026-09-19) :
--   code 2  -> butin    289/319 d'accord      code 16 -> butin    50/50
--   code 4  -> quête     65/66                code 21 -> butin    20/20
--   code 5  -> vendeur  306/310
-- La seule nature qu'on ne sépare pas est la RÉPUTATION : pour Wowhead un quartier-maître est un
-- vendeur (86 des 310 objets « vendeur » sont en fait derrière une réputation chez MTSL). Perte
-- assumée — « va le voir chez un PNJ » reste vrai.
--
-- CE QU'ON N'ÉMET PAS, ET POURQUOI. Le FORMATEUR ne s'écrit jamais ici. Aucune page ne l'affirme :
-- on ne le déduit que de l'ABSENCE d'objet-recette, et une absence a deux causes indiscernables —
-- la recette s'apprend au formateur, ou Wowhead ne la connaît pas ENCORE (pages `forever` : 48 %
-- des objets portent une source contre 93 % en `classic`, le client est obfusqué et le site se
-- remplit par observation). Une donnée générée ne doit contenir que des FAITS ; l'inférence
-- « aucun objet connu, donc probablement le formateur » appartient au fournisseur runtime, qui
-- peut la nuancer et la dire au joueur. Écrire "trainer" ici figerait une supposition en donnée.
--
-- SECONDE TABLE, `recipeOrigin` : QUI est derrière le plan, et où. Wowhead attache un `sourcemore`
-- aux lignes d'objet ; les entrées `"t":1` sont des PNJ (`ti` = son id, `n` = son nom anglais, `z` =
-- l'AreaID du jeu) et les `"t":5` des quêtes (`ti` = son id, pas de zone). On stocke l'AreaID et
-- JAMAIS le nom de zone : `C_Map.GetAreaInfo` le rend LOCALISÉ par le client, sur toutes les
-- saveurs. Le nom, lui, n'a aucune API de résolution par id -- il est stocké en anglais, faute de
-- mieux, et c'est la seule chaîne figée ici.
--
-- ⚠️ UNE SEULE TABLE, ET SON SENS VIENT DE `recipeSource`. Le même champ désigne le MARCHAND sur un
-- plan vendu, la CRÉATURE QUI LE LÂCHE sur un plan qui tombe, et la QUÊTE sur un plan de quête.
-- Longtemps on ne gardait que le premier cas, au motif qu'une créature « n'est pas un endroit où
-- aller l'acheter » -- vrai, mais c'est quand même la réponse à « où je vais le chercher ? », et
-- s'en priver laissait 422 recettes de butin avec le seul mot « Butin » pour tout viatique.
-- Trois tables jumelles obligeraient chaque appelant à les interroger dans le bon ordre ; une table
-- plus la nature déjà stockée ne laisse aucune combinaison à inventer.
-- Couverture mesurée sur `forever` : 184 marchands, 133 créatures, 46 quêtes.
--
-- JOINTURE objet -> sort : le bloc `taughtBy` DU FICHIER DATA, pas une re-déduction par nom.
-- gen_flavor.lua l'a déjà calculé et désambiguïsé ; le refaire autrement, c'est se préparer deux
-- vérités qui divergent.
--
-- IDEMPOTENT : bloc sentinellisé `-- >>> gen_sources.lua`, remplacé à chaque relance ; coexiste
-- avec les blocs gen_skill_colors / gen_metadata (chaque outil ne touche que SES sentinelles).
-- NE TOUCHE JAMAIS `recipes` : la dataVersion reste intacte (check_dataversion.lua).
-- ⚠️ gen_flavor.lua RÉÉCRIT les fichiers de zéro : relancer cet outil APRÈS lui (refresh_flavor.ps1).
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   lua tools\gen_sources.lua            # Vanilla (cache tools\wh\classic_*.html)
--   lua tools\gen_sources.lua Camelot    # pages forever/
--   lua tools\gen_sources.lua Camelot -check   # ne rien écrire, juste mesurer la couverture

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local WH_DIR    = [[tools\wh\]]

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

-- Code Wowhead -> nature. Table étalonnée (cf. en-tête) : tout code absent d'ici est IGNORÉ, il ne
-- devient jamais "unknown" stocké — une nature qu'on n'a pas mesurée ne s'écrit pas.
local KIND = { [2] = "drop", [16] = "drop", [21] = "drop", [4] = "quest", [5] = "vendor" }

-- Ordre de PRÉFÉRENCE quand un objet a plusieurs sources (« [2,5,21] » = tombe ET se vend).
-- Copié sur MTSL:SourceKind, pour que les deux fournisseurs racontent la même histoire : on
-- annonce d'abord ce sur quoi le joueur peut AGIR tout de suite.
local PREF = { "vendor", "drop", "quest" }

local MARK_OPEN  = "    -- >>> gen_sources.lua"
local MARK_CLOSE = "    -- <<< gen_sources.lua"

local function readFile(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local function writeFile(p, c)
    local f = assert(io.open(p, "wb")); f:write(c); f:close()
end

-- `taughtBy` du fichier data : itemID -> spellID.
local function taughtBySet(content)
    local block = content:match("taughtBy%s*=%s*(%b{})")
    if not block then return {}, 0 end
    local out, n = {}, 0
    for item, spell in block:gmatch("%[(%d+)%]%s*=%s*(%d+)") do
        out[tonumber(item)] = tonumber(spell); n = n + 1
    end
    return out, n
end

-- Lignes de Listview à ACCOLADES ÉQUILIBRÉES. Les autres outils découpent sur `[^{}]-`, ce qui
-- suffit tant qu'une ligne n'imbrique rien — mais `"sourcemore":[{...}]` imbrique, et un découpage
-- naïf tronque la ligne AVANT son champ `source`. Symptôme mesuré le 2026-09-19 : 168 objets vus
-- au lieu de 172 en Enchantement, et des sources perdues en silence sur les lignes les plus riches.
local function balancedRows(html, needle)
    local out, pos = {}, 1
    while true do
        local hit = html:find(needle, pos, true)
        if not hit then return out end
        local s = hit
        while s > 1 and html:sub(s, s) ~= "{" do s = s - 1 end
        local depth, i = 0, s
        while i <= #html do
            local c = html:sub(i, i)
            if c == "{" then depth = depth + 1
            elseif c == "}" then
                depth = depth - 1
                if depth == 0 then out[#out + 1] = html:sub(s, i); break end
            end
            i = i + 1
        end
        pos = hit + #needle
    end
end

-- Première entrée de type `t` du `sourcemore` d'une ligne : id, AreaID (absent sur une quête), nom
-- anglais. nil s'il n'y en a pas. Deux types servent : `1` (PNJ -- marchand OU créature qui lâche le
-- plan, c'est la MÊME forme) et `5` (quête). `t:3` (conteneur, objet du décor) n'est pas un
-- interlocuteur : on n'en fait rien.
--
-- ⚠️ ON N'EN GARDE QU'UNE, la première. Wowhead en liste parfois dix (un plan que lâchent tous les
-- bandits d'une zone) ; les dix ne tiendraient dans aucune infobulle et ne diraient pas mieux où
-- aller. C'est un EXEMPLE, et la vue doit le présenter comme tel -- jamais comme le seul endroit.
local function parseSourceMore(row, t)
    local sm = row:match('"sourcemore":(%b[])')
    if not sm then return nil end
    for entry in sm:gmatch("%b{}") do
        if entry:match('"t":(%d+)') == t then
            local ti = tonumber(entry:match('"ti":(%d+)'))
            local n  = entry:match('"n":"([^"]*)"')
            if ti and n then return ti, tonumber(entry:match('"z":(%d+)')), n end
        end
    end
    return nil
end

-- Objets-recette de la page : itemID -> nature retenue. `nSeen` compte les lignes vues,
-- `nNoSrc` celles sans aucun champ `source` (Wowhead ne sait pas encore) — la différence entre
-- les deux est la mesure de fraîcheur de la page, et elle doit rester VISIBLE.
local function parseItemKinds(html)
    local out, origin, nSeen, nNoSrc = {}, {}, 0, 0
    for _, row in ipairs(balancedRows(html, '"classs":9')) do
        nSeen = nSeen + 1
        local id  = tonumber(row:match('"id":(%d+)'))
        local src = row:match('"source":%[([%d,]+)%]')
        if not src then nNoSrc = nNoSrc + 1
        elseif id then
            local got = {}
            for code in src:gmatch("%d+") do
                local k = KIND[tonumber(code)]
                if k then got[k] = true end
            end
            for _, k in ipairs(PREF) do
                if got[k] then out[id] = k; break end
            end
            -- Le `sourcemore` se lit SELON la nature retenue : marchand sur un plan vendu, créature
            -- sur un plan qui tombe (même forme `t:1`), quête sur un plan de quête (`t:5`).
            local kind = out[id]
            if kind == "vendor" or kind == "drop" then
                local ti, z, n = parseSourceMore(row, "1")
                if ti then origin[id] = { ti, z, n } end
            elseif kind == "quest" then
                local ti, _, n = parseSourceMore(row, "5")
                if ti then origin[id] = { ti, nil, n } end
            end
        end
    end
    return out, nSeen, nNoSrc, origin
end

-- Bloc sentinellisé + compteurs par nature. Restreint aux recettes que le fichier connaît : un
-- objet dont le sort n'est pas dans `taughtBy` n'a rien à faire ici.
local function renderUnit(kinds, taught, sourceNote, origin)
    local rows, count = {}, { vendor = 0, drop = 0, quest = 0 }
    local named, orig = { vendor = 0, drop = 0, quest = 0 }, {}
    for itemID, kind in pairs(kinds) do
        local sid = taught[itemID]
        if sid then
            rows[#rows + 1] = { sid, kind }; count[kind] = count[kind] + 1
            local v = origin and origin[itemID]
            if v then orig[#orig + 1] = { sid, v[1], v[2], v[3] }; named[kind] = named[kind] + 1 end
        end
    end
    table.sort(rows, function(a, b) return a[1] < b[1] end)
    table.sort(orig, function(a, b) return a[1] < b[1] end)
    local out = { MARK_OPEN .. " (généré — " .. sourceNote .. " ; ne pas éditer à la main)" }
    out[#out + 1] = "    -- où s'obtient le PLAN : [spellID] = \"vendor\" | \"drop\" | \"quest\""
    out[#out + 1] = "    -- (le formateur ne s'écrit pas : il se DÉDUIT de l'absence d'objet-recette)"
    out[#out + 1] = "    recipeSource = {"
    for _, r in ipairs(rows) do
        out[#out + 1] = string.format("        [%d] = %q,", r[1], r[2])
    end
    out[#out + 1] = "    },"
    -- QUI est derrière le plan : [spellID] = { id, areaID, "nom anglais" }. Le SENS du triplet
    -- vient de `recipeSource` ci-dessus : marchand, créature qui le lâche, ou quête (areaID nil).
    -- La zone se résout au runtime (C_Map.GetAreaInfo) ; areaID nil = aucune zone connue.
    out[#out + 1] = "    recipeOrigin = {"
    for _, v in ipairs(orig) do
        out[#out + 1] = string.format("        [%d] = { %d, %s, %q },", v[1], v[2],
            v[3] and tostring(v[3]) or "nil", v[4])
    end
    out[#out + 1] = "    },"
    out[#out + 1] = MARK_CLOSE
    return table.concat(out, "\n"), #rows, count, named
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
local flavor, check = "Vanilla", false
for i = 1, #(arg or {}) do
    if arg[i] == "-check" then check = true elseif arg[i] then flavor = arg[i] end
end
local cfg = FLAVORS[flavor] or error("saveur inconnue : " .. tostring(flavor))

-- `nVendor/nDrop/nQuest` = les sources qui portent en plus un NOM. L'écart avec `vendor/drop/quest`
-- est la vraie mesure d'utilité : une nature sans nom ne dit au joueur ni où aller ni qui voir.
local tot = { vendor = 0, drop = 0, quest = 0, noItem = 0, noSrc = 0,
              nVendor = 0, nDrop = 0, nQuest = 0 }

for _, prof in ipairs(cfg.profs) do
    local path     = DATA_ROOT .. flavor .. [[\]] .. prof .. ".lua"
    local content  = readFile(path)
    local htmlPath = WH_DIR .. cfg.domain .. "_" .. prof .. ".html"
    local html     = readFile(htmlPath)
    if not content then print("SKIP " .. prof .. " (fichier data absent : " .. path .. ")")
    elseif not html then print("SKIP " .. prof .. " (cache " .. htmlPath .. " manquant)")
    else
        local taught, nTaught = taughtBySet(content)
        local kinds, nSeen, nNoSrc, origin = parseItemKinds(html)
        local unit, n, count, named = renderUnit(kinds, taught, "Wowhead " .. cfg.domain, origin)
        if not check then writeFile(path, upsertUnit(content, unit)) end
        for k in pairs(count) do tot[k] = tot[k] + count[k] end
        tot.noItem = tot.noItem + (nTaught - n)
        tot.noSrc  = tot.noSrc + nNoSrc
        tot.nVendor, tot.nDrop = tot.nVendor + named.vendor, tot.nDrop + named.drop
        tot.nQuest = tot.nQuest + named.quest
        print(string.format("%-16s objets=%-4d sans-source=%-4d | vendeur=%d/%d butin=%d/%d quete=%d/%d -> %d sorts",
            prof, nSeen, nNoSrc, named.vendor, count.vendor, named.drop, count.drop,
            named.quest, count.quest, n))
    end
end

print(string.format("%s (%s) : %d vendeur, %d butin, %d quete -- dont %d, %d et %d avec un NOM. %d objets-recette sans source connue%s.",
    check and "Mesure" or "Terminé", flavor, tot.vendor, tot.drop, tot.quest,
    tot.nVendor, tot.nDrop, tot.nQuest, tot.noSrc, check and " (rien écrit)" or ""))
print("Rappel : une recette sans objet-recette n'est PAS écrite ici — le fournisseur runtime en")
print("déduit le formateur, et c'est lui qui doit dire au joueur que c'est une déduction.")
