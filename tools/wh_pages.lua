---@diagnostic disable: undefined-global
-- tools/wh_pages.lua — LECTURE des pages Wowhead, et rien d'autre.
--
-- Extrait de gen_origins.lua quand celui-ci a dû lire TROIS sortes de pages (objet, sort, PNJ) et
-- s'est approché du plafond anti-monolithe. Le partage n'est pas qu'une question de taille : ces
-- parseurs n'ont aucune idée de nos fichiers de données, et c'est ce qui les rend testables et
-- réutilisables. Ici on lit du HTML ; décider quoi en faire appartient à l'appelant.
--
-- Toutes les fonctions prennent le HTML BRUT d'une page et rendent des tables Lua ordinaires.
--
-- Usage : local WH = dofile("tools/wh_pages.lua")

local WH = {}

-- Les lignes d'une Listview nommée, à accolades ÉQUILIBRÉES : chaque ligne imbrique `modes` et
-- `itemSeasonPhaseData`, un découpage naïf les couperait en plein milieu.
function WH.rows(html, lvid)
    local at = html:find("id: '" .. lvid .. "'", 1, true)
    if not at then return {} end
    local s = html:find("data: [", at, true)
    if not s then return {} end
    local out, i, depth, start = {}, s + 7, 0, nil
    while i <= #html do
        local c = html:sub(i, i)
        if c == "{" then
            if depth == 0 then start = i end
            depth = depth + 1
        elseif c == "}" then
            depth = depth - 1
            if depth == 0 and start then out[#out + 1] = html:sub(start, i); start = nil end
        elseif c == "]" and depth == 0 then
            break
        end
        i = i + 1
    end
    return out
end

-- "A" (Alliance seule) | "H" (Horde seule) | nil (les deux, ou hostile aux deux : une créature).
function WH.side(row)
    local r = row:match('"react":%[([^%]]*)%]')
    if not r then return nil end
    local a, h = r:match("([^,]+),([^,]+)")
    local na, nh = tonumber(a), tonumber(h)
    if na and na > 0 and not nh then return "A" end
    if nh and nh > 0 and not na then return "H" end
    return nil
end

-- `"name":"…"` et pas `"displayName":"…"` : la majuscule de Name suffit à les distinguer, et
-- `"names":[]` ne matche pas non plus (le motif exige le guillemet fermant du champ).
function WH.name(row) return row:match('"name":"([^"]*)"') end

-- Une entrée standard { id, areaID, nom, faction } depuis une ligne de Listview.
local function entry(row)
    local id, nm = tonumber(row:match('"id":(%d+)')), WH.name(row)
    if not (id and nm) then return nil end
    return { id, tonumber(row:match('"location":%[(%d+)')), nm, WH.side(row) }
end

-- PAGE D'OBJET — les marchands qui vendent le plan, plus son PRIX en cuivre.
function WH.soldBy(html)
    local out, price = {}, nil
    for _, row in ipairs(WH.rows(html, "sold-by")) do
        local e = entry(row); if e then out[#out + 1] = e end
        price = price or tonumber(row:match('"cost":%[%[(%d+)'))
    end
    return out, price
end

-- PAGE D'OBJET — les créatures qui lâchent le plan, TRIÉES PAR TAUX décroissant. Wowhead les rend
-- dans l'ordre de sa page ; envoyer le joueur sur la première venue plutôt que sur la plus
-- généreuse serait un conseil au hasard. `count`/`outof` sont le premier couple de la ligne (ceux
-- de `modes` répètent les mêmes valeurs plus loin).
function WH.droppedBy(html)
    local out = {}
    for _, row in ipairs(WH.rows(html, "dropped-by")) do
        local e = entry(row)
        if e then
            local c, o = tonumber(row:match('"count":(%d+)')), tonumber(row:match('"outof":(%d+)'))
            e.rate = (c and o and o > 0) and (c / o) or 0
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b) return a.rate > b.rate end)
    return out
end

-- PAGE D'OBJET — les quêtes qui donnent le plan. `side` 1 = Alliance, 2 = Horde, absent = les deux.
-- AUCUNE zone : Wowhead n'attache pas d'AreaID à une quête, et `category` est un identifiant à lui,
-- pas du jeu. On préfère une zone absente à une zone fausse.
function WH.quests(html)
    local out = {}
    for _, row in ipairs(WH.rows(html, "reward-from-q")) do
        local id, nm = tonumber(row:match('"id":(%d+)')), WH.name(row)
        if id and nm then
            local s = tonumber(row:match('"side":(%d+)'))
            out[#out + 1] = { id, nil, nm, (s == 1 and "A") or (s == 2 and "H") or nil }
        end
    end
    return out
end

-- PAGE DE SORT — LES FORMATEURS. C'est la seule porte : un plan de formateur ne laisse aucun objet,
-- donc aucune page d'objet, et on en a longtemps conclu à tort que Wowhead ne le savait pas. Il le
-- sait, il le dit ailleurs -- `spell=<id>`, onglet `taught-by-npc` (20 formateurs pour le sort 2539).
function WH.trainers(html)
    local out = {}
    for _, row in ipairs(WH.rows(html, "taught-by-npc")) do
        local e = entry(row); if e then out[#out + 1] = e end
    end
    return out
end

-- PAGE DE PNJ — OÙ IL SE TIENT : { uiMapID, x, y } en 0-100, ou nil.
--
-- `g_mapperData` est indexé par AreaID -- celui-là même qu'on stocke déjà dans les origines -- et
-- porte `uiMapId`, l'identifiant de carte du JEU. C'est mieux qu'un nom de zone : le repère se pose
-- sans passer par la résolution par libellé, qui échoue dès que deux noms divergent d'une lettre.
-- On prend les coordonnées de l'aire DEMANDÉE quand elle y est (un PNJ apparaît parfois dans
-- plusieurs zones), sinon la première venue, et la PREMIÈRE de ses positions : un marchand en a
-- souvent trois à quelques pas les unes des autres.
function WH.spot(html, areaID)
    local blob = html:match("var g_mapperData = (%b{})")
    if not blob then return nil end
    local pick
    for area, body in blob:gmatch('"(%d+)":(%b[])') do
        local uiMap = tonumber(body:match('"uiMapId":(%d+)'))
        local x, y = body:match('"coords":%[%[([%d%.%-]+),([%d%.%-]+)%]')
        if uiMap and x and y then
            local cand = { uiMap, tonumber(x), tonumber(y) }
            if tonumber(area) == areaID then return cand end
            pick = pick or cand
        end
    end
    return pick
end

return WH
