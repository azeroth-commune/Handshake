-- Handshake, le projet (CONTEXT.md) : ce que je veux faire fabriquer (des objets × quantités), mes choix de case
-- (décomposer, acheter) et mes apports ; son arbre fusionné en cases (une par objet) et ses blocs (un par métier, avec
-- qui peut les faire). Toute modification d'un projet passe par ce module ; la fenêtre (Fenetre.lua) ne fait que dessiner.
-- Enregistrés dans HandshakeDB.projets[i] = { name, lines = { { id, qty } }, choix = { [id] = "fabriquer" | "acheter" },
--   apports = { [id] = true }, commandes = { { bloc (le métier ; nil = tout le projet, toujours la 1re), player
--   (l'artisan), tip (l'offre, en cuivre), contrat (clé de son contrat, une fois préparée), id } }, seq, reponse (clé
--   du contrat dont il est la réponse), reponseHash, created } ;
--   HandshakeDB.courant = le projet affiché.
local _, ns = ...

local function db()
  HandshakeDB.projets = HandshakeDB.projets or {}
  return HandshakeDB
end

-- Les commandes d'un projet. Un projet d'avant (19/11/2026) portait un artisan et une offre : ils deviennent sa
-- commande « tout le projet » (nouveauProjet accepte encore player et tip, pour la même raison).
-- Chaque commande a son identité (c.id, unique dans son projet ; p.seq = la dernière donnée), même celles d'avant.
local function commandes(p)
  if not p.commandes then p.commandes, p.player, p.tip = { { player = p.player, tip = p.tip } }, nil, nil end
  for _, c in ipairs(p.commandes) do
    if not c.id then p.seq = (p.seq or 0) + 1; c.id = p.seq end
  end
  return p.commandes
end

function ns.nouveauProjet(p)
  p = p or {}
  p.lines = p.lines or {}
  commandes(p)
  p.name = p.name or ("Projet du " .. date("%d/%m %H:%M"))
  p.created = time()
  local d = db()
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

function ns.supprimerProjet() table.remove(db().projets, db().courant) end

-- « Je réponds » : la demande reçue devient une réponse, un projet lié au contrat (p.reponse = sa clé). Ce qu'il veut
-- est figé ; ses apports (Ctrl+clic pour contre-proposer) et le prix actuel sont recopiés à chaque nouvelle version.
function ns.projetReponse(c)
  local key, p = ns.ctKey(c), nil
  for i, x in ipairs(db().projets) do if x.reponse == key then p, db().courant = x, i end end
  p = p or ns.nouveauProjet({ reponse = key })
  if p.reponseHash == c.hash then return p end -- même version : on garde ce que tu as changé
  local tout = commandes(p)[1]
  p.reponseHash, p.name, tout.player = c.hash, "Réponse à " .. c.client:match("^[^%-]+"), c.client
  p.lines, p.apports = {}, nil
  for _, l in ipairs(c.o) do p.lines[#p.lines + 1] = { id = l.id, qty = l.qty } end
  for _, l in ipairs(c.m) do p.apports = p.apports or {}; p.apports[l.id] = true end
  tout.tip = math.max(0, ns.ctTotal(c.o) - ns.ctTotal(c.m))
  return p
end

---------------------------------------------------------------------------------------------------
-- Modifications. Dans une réponse, ce que veut le demandeur est figé : lignes et quantités refusées (false).
function ns.projetAjouter(p, id, qty)
  if p.reponse then return false end
  for _, l in ipairs(p.lines) do
    if l.id == id then l.qty = qty; return true end
  end
  p.lines[#p.lines + 1] = { id = id, qty = qty }
  return true
end

function ns.projetQuantite(p, i, qty)
  if p.reponse or not p.lines[i] then return false end
  if qty and qty >= 1 then p.lines[i].qty = math.min(qty, 9999) end
  return true
end

function ns.projetRetirer(p, i)
  if p.reponse then return false end
  table.remove(p.lines, i)
  return true
end

-- choix = "fabriquer" (« + », décomposer), "acheter" (« – », tout fait) ou nil (le calcul des prix décide).
function ns.projetChoix(p, id, choix)
  p.choix = p.choix or {}
  p.choix[id] = choix
  if not next(p.choix) then p.choix = nil end
end

-- « Je le fournis » : la case entière, et tout ce qu'il y a sous elle, sort de la part de l'artisan.
function ns.projetApport(p, id, oui)
  p.apports = p.apports or {}
  p.apports[id] = oui or nil
  if not next(p.apports) then p.apports = nil end
end

function ns.projetRenommer(p, name) p.name = name end

---------------------------------------------------------------------------------------------------
-- Commandes (CONTEXT.md) : des parts du projet, chacune à un artisan, avec son offre. i = son rang (1 = tout le
-- projet, par défaut). Dans une réponse, la 1re est la réponse elle-même (son artisan = le demandeur, son offre = mon
-- prix) ; commander un de ses blocs, c'est le sous-traiter.
-- Envoyée (#7), elle est une demande : figée, son contenu est celui de son contrat (c.contrat = sa clé, ns.ctKey), à
-- sa dernière version ; v.fige, v.contrat. Son état (v.etat) se lit toujours dans le contrat, jamais saisi à part.
-- Un brouillon (« Préparer la demande », pas encore parti) ne la fige pas : elle suit encore le projet.
local function envoyee(c)
  local ct = c.contrat and ns.ctStore()[c.contrat]
  return ct and ct.status ~= "brouillon" and ct or nil
end
local ETATS = { envoye = "demande envoyée", a_signer = "contre-proposée", signe = "signée", clos = "livrée",
  echu = "échue", refuse = "refusée", retire = "retirée" }
local function etat(ct)
  if not ct then return "pas envoyée" end
  local s = ns.ctStatus(ct)
  if s == "envoye" and ct.v ~= "1" then return "contre-proposée" end -- j'ai répondu à sa contre-proposition
  return ETATS[s] or s
end

function ns.projetArtisan(p, name, i) commandes(p)[i or 1].player = name ~= "" and name or nil end
function ns.projetOffre(p, cuivre, i) commandes(p)[i or 1].tip = cuivre end

-- « Commander » un bloc (res.blocs) : une commande de plus dans ce projet, à celui qui en connaît le plus ; le même
-- bloc commandé deux fois redonne la même, tant qu'elle n'est pas envoyée (figée, une nouvelle la remplace pour la
-- suite). Renvoie son rang.
function ns.projetCommander(p, bloc)
  local list = commandes(p)
  for i, c in ipairs(list) do if c.bloc == bloc.key and not envoyee(c) then return i end end
  list[#list + 1] = { bloc = bloc.key, player = bloc.best }
  return #commandes(p)
end

-- La part du projet que vise la commande c, telle que le projet la fait maintenant : ses lignes et ses apports, rangés dans
-- v. Une commande de bloc livre ce que le bloc produit ; ses apports = ce qui entre dans le bloc (les livraisons des autres
-- blocs) et mes apports sous ses cases. Tout se lit sur l'arbre de la demande (dem = ns.projetDemande(p), aucun stock
-- déduit) : ce qu'un bloc livre = ce que le suivant reçoit, quel que soit le stock affiché dans la fenêtre. Si le bloc a
-- disparu (tout acheté…), elle reste, vide.
local function part(p, c, dem, v)
  if not c.bloc then
    v.lines, v.apports, v.reponse = p.lines, p.apports, p.reponse
    return v
  end
  v.lines, v.apports = {}, {}
  local bloc = dem().blocDe[c.bloc]
  for _, id in ipairs(bloc and bloc.deliver or {}) do v.lines[#v.lines + 1] = { id = id, qty = bloc.qty[id] } end
  for id in pairs(bloc and bloc.inputs or {}) do v.apports[id] = true end
  for _, n in ipairs(bloc and bloc.cases or {}) do
    for _, k in ipairs(n.children) do if k.apport > 0 then v.apports[k.id] = true end end
  end
  return v
end

-- Écart (#8) : la part que le projet fait maintenant (order) ne demande plus ce que dit le contrat ct : d'autres lignes ou
-- quantités, d'autres apports. Comparé objet par objet, quantité par quantité, comme le contrat les range : ni le marché ni
-- l'arrondi des prix par objet n'en créent un. Un choix de case se voit quand il change ces lignes ou ces apports ;
-- sinon il ne regarde que l'artisan (sa part, il la fabrique ou l'achète comme il veut).
local function ecart(order, ct)
  local function differe(list, t)
    for _, l in ipairs(list) do
      if t[l.id] ~= l.qty then return true end
      t[l.id] = nil
    end
    return next(t) ~= nil
  end
  local o, m = {}, {}
  for _, l in ipairs(order.lines) do o[l.id] = (o[l.id] or 0) + l.qty end
  for _, a in ipairs(ns.demandeApports(ns.projetDemande(order))) do m[a.id] = a.qty end
  return differe(ct.o, o) or differe(ct.m, m)
end
-- Un brouillon ne suit pas le projet non plus : il diffère aussi par l'artisan ou l'offre (à l'arrondi près, ½ pc par
-- objet livré, voir ns.ctFromDemande).
local function brouillonEcart(v, ct)
  local arrondi = 0
  for _, l in ipairs(ct.o) do arrondi = arrondi + l.qty / 2 end
  return ns.fullName(v.player or "") ~= ct.artisan or math.abs((v.tip or 0) - (ns.ctTotal(ct.o) - ns.ctTotal(ct.m))) > arrondi
    or ecart(v, ct)
end

-- Une commande telle qu'elle partirait : { part ("tout le projet" ou le métier), bloc, player, tip, lines, apports,
-- choix, reponse, vide }, la forme qu'attendent ns.ctFromDemande et ns.sendOrder. Pas envoyée, elle est une vue sur le
-- projet (part), recalculée à chaque appel, rien n'est recopié.
-- Envoyée, tant que son contrat prend une nouvelle version (envoyé, contre-proposé), v.ecart dit si sa part du projet a
-- changé depuis ; un brouillon, s'il ne suit plus le projet. Refusée, retirée ou échue : v.recommander, elle se commande
-- de nouveau (ns.projetRecommander).
local FINIE = { refuse = true, retire = true, echu = true }
local function vue(p, c, dem)
  local v = { id = c.id, part = c.bloc or "tout le projet", bloc = c.bloc, player = c.player, tip = c.tip, choix = p.choix, contrat = c.contrat }
  local ct = envoyee(c)
  if ct then
    v.fige, v.player, v.tip, v.lines, v.apports = true, ct.artisan:match("^[^%-]+"), math.max(0, ns.ctTotal(ct.o) - ns.ctTotal(ct.m)), {}, {}
    for _, l in ipairs(ct.o) do v.lines[#v.lines + 1] = { id = l.id, qty = l.qty } end
    for _, l in ipairs(ct.m) do v.apports[l.id] = true end
    local s = ns.ctStatus(ct)
    if (s == "envoye" or s == "a_signer") and ecart(part(p, c, dem, { choix = p.choix }), ct) then
      v.ecart = s == "envoye" and "a changé depuis la demande" or "diffère de sa contre-proposition"
    end
    v.recommander = FINIE[s]
  else
    part(p, c, dem, v)
    local brouillon = c.contrat and ns.ctStore()[c.contrat]
    if brouillon and not v.reponse and brouillonEcart(v, brouillon) then v.ecart = "brouillon à refaire" end
  end
  v.vide = #v.lines == 0
  if not v.reponse then v.etat = etat(ct) end
  return v
end

-- L'arbre de la demande, calculé au plus une fois et seulement si une commande de bloc le lit.
-- ponytail: recalculé à chaque appel (quelques ms) ; un cache le jour où la fenêtre rame
local function demandeDe(p)
  local dem
  return function() dem = dem or ns.projetDemande(p) return dem end
end

function ns.projetCommande(p, i)
  local c = commandes(p)[i or 1]
  return c and vue(p, c, demandeDe(p))
end

-- « Préparer la demande » : la commande i en brouillon de contrat (moi client, son artisan), lié à elle ; préparée de
-- nouveau, le brouillon est refait d'après le projet. Déjà envoyée : son contrat, inchangé. Renvoie le contrat, ou nil,
-- raison.
function ns.projetEnvoyer(p, i)
  local c = commandes(p)[i or 1]
  if envoyee(c) then return envoyee(c) end
  local ct, err = ns.ctFromDemande(ns.projetCommande(p, i), 3)
  if not ct then return nil, err end
  if c.contrat then ns.ctStore()[c.contrat] = nil end -- l'ancien brouillon
  ct.status, c.contrat = "brouillon", ns.ctKey(ct)
  ns.ctStore()[c.contrat] = ct
  return ct
end

-- « Nouvelle version » (#8) : la commande envoyée i, dont la part du projet a changé, repart en contre-proposition
-- (Contrat : nouvelle version, l'artisan voit le différentiel, accepte ou refuse) avec ce que sa part est maintenant. Son
-- offre reste celle du contrat : le différentiel = l'écart. Seulement sur un clic du joueur, jamais d'office. Renvoie la
-- nouvelle version, ou nil, raison.
function ns.projetNouvelleVersion(p, i)
  local c = commandes(p)[i or 1]
  local ct = envoyee(c)
  if not ct then return nil, "cette commande n'est pas envoyée" end
  local order = part(p, c, demandeDe(p), { choix = p.choix, tip = math.max(0, ns.ctTotal(ct.o) - ns.ctTotal(ct.m)) })
  if not ecart(order, ct) then return nil, "sa part du projet n'a pas changé" end
  return ns.ctVersionDemande(ct, order)
end

-- Une commande refusée, retirée ou échue se commande de nouveau : une commande vivante pour la même part, au même artisan
-- (la règle de « Commander » : celle qui n'est pas partie est reprise). Tout le projet aussi. Renvoie son rang, ou nil.
function ns.projetRecommander(p, i)
  local c = commandes(p)[i]
  local ct = c and envoyee(c)
  if not (ct and FINIE[ns.ctStatus(ct)]) then return nil end
  return ns.projetCommander(p, { key = c.bloc, best = c.player })
end

function ns.projetCommandes(p)
  local out, dem = {}, demandeDe(p)
  for i, c in ipairs(commandes(p)) do out[i] = vue(p, c, dem) end
  return out
end

---------------------------------------------------------------------------------------------------
-- Les cases : roots[i] = plan d'une ligne (ns.plan), fusionnés. Clés : "T<i>" la ligne i, "I<id>" un objet (toutes ses
-- apparitions additionnées). Un objet peut être en partie en stock, en partie fabriqué (made), en partie acheté (need),
-- ou apporté (apport). n.choix = le choix de case du projet ; n.parents / n.children et les liens (from, to, qty) : l'arbre.
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
  local list, me, byKey = {}, ns.charKey(), {}
  local function entry(key) -- un perso peut avoir ses recettes relevées sans fiche (ou l'inverse)
    if not byKey[key] then
      byKey[key] = { key = key, name = key:match("^[^%s%-]+"), ranks = {}, known = {} }
      list[#list + 1] = byKey[key]
    end
    return byKey[key]
  end
  for key, c in pairs(ns.chars()) do
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
  -- Un bloc = une commande : ce qu'il livre (aux autres blocs, et les objets du projet qu'il fabrique), ce qu'il reçoit
  -- des autres blocs (ses apports quand on le commande). Étape = 1 + la plus haute étape de ses fournisseurs : on
  -- commande du bas vers le haut.
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

-- L'arbre d'un projet : ses lignes l'une après l'autre sur le même stock, avec SES choix de case et SES apports, puis
-- les cases et les blocs. opts : options de stock et de recettes (celles de la fenêtre par défaut).
-- Renvoie { roots, cases, caseDe, liens, blocs, blocDe, livraisons, total, incomplete, market }.
function ns.projetArbre(p, opts)
  local roots, market, stock, total, incomplete = {}, nil, nil, 0, false
  for i, l in ipairs(p.lines) do
    roots[i], market, stock = ns.craftPlan(l.id, l.qty, opts or HandshakeDB.options, stock, p.apports, p.choix)
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
function ns.projetDemande(p) return ns.projetArbre(p, { unlearned = true }) end

---------------------------------------------------------------------------------------------------
-- Migration des SavedVariables (19/11/2026) : chaque commande enregistrée devient un projet (artisan et offre repris
-- tels quels, puis rangés dans sa commande « tout le projet » à la première lecture, voir commandes), une commande liée
-- à un contrat devient une réponse, la table globale des choix (« force ») est jetée.
-- old = GameDataDB d'avant le module (ses suivis deviennent un projet).
function ns.migrerProjets(d, old)
  if not d.projets then
    d.projets = {}
    for _, o in ipairs(d.orders or {}) do
      o.reponse, o.reponseHash, o.reply, o.replyHash = o.reply, o.replyHash, nil, nil
      d.projets[#d.projets + 1] = o
    end
    d.courant = d.current
    if not d.orders and old.craft_targets and #old.craft_targets > 0 then
      ns.nouveauProjet({ name = "Mon projet", lines = old.craft_targets })
    end
  end
  d.orders, d.current, d.force = nil, nil, nil
end
