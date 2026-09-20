-- CraftLink-1.0 — infrastructure partagée des addons de craft Classic (registre + transports).
--
-- Lib EMBARQUÉE (vendored) via LibStub, pas un addon installé séparément : chaque addon
-- (Guild Economy / TradeScanner, Crafting Order - Classic, un futur build TBC) embarque sa
-- copie ; LibStub n'en garde qu'une instance au runtime (la version la plus haute gagne).
-- Source canonique : repo CraftLink ; synchronisée dans Addon/Libs/ par sync-libs.ps1.
--
-- Périmètre = INFRA GÉNÉRIQUE seulement :
--   * catalogue de recettes canonique (index des positions de bits du registre)
--   * codec hex du registre "recettes connues" (CraftLink_Registry.lua)
--   * versions : dataVersion (compat des index) + protocolVersion (compat du wire)
--   * à venir : transports (canal global / guilde / proximité) — CraftLink_Transport.lua
-- Ce qui touche les GENS (présence, profils, favoris, réputation) N'EST PAS ici : ça vit
-- dans le produit Crafting Order - Classic. CraftLink ne connaît ni l'UI ni le skin de l'hôte.
--
-- Ce fichier = le CATALOGUE + les VERSIONS. Tous les clients d'une même `dataVersion`
-- partagent le mapping position <-> spellID, condition pour que les bitfields échangés
-- (cf. CraftLink_Registry) soient interprétables.

local MAJOR, MINOR = "CraftLink-1.0", 16   -- v16 : `recipeOrigin` (LISTE { id, areaID, nom,
-- faction }) remplace `recipeVendor`, + `recipePrice` et `npcSpot` ; RecipeOrigin choisit par
-- FACTION. Bump obligatoire : la liste de fusion d'ExtendProfession et la forme des donnees
-- changent, et une vieille copie embarquee ailleurs gagnerait le NewLibrary en silence.
-- (v15 : codec registre par IDENTIFIANTS (RI|prof|payload) pour Camelot, sans catalogue ; (v14 : résolution de noms compatible MAINLINE (C_Item/C_Spell) pour WoW: Forever ; (v13 : `names` (noms anglais canoniques des recettes à objet, Joaillerie TBC/Wrath) (v12 : deSources + DisenchantSource ; v11 : skillColors/RecipeColors ; v10 : enchants fusionnés ; v9 : couches saisonnières ; v8 : cooldowns ; v7 : gardes anti-clobber)
local lib = LibStub:NewLibrary(MAJOR, MINOR)
if not lib then return end  -- déjà chargé par un autre addon avec une version >= : on garde l'existante

-- Catalogue : [profCanonical] = { recipes = { spellID, ... } (trié), pos = { [spellID] = index } }
lib.catalog     = lib.catalog or {}
lib.dataVersion = lib.dataVersion or 0

-- Données brutes par métier, enregistrées par les fichiers Data embarqués (RegisterProfession) :
-- [prof] = { aliases, sellable, disenchant, enchants, names, recipes, itemToSpell }. Le catalogue (index
-- de bits) en est dérivé paresseusement (EnsureCatalog) → la lib est self-contained, sans hôte.
lib.professions    = lib.professions or {}
lib._catalogDirty  = lib._catalogDirty or false

-- protocolVersion : compat du FORMAT FILAIRE (verbes/champs des messages réseau). Distinct de
-- dataVersion (compat des index de bits du catalogue). On le bump quand le wire change de façon
-- incompatible ; deux clients de protocolVersion différentes peuvent refuser/adapter le dialogue.
lib.PROTOCOL_VERSION = 1
function lib:ProtocolVersion() return self.PROTOCOL_VERSION end

-- Empreinte déterministe d'un catalogue : deux clients aux mêmes données la calculent
-- à l'identique. Préférée à un numéro baké (qui pourrait se désynchroniser des données).
-- Repliée sur les noms de métiers triés + leurs recettes (déjà triées) → stable.
local function computeDataVersion(catalog)
    local profs = {}
    for prof in pairs(catalog) do profs[#profs + 1] = prof end
    table.sort(profs)
    local v = 0
    for _, prof in ipairs(profs) do
        for _, id in ipairs(catalog[prof].recipes) do
            v = (v * 31 + id) % 2147483647  -- borné < 2^31 : reste exact en double Lua 5.1
        end
    end
    return v
end

-- Enregistre l'index canonique de recettes. `professions` = { [prof] = { recipes = {spellID,...} } }
-- (l'addon le fournit depuis ses données bakées ; la lib reste agnostique du chargement).
-- La `dataVersion` (empreinte) est calculée ici : deux clients ne comparent leurs bitfields
-- QUE si elle correspond (sinon les positions de bits divergent → lecture faussée).
function lib:SetCatalog(professions)
    self.catalog = {}
    for prof, def in pairs(professions or {}) do
        local recipes = def.recipes
        if type(recipes) == "table" and #recipes > 0 then
            local pos = {}
            for i = 1, #recipes do pos[recipes[i]] = i end
            self.catalog[prof] = { recipes = recipes, pos = pos }
        end
    end
    self.dataVersion = computeDataVersion(self.catalog)
    self._catalogDirty = false  -- catalogue posé explicitement : pas de reconstruction paresseuse
end

-- Enregistre les données brutes d'un métier (appelé par les fichiers Data embarqués). Le
-- catalogue est reconstruit paresseusement au prochain accès (EnsureCatalog). `def` =
-- { aliases, sellable, disenchant, enchants, names, recipes (triés), itemToSpell }.
-- MERGE des champs si le métier existe déjà (ex. Mining = recettes de fonte + `gathers` minerais,
-- enregistrés par deux fichiers Data distincts). Sinon enregistrement direct. Idempotent.
function lib:RegisterProfession(name, def)
    local existing = self.professions[name]
    if existing then
        for k, v in pairs(def) do existing[k] = v end
    else
        self.professions[name] = def
    end
    self._catalogDirty = true
    self._aliasMap = nil      -- invalide le cache d'alias (cf. CraftLink_Professions)
    self._profCatCache = nil  -- invalide le cache de ProfessionCatalogue (dérivé de def)
end

-- ------------------------------------------------------------------
-- Couches SAISONNIÈRES (Saison de la Découverte, et demain Camelot)
-- ------------------------------------------------------------------
-- Saison active du royaume : 0 = aucune (Era classique), 2 = Saison de la Découverte
-- (`Enum.SeasonID.SeasonOfDiscovery`). Sert de garde aux fichiers Data/<Season>/ : hors de leur
-- saison ils ne s'enregistrent pas, donc un joueur Era garde EXACTEMENT le catalogue de base
-- (dataVersion figée) — aucune perturbation des bitfields déjà diffusés.
function lib:ActiveSeason()
    if C_Seasons and C_Seasons.GetActiveSeason then
        local ok, s = pcall(C_Seasons.GetActiveSeason)
        if ok and type(s) == "number" then return s end
    end
    return 0
end

-- ÉTEND un métier déjà enregistré avec des recettes saisonnières, en APPEND-ONLY.
--
-- Contrairement à RegisterProfession (qui REMPLACE `def.recipes`), on ajoute à la FIN : les
-- positions 1..N des recettes de base — donc les bitfields du registre (cf. CraftLink_Registry)
-- déjà encodés chez les joueurs — restent valides bit pour bit. Seule `dataVersion` change, ce qui
-- est voulu : un client dans la saison et un client hors saison ne doivent PAS comparer leurs
-- bitfields (positions divergentes au-delà de N). Les tables associatives (produces/reagents/
-- learnedAt/taughtBy/itemToSpell) sont fusionnées clé par clé, sans écraser une entrée de base.
--
-- IDEMPOTENT : un spellID déjà présent n'est jamais ré-appondu (deux hôtes embarquant la lib, ou un
-- double chargement du XML, ne dupliquent donc ni recette ni position).
-- No-op si le métier de base n'existe pas : une couche saisonnière n'invente pas un métier.
function lib:ExtendProfession(name, def)
    local base = self.professions[name]
    if not (base and type(base.recipes) == "table" and type(def) == "table") then return end
    if type(def.recipes) == "table" then
        local seen = {}
        for _, id in ipairs(base.recipes) do seen[id] = true end
        for _, id in ipairs(def.recipes) do
            if not seen[id] then seen[id] = true; base.recipes[#base.recipes + 1] = id end
        end
    end
    for _, key in ipairs({ "produces", "reagents", "learnedAt", "taughtBy", "itemToSpell", "sellable",
                           "skillColors", "recipeSource", "recipeOrigin", "recipePrice", "npcSpot" }) do
        local add = def[key]
        if type(add) == "table" then
            local dst = base[key]; if not dst then dst = {}; base[key] = dst end
            for k, v in pairs(add) do if dst[k] == nil then dst[k] = v end end
        end
    end
    -- `enchants` (services sans objet) et `names` (recettes qui produisent un objet) sont des LISTES
    -- ({id, name}, noms anglais canoniques), pas des maps : append avec dédup par id — même discipline
    -- « la base d'abord, jamais écrasée » que les tables ci-dessus.
    for _, key in ipairs({ "enchants", "names" }) do
        if type(def[key]) == "table" then
            local dst = base[key]; if not dst then dst = {}; base[key] = dst end
            local have = {}
            for _, e in ipairs(dst) do if e.id then have[e.id] = true end end
            for _, e in ipairs(def[key]) do
                if e.id and e.name and not have[e.id] then have[e.id] = true; dst[#dst + 1] = e end
            end
        end
    end
    self._catalogDirty = true
    self._profCatCache = nil   -- ProfessionCatalogue dérive de `def` → cache périmé
end

-- (Re)construit le catalogue (index de bits) depuis les données enregistrées, si nécessaire.
-- Idempotent ; appelé en tête de chaque accesseur → l'hôte n'a aucun finalize à ordonnancer.
function lib:EnsureCatalog()
    if not self._catalogDirty then return end
    self._catalogDirty = false
    local cat = {}
    for prof, def in pairs(self.professions) do
        local recipes = def.recipes
        if type(recipes) == "table" and #recipes > 0 then
            local pos = {}
            for i = 1, #recipes do pos[recipes[i]] = i end
            cat[prof] = { recipes = recipes, pos = pos }
        end
    end
    self.catalog     = cat
    self.dataVersion = computeDataVersion(cat)
end

-- itemToSpell d'un métier (itemID produit -> spellID) : repli runtime pour le scan TradeSkill.
function lib:ItemToSpell(prof)
    local def = self.professions[prof]
    return def and def.itemToSpell or nil
end

-- Données brutes d'un métier (aliases/sellable/disenchant/enchants/...), ou nil.
function lib:GetProfession(prof)
    return self.professions[prof]
end

-- Objet produit par une recette (spellID -> itemID), ou nil (services/enchantements).
function lib:RecipeProduct(prof, spellID)
    local def = self.professions[prof]
    return def and def.produces and def.produces[spellID] or nil
end

-- Réactifs d'une recette : { {itemID, qty}, ... } ou nil. Noms via ItemName (runtime, localisé).
function lib:RecipeReagents(prof, spellID)
    local def = self.professions[prof]
    return def and def.reagents and def.reagents[spellID] or nil
end

-- Niveau de métier auquel la recette s'apprend (spellID -> niveau), ou nil si inconnu
-- (donnée générée par tools/gen_metadata.lua ; les Poisons Vanilla n'en ont pas).
function lib:RecipeLearnedAt(prof, spellID)
    local def = self.professions[prof]
    return def and def.learnedAt and def.learnedAt[spellID] or nil
end

-- Seuils de difficulté RÉELS d'une recette : { orange, jaune, vert, gris } (gris = rang où elle
-- ne rapporte plus de point), ou nil si hors base (donnée générée par tools/gen_skill_colors.lua,
-- source Wowhead ; lacune connue : Poisons Vanilla). La couleur LIVE de l'API du jeu reste la
-- référence pour une recette APPRISE au rang courant — ces seuils servent aux recettes MANQUANTES
-- et à la prédiction de couleur à un rang futur (plan de route de montée de métier).
function lib:RecipeColors(prof, spellID)
    local def = self.professions[prof]
    return def and def.skillColors and def.skillColors[spellID] or nil
end

-- Où s'obtient le PLAN d'une recette : "vendor" | "drop" | "quest", ou nil si on ne sait pas.
-- Donnée générée par tools/gen_sources.lua (source Wowhead, codes étalonnés sur MTSL : 95,5 %
-- d'accord sur 739 recettes vérifiables).
--
-- ⚠️ "trainer" N'EST JAMAIS RENDU ICI, et c'est délibéré. Aucune page ne l'affirme : on ne le
-- déduit que de l'absence d'objet-recette, et une absence a deux causes qu'on ne distingue pas --
-- la recette s'apprend bien au formateur, ou la source n'est pas ENCORE connue de la source de
-- données (c'est le cas de la moitié des objets sur Forever pendant la bêta). La lib ne rend donc
-- que des FAITS ; l'inférence appartient à l'appelant, qui seul peut la présenter comme telle.
function lib:RecipeSource(prof, spellID)
    local def = self.professions[prof]
    return def and def.recipeSource and def.recipeSource[spellID] or nil
end

-- Le camp du joueur, en "A"/"H", ou nil quand le client ne répond pas.
--
-- ⚠️ PAS DE CACHE, et ce n'est pas un oubli. `UnitFactionGroup` rend nil avant que le personnage
-- soit entré en jeu ; mémoriser ce nil-là figerait « faction inconnue » pour toute la session, et
-- tous les joueurs se verraient proposer le marchand du camp d'en face. L'appel est trivial, il est
-- fait au survol d'une ligne, pas dans une boucle : il n'y a rien à économiser ici.
local function side()
    local f = UnitFactionGroup and UnitFactionGroup("player")
    return (f == "Alliance" and "A") or (f == "Horde" and "H") or nil
end

-- TOUTES les entrées connues derrière le plan d'une recette : { { id, areaID, nom, faction }, ... }
-- ou nil. Le SENS de ces entrées vient de `RecipeSource` : le marchand qui vend le plan, la créature
-- qui le lâche (triées par taux décroissant), ou la quête qui le donne (areaID toujours nil).
--
-- La faction "A"/"H" veut dire CE CAMP SEULEMENT ; nil veut dire « les deux » OU « on ne sait pas »,
-- et ces deux-là ne se distinguent pas -- la donnée ne le dit pas. Un appelant ne doit donc jamais
-- présenter un nil comme une garantie de neutralité.
function lib:RecipeOrigins(prof, spellID)
    local def = self.professions[prof]
    return def and def.recipeOrigin and def.recipeOrigin[spellID] or nil
end

-- L'entrée à montrer à CE joueur : la première de son camp, sinon la première sans camp. Rend
-- `id, areaID, nom, faction`.
--
-- ⚠️ POURQUOI LA FACTION EST UN CRITÈRE ET PAS UN DÉTAIL. Envoyer un joueur de la Horde chez un
-- marchand de Forgefer n'est pas une imprécision, c'est un aller simple en territoire ennemi. La
-- page de métier ne donnait qu'UN nom sans son camp : pour « Recipe: Gingerbread Cookie » c'était
-- systématiquement Wulmort Jinglepocket, à Forgefer, pour tout le monde.
--
-- Quand RIEN ne correspond, on rend quand même la première entrée plutôt que nil : un nom en
-- territoire adverse reste une information. C'est à la VUE de dire qu'elle l'est (la faction est
-- rendue pour ça), pas à la lib de mentir par omission.
function lib:RecipeOrigin(prof, spellID)
    local list = self:RecipeOrigins(prof, spellID)
    if not (list and list[1]) then return nil end
    local me, neutral = side(), nil
    for _, e in ipairs(list) do
        if e[4] == me then return e[1], e[2], e[3], e[4] end
        if not e[4] and not neutral then neutral = e end
    end
    local e = neutral or list[1]
    return e[1], e[2], e[3], e[4]
end

-- Le PNJ qui VEND le plan, et lui seul : la même donnée, filtrée sur la nature. Les appelants
-- historiques (liste de courses de la Bourse d'artisan, fournitures du Plan de route) parlent tous
-- d'un ACHAT ; leur rendre la créature qui lâche le plan leur ferait conseiller d'aller l'acheter.
function lib:RecipeVendor(prof, spellID)
    if self:RecipeSource(prof, spellID) ~= "vendor" then return nil end
    return self:RecipeOrigin(prof, spellID)
end

-- La NATURE portee par la liste d'origines elle-meme, quand elle a ete DEDUITE de la page de
-- l'objet ou du sort faute de reponse de la page de metier. nil = la page de metier a repondu (c'est
-- `RecipeSource` qui fait foi) ou on ne sait rien.
function lib:RecipeOriginKind(prof, spellID)
    local list = self:RecipeOrigins(prof, spellID)
    return list and list.kind or nil
end

-- OU SE TIENT UN PNJ : uiMapID, x, y (0-100), ou nil. Cle par PNJ et pas par recette -- un marchand
-- sert des dizaines de plans, et sa position ne depend pas de ce qu'il vend.
--
-- `uiMapID` est l'identifiant de carte du JEU, pas un nom de zone : le repere se pose sans passer
-- par une resolution par libelle, qui echoue des que deux noms divergent d'une lettre.
function lib:NpcSpot(prof, npcID)
    local def = self.professions[prof]
    local sp = def and def.npcSpot and def.npcSpot[npcID]
    if not sp then return nil end
    return sp[1], sp[2], sp[3]
end

-- PRIX du plan chez son marchand, en cuivre, ou nil. nil = INCONNU, JAMAIS zéro : un appelant qui
-- confondrait les deux conseillerait d'acheter « gratuitement » un plan qui coûte.
function lib:RecipePrice(prof, spellID)
    local def = self.professions[prof]
    local p = def and def.recipePrice and def.recipePrice[spellID] or nil
    -- Un zero n'est pas un prix, c'est une absence de prix EN ARGENT (le plan s'echange contre un
    -- objet, ou la source ne le dit pas). Le rendre tel quel ferait afficher « Prix : 0 ».
    return (p and p > 0) and p or nil
end

-- Durée (secondes) du cooldown d'une recette, ou nil si la recette n'a pas de mécanique de CD.
-- L'API du jeu ne distingue pas « prête » de « sans CD » (GetTradeSkillCooldown rend nil pour
-- les deux) : cette table curatée (Data/Cooldowns.lua, source Wowhead) est la référence.
function lib:RecipeCooldown(prof, spellID)
    local def = self.professions[prof]
    return def and def.cooldowns and def.cooldowns[spellID] or nil
end

-- Groupe de cooldown PARTAGÉ d'une recette (ex. "transmute"), ou nil si CD indépendant.
-- Caster un sort du groupe déclenche le CD de tout le groupe, avec la durée du sort casté.
function lib:RecipeCdGroup(prof, spellID)
    local def = self.professions[prof]
    return def and def.cdGroup and def.cdGroup[spellID] or nil
end

-- Table { [spellID] = durée } des recettes à cooldown d'un métier, ou nil — pour itérer.
function lib:CooldownRecipes(prof)
    local def = self.professions[prof]
    return def and def.cooldowns or nil
end

-- Résout un objet-PLAN (Recette/Formule/Schéma/Patron/Dessin looté ou en sac) vers
-- (profCanonical, spellID enseigné), ou nil si l'objet n'enseigne rien de catalogué.
-- Parcourt tous les métiers : un plan looté ne dit pas de quel métier il relève.
function lib:RecipeFromPlanItem(itemID)
    if not itemID then return nil end
    for prof, def in pairs(self.professions) do
        local sid = def.taughtBy and def.taughtBy[itemID]
        if sid then return prof, sid end
    end
    return nil
end

-- Conversions « détruire pour obtenir des composants » (disenchant/milling/prospecting) ou nil.
function lib:Conversions(prof)
    local def = self.professions[prof]
    return def and def.conversions or nil
end

-- Classe d'objets à DÉSENCHANTER pour obtenir un composant, ou nil : { q = qualité (2 vert /
-- 3 bleu / 4 épique), lo, hi = tranche de NIVEAU D'OBJET (ilvl, ≠ niveau requis — l'afficher
-- comme « niv. d'objet ») }. Table curatée Data/Disenchant.lua (ESTIMATION, source Wowpedia) —
-- complémentaire de Conversions (ici la source est une classe d'objets, pas un objet précis).
function lib:DisenchantSource(itemID)
    return self.deSources and self.deSources[itemID] or nil
end

-- Items récoltés par un métier de récolte (Herbalism/Skinning/Fishing/Mining) : { itemID, ... } ou nil.
function lib:Gathers(prof)
    local def = self.professions[prof]
    return def and def.gathers or nil
end

-- Catalogue COMMANDABLE d'un métier : objets fabricables (via produces, avec spellID pour les
-- réactifs) + objets récoltables (via gathers, sans spellID). Liste { {itemID=, spellID=}, ... }
-- dédupliquée par itemID. Sert à l'UI de recherche de craft / commande de matières.
-- Résultat mémoïsé par métier (invalidé par RegisterProfession → _profCatCache=nil) : la liste ne
-- dépend que de `def`, stable après le chargement des Data. Appelée à chaque refresh UI (Commande/
-- Récolte) et par le scan de crafteurs → la reconstruire à chaque fois coûtait cher. NE PAS muter le retour.
function lib:ProfessionCatalogue(prof)
    local def = self.professions[prof]
    if not def then return {} end
    self._profCatCache = self._profCatCache or {}
    if self._profCatCache[prof] then return self._profCatCache[prof] end
    local seen, out = {}, {}
    local function add(entry, key)
        if not seen[key] then seen[key] = true; out[#out + 1] = entry end
    end
    -- Recettes : objet produit (itemID+spellID) OU service sans objet (spellID seul, ex. enchants).
    if def.recipes then
        for _, spellID in ipairs(def.recipes) do
            local itemID = def.produces and def.produces[spellID]
            if itemID then add({ itemID = itemID, spellID = spellID }, "i" .. itemID)
            else add({ spellID = spellID, service = true }, "s" .. spellID) end
        end
    end
    -- Matières récoltées (Herbalism/Skinning/Fishing/Mining) — commandables.
    if def.gathers then
        for _, itemID in ipairs(def.gathers) do add({ itemID = itemID }, "i" .. itemID) end
    end
    -- Mats de désenchantement (Enchanteur) — commandables comme matières.
    if def.disenchant then
        for itemID in pairs(def.disenchant) do add({ itemID = itemID }, "i" .. itemID) end
    end
    self._profCatCache[prof] = out
    return out
end

-- Liste triée des métiers connus (catalogue). NE PAS muter.
function lib:Professions()
    local out = {}
    for prof in pairs(self.professions) do out[#out + 1] = prof end
    table.sort(out)
    return out
end

-- Résolution de NOM multilingue : le client localise via GetItemInfo/GetSpellInfo ; repli baké.
-- SAVEURS : sur un client MAINLINE (WoW: Forever / Camelot) ces globaux n'existent plus, ils
-- vivent dans C_Item / C_Spell. La lib charge AVANT l'addon hôte : elle ne peut pas s'appuyer
-- sur la couche de compat de COC et résout donc chez elle. On préfère la forme moderne quand
-- elle existe (l'Era l'a aussi), l'ancienne sinon. GetSpellInfo rend un tuple en Classic et une
-- table en Retail : on passe par GetSpellName, qui rend une chaîne des deux côtés.
function lib:ItemName(itemID, fallback)
    local getItem = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if itemID and getItem then local n = getItem(itemID); if n and n ~= "" then return n end end
    return fallback or (itemID and ("item:" .. itemID)) or "?"
end

function lib:RecipeName(spellID, fallback)
    local getSpell = (C_Spell and C_Spell.GetSpellName)
        or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
    if spellID and getSpell then local n = getSpell(spellID); if n and n ~= "" then return n end end
    return fallback or (spellID and ("spell:" .. spellID)) or "?"
end

function lib:HasCatalog()
    self:EnsureCatalog()
    return next(self.catalog) ~= nil
end

function lib:DataVersion()
    self:EnsureCatalog()
    return self.dataVersion
end

-- Liste ordonnée des spellID d'un métier (ou nil). NE PAS muter.
function lib:GetRecipes(prof)
    self:EnsureCatalog()
    local c = self.catalog[prof]
    return c and c.recipes or nil
end

-- Position de bit (1-based) d'une recette dans son métier, ou nil si inconnue.
function lib:Position(prof, spellID)
    self:EnsureCatalog()
    local c = self.catalog[prof]
    return c and c.pos[spellID] or nil
end

-- Nombre de recettes cataloguées pour un métier (0 si inconnu).
function lib:Count(prof)
    self:EnsureCatalog()
    local c = self.catalog[prof]
    return c and #c.recipes or 0
end
