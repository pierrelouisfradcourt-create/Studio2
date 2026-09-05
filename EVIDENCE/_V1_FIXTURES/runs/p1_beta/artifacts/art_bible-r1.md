---
styles: [luminous-vector, ember-glow, deep-space-flat, hud-neon]
mood_keywords: [luminous, ascendant, cosmic, calm-to-radiant, weightless, incandescent, meditative, minimal]
---

# Art Bible — p1_beta (v0.1)

> Run : `p1_beta-20260830-run1` · étape : `s2.5-artbible` · rôle : Art Director (bras LIBRE L).
> Sources héritées réellement présentes : `charter.yaml`, `worldscan.json` (3 comparables),
> `story_bible.json` (7 sections NOT_GROUNDED, 1 GROUNDED : `coherence_rules`).
> La Story Bible n'impose AUCUN monde diégétique (`story_bible:context` = NOT_GROUNDED) —
> l'identité visuelle ci-dessous est donc DÉCIDÉE de zéro, sous les seules contraintes
> `story_bible:coherence_rules` (pas de copie Cookie Clicker, grammaire de genre, fin finie).
> `claim_verdict: NO_CLAIM_ALLOWED` — ce document décrit une intention visuelle et sa
> traduction structurée ; il ne certifie aucune qualité esthétique.

## 1. IDENTITÉ VISUELLE

**Thème décidé : « Le Foyer » — une forge de lumière cosmique.** Le joueur attise un
foyer de lumière unique posé au centre d'un champ sombre et vide. Chaque action d'attisage
projette des éclats de lumière qui alimentent un compteur ; des émetteurs achetables
prolongent et automatisent cette lumière ; à mesure que la lumière s'accumule, le champ
noir s'illumine et une constellation se dessine, jusqu'à un embrasement final observable
qui clôt la partie. Aucun avatar, aucun personnage, aucun monde nommé : les seuls
« acteurs » sont des systèmes abstraits de lumière (cohérent avec `story_bible:characters`
= NOT_GROUNDED, aucun personnage à ancrer).

**Palette (décidée) :**
- **Fond** — indigo quasi-noir `#0B0E1A` → violet profond `#1A1636`. Vide, calme, non
  distrayant ; se réchauffe globalement à mesure de la progression (embrasement).
- **Foyer / ressource (chaud, émissif)** — braise `#FF7A18` → or incandescent `#FFD24A` →
  blanc-chaud `#FFF3D0` au cœur. C'est le seul foyer chaud de l'écran : l'œil y va d'abord.
- **Émetteurs / progression (froid, luminescent)** — cyan `#3FE0D0`, violet-néon `#A46BFF`.
  Signalent l'automatisation et l'avancée, en contraste franc avec le chaud du foyer.
- **UI / HUD (neutre lisible)** — texte `#EAF0FF` sur panneaux `#12162B` à ~85 % d'opacité,
  liseré néon `#3FE0D0`. Accent d'action (boutons actifs) en or `#FFD24A`.
- **États verrouillés** — désaturés vers gris-bleu `#3A4060`, opacité réduite, aucun glow.

**Mood :** lumineux, ascendant, apesanteur, méditatif au départ puis incandescent à la fin
(`calm-to-radiant`). Registre minimal et vectoriel : formes nettes + halo émissif, jamais
de texture chargée. Composition CENTRÉE (le foyer au milieu, l'UI en périphérie) — le genre
clicker n'a pas de point de vue navigable, la lecture est frontale.

**Références de style (mots-clés, advisory) :** art vectoriel émissif « glow-on-dark »,
lisibilité de dataviz nocturne, minimalisme lumineux. AUCUN emprunt à Cookie Clicker
(ni biscuit, ni pâtisserie, ni curseur/grand-mère, ni valeur numérique) — contrainte dure
`story_bible:coherence_rules[0]`.

## 2. RATIONALE

**Pourquoi ce style sert la boucle observable exigée par le charter.** Le charter
(`criteres_demo`) impose quatre choses VISIBLES : (a) une action cœur qui fait monter un
compteur à l'écran, (b) au moins un achat/déblocage qui change observablement l'écran,
(c) un état terminal signalé à l'écran, (d) le déterminisme. Le thème « forge de lumière »
mappe chacune sur un signal visuel non ambigu :

- **(a) Action cœur → chaleur.** Attiser le foyer émet une gerbe d'éclats chauds et fait
  bondir le compteur de lumière. La chaleur = la ressource : un seul foyer chaud à l'écran,
  impossible à confondre. Hérité de la convention de genre « clic → le nombre monte, le
  prochain achat se déverrouille » (`worldscan:games[0].loops.minute_1`).
- **(b) Achat → froid qui s'allume.** Chaque émetteur acheté APPARAÎT physiquement autour
  du foyer (nouvelle silhouette froide luminescente) ET augmente visiblement le flux de
  lumière. Le passage « le revenu passif devient visible » du genre
  (`worldscan:games[0].loops.minute_10`) devient ici une addition d'objets à l'écran, pas
  seulement un chiffre qui accélère.
- **(c) Fin → embrasement.** La progression remplit une constellation ; à saturation, le
  champ entier s'embrase et un panneau de fin s'affiche. Le genre observé GRAVITE vers
  l'absence de fin (`worldscan:games[0].objectives[0].has_win_state` = false,
  `worldscan:games[1].objectives[0].has_win_state` = false) — la fin est une déviation
  DÉLIBÉRÉE exigée par le charter (`story_bible:coherence_rules[2..3]`), donc elle doit être
  le moment visuel le PLUS fort (contraste maximal chaud→blanc). Le précédent d'un genre
  qui PEUT avoir une fin existe (`worldscan:games[2].objectives[0].has_win_state` = true,
  Kittens Game / space age), ce qui rend l'exigence cohérente avec le genre, pas étrangère.
- **(d) Déterminisme → lisibilité stable.** Palette et silhouettes fixes, aucun aléa
  visuel non seedé : deux rejeux d'une même seed donnent la même image aux mêmes ticks.

**La prose ci-dessus n'est PAS une preuve de couverture.** La couverture réelle est portée
UNIQUEMENT par la section 3 (`visual_requirements` structurés) et par `asset_requests.json` —
seule cette donnée structurée est vérifiée mécaniquement par `check_artbible.mjs`. Ce
RATIONALE explique les choix ; il ne les certifie pas.

## 3. BESOINS VISUELS

Chaque entité visuelle distincte de la boucle clicker est listée ci-dessous. `required:true`
dès qu'une entité est citée par une source héritée OU centrale à l'action cœur / au déblocage /
à l'état terminal (conditions observables du charter). `required:false` UNIQUEMENT pour du
décor réellement cosmétique. Chaque `required:true` a au moins une `asset_request` de même
`entity_role` dans `asset_requests.json` (couverture close).

```json
{
  "visual_requirements": [
    {
      "id": "vr_core_hearth",
      "entity_role": "other",
      "required": true,
      "description": "Le FOYER central attisable — objet lumineux chaud, unique, au centre de l'ecran. C'est l'affordance de l'action coeur : le cliquer emet de la lumiere et fait monter le compteur. Doit lire 'chaud, vivant, cliquable' au premier coup d'oeil (source heritee : worldscan:games[0].loops.minute_1, action coeur du genre)."
    },
    {
      "id": "vr_emitter_unit",
      "entity_role": "item",
      "required": true,
      "description": "Un EMETTEUR achetable — silhouette froide luminescente (cyan/violet) qui apparait autour du foyer une fois acquise et automatise/prolonge la production de lumiere. C'est le deblocage/achat qui change observablement l'ecran (charter:criteres_demo ; worldscan:games[0].loops.minute_10 'le revenu passif devient visible')."
    },
    {
      "id": "vr_spark_burst",
      "entity_role": "effect",
      "required": true,
      "description": "La gerbe d'ECLATS emise a chaque attisage du foyer — feedback visuel immediat prouvant a l'ecran que le compteur augmente (charter:criteres_demo 'compteur qui AUGMENTE visiblement'). Particules chaudes courtes, deterministes (pas d'alea non seede)."
    },
    {
      "id": "vr_light_counter",
      "entity_role": "ui",
      "required": true,
      "description": "Le COMPTEUR de lumiere (ressource) affiche en HUD — le nombre central que l'action coeur fait monter et qui sert de score/progression. Lisibilite maximale sur fond sombre (charter:criteres_demo)."
    },
    {
      "id": "vr_buy_button",
      "entity_role": "ui",
      "required": true,
      "description": "Le BOUTON d'achat/amelioration d'un emetteur — affordance UI cliquable, avec etat actif (or) et etat non-abordable (desature). Central a la progression : sans lui, aucun deblocage n'est declenchable."
    },
    {
      "id": "vr_progress_constellation",
      "entity_role": "ui",
      "required": true,
      "description": "L'INDICATEUR DE PROGRESSION vers la fin — une constellation/jauge qui se remplit a mesure que la lumiere s'accumule, rendant l'avancee vers l'etat terminal observable a l'ecran (charter:condition_de_victoire, fin ATTEIGNABLE et OBSERVABLE)."
    },
    {
      "id": "vr_end_screen",
      "entity_role": "ui",
      "required": true,
      "description": "L'ECRAN/MARQUEUR DE FIN — panneau d'embrasement affiche quand l'etat terminal est atteint dans le budget de ticks. Signale sans ambiguite 'la partie est finie' (charter:criteres_demo 'atteint et SIGNALE A L'ECRAN un etat terminal')."
    },
    {
      "id": "vr_locked_glyph",
      "entity_role": "icon",
      "required": true,
      "description": "Le GLYPHE d'etat verrouille — petite icone desaturee sans glow indiquant qu'un emetteur/amelioration n'est pas encore accessible. Porte la regle d'affordance verrouille vs disponible, necessaire pour que la progression (deverrouillages successifs) soit lisible."
    },
    {
      "id": "vr_field_background",
      "entity_role": "environment",
      "required": false,
      "description": "Le CHAMP de fond cosmique (indigo->violet) qui se rechauffe globalement avec la progression. Cosmetique : la boucle observable fonctionne sur un aplat de couleur uni ; ce fond enrichit l'ambiance sans etre requis pour aucune condition de victoire/defaite/score. Marque required:false a ce titre (decor veritablement optionnel)."
    }
  ]
}
```

## heritage_worldscan

Ce que l'identité visuelle HÉRITE du World Scan (`worldscan.json`), avec adresses réelles —
matière citée, jamais redite ni jugée :

- **Action cœur = clic qui fait monter un nombre et déverrouille l'achat suivant.**
  `worldscan:games[0].loops.minute_1` (« Manual clicking accumulates first cookies […]
  number increases, next purchase unlocks »). → Décision visuelle : un unique foyer chaud
  cliquable + un compteur qui bondit à chaque clic (cf. `vr_core_hearth`, `vr_light_counter`).
- **L'automatisation doit devenir VISIBLE, pas seulement plus rapide.**
  `worldscan:games[0].loops.minute_10` (« Passive income becomes visible »). → Chaque
  émetteur acheté est un OBJET ajouté à l'écran, pas un simple coefficient
  (cf. `vr_emitter_unit`).
- **Le feedback direct de l'action est un pilier du genre.**
  `worldscan:games[1].loops.minute_1` (« Feedback: monster health decreases, gold
  increases »). → La gerbe d'éclats à chaque attisage (cf. `vr_spark_burst`).
- **La progression exponentielle porte la « sensation de puissance ».**
  `worldscan:games[0].retention_answer` (« Exponential progression creates eternal sense of
  power »). → Rendu par un embrasement croissant du champ (le fond se réchauffe globalement).
- **Le genre gravite vers l'ABSENCE de fin — donc la fin est une déviation à afficher fort.**
  `worldscan:games[0].objectives[0].has_win_state` = false ;
  `worldscan:games[1].objectives[0].has_win_state` = false. → L'état terminal reçoit le
  contraste visuel maximal (cf. `vr_end_screen`, `vr_progress_constellation`).
- **Un précédent de genre AVEC fin observable existe et rend l'exigence cohérente.**
  `worldscan:games[2].objectives[0].has_win_state` = true, `victory_condition` = « Reach
  space age ». → Justifie qu'une fin atteignable n'est pas étrangère au genre.

## heritage_story_bible

Ce que l'identité visuelle HÉRITE de la Story Bible (`story_bible.json`) — quasi vide par
construction (genre sans monde inhérent), donc l'héritage est surtout une série de
CONTRAINTES et de latitudes, avec adresses réelles :

- **Aucun monde diégétique imposé → latitude totale de décision visuelle.**
  `story_bible:context` = NOT_GROUNDED (« Ni le charter ni le worldscan ne fixent de monde
  diegetique »). → L'Art Director invente librement le thème « forge de lumière ».
- **Aucun personnage imposé → pas d'avatar, acteurs abstraits.**
  `story_bible:characters` = NOT_GROUNDED. → Les « acteurs » sont des systèmes de lumière
  (foyer, émetteurs), jamais un personnage (cf. `vr_core_hearth`, `vr_emitter_unit`).
- **Interdit dur : aucune reprise de Cookie Clicker (asset, nom, contenu, valeur).**
  `story_bible:coherence_rules[0]` (source charter `actions_interdites`). → Thème non
  alimentaire, non pâtissier ; aucune référence de curseur/grand-mère ; palette et
  silhouettes originales.
- **Rester dans la grammaire du genre incremental/clicker.**
  `story_bible:coherence_rules[1]` (source charter `reference_jeu`). → Composition frontale
  centrée, action cœur unique, achats périphériques, compteur proéminent.
- **Le monde visuel doit accueillir une fin observable et atteignable ; idle infini proscrit.**
  `story_bible:coherence_rules[2]` (source charter `condition_de_victoire`). → La
  constellation/jauge et l'embrasement final matérialisent une clôture
  (cf. `vr_progress_constellation`, `vr_end_screen`).
- **La fin est une déviation délibérée par rapport à la norme du genre, à MAINTENIR.**
  `story_bible:coherence_rules[3]` (source worldscan). → L'état terminal est le climax
  visuel, pas un détail.

## visual_language

Style réel DÉCIDÉ (aucune adresse héritée exigée ici) :

- **Langage :** art vectoriel plat + halo émissif (glow additif sur fond sombre). Formes
  géométriques simples et nettes ; le volume est suggéré par le glow, jamais par des textures.
- **Hiérarchie chromatique :** un seul foyer CHAUD (le point d'action) ; tout le reste en
  FROID (émetteurs, progression) ou NEUTRE (UI). Le chaud est réservé à la ressource et à
  l'action — jamais utilisé pour du décor, pour que l'œil sache toujours où cliquer.
- **Épaisseur de trait :** contours fins et réguliers (2 px de référence à l'échelle 1x),
  coins arrondis doux. Pas de dégradés sales : dégradés radiaux propres du cœur vers le halo.
- **Échelle & composition :** foyer centré occupant ~25–30 % de la hauteur ; UI ancrée aux
  bords (compteur en haut, achats sur un côté). Marges généreuses, densité faible : la
  lumière respire.
- **Animation :** pulsations lentes du foyer au repos ; flash bref (< 200 ms) à l'attisage ;
  montée de glow continue du fond avec la progression. Toute animation dérive de l'état de
  jeu (déterministe), jamais d'un timer aléatoire non seedé.

## affordance_rules

Règles d'affordance DÉCIDÉES — comment le joueur SAIT ce qui est interactif :

- **Chaud + halo pulsant = cliquable maintenant** (le foyer). C'est la SEULE source chaude
  animée ; elle attire l'action.
- **Froid + pleine opacité + liseré net = achetable et abordable** (émetteur/bouton actif,
  accent or sur le bouton).
- **Désaturé + opacité réduite + aucun glow = verrouillé / non abordable** (cf. `vr_locked_glyph`).
  Un élément verrouillé ne doit JAMAIS emprunter le chaud ni un halo, sous peine de fausse
  affordance.
- **Transition d'état visible :** au moment où un achat devient abordable, l'élément passe
  de désaturé à froid-plein (changement observable exigé par le charter). Au moment de
  l'achat, l'émetteur APPARAÎT autour du foyer.
- **Un seul niveau de focus à la fois :** pendant l'écran de fin, l'interaction de jeu est
  visuellement neutralisée (assombrissement du HUD) pour que le climax soit sans ambiguïté.

## character_states

Le jeu n'a pas de personnage (avatar) — `story_bible:characters` = NOT_GROUNDED. Les « états »
concernent donc les objets-systèmes, DÉCIDÉS ici :

- **Foyer :** `dormant` (glow faible, pulsation lente) → `attisé` (flash bref à chaque clic)
  → `saturé` (glow soutenu quand la production est haute) → `embrasé` (état terminal, blanc-chaud).
- **Émetteur :** `verrouillé` (absent/silhouette fantôme désaturée) → `disponible`
  (silhouette froide pleine, prête à l'achat) → `actif` (émet un filet de lumière visible
  vers le foyer/le compteur).
- **Bouton d'achat :** `indisponible` (désaturé) → `abordable` (accent or) → `pressé`
  (flash) → `épuisé/max` (verrouillé neutre si plus rien à acheter).
- Aucune animation d'état n'introduit d'aléa non déterministe : chaque état est fonction
  pure de l'état de jeu à un tick donné.

## ui_readability

Règles de lisibilité UI DÉCIDÉES (fond sombre, sonde mesurée + évaluateur humain aveugle) :

- **Contraste :** texte `#EAF0FF` sur panneaux `#12162B` ≥ ratio AA (≥ 4.5:1) pour les
  valeurs de compteur et les libellés d'achat.
- **Compteur = plus gros élément textuel** de l'écran ; toujours visible, jamais recouvert
  par un émetteur ou un effet (les effets se dessinent SOUS la couche HUD).
- **Chiffres :** police à chasse tabulaire (les colonnes de chiffres ne « sautent » pas quand
  la valeur monte) — critique pour lire une progression rapide et pour un rejeu déterministe
  comparable image à image.
- **Zone d'action protégée :** le foyer et sa gerbe d'éclats ne recouvrent jamais le
  compteur ni les boutons ; marge de sécurité autour du HUD.
- **État terminal non ambigu :** l'écran de fin porte un libellé texte explicite (ex.
  « Embrasement complet ») en plus du signal chromatique — un marqueur lisible par un bot
  comme par un humain.

## world_constraints

Contraintes connues DÉCIDÉES (limites que l'aval doit respecter) :

- **Runtime :** web HTML + JS canvas 2D uniquement (charter:plateforme_cible). Tous les
  assets sont 2D `html` ; aucun modèle 3D, aucun octet réseau à l'exécution.
- **Rendu déterministe :** aucun effet visuel ne peut dépendre d'un aléa non seedé (le rejeu
  d'une seed doit reproduire l'image aux mêmes ticks — charter:criteres_demo).
- **Budget de ticks fixe :** la progression visuelle (remplissage constellation, réchauffement
  du fond) doit être bornée et atteindre l'embrasement dans le budget — pas d'idle infini
  visuel (charter:condition_de_victoire).
- **Isolement L/D :** aucune valeur numérique, nom ou asset repris de Cookie Clicker ni du
  bras dirigé (charter:actions_interdites). Les silhouettes et la palette ci-dessus sont
  originales.
- **Aucune ingestion d'asset :** cette étape ne télécharge ni ne génère aucun octet ; toute
  nouvelle ingestion catalogue reste une gate Pierre (knowledge_base/README.md).

## asset_rules

Règles d'assets DÉCIDÉES (comment l'aval doit produire/résoudre) :

- **Un asset = une entité de la boucle.** Aucune requête générique « fourre-tout » : chaque
  `visual_requirement` `required:true` porte sa propre `asset_request` (cf. `asset_requests.json`).
- **Style déclaré = style demandé.** Chaque `asset_request.style` appartient au frontmatter
  `styles` de cette bible (`luminous-vector`, `ember-glow`, `deep-space-flat`, `hud-neon`) —
  cohérence bible↔requêtes vérifiée par `check_artbible.mjs`.
- **Formats :** sprites/icônes/vfx 2D `html`, licences ouvertes
  (`CC0-1.0`/`MIT`/`CC-BY-4.0`/`CC-BY-3.0`), pas de plafond de taille imposé (`max_size_kb:null`).
- **Résolution advisory attendue = BLOCKED, et c'est légitime.** Le catalogue actuel ne
  contient aucun asset de style « lumineux cosmique incremental » (il a `candy-pop` et
  `flat-top-down`, genres `shooter`/`tactical`) : les requêtes résoudront BLOCKED contre le
  catalogue. C'est un `resolution_stats.blocked` LÉGITIME (catalogue incomplet), à sourcer
  en HumanGate — jamais un `coverage.missing`, et jamais une raison d'assouplir une requête.
- **Aucun jugement esthétique mécanique.** `style_tag_match` compare des tags, pas des pixels
  (docs/forge/ASSET_CONTRACT_V0.md) : l'adéquation visuelle réelle reste un fog HumanGate.
