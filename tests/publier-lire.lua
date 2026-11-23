-- Annonces (#51, #52, #53) dans le simulateur : publier une commande dans le Commerce (« Annoncer »), par Trade Board quand
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

test("Annoncer la commande à la main : un message WTB dans le Commerce, puis le bouton dit quand réessayer", function()
    enVille(function(envoyes)
        HandshakeDB.main = { lines = { { id = 2841, qty = 10 }, { id = 2840, qty = 4 } }, apporte = {} }
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
        assertTrue(envoyes[1].msg:find(" x4$") ~= nil, envoyes[1].msg)
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

if not Composants then return end

test("« Annoncer dans le Commerce » dans le menu « Plus » de Composants : regroupée, 255 octets, liens intacts", function()
    enVille(function(envoyes)
        local lines = {}
        for _, id in ipairs({ 2841, 2840, 2842, 3575, 3576, 3577, 3859, 3860, 6037, 12359 }) do lines[#lines + 1] = { id = id, qty = 20 } end
        local p = Composants.NouveauProjet({ name = "Annonce longue", lines = lines })
        Composants.Ouvrir(p.id)
        local plus = deroulant(ComposantsFrame, function(c) return c.GetText and c:GetText() == "Plus" end)
        assertNotNil(plus, "le menu « Plus »")
        assertTrue(choisir(plus, "Annoncer dans le Commerce"), "l'entrée du menu")
        assertEquals(1, #envoyes)
        annonceSaine(envoyes[1].msg)
        assertTrue(envoyes[1].msg:find(" …$") ~= nil, "trop d'objets : coupée, « … » au bout")
        Composants.Supprimer(p.id)
    end)
    ComposantsFrame:Hide()
end)
