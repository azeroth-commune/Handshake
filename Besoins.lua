-- Handshake, la liste des besoins de la commande affichée : une petite fenêtre à garder ouverte
-- pendant qu'on rassemble. Chaque ligne avance quand l'objet arrive dans les sacs (ou la banque, les autres persos,
-- selon les options) ; coche verte quand c'est complet. En dessous, les recettes pas encore apprises.
-- « Envoyer » chuchote la liste au joueur de la commande (même format qu'une commande).
-- HV ouvert : clic sur une ligne = la chercher à l'HV.
local _, ns = ...

local W, ROW = 380, 28
local COLORS = { { 0.35, 0.80, 0.45 }, { 0.35, 0.60, 1.00 }, { 0.66, 0.56, 1.00 } }
local READY = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local frame, rows, used = nil, {}, 0

-- Met le nom dans la recherche de l'HV et la lance. On ne change jamais d'onglet nous-mêmes : un onglet ouvert
-- par un addon bloque ensuite les clics du jeu (vu chez Mastercraft) ; hors de l'onglet Acheter, le nom attend.
local function ahSearch(id)
  local ah = AuctionHouseFrame
  local bar = ah and ah:IsShown() and ah.SearchBar
  if not bar then return print("Commandes : ouvre l'hôtel des ventes, puis clique sur la ligne.") end
  local it = ns.items()[id]
  local name = (it and it.name) or C_Item.GetItemInfo(id)
  if not name then return end
  bar:SetSearchText(name)
  if ah.GetDisplayMode and AuctionHouseFrameDisplayMode and ah:GetDisplayMode() ~= AuctionHouseFrameDisplayMode.Buy then
    return print("Commandes : « " .. name .. " » est dans la recherche ; reviens sur l'onglet Acheter et lance-la.")
  end
  bar:StartSearch()
end

local function newRow()
  local r = CreateFrame("Button", nil, frame)
  r:SetSize(W - 28, ROW)
  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(20, 20)
  r.icon:SetPoint("TOPLEFT", 0, -2)
  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.text:SetPoint("TOPLEFT", 26, -4)
  r.text:SetPoint("RIGHT", -90, 0)
  r.text:SetJustifyH("LEFT")
  r.text:SetWordWrap(false)
  r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  r.count:SetPoint("TOPRIGHT", 0, -4)
  r.bg = r:CreateTexture(nil, "ARTWORK")
  r.bg:SetColorTexture(1, 1, 1, 0.08)
  r.bg:SetPoint("BOTTOMLEFT", 26, 4)
  r.bg:SetSize(W - 54, 4)
  r.seg = {}
  for i = 1, 4 do r.seg[i] = r:CreateTexture(nil, "OVERLAY") end
  r:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    if self.info then GameTooltip:AddLine(self.info, 0.8, 0.8, 0.8, true) end
    if AuctionHouseFrame and AuctionHouseFrame:IsShown() then GameTooltip:AddLine("Clic : chercher à l'HV", 0.66, 0.56, 1) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", function() GameTooltip:Hide() end)
  r:SetScript("OnClick", function(self) if self.itemID then ahSearch(self.itemID) end end)
  return r
end

local function line(icon, text, count, itemID, info, have, required, missingColor)
  used = used + 1
  local r = rows[used] or newRow()
  rows[used] = r
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", 14, -frame.y)
  r.icon:SetTexture(icon)
  r.icon:SetShown(icon ~= nil)
  r.text:SetText(text)
  r.count:SetText(count or "")
  r.itemID, r.info = itemID, info
  local left, wmax = 26, W - 54
  local parts = have and { have[1], have[2], have[3], math.max(0, required - have[1] - have[2] - have[3]) } or {}
  r.bg:SetShown(have ~= nil)
  for i = 1, 4 do
    local wpx = have and required > 0 and wmax * parts[i] / required or 0
    local seg = r.seg[i]
    if wpx >= 1 then
      local c = COLORS[i] or missingColor
      seg:SetColorTexture(c[1], c[2], c[3], 0.9)
      seg:ClearAllPoints()
      seg:SetPoint("BOTTOMLEFT", left, 4)
      seg:SetSize(wpx, 4)
      seg:Show()
      left = left + wpx
    else
      seg:Hide()
    end
  end
  r:Show()
  frame.y = frame.y + ROW
end

local function title(text)
  used = used + 1
  local r = rows[used] or newRow()
  rows[used] = r
  r:ClearAllPoints()
  r:SetPoint("TOPLEFT", 14, -frame.y)
  r.icon:Hide(); r.bg:Hide()
  for i = 1, 4 do r.seg[i]:Hide() end
  r.text:SetText("|cffffd100" .. text .. "|r")
  r.count:SetText("")
  r.itemID = nil
  r:Show()
  frame.y = frame.y + 22
end

function ns.refreshNeeds(res)
  if not (frame and frame:IsShown()) then return end
  local order = ns.currentOrder()
  res = res or ns.computeOrder(order)
  local list, recipes = ns.orderNeeds(res)
  used, frame.y = 0, 40
  frame.head:SetText((order.name or "Commande") .. (order.player and (" · " .. order.player) or ""))

  title("À rassembler")
  local done, buy = 0, 0
  for _, r in ipairs(list) do
    local have = r.have[1] + r.have[2] + r.have[3]
    local complete = r.need == 0
    if complete then done = done + 1 end
    local count = complete and (READY .. " " .. r.required) or ("%d/%d"):format(have, r.required)
    if not complete then
      count = (r.unpriced and "|cffe64d4dsans prix|r  " or (ns.moneyShort(r.cost) .. "  ")) .. count
      buy = buy + (r.cost or 0)
    end
    local info = ("Il en faut %d : %d sacs, %d banque, %d autres persos"):format(r.required, r.have[1], r.have[2], r.have[3])
    if r.need > 0 then info = info .. (r.unpriced and "\nNi prix ni recette" or ("\nReste %d à %s"):format(r.need, r.how == "marchand" and "acheter au marchand" or "acheter à l'HV")) end
    line(C_Item.GetItemIconByID(r.id), ns.itemLabel(r.id), count, r.id, info, r.have, r.required, r.unpriced and { 0.9, 0.3, 0.3 } or { 0.6, 0.6, 0.62 })
  end
  if #list == 0 then title("|cff999999Rien : tout se fabriquera avec ce que tu as.|r") end
  local brought = ns.demandeApports(res)
  if #brought > 0 then
    frame.y = frame.y + 6
    title("Tu apportes")
    for _, a in ipairs(brought) do
      local have = C_Item.GetItemCount and C_Item.GetItemCount(a.id) or 0
      line(C_Item.GetItemIconByID(a.id), ns.itemLabel(a.id), have >= a.qty and (READY .. " " .. a.qty) or ("%d/%d"):format(have, a.qty),
        a.id, "Dans tes sacs : " .. have, { math.min(have, a.qty), 0, 0 }, a.qty, { 0.30, 0.80, 0.85 })
    end
  end

  if #recipes > 0 then
    frame.y = frame.y + 6
    title("Recettes à apprendre")
    for _, r in ipairs(recipes) do
      local text = r.item and ns.itemLabel(r.item) or ("Recette : " .. r.name .. " |cff999999(objet jamais vu)|r")
      line(C_Item.GetItemIconByID(r.item or r.product), text, "à trouver", r.item or r.product, "Pour fabriquer " .. ns.itemLabel(r.product))
    end
  end
  for i = used + 1, #rows do rows[i]:Hide() end

  local foot = ("%d/%d prêts"):format(done, #list)
  if buy > 0 then foot = foot .. " · à acheter : " .. ns.moneyShort(buy) end
  if order.tip and order.tip > 0 then foot = foot .. " · pourboire " .. ns.moneyShort(order.tip) end
  frame.foot:SetText(foot)
  frame.send:SetText(order.player and ("Envoyer à " .. order.player) or "Envoyer (joueur ?)")
  frame:SetHeight(frame.y + 70)
end

local function build()
  frame = ns.newWindow("HandshakeBesoinsFrame", "Besoins", W, 200)
  frame:ClearAllPoints()
  frame:SetPoint("TOPRIGHT", -60, -160) -- à côté, pas par-dessus la fenêtre des commandes
  frame.title:SetText("")
  frame.head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.head:SetPoint("TOPLEFT", 14, -12)
  frame.head:SetPoint("RIGHT", -60, 0)
  frame.head:SetJustifyH("LEFT")
  frame.head:SetWordWrap(false)
  frame.foot = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.foot:SetPoint("BOTTOMLEFT", 14, 44)
  frame.send = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.send:SetSize(W - 28, 22)
  frame.send:SetPoint("BOTTOMLEFT", 14, 12)
  frame.send:SetScript("OnClick", function()
    local order = ns.currentOrder()
    ns.sendNeeds(order, ns.computeOrder(order))
  end)
  local pending
  frame:RegisterEvent("BAG_UPDATE_DELAYED")
  frame:SetScript("OnEvent", function()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(1, function() pending = false; ns.refreshNeeds() end)
  end)
  frame:SetScript("OnShow", function() ns.refreshNeeds() end)
end

function ns.toggleNeeds()
  if not frame then build() end
  frame:SetShown(not frame:IsShown())
end
