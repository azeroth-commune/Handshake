-- Commande à la main (#38) dans le simulateur : la liste se remplit par la recherche d'objets du socle et par un objet déposé,
-- part en demande par le chemin d'aujourd'hui (brouillon relu dans Contrats, « Envoyer la proposition ») ; côté artisan,
-- une demande reçue se répond dans la liste.
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function bouton(f, texte)
    return tous(f, function(c) return c:GetObjectType() == "Button" and c:IsShown() and c.GetText and c:GetText() == texte end)[1]
end
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
-- Les deux barres de recherche : « ce que je veux » à gauche, « ce que j'apporte » à droite.
local function recherches()
    local r = tous(HandshakeMainFrame, function(c) return c:GetObjectType() == "EditBox" and c.recherche ~= nil end)
    table.sort(r, function(a, b) return a:GetLeft() < b:GetLeft() end)
    return r
end
-- Taper dans une barre et choisir la 1re suggestion (celle de la recherche du socle).
local function choisir(box, texte)
    box:SetText(texte)
    box:GetScript("OnTextChanged")(box, true)
    local premier = AzerothCommune.ChercherObjets(texte, 8)[1]
    assertNotNil(premier, "la recherche du socle trouve « " .. texte .. " »")
    local s = tous(HandshakeMainFrame, function(c) return c:GetObjectType() == "Button" and c:IsShown() and c.text ~= nil and c.text.GetText ~= nil and (c.text:GetText() or ""):find(premier.name, 1, true) == 1 end)
    assertTrue(#s > 0, "suggestion affichée")
    s[1]:Click()
    return premier.id
end

local ARTISAN = "Bel Dupont"
local function artisanConnu() -- son chuchotement : le jeu y joint son GUID (Handshake le retient)
    FireEvent("CHAT_MSG_WHISPER", "bonjour", ARTISAN, "", "", ARTISAN, "", 0, 0, "", 0, 1, "Player-1-0000BE11")
end

test("commande à la main → demande → contrat", function()
    HandshakeDB.main = nil
    SlashCmdList.HANDSHAKE("liste")
    assertTrue(HandshakeMainFrame:IsShown())
    local veux, apporte = unpack(recherches())
    assertNotNil(apporte, "deux barres de recherche")
    local voulu = choisir(veux, "bronze")
    local apport = choisir(apporte, "cuivre")
    -- Un objet pris dans les sacs et déposé sur la liste « j'apporte » y entre ; le curseur est vidé.
    -- Maj+clic n'est plus pris : il garde son sens dans le jeu (séparer une pile, lien dans la discussion).
    local zone = HandshakeMainFrame.cols[2].depot
    assertNotNil(zone, "la liste reçoit un objet déposé")
    local getCursor, clear, vide = GetCursorInfo, ClearCursor, false
    GetCursorInfo = function() return "item", 2589 end
    ClearCursor = function() vide = true end
    zone:GetScript("OnReceiveDrag")(zone)
    GetCursorInfo, ClearCursor = getCursor, clear
    assertTrue(vide, "curseur vidé")
    local m = HandshakeDB.main
    assertEquals(1, #m.lines)
    assertEquals(voulu, m.lines[1].id)
    assertEquals(2, #m.apporte)
    assertEquals(apport, m.apporte[1].id)
    assertEquals(2589, m.apporte[2].id)
    artisanConnu()
    m.player, m.tip = ARTISAN, 20000
    bouton(HandshakeMainFrame, "Préparer la demande"):Click()
    assertTrue(HandshakeContratsFrame:IsShown(), "le brouillon s'ouvre dans les contrats")
    local ct = HandshakeDB.contracts[m.contrat]
    assertEquals("brouillon", ct.status)
    bouton(HandshakeContratsFrame, "Envoyer la proposition"):Click()
    assertEquals("envoye", ct.status)
    assertEquals("1", ct.v)
    assertEquals(voulu, ct.o[1].id)
    assertEquals(1, ct.o[1].qty)
    local ids = {}
    for _, l in ipairs(ct.m) do ids[l.id] = l.qty end
    assertEquals(1, ids[apport])
    assertEquals(1, ids[2589])
    HandshakeContratsFrame:Hide()
    HandshakeMainFrame:Hide()
    HandshakeMainFrame:Show()
    local vu
    for _, r in ipairs({ HandshakeMainFrame:GetRegions() }) do
        if r.GetText and (r:GetText() or ""):find("Contrat envoyé", 1, true) then vu = true end
    end
    assertTrue(vu, "l'état de la demande s'affiche dans la liste")
    HandshakeMainFrame:Hide()
    HandshakeDB.main = nil
end)

test("une demande reçue se répond dans la liste : ce qu'il veut est figé", function()
    local moi = UnitGUID("player")
    local c = { origin = "Player-1-0000B0B0", id = "4242", v = "1", parent = "0", client = "Player-1-0000B0B0", artisan = moi,
        m = { { id = 2770, qty = 4, unit = 10 } }, o = { { id = 2841, qty = 2, unit = 5040 } }, d = GetServerTime() + 86400,
        hash = "00000000deadbeef", status = "a_signer", author = "Player-1-0000B0B0", peer = { guid = "Player-1-0000B0B0", name = "Bob Dupont" } }
    HandshakeDB.contracts["Player-1-0000B0B0#4242"] = c
    SlashCmdList.HANDSHAKECONTRAT()
    parcourir(deroulant(HandshakeContratsFrame, function() return true end),
        function() return bouton(HandshakeContratsFrame, "Répondre en liste") ~= nil end)
    bouton(HandshakeContratsFrame, "Répondre en liste"):Click()
    assertTrue(HandshakeMainFrame:IsShown())
    local veux, apporte = unpack(recherches())
    assertTrue(not veux:IsShown(), "ce qu'il veut : pas de recherche")
    assertTrue(apporte:IsShown(), "ses apports : la recherche reste")
    local qtes = tous(HandshakeMainFrame, function(x) return x:GetObjectType() == "EditBox" and x:IsVisible() and x.liste == "lines" end)
    assertEquals(1, #qtes)
    assertTrue(not qtes[1]:IsEnabled(), "la quantité de ce qu'il veut est grisée")
    assertNotNil(bouton(HandshakeMainFrame, "Contre-proposer…"))
    HandshakeMainFrame:Hide()
    HandshakeContratsFrame:Hide()
    HandshakeDB.contracts["Player-1-0000B0B0#4242"] = nil
end)
