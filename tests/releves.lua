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
