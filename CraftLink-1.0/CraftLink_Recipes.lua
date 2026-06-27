-- CraftLink-1.0 — Registre « MES recettes connues » : détection de la fenêtre métier ouverte,
-- capture des spellID réellement appris, état en mémoire + sérialisation, et codec du fil RK.
--
-- C'est le cœur qui rend un addon AUTONOME : il capte tes recettes sans dépendre de l'hôte
-- (Guild Economy / Crafting Order). Comme la lib est un singleton partagé, l'état « mes recettes »
-- (myKnown) vit ICI, en mémoire ; chaque addon le charge/sauvegarde en UNION vers SA propre
-- SavedVariables (LoadMyRecipes/SaveMyRecipes) → pas de conflit si les deux addons coexistent.
--
-- Le roster des AUTRES joueurs (qui sait quoi) est volontairement HORS de ce module : c'est de
-- l'annuaire (people), pas du registre (recipes) — il vivra dans le transport/Directory (étape B).
--
-- Identité d'une recette = spellID. TradeSkill ne donne que l'itemID produit → repli itemToSpell
-- (catalogue). L'Enchantement (API Craft) expose |Henchant:spellID| directement (non capté par
-- craftedItems qui ne matche que |Hitem:|), d'où le scan dédié. Cf. wow-enchanting-craft-api.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- État partagé (singleton) : [profCanonical] = { [spellID] = true }
lib.myKnown = lib.myKnown or {}

local function spellFromLink(link)
    return link and tonumber(link:match("enchant:(%d+)")) or nil
end

-- ------------------------------------------------------------------
-- Persistance (union) vers/depuis la SavedVariables d'un addon hôte
-- ------------------------------------------------------------------
-- UNION jamais retrait : un addon qui charge sa SV enrichit l'état partagé sans rien perdre ;
-- deux addons convergent vers la même union. saved = { [prof] = { [spellID] = true } }.
function lib:LoadMyRecipes(saved)
    if type(saved) ~= "table" then return end
    for prof, set in pairs(saved) do
        if type(set) == "table" then
            local mine = self.myKnown[prof]; if not mine then mine = {}; self.myKnown[prof] = mine end
            for spellID in pairs(set) do mine[spellID] = true end
        end
    end
end

-- Reflète l'état partagé dans la SV de l'hôte (remplace son contenu par l'union courante).
function lib:SaveMyRecipes(saved)
    if type(saved) ~= "table" then return end
    for prof in pairs(saved) do saved[prof] = nil end
    for prof, set in pairs(self.myKnown) do
        local out = {}; for spellID in pairs(set) do out[spellID] = true end
        saved[prof] = out
    end
end

-- ------------------------------------------------------------------
-- Détection de la fenêtre métier ouverte (Craft API vs TradeSkill API)
-- ------------------------------------------------------------------
-- Retourne (profCanonical, isCraft) ou (nil, nil). isCraft = API Craft (Enchantement & co).
function lib:OpenProfession()
    if CraftFrame and CraftFrame:IsShown() then
        local name = (GetCraftDisplaySkillLine and GetCraftDisplaySkillLine())
                  or (GetCraftName and GetCraftName())
        if name and name ~= "" and name ~= "UNKNOWN" then return self:ResolveProfession(name), true end
    end
    if GetTradeSkillLine then
        local name = GetTradeSkillLine()
        if name and name ~= "" and name ~= "UNKNOWN" then return self:ResolveProfession(name), false end
    end
    return nil, nil
end

-- Lit la fenêtre ouverte → (profCanonical, set{spellID=true}). set vide si rien capté.
function lib:ReadOpenKnown()
    local prof, isCraft = self:OpenProfession()
    if not prof or self:Count(prof) == 0 then return prof, {} end
    local set = {}
    if isCraft then
        local n = (GetNumCrafts and GetNumCrafts()) or 0
        for i = 1, n do
            local _, _, ctype = GetCraftInfo(i)
            if ctype ~= "header" then
                local sid = spellFromLink(GetCraftItemLink and GetCraftItemLink(i))
                if sid then set[sid] = true end
            end
        end
    else
        local n   = (GetNumTradeSkills and GetNumTradeSkills()) or 0
        local i2s = self:ItemToSpell(prof) or {}
        for i = 1, n do
            local _, stype = GetTradeSkillInfo(i)
            if stype ~= "header" and stype ~= "subheader" then
                local sid = spellFromLink(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
                if not sid then
                    local link   = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
                    local itemID = link and tonumber(link:match("item:(%d+)"))
                    sid = itemID and i2s[itemID] or nil
                end
                if sid then set[sid] = true end
            end
        end
    end
    return prof, set
end

-- Scan + union dans l'état partagé. Retourne (prof, changed). L'hôte décide quoi faire de
-- `changed` (sauvegarder sa SV, diffuser le RK). Union (jamais retrait) : un scan partiel
-- (liste pas encore peuplée) ne régresse pas.
function lib:ScanOpenKnown()
    local prof, set = self:ReadOpenKnown()
    if not prof or not set or not next(set) then return prof, false end
    local known = self.myKnown[prof]; if not known then known = {}; self.myKnown[prof] = known end
    local changed = false
    for sid in pairs(set) do
        if not known[sid] then known[sid] = true; changed = true end
    end
    return prof, changed
end

-- ------------------------------------------------------------------
-- Requêtes (MOI)
-- ------------------------------------------------------------------
function lib:MyKnownSet(prof)
    return self.myKnown[prof]
end

function lib:MyHex(prof)
    return (self:EncodeKnown(prof, self.myKnown[prof] or {}))
end

function lib:IKnowRecipeBySpell(prof, spellID)
    local k = self.myKnown[prof]
    return k ~= nil and k[spellID] == true
end

-- Pour une commande d'OBJET : connais-je la recette qui produit cet itemID ?
function lib:IKnowRecipeForItem(prof, itemID)
    local i2s = self:ItemToSpell(prof)
    local sid = i2s and i2s[itemID]
    return sid ~= nil and self:IKnowRecipeBySpell(prof, sid)
end

-- Récap : { { prof, known, total }, ... } trié par métier.
function lib:RecipeSummary()
    local out = {}
    for prof, set in pairs(self.myKnown) do
        local n = 0; for _ in pairs(set) do n = n + 1 end
        out[#out + 1] = { prof = prof, known = n, total = self:Count(prof) }
    end
    table.sort(out, function(a, b) return a.prof < b.prof end)
    return out
end

-- Liste des métiers où j'ai au moins une recette captée (pour diffuser tout mon registre).
function lib:MyProfessions()
    local out = {}
    for prof in pairs(self.myKnown) do out[#out + 1] = prof end
    return out
end

-- ------------------------------------------------------------------
-- Fil RK : "RK|prof|hex|dataVersion" (hex = bitfield des recettes connues du métier)
-- ------------------------------------------------------------------
function lib:BuildRK(prof)
    local hex = self:MyHex(prof)
    if not hex or hex == "" then return nil end
    return string.format("RK|%s|%s|%d", prof, hex, self:DataVersion())
end

-- Parse un message RK → (prof, hex, dataVersion) ou nil. Ne stocke rien (l'hôte gère le roster).
function lib:ParseRK(message)
    local prof, hex, dv = (message or ""):match("^RK|([^|]*)|([^|]*)|?(%d*)$")
    if prof and prof ~= "" and hex then return prof, hex, tonumber(dv) or 0 end
    return nil
end
