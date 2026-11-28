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
local function ouvrir() SlashCmdList.HANDSHAKECONTRAT() return HandshakeContratsFrame end -- ouvre ou rafraîchit
local function affiche(f)
    for _, nom in ipairs({ "Aline Affichee", "Bruno Encours", "Carla Arrivee" }) do
        if f.body:GetText():find("Contrat avec " .. nom, 1, true) then return nom end
    end
end
local function cliquerEntree(f, nom)
    for _, b in ipairs(f.entrees) do if b:IsShown() and b.c.peer.name == nom then return b:Click() end end
    error("pas d'entrée pour " .. nom)
end
local function nettoyer()
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
    for _, k in ipairs(cles) do HandshakeDB.contracts[k] = nil end
end
local function sur(fn)
    local ok, err = pcall(fn)
    nettoyer()
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
        -- relu (la fenêtre redessinée), le clic part avec ce qui est affiché
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
