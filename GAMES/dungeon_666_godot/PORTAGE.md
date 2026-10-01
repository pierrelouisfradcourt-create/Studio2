# Dungeon 666 sous Godot — conventions de code de `sim/`

> Histoire : `sim/` est né comme le portage, module par module et au bit près, de la simulation web
> (`GAMES/dungeon_666/src/sim/*.mjs`) ; ce fichier en était le règlement. Depuis le 2026-10-01,
> Godot est la source des règles : ce qui suit n'est plus une consigne de fidélité au web, ce sont
> les conventions du code existant — à suivre pour que `sim/` reste un seul style. Voir
> `parite/LISEZ_MOI.md`.

`statut_artefact : PROPOSED`. Une règle se change ici, dans `sim/` et `data/` ; ses gardes sont
`tests/regles/` et `references/` (`README.md`, « Changer une règle »).

## 1. Forme du code

- **Un module = un script** `sim/<module>.gd`, `class_name D6<ModuleEnPascal>`, `extends RefCounted` :
  `state` → `D6State`, `kit_common` → `D6KitCommon`, `boss_charon` → `D6BossCharon`,
  `ai_common` → `D6AiCommon`, `calm_rooms` → `D6CalmRooms`. Socle : `D6Rng` (aléatoire), `D6Geo`
  (géométrie), `D6Trig` (trigonométrie), `D6Js` (arrondis, entiers 32 bits, copies), `D6Data` (données).
- **Fonctions** : `static func`, snake_case. Une fonction interne au module prend un tiret bas
  (`_tick_statuses`) ; une fonction que d'autres modules appellent n'en prend pas
  (`D6Combat.damage_enemy(...)`). Plus de 50 lignes : découper (une fonction par état d'une
  machine à états, par exemple) sans changer l'ordre des effets.
- **L'état est fait de dictionnaires et de tableaux**, clés en camelCase : `game.player.x`,
  `e.stateTime`, `game.rng.combat`. On y accède par le point. Pas de classes d'entités : l'état
  doit rester copiable (`D6Js.clone`), comparable clé par clé et lisible par une empreinte
  (`references/partie.gd`, `digest`). Les vues de `jeu/` lisent ces mêmes clés.
- **Constantes de module** : `const BURN_TICK := 0.25`, nommées, avec leur unité en commentaire.
- **Tables de données** (`BOONS`, `ROSTER`, `LAYOUTS`, `LAB_AXES`…) : jamais recopiées dans le
  code, lues dans `D6Data.tables().<module>.<NOM>`. Partagées : ne pas les modifier ;
  `D6Js.clone(x)` avant d'écrire dans une copie.
- **Réglages** : `game.tuning` (dictionnaire, copie de `D6Data.default_tuning()`). `D6Data.DT`,
  `D6Data.DEG`, `D6Data.SIM_HZ`. Un nombre réglable vit dans `data/`, pas dans le code.
- **Commentaires** en français ; en tête de script, une ligne qui dit ce que fait le module.

## 2. Les pièges (chacun a déjà coûté une erreur)

1. **Tout nombre est un float.** Toutes les données lues par `D6Data` sont des floats. Écrire les
   littéraux avec un point (`2.0`, `0.5`), sinon `1 / 2` vaut 0. On ne passe en entier que pour
   indexer : `arr[int(i)]`, `for i in range(int(n))`. Les compteurs (ids, `tick`, `comboIndex`)
   restent des floats ou des ints, peu importe, tant qu'aucune division entière ne s'y glisse.
2. **Arrondis.** `D6Js.jround` : la demie monte toujours (`roundf(-2.5)` rendrait -3). `floorf`,
   `ceilf`, `absf`, `maxf(a, b)` (emboîter au-delà de deux), `minf`, `x * x` plutôt qu'une
   puissance, `fmod(a, b)` sur des floats, `sqrt`.
3. **Trigonométrie : `D6Trig`, jamais les natifs.** `sin`, `cos`, `atan2`, `asin`, `exp`, `pow`
   natifs n'ont pas le même dernier bit d'une machine, d'un compilateur ou d'une version de Godot
   à l'autre. `D6Trig.sin`, `D6Trig.cos`, `D6Trig.atan2`, `D6Trig.asin`, `D6Trig.exp`,
   `D6Trig.pow` ne font que des additions, multiplications et divisions : mêmes bits partout.
   C'est ce qui permet aux références de comparer des parties **au bit près**.
4. **Clé absente.** `e.invuln` sur une clé absente est une ERREUR. Pour tout champ que le module
   ne crée pas lui-même à la naissance de l'objet : `e.get("invuln", 0.0)`, ou `D6Js.nz(a, b)`
   (`b` si `a` est null). Tester `a != null` avant `a.b`.
5. **Vrai / faux.** Sur un nombre, un texte ou un objet, écrire la comparaison (`x != 0.0`,
   `x != ""`, `x != null`), ou `D6Js.truthy(x)` quand la valeur peut être de plusieurs types
   (null, false, 0, NaN et "" sont faux).
6. **Identité d'objet.** `==` compare deux dictionnaires PAR VALEUR ; « est-ce le même objet ? »
   s'écrit `is_same(a, b)`.
7. **Tri.** `sort_custom` n'est pas stable : à égalité, départager par le rang d'origine.
8. **Parcours pendant modification.** Si la boucle doit voir les éléments ajoutés pendant le
   parcours (ennemis invoqués), boucle à index (`while i < arr.size()`).
9. **Fermetures.** Une lambda capture les variables locales PAR VALEUR : pour modifier un compteur
   depuis une lambda, passer par un dictionnaire ou un tableau.
10. **Tables de fonctions** (IA par `kind`, attaques de Gardien, zones) : dictionnaire de
    `Callable` rendu par une fonction statique (`static func _ai() -> Dictionary`), ou `match`.
11. **État partagé d'un module** (résultat réutilisé de `physics`, sortie de `nav`) : `static var`.
    Conséquence : jamais deux parties dans deux fils ; pour paralléliser, plusieurs processus.
12. **Ensembles** : tableau + `in`, ou dictionnaire `{clé: true}`.
13. **Clés numériques.** Les clés des données sont des TEXTES (`reinforcements` : « 2 », « 3 ») :
    `d[D6Js.num_str(phase)]`.
14. **Texte.** Un nombre dans un texte : `D6Js.num_str(x)` (50, pas 50.0).
15. **Copies.** `D6Js.clone(x)` (copie profonde) ; fusion : `a.duplicate()` puis `merge(b, true)` ;
    concaténation : `a + b` ; vider sans changer d'objet : `arr.clear()`.
16. **Mots réservés.** `super`, `class`, `trait`, `signal`… ne passent pas par le point :
    `t["super"]`, `p["class"]`.
17. **Ordre des clés.** Des boucles parcourent les dictionnaires de données (`tuning.classes`,
    les dispositions d'un Cercle) : l'ordre des clés d'un fichier de `data/` fait partie des règles.

## 3. Ce qui est interdit

- Lire `randf`, `randi`, l'horloge, ou tout état hors de `game` : une partie doit être rejouable
  à l'identique depuis sa graine et ses entrées. L'aléatoire passe par `D6Rng` et `game.rng`.
- Toucher à un nœud, une scène, un signal dans `sim/` : la simulation ne connaît pas Godot.
- Changer une règle sans garde : son test dans `tests/regles/`, puis les références
  réenregistrées et le changement dit dans le commit (`references/enregistrer.gd`, consigne en tête).

## 4. Vérifier

```
G=C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe
"$G" --headless --path . --check-only --script res://sim/<module>.gd      # le script se lit-il ?
"$G" --headless --path . --script res://tests/regles.gd -- <fichier>      # les tests d'un fichier de tests/regles/
"$G" --headless --path . --script res://references/verifier.gd            # la simulation a-t-elle changé ?
bash outils/verifier.sh                                                   # tout (seul endroit où --import est lancé)
```

Après tout NOUVEAU script à `class_name`, `bash outils/verifier.sh` (son étape 1 enregistre les
classes). Un outil ou un test n'a pas besoin de `class_name` : il se charge par `preload`.
