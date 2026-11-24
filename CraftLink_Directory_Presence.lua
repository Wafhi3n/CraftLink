-- CraftLink_Directory_Presence.lua — présence : la vérité JEU (amis/guilde) et sa fusion avec la vérité
-- ADDON. Copié de Directory_Presence.lua de COC v1.53.0 (spec docs/specs/addon-partage.md, étape 3).
--
-- Deux sources, à ne JAMAIS confondre :
--   * Dir.online     — il RÉPOND en CraftLink (JOIN/LEAVE du canal, ou tout message reçu → _Touch).
--                      C'est la seule qui autorise une commande : ses données sont fraîches.
--   * Dir.onlineGame — le JEU le dit connecté (roster de guilde / liste d'amis / BNet), addon ou pas.
--                      Ne vaut que pour mes RELATIONS : le jeu ne dit rien d'un simple croisé.
-- Sans la seconde, un guildmate connecté SANS l'addon s'affichait « Hors ligne » — faux, et ça
-- ressemblait à une panne réseau. Dir:PresenceOf les fusionne en 3 états pour l'UI.
--
-- Satellite de Directory.lua (anti-monolithe) : y vivent le sweep des relations en ligne
-- (DiscoverFriendsAndGuild), la requête d'affichage, et le filtre des erreurs « No player named »,
-- seule présence qu'on ait d'un simple croisé. Chargé APRÈS Directory.lua (.toc).

local _, NS = ...
NS = NS or _G.CraftLink
local Dir = NS.Directory
local CraftLink = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)

Dir.onlineGame = {}   -- [playerShort] = true (éphémère, mémoire) — connecté selon le JEU, addon ou pas

local function shortName(n) return n and (n:match("^([^%-]+)") or n) or n end
local function now() return (GetTime and GetTime()) or 0 end

-- Amis Battle.net (BattleTag) en plus des amis « classiques » : sans ça, un ami ajouté uniquement
-- via BattleTag n'entre jamais dans l'onglet Amis même croisé et en ligne. `fn` reçoit chaque perso.
-- BNGetFriendInfo ne liste QUE les connectés → tout perso rendu ici est en ligne.
function Dir:ForEachBNetWoWFriend(fn)
    if not BNGetNumFriends then return end
    for i = 1, (BNGetNumFriends() or 0) do
        local characterName, client, isOnline = NS.Api.GetBNetFriend(i)
        if isOnline and characterName and client == (BNET_CLIENT_WOW or "WoW") then fn(characterName) end
    end
end

-- Découverte des amis + guildmates EN LIGNE par whisper (PING+HI) — fiable hors canal global et sans
-- ciblage mutuel. Au login (1er appel → prev vide) on ping TOUS les en-ligne ; ensuite, sur chaque
-- FRIENDLIST/GUILD_ROSTER_UPDATE, on ne ping QUE les nouveaux connectés (transition hors-ligne→en-ligne)
-- pour ne pas re-sonder en boucle les déjà-présents ni les non-porteurs. DiscoverPlayer reste throttlé
-- 60 s/nom en filet de sécurité. `_wasOnlineRel` = statut en-ligne (API jeu) du sweep précédent.
-- Effet de bord VOULU : le sweep publie aussi `onlineGame` (même table) — c'est le seul endroit où
-- l'on lit la vérité de présence du jeu, autant la garder au lieu de la jeter.
function Dir:DiscoverFriendsAndGuild()
    local prev, cur = self._wasOnlineRel or {}, {}
    local function consider(name, online)
        name = shortName(name)
        if not (name and online) then return end
        cur[name] = true
        if not prev[name] then self:DiscoverPlayer(name) end   -- vient de se connecter
    end
    if C_FriendList and C_FriendList.GetNumFriends then
        for i = 1, (C_FriendList.GetNumFriends() or 0) do
            local info = C_FriendList.GetFriendInfoByIndex(i)
            if info then consider(info.name, info.connected) end
        end
    end
    if IsInGuild and IsInGuild() and GetNumGuildMembers then
        for i = 1, (GetNumGuildMembers() or 0) do
            local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            consider(name, online)
        end
    end
    self:ForEachBNetWoWFriend(function(n) consider(n, true) end)
    -- Membres de cercle en ligne (présence donnée par le CLUB, donc vérité du JEU — exactement la
    -- même nature que la guilde ou la liste d'amis). Même traitement que `consider`, à une nuance
    -- près : un cercle n'a pas la taille bornée d'une guilde (capacité mesurée 1000), et au premier
    -- balayage d'une session `prev` est vide, donc TOUT le monde partirait en découverte d'un seul
    -- coup dans la file partagée de CraftLink. Le module cercle marque donc les sondables ; ici on
    -- publie la présence de TOUS et on ne sonde que ceux-là.
    if self.ForEachCircleMemberOnline then
        self:ForEachCircleMemberOnline(function(name, mayDiscover)
            name = shortName(name)
            if not name then return end
            cur[name] = true
            if mayDiscover and not prev[name] then self:DiscoverPlayer(name) end
        end)
    end
    -- Parti selon le JEU (ami, guildmate, membre de cercle) alors qu'il répondait en addon : on l'ÉTEINT,
    -- et on le sonde quand même. Relevé en jeu le 2026-09-28 : Rédemption quitte le jeu, Gnomi le voit
    -- toujours connecté — le sondage seul (1re version, sur avis de la revue protocole) ne ramenait rien
    -- dans les secondes suivantes : jamais TargetOffline, et « aucun joueur nommé » n'arrive que ~110 s
    -- plus tard (mesuré le 2026-10-03, cf. _InstallWhisperErrorFilter). Le jeu, lui, le sait tout de suite.
    -- Un personnage que le jeu dit déconnecté ne fait pas tourner d'addon ; si le jeu s'est trompé, le
    -- sondage le fait répondre et _Touch le rallume aussitôt. (Idée du user : la présence fait foi.)
    for name in pairs(prev) do
        if not cur[name] and self.online and self.online[name] then
            self:MarkOffline(name)   -- l'interface est rafraîchie en fin de balayage
            self:DiscoverPlayer(name)
        end
    end
    self._wasOnlineRel = cur
    self.onlineGame    = cur
    Dir:_Changed()
end

-- Présence d'un joueur en 3 états — POINT DE VÉRITÉ UNIQUE de l'affichage :
--   "online"  = il répond en CraftLink → données fraîches, commande possible (pastille verte)
--   "game"    = le jeu le dit connecté mais il ne répond pas → il n'a pas (ou plus) l'addon,
--               ses données sont celles de sa dernière session (pastille jaune)
--   "offline" = déconnecté, OU hors de ma portée de sondage (un croisé n'est ni ami ni guildmate,
--               le jeu ne me dit rien de lui) → l'absence de preuve reste « hors ligne »
function Dir:PresenceOf(name)
    if not name then return "offline" end
    if self.online and self.online[name] then return "online" end
    if self.onlineGame and self.onlineGame[shortName(name)] then return "game" end
    return "offline"
end

-- ------------------------------------------------------------------
-- « No player named 'X' is currently playing. » : le retour d'un whisper vers un absent
-- ------------------------------------------------------------------
-- Le serveur de Forever rend cette erreur pour un whisper d'ADDON vers un joueur hors ligne (ou un nom
-- inconnu), mais ~110 s APRÈS l'envoi. Mesuré le 2026-10-03 (DevMacro, Stormwind, sans changer de zone) :
-- 108 à 112 s, en paquet, dans l'ordre d'envoi. La fenêtre de 15 s d'avant ne reconnaissait donc plus
-- NOTRE whisper : l'erreur s'affichait, et le pair restait « en ligne ». Chaque annonce, chaque renvoi
-- de commande lui repartait, et revenait en erreur deux minutes plus tard : le spam vu à Ironforge.
local WHISPER_ERR_WINDOW = 300   -- s : ~3 fois le retard mesuré. Prix : un whisper À LA MAIN vers un
                                 -- absent que l'addon a écrit dans ces 5 min perd son message d'erreur.
-- Il m'a parlé il y a moins que ça : il est revenu APRÈS l'envoi refusé (parti au moins ~100 s plus
-- tôt). L'erreur est avalée, mais on ne l'éteint pas.
local BACK_ONLINE_GRACE  = 60

-- L'addon a-t-il écrit à `who` dans la fenêtre (sonde de découverte, ou file de CraftLink) ?
local function ourWhisper(who)
    local t = Dir._lastPing and Dir._lastPing[who]
    if t and now() - t < WHISPER_ERR_WINDOW then return true end
    return (CraftLink and CraftLink.WhisperedRecently and CraftLink:WhisperedRecently(who, WHISPER_ERR_WINDOW)) == true
end

local function heardSince(who)
    local r = Dir.roster and Dir.roster[who]
    return r ~= nil and r.lastSeen ~= nil and (time() - r.lastSeen) < BACK_ONLINE_GRACE
end

-- Avale l'erreur quand X est un nom que l'addon a chuchoté, et l'éteint : c'est la présence que donnait
-- le canal. Une erreur pour un nom que l'addon n'a pas écrit (whisper du joueur) reste affichée.
function Dir:_InstallWhisperErrorFilter()
    if self._errFilter then return end
    local raw = ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
    local pat = "^" .. raw:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%0"):gsub("%%%%s", "(.-)") .. "$"
    self._errFilter = NS.Api.AddChatFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
        if NS.Api.IsSecret(msg) then return false end   -- instance : texte secret, ni match ni comparaison
        local who = type(msg) == "string" and msg:match(pat)
        who = who and shortName(who)
        if not (who and ourWhisper(who)) then return false end
        if not heardSince(who) and Dir:MarkOffline(who) then Dir:_Changed() end
        return true
    end)
end
