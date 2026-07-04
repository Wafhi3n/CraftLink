-- CraftLink-1.0 — Registre de recettes : codec hexadécimal du bitfield "recettes connues".
--
-- Idée : "quelles recettes de ce métier je connais" = un champ de bits indexé par le catalogue
-- canonique (CraftLink-1.0.lua). On le sérialise en hexa compact pour le diffuser en UN addon
-- message (~300 recettes => ~38 octets => ~76 chars hex).
--
-- Convention de bits : position i (1-based dans `recipes`) -> octet floor((i-1)/8)+1,
-- bit (i-1)%8, poids faible d'abord. Encode et décode partagent cette lib, donc seule la
-- cohérence interne compte. Les octets de poids fort tout-à-zéro sont tronqués (un set qui
-- ne touche que des recettes basses produit un hex court ; le décodage complète par des 0).
--
-- Lua 5.1 (WoW) n'a pas d'opérateurs bit-à-bit : on travaille en arithmétique via POW.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber (cf. CraftLink_Transport) : fichier compagnon qui re-patche la lib hors du gate de
-- version LibStub:NewLibrary → une copie plus ANCIENNE chargée après nous écraserait le codec hex.
-- On refuse de réécraser une révision >= la nôtre. BUMP à chaque évolution du codec (+ resync hôtes).
local REGISTRY_REV = 1
if (lib._registryRev or 0) >= REGISTRY_REV then return end
lib._registryRev = REGISTRY_REV

local POW = { 1, 2, 4, 8, 16, 32, 64, 128 }  -- POW[b+1] = 2^b
local floor, format, concat = math.floor, string.format, table.concat

-- knownSet = { [spellID] = true }. Retourne (hexString, nbBitsPosés).
-- Les spellID hors catalogue du métier sont ignorés (ex. recette d'une autre version).
function lib:EncodeKnown(prof, knownSet)
    local c = self.catalog[prof]
    if not c then return nil, 0 end
    local n      = #c.recipes
    local nbytes = floor((n + 7) / 8)
    local bytes  = {}
    for i = 1, nbytes do bytes[i] = 0 end
    local count = 0
    for spellID in pairs(knownSet or {}) do
        local p = c.pos[spellID]
        if p then
            local bi  = floor((p - 1) / 8) + 1
            local bit = (p - 1) % 8
            if floor(bytes[bi] / POW[bit + 1]) % 2 == 0 then
                bytes[bi] = bytes[bi] + POW[bit + 1]
                count = count + 1
            end
        end
    end
    -- Troncature des octets nuls de poids fort
    local last = nbytes
    while last > 0 and bytes[last] == 0 do last = last - 1 end
    if last == 0 then return "", 0 end
    local out = {}
    for i = 1, last do out[i] = format("%02x", bytes[i]) end
    return concat(out), count
end

-- hex -> knownSet = { [spellID] = true }. Retourne nil si le métier n'est pas catalogué.
function lib:DecodeKnown(prof, hex)
    local c = self.catalog[prof]
    if not c then return nil end
    local recipes, known = c.recipes, {}
    hex = hex or ""
    local nbytes = floor(#hex / 2)
    for i = 1, nbytes do
        local byte = tonumber(hex:sub(i * 2 - 1, i * 2), 16) or 0
        if byte > 0 then
            for bit = 0, 7 do
                if floor(byte / POW[bit + 1]) % 2 == 1 then
                    local spellID = recipes[(i - 1) * 8 + bit + 1]
                    if spellID then known[spellID] = true end
                end
            end
        end
    end
    return known
end

-- Teste UN seul bit sans décoder tout le set : "est-ce que ce hex connaît cette recette ?".
-- Efficace pour les requêtes de roster (WhoKnows/IKnow) qui ne ciblent qu'un spellID.
function lib:HasBit(prof, hex, spellID)
    local c = self.catalog[prof]
    if not c then return false end
    local p = c.pos[spellID]
    if not p then return false end
    local bi  = floor((p - 1) / 8) + 1
    local bit = (p - 1) % 8
    hex = hex or ""
    if #hex < bi * 2 then return false end  -- octet de poids fort tronqué (= 0)
    local byte = tonumber(hex:sub(bi * 2 - 1, bi * 2), 16) or 0
    return floor(byte / POW[bit + 1]) % 2 == 1
end

-- Nombre de recettes connues encodées dans un hex (sans matérialiser le set).
function lib:CountKnown(prof, hex)
    local c = self.catalog[prof]
    if not c then return 0 end
    hex = hex or ""
    local total, nbytes = 0, floor(#hex / 2)
    for i = 1, nbytes do
        local byte = tonumber(hex:sub(i * 2 - 1, i * 2), 16) or 0
        for bit = 0, 7 do
            if floor(byte / POW[bit + 1]) % 2 == 1 then total = total + 1 end
        end
    end
    return total
end
