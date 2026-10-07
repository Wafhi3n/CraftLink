-- CraftLink-1.0 — Fanout : la portée « global » quand il n'y a PAS de canal.
--
-- Pourquoi : sur WoW: Forever, un canal custom est MORCELÉ en salles, une par royaume sous le méga-serveur
-- (prouvé le 2026-09-27 : deux joueurs côte à côte, même camp, même couche, ne s'entendaient pas dans
-- CraftLinkNet ; leurs whispers, eux, passaient. Clé mesurée le 2026-10-07 : le royaume, attribué au
-- COMPTE, lisible par GetRealmID()). Le produit coupe donc le canal (SetAutoJoin(false)) et désigne ses
-- pairs (SetPeerSource) : « à tous » devient un whisper par pair en ligne. Aucun appelant ne change —
-- une douzaine d'appels émettent « global », les rerouter un par un en aurait oublié un.
--
-- Ce que ce fichier possède :
--   * le fanout (plafond MAX_PEERS, jamais vers soi) ;
--   * l'anti-doublon des whispers : Orders:Broadcast vise déjà les artisans concernés, puis « tous »,
--     puis le texte — trois chemins vers le même joueur ;
--   * la lecture du code rendu par SendAddonMessage : débit dépassé → le message repasse en tête ;
--     cible hors ligne → le produit est prévenu (c'est la présence que donnait le canal) ;
--   * la mise en route sans canal (réseau « prêt », départ d'une salle restée d'avant).
-- Spec : CraftingOrderClassic/docs/specs/communaute-sans-canal.md

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber, même règle que Transport : BUMP à chaque évolution, et resync de TOUS les hôtes.
local FANOUT_REV = 4   -- 4 : _FixSlot1 (rendre le /1) ; 3 : salle de découverte ; 2 : tout refus du jeu est tracé
if (lib._fanoutRev or 0) >= FANOUT_REV then return end
lib._fanoutRev = FANOUT_REV

local CHANNEL_NAME  = "CraftLinkNet"   -- même défaut que Transport (SetGlobalChannel le remplace)
local MAX_PEERS     = 40   -- whispers par message « à tous » ; au-delà, ce transport ne suffit plus
local DEDUP_WINDOW  = 2    -- s : même message vers la même cible → une seule fois
local READY_DELAY   = 3    -- s : laisse le produit brancher ses rappels avant de déclarer le réseau prêt
local THROTTLE_WAIT = 1    -- s : pause de la file quand le serveur signale un débit dépassé
local MAX_TRIES     = 5    -- essais d'un message refusé pour débit, avant abandon tracé

-- Codes de SendAddonMessage (Enum.SendAddonMessageResult, ChatConstantsDocumentation de Forever). Sur
-- Classic Era l'appel rend autre chose (booléen ou rien) : aucune égalité ne tient, rien ne se déclenche.
local RES = (Enum and Enum.SendAddonMessageResult) or {}
local RES_THROTTLE = RES.AddonMessageThrottle or 3
local RES_LOCKDOWN = RES.AddOnMessageLockdown or 11   -- verrouillage d'instance : refusé, sans reprise utile
local RES_OFFLINE  = RES.TargetOffline or 12
local RES_SUCCESS  = RES.Success or 0
local RES_NAME = {}                                    -- code -> nom, pour une trace lisible
for name, code in pairs(RES) do RES_NAME[code] = name end

lib._recentSends = lib._recentSends or {}   -- [cible \0 message] = instant d'enfilage
lib._lastWhisper = lib._lastWhisper or {}   -- [cible] = instant du dernier whisper parti

local function now() return (GetTime and GetTime()) or 0 end
local function trace(cat, msg) if lib._trace then pcall(lib._trace, cat, msg) end end
-- Valeur SECRÈTE sous le verrou du chat (CraftLink_Sender, chargé avant nous) ; sans lui, rien n'est secret.
local function unreadable(...) return lib._Unreadable ~= nil and lib._Unreadable(...) end

-- fn() rend { [nom] = true } : les pairs que le produit sait EN LIGNE avec l'addon.
function lib:SetPeerSource(fn) self._peerSource = fn end
-- fn(nom) : un envoi vers ce joueur a répondu « cible hors ligne ».
function lib:OnPeerOffline(fn) self._peerOfflineCb = fn end

-- "channel" | "whisper" | nil (pas encore prêt) — pour le statut du produit. La salle de découverte ne
-- change pas le mode : « à tous » y reste en whisper.
function lib:NetworkMode()
    if self._channelJoined and self._autoJoin ~= false then return "channel" end
    if self._offlineReady then return "whisper" end
    return nil
end

-- L'addon a-t-il écrit à ce joueur il y a moins de `window` s ? Le produit reconnaît ainsi SON whisper
-- derrière un « Aucun joueur nommé X » du serveur, pour l'avaler et éteindre X.
function lib:WhisperedRecently(name, window)
    local t = name and self._lastWhisper[name]
    return t ~= nil and (now() - t) < (window or 15)
end

-- ------------------------------------------------------------------
-- Anti-doublon des whispers
-- ------------------------------------------------------------------
-- Par INSTANT D'ENFILAGE, pas par présence dans la file : le premier exemplaire est souvent déjà parti
-- (file vide → envoi immédiat) quand le deuxième arrive. Tout récepteur déduplique déjà (id d'ordre,
-- throttle d'annonce) : le même message pour la même cible en moins de 2 s n'apporte jamais rien.
local function purgeRecent(t)
    local n = 0
    for k, at in pairs(lib._recentSends) do
        if t - at >= DEDUP_WINDOW then lib._recentSends[k] = nil else n = n + 1 end
    end
    lib._recentCount = n
end

function lib:_IsDuplicate(payload, target)
    if not target then return false end
    local t, key = now(), target .. "\0" .. payload
    local at = self._recentSends[key]
    if at and t - at < DEDUP_WINDOW then return true end
    self._recentSends[key] = t
    self._recentCount = (self._recentCount or 0) + 1
    if self._recentCount > 200 then purgeRecent(t) end
    return false
end

-- ------------------------------------------------------------------
-- Fanout : « à tous » sans canal
-- ------------------------------------------------------------------
-- Rend le nombre de whispers demandés. Personne en ligne (au login) → 0, et c'est normal : le contact
-- s'établit par la découverte dirigée du produit (amis, guilde, cercle), qui ajoute ses pairs au fil
-- des réponses. Au-delà du plafond, ce sont toujours les mêmes que `pairs` laisse de côté : c'est
-- tracé, et c'est le signal que la communauté a dépassé ce que ce transport sait porter.
function lib:_FanoutGlobal(payload)
    if not (payload and payload ~= "" and self._peerSource) then return 0 end
    local ok, peers = pcall(self._peerSource)
    if not ok or type(peers) ~= "table" then return 0 end
    local sent, left = 0, 0
    for name in pairs(peers) do
        if name ~= self._me then
            if sent < MAX_PEERS then
                sent = sent + 1
                self:Send(payload, "whisper", name)
            else
                left = left + 1
            end
        end
    end
    if left > 0 then
        trace("send", ("fanout plafonné à %d : %d pair(s) laissé(s) de côté"):format(MAX_PEERS, left))
    end
    return sent
end

-- ------------------------------------------------------------------
-- Code rendu par SendAddonMessage
-- ------------------------------------------------------------------
-- Appelé par _Pump après chaque envoi ; rend l'attente avant le suivant (nil = cadence normale).
-- Le débit est la raison d'être de ce retour : un fanout multiplie les whispers, et un message refusé
-- pour débit était PERDU sans que personne le sache.
function lib:_OnSendResult(item, res)
    if item.scope == "whisper" and item.target then self._lastWhisper[item.target] = now() end
    if res == RES_THROTTLE then
        item.tries = (item.tries or 0) + 1
        if item.tries < MAX_TRIES then
            table.insert(self._sendQueue, 1, item)
            trace("send", "débit serveur dépassé → nouvel essai dans " .. THROTTLE_WAIT .. " s")
        else
            trace("send", "débit serveur : abandon après " .. MAX_TRIES .. " essais : " .. item.payload:sub(1, 40))
        end
        return THROTTLE_WAIT
    end
    if res == RES_OFFLINE and item.target then
        trace("send", "cible hors ligne : " .. item.target)
        if self._peerOfflineCb then pcall(self._peerOfflineCb, item.target) end
    elseif res == RES_LOCKDOWN then
        -- Pas de reprise : le verrou dure toute la rencontre, et un message rejoué tard ment (commande
        -- annulée depuis). La trace est la seule preuve qu'un envoi est tombé en instance.
        trace("send", "verrouillage d'instance : message perdu : " .. item.payload:sub(1, 40))
    elseif type(res) == "number" and res ~= RES_SUCCESS then
        -- Tout autre refus. La ligne « [send] » est écrite AVANT l'envoi : sans celle-ci, un message que
        -- le jeu refuse passait pour parti. Vécu : le PING crié de COC, InvalidChatType hors instance sur
        -- Forever, tracé « [send] yell : PING » pendant des semaines (banc des constats C9, 2026-09-29).
        trace("send", ("refusé par le jeu (%s) : %s"):format(RES_NAME[res] or tostring(res), item.payload:sub(1, 40)))
    end
    return nil
end

-- ------------------------------------------------------------------
-- Mise en route sans canal
-- ------------------------------------------------------------------
-- Quitte CraftLinkNet s'il est encore là : un /reload ne fait quitter aucun canal, et le joueur qui
-- vient de mettre l'addon à jour y serait resté (souvent sur le n° 1). Appelé au démarrage et par le
-- chien de garde (8 s), donc aussi quand le canal n'apparaît qu'après le login.
function lib:_LeaveStaleChannel()
    local name = self._channelName or CHANNEL_NAME
    local idx = GetChannelName and GetChannelName(name) or 0
    if type(idx) == "number" and idx > 0 and LeaveChannelByName then
        pcall(LeaveChannelByName, name)
        trace("net", "canal " .. name .. " encore présent → quitté (réseau sans canal)")
    end
end

-- Déclare le réseau prêt SANS canal : IsNetworkReady() devient vrai et les rappels OnNetworkReady
-- (démarrage du produit : annonce, renvoi des commandes, LFW) partent une fois. Différé : au démarrage
-- du transport, le produit n'a pas encore branché tous ses rappels.
function lib:_StartOffline()
    if self._offlineReady or self._offlinePending then return end
    self._offlinePending = true
    local function go()
        lib._offlinePending = nil
        if lib._autoJoin ~= false or lib._offlineReady then return end   -- canal repris entre-temps
        lib._offlineReady = true
        if not lib._discovery then lib:_LeaveStaleChannel() end   -- la salle, elle, reste
        trace("net", "réseau SANS canal : « global » part en whisper vers les pairs en ligne")
        lib:_FireReady()
    end
    if C_Timer and C_Timer.After then C_Timer.After(READY_DELAY, go) else go() end
end

-- ------------------------------------------------------------------
-- Salle de découverte
-- ------------------------------------------------------------------
-- Sur Forever, le canal custom est découpé en salles (2026-09-27) : il ne peut plus porter les données
-- d'un réseau, qui passent en whisper vers les pairs connus. Mais un inconnu, lui, n'est jamais connu.
-- Le banc des constats (2026-09-29) a fermé toutes les autres voies globales (communauté, canaux du jeu,
-- crier) et prouvé que le message d'addon passe DANS une salle. D'où la salle : le canal est rejoint
-- (même garde anti-/1, caché des fenêtres) pour SE PRÉSENTER aux porteurs de la même salle, pas pour
-- transporter. « global » reste en whisper ; seule la portée « room » y écrit. Chaque arrivée prévient
-- le produit (OnRoomJoined), qui y dit bonjour ; les présents répondent en whisper, et deviennent connus.
function lib:SetDiscovery(on)
    self._discovery = (on == true)
    if self._autoJoin ~= false then return end          -- canal plein : la salle n'a pas de sens
    if self._discovery then
        if self._transportStarted then self:JoinNetwork() end
    elseif self._channelJoined then
        self:LeaveNetwork()
    end
end

-- La salle est-elle rejointe (réseau sans canal, découverte active) ?
function lib:RoomJoined()
    return self._autoJoin == false and self._discovery == true and self._channelJoined == true
end

-- Notre canal tient le /1 : on l'échange avec le premier canal du jeu qui suit, sinon taper /1 écrirait
-- dans un canal caché. Relevé du 2026-10-07 : un perso neuf n'avait aucun canal du jeu au bout de 10 s,
-- la salle a pris le /1, et le jeu le lui redonnait à chaque connexion (General en /2). Mesuré le même
-- jour en /run : SwapChatChannelsByChannelIndex(1, 2) met General en 1 et CraftLinkNet en 2. Appelé à
-- l'arrivée et par le chien de garde ; un échange qui échoue n'est pas retenté de la session (trace).
-- Sous le verrou du chat (combat de boss), un nom de canal peut être SECRET : le comparer lèverait toutes
-- les 8 s depuis le chien de garde. On ne touche alors à rien, il repassera après (revue du 2026-10-07).
-- Les couleurs des canaux ne sont pas échangées (le panneau de Blizzard le fait, pas l'API) : cosmétique.
function lib:_FixSlot1()
    if self._channelIndex ~= 1 or self._slot1Failed then return end
    local swap = C_ChatInfo and C_ChatInfo.SwapChatChannelsByChannelIndex
    if not (swap and GetChannelName) then return end
    local mine = self._channelName or CHANNEL_NAME
    for i = 2, 20 do
        local _, other = GetChannelName(i)
        if unreadable(other) then return end
        if other and other ~= "" and other ~= mine then
            local ok = pcall(swap, 1, i)
            local idx = GetChannelName(mine)
            if unreadable(idx) then return end
            idx = tonumber(idx) or 0
            if ok and idx > 1 then
                self._channelIndex = idx
                trace("net", "canal déplacé du /1 au /" .. idx .. " : le /1 rendu à " .. other)
            else
                self._slot1Failed = true
                trace("net", "échange du /1 refusé ou sans effet (" .. tostring(ok) .. ", idx=" .. tostring(idx) .. ")")
            end
            return
        end
    end
end

-- fn() : appelé à chaque arrivée dans la salle (rejoint, ou ré-acquis par le chien de garde).
function lib:OnRoomJoined(fn) self._roomCb = fn end

-- Le bonjour attend ROOM_HELLO_DELAY : relevé du 2026-09-29, après /co channel room off puis on, le client
-- rendait l'index du canal tout de suite (il le croyait encore rejoint) et le bonjour parti dans la
-- seconde a été refusé par le serveur (InvalidChannel). Au login, les essais de résolution faisaient déjà
-- attendre. Si la salle a été quittée entre-temps, pas de bonjour.
local ROOM_HELLO_DELAY = 2

function lib:_RoomReady()
    if self._hideChannel then self._hideChannel() end
    trace("net", "salle de découverte rejointe (idx=" .. tostring(self._channelIndex) .. ") : bonjour aux présents")
    local cb = self._roomCb
    if not cb then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(ROOM_HELLO_DELAY, function() if lib:RoomJoined() then pcall(cb) end end)
    else
        pcall(cb)
    end
end
