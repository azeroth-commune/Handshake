# Handshake — artisanat et commandes entre joueurs

Un joueur décrit ce qu'il veut faire fabriquer, estime ce que ça coûte, et passe un contrat protégé avec un artisan. Détail de la conception : `CONCEPTION.md`.

Les projets, l'arbre, les cases, les blocs et les choix de case appartiennent à l'add-on Composants (nom provisoire) : glossaire dans `../Composants/CONTEXT.md`.

## Language

### Commandes

**Commande**:
Ce que je demande à un seul artisan : une part d'un projet (le projet entier ou un bloc), ou une liste faite à la main, sans arbre (ce que je veux, ce que j'apporte). Tant qu'elle n'est pas partie, une commande de projet suit le projet ; toute commande se fige quand elle devient une demande. Supprimer le projet efface ses commandes pas encore parties, jamais un contrat.
_Avoid_: order (à l'écrit), sous-commande

**Demande**:
Une commande telle qu'elle part vers l'artisan : ce que je veux, mes apports, mon offre ; la version 1 d'un contrat, dont l'état dit ensuite où en est la commande. (Ne pas confondre avec la demande d'un type de données, au sens de l'atelier.)
_Avoid_: requête

**Réponse**:
Le projet tenu d'un artisan, né d'une demande reçue : Handshake en tient les lignes (ce que le demandeur veut) ; l'artisan y change ses apports, ses choix de case et son prix, puis contre-propose. Il peut à son tour en commander des blocs à d'autres.
_Avoid_: reply (à l'écrit)

### Le prix

**Apport**:
Une case de la part commandée que le demandeur fournit lui-même, en entier ; c'est elle que couvre la caution. N'existe que dans une commande : un projet seul ne connaît pas d'apport.
_Avoid_: composants fournis, mats

**Part de l'artisan**:
Tout ce qui n'est pas apporté ; l'artisan la fabrique ou l'achète comme il veut.

**Offre**:
Le prix proposé pour la part de l'artisan et son travail.
_Avoid_: pourboire, tip

### Le chat public

**Annonce**:
Une ligne publiée ou lue dans le chat public (canal Commerce, cris) : la mienne, « WTB [lien] xN, … », publiée d'un clic
depuis une commande pas encore partie ; ou celle d'un autre, lue parce qu'elle demande ce que je sais fabriquer. Elle
n'engage à rien : seul le contrat engage.
_Avoid_: offre (c'est le prix), publicité

## Ambiguïtés relevées

- « Brouillon » désignait aussi un contrat préparé mais pas envoyé. Tranché le 20/11/2026 : le mot va au Brouillon des projets ; un tel contrat est **préparé**.
