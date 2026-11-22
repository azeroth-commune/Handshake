-- Handshake, la base : les données dont les contrats ont besoin (fenêtres, montants, noms d'objets : le socle).
-- Aucune donnée relevée n'est sauvegardée ici (ADR 0002 de l'atelier) : base des recettes (vérifier les besoins d'un
-- contrat), marchands et cours de l'HV (prix d'achat : caution, estimation), objets (noms, recherche) sont lus par le
-- socle (requis, lib:Lire) ; l'HV passe par son scan ou par un fournisseur (Auctionator…). L'arbre et ses données (sacs,
-- recettes connues, métiers des persos) sont à Composants.
-- HandshakeDB ne garde que les données propres de Handshake : commandes, contrats, réglages.
local _, ns = ...

local lib = AzerothCommune
-- Ce que Handshake lit : le socle ne relève que les types auxquels un add-on a souscrit (GameData#4).
for _, t in ipairs({ "base des recettes", "marchands", "objets", "cours de l'HV" }) do lib:Souscrire(t) end

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
-- Suggestions de la barre de recherche de la commande à la main : objets vus et objets fabriqués de la base des recettes,
-- lus par le socle (Handshake souscrit aux deux types ci-dessus).
ns.chercherObjets = lib.ChercherObjets

---------------------------------------------------------------------------------------------------
-- Les données relevées ne se sauvegardent plus ici (ADR 0002 de l'atelier) : on purge celles d'un Handshake d'avant
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
