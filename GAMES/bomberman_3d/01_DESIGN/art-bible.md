# ART BIBLE — Bomberman 3D

> **statut_artefact** : PROPOSED · **claim_verdict** : NO_CLAIM_ALLOWED
> **evidence_verdict** : MECHANICAL_VALIDATION_ONLY
> **Direction ratifiée Pierre 2026-08-11** : **A — Jouet de guerre**
> **Amont** : `docs/forge/BOMBERMAN_3D_L0_CONTRACT.md` · `00_CHARTER/game_contract.yaml`
> **Descripteur visuel unique** : `06_RUNTIME/adapters/palette/palette.gd` — toute couleur
> nommée ici est un CANDIDAT de constante dans ce fichier, jamais un littéral ailleurs.
> Garde mécanique active : `06_RUNTIME/adapters/proof_harness/purete_visuelle.gd`.
>
> **Sections 5 à 9 : à venir.** Aucun asset n'est produit avant ratification complète.
>
> **⚠ Ce document décrivait un état antérieur.** Voir la **RÉVISION 3 (2026-08-12)** en fin de
> fichier : elle porte l'état RÉELLEMENT implémenté et mesuré. En cas de contradiction entre
> une section ci-dessous et la révision 3, **la révision 3 fait foi** — elle est adossée à des
> mesures, les sections antérieures à des propositions.

---

## 1. Énoncé d'identité visuelle

> **Bomberman 3D est un jouet de guerre lisible : chaque case, chaque acteur, chaque menace
> se comprend d'un regard, à la vitesse d'une explosion — la clarté EST le style, jamais son
> sacrifice.**

Cette règle tranche dans un seul sens : entre « plus beau » et « plus lisible », **lisible
gagne**. Elle prolonge le contrat L0 (`identity` : *« la 3D sert la lisibilité de la grille,
jamais la simulation »*) du terrain vers les acteurs et l'UI.

**Direction retenue — A, Jouet de guerre.** Diorama de jouets militaires stylisés,
proportions trapues, couleurs primaires franches, chaos joyeux. Réalisable avec les moyens
existants : primitives et proportions exagérées, aucun nouveau pipeline.
**Interdit par cette direction** : réalisme, textures peintes, dégradés subtils.
**Écartées** : B (diorama tactique — sacrifie la personnalité et sous-exploite les 3 `.glb`),
C (arcade lumineuse — le canal `emission` obligerait à re-mesurer `ECART_LUMINANCE_MIN` et
risquerait de noyer le contraste sol/menace déjà prouvé).

### P1 — La silhouette avant le matériau
Un objet doit rester identifiable écran désaturé. C'est déjà la doctrine des power-ups
(couleur + FORME + hauteur, prouvée en pixels) ; elle s'étend à tout ce qui compte pour la
survie.
*Test* : quand une géométrie est ambiguë entre deux objets de gameplay, on change la
**forme** avant la teinte.

### P2 — Le danger précède toujours l'effet
La case menacée est dessinée avant la flamme, et c'est prouvé en pixels
(`lisibilite_powerups`, volet « danger LISIBLE »). Ce principe l'élève de règle mécanique à
règle permanente.
*Test* : tout nouvel élément qui peut tuer doit avoir un état « annoncé » visuellement
distinct de son état « actif », **avant** d'être ajouté à quoi que ce soit d'autre.

### P3 — Le thème habille, il ne cache jamais la grille
Les 3 thèmes changent l'ambiance, jamais le repérage de case ni la lecture d'un acteur.
`ECART_LUMINANCE_MIN` existe déjà comme garde mécanique du damier ; ce principe l'étend en
doctrine.
*Test* : un choix esthétique qui fait descendre le contraste sol/mur/acteur sous le seuil
mesuré est rejeté, même s'il est plus joli.

---

## 2. Ambiance par état de jeu

États réels du runtime (`ui_shell.gd`) : MENU · EN_JEU · PAUSE · RESULTAT. La mort subite
n'est aujourd'hui qu'une alerte textuelle dans EN_JEU ; elle est traitée ici comme un état
ambiant à part car elle doit se distinguer nettement.

| État | Cible émotionnelle | Éclairage | Élément porteur |
|---|---|---|---|
| **Menu** | invitation ludique, choix sans pression | thème de la carte assourdi par `UI_VOILE` (α 0.82), contraste aplati | titre en `UI_TITRE` tranchant sur le voile ; la carte reste vivante en fond, jamais figée |
| **En jeu** | tension enjouée, danger maîtrisable | pleine lumière du thème, aucun voile — l'état le plus lumineux des quatre | la dalle `MENACE` au ras du sol |
| **Mort subite** | urgence croissante, claustrophobie | bascule vers le chaud-alarmant | les murs de fermeture de la spirale |
| **Résultat** | résolution, calme après la tempête | scène figée sous voile, plus sombre que le menu | l'état final de l'arène, qui doit raconter le combat |

**Candidats de production, non implémentés** — à ratifier avant toute écriture :
- pulsation d'opacité de `MENACE` (modulation d'alpha par script, aucun shader) — ajoute un
  canal de **mouvement**, utile aux daltonismes rouge-vert sévères ;
- teinte de mort subite **dérivée** et non littérale, sur le modèle de `tronc()` qui dérive
  déjà une teinte d'une autre : `ambiance.lerp(MENACE, 0.35)` ;
- mur de fermeture visuellement distinct d'un mur `SOLIDE` normal — sans quoi P2 est
  contredit sur le pire danger de fin de partie : `THEMES[nom]["mur"].lerp(MENACE, 0.4)` ;
- **acteur mort aplati plutôt que supprimé.** Mesuré : `arena_view_3d.gd:302` fait
  `if not a["vivant"]: continue` — l'écran de résultat gèle donc une arène qui ne raconte
  rien. Aplatir (scale Y ≈ 0, même primitive) coûte zéro géométrie et fait de
  « aplati = mort » une règle de forme.

---

## 3. Langage des formes

### Personnages — le trou nommé
Les 4 acteurs sont aujourd'hui des cubes identiques différenciés par la **seule couleur**
(`ACTEURS`, palette.gd:132). La couleur seule échoue pour un joueur daltonien, et échoue à
distance de caméra.

**Proposition** : garder le corps commun (le cube — signature du jouet de guerre) et ajouter
un **couvre-chef** distinct, en primitives pures — même geste que pour les power-ups, deux
canaux redondants.

| Joueur | Couleur existante | Couvre-chef | Lecture |
|---|---|---|---|
| J1 | blanc | demi-sphère | ronde, douce |
| J2 | rouge | prisme pointu | anguleuse, agressive |
| J3 | bleu | cylindre horizontal | technique, froide |
| J4 | jaune | deux cubes symétriques | large, écartée |

**Arbitrage retenu** : couvre-chef **attaché et non flottant**, plus petit que les power-ups
et solidaire du corps — la distinction « objet à ramasser » vs « partie d'un joueur » repose
sur le contexte (hauteur d'attache + mouvement), pas sur la forme brute.
**Arbitrage retenu** : la **taille** est écartée comme canal de différenciation. Des joueurs
de tailles inégales se lisent comme un déséquilibre de puissance dans un jeu symétrique.
*Réversible par Pierre* si une lecture « poids/masse » est un jour voulue (bots vs humain).

### Arène
Le langage existe déjà, il n'était pas nommé : **rectiligne et dur = permanent** (`SOLIDE`,
`BoxMesh`) · **organique et arrondi = destructible** (`gen_crate_wood_01`,
`gen_barrel_01`). Ratifié comme règle de forme plutôt que d'introduire une géométrie neuve.
`gen_pillar_stone_01` reste écarté comme mur (3× trop haut, confirmé au contrat L0).

### UI
Le HUD porte aujourd'hui du texte et **1** nœud `ColorRect` (voile plein écran), **0**
`Polygon2D`, **aucune icône**, et **aucun HUD par joueur**. (Décompte corrigé le
2026-08-11 : une première lecture comptait 2 *occurrences textuelles* — déclaration et
instanciation — au lieu de compter les nœuds.)
**Proposition, sans nouveau pipeline** : des pastilles 2D (`Polygon2D`/`ColorRect`) qui
**répètent la silhouette 3D** du power-up correspondant — carré sombre pour les bombes,
losange orange pour la portée, ovale vert pour la vitesse. Le HUD devient un prolongement du
monde, et reste lisible sans lecture de couleur seule (P1).

---

## 4. Système de couleur

### Rôles sémantiques (état mesuré dans `palette.gd`)

| Constante | Valeur | Rôle |
|---|---|---|
| `MENACE` | (0.72, 0.14, 0.12) | danger **annoncé**, pas encore mortel |
| `FLAMME` | (1.0, 0.55, 0.12) | mort **immédiate** |
| `ACTEURS[0..3]` | blanc · rouge · bleu · jaune | identité joueur — **jamais** un signal système |
| `POWERUPS[*]` | cyan · orange · vert | capacité (bombes · portée · vitesse) |
| `UI_TITRE` / `UI_HUD` / `UI_FLASH` | blanc · neutre · jaune chaud | interface, confirmation positive |
| `THEMES[*]` | gris pierre · verts · bleus | habillage — **jamais** un signal de gameplay |

### Tension nommée, délibérément NON corrigée
Le rouge porte deux sens : identité J2 (saturé, 0.90) et danger `MENACE` (désaturé, 0.72).
L'écart existe dans les valeurs mais **n'a jamais été mesuré en pixels côte à côte** —
l'oracle teste des cases vides, pas un acteur rouge sur une case menacée.
Aucune correction préventive : la doctrine du studio interdit de réparer un signal dont le
défaut n'est pas mesuré. Réparation déjà tracée si un playtest la révèle : désaturer
`MENACE` vers un rouge-brun terreux. Même remarque, enjeu moindre, sur le blanc (J1 vs UI) —
les deux vivent sur des plans différents (monde 3D vs overlay 2D).

### Articulation avec les thèmes
Aucun décor de thème n'entre aujourd'hui dans la bande rouge-orange réservée au danger.
**Principe** : aucune couleur de thème ne doit y tomber — et cela doit devenir une extension
mesurée de l'oracle de discernabilité, pas une relecture humaine. Nommé ici, non engagé.

### Palette d'UI
**Candidat** : une constante `UI_PANEL_JOUEUR` (α ≈ 0.35, ton neutre proche de `UI_HUD`)
plutôt que de réutiliser `UI_VOILE`, calibré pour un voile plein écran quasi opaque et non
pour un chrome léger en cours de partie. Chaque panneau se teinte en **accent** avec
`ACTEURS[i]`, le texte restant en `UI_HUD` neutre : la couleur est un repère de bord, jamais
le porteur de l'information.

### Secours non chromatiques exigés

| Signal | Secours |
|---|---|
| `MENACE` | géométrie plate au sol (acquis) + pulsation d'opacité (candidat) |
| `FLAMME` | volume nettement plus grand que `MENACE` (acquis, prouvé en pixels) |
| identité des 4 joueurs | couvre-chef distinct (**candidat — c'est le trou du brief**) |
| power-ups | couleur + forme + hauteur (acquis, prouvé en pixels) |
| damier des thèmes | alternance par **luminance** garantie, canal indépendant de la teinte (acquis) |
| ramassage | libellé en toutes lettres ; le flash coloré est un renfort, jamais le seul canal |

---

## 5–8 — Déclinaison (extraits ratifiés)

### 7. HUD par joueur — **DÉCISION (b) RATIFIÉE Pierre 2026-08-11**

> **En jeu : vie/mort seulement. Détails complets en PAUSE.**
> Motif inscrit : P2 est une contrainte de lisibilité produit supérieure à l'affichage
> permanent des quatre métriques. `bombes_max`, `rayon` et `cooldown` restent disponibles
> sans encombrer la scène au moment où le danger doit dominer.
> Option écartée : (a) HUD complet permanent — 16 éléments graphiques ajoutés à l'écran en
> cours de partie, en concurrence directe avec la dalle `MENACE` que P2 doit garder première.

ACQUIS mesuré : le HUD est **un** `Label` (`ui_shell.gd:105-109`) pour le **seul joueur 0**,
alors que l'état porte `bombes_max`, `rayon`, `cooldown`, `vivant` pour les quatre. La
vitesse n'est jamais affichée. **1** nœud `ColorRect`, **0** `Polygon2D`.
CANDIDAT : 4 panneaux ancrés à l'**index** de joueur (pas à sa position — un HUD collé à la
position bougerait à chaque tick). Bordure en `ACTEURS[i]`, texte en `UI_HUD` neutre.
**Aucune animation de HUD** tant que la pulsation de `MENACE` n'est pas tranchée : deux
sources de mouvement non coordonnées sont précisément ce que P2 doit empêcher.

### 5. Personnages — trou de vérification nommé
`_identites_jouables()` (`palette.gd:188`) attribue `FORME_CUBE` **en dur** aux 4 acteurs :
l'oracle ne vérifie donc que la **couleur** pour les joueurs, là où il vérifie couleur ET
forme pour les power-ups. Ajouter un couvre-chef sans compléter cette entrée laisserait P1
non vérifié mécaniquement. Câblage candidat = un champ dans une entrée existante, pas un
oracle de plus.
Corps ACQUIS : `0.58 × 0.70 × 0.58`, ratio 1,21:1 — déjà trapu, conforme à la direction A,
rien à changer. Borne dure candidate du couvre-chef : hauteur ≤ 0,40 (sous le plus petit
power-up, 0,46).

### 6. Environnement — déclaration morte confirmée
`MESH_DECOR_VERTICAL` / `gen_pillar_stone_01` : **déclaré `arena_view_3d.gd:34`, jamais
consommé** (2 occurrences dans tout le jeu, dont 1 commentaire). Cas mesuré de
« déclaré ≠ exécuté ».
ACQUIS : le décor ne touche jamais la grille jouable — anneau extérieur, 2 cases sur 3.
P3 tient par construction.

### 8. Standards d'asset — ORACLE EXÉCUTÉ le 2026-08-11 (lecture seule)

L'Asset Geometry Oracle existait et n'avait **jamais tourné** sur ces fichiers. Exécuté sans
inventer aucun seuil :

| Asset | verdict | sommets | min_y | max_y | sha256 (8) |
|---|---|---|---|---|---|
| `gen_crate_wood_01` | **OK** | 24 | 0.000 | 0.80 | `b57c561b` |
| `gen_pillar_stone_01` | **OK** | 96 | 0.000 | 3.00 | `aee2cf9d` |
| `gen_barrel_01` | **OK** | 144 | ~1.2e-08 | 0.90 | `88a2…` |

Commun aux trois : `up_axis: Y`, `measurement_space: gltf_bind_pose`, pivot en base
(`min_y ≈ 0`), `has_material: true`, aucun skin. **3/3 OK.**
`fog` porté par l'oracle lui-même, et conservé tel quel : *« conformité esthétique et
adéquation visuelle non évaluées — jugement Pierre requis »*.
Conséquence pour les budgets : les comptes de sommets **existent** (24 / 96 / 144) ; il
manque uniquement une clé de seuil dans `rules.yaml`. Un budget écrit aujourd'hui resterait
un vœu — non écrit ici, conformément à la consigne « pas de nouveau seuil inventé ».

---

## RÉVISION 2 — 2026-08-11 (décisions Pierre)

Ratifiées et intégrées ici : pulsation de `MENACE` · acteur mort aplati · différenciation des
joueurs par silhouette secondaire · HUD compact par joueur.
Ces quatre entrées quittent l'état CANDIDAT pour l'état **RATIFIÉ, NON IMPLÉMENTÉ**.

### 10. `GENERIC_CLOSURE_ASSET` — fermeture de mort subite (PROPOSÉ)

**Correction de la spécification §2.** Ne pas concevoir un asset de fermeture par thème.
Séparation exigée :

    SÉMANTIQUE GAMEPLAY -> cellule condamnée -> obstacle/danger -> REPRÉSENTATION THÉMATIQUE

Le gameplay ne dépend **jamais** de l'asset employé. Un concept unique,
`GENERIC_CLOSURE_ASSET`, porte l'idée « cette cellule vient d'être condamnée » ; le thème
choisit sa représentation — forêt : arbre tombé · roche : éboulement · eau : masse d'eau ·
gaz : nuage. Ce sont des DIRECTIONS, aucun asset n'est sélectionné.

Contraintes : lisible immédiatement comme un événement de fermeture · jamais un cube
recoloré · compatible grille · ne masque pas la lecture des cellules voisines · aucun
nouveau pipeline · sémantique identique quel que soit le thème.

**Trois états à ne jamais fusionner** — ils vivent sur des plans différents :

| État | Sens | Support |
|---|---|---|
| `MENACE` | danger **annoncé**, réversible | dalle au sol + pulsation (ratifiée) |
| `FLAMME` | mort **immédiate**, transitoire | volume haut |
| **FERMETURE** | condamnation **irréversible** du terrain | `GENERIC_CLOSURE_ASSET` |

P2 tient : la fermeture doit être identifiable **avant ou au moment** où la cellule devient
inaccessible. La représentation thématique ne doit pas effacer cette distinction.

### 11. HUD compact — REMPLACE la spécification à 4 panneaux (RATIFIÉ, NON IMPLÉMENTÉ)

La proposition des quatre panneaux d'angle est **abandonnée**. Le HUD est **une bande
horizontale compacte**, une petite zone fixe par joueur, indexée par joueur (J1..J4) et non
par position dans l'arène.

    | J1 [b][p][v] | J2 [b][p][v] | J3 [b][p][v] | J4 [b][p][v] |

En jeu, par priorité : identifiant joueur · vivant/mort · bonus courants (bombes, portée,
vitesse — les trois déjà portés par l'état). Compact : pas de gros texte, pas de panneau
occupant une part notable de l'écran. La scène et `MENACE` restent prioritaires (P2).
En pause, **le même système** fournit le détail complet — pas de seconde architecture HUD.
**Aucune animation de HUD** tant que la pulsation de `MENACE` n'est pas implémentée et
évaluée. Le HUD reste visuellement stable.

### 12. Identité des joueurs — nouvelle cible (PROPOSÉ)

La triade demi-sphère / prisme / cylindre **n'est plus la solution retenue** : elle reste
comme **preuve** que plusieurs canaux de silhouette sont possibles, rien de plus.
Cible : un **set cohérent de 4 assets** — recherchés ensemble, jamais choisis
indépendamment — compatible avec la direction A. Composition :

    corps cube trapu (commun, inchangé) + silhouette secondaire + couleur joueur

Critères d'évaluation d'un candidat : licence utilisable · cohérence avec A · lisibilité à
distance · silhouette distincte · intégration au corps cube · taille raisonnable · coût
géométrique raisonnable · aucun nouveau pipeline · corps commun conservé · aucune confusion
avec les power-ups.
Contraintes de forme : attaché, non flottant, solidaire du corps, plus petit que les
power-ups (< 0,46), reconnaissable **sans dépendre de la seule couleur**.
La différenciation par **taille de corps** reste refusée, sauf nouvelle décision humaine.

### 13. Consommation par l'oracle existant — MESURÉ, non modifié

    ASSET RÉEL -> IDENTITÉ JOUEUR -> ORACLE EXISTANT -> PREUVE

**MESURÉ** — `06_RUNTIME/adapters/palette/palette.gd` :
- `_identites_jouables()` l.179-189 ; **l.188** attribue `"forme": FORME_CUBE` **en dur** aux
  4 acteurs.
- `categories_couleur_partagee()` l.194 consomme ces identités mais **ne compare que la
  COULEUR** — le champ `forme` des acteurs n'est lu par personne.
- `powerups_identite_partagee()` l.207 est le contrôle **plus dur** (couleur **et** forme)
  mais il itère sur `P.POWERUP_IDS` : **il ne voit jamais les acteurs**.

**Conclusion mesurée** : aucun contrôle existant ne consomme la forme d'un acteur. Donner une
silhouette distincte à chaque joueur sans autre changement produirait une **convention
artistique non vérifiée** — exactement le défaut que P1 doit empêcher.

**Modification minimale nécessaire (PROPOSÉ, non appliquée)** :
1. `palette.gd` l.188 — remplacer `FORME_CUBE` en dur par une entrée d'un tableau
   `FORMES_ACTEURS` parallèle à `ACTEURS`, une forme par joueur.
2. `palette.gd` l.207 — **généraliser la fonction existante** pour qu'elle accepte la liste
   d'identités à contrôler, au lieu de coder `P.POWERUP_IDS` en dur. C'est la modification
   d'une fonction en place, **pas un oracle de plus**.
**Preuve attendue** : le contrôle couleur-ET-forme rend 0 paire partagée sur les 4 acteurs,
et la falsification tient — donner deux fois la même silhouette à deux joueurs doit le faire
rougir.

---

## RÉVISION 3 — 2026-08-12 · MISE EN COHÉRENCE AVEC L'ÉTAT RÉEL

*La direction **A — Jouet de guerre** est inchangée. Cette révision ne décide rien de neuf :
elle remplace des propositions par ce qui est implémenté et mesuré, et nomme ce qui reste
ouvert. Chaque ligne porte son statut.*

### 14. Personnages — la triade « couvre-chef sur cube » est MORTE

**§3 et §12 sont périmés.** La différenciation par couvre-chef posé sur un corps cubique a été
implémentée puis **rejetée au playtest** (« des chapeaux ridicules sur des cubes »). Elle est
supprimée du code, pas seulement dépréciée.

**IMPLÉMENTÉ** — quatre personnages 3D complets, un `.glb` par joueur, produits par l'archétype
`soldier` unique de `scripts/forge/asset_producer/build_asset.py` (corps et proportions écrits
UNE fois ; seuls casque et accessoire varient — c'est ce qui en fait un set) :

| joueur | asset | rôle visuel | sommets | dims X/Y/Z |
|---|---|---|---|---|
| J1 blanc | `gen_soldier_scout_01.glb` | éclaireur — casque rond, oreillettes, radio + antenne | 844 | 0.580 × 0.799 × 0.348 |
| J2 rouge | `gen_soldier_assault_01.glb` | assaut — casque anguleux, crête, épaulières | 648 | 0.595 × 0.836 × 0.398 |
| J3 bleu | `gen_soldier_tech_01.glb` | technicien — barre de visée, lampe, module dorsal | 820 | 0.580 × 0.782 × 0.413 |
| J4 jaune | `gen_soldier_demo_01.glb` | démineur — large bord, bavolet, sacoche | 868 | 0.580 × 0.822 × 0.430 |

Volumes communs à l'escouade : cou · épaules · ceinture · harnais · bras en deux segments ·
revers de bottes · bordure de casque · sac dorsal. Écart de hauteur du set : **0,054 m**.
Le `.glb` porte la FORME, `palette.gd` porte la LECTURE (surface 0 = corps, surface 1 = accent).

**Le corps `0.58 × 0.70 × 0.58` de §5 n'existe plus** comme personnage ; il ne survit que comme
repère de gabarit.

**UNKNOWN — qualité visuelle V2 : playtest humain non effectué.** Aucune modification des
personnages n'est autorisée avant ce playtest (GO Pierre du 2026-08-12, point 4).

### 15. Vocabulaire de silhouette — séparé des primitives

`FORMES_ACTEURS` (valeurs `FORME_*`) est remplacé par `SILHOUETTES_ACTEURS` (valeurs 100-103).
L'écart de numérotation est délibéré : une silhouette d'acteur est un personnage 3D complet,
une `FORME_*` est une primitive de rendu. Les confondre rouvrirait la porte au « chapeau sur
un cube ». **IMPLÉMENTÉ · TESTED** — `acteurs_identite_partagee() == 0`, falsification vérifiée.

### 16. Décisions de la révision 2 — état réel

| Entrée | §  | État au 2026-08-12 |
|---|---|---|
| Pulsation `MENACE` (opacité, sans shader) | 2 | **IMPLÉMENTÉ · TESTED** — fonction pure du tick, alpha 0,45→0,90, période 12 ticks |
| Acteur mort aplati | 2 | **IMPLÉMENTÉ · TESTED** — `ECRASEMENT_MORT = 0.14`, jamais supprimé |
| HUD compact J1–J4 | 11 | **IMPLÉMENTÉ · TESTED** — bande horizontale indexée par joueur, détail en pause, même système |
| `GENERIC_CLOSURE_ASSET` | 10 | **IMPLÉMENTÉ · TESTED** — dérivé de l'état existant, forme non cubique par thème, hauteur 0,85 < mur |
| Différenciation par silhouette | 12 | **REMPLACÉ** par la §14 ci-dessus |

### 17. Trois états — séparation tenue et mesurée

```
MENACE     dalle y=0.03, h=0.06, alpha PULSÉE       annoncé,   réversible
FLAMME     volume 0.9 × 0.55 × 0.9 à y=0.30         immédiat,  transitoire
FERMETURE  volume h=0.85, forme NON cubique         condamné,  irréversible
```

Chaîne respectée : `sudden_death.gd` solidifie la cellule et n'apprend rien de la palette. La
distinction fermeture / mur permanent est **dérivée** d'une empreinte prise à la construction —
aucun état parallèle, donc le gameplay ne peut pas dériver de l'habillage.

### 18. Budgets et seuils — toujours AUCUN

Les comptes de sommets (24 · 96 · 144 pour le décor, 648 → 868 pour les personnages) restent
des **mesures**, pas des budgets. `rules.yaml` ne porte toujours aucun seuil de polygones, et
`§8` reste vrai sur ce point. Le `fog` de l'oracle est inchangé : *conformité esthétique et
adéquation visuelle non évaluées — jugement Pierre requis*.

### 19. Coût de rendu — mesuré, et ce que la mesure NE dit pas

Frame réelle, arène 15×13, fenêtre GPU, V-Sync désactivé, une reconstruction par image :

| fermeture | sans cache de ressources | avec cache | gain |
|---|---|---|---|
| 0 bloc | 4,76 ms (210 fps) | 1,67 ms (600 fps) | −65 % |
| 71 blocs | 6,06 ms (165 fps) | 2,05 ms (487 fps) | −66 % |
| **143 blocs (max)** | **6,99 ms (143 fps)** | **2,15 ms (465 fps)** | **−69 %** |

**Ce que cela ne prouve pas** : même SANS cache, la frame tenait dans le budget 60 fps sur ce
poste. Le cache est un gain réel, il **n'explique pas à lui seul** le ralenti ressenti au
playtest. Cause du ralenti : **UNKNOWN**, hypothèse non close.

### 20. Ce qui reste ouvert

- **Qualité visuelle V2** — playtest humain requis, aucune retouche avant.
- **Cause du ralenti ressenti** — non identifiée ; le coût de rendu seul ne l'explique pas.
- **Suicide du bot par sa propre bombe** — diagnostiqué, non corrigé (voir §21).
- **Collision rouge J2 / rouge `MENACE`** — toujours non mesurée en pixels côte à côte (§4).
- **Résidu de blocage carte 2** — 145 ticks sur 5 graines, non diagnostiqué.

### 21. Bot — désengagement acquis, suicide diagnostiqué non corrigé

**IMPLÉMENTÉ** : un bot ne peut plus choisir sa propre case comme cible de routage
(`bot_policy.gd::_cap`). Blocage mutuel J2/J4 mesuré sur 15 runs : **10 058 → 950 ticks
(−90,6 %)**, pire épisode 26,5 s → 2,7 s.

**DIAGNOSTIQUÉ, NON CORRIGÉ** — le bot se tue avec sa propre bombe. Mesure sur deux graines,
séquence identique :

```
POSE t=3598 en (13,3)   issue_pour_soi = true   cases_sures_apres = 1
                        mèche = 150 ticks
                        mort subite MAINTENANT = false
                        mort subite À ÉCHÉANCE  = true
mort t=3747 en (12,3)   immobile 30+ ticks · cases_sures = 0 · refuge = sa propre case
```

**Cause nommée** : `issue_pour_soi` est évalué **au présent**, alors que la mèche dure 150 ticks
pendant lesquels la mort subite condamne l'unique case de repli. Le plan d'évasion était valide
quand il a été fait, invalide quand il a servi. Le `AUCUNE` final n'est pas le défaut : c'est la
branche « fuite » qui fonctionne correctement sans aucune option.

Ce défaut **préexistait** (3 suicides sur 18 runs sans le correctif) ; le correctif de
désengagement en a augmenté la fréquence (**6 sur 18**) en changeant les trajectoires.
Correction hors périmètre du GO du 2026-08-12.

---

## RÉVISION 3 — 2026-08-11 · BASELINE V3 (décision Pierre)

### 14. Personnages — le corps cube est REMPLACÉ

**La spécification « corps cube commun + silhouette secondaire » des §3 et §12 est CADUQUE.**
Elle n'est pas supprimée du document — elle reste lisible comme l'étape qui a mené ici — mais
elle ne décrit plus la cible. Ne pas y revenir.

**Baseline V3, IMPLEMENTED et MESURÉ** : quatre soldats 3D complets remplacent les cubes.

| Asset | oracle géométrie | sommets | hauteur |
|---|---|---|---|
| `gen_soldier_assault_01` | **OK** | 648 | 0.836 |
| `gen_soldier_demo_01` | **OK** | 868 | 0.822 |
| `gen_soldier_scout_01` | **OK** | 844 | 0.799 |
| `gen_soldier_tech_01` | **OK** | 820 | 0.782 |

Commun aux quatre : **pivot en base** (`min_y = 0.000`), `up_axis: Y`, **4/4 OK**.
Set cohérent produit en interne — aucune dépendance externe, aucune licence à arbitrer.

**Consommation runtime PROUVÉE**, et c'est ce qui distingue V3 d'une convention artistique :
- `arena_view_3d.gd` référence `gen_soldier` **4×** — les assets sont consommés, pas
  seulement déclarés.
- `palette.gd:284` — `"forme": silhouette_acteur(i)`. Le `FORME_CUBE` codé en dur a disparu.
  Le trou nommé au §13 est **fermé** : la silhouette de chaque joueur est désormais une
  propriété que le contrôle couleur-ET-forme peut vérifier, plus une intention.
- Suite mécanique : **584 assertions vertes** (contre 462 avant V3).

Ce qui reste **UNKNOWN** : la qualité artistique perçue. Elle se juge en playtest, par Pierre.
Aucun oracle ne la mesure et aucun ne le prétend.

### 15. R9 — la garde `voisin == depart` est REJETÉE (mesure)

    avec la garde   R9 = 5/20        sans la garde   R9 = 7/20
    584 tests verts dans les deux cas

Retirée sur arbitrage Pierre. Sa cause était réelle — le gel en face-à-face — mais corriger
un comportement réel ne suffit pas à conserver une mutation qui dégrade l'unique mesure
produit. **Le gel reste une anomalie connue, pas un problème résolu.**
Détail et attribution : `knowledge_base/proposals/forge.proven_cause_is_not_a_mandate.yaml`.

### 16. ARENA_ART_V3 — DOCUMENTED_ONLY, non lancé

Le plateau reste un prototype technique pendant que les pièces sont devenues bonnes.
Règle posée pour cette passe : **un kit cohérent vaut mieux qu'une collection de beaux assets
indépendants.** À produire ensemble, même direction, même échelle, même niveau de détail :
sol · murs · protections · obstacles · débris · éléments périphériques · éclairage et
signalétique · destructibles.
La grille reste le squelette gameplay ; elle ne doit plus être **perceptible** comme rendu
final. Aucune règle de grille ni aucun oracle n'est touché par cette passe.
