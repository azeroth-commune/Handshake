-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Handshake) : Handshake chargé avec LibCommune et GameData dans
-- l'interface Forever simulée (le WTF de session ne contient pas nos SavedVariables : la migration des commandes en
-- projets est testée dans check.lua).
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
-- viennent de la réserve Classic (RecettesClassic.lua, généré, hors du repo : à copier dans une branche en worktree),
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
    assertTrue(#commander > 0, "des blocs dessinés (RecettesClassic.lua présent ?)")
    commander[1]:Click()
    assertEquals(nb, #HandshakeDB.projets)
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    local liste = commandes()
    assertEquals(2, #liste)
    commander[1]:Click() -- le même bloc : la même commande
    assertEquals(2, #commandes())
end) end)

-- Envoyer une commande (#7) : son état, lu dans son contrat, s'affiche à côté d'elle dans la liste des commandes.
test("L'état de chaque commande s'affiche à côté d'elle, lu dans son contrat", function() sansRecettes(function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    boutons(function(t) return t == "Commander" end)[1]:Click()
    for _, b in ipairs(commandes()) do assertTrue(b:GetText():find("pas envoyée", 1, true) ~= nil, b:GetText()) end
    local p = HandshakeDB.projets[#HandshakeDB.projets]
    p.commandes[1].player = "Bel" -- la commande « tout le projet », à un autre joueur
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

-- Écart (#8) : la part d'une commande envoyée change, l'écart s'affiche à côté d'elle avec « Nouvelle version », qui la
-- renvoie (v2) seulement sur ce clic. Retirée, elle se commande de nouveau.
test("Une commande envoyée signale l'écart et repart en nouvelle version sur un clic", function() sansRecettes(function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    local p = HandshakeDB.projets[#HandshakeDB.projets]
    p.commandes[1].player = "Bel"
    commandes()[1]:Click()
    bouton("Préparer la demande"):Click()
    for _, c in ipairs({ HandshakeContratsFrame:GetChildren() }) do
        if c.GetText and c:GetText() == "Envoyer la proposition" then c:Click() end
    end
    HandshakeContratsFrame:Hide()
    local ct = HandshakeDB.contracts[p.commandes[1].contrat]
    assertEquals("envoye", ct.status)
    assertTrue(commandes()[1]:GetText():find("a changé", 1, true) == nil, "rien n'a changé")
    p.lines[1].qty = p.lines[1].qty + 1 -- une ligne de plus à fabriquer : la part de « tout le projet » change
    commandes()[1]:Click()
    local texte = commandes()[1]:GetText()
    assertTrue(texte:find("a changé depuis la demande", 1, true) ~= nil, texte)
    assertEquals("1", ct.v, "rien ne part sans clic")
    bouton("Nouvelle version"):Click()
    local v2 = HandshakeDB.contracts[p.commandes[1].contrat]
    assertEquals("2", v2.v)
    assertEquals("1", v2.prev.v)
    assertTrue(HandshakeContratsFrame:IsShown(), "la nouvelle version s'ouvre dans les contrats, différentiel compris")
    HandshakeContratsFrame:Hide()
    assertTrue(commandes()[1]:GetText():find("a changé", 1, true) == nil, "partie : plus d'écart")
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

-- Règles de la réponse (#10) : la fenêtre demande au projet ce qui se modifie. Dans une réponse, la quantité de ce qu'il
-- veut est grisée ; dans un projet à moi, elle se tape. (Une réponse à un contrat qui n'existe pas : seul compte qu'elle
-- en soit une.) Le projet redevient le mien même si une vérification échoue.
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
        p.reponse = "Bob-R#1"
        bouton("<"):Click(); bouton(">"):Click() -- redessiné
        assertEquals(p, HandshakeDB.projets[HandshakeDB.courant])
        assertTrue(#quantites() > 0, "toujours affichée")
        for _, q in ipairs(quantites()) do assertTrue(not q:IsEnabled(), "réponse : la quantité est figée") end
        assertTrue(bouton("Contre-proposer") ~= nil, "une réponse se contre-propose")
    end)
    p.reponse = nil
    HandshakeFrame:Hide()
    if not ok then error(err, 0) end
end)
