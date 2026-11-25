-- Handshake, MODE DEBUG — NON PUBLIÉ (exclu du zip par tools/package.py). /handshake debug
-- Pour tester seul les deux côtés d'une demande ou d'un contrat :
--   * bac à sable : rien ne part sur le réseau, tout ce que Handshake enverrait (messages d'addon, chuchotements)
--     s'écrit dans le journal, copiable (Ctrl+A, Ctrl+C) ;
--   * un second joueur fictif, « Testeur » (prénom, nom de famille, identifiant inventés), avec SES contrats :
--     « Jouer Testeur » te met à sa place, toutes les fenêtres suivent ;
--   * livraison automatique : ce que l'un envoie à l'autre arrive chez l'autre, comme sur le réseau ;
--   * boîte de réception : un message tapé ou collé (modifié si tu veux, pour jouer l'attaquant), reçu de qui tu veux ;
--   * faux échange : ce que chacun pose, évalué par le vrai panneau, puis inscrit.
local _, ns = ...

local TESTER = { name = "Testeur Bacasable", guid = "Player-0-00000DEB" } -- numéro de serveur 0 : il n'existe pas
local dbg = { on = false, as = nil, auto = true, log = {} }
local frame

local realGUID, realName = ns.me, ns.myName
local function testerName() return TESTER.name end
ns.me = function() if dbg.as then return TESTER.guid end return realGUID() end
ns.myName = function() if dbg.as then return TESTER.name end return realName() end

-- Base de contrats du Testeur (gardée dans HandshakeDB.debug, jamais mélangée aux tiennes).
ns.debugStore = function()
  if not dbg.as then return nil end
  HandshakeDB.debug = HandshakeDB.debug or {}
  HandshakeDB.debug.contracts = HandshakeDB.debug.contracts or {}
  return HandshakeDB.debug.contracts
end

local function other() return dbg.as and realName() or testerName() end
local function refreshAll()
  if ns.refreshContracts then ns.refreshContracts() end
  if Composants then Composants.Rafraichir() end
  if frame and frame:IsShown() then frame.refresh() end
end

-- Être l'un ou l'autre le temps d'un appel (livraison d'un message à son destinataire).
local function as(who, fn)
  local before = dbg.as
  dbg.as = who
  local ok, err = pcall(fn)
  dbg.as = before
  if not ok then print("|cffe64d4dHandshake debug :|r " .. tostring(err)) end
end

local function deliver(kind, from, to, text)
  local toTester = to == testerName()
  if not toTester and to ~= realName() then return false end
  as(toTester and "tester" or nil, function()
    if kind == "addon" then ns.ctOnAddon(ns.PREFIX, text, "WHISPER", from)
    else ns.onChat("CHAT_MSG_WHISPER", text, from) end
  end)
  return true
end

-- Interception des envois : en bac à sable, tout ; et TOUJOURS ce qui va au Testeur ou en vient (il n'existe pas sur
-- le serveur : un envoi réel donnait « Aucun joueur nommé 'Testeur …' »). Renvoie vrai si l'envoi est pris en charge.
ns.debugSend = function(kind, target, text)
  local to = ns.fullName(target) or target
  local involvesTester = to == testerName() or dbg.as
  if not (dbg.on or involvesTester) then return false end
  local from = ns.myName()
  local delivered = (dbg.auto or not dbg.on) and deliver(kind, from, to, text)
  table.insert(dbg.log, ("[%s] %s -> %s%s : %s"):format(kind, from, tostring(target), delivered and " (livré)" or "", text))
  if not delivered and to ~= testerName() then -- un vrai joueur n'aura rien : le dire, pas seulement le journal
    print(("|cffe64d4dHandshake debug :|r bac à sable actif, rien n'est parti vers %s (/handshake debug pour le couper)."):format(tostring(target)))
  end
  while #dbg.log > 60 do table.remove(dbg.log, 1) end
  C_Timer.After(0, refreshAll)
  return true
end
local function setSandbox(on)
  dbg.on = on and true or false
  HandshakeDB.debug = HandshakeDB.debug or {}
  HandshakeDB.debug.on = dbg.on -- gardé d'une session à l'autre
  if not on then dbg.as = nil end
end
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  dbg.on = HandshakeDB.debug and HandshakeDB.debug.on or false
  if dbg.on then print("|cffe64d4dHandshake debug :|r bac à sable actif : rien ne part vers les autres joueurs (/handshake debug pour le couper).") end
end)

-- « 3858x20 7963x1 5.5po 30pa 12pc » -> { items = {[id]=qté}, money = cuivre }
local function parseSide(s)
  local side = { items = {}, money = 0 }
  for id, q in (s or ""):gmatch("(%d+)x(%d+)") do
    id = tonumber(id)
    side.items[id] = (side.items[id] or 0) + tonumber(q)
  end
  for n, unit in (s or ""):gsub(",", "."):gmatch("([%d%.]+)%s*(p[oac])") do
    side.money = side.money + math.floor(tonumber(n) * (unit == "po" and 10000 or unit == "pa" and 100 or 1) + 0.5)
  end
  return side
end

local function build()
  local H = 560
  frame = ns.newWindow("HandshakeDebug", "Handshake — debug (bac à sable)", 620, H)
  -- Sous le journal, tout est posé depuis le bas (y compté depuis le haut à la taille de départ) : agrandie, la fenêtre
  -- donne sa hauteur au journal.
  local function bas(y) return H + y end
  local function button(text, w, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", function() onClick(); refreshAll() end)
    return b
  end
  local function check(label, x, y, get, set)
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", x, y)
    local t = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    t:SetText(label)
    cb:SetScript("OnClick", function(self) set(self:GetChecked()); refreshAll() end)
    cb.get = get
    return cb
  end
  local function input(w, x, y, label)
    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", x, bas(y - 4))
    t:SetText(label)
    local e = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    e:SetSize(w, 22)
    e:SetPoint("LEFT", t, "RIGHT", 10, 0)
    e:SetAutoFocus(false)
    e:SetMaxLetters(0)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
  end

  local sandbox = check("Bac à sable : rien ne part sur le réseau", 12, -38, function() return dbg.on end, setSandbox)
  local auto = check("Livrer automatiquement à l'autre", 330, -38, function() return dbg.auto end, function(v) dbg.auto = v and true or false end)
  frame.who = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.who:SetPoint("TOPLEFT", 16, -70)
  local swap = button("Jouer l'autre", 120, function()
    if not dbg.on then setSandbox(true) end
    dbg.as = not dbg.as and "tester" or nil
  end)
  swap:SetPoint("TOPRIGHT", -14, -66)

  -- Journal
  local logTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  logTitle:SetPoint("TOPLEFT", 14, -98)
  logTitle:SetText("Journal (ce qui serait parti) — Ctrl+A puis Ctrl+C pour copier")
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -116)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, H - 316)
  local log = CreateFrame("EditBox", nil, scroll)
  log:SetMultiLine(true)
  log:SetFontObject("GameFontHighlightSmall")
  log:SetWidth(560)
  scroll:SetScript("OnSizeChanged", function(_, w) log:SetWidth(w) end)
  log:SetAutoFocus(false)
  log:SetMaxLetters(0)
  log:SetScript("OnEscapePressed", log.ClearFocus)
  scroll:SetScrollChild(log)
  local clear = button("Vider", 60, function() dbg.log = {} end)
  clear:SetPoint("TOPRIGHT", -14, -94)

  -- Réception
  local inbox = input(440, 14, -330, "Message reçu")
  local from = input(160, 14, -360, "De la part de")
  local recvAddon = button("Recevoir (addon)", 130, function()
    local text = inbox:GetText():gsub("||", "|") -- copié depuis le journal : « | » doublé
    if not text:match("^%d+/%d+|") then text = "1/1|" .. text end -- un message de contrat sans en-tête de morceau
    as(dbg.as, function() ns.ctOnAddon(ns.PREFIX, text, "WHISPER", from:GetText()) end)
  end)
  recvAddon:SetPoint("LEFT", from, "RIGHT", 10, 0)
  local recvChat = button("Recevoir (chuchotement)", 170, function()
    as(dbg.as, function() ns.onChat("CHAT_MSG_WHISPER", (inbox:GetText():gsub("||", "|")), from:GetText()) end)
  end)
  recvChat:SetPoint("LEFT", recvAddon, "RIGHT", 6, 0)
  local last = button("Reprendre le dernier envoi", 190, function()
    local l = dbg.log[#dbg.log]
    if l then inbox:SetText((l:match(" : (.*)$") or ""):gsub("^%d+/%d+|", "")) end
  end)
  last:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 14, bas(-388))

  -- Faux échange
  local trTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  trTitle:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 14, bas(-424))
  trTitle:SetText("Faux échange avec l'autre (« 3858x20 7963x1 5.5po 30pa »)")
  local give = input(220, 14, -446, "Tu donnes")
  local get = input(220, 320, -446, "Il donne")
  local evalB = button("Évaluer", 90, function()
    local guid = dbg.as and realGUID() or TESTER.guid
    ns.tradeDebug({ partner = other(), guid = guid, give = parseSide(give:GetText()), get = parseSide(get:GetText()) })
  end)
  evalB:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 14, bas(-480))
  local finish = button("Terminer l'échange", 150, function() ns.tradeDebugFinish() end)
  finish:SetPoint("LEFT", evalB, "RIGHT", 6, 0)
  local reset = button("Effacer les contrats de test", 200, function()
    for key, c in pairs(HandshakeDB.contracts) do
      if c.client == TESTER.guid or c.artisan == TESTER.guid then HandshakeDB.contracts[key] = nil end
    end
    if HandshakeDB.debug then HandshakeDB.debug.contracts = {} end
    print("Handshake debug : contrats avec le Testeur effacés des deux côtés.")
  end)
  reset:SetPoint("BOTTOMLEFT", 14, 12)
  local contracts = button("Contrats", 90, function() ns.openContracts() end)
  contracts:SetPoint("BOTTOMRIGHT", -26, 12) -- à gauche de la poignée
  local orders = button("Commandes", 100, function() ns.ouvrir() end)
  orders:SetPoint("RIGHT", contracts, "LEFT", -6, 0)

  frame.refresh = function()
    sandbox:SetChecked(dbg.on)
    auto:SetChecked(dbg.auto)
    frame.who:SetText(("Tu es : |cffffffff%s|r%s"):format(ns.myIdentity(),
      dbg.on and "" or "  |cffe64d4d(bac à sable coupé : les envois partent vraiment)|r"))
    swap:SetText(dbg.as and "Redevenir moi" or "Jouer Testeur")
    if from:GetText() == "" or from:GetText() == realName() or from:GetText() == testerName() then from:SetText(other()) end
    -- « | » doublé : sinon le jeu lit « |3… », « |c… » comme des codes de mise en forme et mange le texte
    if not log:HasFocus() then log:SetText((table.concat(dbg.log, "\n"):gsub("|", "||"))) end
  end
  frame:SetScript("OnShow", frame.refresh)
end

local function open()
  -- chacun connaît le GUID de l'autre, comme s'il l'avait ciblé : les demandes partent dans les deux sens
  ns.learnGUID(TESTER.name, TESTER.guid)
  ns.learnGUID(realName(), realGUID())
  if not frame then build() end
  if not dbg.on then setSandbox(true) end
  frame:Show()
  frame.refresh()
end

-- /handshake debug (branché sur la commande existante)
local previous = SlashCmdList.HANDSHAKE
SlashCmdList.HANDSHAKE = function(args)
  if (args or ""):match("^%s*debug") then return open() end
  return previous(args)
end
