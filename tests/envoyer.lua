-- Envoyer (#71) dans le simulateur : un seul bouton. Sans réponse de son Handshake en 3 s, le contrat part en clair ; en
-- bas d'un contrat en attente : Retirer, et « Il a dit oui » seulement s'il est parti en clair, réarmé 2 s comme Signer.
-- Plus de bouton « Envoyer en clair ».
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
local function contrat(g, id, status, nom, champs)
    local c = { origin = moi, id = id, v = "1", parent = "0", client = moi, artisan = g, m = {},
        o = { { id = 2841, qty = 1, unit = 100 } }, d = GetServerTime() + 86400, status = status, author = moi,
        peer = { guid = g, name = nom } }
    for k, v in pairs(champs or {}) do c[k] = v end
    return c
end
local function afficher(nom)
    SlashCmdList.HANDSHAKECONTRAT()
    for _, b in ipairs(HandshakeContratsFrame.entrees) do if b:IsShown() and b.c.peer.name == nom then return b:Click() end end
    error("pas d'entrée pour " .. nom)
end
test("Envoyer : parti par Handshake, en bas Retirer seulement ; plus de bouton « Envoyer en clair »", function()
    local g, k = "Player-1-0000E001", moi .. "#7101"
    HandshakeDB.contracts[k] = contrat(g, "7101", "envoye", "Hugo Handshake", { hash = "0000000000007101" })
    local ok, err = pcall(function()
        afficher("Hugo Handshake")
        local f = HandshakeContratsFrame
        assertNotNil(bouton(f, "Retirer"))
        assertNil(bouton(f, "Il a dit oui"), "parti par Handshake : sa signature compte")
        assertNil(bouton(f, "Envoyer en clair"))
        assertNil(bouton(f, "Il a dit oui (sans addon)"))
    end)
    HandshakeContratsFrame:Hide()
    HandshakeDB.contracts[k] = nil
    if not ok then error(err, 0) end
end)

-- Le temps est simulé : les minuteurs de 3 s (la réponse attendue) sont captés et lancés à la main, GetTime avancé de 2 s
-- pour le réarmement.
test("Envoyer : sans réponse en 3 s, parti en clair ; « Il a dit oui » réarmé 2 s, puis signé", function()
    local g, k = "Player-1-0000E002", moi .. "#7102"
    local c = contrat(g, "7102", "brouillon", "Sam Sansaddon")
    HandshakeDB.contracts[k] = c
    local T0, G0, minuteurs, decalage = C_Timer.After, GetTime, {}, 0
    C_Timer.After = function(s, fn) if s == 3 then minuteurs[#minuteurs + 1] = fn else return T0(s, fn) end end
    GetTime = function() return G0() + decalage end
    local ok, err = pcall(function()
        afficher("Sam Sansaddon")
        local f = HandshakeContratsFrame
        assertNil(bouton(f, "Envoyer en clair"), "plus de bouton « Envoyer en clair »")
        local envoyer = bouton(f, "Envoyer la proposition")
        envoyer:Click()
        assertEquals("brouillon", c.status, "la question est partie : on attend sa réponse")
        assertTrue(not envoyer:IsEnabled(), "pendant l'attente, pas de second envoi")
        assertEquals(1, #minuteurs, "une attente de 3 s")
        minuteurs[1]() -- 3 s, pas de réponse
        assertEquals("envoye", c.status, "pas de réponse : parti")
        assertTrue(c.enClair, "marqué en clair")
        afficher("Sam Sansaddon")
        assertNotNil(bouton(f, "Retirer"))
        local oui = bouton(f, "Il a dit oui")
        assertNotNil(oui, "parti en clair : « Il a dit oui »")
        assertTrue(not oui:IsEnabled(), "réarmé : pas tout de suite")
        decalage = 2.1
        afficher("Sam Sansaddon")
        assertTrue(oui:IsEnabled(), "2 s après : actif")
        oui:Click()
        assertEquals("signe", c.status)
        assertTrue(c.manual, "noté à la main")
    end)
    C_Timer.After, GetTime = T0, G0
    HandshakeContratsFrame:Hide()
    HandshakeDB.contracts[k] = nil
    if not ok then error(err, 0) end
end)
