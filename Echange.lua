-- Handshake, le panneau d'échange : pendant un échange avec quelqu'un avec qui tu as un contrat signé,
-- un panneau accroché à la fenêtre d'échange dit si ce qui est posé des deux côtés est conforme à TA copie du contrat.
-- Cases 1 à 6 seulement, objets reconnus par leur ID, or au cuivre près, dans les deux sens (SECURITE.md, n° 28-38).
-- « Remplir ma part » pose tes objets (piles coupées au compte exact) et l'or dû ; c'est toi qui cliques « Accepter ».
-- Non conforme : « Accepter » est grisé ; « Accepter quand même » demande une confirmation qui chiffre la perte.
-- Un échange terminé n'est inscrit que si ton or et tes sacs ont bougé comme prévu ; sinon « à vérifier ».
local _, ns = ...

-- Fonctions du jeu capturées au chargement ; si un addon chargé avant nous les a remplacées, on le dit (n° 38).
local API, tampered = {}, false
for _, n in ipairs({ "GetTradePlayerItemLink", "GetTradePlayerItemInfo", "GetTradeTargetItemLink", "GetTradeTargetItemInfo",
  "GetPlayerTradeMoney", "GetTargetTradeMoney", "UnitName", "UnitGUID", "GetMoney" }) do
  API[n] = _G[n]
  if issecurevariable and not issecurevariable(n) then tampered = true end
end
local GetItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local OK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
local NO = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12|t"

local function itemID(link) return link and tonumber(link:match("item:(%d+)")) end

-- Ce qui est posé dans l'échange, tel que le serveur le montre (ou, en mode debug, l'échange simulé).
local fake
local function read()
  if fake then return fake end
  local s = { give = { items = {}, money = API.GetPlayerTradeMoney() or 0 }, get = { items = {}, money = API.GetTargetTradeMoney() or 0 }, api = tampered }
  for i = 1, 6 do
    local mine, theirs = itemID(API.GetTradePlayerItemLink(i)), itemID(API.GetTradeTargetItemLink(i))
    local mineName, _, mineQty = API.GetTradePlayerItemInfo(i)
    local theirName, _, theirQty = API.GetTradeTargetItemInfo(i)
    if mine then s.give.items[mine] = (s.give.items[mine] or 0) + (mineQty or 1) elseif mineName then s.unknown = true end
    if theirs then s.get.items[theirs] = (s.get.items[theirs] or 0) + (theirQty or 1) elseif theirName then s.unknown = true end
  end
  if API.GetTradeTargetItemInfo(7) or API.GetTradePlayerItemInfo(7) then s.slot7 = true end
  s.partner, s.guid = ns.unitName(API.UnitName("NPC")), API.UnitGUID("NPC") -- « Prénom Nom » et GUID, donnés par le serveur
  return s
end

local function signature(s)
  local t = { s.give.money, s.get.money }
  for id, q in pairs(s.give.items) do t[#t + 1] = "g" .. id .. ":" .. q end
  for id, q in pairs(s.get.items) do t[#t + 1] = "r" .. id .. ":" .. q end
  table.sort(t, function(a, b) return tostring(a) < tostring(b) end)
  return table.concat(t, ",")
end

---------------------------------------------------------------------------------------------------
local panel, contracts, index, last, override, armToken = nil, {}, 1, nil, nil, 0
local W = 330

local function current() return contracts[index] end

local function setAccept(enabled)
  if not TradeFrameTradeButton then return end
  if enabled then TradeFrameTradeButton:Enable() else TradeFrameTradeButton:Disable() end
end

local function money(c) return ns.moneyShort(c) end

local function build()
  panel = ns.newWindow("HandshakeEchangePanel", "Contrat", W, 300)
  table.remove(UISpecialFrames) -- Échap ferme l'échange, pas seulement le panneau
  panel:SetFrameStrata("DIALOG")
  panel.lines = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.lines:SetPoint("TOPLEFT", 14, -38)
  panel.lines:SetPoint("RIGHT", -14, 0)
  panel.lines:SetJustifyH("LEFT")
  panel.lines:SetSpacing(3)
  panel.verdict = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.verdict:SetPoint("TOPLEFT", panel.lines, "BOTTOMLEFT", 0, -10)
  panel.notes = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.notes:SetPoint("TOPLEFT", panel.verdict, "BOTTOMLEFT", 0, -6)
  panel.notes:SetPoint("RIGHT", -14, 0)
  panel.notes:SetJustifyH("LEFT")
  local function button(text, w)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
  end
  panel.fill = button("Remplir ma part", 140)
  panel.fill:SetPoint("BOTTOMLEFT", 14, 12)
  panel.force = button("Accepter quand même", 160)
  panel.force:SetPoint("BOTTOMRIGHT", -14, 12)
  panel.switch = button(">", 24)
  panel.switch:SetPoint("TOPRIGHT", -34, -8)
  panel.switch:SetScript("OnClick", function() index = index % #contracts + 1; ns.refreshTradePanel() end)
end

local function lineText(c, me, s, r)
  local artisan = me == c.artisan
  local inList, outList = artisan and c.m or c.o, artisan and c.o or c.m
  local got, gave = c.got or {}, c.gave or {}
  local peer = c.peer or {}
  local t = { ("|cffa98fff%s|r"):format(ns.identity(peer.name, peer.guid)),
    ("v%s · empreinte %s"):format(c.v, c.hash:sub(1, 8)) }
  local function block(title, list, here, done, word)
    if #list == 0 then return end
    t[#t + 1] = "|cffffd100" .. title .. "|r"
    for _, l in ipairs(list) do
      local q, d = here[l.id] or 0, done[l.id] or 0
      local mark = (q > 0 and q <= l.qty - d) and " " .. OK or ""
      t[#t + 1] = ("  %s  ici %d · %s %d/%d%s"):format(ns.itemLabel(l.id), q, word, d, l.qty, mark)
    end
  end
  block("Tu donnes", outList, s.give.items, gave, "donné")
  block("Il donne", inList, s.get.items, got, "reçu")
  t[#t + 1] = ("Or : tu donnes %s · il donne %s"):format(money(s.give.money), money(s.get.money))
  t[#t + 1] = ("Valeur reçue %s · donnée %s · solde après %s"):format(money(r.valueIn), money(r.valueOut), ns.moneySigned(r.net))
  return table.concat(t, "\n")
end

function ns.refreshTradePanel()
  if not (panel and panel:IsShown()) then return end
  local c, me = current(), ns.me()
  if not c then return end
  local s = read()
  local r = ns.ctEvaluate(c, me, s, GetServerTime())
  last = { s = s, r = r, c = c, sig = signature(s), money = API.GetMoney() }
  last.counts = {}
  for id in pairs(s.give.items) do last.counts[id] = GetItemCount(id) end
  for id in pairs(s.get.items) do last.counts[id] = GetItemCount(id) end
  panel.switch:SetShown(#contracts > 1)
  panel.title:SetText(#contracts > 1 and ("Contrat %d/%d"):format(index, #contracts) or "Contrat")
  panel.lines:SetText(lineText(c, me, s, r))
  local notes = {}
  for _, p in ipairs(r.problems) do notes[#notes + 1] = NO .. " |cffe64d4d" .. p .. (p == "il manque de son côté" and (" : " .. money(r.short)) or "") .. "|r" end
  for _, w in ipairs(r.warnings) do notes[#notes + 1] = "|cffe6994d! " .. w .. "|r" end
  panel.notes:SetText(table.concat(notes, "\n"))
  if r.empty then panel.verdict:SetText("|cff999999Rien de posé|r")
  elseif r.ok then panel.verdict:SetText(OK .. " |cff59cc73CONFORME AU CONTRAT|r")
  else panel.verdict:SetText((s.api or s.unknown) and "|cff999999? NON VÉRIFIÉ|r" or NO .. " |cffe64d4dNON CONFORME|r") end
  panel.force:SetShown(not r.ok and not r.empty and override ~= last.sig)
  panel.force:SetText("Accepter quand même")
  panel.force.armed = nil
  panel:SetHeight(panel.lines:GetStringHeight() + panel.notes:GetStringHeight() + 120)
  -- Accepter : grisé si non conforme ; après tout changement, réarmé au bout d'une seconde (P7).
  armToken = armToken + 1
  local token = armToken
  setAccept(false)
  if r.ok or r.empty or override == last.sig then
    C_Timer.After(1, function() if token == armToken then setAccept(true) end end)
  end
end

-- Dérogation : deux clics, le second énonce la perte, et c'est noté dans le contrat (n° 60).
local function forceClick(self)
  if not last then return end
  local loss = math.max(0, last.r.valueOut - last.r.valueIn - (last.c.net or 0))
  if not self.armed then
    self.armed = true
    self:SetText("Oui, je perds " .. ns.money(loss))
    return
  end
  override = last.sig
  last.c.overrides = last.c.overrides or {}
  table.insert(last.c.overrides, { t = GetServerTime(), loss = loss, sig = last.sig })
  ns.refreshTradePanel()
end

-- Remplir ma part : mes objets restants (jamais liés ni verrouillés, cases 1-6 libres), puis l'or dû.
local function setMoney(c)
  local s = read()
  local r = ns.ctEvaluate(c, ns.me(), s, GetServerTime())
  local owe = math.max(0, math.floor((c.net or 0) + r.valueIn - (r.valueOut - s.give.money)))
  if owe > API.GetMoney() then return print("|cffe64d4dContrats :|r pas assez d'or pour " .. money(owe) .. ".") end
  if SetTradeMoney and owe ~= s.give.money then SetTradeMoney(owe) end
end

local function fill()
  local c, me = current(), ns.me()
  if not c then return end
  local outList = me == c.artisan and c.o or c.m
  local s = read()
  local used = {}
  for i = 1, 6 do if API.GetTradePlayerItemInfo(i) then used[i] = true end end
  local function freeSlot()
    for i = 1, 6 do if not used[i] then used[i] = true return i end end
  end
  for _, l in ipairs(outList) do
    local left = l.qty - ((c.gave or {})[l.id] or 0) - (s.give.items[l.id] or 0)
    for bag = 0, NUM_BAG_SLOTS or 4 do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        if left <= 0 then break end
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info and info.itemID == l.id and not info.isBound and not info.isLocked then
          local ts = freeSlot()
          if not ts then
            print("Contrats : les 6 cases sont prises, le reste au prochain échange.")
            return C_Timer.After(0.6, function() setMoney(c) end)
          end
          local n = math.min(left, info.stackCount)
          if n < info.stackCount then C_Container.SplitContainerItem(bag, slot, n) else C_Container.PickupContainerItem(bag, slot) end
          ClickTradeButton(ts)
          if CursorHasItem and CursorHasItem() then ClearCursor() end
          left = left - n
        end
      end
    end
  end
  C_Timer.After(0.6, function() setMoney(c) end)
end

-- Fin d'échange : inscrit seulement si l'or et les sacs ont bougé comme prévu (n° 37), sinon « à vérifier ».
local function confirm(snapshot, tries)
  local s, c = snapshot.s, snapshot.c
  local ok = API.GetMoney() - snapshot.money == s.get.money - s.give.money
  for id, before in pairs(snapshot.counts) do
    if GetItemCount(id) - before ~= (s.get.items[id] or 0) - (s.give.items[id] or 0) then ok = false end
  end
  if not ok and tries < 3 then return C_Timer.After(1, function() confirm(snapshot, tries + 1) end) end
  if ok then
    ns.ctRecord(c, ns.me(), s, GetServerTime())
    print(("Contrats : échange avec %s inscrit%s. Fais /reload (ou « Sauvegarder » dans /contrat) pour l'enregistrer sur le disque.")
      :format(tostring(c.peer and c.peer.name), c.status == "clos" and ", contrat CLOS" or ""))
  else
    c.unconfirmed = c.unconfirmed or {}
    table.insert(c.unconfirmed, { t = GetServerTime(), give = s.give, get = s.get })
    c.unsaved = true
    print("|cffe6994dContrats :|r échange terminé, mais ton or ou tes sacs ne correspondent pas : noté « à vérifier », pas inscrit.")
  end
  if ns.refreshContracts then ns.refreshContracts() end
end

local f = CreateFrame("Frame")
for _, e in ipairs({ "TRADE_SHOW", "TRADE_CLOSED", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_TARGET_ITEM_CHANGED", "TRADE_MONEY_CHANGED",
  "TRADE_ACCEPT_UPDATE", "UI_INFO_MESSAGE", "GET_ITEM_INFO_RECEIVED" }) do f:RegisterEvent(e) end
f:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "TRADE_SHOW" then
    contracts, index, override, last = ns.ctActiveWith(ns.unitName(API.UnitName("NPC")), API.UnitGUID("NPC")), 1, nil, nil
    if #contracts == 0 then return end
    if not panel then build(); panel.fill:SetScript("OnClick", fill); panel.force:SetScript("OnClick", forceClick) end
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", TradeFrame or UIParent, "TOPRIGHT", 4, 0)
    panel:Show()
    ns.refreshTradePanel()
  elseif event == "TRADE_CLOSED" then
    if panel then panel:Hide() end
    setAccept(true)
  elseif event == "UI_INFO_MESSAGE" then
    if (a2 == ERR_TRADE_COMPLETE or a1 == ERR_TRADE_COMPLETE) and last and last.c then
      local snapshot = last
      last = nil
      C_Timer.After(1, function() confirm(snapshot, 1) end)
    end
  elseif event ~= "TRADE_ACCEPT_UPDATE" and panel and panel:IsShown() then
    override = nil -- tout changement annule la dérogation
    ns.refreshTradePanel()
  end
end)

-- Mode debug : un échange simulé (pas de fenêtre d'échange), évalué par le même panneau, puis inscrit sans la
-- vérification de l'or et des sacs (il n'y a pas eu de vrai échange).
function ns.tradeDebug(snap)
  fake = snap
  contracts, index, override, last = ns.ctActiveWith(snap.partner, snap.guid), 1, nil, nil
  if #contracts == 0 then print("Handshake debug : aucun contrat signé avec " .. tostring(snap.partner) .. ".") return end
  if not panel then build(); panel.fill:SetScript("OnClick", fill); panel.force:SetScript("OnClick", forceClick) end
  panel:ClearAllPoints()
  panel:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  panel:Show()
  ns.refreshTradePanel()
end
function ns.tradeDebugFinish()
  local c = current()
  if fake and c then
    ns.ctRecord(c, ns.me(), fake, GetServerTime())
    print("Handshake debug : échange simulé inscrit" .. (c.status == "clos" and ", contrat CLOS." or "."))
  end
  fake = nil
  if panel then panel:Hide() end
  if ns.refreshContracts then ns.refreshContracts() end
end
