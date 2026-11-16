---@diagnostic disable: undefined-global
-- tools/sante.lua — BILAN de santé des données d'une saveur, en LECTURE SEULE.
--
-- POURQUOI : l'agent data-keeper (.claude/agents/data-keeper.md de l'outillage) refait le même bilan
-- à chaque passage. Compter des trous à la main dans des tables Lua de deux mille lignes, c'est se
-- tromper ou compter autrement d'une fois sur l'autre. Ici la façon de compter ne bouge pas : un
-- écart entre deux bilans veut dire que les DONNÉES ont changé.
--
-- Ce qu'il dit : le build des tables du client contre les caches et le client installé ; par métier,
-- les recettes sans objet produit (hors enchantements), sans niveau d'apprentissage, sans couleurs,
-- grises dès l'apprentissage (jaune ET vert à 0), à seuils tous égaux {L,L,L,L} ; les sorts que le
-- client connaît et qu'aucune recette de CraftLink ne porte ; les conflits de couleurs de la dernière
-- passe. Ce qu'il ne dit PAS : si une donnée est JUSTE en jeu. Ça, seul le jeu le tranche.
--
-- Il n'écrit rien et ne télécharge rien. Les données sont chargées comme le client les charge
-- (Data/<Saveur>.xml lu, pas recopié), avec un CraftLink factice qui ne fait que ranger les
-- RegisterProfession : la lib n'a rien à dire sur ce que les fichiers déclarent.
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) :
--   ..\tools\elune\bin\lua.exe tools\sante.lua                    # Camelot
--   ..\tools\elune\bin\lua.exe tools\sante.lua Camelot -ids       # + les spellID de chaque catégorie
--   ..\tools\elune\bin\lua.exe tools\sante.lua Camelot -wow "D:\Jeux\World of Warcraft"

local DATA_ROOT = [[CraftLink-1.0\Data\]]
local DB2_DIR   = [[tools\db2\]]
local WOW_ROOT  = [[D:\Jeux\World of Warcraft]]   -- le .build.info est à la racine, pas dans _forever_

local flavor, showIds = "Camelot", false
do
    local i = 1
    while arg[i] do
        local a = arg[i]
        if a == "-ids" then showIds = true
        elseif a == "-wow" then i = i + 1; WOW_ROOT = arg[i] or WOW_ROOT
        elseif a:sub(1, 1) ~= "-" then flavor = a end
        i = i + 1
    end
end

local function readFile(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local s = fh:read("*a"); fh:close()
    return s
end

-- Les fichiers de MÉTIER de la saveur, dans l'ordre du XML (Gathering, Smelting… ne sont pas des
-- métiers enregistrés et restent dehors).
local function loadDefs()
    local xml = readFile(DATA_ROOT .. flavor .. ".xml")
    if not xml then error("Data/" .. flavor .. ".xml introuvable (cwd = CraftLink ?)") end
    local defs, order = {}, {}
    local fake = { RegisterProfession = function(_, name, def) defs[name] = def; order[#order + 1] = name end }
    _G.LibStub = { GetLibrary = function() return fake end }
    for f in xml:gmatch('<Script file="([^"]+)"') do
        if f:find("^" .. flavor .. "\\") then dofile(DATA_ROOT .. f) end
    end
    return defs, order
end

local function toSet(list)
    local s = {}
    for _, v in ipairs(list or {}) do s[v] = true end
    return s
end

local function enchantSet(def)
    local s = {}
    for _, e in ipairs(def.enchants or {}) do s[e.id] = true end
    return s
end

-- Une recette passe dans les catégories dont elle relève ; chaque catégorie garde ses spellID triés.
local CATS = {
    { key = "noProduct", label = "sans objet",  test = function(id, d, ench) return not (d.produces or {})[id] and not ench[id] end },
    { key = "noLearned", label = "sans niveau", test = function(id, d) return (d.learnedAt or {})[id] == nil end },
    { key = "noColors",  label = "sans couleur", test = function(id, d) return (d.skillColors or {})[id] == nil end },
    { key = "greyLearn", label = "grise appr.",  test = function(id, d)
        local c = (d.skillColors or {})[id]
        return c ~= nil and c[2] == 0 and c[3] == 0 end },
    { key = "flat",      label = "{L,L,L,L}",    test = function(id, d)
        local c = (d.skillColors or {})[id]
        return c ~= nil and c[1] > 0 and c[1] == c[2] and c[2] == c[3] and c[3] == c[4] end },
}

local function auditProfession(def)
    local ench, out = enchantSet(def), { n = 0 }
    for _, c in ipairs(CATS) do out[c.key] = {} end
    for _, id in ipairs(def.recipes or {}) do
        out.n = out.n + 1
        for _, c in ipairs(CATS) do
            if c.test(id, def, ench) then table.insert(out[c.key], id) end
        end
    end
    for _, c in ipairs(CATS) do table.sort(out[c.key]) end
    return out
end

local function printTable(defs, order)
    local head = string.format("  %-15s %8s", "métier", "recettes")
    for _, c in ipairs(CATS) do head = head .. string.format(" %12s", c.label) end
    print(head)
    local total, results = { n = 0 }, {}
    for _, c in ipairs(CATS) do total[c.key] = 0 end
    for _, name in ipairs(order) do
        local r = auditProfession(defs[name])
        results[name] = r
        local line = string.format("  %-15s %8d", name, r.n)
        total.n = total.n + r.n
        for _, c in ipairs(CATS) do
            line = line .. string.format(" %12d", #r[c.key])
            total[c.key] = total[c.key] + #r[c.key]
        end
        print(line)
    end
    local line = string.format("  %-15s %8d", "TOTAL", total.n)
    for _, c in ipairs(CATS) do line = line .. string.format(" %12d", total[c.key]) end
    print(line)
    return results
end

local function printIds(order, results)
    for _, c in ipairs(CATS) do
        for _, name in ipairs(order) do
            local ids = results[name][c.key]
            if #ids > 0 then
                print(string.format("  %s / %s (%d) : %s", c.label, name, #ids, table.concat(ids, ", ")))
            end
        end
    end
end

-- Build Forever installé : colonne Version de la ligne du produit wowf (même lecture que
-- scripts\ui_build_check.ps1).
local function installedBuild()
    local info = readFile(WOW_ROOT .. [[\.build.info]])
    if not info then return nil end
    local lines = {}
    for l in info:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
    local iv, ip, col = nil, nil, 0
    for h in (lines[1] or ""):gmatch("[^|]+") do
        col = col + 1
        local name = h:match("^([^!]+)")
        if name == "Version" then iv = col elseif name == "Product" then ip = col end
    end
    if not (iv and ip) then return nil end
    for k = 2, #lines do
        local cells, n = {}, 0
        for cell in (lines[k] .. "|"):gmatch("([^|]*)|") do n = n + 1; cells[n] = cell end
        if cells[ip] == "wowf" then return cells[iv] end
    end
    return nil
end

local function cachedBuilds()
    local out = {}
    local p = io.popen('dir /b /ad "' .. DB2_DIR .. '" 2>nul')
    if p then
        for l in p:lines() do if l:match("^%d") then out[#out + 1] = l end end
        p:close()
    end
    table.sort(out)
    return out
end

local function printBuilds(clientBuild)
    print("Builds")
    print("  tables du client dans les données : " .. (clientBuild or "?") ..
        "  (en-tête de tools/Curated/client_" .. flavor .. ".lua)")
    local cached = cachedBuilds()
    print("  caches tools/db2/                 : " .. (#cached > 0 and table.concat(cached, ", ") or "aucun"))
    local inst = installedBuild()
    print("  client installé (wowf)            : " .. (inst or ("illisible (" .. WOW_ROOT .. "\\.build.info)")))
    if inst and clientBuild and inst ~= clientBuild then
        print("  >> le client installé n'est PAS le build des données : passe de build à prévoir")
    end
end

-- Les sorts que les tables du client portent pour les lignes de métier et qu'aucune recette de la
-- saveur ne contient. Pas des trous à combler d'office : le client garde des lignes mortes (potions
-- de soin parties de l'Alchimie), des sorts de rang, et la ligne Poisons qui n'a pas de fichier.
local function clientOnly(client, defs, order)
    local known = {}
    for _, name in ipairs(order) do
        for id in pairs(toSet(defs[name].recipes)) do known[id] = true end
    end
    local seen, out = {}, {}
    for _, tbl in ipairs({ client.trivial or {}, client.produces or {} }) do
        for id in pairs(tbl) do
            if not known[id] and not seen[id] then seen[id] = true; out[#out + 1] = id end
        end
    end
    table.sort(out)
    return out
end

local function printConflicts()
    local txt = readFile(DB2_DIR .. "conflits_couleurs_" .. flavor .. ".txt")
    if not txt then print("  conflits de couleurs : pas de fichier (aucune passe des tables du client ici)"); return end
    local fixed, open = 0, 0
    for l in txt:gmatch("[^\r\n]+") do
        if l:find("^corrige") then fixed = fixed + 1 elseif l:find("^conflit") then open = open + 1 end
    end
    print(string.format("  conflits de couleurs (dernière passe) : %d corrigées par le client, %d conflits (Wowhead gardé)", fixed, open))
end

local function main()
    local defs, order = loadDefs()
    print("Santé des données CraftLink — saveur " .. flavor .. " (lecture seule)")
    print("")
    local clientSrc = readFile([[tools\Curated\client_]] .. flavor .. ".lua")
    local clientBuild = clientSrc and clientSrc:match("build ([%d%.]+%d)")
    printBuilds(clientBuild)
    print("")
    print("Recettes par métier (« sans objet » exclut les enchantements, qui ne produisent rien)")
    local results = printTable(defs, order)
    print("")
    print("Tables du client")
    if clientSrc then
        local only = clientOnly(dofile([[tools\Curated\client_]] .. flavor .. ".lua"), defs, order)
        print(string.format("  sorts du client absents de CraftLink : %d (lignes mortes, rangs et Poisons compris : à regarder, pas à combler d'office)", #only))
        if showIds and #only > 0 then print("    " .. table.concat(only, ", ")) end
    else
        print("  pas de tools/Curated/client_" .. flavor .. ".lua : saveur sans tables du client")
    end
    printConflicts()
    if showIds then
        print("")
        print("spellID par catégorie")
        printIds(order, results)
    end
end

main()
