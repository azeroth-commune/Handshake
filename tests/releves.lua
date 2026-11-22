-- Handshake#1 (ADR 0001 de l'atelier) : Handshake ne sauvegarde aucune donnée relevée ; il souscrit à ses types de
-- données et les lit par le socle Azeroth Commune.
test("Handshake souscrit à ses types de données", function()
    for _, t in ipairs({ "base des recettes", "marchands", "objets", "cours de l'HV" }) do
        -- tenue par la base du socle (AzerothCommune#41), datée de ce chargement : faite au chargement de Handshake, après
        -- celui du socle (pas une date restée dans des SavedVariables)
        assertType("number", AzerothCommuneDB.souscriptions[t])
        assertTrue(time() - AzerothCommuneDB.souscriptions[t] < 600, t)
    end
end)

-- Handshake#36 : plus de réserve livrée avec Handshake ni de remise au socle ; ses recettes sont la base des recettes du
-- socle (recettes vues, puis sa réserve Classic pour les objets qu'aucune recette vue ne fabrique).
test("recettes lues dans la base des recettes du socle, plus de réserve dans Handshake", function()
    assertNil(HandshakeClassicRecipes)
    assertNil(AzerothCommune.RemettreRecettes)
    local base = AzerothCommune:Lire("base des recettes")
    assertNotNil(base, "base des recettes vide (RecettesClassic.lua du socle présent ?)")
    local _, r = next(base)
    assertType("number", r.output)
    assertType("string", r.profession)
end)

test("HandshakeDB sans données relevées après le chargement", function()
    assertType("table", HandshakeDB)
    for _, k in ipairs({ "recipes", "chars", "items", "market" }) do assertNil(HandshakeDB[k]) end
    assertType("table", HandshakeDB.contracts) -- ses données propres, elles, sont là
end)


-- LibCommune#19, #35 : mes persos sont rangés sous leur GUID ; la lib rend mon GUID et mon nom, plus d'adresse.
-- (Les inventaires par GUID sont lus par Composants depuis Handshake#39 : testés avec lui.)
test("mon perso par son GUID, mon nom par la lib", function()
    local moi = AzerothCommune.Personnage()
    assertEquals(UnitGUID("player"), moi.guid)
    assertType("string", moi.nom)
    assertNil(moi.adresse)
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
