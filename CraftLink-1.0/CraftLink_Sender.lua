-- CraftLink-1.0 — Qui parle ? Lecture de l'ÉMETTEUR d'un message : nom court, royaume admis, lisibilité.
--
-- Sorti de CraftLink_Transport (TRANSPORT_REV 17) : ce sont les quatre questions que le transport pose
-- à chaque message reçu avant de le dispatcher, et le transport dépassait sa taille. Aucune n'envoie
-- rien. Chargé AVANT Transport (lib.xml), qui en garde des alias locaux sous les mêmes noms.

local lib = LibStub and LibStub:GetLibrary("CraftLink-1.0", true)
if not lib then return end

-- Anti-clobber, même règle que Transport : BUMP à chaque évolution, et resync de TOUS les hôtes.
local SENDER_REV = 1
if (lib._senderRev or 0) >= SENDER_REV then return end
lib._senderRev = SENDER_REV

-- « Prénom Nom-Royaume » → « Prénom Nom ». Les noms de perso ne contiennent jamais de « - » (WoW).
function lib._PlayerShort(name)
    if not name then return nil end
    return name:match("^([^%-]+)") or name
end

-- Confinement ROYAUME : le canal custom peut être partagé entre royaumes CONNECTÉS (voire au-delà). Les
-- DONNÉES de canal (découverte, ordres) ne valent que pour des joueurs avec qui on peut réellement
-- échanger → on n'accepte que le royaume courant + les royaumes connectés. L'émetteur d'un event canal
-- porte un suffixe « -Royaume » (normalisé, sans espace) s'il n'est PAS sur notre royaume ; pas de
-- suffixe = même royaume. `C_AutoComplete` d'abord : le global `GetAutoCompleteRealms` n'est qu'un alias
-- posé par Blizzard_DeprecatedAutoComplete, que le réglage `loadDeprecationFallbacks` peut ne pas charger.
function lib._SameRealmGroup(author)
    if type(author) ~= "string" then return false end
    local realm = author:match("%-(.+)$")
    if not realm then return true end                       -- pas de suffixe = mon royaume exact
    local mine = GetNormalizedRealmName and GetNormalizedRealmName()
    if mine and realm == mine then return true end
    local connected = (C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms) or GetAutoCompleteRealms
    if connected then
        for _, r in ipairs(connected() or {}) do if r == realm then return true end end
    end
    return false
end

-- Valeurs SECRÈTES (Forever) : sous le verrou du chat (en instance), CHAT_MSG_CHANNEL, _JOIN et _LEAVE
-- livrent texte et émetteur SECRETS (`SecretInChatMessagingLockdown`, doc du build 70124). Une secrète
-- dit `type == "string"` mais lève dès qu'on l'indexe (:sub, :match) ou qu'on la compare. Relevé en
-- jeu le 2026-09-25 (Wailing Caverns, BugGrabber) : playerShort et isTechChannelText tombaient à chaque
-- ligne. Un message illisible n'est pas pour nous : on le laisse passer. Le prédicat lui-même est
-- appelé sous pcall — la doc le marque `AllowedWhenUntainted`, et nous sommes du code d'addon : s'il
-- lève, la valeur est tenue pour illisible. Classic Era n'a pas de prédicat : rien n'est secret.
function lib._Unreadable(...)
    local isSecret = _G.issecretvalue
    if not isSecret then return false end
    for i = 1, select("#", ...) do
        local ok, secret = pcall(isSecret, (select(i, ...)))
        if not ok or secret then return true end
    end
    return false
end

-- Nom RÉSEAU du joueur, celui que le serveur met en émetteur de NOS messages (écho du canal compris).
-- Forever : « Prénom Nom » ; UnitName n'en rend que le prénom, GetUnitName les recolle (Camelot/
-- NameUtil.lua ; relevé 2026-09-27). Comparer au prénom laissait notre écho entrer dans l'annuaire.
function lib._MyNetworkName()
    if GetUnitName then
        local ok, n = pcall(GetUnitName, "player", true)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return UnitName and UnitName("player") or "?"
end
