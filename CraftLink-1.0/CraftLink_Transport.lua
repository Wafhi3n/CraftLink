-- CraftLink-1.0 — Transport générique : 3 canaux + dispatch par verbe + présence de canal.
--
-- Infrastructure réseau réutilisable (pas spécifique aux recettes) : un addon enregistre des
-- handlers par verbe (`RegisterHandler("RK", fn)`) et émet via `Send(payload, scope)`. Trois
-- portées :
--   * "global"    : canal caché à l'échelle du royaume (JoinTemporaryChannel + SendAddonMessage
--                   distribution "CHANNEL") — confirmé OK en Classic Era, sans hardware event.
--   * "guild"     : distribution "GUILD" (+ relais GreenWall à brancher — hardware-event only).
--   * "say"/"yell": proximité (SendAddonMessage "SAY"/"YELL", limité par la portée) → découverte
--                   des porteurs de l'addon autour de soi (PING/PONG côté produit).
--
-- Présence : on N'ENVOIE PAS de heartbeat — l'appartenance au canal caché EST la présence. Les
-- events CHAT_MSG_CHANNEL_JOIN/_LEAVE du canal sont relayés via `OnPresence(fn)`. L'annuaire des
-- gens (qui est là, qui peut crafter quoi) se construit DANS LE PRODUIT, pas ici.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

local PREFIX        = "CraftLink"
local CHANNEL_NAME  = "CraftLinkNet"   -- nom FIXE : on VEUT que tous les porteurs partagent le canal
local SEND_INTERVAL = 0.15             -- s entre 2 AddonMessage (~6-7/s, sous le plafond client)
local JOIN_RETRY    = 1.0              -- s : JoinTemporaryChannel est async, on résout l'index en différé

lib._handlers    = lib._handlers    or {}   -- [verb] = fn(sender, payload, distribution)
lib._presenceCb  = lib._presenceCb  or nil  -- fn("join"|"leave", playerShort)
lib._sendQueue   = lib._sendQueue   or {}
lib._sendBusy    = lib._sendBusy    or false

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
function lib:IsNetworkReady()          return self._channelJoined == true end
function lib:ChannelName()             return CHANNEL_NAME end

local function playerShort(name)
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

-- ------------------------------------------------------------------
-- Canal global caché
-- ------------------------------------------------------------------
local function hideChannelFromChat()
    if not ChatFrame_RemoveChannel then return end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        if cf then pcall(ChatFrame_RemoveChannel, cf, CHANNEL_NAME) end
    end
end

-- Rejoint le canal caché et résout son index (async → retry borné). Idempotent.
function lib:JoinNetwork(attempt)
    attempt = attempt or 1
    if self._channelJoined then return end
    if JoinTemporaryChannel then JoinTemporaryChannel(CHANNEL_NAME) end
    local idx = GetChannelName and GetChannelName(CHANNEL_NAME) or 0
    if idx and idx > 0 then
        self._channelIndex  = idx
        self._channelJoined = true
        hideChannelFromChat()
    elseif attempt < 10 and C_Timer and C_Timer.After then
        C_Timer.After(JOIN_RETRY, function() lib:JoinNetwork(attempt + 1) end)
    end
end

-- ------------------------------------------------------------------
-- Envoi (file FIFO throttlée, partagée par toutes les portées)
-- ------------------------------------------------------------------
local function rawSend(payload, scope)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if scope == "guild" then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    elseif scope == "say" or scope == "yell" then
        C_ChatInfo.SendAddonMessage(PREFIX, payload, scope == "yell" and "YELL" or "SAY")
    else -- "global"
        if lib._channelIndex then
            C_ChatInfo.SendAddonMessage(PREFIX, payload, "CHANNEL", lib._channelIndex)
        end
    end
end

function lib:_Pump()
    if self._sendBusy then return end
    local item = table.remove(self._sendQueue, 1)
    if not item then return end
    rawSend(item.payload, item.scope)
    self._sendBusy = true
    if C_Timer and C_Timer.After then
        C_Timer.After(SEND_INTERVAL, function() lib._sendBusy = false; lib:_Pump() end)
    else
        self._sendBusy = false
    end
end

-- scope : "global" (défaut) | "guild" | "say" | "yell".
function lib:Send(payload, scope)
    if not payload or payload == "" then return end
    self._sendQueue[#self._sendQueue + 1] = { payload = payload, scope = scope or "global" }
    self:_Pump()
end

-- ------------------------------------------------------------------
-- Réception : dispatch par verbe
-- ------------------------------------------------------------------
function lib:_Dispatch(sender, message, distribution)
    if not message or message == "" then return end
    local verb = message:match("^([A-Z]+)")
    local list = verb and self._handlers[verb]
    if list then
        local who = playerShort(sender)
        for _, fn in ipairs(list) do pcall(fn, who, message, distribution) end
    end
end

-- ------------------------------------------------------------------
-- Démarrage : enregistre le préfixe + les events, rejoint le canal. Idempotent.
-- Appelé par le PRODUIT qui veut le réseau (Guild Economy garde son propre TS.Net pour l'instant).
-- ------------------------------------------------------------------
function lib:StartTransport()
    if self._transportStarted then return end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) then return end
    self._transportStarted = true
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    local me = UnitName and UnitName("player") or "?"
    local f = CreateFrame("Frame", "CraftLinkTransportFrame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("CHAT_MSG_CHANNEL_JOIN")
    f:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            local prefix, message, distribution, sender = ...
            if prefix == PREFIX and playerShort(sender) ~= me then
                lib:_Dispatch(sender, message, distribution)
            end
        else
            -- CHANNEL_JOIN/_LEAVE : arg2 = joueur, arg8 = numéro de canal, arg9 = nom de base.
            -- On matche par NOM (fiable) ou par index → c'est bien NOTRE canal caché.
            local who      = select(2, ...)
            local chanNum  = select(8, ...)
            local chanName = select(9, ...)
            local mine = (chanName and chanName:upper() == CHANNEL_NAME:upper())
                      or (lib._channelIndex and chanNum == lib._channelIndex)
            if mine and lib._presenceCb then
                local kind = (event == "CHAT_MSG_CHANNEL_JOIN") and "join" or "leave"
                pcall(lib._presenceCb, kind, playerShort(who))
            end
        end
    end)

    self:JoinNetwork()
end
