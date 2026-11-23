-- CraftLink_Directory_Community.lua — le réseau SANS canal : la glue entre la bibliothèque et l'annuaire.
-- Copié de la 1re partie de Directory_Community.lua de COC v1.53.0 (spec docs/specs/addon-partage.md,
-- étape 3). La suite de ce fichier chez COC (communauté officielle, coupée depuis le 2026-09-29, lien
-- « Rejoindre », libellé de /co status) reste chez COC : elle s'appuie sur ses cercles (Directory_Club).
--
-- Sur Forever, un canal custom est MORCELÉ en salles (prouvé le 2026-09-27) : « à tous » part donc en
-- whisper vers les pairs que DÉSIGNE l'annuaire (Dir.online), et la bibliothèque prévient quand l'un d'eux
-- ne répond plus — la présence que donnait le canal.

local _, NS = ...
NS = NS or _G.CraftLink
local Dir = NS.Directory
local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)

-- Les pairs EN LIGNE : ceux qui ont répondu en CraftLink dans la session, moi exclu. C'est l'audience
-- exacte du canal quand il marchait — les joueurs de l'addon qu'on entend.
function Dir:OnlinePeers()
    local out, m = {}, NS.Api.PlayerName()
    for name in pairs(self.online or {}) do
        if name ~= m then out[name] = true end
    end
    return out
end

-- Un pair ne répond plus (départ du canal, whisper refusé, jeu qui le dit déconnecté) : il sort de
-- l'annuaire EN LIGNE. L'hôte éteint ce qui en dépend chez lui (COC : sa « recherche de travail »,
-- Dir.OnMarkOffline). Rend vrai s'il était en ligne ; l'appelant rafraîchit (OnPresence le fait déjà).
function Dir:MarkOffline(who)
    if not who then return false end
    local was = self.online and self.online[who] == true
    if self.online then self.online[who] = nil end
    if self.OnMarkOffline then self:OnMarkOffline(who) end
    return was
end

-- Branché par Dir:Start AVANT StartTransport : la lib doit connaître ses pairs dès son premier envoi.
function Dir:_WireNoChannel()
    if not (CraftLink and CraftLink.SetPeerSource) then return end
    CraftLink:SetPeerSource(function() return Dir:OnlinePeers() end)
    CraftLink:OnPeerOffline(function(who) if Dir:MarkOffline(who) then Dir:_Changed() end end)
end
