---@diagnostic disable: undefined-global
-- tools/import_client.lua — tables du client (CSV de wago.tools) -> tools/Curated/client_<Saveur>.lua.
--
-- Lancé par tools/fetch_client.ps1, qui télécharge les CSV et passe les lignes de compétence des métiers
-- (lues dans gen_flavor.lua -urls : une seule liste de métiers, jamais redéclarée ici). Le fichier curé
-- est COMMITÉ : les CSV (plusieurs Mo) restent dans le cache tools/db2/, gitignoré, alors que le fichier
-- curé doit être là sur les deux postes — sinon une régénération sans lui compterait en PERTE chaque
-- objet produit qu'il avait comblé.
--
-- Usage (cwd = CraftLink) :
--   lua tools\import_client.lua Camelot tools\db2\1.60.1.70862 171 164 185 ...

local Client = dofile([[tools\client_data.lua]])

local TABLES = { "SkillLineAbility", "SpellEffect", "SpellReagents" }

local function read(p)
    local f = io.open(p, "rb"); if not f then return nil end
    local c = f:read("*a"); f:close(); return c
end

local flavor, dir = arg[1], arg[2]
if not (flavor and dir) then
    print("usage : lua tools\\import_client.lua <Saveur> <dossier des CSV> <ligne de compétence> ...")
    os.exit(1)
end
local skills = {}
for i = 3, #arg do skills[#skills + 1] = tonumber(arg[i]) end
if #skills == 0 then print("ERREUR : aucune ligne de compétence passée."); os.exit(1) end

local build = dir:gsub("[\\/]+$", ""):match("([^\\/]+)$")
local tables, hotfixed = {}, 0
for _, name in ipairs(TABLES) do
    local text = read(dir .. [[\]] .. name .. ".csv")
    if not text then print("ERREUR : " .. dir .. "\\" .. name .. ".csv absent."); os.exit(1) end
    tables[name] = Client.records(text)
    -- Les hotfixes du serveur (relevés par fetch_client.ps1) passent par-dessus : c'est ce que le jeu
    -- applique. Absents (cache d'avant le 2026-11-11) : la table du build seule, comme avant.
    local hot = read(dir .. [[\]] .. name .. ".hotfixes.csv")
    local note = ""
    if hot then
        local st
        tables[name], st = Client.applyHotfixes(tables[name], Client.records(hot))
        hotfixed = hotfixed + st.replaced + st.added + st.removed
        note = string.format("  (hotfixes : %d remplacées, %d ajoutées, %d retirées)", st.replaced, st.added, st.removed)
    end
    print(string.format("  %-17s %d lignes%s", name, #tables[name], note))
end

local data = Client.extract(tables, skills)
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local out = string.format([[tools\Curated\client_%s.lua]], flavor)
local f = assert(io.open(out, "wb"))
-- Le bilan chiffré reste à l'écran : écrit dans le fichier commité, il bougerait à chaque hotfix d'un
-- sort sans rapport avec les métiers.
f:write(Client.render(data, { flavor = flavor, build = build, skills = skills, hotfixes = hotfixed > 0 }))
f:close()
print(string.format("%s : build %s, objets produits %d, réactifs %d, seuils %d",
    out, build, count(data.produces), count(data.reagents), count(data.trivial)))
