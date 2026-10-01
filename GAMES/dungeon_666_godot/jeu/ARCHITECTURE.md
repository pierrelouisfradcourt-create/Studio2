# Dungeon 666 sous Godot — architecture de la couche visible

`statut_artefact : PROPOSED`. La simulation (`sim/`, portée du web et vérifiée au bit près) ne
connaît pas Godot. Tout ce qui se voit, s'entend ou se touche vit sous `jeu/`, et **lit** la
simulation sans jamais la modifier. La version web (`GAMES/dungeon_666/src/{render,ui,input,audio}`
et `src/main.mjs`) est la référence de ce que le joueur doit voir, entendre et pouvoir faire ; ce
n'est pas une référence au pixel : la version Godot doit être **plus propre** (nœuds, scènes,
thème, conteneurs), pas un calque du canvas.

## Les pièces

```
Principal (Node)            jeu/principal.gd     flux titre → Ville → descente, profil, réglages  [fait]
├─ Partie (Node)            jeu/partie.gd        boucle à pas fixe, événements, interpolation     [fait]
├─ Monde (Node2D)           jeu/monde/monde.tscn     la salle, les zones, les tirs ; sa Camera2D
│   └─ Entites (Node2D)     jeu/monde/entites.gd     le héros, les ennemis, les Gardiens
├─ Effets (Node2D)          jeu/effets/effets.tscn   particules, chiffres de dégâts, éclairs, flashs
├─ Son (Node)               jeu/son/son.tscn         bruitages procéduraux, vibrations
├─ Hud (CanvasLayer)        jeu/interface/hud.tscn   PV, étage, jauges, Gardien, bannières
├─ Entrees (Control)        jeu/entrees/entrees.tscn tactile, clavier/souris, manette → InputFrame (ne dessine rien)
├─ Ville (CanvasLayer)      jeu/ville/ville.tscn     la Ville de Dité (7 onglets), le panneau du labo
└─ Ecrans (CanvasLayer)     jeu/ecrans/ecrans.tscn   titre, choix, mort, victoire, pause, réglages du feel
```

`Principal` monte chaque scène si elle existe, puis appelle sur sa racine :

```gdscript
func brancher(app: Node, partie: Node) -> void
```

C'est le SEUL point d'entrée d'une vue. Elle y garde `app` et `partie`, et s'abonne aux signaux.

## Ce qu'une vue peut lire

- `partie.game` : l'état de la simulation (dictionnaire, clés JavaScript : `game.player.x`,
  `game.enemies`, `game.room`, `game.run`, `game.meta`, `game.choice`, `game.tuning`, `game.mode`),
  ou `null` hors partie. Les champs que la simulation ne pose pas à la naissance d'un objet se
  lisent par `.get("clé", défaut)` ; vrai/faux par `D6Js.truthy(...)`. Tous les nombres sont des
  floats ; un nombre dans un texte s'écrit `D6Js.num_str(x)`.
- `partie.position_dessin(e, est_heros := false) -> Vector2` : la position INTERPOLÉE d'une
  entité (héros, ennemi, projectile, ramassable). Toujours dessiner à cette position, jamais à `e.x, e.y`.
- `partie.en_pause`, `partie.alpha`.
- `app.profil` (profil permanent), `app.reglages` (`sound`, `haptics`, `shake`, `lab`),
  `app.contenu` (réglages de référence : classes, armes, prix, pour la Ville), `app.ecran`
  (`titre` | `ville` | `jeu`), `app.vues` (les autres vues, par nom de scène : `app.vues.monde`…).
- Tables : `D6Data.tables()` (bénédictions, raretés, libellés…), jamais recopiées.

## Signaux

- `partie.evenements(liste: Array)` : les événements de simulation de l'image (`{type, tick, …}`),
  dans l'ordre. C'est par eux que passent effets, sons, bannières. Liste des types : voir
  `emit(game, '…')` dans `GAMES/dungeon_666/src/sim/` et leurs usages dans `src/render/fx.mjs`
  et `src/audio/sfx.mjs`.
- `partie.partie_demarree`, `partie.mode_change(mode)` (`play` | `choice` | `dead` | `victory` | `town`).
- `app.ecran_change(ecran)`, `app.profil_change`, `app.reglages_change`.

## Ce qu'une vue peut faire (et rien d'autre)

| Action | Appel |
|---|---|
| Commande de menu en partie (`choose`, `equip`, `stash`, `salvage`, `close`, `respawn`, `returnToTown`) | `app.commande({"type": "choose", "index": 1.0})` |
| Pause / reprise | `app.mettre_en_pause(true / false)` |
| Abandonner la descente | `app.abandonner()` |
| Aller au titre, en Ville | `app.ouvrir_titre()`, `app.ouvrir_ville()` |
| Descendre, arène, entraînement | `app.demarrer_descente(etage)`, `app.demarrer_descente(1.0, true)`, `app.demarrer_entrainement(gardien)` |
| Opération de la Ville | `app.operation_ville("unlock", ["weapons", "dagues"])` → `{ok, reason?}` |
| Réglage, labo du feel | `app.regler("sound", false)`, `app.regler_labo("hitstop", "local")` |

Une vue ne modifie JAMAIS `partie.game`, n'appelle JAMAIS `D6Game.step_game`, ne tire aucun
nombre au hasard qui influence la partie (`randf` est permis pour une particule, pas pour une règle).

## Contrats entre vues

- **Monde** expose : `camera` (sa `Camera2D`, script `jeu/monde/camera.gd`) avec
  `secouer(force: float, du_heros: bool = false)`, `recul(dir: Vector2, force: float)`,
  `coup_de_zoom(force: float)` (portage de `addTrauma`, `kick` et du zoom de `src/render/camera.mjs`) ;
  et `monde_vers_ecran(p: Vector2) -> Vector2`, `ecran_vers_monde(p: Vector2) -> Vector2`.
- **Entrees** expose : `lire() -> Dictionary` (un InputFrame par pas de simulation, fronts
  accumulés puis consommés), `vider()`, `tactile() -> bool`, `interface_tactile() -> Dictionary`
  (la disposition des commandes tactiles, même forme que `touchUI()` de `src/input/input.mjs` :
  c'est le HUD qui les DESSINE), et le signal `pause_demandee`.
  Elle demande la position du héros à l'écran à `app.vues.monde.monde_vers_ecran(...)`.
- **Effets** et **Son** n'exposent rien : ils écoutent `partie.evenements`. Effets appelle la
  caméra du Monde pour les secousses.
- **Hud** laisse la zone des commandes tactiles libre (il lit `app.vues.entrees.tactile()`).
- **Ecrans** est seul à afficher des panneaux par-dessus le JEU (et l'écran titre) ; il met le jeu
  en pause quand il le faut et écoute `app.vues.entrees.pause_demandee`. **Ville** affiche la Ville
  quand `app.ecran == "ville"` et fournit `jeu/ville/panneau_labo.tscn` (racine avec
  `brancher(app, partie)`), que la pause d'Ecrans réutilise.

Une vue doit fonctionner si une autre manque (`app.vues.has("monde")`).

## Règles de maison

- Scripts : pas de logique de jeu dans les scripts d'interface ; fonctions ≤ 50 lignes ;
  `@onready var` plutôt que `get_node("…")` ; signaux plutôt qu'appels directs entre vues.
- Français pour les noms de nœuds, de fonctions de vue et les commentaires ; les clés de l'état
  de simulation restent celles du JavaScript.
- Pas de `class_name` sous `jeu/` (on charge par `preload`), pas de `--import` pendant que
  d'autres lots travaillent : un fichier `.tscn` s'écrit en texte, à la main.
- Couleurs : `preload("res://jeu/theme/couleurs.gd").PAL` (la palette par RÔLE de
  `src/render/palette.mjs`, mêmes clés ; aussi `ELITE_COLORS`, `CIRCLE_TINTS`, `REWARD_COLORS`, `UI`).
  Panneaux, boutons, textes d'interface : le thème `preload("res://jeu/theme/theme.gd").theme()`
  posé sur la racine de la vue, et ses polices `police_corps()` / `police_titre()`. Aucune couleur
  de bouton ni de panneau écrite dans une vue.
- Résolution de référence 960 × 540, étirement `canvas_items` + `expand` : ancrer les éléments,
  jamais de coordonnées d'écran en dur. Le jeu doit rester lisible en 1600 × 720 et en 960 × 540.
- Aucun fichier d'image, de son ou de police importé : formes dessinées, sons synthétisés,
  polices du système (`SystemFont`). Tout est procédural, comme dans la version web.
- Un essai ne lit ni n'écrit le vrai profil : `outils/capture.gd` pose `D666_DONNEES`.

## Vérifier une vue

```
G=C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe
"$G" --headless --path . --check-only --script res://jeu/<...>.gd
"$G" --position -3000,-3000 --resolution 960x540 --path . --script res://outils/capture.gd -- <scene.tscn> <sortie.png> [images] [pilote]
```

`capture.gd` lance une scène dans une vraie fenêtre (hors écran), la laisse vivre, et enregistre
des PNG : c'est la preuve d'une vue. Chaque lot écrit sa scène de banc `jeu/<lot>/banc.tscn`
(sa vue + une Partie démarrée à un étage choisi, exposée par la propriété `partie`) pour se
capturer seul, et REGARDE ses captures avant de rendre.

## Doigt et souris

Le projet a `emulate_mouse_from_touch = true` : mesuré, sans cela un `Button` Godot ne réagit pas
au doigt (il consomme le toucher sans émettre `pressed`), et les menus seraient muets sur
téléphone. La vue Entrees ignore les souris émulées depuis un doigt. `emulate_touch_from_mouse`
reste à `false` : la souris n'est pas un doigt.
