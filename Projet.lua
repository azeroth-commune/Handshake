-- Handshake, le module des projets (glossaire : CONTEXT.md de Composants, où il partira) : ce que je veux faire fabriquer
-- (des objets × quantités) et mes choix de case (décomposer, acheter) ; son arbre fusionné en cases (une par objet) et
-- ses blocs (un par métier, avec qui peut les faire). Il ne connaît ni commandes, ni apports, ni contrats (Commande.lua) ;
-- un autre module peut tenir ses lignes (projet tenu). Toute modification d'un projet passe par ce module ; la fenêtre
-- (Fenetre.lua) ne fait que dessiner.
-- Enregistrés dans HandshakeDB.projets[i] = { id (son identité), name, lines = { { id, qty } }, choix = { [id] =
--   "fabriquer" | "acheter" }, tenu (la raison de celui qui tient ses lignes), created } ;
--   HandshakeDB.courant = le rang du projet affiché.
local _, ns = ...

local function db()
  HandshakeDB.projets = HandshakeDB.projets or {}
  return HandshakeDB
end

-- Un projet a une identité stable (p.id, jamais redonnée ; d.projetSeq = la dernière donnée) : supprimer ou réordonner
-- les autres ne la change pas. Son rang (d.courant pour celui affiché) ne dit que sa place dans la liste.
function ns.nouveauProjet(p)
  p = p or {}
  p.lines = p.lines or {}
  p.name = p.name or ("Projet du " .. date("%d/%m %H:%M"))
  p.created = time()
  local d = db()
  d.projetSeq = (d.projetSeq or 0) + 1
  p.id = d.projetSeq
  table.insert(d.projets, p)
  d.courant = #d.projets
  return p
end

function ns.projetCourant()
  local d = db()
  if #d.projets == 0 then ns.nouveauProjet() end
  d.courant = math.min(math.max(1, d.courant or 1), #d.projets)
  return d.projets[d.courant]
end

-- « < » et « > » : le projet d'avant, d'après.
function ns.changerProjet(delta)
  local d = db()
  d.courant = (d.courant or 1) + delta
  return ns.projetCourant()
end

-- Position du projet affiché, nombre de projets.
function ns.numeroProjet()
  ns.projetCourant()
  return db().courant, #db().projets
end

-- Supprime le projet affiché et le renvoie.
function ns.supprimerProjet() return table.remove(db().projets, db().courant) end

-- Le projet d'identité id, affiché ; nil s'il n'existe plus.
function ns.ouvrirProjet(id)
  for i, p in ipairs(db().projets) do
    if p.id == id then db().courant = i return p end
  end
end

---------------------------------------------------------------------------------------------------
-- Projet tenu (CONTEXT.md de Composants) : un autre module prend les lignes du projet (lignes : les nouvelles, sinon
-- celles qu'il a) en donnant une raison ; ajouter, retirer une ligne ou changer une quantité sont alors refusés avec
-- cette raison telle quelle, les choix de case restent libres. Le projet ne sait pas pourquoi il est tenu ; raison nil :
-- il est rendu.
function ns.projetTenir(p, raison, lignes)
  p.tenu = raison
  if lignes then p.lines = lignes end
end

-- « Peut-on modifier quoi sur ce projet ? » (la fenêtre grise d'après elle) : true, ou false, raison.
function ns.projetPeut(p, quoi)
  if quoi == "lignes" and p.tenu then return false, p.tenu end
  return true
end

-- Chaque modification des lignes renvoie true, ou false, raison.
function ns.projetAjouter(p, id, qty)
  local ok, raison = ns.projetPeut(p, "lignes")
  if not ok then return false, raison end
  for _, l in ipairs(p.lines) do
    if l.id == id then l.qty = qty; return true end
  end
  p.lines[#p.lines + 1] = { id = id, qty = qty }
  return true
end

function ns.projetQuantite(p, i, qty)
  local ok, raison = ns.projetPeut(p, "lignes")
  if not ok then return false, raison end
  if not p.lines[i] then return false, "cette ligne n'existe pas" end
  if qty and qty >= 1 then p.lines[i].qty = math.min(qty, 9999) end
  return true
end

function ns.projetRetirer(p, i)
  local ok, raison = ns.projetPeut(p, "lignes")
  if not ok then return false, raison end
  table.remove(p.lines, i)
  return true
end

-- choix = "fabriquer" (« + », décomposer), "acheter" (« – », tout fait) ou nil (le calcul des prix décide) ; libre
-- même dans un projet tenu.
function ns.projetChoix(p, id, choix)
  p.choix = p.choix or {}
  p.choix[id] = choix
  if not next(p.choix) then p.choix = nil end
  return true
end

function ns.projetRenommer(p, name) p.name = name end

---------------------------------------------------------------------------------------------------
-- Les cases : roots[i] = plan d'une ligne (ns.plan), fusionnés. Clés : "T<i>" la ligne i, "I<id>" un objet (toutes ses
-- apparitions additionnées). Un objet peut être en partie en stock, en partie fabriqué (made), en partie acheté (need),
-- ou apporté (apport, Commande.lua). n.choix = le choix de case du projet ; n.parents / n.children et les liens (from, to, qty) : l'arbre.
local function cases(roots, choix)
  local nodes, list, edges, byPair = {}, {}, {}, {}
  local function nodeOf(key, kind, id)
    local n = nodes[key]
    if not n then
      n = { key = key, kind = kind, id = id, qty = 0, have = { 0, 0, 0 }, need = 0, cost = 0, made = 0, madeCost = 0, crafts = 0, apport = 0,
        parents = {}, children = {}, choix = choix[id] }
      nodes[key], list[#list + 1] = n, n
    end
    return n
  end
  local function edge(from, to, qty)
    local k = from.key .. ">" .. to.key
    local e = byPair[k]
    if not e then
      e = { from = from, to = to, qty = 0 }
      byPair[k], edges[#edges + 1] = e, e
      to.parents[#to.parents + 1], from.children[#from.children + 1] = from, to
    end
    e.qty = e.qty + qty
  end
  local function add(n, p)
    n.qty = n.qty + p.qty
    for i = 1, 3 do n.have[i] = n.have[i] + p.have[i] end
    n.craftable = n.craftable or p.craftable
    if p.how == "apport" then
      n.apport = n.apport + p.qty
    elseif p.how == "fabriquer" then
      n.made, n.madeCost, n.crafts = n.made + p.need, n.madeCost + p.cost, n.crafts + p.crafts
      n.recipe, n.unknown, n.incomplete = p.recipe, n.unknown or not p.known, n.incomplete or p.incomplete
      n.recipeKey = n.recipeKey or p.recipeKey
      if p.buy then n.buy = (n.buy or 0) + p.buy end
      for _, part in ipairs(p.parts) do
        local c = nodeOf("I" .. part.id, "item", part.id)
        add(c, part)
        edge(n, c, part.qty)
      end
    else
      n.need, n.cost = n.need + p.need, n.cost + (p.cost or 0)
      if p.need > 0 and not p.cost then n.unpriced = true end
      if p.how ~= "stock" then n.how = p.how end
      n.partial = n.partial or p.partial
    end
  end
  for i, r in ipairs(roots) do
    local t = nodeOf("T" .. i, "target", r.id)
    t.index = i
    add(t, r)
  end
  return { cases = list, caseDe = nodes, liens = edges }
end

-- Qui fabrique quoi. La liste des artisans est pour l'instant tes persos ; plus tard une guilde ou des amis
-- (synchronisés quand ils sont connectés), sous la même forme : { key, name, ranks = { [métier] = niveau },
-- known = { [recette] = true } }. Ton perso connecté passe en premier.
function ns.crafters()
  local list, me, byKey = {}, UnitGUID("player"), {}
  local function entry(key) -- un perso peut avoir ses recettes relevées sans fiche (ou l'inverse)
    if not byKey[key] then
      byKey[key] = { key = key, name = ns.nomPerso(key), ranks = {}, known = {} } -- key : le GUID ; name : « Prénom Nom »
      list[#list + 1] = byKey[key]
    end
    return byKey[key]
  end
  for key, c in pairs(ns.metiers()) do
    local e = entry(key)
    for _, p in pairs(c.professions or {}) do
      if type(p) == "table" and p.name then e.ranks[p.name] = math.max(e.ranks[p.name] or 0, p.rank or 0) end
    end
  end
  for key, metiers in pairs(ns.knownRecipes()) do
    local e = entry(key)
    for prof, p in pairs(metiers) do
      e.ranks[prof] = math.max(e.ranks[prof] or 0, p.rank or 0)
      for k in pairs(p.known or {}) do e.known[k] = true end
    end
  end
  table.sort(list, function(a, b)
    if (a.key == me) ~= (b.key == me) then return a.key == me end
    if a.name ~= b.name then return a.name < b.name end -- par nom (la clé est un GUID)
    return a.key < b.key
  end)
  return list
end

-- Le métier d'une case fabriquée (la clé de son bloc), nil sinon.
local function metier(n) return n.made > 0 and n.recipe and (n.recipe.profession or "Métier inconnu") or nil end

-- Les blocs : les cases fabriquées d'un même métier, et qui, dans la liste des artisans, a ce métier (son niveau, combien
-- de ces recettes il connaît). res.blocs = { { key (le métier), level (niveau requis le plus haut), recipes = { { key,
-- name, level, known = { noms } } }, crafters = { { name, rank, known } }, best (celui qui en connaît le plus), cases,
-- deliver / qty (ce qu'il livre), inputs (ce qu'il reçoit des autres blocs), step } }, de la dernière étape à la
-- première ; res.blocDe[métier]. Chaque case fabriquée garde n.who (qui connaît sa recette, sinon qui a le métier,
-- sinon false) et n.whoKnows.
-- res.livraisons : tout ce que le bloc B fabrique pour une case du bloc A = UNE livraison B -> A (une par sens) :
-- { maker, client (métiers, ou "reste"), player (qui fait B), lines = { id… }, qty = { [id] }, edges } ; e.livraison.
-- ponytail: qui fait quoi reste automatique ; le choix à la main viendra avec les listes d'amis.
local function blocs(res, crafters)
  local groups, byKey = {}, {}
  for _, n in ipairs(res.cases) do
    local prof = metier(n)
    if prof then
      local grp = byKey[prof]
      if not grp then
        grp = { key = prof, level = 0, recipes = {}, seen = {}, cases = {} }
        byKey[prof], groups[#groups + 1] = grp, grp
      end
      grp.cases[#grp.cases + 1] = n
      local found, knows
      for _, c in ipairs(crafters) do
        if n.recipeKey and c.known[n.recipeKey] then found, knows = c, true break end
        if not found and c.ranks[prof] then found = c end
      end
      n.who, n.whoKnows = found and found.name or false, knows or false
      local rk = n.recipeKey or n.id
      if not grp.seen[rk] then
        local r = { key = n.recipeKey, name = n.recipe.name or ns.itemLabel(n.id), level = ns.recipeLevel(n.recipeKey, n.recipe), known = {} }
        for _, c in ipairs(crafters) do if n.recipeKey and c.known[n.recipeKey] then r.known[#r.known + 1] = c.name end end
        grp.seen[rk], grp.recipes[#grp.recipes + 1] = true, r
        grp.level = math.max(grp.level, r.level or 0)
      end
    end
  end
  for _, grp in ipairs(groups) do
    grp.crafters = {}
    for _, c in ipairs(crafters) do
      if c.ranks[grp.key] then
        local k = 0
        for _, r in ipairs(grp.recipes) do if r.key and c.known[r.key] then k = k + 1 end end
        grp.crafters[#grp.crafters + 1] = { name = c.name, rank = c.ranks[grp.key], known = k }
      end
    end
    table.sort(grp.crafters, function(a, b) if a.known ~= b.known then return a.known > b.known end return a.rank > b.rank end)
    grp.best = grp.crafters[1] and grp.crafters[1].name or nil
  end
  local orders, byPair = {}, {}
  for _, e in ipairs(res.liens) do
    local maker, client = metier(e.to), metier(e.from) or "reste"
    if maker and maker ~= client then
      local k = maker .. ">" .. client
      local o = byPair[k]
      if not o then
        o = { maker = maker, client = client, player = byKey[maker].best, lines = {}, qty = {}, edges = {} }
        byPair[k], orders[#orders + 1] = o, o
      end
      if not o.qty[e.to.id] then o.lines[#o.lines + 1] = e.to.id end
      o.qty[e.to.id] = (o.qty[e.to.id] or 0) + e.qty
      o.edges[#o.edges + 1], e.livraison = e, o
    end
  end
  -- Un bloc : ce qu'il livre (aux autres blocs, et les objets du projet qu'il fabrique), ce qu'il reçoit des autres
  -- blocs (ses apports quand Handshake le commande). Étape = 1 + la plus haute étape de ses fournisseurs : on fait du
  -- bas vers le haut.
  for _, grp in ipairs(groups) do grp.deliver, grp.qty, grp.inputs = {}, {}, {} end
  local function give(grp, id, q)
    if not grp.qty[id] then grp.deliver[#grp.deliver + 1] = id end
    grp.qty[id] = (grp.qty[id] or 0) + q
  end
  for _, n in ipairs(res.cases) do
    if n.kind == "target" and metier(n) then give(byKey[metier(n)], n.id, n.qty) end
  end
  for _, o in ipairs(orders) do
    for _, id in ipairs(o.lines) do
      give(byKey[o.maker], id, o.qty[id])
      if byKey[o.client] then byKey[o.client].inputs[id] = true end
    end
  end
  local busy = {}
  local function step(grp)
    if grp.step then return grp.step end
    if busy[grp] then return 1 end -- boucle entre métiers : coupée
    busy[grp] = true
    local st = 1
    for _, o in ipairs(orders) do
      if o.client == grp.key and byKey[o.maker] then st = math.max(st, step(byKey[o.maker]) + 1) end
    end
    busy[grp], grp.step = nil, st
    return st
  end
  for _, grp in ipairs(groups) do step(grp) end
  -- La dernière étape d'abord (les objets du projet), puis en descendant ; à étape égale, les métiers que quelqu'un a
  -- d'abord, puis par nom.
  table.sort(groups, function(a, b)
    if a.step ~= b.step then return a.step > b.step end
    if (#a.crafters > 0) ~= (#b.crafters > 0) then return #a.crafters > 0 end
    return a.key < b.key
  end)
  res.blocs, res.blocDe, res.livraisons = groups, byKey, orders
end

-- L'arbre d'un projet : ses lignes l'une après l'autre sur le même stock, avec SES choix de case, puis les cases et les
-- blocs. opts : options de stock et de recettes (celles de la fenêtre par défaut). apports (facultatif) = { [id] = true },
-- les cases qu'une commande apporte (Commande.lua) : elles sortent de l'arbre, le projet ne les garde pas.
-- Renvoie { roots, cases, caseDe, liens, blocs, blocDe, livraisons, total, incomplete, market }.
function ns.projetArbre(p, opts, apports)
  local roots, market, stock, vendors, total, incomplete = {}, nil, nil, nil, 0, false
  for i, l in ipairs(p.lines) do -- les prix marchands lus une fois pour tout le projet
    roots[i], market, stock, vendors = ns.craftPlan(l.id, l.qty, opts or HandshakeDB.options, stock, apports, p.choix, vendors)
    total = total + (roots[i].cost or 0)
    incomplete = incomplete or roots[i].incomplete or not roots[i].cost
  end
  local res = cases(roots, p.choix or {})
  res.roots, res.total, res.incomplete, res.market = roots, total, incomplete, market
  blocs(res, ns.crafters())
  return res
end

-- La demande telle que l'artisan la verra : toutes les recettes, aucun stock déduit (les stocks du demandeur ne
-- réduisent pas la part de l'artisan, CONCEPTION.md), les apports retirés.
function ns.projetDemande(p, apports) return ns.projetArbre(p, { unlearned = true }, apports) end

---------------------------------------------------------------------------------------------------
-- Au chargement : les projets d'avant l'identité stable (Handshake#37) sont effacés, sans migration (perte acceptée), avec
-- les vieilles commandes d'avant les projets et la table globale des choix (« force »).
function ns.purgerProjets(d)
  d.projets = d.projets or {}
  for i = #d.projets, 1, -1 do
    if not d.projets[i].id then table.remove(d.projets, i) end
  end
  d.orders, d.current, d.force = nil, nil, nil
end
