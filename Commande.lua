-- Handshake : une commande passe d'un joueur à l'autre.
-- Commande = une part d'un projet de Composants (ns.projetCommande, plus bas ; le projet, son arbre et ses blocs : l'API
-- publique de Composants, global Composants, quand il est chargé) ou une commande à la main (CommandeMain.lua) : ses lignes
-- « objet × quantité », le joueur d'en face, une offre, des apports.
-- Échange : du texte avec des liens d'objets, lisible et écrivable à la main (Maj+clic), par chuchotement :
--   Commande : 1x[Claymore en mithril] 1x[Camail en mithril] · j'apporte 36x[Minerai de mithril] · offre 5 po
--   Besoins (1/2) : 36x[Minerai de mithril] 12x[Pierre solide] …
-- Un message est limité à 255 caractères (un lien en prend ~80) : la liste part en plusieurs messages (i/n),
-- recollés à l'arrivée.
local _, ns = ...

local MAX_MSG = 255

---------------------------------------------------------------------------------------------------
-- Les commandes d'un projet (CONTEXT.md), rangées à part dans HandshakeDB.commandes[p.id], rattachées à l'identité du
-- projet de Composants (qui ne sait rien d'elles) : { liste = { { id (unique dans le projet), bloc (le métier ; nil = tout
-- le projet : la 1re, et celles recommandées), player (l'artisan), tip (l'offre, en cuivre), contrat (clé de son contrat,
-- une fois préparée) } }, seq (la dernière identité de commande donnée), apports = { [id] = true } (mes apports, pour
-- toutes ses commandes), reponse (clé du contrat dont il est la réponse), reponseHash }.
local function rangement(p)
  HandshakeDB.commandes = HandshakeDB.commandes or {}
  local r = HandshakeDB.commandes[p.id]
  if not r then
    r = { liste = { { id = 1 } }, seq = 1 }
    HandshakeDB.commandes[p.id] = r
  end
  return r
end
local function commandes(p) return rangement(p).liste end

-- Supprimer un projet (Composants le signale) efface ses commandes pas encore parties ; jamais un contrat : une commande
-- envoyée reste dans Contrats, sans écart calculé (plus de projet à comparer).
function ns.oublierCommandes(p)
  local r = p and HandshakeDB.commandes and HandshakeDB.commandes[p.id]
  if not r then return end
  for _, c in ipairs(r.liste) do ns.retirerTB(c) end -- ses demandes au tableau de Trade Board (Annonce.lua)
  HandshakeDB.commandes[p.id] = nil
end

-- L'arbre de la demande (CONCEPTION.md) d'un projet ou d'une part de projet { lines, choix } : toutes les recettes, aucun
-- stock déduit (les stocks du demandeur ne réduisent pas la part de l'artisan), les apports retirés. Par Composants.
function ns.arbreDemande(p, apports) return Composants.Arbre(p, true, apports) end

-- Mes apports sur ce projet (nil = aucun) : l'arbre les reçoit (Composants.Arbre(p, …, ns.projetApports(p))).
function ns.projetApports(p) return rangement(p).apports end

-- « Je le fournis » : un terme des commandes du projet, par case entière ; la case, et tout ce qu'il y a sous elle, sort
-- de la part de l'artisan.
function ns.projetApport(p, id, oui)
  local r = rangement(p)
  r.apports = r.apports or {}
  r.apports[id] = oui or nil
  if not next(r.apports) then r.apports = nil end
  return true
end

-- Ce projet est-il une réponse (la demande d'un autre) ?
function ns.estReponse(p) return rangement(p).reponse ~= nil end

-- « Je réponds » (Composants chargé) : la demande reçue devient une réponse, un projet de Composants lié au contrat (sa clé
-- dans le rangement) et tenu (Composants.Tenir) : ce qu'il veut ne change pas ici ; ses apports (Ctrl+clic pour contre-proposer) et le prix actuel
-- sont recopiés à chaque nouvelle version. Ses choix de case, son prix et les blocs qu'il commande restent à l'artisan.
local FIGE = "c'est sa demande : ce qu'il veut ne change pas ici"
ns.FIGE = FIGE -- la même raison dans la réponse en liste (CommandeMain.lua)
function ns.projetReponse(c)
  local C, key, p, r = Composants, ns.ctKey(c), nil, nil
  for id, x in pairs(HandshakeDB.commandes or {}) do
    local q = x.reponse == key and C.Projet(id)
    if q then p, r = q, x end
  end
  if not p then
    p = C.NouveauProjet()
    r = rangement(p)
    r.reponse = key
  end
  if r.reponseHash == c.hash then return p end -- même version : on garde ce que tu as changé
  local tout = r.liste[1]
  local client = c.peer and c.peer.name or "?" -- le client, sous le nom donné par le serveur
  r.reponseHash, tout.player = c.hash, client
  C.Renommer(p, "Réponse à " .. client:match("^%S+"))
  local lines = {}
  for _, l in ipairs(c.o) do lines[#lines + 1] = { id = l.id, qty = l.qty } end
  C.Tenir(p, FIGE, lines) -- ses choix de case restent
  r.apports = nil
  for _, l in ipairs(c.m) do r.apports = r.apports or {}; r.apports[l.id] = true end
  tout.tip = math.max(0, ns.ctTotal(c.o) - ns.ctTotal(c.m))
  return p
end

-- Les commandes : des parts du projet, chacune à un artisan, avec son offre. i = son rang (1 = tout le
-- projet, par défaut). Dans une réponse, la 1re est la réponse elle-même (son artisan = le demandeur, son offre = mon
-- prix) ; commander un de ses blocs, c'est le sous-traiter.
-- Envoyée (#7), elle est une demande : figée, son contenu est celui de son contrat (c.contrat = sa clé, ns.ctKey), à
-- sa dernière version ; v.fige, v.contrat. Son état (v.etat) se lit toujours dans le contrat, jamais saisi à part.
-- Un brouillon (« Préparer la demande », pas encore parti) ne la fige pas : elle suit encore le projet.
local function envoyee(c)
  local ct = c.contrat and ns.ctStore()[c.contrat]
  return ct and ct.status ~= "brouillon" and ct or nil
end
ns.commandeEnvoyee = envoyee
local ETATS = { envoye = "demande envoyée", a_signer = "contre-proposée", signe = "signée", clos = "livrée",
  echu = "échue", refuse = "refusée", retire = "retirée" }
local function etat(ct)
  if not ct then return "pas envoyée" end
  local s = ns.ctStatus(ct)
  if s == "envoye" and ct.v ~= "1" then return "contre-proposée" end -- j'ai répondu à sa contre-proposition
  return ETATS[s] or s
end
ns.etatDemande = etat

function ns.projetArtisan(p, name, i) commandes(p)[i or 1].player = name ~= "" and name or nil end
function ns.projetOffre(p, cuivre, i)
  commandes(p)[i or 1].tip = cuivre
  return true
end

-- « Commander » un bloc (res.blocs) : une commande de plus dans ce projet, à celui qui en connaît le plus ; le même
-- bloc commandé deux fois redonne la même, tant qu'elle n'est pas envoyée (figée, une nouvelle la remplace pour la
-- suite). Renvoie son rang.
function ns.projetCommander(p, bloc)
  local r = rangement(p)
  for i, c in ipairs(r.liste) do if c.bloc == bloc.key and not envoyee(c) then return i end end
  r.seq = r.seq + 1
  r.liste[#r.liste + 1] = { id = r.seq, bloc = bloc.key, player = bloc.best }
  return #r.liste
end

-- La part du projet que vise la commande c, telle que le projet la fait maintenant : ses lignes et ses apports, rangés dans
-- v. Une commande de bloc livre ce que le bloc produit ; ses apports = ce qui entre dans le bloc (les livraisons des autres
-- blocs) et mes apports sous ses cases. Tout se lit sur l'arbre de la demande (dem = ns.arbreDemande, aucun stock
-- déduit) : ce qu'un bloc livre = ce que le suivant reçoit, quel que soit le stock affiché dans la fenêtre. Si le bloc a
-- disparu (tout acheté…), elle reste, vide.
-- Les lignes du projet telles qu'elles s'échangent : une fabrication { recette, fois } (Composants) devient l'objet produit
-- × fois × quantité produite ; un enchantement (rien de produit) ou une recette absente de la base ne s'échange pas : pas
-- de ligne (#49).
local function objets(lines)
  local out, recettes = {}, nil
  for _, l in ipairs(lines) do
    if l.recette then
      recettes = recettes or ns.recipes()
      local r = recettes[l.recette]
      if r and r.output then out[#out + 1] = { id = r.output, qty = l.fois * math.max(1, r.made_min or 1) } end
    else
      out[#out + 1] = l
    end
  end
  return out
end

local function part(p, c, dem, v)
  if not c.bloc then
    local r = rangement(p)
    v.lines, v.apports, v.reponse = objets(p.lines), r.apports, r.reponse
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
  for _, a in ipairs(ns.demandeApports(ns.arbreDemande(order, order.apports))) do m[a.id] = a.qty end
  return differe(ct.o, o) or differe(ct.m, m)
end
-- Un brouillon ne suit pas le projet non plus : il diffère aussi par l'artisan ou l'offre (à l'arrondi près, ½ pc par
-- objet livré, voir ns.ctFromDemande).
local function brouillonEcart(v, ct)
  local arrondi = 0
  for _, l in ipairs(ct.o) do arrondi = arrondi + l.qty / 2 end
  return ns.fullName(v.player or "") ~= (ct.peer and ct.peer.name) or math.abs((v.tip or 0) - (ns.ctTotal(ct.o) - ns.ctTotal(ct.m))) > arrondi
    or ecart(v, ct)
end

-- Une commande telle qu'elle partirait : { part ("tout le projet" ou le métier), bloc, player, tip, lines, apports,
-- choix, reponse, vide }, la forme qu'attendent ns.ctFromDemande et ns.sendOrder. Pas envoyée, elle est une vue sur le
-- projet (part), recalculée à chaque appel, rien n'est recopié.
-- Envoyée, tant que son contrat prend une nouvelle version (envoyé, contre-proposé), v.ecart dit si sa part du projet ne
-- correspond plus au contrat ; un brouillon, s'il ne suit plus le projet. L'écart est constaté, jamais expliqué (#18) : le
-- marché, l'autre joueur ou moi, la page ne peut pas savoir. Envoyée avec des apports : sa caution contre MON estimation
-- actuelle (P8, ns.ctEstimation, la même que la fiche du contrat) : v.ecartPrix en %, v.alertePrix au-delà du seuil, ou
-- v.incomplet (un composant sans prix connu : pas de pourcentage faux). Refusée, retirée ou échue : v.recommander, elle se
-- commande de nouveau (ns.projetRecommander).
local FINIE = { refuse = true, retire = true, echu = true }
local function vue(p, c, dem)
  local v = { id = c.id, part = c.bloc or "tout le projet", bloc = c.bloc, player = c.player, tip = c.tip, choix = p.choix, contrat = c.contrat }
  local ct = envoyee(c)
  if ct then
    v.fige, v.player, v.tip, v.lines, v.apports = true, ct.peer and ct.peer.name, math.max(0, ns.ctTotal(ct.o) - ns.ctTotal(ct.m)), {}, {}
    for _, l in ipairs(ct.o) do v.lines[#v.lines + 1] = { id = l.id, qty = l.qty } end
    for _, l in ipairs(ct.m) do v.apports[l.id] = true end
    local s = ns.ctStatus(ct)
    if (s == "envoye" or s == "a_signer") and ecart(part(p, c, dem, { choix = p.choix }), ct) then
      v.ecart = "ne correspond plus au contrat"
    end
    if #ct.m > 0 then
      local e = ns.ctEstimation(ct, ns.me())
      v.incomplet = e.manquants > 0
      if not v.incomplet then v.ecartPrix, v.alertePrix = e.ecart, e.alerte end
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
  return function() dem = dem or ns.arbreDemande(p, ns.projetApports(p)) return dem end
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

-- « Nouvelle version » (#8) : la commande envoyée i, dont la part du projet a changé, prépare sa contre-proposition
-- (Contrat : nouvelle version, l'artisan voit le différentiel, accepte ou refuse) avec ce que sa part est maintenant. Son
-- offre reste celle du contrat : le différentiel = l'écart. Elle reste en brouillon (#19) : le joueur la relit dans
-- Contrats et l'envoie de là. Renvoie le brouillon, ou nil, raison.
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

-- « Annoncer » la commande i (Annonce.lua) ; rend true, ou nil et la raison.
function ns.projetAnnoncer(p, i) return ns.annoncer(ns.projetCommande(p, i), nil, commandes(p)[i or 1]) end

function ns.projetCommandes(p)
  local out, dem = {}, demandeDe(p)
  for i, c in ipairs(commandes(p)) do out[i] = vue(p, c, dem) end
  return out
end

---------------------------------------------------------------------------------------------------
-- Les apports d'une demande, avec leur quantité (case entière) : { { id, qty }, … } triés par ID.
function ns.demandeApports(res)
  local out = {}
  for _, n in ipairs(res.cases) do
    if (n.apport or 0) > 0 then out[#out + 1] = { id = n.id, qty = n.apport } end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- Ce que la commande apporte, objets × quantités triés par ID : la liste d'une commande à la main (order.apporte, un
-- même objet cumulé), sinon les cases apportées de l'arbre de la commande de projet (res, calculé au besoin).
function ns.commandeApports(order, res)
  if not order.apporte then return ns.demandeApports(res or ns.arbreDemande(order, order.apports)) end
  local qty, out = {}, {}
  for _, a in ipairs(order.apporte) do qty[a.id] = (qty[a.id] or 0) + a.qty end
  for id, q in pairs(qty) do out[#out + 1] = { id = id, qty = q } end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

---------------------------------------------------------------------------------------------------
-- Texte échangé
local function chatLink(id)
  local it = ns.items()[id]
  return (it and it.link) or select(2, C_Item.GetItemInfo(id)) or ("[" .. ((it and it.name) or ("objet " .. id)) .. "]")
end
ns.lienObjet = chatLink

local function po(copper) return (("%.2f"):format(copper / 10000)):gsub("%.?0+$", "") .. " po" end
ns.poText = po

-- lines : { { id, qty } ou { text, qty } } ; extra : texte ajouté à la fin (offre…). Renvoie les messages.
-- annonce (Annonce.lua) : un seul message « WTB [lien] xN, [lien] xM », la forme que lisent les lecteurs du Commerce (Trade
-- Board…) ; trop long, il est coupé entre deux liens, « … » au bout.
function ns.listMessages(kind, lines, extra, annonce)
  local tokens = {}
  for _, l in ipairs(lines) do
    local lien = not l.raw and (l.text or chatLink(l.id))
    tokens[#tokens + 1] = l.raw or (annonce and ("%s x%d"):format(lien, l.qty) or ("%dx%s"):format(l.qty, lien))
  end
  if extra and extra ~= "" then tokens[#tokens + 1] = extra end
  if annonce then
    local function joindre(room)
      local msg, n = kind, 0
      for i, t in ipairs(tokens) do
        local sep = i == 1 and " " or ", "
        if #msg + #sep + #t > room then break end
        msg, n = msg .. sep .. t, i
      end
      return msg, n
    end
    local msg, n = joindre(MAX_MSG)
    if n < #tokens then msg = joindre(MAX_MSG - #" …") .. " …" end
    return { msg }
  end
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
-- crochets tapés à la main. Renvoie lines, genre (« commande », « besoins »…), offre (cuivre), apports, puis (dans ce qu'on
-- veut) les sorts des liens de recette (« |Henchant:… », « |Hspell:… ») et liens (au moins un lien d'objet ou de recette lu,
-- pas des noms tapés).
local function parseItems(text)
  local lines, byId, recettes = {}, {}, {}
  local function add(id, q)
    if not id then return end
    if byId[id] then byId[id].qty = byId[id].qty + q return end
    byId[id] = { id = id, qty = q }
    lines[#lines + 1] = byId[id]
  end
  local pos, found = 1, false
  while true do
    local s, e, quoi, id = text:find("|H(%a+):(%d+)[^|]*|h[^|]*|h", pos)
    if not s then break end
    if quoi == "item" then
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
    elseif quoi == "enchant" or quoi == "spell" then -- le lien d'une recette (son sort) : à part, ce n'est pas un objet
      found = true
      recettes[#recettes + 1] = tonumber(id)
    end
    pos = e + 1
  end
  if not found then
    for q, name in text:gmatch("(%d*)%s*[xX]?%s*%[([^%]]+)%]") do add(ns.findItem(name), tonumber(q) or 1) end
  end
  return lines, recettes, found
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
  local lines, recettes, liens = parseItems(wanted)
  return lines, kind and kind:lower(), tip, brought, recettes, liens
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
  local nom = ns.nomComplet(target)
  if not nom then
    return print(("|cffe64d4dCommandes :|r « %s » : indique son nom complet « Prénom Nom », le serveur refuse un chuchotement au prénom seul."):format(target))
  end
  target = nom
  for _, m in ipairs(msgs) do ns.whisper(m, target) end
  print(("Commandes : %s envoyée à %s (%d message%s)."):format(kind:lower(), target, #msgs, #msgs > 1 and "s" or ""))
end

-- La demande en clair (pour quelqu'un sans l'addon) : « Commande : 1x[Armure] · j'apporte 4x[Cuir lourd] · offre 5 po ».
-- order = une commande (ns.projetCommande, ou à la main : ns.commandeMain) ; envoyée (figée), ses apports sont ceux de
-- son contrat.
function ns.sendOrder(order, loop)
  local lines = {}
  for _, l in ipairs(order.lines) do lines[#lines + 1] = l end
  local brought = order.fige and ns.ctStore()[order.contrat].m or ns.commandeApports(order)
  if #brought > 0 then
    lines[#lines + 1] = { raw = "· j'apporte" }
    for _, l in ipairs(brought) do lines[#lines + 1] = l end
  end
  send("Commande", lines, order.tip and order.tip > 0 and ("· offre " .. po(order.tip)) or nil, order.player, loop)
end

---------------------------------------------------------------------------------------------------
-- Réception : le dernier message avec des objets (pour l'import à la main), et les listes en plusieurs
-- morceaux recollées. Une commande ou des besoins reçus en chuchotement proposent l'import.
ns.lastReceived = nil
local parts = {}

-- Importée : un projet de Composants et sa commande « tout le projet », ou, sans Composants, une nouvelle commande à la main.
function ns.importText(text, player)
  local lines, kind, tip, brought = ns.parseList(text)
  if #lines == 0 then return print("|cffe64d4dCommandes :|r aucun objet reconnu dans ce texte.") end
  local who = player and player ~= "" and player or nil
  if not Composants then
    local cur = ns.commandeMain()
    if (#cur.lines > 0 or #cur.apporte > 0) and not ns.commandeEnvoyee(cur) then
      print("|cffe64d4dCommandes :|r une commande à la main est en cours : envoie-la ou fais « Nouvelle », puis importe de nouveau.")
      return ns.openCommandeMain()
    end
    local m = ns.mainNouvelle()
    m.lines, m.apporte, m.player, m.tip = lines, brought, who, tip
    return ns.openCommandeMain()
  end
  local p = Composants.NouveauProjet({ name = (kind == "besoins" and "Besoins" or "Commande") .. (who and (" de " .. who) or ""), lines = lines })
  ns.projetArtisan(p, who)
  ns.projetOffre(p, tip)
  for _, l in ipairs(brought) do ns.projetApport(p, l.id, true) end
  Composants.Ouvrir(p.id)
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
    -- le jeu joint à chaque chuchotement le GUID de l'expéditeur (12e valeur) : source serveur, on le retient
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
f:RegisterEvent("PLAYER_LOGIN")
for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD" }) do
  f:RegisterEvent(e)
end
f:SetScript("OnEvent", function(_, event, a1, a2, ...)
  if event == "PLAYER_LOGIN" then return ns.brancherComposants() end
  if event ~= "ADDON_LOADED" then return ns.onChat(event, a1, a2, ...) end
  if a1 ~= "Handshake" then return end
  HandshakeDB = HandshakeDB or {}
  local db = HandshakeDB
  db.contracts = db.contracts or {}
  -- Contrats d'avant la signature par GUID (Handshake#29 : signataires « Prénom-Royaume ») : plus lus, purgés.
  for _, base in ipairs({ db.contracts, db.debug and db.debug.contracts or {} }) do
    for k, c in pairs(base) do if not tostring(c.client):find("^Player%-") then base[k] = nil end end
  end
  for _, c in pairs(db.contracts) do c.unsaved = nil end -- ce qui est chargé a été enregistré
  ns.purgerProjets(db)
end)

-- Les projets sont partis dans Composants (Handshake#39), sans migration (perte acceptée) : ceux d'avant, leurs commandes
-- (rattachées à des identités que Composants redonnera) et les réglages de l'arbre s'effacent ; les contrats restent.
function ns.purgerProjets(db)
  if db.projets then db.projets, db.projetSeq, db.courant, db.commandes = nil, nil, nil, nil end
  db.options, db.orders, db.current, db.force = nil, nil, nil, nil
end

-- Composants chargé (après Handshake : il le déclare en OptionalDeps) : à l'entrée en jeu, ses projets sont lus. Les
-- commandes pas encore parties d'un projet qui n'existe plus sont oubliées (un contrat, lui, reste toujours), puis chaque
-- suppression de projet efface les siennes.
function ns.brancherComposants()
  local C = Composants
  if not C or ns.branche then return end
  ns.branche = true
  for id in pairs(HandshakeDB.commandes or {}) do
    if not C.Projet(id) then ns.oublierCommandes({ id = id }) end
  end
  C.QuandChange(function(p, quoi) if quoi == "supprime" then ns.oublierCommandes(p) end end)
end

---------------------------------------------------------------------------------------------------
-- /handshake (ou /commande) : avec Composants, la fenêtre des projets, où vivent les commandes ; sans lui, la commande à
-- la main. /handshake liste : la commande à la main ; /handshake demandes : les Demandes lues (Annonce.lua). /handshake
-- essai : la commande à la main revient comme un chuchotement de soi-même, sans réseau (le même chemin qu'à l'arrivée) ;
-- /handshake essai annonce : son annonce, affichée seulement. /handshake debug : Debug.lua.
function ns.ouvrir()
  if Composants then return Composants.Ouvrir() end
  ns.openCommandeMain()
end
SLASH_HANDSHAKE1, SLASH_HANDSHAKE2 = "/handshake", "/commande"
SlashCmdList.HANDSHAKE = function(args)
  args = args or ""
  if args:match("^%s*liste%s*$") then return ns.openCommandeMain() end
  if args:match("^%s*demandes%s*$") then return ns.openDemandes() end
  if args:match("^%s*essai%s+annonce") then -- l'annonce de la commande à la main, affichée, rien sur le réseau
    local ok, err = ns.annoncer(ns.commandeMain(), true)
    if not ok then print("|cffe64d4dHandshake :|r " .. err .. ".") end
    return
  end
  if args:match("^%s*essai") then return ns.sendOrder(ns.commandeMain(), true) end
  -- /handshake <objet> [qté] [tout], /handshake demo … : l'arbre est à Composants, la commande lui revient.
  if args:match("%S") and Composants and SlashCmdList.COMPOSANTS then return SlashCmdList.COMPOSANTS(args) end
  ns.ouvrir()
end

-- Bouton de minicarte et entrée des options communs d'Azeroth Commune : clic ou ligne du menu = /handshake.
AzerothCommune.Regrouper({ nom = "Handshake", dossier = "Handshake", icone = "Interface\\Icons\\Trade_BlackSmithing",
  ouvrir = function() ns.ouvrir() end, store = function() return HandshakeDB end })
