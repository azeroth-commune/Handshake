-- La fenêtre Contrats retient le contrat affiché par sa clé (#69) : une proposition qui arrive en tête, un brouillon
-- périmé effacé ne font pas glisser un autre contrat sous les yeux ; un clic d'envoi part avec ce qui est affiché, ou rien.
local moi = UnitGUID("player")
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
-- Un contrat de moi (client) avec g, posé directement dans la base.
local function contrat(g, id, status, nom, champs)
    local c = { origin = g, id = id, v = "1", parent = "0", client = moi, artisan = g, m = {},
        o = { { id = 2841, qty = 1, unit = 100 } }, d = GetServerTime() + 86400, status = status, author = moi,
        peer = { guid = g, name = nom } }
    for k, v in pairs(champs or {}) do c[k] = v end
    return c
end
local A, B, C = "Player-1-0000A001", "Player-1-0000B002", "Player-1-0000C003"
local cles = { A .. "#771", B .. "#880", B .. "#880+", C .. "#990" }
for i = 1, 6 do cles[#cles + 1] = ("Player-1-0000D00%d#66%d"):format(i, i) end -- ceux de la colonne (#72)
local function ouvrir() SlashCmdList.HANDSHAKECONTRAT() return HandshakeContratsFrame end -- ouvre ou rafraîchit
local function affiche(f)
    for _, nom in ipairs({ "Aline Affichee", "Bruno Encours", "Carla Arrivee" }) do
        if f.titre:GetText():find(nom, 1, true) == 1 then return nom end
    end
end
local function cliquerEntree(f, nom)
    for _, b in ipairs(f.entrees) do if b:IsShown() and b.c.peer.name == nom then return b:Click() end end
    error("pas d'entrée pour " .. nom)
end
-- Chaque test sur une base des contrats à lui (les tests d'avant en laissent : leur tri, leurs archivés), rendue après.
local function sur(fn)
    local avant = HandshakeDB.contracts
    HandshakeDB.contracts = {}
    local ok, err = pcall(fn)
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
    HandshakeDB.contracts = avant
    if not ok then error(err, 0) end
end

test("Contrats : le contrat affiché reste le même quand un autre arrive en tête ou qu'un brouillon périmé est effacé", function()
    sur(function()
        local db = HandshakeDB.contracts
        db[cles[1]] = contrat(A, "771", "brouillon", "Aline Affichee")
        db[cles[2]] = contrat(B, "880", "envoye", "Bruno Encours", { hash = "00000000000b0880" })
        -- un brouillon de sa v2, rangé avant celui d'Aline (même état, numéro plus grand)
        db[cles[3]] = contrat(B, "880", "brouillon", "Bruno Encours", { v = "2", parent = "00000000000b0880" })
        local f = ouvrir()
        cliquerEntree(f, "Aline Affichee")
        assertEquals("Aline Affichee", affiche(f))
        db[cles[4]] = contrat(C, "990", "a_signer", "Carla Arrivee", { hash = "00000000000c0990", author = C, artisan = moi, client = C })
        ouvrir()
        assertEquals("Aline Affichee", affiche(f), "une proposition arrivée en tête ne prend pas sa place")
        db[cles[2]].status = "refuse" -- la version en cours a changé : le brouillon de Bruno est périmé
        ouvrir()
        assertEquals(nil, db[cles[3]], "le brouillon périmé est effacé")
        assertEquals("Aline Affichee", affiche(f), "et Aline reste affichée")
    end)
end)

test("Contrats : un clic d'envoi dont le contrat affiché a changé n'envoie rien, une ligne le dit", function()
    local dits, P = {}, print
    local ok, err = pcall(sur, function()
        print = function(s) dits[#dits + 1] = tostring(s) end
        local db = HandshakeDB.contracts
        db[cles[1]] = contrat(A, "771", "brouillon", "Aline Affichee")
        local f = ouvrir()
        cliquerEntree(f, "Aline Affichee")
        -- refait ailleurs (Composants refait un brouillon), sans que la fenêtre se redessine : autre empreinte
        local refait = contrat(A, "771", "brouillon", "Aline Affichee", { o = { { id = 2841, qty = 1, unit = 900 } } })
        db[cles[1]] = refait
        bouton(f, "Envoyer la proposition"):Click()
        assertEquals(refait, db[cles[1]], "autre empreinte : rien n'est parti, ni l'ancien brouillon affiché")
        assertEquals("brouillon", refait.status, "autre empreinte : rien n'est parti")
        assertTrue(#dits > 0 and dits[#dits]:find("a changé", 1, true) ~= nil, "une ligne le dit : " .. tostring(dits[#dits]))
        -- le clic a redessiné : c'est maintenant le brouillon refait qui est affiché ; effacé sans redessin : autre clé
        db[cles[1]] = nil
        local n = #dits
        bouton(f, "Envoyer la proposition"):Click()
        assertEquals("brouillon", refait.status, "plus affichable : rien n'est parti")
        assertTrue(#dits > n and dits[#dits]:find("a changé", 1, true) ~= nil, "une ligne le dit")
        -- relu (la fenêtre redessinée), le clic part avec ce qui est affiché ; Aline a Handshake (un message d'elle : #71)
        FireEvent("CHAT_MSG_ADDON", "Handshake", "1/1|H|3|" .. A, "WHISPER", "Aline Affichee")
        db[cles[1]] = refait
        ouvrir()
        cliquerEntree(f, "Aline Affichee")
        bouton(f, "Envoyer la proposition"):Click()
        assertEquals("envoye", refait.status, "relu : il part")
    end)
    print = P -- rendu même si le test échoue
    if not ok then error(err, 0) end
end)

test("Contrats : Entrée dans un champ ne valide jamais rien (P7)", function()
    sur(function()
        local db = HandshakeDB.contracts
        db[cles[1]] = contrat(A, "771", "brouillon", "Aline Affichee")
        db[cles[4]] = contrat(C, "990", "a_signer", "Carla Arrivee", { hash = "00000000000c0990", author = C, artisan = moi, client = C })
        local f = ouvrir()
        for _, nom in ipairs({ "Aline Affichee", "Carla Arrivee" }) do
            cliquerEntree(f, nom)
            local champs = tous(f, function(c) return c:GetObjectType() == "EditBox" and c:IsVisible() end)
            assertTrue(#champs >= 3, "les champs de " .. nom)
            for _, e in ipairs(champs) do
                e:SetFocus()
                e:SetText("7")
                local entree = e:GetScript("OnEnterPressed")
                if entree then entree(e) end
            end
        end
        assertEquals(nil, db[A .. "#771+"] or db[C .. "#990+"], "pas de contre-proposition")
        assertEquals("brouillon", db[cles[1]].status, "le brouillon n'est pas parti")
        assertEquals(100, db[cles[1]].o[1].unit, "ni modifié")
        assertEquals("a_signer", db[cles[4]].status, "la proposition n'est ni signée ni refusée")
    end)
end)

test("Contrats : le contrat affiché disparu sans version en cours (brouillon abandonné, effacé), la tête de liste s'affiche", function()
    sur(function()
        local db = HandshakeDB.contracts
        db[cles[4]] = contrat(C, "990", "a_signer", "Carla Arrivee", { hash = "00000000000c0990", author = C, artisan = moi, client = C })
        db[cles[1]] = contrat(A, "771", "brouillon", "Aline Affichee")
        db[cles[2]] = contrat(B, "880", "envoye", "Bruno Encours", { hash = "00000000000b0880" })
        local f = ouvrir()
        cliquerEntree(f, "Aline Affichee") -- au milieu : Carla avant, Bruno après
        db[cles[1]] = nil -- son brouillon abandonné
        ouvrir()
        assertEquals("Carla Arrivee", affiche(f), "la tête de liste, pas Bruno qui a glissé à sa place")
    end)
end)

-- La colonne (#72) : nom, icône du premier objet livré, état ; bulle avec tous les objets ; les terminés archivés d'office
-- sauf le dernier, sous « Archivés (n) », replié par défaut ; clic droit « Désarchiver ».
local D = {}
for i = 1, 6 do D[i] = ("Player-1-0000D00%d"):format(i) end
local function colonne(f)
    local t = {}
    for _, b in ipairs(f.entrees) do if b:IsShown() then t[#t + 1] = b end end
    table.sort(t, function(a, b) return a:GetTop() > b:GetTop() end)
    return t
end
local function entreeDe(f, nom)
    for _, b in ipairs(colonne(f)) do if b.c.peer.name == nom then return b end end
end
local function texte(fs) return (fs:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function semer()
    local db, t = HandshakeDB.contracts, GetServerTime()
    db[cles[1]] = contrat(A, "771", "brouillon", "Aline Affichee", { o = { { id = 2841, qty = 2, unit = 100 }, { id = 2770, qty = 5, unit = 10 } } })
    db[cles[2]] = contrat(B, "880", "envoye", "Bruno Encours", { hash = "00000000000b0880" })
    db[cles[4]] = contrat(C, "990", "a_signer", "Carla Arrivee", { hash = "00000000000c0990", author = C, artisan = moi, client = C })
    db[cles[5]] = contrat(D[1], "661", "signe", "Denis Signe", { hash = "00000000000d0661", signed = t - 100 })
    db[cles[6]] = contrat(D[2], "662", "clos", "Emma Close", { hash = "00000000000d0662", ledger = { { t = t - 10 } } })
    db[cles[7]] = contrat(D[3], "663", "refuse", "Fanny Refus", { hash = "00000000000d0663", received = t - 5000 })
    db[cles[8]] = contrat(D[4], "664", "signe", "Gilles Echu", { hash = "00000000000d0664", signed = t - 9000, d = t - 3600 })
    return db
end
local function noms(f) local t = {} for i, b in ipairs(colonne(f)) do t[i] = b.c.peer.name end return table.concat(t, ", ") end

test("Contrats, la colonne : nom, icône du premier objet livré, état en couleur ; la bulle donne tous les objets", function()
    sur(function()
        semer()
        local f = ouvrir()
        local b = entreeDe(f, "Aline Affichee")
        assertEquals("Aline Affichee", b.nom:GetText(), "le nom seul : la version passe sur la fiche")
        assertEquals(C_Item.GetItemIconByID(2841), b.icone:GetTexture(), "l'icône du premier objet livré")
        assertEquals("brouillon", texte(b.etat))
        assertTrue(b.etat:GetText():find("^|c") ~= nil, "l'état en couleur")
        b:GetScript("OnEnter")(b)
        local bulle = {}
        for i = 1, GameTooltip:NumLines() do bulle[#bulle + 1] = _G["GameTooltipTextLeft" .. i]:GetText() end
        GameTooltip:Hide()
        bulle = table.concat(bulle, "\n")
        assertTrue(bulle:find("2 ×", 1, true) and bulle:find("5 ×", 1, true), "les deux objets dans la bulle : " .. bulle)
        cliquerEntree(f, "Aline Affichee")
        assertTrue(f.titre:GetText():find("v1", 1, true) ~= nil, "la version sur la fiche")
    end)
end)

test("Contrats, la colonne : à signer, préparé, en attente, signé, le dernier terminé ; les autres terminés archivés, repliés", function()
    sur(function()
        local db = semer()
        local f = ouvrir()
        assertEquals("Carla Arrivee, Aline Affichee, Bruno Encours, Denis Signe, Emma Close", noms(f), "l'ordre, les archivés repliés")
        assertTrue(db[cles[7]].archive and db[cles[8]].archive, "le refusé et l'échu par le temps : archivés")
        assertTrue(not db[cles[5]].archive and not db[cles[6]].archive, "ni le signé ni le dernier terminé")
        assertEquals("Archivés (2)", f.archives:GetText(), "repliés par défaut, le nombre")
        assertTrue(f.archives:GetTop() <= entreeDe(f, "Emma Close"):GetBottom() + 1, "en bas de la colonne")
        f.archives:Click()
        local vus = colonne(f)
        assertEquals(7, #vus, "dépliés d'un clic")
        local fanny = entreeDe(f, "Fanny Refus")
        assertTrue(fanny:GetTop() <= f.archives:GetBottom() + 1, "sous l'en-tête")
        assertTrue(fanny:GetAlpha() < 1 and entreeDe(f, "Emma Close"):GetAlpha() == 1, "les archivés plus pâles")
        fanny:Click()
        assertTrue(f.titre:GetText():find("Fanny Refus", 1, true) == 1, "un archivé s'affiche et se relit")
        assertTrue(fanny.fond:IsShown(), "surligné")
        f.archives:Click() -- replié de nouveau (le repli tient pour la session)
        assertEquals(5, #colonne(f), "replié d'un clic")
    end)
end)

test("Contrats, la colonne : clic droit « Désarchiver » le remet parmi les autres, et il y reste", function()
    sur(function()
        local db = semer()
        local f = ouvrir()
        f.archives:Click()
        local fanny = entreeDe(f, "Fanny Refus")
        local vrai, racine = MenuUtil.CreateContextMenu, nil
        MenuUtil.CreateContextMenu = function(owner, gen)
            racine = MenuUtil.CreateRootMenuDescription(MenuVariants.GetDefaultContextMenuMixin())
            gen(owner, racine)
            return vrai(owner, gen)
        end
        local ok, err = pcall(fanny.Click, fanny, "RightButton")
        MenuUtil.CreateContextMenu = vrai
        Menu.GetManager():CloseMenus()
        if not ok then error(err, 0) end
        local choix
        for _, d in racine:EnumerateElementDescriptions() do if MenuUtil.GetElementText(d) == "Désarchiver" then choix = d end end
        assertNotNil(choix, "« Désarchiver » au clic droit")
        choix:Pick(MenuInputContext.MouseButton, "LeftButton")
        f.archives:Click() -- replié
        ouvrir()
        assertEquals(nil, db[cles[7]].archive, "plus archivé, même après un nouveau tri")
        assertEquals("Archivés (1)", f.archives:GetText())
        assertTrue(entreeDe(f, "Fanny Refus") and entreeDe(f, "Fanny Refus"):GetAlpha() == 1, "parmi les autres, pas pâle")
    end)
end)

test("Contrats, la colonne : « + Nouvelle commande » reste en haut, hors de la liste qui défile", function()
    sur(function()
        semer()
        local f = ouvrir()
        local nouvelle = bouton(f, "+ Nouvelle commande")
        local sc = f.entrees[1]:GetParent():GetParent()
        assertEquals("ScrollFrame", sc:GetObjectType())
        local p = nouvelle:GetParent()
        while p and p ~= sc do p = p:GetParent() end
        assertNil(p, "« + Nouvelle commande » n'est pas dans ce qui défile")
        assertTrue(nouvelle:GetBottom() >= sc:GetTop() - 1, "au-dessus de la liste")
    end)
end)
