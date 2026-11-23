# Contrats : modèle de menace

But non négociable : **un joueur qui utilise l'addon officiel, non modifié, et qui suit le verdict du panneau, ne
peut pas se faire avoir.** L'attaquant a le code source, son propre addon modifié (ou aucun addon), peut envoyer
n'importe quel message, courrier ou contenu d'échange, et peut manipuler socialement.

Deux analyses indépendantes, fusionnées ici (18/11/2026), avant d'écrire la moindre ligne des contrats.

## Ce sur quoi la sécurité repose (et rien d'autre)

1. **Ce que le serveur garantit** : le nom de l'expéditeur d'un message ou d'un courrier (« Prénom Nom » sur Forever,
   sans GUID), le GUID d'un perso qu'on voit (cible, survol, groupe) ou qui chuchote, le partenaire d'échange (nom et
   GUID), le contenu réel de la fenêtre d'échange, les pièces jointes et le montant d'un contre-remboursement,
   tes sacs et ton or.
2. **Ta copie locale du contrat**, telle que tu l'as vue et acceptée.
3. **Tes clics**, sur un affichage clair.

Seuls la fenêtre d'échange (simultanée) et le contre-remboursement (payer pour retirer) *imposent* quelque chose.
Contrat, empreinte, versions et messages ne font que *coordonner*. Ce que l'autre addon affirme (une étape « livrée »,
un contrat « signé », un nom d'objet, une version d'addon) n'est jamais une preuve.

## Principes

- **P1 — Chaque échange est équilibré, et le cumul aussi.** Le contrat signé fixe une valeur par unité de chaque
  composant (leur somme = la caution) et par objet fabriqué (caution rendue + prix). Après chaque échange ou
  contre-remboursement, ce que tu as reçu en cumul vaut au moins ce que tu as donné, en valeurs du contrat ; l'or se
  fractionne au prorata, avec une règle d'arrondi fixe (solde exact au dernier lot). Jamais de crédit, jamais de
  mélange entre contrats.
- **P2 — Le registre prime sur les étapes.** Dû = termes du contrat − transferts que *ton* addon a constatés (fin
  d'échange confirmée + mouvement réel de ton or et de tes sacs, courrier réellement pris). Un message de l'autre, ni
  le GUID qu'il y déclare, ne change jamais l'état ; il s'affiche « Bob dit : … ».
- **P3 — Ce qu'on affiche = ce qu'on stocke = ce qu'on vérifie = ce qu'on hache.** Le message reçu est lu dans une
  structure provisoire, validé champ par champ, puis reconstruit localement sous forme canonique ; seule cette forme
  est affichée, signée, vérifiée. La copie locale n'est jamais remplacée par des données réseau.
- **P4 — Aucun texte libre ne voyage.** Le contrat ne contient que des identifiants, des nombres bornés et des noms
  fournis par le serveur. Noms, icônes et liens d'objets sont reconstruits localement depuis l'ID.
- **P5 — Un contrat accepté est figé.** Le changer = un nouveau contrat.
- **P6 — Dans le doute, non.** L'état par défaut est NON VÉRIFIÉ : erreur, objet absent du cache, API modifiée par
  un autre addon → pas de « conforme ».
- **P7 — Aucune action de valeur sans clic humain réarmé.** Pas de validation par Entrée, pas de fenêtre surgissante
  pour accepter, bouton réarmé après un court délai suivant tout changement. L'addon ne clique jamais « Accepter ».
- **P8 — Chacun évalue seul.** Ton addon recalcule la caution et la valeur des objets depuis *ton* scan, et te montre
  ta perte maximale avant que tu signes.

## Attaques et contre-mesures

« Reste » : ce qui subsiste après la contre-mesure (— = supprimé).

### A. Négociation et signature

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 1 | **Faux nom d'objet** : lien « [Claymore en mithril] » pointant vers un autre ID. | P4 : seul l'ID compte ; nom, icône, qualité et ID affichés depuis le client local. | — |
| 2 | **Usurpation de l'auteur** : `P|3|<GUID de Belegard>|…` envoyé par Mallory. | L'origine de l'ID doit être le GUID déclaré par l'expéditeur, qui doit concorder avec le serveur (n° 26) ; on affiche toujours le nom authentifié, jamais déduit du GUID. | — |
| 3 | **Rôles incohérents ou inversés** : la victime se retrouve à verser la caution en se croyant cliente. | Rejet si {client, artisan} ≠ {moi, l'expéditeur} ; affichage écrit depuis mon rôle : « TU donnes … / IL donne … ». | — |
| 4 | **Contre-proposition piégée** : « juste la date », mais 36 → 3 minerais, ou caution / fournisseur / paiement changés. | Différentiel champ par champ avec la version précédente, champs changés surlignés, alerte forte sur caution, prix, rôles, fournisseur. Jamais d'acceptation automatique. | Inattention |
| 5 | **Version qui change pendant la lecture** : v4 arrive, le clic accepte autre chose que ce qui était lu. | Le bouton Accepter est lié à l'empreinte *affichée* ; une nouvelle version ferme la vue, montre le différentiel, réarme le bouton après 1–2 s. | — |
| 6 | **Rejeu, versions concurrentes** : vieil « accepté », deux v4 différentes. | v(n+1) retire les versions ≤ n ; un « accepté » ne vaut que pour la dernière version et vient de l'autre signataire ; chaque proposition porte l'empreinte de sa version parente (conflit → tout annulé, on repropose) ; dédoublonnage (ID, version, type). | — |
| 7 | **Empreinte truquée ou collision**. | Sans effet sur les valeurs (P3) : l'empreinte ne sert qu'à constater qu'on a signé la même chose. Empreinte d'au moins 64 bits quand même, recalculée sur la forme canonique locale. | — |
| 8 | **ID réutilisé** (contrat clos renvoyé, même horodatage). | Contrats indexés par (GUID du signataire d'origine, ID) ; un ID connu ne peut que progresser en version avant acceptation, et seulement de la part du nom authentifié de sa première version. | Un GUID jamais appris revendiqué par un autre nom occupe cet ID : la proposition s'affiche sous le vrai nom, rien ne passe à l'échange (n° 26) |
| 9 | **Repli « sans addon » forcé** : il ne répond pas, puis conteste ou chuchote un texte « accepté » modifié. | La copie locale reste la référence ; jamais de contrat importé depuis une réponse en discussion ; le panneau vérifie pareil avec ou sans addon en face. | — |
| 10 | **Texte lisible ≠ données** : le chuchotement dit 5 po, le message addon 55 po. | On n'approuve que la vue de l'addon ; un texte qui l'accompagne est comparé et l'écart signalé. | Lecteur humain du texte |
| 11 | **Termes irréalisables** : objet ou composant lié (impossible à échanger), montant au-delà du plafond d'or, échéance absurde, quantités énormes. | Vérification à la signature : type de liaison, bornes, échéance en heure serveur (`GetServerTime`) affichée en relatif (« dans 2 j 5 h »). | — |
| 12 | **Liste de besoins gonflée** : l'artisan demande plus de composants que la recette n'en consomme et garde le surplus. | Le client recalcule lui-même les besoins depuis les recettes connues (relevées par Azeroth Commune) et signale l'écart ; sinon « quantités non vérifiables ». Option : ligne « surplus à rendre » à l'étape 2. | Recette inconnue du client |
| 13 | **Termes injustes** : caution de 1 po pour 20 po de composants, puis disparition. | P8 : « caution X, ton estimation Y, écart Z % » en rouge au-delà d'un seuil ; idem côté artisan si la caution dépasse la valeur ; objets sans prix connu signalés. | Marché, scan ancien |

### B. Messages et lecture

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 14 | **Nombres et clés piégés** : clé en double (`p=40000|p=1`), clé inconnue, `0x10`, `1e9`, `inf`, `nan`, négatifs, décimales. | Grammaire stricte : chaque valeur `^%d+$`, longueur et plage bornées ; clé dupliquée ou inconnue → message rejeté en entier. | — |
| 15 | **Listes énormes**. | ≤ 30 lignes, quantité ≤ 1000, ≤ 3 propositions en attente par expéditeur. | — |
| 16 | **Morceaux abusés** : (1/9999), morceaux jamais complétés, entrelacés. | **Fait dans les commandes** : ≤ 10 morceaux, un « 1/n » repart de zéro, un tampon par expéditeur, oublié après 30 s. Contrats : chaque morceau porte (ID, version, i/n), le tout vérifié par l'empreinte. | — |
| 17 | **Délimiteurs et noms** : `|`, `,`, `=` glissés dans une valeur ; noms accentués, avec royaume. | Caractères autorisés par champ ; aucun nom ne voyage dans un contrat : les signataires sont des GUID, grammaire stricte (`Player-<n°>-<8 hex>`) ; un nom, une adresse ou un GUID malformé à la place → rejeté. | — |
| 18 | **Message qui fait planter l'addon** (état à moitié écrit, gestionnaire mort). | Lecture sous `pcall` dans une structure provisoire, validation, puis écriture en une fois ; jamais de `loadstring`, jamais de motif Lua bâti avec un texte reçu. | — |
| 19 | **Tiers** qui envoie accepté/refus/annulation/étape, ou passage par guilde ou groupe. | Contrats : chuchotement uniquement, et seulement de l'autre signataire. | — |
| 20 | **Fausse étape ou annulation tardive** pour avancer ou effacer un état. | P2 ; une annulation après un transfert ne touche pas au registre : elle affiche ce qu'il reste à échanger pour solder. | — |
| 21 | **Inondation** de propositions pour noyer une vraie offre ou provoquer un clic réflexe. | Débit limité par expéditeur, file plutôt que fenêtres empilées, option « amis / guilde / groupe seulement », liste d'ignorés. | Bruit |
| 22 | **Rétrogradation de protocole** (`CT0`, version inconnue). | Seules les versions connues sont lues, sans repli ; la version entre dans l'empreinte. | — |

### C. Affichage

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 23 | **Injection d'affichage** : `|c`, `|T`, `|H`, `|n` pour fabriquer un faux « ✓ CONFORME » ou un lien piégé. | P4 ; tout texte reçu affiché est échappé (`|` → `||`), sans caractères de contrôle, tronqué ; la zone de verdict n'affiche jamais de texte venu d'ailleurs. | — |
| 24 | **Faux verdict dans la discussion** : « [Contrat] CONFORME, Bob a payé ». | L'addon n'écrit jamais de verdict dans la discussion ; seul le panneau fait foi, et le dit. | Crédulité |
| 25 | **Clic piégé par le timing** : une fenêtre surgit pendant que tu tapes, Entrée accepte. | P7 : pas de fenêtre surgissante pour accepter un contrat, pas de bouton par défaut, pas d'Entrée. | — |
| 26 | **Homonymes** : Bélegard / Belegard, même nom sur un autre serveur, perso supprimé puis recréé. | Les signataires sont des **GUID** ; « Prénom Nom » (celui du serveur) et GUID toujours affichés ; alerte si un nom ne diffère d'un contact que par les accents. **Chaque message porte le GUID de son expéditeur**, qui n'est pas une preuve : un autre GUID appris du serveur pour ce nom (chuchotement, cible, survol), ou ce GUID appris sous un autre nom → message rejeté ; jamais appris, il est accepté pour négocier et **vérifié au premier échange** : le GUID du partenaire, donné par le serveur, doit être celui du contrat, sinon NON CONFORME et rien ne passe. Réputation indexée par GUID. | Avant le 1ᵉʳ échange (aucune valeur n'a encore bougé) |
| 27 | **Confusions** : po/pa/pc, Minerai / Barre de mithril, 19 au lieu de 20. | Le ✓ ne dépend que de l'ID et du compte exact ; l'or est affiché en entier, avec l'écart chiffré. | — |
| 28 | **Verdict trompeur ou périmé** : il ne regarde que l'autre côté, il n'est pas recalculé, un objet absent du cache passe. | Verdict dans **les deux sens** (tu ne donnes pas plus que dû, tu reçois au moins le dû) ; recalcul à chaque événement d'échange + contrôle périodique ; bandeau « CHANGEMENT, revérifie » 2 s ; objet illisible → INCONNU, jamais CONFORME. | — |
| 29 | **Panneau masqué** par une autre fenêtre, verdict seulement en couleur. | Ancré à la fenêtre d'échange, au-dessus ; verdict en texte + icône. | — |

### D. Fenêtre d'échange

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 30 | **7ᵉ case** (« ne sera pas échangé »). | Seules les cases 1 à 6 comptent ; objet en case 7 signalé. | — |
| 31 | **Mauvais partenaire ou mauvais contrat** (deux contrats : faire valider l'étape du moins cher). | Panneau ouvert si le GUID ou le nom du partenaire est celui d'un contrat, CONFORME seulement si son GUID est celui du contrat (et son nom, tant que le GUID n'est pas confirmé) ; un échange = un seul (contrat, lot), choisi et affiché en gros ; pas de contrats combinés. | — |
| 32 | **Échange au dernier moment** après une vérification correcte. | Le jeu annule les deux acceptations ; P7 (réarmement) ; **« Accepter » grisé tant que c'est NON CONFORME**, dérogation explicite et chiffrée (n° 60). À vérifier en jeu : griser ce bouton ne doit pas bloquer le jeu. | — |
| 33 | **Bon ID, objet différent** : suffixe aléatoire, emballage cadeau (l'ID devient celui du papier), durabilité entamée. | Objets fabriqués : chaîne d'objet comparée hors identifiant unique ; emballage → NON CONFORME ; durabilité lue dans l'infobulle. | Durabilité (réduit) |
| 34 | **Je donne trop** : « Remplir ma part » prend mon arme enchantée ou une pile entière, or dans la mauvaise unité. | Remplissage : seulement des exemplaires non liés, non enchantés, jamais l'équipement porté ; division de pile vers une case libre, ou échec propre ; or plafonné au dû ; déclenché uniquement par ton clic ; verdict aussi sur ton côté (n° 28). | — |
| 35 | **Étapes dans le désordre** : rembourser une caution jamais reçue, rejouer l'étape 1. | P2 : dû calculé sur le registre, pas sur une étape annoncée. | — |
| 36 | **Échange hors contrat** avec ton partenaire (« donne d'abord, je paie après »). | Un échange avec un partenaire actif qui ne correspond à aucun dû affiche « hors contrat, non protégé ». | Passer outre |
| 37 | **Fausse fin d'échange** : un échange annulé enregistré comme fait, ou un échange réussi oublié (déconnexion). | Instantané quand les deux ont accepté ; enregistré seulement après le message de fin **et** le mouvement réel de ton or et de tes sacs ; sinon « en attente, à réconcilier ». | n° 49 |
| 38 | **Faux verdict local** : un autre addon remplace les fonctions de lecture de l'échange. | Fonctions du jeu capturées au chargement ; à chaque verdict, `issecurevariable` sur les fonctions clés ; si l'une est modifiée → « API modifiée par un autre addon », NON VÉRIFIÉ. | n° 52 |

### E. Courrier (contre-remboursement)

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 39 | **Contre-remboursement non conforme** : quantité, objet voisin, montant gonflé. | Avant de payer, pièces jointes et montant comparés au dû du registre ; verdict dans la confirmation du jeu et sur la ligne du courrier. | — |
| 40 | **Expéditeur alt ou homonyme**. | Expéditeur (fourni par le serveur) exactement égal au nom du signataire, celui lié à son GUID, alerte accents. | — |
| 41 | **Courrier gratuit + contre-remboursement** combinés (le bon dans le gratuit, la camelote dans le payant), ou scindés. | Chaque contre-remboursement est équilibré à lui seul ; on n'additionne jamais plusieurs courriers pour valider un paiement. | — |
| 42 | **« Envoie sans contre-remboursement, je te paie après ».** | L'addon ne prépare que des contre-remboursements, envoyés par celui qui fournit les objets ; le reste est signalé non protégé. | Passer outre |
| 43 | **Courrier ouvert par un autre addon** (« tout ouvrir »). | Documenté ; alerte si un addon de courrier connu est chargé. | Réduit |
| 44 | **Retour, expiration, délai d'une heure** : états incohérents, retard imputé à tort. | Un courrier envoyé n'est pas un transfert ; seul un retrait constaté est enregistré ; pas de jugement automatique du retard. | — |

### F. Lots (plusieurs échanges)

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 45 | **Lot déséquilibré** : caution entière au lot 1, moitié des composants, disparition. | P1 (cumul). | — |
| 46 | **« C'est le lot 2/2 »** annoncé par l'autre. | Le reste dû vient du registre local, jamais de l'autre. | — |
| 47 | **Arrondis** qui s'accumulent. | Règle d'arrondi canonique, identique des deux côtés, solde exact au dernier lot. | — |
| 48 | **Livraison partielle** des objets les moins chers, paiement total exigé. | Paiement au prorata de la valeur livrée (P1). | — |

### G. État et stockage

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 49 | **Plantage avant l'écriture** (les SavedVariables ne s'écrivent qu'au /reload) puis « refais l'étape ». | Après chaque étape, bouton « Sauvegarder » (/reload) ; une étape sans trace est « non prouvée », jamais « à refaire » d'office ; ce que l'autre dit sert d'indice à confirmer à la main ; conseil `/chatlog`. | Plantage dans la fenêtre non sauvegardée |
| 50 | **Perte de données** (dossier WTF effacé, autre PC). | Export / import d'un contrat en chaîne ; alerte si la dernière sauvegarde est plus vieille que le dernier transfert. | Réduit |
| 51 | **« Synchronisons, prends ma version »**. | Jamais de fusion automatique : différentiel affiché, tout changement = nouvelle version signée. | — |
| 52 | **Autre addon chez la victime** qui modifie l'état ou dessine un faux panneau. | État en variables locales, rien en global ; n° 38. | Hors de portée |
| 53 | **Mauvais personnage** (contrats enregistrés pour tout le compte). | Le signataire est le personnage, par son GUID ; comparé au GUID du perso connecté. | — |
| 54 | **Retard** : réclamations après coup, livraison après clôture. | Règle écrite dans le contrat : échéance dépassée → chacun garde ce qu'il détient (le client la caution, l'artisan les composants), contrat soldé, étape 2 refusée ensuite. | — |

### H. Économie

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 55 | **Manipulation de l'HV avant ton scan** : une annonce à 1 pc fait baisser la caution, ou rachat des annonces bon marché pour la faire monter. | Prix robuste (paliers pondérés par le volume, valeurs aberrantes écartées), volume minimal, historique sur plusieurs jours, plancher au prix de revente au marchand, écart avec l'historique signalé. | Réduit |
| 56 | **Scan périmé**, faible volume, aucune donnée. | Alerte au-delà de 24–48 h ou à faible volume ; sans donnée, valeur à saisir à la main, signalée. | Réduit |
| 57 | **Exposition entre les deux étapes** (artisan qui disparaît : composants − caution ; client qui disparaît : caution − revente de l'objet + main-d'œuvre). | Les deux pertes maximales affichées, chiffrées, à la signature ; caution < 100 % seulement par choix explicite ; acompte optionnel. | Inhérent au modèle |
| 58 | **Variation du marché** pendant le délai. | Caution figée à la signature, risque affiché, échéances courtes conseillées. | Réduit |
| 59 | **Réputation** : alts jetables, petits contrats honorés puis un gros. | Inconnu affiché « inconnu », pas « neutre » ; réputation locale, par GUID, jamais importée ; elle sert seulement à accepter une caution partielle, jamais à sauter une vérification. | Réduit |

### I. Manipulation sociale et environnement

| # | Attaque | Contre-mesure | Reste |
|---|---|---|---|
| 60 | **« Ton addon bugue, accepte quand même. »** | Dérogation possible mais avec une confirmation qui énonce la perte (« tu reçois 30/36 barres, −X po »), inscrite au registre. | Réduit |
| 61 | **« Pas de contrat cette fois », « à crédit ».** | Avertissement hors contrat (n° 36), documentation. | Réduit |
| 62 | **Pression du temps.** | Aucun compte à rebours imposé par l'addon ; différentiel obligatoire avant d'accepter une nouvelle version. | Réduit |
| 63 | **Intermédiaire** : « je récupère pour Belegard », « envoie à mon alt ». | Pas de cession de contrat : partenaire d'échange et destinataire = exactement le signataire (même GUID), sinon NON CONFORME. | — |
| 64 | **Fausse réputation**, menace de signalement « preuves de l'addon » à l'appui. | Les journaux sont présentés comme des notes personnelles, sans valeur de preuve ; ceux de l'autre sont tout aussi falsifiables. | Réduit |
| 65 | **Version piégée** de l'addon (faux site, « mise à jour » envoyée en chuchotement). | Une seule source, versions publiées avec sommes de contrôle ; l'addon ne demande jamais de mise à jour par la discussion. | Hors de portée |
| 66 | **Addons d'acceptation automatique** (échange, courrier). | Détectés et signalés. | Réduit |
| 67 | **Version d'addon annoncée** par l'autre. | Affichage informatif, jamais un signe de confiance. | — |
| 68 | **Langue, cache, horloge.** | ID partout, attente du chargement des objets, heure serveur pour toutes les dates. | — |

## Ce qui reste, honnêtement

- L'écart entre la caution et la vraie valeur, et l'exposition entre les deux étapes : inhérents au modèle, mais
  chiffrés et affichés avant de signer.
- Un plantage entre un échange et la sauvegarde.
- Une machine compromise (version piégée de l'addon, autre addon malveillant).
- Un joueur qui passe outre un NON CONFORME.

Les deux derniers sortent du périmètre « addon officiel, non modifié, et joueur qui suit le verdict ».

## Ce que ça change à la conception

1. Le contrat porte **une valeur par unité** de chaque composant et de chaque objet fabriqué, pas seulement des totaux.
2. Un **registre** des transferts constatés remplace les « étapes » comme source de vérité.
3. Le partenaire est identifié par son **GUID** : déclaré dans chaque message, concordant avec ce que le serveur a donné,
   vérifié au premier échange.
4. **Grammaire stricte et bornée**, chuchotement uniquement, empreinte de 64 bits ou plus, version de protocole dans l'empreinte.
5. Acceptation **sans fenêtre surgissante**, bouton lié à l'empreinte affichée et réarmé après tout changement.
6. **Besoins recalculés par le client** depuis les recettes, **caution recalculée** par chacun, **pertes maximales** affichées.
7. **Règle d'échéance** écrite dans le contrat.
8. Panneau : verdict dans les deux sens, cases 1–6, objets illisibles = INCONNU, « Accepter » grisé si non conforme (à vérifier en jeu), dérogation chiffrée.
9. Bouton **Sauvegarder** (/reload) après chaque transfert.

## État d'avancement (18/11/2026, contrat + panneau d'échange)

Fait et testé hors jeu (`luajit BeAGoodPal_Commandes/check.lua`, deux joueurs simulés) :
lecture stricte et bornée (n° 2, 3, 11, 14, 15, 17, 22), morceaux bornés (16), signature liée à l'empreinte affichée
(5), versions chaînées et contrat signé figé (6, 8, P5), tiers ignorés (19), 3 propositions en attente au plus (12 —
inondation), valeurs unitaires et équilibre cumulé (P1, 45, 46, 48), registre (P2, 35), cases 1–6 et objets par ID
(30, 33), partenaire par GUID, vérifié au premier échange (26, 31), échéance (54), verdict dans les deux sens (28), besoins
vérifiés contre les recettes (12), estimation et perte maximale de chaque côté (13, 57), différentiel (4), nom proche
d'un autre partenaire (26), objets liés quand ramassés (11).

Écrit mais à vérifier en jeu : panneau d'échange, « Remplir ma part », griser « Accepter » (32), dérogation chiffrée
(60), inscription confirmée par l'or et les sacs (37), fonctions du jeu capturées et `issecurevariable` (38),
« Sauvegarder » (49).

Pas encore fait : courrier contre-remboursement (39–44), réputation (59), option « amis / guilde seulement » (21),
export / import d'un contrat (50), prix robuste sur plusieurs jours et plancher marchand (55), alerte d'addons
d'acceptation automatique (66).

## Ajout : noms de famille sur Forever (n° 69)

Les persos de Forever ont un nom de famille, sans tiret ni espace (le jeu refuse le tiret : « Marteaudefer », relevé
du 20/11/2026, LibCommune#19). `UnitName`, `UnitFullName` et `GetUnitName(unité, true)` rendent ce nom de famille là où
le retail rend le royaume. Depuis le build 71037 (21/11/2026), le jeu ne donne plus le royaume du tout (`GetRealmName()`
rend ""), l'expéditeur d'un message d'add-on est « Prénom Nom », et un chuchotement au prénom seul échoue (« Aucun joueur
nommé 'Belegard' ») : il part vers « Prénom Nom » (`lib.Destinataire`). L'adresse « Prénom-Royaume » a disparu : le nom
sert à afficher et à chuchoter, l'identité est le GUID (protocole 3 ci-dessous). Si deux joueurs partagent un prénom, un
homonyme ne gagne rien : chaque échange est équilibré (P1), et le GUID fait foi.

## Ajout : signature par GUID (protocole 3, Handshake#29)

Les signataires d'un contrat sont des GUID (`Player-<n° de serveur>-<8 hex>`), plus des noms : unique, fourni par le
serveur, le GUID survit à un renommage. Chaque message de contrat porte en 3e champ le GUID de son expéditeur. Ce GUID
déclaré n'est pas une preuve (« Ce sur quoi la sécurité repose ») ; il devient sûr à trois conditions :

- **il concorde** avec ce que le serveur a déjà donné : si un GUID est déjà appris pour ce nom (le GUID que le jeu joint
  à un chuchotement, celui d'une cible, d'un survol, d'un membre du groupe), un GUID déclaré différent fait rejeter le
  message ; de même si le GUID déclaré est déjà appris sous un autre nom ;
- **il est vérifié avant que rien ne bouge** : au premier échange, le GUID du partenaire, donné par le serveur, doit être
  égal au GUID du contrat, sinon NON CONFORME et rien ne passe (n° 26 : « aucune valeur n'a encore bougé ») ;
- **l'affichage reste celui du serveur** : le nom affiché est l'expéditeur authentifié, jamais déduit du GUID déclaré ;
  un contrat ne se poursuit que de la part de ce nom-là (n° 19).

Un GUID déclaré mais jamais appris est donc accepté pour négocier. Une demande n'est envoyée qu'à un artisan dont le
serveur a donné le GUID. `GetPlayerInfoByGUID` n'est plus lu : la forme de ses retours n'a pas été relevée sur Forever.
Un perso renommé reste le même (GUID identique) : une fois son GUID confirmé, l'échange est conforme et le changement de
nom signalé. Le protocole passe à « 3 » ; les messages « 2 » (adresses « Prénom-Royaume ») sont refusés, et les contrats
enregistrés sous l'ancien format sont purgés au chargement (perte de données acceptée).

## Ajout : Annonces dans le chat public (Handshake#51)

Une **Annonce** (« WTB [lien] xN, … » dans le canal Commerce) n'engage à rien : ni prix, ni artisan, ni objet promis. Seul
le contrat engage, et rien de ce qu'une annonce dit ne passe dans un contrat. Publier reste un clic du joueur à chaque fois
(jamais d'envoi automatique, ni de répétition) ; une limite par période empêche de répéter la même annonce, et le mode
essai comme le mode debug ne publient rien sur le réseau.

## Ajout : Demandes lues dans le chat public (Handshake#52)

Handshake lit le canal Commerce et les cris : du texte d'inconnus, sans aucune garantie, comme le sont les messages de
contrat (P2, P4). Ce qui en est montré :

- **est nettoyé avant tout affichage** (`ns.nettoyer`) : caractères de contrôle retirés ; un lien d'objet ou de recette
  reconnu est refait localement depuis son ID (le nom et la couleur sont ceux du client, un « [Épée gratuite] » posé sur
  un autre ID ne passe pas, n° 1) ; tout autre lien (`|Hurl:…`, `|Hplayer:…`…) est réduit à son texte ; codes de couleur
  (`|c…|r`), de texture (`|T…|t`), d'atlas (`|A…|a`) et tout autre `|` retirés ; le texte est coupé (160 octets hors
  liens, jamais au milieu d'un caractère) ; le nom de l'auteur, donné par le serveur, passe par le même nettoyage ;
- **ne déclenche jamais rien sans clic** : une demande lue ne fait qu'entrer dans une liste et écrire une ligne dans le
  chat ; « Répondre » (un clic) envoie un chuchotement fixe, écrit par Handshake, à l'auteur. Rien de lu ne devient une
  commande, un contrat ni un prix ;
- **est bornée** : seules les lignes de demande (« WTB », « Buy », « Search ») avec le lien d'un objet ou d'une recette
  qu'un de mes persos sait fabriquer ; une entrée par joueur et par objet, 30 au plus, oubliées après 15 min. Mes propres
  lignes ne sont pas lues. Un nom d'auteur que le nettoyage changerait est écarté (il sert tel quel à « Répondre »).
- **l'historique du chat** (les lignes déjà dans les fenêtres de chat, lues à l'ouverture de « Demandes lues » et une fois
  à l'entrée en jeu) est lui aussi du texte d'inconnus : les données que le client garde avec chaque ligne (l'évènement et
  ses arguments, auteur, GUID, lineID) passent par **le même lecteur**, avec le même nettoyage et les mêmes bornes ; une
  ligne sans ces données est sautée, jamais analysée depuis son texte affiché. Une ligne déjà listée (même lineID) n'est
  pas relue ; une ligne plus vieille que 15 min (d'après son horodatage) n'entre pas. Rien ne se fait sans clic.
- **gardée pour un /reload** : par perso dans `HandshakeDB.demandes`, seulement ce que le lecteur a déjà produit (texte
  nettoyé et coupé, IDs de l'objet, de la recette, nom du métier, lien refait ici, auteur, lieu, heure), jamais la ligne
  brute ; oubliée après 15 min comme en mémoire. Au chargement, seules les fraîches reviennent.
- **demandes par métier, sans lien** (« LF BS », « cherche forgeron ») : une ligne de demande (aussi « LF » seul,
  « cherche », « recherche » en tête ; LFW, LFG, LFM restent écartés) qui nomme en mot entier un métier qu'un de mes persos
  a. C'est toujours du texte d'inconnus : même nettoyage, même borne (une entrée par joueur et par métier), aucune bulle
  d'objet, et « Répondre » envoie le même genre de chuchotement fixe, sur un clic seulement ;
- **`/handshake essai demande <texte>`** ne fait que passer le texte au lecteur local, d'un faux auteur « Essai » : rien ne
  part sur le réseau (sauf un clic sur « Répondre », comme pour toute demande lue). Les essais d'avant restent listés
  (une entrée par objet ou métier) ; chaque essai écrit sa ligne de signal ou la raison du refus.
