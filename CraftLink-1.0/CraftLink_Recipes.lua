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
-- Identité d'une recette = spellID. Sur la cible du projet (WoW: Forever / Camelot, API MAINLINE)
-- ça tombe juste : un `recipeID` de `C_TradeSkillUI` EST un spellID, aucune conversion.
--
-- ⚠️ CIBLE UNIQUE depuis le 2026-09-21 : cette lib ne lit plus QUE la fenêtre métier MAINLINE.
-- Les deux lectures Classic (API TradeSkill par index, API Craft de l'Enchantement) ont été
-- RETIRÉES : l'Era est gelé (COC branche `era`, v1.30.0), COC n'a plus qu'un `.toc` 16001, et
-- TradeScanner n'embarque plus CraftLink depuis la v2.0.0 — plus aucun consommateur Era.
-- Le jour où il en revient un, c'est un BACKEND à rajouter (cf. le patron de
-- CraftingOrderClassic_Craft_Mainline.lua), pas ces branches-ci à ressusciter.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber (même logique que CraftLink_Transport) : ce fichier compagnon re-patche la lib SANS
-- passer par le gate de version de LibStub:NewLibrary (qui ne protège que le fichier principal). Sans
-- ce garde, une copie embarquée plus ANCIENNE chargée APRÈS nous écraserait EncodeKnown/ScanOpenKnown/…
-- On refuse de réécraser une révision >= la nôtre. BUMP à chaque évolution du codec RK (+ resync hôtes).
local RECIPES_REV = 5   -- 5 : `GetAllRecipeIDs` RÉTABLIE (vivante, mesurée) ; 4 : MAINLINE seul
if (lib._recipesRev or 0) >= RECIPES_REV then return end
lib._recipesRev = RECIPES_REV

-- État partagé (singleton) : [profCanonical] = { [spellID] = true }
lib.myKnown = lib.myKnown or {}

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
-- Détection de la fenêtre métier ouverte (MAINLINE)
-- ------------------------------------------------------------------
-- La fenêtre métier de Forever n'a NI `GetTradeSkillLine` NI index de lignes : elle expose
-- `C_TradeSkillUI`, où un recipeID EST un spellID — exactement notre identité de recette.
-- ⚠️ `C_TradeSkillUI` existe AUSSI sur l'Era (vide de l'énumérateur moderne) : le discriminant
-- reste l'ÉNUMÉRATEUR, jamais la simple présence de la table. Sans lui on rend nil, ce qui laisse
-- l'appelant sans avis — au lieu de prétendre qu'une fenêtre est ouverte et de capter du vide.
--
-- `GetAllRecipeIDs` D'ABORD, et ce n'est pas un détail : elle IGNORE les filtres de la fenêtre,
-- alors que `GetFilteredRecipeIDs` respecte la recherche et les catégories du joueur — capter par
-- elle rendrait le registre (et les cooldowns) dépendant de ce qu'il a tapé dans la recherche.
-- Elle est ABSENTE de la doc d'API générée ET du FrameXML, mais VIVANTE sur le client (mesuré par
-- COCProbe le 2026-09-21, build 69913). Elle avait été retirée le même jour sur la foi de la doc —
-- une régression, rétablie : la doc générée ne prouve JAMAIS une absence.
local function modernEnumerator()
    local c = C_TradeSkillUI
    return c and (c.GetAllRecipeIDs or c.GetFilteredRecipeIDs) or nil
end

local function modernProfessionName()
    local c = C_TradeSkillUI
    if not (c and c.GetBaseProfessionInfo and modernEnumerator()) then return nil end
    local ok, info = pcall(c.GetBaseProfessionInfo)
    local name = (ok and type(info) == "table") and info.professionName or nil
    if name == "" then return nil end
    return name
end

-- Recettes APPRISES de la ligne ouverte, en spellID. On EXIGE la preuve (`info.learned == true`,
-- champ vérifié dans Blizzard_ProfessionsCrafting.lua).
--
-- ⚠️ Les DEUX énumérateurs rendent aussi les recettes NON APPRISES : `GetAllRecipeIDs` par nature,
-- et `GetFilteredRecipeIDs` parce que `Professions.SetDefaultFilters` (Blizzard_Professions.lua)
-- pose `SetShowUnlearned(true)` à CHAQUE ouverture de la fenêtre. Le repli qui vivait ici prenait
-- la liste TELLE QUELLE quand `GetRecipeInfo` manquait, sur l'idée fausse que la liste filtrée ne
-- contenait que l'appris : il aurait diffusé des recettes que le perso ne connaît pas. Sans
-- `GetRecipeInfo` on ne peut RIEN prouver — on rend donc un set VIDE. Une donnée manquante vaut
-- toujours mieux qu'une donnée fausse.
local function modernKnownSet()
    local c, set = C_TradeSkillUI, {}
    local enum = modernEnumerator()
    if not (c and enum and c.GetRecipeInfo) then return set end
    local ok, list = pcall(enum)
    if not (ok and type(list) == "table") then return set end
    for _, id in ipairs(list) do
        local ok2, info = pcall(c.GetRecipeInfo, id)
        if ok2 and type(info) == "table" and info.learned == true then set[id] = true end
    end
    return set
end

-- Métier canonique de la fenêtre ouverte, ou nil. Rendait auparavant (prof, isCraft, isModern) :
-- les deux drapeaux départageaient trois backends, il n'en reste qu'un, ils ne portaient plus
-- d'information. Les appelants internes ont suivi ; aucun consommateur externe ne l'appelait.
function lib:OpenProfession()
    local modern = modernProfessionName()
    if not modern then return nil end
    return self:ResolveProfession(modern)
end

-- Lit la fenêtre ouverte → (profCanonical, set{spellID=true}). set vide si rien capté.
function lib:ReadOpenKnown()
    local prof = self:OpenProfession()
    if not prof or self:Count(prof) == 0 then return prof, {} end
    return prof, modernKnownSet()
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
