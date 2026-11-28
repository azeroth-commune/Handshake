-- Handshake, la fenêtre des contrats (/contrat). Un contrat à la fois : qui donne quoi à chaque étape,
-- ce qui a changé depuis la version d'avant, TON estimation de la caution et ta perte maximale (P8), les
-- vérifications (objets liés, besoins plus gros que les recettes, nom proche d'un autre), l'avancement.
-- Accepter : jamais par Entrée ni fenêtre surgissante, bouton réarmé 2 s après l'affichage d'une version (P7).
-- « Vérifier et envoyer… » dans le panneau d'un contrat préparé (Emplacement.lua, un bloc commandé dans Composants)
-- en ouvre le brouillon, relu ici ; « Préparer la demande » dans la commande à la main (ns.mainPreparer) en fait un
-- brouillon, relu ici ; « Nouvelle version »
-- un brouillon de la version suivante (ns.projetNouvelleVersion) : rien ne part avant « Envoyer ». Une demande reçue se
-- répond dans l'arbre ou en liste. La fenêtre retient la clé du contrat affiché, et chaque clic de sa fiche part avec ce
-- contrat-là, tel qu'affiché (empreinte), ou rien (#69).
local _, ns = ...

-- La colonne des contrats à gauche (COL_W), le contrat affiché à droite de X0. W × H : taille de départ et minimum, ce
-- que prend le cas courant (la ligne « Modifier » et la plus longue rangée de boutons) ; le texte défile, on agrandit.
local COL_W, X0 = 150, 166
local W, H = 680, 400
local ENTREE_H, NOUVELLE_H, ARCHIVES_H = 34, 22, 22
local frame, list, pos, shownHash = nil, {}, 1, nil
local deplie = false -- « Archivés (n) » replié par défaut, pour la session (#72)
-- Le contrat affiché, retenu par sa clé à travers les rafraîchissements (#69), et l'empreinte de ce qui en est affiché.
local shownKey, shownEmpreinte
local firstShown = {} -- empreinte -> moment où cette version a été affichée pour la première fois (réarmement)
local STATUS = { brouillon = "|cff999999BROUILLON (pas envoyé)|r", envoye = "|cffe6994dEN ATTENTE DE SA RÉPONSE|r",
  a_signer = "|cffffd100À SIGNER PAR TOI|r", signe = "|cff59cc73SIGNÉ|r", clos = "|cff59cc73CLOS|r", echu = "|cffe64d4dÉCHU|r",
  refuse = "|cffe64d4dREFUSÉ|r", retire = "|cff999999RETIRÉ|r" }
-- Dans la colonne des contrats : l'état en un mot (avec la couleur de STATUS).
local COURT = { brouillon = "brouillon", envoye = "en attente", a_signer = "à signer", signe = "signé", clos = "clos",
  echu = "échu", refuse = "refusé", retire = "retiré" }
-- L'ordre de la colonne : à signer, préparé, en attente, signé, puis le dernier terminé (et les désarchivés) ; les
-- archivés à la fin, sous leur en-tête (#72).
local ORDER = { a_signer = 1, brouillon = 2, envoye = 3, signe = 4, echu = 5, clos = 6, refuse = 7, retire = 8 }

local money = function(c) return ns.moneyShort(c) end
local function rel(sec)
  if sec < 0 then return "dépassée" end
  local d, h, m = math.floor(sec / 86400), math.floor(sec % 86400 / 3600), math.floor(sec % 3600 / 60)
  return d > 0 and ("dans %d j %d h"):format(d, h) or ("dans %d h %d min"):format(h, m)
end
-- Montant exact en po pour les champs (4 décimales = au cuivre près) : renvoyer un champ inchangé ne doit rien changer.
local function po(c) return (("%.4f"):format(c / 10000):gsub("%.?0+$", "")) end

-- Besoins vérifiés contre les recettes connues (n° 12) : quantité maximale de chaque objet dans l'arbre complet,
-- et ses ancêtres (demander une barre ET son minerai = doublon).
local function expansion(o)
  local by = {}
  for _, r in pairs(ns.recipes()) do
    if r.output and r.reagents and not by[r.output] then by[r.output] = r end
  end
  local qty, anc, unknown = {}, {}, {}
  local function walk(id, n, path, depth)
    local r = by[id]
    if not r then if depth == 0 then unknown[#unknown + 1] = id end return end
    if depth > 10 or path[id] then return end
    path[id] = true
    local crafts = math.ceil(n / math.max(1, r.made_min or 1))
    for _, rg in ipairs(r.reagents) do
      if rg.id then
        local q = rg.qty * crafts
        qty[rg.id] = (qty[rg.id] or 0) + q
        anc[rg.id] = anc[rg.id] or {}
        for a in pairs(path) do anc[rg.id][a] = true end
        walk(rg.id, q, path, depth + 1)
      end
    end
    path[id] = nil
  end
  for _, l in ipairs(o) do walk(l.id, l.qty, {}, 0) end
  return qty, anc, unknown
end

local function plain(name) return name:lower():gsub("[\128-\255]", "") end

function ns.ctDescribe(c, me)
  local t, status = {}, ns.ctStatus(c)
  local peer, artisan = c.peer or {}, me == c.artisan
  local other = peer.name or "?" -- le nom donné par le serveur, jamais déduit du GUID
  local add = function(s) t[#t + 1] = s end
  local caution, delivery = ns.ctTotal(c.m), ns.ctTotal(c.o)
  add(("|cffffd100Contrat avec %s|r"):format(ns.identity(other, peer.guid)))
  add(("Toi : %s   ·   v%s   ·   empreinte %s"):format(ns.myIdentity(), c.v, (c.hash or "—"):sub(1, 8)))
  add((STATUS[status] or status) .. ("   ·   tu es %s   ·   échéance %s"):format(artisan and "l'ARTISAN" or "le CLIENT", rel(c.d - GetServerTime())))
  add(peer.verified and ("Identité de %s : |cff59cc73confirmée par le serveur|r (GUID %s)"):format(other, tostring(peer.guid))
    or ("Identité de %s : |cffe6994dGUID annoncé, vérifié au premier échange|r (GUID %s)"):format(other, tostring(peer.guid)))
  for _, x in pairs(ns.ctStore()) do -- n° 26 : nom presque identique à un autre partenaire
    local o2 = x.peer and x.peer.name or other
    if o2 ~= other and plain(o2) == plain(other) then add(("|cffe64d4d! Nom très proche de %s : vérifie que c'est bien la bonne personne.|r"):format(o2)) break end
  end
  if c.prev then -- n° 4 : ce qui a changé
    local ch = {}
    local pc, pd = ns.ctTotal(c.prev.m), ns.ctTotal(c.prev.o)
    if pc ~= caution then ch[#ch + 1] = ("caution %s -> %s"):format(ns.money(pc), ns.money(caution)) end
    if pd ~= delivery then ch[#ch + 1] = ("livraison %s -> %s"):format(ns.money(pd), ns.money(delivery)) end
    if c.prev.d ~= c.d then ch[#ch + 1] = "échéance changée" end
    for _, pair in ipairs({ { c.prev.m, c.m }, { c.prev.o, c.o } }) do
      local old = {}
      for _, l in ipairs(pair[1]) do old[l.id] = l.qty end
      for _, l in ipairs(pair[2]) do
        if old[l.id] ~= l.qty then ch[#ch + 1] = ("%s %s -> %d"):format(ns.itemLabel(l.id), old[l.id] or "absent", l.qty) end
        old[l.id] = nil
      end
      for id in pairs(old) do ch[#ch + 1] = ns.itemLabel(id) .. " retiré" end
    end
    add(("|cffe6994dChangé depuis la v%s : %s|r"):format(c.prev.v, #ch > 0 and table.concat(ch, " ; ") or "rien"))
  end
  -- « tu donnes » / « Bob donne » : le client et l'artisan vus depuis ma place, prénom seul.
  local otherShort = other:match("^%S+")
  local function verb(isMe, tu, il) return isMe and ("Tu " .. tu) or (otherShort .. " " .. il) end
  add(" ")
  if #c.m > 0 then
    add("|cffffd100Étape 1 — l'artisan achète les composants|r")
    for _, l in ipairs(c.m) do add(("   %s %d × %s   (caution %s l'unité)"):format(verb(not artisan, "donnes", "donne"), l.qty, ns.itemLabel(l.id), ns.money(l.unit))) end
    add(("   %s la caution : %s"):format(verb(artisan, "verses", "verse"), ns.money(caution)))
  end
  add("|cffffd100Étape " .. (#c.m > 0 and "2" or "unique") .. " — le client achète les objets|r")
  for _, l in ipairs(c.o) do add(("   %s %d × %s   (%s l'objet)"):format(verb(artisan, "livres", "livre"), l.qty, ns.itemLabel(l.id), ns.money(l.unit))) end
  add(("   %s : %s%s"):format(verb(not artisan, "paies", "paie"), ns.money(delivery), #c.m > 0 and (" (caution rendue %s + prix %s)"):format(ns.money(caution), ns.moneySigned(delivery - caution)) or ""))
  if delivery - caution <= 0 then
    add(artisan and "   |cffe6994d! Aucun prix pour ton travail : « Répondre » ou « Répondre en liste » pour chiffrer ta part.|r"
      or "   |cffe6994dPrix laissé à l'artisan : il le chiffrera en contre-proposant.|r")
  end
  if #c.m == 0 then add("   |cff999999Vente simple : rien n'est apporté, donc pas de caution ; le panneau vérifiera l'objet et le prix.|r") end
  add(" ")

  -- P8 : ton estimation, ta perte maximale (ns.ctEstimation, la même que sur la page du projet).
  local e = ns.ctEstimation(c, me)
  add(("|cffffd100Ton estimation|r (scan de l'HV : %s)"):format(e.scanned or "jamais"))
  if #c.m > 0 then
    add(("   composants ~%s · caution %s%+.0f %%|r"):format(money(e.composants), e.alerte and "|cffe64d4d" or "|cff59cc73", e.ecart))
    if e.manquants > 0 then add(("   |cffe6994d! %d composant(s) sans prix connu : estimation incomplète|r"):format(e.manquants)) end
    if artisan then
      add(("   Si le client disparaît après l'étape 1 : tu perds au plus %s + ton travail"):format(money(e.perte)))
    else
      add(("   Si l'artisan disparaît après l'étape 1 : tu perds au plus %s"):format(money(e.perte)))
    end
  end
  if e.valeur > 0 then add(("   les objets livrés valent ~%s à l'HV (tu %s %s)"):format(money(e.valeur), artisan and "reçois" or "paies", money(delivery))) end

  -- Vérifications
  local checks = {}
  for _, l in ipairs(c.o) do
    if select(14, C_Item.GetItemInfo(l.id)) == 1 then checks[#checks + 1] = ns.itemLabel(l.id) .. " est lié quand ramassé : impossible à livrer" end
  end
  for _, l in ipairs(c.m) do
    if select(14, C_Item.GetItemInfo(l.id)) == 1 then checks[#checks + 1] = ns.itemLabel(l.id) .. " est lié quand ramassé : impossible à fournir" end
  end
  if #c.m > 0 then
    local need, anc, unknown = expansion(c.o)
    if #unknown > 0 then checks[#checks + 1] = "recette inconnue pour " .. ns.itemLabel(unknown[1]) .. " : quantités de composants non vérifiables" end
    if #unknown == 0 then
      for _, l in ipairs(c.m) do
        if not need[l.id] then checks[#checks + 1] = ns.itemLabel(l.id) .. " n'entre pas dans les recettes"
        elseif l.qty > need[l.id] then checks[#checks + 1] = ("%s : %d demandés, la recette en consomme %d"):format(ns.itemLabel(l.id), l.qty, need[l.id]) end
        for _, l2 in ipairs(c.m) do
          if anc[l2.id] and anc[l2.id][l.id] then checks[#checks + 1] = ns.itemLabel(l.id) .. " ET son composant " .. ns.itemLabel(l2.id) .. " sont demandés" end
        end
      end
    end
  end
  if #checks > 0 then
    add(" ")
    add("|cffe64d4dÀ vérifier|r")
    for _, s in ipairs(checks) do add("   |cffe64d4d! " .. s .. "|r") end
  end

  -- Avancement
  if c.ledger or c.unconfirmed then
    add(" ")
    add("|cffffd100Avancement (ce que ton addon a vu passer)|r")
    local inList, outList = artisan and c.m or c.o, artisan and c.o or c.m
    for _, l in ipairs(inList) do add(("   reçu %d/%d %s"):format((c.got or {})[l.id] or 0, l.qty, ns.itemLabel(l.id))) end
    for _, l in ipairs(outList) do add(("   donné %d/%d %s"):format((c.gave or {})[l.id] or 0, l.qty, ns.itemLabel(l.id))) end
    add(("   solde (reçu − donné, en valeurs du contrat) : %s"):format(ns.moneySigned(c.net or 0)))
    if c.unconfirmed then add(("   |cffe6994d! %d échange(s) à vérifier : terminés, mais ton or ou tes sacs n'ont pas bougé comme prévu|r"):format(#c.unconfirmed)) end
  end
  return table.concat(t, "\n")
end

---------------------------------------------------------------------------------------------------
local function sorted()
  local l = {}
  for k, c in pairs(ns.ctStore()) do
    if ns.ctBrouillonPerime(c) then ns.ctStore()[k] = nil else l[#l + 1] = c end -- la version en cours a changé depuis
  end
  ns.ctArchiver() -- l'échu vient du temps : l'archivage se règle à chaque tri (#72)
  table.sort(l, function(a, b)
    if not a.archive ~= not b.archive then return not a.archive end
    local oa, ob = ORDER[ns.ctStatus(a)] or 9, ORDER[ns.ctStatus(b)] or 9
    if oa ~= ob then return oa < ob end
    return (a.received or tonumber(a.id) or 0) > (b.received or tonumber(b.id) or 0)
  end)
  return l
end

-- Ce qui est affiché d'un contrat (un brouillon n'a pas encore d'empreinte : on la calcule) : ses termes et son état.
local function empreinte(c) return ns.ctHash(ns.ctCanonical(c)) .. c.status end

local function refresh()
  if Composants then Composants.Rafraichir() end -- l'état des contrats d'un projet (son emplacement du bloc) se lit ici
  if ns.refreshCommandeMain then ns.refreshCommandeMain() end
  if not (frame and frame:IsShown()) then return end
  list = sorted()
  -- Le contrat affiché se retrouve par sa clé, pas par sa place : une proposition arrivée en tête ou un brouillon périmé
  -- effacé ne font rien glisser sous les yeux (#69). Son brouillon parti ou effacé : sa version en cours ; sans version en
  -- cours (brouillon v1 abandonné, contrat effacé) : la tête de liste, pas ce qui a glissé à sa place.
  local function trouve(k) for i, x in ipairs(list) do if ns.ctKey(x) == k then return i end end end
  pos = shownKey and (trouve(shownKey) or trouve((shownKey:gsub("%+$", "")))) or 1
  pos = math.min(math.max(1, pos), math.max(1, #list))
  local c, me = list[pos], ns.me()
  shownKey, shownEmpreinte = c and ns.ctKey(c), c and empreinte(c)
  frame.syncColonne() -- la liste et le contrat affiché ont pu changer
  for _, b in ipairs(frame.actions) do b:Hide() end
  frame.edit:SetShown(false)
  if not c then
    frame.body:SetText("|cff999999Aucun contrat. « Commander » un bloc dans Composants, ou « + Nouvelle commande » puis « Préparer la demande ».|r")
    frame.content:SetHeight(frame.body:GetStringHeight() + 10)
    return
  end
  frame.body:SetText(ns.ctDescribe(c, me))
  frame.content:SetHeight(frame.body:GetStringHeight() + 10)
  local status = ns.ctStatus(c)
  local function show(b) b:Show() end
  if status == "a_signer" then
    show(frame.accept); show(frame.refuse)
    if c.artisan == me then
      if Composants then show(frame.reply) end -- sans Composants, pas d'arbre : la liste seulement
      show(frame.replyList)
    end
    -- Réarmement (n° 5) : « Signer » s'active 2 s après le premier affichage de CETTE version ; le bouton porte
    -- l'empreinte affichée, une autre version ne peut pas être signée par ce clic.
    shownHash = c.hash
    firstShown[c.hash] = firstShown[c.hash] or GetTime()
    local wait = 2 - (GetTime() - firstShown[c.hash])
    frame.accept:SetEnabled(wait <= 0)
    if wait > 0 then C_Timer.After(wait + 0.05, refresh) end
  end
  if status == "brouillon" then show(frame.send) end
  if status == "envoye" then show(frame.withdraw); show(frame.manual) end
  if status == "brouillon" or status == "envoye" then
    frame.readable:ClearAllPoints()
    frame.readable:SetPoint("LEFT", status == "brouillon" and frame.send or frame.manual, "RIGHT", 6, 0)
    show(frame.readable)
  end
  if status == "a_signer" or status == "brouillon" then
    frame.edit:Show()
    if frame.edit.shownFor ~= (c.hash or ns.ctKey(c) .. ns.ctTotal(c.o) .. ns.ctTotal(c.m) .. c.d) then -- remplis une fois par version (pas d'écrasement pendant la saisie)
      frame.edit.shownFor = c.hash or ns.ctKey(c) .. ns.ctTotal(c.o) .. ns.ctTotal(c.m) .. c.d
      frame.edit.caution:SetText(po(ns.ctTotal(c.m)))
      frame.edit.delivery:SetText(po(ns.ctTotal(c.o)))
      frame.edit.days:SetText((("%.1f"):format(math.max(0, (c.d - GetServerTime()) / 86400)):gsub("%.0$", "")))
      frame.edit.initial = { frame.edit.caution:GetText(), frame.edit.delivery:GetText(), frame.edit.days:GetText() }
    end
    frame.edit.caution:SetEnabled(#c.m > 0)
    frame.edit.go:SetText(status == "brouillon" and "Modifier" or "Contre-proposer…")
  end
end
ns.refreshContracts = refresh

ns.ctNotify = function(text)
  print("|cffa98fffContrats :|r " .. text)
  refresh()
end

-- Le texte du contrat en clair, pour quelqu'un qui n'a pas l'addon (il ne vaut pas signature).
local function readable(c)
  local SendChatMessage = function(msg, _, _, target) ns.whisper(msg, target) end
  local other = c.peer and c.peer.name
  if #c.m > 0 then
    for _, msg in ipairs(ns.listMessages("Contrat", c.m, ("· composants fournis par le client, caution %s"):format(ns.poText(ns.ctTotal(c.m))))) do
      SendChatMessage(msg, "WHISPER", nil, other)
    end
  end
  for _, msg in ipairs(ns.listMessages("Contrat", c.o, ("· à la livraison %s · avant le %s"):format(ns.poText(ns.ctTotal(c.o)), date("%d/%m %H:%M", c.d)))) do
    SendChatMessage(msg, "WHISPER", nil, other)
  end
end

local function build()
  frame = ns.newWindow("HandshakeContratsFrame", "Contrats", W, H)
  local function button(text, w, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    -- Un clic agit sur le contrat AFFICHÉ (#69, P3) : relu dans la base par sa clé, et seulement s'il n'a pas changé depuis
    -- l'affichage (même empreinte) ; sinon rien ne part, et le contrat redessiné est à relire.
    b:SetScript("OnClick", function()
      local c = shownKey and ns.ctStore()[shownKey]
      if c and empreinte(c) == shownEmpreinte then
        onClick(c)
        shownKey = ns.ctKey(c) -- un brouillon parti change de clé (« origine#id+ » -> « origine#id »)
      else
        print("|cffe64d4dContrats :|r le contrat affiché a changé : relis-le, rien n'est parti.")
      end
      refresh()
    end)
    return b
  end
  -- Le contrat affiché : une colonne de tous les contrats, comme celle des projets de Composants (skill ui-addon : pas de
  -- menu déroulant) ; une entrée par contrat : l'icône du premier objet livré, le nom de l'autre, l'état en couleur en
  -- dessous (la version est sur la fiche) ; la bulle donne tous les objets. Celle affichée surlignée (le surlignage du
  -- jeu, tenu, et un trait doré) ; clic = l'afficher. Elle défile au-delà de sa hauteur. En bas, « Archivés (n) », replié
  -- par défaut ; clic droit sur un archivé : « Désarchiver » (#72). En tête, fixe hors de la liste qui défile,
  -- « + Nouvelle commande » : la Commande à la main, sans arbre ni projet (#38, #70).
  local col = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  col:SetPoint("TOPLEFT", 10, -30) -- sous la barre de titre du gabarit
  col:SetPoint("BOTTOMLEFT", 10, 10)
  col:SetWidth(COL_W)
  local sc = CreateFrame("ScrollFrame", nil, col, "UIPanelScrollFrameTemplate")
  sc:SetPoint("TOPLEFT", 4, -4 - NOUVELLE_H)
  sc:SetPoint("BOTTOMRIGHT", -24, 4)
  local liste = CreateFrame("Frame", nil, sc)
  liste:SetSize(COL_W - 28, 1)
  sc:SetScrollChild(liste)
  local nouvelle = CreateFrame("Button", nil, col)
  nouvelle:SetSize(COL_W - 28, NOUVELLE_H - 2)
  nouvelle:SetPoint("TOPLEFT", 4, -4)
  nouvelle:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  nouvelle:SetFontString(nouvelle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")) -- doré, aligné sur les noms
  nouvelle:GetFontString():SetPoint("LEFT", 8, 0)
  nouvelle:SetText("+ Nouvelle commande")
  nouvelle:SetScript("OnClick", function() ns.openCommandeMain() end)
  -- L'en-tête des archivés, comme ceux du journal de quêtes (le + / – du jeu).
  local archives = CreateFrame("Button", nil, liste)
  archives:SetSize(COL_W - 28, ARCHIVES_H - 2)
  archives:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  archives.signe = archives:CreateTexture(nil, "ARTWORK")
  archives.signe:SetSize(14, 14)
  archives.signe:SetPoint("LEFT", 6, 0)
  archives:SetFontString(archives:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"))
  archives:GetFontString():SetPoint("LEFT", archives.signe, "RIGHT", 4, 0)
  archives:SetScript("OnClick", function() deplie = not deplie; frame.syncColonne() end)
  frame.archives = archives
  frame.entrees = {}
  local function entree(i)
    local b = CreateFrame("Button", nil, liste)
    b:SetSize(COL_W - 28, ENTREE_H - 2)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.fond = b:CreateTexture(nil, "BACKGROUND")
    b.fond:SetAllPoints()
    b.fond:SetTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
    b.fond:SetBlendMode("ADD")
    b.fond:SetVertexColor(1, 0.82, 0, 0.5)
    b.trait = b:CreateTexture(nil, "ARTWORK")
    b.trait:SetPoint("TOPLEFT"); b.trait:SetPoint("BOTTOMLEFT"); b.trait:SetWidth(2)
    b.trait:SetColorTexture(1, 0.82, 0, 0.9)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    b.icone = b:CreateTexture(nil, "ARTWORK")
    b.icone:SetSize(22, 22)
    b.icone:SetPoint("LEFT", 6, 0)
    b.nom = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.nom:SetPoint("TOPLEFT", 32, -4); b.nom:SetPoint("RIGHT", -4, 0)
    b.nom:SetJustifyH("LEFT"); b.nom:SetWordWrap(false)
    b.etat = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.etat:SetPoint("TOPLEFT", 32, -18); b.etat:SetPoint("RIGHT", -4, 0)
    b.etat:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self, souris)
      local c = self.c
      if souris ~= "RightButton" then shownKey = ns.ctKey(c); return refresh() end
      if c.archive then
        MenuUtil.CreateContextMenu(self, function(_, root)
          root:CreateButton("Désarchiver", function() ns.ctDesarchiver(c); refresh() end)
        end)
      end
    end)
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(self.nom:GetText())
      for _, l in ipairs(self.c.o) do GameTooltip:AddLine(("%d × %s"):format(l.qty, ns.itemLabel(l.id)), 1, 1, 1) end
      if self.c.archive then GameTooltip:AddLine("Clic droit : Désarchiver", 0.6, 0.6, 0.6) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.entrees[i] = b
    return b
  end
  frame.syncColonne = function()
    local n, y = 0, 0
    for _, c in ipairs(list) do if c.archive then n = n + 1 end end
    archives:SetShown(n > 0)
    archives:SetText(("Archivés (%d)"):format(n))
    archives.signe:SetTexture(deplie and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    for i, c in ipairs(list) do
      local b = frame.entrees[i] or entree(i)
      if i == #list - n + 1 then archives:SetPoint("TOPLEFT", 0, -y); y = y + ARCHIVES_H end -- le premier archivé
      local s = ns.ctStatus(c)
      b.c = c
      b.nom:SetText(c.peer and c.peer.name or "?")
      b.icone:SetTexture(c.o[1] and C_Item.GetItemIconByID(c.o[1].id) or "Interface\\Icons\\INV_Misc_Note_01")
      local couleur = (STATUS[s] or ""):match("^|c" .. ("%x"):rep(8)) -- la couleur de l'état en entier (8 chiffres : « |cff999999BROUILLON »)
      b.etat:SetText(couleur and (couleur .. (COURT[s] or s) .. "|r") or (COURT[s] or s))
      b.fond:SetShown(i == pos)
      b.trait:SetShown(i == pos)
      b:SetAlpha(c.archive and 0.5 or 1)
      b:SetPoint("TOPLEFT", 0, -y)
      b:SetShown(not c.archive or deplie)
      if b:IsShown() then y = y + ENTREE_H end
    end
    for i = #list + 1, #frame.entrees do frame.entrees[i]:Hide() end
    liste:SetHeight(y + 8)
    if sc.ScrollBar then sc.ScrollBar:SetShown(liste:GetHeight() > sc:GetHeight()) end -- la barre seulement si ça déborde
  end

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", X0, -34) -- sous la barre de titre
  scroll:SetPoint("BOTTOMRIGHT", -32, 96)
  frame.content = CreateFrame("Frame", nil, scroll)
  frame.content:SetSize(W - X0 - 36, 1)
  scroll:SetScrollChild(frame.content)
  frame.body = frame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.body:SetPoint("TOPLEFT")
  frame.body:SetWidth(W - X0 - 42)
  scroll:SetScript("OnSizeChanged", function(_, w) -- le texte suit la largeur de la fenêtre agrandie
    frame.content:SetWidth(w)
    frame.body:SetWidth(w - 6)
    frame.content:SetHeight(frame.body:GetStringHeight() + 10)
  end)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetSpacing(3)

  -- Actions (bas de la fenêtre)
  frame.accept = button("Signer", 90, function(c) if not ns.ctAccept(c, shownHash) then print("Contrats : la version affichée a changé, relis-la.") end end)
  frame.refuse = button("Refuser", 80, function(c) ns.ctRefuse(c) end)
  -- « Répondre » : la Réponse, un projet tenu de Composants ouvert en Préparer (seulement s'il est chargé).
  frame.reply = button("Répondre", 90, function(c) Composants.Ouvrir(ns.projetReponse(c).id) end)
  frame.replyList = button("Répondre en liste", 130, function(c) ns.openCommandeMain(c) end) -- sans arbre (#38)
  frame.send = button("Envoyer la proposition", 170, function(c)
    local ok, err = ns.ctPropose(c)
    if not ok then print("|cffe64d4dContrats :|r " .. err .. ".") end
  end)
  frame.withdraw = button("Retirer", 90, function(c) ns.ctWithdraw(c) end)
  frame.manual = button("Il a dit oui (sans addon)", 180, function(c)
    -- Il n'a pas l'addon : tu notes son accord. Ton panneau vérifiera tes échanges contre TA copie.
    if c.status == "envoye" then
      c.status, c.signed, c.manual = "signe", GetServerTime(), true
    end
  end)
  frame.readable = button("Envoyer en clair", 130, function(c) readable(c) end)
  frame.actions = { frame.accept, frame.refuse, frame.reply, frame.replyList, frame.send, frame.withdraw, frame.manual, frame.readable }
  frame.accept:SetPoint("BOTTOMLEFT", X0, 12)
  frame.refuse:SetPoint("LEFT", frame.accept, "RIGHT", 6, 0)
  frame.reply:SetPoint("LEFT", frame.refuse, "RIGHT", 6, 0)
  frame.replyList:SetPoint("LEFT", frame.reply, "RIGHT", 6, 0)
  frame.send:SetPoint("BOTTOMLEFT", X0, 12)
  frame.withdraw:SetPoint("BOTTOMLEFT", X0, 12)
  frame.manual:SetPoint("LEFT", frame.withdraw, "RIGHT", 6, 0)

  -- Modifier / contre-proposer : totaux et échéance
  local edit = CreateFrame("Frame", nil, frame)
  edit:SetPoint("BOTTOMLEFT", X0, 44)
  edit:SetSize(W - X0 - 14, 40)
  local function field(label, w, anchor)
    local t = edit:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    if anchor then t:SetPoint("LEFT", anchor, "RIGHT", 14, 0) else t:SetPoint("LEFT", 0, 0) end
    t:SetText(label)
    local e = CreateFrame("EditBox", nil, edit, "InputBoxTemplate")
    e:SetSize(w, 22)
    e:SetPoint("LEFT", t, "RIGHT", 10, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEnterPressed", e.ClearFocus) -- Entrée ne valide rien (P7)
    return e
  end
  edit.caution = field("Caution (po)", 60)
  edit.delivery = field("Livraison (po)", 60, edit.caution)
  edit.days = field("Délai (jours)", 36, edit.delivery)
  edit.go = CreateFrame("Button", nil, edit, "UIPanelButtonTemplate")
  edit.go:SetSize(90, 22)
  edit.go:SetPoint("LEFT", edit.days, "RIGHT", 12, 0)
  edit.go:SetScript("OnClick", function()
    local c = list[pos]
    if not c then return end
    local function copper(e) local n = tonumber((e:GetText():gsub(",", "."))) return n and n >= 0 and math.floor(n * 10000 + 0.5) or nil end
    -- seuls les champs que tu as modifiés changent quelque chose
    local init = edit.initial or {}
    local caution = #c.m > 0 and edit.caution:GetText() ~= init[1] and copper(edit.caution) or nil
    local delivery = edit.delivery:GetText() ~= init[2] and copper(edit.delivery) or nil
    local days = edit.days:GetText() ~= init[3] and tonumber((edit.days:GetText():gsub(",", "."))) or nil
    if not (caution or delivery or days) then return print("Contrats : tu n'as rien modifié.") end
    if days and (days <= 0 or days > 30) then return print("Contrats : échéance entre 0 et 30 jours.") end
    if ns.ctStatus(c) == "brouillon" then ns.ctEditDraft(c, caution, delivery, days)
    else
      local n, err = ns.ctCounter(c, caution, delivery, days) -- un brouillon : sa fiche, puis « Envoyer la proposition »
      if not n then return print("|cffe64d4dContrats :|r " .. err .. ".") end
      return ns.openContracts(ns.ctKey(n))
    end
    refresh()
  end)
  frame.edit = edit
  frame:SetScript("OnShow", refresh)
end

function ns.openContracts(key)
  if not frame then build() end
  frame:Show()
  if key then shownKey = key end
  refresh()
end

SLASH_HANDSHAKECONTRAT1 = "/contrat"
SlashCmdList.HANDSHAKECONTRAT = function() ns.openContracts() end
