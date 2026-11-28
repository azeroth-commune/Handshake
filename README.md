# Handshake (bêta)

Add-on WoW Forever, catégorie Métiers : commandes et contrats d'artisanat entre joueurs. Glossaire : `CONTEXT.md` ;
conception : `CONCEPTION.md` ; modèle de menace : `SECURITE.md` ; pour le joueur : `LISEZ-MOI.txt`.

- **Requiert** le socle Azeroth Commune (`## Dependencies: AzerothCommune`).
- **Seul**, Handshake sert par la commande à la main (`/handshake liste`, ou `/handshake`), les contrats (`/contrat`) et
  le panneau qui vérifie chaque échange. Dans le chat public (`Annonce.lua`) : « Annoncer » une commande dans le canal
  Commerce, et les **Annonces lues** (`/handshake annonces`, onglet de la commande à la main) : les demandes du Commerce et
  des cris pour ce que mes persos savent fabriquer (recettes connues relevées par le socle) ou pour un métier qu'ils ont
  (« LF BS », sans lien), lues en direct et dans l'historique du chat (à l'ouverture de la fenêtre et à l'entrée en jeu),
  gardées par perso pour un /reload, chacune quelques minutes ; `/handshake essai lue <texte>`
  lit un texte comme une ligne du Commerce et dit pourquoi elle est écartée.
- **Avec Composants** (chargé ou non, aucun des deux ne requiert l'autre ; `## OptionalDeps: TradeBoard, Composants`),
  Handshake se branche sur l'**emplacement du bloc** de Composants (`Composants.Emplacements`, `Emplacement.lua`) :
  Composants ne connaît ni Handshake ni les contrats. « Commander » sur un bloc (ou « Commander tout » sur la ligne du
  projet) crée tout de suite un contrat préparé, numéroté, rattaché au projet et au bloc
  (`HandshakeDB.commandes[p.id]`) ; le bloc se réduit à une case « Contrat n°12 · artisan · état » ; son panneau (une
  fenêtre de Handshake) règle l'artisan, l'offre et les apports ; « Vérifier et envoyer… » prépare le brouillon de la v1
  et l'ouvre sur sa fiche dans Contrats (caution, perte maximale, objets sans prix, échéance, objets liés, nom et GUID),
  d'où « Envoyer la proposition » le fait partir (par Handshake s'il l'a, sinon en clair, #71) : rien ne part du
  panneau ; « Plus » : voir dans Contrats, annoncer dans le Commerce, abandonner. Hors Préparer (`p.phase`), le panneau est en lecture seule. Refusé,
  retiré, échu ou abandonné, le bloc revient, sans ses apports. Dans les **Besoins** (l'emplacement des Besoins, même
  fournisseur, phase Réunir) : une ligne par contrat vivant, « Contrat n°12 · à recevoir », verte « reçu » une fois livré,
  son état et « Abandonner » (la lecture seule hors Préparer ne vaut que pour l'arbre) ; `clos` = tous les contrats
  vivants du projet livrés (Réunir → Fabriquer et Fini l'attendent) ; mes apports vivants (`ns.elaguerApports`) et les
  termes de mes contrats partis sont `aDonner` (des lignes des Besoins), ceux du demandeur dans une Réponse restent
  `apports` (hors de mon arbre). Abandonner selon l'état (`ns.abandonner`) : préparé → effacé ; envoyé → retiré
  (`ns.ctWithdraw`, comme « Retirer ») ; à signer → refusé (`ns.ctRefuse`, comme « Refuser ») ; signé → lâché par le
  projet seulement (rien n'est envoyé, le contrat reste signé dans Contrats jusqu'à l'échéance, SECURITE.md P2/P5 n° 20) ;
  livré → rien. Une liste reçue (« Importer une liste reçue », menu
  « Plus » de la fenêtre de Handshake) devient un projet commandé en entier. Une demande reçue s'ouvre en **Réponse**, un projet tenu
  de Composants (`Composants.Tenir`) ouvert en Préparer (« Répondre » dans Contrats), son panneau sur la ligne du projet
  (mon prix, ses apports, « Contre-proposer… » en Préparer : un brouillon de la nouvelle version, relu sur sa fiche dans
  Contrats, qui part de là ; toute contre-proposition aussi, SECURITE.md P8). Lancer y attend la signature (champ
  `lancer` de l'emplacement : « Lancer (contrat à signer) ») ; elle est Finie quand son contrat est clos (champ `fini`),
  et son propre contrat ne compte pas dans `clos` (ses sous-traitances seules).
  Handshake lit l'arbre par `Composants.Arbre` et suit le signal `Composants.QuandChange` : supprimer un projet efface
  ses contrats préparés (et leurs brouillons dans Contrats), jamais un contrat parti ; à l'entrée en jeu, ceux d'un
  projet qui n'existe plus sont oubliés.
- **Avec Trade Board** (Kurki ; `## OptionalDeps: TradeBoard`), quand son API hôte a la version attendue
  (`tradeBoard.hostApiVersion == 1`), « Annoncer » ne publie plus lui-même : il ouvre son dialogue de demande, rempli
  avec le premier objet et sa quantité (`OpenRequestDialog("item", id, n)`, le joueur y choisit guilde ou Commerce), et
  ajoute les autres objets à son tableau (`AddRequest`, guilde par défaut). Son API ne prend pas de prix (et le sien est
  à l'unité) : l'offre de la commande est rappelée dans le chat, à saisir dans son dialogue. Quand la commande part en contrat, est
  remplacée ou que son projet est supprimé, Handshake retire de son tableau les demandes qu'il y a mises
  (`HasOwnRequest`, `RemoveOwnRequest`). Seules ces fonctions de son API hôte sont appelées, jamais `Integrate` (un seul
  hôte possible : Profession Master) ni son intérieur. Sans lui, ou avec une autre version, l'annonce de Handshake.

## API publique

Aucune (Composants#26) : le global `Handshake` reste, vide, et dit seulement que Handshake est chargé. C'est Handshake
qui se branche sur Composants (`Composants.Emplacements`), jamais l'inverse.

## Développement

Lien symbolique de ce dossier dans `Interface/AddOns/` du jeu, `/reload` suffit. Vérifier, depuis le dossier des add-ons :
`luajit Handshake/check.lua` (charge le socle et Composants voisins ; « sans Composants » en le retirant), puis
`tools/sim.sh test Handshake` et `tools/sim.sh erreurs` dans l'atelier, avec et sans Composants dans les racines.
