-- Handshake#1 (ADR 0001 de l'atelier) : Handshake ne sauvegarde aucune donnée relevée ; il souscrit à ses types de
-- données et les lit par le socle Azeroth Commune.
test("Handshake souscrit à ses types de données", function()
    for _, t in ipairs({ "recettes connues", "inventaires", "métiers et compétences", "marchands", "objets", "cours de l'HV" }) do
        -- tenue par la base du socle (AzerothCommune#41), datée de ce chargement : faite au chargement de Handshake, après
        -- celui du socle (pas une date restée dans des SavedVariables)
        assertType("number", AzerothCommuneDB.souscriptions[t])
        assertTrue(time() - AzerothCommuneDB.souscriptions[t] < 600, t)
    end
end)

-- Handshake#34 : la réserve Classic (RecettesClassic.lua) est remise au socle à notre chargement ; son relevé des
-- recettes connues sans fenêtre l'interroge (une recette de la réserve, connue d'un perso simulé qui a son métier).
test("réserve Classic remise au socle : le relevé sans fenêtre l'interroge", function()
    assertType("table", HandshakeClassicRecipes)
    local id, c = next(HandshakeClassicRecipes)
    local vrais = { GetProfessions, GetProfessionInfo, IsPlayerSpell, C_Timer.After }
    GetProfessions = function() return 1 end
    GetProfessionInfo = function() return c[4], nil, 100, 300 end
    IsPlayerSpell = function(s) return s == id end
    C_Timer.After = function(_, fn) fn() end -- les images du relevé, tout de suite
    local metiers, fini = {}, false
    local ok, err = pcall(AzerothCommune.ReleverRecettesSansFenetre, AzerothCommune, metiers, {}, function() fini = true end)
    GetProfessions, GetProfessionInfo, IsPlayerSpell, C_Timer.After = vrais[1], vrais[2], vrais[3], vrais[4]
    assertTrue(ok, tostring(err))
    assertTrue(fini)
    assertNotNil(metiers[c[4]] and metiers[c[4]].known[id], "recette " .. id .. " (" .. c[4] .. ") relevée sans fenêtre")
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
