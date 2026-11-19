-- Tests d'intégration dans wow-ui-sim (tools/sim.sh test Handshake) : Handshake chargé avec LibCommune et GameData dans
-- l'interface Forever simulée (le WTF de session ne contient pas nos SavedVariables : la migration des commandes en
-- projets est testée dans check.lua).
test("Handshake se charge : des projets, plus de table globale des choix", function()
    assertType("table", HandshakeDB)
    assertType("table", HandshakeDB.projets)
    assertNil(HandshakeDB.force)
    assertNil(HandshakeDB.orders)
    assertType("function", SlashCmdList.HANDSHAKE)
end)

local function enfant(ok)
    for _, c in ipairs({ HandshakeFrame:GetChildren() }) do
        if ok(c) then return c end
    end
end
local function bouton(texte) return enfant(function(c) return c.GetText and c:GetText() == texte and c:GetObjectType() == "Button" end) end
-- Le nom du projet affiché en haut de la fenêtre.
local function affiche(nom) return enfant(function(c) return c:GetObjectType() == "EditBox" and c:GetText() == nom end) ~= nil end

test("un projet créé s'ouvre dans la fenêtre, < et > passent d'un projet à l'autre", function()
    SlashCmdList.HANDSHAKE("demo ceinture") -- crée un projet et ouvre la fenêtre (calcul et dessin de l'arbre)
    assertTrue(HandshakeFrame:IsShown())
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    SlashCmdList.HANDSHAKE("demo set")
    assertTrue(affiche("Essai : set en thorium enchanté"))
    bouton("<"):Click()
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    bouton(">"):Click()
    assertTrue(affiche("Essai : set en thorium enchanté"))
    HandshakeFrame:Hide()
end)
