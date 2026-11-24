-- CraftLink_Directory_Skills.lua — niveaux de compétence (couche « profil » de l'annuaire), copié de
-- Directory_Skills.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
--
-- Capture MES niveaux de métier (API skill, lisibles sans ouvrir la fenêtre), les diffuse (verbe SK), et
-- reçoit ceux des autres → Dir.roster[name].skill/.level/.rep. Trois morceaux du SK appartiennent à
-- l'hôte et n'en partent que s'il les fournit : `rep=` (commandes livrées, Dir.Delivered), `cv=` (sa
-- version, Dir._MyVersion) et `rl=1` (relais de confiance, Dir.OnTrustEnvelope). Le miroir par perso de
-- l'onglet « Mes artisans » de COC passe par Dir.OnMySkills.

local _, NS = ...
NS = NS or _G.CraftLink
local Dir = NS.Directory

local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)

-- L'hôte garde une copie PAR PERSO de mes niveaux (COC : onglet « Mes artisans »).
local function mirrorMySkills(skills)
    if Dir.OnMySkills then Dir:OnMySkills(skills) end
end

-- L'API skill existe sous DEUX formes qui ne se recouvrent pas, et c'est un piège à double détente :
--   * Classic Era/TBC/Wrath : globales `GetNumSkillLines` / `GetSkillLineInfo(i)`, qui rend un TUPLE.
--   * Forever/Camelot (MAINLINE) : `C_SkillInfo.GetNumSkillLines` / `.GetSkillLineInfo(i)`, qui rend
--     UNE TABLE (`SkillLineAttributes`) — et où les globales n'existent PAS.
-- Le portage Forever a manqué les deux : la garde sortait en silence faute de global, donc `mySkills`
-- restait VIDE. Conséquence bien plus large que le menu « Mes métiers » qui l'a révélé : `_SkillPayload`
-- se construit sur `mySkills`, donc le fil SK n'annonçait **aucun métier** — sur la cible du projet.
-- Les deux helpers acceptent les deux formes DEPUIS LES DEUX points d'entrée : c'est le type du retour
-- qui tranche, jamais la saveur supposée. Une garde par saveur redeviendrait fausse au prochain portage.
local function numSkillLines()
    local get = (C_SkillInfo and C_SkillInfo.GetNumSkillLines) or GetNumSkillLines
    if not get then return nil end           -- aucune API : ne RIEN toucher (surtout pas vider mySkills)
    return get() or 0
end

-- Rend (name, isHeader, rank, maxRank). On passe par `{ get(i) }` et non par une destructuration
-- positionnelle : sur la forme TABLE, `local a, b = get(i)` rend b = nil SANS erreur — c'est
-- exactement le silence qu'on corrige ici, et il ne doit pas pouvoir revenir par la petite porte.
local function skillLineInfo(i)
    local get = (C_SkillInfo and C_SkillInfo.GetSkillLineInfo) or GetSkillLineInfo
    if not get then return nil end
    local r = { get(i) }
    if type(r[1]) == "table" then
        local a = r[1]
        return a.name, a.isHeader, a.rank, a.maxRank
    end
    return r[1], r[2], r[4], r[7]            -- tuple Classic : name, isHeader, rank(4), maxRank(7)
end

-- Capture MES niveaux de métier via l'API skill. Le nom de ligne est localisé → ResolveProfession
-- le ramène à la clé interne EN (les aliases de CraftLink contiennent les noms FR/DE/ES).
function Dir:CaptureSkills()
    if not CraftLink then return end
    local n = numSkillLines()
    if not n then return end
    self.mySkills = {}
    for i = 1, n do
        local name, isHeader, rank, maxRank = skillLineInfo(i)
        if name and not isHeader and rank and rank > 0 then
            local key = CraftLink:ResolveProfession(name)
            if key and CraftLink.professions[key] then self.mySkills[key] = { rank, maxRank } end
        end
    end
    if NS.db then NS.db.mySkills = self.mySkills; mirrorMySkills(self.mySkills) end
end

-- Mon royaume sous le méga-serveur (GetRealmID = la partie serveur de mon GUID, mesuré le 2026-10-07) :
-- un canal s'arrête au royaume, le pont entre royaumes en a besoin (spec pont-royaumes). nil sans l'API.
function Dir:_MyRealmID()
    local ok, id = pcall(function() return GetRealmID and GetRealmID() end)
    id = ok and tonumber(id) or nil
    return (id and id > 0) and id or nil
end

-- Fil SK : "SK|lvl=<n>|[rm=<royaume>;]key,cur,max;...[;rep=<n>][;cv=<ver>]". rep (crafts livrés) et cv
-- (ma version, cf. Directory_Version) = pseudo-chunks FINAUX ; rm = PREMIER morceau : le jeu coupe un
-- message à 255 octets sans prévenir, une fin coupée ferait d'un rm=4618 un rm=46. Tous trois sont ignorés
-- par un vieux client (il ne garde que les morceaux clé,cur,max, rep= et cv= : vérifié de v1.30 à v1.44.2).
-- Jamais rien entre « lvl= » et le « | » qui suit (corromprait le niveau chez eux). Pas de cv= depuis un
-- build de dev (Dir:_IsDevBuild) : le banc annonçait sa version pas encore publiée à tout le royaume.
function Dir:_SkillPayload()
    local parts = {}
    for key, sk in pairs(self.mySkills or {}) do parts[#parts + 1] = key .. "," .. sk[1] .. "," .. sk[2] end
    if #parts == 0 then return nil end
    local lvl = (UnitLevel and UnitLevel("player")) or 0
    local rep = (self.Delivered and self:Delivered()) or 0   -- commandes livrées : compte de l'hôte (COC)
    local tail = (rep > 0) and (";rep=" .. rep) or ""
    if self._MyVersion and not (self._IsDevBuild and self:_IsDevBuild()) then
        self:_MyVersion(); if self._myVerStr then tail = tail .. ";cv=" .. self._myVerStr end
    end
    local rm = self:_MyRealmID()
    local rl = (rm and self.OnTrustEnvelope) and "rl=1;" or ""   -- je sais relayer (Directory_TrustRelay)
    return "SK|lvl=" .. lvl .. "|" .. (rm and ("rm=" .. rm .. ";") or "") .. rl .. table.concat(parts, ";") .. tail
end

function Dir:AnnounceSkills()
    if not (CraftLink and CraftLink:IsNetworkReady()) then return end
    local sk = self:_SkillPayload()
    if sk then CraftLink:Send(sk, "global") end
end

-- Parse le message SK → (skills, level, rep, ver, realm) ou nil. PUR (aucun effet sur le roster) :
-- réutilisé par OnSkill (données directes) ET Directory_Relay (fiche relayée). Formats : "SK|lvl=N|..."
-- (avec niveau) ou ancien "SK|...". rm (royaume), rep, cv (version) : pseudo-chunks (cf. _SkillPayload).
function Dir:_ParseSKBody(message)
    local lvl, body = (message or ""):match("^SK|lvl=(%d+)|(.+)$")
    if not body then body = (message or ""):match("^SK|(.+)$") end
    if not body then return nil end
    local skills, rep, ver, realm, relay = {}, nil, nil, nil, nil
    for chunk in body:gmatch("[^;]+") do
        local rp = chunk:match("^rep=(%d+)$")
        local cv = (not rp) and chunk:match("^cv=(.+)$") or nil
        local rm = chunk:match("^rm=(%d+)$")
        if rp then rep = tonumber(rp)
        elseif cv then ver = cv
        elseif rm then realm = tonumber(rm)
        elseif chunk == "rl=1" then relay = true
        else
            local key, cur, max = chunk:match("^([^,]+),(%d+),(%d+)$")
            if key then skills[key] = { tonumber(cur), tonumber(max) } end
        end
    end
    return skills, lvl and tonumber(lvl) or nil, rep, ver, realm, relay
end

-- Le royaume d'un pair, lu dans SA fiche (jamais d'un relais) ; le pont s'en sert (Directory_Bridge).
function Dir:_NoteRealm(name, realm)
    local r = name and self.roster and self.roster[name]
    if not (r and realm) then return end
    r.realm = realm
    if self.BridgeOnRealm then self:BridgeOnRealm(name, realm) end
end

-- SK reçu (niveaux d'un autre) → cache roster. Le royaume n'est gardé que d'une fiche DIRECTE (ici),
-- jamais d'une fiche relayée : il ne fait foi que pour celui qui l'annonce.
function Dir:OnSkill(sender, message)
    if not sender then return end
    local skills, lvl, rep, ver, realm, relay = self:_ParseSKBody(message)
    if not skills then return end
    if ver and self.NotePeerVersion then self:NotePeerVersion(sender, ver) end   -- version = 1re main (jamais relais)
    local r = self:_Touch(sender)
    if lvl then r.level = lvl end
    if rep then r.rep = rep end
    r.relay = relay or nil                                -- sait relayer (rl=1) : relais de confiance possible
    if realm then self:_NoteRealm(sender, realm) end
    -- SK = énumération COMPLÈTE des métiers RÉELS du perso courant de l'émetteur (GetNumSkillLines,
    -- jamais bleedée par les alts contrairement au RK). On reconstruit à neuf (un métier abandonné
    -- disparaît) puis on s'en sert comme vérité terrain pour purger les RK périmés.
    if next(skills) then
        r.skill = skills
        -- Purge la fuite d'alts : un RK pour un métier que le perso n'a pas réellement (absent du SK)
        -- est périmé/bleedé par un vieux client (ex. « Poisons » diffusé par un non-voleur) → on l'enlève.
        if r.recipes then
            for prof in pairs(r.recipes) do
                if not skills[prof] then r.recipes[prof] = nil end
            end
        end
    end
    Dir:_Changed()
end

-- « Bonjour » DIRIGÉ, niveaux de métier COLLÉS ("HI|SK|…" si j'ai des métiers, sinon "HI" nu) : l'autre
-- apprend mes métiers DÈS le hello, sans round-trip AnnounceTo séparé → moins de transactions, et plus
-- de « Croisé en ligne, 0 métier ». Un client v≤1.15 ignore le corps du HI → rétro-compatible. Sans
-- métier, le royaume seul : "HI|rm=<id>" (un client d'avant n'y cherche que "SK", il l'ignore).
function Dir:_HelloPayload()
    local sk = self:_SkillPayload()
    if sk then return "HI|" .. sk end
    local rm = self:_MyRealmID()
    return rm and ("HI|rm=" .. rm) or "HI"
end

-- Réponse d'annuaire throttlée PAR CIBLE (60 s, comme DiscoverPlayer) : un pair qui me spamme de HI/PING ne
-- peut plus me faire rediffuser tout mon profil (SK+RK×métiers+CD+ALT) à chaque message ; un PING+HI groupé
-- (vieux client) ne déclenche qu'UNE annonce (throttle partagé OnPing/OnHello). 1re sollicitation = plein.
function Dir:_AnnounceToThrottled(target)
    if not target then return end
    self._lastAnnTo = self._lastAnnTo or {}
    local t = (GetTime and GetTime()) or 0
    if (self._lastAnnTo[target] or 0) + 60 > t then return end
    self._lastAnnTo[target] = t
    self:AnnounceTo(target)
end

-- Re-publication COALESCÉE : appelée quand mes recettes changent (plan appris), qu'un cooldown bouge ou
-- qu'un point de métier tombe. Canal plein : 3 s, un message sert tout le monde. Sans canal, une annonce
-- = SK + RI par métier + CD, à CHAQUE pair : en montant un métier (un point par craft), c'était toute ma
-- fiche à tous toutes les 3 à 10 s (vu le 2026-10-03). 60 s suffisent : un arrivant, lui, reçoit ma
-- fiche fraîche tout de suite (_AnnounceToThrottled sur son HI).
local ANNOUNCE_COALESCE = { channel = 3, whisper = 60 }

function Dir:AnnounceThrottled()
    if not C_Timer then return self:Announce() end
    if self._annTimer then return end
    self._annTimer = true
    local channel = CraftLink and CraftLink.NetworkMode and CraftLink:NetworkMode() == "channel"
    C_Timer.After(channel and ANNOUNCE_COALESCE.channel or ANNOUNCE_COALESCE.whisper,
        function() self._annTimer = nil; Dir:Announce(true) end)   -- seuls les paliers RI changés
end
