-- CraftLink-1.0 — Transport générique : 4 portées + dispatch par verbe + présence + santé réseau.
--
-- Infrastructure réseau réutilisable (pas spécifique aux recettes) : un addon enregistre des
-- handlers par verbe (`RegisterHandler("RK", fn)`) et émet via `Send(payload, scope[, target])`.
-- Portées :
--   * "global"  : À TOUS. Canal CUSTOM "CraftLinkNet" s'il est joint (les canaux SYSTÈME n'ont jamais
--                 relayé l'AddonMessage, testé PTR 2026-06-30). SANS canal (SetAutoJoin(false), le cas
--                 de COC depuis que Forever MORCELLE le canal, 2026-09-27) : un whisper par pair en
--                 ligne que le produit désigne — cf. CraftLink_Fanout.lua.
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
local TRANSPORT_REV = 18   -- 18 : notre canal rend le /1 (_FixSlot1) ; 17 : valeurs SECRÈTES du chat écartées
                           -- 16 : salle de découverte — canal rejoint pour se présenter, « global » reste en whisper
                           -- 14 : « moi » = nom COMPLET (Prénom Nom sur Forever) — l'écho du canal était pris pour un autre
                           -- 13 : ChannelDelivers() — on CONSTATE que l'AddonMessage CHANNEL arrive
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

-- La MÉCANIQUE de file (enfilage, plafond, TTL, drain à l'input) vit dans CraftLink_TextQueue. Ici on
-- ne garde que ce qui relève du FORMAT DE FIL : les préfixes et le throttle propre à chaque genre de
-- ligne, passés à `_EnqueueText`.

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
function lib:IsNetworkReady()          return self._channelJoined == true or self._offlineReady == true end

-- Configuration produit (optionnelle, à appeler AVANT StartTransport) :
--   SetGlobalChannel(name) : remplace le nom du canal custom (défaut "CraftLinkNet").
--   SetAutoJoin(false)     : opt-out de l'auto-join → portée "global" indisponible (whisper/guilde OK).
function lib:SetGlobalChannel(name) if name and name ~= "" then self._channelName = name end end

-- Opt-out RÉEL. Avant, SetAutoJoin(false) ne posait qu'un drapeau : le joueur restait DANS le canal,
-- continuait de recevoir, et `sendChannelLine` continuait d'émettre (elle ne teste que `_channelIndex`).
-- « /co channel off » promettait pourtant que le carnet global ne fonctionnerait plus. On quitte donc
-- vraiment, on oublie l'index, et on jette la file d'envoi (ces lignes ne doivent plus jamais partir).
-- La distribution CHANNEL des AddonMessages est-elle RÉELLEMENT délivrée sur ce serveur ? Faux tant
-- qu'on n'en a pas reçu un seul. Mesuré sur le trafic ORDINAIRE (HI/SK/ORD…), donc aucun sondage et
-- aucun ajout au protocole. Session seulement : un état réseau persisté qui ne se ré-atteste plus est
-- un piège (cf. la notif de version), et le coût d'attendre la 1re réception est nul.
-- Vrai sur WoW: Forever (mesuré 2026-09-19, 2 comptes) ; faux sur Classic Era, où la voie reste morte.
function lib:ChannelDelivers()
    return self._channelProven == true
end

function lib:LeaveNetwork()
    if self._channelJoined and LeaveChannelByName then
        pcall(LeaveChannelByName, self._channelName or CHANNEL_NAME)
    end
    self._channelJoined, self._channelIndex, self._joinSince = false, nil, nil
    self._channelProven = nil   -- on quitte : le constat ne vaut plus, il se refera à la 1re réception
    for i = #self._textQueue, 1, -1 do self._textQueue[i] = nil end
    trace("net", "canal quitté (opt-out) — file d'envoi vidée")
end

function lib:SetAutoJoin(enabled)
    local on = (enabled ~= false)
    self._autoJoin = on
    if on then self._offlineReady = nil; return end
    self:LeaveNetwork()
    if self._transportStarted and self._StartOffline then self:_StartOffline() end   -- bascule en cours de session
end
function lib:GlobalChannelKind()    return (self._channelJoined and self._autoJoin ~= false) and "custom" or nil end

-- Label humain du canal global ACTIF (pour le statut produit).
function lib:GlobalChannelLabel() return self._channelName or CHANNEL_NAME end
function lib:ChannelName()        return self:GlobalChannelLabel() end

-- Callback « réseau prêt » : déclenché à chaque (re)acquisition du canal. Si déjà prêt à
-- l'enregistrement → déclenché tout de suite (le produit ne rate jamais la fenêtre).
function lib:OnNetworkReady(fn)
    if type(fn) ~= "function" then return end
    self._readyCbs[#self._readyCbs + 1] = fn
    if self:IsNetworkReady() then pcall(fn) end
end

-- Retire NOTRE canal de l'affichage de TOUTES les fenêtres de chat (trafic technique invisible au
-- joueur) : double sécurité par-dessus JoinTemporaryChannel (déjà frame-less). N'affecte PAS la réception
-- (l'event CHAT_MSG_CHANNEL arrive au handler indépendamment de l'affichage). Appelé à chaque acquisition.
-- La méthode du cadre d'abord : `ChatFrame_RemoveChannel` n'est qu'un alias posé par
-- Blizzard_DeprecatedChatInfo, que le réglage `loadDeprecationFallbacks` peut ne pas charger.
local function hideChannelFromFrames()
    local name = lib._channelName or CHANNEL_NAME
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local cf = _G["ChatFrame" .. i]
        local remove = cf and (cf.RemoveChannel or ChatFrame_RemoveChannel)
        if remove then pcall(remove, cf, name) end
    end
end

lib._hideChannel = hideChannelFromFrames   -- la salle de découverte (CraftLink_Fanout) se cache aussi
function lib:_FireReady()   -- méthode, pas locale : CraftLink_Fanout la déclenche aussi (réseau sans canal)
    trace("net", "réseau prêt (canal idx=" .. tostring(lib._channelIndex) .. ") → ready callbacks")
    hideChannelFromFrames()
    for _, fn in ipairs(lib._readyCbs) do pcall(fn) end
end

-- Qui parle ? (CraftLink_Sender, chargé avant nous) : nom court, royaume admis, lisibilité.
local playerShort    = lib._PlayerShort
local sameRealmGroup = lib._SameRealmGroup
local unreadable     = lib._Unreadable

-- ------------------------------------------------------------------
-- Anti-slot-/1 : les canaux par défaut (General/Trade…) ne sont joints qu'APRÈS l'entrée en jeu. Si on
-- rejoint avant eux, NOTRE canal rafle le n°1 (taper /1 y écrirait → gêne le joueur). On vérifie donc
-- qu'un canal occupe déjà le slot 1 avant de rejoindre. Si on l'a quand même (perso neuf : aucun canal du
-- jeu au bout de 10 s ; le jeu garde ensuite ce n°1 d'une session à l'autre), _FixSlot1 (CraftLink_Fanout)
-- le rend au premier canal du jeu.
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
    if self._autoJoin == false and not self._discovery then return end   -- ni canal, ni salle de découverte
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
        if self._FixSlot1 then self:_FixSlot1() end
        if self._autoJoin == false then lib:_RoomReady() else lib:_FireReady() end   -- salle : pas « réseau prêt »
    elseif attempt < 15 and C_Timer and C_Timer.After then
        trace("net", "join tentative " .. attempt .. " — index pas encore résolu")
        C_Timer.After(JOIN_RETRY, function() lib:JoinNetwork(attempt + 1) end)
    else
        trace("net", "join ÉCHEC après " .. attempt .. " tentatives (le watchdog réessaiera)")
    end
end

-- Watchdog : ré-résout l'index et rejoint si le canal a été perdu (reload, kick, etc.).
function lib:_Watchdog()
    self:_TrimTextQueue()                    -- purge des lignes canal périmées (hors du chemin d'input)
    if self._autoJoin == false and not self._discovery then
        if self._LeaveStaleChannel then self:_LeaveStaleChannel() end   -- une salle restée d'avant (/reload)
        return
    end
    local name = self._channelName or CHANNEL_NAME
    local idx  = GetChannelName and GetChannelName(name) or 0
    if idx and idx > 0 then
        if not self._channelJoined or self._channelIndex ~= idx then
            self._channelIndex  = idx
            local was = self._channelJoined
            self._channelJoined = true
            if not was then
                trace("net", "watchdog : canal ré-acquis (idx=" .. idx .. ")")
                if self._autoJoin == false then lib:_RoomReady() else lib:_FireReady() end
            end
        end
        if self._FixSlot1 then self:_FixSlot1() end   -- un canal du jeu arrivé depuis : on lui rend le /1
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
-- Rend le code de SendAddonMessage (un Enum.SendAddonMessageResult sur Forever : débit, cible hors
-- ligne…), lu par _OnSendResult (CraftLink_Fanout). nil quand rien n'est parti.
local function rawSend(payload, scope, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end
    if scope == "guild" then
        return C_ChatInfo.SendAddonMessage(PREFIX, payload, "GUILD")
    elseif scope == "whisper" then
        if target and target ~= "" then return C_ChatInfo.SendAddonMessage(PREFIX, payload, "WHISPER", target) end
    elseif scope == "say" or scope == "yell" then
        return C_ChatInfo.SendAddonMessage(PREFIX, payload, scope == "yell" and "YELL" or "SAY")
    else -- "global" (canal plein) ou "room" (salle de découverte : Send ne la détourne pas en whisper)
        if lib._channelIndex then
            return C_ChatInfo.SendAddonMessage(PREFIX, payload, "CHANNEL", lib._channelIndex)
        end
        trace("send", "DROP global (canal pas prêt) : " .. payload:sub(1, 40))
    end
end

function lib:_Pump()
    if self._sendBusy then return end
    local item = table.remove(self._sendQueue, 1)
    if not item then return end
    trace("send", (item.scope or "global") .. (item.target and ("→" .. item.target) or "") .. " : " .. item.payload:sub(1, 60))
    local res = rawSend(item.payload, item.scope, item.target)
    local wait = (self._OnSendResult and self:_OnSendResult(item, res)) or SEND_INTERVAL
    self._sendBusy = true
    if C_Timer and C_Timer.After then
        C_Timer.After(wait, function() lib._sendBusy = false; lib:_Pump() end)
    else
        self._sendBusy = false
    end
end

-- scope : "global" (défaut) | "guild" | "say" | "yell" | "whisper" (requiert target).
function lib:Send(payload, scope, target)
    if not payload or payload == "" then return end
    scope = scope or "global"
    if scope == "global" and self._autoJoin == false and self._FanoutGlobal then return self:_FanoutGlobal(payload) end
    if scope == "whisper" and self._IsDuplicate and self:_IsDuplicate(payload, target) then return end
    self._sendQueue[#self._sendQueue + 1] = { payload = payload, scope = scope, target = target }
    self:_Pump()
end

-- Envoi d'une ligne TEXTE sur le canal (balise CLNK1 découverte OU données CLD1) : garde canal +
-- throttle par champ (`lastKey`) + pcall + trace. SendChatMessage est PROTÉGÉ hardware-event-only en
-- Classic Era → à n'appeler QUE sous input (clic/slash).
-- ⚠️ Le `pcall` N'ABSORBE PAS un ADDON_ACTION_BLOCKED : c'est un ÉVÉNEMENT émis APRÈS le retour normal
-- de l'appel, pas une erreur Lua → hors input : popup d'erreur ET envoi faussement compté « parti ».
-- Les émetteurs hors input (login, ticker) passent donc par QueueText. Retourne true SEULEMENT si l'appel
-- a été tenté (ni canal absent, ni throttlé) — ce qui, sous input, vaut « parti ».
-- `C_ChatInfo.SendChatMessage` d'abord : le global n'est qu'un alias déprécié (Blizzard_DeprecatedChatInfo).
local function sendChannelLine(line, minInterval, lastKey)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if not (send and lib._channelIndex) then return false end
    local t = (GetTime and GetTime()) or 0
    if t - (lib[lastKey] or 0) < minInterval then return false end
    lib[lastKey] = t
    trace("send", "canal(texte) : " .. line:sub(1, 60))
    local ok = pcall(send, line, "CHANNEL", nil, lib._channelIndex)
    if not ok then trace("send", "canal(texte) ÉCHOUÉ (hardware event ?) : " .. line:sub(1, 40)) end
    return ok
end

-- Le drain de la file vit dans CraftLink_TextQueue : il lui faut ce chemin d'envoi, resté local ici
-- (c'est Transport qui possède le canal et son throttle). Seam interne, pas une API produit.
function lib:_SendChannelLine(line, minInterval, lastKey)
    return sendChannelLine(line, minInterval or DATA_MIN_INTERVAL, lastKey or "_lastData")
end

-- Balise TEXTE de découverte (le NOM de l'émetteur, porté par l'event, suffit → `extra` optionnel/court).
-- Masquée du chat par le filtre. Throttlée dur (anti-flood ; SendChatMessage subit l'anti-spam serveur).
-- Sans canal, pas de balise, même salle rejointe : la salle se présente par un message d'ADDON (portée
-- « room »). Une ligne de TEXTE y arrivait SECRÈTE chez chaque porteur en donjon (TRANSPORT_REV 17).
function lib:SendBeacon(extra)
    if self._autoJoin == false then return false end
    return sendChannelLine(BEACON_TAG .. (extra and (" " .. extra) or ""), BEACON_MIN_INTERVAL, "_lastBeacon")
end

-- Balise d'ARRIVÉE : la même ligne, mais ENFILÉE au lieu d'être émise. À appeler depuis le bring-up
-- (`OnNetworkReady`), où il n'y a par construction aucun hardware event : elle partira au premier clic
-- ou à la première touche du joueur, donc quelques secondes après son login, sans qu'il ait rien à faire.
-- C'EST le correctif du défaut « un nouvel installé reste invisible » (cf. l'en-tête de TextQueue).
-- `kind` : UNE seule balise en file (le watchdog re-déclenche OnNetworkReady) ; `ttl = false` : « je suis
-- là » reste vrai tant que le joueur est connecté ; `sticky` : la plus ancienne, le plafond la sacrifierait.
-- Sans canal, pas de balise : aucun inconnu ne l'entendrait (le cercle remplace la découverte).
function lib:QueueBeacon(extra)
    if self._autoJoin == false then return false end
    return self:_EnqueueText(BEACON_TAG .. (extra and (" " .. extra) or ""),
        { minInterval = BEACON_MIN_INTERVAL, lastKey = "_lastBeacon",
          kind = "beacon", ttl = false, sticky = true })
end

-- Diffuse un message CraftLink (ex. « ORD|NEW|… ») en TEXTE de canal → portée ROYAUME réelle, en
-- complément du whisper. Encode canal-safe (`|`→`~` ; le codec garantit qu'aucun champ ne contient `~`,
-- cf. Orders_Codec). L'envoi immédiat n'aboutit que sous hardware event, canal joint et hors throttle :
-- sinon la ligne part en FILE et sera drainée au prochain clic/touche. L'appelant n'a donc plus à
-- garantir le contexte d'input — il garantit seulement que la diffusion est VOULUE (cf. opts.channel).
-- Throttle des lignes de DONNÉES, passé à la file : elle mêle des genres qui n'ont pas la même cadence.
local DATA_OPTS = { minInterval = DATA_MIN_INTERVAL, lastKey = "_lastData" }

function lib:BroadcastText(payload)
    if not (payload and payload ~= "") then return false end
    if self._autoJoin == false then return (self._FanoutGlobal and self:_FanoutGlobal(payload) or 0) > 0 end
    local line = DATA_TAG .. payload:gsub("|", "~")
    if sendChannelLine(line, DATA_MIN_INTERVAL, "_lastData") then return true end
    self:_EnqueueText(line, DATA_OPTS)
    return false
end

-- Comme BroadcastText mais SANS tentative d'envoi immédiat : à utiliser depuis un contexte HORS
-- hardware event (login/OnNetworkReady, ticker de rafraîchissement) où un SendChatMessage déclencherait
-- ADDON_ACTION_BLOCKED (cf. sendChannelLine : le pcall ne l'attrape pas). La ligne part au prochain
-- clic/touche via _DrainText — seul créneau où l'envoi canal-texte est réellement autorisé.
function lib:QueueText(payload)
    if not (payload and payload ~= "") then return false end
    if self._autoJoin == false then return (self._FanoutGlobal and self:_FanoutGlobal(payload) or 0) > 0 end
    return self:_EnqueueText(DATA_TAG .. payload:gsub("|", "~"), DATA_OPTS) and true or false
end

-- La file canal-texte (enfilage, plafond, TTL, drain sous input) vit dans CraftLink_TextQueue :
-- `PendingTextCount`, `_DrainText`, `_TrimTextQueue` et `_InstallInputDrain` y sont définis.

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

-- Une ligne de NOTRE canal est-elle du trafic TECHNIQUE (balise ou données) ? Partagé par le filtre de
-- chat (masquage) et le dispatch : un seul endroit pour la liste des préfixes → pas de risque d'oublier
-- le filtre en ajoutant un préfixe (sinon le message fuiterait en clair dans le chat du joueur).
local function isTechChannelText(msg)
    return type(msg) == "string"
        and (msg:sub(1, #BEACON_TAG) == BEACON_TAG or msg:sub(1, #DATA_TAG) == DATA_TAG)
end

-- CHAT_MSG_ADDON : trafic addon (toutes portées) → dispatch par verbe (sauf soi-même).
-- CONFINEMENT ROYAUME (même garde que le texte de canal) : `_Dispatch` strippe le suffixe « -Royaume » du
-- sender (playerShort) → sans ça, un joueur d'un royaume NON connecté (croisé en zone cross-royaume) portant
-- le MÊME nom qu'un de nos interlocuteurs devenait indiscernable de lui (sender==buyer) et pouvait ACK/CANCEL
-- en son nom. Les royaumes CONNECTÉS partagent un espace de noms UNIQUE (aucun homonyme possible dedans) →
-- on accepte royaume courant + connectés, on rejette le reste (avec qui on ne peut ni échanger ni courrier).
local function onAddonMsg(me, ...)
    local prefix, message, distribution, sender = ...
    if prefix == PREFIX and playerShort(sender) ~= me and sameRealmGroup(sender) then
        -- CONSTAT, pas hypothèse : si un AddonMessage nous arrive par le CANAL, alors cette voie est
        -- ouverte sur ce serveur. Mesuré ici et NULLE PART ailleurs — surtout pas dans _Dispatch, que
        -- la voie TEXTE (`CLD1`) appelle aussi avec "CHANNEL" : elle se prouverait elle-même et se
        -- ferait couper sur Era, où elle est le seul chemin qui marche.
        if distribution == "CHANNEL" then lib._channelProven = true end
        lib:_Dispatch(sender, message, distribution)
    end
end

-- CHAT_MSG_CHANNEL : texte de NOTRE canal (arg1 texte, arg2 émetteur, arg8 n°, arg9 nom). Deux formes :
--   * balise `CLNK1` → découverte (beaconCb) ;   * données `CLD1 ` → message CraftLink dispatché par verbe.
local function onChannelText(me, ...)
    local text, author = ...
    local chanNum, chanName = select(8, ...)
    -- Gardes ORDONNÉES du moins cher au plus cher : le canal Deathlog (royaume HC) crache des dizaines
    -- de messages/s → on écarte d'abord par index de canal (numérique) AVANT tout string:match sur l'auteur.
    -- Chaque valeur est reconnue lisible AVANT d'être comparée ou indexée (valeurs secrètes, cf. Sender).
    if type(text) ~= "string" or unreadable(chanNum, chanName) or not isMyChannel(chanNum, chanName) then return end
    if unreadable(text, author) or not isTechChannelText(text) then return end
    local who = playerShort(author)
    if who == me or not sameRealmGroup(author) then return end   -- soi-même / confinement royaume
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
    local chanNum, chanName = select(8, ...)
    if unreadable(who, chanNum, chanName) or not isMyChannel(chanNum, chanName) then return end
    local kind = (event == "CHAT_MSG_CHANNEL_JOIN") and "join" or "leave"
    trace("pres", kind .. " " .. tostring(playerShort(who)))
    pcall(lib._presenceCb, kind, playerShort(who))
end

-- Masque les balises texte de NOTRE canal du chat du joueur (trafic technique invisible pour lui).
-- `ChatFrameUtil` d'abord : `ChatFrame_AddMessageEventFilter` n'est qu'un alias déprécié. Sur Forever,
-- Blizzard n'appelle pas le filtre quand un argument est secret (ChatFrameFilters.lua) : pas de garde ici.
local function installBeaconFilter()
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add or lib._beaconFilterInstalled then return end
    lib._beaconFilterInstalled = true
    -- Filtre : signature décalée de (self, event) → chanNum = arg8 (10e param), chanName = arg9 (11e).
    add("CHAT_MSG_CHANNEL",
        function(_, _, msg, _, _, _, _, _, _, chanNum, chanName)
            if isMyChannel(chanNum, chanName) and isTechChannelText(msg) then
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

    local me = lib._MyNetworkName()
    self._me = me   -- le fanout ne s'écrit jamais à lui-même
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
    lib:_InstallInputDrain()

    self:JoinNetwork()
    if self._autoJoin == false and self._StartOffline then self:_StartOffline() end   -- réseau sans canal
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(WATCHDOG, function() lib:_Watchdog() end)
    end
end
