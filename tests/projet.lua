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

-- Commandes (#6) : « Commander » sur un bloc ajoute une commande à la liste du projet, sans nouvelle page. Les blocs
-- viennent de la réserve Classic (RecettesClassic.lua, généré, hors du repo : à copier dans une branche en worktree),
-- recettes pas apprises comprises (« tout »).
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function boutons(ok) return tous(HandshakeFrame, function(c) return c:GetObjectType() == "Button" and c:IsShown() and ok(c:GetText() or "") end) end
-- La liste des commandes : un bouton par commande, « part · artisan[ · offre] ».
local function commandes() return boutons(function(t) return t:find(" · ", 1, true) ~= nil end) end

test("Commander un bloc ajoute une commande au projet, sur la même page", function()
    local avant = HandshakeDB.options.unlearned
    HandshakeDB.options.unlearned = true -- personne n'a de recette ici : toutes comptent, les blocs se dessinent
    SlashCmdList.HANDSHAKE("demo ceinture")
    local nb = #HandshakeDB.projets
    assertEquals(1, #commandes()) -- tout le projet
    local commander = boutons(function(t) return t == "Commander" end)
    assertTrue(#commander > 0, "des blocs dessinés (RecettesClassic.lua présent ?)")
    commander[1]:Click()
    assertEquals(nb, #HandshakeDB.projets)
    assertTrue(affiche("Essai : ceintures multi-métiers"))
    local liste = commandes()
    assertEquals(2, #liste)
    commander[1]:Click() -- le même bloc : la même commande
    assertEquals(2, #commandes())
    HandshakeDB.options.unlearned = avant
    HandshakeFrame:Hide()
end)
