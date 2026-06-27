-- CraftLink-1.0 — Helpers métiers : résolution de nom localisé + accès aux données brutes.
--
-- S'appuie sur lib.professions (rempli par les fichiers Data embarqués via RegisterProfession).
-- Déplacé depuis TradeScanner_Data.lua pour rendre la lib self-contained : tout addon hôte
-- (Guild Economy, Crafting Order - Classic) résout les métiers sans logique propre.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Cache des alias : [aliasLower] = profCanonical. Invalidé par RegisterProfession (_aliasMap=nil).
local function buildAliasMap(self)
    local map = {}
    for profName, def in pairs(self.professions) do
        map[profName:lower()] = profName
        if def.aliases then
            for _, alias in ipairs(def.aliases) do
                map[alias:lower()] = profName
            end
        end
    end
    self._aliasMap = map
end

-- Résout un nom de métier ouvert ("Enchantement") vers la clé canonique ("Enchanting").
function lib:ResolveProfession(openName)
    if not openName then return nil end
    if not self._aliasMap then buildAliasMap(self) end
    return self._aliasMap[openName:lower()] or openName
end

-- Liste les mats de désenchantement connus pour un métier (clé canonique) -> { [itemID] = name }.
function lib:GetDisenchantMats(profName)
    local out = {}
    local def = self.professions[profName]
    if def and def.disenchant then
        for itemID, name in pairs(def.disenchant) do out[itemID] = name end
    end
    return out
end
