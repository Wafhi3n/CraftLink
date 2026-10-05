-- CraftLink-1.0 — Registre de recettes, variante par IDENTIFIANTS (cible Camelot / WoW: Forever).
--
-- Pourquoi une deuxième forme. Le codec historique (CraftLink_Registry.lua) sérialise « quelles
-- recettes de ce métier je connais » en champ de bits INDEXÉ PAR LE CATALOGUE : compact (~76 chars
-- hex pour 300 recettes) mais il exige que les deux bouts partagent EXACTEMENT le même catalogue,
-- d'où le `dataVersion` sur le fil et le refus de décoder en cas d'écart.
--
-- Sur Camelot ce contrat ne tient pas : le catalogue n'est pas « Vanilla + une couche » — des
-- recettes CHANGENT DE MÉTIER (le Secourisme fabrique des potions) — et aucune source complète
-- n'existe tant que le contenu bouge. Sans catalogue, pas de positions, donc pas de bitfield.
--
-- Ici on envoie les `recipeID` eux-mêmes. Ils SONT des spellID : n'importe quel client résout nom
-- et icône via C_Spell, sans catalogue et même pour un métier qu'il n'a pas. Le fil devient
-- auto-descriptif et survit à tout patch de contenu.
--
-- Coût mesuré sur nos données (Forge, 610 recettes, pire cas) : 154 chars en bitfield contre 1296
-- ici. Le tri + delta + base36 fait l'essentiel du travail : les IDs d'un même métier sont
-- groupés, donc les écarts sont petits et tiennent sur 1 à 3 caractères.
--
-- Lua 5.1 (WoW) : pas d'opérateurs bit-à-bit ni de goto, arithmétique simple uniquement.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber (cf. CraftLink_Transport) : fichier compagnon qui re-patche la lib HORS du gate de
-- version LibStub:NewLibrary → une copie plus ANCIENNE chargée après nous écraserait ce codec.
-- On refuse de réécraser une révision >= la nôtre. BUMP à chaque évolution du format + resync hôtes.
local REGISTRY_IDS_REV = 2   -- 2 : fil RI PAR PALIER du jeu, découpé sous 255 octets (cf. plus bas)
if (lib._registryIdsRev or 0) >= REGISTRY_IDS_REV then return end
lib._registryIdsRev = REGISTRY_IDS_REV

local floor, concat, sort = math.floor, table.concat, table.sort

local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local SEP = "."   -- hors de l'alphabet base36 : aucune ambiguïté de découpage

local function toB36(n)
    n = floor(n or 0)
    if n <= 0 then return "0" end
    local s = ""
    while n > 0 do
        local d = n % 36
        s = B36:sub(d + 1, d + 1) .. s
        n = floor(n / 36)
    end
    return s
end

-- ------------------------------------------------------------------
-- Encodage / décodage
-- ------------------------------------------------------------------

-- knownSet = { [spellID] = true } → chaîne compacte, ou nil si rien à dire.
-- Trie, puis n'écrit que le PREMIER id en absolu et les ÉCARTS ensuite.
function lib:EncodeKnownIDs(knownSet)
    if type(knownSet) ~= "table" then return nil end
    local ids = {}
    for id, on in pairs(knownSet) do
        local n = tonumber(id)
        if on and n and n > 0 then ids[#ids + 1] = floor(n) end
    end
    if #ids == 0 then return nil end
    sort(ids)
    local out, prev = {}, 0
    for i = 1, #ids do
        if ids[i] ~= prev then                 -- dédoublonne un set mal formé
            out[#out + 1] = toB36(ids[i] - prev)
            prev = ids[i]
        end
    end
    return concat(out, SEP)
end

-- Chaîne → { [spellID] = true }. Tolère le vide, le nil et les fragments illisibles (un message
-- tronqué ne doit pas faire tomber le décodage de TOUT le registre d'un joueur).
function lib:DecodeKnownIDs(payload)
    local out = {}
    if type(payload) ~= "string" or payload == "" then return out end
    local acc = 0
    for chunk in payload:gmatch("[^" .. SEP .. "]+") do
        local d = tonumber(chunk, 36)
        if d and d > 0 then
            acc = acc + d
            out[acc] = true
        end
    end
    return out
end

-- ------------------------------------------------------------------
-- Test d'appartenance (ce que consomme l'UI)
-- ------------------------------------------------------------------

-- Le roster PERSISTE la chaîne (compacte en SavedVariables), pas le set. On décode donc à la
-- demande, avec un mémo indexé par la chaîne elle-même : il s'invalide tout seul dès que le
-- payload change, sans aucune gestion de version.
local memo = setmetatable({}, { __mode = "v" })   -- faible : le GC peut reprendre les gros sets

function lib:HasRecipeID(payload, spellID)
    if not (payload and spellID) then return false end
    local set = memo[payload]
    if not set then
        set = self:DecodeKnownIDs(payload)
        memo[payload] = set
    end
    return set[tonumber(spellID) or spellID] and true or false
end

-- Nombre de recettes portées par une chaîne (affichage « N recettes », diagnostics).
function lib:CountRecipeIDs(payload)
    local n = 0
    for _ in pairs(self:DecodeKnownIDs(payload)) do n = n + 1 end
    return n
end

-- Union de plusieurs chaînes d'identifiants (table ou liste de payloads) → une chaîne, ou nil.
-- Sert à recoller les morceaux d'un palier, et les paliers d'un registre.
function lib:UnionKnownIDs(payloads)
    local set = {}
    for _, p in pairs(payloads or {}) do
        for id in pairs(self:DecodeKnownIDs(p)) do set[id] = true end
    end
    return self:EncodeKnownIDs(set)
end

-- ------------------------------------------------------------------
-- Fil RI
-- ------------------------------------------------------------------
-- VERBE DISTINCT de RK, volontairement. Un client qui ne connaît pas RI l'ignore (verbe inconnu)
-- au lieu de lire des IDs comme un bitfield et d'afficher n'importe quoi. Pas de `dataVersion` :
-- il n'y a plus de catalogue partagé à faire concorder — c'est tout l'intérêt de cette forme.
--
-- ⚠️ 255 OCTETS, COUPÉS EN SILENCE. Mesuré le 2026-10-05 (build 70205, deux comptes, sonde DevMacro
-- DMLen) : un message d'addon de plus de 255 octets part avec `Success` et arrive coupé à 255, sans
-- aucune erreur. La forme d'origine, « RI|prof|payload » en UN message, dépasse dès ~100 recettes
-- connues dans un métier : l'autre gardait un registre tronqué, souvent fini par un identifiant FAUX
-- (le dernier, coupé en deux). D'où, depuis REGISTRY_IDS_REV 2, le découpage par PALIER DU JEU :
--
--   RI|<prof>|<ids>|<palier>|<masque>              un palier en un message
--   RI|<prof>|<ids>|<palier>.<k>/<n>|<masque>      morceau k sur n d'un palier trop gros
--
-- <palier> : 1 (appris jusqu'à 75), 2 (150), 3 (225), 4 (au-delà), 0 (niveau inconnu de nos données).
-- <masque> : les paliers NON VIDES de l'émetteur (« 0234 ») ; le récepteur oublie ceux qui n'y sont
-- plus. Chaque morceau est lisible seul (premier identifiant en absolu). Le palier est lu dans les
-- données de l'ÉMETTEUR et voyage dans le message : le récepteur n'a pas à avoir les mêmes données.
-- Un client d'avant REV 2 lit encore la partie identifiants : le suffixe colle au dernier fragment,
-- qui devient illisible et tombe (DecodeKnownIDs ignore un fragment qui n'est pas du base 36).
--
-- ⚠️ UN REGISTRE QUI TIENT EN UN MESSAGE PART EN UN MESSAGE, À L'ANCIENNE FORME, sans palier. Un client
-- d'avant REV 2 REMPLACE le registre à chaque message reçu : découper un registre qui tenait lui ferait
-- garder le dernier palier seul, là où il voyait tout. Le découpage ne commence qu'au-delà, où l'ancienne
-- forme arrivait de toute façon coupée. Un récepteur à jour lit l'ancienne forme comme un registre
-- ENTIER, qui remplace ses paliers.

local LEGACY_MAX = 250  -- au plus : un registre entier en UN message (mesuré : coupé au-delà de 255)
local RI_CAP    = 200   -- octets d'un morceau de palier : sous 255, avec la place d'une enveloppe de relais
local MAX_PARTS = 32    -- morceaux d'un palier, au plus (le pire palier mesuré en fait 5)
local TAG_ROOM  = #"|4.32/32|"
local TIER_TOP  = { 75, 150, 225 }   -- niveau d'apprentissage max des paliers 1 à 3 ; au-delà, 4

-- Palier du jeu d'une recette, d'après son niveau d'apprentissage : 1 à 4, ou 0 s'il est inconnu.
function lib:RecipeTier(prof, spellID)
    local at = tonumber(self.RecipeLearnedAt and self:RecipeLearnedAt(prof, spellID))
    if not at then return 0 end
    for i, top in ipairs(TIER_TOP) do
        if at <= top then return i end
    end
    return #TIER_TOP + 1
end

-- Identifiants TRIÉS → morceaux de payload de `budget` octets au plus, chacun lisible seul : son
-- premier identifiant s'écrit en absolu, les suivants en écart.
local function encodeParts(ids, budget)
    local parts, cur, prev = {}, nil, 0
    for _, id in ipairs(ids) do
        local tok = toB36(id - prev)
        if cur and #cur + #SEP + #tok > budget then
            parts[#parts + 1] = cur
            cur, tok = nil, toB36(id)
        end
        cur = cur and (cur .. SEP .. tok) or tok
        prev = id
    end
    if cur then parts[#parts + 1] = cur end
    return parts
end

-- knownSet → { [palier] = { id, … } triés, dédoublonnés }.
local function idsByTier(self, prof, knownSet)
    local byTier, seen = {}, {}
    for id, on in pairs(knownSet or {}) do
        local n = tonumber(id)
        if on and n and n > 0 then
            n = floor(n)
            if not seen[n] then
                seen[n] = true
                local t = self:RecipeTier(prof, n)
                local list = byTier[t]; if not list then list = {}; byTier[t] = list end
                list[#list + 1] = n
            end
        end
    end
    for _, list in pairs(byTier) do sort(list) end
    return byTier
end

-- Messages RI d'un métier, PAR PALIER : { { tier = t, msgs = { … } }, … } triés par palier, ou nil.
-- Un registre qui tient en un message rend { { tier = "entier", msgs = { "RI|prof|ids" } } }.
-- `knownSet` : par défaut MON registre ; `cap` : octets max d'un message (LEGACY_MAX pour le registre
-- entier, RI_CAP pour un morceau de palier — un relayeur passe moins, pour son enveloppe).
function lib:BuildRITiers(prof, knownSet, cap)
    if not prof then return nil end
    knownSet = knownSet or (self.myKnown and self.myKnown[prof])
    local whole = self:EncodeKnownIDs(knownSet)
    if not whole then return nil end
    local single = "RI|" .. prof .. "|" .. whole
    if #single <= (cap or LEGACY_MAX) then return { { tier = "entier", msgs = { single } } } end
    local byTier = idsByTier(self, prof, knownSet)
    local tiers = {}
    for t in pairs(byTier) do tiers[#tiers + 1] = t end
    if #tiers == 0 then return nil end
    sort(tiers)
    local mask, head = concat(tiers), "RI|" .. prof .. "|"
    local budget = (cap or RI_CAP) - #head - TAG_ROOM - #mask
    if budget < 16 then return nil end
    local out = {}
    for _, t in ipairs(tiers) do
        local parts, msgs = encodeParts(byTier[t], budget), {}
        if #parts > MAX_PARTS then return nil end
        for k, p in ipairs(parts) do
            local tag = (#parts == 1) and tostring(t) or (t .. "." .. k .. "/" .. #parts)
            msgs[k] = head .. p .. "|" .. tag .. "|" .. mask
        end
        out[#out + 1] = { tier = t, msgs = msgs }
    end
    return out
end

-- Les mêmes messages, à plat, dans l'ordre des paliers.
function lib:BuildRIMessages(prof, knownSet, cap)
    local out = {}
    for _, e in ipairs(self:BuildRITiers(prof, knownSet, cap) or {}) do
        for _, m in ipairs(e.msgs) do out[#out + 1] = m end
    end
    return (#out > 0) and out or nil
end

-- Forme d'avant REV 2, en UN message, SANS limite : coupée par le serveur au-delà de 255 octets.
-- BuildRITiers la rend d'elle-même quand le registre tient ; gardée pour les hôtes qui n'y sont pas passés.
function lib:BuildRI(prof)
    if not prof then return nil end
    local payload = self:EncodeKnownIDs(self.myKnown and self.myKnown[prof])
    if not payload then return nil end
    return string.format("RI|%s|%s", prof, payload)
end

-- Parse un message RI → prof, payload, palier, k, n, masque ; ou nil. Ne stocke rien (l'hôte gère
-- le roster). Forme d'avant REV 2 (sans suffixe) : palier nil, un registre ENTIER. Un palier en un
-- seul message : k et n nil.
function lib:ParseRI(message)
    local prof, payload, tail = (message or ""):match("^RI|([^|]*)|([^|]*)(.*)$")
    if not (prof and prof ~= "" and payload ~= "") then return nil end
    if tail == "" then return prof, payload end
    local tag, mask = tail:match("^|([%d%./]+)|([0-4]*)$")
    if not tag then return nil end
    local t, k, n = tag:match("^([0-4])%.(%d+)/(%d+)$")
    if not t then t = tag:match("^([0-4])$") end
    if not t then return nil end
    k, n = tonumber(k), tonumber(n)
    if n and (n < 2 or n > MAX_PARTS or k < 1 or k > n) then return nil end
    if mask ~= "" and not mask:find(t, 1, true) then return nil end   -- palier absent de son masque
    return prof, payload, tonumber(t), k, n, mask
end
