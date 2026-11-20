-- Handshake#1 (ADR 0001 de l'atelier) : Handshake ne sauvegarde aucune donnée relevée ; il souscrit à ses types de
-- données et les lit par la lib commune (avec GameData dans le simulateur).
test("Handshake souscrit à ses types de données", function()
    local lib = LibStub("LibCommune-1.0")
    for _, t in ipairs({ "recettes connues", "inventaires", "métiers et compétences", "marchands", "objets", "cours de l'HV" }) do
        assertTrue(lib.souscriptions[t] == true)
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

-- LibCommune#19 : mes persos sont rangés sous leur GUID ; « moi » est l'adresse rendue par la lib commune.
test("mon perso par son GUID : recettes connues sous mon GUID, mon adresse par la lib", function()
    local lib = LibStub("LibCommune-1.0")
    local moi = lib.Personnage()
    assertEquals(UnitGUID("player"), moi.guid)
    assertEquals(moi.adresse, lib.Adresse((UnitName("player"))))
    local d = lib:Lire("inventaires", "tous")
    if not d then SlashCmdList.GAMEDATA("") d = lib:Lire("inventaires", "tous") end -- /gdata : relevé tout de suite
    assertNotNil(d, "inventaires relevés (Handshake y souscrit)")
    local n = 0
    for cle in pairs(d.persos) do n = n + 1; assertTrue(cle:find("^Player%-") ~= nil, "clé " .. cle) end
    assertTrue(n > 0, "au moins mon perso")
    assertNotNil(d.persos[UnitGUID("player")], "mon perso sous mon GUID")
    SlashCmdList.HANDSHAKE("demo ceinture") -- la fenêtre lit les artisans et le stock par GUID
    assertTrue(HandshakeFrame:IsShown())
    HandshakeFrame:Hide()
end)
