-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Handshake) : Handshake et Composants chargés avec le socle Azeroth
-- Commune dans l'interface Forever simulée. Handshake se branche sur l'emplacement du bloc de Composants (Emplacement.lua) :
-- « Commander » un bloc, la case « Contrat n°… », son panneau. Sans Composants dans les racines, seuls les premiers tests
-- tournent (Handshake seul).
test("Handshake se charge : plus de projets à lui, plus de table globale des choix", function()
    assertType("table", HandshakeDB)
    assertNil(HandshakeDB.projets)
    assertNil(HandshakeDB.options)
    assertNil(HandshakeDB.force)
    assertNil(HandshakeDB.orders)
    assertType("function", SlashCmdList.HANDSHAKE)
    assertType("table", Handshake)
    assertNil(ComposantsFrame, "plus de fenêtre de l'arbre dans Handshake")
end)

if not Composants then
    test("Handshake seul : /handshake ouvre la commande à la main", function()
        SlashCmdList.HANDSHAKE("")
        assertTrue(HandshakeMainFrame:IsShown())
        HandshakeMainFrame:Hide()
    end)
    return
end

local function enfant(ok)
    for _, c in ipairs({ ComposantsFrame:GetChildren() }) do
        if ok(c) then return c end
    end
end
local function bouton(texte) return enfant(function(c) return c.GetText and c:GetText() == texte and c:GetObjectType() == "Button" end) end
-- Le nom du projet affiché en haut de la fenêtre.
local function affiche(nom)
    for _, r in ipairs({ ComposantsFrame:GetRegions() }) do
        if r.GetText and r:IsShown() and r:GetText() == nom then return true end
    end
    return false
end
-- Le projet affiché dans la fenêtre de Composants.
local function affichePas() return ComposantsDB.projets[ComposantsDB.courant] end
-- Les menus déroulants (contrats, projets) : chaque entrée choisie tour à tour jusqu'à ce que ok() soit vrai, ou celle
-- dont le texte est « entree ».
local function deroulant(f, ok)
    for _, c in ipairs({ f:GetChildren() }) do
        if c.GenerateMenu and c.GetMenuDescription and c:IsVisible() and ok(c) then return c end
        local r = deroulant(c, ok)
        if r then return r end
    end
end
local function parcourir(dd, jusque)
    dd:GenerateMenu()
    local entrees = {}
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do entrees[#entrees + 1] = e end
    for _, e in ipairs(entrees) do
        dd:Pick(e, MenuInputContext.MouseButton, "LeftButton")
        if jusque(MenuUtil.GetElementText(e)) then return true end
    end
end

test("avec Composants : /handshake ouvre la fenêtre de Handshake (Importer) ; plus de barre des commandes dans Composants", function()
    SlashCmdList.HANDSHAKE("")
    assertTrue(HandshakeMainFrame:IsShown(), "la fenêtre de Handshake")
    -- Importer une liste reçue : rare, dans le menu « Plus » de la fenêtre de Handshake (au plus 4 boutons, ui-addon).
    local plus = deroulant(HandshakeMainFrame, function(c) return c.GetText and c:GetText() == "Plus" end)
    assertNotNil(plus, "le menu « Plus » de Handshake")
    assertTrue(parcourir(plus, function(t) return t == "Importer une liste reçue" end), "Importer une liste reçue, dans Handshake")
    assertTrue(HandshakeImport:IsShown(), "la fenêtre d'import")
    for _, c in ipairs({ HandshakeMainFrame:GetChildren() }) do -- plus en boutons : dans « Plus »
        local t = c.GetText and c.GenerateMenu == nil and c:IsShown() and c:GetText()
        assertTrue(t ~= "Importer une liste reçue" and t ~= "En clair", tostring(t) .. " en bouton")
    end
    HandshakeImport:Hide()
    HandshakeMainFrame:Hide()
    SlashCmdList.COMPOSANTS("demo ceinture")
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    for _, t in ipairs({ "Préparer la demande", "Joueur", "Offre", "Commandes :", "Nouvelle version", "Commander de nouveau", "Plus" }) do
        assertNil(bouton(t), t .. " dans Composants")
        for _, r in ipairs({ ComposantsFrame:GetRegions() }) do
            assertTrue(not (r.GetText and r:IsShown() and r:GetText() == t), t .. " écrit dans Composants")
        end
    end
    ComposantsFrame:Hide()
end)

-- « Commander » sur un bloc (Composants#26) crée tout de suite un contrat préparé : le bloc se réduit à une case
-- « Contrat n°… · métier », « artisan · état ». Les blocs viennent de la base des recettes du socle (sa réserve Classic,
-- AzerothCommune/RecettesReserve.lua, générée, hors du repo : à copier dans une branche en worktree), recettes pas apprises
-- comprises (« tout »).
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function boutons(ok) return tous(ComposantsFrame, function(c) return c:GetObjectType() == "Button" and c:IsVisible() and ok(c:GetText() or "") end) end

-- Les cases des contrats (dessinées par Handshake dans l'emplacement du bloc), et la 1re ligne de chacune.
local function casesContrat()
    return tous(ComposantsFrame, function(c) return c.l1 ~= nil and c.l2 ~= nil and c:IsVisible() end)
end
local function cases() return tous(ComposantsFrame, function(c) return c.node ~= nil and c:IsVisible() end) end
-- Le panneau d'un contrat : ses champs (artisan, offre), son bouton d'action, ses menus.
local function panneau() return HandshakeContratPanneau end
local function champs()
    local e = tous(panneau(), function(c) return c:GetObjectType() == "EditBox" and c:IsVisible() end)
    table.sort(e, function(a, b) return a:GetTop() > b:GetTop() end)
    return e[1], e[2] -- artisan, offre
end
local function taper(e, texte) e:SetText(texte); e:GetScript("OnTextChanged")(e, true) end
local function action() return tous(panneau(), function(c) return c:GetObjectType() == "Button" and c:IsVisible() and c:GetWidth() == 150 end)[1] end
local function menu(nom) return deroulant(panneau(), function(c) return c:GetText() == nom end) end
local function entrees(dd)
    dd:GenerateMenu()
    local t = {}
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do t[#t + 1] = e end
    return t
end

-- Personne n'a de recette ici : « recettes pas apprises » cochée, toutes comptent et les blocs se dessinent. L'option est
-- rendue telle quelle, même si une vérification échoue.
local function sansRecettes(f)
    local avant = ComposantsDB.options.unlearned
    ComposantsDB.options.unlearned = true
    local ok, err = pcall(f)
    ComposantsDB.options.unlearned = avant
    ComposantsFrame:Hide()
    if HandshakeContratPanneau then HandshakeContratPanneau:Hide() end
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
    if not ok then error(err, 0) end
end

-- Un contrat porte deux GUID (Handshake#29) : l'artisan d'une demande doit avoir un GUID donné par le serveur. Ici, son
-- chuchotement : le jeu y joint le GUID de l'expéditeur (12e valeur de CHAT_MSG_WHISPER), Handshake le retient.
local ARTISAN = "Bel Dupont"
local function artisanConnu()
    FireEvent("CHAT_MSG_WHISPER", "bonjour", ARTISAN, "", "", ARTISAN, "", 0, 0, "", 0, 1, "Player-1-0000BE11")
end
local function liste(p) return HandshakeDB.commandes[p.id].liste end
-- « Vérifier et envoyer… » : le brouillon de la v1 s'ouvre sur sa fiche dans Contrats (rien sur le fil) ; « Envoyer la
-- proposition », là, le fait partir.
local function verifierEtEnvoyer(c)
    assertEquals("Vérifier et envoyer…", action():GetText())
    action():Click()
    local ct = HandshakeDB.contracts[c.contrat]
    assertNotNil(ct, "un brouillon")
    assertEquals("brouillon", ct.status, "rien sur le fil depuis le panneau")
    assertTrue(HandshakeContratsFrame:IsShown(), "la fiche s'ouvre dans Contrats")
    assertTrue(HandshakeContratsFrame.body:GetText():find("BROUILLON", 1, true) ~= nil, "sur la fiche de ce brouillon")
    local envoyer
    for _, b in ipairs(tous(HandshakeContratsFrame, function(b) return b.GetText and b:GetText() == "Envoyer la proposition" and b:IsShown() end)) do envoyer = b end
    assertNotNil(envoyer, "« Envoyer la proposition » sur la fiche")
    envoyer:Click()
    HandshakeContratsFrame:Hide()
    return HandshakeDB.contracts[c.contrat]
end

test("Commander un bloc : un contrat préparé, le bloc réduit à la case « Contrat n°… », son panneau ouvert", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p, nb, avant = affichePas(), #ComposantsDB.projets, #cases()
    assertEquals(0, #casesContrat(), "rien de commandé")
    local commander = boutons(function(t) return t == "Commander" end)
    assertTrue(#commander > 1, "des blocs dessinés (AzerothCommune/RecettesReserve.lua présent ?)")
    commander[#commander]:Click()
    assertEquals(nb, #ComposantsDB.projets, "pas de nouveau projet")
    local cs = casesContrat()
    assertEquals(1, #cs)
    local c = liste(p)[#liste(p)]
    assertType("number", c.n)
    assertEquals(("Contrat n°%d · %s"):format(c.n, c.bloc), cs[1].l1:GetText())
    assertTrue(cs[1].l2:GetText():find("préparé", 1, true) ~= nil, cs[1].l2:GetText())
    assertTrue(#cases() < avant, "ses cases sortent du dessin")
    assertEquals(#commander - 1, #boutons(function(t) return t == "Commander" end), "un « Commander » de moins")
    assertTrue(panneau():IsShown(), "son panneau s'ouvre")
    assertEquals(("Contrat n°%d · %s"):format(c.n, c.bloc), panneau().title:GetText())
    assertEquals("Vérifier et envoyer…", action():GetText())
end) end)

-- Envoyer (#7, Composants#26) : l'artisan, l'offre et les apports se règlent dans le panneau, « Envoyer » le fait partir ;
-- son état, lu dans son contrat, s'affiche sur la case.
test("Artisan, offre, apports et envoi depuis l'emplacement du bloc", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = affichePas()
    local commander = boutons(function(t) return t == "Commander" end)
    commander[1]:Click()
    local c = liste(p)[#liste(p)]
    artisanConnu()
    local who, tip = champs()
    taper(who, ARTISAN)
    taper(tip, "2")
    assertEquals(ARTISAN, c.player)
    assertEquals(20000, c.tip)
    assertTrue(casesContrat()[1].l2:GetText():find(ARTISAN, 1, true) ~= nil, "l'artisan sur la case")
    -- Les apports : un menu de cases à cocher ; en cocher une la met dans les apports du contrat.
    local cocher
    for _, e in ipairs(entrees(menu("Apports"))) do
        local t = MenuUtil.GetElementText(e) or ""
        if t:find("× ", 1, true) and not t:find("d'un autre bloc", 1, true) then cocher = e break end
    end
    assertNotNil(cocher, "une case à cocher dans le menu des apports")
    menu("Apports"):Pick(cocher, MenuInputContext.MouseButton, "LeftButton")
    assertTrue(next(HandshakeDB.commandes[p.id].apports or {}) ~= nil, "un apport coché")
    local ct = verifierEtEnvoyer(c)
    assertEquals("envoye", ct.status)
    assertEquals("1", ct.v)
    local l2 = casesContrat()[1].l2:GetText()
    assertTrue(l2:find("envoyé", 1, true) ~= nil, l2)
    assertEquals("Voir dans Contrats", action():GetText())
    assertTrue(not who:IsEnabled(), "parti : l'artisan est celui du contrat")
end) end)

-- Écart (#8) : la part d'un contrat parti change ; le panneau le dit et propose « Nouvelle version », qui prépare la v2 en
-- brouillon et l'ouvre dans Contrats (#19) ; elle part de là. Refusé, le bloc revient et se commande de nouveau.
test("Un contrat parti signale l'écart ; sa nouvelle version se relit avant l'envoi ; refusé, le bloc revient", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = affichePas()
    boutons(function(t) return t == "Commander tout" end)[1]:Click()
    assertEquals(1, #casesContrat(), "tout le projet : une seule case")
    assertEquals(0, #cases(), "plus aucune autre case")
    artisanConnu()
    taper((champs()), ARTISAN)
    local c = liste(p)[1]
    local ct = verifierEtEnvoyer(c)
    assertEquals("envoye", ct.status)
    p.lines[1].qty = p.lines[1].qty + 1 -- une ligne de plus à fabriquer : la part de « tout le projet » change
    Composants.Rafraichir()
    assertTrue(panneau().etat:GetText():find("ne correspond plus au contrat", 1, true) ~= nil, panneau().etat:GetText())
    assertEquals("1", ct.v, "rien ne part sans clic")
    assertEquals("Nouvelle version", action():GetText())
    action():Click()
    local brouillon = HandshakeDB.contracts[c.contrat .. "+"]
    assertEquals("brouillon", brouillon.status)
    assertEquals("2", brouillon.v)
    assertTrue(HandshakeContratsFrame:IsShown(), "le brouillon de la v2 s'ouvre dans les contrats")
    local fiche
    for _, r in ipairs(tous(HandshakeContratsFrame, function() return true end)) do
        for _, z in ipairs({ r:GetRegions() }) do
            if z.GetText and (z:GetText() or ""):find("Changé depuis la v1", 1, true) then fiche = true end
        end
    end
    assertTrue(fiche, "le différentiel est affiché avant l'envoi")
    for _, b in ipairs(tous(HandshakeContratsFrame, function(b) return b.GetText and b:GetText() == "Envoyer la proposition" and b:IsShown() end)) do b:Click() end
    HandshakeContratsFrame:Hide()
    local v2 = HandshakeDB.contracts[c.contrat]
    assertEquals("2", v2.v)
    assertEquals("envoye", v2.status)
    Composants.Rafraichir()
    assertEquals("Voir dans Contrats", action():GetText(), "partie : plus d'écart")
    v2.status = "refuse" -- (comme s'il l'avait refusée)
    Composants.Rafraichir()
    assertEquals(0, #casesContrat(), "refusé : le bloc revient")
    assertTrue(#cases() > 0, "l'arbre revient")
    assertNotNil(boutons(function(t) return t == "Commander tout" end)[1], "il se commande de nouveau")
end) end)

-- Supprimer le projet (Composants#26) : ses contrats préparés (et leurs brouillons) s'effacent, jamais un contrat parti.
test("Supprimer le projet efface ses contrats préparés, jamais un contrat parti", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = affichePas()
    local commander = boutons(function(t) return t == "Commander" end)
    commander[1]:Click()
    artisanConnu()
    taper((champs()), ARTISAN)
    verifierEtEnvoyer(liste(p)[#liste(p)])
    local parti = liste(p)[#liste(p)].contrat
    assertEquals("envoye", HandshakeDB.contracts[parti].status)
    boutons(function(t) return t == "Commander" end)[1]:Click()
    local prepare = liste(p)[#liste(p)]
    assertNil(prepare.contrat, "préparé : rien dans Contrats")
    Composants.Supprimer(p.id)
    assertNil(HandshakeDB.commandes[p.id], "ses contrats préparés effacés")
    assertNotNil(HandshakeDB.contracts[parti], "le contrat parti reste")
    assertEquals("envoye", HandshakeDB.contracts[parti].status)
end) end)

-- Hors Préparer (Fabriquer, Fini), l'arbre est en lecture seule, l'emplacement aussi : la case et son état, « Voir dans
-- Contrats » ; ni Commander, ni Commander tout, ni artisan, offre, apports ou « Plus ».
test("Hors Préparer, l'emplacement est en lecture seule", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = affichePas()
    boutons(function(t) return t == "Commander" end)[1]:Click()
    panneau():Hide()
    local ok, err = pcall(function()
        p.phase = "fabriquer"
        Composants.Rafraichir()
        assertEquals(0, #boutons(function(t) return t == "Commander" or t == "Commander tout" end), "rien à commander")
        assertEquals(1, #casesContrat(), "la case reste")
        casesContrat()[1]:Click()
        assertTrue(panneau():IsShown(), "son panneau, en lecture")
        assertEquals("Voir dans Contrats", action():GetText())
        assertTrue(not action():IsEnabled(), "préparé : rien encore dans Contrats")
        local who, tip = champs()
        assertTrue(not who or (not who:IsEnabled() and not tip:IsEnabled()), "artisan et offre figés")
        assertNil(menu("Apports"), "pas de menu des apports")
        assertNil(menu("Plus"), "pas de « Plus » (ni Abandonner)")
    end)
    p.phase = nil
    if not ok then error(err, 0) end
end) end)

-- Recettes équivalentes (#46), avec la vraie réserve (extraite du client, transmutations d'essences en boucle) : dans la
-- démo « set », les essences de terre et d'eau s'achètent, aucune essence n'est fabriquée par une transmutation.
test("Démo « set » : pas de boucle de transmutation, les essences s'achètent", function() sansRecettes(function()
    SlashCmdList.COMPOSANTS("demo set")
    local caseDe = {}
    for _, c in ipairs(tous(ComposantsFrame, function(c) return c.node ~= nil end)) do caseDe[c.node.id] = c.node end
    assertNotNil(caseDe[7076], "une case Essence de terre (AzerothCommune/RecettesReserve.lua présent ?)")
    assertNotNil(caseDe[7080], "une case Essence d'eau")
    for _, id in ipairs({ 7076, 7078, 7080, 7082, 12803, 12808 }) do
        assertTrue(caseDe[id] == nil or caseDe[id].made == 0, "essence " .. id .. " fabriquée")
    end
end) end)

-- Règles de la réponse (#10) : la fenêtre demande au projet ce qui se modifie. Dans une réponse (un projet tenu, #37), la
-- quantité de ce qu'il veut est grisée ; dans un projet à moi, elle se tape. (Une réponse à un contrat qui n'existe pas :
-- seul compte qu'elle en soit une.) Le projet redevient le mien même si une vérification échoue.
-- Les champs de quantité des cases de la colonne 0 (une case porte son nœud).
local function quantites()
    return tous(ComposantsFrame, function(c) return c:GetObjectType() == "EditBox" and c:IsVisible() and c:GetParent().node ~= nil end)
end
test("Dans une réponse, la quantité de ce qu'il veut est grisée, d'après le projet", function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = ComposantsDB.projets[#ComposantsDB.projets]
    local ok, err = pcall(function()
        assertTrue(#quantites() > 0, "une case par objet du projet")
        for _, q in ipairs(quantites()) do assertTrue(q:IsEnabled(), "mon projet : la quantité se tape") end
        HandshakeDB.commandes = HandshakeDB.commandes or {}
        HandshakeDB.commandes[p.id] = HandshakeDB.commandes[p.id] or { liste = { { id = 1 } }, seq = 1 }
        HandshakeDB.commandes[p.id].reponse, p.tenu = "Bob-R#1", "c'est sa demande : ce qu'il veut ne change pas ici"
        Composants.Rafraichir() -- le même projet, redessiné
        assertEquals(p, affichePas())
        assertTrue(#quantites() > 0, "toujours affichée")
        for _, q in ipairs(quantites()) do assertTrue(not q:IsEnabled(), "réponse : la quantité est figée") end
        local rep = boutons(function(t) return t:find("^Réponse à ") ~= nil end)[1]
        assertNotNil(rep, "la Réponse, sur la ligne du projet")
        rep:Click()
        assertEquals("Contre-proposer", action():GetText(), "une réponse se contre-propose, de son panneau")
    end)
    HandshakeDB.commandes[p.id].reponse, p.tenu = nil, nil
    ComposantsFrame:Hide()
    if not ok then error(err, 0) end
end)

-- AzerothCommune#49 : la barre de recherche de la fenêtre propose ce que rend la recherche d'objets du socle, dans son
-- ordre (Handshake n'a plus d'index d'objets à lui).
test("la barre de recherche propose les objets de la recherche du socle", function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local box = enfant(function(c) return c:GetObjectType() == "EditBox" and math.floor(c:GetWidth() + 0.5) == 280 end)
    assertNotNil(box, "barre de recherche")
    box:SetText("bronze")
    box:GetScript("OnTextChanged")(box, true)
    local attendus = AzerothCommune.ChercherObjets("bronze", 8)
    assertEquals(8, #attendus)
    local montres = tous(ComposantsFrame, function(c)
        return c:GetObjectType() == "Button" and c:IsShown() and c.text ~= nil and math.floor(c:GetWidth() + 0.5) == 316
    end)
    assertEquals(#attendus, #montres)
    for i, e in ipairs(attendus) do
        assertEquals(e.name .. (e.fabricable and "  |cffe6a640fabricable|r" or ""), montres[i].text:GetText())
    end
    box:SetText("")
    ComposantsFrame:Hide()
end)

-- Réponse (#39) : une demande reçue, « Répondre dans l'arbre » dans Contrats, s'ouvre comme un projet tenu de Composants
-- (ce qu'il veut, avec la raison de Handshake) ; on y commande un bloc à un autre artisan (sous-traitance).
local function boutonDe(f, texte)
    local function chercher(x)
        for _, c in ipairs({ x:GetChildren() }) do
            if c:GetObjectType() == "Button" and c:IsShown() and c.GetText and c:GetText() == texte then return c end
            local r = chercher(c)
            if r then return r end
        end
    end
    return chercher(f)
end
test("une demande reçue s'ouvre en Réponse, un projet tenu de Composants ; on en commande un bloc", function() sansRecettes(function()
    local moi, cle = UnitGUID("player"), "Player-1-0000B0B0#4343"
    local c = { origin = "Player-1-0000B0B0", id = "4343", v = "1", parent = "0", client = "Player-1-0000B0B0", artisan = moi,
        m = {}, o = { { id = 10721, qty = 1, unit = 50000 } }, d = GetServerTime() + 86400,
        hash = "00000000cafebabe", status = "a_signer", author = "Player-1-0000B0B0", peer = { guid = "Player-1-0000B0B0", name = "Bob Dupont" } }
    HandshakeDB.contracts[cle] = c
    local ok, err = pcall(function()
        SlashCmdList.HANDSHAKECONTRAT()
        parcourir(deroulant(HandshakeContratsFrame, function() return true end),
            function() return boutonDe(HandshakeContratsFrame, "Répondre dans l'arbre") ~= nil end)
        boutonDe(HandshakeContratsFrame, "Répondre dans l'arbre"):Click()
        HandshakeContratsFrame:Hide()
        assertTrue(ComposantsFrame:IsShown(), "la Réponse s'ouvre dans la fenêtre de Composants")
        local p = affichePas()
        assertEquals("Réponse à Bob", p.name)
        assertEquals(1, #p.lines)
        assertEquals(10721, p.lines[1].id)
        assertType("string", p.tenu)
        local refus, raison = Composants.Ajouter(p, 2841, 1)
        assertTrue(refus == false and raison == p.tenu, "ses lignes sont tenues, avec la raison de Handshake")
        assertEquals(cle, HandshakeDB.commandes[p.id].reponse)
        local rep = boutons(function(t) return t:find("^Réponse à Bob") ~= nil end)[1]
        assertNotNil(rep, "la Réponse, sur la ligne du projet")
        rep:Click()
        assertEquals("Contre-proposer", action():GetText())
        assertEquals("Réponse à Bob", panneau().title:GetText())
        assertEquals(0, #boutons(function(t) return t == "Commander tout" end), "une Réponse ne se commande pas en entier")
        local commander = boutons(function(t) return t == "Commander" end)
        assertTrue(#commander > 0, "« Commander » sur les blocs de la Réponse")
        commander[1]:Click()
        local l = liste(p)
        assertEquals(2, #l)
        assertNil(l[1].n, "la 1re reste la Réponse, pas un contrat préparé")
        assertType("number", l[2].n, "le bloc commandé : un contrat préparé (sous-traitance)")
        assertEquals(1, #casesContrat())
        assertTrue(casesContrat()[1].l2:GetText():find("préparé", 1, true) ~= nil)
        -- Supprimer la Réponse dans Composants : ses contrats préparés s'effacent, le contrat reste.
        Composants.Supprimer(p.id)
        assertNil(HandshakeDB.commandes[p.id])
        assertNotNil(HandshakeDB.contracts[cle], "aucun contrat perdu")
    end)
    HandshakeDB.contracts[cle] = nil
    if not ok then error(err, 0) end
end) end)

-- Les contrats dans les Besoins (Composants#27) : une ligne par contrat du projet, « Contrat n°… · à recevoir », verte
-- « reçu » à la livraison ; Lancer marche avec un contrat pas signé ; tout réuni mais un contrat ouvert, on reste en
-- Réunir, livré : Fabriquer ; mes apports sont des lignes des Besoins ; abandonné (ou retiré), le bloc revient dans
-- l'arbre et ses composants dans les Besoins. Les sacs du simulateur sont vides : les lignes d'objets restent à réunir.
local function lignesContrat()
    return tous(ComposantsBesoinsFrame, function(c) return c.texte ~= nil and c.abandon ~= nil and c:IsVisible() end)
end
local function objetsBesoins()
    local out = {}
    for _, c in ipairs(tous(ComposantsBesoinsFrame, function(c) return c.itemID ~= nil and c:IsShown() end)) do out[c.itemID] = c end
    return out
end
local function besoinsAussi(f)
    sansRecettes(function()
        local ok, err = pcall(f)
        if ComposantsBesoinsFrame then ComposantsBesoinsFrame:Hide() end
        if not ok then error(err, 0) end
    end)
end

test("Besoins : la ligne du contrat, verte à la livraison ; les apports ; abandonné, le bloc et ses composants reviennent", function() besoinsAussi(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = affichePas()
    -- Les Besoins sans contrat, pour comparer.
    ComposantsFrame.lancerB:Click()
    local sans = objetsBesoins()
    assertEquals(0, #lignesContrat(), "aucun contrat : aucune ligne de contrat")
    Composants.Ouvrir(p.id)
    p.phase = nil -- (revenu en Préparer pour commander)
    Composants.Ouvrir(p.id)
    local commander = boutons(function(t) return t == "Commander" end)
    commander[#commander]:Click() -- la première étape : son bloc
    local c = liste(p)[#liste(p)]
    artisanConnu()
    taper((champs()), ARTISAN)
    local ct = verifierEtEnvoyer(c)
    assertEquals("envoye", ct.status)
    panneau():Hide()
    ComposantsFrame.lancerB:Click()
    assertEquals("reunir", p.phase, "Lancer avec un contrat pas signé")
    local l = lignesContrat()
    assertEquals(1, #l, "une ligne par contrat")
    assertEquals(("Contrat n°%d · à recevoir"):format(c.n), l[1].texte:GetText())
    assertTrue(l[1].abandon:IsVisible(), "« Abandonner » sur la ligne")
    local avec = objetsBesoins()
    local sorti
    for id in pairs(sans) do if not avec[id] then sorti = id end end
    assertNotNil(sorti, "le bloc confié : ses composants sortent des Besoins")
    -- Livré : la ligne passe au vert ; les lignes d'objets manquent encore, on reste en Réunir.
    ct.status = "clos" -- (comme après le dernier échange vérifié)
    Composants.Rafraichir()
    l = lignesContrat()
    assertEquals(("|cff59cc73Contrat n°%d · reçu|r"):format(c.n), l[1].texte:GetText())
    assertTrue(not l[1].abandon:IsVisible(), "livré : rien à abandonner")
    assertEquals("reunir", p.phase, "des objets à réunir encore")
    -- Retiré (comme s'il l'avait été) : le bloc revient, la ligne part, ses composants reviennent.
    ct.status = "retire"
    Composants.Rafraichir()
    assertEquals(0, #lignesContrat(), "retiré : plus de ligne")
    assertNotNil(objetsBesoins()[sorti], "retiré : ses composants reviennent dans les Besoins")
    -- Commandé de nouveau, un apport coché : une ligne des Besoins ; Abandonner (préparé) : le bloc revient dans l'arbre.
    p.phase = nil
    Composants.Ouvrir(p.id)
    commander = boutons(function(t) return t == "Commander" end)
    commander[#commander]:Click()
    local cocher, id
    for _, e in ipairs(entrees(menu("Apports"))) do
        local t = MenuUtil.GetElementText(e) or ""
        if t:find("× ", 1, true) and not t:find("d'un autre bloc", 1, true) then cocher = e break end
    end
    assertNotNil(cocher, "une case à cocher dans le menu des apports")
    menu("Apports"):Pick(cocher, MenuInputContext.MouseButton, "LeftButton")
    id = next(HandshakeDB.commandes[p.id].apports)
    panneau():Hide()
    ComposantsFrame.lancerB:Click()
    assertNotNil(objetsBesoins()[id], "l'apport : une ligne des Besoins")
    assertEquals(1, #lignesContrat())
    lignesContrat()[1].abandon:Click()
    assertEquals(0, #lignesContrat(), "abandonné : plus de ligne")
    assertNotNil(objetsBesoins()[sorti], "abandonné : ses composants reviennent dans les Besoins")
    p.phase = nil
    Composants.Ouvrir(p.id)
    assertEquals(0, #casesContrat(), "abandonné : le bloc revient dans l'arbre")
    assertEquals(#commander, #boutons(function(t) return t == "Commander" end), "il se commande de nouveau")
end) end)

test("Tout réuni mais le contrat ouvert : Réunir ; livré : Fabriquer", function() besoinsAussi(function()
    SlashCmdList.COMPOSANTS("demo ceinture")
    local p = affichePas()
    boutons(function(t) return t == "Commander tout" end)[1]:Click()
    artisanConnu()
    taper((champs()), ARTISAN)
    local ct = verifierEtEnvoyer(liste(p)[1])
    panneau():Hide()
    ComposantsFrame.lancerB:Click()
    assertEquals("reunir", p.phase, "Lancer : Réunir")
    assertNil(next(objetsBesoins()), "tout confié, rien à apporter : rien à réunir")
    assertEquals(1, #lignesContrat())
    Composants.Rafraichir()
    assertEquals("reunir", p.phase, "le contrat ouvert : on reste en Réunir")
    ct.status = "clos"
    Composants.Rafraichir()
    assertEquals("fabriquer", p.phase, "livré : Fabriquer tout seul")
end) end)
