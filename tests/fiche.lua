-- La fiche du contrat lisible (#73) : l'en-tête et la bulle du nom, les alertes seulement quand elles s'appliquent, deux
-- colonnes par étape (la mienne à gauche), les objets comme ceux du jeu, l'avancement à côté des quantités une fois signé.
local moi = UnitGUID("player")
local CARLA = "Player-1-0000CA73"
local function contrat(champs)
    local c = { origin = CARLA, id = "7301", v = "2", parent = "00000000000c7300", client = moi, artisan = CARLA, author = CARLA,
        m = { { id = 2770, qty = 20, unit = 30 }, { id = 2771, qty = 10, unit = 70 } }, o = { { id = 2841, qty = 10, unit = 3000 } },
        d = GetServerTime() + 3 * 86400, status = "a_signer", hash = "00000000000c7301",
        peer = { guid = CARLA, name = "Carla Fiche" },
        prev = { v = "1", m = { { id = 2770, qty = 20, unit = 30 }, { id = 2771, qty = 10, unit = 70 } },
            o = { { id = 2841, qty = 10, unit = 2500 } }, d = GetServerTime() + 3 * 86400 } }
    for k, v in pairs(champs or {}) do c[k] = v end
    return c
end
local function sur(c, fn, autres) -- autres : d'autres contrats dans la base (clé -> contrat)
    local avant = HandshakeDB.contracts
    HandshakeDB.contracts = { [CARLA .. "#7301"] = c }
    for k, x in pairs(autres or {}) do HandshakeDB.contracts[k] = x end
    local ok, err = pcall(function() SlashCmdList.HANDSHAKECONTRAT(); fn(HandshakeContratsFrame) end)
    GameTooltip:Hide()
    if HandshakeContratsFrame then HandshakeContratsFrame:Hide() end
    HandshakeDB.contracts = avant
    if not ok then error(err, 0) end
end
local function bulle(r)
    r:GetScript("OnEnter")(r)
    local t = {}
    for i = 1, GameTooltip:NumLines() do t[#t + 1] = _G["GameTooltipTextLeft" .. i]:GetText() or "" end
    GameTooltip:Hide()
    return table.concat(t, "\n")
end
local function cellules(f)
    local t = {}
    for _, b in ipairs(f.cellules) do if b:IsShown() then t[#t + 1] = b end end
    return t
end
local function objet(f, id) for _, b in ipairs(cellules(f)) do if b.l.id == id then return b end end end

test("Fiche : l'en-tête (avec qui, version, état, rôle, échéance) ; GUID, empreinte et identité dans la bulle du nom", function()
    sur(contrat(), function(f)
        assertTrue(f.titre:GetText():find("Carla Fiche · v2 · ", 1, true) == 1 and f.titre:GetText():find("À SIGNER PAR TOI", 1, true) ~= nil, f.titre:GetText())
        assertTrue(f.echeance:GetText():find("échéance dans 2 j", 1, true) ~= nil or f.echeance:GetText():find("échéance dans 3 j", 1, true) ~= nil, f.echeance:GetText())
        assertTrue(f.echeance:GetRight() > f.titre:GetFontString():GetLeft() + 200, "l'échéance à droite")
        assertEquals("Tu es le client.", f.role:GetText())
        local b = bulle(f.titre)
        assertTrue(b:find(CARLA, 1, true) and b:find("empreinte 00000000", 1, true) and b:find("vérifié au premier échange", 1, true)
            and b:find("Toi : ", 1, true), "la bulle du nom : " .. b)
    end)
end)

test("Fiche : les alertes en haut seulement quand elles s'appliquent", function()
    sur(contrat(), function(f)
        assertTrue(f.alertes:IsShown(), "des alertes")
        local a = f.alertes:GetText()
        assertTrue(a:find("Changé depuis la v1", 1, true) and a:find("Identité de Carla pas encore vérifiée", 1, true), a)
        assertTrue(f.alertes:GetTop() > f.etapes[1][1]:GetTop(), "au-dessus des étapes")
    end)
    local propre = contrat({ prev = false, peer = { guid = CARLA, name = "Carla Fiche", verified = true }, m = {} })
    sur(propre, function(f) assertFalse(f.alertes:IsShown(), "rien à signaler : pas de ligne d'alerte") end)
end)

test("Fiche : deux colonnes par étape, la mienne à gauche ; une vente simple en une étape", function()
    sur(contrat(), function(f)
        local e1, e2 = f.etapes[1], f.etapes[2]
        assertEquals("1. Composants", e1[1]:GetText())
        assertEquals("Tu donnes", e1[2]:GetText())
        assertEquals("Carla donne", e1[3]:GetText())
        assertEquals("Tu paies", e2[2]:GetText())
        assertEquals("Carla livre", e2[3]:GetText())
        assertTrue(e1[2]:GetLeft() < e1[3]:GetLeft() - 100, "deux colonnes")
        local cuivre, bronze = objet(f, 2770), objet(f, 2841)
        assertTrue(math.abs(cuivre:GetLeft() - e1[2]:GetLeft()) < 2, "mes composants sous « Tu donnes »")
        assertTrue(math.abs(bronze:GetLeft() - e2[3]:GetLeft()) < 2, "le bronze sous « Carla livre »")
        assertTrue(cuivre:GetTop() < e1[2]:GetTop() and cuivre:GetTop() > e2[2]:GetTop(), "dans l'étape 1")
        assertTrue(f.estimation:GetText():find("Ton estimation", 1, true) ~= nil and f.estimation:GetTop() < bronze:GetBottom(), "l'estimation en bas")
    end)
    sur(contrat({ m = {}, prev = false }), function(f)
        assertEquals("Livraison", f.etapes[1][1]:GetText())
        assertFalse(f.etapes[2][1]:IsShown(), "une seule étape")
        assertTrue(f.apres:GetText():find("Vente simple", 1, true) ~= nil, "sans caution")
    end)
end)

test("Fiche : un objet a son icône, la bulle du jeu, et les clics du jeu (Maj+clic, Ctrl+clic)", function()
    sur(contrat(), function(f)
        local b = objet(f, 2841)
        assertNotNil(b, "le bronze livré")
        assertTrue(b.icone:IsShown(), "son icône")
        assertEquals(C_Item.GetItemIconByID(2841), b.icone:GetTexture())
        assertTrue(b.texte:GetText():find("^10 ") ~= nil, "la quantité : " .. b.texte:GetText())
        local texte = bulle(b)
        assertTrue(texte:find("10 au contrat", 1, true) and texte:find("l'objet", 1, true), "la bulle, puis le prix au contrat : " .. texte)
        local vu
        local avant = HandleModifiedItemClick
        HandleModifiedItemClick = function(lien) vu = lien end
        local ok, err = pcall(function() b:Click() end)
        HandleModifiedItemClick = avant
        if not ok then error(err, 0) end
        assertTrue(vu and vu:find("|Hitem:2841", 1, true) ~= nil, "HandleModifiedItemClick avec le lien de l'objet : " .. tostring(vu))
    end)
end)

test("Fiche : signé, l'avancement à côté de chaque quantité", function()
    local c = contrat({ status = "signe", signed = GetServerTime() - 60, prev = false, gave = { [2770] = 20, [2771] = 3 },
        got = { [2841] = 5 }, ledger = { { t = GetServerTime() - 30 } }, net = 0 })
    sur(c, function(f)
        assertTrue(objet(f, 2770).texte:GetText():find("donné 20/20", 1, true) ~= nil, objet(f, 2770).texte:GetText())
        assertTrue(objet(f, 2771).texte:GetText():find("donné 3/10", 1, true) ~= nil, objet(f, 2771).texte:GetText())
        assertTrue(objet(f, 2841).texte:GetText():find("reçu 5/10", 1, true) ~= nil, objet(f, 2841).texte:GetText())
        assertTrue(f.apres:GetText():find("Solde des échanges", 1, true) ~= nil, "le solde")
    end)
end)

-- n° 26 (#80) : un nom qui ne diffère d'un autre partenaire que par les accents déclenche l'alerte ; l'accent est ramené
-- à sa lettre de base (l'exemple de SECURITE.md : Bélegard / Belegard), un nom sans accent n'y change rien.
test("Fiche : nom très proche, les accents ramenés à la lettre de base (Bélegard / Belegard)", function()
    local function alertes(nom, autre)
        local texte
        sur(contrat({ peer = { guid = CARLA, name = nom } }), function(f) texte = f.alertes:GetText() or "" end,
            { ["Player-1-0000BE26#1"] = contrat({ origin = "Player-1-0000BE26", id = "1", peer = { guid = "Player-1-0000BE26", name = autre } }) })
        return texte
    end
    assertTrue(alertes("Bélegard Marteaudefer", "Belegard Marteaudefer"):find("Nom très proche de Belegard Marteaudefer", 1, true) ~= nil, "Bélegard / Belegard")
    assertTrue(alertes("Belegard Marteaudefer", "Bélegard Marteaudefer"):find("Nom très proche de Bélegard Marteaudefer", 1, true) ~= nil, "Belegard / Bélegard")
    assertTrue(alertes("Élise Forge", "Elise Forge"):find("Nom très proche", 1, true) ~= nil, "majuscule accentuée : Élise / Elise")
    assertTrue(alertes("Belegard Marteaudefer", "Bolegard Marteaudefer"):find("Nom très proche", 1, true) == nil, "sans accent, un autre nom : pas d'alerte")
end)
