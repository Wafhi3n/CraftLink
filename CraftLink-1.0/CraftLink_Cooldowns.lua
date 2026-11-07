-- CraftLink-1.0 — « MES cooldowns de recettes » : lecture de la fenêtre métier ouverte
-- (C_TradeSkillUI.GetRecipeCooldown), état en mémoire + sérialisation, et codec du fil CD.
--
-- L'API du jeu ne donne le CD que pour SOI et rend nil aussi bien pour « prête » que pour
-- « sans mécanique de CD » : on ne suit donc QUE les spellID de la table curatée
-- Data/Cooldowns.lua (RecipeCooldown). État stocké en ABSOLU (readyAt epoch time()) pour
-- survivre aux relogs ; le fil transporte du RELATIF (secondes restantes) pour être
-- insensible à la dérive d'horloge entre clients. remain 0 = « prête » CONFIRMÉE
-- (l'absence d'entrée = inconnu). Le roster des AUTRES joueurs vit dans l'hôte (Directory).

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber (même logique que CraftLink_Recipes) : compagnon re-patché hors du gate
-- LibStub. BUMP à chaque évolution du codec CD (+ resync hôtes).
local COOLDOWNS_REV = 7   -- 7 : CD des seules recettes APPRISES, retrait sur preuve ; 6 : rien lu sur le métier d'un AUTRE ; 5 : `GetAllRecipeIDs` rétablie
if (lib._cooldownsRev or 0) >= COOLDOWNS_REV then return end
lib._cooldownsRev = COOLDOWNS_REV

-- État partagé (singleton) : [profCanonical] = { [spellID] = readyAt (epoch) }
lib.myCooldowns = lib.myCooldowns or {}

local _time = time or (os and os.time)          -- headless : time() n'existe qu'en client WoW
local STALE_AFTER = 14 * 86400                  -- purge d'un readyAt dépassé depuis > 14 j
local REMAIN_CAP  = 864000                      -- restant max accepté sur le fil : 10 j
local MAX_ENTRIES = 40                          -- entrées max par message CD (anti-junk)
local WIRE_CAP    = 230                         -- taille max d'un payload (AddonMessage ≤ 255)

-- ------------------------------------------------------------------
-- Persistance vers/depuis la SavedVariables d'un addon hôte (partition PAR PERSO côté hôte)
-- ------------------------------------------------------------------
-- Copie SV → état, en purgeant (état ET SV) les readyAt dépassés depuis trop longtemps.
-- Un CD expiré RÉCEMMENT est conservé : readyAt passé = « prête », info encore utile.
function lib:LoadMyCooldowns(saved, now)
    if type(saved) ~= "table" then return end
    now = now or _time()
    for prof, set in pairs(saved) do
        if type(set) == "table" then
            local mine = self.myCooldowns[prof]
            if not mine then mine = {}; self.myCooldowns[prof] = mine end
            for sid, readyAt in pairs(set) do
                if type(readyAt) == "number" and readyAt > now - STALE_AFTER then
                    mine[sid] = readyAt
                else
                    set[sid] = nil
                end
            end
        end
    end
end

-- Reflète l'état dans la SV de l'hôte (REMPLACEMENT, pas union : un CD se rend — contrairement
-- aux recettes, l'état courant est la seule vérité).
function lib:SaveMyCooldowns(saved)
    if type(saved) ~= "table" then return end
    for prof in pairs(saved) do saved[prof] = nil end
    for prof, set in pairs(self.myCooldowns) do
        local out = {}
        for sid, readyAt in pairs(set) do out[sid] = readyAt end
        saved[prof] = out
    end
end

-- ------------------------------------------------------------------
-- Lecture de la fenêtre métier ouverte
-- ------------------------------------------------------------------
-- → (profCanonical, { [spellID] = restant en s, 0 = prête }, { [spellID] = true } non apprises)
-- pour les seules recettes cataloguées à CD, ou (prof, nil) si le métier n'en a pas / API absente.
--
-- ⚠️ MAINLINE SEUL depuis le 2026-09-21 (cf. l'en-tête de CraftLink_Recipes) : les deux boucles
-- Classic ont été retirées. Un recipeID EST un spellID, et `C_TradeSkillUI.GetRecipeCooldown` rend
-- le restant — nil = pas de CD en cours, donc recette PRÊTE (0), jamais « pas d'avis ».
-- Cette fonction est ABSENTE de la doc d'API générée du client, mais Blizzard l'appelle dans son
-- propre Blizzard_Professions (1.60.1) : elle existe. La doc générée ne prouve pas une absence.
-- Énumération par `GetAllRecipeIDs` d'abord (vivante, mesurée) : elle ignore la recherche et les
-- catégories du joueur — sinon une transmutation hors filtre sortirait du relevé des CD.
--
-- ⚠️ CE « nil = PRÊTE » NE VAUT QUE POUR UNE RECETTE APPRISE (COOLDOWNS_REV 7). L'énumérateur rend
-- aussi les recettes NON apprises (cf. modernKnownSet dans CraftLink_Recipes), et le restant d'une
-- recette qu'on n'a pas est nil lui aussi. Sans la preuve `learned`, chaque recette à CD de la liste
-- sortait « prête » et partait sur le fil. Relevé le 2026-10-05 dans une SavedVariable du banc : un
-- tailleur de rang 56 portait l'Étoffe lunaire (apprise à 250), et des inconnus diffusaient la même
-- chose sur la bêta, plafonnée au niveau 30. Sans `GetRecipeInfo`, rien n'est prouvable : pas d'avis.

-- true = apprise, false = déclarée NON apprise, nil = aucun avis (info absente, appel qui lève).
local function learnedState(c, sid)
    local ok, info = pcall(c.GetRecipeInfo, sid)
    if not (ok and type(info) == "table") then return nil end
    if info.learned == true then return true end
    if info.learned == false then return false end
    return nil
end

-- La fenêtre est-elle CHARGÉE ? Vrai dès qu'une recette de la liste est prouvée apprise. Même garde
-- que le retrait des recettes (CraftLink_Recipes, RECIPES_REV 7) : une liste dont les infos ne sont
-- pas encore arrivées ne prouve pas « non appris ». Ne parcourt la liste que s'il y a à retirer.
local function windowProven(c, list)
    for _, id in ipairs(list) do
        if learnedState(c, id) == true then return true end
    end
    return false
end

function lib:ReadOpenCooldowns()
    if not self.OpenProfession then return nil, nil end   -- compagnon Recipes absent (lib partielle)
    local prof = self:OpenProfession()
    if not prof then return nil, nil end
    -- Le métier d'un AUTRE (lien, guilde, PNJ) : ses recettes à CD ne sont pas les miennes, et un
    -- restant nil y vaudrait « prête » — on annoncerait des transmutations qu'on n'a pas.
    if self.IsOwnProfessionOpen and not self:IsOwnProfessionOpen() then return prof, nil end
    local cds = self:CooldownRecipes(prof)
    if not cds then return prof, nil end
    local c   = C_TradeSkillUI
    local get = c and (c.GetAllRecipeIDs or c.GetFilteredRecipeIDs)
    if not (get and c.GetRecipeCooldown and c.GetRecipeInfo) then return prof, nil end
    local ok, list = pcall(get)
    if not (ok and type(list) == "table") then return prof, nil end
    local out, unlearned = {}, {}
    for _, sid in ipairs(list) do
        if cds[sid] then
            local learned = learnedState(c, sid)
            if learned then
                local ok2, remain = pcall(c.GetRecipeCooldown, sid)
                out[sid] = (ok2 and tonumber(remain)) or 0
            elseif learned == false then
                unlearned[sid] = true
            end
        end
    end
    if next(unlearned) and not windowProven(c, list) then unlearned = {} end
    return prof, out, unlearned
end

-- Scan + mise à jour de l'état. Retourne (prof, changed) ; l'hôte décide (sauver SV, diffuser).
-- Tolérance 90 s : le restant lu fluctue d'une lecture à l'autre, on ne « change »
-- que sur un vrai mouvement. Une recette PRÊTE garde son readyAt d'origine (pas de re-stamp
-- à chaque scan, sinon fausses annonces en boucle).
-- RETRAIT SUR PREUVE : une recette que le client déclare non apprise sort de mes CD — c'est ce qui
-- nettoie un « prête » relevé à tort avant COOLDOWNS_REV 7 et gardé par la SavedVariable.
function lib:ScanOpenCooldowns(now)
    now = now or _time()
    local prof, remains, unlearned = self:ReadOpenCooldowns()
    if not prof or not remains then return prof, false end
    local mine = self.myCooldowns[prof]
    if not mine then mine = {}; self.myCooldowns[prof] = mine end
    local changed = false
    for sid in pairs(unlearned or {}) do
        if mine[sid] then mine[sid] = nil; changed = true end
    end
    for sid, remain in pairs(remains) do
        local old = mine[sid]
        if remain <= 0 then
            if not old or old > now then mine[sid] = now; changed = true end
        else
            local readyAt = now + math.ceil(remain)
            if not old or math.abs(readyAt - old) > 90 then mine[sid] = readyAt; changed = true end
        end
    end
    return prof, changed
end

-- Pose le départ d'un CD SANS fenêtre (ex. cast vu par l'hôte). Propage au groupe partagé :
-- caster un sort du groupe verrouille tout le groupe pour LA durée du sort casté (Wowhead).
-- N'étend qu'aux recettes que je connais (myKnown) — pas de CD fantôme sur du non-appris.
function lib:NoteCooldownStart(prof, spellID, now)
    local dur = self:RecipeCooldown(prof, spellID)
    if not dur then return nil end
    now = now or _time()
    local mine = self.myCooldowns[prof]
    if not mine then mine = {}; self.myCooldowns[prof] = mine end
    local readyAt = now + dur
    mine[spellID] = readyAt
    local group = self:RecipeCdGroup(prof, spellID)
    if group then
        local known = self.myKnown and self.myKnown[prof]
        for sid in pairs(self:CooldownRecipes(prof) or {}) do
            if sid ~= spellID and known and known[sid]
               and self:RecipeCdGroup(prof, sid) == group then
                mine[sid] = readyAt
            end
        end
    end
    return readyAt
end

-- Liste triée des métiers où j'ai au moins un CD suivi (pour tout diffuser).
function lib:MyCooldownProfessions()
    local out = {}
    for prof, set in pairs(self.myCooldowns) do
        if next(set) then out[#out + 1] = prof end
    end
    table.sort(out)
    return out
end

-- ------------------------------------------------------------------
-- Fil CD : "CD|prof|spellID,restant[;spellID,restant]…" (restant en s, 0 = prête)
-- ------------------------------------------------------------------
-- → liste de payloads (découpés à WIRE_CAP octets), ou nil si rien à diffuser. Tri par
-- spellID : ordre déterministe (tests + diff réseau stables). L'émetteur envoie l'état
-- de TOUTES ses recettes à CD suivies — le récepteur n'a pas besoin de connaître les groupes.
--
-- Seules partent les recettes de MON registre (myKnown), quand j'en ai un pour ce métier. Un CD
-- relevé à tort avant COOLDOWNS_REV 7 reste dans la SavedVariable jusqu'à la prochaine ouverture de
-- la fenêtre : ce filtre le fait taire dès la mise à jour. Le registre et les CD sont lus par le même
-- scan, sur la même preuve `learned` : un vrai CD y est toujours. Sans registre du tout pour ce
-- métier (CD posé par NoteCooldownStart avant toute capture), on n'a pas d'avis et on émet.
function lib:BuildCD(prof, now)
    local mine = self.myCooldowns[prof]
    if not mine or not next(mine) then return nil end
    now = now or _time()
    local known = self.myKnown and self.myKnown[prof]
    if known and not next(known) then known = nil end
    local sids = {}
    for sid in pairs(mine) do
        if not known or known[sid] then sids[#sids + 1] = sid end
    end
    if #sids == 0 then return nil end
    table.sort(sids)
    local head, msgs, cur = "CD|" .. prof .. "|", {}, nil
    for _, sid in ipairs(sids) do
        local remain = math.ceil(mine[sid] - now)
        if remain < 0 then remain = 0 end
        local entry = sid .. "," .. remain
        if not cur then
            cur = head .. entry
        elseif #cur + 1 + #entry <= WIRE_CAP then
            cur = cur .. ";" .. entry
        else
            msgs[#msgs + 1] = cur
            cur = head .. entry
        end
    end
    if cur then msgs[#msgs + 1] = cur end
    return msgs
end

-- Parse un message CD → (prof, { {sid=, remain=}, … }) ou nil. PUR (pas d'horloge) ; ne
-- stocke rien (l'hôte gère le roster). Validation : métier catalogué À CD, spellID catalogué
-- CD (anti-junk), restant borné, nombre d'entrées plafonné (au-delà : tronqué).
function lib:ParseCD(message)
    local prof, body = (message or ""):match("^CD|([^|]+)|(.+)$")
    if not prof then return nil end
    local cds = self:CooldownRecipes(prof)
    if not cds then return nil end
    local out = {}
    for sidStr, remStr in body:gmatch("(%d+),(%d+)") do
        local sid, remain = tonumber(sidStr), tonumber(remStr)
        if sid and remain and cds[sid] and remain <= REMAIN_CAP then
            out[#out + 1] = { sid = sid, remain = remain }
            if #out >= MAX_ENTRIES then break end
        end
    end
    if #out == 0 then return nil end
    return prof, out
end
