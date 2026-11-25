# Handshake — artisanat et commandes entre joueurs

Un joueur décrit ce qu'il veut faire fabriquer, estime ce que ça coûte, et passe un contrat protégé avec un artisan. Détail de la conception : `CONCEPTION.md`.

Les projets, l'arbre, les cases, les blocs et les choix de case appartiennent à l'add-on Composants (nom provisoire) : glossaire dans `../Composants/CONTEXT.md`.

## Language

### Commandes

**Commander** (verbe):
Demander à un seul artisan une part d'un projet (un bloc, ou le projet entier) : ça crée tout de suite un contrat préparé, rattaché à ce bloc, où l'on règle l'artisan, l'offre et les apports avant de l'envoyer. Il n'y a pas d'objet « commande » entre le projet et le contrat (25/11/2026). Une liste faite à la main, sans arbre, est un projet ordinaire commandé en entier. Supprimer le projet efface ses contrats préparés, jamais un contrat parti.
_Avoid_: commande (le nom), order (à l'écrit), sous-commande

**Emplacements** (dans Composants):
Les deux endroits où Composants laisse Handshake dessiner, quand les deux sont là : le bloc commandé dans l'arbre du projet (le contrat, ses boutons pour commander, négocier, abandonner) et une ligne par contrat dans les Besoins (« Contrat n°12 · à recevoir »). Handshake y définit l'interface et les gestes ; Composants n'en sait rien.

**Demande**:
Le contrat préparé tel qu'il part vers l'artisan : ce que je veux, mes apports, mon offre ; sa version 1, dont l'état dit ensuite où en est la part commandée. (Ne pas confondre avec la demande d'un type de données, au sens de l'atelier.)
_Avoid_: requête

**Réponse**:
Le projet tenu d'un artisan, né d'une demande reçue (« Répondre », dans la fenêtre des contrats de Handshake) et ouvert en Préparer : Handshake en tient les lignes (ce que le demandeur veut) ; l'artisan y change ses apports, ses choix de case et son prix, puis contre-propose. Lancer y attend la signature ; elle est Finie quand le contrat est clos (livré par l'échange vérifié), pas quand l'arbre est plein. L'artisan peut à son tour en commander des blocs à d'autres.
_Avoid_: reply (à l'écrit)

### Le prix

**Apport**:
Une case de la part commandée que le demandeur fournit lui-même, en entier ; c'est elle que couvre la caution. N'existe que dans un contrat : un projet seul ne connaît pas d'apport. Côté demandeur, un apport est un Besoin comme un autre (il faut l'avoir sur soi pour le donner).
_Avoid_: composants fournis, mats

**Part de l'artisan**:
Tout ce qui n'est pas apporté ; l'artisan la fabrique ou l'achète comme il veut.

**Offre**:
Le prix proposé pour la part de l'artisan et son travail.
_Avoid_: pourboire, tip

### Le chat public

**Annonce**:
Une ligne publiée ou lue dans le chat public (canal Commerce, cris) : la mienne, « WTB [lien] xN, … », publiée d'un clic
depuis un contrat préparé ; ou celle d'un autre, lue parce qu'elle demande ce que je sais fabriquer ou un métier que j'ai (la fenêtre « Annonces lues »). Elle
n'engage à rien : seul le contrat engage.
_Avoid_: offre (c'est le prix), publicité

## Ambiguïtés relevées

- Une commande de projet et le projet étaient presque la même chose. Tranché le 25/11/2026 : l'objet « commande » disparaît ; « commander » crée un contrat (voir `../Composants/CONTEXT.md`, Ambiguïtés).

- « Brouillon » désignait aussi un contrat préparé mais pas envoyé. Tranché le 20/11/2026 : le mot va au Brouillon des projets ; un tel contrat est **préparé**.
