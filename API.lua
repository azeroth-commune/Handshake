-- Handshake, l'API publique (README.md) : un seul global, Handshake, celui dont Composants se sert pour dessiner dans sa
-- fenêtre des projets « Commander » sur un bloc, Ctrl+clic « j'apporte » sur une case et la barre des commandes. Seul ce
-- qui est ici est promis ; l'intérieur (contrats, échange) reste privé. p = un projet de Composants (Handshake range ses
-- commandes par son identité, p.id) ; i = le rang d'une commande dans le projet (1 = tout le projet, ou la Réponse).
local _, ns = ...

local function dire(err) if err then print("|cffe64d4dContrats :|r " .. err .. ".") end end

Handshake = {
  -- Les commandes du projet, telles qu'elles partiraient : { part, bloc, player, tip, lines, apports, etat, fige, ecart,
  -- ecartPrix, alertePrix, incomplet, recommander, reponse, vide } ; l'état se lit dans le contrat, jamais saisi à part.
  Commandes = function(p) return ns.projetCommandes(p) end,
  Commande = function(p, i) return ns.projetCommande(p, i) end,
  Commander = function(p, bloc) return ns.projetCommander(p, bloc) end, -- bloc = Composants.Arbre(p).blocDe[métier] ; rend son rang
  Artisan = function(p, nom, i) ns.projetArtisan(p, nom, i) end,
  Offre = function(p, cuivre, i) return ns.projetOffre(p, cuivre, i) end,
  -- « Préparer la demande » : le brouillon de contrat de la commande i (ou, dans une Réponse, la contre-proposition), ouvert
  -- dans Contrats ; déjà envoyée, son contrat. Rend le contrat, ou nil (la raison est dite dans le chat).
  Preparer = function(p, i)
    local c = ns.projetCommande(p, i)
    local ct, err
    if c.reponse then ct, err = ns.ctReplyFromOrder(c) else ct, err = ns.projetEnvoyer(p, i) end
    if not ct then return dire(err) end
    ns.openContracts(ns.ctKey(ct))
    return ct
  end,
  -- À côté d'une commande partie : « Commander de nouveau » (refusée, retirée, échue : rend le rang de la nouvelle) ou
  -- « Nouvelle version » (sa part du projet a changé : le brouillon s'ouvre dans Contrats ; rend nil).
  Agir = function(p, i)
    if ns.projetCommande(p, i).recommander then return ns.projetRecommander(p, i) end
    local n, err = ns.projetNouvelleVersion(p, i)
    if not n then return dire(err) end
    ns.openContracts(ns.ctKey(n))
  end,
  EnClair = function(p, i) ns.sendOrder(ns.projetCommande(p, i)) end, -- la demande en texte lisible, chuchotée à l'artisan
  Importer = function() ns.openImport() end,                        -- une liste reçue, en projet
  -- L'apport : une case que le demandeur fournit lui-même, un terme des commandes du projet (jamais du projet).
  Apports = function(p) return ns.projetApports(p) end,             -- { [itemID] = true }, ou nil
  Apporter = function(p, id, oui) return ns.projetApport(p, id, oui) end,
  EstReponse = function(p) return ns.estReponse(p) end,             -- ce projet est-il la Réponse à une demande reçue ?
}
