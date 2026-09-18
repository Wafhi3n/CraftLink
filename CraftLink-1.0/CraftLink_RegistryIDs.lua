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
local REGISTRY_IDS_REV = 1
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

-- ------------------------------------------------------------------
-- Fil RI : "RI|prof|payload"
-- ------------------------------------------------------------------
-- VERBE DISTINCT de RK, volontairement. Un client qui ne connaît pas RI l'ignore (verbe inconnu)
-- au lieu de lire des IDs comme un bitfield et d'afficher n'importe quoi. Pas de `dataVersion` :
-- il n'y a plus de catalogue partagé à faire concorder — c'est tout l'intérêt de cette forme.

function lib:BuildRI(prof)
    if not prof then return nil end
    local payload = self:EncodeKnownIDs(self.myKnown and self.myKnown[prof])
    if not payload then return nil end
    return string.format("RI|%s|%s", prof, payload)
end

-- Parse un message RI → (prof, payload) ou nil. Ne stocke rien (l'hôte gère le roster).
function lib:ParseRI(message)
    local prof, payload = (message or ""):match("^RI|([^|]*)|(.*)$")
    if prof and prof ~= "" and payload and payload ~= "" then return prof, payload end
    return nil
end
