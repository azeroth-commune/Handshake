-- Les fenêtres de Handshake au look du jeu (#62) dans le simulateur : agrandies, elles montrent plus ; le contrat pendant
-- l'échange n'a pas de poignée et sa hauteur suit son texte (tout ce qui est vérifié reste visible).
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

-- Asynchrone : le jeu (et le simulateur) signale un changement de taille (OnSizeChanged) à l'image suivante.
local function ensuite(done, fn)
    C_Timer.After(0.05, function()
        local ok, err = pcall(fn)
        if not ok then done(function() error(err, 0) end) end
    end)
end

async_test("Commande à la main agrandie : plus de lignes, les boutons du bas restent en bas", function(done)
    HandshakeDB.main = { lines = {}, apporte = {} }
    for i = 1, 14 do HandshakeDB.main.lines[i] = { id = 2770 + i, qty = 1 } end
    SlashCmdList.HANDSHAKE("")
    local f = HandshakeMainFrame
    local w, h = f:GetSize()
    local function vues() local n = 0 for _, r in ipairs(f.cols[1].rows) do if r:IsShown() then n = n + 1 end end return n end
    local function fin() f:SetSize(w, h); f:Hide(); HandshakeDB.main = nil end
    ensuite(done, function()
        assertEquals(4, vues(), "4 lignes à la taille de départ")
        assertEquals("… et 10 autre(s)", f.cols[1].more:GetText())
        assertNotNil(f.ResizeButton, "une poignée")
        f:SetSize(w + 200, h + 260)
        ensuite(done, function()
            done(function()
                local ok, err = pcall(function()
                    assertEquals(14, vues(), "agrandie : toutes les lignes")
                    assertEquals("", f.cols[1].more:GetText())
                    local go = bouton(f, "Préparer la demande")
                    assertTrue(math.abs(go:GetBottom() - f:GetBottom() - 12) < 1, "« Préparer la demande » collé au bas")
                    assertTrue(f.cols[2].depot:GetLeft() > f:GetLeft() + (w + 200) / 2 - 10, "la seconde colonne prend la moitié droite")
                end)
                fin()
                if not ok then error(err, 0) end
            end)
        end)
    end)
end)

async_test("Contrats agrandie : le texte suit la largeur ; aucun bouton en haut, la fiche sous la barre de titre", function(done)
    SlashCmdList.HANDSHAKECONTRAT()
    local f = HandshakeContratsFrame
    local w, h = f:GetSize()
    for _, t in ipairs({ "Commande à la main", "Sauvegarder" }) do assertNil(bouton(f, t), "plus de « " .. t .. " »") end
    local haut = f.body:GetTop()
    assertTrue(haut <= f:GetTop() - 24 and haut >= f:GetTop() - 40, "la fiche sous la barre de titre : " .. (f:GetTop() - haut))
    local avant = f.body:GetWidth()
    f:SetSize(w + 200, h)
    ensuite(done, function()
        done(function()
            local large = f.body:GetWidth()
            f:SetSize(w, h)
            f:Hide()
            assertTrue(large >= avant + 190, "le texte s'élargit avec la fenêtre : " .. avant .. " -> " .. large)
            assertTrue(avant >= 440, "à la taille de départ, le texte a sa place : " .. avant)
        end)
    end)
end)

test("Contrats : une colonne à gauche, une entrée par contrat ; un clic l'affiche, surlignée ; plus de menu déroulant", function()
    local moi = UnitGUID("player")
    local cles, noms = {}, { "Aline Brouillon", "Bruno Attente", "Carla Signer", "Denis Signé" }
    for i, st in ipairs({ "brouillon", "envoye", "a_signer", "signe" }) do
        local g = ("Player-1-0000C0%02d"):format(i)
        cles[i] = g .. "#77" .. i
        HandshakeDB.contracts[cles[i]] = { origin = g, id = "77" .. i, v = "1", parent = "0", client = moi, artisan = g,
            m = {}, o = { { id = 2841, qty = 1, unit = 100 } }, d = GetServerTime() + 86400, hash = ("0000000%dfeedface"):format(i),
            status = st, signed = st == "signe" and GetServerTime() or nil, author = moi, peer = { guid = g, name = noms[i] } }
    end
    local ok, err = pcall(function()
        SlashCmdList.HANDSHAKECONTRAT()
        local f = HandshakeContratsFrame
        for _, c in ipairs({ f:GetChildren() }) do assertTrue(not c.GetMenuDescription, "plus de menu déroulant") end
        local montrees = {}
        for _, b in ipairs(f.entrees) do if b:IsShown() then montrees[#montrees + 1] = b end end
        for i, cle in ipairs(cles) do
            local b
            for _, x in ipairs(montrees) do if x.c == HandshakeDB.contracts[cle] then b = x end end
            assertNotNil(b, "l'entrée de " .. noms[i])
            assertTrue(b.nom:GetText():find(noms[i], 1, true) == 1, b.nom:GetText())
            b:Click()
            assertTrue(f.body:GetText():find("Contrat avec " .. noms[i], 1, true) ~= nil, "le clic affiche " .. noms[i])
            for _, x in ipairs(montrees) do assertEquals(x == b, x.fond:IsShown(), "surlignée : seulement l'affichée") end
            assertTrue(b.trait:IsShown(), "le trait doré")
            assertEquals(({ "brouillon", "en attente", "à signer", "signé" })[i], (b.etat:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")), "l'état court")
        end
        -- l'ordre de la colonne : à signer, brouillon, en attente, signé (ORDER)
        local rang = {}
        for k, x in ipairs(montrees) do rang[x.c] = k end
        local function r(i) return rang[HandshakeDB.contracts[cles[i]]] end
        assertTrue(r(3) < r(1) and r(1) < r(2) and r(2) < r(4), "triée comme le menu d'avant")
        assertTrue(montrees[1]:GetLeft() < f.body:GetLeft(), "la colonne à gauche du contrat")
        -- « + Nouvelle commande » : la première ligne de la colonne, au-dessus de tous les contrats ; elle ouvre la Commande à la main.
        local nouvelle = bouton(f, "+ Nouvelle commande")
        assertNotNil(nouvelle, "« + Nouvelle commande »")
        assertTrue(nouvelle:GetLeft() < f.body:GetLeft(), "dans la colonne")
        for _, x in ipairs(montrees) do assertTrue(nouvelle:GetBottom() >= x:GetTop() - 1, "au-dessus de " .. x.nom:GetText()) end
        nouvelle:Click()
        assertTrue(HandshakeMainFrame and HandshakeMainFrame:IsShown(), "la Commande à la main s'ouvre")
        HandshakeMainFrame:Hide()
    end)
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
    for _, cle in ipairs(cles) do HandshakeDB.contracts[cle] = nil end
    if not ok then error(err, 0) end
end)

test("contrat pendant l'échange : pas de poignée, tout son texte dans le cadre, hors d'Échap, en DIALOG", function()
    local moi, testeur = UnitGUID("player"), "Player-0-00000DEB" -- le Testeur du mode debug (Debug.lua)
    local o = {}
    for i = 1, 16 do o[i] = { id = 2770 + i, qty = 2, unit = 100 } end
    local cle = "Player-0-00000DEB#9191"
    HandshakeDB.contracts[cle] = { origin = testeur, id = "9191", v = "1", parent = "0", client = moi, artisan = testeur,
        m = {}, o = o, d = GetServerTime() + 86400, hash = "00000000cafebabe", status = "signe", signed = GetServerTime(),
        author = moi, peer = { guid = testeur, name = "Testeur Bacasable" }, got = {}, gave = {}, net = 0 }
    local debugAvant = HandshakeDB.debug
    local ok, err = pcall(function()
        SlashCmdList.HANDSHAKE("debug")
        bouton(HandshakeDebug, "Évaluer"):Click()
        local p = HandshakeEchangePanel
        assertTrue(p:IsShown(), "le panneau s'ouvre")
        assertNil(p.ResizeButton, "pas de poignée")
        assertEquals("DIALOG", p:GetFrameStrata())
        for _, n in ipairs(UISpecialFrames) do assertTrue(n ~= "HandshakeEchangePanel", "Échap ferme l'échange, pas le panneau seul") end
        assertTrue(p.lines:GetStringHeight() > 16 * 10, "un texte long")
        local bas = math.min(p.lines:GetBottom(), p.notes:GetBottom())
        assertTrue(bas >= p.fill:GetTop(), "tout le texte au-dessus des boutons")
        assertTrue(p.lines:GetTop() <= p:GetTop() - 24, "le texte sous la barre de titre")
    end)
    if HandshakeEchangePanel then HandshakeEchangePanel:Hide() end
    if HandshakeDebug then -- le bac à sable recoupé (ouvrir le debug l'allume) : les tests suivants envoient pour de vrai
        local sable = tous(HandshakeDebug, function(c) return c:GetObjectType() == "CheckButton" and c:GetChecked() and c:GetPoint(1) and select(5, c:GetPoint(1)) == -38 and select(4, c:GetPoint(1)) == 12 end)[1]
        if sable then sable:Click() end
        HandshakeDebug:Hide()
    end
    HandshakeDB.contracts[cle], HandshakeDB.debug = nil, debugAvant
    if not ok then error(err, 0) end
end)
