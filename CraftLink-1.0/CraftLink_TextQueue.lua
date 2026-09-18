-- CraftLink-1.0 — File d'envoi canal-TEXTE : garde une ligne quand le hardware event manque, puis la
-- draine au prochain clic/touche (pattern Deathlog).
--
-- Pourquoi ce module existe. `SendChatMessage` est protégé hardware-event-only : une ligne émise hors
-- input (login, ticker) est perdue SANS REPRISE — et le `pcall` de l'appel ne le signale même pas (le
-- blocage est un ÉVÉNEMENT, ADDON_ACTION_BLOCKED, pas une erreur Lua). On enfile donc, et on draine à
-- l'input suivant.
--
-- Ce module ne connaît AUCUN format de fil : il transporte des lignes DÉJÀ encodées. Les préfixes
-- (`CLD1 ` pour les données, `CLNK1` pour la balise) et le throttle qui va avec restent dans
-- CraftLink_Transport, qui appelle `_EnqueueText(line, opts)`.
--
-- ⚠️ RÈGLE AFFINÉE LE 2026-09-18 — elle a coûté un défaut mesuré en jeu. La règle d'origine était
-- « une balise throttlée doit être PERDUE : la rejouer plus tard ne vaut rien et floode ». Elle est
-- vraie d'une balise RÉPÉTÉE (ticker) : s'il en passe une plus tard, rien n'est perdu. Elle est
-- FAUSSE de la balise d'ARRIVÉE, qui est unique — rien ne la rejoue. Constat au premier test à deux
-- clients réels : un joueur qui venait d'installer l'addon restait INVISIBLE des inconnus du royaume
-- tant qu'il ne pensait pas à cliquer « Rafraîchir l'annuaire ».
-- Donc : **ce qui se REPRODUIT peut se perdre ; ce qui n'arrive QU'UNE FOIS doit être enfilé.**

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber : même raison que dans CraftLink_Transport — ce fichier compagnon re-patche des
-- fonctions SANS passer par le gate de version de LibStub:NewLibrary, donc une copie embarquée plus
-- ANCIENNE chargée après nous écraserait les nôtres. BUMP à chaque évolution (et resync des hôtes).
local TEXTQUEUE_REV = 1
if (lib._textQueueRev or 0) >= TEXTQUEUE_REV then return end
lib._textQueueRev = TEXTQUEUE_REV

local QUEUE_MAX = 24        -- plafond ; au-delà on drope la plus ancienne ligne SACRIFIABLE
local QUEUE_TTL = 120       -- s : TTL par défaut, au-delà une ligne n'a plus d'intérêt sur le canal

lib._textQueue = lib._textQueue or {}   -- { { line, ts, kind, minInterval, lastKey, ttl, sticky }, … }

local function trace(cat, msg) if lib._trace then pcall(lib._trace, cat, msg) end end

-- Drope la plus ancienne ligne SACRIFIABLE. Une entrée `sticky` (la balise d'arrivée) est épargnée :
-- elle est en tête PARCE QU'elle a été enfilée au login, donc la plus ancienne — et c'est justement
-- celle qu'on veut garder. Sans cette exception, le plafond sacrifierait d'abord ce qui compte le plus.
-- Pour les DONNÉES, droper la plus ancienne reste le bon sens : perdre un NEW dont le CANCEL survit
-- est inoffensif (le récepteur ignore un CANCEL sur un id inconnu) ; l'inverse laisserait une
-- commande fantôme. D'où le sens de balayage, de la tête vers la queue.
local function dropOldest(q)
    for i = 1, #q do
        if not q[i].sticky then table.remove(q, i); return end
    end
    table.remove(q, 1)
end

-- opts : minInterval / lastKey (throttle PROPRE à la ligne — la file mêle des genres qui n'ont pas la
-- même cadence), ttl (nil = QUEUE_TTL, false = n'expire jamais), kind (dédoublonnage : une seule ligne
-- de ce genre en file), sticky (épargnée par le plafond).
function lib:_EnqueueText(line, opts)
    if not (line and line ~= "") then return false end
    opts = opts or {}
    local q = self._textQueue
    if opts.kind then
        for _, e in ipairs(q) do if e.kind == opts.kind then return false end end
    end
    q[#q + 1] = { line = line, ts = (GetTime and GetTime()) or 0, kind = opts.kind,
                  minInterval = opts.minInterval, lastKey = opts.lastKey,
                  ttl = opts.ttl, sticky = opts.sticky }
    while #q > QUEUE_MAX do dropOldest(q) end
    trace("send", "canal(texte) MIS EN FILE (" .. #q .. ") : " .. line:sub(1, 40))
    return true
end

-- Nombre de lignes canal en attente de drain (diagnostic : COCMonitor, /co trace).
function lib:PendingTextCount() return #self._textQueue end

-- Draine UNE ligne par événement d'input (hardware event → SendChatMessage autorisé). CHEMIN CHAUD :
-- appelé à chaque clic dans le monde et à chaque touche → la garde sur file vide est la 1re instruction.
-- Échec d'envoi (throttle, canal perdu, blocage) → l'entrée reste en tête, retentée au prochain input.
function lib:_DrainText()
    local q = self._textQueue
    if #q == 0 then return end
    local e = q[1]
    if self:_SendChannelLine(e.line, e.minInterval, e.lastKey) then table.remove(q, 1) end
end

-- Purge des lignes périmées (appelée par le watchdog, pas par le drain : garde le chemin chaud minimal).
-- On balaie TOUTE la file : le TTL est désormais par entrée (la balise d'arrivée n'expire pas), donc
-- l'ancien raccourci « FIFO → s'arrêter à la première fraîche » ne tient plus.
function lib:_TrimTextQueue()
    local q, now = self._textQueue, (GetTime and GetTime()) or 0
    for i = #q, 1, -1 do
        local ttl = q[i].ttl
        if ttl == nil then ttl = QUEUE_TTL end
        if ttl and (now - q[i].ts) >= ttl then
            trace("send", "canal(texte) PÉRIMÉ, abandon : " .. q[i].line:sub(1, 40))
            table.remove(q, i)
        end
    end
end

-- Hooks d'input : un clic monde OU une touche = hardware event → on draine une ligne. Deux points
-- non-évidents, vérifiés en jeu :
--   * `EnableKeyboard(true)` est REQUIS, sinon le frame ne reçoit jamais OnKeyDown (le drain ne se
--     faisait qu'au clic — angle mort partagé par Deathlog, qui l'omet aussi).
--   * `SetPropagateKeyboardInput(true)` est IMPÉRATIF avec le clavier activé : sans lui le frame
--     AVALE les touches (chat, raccourcis d'action). Avec, la touche est rejouée telle quelle.
function lib:_InstallInputDrain()
    if self._inputDrainInstalled then return end
    self._inputDrainInstalled = true
    local function drain() lib:_DrainText() end
    if WorldFrame and WorldFrame.HookScript then WorldFrame:HookScript("OnMouseDown", drain) end
    if CreateFrame then
        local kf = CreateFrame("Frame", "CraftLinkInputDrainFrame", UIParent)
        if kf.EnableKeyboard then kf:EnableKeyboard(true) end
        if kf.SetPropagateKeyboardInput then kf:SetPropagateKeyboardInput(true) end
        kf:SetScript("OnKeyDown", drain)
    end
end
