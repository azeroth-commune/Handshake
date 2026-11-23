-- Handshake : la commande à la main (#38), sans arbre ni projet. Deux listes d'objets × quantités, « ce que je veux » et
-- « ce que j'apporte », remplies par la recherche d'objets du socle ou par un objet déposé dessus ; l'artisan et l'offre.
-- Elle part par le chemin d'une commande de projet : brouillon de contrat (ns.ctFromDemande), relu et envoyé dans
-- Contrats, ou texte lisible (ns.sendOrder). Côté artisan, une demande reçue se répond dans la même liste : ce qu'il veut
-- en lecture seule, apports et prix modifiables, contre-proposition (ns.ctReplyFromOrder).
-- Ctrl+clic droit n'est jamais pris ici : il appartient à Composants.
local _, ns = ...

---------------------------------------------------------------------------------------------------
-- La commande : HandshakeDB.main = { lines = { { id, qty } }, apporte = { { id, qty } }, player (l'artisan), tip (l'offre,
-- en cuivre), contrat (clé de son contrat une fois préparée) }. Une seule à la fois : « Nouvelle » en recommence une.
function ns.commandeMain()
  HandshakeDB.main = HandshakeDB.main or { lines = {}, apporte = {} }
  return HandshakeDB.main
end

-- « Nouvelle » : un brouillon pas parti s'efface avec elle ; un contrat envoyé reste dans Contrats.
function ns.mainNouvelle()
  local old = HandshakeDB.main
  if old and old.contrat and not ns.commandeEnvoyee(old) then ns.ctStore()[old.contrat] = nil end
  ns.retirerTB(old) -- ses demandes au tableau de Trade Board (Annonce.lua)
  HandshakeDB.main = nil
  return ns.commandeMain()
end

-- La réponse à une demande reçue c, dans la liste : ce qu'il veut (c.o), ses apports (c.m) et le prix actuel. La même
-- version rouverte garde ce que j'ai changé ; une nouvelle version de sa part la refait.
-- ponytail: en mémoire seulement ; après un /reload la réponse repart du contrat, rien de signé n'est perdu
local reponses = {}
function ns.reponseMain(c)
  local key = ns.ctKey(c)
  local r = reponses[key]
  if r and r.hash == c.hash then return r end
  r = { reponse = key, hash = c.hash, player = c.peer and c.peer.name, lines = {}, apporte = {},
    tip = math.max(0, ns.ctTotal(c.o) - ns.ctTotal(c.m)) }
  for _, l in ipairs(c.o) do r.lines[#r.lines + 1] = { id = l.id, qty = l.qty } end
  for _, l in ipairs(c.m) do r.apporte[#r.apporte + 1] = { id = l.id, qty = l.qty } end
  reponses[key] = r
  return r
end

-- Ce qui se modifie : dans une réponse, ce qu'il veut est figé ; une demande envoyée l'est entièrement (elle a son contrat).
function ns.mainPeut(order, liste)
  if order.reponse and liste == "lines" then return false, ns.FIGE end
  if ns.commandeEnvoyee(order) then return false, "demande envoyée : « Nouvelle » pour une autre commande" end
  return true
end

-- Un objet de plus dans une liste (« lines » ou « apporte ») ; déjà dedans, sa quantité s'ajoute.
function ns.mainAjouter(order, liste, id, qty)
  local ok, raison = ns.mainPeut(order, liste)
  if not ok then return false, raison end
  id, qty = tonumber(id), math.floor(tonumber(qty) or 1)
  if not id or qty < 1 then return false, "objet introuvable (nom exact, lien ou ID)" end
  for _, l in ipairs(order[liste]) do
    if l.id == id then l.qty = l.qty + qty return true end
  end
  table.insert(order[liste], { id = id, qty = qty })
  return true
end

-- La quantité de la ligne i ; 0 la retire.
function ns.mainQuantite(order, liste, i, qty)
  local ok, raison = ns.mainPeut(order, liste)
  if not ok then return false, raison end
  qty = math.floor(tonumber(qty) or 0)
  if not order[liste][i] then return false end
  if qty < 1 then table.remove(order[liste], i) else order[liste][i].qty = qty end
  return true
end

-- « Préparer la demande » : la commande en brouillon de contrat (moi client), refait tant qu'il n'est pas parti ; déjà
-- envoyée, son contrat, inchangé. Renvoie le contrat, ou nil, raison.
function ns.mainPreparer(order)
  local sent = ns.commandeEnvoyee(order)
  if sent then return sent end
  local ct, err = ns.ctFromDemande(order, 3)
  if not ct then return nil, err end
  if order.contrat then ns.ctStore()[order.contrat] = nil end -- l'ancien brouillon
  ct.status, order.contrat = "brouillon", ns.ctKey(ct)
  ns.ctStore()[order.contrat] = ct
  return ct
end

---------------------------------------------------------------------------------------------------
-- Un objet pris dans les sacs (au curseur) et déposé sur f : il est rendu à son sac et onObjet(id) le reçoit.
function ns.recevoirObjet(f, onObjet)
  local function depose()
    local kind, id = GetCursorInfo()
    if kind ~= "item" then return end
    ClearCursor()
    onObjet(id)
  end
  f:EnableMouse(true)
  f:SetScript("OnReceiveDrag", depose)
  f:HookScript("OnMouseUp", depose)
end

---------------------------------------------------------------------------------------------------
-- Barre de recherche avec suggestions (la recherche d'objets du socle, AzerothCommune#49) : flèches haut/bas, Entrée ou
-- Tab pour choisir, ou clic ; un objet déposé sur le champ l'ajoute aussitôt. onPick(id, quantité).
-- Maj+clic n'est pas pris : dans le jeu, il sépare une pile ou colle le lien dans la discussion.
-- (Composants en a sa copie pour sa fenêtre des projets.) w = largeur du champ (280 par défaut).
function ns.rechercheObjets(parent, qty, onPick, w)
  w = w or 280
  local name = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  name:SetSize(w, 22)
  name:SetAutoFocus(false)
  name.recherche = true
  local drop = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  drop:SetPoint("TOPLEFT", name, "BOTTOMLEFT", -6, -2)
  drop:SetSize(w + 40, 10)
  drop:SetFrameStrata("DIALOG")
  drop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  drop:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
  drop:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.35)
  drop:Hide()
  local buttons, hits, sel = {}, {}, 1
  local function qtyValue() return math.max(1, tonumber(qty:GetText()) or 1) end
  local function pick(e)
    onPick(e.id, qtyValue())
    name:SetText("")
    name:ClearFocus()
    drop:Hide()
  end
  local function paint()
    for i, b in ipairs(buttons) do b.hl:SetShown(i == sel) end
  end
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, drop)
    b:SetSize(w + 36, 20)
    b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 20)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(0.66, 0.56, 1.00, 0.18)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 4, 0)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 24, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnEnter", function() sel = i; paint() end)
    b:SetScript("OnClick", function() if hits[i] then pick(hits[i]) end end)
    buttons[i] = b
  end
  local function update()
    hits, sel = ns.chercherObjets(name:GetText(), 8), 1
    for i, b in ipairs(buttons) do
      local e = hits[i]
      b:SetShown(e ~= nil)
      if e then
        b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
        b.text:SetText(e.name .. (e.fabricable and "  |cffe6a640fabricable|r" or ""))
      end
    end
    drop:SetHeight(4 + 20 * #hits)
    drop:SetShown(#hits > 0)
    paint()
  end
  local function submit()
    if drop:IsShown() and hits[sel] then return pick(hits[sel]) end
    local id = ns.findItem(name:GetText() or "")
    if not id then return print("Handshake : objet introuvable (nom exact, lien ou ID).") end
    pick({ id = id })
  end
  name:SetScript("OnTextChanged", function(_, userInput) if userInput then update() end end)
  name:SetScript("OnEditFocusLost", function() C_Timer.After(0.2, function() drop:Hide() end) end) -- laisse passer le clic
  name:SetScript("OnEscapePressed", function(self) drop:Hide(); self:ClearFocus() end)
  name:SetScript("OnEnterPressed", submit)
  name:SetScript("OnTabPressed", function() if hits[sel] then pick(hits[sel]) end end)
  name:SetScript("OnArrowPressed", function(_, key)
    if not drop:IsShown() then return end
    if key == "DOWN" then sel = math.min(#hits, sel + 1) elseif key == "UP" then sel = math.max(1, sel - 1) end
    paint()
  end)
  qty:SetScript("OnEnterPressed", submit)
  ns.recevoirObjet(name, function(id) onPick(id, qtyValue()) end)
  return name, submit
end

---------------------------------------------------------------------------------------------------
-- La fenêtre (/handshake liste ; « Répondre en liste » dans Contrats) : l'artisan et l'offre en haut, les deux
-- listes côte à côte, l'état de la demande et les boutons en bas.
local W, ROW, ROWS = 580, 24, 10
local frame, reponse -- reponse : la clé du contrat auquel on répond (nil = ma commande à la main)
local function order()
  local c = reponse and ns.ctStore()[reponse]
  return c and ns.reponseMain(c) or ns.commandeMain()
end
local function say(err) if err then print("|cffe64d4dCommandes :|r " .. err .. ".") end end
local refresh

local function build()
  frame = ns.newWindow("HandshakeMainFrame", "Commande à la main", W, 150 + ROWS * ROW + 70)
  local function button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end
  local function input(w, numeric)
    local e = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    e:SetSize(w, 22)
    e:SetAutoFocus(false)
    e:SetNumeric(numeric or false)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
  end
  local function text(font, ...)
    local t = frame:CreateFontString(nil, "OVERLAY", font)
    t:SetPoint(...)
    return t
  end

  -- L'artisan (le demandeur, dans une réponse : le nom donné par le serveur, figé) et l'offre (mon prix).
  frame.whoL = text("GameFontHighlightSmall", "TOPLEFT", 14, -50)
  frame.who = input(170)
  frame.who:SetPoint("LEFT", frame.whoL, "RIGHT", 10, 0)
  frame.who:SetScript("OnTextChanged", function(self, user)
    if user then order().player = self:GetText() ~= "" and self:GetText() or nil end
  end)
  frame.tipL = text("GameFontHighlightSmall", "LEFT", frame.who, "RIGHT", 18, 0)
  frame.tip = input(60)
  frame.tip:SetPoint("LEFT", frame.tipL, "RIGHT", 10, 0)
  frame.tip:SetScript("OnTextChanged", function(self, user)
    if not user then return end
    local n = tonumber((self:GetText():gsub(",", ".")))
    order().tip = n and n >= 0 and math.floor(n * 10000 + 0.5) or nil
  end)
  text("GameFontHighlightSmall", "LEFT", frame.tip, "RIGHT", 4, 0):SetText("po")

  -- Les deux listes : un titre, une recherche (quantité, « Ajouter »), puis une ligne par objet (quantité, « × » retire).
  frame.cols = {}
  for k, liste in ipairs({ "lines", "apporte" }) do
    local x = 14 + (k - 1) * (W / 2)
    local col = { liste = liste, rows = {} }
    -- La colonne entière reçoit un objet déposé (sous la recherche et les lignes, qui restent cliquables).
    col.depot = CreateFrame("Frame", nil, frame)
    col.depot:SetPoint("TOPLEFT", x - 4, -80)
    col.depot:SetSize(W / 2 - 16, 64 + ROWS * ROW)
    col.depot:SetFrameLevel(frame:GetFrameLevel() + 1)
    col.title = text("GameFontNormal", "TOPLEFT", x, -86)
    col.qty = input(32, true)
    col.qty:SetText("1")
    col.search = ns.rechercheObjets(frame, col.qty, function(id, q)
      local ok, err = ns.mainAjouter(order(), liste, id, q)
      if not ok then say(err) end
      refresh()
    end, 150)
    col.search:SetPoint("TOPLEFT", x + 6, -106)
    col.qty:SetPoint("LEFT", col.search, "RIGHT", 8, 0)
    col.add = button(frame, "Ajouter", 60, function() col.search:GetScript("OnEnterPressed")(col.search) end)
    col.add:SetPoint("LEFT", col.qty, "RIGHT", 6, 0)
    ns.recevoirObjet(col.depot, function(id)
      local ok, err = ns.mainAjouter(order(), liste, id, math.max(1, tonumber(col.qty:GetText()) or 1))
      if not ok then say(err) end
      refresh()
    end)
    for _, f in ipairs({ col.search, col.qty, col.add }) do f:SetFrameLevel(col.depot:GetFrameLevel() + 2) end
    for i = 1, ROWS do
      local r = CreateFrame("Frame", nil, frame)
      r:SetSize(W / 2 - 24, ROW)
      r:SetPoint("TOPLEFT", x, -136 - (i - 1) * ROW)
      r:SetFrameLevel(col.depot:GetFrameLevel() + 2)
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(18, 18)
      r.icon:SetPoint("LEFT", 0, 0)
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.name:SetPoint("LEFT", 24, 0)
      r.name:SetWidth(W / 2 - 110)
      r.name:SetJustifyH("LEFT")
      r.name:SetWordWrap(false)
      r.qty = CreateFrame("EditBox", nil, r, "InputBoxTemplate")
      r.qty:SetSize(36, 20)
      r.qty:SetPoint("RIGHT", -28, 0)
      r.qty:SetAutoFocus(false)
      r.qty:SetNumeric(true)
      r.qty.liste = liste
      r.qty:SetScript("OnEnterPressed", r.qty.ClearFocus)
      r.qty:SetScript("OnTextChanged", function(self, user)
        local n = tonumber(self:GetText())
        if user and n and n >= 1 then say(select(2, ns.mainQuantite(order(), liste, r.i, n))) end
      end)
      r.del = button(r, "×", 22, function()
        say(select(2, ns.mainQuantite(order(), liste, r.i, 0)))
        refresh()
      end)
      r.del:SetPoint("RIGHT", 0, 0)
      col.rows[i] = r
    end
    col.more = text("GameFontDisableSmall", "TOPLEFT", x, -136 - ROWS * ROW)
    frame.cols[k] = col
  end

  frame.status = text("GameFontHighlightSmall", "BOTTOMLEFT", 14, 44)
  frame.status:SetWidth(W - 28)
  frame.status:SetJustifyH("LEFT")
  text("GameFontDisableSmall", "BOTTOMRIGHT", -14, 62):SetText("Glisse un objet de tes sacs sur une liste : il y entre")
  frame.go = button(frame, "Préparer la demande", 160, function()
    local o = order()
    if o.reponse then
      local n, err = ns.ctReplyFromOrder(o)
      if not n then return say(err) end
      return ns.openContracts(ns.ctKey(n))
    end
    local ct, err = ns.mainPreparer(o)
    if not ct then return say(err) end
    refresh()
    ns.openContracts(ns.ctKey(ct))
  end)
  frame.go:SetPoint("BOTTOMLEFT", 14, 12)
  frame.clair = button(frame, "En clair", 90, function()
    local o = order()
    if #o.lines == 0 then return say("rien à envoyer") end
    ns.sendOrder(o)
  end)
  frame.clair:SetPoint("LEFT", frame.go, "RIGHT", 6, 0)
  frame.nouvelle = button(frame, "Nouvelle", 90, function() ns.mainNouvelle(); refresh() end)
  frame.nouvelle:SetPoint("LEFT", frame.clair, "RIGHT", 6, 0)
  -- « Annoncer » : l'Annonce dans le Commerce (Annonce.lua) ; le bouton dit s'il peut partir, et sinon pourquoi ou quand.
  frame.annonce = button(frame, "Annoncer", 170, function()
    local o = order()
    say(select(2, ns.annoncer(o, nil, o)))
    refresh()
  end)
  frame.annonce:SetPoint("LEFT", frame.nouvelle, "RIGHT", 6, 0)
  ns.onglets(frame, 1) -- et l'onglet « Annonces lues » (Annonce.lua)
  frame:SetScript("OnShow", function() refresh() end)
  frame:RegisterEvent("ITEM_DATA_LOAD_RESULT") -- un nom d'objet arrive du serveur
  frame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE") -- un canal rejoint ou quitté : le Commerce, pour « Annoncer »
  frame:SetScript("OnEvent", function() refresh() end)
end

function refresh()
  if not (frame and frame:IsShown()) then return end
  local o = order()
  local c = o.reponse and ns.ctStore()[o.reponse]
  local client = o.player and o.player:match("^%S+") or "?"
  frame.title:SetText(c and ("Réponse à " .. client) or "Commande à la main")
  frame.whoL:SetText(c and "Demandeur" or "Artisan")
  frame.tipL:SetText(c and "Mon prix" or "Offre")
  if not frame.who:HasFocus() then frame.who:SetText(o.player or "") end
  if not frame.tip:HasFocus() then frame.tip:SetText(o.tip and o.tip > 0 and (ns.poText(o.tip):gsub(" po$", "")) or "") end
  local libre = ns.mainPeut(o, "apporte")
  frame.who:SetEnabled(not c and libre)
  frame.tip:SetEnabled(libre and true or false)
  local titres = c and { "Ce qu'il veut (sa demande)", "Ce qu'il apporte" } or { "Ce que je veux", "Ce que j'apporte" }
  for k, col in ipairs(frame.cols) do
    local peut = ns.mainPeut(o, col.liste)
    col.title:SetText(titres[k])
    col.search:SetShown(peut); col.qty:SetShown(peut); col.add:SetShown(peut)
    local list = o[col.liste]
    for i, r in ipairs(col.rows) do
      local l = list[i]
      r:SetShown(l ~= nil)
      if l then
        r.i = i
        r.icon:SetTexture(C_Item.GetItemIconByID(l.id))
        local inconnu = col.liste == "lines" and not ns.prixAchatLigne(l.id, l.qty)
        r.name:SetText(ns.itemLabel(l.id) .. (inconnu and "  |cff999999prix inconnu|r" or ""))
        if not r.qty:HasFocus() then r.qty:SetText(tostring(l.qty)) end
        r.qty:SetEnabled(peut and true or false)
        r.del:SetShown(peut)
      end
    end
    -- ponytail: 10 lignes affichées (le contrat en prend 30) ; un défilement le jour où une commande les dépasse
    col.more:SetText(#list > ROWS and ("… et %d autre(s)"):format(#list - ROWS) or (#list == 0 and "(vide)" or ""))
  end
  if c then
    frame.status:SetText(ns.ctStatus(c) == "a_signer" and ("Sa demande, v%s : ajoute ou retire des apports, fixe ton prix, puis contre-propose."):format(c.v)
      or "Ce contrat n'attend plus ta réponse : vois-le dans Contrats.")
  else
    local ct = o.contrat and ns.ctStore()[o.contrat]
    frame.status:SetText(not ct and "Pas encore préparée."
      or ct.status == "brouillon" and "Brouillon dans Contrats : relis-le, puis « Envoyer la proposition »."
      or ("Demande : %s. « Nouvelle » pour une autre commande."):format(ns.etatDemande(ct)))
  end
  frame.go:SetText(c and "Contre-proposer" or ns.commandeEnvoyee(o) and "Voir la demande" or "Préparer la demande")
  frame.clair:SetShown(not c)
  frame.nouvelle:SetShown(not c)
  frame.annonce:SetShown(not c)
  local texte, peut, quand = ns.annonceEtiquette(o)
  frame.annonce:SetText(texte)
  frame.annonce:SetEnabled(peut)
  if quand and frame.minuteur ~= quand then -- « Annoncer à 14:32 » : le bouton se réarme tout seul à l'heure dite
    frame.minuteur = quand
    C_Timer.After(quand - GetTime() + 0.1, refresh)
  end
end
ns.refreshCommandeMain = refresh

-- Ma commande à la main, ou (c, un contrat à signer dont je suis l'artisan) ma réponse à cette demande.
function ns.openCommandeMain(c)
  if not frame then build() end
  reponse = c and ns.ctKey(c) or nil
  frame:Show()
  refresh()
end
