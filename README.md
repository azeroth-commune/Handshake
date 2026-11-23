# Handshake (bêta)

Add-on WoW Forever, catégorie Métiers : commandes et contrats d'artisanat entre joueurs. Glossaire : `CONTEXT.md` ;
conception : `CONCEPTION.md` ; modèle de menace : `SECURITE.md` ; pour le joueur : `LISEZ-MOI.txt`.

- **Requiert** le socle Azeroth Commune (`## Dependencies: AzerothCommune`).
- **Seul**, Handshake sert par la commande à la main (`/handshake liste`, ou `/handshake`), les contrats (`/contrat`) et
  le panneau qui vérifie chaque échange. Dans le chat public (`Annonce.lua`) : « Annoncer » une commande dans le canal
  Commerce, et les **Demandes lues** (`/handshake demandes`, onglet de la commande à la main) : les demandes du Commerce et
  des cris pour ce que mes persos savent fabriquer (recettes connues relevées par le socle), en mémoire le temps de la
  session, chacune quelques minutes.
- **Avec Composants** (chargé ou non, aucun des deux ne requiert l'autre), les commandes rejoignent ses projets : chaque
  commande est rangée sous l'identité d'un projet de Composants (`HandshakeDB.commandes[p.id]`), et la fenêtre des projets
  de Composants dessine « Commander » sur un bloc, Ctrl+clic « j'apporte » sur une case et la barre des commandes en
  appelant l'API ci-dessous. Une demande reçue s'ouvre en **Réponse**, un projet tenu de Composants
  (`Composants.Tenir`). Handshake lit l'arbre par `Composants.Arbre` et suit le signal `Composants.QuandChange` :
  supprimer un projet efface ses commandes pas encore parties, jamais un contrat ; à l'entrée en jeu, les commandes
  d'un projet qui n'existe plus sont oubliées.
- **Avec Trade Board** (Kurki ; `## OptionalDeps: TradeBoard`), quand son API hôte a la version attendue
  (`tradeBoard.hostApiVersion == 1`), « Annoncer » ne publie plus lui-même : il ouvre son dialogue de demande, rempli
  avec le premier objet et sa quantité (`OpenRequestDialog("item", id, n)`, le joueur y choisit guilde ou Commerce), et
  ajoute les autres objets à son tableau (`AddRequest`, guilde par défaut). Quand la commande part en contrat, est
  remplacée ou que son projet est supprimé, Handshake retire de son tableau les demandes qu'il y a mises
  (`HasOwnRequest`, `RemoveOwnRequest`). Seules ces fonctions de son API hôte sont appelées, jamais `Integrate` (un seul
  hôte possible : Profession Master) ni son intérieur. Sans lui, ou avec une autre version, l'annonce de Handshake.

## API publique

Un seul global, `Handshake`, pour Composants. Seul ce qui suit est promis ; l'intérieur (contrats, échange, réseau) reste
privé. `p` = un projet de Composants ; `i` = le rang d'une commande dans le projet (1 = tout le projet, ou dans une
Réponse la Réponse elle-même).

```lua
local H = Handshake
H.Commandes(p)          -- les commandes du projet : { { part, bloc, player, tip, lines, apports, etat, fige, ecart, ecartPrix,
                        --   alertePrix, incomplet, recommander, reponse, vide }, … } ; l'état est lu dans le contrat
H.Commande(p, i)        -- l'une d'elles
H.Commander(p, bloc)    -- « Commander » un bloc (Composants.Arbre(p).blocDe[métier]) : rend le rang de sa commande
H.Artisan(p, nom, i)    -- l'artisan de la commande i (« Prénom Nom »)
H.Offre(p, cuivre, i)   -- son offre (dans une Réponse, mon prix)
H.Preparer(p, i)        -- « Préparer la demande » (ou « Contre-proposer » dans une Réponse) : le contrat préparé s'ouvre dans Contrats
H.Agir(p, i)            -- « Nouvelle version » (contrat préparé ouvert dans Contrats, rend nil) ou « Commander de nouveau » (rend le rang)
H.EnClair(p, i)         -- la demande en texte lisible, chuchotée à l'artisan
H.Annoncer(p, i)        -- « Annoncer dans le Commerce » : l'Annonce « WTB [lien] xN, … » de la commande i, un clic = un message
                        --   (limite par période, hors d'une ville refusée, écho vérifié) ; refusée, la raison est dite. Rend true, ou nil
H.Importer()            -- importer une liste reçue
H.Apports(p)            -- { [itemID] = true } : les cases que j'apporte dans les commandes du projet, ou nil
H.Apporter(p, id, oui)  -- « j'apporte » (oui) ou « je le reprends » (nil)
H.EstReponse(p)         -- ce projet est-il la Réponse à une demande reçue ?
```

## Développement

Lien symbolique de ce dossier dans `Interface/AddOns/` du jeu, `/reload` suffit. Vérifier, depuis le dossier des add-ons :
`luajit Handshake/check.lua` (charge le socle et Composants voisins ; « sans Composants » en le retirant), puis
`tools/sim.sh test Handshake` et `tools/sim.sh erreurs` dans l'atelier, avec et sans Composants dans les racines.
