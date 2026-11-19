-- Handshake : une commande passe d'un joueur à l'autre.
-- Commande = les lignes « objet × quantité » d'un projet (Projet.lua), le joueur d'en face, une offre, des apports.
-- Ce qu'il faut pour la faire (la liste des besoins) a la même forme : on peut la renvoyer au client, ou la passer
-- à un autre joueur comme une commande.
-- Échange : du texte avec des liens d'objets, lisible et écrivable à la main (Maj+clic), par chuchotement :
--   Commande : 1x[Claymore en mithril] 1x[Camail en mithril] · pourboire 5 po · je fournis les composants
--   Besoins (1/2) : 36x[Minerai de mithril] 12x[Pierre solide] …
-- Un message est limité à 255 caractères (un lien en prend ~80) : la liste part en plusieurs messages (i/n),
-- recollés à l'arrivée.
local _, ns = ...

local MAX_MSG = 255

---------------------------------------------------------------------------------------------------
-- /handshake demo [set|ceinture|hasard] : une commande d'essai parlante. Choisis dans les données (arbres profonds qui
-- traversent plusieurs métiers, tools/crafts_critiques.py) :
--   set      : l'ensemble en thorium enchanté (heaume, cuirasse, jambières) — forge 300 + alchimie, enchantement, minage ;
--   ceinture : ceinture de prévention gnome (ingénierie 215, 5 métiers) + ceinture barbare (cuir 200, 4 métiers) ;
--   hasard   : 2 objets par métier tirés au hasard (pour charger la fenêtre).
local DEMOS = {
  set = { name = "Essai : set en thorium enchanté", ids = { 12620, 12618, 12619 } },
  ceinture = { name = "Essai : ceintures multi-métiers", ids = { 10721, 4264 } },
}
function ns.demoOrder(kind, perProf)
  local d = DEMOS[kind or "set"]
  if d then
    local lines = {}
    for _, id in ipairs(d.ids) do lines[#lines + 1] = { id = id, qty = 1 } end
    return ns.nouveauProjet({ name = d.name, lines = lines })
  end
  local recipes, makes, byProf = ns.recipes(), {}, {}
  for _, r in pairs(recipes) do if r.output then makes[r.output] = true end end
  for _, r in pairs(recipes) do
    if r.output and r.profession and r.reagents then
      for _, g in ipairs(r.reagents) do
        if makes[g.id] then
          byProf[r.profession] = byProf[r.profession] or {}
          table.insert(byProf[r.profession], r.output)
          break
        end
      end
    end
  end
  local lines, seen = {}, {}
  for _, list in pairs(byProf) do
    for _ = 1, math.min(perProf or 2, #list) do
      local id = table.remove(list, math.random(#list))
      if not seen[id] then seen[id], lines[#lines + 1] = true, { id = id, qty = 1 } end
    end
  end
  return ns.nouveauProjet({ name = "Essai : au hasard", lines = lines })
end

-- Les apports d'une demande, avec leur quantité (case entière) : { { id, qty }, … } triés par ID.
function ns.demandeApports(res)
  local out = {}
  for _, n in ipairs(res.cases) do
    if (n.apport or 0) > 0 then out[#out + 1] = { id = n.id, qty = n.apport } end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- L'objet qui apprend une recette : « Plans : Claymore en mithril », « Formule : … », « Patron : … ».
-- ponytail: par le nom, faute de lien recette -> objet dans les données ; nil si jamais vu
local recipeItems = {}
function ns.recipeItem(name)
  if recipeItems[name] ~= nil then return recipeItems[name] or nil end
  local found = false
  for id, it in pairs(ns.items()) do
    local n = it.name
    if n and #n > #name and n:sub(-#name) == name and n:sub(1, #n - #name):find(":%s*$") then found = id break end
  end
  recipeItems[name] = found
  return found or nil
end

-- La liste des besoins : ce qui ne se fabrique pas dans l'arbre (acheté, fourni, ou déjà en stock), avec
-- combien il en faut et combien on en a ; puis les recettes pas apprises.
function ns.orderNeeds(res)
  local rows, recipes = {}, {}
  for _, n in ipairs(res.cases) do
    local required = n.qty - n.made
    if required > 0 and (n.made == 0 or n.need > 0) and (n.apport or 0) == 0 then
      rows[#rows + 1] = { id = n.id, required = required, have = n.have, need = n.need, cost = n.cost, unpriced = n.unpriced, how = n.how }
    end
    if n.made > 0 and n.unknown and n.recipe then
      recipes[#recipes + 1] = { name = n.recipe.name, item = ns.recipeItem(n.recipe.name), product = n.id }
    end
  end
  table.sort(rows, function(a, b)
    if (a.need > 0) ~= (b.need > 0) then return a.need > 0 end
    return a.id < b.id
  end)
  return rows, recipes
end

---------------------------------------------------------------------------------------------------
-- Texte échangé
local function chatLink(id)
  local it = ns.items()[id]
  return (it and it.link) or select(2, C_Item.GetItemInfo(id)) or ("[" .. ((it and it.name) or ("objet " .. id)) .. "]")
end

local function po(copper) return (("%.2f"):format(copper / 10000)):gsub("%.?0+$", "") .. " po" end
ns.poText = po

-- lines : { { id, qty } ou { text, qty } } ; extra : texte ajouté à la fin (pourboire…). Renvoie les messages.
function ns.listMessages(kind, lines, extra)
  local tokens = {}
  for _, l in ipairs(lines) do tokens[#tokens + 1] = l.raw or ("%dx%s"):format(l.qty, l.text or chatLink(l.id)) end
  if extra and extra ~= "" then tokens[#tokens + 1] = extra end
  local bodies, cur = {}, nil
  local room = MAX_MSG - #kind - #" (99/99) : "
  for _, t in ipairs(tokens) do
    if cur and #cur + 1 + #t <= room then cur = cur .. " " .. t
    else
      if cur then bodies[#bodies + 1] = cur end
      cur = t
    end
  end
  bodies[#bodies + 1] = cur or ""
  local msgs = {}
  for i, b in ipairs(bodies) do
    msgs[i] = #bodies > 1 and ("%s (%d/%d) : %s"):format(kind, i, #bodies, b) or ("%s : %s"):format(kind, b)
  end
  return msgs
end

-- Lit une liste : ce qui précède « j'apporte » = ce qu'on veut, ce qui suit (jusqu'au prochain « · ») = les apports.
-- Liens d'objets (quantité avant « 3x[…] » ou après « […] x3 »), ou à défaut des noms entre
-- crochets tapés à la main. Renvoie lines, genre (« commande », « besoins »…), offre (cuivre), apports.
local function parseItems(text)
  local lines, byId = {}, {}
  local function add(id, q)
    if not id then return end
    if byId[id] then byId[id].qty = byId[id].qty + q return end
    byId[id] = { id = id, qty = q }
    lines[#lines + 1] = byId[id]
  end
  local pos, found = 1, false
  while true do
    local s, e, id = text:find("|Hitem:(%d+)[^|]*|h[^|]*|h", pos)
    if not s then break end
    found = true
    local after = text:sub(e + 1):gsub("^|r", "")
    local skip, q = after:match("^(%s*[xX]%s*(%d+))")
    if q then
      e = e + #skip + (text:sub(e + 1, e + 2) == "|r" and 2 or 0)
    else
      local before = text:sub(pos, s - 1):gsub("|c%x%x%x%x%x%x%x%x$", "")
      q = before:match("(%d+)%s*[xX]?%s*$")
    end
    add(tonumber(id), tonumber(q) or 1)
    pos = e + 1
  end
  if not found then
    for q, name in text:gmatch("(%d*)%s*[xX]?%s*%[([^%]]+)%]") do add(ns.findItem(name), tonumber(q) or 1) end
  end
  return lines
end

function ns.parseList(text)
  text = (text or ""):gsub("×", "x")
  local kind = text:match("^%s*(%a+)")
  local wanted, rest = text, nil
  local a, b = text:find("j'apporte", 1, true)
  if a then wanted, rest = text:sub(1, a - 1), text:sub(b + 1) end
  local brought = rest and parseItems(rest:match("^(.-)·") or rest) or {}
  local tip = text:match("offre%s*:?%s*([%d%.,]+)%s*po") or text:match("pourboire%s*:?%s*([%d%.,]+)%s*po")
  tip = tip and tonumber((tip:gsub(",", "."))) and math.floor(tonumber((tip:gsub(",", "."))) * 10000 + 0.5) or nil
  return parseItems(wanted), kind and kind:lower(), tip, brought
end

---------------------------------------------------------------------------------------------------
-- Envoi : un chuchotement par message, au joueur de la commande. Le clic sur « Envoyer » vaut validation.
-- loop (/commande essai) : rien ne part sur le réseau, les messages sont affichés puis reçus comme un chuchotement
-- de toi-même — le même chemin qu'à l'arrivée (recollage des morceaux, proposition d'import).
-- Un chuchotement (le mode debug le détourne vers son journal).
function ns.whisper(msg, target)
  if ns.debugSend and ns.debugSend("chuchotement", target, msg) then return end
  local say = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
  say(msg, "WHISPER", nil, ns.whisperTarget and ns.whisperTarget(target) or target)
end

local function send(kind, lines, extra, target, loop)
  if #lines == 0 then return print("|cffe64d4dCommandes :|r rien à envoyer.") end
  local msgs = ns.listMessages(kind, lines, extra)
  if loop then
    for _, m in ipairs(msgs) do print("|cff999999[essai]|r " .. m) end
    for _, m in ipairs(msgs) do ns.onChat("CHAT_MSG_WHISPER", m, UnitName("player")) end
    return
  end
  target = target and target:gsub("^%s+", ""):gsub("%s+$", "")
  if not target or target == "" then return print("|cffe64d4dCommandes :|r indique le joueur à qui envoyer.") end
  for _, m in ipairs(msgs) do ns.whisper(m, target) end
  print(("Commandes : %s envoyée à %s (%d message%s)."):format(kind:lower(), target, #msgs, #msgs > 1 and "s" or ""))
end

-- La demande en clair (pour quelqu'un sans l'addon) : « Commande : 1x[Armure] · j'apporte 4x[Cuir lourd] · offre 5 po ».
function ns.sendOrder(order, loop)
  local lines = {}
  for _, l in ipairs(order.lines) do lines[#lines + 1] = l end
  local brought = ns.demandeApports(ns.projetDemande(order))
  if #brought > 0 then
    lines[#lines + 1] = { raw = "· j'apporte" }
    for _, l in ipairs(brought) do lines[#lines + 1] = l end
  end
  send("Commande", lines, order.tip and order.tip > 0 and ("· offre " .. po(order.tip)) or nil, order.player, loop)
end

function ns.sendNeeds(order, res, loop)
  local rows, recipes = ns.orderNeeds(res)
  local lines = {}
  for _, r in ipairs(rows) do if r.need > 0 then lines[#lines + 1] = { id = r.id, qty = r.need } end end
  for _, r in ipairs(recipes) do
    lines[#lines + 1] = r.item and { id = r.item, qty = 1 } or { text = "[Recette : " .. r.name .. "]", qty = 1 }
  end
  local extra = {}
  if order.tip and order.tip > 0 then extra[#extra + 1] = "offre " .. po(order.tip) end
  if res.total > 0 then extra[#extra + 1] = "ou je les achète : ~" .. po(res.total) end
  send("Besoins", lines, #extra > 0 and ("· " .. table.concat(extra, " · ")) or nil, order.player, loop)
end

---------------------------------------------------------------------------------------------------
-- Réception : le dernier message avec des objets (pour l'import à la main), et les listes en plusieurs
-- morceaux recollées. Une commande ou des besoins reçus en chuchotement proposent l'import.
ns.lastReceived = nil
local parts = {}

function ns.importText(text, player)
  local lines, kind, tip, brought = ns.parseList(text)
  if #lines == 0 then return print("|cffe64d4dCommandes :|r aucun objet reconnu dans ce texte.") end
  local who = player and player ~= "" and player or nil
  local apports = {}
  for _, l in ipairs(brought) do apports[l.id] = true end
  ns.nouveauProjet({ name = (kind == "besoins" and "Besoins" or "Commande") .. (who and (" de " .. who) or ""),
    player = who, lines = lines, tip = tip, apports = next(apports) and apports or nil })
  ns.openCraftWindow()
end

StaticPopupDialogs.HANDSHAKE_COMMANDE_RECUE = {
  text = "%s t'envoie une liste (%s).\nL'importer comme commande ?",
  button1 = "Importer", button2 = "Plus tard",
  OnAccept = function(_, data) ns.importText(data.text, data.player) end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

function ns.onChat(event, msg, sender, ...)
  if type(msg) ~= "string" or (issecretvalue and (issecretvalue(msg) or issecretvalue(sender))) then return end
  if event == "CHAT_MSG_WHISPER" then
    if ns.rawSenders then ns.rawSenders.whisper = sender end
    -- le jeu joint à chaque chuchotement l'identifiant de l'expéditeur (12e valeur) : source serveur, on le retient
    if ns.learnGUID then ns.learnGUID(ns.fullName(sender), (select(10, ...))) end
  end
  sender = Ambiguate and Ambiguate(sender or "", "none") or sender
  local kind, i, n, body = msg:match("^%s*(%a+) %((%d+)/(%d+)%) : (.*)$")
  if kind then
    -- Bornes (modèle de menace, SECURITE.md) : 10 morceaux au plus, un « 1/n » repart de zéro, un tampon par
    -- expéditeur, oublié après 30 s.
    i, n = tonumber(i), tonumber(n)
    if n < 1 or n > 10 or i < 1 or i > n then return end
    local p = parts[sender]
    if i == 1 or not p or p.kind ~= kind or p.n ~= n or GetTime() - p.t > 30 then
      p = { kind = kind, n = n }
      parts[sender] = p
    end
    p[i], p.t = body, GetTime()
    for k = 1, n do if not p[k] then return end end
    msg, parts[sender] = kind .. " : " .. table.concat(p, " ", 1, n), nil
  end
  if not msg:find("|Hitem:") then return end
  ns.lastReceived = { player = sender, text = msg }
  local k = msg:match("^%s*(%a+) :")
  if event == "CHAT_MSG_WHISPER" and (k == "Commande" or k == "Besoins") then
    StaticPopup_Show("HANDSHAKE_COMMANDE_RECUE", sender, k:lower(), { player = sender, text = msg })
  end
end

-- Import à la main : le dernier message reçu avec des objets, modifiable, ou des liens collés par Maj+clic.
local importFrame
function ns.openImport()
  if not importFrame then
    local f = ns.newWindow("HandshakeImport", "Importer une liste", 520, 150)
    f:SetFrameStrata("DIALOG")
    local text = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    text:SetSize(480, 22)
    text:SetPoint("TOPLEFT", 22, -44)
    text:SetAutoFocus(false)
    text:SetMaxLetters(0)
    local who = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    who:SetSize(160, 22)
    who:SetPoint("TOPLEFT", 90, -78)
    who:SetAutoFocus(false)
    local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("RIGHT", who, "LEFT", -10, 0)
    label:SetText("De la part de")
    local ok = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    ok:SetSize(100, 22)
    ok:SetPoint("BOTTOMRIGHT", -14, 12)
    ok:SetText("Importer")
    ok:SetScript("OnClick", function() f:Hide(); ns.importText(text:GetText(), who:GetText()) end)
    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", 14, 16)
    hint:SetText("Le dernier message reçu avec des objets ; Maj+clic sur un objet pour en ajouter.")
    if ChatEdit_InsertLink then
      hooksecurefunc("ChatEdit_InsertLink", function(link)
        if text:HasFocus() and link then text:Insert(" 1x" .. link) end
      end)
    end
    f.text, f.who = text, who
    importFrame = f
  end
  local last = ns.lastReceived
  importFrame.text:SetText(last and last.text or "")
  importFrame.who:SetText(last and last.player or "")
  importFrame:Show()
end

---------------------------------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD" }) do
  f:RegisterEvent(e)
end
f:SetScript("OnEvent", function(_, event, a1, a2, ...)
  if event ~= "ADDON_LOADED" then return ns.onChat(event, a1, a2, ...) end
  if a1 ~= "Handshake" then return end
  HandshakeDB = HandshakeDB or {}
  local db, old = HandshakeDB, GameDataDB or {}
  -- Reprise de ce qui vivait dans GameData avant le module (18/11/2026).
  db.options = db.options or old.craft_options or { bags = true, bank = true, alts = false, unlearned = false }
  db.contracts = db.contracts or {}
  for _, c in pairs(db.contracts) do c.unsaved = nil end -- ce qui est chargé a été enregistré
  ns.migrerProjets(db, old)
  old.craft_options, old.craft_force, old.craft_targets = nil, nil, nil
end)
