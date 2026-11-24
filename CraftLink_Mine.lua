-- CraftLink_Mine.lua — MES recettes et mes niveaux : ce que CraftingOrderClassic.lua (v1.53.0) faisait
-- pour l'annuaire, repris pour CraftLink seul (spec docs/specs/addon-partage.md, étape 3).
--
-- La fenêtre de métier ouverte est relue (débouncé 0,3 s, les événements de liste spamment pendant un
-- craft en série), l'union va dans la bibliothèque et dans la partition du perso courant de CraftLinkDB,
-- puis l'annuaire rediffuse. Un point de métier gagné rediffuse mes niveaux (throttlé 2 s). Les temps de
-- recharge, eux, restent à COC. Démarré par NS:Start, donc jamais quand la garde a mis CraftLink en pause.

local _, NS = ...
NS = NS or _G.CraftLink
local Mine = {}
NS.Mine = Mine
local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)

-- knownRecipes[« Prénom-Royaume »] : la base est par COMPTE, on ne charge et ne diffuse que la partition
-- du perso courant, sinon les métiers d'un reroll fuiraient dans mon annonce (même découpage que COC).
function Mine:Store()
    local db = NS.db
    if not db then return nil end
    db.knownRecipes = db.knownRecipes or {}
    local me = ((UnitName and UnitName("player")) or "?") .. "-" .. ((GetRealmName and GetRealmName()) or "")
    db.knownRecipes[me] = db.knownRecipes[me] or {}
    return db.knownRecipes[me]
end

function Mine:Load()
    local store = self:Store()
    if CraftLink and store then CraftLink:LoadMyRecipes(store) end
end

-- Union (jamais retrait) : un scan partiel, liste pas encore peuplée, ne fait rien régresser.
function Mine:Scan()
    if not (CraftLink and NS.db) then return end
    local _, changed = CraftLink:ScanOpenKnown()
    if not changed then return end
    local store = self:Store()
    if store then CraftLink:SaveMyRecipes(store) end
    if NS.Directory then NS.Directory:AnnounceThrottled() end
end

-- Une lecture qui casse (un build qui change la fenêtre) ne lève pas devant le joueur, mais ne se tait
-- pas non plus : /craftlink montre la dernière erreur.
local function safeScan()
    local ok, err = pcall(Mine.Scan, Mine)
    if not ok then NS.lastError = tostring(err) end
end

function Mine:ScanSoon()
    if self._scanTimer then return end
    if not (C_Timer and C_Timer.After) then safeScan(); return end
    self._scanTimer = true
    C_Timer.After(0.3, function() Mine._scanTimer = nil; safeScan() end)
end

-- Point de métier gagné, métier appris ou oublié : mes niveaux repartent, une fois par série de 2 s.
function Mine:OnSkillLines()
    local Dir = NS.Directory
    if not (Dir and C_Timer and C_Timer.After) or self._skillTimer then return end
    self._skillTimer = true
    C_Timer.After(2, function() Mine._skillTimer = nil; Dir:CaptureSkills(); Dir:AnnounceSkills() end)
end

function Mine:Start()
    self:Load()
    local f = CreateFrame("Frame")
    for _, ev in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "SKILL_LINES_CHANGED" }) do
        pcall(f.RegisterEvent, f, ev)   -- un événement absent de ce client lève : on passe
    end
    f:SetScript("OnEvent", function(_, event)
        if event == "SKILL_LINES_CHANGED" then Mine:OnSkillLines() else Mine:ScanSoon() end
    end)
end
