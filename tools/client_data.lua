-- tools/client_data.lua — les TABLES DU CLIENT de jeu (db2), servies par wago.tools, comme seconde
-- source des données de métier. Module PUR (aucune E/S) : tests/test_client_data.lua le charge tel quel.
--
-- POURQUOI : depuis le 2026-10-16, un pare-feu anti-robot (AWS WAF) refuse nos requêtes vers
-- wowhead.com (403) — la boucle refresh_flavor.ps1 ne télécharge plus rien, et on ne le contourne pas.
-- wago.tools publie, build par build, les tables du client Forever lui-même. Mesuré le 2026-11-07 sur
-- le build 1.60.1.70862 contre nos données (Wowhead du 2026-10-03) :
--   - objet produit : 2049 recettes renseignées des deux côtés, 2049 identiques ; 253 trous comblables ;
--   - réactifs : 0 différence ;
--   - seuils jaune/gris (TrivialSkillLineRankLow/High) : ce sont ceux dont Wowhead tire ses couleurs
--     (cf. wantedColors) ; ils créent les lignes que la page n'a pas, et CORRIGENT celles qui les
--     contredisent (cf. fillColors : vu en jeu le 2026-11-07, la fenêtre du métier suit le client).
--
-- CE QUE CES TABLES NE DONNENT JAMAIS, et que ce module refuse donc d'écrire :
--   - `recipes` : SkillLineAbility garde des lignes MORTES (les six potions de soin parties de l'Alchimie
--     pour les Premiers soins y sont encore) et les sorts de RANG du métier. Les y prendre ramènerait des
--     recettes fantômes, commandables — le défaut même que la saveur complète existe pour empêcher.
--   - `learnedAt` : MinSkillLineRank vaut 1 pour une recette de formateur ; le niveau requis n'est pas là.
--   - l'ORANGE des couleurs : il n'est pas dans la table ; c'est le niveau d'apprentissage (cf. wantedColors).
--
-- RÈGLE : le client COMBLE, il ne remplace jamais (même règle que la récolte en jeu, cf. observed.lua).
--   comble   : Wowhead se tait, le client parle      -> on écrit la valeur du client
--   confirme : les deux disent la même chose          -> rien de neuf
--   conflit  : les deux se contredisent               -> on garde Wowhead, et le conflit s'imprime
-- SEULE EXCEPTION, les couleurs d'une recette au niveau d'apprentissage connu :
--   corrige  : la ligne de Wowhead contredit le client -> le client calé sur ce niveau la remplace

local M = {}

-- ------------------------------------------------------------------
-- CSV (RFC 4180 : champ entre guillemets, "" pour un guillemet, virgule ou saut de ligne dedans)
-- ------------------------------------------------------------------

-- Un champ entre guillemets à partir de i (sur le guillemet ouvrant) : valeur, position suivante.
local function quoted(text, i)
    local buf, j = {}, i + 1
    while true do
        local q = text:find('"', j, true)
        if not q then error("CSV : guillemet non fermé (position " .. i .. ")") end
        buf[#buf + 1] = text:sub(j, q - 1)
        if text:sub(q + 1, q + 1) == '"' then
            buf[#buf + 1] = '"'; j = q + 2
        else
            return table.concat(buf), q + 1
        end
    end
end

-- Texte CSV -> liste de lignes, chaque ligne une liste de champs (chaînes).
function M.parseCSV(text)
    local rows, row, i, n = {}, {}, 1, #text
    while i <= n do
        local value
        if text:sub(i, i) == '"' then
            value, i = quoted(text, i)
        else
            local e = text:find("[,\r\n]", i) or (n + 1)
            value, i = text:sub(i, e - 1), e
        end
        row[#row + 1] = value
        local d = text:sub(i, i)
        if d == "," then
            i = i + 1
        else
            rows[#rows + 1] = row; row = {}
            if d == "\r" then i = i + 1 end
            if text:sub(i, i) == "\n" then i = i + 1 end
        end
    end
    return rows
end

-- Texte CSV avec en-tête -> liste d'enregistrements { [colonne] = chaîne }.
function M.records(text)
    local rows = M.parseCSV(text)
    local head, out = rows[1] or {}, {}
    for r = 2, #rows do
        local rec = {}
        for k, name in ipairs(head) do rec[name] = rows[r][k] end
        out[#out + 1] = rec
    end
    return out
end

-- ------------------------------------------------------------------
-- Extraction : trois tables du client -> { produces, reagents, trivial } par spellID
-- ------------------------------------------------------------------

local CREATE_ITEM = "24"   -- SpellEffect.Effect : SPELL_EFFECT_CREATE_ITEM

-- Sorts des lignes de compétence voulues, et leurs seuils jaune/gris quand ils ont un sens.
local function skillSpells(sla, wanted, out)
    local spells = {}
    for _, r in ipairs(sla) do
        if wanted[tonumber(r.SkillLine)] then
            local sid = tonumber(r.Spell)
            local lo, hi = tonumber(r.TrivialSkillLineRankLow), tonumber(r.TrivialSkillLineRankHigh)
            if sid then
                spells[sid] = true
                if hi and lo and hi > 0 and lo >= 0 and lo <= hi then out.trivial[sid] = { lo, hi } end
            end
        end
    end
    return spells
end

-- Objet créé : l'effet CREATE_ITEM de plus petit indice, difficulté 0.
local function createdItems(effects, spells, out)
    local bestIdx = {}
    for _, r in ipairs(effects) do
        local sid = tonumber(r.SpellID)
        if sid and spells[sid] and r.Effect == CREATE_ITEM and tonumber(r.DifficultyID) == 0 then
            local item, idx = tonumber(r.EffectItemType), tonumber(r.EffectIndex) or 0
            if item and item > 0 and (bestIdx[sid] == nil or idx < bestIdx[sid]) then
                bestIdx[sid] = idx; out.produces[sid] = item
            end
        end
    end
end

-- Réactifs, dans l'ordre de la table (le même que Wowhead, mesuré). Première ligne par sort.
local function reagentLists(reags, spells, out)
    for _, r in ipairs(reags) do
        local sid = tonumber(r.SpellID)
        if sid and spells[sid] and not out.reagents[sid] then
            local list = {}
            for k = 0, 7 do
                local item, qty = tonumber(r["Reagent_" .. k]), tonumber(r["ReagentCount_" .. k])
                if item and item > 0 and qty and qty > 0 then list[#list + 1] = { item, qty } end
            end
            if #list > 0 then out.reagents[sid] = list end
        end
    end
end

-- tables = { SkillLineAbility = recs, SpellEffect = recs, SpellReagents = recs } ; skillLines = { id, ... }
function M.extract(tables, skillLines)
    local wanted = {}
    for _, id in ipairs(skillLines) do wanted[tonumber(id)] = true end
    local out = { produces = {}, reagents = {}, trivial = {} }
    local spells = skillSpells(tables.SkillLineAbility or {}, wanted, out)
    createdItems(tables.SpellEffect or {}, spells, out)
    reagentLists(tables.SpellReagents or {}, spells, out)
    return out
end

-- ------------------------------------------------------------------
-- Rendu du fichier curé (tools/Curated/client_<Saveur>.lua, commité : il vit sur les DEUX postes)
-- ------------------------------------------------------------------

local function sortedKeys(t)
    local k = {}; for id in pairs(t) do k[#k + 1] = id end; table.sort(k); return k
end

local function renderBlock(out, name, t, fmt)
    out[#out + 1] = "    " .. name .. " = {"
    for _, sid in ipairs(sortedKeys(t)) do out[#out + 1] = "        [" .. sid .. "] = " .. fmt(t[sid]) .. "," end
    out[#out + 1] = "    },"
end

-- meta = { flavor, build, skills = { id, ... } }
function M.render(data, meta)
    local out = {
        "-- tools/Curated/client_" .. meta.flavor .. ".lua — tables du CLIENT de jeu, build " .. meta.build .. ".",
        "-- GÉNÉRÉ par tools/import_client.lua (via tools/fetch_client.ps1) depuis wago.tools. NE PAS ÉDITER.",
        "-- Lu par gen_flavor.lua (objet produit, réactifs) et gen_skill_colors.lua (seuils jaune/gris) :",
        "-- il COMBLE les trous de Wowhead, ne les remplace jamais (cf. tools/client_data.lua).",
        "return {",
        string.format("    build = %q,", meta.build),
        "    skillLines = { " .. table.concat(meta.skills, ", ") .. " },",
    }
    renderBlock(out, "produces", data.produces, function(v) return tostring(v) end)
    renderBlock(out, "reagents", data.reagents, function(v)
        local parts = {}
        for _, r in ipairs(v) do parts[#parts + 1] = string.format("{%d,%d}", r[1], r[2]) end
        return "{ " .. table.concat(parts, ", ") .. " }"
    end)
    renderBlock(out, "trivial", data.trivial, function(v) return string.format("{ %d, %d }", v[1], v[2]) end)
    out[#out + 1] = "}"
    return table.concat(out, "\n") .. "\n"
end

-- ------------------------------------------------------------------
-- Comblement
-- ------------------------------------------------------------------

-- stat = M.newStat() ; stat[champ] = { comble, confirme, conflit, corrige } ;
-- stat.conflicts = { {champ, sid, wowhead, client, nature} }, nature = "conflit" (gardé) | "corrige"
function M.newStat()
    return { conflicts = {} }
end

local function bump(stat, field, kind)
    stat[field] = stat[field] or { comble = 0, confirme = 0, conflit = 0, corrige = 0 }
    stat[field][kind] = stat[field][kind] + 1
end

local function sameReagents(a, b)
    if #a ~= #b then return false end
    local qty = {}
    for _, r in ipairs(a) do qty[r[1]] = r[2] end
    for _, r in ipairs(b) do if qty[r[1]] ~= r[2] then return false end end
    return true
end

local function copyList(v)
    local c = {}
    for i, r in ipairs(v) do c[i] = { r[1], r[2] } end
    return c
end

local function fillField(e, field, v, stat, sid, same, copy)
    if v == nil then return end
    if e[field] == nil then
        e[field] = copy(v); bump(stat, field, "comble")
    elseif same(e[field], v) then
        bump(stat, field, "confirme")
    else
        bump(stat, field, "conflit")
        stat.conflicts[#stat.conflicts + 1] = { field, sid, e[field], v, "conflit" }
    end
end

-- recipes = parseAll de gen_flavor : { [spellID] = { produces=, reagents=, ... } }, complété EN PLACE.
-- Ne crée jamais de recette : seules celles de la page Wowhead sont regardées.
function M.fillRecipes(recipes, data, stat)
    if not data then return end
    local same = function(a, b) return a == b end
    local id = function(v) return v end
    for sid, e in pairs(recipes) do
        fillField(e, "produces", data.produces and data.produces[sid], stat, sid, same, id)
        fillField(e, "reagents", data.reagents and data.reagents[sid], stat, sid, sameReagents, copyList)
    end
end

-- Seuils { orange, jaune, vert, gris } d'après le client et le niveau d'apprentissage L. C'est la règle
-- de Wowhead lui-même, retrouvée le 2026-11-07 sur nos 2481 lignes : jaune = TrivialLow, vert = milieu
-- jaune-gris arrondi par défaut, gris = TrivialHigh, chacun RAMENÉ à L quand la recette s'apprend
-- au-dessus (orange = L). Une recette apprise à 265 dont le client dit jaune à 260 est jaune dès 265 ;
-- apprise à 250 avec un gris client à 235, elle est grise dès 250 et ne rapporte rien.
local function wantedColors(t, L)
    local lo, hi = t[1], t[2]
    local mid = math.floor((lo + hi) / 2)
    return { L, math.max(lo, L), math.max(mid, L), math.max(hi, L) }
end

-- Une ligne de Wowhead face au client : "confirme" ou "conflit". Un ZÉRO de Wowhead n'est PAS un trou :
-- il dit qu'une couleur n'existe pas pour cette recette (le calage sur L l'a écrasée), et COC le lit
-- déjà juste au-dessus du niveau requis. On ne le compare donc pas. L'ORANGE ne se juge que si le
-- niveau d'apprentissage est connu (`hasL`) : la fenêtre « à apprendre » de COC exige rang >= orange,
-- un orange au-dessus du niveau du jeu y cache la recette (2664 : apprise à 65, proposée à 90).
local function judgeColors(c, want, hasL)
    for k = hasL and 1 or 2, 4 do
        if c[k] ~= 0 and c[k] ~= want[k] then return "conflit" end
    end
    return "confirme"
end

-- colors = { [spellID] = { o, j, v, g } } (parseColors de gen_skill_colors) ; recipes = set des recettes
-- du fichier ; learnedAt = { [spellID] = niveau } du même fichier (relevé en jeu compris).
-- Une recette SANS ligne Wowhead en reçoit une. Une ligne Wowhead qui CONTREDIT le client est
-- remplacée par le client calé sur le niveau, si ce niveau est connu (sinon le conflit reste listé).
-- POURQUOI le client gagne ici : la ligne de Wowhead, ce sont les MÊMES seuils calés sur SON niveau,
-- et Forever enseigne beaucoup de recettes plus bas (souvent de 25) ; ses seuils datent aussi du
-- 2026-10-03. Vu en jeu le 2026-11-07, Forge à 94 : Silver Rod (7818) GRIS, comme le dit le client
-- (gris 85), là où la ligne Wowhead (gris 100) faisait croire à COC qu'il rapportait encore.
function M.fillColors(colors, recipes, data, learnedAt, stat)
    if not (data and data.trivial) then return end
    for sid in pairs(recipes) do
        local t = data.trivial[sid]
        if t and t[2] > 0 then
            local c, L = colors[sid], learnedAt and learnedAt[sid]
            local want = wantedColors(t, L or 0)
            if not c then
                colors[sid] = want; bump(stat, "skillColors", "comble")
            else
                local kind = judgeColors(c, want, L ~= nil)
                if kind == "conflit" and L then
                    kind = "corrige"; colors[sid] = want
                end
                bump(stat, "skillColors", kind)
                if kind ~= "confirme" then
                    stat.conflicts[#stat.conflicts + 1] = { "skillColors", sid, c, want, kind }
                end
            end
        end
    end
end

-- Fichier curé chargé, ou nil s'il n'existe pas (saveur sans tables du client : rien ne change).
function M.load(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    f:close()
    local ok, t = pcall(dofile, path)
    if ok and type(t) == "table" then return t end
    error("fichier curé illisible : " .. path .. " (" .. tostring(t) .. ")")
end

-- Une ligne de bilan par champ, pour les sorties des générateurs.
function M.summary(stat, build)
    local lines = {}
    for _, field in ipairs({ "produces", "reagents", "skillColors" }) do
        local s = stat[field]
        if s then
            lines[#lines + 1] = string.format("  %-11s comble=%d confirme=%d conflit=%d%s", field, s.comble,
                s.confirme, s.conflit, s.corrige > 0 and (" corrige=" .. s.corrige) or "")
        end
    end
    if #lines == 0 then return nil end
    return "Tables du client (build " .. tostring(build) .. ") :\n" .. table.concat(lines, "\n")
end

return M
