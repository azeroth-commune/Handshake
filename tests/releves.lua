-- Handshake#1 (ADR 0001 de l'atelier) : Handshake ne sauvegarde aucune donnée relevée ; il souscrit à ses types de
-- données et les lit par le socle Azeroth Commune.
test("Handshake souscrit à ses types de données", function()
    local lib = AzerothCommune
    for _, t in ipairs({ "recettes connues", "inventaires", "métiers et compétences", "marchands", "objets", "cours de l'HV" }) do
        assertType("number", AzerothCommuneDB.souscriptions[t]) -- la souscription est tenue par la base du socle (AzerothCommune#41)
    end
end)

test("HandshakeDB sans données relevées après le chargement", function()
    assertType("table", HandshakeDB)
    for _, k in ipairs({ "recipes", "chars", "items", "market" }) do assertNil(HandshakeDB[k]) end
    assertType("table", HandshakeDB.options) -- ses données propres, elles, sont là
    assertType("table", HandshakeDB.contracts)
end)

test("la fenêtre se calcule par la lib : un projet, l'état de l'HV", function()
    SlashCmdList.HANDSHAKE("demo ceinture")
    assertTrue(HandshakeFrame:IsShown())
    HandshakeFrame:Hide()
    for _, k in ipairs({ "recipes", "chars", "items", "market" }) do assertNil(HandshakeDB[k]) end
end)

-- LibCommune#19, #35 : mes persos sont rangés sous leur GUID ; la lib rend mon GUID et mon nom, plus d'adresse.
test("mon perso par son GUID : recettes connues sous mon GUID, mon nom par la lib", function()
    local lib = AzerothCommune
    local moi = lib.Personnage()
    assertEquals(UnitGUID("player"), moi.guid)
    assertType("string", moi.nom)
    assertNil(moi.adresse)
    local d = lib:Lire("inventaires", "tous")
    if not d then SlashCmdList.AZEROTHCOMMUNE("") d = lib:Lire("inventaires", "tous") end -- /ac : relevé tout de suite
    assertNotNil(d, "inventaires relevés (Handshake y souscrit)")
    local n = 0
    for cle in pairs(d.persos) do n = n + 1; assertTrue(cle:find("^Player%-") ~= nil, "clé " .. cle) end
    assertTrue(n > 0, "au moins mon perso")
    assertNotNil(d.persos[UnitGUID("player")], "mon perso sous mon GUID")
    SlashCmdList.HANDSHAKE("demo ceinture") -- la fenêtre lit les artisans et le stock par GUID
    assertTrue(HandshakeFrame:IsShown())
    HandshakeFrame:Hide()
end)

-- Handshake#29 : les contrats sont signés par GUID ; ceux d'avant (signataires « Prénom-Royaume ») sont purgés au
-- chargement, et les noms de famille d'avant aussi (le nom complet vient maintenant du serveur).
test("chargement : contrats signés par GUID seulement, plus de noms de famille gardés", function()
    assertType("table", HandshakeDB.contracts)
    for cle, c in pairs(HandshakeDB.contracts) do
        assertTrue(tostring(c.client):find("^Player%-") ~= nil, "contrat d'avant le GUID resté : " .. tostring(cle))
    end
    assertNil(HandshakeDB.surnames)
    local lib = AzerothCommune
    assertNil(lib.Adresse) -- plus d'adresse dans le socle : Handshake était son dernier appelant
    assertEquals(lib.Personnage().nom, lib.Destinataire(lib.Personnage().nom)) -- chuchoté par son nom complet
end)
