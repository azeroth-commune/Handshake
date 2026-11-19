-- Handshake, la fenêtre (/commande) : un projet en haut (Projet.lua), la liste de ses commandes, son arbre par étages dessous.
-- Colonne 0 : ce qu'on suit. Étage 1 : ce qu'il faut pour le fabriquer. Étage 2 : ce qu'il faut pour ces
-- composants, etc. Une seule case par objet : la barre de bronze du marteau et de la dague, c'est la même case,
-- rangée à l'étage le plus profond où elle sert.
-- Un objet est décomposé quand c'est moins cher d'après le dernier scan de l'HV ; « + » le décompose quand même,
-- « – » l'achète tout fait (clic encore = retour au calcul). Ce choix de case appartient au projet affiché.
-- Barre sous chaque case : vert = dans tes sacs, bleu = à ta banque, violet = chez tes autres persos,
-- orange = à fabriquer, gris = à acheter, rouge = ni prix ni recette. Le stock est partagé : ce qu'un suivi
-- prend n'est plus là pour le suivant.
local _, ns = ...

local W, H = 1000, 690
local NODE_W, NODE_H, GAP, TOP = 190, 42, 18, 36 -- l'écart et le haut laissent la place au nom des artisans
local RELAY = 14 -- place réservée à un lien qui traverse un étage
local BAND_GAP = 30 -- entre les rectangles de deux artisans (la place de leur nom)
local MARGIN = 10   -- à gauche et à droite : le rectangle d'un artisan dépasse ses cases de 6
local STEP = NODE_H + GAP
local COLORS = {
  { 0.35, 0.80, 0.45 }, { 0.35, 0.60, 1.00 }, { 0.66, 0.56, 1.00 }, -- sacs, banque, autres persos
  fabriquer = { 0.95, 0.65, 0.25 }, buy = { 0.60, 0.60, 0.62 }, none = { 0.90, 0.30, 0.30 }, target = { 0.66, 0.56, 1.00 },
  apport = { 0.30, 0.80, 0.85 },
}

local frame, content, scroll
-- Vue du dessin : zoom (× l'échelle qui fait tout tenir en largeur) et décalage, en unités du dessin.
local view = { zoom = 1, x = 0, y = 0, fit = 1 }
local function applyView()
  if not content then return end
  view.zoom = math.max(0.25, math.min(3, view.zoom))
  content:SetScale(view.fit * view.zoom)
  content:ClearAllPoints()
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", view.x, view.y) -- décalage dans l'échelle du dessin
end
-- Couleur de chaque artisan, dans l'ordre de la liste (ton perso d'abord) ; rouge = personne ne sait le faire.
local CRAFTER_COLORS = { { 0.66, 0.56, 1.00 }, { 0.30, 0.80, 0.85 }, { 0.95, 0.65, 0.25 }, { 0.95, 0.45, 0.75 }, { 0.45, 0.85, 0.58 } }
local boxes = {}
-- Étiquettes des commandes entre artisans : survol = la liste, clic = en faire une commande à part pour l'artisan.
local orderTags = {}
local function bandName(b) return b == "reste" and "toi" or tostring(b) end
local function newOrderTag()
  local t = CreateFrame("Button", nil, content, "BackdropTemplate")
  t:SetFrameLevel(content:GetFrameLevel() + 5)
  t:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  t:SetBackdropColor(0.08, 0.08, 0.10, 0.95)
  t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  t.text:SetPoint("CENTER")
  t:SetScript("OnEnter", function(self)
    local o = self.order
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(("Livraison : %s pour %s"):format(o.maker, bandName(o.client)))
    GameTooltip:AddLine(o.player and ("Par " .. o.player) or "Personne de ta liste n'a ce métier", 0.8, 0.8, 0.8)
    for _, id in ipairs(o.lines) do GameTooltip:AddLine(("%d× %s"):format(o.qty[id], ns.itemLabel(id)), 1, 1, 1) end
    GameTooltip:AddLine("Pour la commander : « Commander » sur le titre du bloc", 0.66, 0.56, 1)
    GameTooltip:Show()
  end)
  t:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return t
end
local cards, lines, labels = {}, {}, {}

local function opts() return HandshakeDB.options end
local function projet() return ns.projetCourant() end
-- Affichage seulement (« il le fournit », « mon prix ») : ce qui se modifie, la fenêtre le demande au projet (ns.projetPeut).
local function replying() return projet().reponse ~= nil end -- « je réponds » : la demande d'un autre
local function lignes() return (ns.projetPeut(projet(), "lignes")) end -- ajouter, retirer, changer une quantité
-- La commande choisie dans le projet affiché (1 = tout le projet) : Joueur, Offre, « Préparer la demande » et « En clair »
-- portent sur elle. Un autre projet affiché : retour à 1.
local choisie = {}
local function laCommande()
  if choisie.p ~= projet() then choisie.p, choisie.i = projet(), 1 end
  return choisie.i
end
local function commande() return ns.projetCommande(projet(), laCommande()) end

---------------------------------------------------------------------------------------------------
-- Hauteurs. Chaque case (ou relais) vise le milieu de ses voisins, sans chevauchement (de gauche à droite, puis retour).
-- Un relais ne prend que la hauteur d'un lien. bands (facultatif) = clés de bande dans l'ordre, n.band sur chaque nœud :
-- chaque bande est placée seule (voisins de sa bande seulement), puis les bandes sont empilées, BAND_GAP entre elles.
-- Une bande tient donc dans un rectangle ; un lien d'une bande à l'autre ne passe qu'entre deux étages.
function ns.layoutGraph(g, bands)
  local last, up, down = g.cols - 1, g.up, g.down
  local function half(n) return n.kind == "relay" and RELAY / 2 or NODE_H / 2 end
  local function size(n) return n.kind == "relay" and RELAY or STEP end
  local function bandOf(n) -- (pas « bands and n.band or 1 » : la bande « personne » a la clé false)
    if bands then return n.band end
    return 1
  end
  local offset, any = 0, false
  for _, key in ipairs(bands or { 1 }) do
    local cols, members = {}, {}
    for c = 0, last do cols[c] = {} end
    for _, n in ipairs(g.all) do
      if bandOf(n) == key then table.insert(cols[n.col], n); members[#members + 1] = n end
    end
    if #members > 0 then
      local function aim(n, around, fallback)
        local s, k = 0, 0
        for _, v in ipairs(around) do
          if bandOf(v) == key then s, k = s + v.y + half(v), k + 1 end
        end
        if k == 0 then return fallback end
        return s / k - half(n)
      end
      local function place(col)
        table.sort(col, function(a, b) if a.w ~= b.w then return a.w < b.w end return a.key < b.key end)
        local prev
        for _, n in ipairs(col) do
          n.y = (prev and n.w < prev.y + size(prev)) and prev.y + size(prev) or n.w
          prev = n
        end
      end
      table.sort(cols[0], function(a, b) return (a.index or 0) < (b.index or 0) end)
      for i, n in ipairs(cols[0]) do n.w = (i - 1) * STEP end
      place(cols[0])
      for c = 1, last do
        for _, n in ipairs(cols[c]) do n.w = aim(n, up[n], 0) end
        place(cols[c])
      end
      for c = last - 1, 0, -1 do
        for _, n in ipairs(cols[c]) do n.w = aim(n, down[n], n.y) end
        place(cols[c])
      end
      local minY, maxY = math.huge, -math.huge
      for _, n in ipairs(members) do minY, maxY = math.min(minY, n.y), math.max(maxY, n.y + 2 * half(n)) end
      if any then offset = offset + BAND_GAP end
      for _, n in ipairs(members) do n.y = n.y - minY + offset end
      offset, any = offset + maxY - minY, true
    end
  end
  g.height = offset
end

-- Le dessin de l'arbre d'un projet (res = ns.projetArbre, Projet.lua), sans rien afficher (testé hors jeu dans check.lua).
-- Étages : les lignes du projet en 0, un objet juste à droite de son parent le plus à droite. Bandes : un bloc = ses
-- cases + ce qui n'est pas fabriqué sous elles (rattaché à son premier parent), puis le reste (acheté ou en stock).
-- Chaque bloc reçoit sa couleur (index), son titre (label) et ses cases dessinées (cards).
function ns.dessinArbre(res)
  local list, edges = res.cases, res.liens
  local last = 0
  for _, n in ipairs(list) do n.col = n.kind == "target" and 0 or 1 end
  for _ = 1, #list do -- ponytail: relaxation O(n²), assez pour quelques dizaines de cases ; s'arrête sur une boucle
    local changed = false
    for _, n in ipairs(list) do
      if n.kind == "item" then
        local c = 1
        for _, p in ipairs(n.parents) do c = math.max(c, p.col + 1) end
        if c ~= n.col then n.col, changed = c, true end
      end
    end
    if not changed then break end
  end
  for _, n in ipairs(list) do last = math.max(last, n.col) end

  -- Un lien qui saute des étages passe par un relais dans chacun (pas de case, juste sa place) : les cases de ces
  -- étages s'écartent pour lui, et il ne passe jamais sous une case. e.path = départ, relais…, arrivée.
  local all, up, down = {}, {}, {}
  for _, n in ipairs(list) do all[#all + 1], up[n], down[n] = n, {}, {} end
  for _, e in ipairs(edges) do
    e.path = { e.from }
    for c = e.from.col + 1, e.to.col - 1 do
      local r = { key = "R" .. e.from.key .. ">" .. e.to.key .. ":" .. c, kind = "relay", col = c }
      all[#all + 1], up[r], down[r] = r, {}, {}
      e.path[#e.path + 1] = r
    end
    e.path[#e.path + 1] = e.to
    for i = 2, #e.path do
      table.insert(down[e.path[i - 1]], e.path[i]); table.insert(up[e.path[i]], e.path[i - 1])
    end
    e.first, e.last = e.path[2], e.path[#e.path - 1]
  end
  local g = { nodes = list, edges = edges, cols = last + 1, byKey = res.caseDe, all = all, up = up, down = down,
    groups = res.blocs, groupOf = res.blocDe, livraisons = res.livraisons }

  local blocOf = {}
  for _, grp in ipairs(res.blocs) do for _, n in ipairs(grp.cases) do blocOf[n] = grp.key end end
  local sorted = {}
  for _, n in ipairs(all) do sorted[#sorted + 1] = n end
  table.sort(sorted, function(x, y) return x.col < y.col end)
  for _, n in ipairs(sorted) do
    if blocOf[n] then n.band = blocOf[n]
    else
      n.band = "reste"
      for _, p in ipairs(up[n]) do if p.band ~= nil then n.band = p.band break end end
    end
  end
  local order = {}
  for i, grp in ipairs(g.groups) do
    grp.index, order[#order + 1] = i, grp.key
    local who = {}
    for _, c in ipairs(grp.crafters) do who[#who + 1] = ("%s %d (%d/%d)"):format(c.name, c.rank, c.known, #grp.recipes) end
    grp.label = ("Étape %d · %s%s · %s"):format(grp.step, grp.key, grp.level > 0 and (" · niv. " .. grp.level .. " requis") or "",
      #who > 0 and table.concat(who, ", ") or "personne de ta liste")
    grp.cards = {}
    for _, n in ipairs(list) do if n.band == grp.key then grp.cards[#grp.cards + 1] = n end end
  end
  order[#order + 1] = "reste"
  ns.layoutGraph(g, order)
  return g
end

-- Suggestions pour la barre de recherche : objets du catalogue et recettes dont l'objet n'a pas encore de nom.
-- Fabricables d'abord, puis ceux qui commencent par le texte tapé, puis les noms courts.
function ns.itemIndex()
  local craft, index = {}, {}
  for _, r in pairs(ns.recipes()) do
    if r.output then craft[r.output] = r.name or craft[r.output] or true end
  end
  local items = ns.items()
  for id, it in pairs(items) do
    if it.name then index[#index + 1] = { id = id, name = it.name, low = it.name:lower(), craft = craft[id] ~= nil } end
  end
  for id, rname in pairs(craft) do
    if type(rname) == "string" and not (items[id] and items[id].name) then
      index[#index + 1] = { id = id, name = rname, low = rname:lower(), craft = true }
    end
  end
  return index
end

-- ponytail: :lower() ne connaît pas les accents (« É » reste « É ») ; taper en minuscules marche
function ns.suggestItems(index, text, max)
  local q = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if #q < 2 then return {} end
  local hits = {}
  for _, e in ipairs(index) do
    local at = e.low:find(q, 1, true)
    if at then hits[#hits + 1] = { e = e, s = (e.craft and 0 or 2) + (at == 1 and 0 or 1) } end
  end
  table.sort(hits, function(a, b)
    if a.s ~= b.s then return a.s < b.s end
    if #a.e.name ~= #b.e.name then return #a.e.name < #b.e.name end
    return a.e.id < b.e.id
  end)
  local out = {}
  for i = 1, math.min(max or 8, #hits) do out[i] = hits[i].e end
  return out
end

---------------------------------------------------------------------------------------------------
-- Dessin
local function stocked(n) return n.have[1] + n.have[2] + n.have[3] end

local function stateColor(n)
  if n.kind == "target" then return COLORS.target end
  if n.made > 0 then return COLORS.fabriquer end
  if n.apport > 0 and n.need == 0 then return COLORS.apport end
  if n.unpriced then return COLORS.none end
  if n.need == 0 then return COLORS[1] end
  return COLORS.buy
end

-- Maj+clic : la recette dans la fenêtre de métier du jeu. Seulement une fois la fenêtre chargée par le jeu
-- (Mastercraft fait pareil : l'ouvrir avant casse la fenêtre) et si ce perso-ci connaît la recette.
local function openRecipe(n)
  local key = n.recipeKey
  if type(key) ~= "number" then return print("Commandes : pas de recette à ouvrir pour " .. ns.itemLabel(n.id) .. ".") end
  for _, prof in pairs(ns.knownRecipes()[ns.charKey()] or {}) do
    if prof.known and prof.known[key] then
      local loaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
      if not (loaded and loaded("Blizzard_Professions")) then return print("Commandes : ouvre une fois ta fenêtre de métier, puis Maj+clic.") end
      return C_TradeSkillUI.OpenRecipe(key)
    end
  end
  local who = {}
  for k, metiers in pairs(ns.knownRecipes()) do
    for _, prof in pairs(metiers) do if prof.known and prof.known[key] then who[#who + 1] = k:match("^[^%-]+") end end
  end
  print(("Commandes : %s — %s."):format(n.recipe and n.recipe.name or "recette",
    #who > 0 and ("connue de " .. table.concat(who, ", ") .. ", pas de ce perso") or "aucun de tes persos ne la connaît"))
end

-- Ce que fait un clic sur la case : revenir au calcul si le choix était forcé, sinon forcer l'inverse.
local function toggleOf(n)
  if n.apport > 0 then return end -- fourni par toi : Ctrl+clic pour le reprendre
  if n.choix then return "reset" end
  if n.made > 0 then return "acheter" end
  if n.craftable then return "fabriquer" end -- même en stock : « + » le fabrique au lieu de le prendre
end

local function newCard()
  local c = CreateFrame("Button", nil, content, "BackdropTemplate")
  c:SetFrameLevel(content:GetFrameLevel() + 3) -- au-dessus des cadres d'artisans
  c:SetSize(NODE_W, NODE_H)
  c:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  c:SetBackdropColor(0.11, 0.11, 0.14, 0.95)
  c:SetBackdropBorderColor(1, 1, 1, 0.08)
  c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  c.accent = c:CreateTexture(nil, "ARTWORK")
  c.accent:SetPoint("TOPLEFT", 1, -1)
  c.accent:SetPoint("BOTTOMLEFT", 1, 1)
  c.accent:SetWidth(3)
  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(26, 26)
  c.icon:SetPoint("TOPLEFT", 8, -5)
  c.name = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  c.name:SetPoint("TOPLEFT", 40, -6)
  c.name:SetPoint("RIGHT", -20, 0)
  c.name:SetJustifyH("LEFT")
  c.name:SetWordWrap(false)
  c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  c.sub:SetPoint("TOPLEFT", 40, -20)
  c.sub:SetPoint("RIGHT", -6, 0)
  c.sub:SetJustifyH("LEFT")
  c.sub:SetWordWrap(false)
  -- Quantité commandée (cases de la colonne 0) : à taper, ou molette (Maj = par 10). Grisée si le projet
  -- ne permet pas de changer ses lignes (une réponse).
  c.qty = CreateFrame("EditBox", nil, c)
  c.qty:SetSize(36, 14); c.qty:SetPoint("TOPLEFT", 40, -19)
  c.qty:SetFontObject(GameFontHighlightSmall); c.qty:SetAutoFocus(false); c.qty:SetNumeric(true); c.qty:SetMaxLetters(4)
  c.qty:SetTextInsets(10, 2, 0, 0)
  local qbg = c.qty:CreateTexture(nil, "BACKGROUND"); qbg:SetAllPoints(); qbg:SetColorTexture(1, 1, 1, 0.08)
  local x = c.qty:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"); x:SetPoint("LEFT", 2, 0); x:SetText("×")
  local function setQty(q)
    local n = c.node
    if not (n and n.kind == "target") then return end
    ns.projetQuantite(projet(), n.index, q)
    ns.refreshCraftWindow()
  end
  c.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  c.qty:SetScript("OnEscapePressed", function(self) self.cancel = true; self:ClearFocus() end)
  c.qty:SetScript("OnEditFocusLost", function(self)
    if self.cancel then self.cancel = nil; return ns.refreshCraftWindow() end
    setQty(tonumber(self:GetText()))
  end)
  c.qty:SetScript("OnMouseWheel", function(self, d)
    local n = c.node
    if n and n.kind == "target" then setQty(math.max(1, n.qty + d * (IsShiftKeyDown() and 10 or 1))) end
  end)
  c.toggle = c:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  c.toggle:SetPoint("TOPRIGHT", -6, -2)
  c.barBg = c:CreateTexture(nil, "ARTWORK")
  c.barBg:SetColorTexture(1, 1, 1, 0.08)
  c.barBg:SetPoint("BOTTOMLEFT", 40, 5)
  c.barBg:SetSize(NODE_W - 48, 4)
  c.seg = {}
  for i = 1, 6 do c.seg[i] = c:CreateTexture(nil, "OVERLAY") end
  c:SetScript("OnEnter", function(self)
    local n = self.node
    if not n then return end
    self:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.6)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(n.id)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(("Il en faut %d"):format(n.qty), 1, 1, 1)
    if stocked(n) > 0 then GameTooltip:AddLine(("En stock : %d sacs, %d banque, %d autres persos"):format(n.have[1], n.have[2], n.have[3]), 0.35, 0.8, 0.45) end
    if n.made > 0 then
      GameTooltip:AddLine(("À fabriquer : %d — %s ×%d, %s"):format(n.made, n.recipe and n.recipe.name or "?", n.crafts, ns.money(n.madeCost)), 0.95, 0.65, 0.25)
      if n.who then GameTooltip:AddLine(("Par %s%s"):format(n.who, n.whoKnows and "" or " (a le métier, recette à apprendre)"), 0.66, 0.56, 1)
      elseif n.who == false then GameTooltip:AddLine("Personne de ta liste n'a ce métier", 0.9, 0.3, 0.3) end
      if n.unknown then GameTooltip:AddLine("Recette pas encore apprise", 0.9, 0.3, 0.3)
      elseif type(n.recipeKey) == "number" then GameTooltip:AddLine("Maj+clic : ouvrir la recette dans la fenêtre de métier", 0.6, 0.6, 0.6) end
      if n.buy then GameTooltip:AddLine("Acheter tout fait coûterait " .. ns.money(n.buy), 0.7, 0.7, 0.7) end
    end
    if n.need > 0 then
      GameTooltip:AddLine(n.unpriced and ("À trouver : %d — ni prix ni recette"):format(n.need)
        or ("À acheter : %d — %s, %s"):format(n.need, n.how == "marchand" and "marchand" or "HV", ns.money(n.cost)), 0.8, 0.8, 0.8)
    end
    if n.incomplete then GameTooltip:AddLine("Coût incomplet : un composant n'a ni prix ni recette (en rouge)", 0.9, 0.3, 0.3) end
    if n.partial then GameTooltip:AddLine("Pas assez en vente à l'HV : le reste est compté au dernier prix vu", 0.9, 0.6, 0.3) end
    local t = toggleOf(n)
    if t == "reset" then GameTooltip:AddLine("Choix forcé à la main — clic : revenir au calcul des prix", 0.66, 0.56, 1)
    elseif t == "acheter" then GameTooltip:AddLine("Clic : l'acheter tout fait au lieu de le fabriquer", 0.6, 0.6, 0.6)
    elseif t == "fabriquer" then
      GameTooltip:AddLine(n.need == 0 and "Clic : le fabriquer au lieu de prendre ton stock" or "Clic : le décomposer (fabriquer) même si c'est plus cher", 0.6, 0.6, 0.6)
    end
    local who = replying() and "Il le fournit" or "Tu le fournis"
    if n.apport > 0 then GameTooltip:AddLine(("%s : %d (Ctrl+clic pour le reprendre)"):format(who, n.apport), 0.3, 0.8, 0.85)
    elseif n.kind ~= "target" then GameTooltip:AddLine("Ctrl+clic : " .. who:lower(), 0.6, 0.6, 0.6) end
    if n.kind == "target" and lignes() then GameTooltip:AddLine("Clic droit : ne plus suivre", 0.6, 0.6, 0.6) end
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(1, 1, 1, 0.08); GameTooltip:Hide() end)
  c:SetScript("OnClick", function(self, button)
    local n = self.node
    if button == "RightButton" then
      if n.kind ~= "target" or not ns.projetRetirer(projet(), n.index) then return end
    elseif IsShiftKeyDown() then
      return openRecipe(n)
    elseif IsControlKeyDown() and n.kind ~= "target" then -- « je le fournis » : apport de la demande
      ns.projetApport(projet(), n.id, n.apport == 0)
    else
      local t = toggleOf(n)
      if not t then return end
      ns.projetChoix(projet(), n.id, t ~= "reset" and t or nil)
    end
    ns.refreshCraftWindow()
    if self:IsMouseOver() then self:GetScript("OnEnter")(self) end
  end)
  return c
end

-- Barre : sacs, banque, autres persos, à fabriquer, à acheter (rouge si sans prix).
local function bar(c, n)
  local parts = { n.have[1], n.have[2], n.have[3], n.made, n.need, n.apport }
  local tints = { COLORS[1], COLORS[2], COLORS[3], COLORS.fabriquer, n.unpriced and COLORS.none or COLORS.buy, COLORS.apport }
  local left, wmax = 40, NODE_W - 48
  for i = 1, 6 do
    local wpx = n.qty > 0 and wmax * parts[i] / n.qty or 0
    local seg = c.seg[i]
    if wpx >= 1 then
      local k = tints[i]
      seg:SetColorTexture(k[1], k[2], k[3], 0.9)
      seg:ClearAllPoints()
      seg:SetPoint("BOTTOMLEFT", left, 5)
      seg:SetSize(wpx, 4)
      seg:Show()
      left = left + wpx
    else
      seg:Hide()
    end
  end
end

local function subText(n)
  local s = n.kind == "target" and "" or ("×" .. n.qty) -- la commande a son champ de quantité
  if stocked(n) > 0 then s = s .. (" |cff59cc73%d stock|r"):format(stocked(n)) end
  if n.made > 0 then s = s .. (n.unknown and " |cffe64d4d%d à fab.|r" or " |cffe6a640%d à fab.|r"):format(n.made) end
  if n.need > 0 then
    s = s .. (n.unpriced and (" |cffe64d4d%d sans prix|r"):format(n.need) or (" %d %s"):format(n.need, n.how == "marchand" and "marchand" or "HV"))
  end
  local cost = n.madeCost + n.cost
  if cost > 0 then s = s .. " · " .. ns.moneyShort(cost) end
  if n.apport > 0 then s = s .. (" |cff4dccd9%d fourni par %s|r"):format(n.apport, replying() and "lui" or "toi") end
  if n.incomplete then s = s .. " |cffe64d4d+ ?|r" end
  return s
end

local usedLines, usedLabels = 0, 0
local function segment(x1, y1, x2, y2, col, thick)
  usedLines = usedLines + 1
  local l = lines[usedLines] or content:CreateLine(nil, "BACKGROUND")
  lines[usedLines] = l
  l:SetThickness(thick)
  l:SetColorTexture(col[1], col[2], col[3], 0.45)
  l:SetStartPoint("TOPLEFT", content, x1, -y1)
  l:SetEndPoint("TOPLEFT", content, x2, -y2)
  l:Show()
end

-- Courbe en S entre deux cases (8 segments), quantité juste avant la case d'arrivée.
local function curve(x1, y1, x2, y2, col, qty, thick)
  local px, py = x1, y1
  for i = 1, 8 do
    local t = i / 8
    local s = t * t * (3 - 2 * t)
    local x, y = x1 + (x2 - x1) * t, y1 + (y2 - y1) * s
    segment(px, py, x, y, col, thick or 2)
    px, py = x, y
  end
  if not qty then return end -- tronçon avant un relais : la quantité n'est écrite qu'à l'arrivée
  usedLabels = usedLabels + 1
  local f = labels[usedLabels] or content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  labels[usedLabels] = f
  f:ClearAllPoints()
  f:SetPoint("RIGHT", content, "TOPLEFT", x2 - 3, -y2 + 6)
  f:SetText("×" .. qty)
  f:Show()
end

local headers = {}
local function header(i, x, text)
  local h = headers[i] or content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  headers[i] = h
  h:ClearAllPoints()
  h:SetPoint("TOPLEFT", content, "TOPLEFT", MARGIN + x, 0)
  h:SetText(text)
  h:Show()
end

local function refresh()
  if not (frame and frame:IsShown()) then return end
  local res = ns.projetArbre(projet())
  local roots, market, total, incomplete, g = res.roots, res.market, res.total, res.incomplete, ns.dessinArbre(res)
  if frame.syncOrder then frame.syncOrder() end
  if ns.refreshNeeds then ns.refreshNeeds(res) end

  -- Les étages s'étalent sur la largeur ; trop nombreux, le dessin rétrécit pour tenir (puis molette pour zoomer).
  local avail = scroll:GetWidth()
  if avail < 100 then avail = W - 28 end -- pas encore mis en page
  local spacing = g.cols > 1 and math.max(NODE_W + 60, (avail - NODE_W - 2 * MARGIN) / (g.cols - 1)) or 0
  local width = NODE_W + spacing * (g.cols - 1) + 2 * MARGIN
  view.fit = math.min(1, avail / width)
  content:SetSize(width, math.max(1, (g.height + TOP + 10)))
  applyView()

  for _, h in ipairs(headers) do h:Hide() end
  if #roots == 0 then
    header(1, 0, "|cff999999Tape un nom (suggestions), dépose un objet, ou Maj+clic sur un lien, puis Ajouter ; ou Importer une liste reçue.|r")
  else
    local o, cost = projet(), ns.moneyShort(total) .. (incomplete and " |cffe64d4d+ ?|r" or "")
    if replying() then -- ma part, mon prix, ce qui reste pour mon travail
      local price = ns.projetCommande(o).tip or 0
      header(1, 0, ("Ma part · %s · mon prix %s · travail %s"):format(cost, ns.moneyShort(price), ns.moneySigned(price - total)))
    else
      header(1, 0, "Projet · " .. cost)
    end
    for c = 1, g.cols - 1 do header(c + 1, spacing * c, "Étage " .. c) end
  end

  local x = function(n) return MARGIN + n.col * spacing end
  for i, n in ipairs(g.nodes) do
    local c = cards[i] or newCard()
    cards[i] = c
    c.node = n
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", content, "TOPLEFT", x(n), -(n.y + TOP))
    local k = stateColor(n)
    c.accent:SetColorTexture(k[1], k[2], k[3], 0.9)
    c.icon:SetTexture(C_Item.GetItemIconByID(n.id))
    c.name:SetText(ns.itemLabel(n.id))
    c.sub:SetText((subText(n):gsub("^ ", "")))
    local target = n.kind == "target"
    c.qty:SetShown(target); c.qty:SetEnabled(target and lignes())
    if target and not c.qty:HasFocus() then c.qty:SetText(n.qty) end
    c.sub:SetPoint("TOPLEFT", target and 80 or 40, -20)
    local t = toggleOf(n)
    local sign = (n.made > 0 and "–") or (t and "+") or ""
    c.toggle:SetText(n.choix and ("|cffa98fff" .. sign .. "|r") or sign)
    bar(c, n)
    c:Show()
  end
  for i = #g.nodes + 1, #cards do cards[i]:Hide() end

  -- Un rectangle par artisan : toutes ses cases (et ce qui n'est pas fabriqué sous elles), à sa couleur, son nom
  -- au-dessus (et « recette à apprendre »). Rouge : personne de ta liste ne sait le faire.
  local usedBoxes, boxOf = 0, {}
  for _, grp in ipairs(g.groups or {}) do
    local top, bottom, left, right = math.huge, -math.huge, math.huge, -math.huge
    for _, n in ipairs(grp.cards) do
      top, bottom = math.min(top, n.y), math.max(bottom, n.y + NODE_H)
      left, right = math.min(left, x(n)), math.max(right, x(n) + NODE_W)
    end
    usedBoxes = usedBoxes + 1
    local b = boxes[usedBoxes]
    if not b then
      b = CreateFrame("Frame", nil, content, "BackdropTemplate")
      b:SetFrameLevel(content:GetFrameLevel() + 1)
      b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      b.name:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 4, 2)
      -- Survol du nom : les recettes du métier, leur niveau requis, qui les connaît ; puis qui a le métier.
      b.hit = CreateFrame("Button", nil, b)
      b.hit:SetAllPoints(b.name)
      b.hit:SetScript("OnEnter", function(self)
        local grp = b.grp
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(grp.key)
        for _, r in ipairs(grp.recipes) do
          GameTooltip:AddDoubleLine(r.name .. (r.level and (" |cff999999(" .. r.level .. ")|r") or ""),
            #r.known > 0 and table.concat(r.known, ", ") or "à apprendre", 1, 1, 1, #r.known > 0 and 0.35 or 0.9, #r.known > 0 and 0.8 or 0.3, #r.known > 0 and 0.45 or 0.3)
        end
        GameTooltip:AddLine(" ")
        if #grp.crafters == 0 then GameTooltip:AddLine("Personne de ta liste n'a ce métier", 0.9, 0.3, 0.3) end
        for _, c in ipairs(grp.crafters) do
          GameTooltip:AddLine(("%s : niveau %d, %d recette%s sur %d"):format(c.name, c.rank, c.known, c.known > 1 and "s" or "", #grp.recipes), 0.66, 0.56, 1)
        end
        GameTooltip:Show()
      end)
      b.hit:SetScript("OnLeave", function() GameTooltip:Hide() end)
      -- « Commander » : tout le bloc en une commande du projet — ce qu'il livre, et ce qu'il reçoit des autres blocs en
      -- apport. Elle s'ajoute à la liste des commandes, sur la même page.
      b.cmd = CreateFrame("Button", nil, b, "BackdropTemplate")
      b.cmd:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
      b.cmd:SetBackdropColor(0.16, 0.15, 0.25, 0.95)
      b.cmd.text = b.cmd:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.cmd.text:SetPoint("CENTER")
      b.cmd.text:SetText("Commander")
      b.cmd:SetSize(b.cmd.text:GetStringWidth() + 14, 16)
      b.cmd:SetPoint("LEFT", b.name, "RIGHT", 8, 0)
      b.cmd:SetScript("OnEnter", function(self)
        local grp = b.grp
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(("Commander le bloc %s%s"):format(grp.key, grp.best and (" à " .. grp.best) or ""))
        for _, id in ipairs(grp.deliver) do GameTooltip:AddLine(("%d× %s"):format(grp.qty[id], ns.itemLabel(id)), 1, 1, 1) end
        local brought = {}
        for id in pairs(grp.inputs) do brought[#brought + 1] = ns.itemLabel(id) end
        if #brought > 0 then GameTooltip:AddLine("Tu fournis : " .. table.concat(brought, ", "), 0.3, 0.8, 0.85, true) end
        GameTooltip:AddLine("Clic : une commande de ce bloc, ajoutée aux commandes du projet", 0.66, 0.56, 1)
        GameTooltip:Show()
      end)
      b.cmd:SetScript("OnLeave", function() GameTooltip:Hide() end)
      b.cmd:SetFontString(b.cmd.text) -- (GetText, pour les tests du simulateur)
      b.cmd:SetScript("OnClick", function()
        choisie.p, choisie.i = projet(), ns.projetCommander(projet(), b.grp)
        print(("Commandes : le bloc %s est dans les commandes du projet."):format(b.grp.key))
        ns.refreshCraftWindow()
      end)
      boxes[usedBoxes] = b
    end
    local k = #grp.crafters > 0 and CRAFTER_COLORS[(grp.index - 1) % #CRAFTER_COLORS + 1] or COLORS.none
    boxOf[grp.key], b.color = b, k
    b:SetBackdropColor(k[1], k[2], k[3], 0.06)
    b:SetBackdropBorderColor(k[1], k[2], k[3], 0.7)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", content, "TOPLEFT", left - 6, -(top + TOP) + 6)
    b:SetSize(right - left + 12, bottom - top + 12)
    b.name:SetTextColor(k[1], k[2], k[3])
    b.name:SetText(grp.label)
    b.grp = grp
    b:Show()
  end
  for i = usedBoxes + 1, #boxes do boxes[i]:Hide() end

  -- Chaque courbe part et arrive à sa propre hauteur sur le bord de la case, dans l'ordre des cases d'en face :
  -- pas de croisement au départ, et les quantités ne se marchent pas dessus.
  -- ponytail: au-delà de 3 courbes sur un même bord, les quantités se rapprochent trop ; agrandir NODE_H si ça arrive
  local outs, ins, drawn = {}, {}, {}
  for _, e in ipairs(g.edges) do -- une livraison entre blocs : un seul lien (le premier), épais
    if not e.livraison or e.livraison.edges[1] == e then drawn[#drawn + 1] = e end
  end
  for _, e in ipairs(drawn) do
    outs[e.from] = outs[e.from] or {}
    ins[e.to] = ins[e.to] or {}
    table.insert(outs[e.from], e)
    table.insert(ins[e.to], e)
  end
  local function spread(map, field, other)
    for _, es in pairs(map) do
      table.sort(es, function(a, b)
        if a[other].y ~= b[other].y then return a[other].y < b[other].y end
        return a[other].key < b[other].key
      end)
      for i, e in ipairs(es) do e[field] = NODE_H * i / (#es + 1) end
    end
  end
  spread(outs, "dy1", "first")
  spread(ins, "dy2", "last")
  usedLines, usedLabels = 0, 0
  local usedTags = 0
  for _, e in ipairs(drawn) do
    local k = stateColor(e.to)
    local thick = e.livraison and 4 or 2
    if e.livraison then
      local grp = g.groupOf[e.livraison.maker]
      k = #grp.crafters > 0 and CRAFTER_COLORS[(grp.index - 1) % #CRAFTER_COLORS + 1] or COLORS.none
    end
    local px, py = x(e.from) + NODE_W, e.from.y + TOP + e.dy1
    for i = 2, #e.path - 1 do -- relais : on y entre, on traverse l'étage tout droit, on en ressort
      local r = e.path[i]
      local ry = r.y + TOP + RELAY / 2
      curve(px, py, x(r), ry, k, nil, thick)
      segment(x(r), ry, x(r) + NODE_W, ry, k, thick)
      px, py = x(r) + NODE_W, ry
    end
    local ex, ey = x(e.to), e.to.y + TOP + e.dy2
    curve(px, py, ex, ey, k, not e.livraison and e.qty or nil, thick)
  end
  -- Étiquettes des commandes : sur la ligne de titre du rectangle du métier qui fabrique, à la suite du titre (jamais
  -- sur une case ni sur le titre ; elles peuvent dépasser à droite du rectangle, la ligne de titre y est libre).
  local shelf = {}
  for _, o in ipairs(g.livraisons) do
    local b = boxOf[o.maker]
    if b then
      usedTags = usedTags + 1
      local t = orderTags[usedTags] or newOrderTag()
      orderTags[usedTags] = t
      t.order = o
      local first = o.lines[1]
      t.text:SetText(("pour %s · %d× %s%s"):format(bandName(o.client), o.qty[first], ns.itemLabel(first),
        #o.lines > 1 and (" +" .. (#o.lines - 1)) or ""))
      t:SetSize(t.text:GetStringWidth() + 12, 16)
      local k = b.color
      t:SetBackdropBorderColor(k[1], k[2], k[3], 0.9)
      t:ClearAllPoints()
      t:SetPoint("LEFT", shelf[b] or b.cmd, "RIGHT", 6, 0)
      shelf[b] = t
      t:Show()
    end
  end
  for i = usedTags + 1, #orderTags do orderTags[i]:Hide() end
  for i = usedLines + 1, #lines do lines[i]:Hide() end
  for i = usedLabels + 1, #labels do labels[i]:Hide() end

  frame.status:SetText((market and ("HV du " .. market.scanned) or "HV jamais scanné : ouvre l'hôtel des ventes")
    .. " · « + » décompose, « – » achète tout fait (violet = ton choix) · molette : zoom, glisser : déplacer, clic milieu : ajuster")
end
ns.refreshCraftWindow = refresh
-- L'état des commandes (un contrat a bougé) : la liste des commandes seulement, pas l'arbre.
function ns.syncCommandes() if frame and frame:IsShown() then frame.syncOrder() end end

---------------------------------------------------------------------------------------------------
local function track(id, qty)
  if not id then return end
  local ok, raison = ns.projetAjouter(projet(), id, qty)
  if not ok then return print("Commandes : " .. raison .. " (Nouvelle pour un projet à toi).") end
  refresh()
end

-- Barre de recherche avec suggestions : flèches haut/bas, Entrée ou Tab pour choisir, ou clic.
local function searchBox(qty)
  local name = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  name:SetSize(280, 22)
  name:SetAutoFocus(false)
  local drop = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  drop:SetPoint("TOPLEFT", name, "BOTTOMLEFT", -6, -2)
  drop:SetSize(320, 10)
  drop:SetFrameStrata("DIALOG")
  drop:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  drop:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
  drop:SetBackdropBorderColor(0.66, 0.56, 1.00, 0.35)
  drop:Hide()
  local buttons, hits, sel, index = {}, {}, 1, nil
  local function qtyValue() return math.max(1, tonumber(qty:GetText()) or 1) end
  local function pick(e)
    track(e.id, qtyValue())
    name:SetText("")
    name:ClearFocus()
    drop:Hide()
  end
  local function paint()
    for i, b in ipairs(buttons) do b.hl:SetShown(i == sel) end
  end
  for i = 1, 8 do
    local b = CreateFrame("Button", nil, drop)
    b:SetSize(316, 20)
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
    index = index or ns.itemIndex()
    hits, sel = ns.suggestItems(index, name:GetText(), 8), 1
    for i, b in ipairs(buttons) do
      local e = hits[i]
      b:SetShown(e ~= nil)
      if e then
        b.icon:SetTexture(C_Item.GetItemIconByID(e.id))
        b.text:SetText(e.name .. (e.craft and "  |cffe6a640fabricable|r" or ""))
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
  name:SetScript("OnEditFocusGained", function() index = ns.itemIndex() end) -- le catalogue grossit pendant le scan
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
  if ChatEdit_InsertLink then -- Maj+clic sur un objet quand le champ a le focus : son lien y arrive
    hooksecurefunc("ChatEdit_InsertLink", function(link)
      if name:HasFocus() and link then name:SetText(link); drop:Hide() end
    end)
  end
  return name, submit
end

local function build()
  frame = ns.newWindow("HandshakeFrame", "Commandes", W, H)
  local function button(text, w, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end
  local function input(w, onChange)
    local e = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    e:SetSize(w, 22)
    e:SetAutoFocus(false)
    e:SetScript("OnTextChanged", function(self, user) if user then onChange(self:GetText()) end end)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    return e
  end
  local function label(text, anchor, gap)
    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("LEFT", anchor, "RIGHT", gap or 12, 0)
    t:SetText(text)
    return t
  end

  -- Le projet affiché (Projet.lua) : < et >, nom, joueur d'en face, offre.
  local function switch(d)
    ns.changerProjet(d)
    refresh()
  end
  local prevB = button("<", 24, function() switch(-1) end)
  prevB:SetPoint("TOPLEFT", 14, -40)
  local orderName = input(190, function(v) ns.projetRenommer(projet(), v) end)
  orderName:SetPoint("LEFT", prevB, "RIGHT", 10, 0)
  local nextB = button(">", 24, function() switch(1) end)
  nextB:SetPoint("LEFT", orderName, "RIGHT", 4, 0)
  local count = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  count:SetPoint("LEFT", nextB, "RIGHT", 6, 0)
  local newB = button("Nouvelle", 80, function() ns.nouveauProjet(); refresh() end)
  newB:SetPoint("LEFT", nextB, "RIGHT", 44, 0)
  local delB = button("Supprimer", 84, function()
    if not IsShiftKeyDown() then return print("Commandes : Maj+clic sur « Supprimer » pour effacer ce projet.") end
    ns.supprimerProjet()
    refresh()
  end)
  delB:SetPoint("LEFT", newB, "RIGHT", 4, 0)
  local playerL = label("Joueur", delB, 16)
  local player = input(120, function(v) ns.projetArtisan(projet(), v, laCommande()); frame.syncOrder() end)
  player:SetPoint("LEFT", playerL, "RIGHT", 10, 0)
  local tipL = label("Offre", player, 14)
  local tip = input(48, function(v)
    local n = tonumber((v:gsub(",", ".")))
    ns.projetOffre(projet(), n and math.floor(n * 10000 + 0.5) or nil, laCommande())
    if replying() and laCommande() == 1 then return refresh() end -- l'en-tête montre ce qui reste pour mon travail
    frame.syncOrder()
    if ns.refreshNeeds then ns.refreshNeeds() end
  end)
  tip:SetPoint("LEFT", tipL, "RIGHT", 10, 0)
  local poL = label("po", tip, 4)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("LEFT", poL, "RIGHT", 12, 0)
  hint:SetText("Ctrl+clic sur une case : je la fournis")
  local contractB -- plus bas, sur la ligne d'ajout
  -- Les commandes du projet, une par bouton : sa part, son artisan et son offre, ou « vide » (son bloc a disparu), puis
  -- son état (lu dans son contrat) ; clic = la choisir.
  local cmdL = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cmdL:SetPoint("TOPLEFT", 14, -164)
  cmdL:SetText("Commandes :")
  local cmdB, actB = {}, {}
  -- À côté d'une commande : « Nouvelle version » (envoyée, sa part du projet a changé ; elle part sur ce clic, jamais
  -- d'office) ou « Commander de nouveau » (refusée, retirée, échue).
  local function agir(self)
    local o = projet()
    if ns.projetCommande(o, self.i).recommander then
      choisie.p, choisie.i = o, ns.projetRecommander(o, self.i)
      return frame.syncOrder()
    end
    local n, err = ns.projetNouvelleVersion(o, self.i)
    if not n then return print("|cffe64d4dContrats :|r " .. err .. ".") end
    frame.syncOrder()
    ns.openContracts(ns.ctKey(n))
  end
  frame.syncOrder = function()
    local o, sel = projet(), laCommande()
    local vues = ns.projetCommandes(o)
    local c = vues[sel]
    if not orderName:HasFocus() then orderName:SetText(o.name or "") end
    if not player:HasFocus() then player:SetText(c.player or "") end
    if not tip:HasFocus() then tip:SetText(c.tip and c.tip > 0 and (ns.poText(c.tip):gsub(" po$", "")) or "") end
    player:SetEnabled(not c.fige); tip:SetEnabled(not c.fige) -- envoyée : son artisan et son offre sont ceux du contrat
    count:SetText(("%d/%d"):format(ns.numeroProjet()))
    tipL:SetText(c.reponse and "Mon prix" or "Offre")
    if frame.apportLegend then frame.apportLegend:SetText(replying() and "fourni par lui" or "fourni par toi") end
    contractB:SetText(c.reponse and "Contre-proposer" or c.fige and "Voir la demande" or "Préparer la demande")
    hint:SetText(replying() and "Ctrl+clic sur une case : il la fournit / je la reprends" or "Ctrl+clic sur une case : je la fournis")
    local prev = cmdL
    for i, v in ipairs(vues) do
      local b = cmdB[i]
      if not b then
        b = button("", 60, function(self) choisie.p, choisie.i = projet(), self.i; frame.syncOrder() end)
        cmdB[i], actB[i] = b, button("", 60, agir)
      end
      b.i = i
      b:ClearAllPoints()
      b:SetPoint("LEFT", prev, "RIGHT", 6, 0)
      -- ponytail: une seule ligne ; au-delà de 4 ou 5 commandes elle dépasse à droite, passer à deux lignes alors
      local text = ("%s · %s%s%s"):format(v.reponse and "réponse" or v.part, v.vide and "vide" or (v.player or "artisan ?"),
        not v.vide and v.tip and v.tip > 0 and (" · " .. ns.moneyShort(v.tip)) or "", v.etat and (" · " .. v.etat) or "")
      b:SetText((i == sel and ("|cffa98fff" .. text .. "|r") or text) .. (v.ecart and (" · |cffe6994d" .. v.ecart .. "|r") or ""))
      b:SetWidth(b:GetTextWidth() + 24)
      b:Show()
      prev = b
      local a, act = actB[i], v.fige and v.ecart and "Nouvelle version" or v.recommander and "Commander de nouveau"
      a.i = i
      a:SetShown(act and true or false)
      if act then
        a:SetText(act)
        a:SetWidth(a:GetTextWidth() + 24)
        a:ClearAllPoints()
        a:SetPoint("LEFT", b, "RIGHT", 2, 0)
        prev = a
      end
    end
    for i = #vues + 1, #cmdB do cmdB[i]:Hide(); actB[i]:Hide() end
  end

  -- Ligne d'ajout : déposer un objet sur la case, ou taper son nom.
  local slot = CreateFrame("Button", nil, frame)
  slot:SetSize(32, 32)
  slot:SetPoint("TOPLEFT", 14, -70)
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetAllPoints()
  slot.icon:SetTexture("Interface\\Buttons\\UI-EmptySlot-Disabled")
  local qty = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  qty:SetSize(44, 22)
  qty:SetAutoFocus(false)
  qty:SetNumeric(true)
  qty:SetText("1")
  local name, submit = searchBox(qty)
  name:SetPoint("LEFT", slot, "RIGHT", 12, 0)
  qty:SetPoint("LEFT", name, "RIGHT", 10, 0)
  local add = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  add:SetSize(80, 22)
  add:SetPoint("LEFT", qty, "RIGHT", 8, 0)
  add:SetText("Ajouter")
  add:SetScript("OnClick", submit)
  local needsB = button("Besoins", 90, function() ns.toggleNeeds() end)
  needsB:SetPoint("TOPRIGHT", -14, -75)
  local sendB = button("En clair", 90, function() ns.sendOrder(commande()) end)
  sendB:SetPoint("RIGHT", needsB, "LEFT", -6, 0)
  local importB = button("Importer", 90, function() ns.openImport() end)
  importB:SetPoint("RIGHT", sendB, "LEFT", -6, 0)
  contractB = button("Préparer la demande", 150, function()
    local c = commande()
    if not c.reponse then -- brouillon de contrat (refait tant qu'il n'est pas parti), ou la demande déjà envoyée
      local ct, err = ns.projetEnvoyer(projet(), laCommande())
      if not ct then return print("|cffe64d4dContrats :|r " .. err .. ".") end
      frame.syncOrder()
      return ns.openContracts(ns.ctKey(ct))
    end
    local n, err = ns.ctReplyFromOrder(c)
    if not n then return print("|cffe64d4dContrats :|r " .. err .. ".") end
    ns.openContracts(ns.ctKey(n))
  end)
  contractB:SetPoint("RIGHT", importB, "LEFT", -6, 0)
  local function dropped()
    local kind, id = GetCursorInfo()
    if kind == "item" then
      ClearCursor()
      track(id, math.max(1, tonumber(qty:GetText()) or 1))
    end
  end
  slot:SetScript("OnReceiveDrag", dropped)
  slot:SetScript("OnClick", dropped)

  -- Options, à droite de la ligne d'ajout
  local labelsOpt = { { "bags", "Déduire mes sacs" }, { "bank", "ma banque" }, { "alts", "mes autres persos" }, { "unlearned", "recettes pas apprises" } }
  local prev
  for _, o in ipairs(labelsOpt) do
    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    if prev then cb:SetPoint("LEFT", prev.label, "RIGHT", 8, 0) else cb:SetPoint("TOPLEFT", 12, -108) end
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 0, 0)
    cb.label:SetText(o[2])
    cb:SetChecked(opts()[o[1]])
    cb:SetScript("OnClick", function(self) opts()[o[1]] = self:GetChecked() and true or false; refresh() end)
    prev = cb
  end

  -- Légende des couleurs
  local legend = { { COLORS.target, "commandé" }, { COLORS.apport, "fourni par toi" }, { COLORS.fabriquer, "à fabriquer" }, { COLORS[1], "sacs" }, { COLORS[2], "banque" },
    { COLORS[3], "autres persos" }, { COLORS.buy, "à acheter" }, { COLORS.none, "sans prix" } }
  local lx = 14
  for _, l in ipairs(legend) do
    local sw = frame:CreateTexture(nil, "ARTWORK")
    sw:SetColorTexture(l[1][1], l[1][2], l[1][3], 0.9)
    sw:SetSize(10, 10)
    sw:SetPoint("TOPLEFT", lx, -138)
    local t = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    t:SetPoint("LEFT", sw, "RIGHT", 3, 0)
    t:SetText(l[2])
    if l[1] == COLORS.apport then frame.apportLegend = t end
    lx = lx + 18 + t:GetStringWidth() + 10
  end

  -- La zone de dessin : molette = zoom autour du curseur, glisser le fond = déplacer, clic du milieu = vue ajustée.
  scroll = CreateFrame("Frame", nil, frame)
  scroll:SetPoint("TOPLEFT", 14, -180)
  scroll:SetPoint("BOTTOMRIGHT", -14, 30)
  scroll:SetClipsChildren(true)
  content = CreateFrame("Frame", nil, scroll)
  content:SetSize(W - 28, 1)
  local function cursor() -- le curseur dans la zone, vers la droite et vers le bas
    local cx, cy = GetCursorPosition()
    local es = scroll:GetEffectiveScale()
    return cx / es - scroll:GetLeft(), scroll:GetTop() - cy / es
  end
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(_, d)
    local mx, my = cursor()
    local s = view.fit * view.zoom
    local px, py = mx / s - view.x, my / s + view.y -- le point du dessin sous le curseur…
    view.zoom = view.zoom * (d > 0 and 1.15 or 1 / 1.15)
    applyView()
    s = view.fit * view.zoom
    view.x, view.y = mx / s - px, py - my / s -- …reste sous le curseur
    applyView()
  end)
  scroll:EnableMouse(true)
  local drag
  scroll:SetScript("OnMouseDown", function(_, button)
    if button == "MiddleButton" then view.zoom, view.x, view.y = 1, 0, 0; return applyView() end
    local mx, my = cursor()
    drag = { mx = mx, my = my, x = view.x, y = view.y }
  end)
  scroll:SetScript("OnMouseUp", function() drag = nil end)
  scroll:SetScript("OnUpdate", function()
    if not drag then return end
    if not IsMouseButtonDown("LeftButton") and not IsMouseButtonDown("RightButton") then drag = nil return end
    local mx, my = cursor()
    local s = view.fit * view.zoom
    view.x, view.y = drag.x + (mx - drag.mx) / s, drag.y - (my - drag.my) / s -- le dessin suit la souris
    applyView()
  end)

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.status:SetPoint("BOTTOMLEFT", 14, 10)

  -- Les sacs changent, un nom d'objet arrive du serveur : on recalcule, au plus une fois par seconde.
  local pending
  local function soon()
    if pending or not frame:IsShown() then return end
    pending = true
    C_Timer.After(1, function() pending = false; refresh() end)
  end
  frame:RegisterEvent("BAG_UPDATE_DELAYED")
  frame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  frame:SetScript("OnEvent", soon)
  frame:SetScript("OnShow", function() C_Timer.After(0, refresh) end) -- la largeur du défilement n'est connue qu'affichée
end

function ns.openCraftWindow(id, qty)
  if not frame then build() end
  frame:Show()
  if id then track(id, qty or 1) else refresh() end
end
if GameDataAPI then GameDataAPI.openCraftWindow = ns.openCraftWindow end -- minicarte et menu de GameData
-- Bouton de minicarte et entrée des options communs d'Azeroth Commune (LibCommune#3) : clic ou ligne du menu = cette fenêtre.
local commune = LibStub and LibStub("LibCommune-1.0", true)
if commune and commune.Regrouper then
  commune.Regrouper({ nom = "Handshake", dossier = "Handshake", icone = "Interface\\Icons\\Trade_BlackSmithing",
    ouvrir = function() ns.openCraftWindow() end, store = function() return HandshakeDB end })
end

-- Ctrl+clic droit sur un objet n'importe où dans le jeu (sacs, banque, lien du chat, butin, fenêtre de métier, HV) : il
-- entre dans la commande affichée et la fenêtre s'ouvre. Un objet-recette (« Plans : Claymore ») donne l'objet fabriqué.
-- Les autres touches sont prises : Ctrl+clic = cabine d'essayage, Alt+clic = Mastercraft, AuctionDB, Auctionator ;
-- chez un marchand, Ctrl+clic droit est à BetterVendorPrice.
if HandleModifiedItemClick then
  hooksecurefunc("HandleModifiedItemClick", function(link)
    if not (IsControlKeyDown() and not IsAltKeyDown() and not IsShiftKeyDown() and GetMouseButtonClicked() == "RightButton") then return end
    if (MerchantFrame and MerchantFrame:IsShown()) or type(link) ~= "string" or (issecretvalue and issecretvalue(link)) then return end
    local id = tonumber(link:match("item:(%d+)"))
    if not id then return end
    if select(6, C_Item.GetItemInfoInstant(id)) == 9 then -- recette : l'objet dont elle porte le nom
      local name = link:match("%[(.-)%]")
      local made = name and ns.findItem((name:gsub("^.-:%s*", "")))
      if not made then return print("Commandes : je ne trouve pas l'objet que fabrique " .. link .. ".") end
      id = made
    end
    if not lignes() then ns.nouveauProjet() end -- sa demande ne change pas : un projet à toi
    for _, l in ipairs(ns.projetCourant().lines) do
      if l.id == id then return ns.openCraftWindow() end -- déjà dedans : sa quantité ne bouge pas
    end
    ns.openCraftWindow(id, 1)
  end)
end
