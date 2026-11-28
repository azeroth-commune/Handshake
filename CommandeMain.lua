-- Handshake : la commande à la main (#38), sans arbre ni projet. Deux listes d'objets × quantités, « ce que je veux » et
-- « ce que j'apporte », remplies par la recherche d'objets du socle ou par un objet déposé dessus ; l'artisan et l'offre.
-- Elle part par le chemin d'une commande de projet : brouillon de contrat (ns.ctFromDemande), relu et envoyé dans
-- Contrats (« Envoyer » : par Handshake s'il l'a, sinon en clair, #71). Côté artisan, une demande reçue se répond dans la même liste : ce qu'il veut
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
-- La fenêtre (/handshake liste ; « Répondre » dans Contrats, sans Composants) : l'artisan et l'offre en haut, les deux
-- listes côte à côte, l'état de la demande et les boutons en bas.
local W, ROW, ROWS = 580, 24, 4 -- taille de départ et minimum : 4 lignes par colonne ; plus, on agrandit
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
  -- Chaque colonne prend la moitié de la largeur ; agrandie, la fenêtre montre plus de lignes (refresh, OnSizeChanged).
  frame.cols = {}
  for k, liste in ipairs({ "lines", "apporte" }) do
    local col = { liste = liste, rows = {} }
    -- La colonne entière reçoit un objet déposé (sous la recherche et les lignes, qui restent cliquables).
    col.depot = CreateFrame("Frame", nil, frame)
    col.depot:SetPoint("TOPLEFT", frame, k == 1 and "TOPLEFT" or "TOP", k == 1 and 10 or 4, -80)
    col.depot:SetPoint("BOTTOMRIGHT", frame, k == 1 and "BOTTOM" or "BOTTOMRIGHT", -12, 70)
    col.depot:SetFrameLevel(frame:GetFrameLevel() + 1)
    col.title = text("GameFontNormal", "TOPLEFT", col.depot, "TOPLEFT", 4, -6)
    col.qty = input(32, true)
    col.qty:SetText("1")
    col.search = AzerothCommune.RechercheObjets(frame, col.qty, function(id, q)
      local ok, err = ns.mainAjouter(order(), liste, id, q)
      if not ok then say(err) end
      refresh()
    end, 150)
    col.search:SetPoint("TOPLEFT", col.depot, "TOPLEFT", 10, -26)
    col.qty:SetPoint("LEFT", col.search, "RIGHT", 8, 0)
    col.add = button(frame, "Ajouter", 60, function() col.search:GetScript("OnEnterPressed")(col.search) end)
    col.add:SetPoint("LEFT", col.qty, "RIGHT", 6, 0)
    AzerothCommune.RecevoirObjet(col.depot, function(id)
      local ok, err = ns.mainAjouter(order(), liste, id, math.max(1, tonumber(col.qty:GetText()) or 1))
      if not ok then say(err) end
      refresh()
    end)
    for _, f in ipairs({ col.search, col.qty, col.add }) do f:SetFrameLevel(col.depot:GetFrameLevel() + 2) end
    -- La ligne i, faite la première fois qu'elle tient dans la colonne ; elle suit sa largeur.
    function col.ligne(i)
      if col.rows[i] then return col.rows[i] end
      local r = CreateFrame("Frame", nil, frame)
      r:SetHeight(ROW)
      r:SetPoint("TOPLEFT", col.depot, "TOPLEFT", 4, -56 - (i - 1) * ROW)
      r:SetPoint("RIGHT", col.depot, "RIGHT", -4, 0)
      r:SetFrameLevel(col.depot:GetFrameLevel() + 2)
      r.icon = r:CreateTexture(nil, "ARTWORK")
      r.icon:SetSize(18, 18)
      r.icon:SetPoint("LEFT", 0, 0)
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
      r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      r.name:SetPoint("LEFT", 24, 0)
      r.name:SetPoint("RIGHT", r.qty, "LEFT", -10, 0)
      r.name:SetJustifyH("LEFT")
      r.name:SetWordWrap(false)
      r.del = button(r, "×", 22, function()
        say(select(2, ns.mainQuantite(order(), liste, r.i, 0)))
        refresh()
      end)
      r.del:SetPoint("RIGHT", 0, 0)
      col.rows[i] = r
      return r
    end
    col.more = col.depot:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall") -- sous la dernière ligne qui tient (refresh)
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
  frame.nouvelle = button(frame, "Nouvelle", 90, function() ns.mainNouvelle(); refresh() end)
  frame.nouvelle:SetPoint("LEFT", frame.go, "RIGHT", 6, 0)
  -- « Annoncer » : l'Annonce dans le Commerce (Annonce.lua) ; le bouton dit s'il peut partir, et sinon pourquoi ou quand.
  frame.annonce = button(frame, "Annoncer", 170, function()
    local o = order()
    say(select(2, ns.annoncer(o, nil, o)))
    refresh()
  end)
  frame.annonce:SetPoint("LEFT", frame.nouvelle, "RIGHT", 6, 0)
  -- Ce qui sert rarement (skill ui-addon : 3 ou 4 boutons au plus) : dans « Plus ». Importer une liste reçue (en
  -- chuchotement, ou collée) : un projet de Composants commandé en entier, ou, sans lui, cette commande à la main.
  frame.plus = CreateFrame("DropdownButton", nil, frame, "WowStyle1DropdownTemplate")
  frame.plus:SetWidth(90)
  frame.plus:OverrideText("Plus")
  frame.plus:SetPoint("LEFT", frame.annonce, "RIGHT", 6, 0)
  frame.plus:SetupMenu(function(_, root)
    root:CreateButton("Importer une liste reçue", function() ns.openImport() end)
  end)
  ns.onglets(frame, 1) -- et l'onglet « Annonces lues » (Annonce.lua)
  frame:SetScript("OnShow", function() refresh() end)
  frame:SetScript("OnSizeChanged", function() refresh() end) -- agrandie : plus de lignes
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
    local tient = math.floor((col.depot:GetHeight() - 56 - 14) / ROW) -- les lignes qui tiennent, « … et N autre(s) » dessous
    col.more:SetPoint("TOPLEFT", col.depot, "TOPLEFT", 4, -56 - tient * ROW)
    for i = 1, math.max(#col.rows, math.min(#list, tient)) do
      local l = i <= tient and list[i] or nil
      local r = col.ligne(i)
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
    -- ponytail: les lignes qui tiennent (10 à la taille de départ ; le contrat en prend 30) ; un défilement si ça gêne
    col.more:SetText(#list > tient and ("… et %d autre(s)"):format(#list - tient) or (#list == 0 and "(vide)" or ""))
  end
  if c then
    frame.status:SetText(ns.ctStatus(c) == "a_signer" and ("Sa demande, v%s : ajoute ou retire des apports, fixe ton prix, puis contre-propose."):format(c.v)
      or "Ce contrat n'attend plus ta réponse : vois-le dans Contrats.")
  else
    local ct = o.contrat and ns.ctStore()[o.contrat]
    frame.status:SetText(not ct and "Pas encore préparée."
      or ct.status == "brouillon" and "Brouillon dans Contrats : relis-le, puis « Envoyer »."
      or ("Contrat %s. « Nouvelle » pour une autre commande."):format(ns.etatDemande(ct)))
  end
  frame.go:SetText(c and "Préparer la réponse…" or ns.commandeEnvoyee(o) and "Voir la demande" or "Préparer la demande")
  frame.nouvelle:SetShown(not c)
  frame.annonce:SetShown(not c)
  frame.plus:ClearAllPoints()
  frame.plus:SetPoint("LEFT", c and frame.go or frame.annonce, "RIGHT", 6, 0)
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
