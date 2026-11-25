-- Handshake dans Composants : l'emplacement du bloc (CONTEXT.md, Emplacements ; Composants.Emplacements, README de
-- Composants). Composants ne sait rien des contrats : il demande ici quels blocs sont confiés et laisse dessiner dans ses
-- zones ; tout ce qui touche à un contrat (le commander, l'artisan, l'offre, les apports, l'envoyer) est dessiné et fait ici.
-- - Un bloc libre : « Commander » sur sa ligne de titre ; un clic crée tout de suite son contrat préparé (Commande.lua) et
--   ouvre son panneau.
-- - Un bloc commandé : réduit à une seule case, « Contrat n°12 · Forge » et « artisan · état » ; clic = son panneau.
-- - Le projet entier (sa ligne d'en-tête) : « Commander tout » (une liste sans arbre se commande ainsi), ou dans une
--   Réponse « Réponse à Bob · mon prix · travail » ; commandé en entier, tout l'arbre est une seule case.
-- - Le panneau (une petite fenêtre de Handshake, à côté de la case) : ce qui est livré et apporté, l'artisan, l'offre, le
--   menu des apports, un bouton d'action (Vérifier et envoyer…, Nouvelle version, Contre-proposer, Voir dans Contrats) et
--   « Plus » (Voir dans Contrats, Envoyer en clair, Annoncer dans le Commerce, Abandonner). Rien n'y part sur le fil :
--   « Vérifier et envoyer… » prépare le brouillon de la v1 et l'ouvre sur sa fiche dans Contrats (caution, perte maximale,
--   objets sans prix, échéance, objets liés, nom et GUID : SECURITE.md, P8, n° 11, 13, 26, 57), d'où « Envoyer la
--   proposition » le fait partir ; envoyer la v1 vaut signature dès que l'artisan accepte.
-- - Hors Préparer (Réunir, Fabriquer, Fini : p.phase, l'arbre en lecture seule), seulement la case et son état : ni
--   Commander, ni Commander tout, et le panneau en lecture (son état, « Voir dans Contrats »).
-- - Dans les Besoins (l'emplacement des Besoins, Composants#27) : une ligne par contrat vivant du projet, « Contrat n°12 ·
--   à recevoir », verte « reçu » quand il est livré, son état, « Abandonner » (même hors Préparer : la
--   lecture seule ne vaut que pour l'emplacement du bloc) ; clic = son panneau. Le projet ne passe en
--   Fabriquer (puis Fini) que ses contrats livrés ; mes apports sont des lignes des Besoins comme les autres.
local _, ns = ...

local W8 = "Interface\\Buttons\\WHITE8x8"
local function liste(p)
  local r = HandshakeDB.commandes and HandshakeDB.commandes[p.id]
  return r and r.liste or {}
end
local function rangDe(p, id)
  for i, c in ipairs(liste(p)) do if c.id == id then return i end end
end
local function dire(err) if err then print("|cffe64d4dContrats :|r " .. err .. ".") end end
-- Tout ce qui montre un contrat : Composants (ses cases, ce panneau) et Contrats (ns.refreshContracts redessine les deux).
-- ponytail: à chaque touche tapée dans l'artisan ou l'offre (l'arbre recalculé, quelques ms) ; à la perte du focus si ça rame
local function redessiner() ns.refreshContracts() end

-- L'état en couleur : préparé (gris), parti (orange), signé ou livré (vert), fini sans accord (rouge).
local COULEUR = { ["préparé"] = "999999", ["envoyé"] = "e6994d", ["contre-proposé"] = "a98fff", ["signé"] = "59cc73",
  ["livré"] = "59cc73", ["échu"] = "e64d4d", ["refusé"] = "e64d4d", ["retiré"] = "e64d4d" }
local function etatEnCouleur(v)
  if not v.etat then return "" end
  return ("|cff%s%s|r"):format(COULEUR[v.etat] or "ffffff", v.etat)
end
local function poTexte(c) return c and c > 0 and (("%.2f"):format(c / 10000):gsub("%.?0+$", "")) or "" end
-- Hors Préparer (p.phase de Composants : nil = Préparer), l'emplacement est en lecture seule.
local function enLecture(p) return p.phase ~= nil and p.phase ~= "preparer" end
-- La clé du contrat à voir dans Contrats (la Réponse, ou le contrat de ce contrat préparé, brouillon compris), nil sinon.
local function aVoir(v) return v.reponse or (v.contrat and ns.ctStore()[v.contrat] and v.contrat) end

-- « Abandonner » le contrat i (ns.abandonner, Commande.lua : selon son état, effacé, retiré, refusé ou lâché) ; ce qui a
-- été fait est dit dans le chat. Rend true si le bloc est revenu.
local DIT = {
  efface = "contrat n°%d abandonné : le bloc revient dans le projet.",
  retire = "contrat n°%d retiré (%s en est prévenu) : le bloc revient dans le projet.",
  refuse = "contrat n°%d refusé (%s en est prévenu) : le bloc revient dans le projet.",
  lache = "contrat n°%d lâché par le projet : signé, il reste dans Contrats jusqu'à son échéance, rien n'est envoyé à %s ; le bloc revient dans le projet.",
}
local function abandonner(p, i)
  local c = liste(p)[i]
  local n, qui = c and c.n or 0, c and (ns.projetCommande(p, i).player or "l'artisan")
  local fait, err = ns.abandonner(p, i)
  if not fait then dire(err) return end
  print("|cffa98fffContrats :|r " .. DIT[fait]:format(n, qui))
  redessiner()
  return true
end
-- Ce qu'« Abandonner » fera, pour la bulle : selon l'état du contrat.
local function abandonDit(v)
  if not v.fige then return "Abandonner : il s'efface, le bloc revient" end
  if v.etat == "signé" then return "Abandonner : le projet le lâche ; signé, il reste dans Contrats jusqu'à l'échéance (rien n'est envoyé)" end
  if v.etat == "contre-proposé" and ns.ctStatus(ns.ctStore()[v.contrat]) == "a_signer" then
    return "Abandonner : sa contre-proposition est refusée (il en est prévenu)"
  end
  return "Abandonner : ta proposition est retirée (il en est prévenu)"
end

-- Les zones où chaque contrat est dessiné (pour y ancrer son panneau) : zones["<projet>:<contrat>"] = la zone.
local zones = {}
local function cle(p, id) return p.id .. ":" .. id end

---------------------------------------------------------------------------------------------------
-- Le panneau d'un contrat préparé (ou de la Réponse). ns.ouvrirPanneau(p, id) ; il suit Composants (redessiné avec lui)
-- et se ferme quand sa case n'est plus là (autre projet affiché, contrat abandonné).
local panneau
local sync

-- Les cases qui peuvent être apportées : sous un bloc, ce qui entre dans ses cases sans en être (d'un autre bloc : toujours
-- apporté, entre = true) ; tout le projet, toutes ses cases sauf ses lignes. Lu sur l'arbre de la demande (aucun stock).
local function candidats(p, v)
  local dem = ns.arbreDemande(p, ns.projetApports(p))
  local out, vu = {}, {}
  local function ajouter(n, entre)
    if vu[n.id] then return end
    vu[n.id] = true
    out[#out + 1] = { id = n.id, qty = n.qty, entre = entre }
  end
  if v.bloc then
    local bloc = dem.blocDe[v.bloc]
    local dedans = {}
    for _, n in ipairs(bloc and bloc.cases or {}) do dedans[n] = true end
    for _, n in ipairs(bloc and bloc.cases or {}) do
      for _, k in ipairs(n.children) do if not dedans[k] then ajouter(k, bloc.inputs[k.id]) end end
    end
  else
    -- ponytail: toutes les cases dans un seul menu ; des sous-menus par étage le jour où un projet en a trop
    for _, n in ipairs(dem.cases) do if n.kind ~= "target" then ajouter(n, false) end end
  end
  return out
end

local function construire()
  local P = ns.newWindow("HandshakeContratPanneau", "", 340, 214)
  P:SetFrameStrata("DIALOG")
  local function texte(font, ...)
    local t = P:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint(...)
    t:SetJustifyH("LEFT")
    return t
  end
  local function champ(w, onChange)
    local e = CreateFrame("EditBox", nil, P, "InputBoxTemplate")
    e:SetSize(w, 22)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnTextChanged", function(self, user) if user then onChange(self:GetText()) end end)
    return e
  end
  local function ici() -- le projet, le rang du contrat, sa vue (nil s'il n'existe plus)
    local p = Composants and Composants.Projet(P.pid)
    local i = p and rangDe(p, P.id)
    if i then return p, i, ns.projetCommande(p, i) end
  end
  P.quoi = texte("GameFontHighlightSmall", "TOPLEFT", 14, -38)
  P.quoi:SetWidth(312)
  P.quoi:SetWordWrap(true)
  P.quoi:SetMaxLines(3)
  P.whoL = texte("GameFontHighlightSmall", "TOPLEFT", P.quoi, "BOTTOMLEFT", 0, -16) -- sous ce qui est livré, sans trou
  P.who = champ(160, function(t)
    local p, i = ici()
    if p then ns.projetArtisan(p, t, i); redessiner() end
  end)
  P.who:SetPoint("LEFT", P.whoL, "RIGHT", 10, 0)
  P.tipL = texte("GameFontHighlightSmall", "TOPLEFT", P.whoL, "BOTTOMLEFT", 0, -20)
  P.tip = champ(60, function(t)
    local p, i = ici()
    local n = tonumber((t:gsub(",", ".")))
    if p then ns.projetOffre(p, n and n >= 0 and math.floor(n * 10000 + 0.5) or nil, i); redessiner() end
  end)
  P.tip:SetPoint("LEFT", P.tipL, "RIGHT", 10, 0)
  texte("GameFontHighlightSmall", "LEFT", P.tip, "RIGHT", 4, 0):SetText("po")
  -- Les apports : un menu de cases à cocher (ce qui entre d'un autre bloc est toujours apporté, en titre).
  P.apports = CreateFrame("DropdownButton", nil, P, "WowStyle1DropdownTemplate")
  P.apports:SetWidth(120)
  P.apports:OverrideText("Apports")
  P.apports:SetPoint("LEFT", P.tip, "RIGHT", 34, 0)
  P.apports:SetupMenu(function(_, root)
    local p, _, v = ici()
    if not p then return end
    if v.fige then
      root:CreateTitle("Parti : ceux du contrat")
      for id in pairs(v.apports or {}) do root:CreateTitle(ns.itemLabel(id)) end
      return
    end
    local mes = ns.projetApports(p) or {}
    for _, k in ipairs(candidats(p, v)) do
      local nom = ("%d× %s"):format(k.qty, ns.itemLabel(k.id))
      if k.entre then root:CreateTitle(nom .. " (d'un autre bloc)")
      else
        root:CreateCheckbox(nom, function() return mes[k.id] == true end, function()
          ns.projetApport(p, k.id, not mes[k.id])
          mes = ns.projetApports(p) or {}
          redessiner()
        end)
      end
    end
  end)
  P.etat = texte("GameFontHighlightSmall", "TOPLEFT", P.tipL, "BOTTOMLEFT", 0, -20)
  P.etat:SetWidth(312)
  -- Le bouton d'action : ce que le contrat attend maintenant.
  P.go = CreateFrame("Button", nil, P, "UIPanelButtonTemplate")
  P.go:SetSize(150, 22)
  P.go:SetPoint("BOTTOMLEFT", 14, 12)
  P.go:SetScript("OnClick", function()
    local p, i, v = ici()
    if not p then return end
    if enLecture(p) then return ns.openContracts(aVoir(v)) end
    if v.reponse then -- la contre-proposition de l'artisan (règles de la Réponse : Handshake#60)
      local ct, err = ns.ctReplyFromOrder(v)
      if not ct then return dire(err) end
      ns.openContracts(ns.ctKey(ct))
    elseif not v.fige then -- le brouillon de la v1, sur sa fiche dans Contrats ; il part de là (SECURITE.md, en tête)
      local ct, err = ns.projetEnvoyer(p, i)
      if not ct then return dire(err) end
      ns.openContracts(ns.ctKey(ct))
    elseif v.ecart then -- sa part a changé : la nouvelle version, relue dans Contrats avec le différentiel (#19)
      local n, err = ns.projetNouvelleVersion(p, i)
      if not n then return dire(err) end
      ns.openContracts(ns.ctKey(n))
    else
      ns.openContracts(v.contrat)
    end
    redessiner()
  end)
  -- Ce qui sert rarement : dans « Plus ».
  P.plus = CreateFrame("DropdownButton", nil, P, "WowStyle1DropdownTemplate")
  P.plus:SetWidth(90)
  P.plus:OverrideText("Plus")
  P.plus:SetPoint("LEFT", P.go, "RIGHT", 8, 0)
  P.plus:SetupMenu(function(_, root)
    local p, i, v = ici()
    if not p then return end
    local voir = aVoir(v)
    if voir then root:CreateButton("Voir dans Contrats", function() ns.openContracts(voir) end) end
    if v.reponse or enLecture(p) then return end
    root:CreateButton("Envoyer en clair", function() ns.sendOrder(ns.projetCommande(p, i)) end)
    if not v.fige then
      root:CreateButton("Annoncer dans le Commerce", function() dire(select(2, ns.projetAnnoncer(p, i))); redessiner() end)
    end
    if not ns.contratClos(liste(p)[i]) then
      root:CreateButton("Abandonner", function() if abandonner(p, i) then P:Hide() end end)
    end
  end)
  -- Sa case disparue (autre projet affiché, contrat abandonné, fenêtre fermée) : le panneau se ferme.
  P:SetScript("OnUpdate", function(self)
    local z = self.zone
    if z and not (z:IsVisible() and z.hsCle == self.cle) then self:Hide() end
  end)
  return P
end

function sync()
  local P = panneau
  if not (P and P:IsShown()) then return end
  local p = Composants and Composants.Projet(P.pid)
  local i = p and rangDe(p, P.id)
  if not i then return P:Hide() end
  local c, v = liste(p)[i], ns.projetCommande(p, i)
  local rep = v.reponse ~= nil
  local client = v.player and v.player:match("^%S+") or "?"
  P.title:SetText(rep and ("Réponse à " .. client) or ("Contrat n°%d · %s"):format(c.n or 0, v.part))
  local livre, apporte = {}, {}
  for _, l in ipairs(v.lines) do livre[#livre + 1] = ("%d× %s"):format(l.qty, ns.itemLabel(l.id)) end
  for _, a in ipairs(ns.commandeApports(v)) do apporte[#apporte + 1] = ("%d× %s"):format(a.qty, ns.itemLabel(a.id)) end
  if v.fige then -- parti : les apports sont ceux du contrat
    apporte = {}
    for _, l in ipairs(ns.ctStore()[v.contrat].m) do apporte[#apporte + 1] = ("%d× %s"):format(l.qty, ns.itemLabel(l.id)) end
  end
  P.quoi:SetText(((rep and "Il veut : " or "Livré : ") .. (#livre > 0 and table.concat(livre, ", ") or "rien (le bloc a disparu)"))
    .. (#apporte > 0 and ("\n|cff4dccd9" .. (rep and "Il apporte : " or "Tu apportes : ") .. table.concat(apporte, ", ") .. "|r") or ""))
  P.whoL:SetText(rep and "Demandeur" or "Artisan")
  P.tipL:SetText(rep and "Mon prix" or "Offre")
  if not P.who:HasFocus() then P.who:SetText(v.player or "") end
  if not P.tip:HasFocus() then P.tip:SetText(poTexte(v.tip)) end
  local lecture = enLecture(p)
  P.who:SetEnabled(not v.fige and not rep and not lecture)
  P.tip:SetEnabled(not v.fige and not lecture)
  P.apports:SetShown(not lecture)
  P.plus:SetShown(not lecture)
  local etat = rep and "Sa demande : tes apports et ton prix, puis contre-propose." or ("État : " .. etatEnCouleur(v))
  if lecture then etat = ("État : %s · lecture seule : « Préparer » dans le fil pour le changer"):format(rep and "réponse" or etatEnCouleur(v)) end
  if v.ecart then etat = etat .. " · |cffe6994d" .. v.ecart .. "|r" end
  if v.incomplet then etat = etat .. " · |cffe6994destimation incomplète|r"
  elseif v.ecartPrix then etat = etat .. (" · caution %s%+.0f %%|r"):format(v.alertePrix and "|cffe64d4d" or "|cff59cc73", v.ecartPrix) end
  P.etat:SetText(etat)
  P:SetHeight(38 + P.quoi:GetStringHeight() + 16 + 3 * 20 + 3 * 12 + 36) -- la hauteur suit ce qui est livré et apporté
  if lecture then
    P.go:SetText("Voir dans Contrats")
    P.go:SetEnabled(aVoir(v) ~= nil)
  else
    P.go:SetText(rep and "Contre-proposer" or not v.fige and "Vérifier et envoyer…" or v.ecart and "Nouvelle version" or "Voir dans Contrats")
    P.go:SetEnabled((rep or v.fige or not v.vide) and true or false)
  end
end
ns.syncPanneau = sync

-- Ouvre le panneau du contrat id du projet p, à côté de sa case (ou de la bande de la Réponse).
function ns.ouvrirPanneau(p, id)
  panneau = panneau or construire()
  local z = zones[cle(p, id)]
  panneau.pid, panneau.id, panneau.cle, panneau.zone = p.id, id, cle(p, id), z and z:IsVisible() and z or nil
  panneau:ClearAllPoints()
  if panneau.zone then panneau:SetPoint("TOPLEFT", z, "TOPRIGHT", 8, 0) else panneau:SetPoint("CENTER") end
  panneau:Show()
  sync()
end

---------------------------------------------------------------------------------------------------
-- Les dessins dans les zones de Composants. Une zone est réutilisée d'un dessin à l'autre (et d'un bloc à l'autre) : tout
-- est remis à chaque appel.

-- Un petit bouton sur une ligne de titre (la bande) : « Commander », « Commander tout », la Réponse.
local function boutonBande(zone)
  local b = zone.hsBouton
  if not b then
    b = CreateFrame("Button", nil, zone, "BackdropTemplate")
    b:SetBackdrop({ bgFile = W8, edgeFile = W8, edgeSize = 1 })
    b:SetBackdropColor(0.16, 0.15, 0.25, 0.95)
    b:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.6)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b:SetFontString(b.text) -- (GetText, pour les tests du simulateur)
    b:SetPoint("LEFT")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    zone.hsBouton = b
  end
  return b
end
local function poser(zone, b, texte, survol, clic)
  b:SetText(texte)
  b:SetSize(b.text:GetStringWidth() + 14, 16)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    survol()
    GameTooltip:Show()
  end)
  b:SetScript("OnClick", clic)
  b:Show()
  zone:SetWidth(b:GetWidth())
end

-- Commander ce bloc (nil : tout le projet) : son contrat préparé, puis son panneau.
local function commander(p, bloc)
  local i = ns.projetCommander(p, bloc or {})
  local id = liste(p)[i].id
  Composants.Rafraichir()
  ns.ouvrirPanneau(p, id)
end

local function bande(zone, p, bloc)
  local b = boutonBande(zone)
  local r = HandshakeDB.commandes and HandshakeDB.commandes[p.id]
  if enLecture(p) and not (bloc == nil and r and r.reponse) then b:Hide(); return zone:SetWidth(1) end -- rien à commander
  if bloc then
    return poser(zone, b, "Commander", function()
      GameTooltip:AddLine(("Commander le bloc %s%s"):format(bloc.key, bloc.best and (" à " .. bloc.best) or ""))
      for _, id in ipairs(bloc.deliver) do GameTooltip:AddLine(("%d× %s"):format(bloc.qty[id], ns.itemLabel(id)), 1, 1, 1) end
      local entre = {}
      for id in pairs(bloc.inputs) do entre[#entre + 1] = ns.itemLabel(id) end
      if #entre > 0 then GameTooltip:AddLine("Tu apportes : " .. table.concat(entre, ", "), 0.3, 0.8, 0.85, true) end
      GameTooltip:AddLine("Clic : un contrat préparé ; l'artisan, l'offre et les apports se règlent, puis on l'envoie", 0.66, 0.56, 1, true)
    end, function() commander(p, bloc) end)
  end
  if r and r.reponse then -- la Réponse : son panneau (mon prix, les apports, contre-proposer)
    local v = ns.projetCommande(p, 1)
    local total = Composants.Arbre(p, false, r.apports).total
    zones[cle(p, r.liste[1].id)], zone.hsCle = zone, cle(p, r.liste[1].id)
    return poser(zone, b, ("Réponse à %s · mon prix %s · travail %s"):format((v.player or "?"):match("^%S+") or "?",
      ns.moneyShort(v.tip or 0), ns.moneySigned((v.tip or 0) - total)), function()
      GameTooltip:AddLine("Ma réponse à sa demande")
      GameTooltip:AddLine("Clic : mon prix, ses apports, contre-proposer", 0.66, 0.56, 1)
    end, function() ns.ouvrirPanneau(p, r.liste[1].id) end)
  end
  for _, c in ipairs(r and r.liste or {}) do -- un bloc déjà commandé : pas le projet entier en plus
    if c.bloc and ns.contratDuBloc(p, c.bloc) then b:Hide(); return zone:SetWidth(1) end
  end
  poser(zone, b, "Commander tout", function()
    GameTooltip:AddLine("Commander tout le projet à un seul artisan")
    GameTooltip:AddLine("Clic : un contrat préparé pour tout le projet (une liste sans arbre se commande ainsi)", 0.66, 0.56, 1, true)
  end, function() commander(p, nil) end)
end

-- La case d'un bloc commandé (ou du projet entier) : « Contrat n°12 · Forge », « Bel Dupont · envoyé ».
local function caseContrat(zone, p, i)
  local c, v = liste(p)[i], ns.projetCommande(p, i)
  local b = zone.hsCase
  if not b then
    b = CreateFrame("Button", nil, zone)
    b:SetAllPoints()
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(26, 26)
    b.icone:SetPoint("TOPLEFT", 8, -5)
    b.l1 = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.l1:SetPoint("TOPLEFT", 40, -6); b.l1:SetPoint("RIGHT", -6, 0)
    b.l1:SetJustifyH("LEFT"); b.l1:SetWordWrap(false)
    b.l2 = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.l2:SetPoint("TOPLEFT", 40, -21); b.l2:SetPoint("RIGHT", -6, 0)
    b.l2:SetJustifyH("LEFT"); b.l2:SetWordWrap(false)
    b:SetScript("OnClick", function(self) ns.ouvrirPanneau(self.p, self.id) end)
    b:SetScript("OnEnter", function(self)
      local q = Composants.Projet(self.p.id)
      local k = q and rangDe(q, self.id)
      if not k then return end
      local x = ns.projetCommande(q, k)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.l1:GetText())
      GameTooltip:AddLine(("%s · %s"):format(x.player or "artisan à choisir", etatEnCouleur(x)), 1, 1, 1)
      for _, l in ipairs(x.lines) do GameTooltip:AddLine(("%d× %s"):format(l.qty, ns.itemLabel(l.id)), 0.8, 0.8, 0.8) end
      if x.ecart then GameTooltip:AddLine(x.ecart, 0.9, 0.6, 0.3) end
      GameTooltip:AddLine(enLecture(q) and "Clic : son état, le voir dans Contrats" or "Clic : artisan, offre, apports, vérifier et envoyer", 0.66, 0.56, 1)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    zone.hsCase = b
  end
  b.p, b.id = p, c.id
  zones[cle(p, c.id)], zone.hsCle = zone, cle(p, c.id)
  b.icone:SetTexture(v.lines[1] and C_Item.GetItemIconByID(v.lines[1].id) or "Interface\\Icons\\INV_Misc_Note_01")
  b.l1:SetText(("Contrat n°%d · %s"):format(c.n or 0, v.part))
  b.l2:SetText(("%s · %s%s"):format(v.player or "|cffe6994dartisan ?|r", etatEnCouleur(v), v.ecart and " · |cffe6994d!|r" or ""))
  b:Show()
end

---------------------------------------------------------------------------------------------------
-- Les lignes des contrats dans les Besoins (l'emplacement des Besoins) : une par contrat vivant, réutilisées d'un dessin à
-- l'autre. « Contrat n°12 · à recevoir », son état, « Abandonner » ; livré : « Contrat n°12 · reçu », en vert.
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local HAUT = 28
local function ligneContrat(zone, k)
  zone.hsLignes = zone.hsLignes or {}
  local b = zone.hsLignes[k]
  if b then return b end
  b = CreateFrame("Button", nil, zone)
  b:SetHeight(HAUT)
  b.icone = b:CreateTexture(nil, "ARTWORK")
  b.icone:SetSize(20, 20)
  b.icone:SetPoint("TOPLEFT", 0, -2)
  b.texte = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.texte:SetPoint("TOPLEFT", 26, -4)
  b.texte:SetJustifyH("LEFT")
  b.etat = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.abandon = CreateFrame("Button", nil, b, "UIPanelButtonTemplate")
  b.abandon:SetSize(90, 20)
  b.abandon:SetPoint("TOPRIGHT", 0, -1)
  b.abandon:SetText("Abandonner")
  b.abandon:SetScript("OnClick", function(self) abandonner(b.p, rangDe(b.p, b.id)) end)
  b.abandon:SetScript("OnEnter", function(self)
    local q = Composants.Projet(b.p.id)
    local i = q and rangDe(q, b.id)
    if not i then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(abandonDit(ns.projetCommande(q, i)), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b.abandon:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self) ns.ouvrirPanneau(self.p, self.id) end)
  b:SetScript("OnEnter", function(self)
    local q = Composants.Projet(self.p.id)
    local i = q and rangDe(q, self.id)
    if not i then return end
    local v = ns.projetCommande(q, i)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("Contrat n°%d · %s"):format(liste(q)[i].n or 0, v.part))
    GameTooltip:AddLine(("%s · %s"):format(v.player or "artisan à choisir", etatEnCouleur(v)), 1, 1, 1)
    for _, l in ipairs(v.lines) do GameTooltip:AddLine(("%d× %s"):format(l.qty, ns.itemLabel(l.id)), 0.8, 0.8, 0.8) end
    GameTooltip:AddLine("Clic : son panneau (artisan, offre, apports, envoyer)", 0.66, 0.56, 1)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  zone.hsLignes[k] = b
  return b
end

local function besoins(zone, p)
  local vivants = ns.contratsVivants(p)
  for k, i in ipairs(vivants) do
    local c, v = liste(p)[i], ns.projetCommande(p, i)
    local recu = ns.contratClos(c)
    local b = ligneContrat(zone, k)
    b.p, b.id = p, c.id
    zones[cle(p, c.id)], b.hsCle = b, cle(p, c.id)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 0, -(k - 1) * HAUT)
    b:SetWidth(zone:GetWidth())
    b.icone:SetTexture(v.lines[1] and C_Item.GetItemIconByID(v.lines[1].id) or "Interface\\Icons\\INV_Misc_Note_01")
    b.texte:SetText(recu and ("|cff59cc73Contrat n°%d · reçu|r"):format(c.n) or ("Contrat n°%d · à recevoir"):format(c.n))
    b.etat:ClearAllPoints()
    b.etat:SetPoint("TOPRIGHT", recu and b or b.abandon, recu and "TOPRIGHT" or "TOPLEFT", recu and 0 or -6, recu and -4 or -3)
    b.etat:SetText(recu and READY or etatEnCouleur(v))
    b.abandon:SetShown(not recu)
    b:Show()
  end
  for k = #vivants + 1, #(zone.hsLignes or {}) do zone.hsLignes[k]:Hide() end
  if panneau and panneau:IsShown() then sync() end
  return #vivants * HAUT
end

-- Mes apports : ceux que je coche, d'un contrat vivant (ns.elaguerApports, la seule règle), et les termes de mes contrats
-- partis et vivants.
local function aDonner(p)
  local r = HandshakeDB.commandes and HandshakeDB.commandes[p.id]
  if not r or r.reponse then return nil end
  local out = {}
  for id in pairs(ns.elaguerApports(p) or {}) do out[id] = true end
  for _, i in ipairs(ns.contratsVivants(p)) do
    local ct = ns.commandeEnvoyee(r.liste[i])
    for _, l in ipairs(ct and ct.m or {}) do out[l.id] = true end
  end
  return out
end

-- Le fournisseur de l'emplacement du bloc et des Besoins (Composants.Emplacements, branché à l'entrée en jeu :
-- ns.brancherComposants).
ns.emplacement = {
  confie = function(p, bloc) return ns.contratDuBloc(p, bloc and bloc.key) ~= nil end,
  -- Dans une Réponse, ses apports (ceux du demandeur) sortent de mon arbre ; les miens (demandeur), non : je dois les
  -- avoir sur moi pour les donner (aDonner). Dans les deux cas, seulement ceux d'un contrat vivant (ns.elaguerApports :
  -- un bloc rendu n'en a plus). Rien n'est rangé pour un projet qu'on ne fait que lire.
  apports = function(p)
    local vivants = ns.elaguerApports(p) -- élagués à chaque dessin : un refus reçu entre-temps y est vu
    local r = HandshakeDB.commandes and HandshakeDB.commandes[p.id]
    return r and r.reponse and vivants or nil
  end,
  aDonner = aDonner,
  besoins = besoins,
  -- Tous les contrats vivants du projet livrés (aucun : vrai). Un contrat préparé, envoyé ou signé retient en Réunir.
  clos = function(p)
    local r = HandshakeDB.commandes and HandshakeDB.commandes[p.id]
    for _, i in ipairs(ns.contratsVivants(p)) do if not ns.contratClos(r.liste[i]) then return false end end
    return true
  end,
  bloc = function(zone, p, bloc, confie)
    zone.hsCle = nil
    if confie then
      if zone.hsBouton then zone.hsBouton:Hide() end
      caseContrat(zone, p, ns.contratDuBloc(p, bloc and bloc.key))
    else
      if zone.hsCase then zone.hsCase:Hide() end
      bande(zone, p, bloc)
    end
    if panneau and panneau:IsShown() and panneau.cle == zone.hsCle then sync() end
  end,
}
