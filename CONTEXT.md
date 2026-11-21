# Handshake — artisanat et commandes entre joueurs

Un joueur décrit ce qu'il veut faire fabriquer, estime ce que ça coûte, et passe un contrat protégé avec un artisan. Détail de la conception : `CONCEPTION.md`.

## Language

### Projets d'artisanat (partent dans un add-on solo à nommer, grill du 20/11/2026)

**Projet**:
Ce que je veux faire fabriquer (des objets × quantités), avec son arbre, ses blocs et mes choix de case ; une seule page pour le suivre, et ses commandes quand Handshake est là.
_Avoid_: liste, suivi

**Brouillon**:
Le projet de passage, unique et toujours là, où atterrit tout Ctrl+clic droit sur un objet ; on le vide ou on en retire des lignes, et « + » en fait un vrai projet. Il n'est pas dans la liste des projets.
_Avoid_: projet temporaire, scratch

**Besoins**:
Les objets à réunir pour les projets qu'on y a mis (Brouillon compris), additionnés et toujours à jour de leurs choix de case, avec ce qu'on en a déjà (sacs, banque, autres personnages) ; une petite fenêtre à part pour suivre ce qu'il reste à acheter ou à récolter.
_Avoid_: liste de courses, shopping

### Commandes (Handshake)

**Commande**:
Une part d'un projet (le projet entier ou un bloc) adressée à un seul artisan ; tant qu'elle n'est pas partie, elle suit le projet, et elle se fige quand elle devient une demande.
_Avoid_: order (à l'écrit), sous-commande

**Demande**:
Une commande telle qu'elle part vers l'artisan : ce que je veux, mes apports, mon offre ; la version 1 d'un contrat, dont l'état dit ensuite où en est la commande. (Ne pas confondre avec la demande d'un type de données, au sens de l'atelier.)
_Avoid_: requête

**Réponse**:
Le projet d'un artisan né d'une demande reçue : ce que le demandeur veut y est figé ; l'artisan y change ses apports, ses choix de case et son prix, puis contre-propose. Il peut à son tour en commander des blocs à d'autres.
_Avoid_: reply (à l'écrit)

### L'arbre

**Case**:
Un objet dans l'arbre d'un projet, une seule fois même s'il sert à plusieurs endroits : ce qu'il en faut, ce qu'on a en stock, ce qu'on fabrique, achète ou apporte.
_Avoid_: nœud, node

**Bloc**:
Les cases fabriquées d'un même métier dans un projet, avec qui peut les faire ; un bloc se commande d'un coup à un artisan. Un bloc peut dépendre d'un autre (d'abord les barres, puis l'armure).
_Avoid_: groupe, bande

**Choix de case**:
Ce qu'on décide pour une case de l'arbre : la décomposer, l'acheter toute faite, ou l'apporter ; sans choix, le calcul des prix décide. Un choix de case appartient à un projet, jamais à tout le joueur.
_Avoid_: force, choix forcé

### Le prix

**Apport**:
Une case de l'arbre que le demandeur fournit lui-même, en entier ; c'est elle que couvre la caution.
_Avoid_: composants fournis, mats

**Part de l'artisan**:
Tout ce qui n'est pas apporté ; l'artisan la fabrique ou l'achète comme il veut.

**Offre**:
Le prix proposé pour la part de l'artisan et son travail.
_Avoid_: pourboire, tip

## Ambiguïtés relevées

- « Brouillon » désignait aussi un contrat préparé mais pas envoyé. Tranché le 20/11/2026 : le mot va au Brouillon des projets ; un tel contrat est **préparé**.
