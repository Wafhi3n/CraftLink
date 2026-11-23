-- CraftLink_Api.lua — les quelques adaptations d'API dont l'annuaire a besoin, reprises de
-- CraftingOrderClassic_Compat.lua (COC v1.53.0) avec leur signature : NS.Api.X remplace COC.Api.X dans
-- les modules copiés (spec docs/specs/addon-partage.md, étape 3). Les raisons de chacune sont écrites
-- chez COC ; elles tiennent ici telles quelles.

local _, NS = ...
NS = NS or _G.CraftLink
NS.Api = NS.Api or {}
local A = NS.Api

A.GuildRoster = (C_GuildInfo and C_GuildInfo.GuildRoster) or _G.GuildRoster

-- Forever rend la forme MAINLINE (registre par identifiants, verbe RI) : WOW_PROJECT_ID vaut MAINLINE,
-- ou CAMELOT depuis le build 70170 (relevé du 2026-10-02 chez COC).
local function isMainlineProject()
    local id = _G.WOW_PROJECT_ID
    if id == nil then return false end
    if _G.WOW_PROJECT_MAINLINE ~= nil and id == _G.WOW_PROJECT_MAINLINE then return true end
    return _G.WOW_PROJECT_CAMELOT ~= nil and id == _G.WOW_PROJECT_CAMELOT
end
A.IS_MAINLINE = isMainlineProject()

-- `C_BattleNet.GetFriendAccountInfo` (table) ou l'ancien `BNGetFriendInfo` (tuple) : nom du perso,
-- client, en ligne.
function A.GetBNetFriend(index)
    local get = C_BattleNet and C_BattleNet.GetFriendAccountInfo
    if get then
        local acc = get(index)
        local game = acc and acc.gameAccountInfo
        if not game then return nil end
        return game.characterName, game.clientProgram, game.isOnline
    end
    if _G.BNGetFriendInfo then
        local _, _, _, _, characterName, _, client, isOnline = _G.BNGetFriendInfo(index)
        return characterName, client, isOnline
    end
end

-- Filtre de messages du chat : ChatFrameUtil sur Forever, l'alias global sinon. Rend vrai s'il est posé.
function A.AddChatFilter(event, fn)
    local add = (_G.ChatFrameUtil and _G.ChatFrameUtil.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
    if not add then return false end
    add(event, fn)
    return true
end

-- Une valeur SECRÈTE (contexte restreint) ne s'indexe ni ne se compare : on la traite comme une absence.
function A.IsSecret(v)
    return (_G.issecretvalue and _G.issecretvalue(v)) == true
end

-- Nom RÉSEAU du joueur, « Prénom Nom » sur Forever (UnitName n'en rend que le prénom).
function A.PlayerName()
    if _G.GetUnitName then
        local ok, n = pcall(_G.GetUnitName, "player", true)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    return (_G.UnitName and _G.UnitName("player")) or "?"
end

-- Un nom qu'on peut chuchoter ? Avec un nom de famille chez moi, un nom SANS est incomplet (le
-- chuchotement se perd, puis revient en « No player named »). UNKNOWNOBJECT n'est jamais chuchotable.
function A.IsFullPlayerName(name)
    if A.IsSecret(name) or type(name) ~= "string" or name == "" then return false end
    if name == (_G.UNKNOWNOBJECT or "Unknown") then return false end
    if not A.PlayerName():find(" ", 1, true) then return true end
    return name:find(" ", 1, true) ~= nil
end
