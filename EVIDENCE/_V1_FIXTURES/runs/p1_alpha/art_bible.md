---
styles: [flat-vector-2d, clean-web-ui]
mood_keywords: [satisfaisant, tactile, lisible, chaleureux, ludique, epure, croissance, positif, lumineux, eclat]
---

# ART BIBLE — p1_alpha (s2.5-artbible, RUN p1_alpha-20260830-run1)

> Statut : v0.2 — Round 2 de la boucle de complétion mutuelle ART↔GM (les réponses du
> Game Master sont reçues, le thème est FIXÉ, les deux questions du GM sont traitées).
> Sources héritées : `worldscan.json` (s2), `story_bible.json` (s2.6), le contrat produit
> `s0-contrat.txt` (PROPOSITION quotant `structure_imposee.yaml`, structure RATIFIÉE Pierre
> 2026-08-30 ; note d'honnêteté conservée : `charter.yaml` n'a jamais été matérialisé comme
> fichier — `state.json → s0-contrat.yaml_check.written = false` — la STRUCTURE reste néanmoins
> normative via `structure_imposee.yaml`, seule sa sérialisation en charter a manqué), et
> `gm_worldscan.json` (s2.6-gm, Round 1 : thème décidé + questions ART).
> `claim_verdict: NO_CLAIM_ALLOWED`.

## 1. IDENTITÉ VISUELLE

p1_alpha est un **incremental/clicker web**. Son identité visuelle décidée ici sert **une seule
promesse mécanique** : rendre la **croissance d'un nombre** immédiatement satisfaisante, lisible
et positive, sans jamais faire lire une punition ni un échec (le genre n'en a pas, et la victoire
imposée à S5 est un aboutissement heureux, pas un « game over »).

- **Style décidé** : `flat-vector-2d` pour les objets de jeu (cible cliquable, générateurs, effets,
  fond) et `clean-web-ui` pour la couche interface (compteur, panneau d'achat, badges
  d'améliorations, jauges, écran de victoire). Aplats vectoriels, formes arrondies et tactiles,
  légère profondeur douce (ombres portées discrètes), zéro texture photographique.
- **Palette** : base neutre chaude et sobre (fond peu saturé qui ne concurrence jamais les
  chiffres) ; **un accent unique de « croissance »** — la teinte lumineuse de l'Éclat, réservée aux
  gains, au compteur qui monte, au débit et aux états achetables ; un gris désaturé franc pour
  l'état grisé/non-achetable ; une teinte de célébration réservée à l'écran de victoire (S5). Le
  contraste entre l'accent de gain et le fond est le porteur principal de lisibilité.
- **Mood** : satisfaisant, tactile, épuré, chaleureux, positif, lumineux. Chaque clic « répond »
  (déformation courte de la cible + éclat), chaque seuil franchi « s'ouvre » visiblement.
- **Point de vue** : interface frontale de face (front-facing UI), jamais une vue top-down ni
  latérale — c'est une page-tableau de bord, pas une scène spatiale.
- **Thème / sujet concret — FIXÉ par le Game Master (Round 1, réponse à q_art_001)** : le contrat
  produit **délègue le thème à la chaîne** (`s0-contrat:provenance.non_impose_par_pierre`) ; en
  Round 1 j'avais posé un défaut abstrait, explicitement soumis au GM. Le GM a tranché
  (`gm_worldscan:game_master.grey_blocks.gb_click_target` + `world_interpretation`) : le thème est
  la **CROISSANCE LUMINEUSE (« l'Éclat »)**. **R** = des motes/orbes de lumière (l'Éclat) ; la
  **cible cliquable** = une **Source lumineuse** centrale ; **G1..G4** = **quatre émetteurs de
  lumière** en escalade de silhouette (petit émetteur → grand foyer) ; les **6 améliorations** =
  des badges au gabarit commun (2 « main plus vive » pour le clic ×2/×4, 4 « ×2 prod » un halo par
  émetteur). Conformément à la décision du GM, **les règles de STYLE / affordance / lisibilité de
  cette bible restent INCHANGÉES** — seul le SUJET des assets est désormais concret. Les références
  de style restent advisory (aucune n'est vérifiée mécaniquement).

## 2. RATIONALE

Le style découle des sources héritées, pas d'un goût :

- Le World Scan mesure que la rétention du genre tient au **feedback constant et visible des
  chiffres qui montent** et à l'**asymétrie d'accès** aux achats (`worldscan:games[0].retention_answer`).
  Conséquence artistique **structurée** (cf. `## 3. BESOINS VISUELS` et `## ui_readability`) : le
  compteur R et l'effet de gain au clic sont les deux entités visuelles les plus prioritaires, et
  l'accent lumineux leur est réservé — d'où `vr_resource_icon` et `vr_click_feedback` en
  `required:true`.
- Le genre n'a **ni état de victoire ni état de défaite** par convention
  (`worldscan:games[0].objectives[0].has_win_state` = false, `has_defeat_state` = false), or la
  structure imposée AJOUTE une victoire à S5 (`s0-contrat:§A.3`, `structure_imposee:dimensioning.fin`).
  Cette tension héritée est tranchée visuellement : l'écran de victoire (`vr_victory_screen`) est un
  **aboutissement positif** et ne réemploie aucun code visuel de défaite (il n'en existe aucun).
- La Story Bible établit qu'il n'y a **aucun personnage ni faction** ancrable
  (`story_bible:characters` NOT_GROUNDED, `story_bible:factions` NOT_GROUNDED). Il n'y a donc pas
  d'avatar à habiller : les seules entités « à états » sont les **objets interactifs** (Source,
  émetteurs, boutons d'achat), traités en `## character_states`.
- La structure ratifiée fixe l'inventaire exact des entités de jeu : **1 cible cliquable, 4
  générateurs G1–G4, 6 améliorations, 5 seuils S1–S5, 1 fin observable** (`s0-contrat:§B.charter`).
  Le Round 2 AJOUTE quatre entités visuelles dérivées des **questions du Game Master** (perception
  de l'épargne et de la divergence de stratégie, cf. `gm_worldscan:game_master.loops.economy_loop`
  et `.skill_loop`) : chacune reçoit ci-dessous son besoin visuel et au moins une `asset_request` de
  même `entity_role` — la couverture est démontrée par la donnée structurée, jamais affirmée en
  prose (cette section ne prétend couvrir que ce que la section 3 et `asset_requests.json` portent
  réellement).

## 3. BESOINS VISUELS

Chaque entité visuelle distincte de p1_alpha, dérivée de la structure imposée
(`s0-contrat:§B.charter`), des conventions héritées, et — pour les quatre dernières — des questions
du Game Master traitées au Round 2. `required:true` pour toute entité citée par une source héritée
ou centrale à la boucle / à la condition de victoire ; en cas de doute, `required:true` (coût d'une
requête en trop = nul).

```json
{
  "visual_requirements": [
    {
      "id": "vr_click_target",
      "entity_role": "item",
      "required": true,
      "description": "La Source lumineuse centrale (theme Eclat, gm_worldscan:gb_click_target) que le joueur clique pour gagner R (gain_clic). Piece maitresse de l'ecran, unique, dimensionnee pour etre la plus grande cible de clic et la plus lisible. Doit visiblement 'repondre' au clic par un eclat de lumiere (D2)."
    },
    {
      "id": "vr_resource_icon",
      "entity_role": "icon",
      "required": true,
      "description": "Le symbole de la ressource R = une mote/orbe de lumiere (l'Eclat), affiche en permanence a cote du compteur de solde et du total cumule, et sur chaque cout d'achat. Entite la plus repetee de l'interface (source unique reutilisee partout)."
    },
    {
      "id": "vr_generator_g1",
      "entity_role": "item",
      "required": true,
      "description": "Emetteur de lumiere de palier 1 (G1, prod 0.1 R/s), premier producteur passif, achetable des le chargement (D1). Silhouette la plus modeste de la gamme (petit emetteur)."
    },
    {
      "id": "vr_generator_g2",
      "entity_role": "item",
      "required": true,
      "description": "Emetteur de lumiere de palier 2 (G2, prod 1 R/s), revele au franchissement du seuil S1 (D5). Silhouette plus imposante que G1."
    },
    {
      "id": "vr_generator_g3",
      "entity_role": "item",
      "required": true,
      "description": "Emetteur de lumiere de palier 3 (G3, prod 8 R/s), revele au seuil S2. Escalade de silhouette poursuivie."
    },
    {
      "id": "vr_generator_g4",
      "entity_role": "item",
      "required": true,
      "description": "Emetteur de lumiere de palier 4 (G4, prod 47 R/s), revele au seuil S3. Sommet de la gamme, silhouette la plus imposante (grand foyer)."
    },
    {
      "id": "vr_upgrade_badges",
      "entity_role": "icon",
      "required": true,
      "description": "Famille d'icones pour les 6 ameliorations achetables : 2 'main plus vive' (clic x2 puis x4) et 4 'halo x2 prod' (une par emetteur), theme Eclat (gm_worldscan:reponse q_art_001). Systeme visuel commun (cadre/badge) lisible en liste ; la distinction clic vs production et emetteur cible se lit au gabarit + pictogramme."
    },
    {
      "id": "vr_victory_screen",
      "entity_role": "ui",
      "required": true,
      "description": "Panneau/ecran de victoire observable affiche a S5 (total cumule >= 1 000 000 R), result == VICTORY (S11). Etat de fin POSITIF et lumineux (embrasement de l'Eclat), sans aucun code visuel de defaite (le jeu n'a pas d'echec)."
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
      "description": "Retour visuel immediat du clic sur la Source (eclat/particules de lumiere + gain '+N' flottant). Porte la satisfaction de croissance qui est le coeur de la retention du genre ; signature BURST distincte de la pulsation automatique (cf. vr_autoprod_pulse)."
    },
    {
      "id": "vr_threshold_unlock_fx",
      "entity_role": "effect",
      "required": true,
      "description": "Effet de franchissement d'un seuil cumule S1..S5 marquant un deblocage (nouveau emetteur ou ameliorations qui apparaissent, D5). Transformation perceptible du moment ou une nouvelle possibilite s'ouvre."
    },
    {
      "id": "vr_background",
      "entity_role": "environment",
      "required": true,
      "description": "Fond de la page unique. Support neutre et peu sature qui met en valeur la Source centrale et le HUD sans concurrencer la lisibilite des nombres (contrainte de lisibilite prioritaire)."
    },
    {
      "id": "vr_affordability_meter",
      "entity_role": "ui",
      "required": true,
      "description": "Jauge de progres-vers-abordable integree a CHAQUE bouton d'achat : le bouton se 'charge' de l'accent lumineux proportionnellement a R / cout tant que l'achat n'est pas finançable, puis bascule achetable a 100%. Rend l'EPARGNE perceptible comme un remplissage qui monte, sans imposer une lecture chiffree (reponse a gm q_gm_001 : arbitrage acheter-vs-epargner). Cf. ## saving_arbitrage_perception."
    },
    {
      "id": "vr_yield_preview",
      "entity_role": "ui",
      "required": true,
      "description": "Apercu compact du prochain palier attache a chaque element achetable/previsualise : un repere visuel comparatif (barre/pips) de ce que cet achat AJOUTE au debit R/s, place a cote de son cout, pour arbitrer 'une unite de plus' vs 'epargner pour le tier superieur' sans arithmetique (reponse a gm q_gm_001 : apercu cout/gain du prochain palier). Cf. ## saving_arbitrage_perception."
    },
    {
      "id": "vr_rate_indicator",
      "entity_role": "ui",
      "required": true,
      "description": "Indicateur de rythme R/s (debit de production courant) affiche en permanence, DISTINCT du solde et du total cumule, avec un repere de cadence (aiguille/barre lumineuse) qui rend la VITESSE de montee lisible d'un coup d'oeil. Rend perceptible l'effet d'une strategie sur le rythme (reponse a gm q_gm_002 : indicateur de rythme R/s). Cf. ## strategy_divergence_perception."
    },
    {
      "id": "vr_autoprod_pulse",
      "entity_role": "effect",
      "required": true,
      "description": "Pulsation lumineuse discrete emise par CHAQUE emetteur possede a chaque tick de production automatique, de signature PULSE (rythmee, douce) distincte du BURST du clic (vr_click_feedback). Montre d'ou vient le R (clic-lourd = bursts sur la Source ; generateurs-d'abord = nappe de pulsations), rendant la divergence de strategie perceptible (reponse a gm q_gm_002). Cf. ## strategy_divergence_perception."
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
  compteur, le débit et l'effet de gain sont prioritaires (`## ui_readability`), et l'asymétrie
  d'accès est rendue **perceptible** par la jauge de progrès-vers-abordable (`## saving_arbitrage_perception`).
- **La boucle démarre par un clic manuel puis bascule sur de la production automatique visible** —
  `worldscan:games[0].loops.minute_1` (« Manuel click acquire auto-clicker ; feedback immédiat :
  CpS visible »). ⇒ la cible cliquable et la première production doivent être immédiatement
  lisibles à l'écran ; la source du R (clic vs auto) est distinguée visuellement (`## strategy_divergence_perception`).
- **Les déblocages se font par seuils d'accumulation, pas par le temps** —
  `worldscan:games[0].loops.minute_10` (« déblocages upgrades tous les 5/25/50 achats »). ⇒
  l'apparition d'un nouveau tier/amélioration est un événement visuel (`vr_threshold_unlock_fx`).
- **Le genre n'a ni victoire ni défaite** — `worldscan:games[0].objectives[0].has_win_state` = false
  et `worldscan:games[0].objectives[0].has_defeat_state` = false. ⇒ aucun langage visuel de
  punition ; la victoire imposée par la structure est traitée comme une exception positive.
- **Les noms/entités des jeux observés (Grandmas, Cursors, héros, Managers) restent hors-champ** —
  le worldscan est advisory et ne prescrit pas l'univers de p1_alpha ; aucune de ces entités n'est
  reprise ici (le thème propre est l'Éclat, décidé par le GM, pas emprunté aux références).

## heritage_story_bible

Ce que cette Art Bible reprend de la Story Bible (qui est volontairement quasi vide — 2/8 sections
GROUNDED, faute de charter matérialisé) :

- **Aucun monde diégétique ni personnage n'est ancré** — `story_bible:characters` (NOT_GROUNDED :
  « le genre observé est d'ailleurs sans avatar narratif ») et `story_bible:factions`
  (NOT_GROUNDED). ⇒ pas d'avatar ni de faction à dessiner ; les entités « à états » sont des
  objets d'interface, cf. `## character_states`. Le thème Éclat décidé par le GM est un habillage
  visuel abstrait (lumière/croissance), pas un récit — cohérent avec l'absence de socle narratif.
- **La cohérence interdit une clôture par victoire finale de type narratif et toute menace/défaite**
  — `story_bible:coherence_rules` (« Toute couche narrative éventuelle doit rester sans clôture par
  victoire finale » ; « La cohérence du monde ne peut reposer sur une menace existentielle ni une
  condition de perte »). ⇒ l'écran de victoire S5 est un jalon heureux (embrasement lumineux), pas
  une fin dramatique ; aucun visuel anxiogène.
- **Un reset/prestige, s'il existait, ne doit pas se lire comme une punition** —
  `story_bible:coherence_rules` (« reset reframed comme feature pas punition »). p1_alpha n'a pas de
  prestige dans la structure imposée, mais la règle oriente le ton général : non punitif.
- **Le substrat narratif est explicitement à fournir en aval** — `story_bible:context` (« le socle
  narrateur reste donc à fournir en aval »). ⇒ le thème concret, resté ouvert au Round 1, a été
  fourni par le Game Master (Éclat) au Round 1 de la boucle, et est intégré ici.

## visual_language

(DÉCIDÉ — le style est décidé ici ; le SUJET est désormais concret, fixé par le GM.)

- **Grammaire de formes** : aplats vectoriels, coins arrondis, épaisseurs de trait constantes,
  profondeur suggérée par des ombres douces et non par du relief réaliste. Rien de bruité, rien de
  photographique.
- **Hiérarchie chromatique** (règle, pas décoration) : (1) l'accent lumineux de « croissance »
  (l'Éclat) est **réservé** aux nombres qui augmentent, au gain de clic, au débit R/s et aux boutons
  achetables ; (2) le fond et les cadres restent désaturés ; (3) le gris franc marque
  l'indisponibilité ; (4) une teinte de célébration n'apparaît qu'à la victoire. Un même élément ne
  porte jamais deux rôles chromatiques.
- **Échelle des silhouettes** : G1 < G2 < G3 < G4 en présence visuelle (taille/détail/densité de
  lumière), du petit émetteur au grand foyer, pour que la progression de puissance soit lisible sans
  lire un chiffre.
- **Sujet concret (FIXÉ par le GM, `gm_worldscan:game_master.grey_blocks` + réponse q_art_001)** :
  **R** = motes/orbes de lumière (l'Éclat) ; **cible cliquable** = une **Source lumineuse** centrale ;
  **G1..G4** = quatre **émetteurs de lumière** en escalade ; **améliorations** = badges (2 « main
  plus vive » ×2/×4 clic, 4 « halo ×2 prod » un par émetteur). Ce sujet remplace le défaut abstrait
  du Round 1 ; conformément à la décision du GM, **il ne change aucune règle de style/affordance/
  lisibilité** ci-dessus, seulement ce que les assets représentent. Deux signatures d'effet
  distinctes portent le thème : **BURST** (éclat de clic) vs **PULSE** (pulsation de production
  automatique), cf. `## strategy_divergence_perception`.

## affordance_rules

(DÉCIDÉ.) Chaque règle sert un comportement observable imposé (D1–D5, `s0-contrat:§S1/D`) :

- **Cliquable = évident** : la Source centrale se distingue de tout le reste par sa taille, son accent
  lumineux et sa réaction au survol/enfoncement ; rien d'autre à l'écran n'imite son affordance de clic.
- **Achetable vs refusé** : un achat possible porte l'accent et réagit ; un achat impossible est
  **grisé de façon franche et non ambiguë** et ne bouge pas au clic (D4 : « bouton visiblement
  grisé/refusé et R ne bouge pas »). Le grisé ≠ le caché. Le grisé porte en outre la jauge de
  progrès-vers-abordable (cf. `## saving_arbitrage_perception`) : indisponible ≠ statique.
- **Verrouillé = caché ou grisé lisiblement** : un tier/amélioration non débloqué est masqué ou
  nettement estompé jusqu'à son seuil (D1) ; son apparition est un événement (`vr_threshold_unlock_fx`,
  D5).
- **Coût toujours accompagné de l'icône R** : aucun montant n'est affiché sans le symbole de la
  ressource (l'orbe d'Éclat), pour rendre le coût lisible d'un coup d'œil.
- **Possession visible** : le nombre d'unités possédées de chaque émetteur est montré (D3).

## character_states

(DÉCIDÉ.) p1_alpha **n'a aucun personnage** (`story_bible:characters` NOT_GROUNDED). Cette section
définit donc les **états visuels des objets interactifs**, seuls porteurs d'états dans ce jeu :

- **Source (cible cliquable)** : `repos` (idle, respiration lumineuse lente optionnelle) → `enfoncée`
  (déformation courte au clic) → `juice` (éclat de lumière + « +N » émis). Retour à `repos` immédiat.
- **Émetteur (par tier G1–G4)** : `verrouillé` (caché/estompé avant son seuil) → `achetable`
  (accent, réactif) → `non-achetable` (grisé franc avec jauge de charge, R insuffisant) → `possédé`
  (compteur d'unités visible ; pulsation de production active, cf. `vr_autoprod_pulse`).
- **Amélioration (×6)** : `verrouillée` → `achetable` → `non-achetable (grisée, avec jauge)` →
  `achetée` (badge marqué acquis, non recliquable).
- **Bouton d'achat générique** : `actif/achetable` vs `grisé/refusé` (D4), deux états visuellement
  non confondables ; l'état grisé n'est jamais figé (il porte la jauge de progrès-vers-abordable).
- **Jeu global** : `en cours` → `VICTORY` (bascule l'écran de victoire, S11) — pas d'état de
  défaite.

## ui_readability

(DÉCIDÉ.) La lisibilité est la fonction n°1 de l'interface, dérivée de la rétention héritée
(`worldscan:games[0].retention_answer`) :

- **Le compteur R et le total cumulé sont toujours visibles** (D1, `s0-contrat:§S1`) et constituent
  l'élément typographique le plus grand et le plus contrasté de l'écran ; le total cumulé
  (base des 5 seuils) est distinct du solde et clairement étiqueté.
- **Le débit R/s est lisible en permanence** et distinct du solde/cumul (`vr_rate_indicator`) : la
  vitesse de montée est une information à part entière, portée par un repère de cadence
  (cf. `## strategy_divergence_perception`).
- **Chiffres d'abord** : chiffres tabulaires (largeur fixe) pour éviter les sauts quand les nombres
  grandissent ; grands nombres abrégés lisiblement (ex. 1.2M) sans jamais masquer la progression.
- **Le gain de clic est perçu** : l'incrément « +N » apparaît là où l'œil regarde (près de la Source)
  et disparaît vite, sans encombrer.
- **États non-achetables distinguables** : le grisé garde un contraste de texte suffisant pour rester
  lisible (désactivé ≠ illisible), et sa jauge de charge reste discrète (n'écrase pas le libellé).
- **Victoire visible sans ambiguïté** (S11) : le panneau de fin est franc, centré, et n'obscurcit pas
  au point de faire croire à une erreur/panne.
- **Cible d'accessibilité** : contraste texte/fond visé conforme WCAG AA sur les nombres et les
  libellés de coût ; l'information n'est jamais portée par la seule couleur (forme/texte redondants
  pour l'état grisé, pour la jauge, et pour les deux signatures d'effet BURST/PULSE).

## world_constraints

(DÉCIDÉ, borné par la structure et la plateforme.)

- **Support** : page web unique, **HTML + JS, rendu canvas**, 2D uniquement
  (`s0-contrat:plateforme_cible`). Front-facing UI, jamais de scène 3D ni de vue top-down.
- **Assets locaux, zéro réseau pour la logique** (`s0-contrat:plateforme_cible`) — aucune
  dépendance CDN ; aucun octet réseau généré par cette étape (ingestion nouvelle = gate Pierre).
- **Déterminisme visuel** : aucune animation ne doit dépendre d'un aléa qui affecterait l'économie
  (RNG interdit dans la logique, `s0-contrat:§S3`) ; les effets décoratifs peuvent varier mais ne
  changent jamais l'état de jeu. La jauge de progrès-vers-abordable et le débit R/s sont des
  **rendus dérivés de l'état** (R, coût, production), jamais une source d'aléa.
- **Pas de défaite à représenter** ; la victoire (S5) est le seul état terminal, et il est positif.
- **Budget de lisibilité** : le fond et les décors ne doivent jamais réduire le contraste des
  nombres (contrainte prioritaire, cf. `## ui_readability`).

## asset_rules

(DÉCIDÉ.) Règles de production pour toute demande d'asset de ce jeu :

- **Format/runtime** : tous les assets sont `format: 2D`, `runtime: html` (cf. `asset_requests.json`).
- **Styles autorisés** : `flat-vector-2d` (objets de jeu, effets, fond) et `clean-web-ui` (couche
  interface, jauges, badges) — et seulement ceux-ci ; tout autre tag de style est hors identité et
  doit repasser par cette bible.
- **Licences** : sous-ensemble par défaut du studio (CC0-1.0 / MIT / CC-BY-4.0 / CC-BY-3.0) ; aucune
  contrainte plus stricte déclarée (`license_allowed: null` = défaut assumé).
- **Icône de ressource = source unique** : le même symbole R (orbe d'Éclat) est réutilisé partout où
  R apparaît (compteur, débit, coûts, gains) — jamais deux variantes concurrentes.
- **Escalade des émetteurs** : G1→G4 partagent une famille visuelle (émetteurs de lumière) mais
  escaladent en présence (silhouette), pour lire la puissance sans lire un chiffre.
- **Badges d'améliorations = cadre commun** : les 6 améliorations partagent un gabarit de badge ; le
  thème étant fixé (Éclat), leur contenu est décidé — 2 « main plus vive » (clic) et 4 « halo ×2 prod »
  (un par émetteur).
- **Deux signatures d'effet non confondables** : BURST (clic) et PULSE (production auto) sont des
  familles d'effet distinctes et réutilisables, portant la lecture de « d'où vient le R ».
- **Résolution mécanique ≠ satisfecit esthétique** : qu'une requête résolve `OK` contre le catalogue
  ne prouve jamais que l'asset « est du bon style » au sens visuel (`style_tag_match` compare des
  tags, pas des pixels) — la conformité esthétique reste un fog HumanGate, jamais un claim
  (cf. `docs/forge/ASSET_CONTRACT_V0.md`).
- **Aucune écriture dans `knowledge_base/catalog.json`** (lecture seule) ; les `asset_requests` sont
  un artefact par-run.

## saving_arbitrage_perception

(DÉCIDÉ — Round 2, RÉPONSE à `gm q_gm_001` sur `economy_loop.eco_decision`. Ancre :
`art_bible:saving_arbitrage_perception`.)

Le Game Master a mesuré un vrai trou : la boucle de fond imposée est l'arbitrage **acheter
maintenant vs épargner pour le palier supérieur**, mais au Round 1 la transformation perceptible de
`economy_loop` se réduisait au **grisage** des boutons — la moitié « épargne » de la décision restait
invisible (le grisé dit « non », il ne dit pas « bientôt »). Décision d'art-direction, en deux
dispositifs qui ne forcent **aucune** lecture chiffrée :

1. **Jauge de progrès-vers-abordable** (`vr_affordability_meter`) — chaque bouton d'achat non
   finançable se **charge** de l'accent lumineux proportionnellement à `R / coût_courant`. Épargner
   n'est plus un état mort : c'est un **remplissage qui monte** sous les yeux du joueur, et l'achat
   devient possible quand la jauge est pleine. L'asymétrie d'accès héritée
   (`worldscan:games[0].retention_answer` : « toujours un achat prochain mais pas immédiat ») devient
   littéralement **visible** comme une barre qui se remplit. Rendu dérivé de l'état (R, coût), jamais
   d'aléa (cf. `## world_constraints`).
2. **Aperçu du prochain palier** (`vr_yield_preview`) — à côté du coût de chaque élément
   achetable/prévisualisé, un **repère comparatif** (barre/pips de lumière) montre ce que cet achat
   **ajoute au débit R/s**, de sorte que « une unité de plus de ce tier » et « épargner pour le tier
   supérieur » se **comparent d'un coup d'œil** sans arithmétique. Le joueur voit que le gros émetteur
   verrouillé apporte davantage — c'est ce qui rend l'épargne un choix qui a du sens, pas une attente
   subie.

Ensemble, ces deux dispositifs rendent `economy_loop.transformation_perceptible` complète : le coût
qui monte ET l'épargne qui se remplit ET le gain relatif du palier suivant sont tous perceptibles.
Ces rendus respectent les règles de `## affordance_rules` (le grisé reste franc et non cliquable ;
la jauge est un supplément discret, jamais un faux « achetable ») et `## ui_readability` (jauge et
aperçu ne réduisent jamais le contraste des nombres). Les deux entités sont portées en
`## 3. BESOINS VISUELS` (required:true) et couvertes par une `asset_request` dédiée dans
`asset_requests.json` (`req_affordability_meter`, `req_yield_preview`).

## strategy_divergence_perception

(DÉCIDÉ — Round 2, RÉPONSE à `gm q_gm_002` sur `skill_loop.skill_decision`. Ancre :
`art_bible:strategy_divergence_perception`.)

Le Game Master a mesuré que la seule « compétence » du jeu est la **stratégie d'allocation**
(clic-lourd vs générateurs-d'abord), et que sa divergence est exactement ce que S10 doit mesurer
(temps-jusqu'à-S5, ≥2 valeurs distinctes) — mais qu'au Round 1 rien ne rendait cet effet
**perceptible au joueur**. Décision d'art-direction, en deux dispositifs sans lecture chiffrée
imposée :

1. **Indicateur de rythme R/s** (`vr_rate_indicator`) — un repère de **cadence** (aiguille/barre
   lumineuse) affiché en permanence, **distinct** du solde et du total cumulé, dont la position/vitesse
   traduit le **débit courant**. Une stratégie générateurs-d'abord fait **monter** durablement ce
   repère ; une stratégie clic-lourd le fait **osciller** au rythme des clics. Le joueur *voit* que sa
   stratégie change le rythme, sans devoir lire un nombre. C'est le pendant visuel de la métrique de
   divergence `skill_time_to_s5_ticks` (`gm_worldscan:progression_metrics`).
2. **Distinction de la source du R : BURST vs PULSE** (`vr_autoprod_pulse` + `vr_click_feedback`) —
   le clic émet un **BURST** (éclat ponctuel sur la Source) ; chaque émetteur possédé émet, à son tick
   de production, une **PULSE** (pulsation douce et rythmée). Un joueur clic-lourd voit un écran de
   **bursts** concentrés sur la Source ; un joueur générateurs-d'abord voit une **nappe de pulsations**
   répartie sur ses émetteurs. « D'où vient mon R » devient lisible à l'œil nu, et donc l'effet de la
   stratégie sur la composition de la production.

Ensemble, ces deux dispositifs rendent `skill_loop.transformation_perceptible` réellement perceptible
(« deux stratégies distinctes produisent des rythmes visiblement différents ») au lieu d'être une
propriété seulement mesurée par les bots. Les deux entités sont portées en `## 3. BESOINS VISUELS`
(required:true) et couvertes par une `asset_request` dédiée (`req_rate_indicator`, `req_autoprod_pulse`).

---

Round 2 de la boucle ART↔GM : la réponse du Game Master à `q_art_001` (thème Éclat) est **intégrée**
(sujet concret des assets fixé, règles de style/affordance/lisibilité inchangées comme convenu), et
les **deux questions du Game Master** (`q_gm_001` épargne perceptible, `q_gm_002` divergence de
stratégie perceptible) sont **traitées** par deux sections décidées et **quatre entités visuelles**
nouvelles, couvertes par leurs `asset_requests`. ART n'a plus de question ouverte au GM. Voir le bloc
`design_questions` final (round 2).
