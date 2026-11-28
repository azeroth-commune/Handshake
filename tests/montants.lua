-- Montants sur la fiche (#74) : caution (seulement avec des apports), livraison et délai sont des champs de la fiche d'un
-- contrat préparé ou à signer, du texte ailleurs. Préparé : « Envoyer » part avec ce qu'ils montrent. À signer : rien de
-- touché, « Signer · Refuser · Répondre » ; un champ changé, « Contre-proposer · Annuler » (on ne signe jamais autre chose
-- que ce qui est affiché). Au plus trois boutons en bas, aucun pour un signé.
local moi = UnitGUID("player")
local BOB, BOBN = "Player-1-0000B074", "Bob Montant"
local CLE = BOB .. "#7401"
local function tous(f, ok, out)
    out = out or {}
    for _, c in ipairs({ f:GetChildren() }) do
        if ok(c) then out[#out + 1] = c end
        tous(c, ok, out)
    end
    return out
end
local function bas(f) -- les boutons d'action visibles, de gauche à droite
    local t = {}
    for _, b in ipairs(f.actions) do if b:IsShown() then t[#t + 1] = b end end
    table.sort(t, function(a, b) return a:GetLeft() < b:GetLeft() end)
    local noms = {}
    for i, b in ipairs(t) do noms[i] = b:GetText() end
    return table.concat(noms, " · "), t
end
local function bouton(f, texte) for _, b in ipairs(f.actions) do if b:IsShown() and b:GetText() == texte then return b end end end
local function champsVus(f) return tous(f, function(c) return c:GetObjectType() == "EditBox" and c:IsVisible() end) end
-- Bob (client) me demande une claymore et fournit 4 cuivres : je suis l'artisan, la proposition est à signer.
local function recu(champs)
    local c = { origin = BOB, id = "7401", v = "1", parent = "0", client = BOB, artisan = moi, author = BOB,
        m = { { id = 2770, qty = 4, unit = 100 } }, o = { { id = 2841, qty = 1, unit = 20000 } }, d = GetServerTime() + 3 * 86400,
        status = "a_signer", hash = "00000000000b7401", peer = { guid = BOB, name = BOBN } }
    for k, v in pairs(champs or {}) do c[k] = v end
    return c
end
-- Chaque test sur une base à lui ; les lignes du chat captées ; GetTime avancé à la main pour le réarmement de 2 s.
local decalage, cleSur = 0, nil
local function sur(c, fn)
    local avant, P, G0 = HandshakeDB.contracts, print, GetTime
    local dits = {}
    HandshakeDB.contracts = { [cleSur or CLE] = c }
    print = function(s) dits[#dits + 1] = tostring(s) end
    GetTime = function() return G0() + decalage end
    decalage = 0
    if HandshakeContratsFrame then HandshakeContratsFrame.champs.pour = nil end -- même clé et empreinte d'un test à l'autre : remplis de nouveau
    local ok, err = pcall(function() SlashCmdList.HANDSHAKECONTRAT(); fn(HandshakeContratsFrame, dits) end)
    print, GetTime = P, G0
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
    HandshakeDB.contracts = avant
    if not ok then error(err, 0) end
end
-- Le simulateur ne lance pas OnTextChanged sur SetText (le jeu, si) : lancé à la main, comme une frappe.
local function taper(e, texte) e:SetFocus(); e:SetText(texte); e:GetScript("OnTextChanged")(e, true); e:ClearFocus() end
local function present() FireEvent("CHAT_MSG_ADDON", "Handshake", "1/1|H|3|" .. BOB, "WHISPER", BOBN) end -- son Handshake répond (#71)

test("Montants : à signer, des champs dans la fiche (caution avec les apports) ; rien de touché, Signer · Refuser · Répondre", function()
    sur(recu(), function(f)
        local ch = f.champs
        assertTrue(ch.caution:IsVisible() and ch.livraison:IsVisible() and ch.delai:IsVisible(), "trois champs")
        assertEquals("0.04", ch.caution:GetText())
        assertEquals("2", ch.livraison:GetText())
        assertTrue(ch.delai:GetText() == "3" or ch.delai:GetText() == "2.9", ch.delai:GetText())
        assertTrue(math.abs(ch.delai:GetTop() - f.echeance:GetTop()) < 8 and ch.delai:GetRight() < f.echeance:GetLeft(), "le délai dans l'en-tête, avant l'échéance")
        assertTrue(ch.caution:GetTop() > ch.livraison:GetTop(), "la caution dans l'étape 1, la livraison dans l'étape 2")
        assertEquals("Signer · Refuser · Répondre", (bas(f)))
    end)
    sur(recu({ m = {} }), function(f)
        assertFalse(f.champs.caution:IsVisible(), "sans apports, pas de caution à saisir")
        assertTrue(f.champs.livraison:IsVisible())
    end)
end)

test("Montants : un champ changé, Contre-proposer · Annuler ; Annuler remet le reçu et Signer, réarmé 2 s", function()
    sur(recu(), function(f)
        decalage = 5
        f.champs.livraison:GetScript("OnTextChanged")(f.champs.livraison, true)
        assertTrue(bouton(f, "Signer"):IsEnabled(), "affiché depuis 5 s : armé")
        taper(f.champs.livraison, "3")
        assertEquals("Contre-proposer · Annuler", (bas(f)), "Signer caché dès qu'un montant diffère")
        f.accept:Click()
        assertEquals("a_signer", HandshakeDB.contracts[CLE].status, "un montant changé : rien n'est signé, même par le bouton caché")
        taper(f.champs.livraison, "2.0")
        assertEquals("Signer · Refuser · Répondre", (bas(f)), "la même valeur : rien de changé")
        taper(f.champs.delai, "x")
        assertEquals("Contre-proposer · Annuler", (bas(f)), "illisible : on ne signe pas non plus")
        bouton(f, "Annuler"):Click()
        assertEquals("2", f.champs.livraison:GetText())
        assertTrue(f.champs.delai:GetText() == "3" or f.champs.delai:GetText() == "2.9", "le délai reçu revient")
        assertEquals("Signer · Refuser · Répondre", (bas(f)))
        assertFalse(bouton(f, "Signer"):IsEnabled(), "Signer réarmé : pas tout de suite")
        assertFalse(bouton(f, "Refuser"):IsEnabled(), "Refuser non plus (il prend la place d'Annuler)")
        decalage = 7.1
        SlashCmdList.HANDSHAKECONTRAT()
        assertTrue(bouton(f, "Signer"):IsEnabled(), "2 s après : armé")
    end)
end)

test("Montants : Contre-proposer envoie la v2 avec les montants affichés, du même clic, sans brouillon", function()
    local c = recu()
    sur(c, function(f, dits)
        present()
        taper(f.champs.livraison, "2.5")
        taper(f.champs.caution, "0.08")
        bouton(f, "Contre-proposer"):Click()
        local v2 = HandshakeDB.contracts[CLE]
        assertTrue(v2 ~= c and v2.v == "2" and v2.status == "envoye" and v2.author == moi, "la v2 est partie")
        assertEquals(25000, v2.o[1].qty * v2.o[1].unit, "la livraison affichée")
        assertEquals(800, v2.m[1].qty * v2.m[1].unit, "la caution affichée")
        assertEquals(c.d, v2.d, "le délai pas touché : l'échéance reste")
        assertNil(HandshakeDB.contracts[CLE .. "+"], "pas de brouillon")
        assertEquals("Retirer", (bas(f)), "en attente de sa réponse")
        assertEquals(0, #champsVus(f), "les montants en texte")
        -- #82 : Retirer prend la place de Contre-proposer ; réarmé 2 s, un double clic ne retire pas la v2 tout juste partie.
        assertFalse(bouton(f, "Retirer"):IsEnabled(), "Retirer désarmé juste après l'envoi")
        decalage = 2.1
        SlashCmdList.HANDSHAKECONTRAT()
        assertTrue(bouton(f, "Retirer"):IsEnabled(), "2 s après : armé")
    end)
end)

-- #82 : pendant l'attente de la réponse de présence (≤ 3 s), « En route… » sur le bouton, grisé ; champs et Annuler figés.
-- Un autre joueur (pas encore connu présent pour la session).
test("Montants : Contre-proposer en attente de sa réponse, « En route… », champs et Annuler figés", function()
    local ALI, ALIN = "Player-1-0000A082", "Ali Attente"
    local c = recu({ origin = ALI, client = ALI, author = ALI, peer = { guid = ALI, name = ALIN } })
    cleSur = ALI .. "#7401"
    local ok, err = pcall(sur, c, function(f)
        taper(f.champs.livraison, "2.5")
        bouton(f, "Contre-proposer"):Click()
        assertTrue(HandshakeDB.contracts[cleSur] == c and c.status == "a_signer", "rien n'est encore parti")
        assertEquals("En route… · Annuler", (bas(f)))
        assertFalse(bouton(f, "En route…"):IsEnabled(), "En route… grisé")
        assertFalse(bouton(f, "Annuler"):IsEnabled(), "Annuler figé")
        assertFalse(f.champs.livraison:IsEnabled() or f.champs.caution:IsEnabled() or f.champs.delai:IsEnabled(), "champs figés")
        assertEquals("2.5", f.champs.livraison:GetText(), "la saisie reste")
        -- Un autre contrat affiché puis celui-ci de nouveau : toujours en route, jamais Signer (relecture #82).
        local AUTRE = "Player-1-0000A083"
        HandshakeDB.contracts[AUTRE .. "#1"] = recu({ origin = AUTRE, id = "1", client = AUTRE, author = AUTRE, hash = "00000000000a0831",
            peer = { guid = AUTRE, name = "Autre Contrat" } })
        SlashCmdList.HANDSHAKECONTRAT()
        local function afficher(x) for _, b in ipairs(f.entrees) do if b:IsShown() and b.c == x then b:GetScript("OnClick")(b, "LeftButton") return end end error("entrée absente") end
        afficher(HandshakeDB.contracts[AUTRE .. "#1"])
        assertEquals("Signer · Refuser · Répondre", (bas(f)), "l'autre contrat")
        decalage = 5
        afficher(c)
        assertEquals("En route… · Annuler", (bas(f)), "revenu : toujours en route")
        assertFalse(bouton(f, "En route…"):IsEnabled() or bouton(f, "Annuler"):IsEnabled(), "En route… et Annuler grisés")
        assertEquals("2.5", f.champs.livraison:GetText(), "les champs montrent la contre-proposition en route")
        assertFalse(f.champs.livraison:IsEnabled(), "champs figés")
        HandshakeDB.contracts[AUTRE .. "#1"] = nil
        FireEvent("CHAT_MSG_ADDON", "Handshake", "1/1|H|3|" .. ALI, "WHISPER", ALIN) -- son Handshake répond
        local v2 = HandshakeDB.contracts[cleSur]
        assertTrue(v2 ~= c and v2.v == "2" and v2.status == "envoye", "la v2 est partie à sa réponse")
        assertEquals(25000, v2.o[1].qty * v2.o[1].unit, "avec la livraison affichée")
        assertEquals("Retirer", (bas(f)))
        assertTrue(f.champs.livraison:IsEnabled(), "les champs ne restent pas figés")
    end)
    cleSur = nil
    if not ok then error(err, 0) end
end)

-- #82 : pendant la saisie, la fiche montre ce qui partirait (caution rendue + prix, estimation), sans perdre le champ ; le
-- total réparti par objet peut différer du total tapé (moins d'un cuivre par objet) : la fiche le dit.
test("Montants : la fiche suit la saisie ; le total qui part, arrondi par objet, est dit", function()
    local function texteDe(f, motif)
        for _, b in ipairs(f.cellules) do if b:IsShown() and (b.texte:GetText() or ""):find(motif, 1, true) then return b.texte:GetText() end end
    end
    local pieces = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    sur(recu({ o = { { id = 2841, qty = 3, unit = 20000 } } }), function(f)
        local avant, est = texteDe(f, "caution rendue"), f.estimation:GetText()
        assertNotNil(avant, "la ligne caution rendue + prix")
        local e = f.champs.livraison
        e:SetFocus(); e:SetText("10"); e:GetScript("OnTextChanged")(e, true)
        assertTrue(e:IsVisible() and e:HasFocus(), "le champ garde le focus pendant que la fiche se redessine")
        e:ClearFocus()
        assertTrue(texteDe(f, "caution rendue") ~= avant, "caution rendue + prix suit la saisie : " .. tostring(texteDe(f, "caution rendue")))
        assertTrue(f.estimation:GetText() ~= est or not est:find("objets livrés", 1, true), "l'estimation suit la saisie")
        local unite = texteDe(f, "arrondi par objet")
        assertNotNil(unite, "10 po pour 3 objets : 33333 pc l'objet, le total qui part est dit")
        assertTrue(unite:find("envoyé : " .. pieces(99999), 1, true) ~= nil, "au cuivre près, pas arrondi à 10 po : " .. unite)
        assertTrue(texteDe(f, "caution rendue"):find(pieces(99599), 1, true) ~= nil, "le prix au cuivre près : " .. texteDe(f, "caution rendue"))
        present()
        bouton(f, "Contre-proposer"):Click()
        local v2 = HandshakeDB.contracts[CLE]
        assertEquals(99999, v2.o[1].qty * v2.o[1].unit, "le total dit est celui qui part")
    end)
    sur(recu(), function(f)
        taper(f.champs.livraison, "3")
        assertNil(texteDe(f, "arrondi par objet"), "un objet : le total tapé part tel quel, rien à dire")
    end)
end)

test("Montants : illisible, négatif ou délai hors 0-30 jours, refusé d'une ligne, rien ne part, la saisie reste", function()
    local c = recu()
    sur(c, function(f, dits)
        present()
        for _, cas in ipairs({ { f.champs.livraison, "deux" }, { f.champs.caution, "-1" }, { f.champs.delai, "31" }, { f.champs.delai, "0" } }) do
            if bouton(f, "Annuler") then bouton(f, "Annuler"):Click() end
            taper(cas[1], cas[2])
            local n = #dits
            bouton(f, "Contre-proposer"):Click()
            assertTrue(HandshakeDB.contracts[CLE] == c and c.status == "a_signer", cas[2] .. " : rien n'est parti")
            assertEquals(n + 1, #dits, cas[2] .. " : une ligne")
            assertTrue(dits[#dits]:find("rien n'est parti", 1, true) ~= nil, dits[#dits])
            assertEquals(cas[2], cas[1]:GetText(), "la saisie reste")
        end
    end)
end)

test("Montants : une nouvelle version reçue pendant la saisie, saisies jetées, Signer désarmé 2 s, une ligne le dit", function()
    sur(recu(), function(f, dits)
        decalage = 5
        SlashCmdList.HANDSHAKECONTRAT()
        taper(f.champs.livraison, "9")
        assertEquals("Contre-proposer · Annuler", (bas(f)))
        local d = GetServerTime() + 2 * 86400
        FireEvent("CHAT_MSG_ADDON", "Handshake", ("1/1|P|3|%s|%s|7401|2|00000000000b7401|%s|%s|2770:4:100|2841:1:30000|%d"):format(BOB, BOB, BOB, moi, d),
            "WHISPER", BOBN)
        local v2 = HandshakeDB.contracts[CLE]
        assertEquals("2", v2.v, "sa v2 est arrivée")
        assertTrue(f.titre:GetText():find("v2", 1, true) ~= nil, "la fiche passe à la v2")
        assertEquals("3", f.champs.livraison:GetText(), "la saisie jetée : la livraison de la v2")
        assertEquals("Signer · Refuser · Répondre", (bas(f)))
        assertFalse(bouton(f, "Signer"):IsEnabled(), "Signer désarmé")
        local vu
        for _, s in ipairs(dits) do if s:find(BOBN .. " a envoyé une v2 : tes modifications sont annulées", 1, true) then vu = true end end
        assertTrue(vu, "la ligne du chat : " .. table.concat(dits, " / "))
        decalage = 7.1
        SlashCmdList.HANDSHAKECONTRAT()
        assertTrue(bouton(f, "Signer"):IsEnabled(), "2 s après : armé")
    end)
end)

test("Montants : préparé, Envoyer part avec les montants affichés", function()
    local c = { origin = moi, id = "7402", v = "1", parent = "0", client = moi, artisan = BOB, m = { { id = 2770, qty = 4, unit = 100 } },
        o = { { id = 2841, qty = 1, unit = 20000 } }, d = GetServerTime() + 3 * 86400, status = "brouillon", peer = { guid = BOB, name = BOBN } }
    cleSur = moi .. "#7402"
    local ok, err = pcall(sur, c, function(f)
        assertEquals("Envoyer", (bas(f)))
        assertEquals(3, #champsVus(f), "caution, livraison, délai")
        present()
        taper(f.champs.livraison, "4")
        taper(f.champs.delai, "5")
        bouton(f, "Envoyer"):Click()
        assertEquals("envoye", c.status, "parti")
        assertEquals(40000, c.o[1].unit, "avec la livraison affichée")
        assertEquals(100, c.m[1].unit, "la caution pas touchée")
        assertTrue(math.abs(c.d - (GetServerTime() + 5 * 86400)) < 5, "le délai affiché")
    end)
    cleSur = moi .. "#7402"
    c.status, c.hash, c.author, c.enClair = "brouillon", nil, nil, nil
    if ok then ok, err = pcall(sur, c, function(f, dits)
        present()
        for _, cas in ipairs({ { f.champs.livraison, "-1" }, { f.champs.delai, "31" }, { f.champs.livraison, "300000" } }) do
            local n = #dits
            taper(cas[1], cas[2])
            bouton(f, "Envoyer"):Click()
            assertEquals("brouillon", c.status, cas[2] .. " : rien n'est parti")
            assertTrue(c.o[1].unit == 40000 and math.abs(c.d - (GetServerTime() + 5 * 86400)) < 5, cas[2] .. " : rien n'est rangé")
            assertEquals(n + 1, #dits, cas[2] .. " : une ligne")
            assertEquals(cas[2], cas[1]:GetText(), cas[2] .. " : la saisie reste")
            taper(f.champs.livraison, "4"); taper(f.champs.delai, "5")
        end
    end) end
    cleSur = nil
    if not ok then error(err, 0) end
end)

test("Montants : signé, aucun bouton et les montants en texte ; au plus trois boutons par état", function()
    sur(recu({ status = "signe", signed = GetServerTime() }), function(f)
        assertEquals("", (bas(f)), "signé : aucun bouton")
        assertEquals(0, #champsVus(f), "les montants en texte")
        local texte = {}
        for _, b in ipairs(f.cellules) do if b:IsShown() then texte[#texte + 1] = b.texte:GetText() end end
        assertTrue(table.concat(texte, " "):find("de caution", 1, true) ~= nil, "la caution se lit")
    end)
    for _, s in ipairs({ "a_signer", "envoye", "refuse", "retire", "clos" }) do
        sur(recu({ status = s, enClair = s == "envoye" or nil }), function(f)
            local _, t = bas(f)
            assertTrue(#t <= 3, s .. " : " .. #t .. " boutons")
            if s ~= "a_signer" then assertEquals(0, #champsVus(f), s .. " : pas de champ") end
        end)
    end
end)

-- Relecture #82 : le différentiel n° 4 (« Changé depuis la v1 ») se calcule sur la version reçue, jamais sur ma saisie.
test("Montants : pendant la saisie, « Changé depuis » montre toujours le changement de l'autre", function()
    local pieces = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    local d = GetServerTime() + 3 * 86400
    local c = recu({ v = "2", parent = "00000000000b7400", d = d, o = { { id = 2841, qty = 1, unit = 600000 } },
        prev = { v = "1", m = { { id = 2770, qty = 4, unit = 100 } }, o = { { id = 2841, qty = 1, unit = 450000 } }, d = d } })
    sur(c, function(f)
        local attendu = ("livraison %s -> %s"):format(pieces(450000), pieces(600000))
        assertTrue(f.alertes:GetText():find(attendu, 1, true) ~= nil, "avant la saisie : " .. f.alertes:GetText())
        taper(f.champs.livraison, "10")
        assertTrue(f.alertes:GetText():find(attendu, 1, true) ~= nil, "pendant la saisie, le changement de Bob : " .. f.alertes:GetText())
        assertTrue(f.alertes:GetText():find(pieces(100000), 1, true) == nil, "ma saisie n'entre pas dans le différentiel")
    end)
end)
