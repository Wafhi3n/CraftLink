-- CraftLink_Directory_Room.lua — la salle de découverte : le canal global rejoint pour SE PRÉSENTER, pas
-- pour transporter. Copié de Directory_Room.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
--
-- Pourquoi (2026-09-29) : sans canal général, on chuchote aux joueurs qu'on connaît (amis, guilde) ; un
-- porteur de l'addon qui n'est dans aucun de ces cercles n'est jamais atteint. Le banc des constats a
-- prouvé qu'un message d'addon passe DANS une salle de canal custom. Sur Forever, CraftLinkNet est
-- découpé en salles (2026-09-27) : on n'y fait plus passer de données, mais on peut y dire bonjour.
--
-- Mécanique (CraftLink, FANOUT_REV 3) : le canal est rejoint (garde anti-/1, caché des fenêtres) ; à
-- chaque arrivée, un HI avec mes métiers part sur la salle (portée « room ») ; les présents me répondent
-- en whisper (Dir:OnHello, branche canal : à moi seul), et je les connais. « À tous » reste en whisper.
--
-- Différences avec COC (A11) : la salle est FERMÉE par défaut, ouverte seulement par /craftlink global
-- (CraftLinkDB.global) ; aucun avis au chat en y entrant, /craftlink le dit ; le rappel d'arrivée n'est
-- posé auprès de la bibliothèque qu'au démarrage (Dir:_WireRoom), jamais au chargement du fichier : en
-- pause, il remplacerait celui d'un ancien COC (la bibliothèque n'en garde qu'un).

local _, NS = ...
NS = NS or _G.CraftLink
local Dir = NS.Directory

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)

function Dir:RoomEnabled() return (NS.db and NS.db.global) == true end

-- Arrivée dans la salle : bonjour, métiers compris, à tous les présents.
function Dir:OnRoomJoined()
    if not CraftLink then return end
    CraftLink:Send((self._HelloPayload and self:_HelloPayload()) or "HI", "room")
    self._roomHelloAt = (GetTime and GetTime()) or 0
end

-- Un nouveau bonjour sur la salle, sur un geste du joueur. Même plancher que l'ancienne balise texte
-- (CraftLink REV 16) ; le bonjour d'arrivée compte. Rend vrai s'il est parti.
local ROOM_HELLO_MIN = 30   -- s

function Dir:RoomHello()
    if not (CraftLink and CraftLink.RoomJoined and CraftLink:RoomJoined()) then return false end
    local t = (GetTime and GetTime()) or 0
    if self._roomHelloAt and t - self._roomHelloAt < ROOM_HELLO_MIN then return false end
    self._roomHelloAt = t
    CraftLink:Send((self._HelloPayload and self:_HelloPayload()) or "HI", "room")
    return true
end

-- Ouvre ou ferme la salle, sans rien dire (la commande /craftlink global parle, pas nous).
function Dir:SetRoom(on)
    if not NS.db then return end
    NS.db.global = on and true or false
    if CraftLink and CraftLink.SetDiscovery then CraftLink:SetDiscovery(on and true or false) end
    Dir:_Changed()
end

-- Appelé par Dir:Start, donc jamais en pause.
function Dir:_WireRoom()
    if CraftLink and CraftLink.OnRoomJoined then CraftLink:OnRoomJoined(function() Dir:OnRoomJoined() end) end
end
