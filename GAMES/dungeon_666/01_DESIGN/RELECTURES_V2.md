# Dungeon 666 — relectures adversariales de la V2 (reprise du 2026-10-01)

`statut_artefact : PROPOSED` · rien n'est ratifié. Ce fichier existe parce que les constats des
relectures de la passe précédente n'avaient été écrits nulle part : ils ont été perdus à la
clôture, il a fallu relancer les relectures. Chaque constat a ici son statut et sa preuve.

État de sortie : `node run-oracle.mjs` VERT — 260 tests, solvabilité, classes, e2e 39/39.
Chaque test neuf a été rejoué sur le code d'avant correction : il y échoue.

## Lot CLASSES

| Constat | Mesure avant | Correction | Mesure après | Garde |
|---|---|---|---|---|
| Hache et Maillet maintenus sur place étourdissent en boucle | Maillet : 0 coup de brute reçu en 30 s | **Garde** : 1,5 s après un étourdissement, un coup d'arme ne ré-étourdit plus (`combat.stunGuard`) ; écu dessiné au bout de la barre de vie | Maillet 8,0 coups, Hache 13,9 (Lame : 15,0) | `tests/v2_classes.test.mjs`, `tools/classes.mjs` |
| La Chasseresse se passe du dash | Sans dash : 66 % (arc) et 61 % (arbalète) des dégâts de l'étalon ; elle recule de 185 u/s en tirant, un diablotin court à 150 | Vitesse en tirant (`moveMult` 1,1 → 0,6 ; 0,8 → 0,4) et recul des tirs réduit | Sans dash : 94 % et 87 % de l'étalon | idem |

Reste à juger en main (D11) : la Chasseresse bien jouée ne prend presque rien (0,3 dégât par
salle contre 2,7 pour le Revenant) ; les diablotins restent tenus à distance par le RECUL du
Maillet (2,1 coups en 30 s) ; le Bourreau qui martèle sans lire tient jusqu'à l'étage 15.

## Lot ÉTAGES

| # | Constat | Statut |
|---|---|---|
| 1 | La jauge de Super ne suivait pas l'arme : 90 coups pour un Super à l'étage 1, 3 à l'étage 649 ; 43 % du temps en Super en section 37 | **Corrigé** (`combat.mjs`). Après : 5 à 9 % à toute profondeur. Test `v2_etages_relecture`. |
| 2 | Victoire au 666 : écran sans issue, « checkpoint » posé sur le Gardien final | **Corrigé** (`run.mjs`, `ui/menus.mjs`). Vérifié en navigateur. Test. |
| 3 | Salle d'élite : champion hors du bestiaire de l'étage (Pyromancienne à l'étage 2) | **Corrigé** (`room.mjs`). Test sur 300 graines. |
| 4 | Valeurs plates et or laissés derrière par le scaling (Festin 2 PV = 0,1 % des PV au 649 ; bourse de chambre forte dominée par le recyclage) | **À Pierre** — économie (D10). |
| 5 | « Méditer » sur Envol donnait 3,5 charges de dash | **Corrigé** (`calm_rooms.mjs`, `stats.mjs`). Test. |
| 6 | Chambre forte : la bourse annonçait un montant et en versait un autre (89 % des coffres) | **Corrigé** (`calm_rooms.mjs`). Test sur 60 graines. |
| 7 | `?floor=abc` plantait la sim ; le repli de `main.mjs` pouvait remplacer le profil | **Corrigé** : étage illisible = étage 1 ; un profil n'est remplacé qu'après archivage. README mis à jour. Test + navigateur. |
| 8 | Mort après une téléportation en arrière : reprise imposée au checkpoint le plus profond | **À Pierre** — choix de design (pilier 5). |

## Lot BESTIAIRE

| # | Constat | Statut |
|---|---|---|
| 1 | Champion d'élite hors bestiaire | **Corrigé** (même correction que Étages 3). |
| 2 | Archer et Pyromancienne inertes derrière un obstacle (fuite et approche s'annulaient) | **Corrigé** : on ne fuit que ce qu'on voit. Test `v2_bestiaire_relecture`. |
| 3 | Invocations « fermées » : or de Main avide sans fin tant que l'invocateur vit | **Corrigé** pour l'or. Les soins au kill sur invocation restent : **à Pierre** (toucherait aussi les renforts des Gardiens). |
| 4 | L'arène d'essai ne montre jamais le Nécromancien ni les trois champions V2 | **À Pierre** (le test existant fige « étage de début de section »). |
| 5 | La flaque brûle toutes les 1,0 s au lieu de 0,5 s (l'invulnérabilité après coup avale un tick sur deux) | **À Pierre** — réglage. |
| 6 | Le disque de contact du Bélier et du Diablotin déborde parfois le télégraphe (4 coups sur 354) | **Ouvert** — cause non isolée. |
| 7 | Le souffle d'un élite ardent frappait après « salle nettoyée » | **Corrigé** (`run.mjs`). Test. |
| 8 | `burnDps` jamais remis à zéro | **Corrigé** (`enemies.mjs`). Test. |

Observé en passant, non corrigé : étourdir un ennemi pendant sa récupération lui fait sauter sa
recharge (il ré-attaque plus tôt que si on ne l'avait pas étourdi).

Scripts de reproduction des relectures : hors dépôt (dossier de travail de la session du
2026-10-01). Les tests ci-dessus en sont la forme durable.

## Portage Godot (2026-10-01) : ce que le portage a fait remonter

Décision de Pierre : « une version plus propre sur Godot ». La simulation web reste la
spécification ; la version Godot (`GAMES/dungeon_666_godot/`) la rejoue et doit retrouver les
mêmes états AU BIT PRÈS (`bash outils/verifier.sh` : 44 parties, 7 373 points de contrôle).

Changement fait côté web pour rendre cette égalité possible : la simulation ne calcule plus ses
sinus, cosinus, arcs tangentes, exponentielles et puissances par `Math.*` (dont le dernier bit
change d'un moteur à l'autre) mais par `src/core/trig.mjs`, écrit avec les seules quatre
opérations. Effet de bord utile : une partie est désormais identique quel que soit le navigateur.

Défauts de la spécification vus en portant, **portés tels quels, non corrigés** (à trier) :

| Où | Constat |
|---|---|
| `combat.mjs`, recul | `if (kb * kb > cur2)` : deux tirs de même recul à la même image se départagent au dernier bit (tir roulé de l'arc, éventail de l'arbalète). Sans effet depuis `trig.mjs`, mais fragile. |
| `player.mjs` | `comboIndex` n'est pas remis à zéro au changement d'arme : passer d'une arme à 3 coups à une arme à 2 coups et attaquer dans les 0,32 s planterait. Non reproduit en partie réelle. |
| `run.mjs`, Gardien vaincu | Les portes s'ouvrent tout de suite alors qu'un butin vient d'être posé : on peut partir sans le prendre. |
| `run.mjs`, autel `bloodBoon` | Force la rareté « rare » même si le tirage était épique ; reste proposé à 1 PV. |
| `run.mjs`, `prepareDoors` | Après 20 tirages identiques, deux portes peuvent porter la même récompense. |
| `game.mjs`, `createGame` | `starterItems` consomme deux identifiants à chaque partie, même quand le profil a déjà son équipement. |
| `profile.mjs`, `buyUpgrade` | Répond « niveau maximal » pour une amélioration inconnue. |
| `profile.mjs`, `sanitizeProfile` | Ne vérifie ni le type ni l'unicité des `uid` des objets. |
| `profile.mjs`, `stashPush` | À scores égaux, c'est toujours le plus ancien objet du coffre qui part. |
| `boons.mjs`, `loot.mjs` | Les textes disent « la Lance » quelle que soit la compétence équipée. |
| `boss_charon.mjs`, charge | Au mur, l'état passe à « stunned » sans remettre `patternStep` / `patternT` à zéro. |
| `boss_minos.mjs`, `sweep` | Un tirage aléatoire consommé pour rien en phase 2 et plus. |
| `boss_colosse.mjs`, `geoliers` | L'appel de la phase est consommé même si aucun point d'apparition n'est trouvé. |
| `physics.mjs` | Les obstacles sont résolus après les murs, sans re-bornage ; la ligne de vue échantillonne tous les 16 u. |
| `combat.mjs` | `damageDealt` compte l'overkill, alors que la jauge de Super l'exclut. |
