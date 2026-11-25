-- Le menu du bouton commun : chaque fenêtre de Handshake a sa ligne (aucune seulement par une commande).
test("Menu commun : Commande à la main, Contrats et Annonces lues s'ouvrent depuis leur ligne", function()
    local hs
    for _, r in ipairs(AzerothCommune.regroupes) do if r.nom == "Handshake" then hs = r end end
    assertType("table", hs)
    for _, l in ipairs({ "Commande à la main", "Contrats", "Annonces lues" }) do
        local o
        for _, x in ipairs(hs.outils) do if x.libelle == l then o = x end end
        assertType("table", o)
        o.ouvrir()
        assertEquals(true, _G[o.fenetre]:IsShown())
        _G[o.fenetre]:Hide()
    end
end)
