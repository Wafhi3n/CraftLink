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

-- Données brutes par métier, enregistrées par les fichiers Data embarqués (RegisterProfession) :
-- [prof] = { aliases, sellable, disenchant, enchants, recipes, itemToSpell }. Le catalogue (index
-- de bits) en est dérivé paresseusement (EnsureCatalog) → la lib est self-contained, sans hôte.
lib.professions    = lib.professions or {}
lib._catalogDirty  = lib._catalogDirty or false

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
    self._catalogDirty = false  -- catalogue posé explicitement : pas de reconstruction paresseuse
end

-- Enregistre les données brutes d'un métier (appelé par les fichiers Data embarqués). Le
-- catalogue est reconstruit paresseusement au prochain accès (EnsureCatalog). `def` =
-- { aliases, sellable, disenchant, enchants, recipes (triés), itemToSpell }.
function lib:RegisterProfession(name, def)
    self.professions[name] = def
    self._catalogDirty = true
    self._aliasMap = nil      -- invalide le cache d'alias (cf. CraftLink_Professions)
end

-- (Re)construit le catalogue (index de bits) depuis les données enregistrées, si nécessaire.
-- Idempotent ; appelé en tête de chaque accesseur → l'hôte n'a aucun finalize à ordonnancer.
function lib:EnsureCatalog()
    if not self._catalogDirty then return end
    self._catalogDirty = false
    local cat = {}
    for prof, def in pairs(self.professions) do
        local recipes = def.recipes
        if type(recipes) == "table" and #recipes > 0 then
            local pos = {}
            for i = 1, #recipes do pos[recipes[i]] = i end
            cat[prof] = { recipes = recipes, pos = pos }
        end
    end
    self.catalog     = cat
    self.dataVersion = computeDataVersion(cat)
end

-- itemToSpell d'un métier (itemID produit -> spellID) : repli runtime pour le scan TradeSkill.
function lib:ItemToSpell(prof)
    local def = self.professions[prof]
    return def and def.itemToSpell or nil
end

-- Données brutes d'un métier (aliases/sellable/disenchant/enchants/...), ou nil.
function lib:GetProfession(prof)
    return self.professions[prof]
end

-- Objet produit par une recette (spellID -> itemID), ou nil (services/enchantements).
function lib:RecipeProduct(prof, spellID)
    local def = self.professions[prof]
    return def and def.produces and def.produces[spellID] or nil
end

-- Réactifs d'une recette : { {itemID, qty}, ... } ou nil. Noms via ItemName (runtime, localisé).
function lib:RecipeReagents(prof, spellID)
    local def = self.professions[prof]
    return def and def.reagents and def.reagents[spellID] or nil
end

-- Conversions « détruire pour obtenir des composants » (disenchant/milling/prospecting) ou nil.
function lib:Conversions(prof)
    local def = self.professions[prof]
    return def and def.conversions or nil
end

-- Résolution de NOM multilingue : le client localise via GetItemInfo/GetSpellInfo ; repli baké.
function lib:ItemName(itemID, fallback)
    if itemID and GetItemInfo then local n = GetItemInfo(itemID); if n and n ~= "" then return n end end
    return fallback or (itemID and ("item:" .. itemID)) or "?"
end

function lib:RecipeName(spellID, fallback)
    if spellID and GetSpellInfo then local n = GetSpellInfo(spellID); if n and n ~= "" then return n end end
    return fallback or (spellID and ("spell:" .. spellID)) or "?"
end

function lib:HasCatalog()
    self:EnsureCatalog()
    return next(self.catalog) ~= nil
end

function lib:DataVersion()
    self:EnsureCatalog()
    return self.dataVersion
end

-- Liste ordonnée des spellID d'un métier (ou nil). NE PAS muter.
function lib:GetRecipes(prof)
    self:EnsureCatalog()
    local c = self.catalog[prof]
    return c and c.recipes or nil
end

-- Position de bit (1-based) d'une recette dans son métier, ou nil si inconnue.
function lib:Position(prof, spellID)
    self:EnsureCatalog()
    local c = self.catalog[prof]
    return c and c.pos[spellID] or nil
end

-- Nombre de recettes cataloguées pour un métier (0 si inconnu).
function lib:Count(prof)
    self:EnsureCatalog()
    local c = self.catalog[prof]
    return c and #c.recipes or 0
end
