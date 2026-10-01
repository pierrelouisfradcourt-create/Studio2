# Dungeon 666 sous Godot — règles de portage de la simulation

`statut_artefact : PROPOSED` · décision de Pierre du 2026-10-01 : « une version plus propre sur Godot ».

La simulation web `GAMES/dungeon_666/src/sim/*.mjs` est la **spécification exécutable**. Ce
projet la **porte**, module par module, sans rien redessiner des règles. Le portage est jugé par
une machine : la partie Godot rejoue des parties notées côté web et doit retrouver les mêmes
états, **au bit près** (`parite/`, `bash outils/verifier.sh`). Toute liberté prise avec la
référence se paie par une divergence.

## 1. Un module JavaScript = un script GDScript

| JavaScript | GDScript |
|---|---|
| `src/sim/<module>.mjs` | `sim/<module>.gd`, `class_name D6<ModuleEnPascal>`, `extends RefCounted` |
| `src/core/rng.mjs` | `sim/rng.gd`, `D6Rng` (déjà porté) |
| `src/core/math.mjs` | `sim/geo.gd`, `D6Geo` (déjà porté ; `clamp` → `clampv`, `lerp` → `lerpv`, `len` → `length`) |
| `config.mjs` (code), `kits`, `foe_data`, `boss_data`, `town_data` | `sim/data.gd`, `D6Data` + `data/*.json` (déjà fait) |

Noms de classes : `state` → `D6State`, `kit_common` → `D6KitCommon`, `boss_charon` → `D6BossCharon`,
`ai_common` → `D6AiCommon`, `calm_rooms` → `D6CalmRooms`, `foe_elites` → `D6FoeElites`, etc.

- **Fonctions** : `static func`, même ordre d'arguments, nom en snake_case dérivé mécaniquement
  (`damageEnemy` → `damage_enemy`, `floorInfo` → `floor_info`, `newId` → `new_id`). Une fonction
  NON exportée du module JavaScript prend un tiret bas : `_tick_statuses`. Une fonction exportée
  garde son nom public : les autres modules l'appellent `D6Combat.damage_enemy(...)`.
- **L'état est fait de dictionnaires et de tableaux**, avec EXACTEMENT les clés JavaScript
  (camelCase) : `game.player.x`, `e.stateTime`, `game.rng.combat`. On y accède par le point.
  Pas de classes d'entités : l'état doit rester comparable clé par clé à celui du web.
- **Constantes de module** non exportées (`const BURN_TICK = 0.25`) : `const BURN_TICK := 0.25`.
- **Tables de données exportées** (`BOONS`, `ROSTER`, `LAYOUTS`, `LAB_AXES`…) : jamais recopiées à
  la main, lues dans `D6Data.tables().<module>.<NOM>` (liste : `data/tables.json`). Partagées :
  ne pas les modifier ; `D6Js.clone(x)` avant d'écrire dans une copie.
- **Réglages** : `game.tuning` (dictionnaire). `D6Data.DT`, `D6Data.DEG`, `D6Data.SIM_HZ`.
- **Commentaires** : ceux du JavaScript sont repris (en français), en tête de script une ligne
  « portage de src/sim/<module>.mjs ». Fonctions de plus de 50 lignes : à découper (une fonction
  par état d'une machine à états, par exemple) sans changer l'ordre des effets.

## 2. Les pièges JavaScript → GDScript (chacun a déjà coûté une divergence quelque part)

1. **Tout nombre est un float.** JavaScript n'a que des doubles ; toutes les données décodées
   sont des floats. Écrire les littéraux avec un point (`2.0`, `0.5`), sinon `1 / 2` vaut 0.
   On ne passe en entier que pour indexer : `arr[int(i)]`, `for i in range(int(n))`.
   Les compteurs (ids, `tick`, `comboIndex`) restent des floats ou des ints, peu importe, tant
   qu'aucune division entière ne s'y glisse.
2. **`Math.round` → `D6Js.jround`** (la demie monte toujours). `Math.floor` → `floorf`,
   `Math.ceil` → `ceilf`, `Math.abs` → `absf`, `Math.max(a, b)` → `maxf(a, b)` (emboîter au-delà
   de deux), `Math.min` → `minf`, `x ** 2` → `x * x`, `a % b` sur des floats → `fmod(a, b)`.
   `Math.sqrt` → `sqrt`. **Jamais** `sin`, `cos`, `atan2`, `asin`, `exp`, `pow` natifs : leur dernier
   bit diffère entre Godot et JavaScript. La simulation web passe par `src/core/trig.mjs`
   (`TRIG.sin`…), le portage par `D6Trig.sin`, `D6Trig.cos`, `D6Trig.atan2`, `D6Trig.asin`,
   `D6Trig.exp`, `D6Trig.pow` : mêmes opérations, mêmes bits.
3. **Clé absente.** `e.invuln` sur une clé absente est une ERREUR en GDScript, alors que
   JavaScript rend `undefined` (et `undefined > 0` est faux). Pour tout champ que le module ne
   crée pas lui-même à la naissance de l'objet : `e.get("invuln", 0.0)`. `a ?? b` → `D6Js.nz(a, b)`
   ou `d.get("k", b)`. `a?.b` → tester `a != null` d'abord.
4. **Vrai / faux.** `if (x)` sur un nombre, un texte ou un objet : écrire la comparaison
   (`x != 0.0`, `x != ""`, `x != null`), ou `D6Js.truthy(x)` en cas de doute. `!!x` → `D6Js.truthy(x)`.
5. **Identité d'objet.** `a === b` entre deux objets → `is_same(a, b)` : en GDScript, `==` compare
   deux dictionnaires PAR VALEUR.
6. **Tri.** `Array.sort` de JavaScript est STABLE, `sort_custom` de Godot ne l'est pas : à
   égalité, départager par le rang d'origine.
7. **Parcours pendant modification.** `for (const e of game.enemies)` voit les éléments ajoutés
   pendant la boucle. Reproduire avec une boucle à index (`while i < arr.size()`).
8. **Fermetures.** Une lambda GDScript capture les variables locales PAR VALEUR : pour modifier
   un compteur depuis une lambda, passer par un dictionnaire ou un tableau.
9. **Tables de fonctions** (`AI[e.kind]`, modèles de Gardien, `ZONES`) : dictionnaire de
   `Callable` rendu par une fonction statique (`static func _ai() -> Dictionary`), ou `match`.
10. **Objets partagés de module** (`const result = {...}` dans physics, `navOut`) : `static var`.
11. **Ensembles** (`new Set([...])`) : tableau + `in`, ou dictionnaire `{clé: true}`.
12. **Clés numériques.** `reinforcements[2]` en JavaScript lit la clé « 2 ». Les clés des
    données sont des TEXTES : `d[D6Js.num_str(phase)]`.
13. **Texte.** Un nombre dans un texte : `D6Js.num_str(x)` (50, pas 50.0).
14. **Copies.** `structuredClone(x)` → `D6Js.clone(x)` ; `{ ...a, ...b }` → `a.duplicate()` puis
    `merge(b, true)` ; `[...a, ...b]` → `a + b` ; `arr.length = 0` → `arr.clear()`.
15. **Mots réservés.** `super`, `class`, `trait`, `signal`… ne passent pas par le point :
    `t["super"]`, `p["class"]`.
16. **Méthodes de tableau** : `push` → `append`, `includes` → `has`, `indexOf` → `find`,
    `filter` / `map` / `some` / `every` → `filter` / `map` / `any` / `all`, `find` → boucle.

## 3. Ce qui est interdit

- Lire `randf`, `randi`, l'horloge, ou tout état hors de `game` : la partie doit être rejouable.
- « Améliorer » une règle, un ordre d'évaluation, une formule, un nom de clé. Un défaut vu dans
  la référence se signale ; il se corrige d'abord côté web, puis se porte.
- Toucher à un nœud, une scène, un signal dans `sim/` : la simulation ne connaît pas Godot.

## 4. Vérifier

```
G=C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe
"$G" --headless --path . --import                                  # après tout NOUVEAU fichier .gd (enregistre les class_name)
"$G" --headless --path . --check-only --script res://sim/<module>.gd   # le script se lit-il ?
"$G" --headless --path . --script res://tests/run_tests.gd          # vecteurs + données
```

Fonctions PURES d'un module : ajouter leurs vecteurs côté web dans
`GAMES/dungeon_666/tools/vecteurs/<lot>.mjs` (modèle : `socle.mjs`), les exporter par
`node tools/export_godot.mjs vecteurs`, et leurs adaptateurs dans `parite/adaptateurs/<module>.gd`
(modèle : `geo.gd`). Le nom du module de vecteurs est celui du module JavaScript.
