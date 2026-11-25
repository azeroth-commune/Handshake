-- Annonces (#51, #52, #53, #55) dans le simulateur : publier une commande dans le Commerce (« Annoncer »), par Trade Board quand
-- il est là, et lire les demandes du Commerce que je sais fabriquer.
-- (Nommé pour passer après composants.lua, qui vérifie qu'aucune fenêtre de Composants n'est encore ouverte au départ.)
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function boutonQui(f, ok)
    return tous(f, function(c) return c:GetObjectType() == "Button" and c:IsShown() and c.GetText and ok(c:GetText() or "") end)[1]
end
local function deroulant(f, ok)
    for _, c in ipairs({ f:GetChildren() }) do
        if c.GenerateMenu and c.GetMenuDescription and c:IsVisible() and ok(c) then return c end
        local r = deroulant(c, ok)
        if r then return r end
    end
end
local function choisir(dd, texte)
    dd:GenerateMenu()
    for _, e in dd:GetMenuDescription():EnumerateElementDescriptions() do
        if MenuUtil.GetElementText(e) == texte then
            dd:Pick(e, MenuInputContext.MouseButton, "LeftButton")
            return true
        end
    end
end

-- Le canal Commerce et l'envoi, simulés le temps de f : rend les messages envoyés { msg, kind, cible }.
local function enVille(f)
    local envoyes = {}
    local G, S, CS = GetChannelList, SendChatMessage, C_ChatInfo.SendChatMessage
    local function envoi(msg, kind, _, cible) envoyes[#envoyes + 1] = { msg = msg, kind = kind, cible = cible } end
    GetChannelList = function() return 1, "Général - Hurlevent", false, 2, "Commerce - Ville", false end
    SendChatMessage, C_ChatInfo.SendChatMessage = envoi, envoi
    local ok, err = pcall(f, envoyes)
    GetChannelList, SendChatMessage, C_ChatInfo.SendChatMessage = G, S, CS
    if not ok then error(err, 0) end
end
-- Une annonce : « WTB » en tête, 255 octets au plus, chaque lien entier (son nom entre crochets fermé).
local function annonceSaine(msg)
    assertTrue(msg:find("^WTB ") ~= nil, msg)
    assertTrue(#msg <= 255, #msg .. " octets")
    assertEquals(select(2, msg:gsub("|Hitem:", "")), select(2, msg:gsub("|Hitem:[^|]*|h%[[^%]]*%]|h", "")))
end

test("Annoncer la commande à la main : un message WTB dans le Commerce, l'offre au bout, puis le bouton dit quand réessayer", function()
    enVille(function(envoyes)
        HandshakeDB.main = { lines = { { id = 2841, qty = 10 }, { id = 2840, qty = 4 } }, apporte = {}, tip = 50000 }
        SlashCmdList.HANDSHAKE("liste")
        local b = boutonQui(HandshakeMainFrame, function(t) return t == "Annoncer" end)
        assertNotNil(b, "le bouton « Annoncer »")
        b:Click()
        assertEquals(1, #envoyes)
        assertEquals("CHANNEL", envoyes[1].kind)
        assertEquals(2, envoyes[1].cible)
        annonceSaine(envoyes[1].msg)
        assertTrue(envoyes[1].msg:find("|Hitem:2841:", 1, true) ~= nil, "le lien de l'objet : " .. envoyes[1].msg)
        assertTrue(envoyes[1].msg:find(" x10, ", 1, true) ~= nil, envoyes[1].msg)
        assertTrue(envoyes[1].msg:find(" x4 · offre 5 po$") ~= nil, envoyes[1].msg)
        assertTrue(b:GetText():find("^Annoncer à %d") ~= nil, b:GetText())
        assertTrue(not b:IsEnabled(), "trop tôt : grisé")
        b:Click()
        assertEquals(1, #envoyes)
    end)
    HandshakeMainFrame:Hide()
    HandshakeDB.main = nil
end)

test("hors d'une ville, le bouton « Annoncer » le dit", function()
    HandshakeDB.main = { lines = { { id = 2770, qty = 1 } }, apporte = {} }
    local G = GetChannelList
    GetChannelList = function() return 1, "Général - Elwynn", false end
    SlashCmdList.HANDSHAKE("liste")
    local b = boutonQui(HandshakeMainFrame, function(t) return t == "Pas de Commerce ici" end)
    GetChannelList = G
    assertNotNil(b)
    assertTrue(not b:IsEnabled())
    HandshakeMainFrame:Hide()
    HandshakeDB.main = nil
end)

-- Un faux Trade Board (son API hôte) : rend la table et le journal de ses appels.
local function fauxTradeBoard(version)
    local appels, possede = {}, {}
    local tb = { hostApiVersion = version }
    for _, f in ipairs({ "OpenRequestDialog", "AddRequest", "RemoveOwnRequest" }) do
        tb[f] = function(_, kind, id, q)
            appels[#appels + 1] = f .. " " .. kind .. " " .. id .. (q and (" " .. q) or "")
            possede[id] = f ~= "RemoveOwnRequest" or nil
        end
    end
    tb.HasOwnRequest = function(_, _, id) return possede[id] == true end
    return tb, appels
end

test("avec Trade Board (version 1) : son dialogue rempli, rien publié par Handshake ; partie en contrat, retirée", function()
    local tb, appels = fauxTradeBoard(1)
    tradeBoard = tb
    local ok, err = pcall(enVille, function(envoyes)
        HandshakeDB.main = nil
        local m = { lines = { { id = 2841, qty = 6 } }, apporte = {} }
        HandshakeDB.main = m
        SlashCmdList.HANDSHAKE("liste")
        boutonQui(HandshakeMainFrame, function(t) return t == "Annoncer (Trade Board)" end):Click()
        assertEquals(0, #envoyes)
        assertEquals("OpenRequestDialog item 2841 6", appels[1])
        -- L'artisan connu (son chuchotement donne son GUID), la demande préparée puis envoyée depuis Contrats.
        FireEvent("CHAT_MSG_WHISPER", "bonjour", "Bel Dupont", "", "", "Bel Dupont", "", 0, 0, "", 0, 1, "Player-1-0000BE11")
        m.player = "Bel Dupont"
        boutonQui(HandshakeMainFrame, function(t) return t == "Préparer la demande" end):Click()
        boutonQui(HandshakeContratsFrame, function(t) return t == "Envoyer la proposition" end):Click()
        assertEquals("envoye", HandshakeDB.contracts[m.contrat].status)
        assertEquals("RemoveOwnRequest item 2841", appels[#appels])
        HandshakeDB.contracts[m.contrat] = nil
    end)
    tradeBoard = nil
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
    HandshakeMainFrame:Hide()
    HandshakeDB.main = nil
    if not ok then error(err, 0) end
end)

test("Trade Board d'une autre version, ou absent : l'annonce de Handshake, sans erreur", function()
    for _, version in ipairs({ 2, false }) do
        local tb, appels = fauxTradeBoard(version)
        tradeBoard = version and tb or nil
        enVille(function(envoyes)
            HandshakeDB.main = { lines = { { id = 2842, qty = version and 3 or 5 } }, apporte = {} }
            SlashCmdList.HANDSHAKE("liste")
            boutonQui(HandshakeMainFrame, function(t) return t == "Annoncer" end):Click()
            assertEquals(1, #envoyes)
            assertEquals(0, #appels)
        end)
    end
    tradeBoard = nil
    HandshakeMainFrame:Hide()
    HandshakeDB.main = nil
end)

-- Annonces lues (#52) : de fausses lignes du Commerce ; mon perso sait fabriquer un objet de la base des recettes.
test("Annonces lues : WTB d'un objet que je sais faire, listé et nettoyé ; WTS et piège écartés ; Répondre chuchote", function()
    local moi = AzerothCommuneDB.chars[UnitGUID("player")]
    assertNotNil(moi, "mon perso dans la base du socle")
    local cle, objet
    for k, r in pairs(AzerothCommune:Lire("base des recettes") or {}) do
        if type(k) == "number" and r.output then cle, objet = k, r.output break end
    end
    assertNotNil(cle, "une recette dans la base (RecettesReserve.lua du socle présent ?)")
    local avant, chuchotes = moi.recipes, {}
    moi.recipes = { Forge = { rank = 300, known = { [cle] = "easy" } } }
    local S, CS = SendChatMessage, C_ChatInfo.SendChatMessage
    local function envoi(msg, kind, _, cible) chuchotes[#chuchotes + 1] = { msg = msg, kind = kind, cible = cible } end
    SendChatMessage, C_ChatInfo.SendChatMessage = envoi, envoi
    local ok, err = pcall(function()
        local lien = "|cffffffff|Hitem:" .. objet .. "::::::::::::::::|h[Faux nom]|h|r"
        local function commerce(msg, qui, guid)
            FireEvent("CHAT_MSG_CHANNEL", msg, qui, "", "2. Commerce - Ville", qui, "", 0, 2, "Commerce - Ville", 0, 1, guid)
        end
        commerce("WTB " .. lien .. " pst", "Bob Dupont", "Player-1-00000B0B")
        commerce("WTS " .. lien, "Cid Lebrun", "Player-1-00000C1D")
        commerce("WTB " .. lien .. " |TInterface\\Icons\\INV_Misc_Coin_01:0|t |Hurl:http://x|h[clique]|h |cffff0000rouge|r", "Mal Truand", "Player-1-0000BAD0")
        SlashCmdList.HANDSHAKE("annonces")
        assertTrue(HandshakeDemandesFrame:IsShown())
        local textes = {}
        for _, r in ipairs(HandshakeDemandesFrame.rows) do
            if r:IsShown() then textes[#textes + 1] = { qui = r.qui:GetText(), texte = r.texte:GetText(), bouton = r.repondre } end
        end
        local vus = {}
        for _, t in ipairs(textes) do vus[#vus + 1] = t.qui:match("^(%S+ %S+)") end
        table.sort(vus)
        assertEquals("Bob Dupont,Mal Truand", table.concat(vus, ","))
        for _, t in ipairs(textes) do
            assertTrue(not t.texte:find("|T", 1, true) and not t.texte:find("|Hurl", 1, true) and not t.texte:find("Faux nom", 1, true), t.texte)
            assertTrue(t.texte:find("|Hitem:" .. objet, 1, true) ~= nil, "le lien refait ici : " .. t.texte)
        end
        assertEquals(0, #chuchotes) -- rien sans clic
        local bob
        for _, t in ipairs(textes) do if t.qui:find("^Bob Dupont") then bob = t end end
        bob.bouton:Click()
        assertEquals(1, #chuchotes)
        assertEquals("WHISPER", chuchotes[1].kind)
        assertEquals("Bob Dupont", chuchotes[1].cible)
        assertEquals("Répondu", bob.bouton:GetText())
        -- L'onglet « Commande » ouvre la commande à la main à la place.
        HandshakeDemandesFrame.Tabs[1]:Click()
        assertTrue(HandshakeMainFrame:IsShown() and not HandshakeDemandesFrame:IsShown(), "les onglets relient les deux fenêtres")
    end)
    moi.recipes, SendChatMessage, C_ChatInfo.SendChatMessage = avant, S, CS
    if HandshakeMainFrame then HandshakeMainFrame:Hide() end
    if HandshakeDemandesFrame then HandshakeDemandesFrame:Hide() end
    if not ok then error(err, 0) end
end)

test("Annonces lues par métier : « LF BS » listée pour la Forge, sans icône ; /handshake essai lue", function()
    local moi = AzerothCommuneDB.chars[UnitGUID("player")]
    local avant, P, dits = moi.recipes, print, {}
    moi.recipes = { Forge = { rank = 300, known = {} } }
    print = function(s) dits[#dits + 1] = s end
    local ok, err = pcall(function()
        FireEvent("CHAT_MSG_CHANNEL", "LF BS pls", "Jo Enclume", "", "2. Commerce - Ville", "Jo Enclume", "", 0, 2, "Commerce - Ville", 0, 1, "Player-1-00000E0E")
        FireEvent("CHAT_MSG_CHANNEL", "LFW blacksmith", "Lou Offre", "", "2. Commerce - Ville", "Lou Offre", "", 0, 2, "Commerce - Ville", 0, 1, "Player-1-00000E0F")
        SlashCmdList.HANDSHAKE("annonces")
        local jo, lou
        for _, r in ipairs(HandshakeDemandesFrame.rows) do
            if r:IsShown() and r.qui:GetText():find("^Jo Enclume") then jo = r end
            if r:IsShown() and r.qui:GetText():find("^Lou Offre") then lou = r end
        end
        assertNotNil(jo, "la demande de Jo listée")
        assertTrue(lou == nil, "LFW : une offre, pas listée")
        assertTrue(jo.qui:GetText():find("métier : Forge", 1, true) ~= nil, jo.qui:GetText())
        assertEquals("LF BS pls", jo.texte:GetText())
        assertTrue(not jo.objet:IsShown(), "pas d'icône d'objet")
        SlashCmdList.HANDSHAKE("essai lue WTS bs")
        assertTrue(dits[#dits]:find("offre", 1, true) ~= nil, dits[#dits])
        SlashCmdList.HANDSHAKE("essai lue cherche un forgeron")
        assertTrue(dits[#dits]:find("Essai", 1, true) ~= nil, dits[#dits])
    end)
    moi.recipes, print = avant, P
    if HandshakeDemandesFrame then HandshakeDemandesFrame:Hide() end
    if not ok then error(err, 0) end
end)

test("Annonces lues : une ligne du Commerce déjà dans le chat (arrivée avant) est lue à l'ouverture de la fenêtre", function()
    local moi = AzerothCommuneDB.chars[UnitGUID("player")]
    local cle, objet
    for k, r in pairs(AzerothCommune:Lire("base des recettes") or {}) do
        if type(k) == "number" and r.output then cle, objet = k, r.output break end
    end
    local avant, cl, zl, censure = moi.recipes, ChatFrame1.channelList, ChatFrame1.zoneChannelList, C_ChatInfo.IsChatLineCensored
    moi.recipes = { Forge = { rank = 300, known = { [cle] = "easy" } } }
    local ok, err = pcall(function()
        -- ChatFrame1 abonné au Commerce ; la ligne passe par le vrai gestionnaire du chat de Blizzard, mais pas par Handshake
        -- (comme une ligne arrivée avant son chargement). Le simulateur n'a pas IsChatLineCensored : bouchon.
        C_ChatInfo.IsChatLineCensored = censure or function() return false end
        ChatFrame1:AddMessageGroup("CHANNEL")
        ChatFrame1.channelList, ChatFrame1.zoneChannelList = { "Commerce - Ville" }, { 0 }
        local lien = "|cffffffff|Hitem:" .. objet .. "::::::::::::::::|h[Faux nom]|h|r"
        ChatFrame1:GetScript("OnEvent")(ChatFrame1, "CHAT_MSG_CHANNEL", "WTB " .. lien .. " |TInterface\\Icons\\INV_Misc_Coin_01:0|t svp",
            "Ana Avant", "", "2. Commerce - Ville", "Ana Avant", "", 0, 2, "Commerce - Ville", 0, 4242, "Player-1-00000A4A",
            0, false, false, false, false, { userID = 0 })
        local derniere = ChatFrame1:GetMessageInfo(ChatFrame1:GetNumMessages())
        assertTrue(derniere:find("Ana Avant", 1, true) ~= nil, "la ligne est dans ChatFrame1 : " .. derniere)
        SlashCmdList.HANDSHAKE("annonces")
        local ana
        for _, r in ipairs(HandshakeDemandesFrame.rows) do
            if r:IsShown() and r.qui:GetText():find("^Ana Avant") then ana = r end
        end
        assertNotNil(ana, "la demande d'avant listée")
        assertTrue(ana.qui:GetText():find("dans le Commerce", 1, true) ~= nil, ana.qui:GetText())
        local t = ana.texte:GetText()
        assertTrue(t:find("|Hitem:" .. objet, 1, true) ~= nil and not t:find("|T", 1, true) and not t:find("Faux nom", 1, true), t)
        -- Rouvrir : lue une fois.
        HandshakeDemandesFrame:Hide()
        SlashCmdList.HANDSHAKE("annonces")
        local n = 0
        for _, r in ipairs(HandshakeDemandesFrame.rows) do
            if r:IsShown() and r.qui:GetText():find("^Ana Avant") then n = n + 1 end
        end
        assertEquals(1, n)
        -- Gardée pour un /reload, nettoyée.
        local g = HandshakeDB.demandes[UnitGUID("player")]["Ana Avant#" .. objet]
        assertNotNil(g, "gardée dans HandshakeDB")
        assertTrue(not g.texte:find("|T", 1, true), g.texte)
    end)
    moi.recipes, ChatFrame1.channelList, ChatFrame1.zoneChannelList, C_ChatInfo.IsChatLineCensored = avant, cl, zl, censure
    if HandshakeDemandesFrame then HandshakeDemandesFrame:Hide() end
    if not ok then error(err, 0) end
end)

if not Composants then return end

-- Une liste sans arbre se commande en entier (Composants#26) : « Commander tout », puis le menu « Plus » du panneau de son
-- contrat préparé (une fenêtre de Handshake).
test("« Annoncer dans le Commerce » dans le menu « Plus » du contrat préparé : regroupée, 255 octets, liens intacts", function()
    enVille(function(envoyes)
        local lines = {}
        for _, id in ipairs({ 2841, 2840, 2842, 3575, 3576, 3577, 3859, 3860, 6037, 12359 }) do lines[#lines + 1] = { id = id, qty = 20 } end
        local p = Composants.NouveauProjet({ name = "Annonce longue", lines = lines })
        Composants.Ouvrir(p.id)
        local tout
        local function chercher(f)
            for _, c in ipairs({ f:GetChildren() }) do
                if c.GetText and c:IsVisible() and c:GetText() == "Commander tout" then tout = c end
                chercher(c)
            end
        end
        chercher(ComposantsFrame)
        assertNotNil(tout, "« Commander tout » sur la ligne du projet")
        tout:Click()
        local plus = deroulant(HandshakeContratPanneau, function(c) return c.GetText and c:GetText() == "Plus" end)
        assertNotNil(plus, "le menu « Plus » du panneau")
        assertTrue(choisir(plus, "Annoncer dans le Commerce"), "l'entrée du menu")
        assertEquals(1, #envoyes)
        annonceSaine(envoyes[1].msg)
        assertTrue(envoyes[1].msg:find(" …$") ~= nil, "trop d'objets : coupée, « … » au bout")
        Composants.Supprimer(p.id)
    end)
    ComposantsFrame:Hide()
    if HandshakeContratPanneau then HandshakeContratPanneau:Hide() end
end)
