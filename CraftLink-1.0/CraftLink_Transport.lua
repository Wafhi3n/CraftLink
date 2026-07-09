-- CraftLink-1.0 — Transport générique : 4 portées + dispatch par verbe + présence + santé réseau.
--
-- Infrastructure réseau réutilisable (pas spécifique aux recettes) : un addon enregistre des
-- handlers par verbe (`RegisterHandler("RK", fn)`) et émet via `Send(payload, scope[, target])`.
-- Portées :
--   * "global"  : canal CUSTOM dédié (auto-créé via JoinTemporaryChannel, nom "CraftLinkNet").
--                 ⚠️ Testé PTR 2026-06-30 : les canaux SYSTÈME intégrés (General/Trade/Services/
--                 LocalDefense/WorldDefense/LFG/GuildRecruitment) NE RELAIENT PAS le CHAT_MSG_ADDON
--                 côté serveur (le texte normal passe, l'AddonMessage est silencieusement avalée) —
--                 confirmé avec Services : `[send] global` côté A, AUCUN `[recv]` côté B, alors que
--                 le whisper simultané est bien arrivé. Seul un canal CUSTOM (créé par l'addon, pas
--                 un des canaux par défaut du client) relaie réellement le CHAT_MSG_ADDON. D'où le
--                 retour à un canal dédié pour le TRANSPORT — transparence assurée autrement (canal
--                 visible dans la liste, popup d'info one-shot, opt-out).
--   * "guild"   : distribution "GUILD" (+ relais GreenWall à brancher — hardware-event only).
--   * "say"/"yell": proximité (SendAddonMessage "SAY"/"YELL"), limité par la portée.
--   * "whisper" : 1:1 DIRIGÉ vers `target` (SendAddonMessage "WHISPER"). FIABLE sans guilde ni canal
--                 (zéro race au login, zéro portée) → découverte dirigée + ordres ciblés (2 comptes).
--
-- Présence : on N'ENVOIE PAS de heartbeat — l'appartenance au canal EST la présence. Les events
-- CHAT_MSG_CHANNEL_JOIN/_LEAVE du canal sont relayés via `OnPresence(fn)`.
--
-- Santé : JoinTemporaryChannel est async ET le canal peut se perdre (reload, throttle login). Un
-- watchdog ré-résout l'index et rejoint si besoin ; `OnNetworkReady(fn)` se déclenche à chaque
-- (re)acquisition du canal pour que le produit (re)publie son annuaire.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber : la lib est EMBARQUÉE dans plusieurs addons hôtes et CE fichier compagnon re-patche
-- les fonctions SANS passer par le gate de version de LibStub:NewLibrary (qui ne protège que le
-- fichier principal). Sans ce garde, c'est l'ORDRE DE CHARGEMENT des addons qui arbitre : une copie
-- embarquée plus ANCIENNE chargée après nous écraserait nos fonctions. On refuse de réécraser une
-- révision >= la nôtre. BUMP ce numéro à chaque évolution du transport (et resync TOUS les hôtes).
local TRANSPORT_REV = 6
if (lib._transportRev or 0) >= TRANSPORT_REV then return end
lib._transportRev = TRANSPORT_REV

local PREFIX        = "CraftLink"
local CHANNEL_NAME  = "CraftLinkNet"   -- canal CUSTOM dédié pour la portée "global"
local SEND_INTERVAL = 0.15             -- s entre 2 AddonMessage (~6-7/s, sous le plafond client)
local JOIN_RETRY    = 1.0              -- s : JoinTemporaryChannel est async, on résout l'index en différé
local WATCHDOG       = 8.0             -- s : ré-vérifie périodiquement que le canal est toujours là

-- Balise de découverte en TEXTE (PAS AddonMessage). Testé PTR 2026-06-30 : la distribution CHANNEL des
-- AddonMessages n'est PAS délivrée entre 2 comptes d'un même Battle.net (0 reçu), alors que le TEXTE de
-- canal l'est. On émet donc une courte ligne TEXTE, RARE et throttlée, sur le canal → des INCONNUS se
-- découvrent, puis TOUT le trafic de données bascule en whisper (fiable). La ligne est MASQUÉE du chat
-- du joueur (filtre). RARE = anti-flood (SendChatMessage est soumis à la protection anti-spam serveur).
local BEACON_TAG          = "CLNK1"    -- préfixe reconnaissable (sans « | » : évite les séquences d'échappement du chat)
local BEACON_MIN_INTERVAL = 30         -- s : plancher dur entre 2 balises (anti-flood)

-- DONNÉES en TEXTE de canal (portée royaume RÉELLE). Même constat que la balise : l'AddonMessage CHANNEL
-- est muet, mais le TEXTE passe cross-BNet à l'échelle (prouvé 2026-07-09 en observant Deathlog). On
-- encode un message CraftLink (ex. « ORD|NEW|… ») en texte canal-safe : préfixe `CLD1 ` + payload dont
-- les « | » sont remplacés par « ~ » (le « | » casse le chat = séquence d'échappement ; Deathlog fait de
-- même). Émis SOUS HARDWARE EVENT uniquement (SendChatMessage protégé) → l'appelant garantit l'input.
local DATA_TAG          = "CLD1 "      -- préfixe des messages de DONNÉES (espace inclus = séparateur)
local DATA_MIN_INTERVAL = 1            -- s : plancher léger anti-accident (le posting est déjà rare)

lib._handlers    = lib._handlers    or {}   -- [verb] = { fn(sender, payload, distribution), ... }
lib._presenceCb  = lib._presenceCb  or nil  -- fn("join"|"leave", playerShort)
lib._readyCbs    = lib._readyCbs    or {}   -- { fn(), ... } appelés à chaque (re)acquisition du canal
lib._sendQueue   = lib._sendQueue   or {}
lib._sendBusy    = lib._sendBusy    or false
lib._beaconCb    = lib._beaconCb    or nil   -- fn(senderShort, payload) sur balise texte reçue
lib._lastBeacon  = lib._lastBeacon  or 0
lib._lastData    = lib._lastData    or 0     -- throttle des broadcasts DONNÉES canal-texte

-- ------------------------------------------------------------------
-- Trace (optionnelle) : le produit branche un tracer ; la lib reste agnostique.
-- ------------------------------------------------------------------
function lib:SetTracer(fn) self._trace = fn end
local function trace(cat, msg) if lib._trace then pcall(lib._trace, cat, msg) end end

-- ------------------------------------------------------------------
-- API publique d'enregistrement
-- ------------------------------------------------------------------
-- Plusieurs modules peuvent écouter le même verbe (ex. HI : présence ET resync d'ordres).
function lib:RegisterHandler(verb, fn)
    local list = self._handlers[verb]
    if not list then list = {}; self._handlers[verb] = list end
    list[#list + 1] = fn
end
function lib:OnPresence(fn)            self._presenceCb = fn end
function lib:OnBeacon(fn)              self._beaconCb = fn end   -- balise TEXTE de découverte reçue
function lib:IsNetworkReady()          return self._channelJoined == true end

-- Configuration produit (optionnelle, à appeler AVANT StartTransport) :
--   SetGlobalChannel(name) : remplace le nom du canal custom (défaut "CraftLinkNet").
--   SetAutoJoin(false)     : opt-out de l'auto-join → portée "global" indisponible (whisper/guilde OK).
function lib:SetGlobalChannel(name) if name and name ~= "" then self._channelName = name end end
function lib:SetAutoJoin(enabled)   self._autoJoin = (enabled ~= false) end
function lib:GlobalChannelKind()    return self._channelJoined and "custom" or nil end

-- Label humain du canal global ACTIF (pour le statut produit).
function lib:GlobalChannelLabel() return self._channelName or CHANNEL_NAME end
function lib:ChannelName()        return self:GlobalChannelLabel() end

-- Callback « réseau prêt » : déclenché à chaque (re)acquisition du canal. Si déjà prêt à
-- l'enregistrement → déclenché tout de suite (le produit ne rate jamais la fenêtre).
function lib:OnNetworkReady(fn)
    if type(fn) ~= "function" then return end
    self._readyCbs[#self._readyCbs + 1] = fn
    if self._channelJoined then pcall(fn) end
end

-- Retire NOTRE canal de l'affichage de TOUTES les fenêtres de chat (trafic technique invisible au
-- joueur) : double sécurité par-dessus JoinTemporaryChannel (déjà frame-less). N'affecte PAS la réception
-- (l'event CHAT_MSG_CHANNEL arrive au handler indépendamment de l'affichage). Appelé à chaque acquisition.
local function hideChannelFromFrames()
    local name = lib._channelName or CHANNEL_NAME
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf and ChatFrame_RemoveChannel then pcall(ChatFrame_RemoveChannel, cf, name) end
    end
end

local function fireReady()
    trace("net", "canal acquis (idx=" .. tostring(lib._channelIndex) .. ") → ready callbacks")
    hideChannelFromFrames()
    for _, fn in ipairs(lib._readyCbs) do pcall(fn) end
end

local function playerShort(name)
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

-- Confinement ROYAUME : le canal custom peut être partagé entre royaumes CONNECTÉS (voire au-delà). Les
-- DONNÉES de canal (découverte, ordres) ne valent que pour des joueurs avec qui on peut réellement
-- échanger → on n'accepte que le royaume courant + les royaumes connectés (GetAutoCompleteRealms).
-- L'émetteur d'un event canal porte un suffixe « -Royaume » (normalisé, sans espace) s'il n'est PAS sur
-- notre royaume ; pas de suffixe = même royaume. Les noms de perso ne contiennent jamais de « - » (WoW).
local function sameRealmGroup(author)
    if type(author) ~= "string" then return false end
    local realm = author:match("%-(.+)$")
    if not realm then return true end                       -- pas de suffixe = mon royaume exact
    local mine = GetNormalizedRealmName and GetNormalizedRealmName()
    if mine and realm == mine then return true end
    if GetAutoCompleteRealms then
        for _, r in ipairs(GetAutoCompleteRealms() or {}) do if r == realm then return true end end
    end
    return false
end

-- ------------------------------------------------------------------
-- Anti-slot-/1 : les canaux par défaut (General/Trade…) ne sont joints qu'APRÈS l'entrée en jeu. Si on
-- rejoint avant eux, NOTRE canal rafle le n°1 (taper /1 y écrirait → gêne le joueur). On vérifie donc
-- qu'un canal occupe déjà le slot 1 avant de rejoindre.
-- ------------------------------------------------------------------
local function slot1Taken()
    if not GetChannelName then return true end
    local _, name = GetChannelName(1)
    local mine = lib._channelName or CHANNEL_NAME
    return name ~= nil and name ~= "" and name ~= mine
end

-- Rejoint le canal custom et résout l'index (async → retry borné). Idempotent.
function lib:JoinNetwork(attempt)
    attempt = attempt or 1
    if self._channelJoined then return end
    if self._autoJoin == false then return end   -- opt-out produit : pas de portée "global"
    self._joinSince = self._joinSince or (GetTime and GetTime() or 0)
    if not slot1Taken() and GetTime and (GetTime() - self._joinSince) < 10
       and C_Timer and C_Timer.After then
        trace("net", "attente d'un canal par défaut sur le slot 1 (anti-/1)")
        C_Timer.After(JOIN_RETRY, function() lib:JoinNetwork() end)
        return
    end
    local name = self._channelName or CHANNEL_NAME
    if JoinTemporaryChannel then JoinTemporaryChannel(name) end
    local idx = GetChannelName and GetChannelName(name) or 0
    if idx and idx > 0 then
        self._channelIndex  = idx
        self._channelJoined = true
        fireReady()
    elseif attempt < 15 and C_Timer and C_Timer.After then
        trace("net", "join tentative " .. attempt .. " — index pas encore résolu")
        C_Timer.After(JOIN_RETRY, function() lib:JoinNetwork(attempt + 1) end)
    else
        trace("net", "join ÉCHEC après " .. attempt .. " tentatives (le watchdog réessaiera)")
    end
end

-- Watchdog : ré-résout l'index et rejoint si le canal a été perdu (reload, kick, etc.).
function lib:_Watchdog()
    if self._autoJoin == false then return end
    local name = self._channelName or CHANNEL_NAME
    local idx  = GetChannelName and GetChannelName(name) or 0
    if idx and idx > 0 then
        if not self._channelJoined or self._channelIndex ~= idx then
            self._channelIndex  = idx
            local was = self._channelJoined
            self._channelJoined = true
            if not was then
                trace("net", "watchdog : canal ré-acquis (idx=" .. idx .. ")")
                fireReady()
            end
        end
    else
        if self._channelJoined then trace("net", "watchdog : canal PERDU → rejoin") end
        self._channelJoined = false
        self._channelIndex  = nil
        self:JoinNetwork()
    end
end

-- ------------------------------------------------------------------
-- Envoi (file FIFO throttlée, partagée par toutes les portées)
-- ------------------------------------------------------------------
local function rawSend(payload, scope, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if scope == "guild" then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    elseif scope == "whisper" then
        if target and target ~= "" then C_ChatInfo.SendAddonMessage(PREFIX, payload, "WHISPER", target) end
    elseif scope == "say" or scope == "yell" then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, scope == "yell" and "YELL" or "SAY")
    else -- "global"
        if lib._channelIndex then
            C_ChatInfo.SendAddonMessage(PREFIX, payload, "CHANNEL", lib._channelIndex)
        else
            trace("send", "DROP global (canal pas prêt) : " .. payload:sub(1, 40))
        end
    end
end

function lib:_Pump()
    if self._sendBusy then return end
    local item = table.remove(self._sendQueue, 1)
    if not item then return end
    trace("send", (item.scope or "global") .. (item.target and ("→" .. item.target) or "") .. " : " .. item.payload:sub(1, 60))
    rawSend(item.payload, item.scope, item.target)
    self._sendBusy = true
    if C_Timer and C_Timer.After then
        C_Timer.After(SEND_INTERVAL, function() lib._sendBusy = false; lib:_Pump() end)
    else
        self._sendBusy = false
    end
end

-- scope : "global" (défaut) | "guild" | "say" | "yell" | "whisper" (requiert target).
function lib:Send(payload, scope, target)
    if not payload or payload == "" then return end
    self._sendQueue[#self._sendQueue + 1] = { payload = payload, scope = scope or "global", target = target }
    self:_Pump()
end

-- Balise TEXTE de découverte sur le canal (contourne la distribution CHANNEL addon, muette same-BNet).
-- Le NOM de l'émetteur (porté par l'event canal) suffit à la découverte → `extra` optionnel et court.
-- Throttlée dur (anti-flood) ; masquée du chat par le filtre installé dans StartTransport.
function lib:SendBeacon(extra)
    if not (SendChatMessage and self._channelIndex) then return false end
    local t = (GetTime and GetTime()) or 0
    if t - (self._lastBeacon or 0) < BEACON_MIN_INTERVAL then return false end
    self._lastBeacon = t
    local line = BEACON_TAG .. (extra and (" " .. extra) or "")
    trace("send", "beacon(texte) : " .. line)
    pcall(SendChatMessage, line, "CHANNEL", nil, self._channelIndex)
    return true
end

-- Diffuse un message CraftLink (ex. « ORD|NEW|… ») en TEXTE de canal → portée ROYAUME réelle, en
-- complément du whisper. Encode canal-safe (`|`→`~`, préfixe `CLD1 `). À N'APPELER QUE sous hardware
-- event (SendChatMessage protégé) — typiquement au clic Poster. Throttle léger. Retourne true si émis.
function lib:BroadcastText(payload)
    if not (SendChatMessage and self._channelIndex and payload and payload ~= "") then return false end
    local t = (GetTime and GetTime()) or 0
    if t - (self._lastData or 0) < DATA_MIN_INTERVAL then return false end
    self._lastData = t
    local line = DATA_TAG .. payload:gsub("|", "~")
    -- Garde diagnostic (pas un blocage) : SendChatMessage est protégé hardware-event-only en Classic Era.
    -- Si un futur appelant automatisé (retry, migration) casse l'invariant, ça se voit dans /co trace au
    -- lieu d'un échec silencieux — `pcall` absorbe déjà ADDON_ACTION_BLOCKED sans le remonter autrement.
    trace("send", "data(texte) : " .. line:sub(1, 60))
    local ok = pcall(SendChatMessage, line, "CHANNEL", nil, self._channelIndex)
    if not ok then trace("send", "data(texte) ÉCHOUÉ (hors hardware event ?) : " .. line:sub(1, 40)) end
    return ok
end

-- ------------------------------------------------------------------
-- Réception : dispatch par verbe
-- ------------------------------------------------------------------
function lib:_Dispatch(sender, message, distribution)
    if not message or message == "" then return end
    local verb = message:match("^([A-Z]+)")
    local list = verb and self._handlers[verb]
    local who = playerShort(sender)
    trace("recv", (distribution or "?") .. " " .. tostring(who) .. " : " .. message:sub(1, 60) .. (list and "" or " (verbe inconnu)"))
    if list then
        for _, fn in ipairs(list) do pcall(fn, who, message, distribution) end
    end
end

-- ------------------------------------------------------------------
-- Démarrage : enregistre le préfixe + les events, rejoint le canal. Idempotent.
-- ------------------------------------------------------------------
-- Est-ce NOTRE canal global ? (par index résolu OU par nom de base, insensible à la casse).
-- chanName peut arriver en NOMBRE selon le chemin (event vs filtre) → on garde le type-check.
local function isMyChannel(chanNum, chanName)
    if lib._channelIndex and chanNum == lib._channelIndex then return true end
    local mine_name = lib._channelName or CHANNEL_NAME
    return (type(chanName) == "string" and chanName:upper() == mine_name:upper()) or false
end

-- CHAT_MSG_ADDON : trafic addon (toutes portées) → dispatch par verbe (sauf soi-même).
local function onAddonMsg(me, ...)
    local prefix, message, distribution, sender = ...
    if prefix == PREFIX and playerShort(sender) ~= me then
        lib:_Dispatch(sender, message, distribution)
    end
end

-- CHAT_MSG_CHANNEL : texte de NOTRE canal (arg1 texte, arg2 émetteur, arg8 n°, arg9 nom). Deux formes :
--   * balise `CLNK1` → découverte (beaconCb) ;   * données `CLD1 ` → message CraftLink dispatché par verbe.
local function onChannelText(me, ...)
    local text, author = (...), select(2, ...)
    if type(text) ~= "string" or playerShort(author) == me
       or not isMyChannel(select(8, ...), select(9, ...))
       or not sameRealmGroup(author) then return end   -- confinement royaume : drop cross-royaume
    local who = playerShort(author)
    if text:sub(1, #BEACON_TAG) == BEACON_TAG and lib._beaconCb then
        trace("recv", "beacon(texte) " .. tostring(who) .. " : " .. text:sub(1, 40))
        pcall(lib._beaconCb, who, text:sub(#BEACON_TAG + 2))
    elseif text:sub(1, #DATA_TAG) == DATA_TAG then
        -- Restaure les « | » (swap inverse) et dispatche comme un AddonMessage CHANNEL (par verbe).
        lib:_Dispatch(author, (text:sub(#DATA_TAG + 1):gsub("~", "|")), "CHANNEL")
    end
end

-- CHANNEL_JOIN/_LEAVE de NOTRE canal → présence (arg2 joueur, arg8 n°, arg9 nom).
local function onPresenceEvent(event, ...)
    if not lib._presenceCb then return end
    local who = select(2, ...)
    if not isMyChannel(select(8, ...), select(9, ...)) then return end
    local kind = (event == "CHAT_MSG_CHANNEL_JOIN") and "join" or "leave"
    trace("pres", kind .. " " .. tostring(playerShort(who)))
    pcall(lib._presenceCb, kind, playerShort(who))
end

-- Masque les balises texte de NOTRE canal du chat du joueur (trafic technique invisible pour lui).
local function installBeaconFilter()
    if not ChatFrame_AddMessageEventFilter or lib._beaconFilterInstalled then return end
    lib._beaconFilterInstalled = true
    -- Filtre : signature décalée de (self, event) → chanNum = arg8 (10e param), chanName = arg9 (11e).
    ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL",
        function(_, _, msg, _, _, _, _, _, _, chanNum, chanName)
            if isMyChannel(chanNum, chanName) and type(msg) == "string"
               and (msg:sub(1, #BEACON_TAG) == BEACON_TAG or msg:sub(1, #DATA_TAG) == DATA_TAG) then
                return true   -- avale la ligne technique (balise ou données) : invisible dans le chat
            end
            return false
        end)
end

function lib:StartTransport()
    if self._transportStarted then return end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
    self._transportStarted = true
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    local me = UnitName and UnitName("player") or "?"
    local f = CreateFrame("Frame", "CraftLinkTransportFrame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("CHAT_MSG_CHANNEL")        -- balises TEXTE de découverte (voir SendBeacon)
    f:RegisterEvent("CHAT_MSG_CHANNEL_JOIN")
    f:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON"        then onAddonMsg(me, ...)
        elseif event == "CHAT_MSG_CHANNEL"  then onChannelText(me, ...)
        else onPresenceEvent(event, ...) end
    end)
    installBeaconFilter()

    self:JoinNetwork()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(WATCHDOG, function() lib:_Watchdog() end)
    end
end
