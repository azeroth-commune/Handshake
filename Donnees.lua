-- Handshake, la base : les données dont le calcul a besoin (fenêtres, montants, noms d'objets : le socle).
-- Aucune donnée relevée n'est sauvegardée ici (ADR 0001 de l'atelier) : recettes connues, base des recettes (avec sa
-- réserve Classic, que porte le socle), inventaires, métiers, marchands,
-- objets et cours de l'HV sont lus par le socle (requis, lib:Lire) ; l'HV passe par son scan ou par un fournisseur
-- (Auctionator…).
-- HandshakeDB ne garde que les données propres de Handshake : commandes, contrats, projets, réglages.
local _, ns = ...

local lib = AzerothCommune
-- Ce que Handshake lit : le socle ne relève que les types auxquels un add-on a souscrit (GameData#4).
for _, t in ipairs({ "recettes connues", "base des recettes", "inventaires", "métiers et compétences", "marchands", "objets",
  "cours de l'HV" }) do lib:Souscrire(t) end
-- Recettes connues de tous les persos relevés et recettes vues, ou rien.
local function recettesConnues()
  return lib:Lire("recettes connues", "tous") or { recettes = {}, persos = {} }
end
-- { [GUID] = { [métier] = { rank, max, known = { [clé] = difficulté } } } }
function ns.knownRecipes() return recettesConnues().persos end
-- Un type par perso, tous les persos relevés : { [GUID] = … }.
local function parPerso(t) local d = lib:Lire(t, "tous") return d and d.persos or {} end

---------------------------------------------------------------------------------------------------
-- Accès aux données (par la lib)
-- Recettes : la base des recettes du socle (AzerothCommune#48) : celles relevées dans les fenêtres de métier, puis sa
-- réserve Classic (provenance « source externe ») pour les objets qu'aucune recette vue ne fabrique (les métiers que tu
-- n'as pas). Chaque recette porte sa compétence requise (level) quand la réserve la connaît.
local nomsDemandes = {} -- recettes dont on a déjà demandé les noms d'objets
function ns.recipes()
  local recettes = lib:Lire("base des recettes") or {}
  if not lib:Lire("objets") then -- catalogue des objets pas encore relevé : personne d'autre ne demande ces noms au serveur
    for k, r in pairs(recettes) do
      if not nomsDemandes[k] and not r.provenance then -- les recettes vues seulement, pas la réserve
        nomsDemandes[k] = true
        if r.output then ns.rememberItem(r.output) end
        for _, rg in ipairs(r.reagents or {}) do ns.rememberItem(rg.id) end
      end
    end
  end
  return recettes
end
-- { [GUID] = { bags, bank, … } } ; { [GUID] = { professions, skills } } ; { [PNJ] = { items = { { id, price, stack, limited } } } }
function ns.inventaires() return parPerso("inventaires") end
function ns.metiers() return parPerso("métiers et compétences") end
function ns.vendors() return lib:Lire("marchands") or {} end
-- Mes sacs, lus à l'instant (la fenêtre se recalcule à chaque changement de sac).
function ns.mesSacs() return lib.Conteneurs(lib.EstSac) end

-- Noms d'objets : le catalogue des objets du socle, sinon ceux arrivés du serveur cette session, en mémoire seulement.
local nomsDeSession = {}
function ns.items() return lib:Lire("objets") or nomsDeSession end

-- Cours de l'HV (scan du socle, sinon un fournisseur : Auctionator, TSM, AuctionDB), même forme qu'avant :
-- { items = { [id] = { min, qty, tiers, … } }, scanned (date du scan du socle), source (le fournisseur) }, ou nil et
-- la raison du socle.
function ns.market()
  local d, lot = lib:Lire("cours de l'HV")
  if not d then return nil, lot end
  local h = d.hv and d.hv[lib.MaisonHV()] -- sondée par la lib
  -- ponytail: une ligne lue au plus une fois par calcul (un calcul = un ns.market())
  local items = setmetatable({}, { __index = function(t, id)
    local l = d.objet(id) or false
    rawset(t, id, l)
    return l
  end })
  return { items = items, scanned = h and h.scanned, source = lot and lot.fournisseur }
end
-- L'état des prix de l'HV, pour la barre d'état : d'où ils viennent, ou comment les avoir.
function ns.texteHV(m)
  if not m then m = ns.market() end
  if m and m.scanned then return "HV du " .. m.scanned end
  if m then return "prix de l'HV : " .. (m.source or "?") end
  return "HV jamais scanné : ouvre l'hôtel des ventes"
end

-- Un perso du joueur est rangé sous son GUID (LibCommune#19) ; son nom « Prénom Nom », celui qu'on chuchote (« ? » si la
-- socle ne le connaît pas : un perso pas encore reconnecté depuis le passage au socle) ; son prénom, pour un
-- affichage court.
function ns.nomPerso(guid)
  local p = lib.Personnage(guid)
  return p and p.nom or "?"
end
function ns.prenom(guid) return (ns.nomPerso(guid):match("^%S+")) end

-- Le nom complet « Prénom Nom » d'un destinataire (un « -Royaume » retiré, lib.Destinataire), nil s'il n'y a qu'un
-- prénom : le serveur refuse un chuchotement au prénom seul (LibCommune#35). Aucun nom de famille n'est deviné.
function ns.nomComplet(nom)
  nom = lib.Destinataire(nom)
  return type(nom) == "string" and nom:match("^%S+ %S+$") or nil
end

---------------------------------------------------------------------------------------------------
-- Montants, noms d'objets, fenêtres : ceux du socle. Un nom d'objet arrivé du serveur est retenu en mémoire
-- (nomsDeSession), jamais sauvegardé.
ns.money, ns.moneyShort, ns.moneySigned, ns.newWindow = lib.Argent, lib.ArgentCourt, lib.ArgentSigne, lib.Fenetre
function ns.rememberItem(id) return lib.RetenirObjet(id, nomsDeSession) end
function ns.itemLabel(id) return lib.NomObjet(id, ns.items(), nomsDeSession) end
function ns.findItem(text) return lib.TrouverObjet(text, ns.items(), ns.recipes()) end
-- Suggestions de la barre de recherche des projets : objets vus et objets fabriqués de la base des recettes, lus par le
-- socle (Handshake souscrit aux deux types ci-dessus).
ns.chercherObjets = lib.ChercherObjets

---------------------------------------------------------------------------------------------------
-- Les données relevées ne se sauvegardent plus ici (ADR 0001 de l'atelier) : on purge celles d'un Handshake d'avant
-- (recettes, sacs et banque des persos, noms d'objets, HV). Les données propres restent.
local RELEVES = { "recipes", "chars", "items", "market" }
function ns.purgerAnciensReleves()
  for _, k in ipairs(RELEVES) do HandshakeDB[k] = nil end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, a1)
  if a1 ~= "Handshake" then return end
  HandshakeDB = HandshakeDB or {}
  ns.purgerAnciensReleves()
end)
