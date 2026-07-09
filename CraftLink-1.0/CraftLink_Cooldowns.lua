-- CraftLink-1.0 — « MES cooldowns de recettes » : lecture de la fenêtre métier ouverte
-- (GetTradeSkillCooldown), état en mémoire + sérialisation, et codec du fil CD.
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
local COOLDOWNS_REV = 1
if (lib._cooldownsRev or 0) >= COOLDOWNS_REV then return end
lib._cooldownsRev = COOLDOWNS_REV

-- État partagé (singleton) : [profCanonical] = { [spellID] = readyAt (epoch) }
lib.myCooldowns = lib.myCooldowns or {}

local _time = time or (os and os.time)          -- headless : time() n'existe qu'en client WoW
local STALE_AFTER = 14 * 86400                  -- purge d'un readyAt dépassé depuis > 14 j
local REMAIN_CAP  = 864000                      -- restant max accepté sur le fil : 10 j
local MAX_ENTRIES = 40                          -- entrées max par message CD (anti-junk)
local WIRE_CAP    = 230                         -- taille max d'un payload (AddonMessage ≤ 255)

local function spellFromLink(link)
    return link and tonumber(link:match("enchant:(%d+)")) or nil
end

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
-- → (profCanonical, { [spellID] = restant en s, 0 = prête }) pour les seules recettes
-- cataloguées à CD, ou (prof, nil) si le métier n'en a pas / API absente. Même résolution
-- de spellID que ReadOpenKnown. GetCraftCooldown (API Craft) n'existe qu'à partir du
-- client TBC — gated : en Vanilla l'Enchantement n'a de toute façon aucune recette à CD.
function lib:ReadOpenCooldowns()
    if not self.OpenProfession then return nil, nil end   -- compagnon Recipes absent (lib partielle)
    local prof, isCraft = self:OpenProfession()
    if not prof then return nil, nil end
    local cds = self:CooldownRecipes(prof)
    if not cds then return prof, nil end
    local out = {}
    if isCraft then
        if not GetCraftCooldown then return prof, nil end
        local n = (GetNumCrafts and GetNumCrafts()) or 0
        for i = 1, n do
            local _, _, ctype = GetCraftInfo(i)
            if ctype ~= "header" then
                local sid = spellFromLink(GetCraftItemLink and GetCraftItemLink(i))
                if sid and cds[sid] then out[sid] = GetCraftCooldown(i) or 0 end
            end
        end
    else
        local n   = (GetNumTradeSkills and GetNumTradeSkills()) or 0
        local i2s = self:ItemToSpell(prof) or {}
        for i = 1, n do
            local _, stype = GetTradeSkillInfo(i)
            if stype ~= "header" and stype ~= "subheader" then
                local sid = spellFromLink(GetTradeSkillRecipeLink and GetTradeSkillRecipeLink(i))
                if not sid then
                    local link   = GetTradeSkillItemLink and GetTradeSkillItemLink(i)
                    local itemID = link and tonumber(link:match("item:(%d+)"))
                    sid = itemID and i2s[itemID] or nil
                end
                if sid and cds[sid] then out[sid] = GetTradeSkillCooldown(i) or 0 end
            end
        end
    end
    return prof, out
end

-- Scan + mise à jour de l'état. Retourne (prof, changed) ; l'hôte décide (sauver SV, diffuser).
-- Tolérance 90 s : GetTradeSkillCooldown fluctue d'une lecture à l'autre, on ne « change »
-- que sur un vrai mouvement. Une recette PRÊTE garde son readyAt d'origine (pas de re-stamp
-- à chaque scan, sinon fausses annonces en boucle).
function lib:ScanOpenCooldowns(now)
    now = now or _time()
    local prof, remains = self:ReadOpenCooldowns()
    if not prof or not remains then return prof, false end
    local mine = self.myCooldowns[prof]
    if not mine then mine = {}; self.myCooldowns[prof] = mine end
    local changed = false
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
function lib:BuildCD(prof, now)
    local mine = self.myCooldowns[prof]
    if not mine or not next(mine) then return nil end
    now = now or _time()
    local sids = {}
    for sid in pairs(mine) do sids[#sids + 1] = sid end
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
