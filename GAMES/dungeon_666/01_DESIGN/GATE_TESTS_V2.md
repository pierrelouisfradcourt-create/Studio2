# Gate Pierre demandée : tests existants contredits par la spec V2

`statut : EN ATTENTE DE GATE` · rien de ce qui suit n'est appliqué.

## Pourquoi cette demande

La spec V2 change deux règles que plusieurs tests encodent en dur :

1. **Un Gardien tous les 18 étages** (37 sections), au lieu de tous les 6.
2. **À la mort, les bonus temporaires sont remis à zéro.** Avant, le build était figé au Gardien (instantané) ; « Réessayer le Gardien » rejouait le combat avec le build d'entrée.

La règle du studio (`.claude/rules/tests.md`, régime `create_allowed_modify_denied`) interdit de modifier un test qui existait avant la passe sans ta gate explicite. Ces tests ne sont donc **pas modifiés**. Ils **échouent**, et `run-oracle.mjs` les signale comme « en conflit avec la spec V2 ». Ils ne sont ni masqués ni sautés.

La couverture qu'ils apportaient est **recréée pour la V2 dans des fichiers de tests neufs** (`tests/v2_*.test.mjs`) : Gardien à l'étage 18, checkpoint 19, alerte de l'anneau, gel sur le Gardien…

## Tests en échec, et réécriture minimale proposée

| # | Fichier · test | Ce qui casse | Réécriture minimale proposée |
|---|---|---|---|
| 1 | `logic` · « 666 étages : 111 sections de 6, Gardien au 6e étage de chaque section » | Attend 111 Gardiens et un Gardien à l'étage 6. | Attendre `total / sectionLength` (37). `floorInfo(t, 18).isBoss`. `floorInfo(t, 19).indexInSection === 1`. Le reste ne change pas (étage 666 final, Cercle 9 à 648, finale à 649). |
| 2 | `logic` · « portes : l'étage 5 mène au Gardien, l'antichambre propose marchand ou autel » | Numéros d'étage en dur (5 et 6). | Faire le même test avec les étages 16 et 17 : nettoyer l'étage 16 donne les portes `event`/`shop`, entrer à l'étage 17 donne la porte `boss`. Ou lire les index dans `tuning.section`. |
| 3 | `logic` · « checkpoint : vaincre un Gardien fige le build ; mourir ensuite le restaure » | Contredit la règle V2 (plus de build figé). | Le remplacer par la règle inverse : vaincre le Gardien de l'étage 18 ouvre le checkpoint 19. Mourir ensuite **vide** les bénédictions et garde l'équipement et les Âmes. Ce test existe déjà sous forme neuve dans `tests/v2_loop.test.mjs`. |
| 4 | `logic` · « Gardien vaincu : ses impacts en attente et ses orbes en vol ne blessent plus » | `createGame({ startFloor: 6 })` n'a plus de Gardien. | Remplacer `startFloor: 6` par `startFloor: 18`. |
| 5 | `logic` · « réessayer le Gardien : retour à l'entrée de sa salle avec le build d'entrée » | La V2 retire « Réessayer le Gardien » : il gardait le build temporaire. | Supprimer le test. L'entraînement en Ville (« Défier un Gardien », sans récompense ni build) couvre le besoin de répéter un boss ; il est testé dans les fichiers neufs. |
| 6 | `logic` · « relance de l'appli au checkpoint : même build que la reprise après une mort » | Contredit la règle V2 (instantanés supprimés). | Le remplacer par : relancer au checkpoint donne zéro bénédiction et le même équipement et la même classe que le profil. |
| 7 | `feel_review` · « anneau du Gardien : le cercle d'alerte reste affiché entre les vagues » | `bossIn` utilise `startFloor: 6`. | `startFloor: 18` dans `bossIn` (une seule ligne, l. 77). |
| 8 | `feel_review` · « invocation du Gardien : alerte marquée inoffensive » | Idem. | Idem (même ligne). |
| 9 | `feel_review` · « gel d'impact sur le Gardien : plafonné par le tuning… » | Idem. | Idem (même ligne). |
| 10 | `properties_strict` · « (k) invariants stricts — sections complètes du bot skilled » | La couverture exige un boss avant l'étage 6. | `SECTION_FLOORS = 18`. `SECTION_TICK_CAP` = 30 min de sim. |
| 11 | `properties_strict` · « (k bis) … départ dans chaque type de salle (étages 2 à 6) » | L'étage 6 n'est plus la salle du boss. | `RANDOM_START_FLOORS = [2, 3, 9, 17, 18]` (combat, mi-section, antichambre, Gardien). |
| 12 | `properties_strict` · « (l) le run qui bat la section 1 a réellement tué le boss » | Une section de 6 étages n'a plus de boss. | `SECTION_FLOORS = 18`. `PLAYABILITY_MINUTES = 30`. |

## Tests qui passent encore mais ne prouvent plus leur intention

Ce sont des tests creux. Je les signale, je ne les modifie pas.

- `properties` · « (e) oracle de jouabilité : le bot skilled bat la section 1 (étage 7) » : il passe en atteignant l'étage 7, qui n'est plus la fin de la section. Proposition : `SECTION_FLOORS = 18` et `SECTION_MINUTES = 30`.
- `properties_strict` · « (m) chaque disposition (boss compris)… » : il échantillonne l'étage 6 sous le nom « boss », mais ce n'est plus une salle de boss. Proposition : `BOSS_FLOOR = 18`.
- `logic` · « checkpoint : battre le Gardien de l'étage 6 ouvre la reprise à l'étage 7 » : il passe, car la fonction est pure (`bossFloor + 1`), mais 6 n'est plus un étage de Gardien. Proposition : 18 → 19.

## Ce que je te demande

Un « oui » ou un « non » par ligne (ou un « oui » global) pour appliquer ces réécritures dans les fichiers protégés. Sans gate, ils restent tels quels et en échec, et le rapport de fin de passe les classe `BLOCKED`.
