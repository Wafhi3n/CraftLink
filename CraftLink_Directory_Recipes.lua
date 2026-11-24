-- CraftLink_Directory_Recipes.lua — COUTURE de lecture du registre « qui sait crafter quoi » d'un artisan.
-- Copié de Directory_Recipes.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
--
-- Pourquoi. Le registre reçu peut prendre DEUX formes selon la saveur de l'émetteur :
--   * BITFIELD (verbe RK) — positions de bits dans le catalogue partagé. N'a de sens que si les
--     deux bouts ont EXACTEMENT le même catalogue, d'où le `dataVersion` sur le fil.
--   * IDENTIFIANTS (verbe RI, Camelot / WoW: Forever) — les recipeID eux-mêmes. Auto-descriptif,
--     aucune version à faire concorder (cf. CraftLink_RegistryIDs.lua).
--
-- Avant cette couture, la garde `r.recipeDV == lib:DataVersion()` était RECOPIÉE dans quatre
-- modules (Handoff, LazyGold, UI_Artisans_Needs, UI_Post_Artisans), chacun appelant `HasBit`
-- directement. Ajouter une seconde forme y aurait ajouté quatre branchements — et la prochaine
-- forme, quatre de plus. Ici les appelants posent une QUESTION (« connaît-il cette recette ? ») et
-- ignorent la réponse à « sous quelle forme est-ce stocké ».
--
-- Même philosophie que la table d'API du socle métier (`*_Craft.lua`) : un seul endroit sait que
-- les saveurs divergent.
--
-- NB : les deux jeux étant séparés (un client Camelot ne parle qu'à des clients Camelot), un même
-- roster ne mélange pas les formes en pratique. La couture reste écrite pour les deux — c'est ce
-- qui la rend indépendante de cette hypothèse.

local _, NS = ...
NS = NS or _G.CraftLink
local Dir = NS.Directory
if not Dir then return end

local function CL() return LibStub and LibStub:GetLibrary("CraftLink-1.0", true) end

-- Quelle forme exploitable porte cette fiche pour ce métier ?
-- Rend (forme, donnée) : "ids"+payload, "bits"+hex, ou nil si rien n'est utilisable.
--
-- Les IDs passent EN PREMIER : ils ne dépendent d'aucun catalogue, donc ils sont toujours lisibles.
-- Le bitfield, lui, n'est rendu QUE si les catalogues concordent — sinon les positions désignent
-- d'autres recettes et on afficherait du faux. C'est la garde historique, désormais à un seul
-- endroit : un écart de version donne « pas de données », jamais une mauvaise réponse.
function Dir:RecipeForm(r, prof)
    if not (r and prof) then return nil end
    local payload = r.recipeIDs and r.recipeIDs[prof]
    if payload and payload ~= "" then return "ids", payload end
    local hex = r.recipes and r.recipes[prof]
    if not (hex and hex ~= "") then return nil end
    local c = CL()
    if c and c.DataVersion and r.recipeDV == c:DataVersion() then return "bits", hex end
    return nil
end

-- Prédicat « ce joueur connaît-il cette recette ? », ou nil si aucune donnée exploitable.
-- Rendre nil PLUTÔT qu'un prédicat toujours faux est délibéré : l'appelant doit pouvoir
-- distinguer « il ne la connaît pas » de « je n'en sais rien » — les deux ne s'affichent pas pareil.
function Dir:RecipeTester(r, prof)
    local form, data = self:RecipeForm(r, prof)
    local c = CL()
    if not (form and c) then return nil end
    if form == "ids" then
        if not c.HasRecipeID then return nil end
        return function(spellID) return c:HasRecipeID(data, spellID) end
    end
    if not c.HasBit then return nil end
    return function(spellID) return c:HasBit(prof, data, spellID) end
end

-- Le set des recettes connues { [spellID] = true }, ou nil si rien d'exploitable.
-- Pour ÉNUMÉRER (bourse, plan de route), pas pour tester une recette — dans ce cas utiliser
-- RecipeTester, qui ne décode rien quand la réponse tient en un bit.
-- Les deux codecs rendent déjà la même forme, l'unification est donc gratuite.
function Dir:RecipeKnownSet(r, prof)
    local form, data = self:RecipeForm(r, prof)
    local c = CL()
    if not (form and c) then return nil end
    if form == "ids" then
        return c.DecodeKnownIDs and c:DecodeKnownIDs(data) or nil
    end
    return c.DecodeKnown and c:DecodeKnown(prof, data) or nil
end

-- Y a-t-il de quoi répondre pour ce métier ? (gardes de validité, avant un travail coûteux)
function Dir:HasRecipeData(r, prof)
    return (self:RecipeForm(r, prof)) ~= nil
end

-- Clé de cache : change dès que la donnée change, quelle que soit la forme. La forme est dans la
-- clé — deux registres de formes différentes ne doivent jamais se répondre l'un pour l'autre.
function Dir:RecipeFingerprint(r, prof)
    local form, data = self:RecipeForm(r, prof)
    if not form then return nil end
    return form .. "|" .. tostring(prof) .. "|" .. data
end

-- ------------------------------------------------------------------
-- Le FIL : quelle forme j'émets, et comment je reçois l'autre
-- ------------------------------------------------------------------

-- Les messages de registre à diffuser pour ce métier : une LISTE, ou nil si je n'ai rien à dire.
-- Sur Camelot on émet des IDENTIFIANTS (RI) : il n'y a pas de catalogue partagé à faire concorder,
-- et le contenu du jeu bouge encore. Ailleurs, le bitfield (RK) reste plus compact et le catalogue
-- est stable. Les deux jeux étant séparés, un client ne rencontre jamais l'autre forme en pratique.
--
-- RI part PAR PALIER du jeu, en morceaux si un palier dépasse (CraftLink REGISTRY_IDS_REV 2) : un
-- message d'addon de plus de 255 octets arrive COUPÉ, en silence (mesuré le 2026-10-05).
-- `onlyChanged` : seulement les paliers qui ont changé depuis la dernière annonce à tous ; `record` :
-- cette annonce part à TOUS les pairs, elle devient la référence (une réponse à un seul joueur, non).
function Dir:RecipeMessages(prof, onlyChanged, record)
    local c = CL()
    if not (c and prof) then return nil end
    local mainline = NS.Api and NS.Api.IS_MAINLINE
    if mainline and c.BuildRITiers then return self:_TierMessages(c, prof, onlyChanged, record) end
    local one = (mainline and c.BuildRI and c:BuildRI(prof)) or (not mainline and c.BuildRK and c:BuildRK(prof))
    return one and { one } or nil
end

function Dir:_TierMessages(c, prof, onlyChanged, record)
    local tiers = c:BuildRITiers(prof)
    if not tiers then return nil end
    self._riSent = self._riSent or {}
    local sent, now, out = self._riSent[prof] or {}, {}, {}
    for _, e in ipairs(tiers) do
        local key = table.concat(e.msgs, "\n")   -- le masque y est : un palier vidé change tous les autres
        now[e.tier] = key
        if not onlyChanged or sent[e.tier] ~= key then
            for _, m in ipairs(e.msgs) do out[#out + 1] = m end
        end
    end
    if record then self._riSent[prof] = now end
    return (#out > 0) and out or nil
end

-- ------------------------------------------------------------------
-- Réception par palier (RI, REGISTRY_IDS_REV 2)
-- ------------------------------------------------------------------
-- Un palier reçu REMPLACE ce palier, et lui seul ; `recipeIDs[prof]` est ensuite recollé (union des
-- paliers), et c'est lui que lisent tous les consommateurs (RecipeTester, relais, Social…). Un palier
-- en morceaux n'est remplacé qu'une fois TOUS ses morceaux arrivés : sinon l'ancien reste.
local PART_TTL = 120   -- s : un palier dont il manque un morceau après ce délai repart de zéro

local function now() return (GetTime and GetTime()) or 0 end

-- Range le morceau k/n ; rend le payload du palier entier quand le dernier arrive, sinon nil.
-- `key` : la source (émetteur, ou relayeur et origine), pour ne jamais mêler deux registres.
function Dir:_CollectRIPart(key, prof, tier, k, n, payload)
    self._riParts = self._riParts or {}
    local t, id = now(), key .. "\0" .. prof .. "\0" .. tier
    local p = self._riParts[id]
    if not p or p.n ~= n or t - p.at > PART_TTL then
        for old, q in pairs(self._riParts) do
            if t - q.at > PART_TTL then self._riParts[old] = nil end
        end
        p = { n = n, at = t, got = {}, count = 0 }
        self._riParts[id] = p
    end
    if not p.got[k] then p.count = p.count + 1 end
    p.got[k] = payload
    if p.count < n then return nil end
    self._riParts[id] = nil
    local c = CL()
    return c and c.UnionKnownIDs and c:UnionKnownIDs(p.got) or nil
end

-- Applique un message RI déjà lu à `store` (une fiche du roster, ou son lot relayé). Rend true si
-- le registre a changé. Forme d'avant REV 2 (palier nil) : un registre ENTIER, qui remplace tout.
function Dir:_ApplyRI(store, key, prof, payload, tier, k, n, mask)
    store.recipeIDs = store.recipeIDs or {}
    if not tier then
        store.recipeIDs[prof] = payload
        if store.recipeTiers then store.recipeTiers[prof] = nil end
        return true
    end
    if n then
        payload = self:_CollectRIPart(key, prof, tier, k, n, payload)
        if not payload then return false end
    end
    local c = CL()
    if not (c and c.UnionKnownIDs) then return false end
    store.recipeTiers = store.recipeTiers or {}
    local tiers = store.recipeTiers[prof] or {}
    store.recipeTiers[prof] = tiers
    tiers[tier] = payload
    if mask and mask ~= "" then
        for t in pairs(tiers) do
            if not mask:find(tostring(t), 1, true) then tiers[t] = nil end
        end
    end
    store.recipeIDs[prof] = c:UnionKnownIDs(tiers)
    return true
end

-- RI reçu (recettes d'un autre, forme identifiants) → cache roster persistant.
-- Miroir exact de Dir:OnRK, garde comprise : SK fait foi sur les métiers, donc un registre annoncé
-- pour un métier que l'émetteur ne déclare PAS est refusé. Sans ça, un perso pourrait faire passer
-- les recettes d'un de ses alts pour les siennes — trou déjà fermé une fois côté RK, à ne pas
-- rouvrir en ajoutant un second verbe.
function Dir:OnRI(sender, message)
    local c = CL()
    if not (sender and c and c.ParseRI) then return end
    local prof, payload, tier, k, n, mask = c:ParseRI(message)
    if not prof then return end
    local r = self.roster[sender]; if not r then r = {}; self.roster[sender] = r end
    if r.skill and next(r.skill) and not r.skill[prof] then return end  -- anti fuite d'alts
    self:_ApplyRI(r, sender, prof, payload, tier, k, n, mask)
    self:_ApplySource(sender, r)          -- guilde/ami si reconnu, sinon « recent »
    r.lastSeen = time()
    self.online[sender] = true            -- présence passive : un message prouve la présence
    self:_NoteLinked(sender, r)
    Dir:_Changed()
end

-- Ce joueur a-t-il UN registre quelconque pour ce métier, même illisible ? Sert aux replis qui se
-- contentent de savoir qu'il exerce ce métier (sans prétendre connaître ses recettes).
function Dir:HasAnyRecipeRecord(r, prof)
    if not (r and prof) then return false end
    return ((r.recipes and r.recipes[prof]) or (r.recipeIDs and r.recipeIDs[prof])) ~= nil
end
