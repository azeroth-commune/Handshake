-- Handshake, la fenêtre des contrats (/contrat). Un contrat à la fois : qui donne quoi à chaque étape,
-- ce qui a changé depuis la version d'avant, TON estimation de la caution et ta perte maximale (P8), les
-- vérifications (objets liés, besoins plus gros que les recettes, nom proche d'un autre), l'avancement.
-- Accepter : jamais par Entrée ni fenêtre surgissante, bouton réarmé 2 s après l'affichage d'une version (P7).
-- « Préparer la demande » dans la fenêtre des projets crée un brouillon depuis la commande (ns.projetEnvoyer) : rien ne
-- part avant « Envoyer ».
local _, ns = ...

local W, H = 620, 600
local frame, list, pos, shownHash = nil, {}, 1, nil
local firstShown = {} -- empreinte -> moment où cette version a été affichée pour la première fois (réarmement)
local STATUS = { brouillon = "|cff999999BROUILLON (pas envoyé)|r", envoye = "|cffe6994dEN ATTENTE DE SA RÉPONSE|r",
  a_signer = "|cffa98fffÀ SIGNER PAR TOI|r", signe = "|cff59cc73SIGNÉ|r", clos = "|cff59cc73CLOS|r", echu = "|cffe64d4dÉCHU|r",
  refuse = "|cffe64d4dREFUSÉ|r", retire = "|cff999999RETIRÉ|r" }
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
  local other, artisan = ns.other(c, me), me == c.artisan
  local add = function(s) t[#t + 1] = s end
  local caution, delivery = ns.ctTotal(c.m), ns.ctTotal(c.o)
  local peer = c.peer or {}
  add(("|cffffd100Contrat avec %s|r"):format(ns.identity(other, peer.guid, peer.surname)))
  add(("Toi : %s   ·   v%s   ·   empreinte %s"):format(ns.myIdentity(), c.v, (c.hash or "—"):sub(1, 8)))
  add((STATUS[status] or status) .. ("   ·   tu es %s   ·   échéance %s"):format(artisan and "l'ARTISAN" or "le CLIENT", rel(c.d - GetServerTime())))
  add(peer.verified and ("Identité de %s : |cff59cc73confirmée|r (identifiant %s)"):format(other, peer.guid)
    or peer.guid and ("Identité de %s : |cffe6994dannoncée, à confirmer au premier échange|r (identifiant %s)"):format(other, peer.guid)
    or ("Identité de %s : |cffe6994dinconnue, fixée au premier échange|r"):format(other))
  for _, x in pairs(ns.ctStore()) do -- n° 26 : nom presque identique à un autre partenaire
    local o2 = ns.other(x, me)
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
  local otherShort = other:match("^[^%-]+")
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
    add(artisan and "   |cffe6994d! Aucun prix pour ton travail : « Répondre dans l'arbre » pour chiffrer ta part.|r"
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
  if c.unsaved then add("|cffe6994d! Pas encore enregistré sur le disque : « Sauvegarder » (/reload).|r") end
  return table.concat(t, "\n")
end

---------------------------------------------------------------------------------------------------
local function sorted()
  local l = {}
  for _, c in pairs(ns.ctStore()) do l[#l + 1] = c end
  table.sort(l, function(a, b)
    local oa, ob = ORDER[ns.ctStatus(a)] or 9, ORDER[ns.ctStatus(b)] or 9
    if oa ~= ob then return oa < ob end
    return (a.received or tonumber(a.id) or 0) > (b.received or tonumber(b.id) or 0)
  end)
  return l
end

local function refresh()
  if ns.syncCommandes then ns.syncCommandes() end -- l'état des commandes se lit dans leur contrat
  if not (frame and frame:IsShown()) then return end
  list = sorted()
  pos = math.min(math.max(1, pos), math.max(1, #list))
  local c, me = list[pos], ns.me()
  frame.count:SetText(#list > 0 and ("%d/%d"):format(pos, #list) or "")
  local unsaved = false
  for _, x in ipairs(list) do if x.unsaved then unsaved = true end end
  frame.save:SetShown(unsaved)
  for _, b in ipairs(frame.actions) do b:Hide() end
  frame.edit:SetShown(false)
  if not c then
    frame.body:SetText("|cff999999Aucun contrat. Dans la fenêtre des commandes, « Préparer la demande » en fait un depuis la commande affichée.|r")
    frame.content:SetHeight(frame.body:GetStringHeight() + 10)
    return
  end
  frame.body:SetText(ns.ctDescribe(c, me))
  frame.content:SetHeight(frame.body:GetStringHeight() + 10)
  local status = ns.ctStatus(c)
  local function show(b) b:Show() end
  if status == "a_signer" then
    show(frame.accept); show(frame.refuse)
    if c.artisan == me then show(frame.reply) end
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
    frame.edit.go:SetText(status == "brouillon" and "Modifier" or "Contre-proposer")
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
  local me = ns.me()
  local other = ns.other(c, me)
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
    b:SetScript("OnClick", function() local c = list[pos]; if c then onClick(c) end; refresh() end)
    return b
  end
  local prev = button("<", 24, function() pos = pos - 1 end)
  prev:SetPoint("TOPLEFT", 120, -10)
  local nxt = button(">", 24, function() pos = pos + 1 end)
  nxt:SetPoint("LEFT", prev, "RIGHT", 4, 0)
  frame.count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.count:SetPoint("LEFT", nxt, "RIGHT", 6, 0)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -40)
  scroll:SetPoint("BOTTOMRIGHT", -32, 96)
  frame.content = CreateFrame("Frame", nil, scroll)
  frame.content:SetSize(W - 50, 1)
  scroll:SetScrollChild(frame.content)
  frame.body = frame.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.body:SetPoint("TOPLEFT")
  frame.body:SetWidth(W - 56)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetSpacing(3)

  -- Actions (bas de la fenêtre)
  frame.accept = button("Signer", 110, function(c) if not ns.ctAccept(c, shownHash) then print("Contrats : la version affichée a changé, relis-la.") end end)
  frame.refuse = button("Refuser", 90, function(c) ns.ctRefuse(c) end)
  frame.reply = button("Répondre dans l'arbre", 160, function(c) ns.projetReponse(c); ns.openCraftWindow() end)
  frame.send = button("Envoyer la proposition", 170, function(c)
    local ok, err = ns.ctPropose(c)
    if not ok then print("|cffe64d4dContrats :|r " .. err .. ".") end
  end)
  frame.withdraw = button("Retirer", 90, function(c) ns.ctWithdraw(c) end)
  frame.manual = button("Il a dit oui (sans addon)", 180, function(c)
    -- Il n'a pas l'addon : tu notes son accord. Ton panneau vérifiera tes échanges contre TA copie.
    if c.status == "envoye" then
      c.status, c.signed, c.manual = "signe", GetServerTime(), true
      local known = ns.knownGUID[ns.other(c, ns.me())]
      if known and not c.peer then c.peer = { guid = known, verified = true } end
    end
  end)
  frame.readable = button("Envoyer en clair", 130, function(c) readable(c) end)
  frame.actions = { frame.accept, frame.refuse, frame.reply, frame.send, frame.withdraw, frame.manual, frame.readable }
  frame.accept:SetPoint("BOTTOMLEFT", 14, 12)
  frame.refuse:SetPoint("LEFT", frame.accept, "RIGHT", 6, 0)
  frame.reply:SetPoint("LEFT", frame.refuse, "RIGHT", 6, 0)
  frame.send:SetPoint("BOTTOMLEFT", 14, 12)
  frame.withdraw:SetPoint("BOTTOMLEFT", 14, 12)
  frame.manual:SetPoint("LEFT", frame.withdraw, "RIGHT", 6, 0)
  frame.save = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.save:SetSize(110, 22)
  frame.save:SetPoint("BOTTOMRIGHT", -14, 12)
  frame.save:SetText("Sauvegarder")
  frame.save:SetScript("OnClick", ReloadUI)

  -- Modifier / contre-proposer : totaux et échéance
  local edit = CreateFrame("Frame", nil, frame)
  edit:SetPoint("BOTTOMLEFT", 14, 44)
  edit:SetSize(W - 28, 40)
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
  edit.delivery = field("À la livraison (po)", 60, edit.caution)
  edit.days = field("Échéance (jours)", 36, edit.delivery)
  edit.go = CreateFrame("Button", nil, edit, "UIPanelButtonTemplate")
  edit.go:SetSize(130, 22)
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
      local ok, err = ns.ctCounter(c, caution, delivery, days)
      if not ok then print("|cffe64d4dContrats :|r " .. err .. ".") end
    end
    refresh()
  end)
  frame.edit = edit
  frame:SetScript("OnShow", refresh)
end

function ns.openContracts(key)
  if not frame then build() end
  frame:Show()
  if key then
    list = sorted()
    for i, c in ipairs(list) do if ns.ctKey(c) == key then pos = i end end
  end
  refresh()
end

SLASH_HANDSHAKECONTRAT1 = "/contrat"
SlashCmdList.HANDSHAKECONTRAT = function() ns.openContracts() end
