-- Handshake, « acheter ou fabriquer » : pour un objet et une quantité, le moins cher entre l'acheter (marchand
-- ou hôtel des ventes) et le fabriquer, en redescendant dans les composants (barre de fer -> minerai de fer).
--   /handshake ou /commande <lien, nom ou ID d'objet> [quantité] [tout]
-- Ouvre la fenêtre (Fenetre.lua). Les données : Donnees.lua (toutes par le socle Azeroth Commune). Par défaut seules les recettes connues d'un de tes persos comptent ; « tout » ajoute celles vues mais pas apprises.
-- Les prix de l'HV suivent les paliers du dernier scan : 20 barres coûtent les moins chères, puis les suivantes.
local _, ns = ...

local MAX_DEPTH = 10 -- garde-fou ; les boucles (A fait B fait A) sont coupées par path


-- Prix d'achat (marchand ou HV palier par palier) et prix marchands : ceux du socle (lib:PrixAchat,
-- lib:PrixMarchands), les mêmes que pour la caution et le Journal du Négoce.
local lib = AzerothCommune

local function knownRecipes()
  local known = {}
  for _, metiers in pairs(ns.knownRecipes()) do
    for _, p in pairs(metiers) do
      for key in pairs(p.known or {}) do known[key] = true end
    end
  end
  return known
end

-- Choix entre recettes équivalentes (plusieurs recettes fabriquent l'objet d'une case qu'on décompose), règle fixe (#46) :
--   1. une recette en boucle est écartée (voir enBoucle) : on achète la case, ou on la décompose avec une autre recette ;
--   2. la moins chère l'emporte ;
--   3. à coût égal ou inconnu : la recette connue d'un personnage, puis le plus petit identifiant de recette.
-- Les recettes d'un objet sont donc essayées dans l'ordre 3 (connues d'abord, puis par identifiant) et une suivante ne
-- prend la place que si elle est strictement moins chère : le même projet donne le même arbre, quel que soit l'ordre de
-- la base des recettes (avant, celui de pairs, qui change avec la taille de la base).
local function avant(a, b)
  if (a.known or false) ~= (b.known or false) then return a.known or false end
  local ta, tb = type(a.key), type(b.key)
  if ta ~= tb then return ta == "number" end -- identifiants numériques (sortID) d'abord, puis les clés texte
  return a.key < b.key
end

local function recipesByOutput(all, known)
  local by = {}
  for key, r in pairs(ns.recipes()) do
    if r.output and r.reagents and #r.reagents > 0 and (all or known[key]) then
      by[r.output] = by[r.output] or {}
      table.insert(by[r.output], { key = key, r = r, known = known[key] })
    end
  end
  for _, recs in pairs(by) do table.sort(recs, avant) end
  return by
end

-- Une recette est en boucle quand elle fabrique l'objet d'une case à partir d'un objet que cette case sert elle-même à
-- fabriquer, directement ou non, par les recettes que le calcul peut prendre (Vie → Terre quand Terre → Vie existe ; le
-- tour Air → Feu → Terre → Eau → Air) : la décomposer ne ferait que racheter plus bas ce qu'on fabrique. Elle n'est
-- reprise que sur un choix de case « décomposer ». Mémorisé le temps d'un calcul (ctx.boucle).
local function enBoucle(ctx, rec, id)
  ctx.boucle = ctx.boucle or {}
  if ctx.boucle[rec] == nil then
    local vu = {}
    local function faitDe(x) -- x se fabrique-t-il à partir de id ?
      if x == id then return true end
      if vu[x] then return false end
      vu[x] = true
      for _, r in ipairs(ctx.by[x] or {}) do
        if r.known or ctx.unlearned then
          for _, rg in ipairs(r.r.reagents) do
            if rg.id and faitDe(rg.id) then return true end
          end
        end
      end
      return false
    end
    local b = false
    for _, rg in ipairs(rec.r.reagents) do b = b or (rg.id ~= nil and faitDe(rg.id)) end
    ctx.boucle[rec] = b
  end
  return ctx.boucle[rec]
end

-- Stock déductible : stock[itemID] = { sacs, banque, autres persos }. Partagé par tout l'arbre : un minerai
-- pris pour une branche n'est plus disponible pour une autre.
local function take(stock, id, qty)
  local used, p = { 0, 0, 0 }, stock and stock[id]
  if p then
    for i = 1, 3 do
      local n = math.min(qty, p[i])
      used[i], p[i], qty = n, p[i] - n, qty - n
    end
  end
  return used, qty
end

local function copyStock(s)
  if not s then return nil end
  local c = {}
  for id, p in pairs(s) do c[id] = { p[1], p[2], p[3] } end
  return c
end

-- Le plan le moins cher pour qty objets id :
--   { id, qty, have = { sacs, banque, persos }, need = ce qu'il reste à obtenir, cost (de need),
--     how = "stock"|"marchand"|"HV"|"fabriquer"|nil, recipe, crafts, parts, buy = coût d'achat de need }
-- cost = nil : ni prix ni recette. Chaque recette essayée travaille sur sa propre copie du stock ;
-- celle de la meilleure option est gardée. craftable = une recette existe (le « + » de la fenêtre).
-- ctx.force[itemID] = "fabriquer" | "acheter" : le choix de case du projet l'emporte sur les prix.
local function plan(id, qty, ctx, depth, path)
  -- « je le fournis » (apport du demandeur) : la case et tout ce qu'il y a dessous sortent de la part de l'artisan.
  if depth > 0 and ctx.apports and ctx.apports[id] then
    return { id = id, qty = qty, have = { 0, 0, 0 }, need = 0, cost = 0, how = "apport" }
  end
  -- « + » sur un objet qu'on a déjà : on le fabrique quand même, sans puiser dans le stock (pour voir son arbre).
  local canCraft = ctx.by[id] and depth < MAX_DEPTH and not path[id]
  local have, need
  if canCraft and ctx.force and ctx.force[id] == "fabriquer" then have, need = { 0, 0, 0 }, qty
  else have, need = take(ctx.stock, id, qty) end
  local node = { id = id, qty = qty, have = have, need = need }
  if need == 0 then node.cost, node.how, node.craftable = 0, "stock", canCraft or nil return node end
  local cost, how, partial = lib:PrixAchat(id, need, ctx.market, ctx.vendors)
  node.cost, node.how, node.partial, node.buy = cost, how, partial, cost
  if depth >= MAX_DEPTH or path[id] or not ctx.by[id] then return node end
  node.craftable = true
  local force = ctx.force and ctx.force[id]
  if force == "acheter" then return node end
  if force == "fabriquer" then node.cost, node.how, node.partial = nil, nil, nil end -- l'achat ne compte plus
  path[id] = true
  local base, keep = ctx.stock, ctx.stock
  -- Le calcul automatique ne prend que les recettes connues (sauf option « recettes pas apprises ») et hors boucle ; le
  -- « + » existe dès qu'une recette existe, et un choix de case « décomposer » essaie aussi celles que personne n'a
  -- apprises (en rouge) et celles en boucle. Ordre d'essai et départage : voir « Choix entre recettes équivalentes ».
  local recs = {}
  for _, rec in ipairs(ctx.by[id]) do
    if force == "fabriquer" or (rec.known or ctx.unlearned) and not enBoucle(ctx, rec, id) then recs[#recs + 1] = rec end
  end
  for _, rec in ipairs(recs) do
    local per = math.max(1, rec.r.made_min or 1)
    local crafts = math.ceil(need / per)
    ctx.stock = copyStock(base)
    local total, parts, missing = 0, {}, false
    for _, rg in ipairs(rec.r.reagents) do
      local p = rg.id and plan(rg.id, rg.qty * crafts, ctx, depth + 1, path)
      if p then
        total = total + (p.cost or 0)
        parts[#parts + 1] = p
      end
      if not p or not p.cost or p.incomplete then missing = true end
    end
    -- Une recette complète l'emporte si elle est moins chère ; une recette où un composant n'a ni prix ni recette
    -- n'est gardée que faute de mieux (coût « incomplet »), pour voir l'arbre quand même.
    local better = not missing and (not node.cost or node.incomplete or total < node.cost)
    if better or (missing and not node.cost) then
      node.cost, node.how, node.recipe, node.known, node.crafts, node.parts = total, "fabriquer", rec.r, rec.known, crafts, parts
      node.recipeKey = rec.key
      node.partial, node.incomplete, keep = nil, missing or nil, ctx.stock
    end
  end
  ctx.stock = keep
  path[id] = nil
  return node
end
ns.plan = plan

local function shopping(p, out)
  if p.how == "fabriquer" then
    for _, part in ipairs(p.parts) do shopping(part, out) end
  elseif p.need > 0 then
    out[p.id] = out[p.id] or { qty = 0, cost = 0, how = p.how }
    out[p.id].qty = out[p.id].qty + p.need
    out[p.id].cost = out[p.id].cost + (p.cost or 0)
  end
  return out
end
ns.shopping = shopping

-- Le stock selon les options : mes sacs (lus à l'instant), ma banque (dernier passage), mes autres persos (relevés par
-- le socle).
local function buildStock(opts)
  if not (opts.bags or opts.bank or opts.alts) then return nil end
  local stock = {}
  local function add(containers, pool)
    for _, bag in pairs(containers or {}) do
      for _, it in ipairs(bag.items or {}) do
        if it.id then
          stock[it.id] = stock[it.id] or { 0, 0, 0 }
          stock[it.id][pool] = stock[it.id][pool] + (it.count or 1)
        end
      end
    end
  end
  local me, inv = UnitGUID("player"), ns.inventaires()
  if opts.bags then add(ns.mesSacs(), 1) end
  if opts.bank then add(inv[me] and inv[me].bank, 2) end
  if opts.alts then
    for key, c in pairs(inv) do
      if key ~= me then add(c.bags, 3); add(c.bank, 3) end
    end
  end
  return stock
end

-- Calcul complet d'une ligne d'un projet (Projet.lua), avec ses apports et ses choix de case.
-- stock : celui laissé par la ligne précédente (nil = le construire) ; il est renvoyé pour la suivante.
function ns.craftPlan(id, qty, opts, stock, apports, choix, vendors)
  local market = ns.market()
  local ctx = { market = market and market.items, by = recipesByOutput(true, knownRecipes()), unlearned = opts.unlearned, stock = stock or buildStock(opts),
    force = choix, apports = apports, vendors = vendors or lib:PrixMarchands() }
  local node = plan(id, qty, ctx, 0, {})
  return node, market, ctx.stock, ctx.vendors
end

function ns.costCommand(args)
  local test = args:match("^%s*essai%s*(%a*)")
  if test then -- /commande essai [besoins] : la commande affichée (ou ses besoins) reçue comme un chuchotement
    local p = ns.projetCourant()
    if test == "besoins" then return ns.sendNeeds(ns.projetCommande(p), ns.projetArbre(p, nil, ns.projetApports(p)), true) end
    return ns.sendOrder(ns.projetCommande(p), true)
  end
  local all = args:find("%f[%w]tout%f[%W]") ~= nil
  args = args:gsub("%f[%w]tout%f[%W]", "")
  local qty = tonumber(args:match("%s(%d+)%s*$")) or 1
  local what = args:gsub("%s%d+%s*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
  local id = what ~= "" and ns.findItem(what)
  if all then HandshakeDB.options.unlearned = true end
  ns.openCraftWindow(id, qty)
end
SLASH_HANDSHAKE1, SLASH_HANDSHAKE2 = "/handshake", "/commande"
SlashCmdList.HANDSHAKE = function(args)
  if args:match("^%s*liste%s*$") then return ns.openCommandeMain() end -- la commande à la main (#38)
  if args:match("^%s*demo") then ns.demoOrder(args:match("^%s*demo%s+(%a+)")); return ns.openCraftWindow() end
  ns.costCommand(args)
end
