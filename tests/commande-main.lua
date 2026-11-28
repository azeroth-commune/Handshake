-- Commande à la main (#38) dans le simulateur : la liste se remplit par la recherche d'objets du socle et par un objet déposé,
-- part en demande par le chemin d'aujourd'hui (brouillon relu dans Contrats, « Envoyer ») ; côté artisan, sans
-- Composants, « Répondre » répond à une demande reçue dans la liste (#74 : plus de « Répondre en liste »).
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
-- La colonne des contrats : chaque entrée cliquée tour à tour jusqu'à ce que jusque() soit vrai.
local function parcourirContrats(jusque)
    for _, b in ipairs(HandshakeContratsFrame.entrees) do
        if b:IsShown() then
            b:Click()
            if jusque() then return true end
        end
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
    -- son Handshake a répondu (#71) : le contrat part par Handshake
    FireEvent("CHAT_MSG_ADDON", "Handshake", "1/1|H|3|Player-1-0000BE11", "WHISPER", ARTISAN)
    bouton(HandshakeContratsFrame, "Envoyer"):Click()
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

test("sans Composants, « Répondre » répond dans la liste : ce qu'il veut est figé ; plus de « Répondre en liste »", function()
    local moi = UnitGUID("player")
    local c = { origin = "Player-1-0000B0B0", id = "4242", v = "1", parent = "0", client = "Player-1-0000B0B0", artisan = moi,
        m = { { id = 2770, qty = 4, unit = 10 } }, o = { { id = 2841, qty = 2, unit = 5040 } }, d = GetServerTime() + 86400,
        hash = "00000000deadbeef", status = "a_signer", author = "Player-1-0000B0B0", peer = { guid = "Player-1-0000B0B0", name = "Bob Dupont" } }
    HandshakeDB.contracts["Player-1-0000B0B0#4242"] = c
    SlashCmdList.HANDSHAKECONTRAT()
    parcourirContrats(function() return bouton(HandshakeContratsFrame, "Répondre") ~= nil end)
    assertNil(bouton(HandshakeContratsFrame, "Répondre en liste"), "un seul « Répondre »")
    local C0 = Composants
    Composants = nil
    local ok, err = pcall(function() bouton(HandshakeContratsFrame, "Répondre"):Click() end)
    Composants = C0
    if not ok then error(err, 0) end
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
