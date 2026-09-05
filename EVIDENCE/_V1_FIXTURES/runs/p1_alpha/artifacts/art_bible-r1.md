---
styles: [flat-vector-2d, clean-web-ui]
mood_keywords: [satisfaisant, tactile, lisible, chaleureux, ludique, epure, croissance, positif]
---

# ART BIBLE — p1_alpha (s2.5-artbible, RUN p1_alpha-20260830-run1)

> Statut : v0.1 — PROPOSITION (Round 1 de la boucle de complétion mutuelle ART↔GM).
> Sources héritées : `worldscan.json` (s2), `story_bible.json` (s2.6), et le contrat produit
> `s0-contrat.txt` (PROPOSITION quotant `structure_imposee.yaml`, structure RATIFIÉE Pierre
> 2026-08-30 ; note d'honnêteté : `charter.yaml` n'a jamais été matérialisé comme fichier —
> `state.json → s0-contrat.yaml_check.written = false` — la STRUCTURE reste néanmoins normative
> via `structure_imposee.yaml`, seule sa sérialisation en charter a manqué).
> `claim_verdict: NO_CLAIM_ALLOWED`.

## 1. IDENTITÉ VISUELLE

p1_alpha est un **incremental/clicker web**. Son identité visuelle décidée ici sert **une seule
promesse mécanique** : rendre la **croissance d'un nombre** immédiatement satisfaisante, lisible
et positive, sans jamais faire lire une punition ni un échec (le genre n'en a pas, et la victoire
imposée à S5 est un aboutissement heureux, pas un « game over »).

- **Style décidé** : `flat-vector-2d` pour les objets de jeu (cible cliquable, générateurs, effets,
  fond) et `clean-web-ui` pour la couche interface (compteur, panneau d'achat, badges
  d'améliorations, écran de victoire). Aplats vectoriels, formes arrondies et tactiles, légère
  profondeur douce (ombres portées discrètes), zéro texture photographique.
- **Palette** : base neutre chaude et sobre (fond peu saturé qui ne concurrence jamais les
  chiffres) ; **un accent unique de « croissance »** (teinte vive réservée aux gains, au compteur
  qui monte et aux états achetables) ; un gris désaturé franc pour l'état grisé/non-achetable ;
  une teinte de célébration réservée à l'écran de victoire (S5). Le contraste entre l'accent de
  gain et le fond est le porteur principal de lisibilité.
- **Mood** : satisfaisant, tactile, épuré, chaleureux, positif. Chaque clic « répond »
  (déformation courte de la cible + éclat), chaque seuil franchi « s'ouvre » visiblement.
- **Point de vue** : interface frontale de face (front-facing UI), jamais une vue top-down ni
  latérale — c'est une page-tableau de bord, pas une scène spatiale.
- **Thème / sujet concret** : le contrat produit **délègue le thème à la chaîne** et aucune étape
  amont ne l'a fixé (Story Bible quasi vide, 2/8 sections ancrées). Je décide donc, comme défaut
  de travail, un **motif abstrait de croissance/accumulation** (jetons, orbes, dispositifs
  géométriques neutres) plutôt qu'une fiction concrète — ce défaut est explicitement soumis au
  Game Master pour appropriation ou remplacement (cf. bloc `design_questions`, section
  `## visual_language`). Les références de style restent advisory (aucune n'est vérifiée
  mécaniquement).

## 2. RATIONALE

Le style découle des sources héritées, pas d'un goût :

- Le World Scan mesure que la rétention du genre tient au **feedback constant et visible des
  chiffres qui montent** et à l'**asymétrie d'accès** aux achats (`worldscan:games[0].retention_answer`).
  Conséquence artistique **structurée** (cf. `## 3. BESOINS VISUELS` et `## ui_readability`) : le
  compteur R et l'effet de gain au clic sont les deux entités visuelles les plus prioritaires, et
  l'accent de couleur leur est réservé — d'où `vr_resource_icon` et `vr_click_feedback` en
  `required:true`.
- Le genre n'a **ni état de victoire ni état de défaite** par convention
  (`worldscan:games[0].objectives[0].has_win_state` = false, `has_defeat_state` = false), or la
  structure imposée AJOUTE une victoire à S5 (`s0-contrat:§A.3`, `structure_imposee:dimensioning.fin`).
  Cette tension héritée est tranchée visuellement : l'écran de victoire (`vr_victory_screen`) est un
  **aboutissement positif** et ne réemploie aucun code visuel de défaite (il n'en existe aucun).
- La Story Bible établit qu'il n'y a **aucun personnage ni faction** ancrable
  (`story_bible:characters` NOT_GROUNDED, `story_bible:factions` NOT_GROUNDED). Il n'y a donc pas
  d'avatar à habiller : les seules entités « à états » sont les **objets interactifs** (cible,
  générateurs, boutons d'achat), traités en `## character_states`.
- La structure ratifiée fixe l'inventaire exact des entités de jeu : **1 cible cliquable, 4
  générateurs G1–G4, 6 améliorations, 5 seuils S1–S5, 1 fin observable** (`s0-contrat:§B.charter`).
  Chaque entité structurelle reçoit ci-dessous un besoin visuel et au moins une `asset_request` de
  même `entity_role` — la couverture est démontrée par la donnée structurée, jamais affirmée en
  prose (cette section ne prétend couvrir que ce que la section 3 et `asset_requests.json` portent
  réellement).

## 3. BESOINS VISUELS

Chaque entité visuelle distincte de p1_alpha, dérivée de la structure imposée
(`s0-contrat:§B.charter`) et des conventions héritées. `required:true` pour toute entité citée par
une source héritée ou centrale à la boucle / à la condition de victoire ; en cas de doute,
`required:true` (coût d'une requête en trop = nul).

```json
{
  "visual_requirements": [
    {
      "id": "vr_click_target",
      "entity_role": "item",
      "required": true,
      "description": "L'objet central que le joueur clique pour gagner R (gain_clic). Piece maitresse de l'ecran, unique, dimensionnee pour etre la plus grande cible de clic et la plus lisible. Doit visiblement 'repondre' au clic (D2)."
    },
    {
      "id": "vr_resource_icon",
      "entity_role": "icon",
      "required": true,
      "description": "Le symbole de la ressource R, affiche en permanence a cote du compteur de solde et du total cumule, et sur chaque cout d'achat. Entite la plus repetee de l'interface (source unique reutilisee partout)."
    },
    {
      "id": "vr_generator_g1",
      "entity_role": "item",
      "required": true,
      "description": "Generateur automatique de palier 1 (G1, prod 0.1 R/s), premier producteur passif, achetable des le chargement (D1). Silhouette la plus modeste de la gamme."
    },
    {
      "id": "vr_generator_g2",
      "entity_role": "item",
      "required": true,
      "description": "Generateur automatique de palier 2 (G2, prod 1 R/s), revele au franchissement du seuil S1 (D5). Silhouette plus imposante que G1."
    },
    {
      "id": "vr_generator_g3",
      "entity_role": "item",
      "required": true,
      "description": "Generateur automatique de palier 3 (G3, prod 8 R/s), revele au seuil S2. Escalade de silhouette poursuivie."
    },
    {
      "id": "vr_generator_g4",
      "entity_role": "item",
      "required": true,
      "description": "Generateur automatique de palier 4 (G4, prod 47 R/s), revele au seuil S3. Sommet de la gamme, silhouette la plus imposante."
    },
    {
      "id": "vr_upgrade_badges",
      "entity_role": "icon",
      "required": true,
      "description": "Famille d'icones pour les 6 ameliorations achetables (2 sur le clic x2 puis x4, 4 en x2 production par generateur). Systeme visuel commun (cadre/badge) lisible en liste ; la distinction thematique amelioration par amelioration depend du theme delegue (question ouverte au GM)."
    },
    {
      "id": "vr_victory_screen",
      "entity_role": "ui",
      "required": true,
      "description": "Panneau/ecran de victoire observable affiche a S5 (total cumule >= 1 000 000 R), result == VICTORY (S11). Etat de fin POSITIF et visible, sans aucun code visuel de defaite (le jeu n'a pas d'echec)."
    },
    {
      "id": "vr_buy_panel",
      "entity_role": "ui",
      "required": true,
      "description": "Cadre du panneau d'achat/boutique (HUD) listant generateurs et ameliorations avec cout, nombre possede, et etat achetable / grise-refuse (D3, D4). Charpente de lisibilite de toute la couche marchande."
    },
    {
      "id": "vr_click_feedback",
      "entity_role": "effect",
      "required": true,
      "description": "Retour visuel immediat du clic sur la cible (eclat/particules + gain '+N' flottant). Porte la satisfaction de croissance qui est le coeur de la retention du genre."
    },
    {
      "id": "vr_threshold_unlock_fx",
      "entity_role": "effect",
      "required": true,
      "description": "Effet de franchissement d'un seuil cumule S1..S5 marquant un deblocage (nouveau tier ou ameliorations qui apparaissent, D5). Transformation perceptible du moment ou une nouvelle possibilite s'ouvre."
    },
    {
      "id": "vr_background",
      "entity_role": "environment",
      "required": true,
      "description": "Fond de la page unique. Support neutre et peu sature qui met en valeur la cible centrale et le HUD sans concurrencer la lisibilite des nombres (contrainte de lisibilite prioritaire)."
    }
  ]
}
```

## heritage_worldscan

Ce que cette Art Bible reprend du World Scan (matière observée sur des jeux de référence, jamais
copiée — le manifeste se déclare `worldscan:advisory` = true) :

- **La rétention naît du feedback visible des chiffres** et de l'asymétrie d'accès aux achats —
  `worldscan:games[0].retention_answer` (« Feedback constant (chiffres croissant exponentiellement,
  visibles à l'écran) + asymétrie d'accès (toujours un achat prochain mais pas immédiat) »). ⇒ le
  compteur et l'effet de gain sont prioritaires (`## ui_readability`).
- **La boucle démarre par un clic manuel puis bascule sur de la production automatique visible** —
  `worldscan:games[0].loops.minute_1` (« Manuel click acquire auto-clicker ; feedback immédiat :
  CpS visible »). ⇒ la cible cliquable et la première production doivent être immédiatement
  lisibles à l'écran.
- **Les déblocages se font par seuils d'accumulation, pas par le temps** —
  `worldscan:games[0].loops.minute_10` (« déblocages upgrades tous les 5/25/50 achats »). ⇒
  l'apparition d'un nouveau tier/amélioration est un événement visuel (`vr_threshold_unlock_fx`).
- **Le genre n'a ni victoire ni défaite** — `worldscan:games[0].objectives[0].has_win_state` = false
  et `worldscan:games[0].objectives[0].has_defeat_state` = false. ⇒ aucun langage visuel de
  punition ; la victoire imposée par la structure est traitée comme une exception positive.
- **Les noms/entités des jeux observés (Grandmas, Cursors, héros, Managers) restent hors-champ** —
  le worldscan est advisory et ne prescrit pas l'univers de p1_alpha ; aucune de ces entités n'est
  reprise ici.

## heritage_story_bible

Ce que cette Art Bible reprend de la Story Bible (qui est volontairement quasi vide — 2/8 sections
GROUNDED, faute de charter matérialisé) :

- **Aucun monde diégétique ni personnage n'est ancré** — `story_bible:characters` (NOT_GROUNDED :
  « le genre observé est d'ailleurs sans avatar narratif ») et `story_bible:factions`
  (NOT_GROUNDED). ⇒ pas d'avatar ni de faction à dessiner ; les entités « à états » sont des
  objets d'interface, cf. `## character_states`.
- **La cohérence interdit une clôture par victoire finale de type narratif et toute menace/défaite**
  — `story_bible:coherence_rules` (« Toute couche narrative éventuelle doit rester sans clôture par
  victoire finale » ; « La cohérence du monde ne peut reposer sur une menace existentielle ni une
  condition de perte »). ⇒ l'écran de victoire S5 est un jalon heureux, pas une fin dramatique ;
  aucun visuel anxiogène.
- **Un reset/prestige, s'il existait, ne doit pas se lire comme une punition** —
  `story_bible:coherence_rules` (« reset reframed comme feature pas punition »). p1_alpha n'a pas de
  prestige dans la structure imposée, mais la règle oriente le ton général : non punitif.
- **Le substrat narratif est explicitement à fournir en aval** — `story_bible:context` (« le socle
  narrateur reste donc à fournir en aval »). ⇒ le thème concret est ouvert (question au GM).

## visual_language

(DÉCIDÉ — aucune adresse héritée exigée.)

- **Grammaire de formes** : aplats vectoriels, coins arrondis, épaisseurs de trait constantes,
  profondeur suggérée par des ombres douces et non par du relief réaliste. Rien de bruité, rien de
  photographique.
- **Hiérarchie chromatique** (règle, pas décoration) : (1) l'accent de « croissance » est
  **réservé** aux nombres qui augmentent, au gain de clic et aux boutons achetables ; (2) le fond et
  les cadres restent désaturés ; (3) le gris franc marque l'indisponibilité ; (4) une teinte de
  célébration n'apparaît qu'à la victoire. Un même élément ne porte jamais deux rôles chromatiques.
- **Échelle des silhouettes** : G1 < G2 < G3 < G4 en présence visuelle (taille/détail/densité), pour
  que la progression de puissance soit lisible sans lire un chiffre.
- **Thème de travail (défaut, soumis au GM)** : motif **abstrait de croissance/accumulation** —
  jetons/orbes de ressource, générateurs comme dispositifs géométriques neutres, améliorations comme
  badges. Ce défaut existe uniquement parce que le thème est délégué à la chaîne et non encore fixé
  (`s0-contrat:provenance.non_impose_par_pierre`) ; le Game Master peut l'adopter tel quel ou fournir
  un thème concret, auquel cas le sujet des assets change (mais pas les règles de style/lisibilité
  ci-dessus). Voir `design_questions` (q_art_001).

## affordance_rules

(DÉCIDÉ.) Chaque règle sert un comportement observable imposé (D1–D5, `s0-contrat:§S1/D`) :

- **Cliquable = évident** : la cible centrale se distingue de tout le reste par sa taille, son accent
  et sa réaction au survol/enfoncement ; rien d'autre à l'écran n'imite son affordance de clic.
- **Achetable vs refusé** : un achat possible porte l'accent et réagit ; un achat impossible est
  **grisé de façon franche et non ambiguë** et ne bouge pas au clic (D4 : « bouton visiblement
  grisé/refusé et R ne bouge pas »). Le grisé ≠ le caché.
- **Verrouillé = caché ou grisé lisiblement** : un tier/amélioration non débloqué est masqué ou
  nettement estompé jusqu'à son seuil (D1) ; son apparition est un événement (`vr_threshold_unlock_fx`,
  D5).
- **Coût toujours accompagné de l'icône R** : aucun montant n'est affiché sans le symbole de la
  ressource, pour rendre le coût lisible d'un coup d'œil.
- **Possession visible** : le nombre d'unités possédées de chaque générateur est montré (D3).

## character_states

(DÉCIDÉ.) p1_alpha **n'a aucun personnage** (`story_bible:characters` NOT_GROUNDED). Cette section
définit donc les **états visuels des objets interactifs**, seuls porteurs d'états dans ce jeu :

- **Cible cliquable** : `repos` (idle, respiration lente optionnelle) → `enfoncée` (déformation
  courte au clic) → `juice` (éclat + « +N » émis). Retour à `repos` immédiat.
- **Générateur (par tier G1–G4)** : `verrouillé` (caché/estompé avant son seuil) → `achetable`
  (accent, réactif) → `non-achetable` (grisé franc, R insuffisant) → `possédé` (compteur d'unités
  visible ; indice discret de production active).
- **Amélioration (×6)** : `verrouillée` → `achetable` → `non-achetable (grisée)` → `achetée`
  (badge marqué acquis, non recliquable).
- **Bouton d'achat générique** : `actif/achetable` vs `grisé/refusé` (D4), deux états visuellement
  non confondables.
- **Jeu global** : `en cours` → `VICTORY` (bascule l'écran de victoire, S11) — pas d'état de
  défaite.

## ui_readability

(DÉCIDÉ.) La lisibilité est la fonction n°1 de l'interface, dérivée de la rétention héritée
(`worldscan:games[0].retention_answer`) :

- **Le compteur R et le total cumulé sont toujours visibles** (D1, `s0-contrat:§S1`) et constituent
  l'élément typographique le plus grand et le plus contrasté de l'écran ; le total cumulé
  (base des 5 seuils) est distinct du solde et clairement étiqueté.
- **Chiffres d'abord** : chiffres tabulaires (largeur fixe) pour éviter les sauts quand les nombres
  grandissent ; grands nombres abrégés lisiblement (ex. 1.2M) sans jamais masquer la progression.
- **Le gain de clic est perçu** : l'incrément « +N » apparaît là où l'œil regarde (près de la cible)
  et disparaît vite, sans encombrer.
- **États non-achetables distinguables** : le grisé garde un contraste de texte suffisant pour rester
  lisible (désactivé ≠ illisible).
- **Victoire visible sans ambiguïté** (S11) : le panneau de fin est franc, centré, et n'obscurcit pas
  au point de faire croire à une erreur/panne.
- **Cible d'accessibilité** : contraste texte/fond visé conforme WCAG AA sur les nombres et les
  libellés de coût ; l'information n'est jamais portée par la seule couleur (forme/texte redondants
  pour l'état grisé).

## world_constraints

(DÉCIDÉ, borné par la structure et la plateforme.)

- **Support** : page web unique, **HTML + JS, rendu canvas**, 2D uniquement
  (`s0-contrat:plateforme_cible`). Front-facing UI, jamais de scène 3D ni de vue top-down.
- **Assets locaux, zéro réseau pour la logique** (`s0-contrat:plateforme_cible`) — aucune
  dépendance CDN ; aucun octet réseau généré par cette étape (ingestion nouvelle = gate Pierre).
- **Déterminisme visuel** : aucune animation ne doit dépendre d'un aléa qui affecterait l'économie
  (RNG interdit dans la logique, `s0-contrat:§S3`) ; les effets décoratifs peuvent varier mais ne
  changent jamais l'état de jeu.
- **Pas de défaite à représenter** ; la victoire (S5) est le seul état terminal, et il est positif.
- **Budget de lisibilité** : le fond et les décors ne doivent jamais réduire le contraste des
  nombres (contrainte prioritaire, cf. `## ui_readability`).

## asset_rules

(DÉCIDÉ.) Règles de production pour toute demande d'asset de ce jeu :

- **Format/runtime** : tous les assets sont `format: 2D`, `runtime: html` (cf. `asset_requests.json`).
- **Styles autorisés** : `flat-vector-2d` (objets de jeu, effets, fond) et `clean-web-ui` (couche
  interface) — et seulement ceux-ci ; tout autre tag de style est hors identité et doit repasser par
  cette bible.
- **Licences** : sous-ensemble par défaut du studio (CC0-1.0 / MIT / CC-BY-4.0 / CC-BY-3.0) ; aucune
  contrainte plus stricte déclarée (`license_allowed: null` = défaut assumé).
- **Icône de ressource = source unique** : le même symbole R est réutilisé partout où R apparaît
  (compteur, coûts, gains) — jamais deux variantes concurrentes.
- **Escalade des générateurs** : G1→G4 partagent une famille visuelle mais escaladent en présence
  (silhouette), pour lire la puissance sans lire un chiffre.
- **Badges d'améliorations = cadre commun** : les 6 améliorations partagent un gabarit de badge ; leur
  contenu thématique reste ouvert tant que le thème n'est pas fixé par le GM (défaut abstrait).
- **Résolution mécanique ≠ satisfecit esthétique** : qu'une requête résolve `OK` contre le catalogue
  ne prouve jamais que l'asset « est du bon style » au sens visuel (`style_tag_match` compare des
  tags, pas des pixels) — la conformité esthétique reste un fog HumanGate, jamais un claim
  (cf. `docs/forge/ASSET_CONTRACT_V0.md`).
- **Aucune écriture dans `knowledge_base/catalog.json`** (lecture seule) ; les `asset_requests` sont
  un artefact par-run.

---

Round 1 de la boucle ART↔GM : l'Art Bible ci-dessus est complète et auto-suffisante (identité,
règles, besoins et couverture structurée). La seule décision qui dépasse l'autorité de l'étape Art
— le **thème concret** (délégué à la chaîne, non encore fixé) — est portée au Game Master dans le
bloc `design_questions` final. Le style, les règles d'affordance/lisibilité et l'inventaire des
entités, eux, sont tranchés ici et n'attendent pas de réponse.
