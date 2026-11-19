# Handshake : conception de la demande (18/11/2026)

## Vocabulaire

- **Demande** : ce que je veux (objets × quantités), ce que j'apporte, et éventuellement ce que j'offre de payer.
  C'est la version 1 d'un contrat, proposée par le **demandeur** (le client).
- **Apport** : un composant que le demandeur fournit lui-même (il l'a, il le fabrique, il l'achète : son affaire).
  Par case entière de l'arbre (pas de quantité partielle pour l'instant).
- **Part de l'artisan** : tout ce qui n'est pas apporté. L'artisan la fabrique ou l'achète comme il veut ; sa marge
  sur ses recettes intermédiaires ne regarde pas le contrat.
- **Offre** : le prix proposé pour la part de l'artisan + son travail. Le demandeur peut en mettre une (l'arbre lui
  en suggère une) ou laisser l'artisan chiffrer.
- **Réponse** : l'artisan accepte, refuse, ou contre-propose (prix, et aussi la liste des apports : « apporte plutôt
  du minerai que des barres »). Chaque changement = une nouvelle version, différentiel affiché.
- **Accord** : une version acceptée des deux côtés.
  - avec apports → **contrat** : caution = prix de marché des apports, puis les deux ventes protégées ;
  - sans apport → **vente simple** : un contrat sans caution ; le panneau vérifie l'objet et le prix convenus.

## Correspondance avec le contrat existant (rien à réinventer)

| Demande | Contrat |
|---|---|
| ce que je veux | `o` (objets livrés), unité = ce que le client paie par objet |
| ce que j'apporte | `m` (composants fournis), unité = caution par unité (prix de marché) |
| offre | totaux de `o` moins caution |
| réponse de l'artisan | contre-proposition (nouvelle version) |
| pas d'apport | `m` vide : étape unique, pas de caution |

## Deux modes, une fenêtre

**Je demande** (je suis le client)
1. Je tape les objets que je veux.
2. L'arbre me montre ce qu'il faut. Chaque case a trois choix : décomposer, acheter, **je le fournis**. Une case
   « je le fournis » sort, avec tout ce qu'il y a sous elle, de la part de l'artisan. Mon stock m'aide à choisir
   (« tu en as déjà 4 »), mais n'est pas déduit en silence.
3. En bas : mes apports, la part de l'artisan et mon estimation de son coût → une offre suggérée.
4. J'envoie la demande (protocole contrat, ou texte lisible pour quelqu'un sans l'addon).

**Je réponds** (je suis l'artisan)
1. Ce que le client veut et ce qu'il apporte : en lecture seule.
2. Mon arbre ne porte que sur ma part, avec MES recettes, MES stocks, MES prix ; mes « + / – » sont mes choix.
3. Mon coût → mon prix ; j'accepte, je refuse, ou je contre-propose (prix, apports).

## Règles

- La caution porte sur les apports seulement, à leur prix de marché ; chacun voit sa propre estimation (P8).
- Les stocks de l'artisan ne réduisent jamais ce que le client doit apporter.
- Tout le reste vient de `SECURITE.md` (chaque échange équilibré, registre, identité, etc.).

## Étapes

1. Modèle « demande » : apports par case, offre facultative, envoi en contrat v1 ou en texte lisible
   (« Commande : 1x[Armure] · j'apporte 4x[Cuir lourd] · offre 5 po »).
2. Mode **je demande** : « je le fournis » dans l'arbre, part de l'artisan, offre suggérée.
3. Mode **je réponds** : arbre de ma part seulement, mon coût, contre-proposition (prix et apports).
   FAIT le 18/11/2026 : « Répondre dans l'arbre » (contrat à signer, côté artisan) ouvre la demande comme une commande
   liée (`order.reply`) : lignes figées, apports en Ctrl+clic, « Mon prix », en-tête « ma part · mon prix · travail »,
   « Contre-proposer » = nouvelle version (cautions déjà au contrat gardées, apport ajouté au prix de mon scan).
4. Accord : contrat avec caution, ou vente simple vérifiée. Retirer le bouton « Contrat » actuel (remplacé par l'envoi
   de la demande) et l'ancienne case « il fournit les composants » (remplacée par les apports).
5. Plus tard : « un objet à la fois » (moins d'avance pour l'artisan), coopération à plusieurs.

## Questions ouvertes (à traiter plus tard)

- Que se passe-t-il si on répond (signe, refuse, contre-propose) pendant que l'autre est hors ligne ?
  (posée le 18/11/2026)

## Idées notées le 19/11/2026 (nuit) — pas encore faites

Le POC « décomposer → blocs par métier → commander bloc par bloc » est validé : la faisabilité est là. À venir :

1. **Projets, vue liste.** On arrive sur « mes projets » : une liste, avec l'état et une barre d'avancement par projet.
   Un projet ouvre la page actuelle (l'arbre en blocs par métier, par étapes) ; ses sous-commandes (« Commander » sur
   un bloc) y sont rattachées et suivies depuis cette même page — pas une page par commande.
   - L'état d'une sous-commande se lit dans son contrat / son registre (pas de double saisie) ; un bloc livré devient
     du stock / un apport pour l'étape suivante.
   - Les « étages » comptent moins que la dépendance entre blocs (d'abord ça, puis ça) ; à garder pour le cas « je fais
     tout moi-même ».
2. **Deux usages en parallèle.**
   - Rapide : Ctrl+clic droit sur un objet / une recette → « comment je le fais » tout de suite ; puis éventuellement
     « enregistrer en projet » (nouveau ou existant).
   - Projet : directement dans l'interface, on tape les objets, etc.
   - Au clic sur un objet : choisir de l'ajouter au projet en cours ou à un nouveau.
3. **Gestion des recettes : CRITIQUE.** Qui connaît quoi, qui a le métier, quel plan acheter pour pouvoir faire tel
   objet. Les données fiables (recettes Forever) viendront plus tard ; pour l'instant réserve Classic.
4. **Commandes proposées : un « hôtel des ventes » sans argent, juste des commandes.**
   - On poste sa commande (un bloc, une demande) ; elle est diffusée.
   - Côté artisan, l'addon intercepte les annonces reçues, filtre celles qu'il peut faire (métier, recettes) et les met
     dans « commandes à dispo » ; plus tard : « si tu achètes ce plan, tu pourras la faire ».
   - L'artisan fait une proposition à l'auteur ; s'il est en ligne, on enchaîne (demande → contrat, déjà en place).
   - C'est l'essentiel qui manque aux autres addons (savoir qui peut faire quoi, sans le cosmétique).
   - **À la signature d'un contrat, on diffuse que la commande n'est plus disponible** : chez tous ceux qui l'avaient
     reçue ou avaient fait une proposition, elle se retire et leurs propositions s'annulent, avec un simple message
     « autre contrat signé ». Ça synchronise même quand des gens étaient hors ligne au moment de la signature (ils le
     reçoivent à la prochaine diffusion / connexion). Risque d'une fausse clôture : du sabotage seulement (retirer
     l'annonce d'un autre), aucun gain d'argent → priorité basse. Parade quasi gratuite : n'accepter une clôture que de
     l'auteur de l'annonce lui-même (le jeu donne l'expéditeur de chaque message).
5. **Question ouverte : où stocker / comment diffuser** sans serveur ni base de données (interdits aux addons) : annonces
   en cours diffusées (canal ou messages d'addon) et récupérées à la connexion ; ce qui reste dans les SavedVariables de
   chacun ; durée de vie d'une annonce ; quelqu'un hors ligne.
