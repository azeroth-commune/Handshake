-- Handshake : la commande à la main (#38), sans arbre ni projet. Deux listes d'objets × quantités, « ce que je veux » et
-- « ce que j'apporte », remplies par la recherche d'objets du socle ou par Maj+clic sur un lien ; l'artisan et l'offre.
-- Elle part par le chemin d'une commande de projet : brouillon de contrat (ns.ctFromDemande), relu et envoyé dans
-- Contrats, ou texte lisible (ns.sendOrder). Côté artisan, une demande reçue se répond dans la même liste : ce qu'il veut
-- en lecture seule, apports et prix modifiables, contre-proposition (ns.ctReplyFromOrder).
-- Ctrl+clic droit n'est jamais pris ici : il appartient aux projets.
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
