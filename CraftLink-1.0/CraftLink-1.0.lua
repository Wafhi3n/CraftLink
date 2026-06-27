-- CraftLink-1.0 — infrastructure partagée des addons de craft Classic (registre + transports).
--
-- Lib EMBARQUÉE (vendored) via LibStub, pas un addon installé séparément : chaque addon
-- (Guild Economy / TradeScanner, Crafting Order - Classic, un futur build TBC) embarque sa
-- copie ; LibStub n'en garde qu'une instance au runtime (la version la plus haute gagne).
-- Source canonique : repo CraftLink ; synchronisée dans Addon/Libs/ par sync-libs.ps1.
--
-- Périmètre = INFRA GÉNÉRIQUE seulement :
--   * catalogue de recettes canonique (index des positions de bits du registre)
--   * codec hex du registre "recettes connues" (CraftLink_Registry.lua)
--   * versions : dataVersion (compat des index) + protocolVersion (compat du wire)
--   * à venir : transports (canal global / guilde / proximité) — CraftLink_Transport.lua
-- Ce qui touche les GENS (présence, profils, favoris, réputation) N'EST PAS ici : ça vit
-- dans le produit Crafting Order - Classic. CraftLink ne connaît ni l'UI ni le skin de l'hôte.
--
-- Ce fichier = le CATALOGUE + les VERSIONS. Tous les clients d'une même `dataVersion`
-- partagent le mapping position <-> spellID, condition pour que les bitfields échangés
-- (cf. CraftLink_Registry) soient interprétables.

local MAJOR, MINOR = "CraftLink-1.0", 1
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end  -- déjà chargé par un autre addon avec une version >= : on garde l'existante

-- Catalogue : [profCanonical] = { recipes = { spellID, ... } (trié), pos = { [spellID] = index } }
lib.catalog     = lib.catalog or {}
lib.dataVersion = lib.dataVersion or 0

-- protocolVersion : compat du FORMAT FILAIRE (verbes/champs des messages réseau). Distinct de
-- dataVersion (compat des index de bits du catalogue). On le bump quand le wire change de façon
-- incompatible ; deux clients de protocolVersion différentes peuvent refuser/adapter le dialogue.
lib.PROTOCOL_VERSION = 1
function lib:ProtocolVersion() return self.PROTOCOL_VERSION end

-- Empreinte déterministe d'un catalogue : deux clients aux mêmes données la calculent
-- à l'identique. Préférée à un numéro baké (qui pourrait se désynchroniser des données).
-- Repliée sur les noms de métiers triés + leurs recettes (déjà triées) → stable.
local function computeDataVersion(catalog)
    local profs = {}
    for prof in pairs(catalog) do profs[#profs + 1] = prof end
    table.sort(profs)
    local v = 0
    for _, prof in ipairs(profs) do
        for _, id in ipairs(catalog[prof].recipes) do
            v = (v * 31 + id) % 2147483647  -- borné < 2^31 : reste exact en double Lua 5.1
        end
    end
    return v
end

-- Enregistre l'index canonique de recettes. `professions` = { [prof] = { recipes = {spellID,...} } }
-- (l'addon le fournit depuis ses données bakées ; la lib reste agnostique du chargement).
-- La `dataVersion` (empreinte) est calculée ici : deux clients ne comparent leurs bitfields
-- QUE si elle correspond (sinon les positions de bits divergent → lecture faussée).
function lib:SetCatalog(professions)
    self.catalog = {}
    for prof, def in pairs(professions or {}) do
        local recipes = def.recipes
        if type(recipes) == "table" and #recipes > 0 then
            local pos = {}
            for i = 1, #recipes do pos[recipes[i]] = i end
            self.catalog[prof] = { recipes = recipes, pos = pos }
        end
    end
    self.dataVersion = computeDataVersion(self.catalog)
end

function lib:HasCatalog()
    return next(self.catalog) ~= nil
end

function lib:DataVersion()
    return self.dataVersion
end

-- Liste ordonnée des spellID d'un métier (ou nil). NE PAS muter.
function lib:GetRecipes(prof)
    local c = self.catalog[prof]
    return c and c.recipes or nil
end

-- Position de bit (1-based) d'une recette dans son métier, ou nil si inconnue.
function lib:Position(prof, spellID)
    local c = self.catalog[prof]
    return c and c.pos[spellID] or nil
end

-- Nombre de recettes cataloguées pour un métier (0 si inconnu).
function lib:Count(prof)
    local c = self.catalog[prof]
    return c and #c.recipes or 0
end
