-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Handshake) : Handshake chargé avec le socle Azeroth Commune dans
-- l'interface Forever simulée (le WTF de session ne contient pas nos SavedVariables : la purge des projets d'avant
-- l'identité stable est testée dans check.lua).
test("Handshake se charge : des projets, plus de table globale des choix", function()
    assertType("table", HandshakeDB)
    assertType("table", HandshakeDB.projets)
    assertNil(HandshakeDB.force)
    assertNil(HandshakeDB.orders)
    assertType("function", SlashCmdList.HANDSHAKE)
end)

local function enfant(ok)
    for _, c in ipairs({ HandshakeFrame:GetChildren() }) do
        if ok(c) then return c end
    end
end
local function bouton(texte) return enfant(function(c) return c.GetText and c:GetText() == texte and c:GetObjectType() == "Button" end) end
-- Le nom du projet affiché en haut de la fenêtre.
local function affiche(nom) return enfant(function(c) return c:GetObjectType() == "EditBox" and c:GetText() == nom end) ~= nil end

test("un projet créé s'ouvre dans la fenêtre, < et > passent d'un projet à l'autre", function()
    SlashCmdList.HANDSHAKE("demo ceinture") -- crée un projet et ouvre la fenêtre (calcul et dessin de l'arbre)
    assertTrue(HandshakeFrame:IsShown())
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    SlashCmdList.HANDSHAKE("demo set")
    assertTrue(affiche("Essai : set en thorium enchanté"))
    bouton("<"):Click()
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    bouton(">"):Click()
    assertTrue(affiche("Essai : set en thorium enchanté"))
    HandshakeFrame:Hide()
end)

-- Commandes (#6) : « Commander » sur un bloc ajoute une commande à la liste du projet, sans nouvelle page. Les blocs
-- viennent de la base des recettes du socle (sa réserve Classic, AzerothCommune/RecettesClassic.lua, générée, hors du repo :
-- à copier dans une branche en worktree),
-- recettes pas apprises comprises (« tout »).
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function boutons(ok) return tous(HandshakeFrame, function(c) return c:GetObjectType() == "Button" and c:IsShown() and ok(c:GetText() or "") end) end
-- La liste des commandes : un bouton par commande, « part · artisan[ · offre] ».
local function commandes() return boutons(function(t) return t:find(" · ", 1, true) ~= nil end) end

-- Personne n'a de recette ici : « recettes pas apprises » cochée, toutes comptent et les blocs se dessinent. L'option est
-- rendue telle quelle, même si une vérification échoue.
local function sansRecettes(f)
    local avant = HandshakeDB.options.unlearned
    HandshakeDB.options.unlearned = true
    local ok, err = pcall(f)
    HandshakeDB.options.unlearned = avant
    HandshakeFrame:Hide()
    if not ok then error(err, 0) end
end

test("Commander un bloc ajoute une commande au projet, sur la même page", function() sansRecettes(function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    local nb = #HandshakeDB.projets
    assertEquals(1, #commandes()) -- tout le projet
    local commander = boutons(function(t) return t == "Commander" end)
    assertTrue(#commander > 0, "des blocs dessinés (AzerothCommune/RecettesClassic.lua présent ?)")
    commander[1]:Click()
    assertEquals(nb, #HandshakeDB.projets)
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    local liste = commandes()
    assertEquals(2, #liste)
    commander[1]:Click() -- le même bloc : la même commande
    assertEquals(2, #commandes())
end) end)

-- Recettes équivalentes (#46), avec la vraie réserve (extraite du client, transmutations d'essences en boucle) : dans la
-- démo « set », les essences de terre et d'eau s'achètent, aucune essence n'est fabriquée par une transmutation.
test("Démo « set » : pas de boucle de transmutation, les essences s'achètent", function() sansRecettes(function()
    SlashCmdList.HANDSHAKE("demo set")
    local caseDe = {}
    for _, c in ipairs(tous(HandshakeFrame, function(c) return c.node ~= nil end)) do caseDe[c.node.id] = c.node end
    assertNotNil(caseDe[7076], "une case Essence de terre (AzerothCommune/RecettesClassic.lua présent ?)")
    assertNotNil(caseDe[7080], "une case Essence d'eau")
    for _, id in ipairs({ 7076, 7078, 7080, 7082, 12803, 12808 }) do
        assertTrue(caseDe[id] == nil or caseDe[id].made == 0, "essence " .. id .. " fabriquée")
    end
end) end)

-- Un contrat porte deux GUID (Handshake#29) : l'artisan d'une demande doit avoir un GUID donné par le serveur. Ici, son
-- chuchotement : le jeu y joint le GUID de l'expéditeur (12e valeur de CHAT_MSG_WHISPER), Handshake le retient.
local ARTISAN = "Bel Dupont"
local function artisanConnu()
    FireEvent("CHAT_MSG_WHISPER", "bonjour", ARTISAN, "", "", ARTISAN, "", 0, 0, "", 0, 1, "Player-1-0000BE11")
end

-- La commande « tout le projet » de p, rangée à part, rattachée à son identité (#37).
local function toutLeProjet(p) return HandshakeDB.commandes[p.id].liste[1] end

-- Envoyer une commande (#7) : son état, lu dans son contrat, s'affiche à côté d'elle dans la liste des commandes.
test("L'état de chaque commande s'affiche à côté d'elle, lu dans son contrat", function() sansRecettes(function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    boutons(function(t) return t == "Commander" end)[1]:Click()
    for _, b in ipairs(commandes()) do assertTrue(b:GetText():find("pas envoyée", 1, true) ~= nil, b:GetText()) end
    local p = HandshakeDB.projets[#HandshakeDB.projets]
    artisanConnu()
    toutLeProjet(p).player = ARTISAN -- la commande « tout le projet », à un autre joueur
    commandes()[1]:Click()
    bouton("Préparer la demande"):Click()
    assertTrue(HandshakeContratsFrame:IsShown(), "le brouillon s'ouvre dans les contrats")
    assertTrue(commandes()[1]:GetText():find("pas envoyée", 1, true) ~= nil, "un brouillon n'est pas parti")
    local envoyer
    for _, c in ipairs({ HandshakeContratsFrame:GetChildren() }) do
        if c.GetText and c:GetText() == "Envoyer la proposition" then envoyer = c end
    end
    envoyer:Click()
    HandshakeContratsFrame:Hide()
    local texte = commandes()[1]:GetText()
    assertTrue(texte:find("demande envoyée", 1, true) ~= nil, texte)
    assertTrue(commandes()[2]:GetText():find("pas envoyée", 1, true) ~= nil, "l'autre commande n'est pas partie")
    assertTrue(bouton("Voir la demande") ~= nil, "envoyée : on la revoit, on ne la refait pas")
end) end)

-- Écart (#8) : la part d'une commande envoyée change, l'écart s'affiche à côté d'elle avec « Nouvelle version », qui
-- prépare la v2 en brouillon et l'ouvre dans les contrats (#19) ; elle part de là, sur « Envoyer la proposition ».
-- Retirée, elle se commande de nouveau.
test("Une commande envoyée signale l'écart, sa nouvelle version se relit avant l'envoi", function() sansRecettes(function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    local p = HandshakeDB.projets[#HandshakeDB.projets]
    artisanConnu()
    toutLeProjet(p).player = ARTISAN
    commandes()[1]:Click()
    bouton("Préparer la demande"):Click()
    for _, c in ipairs({ HandshakeContratsFrame:GetChildren() }) do
        if c.GetText and c:GetText() == "Envoyer la proposition" then c:Click() end
    end
    HandshakeContratsFrame:Hide()
    local ct = HandshakeDB.contracts[toutLeProjet(p).contrat]
    assertEquals("envoye", ct.status)
    -- Écart de prix (#18) : avec un apport, la caution contre mon estimation, en %, ou « estimation incomplète ».
    local m = ct.m
    ct.m = { { id = 2589, qty = 1, unit = 1 } } -- (comme si j'apportais un tissu, caution 1 pc)
    commandes()[1]:Click()
    local prix = commandes()[1]:GetText()
    assertTrue(prix:find("caution |cff%x+[+-]%d+ %%") ~= nil or prix:find("estimation incomplète", 1, true) ~= nil, prix)
    ct.m = m
    commandes()[1]:Click()
    assertTrue(commandes()[1]:GetText():find("caution |cff", 1, true) == nil, "rien d'apporté : pas de caution")
    assertTrue(commandes()[1]:GetText():find("ne correspond plus", 1, true) == nil, "rien n'a changé")
    p.lines[1].qty = p.lines[1].qty + 1 -- une ligne de plus à fabriquer : la part de « tout le projet » change
    commandes()[1]:Click()
    local texte = commandes()[1]:GetText()
    assertTrue(texte:find("ne correspond plus au contrat", 1, true) ~= nil, texte) -- constaté, sans cause supposée (#18)
    assertEquals("1", ct.v, "rien ne part sans clic")
    bouton("Nouvelle version"):Click()
    local brouillon = HandshakeDB.contracts[toutLeProjet(p).contrat .. "+"]
    assertEquals("brouillon", brouillon.status)
    assertEquals("2", brouillon.v)
    assertEquals("1", HandshakeDB.contracts[toutLeProjet(p).contrat].v, "rien n'est parti avant l'envoi")
    assertTrue(HandshakeContratsFrame:IsShown(), "le brouillon de la v2 s'ouvre dans les contrats")
    local envoyer, fiche
    for _, c in ipairs({ HandshakeContratsFrame:GetChildren() }) do
        if c.GetText and c:GetText() == "Envoyer la proposition" and c:IsShown() then envoyer = c end
    end
    for _, r in ipairs(tous(HandshakeContratsFrame, function() return true end)) do
        for _, z in ipairs({ r:GetRegions() }) do
            if z.GetText and (z:GetText() or ""):find("Changé depuis la v1", 1, true) then fiche = true end
        end
    end
    assertTrue(fiche, "le différentiel est affiché avant l'envoi")
    envoyer:Click()
    local v2 = HandshakeDB.contracts[toutLeProjet(p).contrat]
    assertEquals("2", v2.v)
    assertEquals("envoye", v2.status)
    assertEquals("1", v2.prev.v)
    assertNil(HandshakeDB.contracts[toutLeProjet(p).contrat .. "+"], "envoyé : plus de brouillon")
    HandshakeContratsFrame:Hide()
    assertTrue(commandes()[1]:GetText():find("ne correspond plus", 1, true) == nil, "partie : plus d'écart")
    local nv = bouton("Nouvelle version")
    assertTrue(nv == nil or not nv:IsShown(), "plus de « Nouvelle version »")
    v2.status = "retire" -- (comme si je l'avais retirée dans les contrats)
    commandes()[1]:Click()
    local nb = #commandes()
    bouton("Commander de nouveau"):Click()
    assertEquals(nb + 1, #commandes())
    assertTrue(commandes()[nb + 1]:GetText():find("tout le projet", 1, true) ~= nil, commandes()[nb + 1]:GetText())
    assertTrue(commandes()[nb + 1]:GetText():find("pas envoyée", 1, true) ~= nil, "une commande vivante")
end) end)

-- Règles de la réponse (#10) : la fenêtre demande au projet ce qui se modifie. Dans une réponse (un projet tenu, #37), la
-- quantité de ce qu'il veut est grisée ; dans un projet à moi, elle se tape. (Une réponse à un contrat qui n'existe pas :
-- seul compte qu'elle en soit une.) Le projet redevient le mien même si une vérification échoue.
-- Les champs de quantité des cases de la colonne 0 (une case porte son nœud).
local function quantites()
    return tous(HandshakeFrame, function(c) return c:GetObjectType() == "EditBox" and c:IsVisible() and c:GetParent().node ~= nil end)
end
test("Dans une réponse, la quantité de ce qu'il veut est grisée, d'après le projet", function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    local p = HandshakeDB.projets[#HandshakeDB.projets]
    local ok, err = pcall(function()
        assertTrue(#quantites() > 0, "une case par objet du projet")
        for _, q in ipairs(quantites()) do assertTrue(q:IsEnabled(), "mon projet : la quantité se tape") end
        HandshakeDB.commandes[p.id].reponse, p.tenu = "Bob-R#1", "c'est sa demande : ce qu'il veut ne change pas ici"
        bouton("<"):Click(); bouton(">"):Click() -- redessiné
        assertEquals(p, HandshakeDB.projets[HandshakeDB.courant])
        assertTrue(#quantites() > 0, "toujours affichée")
        for _, q in ipairs(quantites()) do assertTrue(not q:IsEnabled(), "réponse : la quantité est figée") end
        assertTrue(bouton("Contre-proposer") ~= nil, "une réponse se contre-propose")
    end)
    HandshakeDB.commandes[p.id].reponse, p.tenu = nil, nil
    HandshakeFrame:Hide()
    if not ok then error(err, 0) end
end)

-- AzerothCommune#49 : la barre de recherche de la fenêtre propose ce que rend la recherche d'objets du socle, dans son
-- ordre (Handshake n'a plus d'index d'objets à lui).
test("la barre de recherche propose les objets de la recherche du socle", function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    local box = enfant(function(c) return c:GetObjectType() == "EditBox" and math.floor(c:GetWidth() + 0.5) == 280 end)
    assertNotNil(box, "barre de recherche")
    box:SetText("bronze")
    box:GetScript("OnTextChanged")(box, true)
    local attendus = AzerothCommune.ChercherObjets("bronze", 8)
    assertEquals(8, #attendus)
    local montres = tous(HandshakeFrame, function(c)
        return c:GetObjectType() == "Button" and c:IsShown() and c.text ~= nil and math.floor(c:GetWidth() + 0.5) == 316
    end)
    assertEquals(#attendus, #montres)
    for i, e in ipairs(attendus) do
        assertEquals(e.name .. (e.fabricable and "  |cffe6a640fabricable|r" or ""), montres[i].text:GetText())
    end
    box:SetText("")
    HandshakeFrame:Hide()
end)
