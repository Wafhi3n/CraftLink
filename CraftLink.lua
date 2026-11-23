-- CraftLink.lua — socle de l'addon : table d'addon, réglages, SavedVariables, garde contre un ancien
-- Crafting Order, commande /craftlink (spec docs/specs/addon-partage.md, A8 à A11).
--
-- Chargé APRÈS la locale, AVANT les modules. Les SavedVariables sont prêtes sur l'ADDON_LOADED de CET
-- addon ; tout le reste attend PLAYER_LOGIN, quand TOUS les addons sont chargés : sans dépendance
-- déclarée, l'ordre de chargement de CraftLink et de Crafting Order n'est pas garanti, et la garde doit
-- voir les deux.
--
-- Silence au chat (A10) : CraftLink n'écrit qu'en réponse à /craftlink, plus une seule ligne, une fois
-- par compte, quand la garde le met en pause.
local ADDON, NS = ...
local L = NS.L

NS.VERSION = "0.1.0"   -- = ## Version du .toc ; scripts\bump_version.ps1 -Addon CraftLink la tient égale
_G.CraftLink = NS

-- global : le joueur a demandé le canal global (/craftlink global, A11). Par défaut, la guilde et les amis.
NS.DEFAULTS = {
    schemaVer = 1,
    global = false,
}

local function CopyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            CopyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function NS:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffCraftLink|r " .. tostring(msg))
end

function NS:Printf(fmt, ...)
    self:Print(string.format(fmt, ...))
end

-- ------------------------------------------------------------------ la garde (A8)
-- Un Crafting Order d'avant la découpe tient encore son propre annuaire, branché sur la même
-- bibliothèque : deux annuaires y répondraient chacun (deux PONG, deux annonces). Tant qu'il est là,
-- CraftLink se tait et le laisse faire. Un Crafting Order d'après la découpe le dira lui-même
-- (`sharesViaCraftLink`) : il lira l'annuaire de CraftLink au lieu de tenir le sien.
function NS:OldCraftingOrder()
    local coc = _G.CraftingOrderClassic
    return type(coc) == "table" and type(coc.Directory) == "table" and not coc.sharesViaCraftLink
end

function NS:CheckGuard()
    self.paused = self:OldCraftingOrder() or nil
    if self.paused and self.db and not self.db.guardNoticeShown then
        self.db.guardNoticeShown = true
        self:Print(L["en pause : Crafting Order partage déjà tes recettes. CraftLink prendra le relais quand Crafting Order sera à jour."])
    end
    return self.paused
end

-- ------------------------------------------------------------------ l'état et le canal global
function NS:CountArtisans()
    local roster = self.Directory and self.Directory.roster
    local n = 0
    for _ in pairs(roster or {}) do n = n + 1 end
    return n
end

function NS:Status()
    if self.paused then
        return L["en pause : Crafting Order partage déjà tes recettes. CraftLink prendra le relais quand Crafting Order sera à jour."]
    end
    local global = self.db and self.db.global
    return string.format(L["partage actif, %d artisan(s) connu(s) ; canal global : %s"], self:CountArtisans(),
        global and L["rejoint"] or L["pas rejoint (/craftlink global pour le rejoindre)"])
end

-- Le canal global ne se rejoint que sur la demande du joueur, et c'est retenu (A11). Le branchement
-- réseau (NS.ApplyGlobal) vient avec les modules du partage ; en pause, c'est Crafting Order qui mène.
function NS:SetGlobal(on)
    self.db.global = on and true or false
    if not self.paused and self.ApplyGlobal then self:ApplyGlobal(self.db.global) end
end

function NS:Slash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(%S*)")
    if cmd == "" then
        self:Print(self:Status())
    elseif cmd == "global" and (arg == "" or arg == "on") then
        self:SetGlobal(true)
        self:Print(self.paused and self:Status() or L["canal global rejoint."])
    elseif cmd == "global" and arg == "off" then
        self:SetGlobal(false)
        self:Print(self.paused and self:Status() or L["canal global quitté."])
    else
        self:Printf(L["version %s. Commandes : /craftlink (état), /craftlink global, /craftlink global off"], self.VERSION)
    end
end

SLASH_CRAFTLINK1 = "/craftlink"
SlashCmdList["CRAFTLINK"] = function(msg) NS:Slash(msg) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        CraftLinkDB = CraftLinkDB or {}
        CopyDefaults(CraftLinkDB, NS.DEFAULTS)
        NS.db = CraftLinkDB
    elseif event == "PLAYER_LOGIN" then
        if not NS:CheckGuard() and NS.Start then NS:Start() end
    end
end)
