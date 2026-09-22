---@diagnostic disable: undefined-global
-- tools/import_observed.lua — verse la récolte en jeu dans tools/Curated/observed_<Saveur>.lua.
--
-- Lit, pour CHAQUE dossier SavedVariables donné, `COCScout.lua` (marchands, positions, formateurs
-- par PNJ) et `CraftingOrderClassic.lua` (formateurs moissonnés par COC). Fusionne sans jamais
-- rien retirer (cf. tools/observed.lua). N'écrit QUE le fichier curé : c'est gen_origins.lua qui
-- le fait passer dans les données, et le diff git de ce fichier qui sert de relecture.
--
-- Usage (cwd = f:\AddonDevellopement\CraftLink) -- en pratique via import_observed.ps1 :
--   lua tools\import_observed.lua Camelot "<...>\WTF\Account\X\SavedVariables" [autres dossiers]

local OBS = dofile("tools/observed.lua")

local flavor = arg and arg[1]
if not flavor or not arg[2] then
    io.stderr:write("usage: import_observed.lua <Saveur> <dossier SavedVariables> [...]\n")
    os.exit(1)
end
local target = [[tools\Curated\observed_]] .. flavor .. ".lua"

-- Une SavedVariable est du Lua qui affecte des globales : on l'exécute dans un env à part.
local function loadSV(path, name)
    local chunk = loadfile(path)
    if not chunk then return nil end
    local env = {}
    setfenv(chunk, env)
    local ok = pcall(chunk)
    return ok and env[name] or nil
end

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local obs = OBS.load(target)
local before = { count(obs.trainer), count(obs.vendor), count(obs.spot) }
for i = 2, #arg do
    local dir = arg[i]
    local scout = loadSV(dir .. [[\COCScout.lua]], "COCScoutDB")
    local coc   = loadSV(dir .. [[\CraftingOrderClassic.lua]], "CraftingOrderClassicDB")
    local a = OBS.mergeScout(obs, scout)
    local b = OBS.mergeCoc(obs, coc, scout)
    print(string.format("  %-60s scout=%-4d coc=%d", dir:sub(-60), a, b))
end

local header = table.concat({
    "-- tools/Curated/observed_" .. flavor .. ".lua — ce qu'on a VU en jeu (COCScout + formateurs COC).",
    "-- Tenu par tools/import_observed.ps1 : il AJOUTE, il ne retire jamais. Une ligne fausse se",
    "-- retire À LA MAIN, ici. Relu par gen_origins.lua à chaque passe, où il ne COMBLE que ce que",
    "-- Wowhead tait -- et seulement si la nature concorde (sinon : conflit affiché, rien écrit).",
    "-- Observé sur UN serveur de bêta par UNE personne : relire le diff git avant de commiter.",
}, "\n")
local f = assert(io.open(target, "wb"))
f:write(OBS.render(obs, header))
f:close()
print(string.format("%s : formateurs %d -> %d sorts, marchands %d -> %d plans, positions %d -> %d",
    target, before[1], count(obs.trainer), before[2], count(obs.vendor), before[3], count(obs.spot)))
