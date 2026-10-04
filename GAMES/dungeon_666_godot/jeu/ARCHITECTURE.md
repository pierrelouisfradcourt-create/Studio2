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
│       ├─ Sol                                       ombres, halos : sous tout ce qui est debout
│       ├─ Debout (y_sort)                           trié du fond vers l'avant, tous ensemble :
│       │   ├─ Piliers      jeu/monde/piliers.gd     un nœud par pilier, dessiné une fois par salle
│       │   ├─ Ennemis                               un nœud par corps
│       │   ├─ Heros                                 devant tout, sauf derrière un pilier au nord duquel il est
│       │   └─ Objets       jeu/monde/objets.gd      relais : l'objet d'interaction, les ramassables masqués
│       └─ Statuts                                   barres de vie, statuts : jamais cachés
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
- `app.profil` (profil permanent), `app.reglages` (`sound`, `haptics`, `shake`, `lab`, et `feel` :
  les écarts des « Réglages du feel », `{chemin de tuning: valeur}`, enregistrés par `jeu/profil.gd`),
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
| Descendre, arène, entraînement | `app.demarrer_descente(etage)`, `app.demarrer_descente(1.0, true)`, `app.demarrer_entrainement(gardien)` ; toutes prennent une graine en dernier argument (absente : tirée au hasard) |
| Opération de la Ville | `app.operation_ville("unlock", ["weapons", "dagues"])` → `{ok, reason?}` ; emplacements : `app.operation_ville("select_slot", [2.0, "chaine"])` (`null` = vider) |
| Réglage, labo du feel | `app.regler("sound", false)`, `app.regler_labo("hitstop", "local")` |
| Réglages du feel (écarts au tuning de référence) | `app.regler_feel({"player.speed": 340.0})` — retenus, enregistrés, et passés à chaque partie neuve par `options.tuning` (`demarrer_descente`) |

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
  c'est le HUD qui les DESSINE), et le signal `pause_demandee`. Combat V3 : l'entrée porte TROIS
  emplacements d'action (`skill1`, `skill2`, `skill3`, chacun `…Pressed`, `…AimX`, `…AimY`) et plus
  aucun bouton Super — clavier : clic droit / E / F ; manette : B / Y / RB ; tactile : les trois
  boutons autour de l'attaque (ids `skill1`, `skill3`, `skill2` dans `interface_tactile()`), qui
  partent au relâcher, visés si le pouce a glissé. L'attaque TENUE (clic gauche, J, X, gâchette,
  pouce posé sans glisser) est ce qui lance l'ultime, jauge pleine : la règle est dans `sim/`, la
  vue ne fait que dire « tenu ». Un pouce qui GLISSE sur l'attaque vise sans la tenir ; le coup
  part au relâcher.
  Elle demande la position du héros à l'écran à `app.vues.monde.monde_vers_ecran(...)`.
- **Effets** et **Son** n'exposent rien : ils écoutent `partie.evenements`. Effets appelle la
  caméra du Monde pour les secousses.
- **Hud** laisse la zone des commandes tactiles libre (il lit `app.vues.entrees.tactile()`). Hors
  tactile, il écrit sous chaque commande la touche du DERNIER périphérique utilisé (clavier et
  souris, ou manette : X, A, B, Y, RB) ; `peripherique()` le dit, `montrer_peripherique(nom)` l'impose.
  Ses commandes : attaque, dash, et les trois emplacements (`skill1`…`skill3`), dont l'état vient de
  `jeu/interface/etat_commandes.gd`, qui lit `D6Loadout.slot_view(game, i)` sans connaître
  l'intérieur (recharge d'une compétence, charges d'un gadget, emplacement vide : bouton éteint,
  sans pictogramme). Le bouton d'ATTAQUE porte la jauge d'ultime en anneau, et un second trait
  pendant le maintien qui le lance (présentation minimale de l'étape 1 : le bouton-jauge et
  l'arc de boutons du plan sont le lot suivant).
- **Ecrans** est seul à afficher des panneaux par-dessus le JEU (et l'écran titre) ; il met le jeu
  en pause quand il le faut et écoute `app.vues.entrees.pause_demandee`. **Ville** affiche la Ville
  quand `app.ecran == "ville"` et fournit `jeu/ville/panneau_labo.tscn` (racine avec
  `brancher(app, partie)`), que la pause d'Ecrans réutilise.

Une vue doit fonctionner si une autre manque (`app.vues.has("monde")`).

## Ordre des couches

Du dessous au dessus. Les nombres sont ceux de `jeu/theme/couches.gd` ; une scène écrite à la main
porte le nombre (`layer = 10`), `jeu/theme/verifier.gd` vérifie qu'il est le bon.

| Couche | `layer` | Qui |
|---|---|---|
| monde | 0 | `Monde` et ses calques, puis `Effets` (particules, formes, chiffres) : repère du monde, caméra |
| voile | 2 | `Monde/Voile` : la vignette d'ambiance. Sur le monde et ses effets, SOUS les flashs |
| flash | 5 | `Effets/Ecran` : voile clair, vignette de blessure. Sur le monde, SOUS le HUD |
| HUD | 10 | `Hud` : toujours lisible, même pendant un flash |
| Ville | 20 | `Ville` (plein écran) |
| écrans | 30 | `Ecrans` : titre, choix, mort, victoire, pause |
| fondu | 100 | `StudioTransitions` (kit du studio), enfant d'`Ecrans` : fondu d'arrivée à chaque changement d'écran (`app.ecran_change`) et à l'entrée d'un étage (`floorEnter`) |

Un fondu COUPE au noir puis éclaircit : l'écran d'arrivée est déjà là et répond pendant
l'éclaircie. Aucun fondu, aucune apparition de panneau ne retarde un choix ; seul l'ARMEMENT d'un
panneau (anti-martelage, `jeu/ecrans/ecrans.gd`) décide quand il répond.

Profondeur : ce qui est DEBOUT (piliers, ennemis, héros) vit dans `Monde/Entites/Debout`, trié
en y ; ce qui se tient au nord d'un pilier passe derrière lui, ce qui est au sud le recouvre.
L'ombre d'un pilier reste au sol (`Murs`). Ce qui doit toujours se lire reste au-dessus du
groupe : `Statuts` (barres de vie), puis `Contours` (bords des dangers) et `Tirs`. Le remplissage
d'un télégraphe est au sol : un pilier le cache là où il se dresse, son bord jamais.

Le rang d'un nœud du groupe est le y de son POINT AU SOL, jamais celui de son dessin : un Gardien
qui bondit (Cerbère) garde son nœud au sol, seul son dessin monte (`corps.envol`). Les ramassables
(or, soin) restent au sol, sous les pieds de qui passe ; celui qui tombe juste au nord d'un pilier
serait caché par son dessus : il est repeint juste devant ce pilier, parce qu'un ramassable doit se
LIRE. L'objet d'interaction (butin, marchand, coffre…) se dresse au rang de son pied : un pilier
plus au nord ne recouvre ni son corps ni sa colonne de lumière. Ses runes et ses halos restent au sol.

Une seule main dessine chaque chose : la taillade d'un coup et la traînée du dash sont au calque
du héros (`jeu/monde/creatures/`, à la portée réelle du coup) ; `Effets` n'ajoute que les éclats,
les ondes, les chiffres, et la grande taillade dorée de l'Exécution (un Super).

## Coût du dessin

En rendu Compatibility (téléphone), ce qui coûte est l'APPEL DE DESSIN. Mesuré : un rectangle,
une ligne non lissée, une primitive partent par lots ; mais chaque polygone coûte 1 appel, chaque
disque lissé 2, chaque trait, arc ou cercle lissé 3 (le moteur trace à part ses franges de
lissage). Un corps fait de vingt formes cernées coûtait ainsi 35 à 60 appels, le HUD 150.

La règle : **un dessin = un lot de triangles** (`jeu/theme/triangles.gd`). On y ajoute les formes
(`disque`, `cercle`, `polygone`, `polyligne`, `contour`, `arc`, `ligne`, `rect`, `vignette`…), puis
`tracer(self)` les envoie en UN appel. Le lot fabrique les mêmes triangles que les gestes du
moteur (mêmes points, même frange) : l'image ne change pas. Il garde en mémoire les formes déjà
vues : les redessiner ne coûte que des recopies.

- Créatures : tout passe par le pinceau (`jeu/monde/creatures/pinceau.gd`), entre `commencer(ci)`
  et `finir()`. Lueurs et ombres vivent dans une même texture (l'atlas) et partent avec le lot ;
  seul un texte le coupe. Un corps d'ennemi = 1 appel ; le sol de toutes les créatures = 1 appel ;
  leurs statuts = 1 appel, plus leurs textes ; le héros = 1 appel.
- Un corps d'ennemi n'est REPEINT que si sa pose change, ou vingt fois par seconde (`corps.gd`) ;
  entre deux, le moteur rejoue son lot sous un nouveau repère. Un Gardien est repeint à chaque image.
- HUD : chaque commande, le fil des étages, les bénédictions, les flèches = 1 appel chacun.
- Ne pas appeler `draw_circle`, `draw_arc`, `draw_polyline` ou `draw_colored_polygon` en boucle
  dans un `_draw` qui vit à chaque image : passer par un lot.

Mesurer (vraie fenêtre, hors écran) : `jeu/monde/mesure.gd` sur le banc `jeu/essai/cout.tscn`
(`D666_ENNEMIS`, `D666_GARDIEN`), simulation arrêtée. Repères au 2026-10-02, 960 × 540, banc de coût :

| Scène | Appels avant | Appels après | ms / image avant | après |
|---|---|---|---|---|
| 0 ennemi | 228 | 48 | 2,1 | 1,3 |
| 10 ennemis | 741 | 63 | 3,5 | 1,9 |
| 20 ennemis | 1240 | 74 | 5,1 | 2,4 |
| 10 ennemis + Cerbère | 820 | 71 | 4,0 | 2,1 |

Preuve d'image : `_dev/captures/lot_cout/` (`capturer.sh`, `comparer.sh`) — mêmes scènes figées,
horloge fixe, avant et après : aucun pixel n'y diffère de plus de 2 / 255, hors des trois cas
de profondeur corrigés le même jour (ramassables, objet d'interaction, Gardien qui bondit).

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
  posé sur la racine de la vue — UN SEUL thème pour le HUD, les écrans et la Ville. Une vue ne
  nomme que des VARIATIONS (`theme_type_variation`, liste en tête de `theme.gd` : bouton principal
  « braise », bouton neutre, carte, sur-titre, titre d'apparat, texte doux, prix, textes du HUD…) ;
  aucune couleur de bouton, de panneau ni de texte écrite dans une vue. L'état grisé :
  `ThemeJeu.OPACITE_GRISE`. Les cibles : `ThemeJeu.CIBLE` (44 px) et `CIBLE_GRANDE` (48 px).
- Briques communes, sous `jeu/theme/` : `carte.tscn` (LA carte, pour les écrans comme pour la
  Ville : `carte.decrire({...})`), `filet.gd` (filet d'ornement sous un grand titre),
  `titre_relief.gd` (relief d'un titre d'apparat), `couches.gd` (ordre des couches),
  `triangles.gd` (le lot de triangles : un dessin en un appel, voir « Coût du dessin »).
- Petite fenêtre (téléphone en paysage, 844 × 390) : chaque vue agrandit sa racine de
  `ThemeJeu.echelle(vue, fenetre)` pour garder la taille de référence (cibles ≥ 44 px), et demande
  un texte net par `ThemeJeu.nettete(viewport, echelle)`.
- Résolution de référence 960 × 540, étirement `canvas_items` + `expand` : ancrer les éléments,
  jamais de coordonnées d'écran en dur. Le jeu doit rester lisible en 1600 × 720 et en 960 × 540.
- Aucun fichier d'image, de son ou de police importé : formes dessinées, sons synthétisés,
  polices du système (`SystemFont`). Tout est procédural, comme dans la version web.
- Un essai ne lit ni n'écrit le vrai profil ni les vrais réglages : il pose `D666_DONNEES`
  LUI-MÊME, avant de monter le jeu (`outils/capture.gd` le fait aussi, mais un banc peut être
  lancé sans lui : scène ouverte seule, éditeur).

## Vérifier une vue

```
G=C:/Users/Studio-Dev/Desktop/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe
"$G" --headless --path . --check-only --script res://jeu/<...>.gd
"$G" --position -3000,-3000 --resolution 960x540 --path . --script res://outils/capture.gd -- <scene.tscn> <sortie.png> [images] [pilote]
```

Le thème commun, l'ordre des couches et les réglages du feel ont leur vérification sans fenêtre :
`"$G" --headless --path . --script res://jeu/theme/verifier.gd` (finit par « THEME : OK »).
L'ordre de profondeur du Monde, le Traqueur disparu et la durée de l'élan aussi :
`res://jeu/monde/test_profondeur.gd` (finit par « PROFONDEUR : OK ») ; pour les juger à l'écran,
le banc `res://jeu/essai/profondeur.tscn` pose le cas voulu dans le vrai jeu (`D666_CAS`).
Le lot de triangles, le rang des ramassables, de l'objet d'interaction et du Gardien qui bondit :
`res://jeu/monde/test_finitions.gd` (finit par « FINITIONS : OK ») ; à l'écran, le banc
`res://jeu/essai/cout.tscn` (`D666_RAMASSABLES`, `D666_OBJET`, `D666_BOND`).

L'ACCUEIL DU PREMIER JOUEUR (`jeu/interface/accueil.gd` + `accueil.tscn`, enfant du HUD, couche
HUD) montre une consigne à la fois, sous le fil des étages ; elle s'efface dès que le geste est
fait. La liste est une TABLE (`jeu/interface/consignes.gd` : identifiant, texte par appareil,
quand elle se montre, quel événement la tient pour acquise). L'acquis vit dans les RÉGLAGES
(`reglages_jeu.json`, champ `accueil` : `actif`, `acquis`), jamais dans le profil de la
simulation ; la pause permet de couper les consignes ou de les revoir. La vue ne lit que
`partie.game` et `partie.evenements`, n'écrit rien dans la simulation, ne met jamais en pause ;
elle est absente de l'arène et de l'entraînement. Vérification sans fenêtre :
`res://jeu/interface/test_accueil.gd` (finit par « ACCUEIL : OK ») ; à l'écran, le banc
`res://jeu/interface/banc_accueil.tscn`. Les accords des textes composés (« de la classe … »)
sont dans `jeu/theme/accords.gd`.

Le jeu ASSEMBLÉ a son parcours sans fenêtre : `res://jeu/essai/test_parcours.gd` (finit par
« PARCOURS : OK », environ 45 s seul, davantage dans l'oracle). Il monte `jeu/principal.tscn` et
fait vivre un joueur par les seules portes des vues (actions de `principal.gd`, commandes de menu,
et le bouton de l'écran de victoire), le bot de `outils/bots/` aux commandes
(`jeu/essai/parcours_pilote.gd`) :

- un joueur neuf : titre, Ville (chaque onglet, un achat refusé, le labo ; le Portail ne propose
  que l'étage 1 et aucun Gardien), descente de l'étage 1 (bénédiction, butin, marchand, autel,
  chambre forte, pause en combat) jusqu'au GARDIEN de l'étage 18, réellement battu par le bot avec
  ce profil neuf : butin, deux portes, checkpoint et Gardien au profil et sur le disque ; le
  héros prend son butin puis le PORTAIL de la Ville (ni mort ni taxe) ; le Portail propose
  l'étage 19 et le Gardien à défier ; REPRISE depuis ce point (équipement gardé, aucune
  bénédiction), mort, « Repartir » (au même point), mort, retour en Ville, une amélioration, un
  objet du coffre ;
- un joueur au bout du chemin (profil écrit par `jeu/ville/profil_essai.gd`, `au_bout_du_chemin` :
  tout acheté, un checkpoint par section, objets légendaires du niveau 648 — aucun mode
  invulnérable) : la dernière section, de son checkpoint (étage 649) au dernier Gardien (étage
  666), fontaine du Léthé comprise ; l'écran de VICTOIRE (ce qu'il dit, son seul bouton, appuyé),
  ce que le profil reçoit (Âmes, Gardien compté, record 666, aucun checkpoint de plus) ;
- un joueur avancé (profil de `jeu/ville/profil_essai.gd`, relu du disque par un jeu neuf) : une
  opération par onglet, arène d'essai, entraînement contre un Gardien, une descente profonde par
  classe (étages 19, 37, 55), finie par abandon ou par mort ;
- quatre cycles titre → Ville → descente → mort → Ville : le nombre de nœuds ne monte pas.

À chaque étape : l'écran et le mode attendus, les vues visibles et celles qui ne le sont pas, le
profil du disque d'essai égal à celui en mémoire. Il est ROUGE de lui-même à la moindre erreur de
script (`parcours_temoin.gd` les compte), et si le parcours n'a pas réellement joué (gardes :
salles, étages jusqu'au 666e, les six sortes de menu, les deux Gardiens battus, le portail, le
départ du point, la victoire, morts, abandons, classes, opérations). Il tient l'horloge : la
boucle de la Partie est appelée pas à pas, graines fixes — même partie à chaque lancement (les
lignes « RÉSUMÉ » sont identiques d'un lancement à l'autre). Il ne touche pas au vrai profil
(dossier `user://essais_parcours`, empreinte du vrai `profil.json` vérifiée avant et après).
Ce qu'il ne prouve pas : le rendu, le toucher des boutons (tests de chaque vue). Avant de fermer
le jeu, un essai laisse finir les fondus (`jeu/essai/fondus.gd`) : un fondu du kit coupé net par
`app.free()` reste en mémoire et Godot écrit « ObjectDB instances leaked at exit » à la sortie.

`capture.gd` lance une scène dans une vraie fenêtre (hors écran), la laisse vivre, et enregistre
des PNG : c'est la preuve d'une vue. Chaque lot écrit sa scène de banc `jeu/<lot>/banc.tscn`
(sa vue + une Partie démarrée à un étage choisi, exposée par la propriété `partie`) pour se
capturer seul, et REGARDE ses captures avant de rendre.

## Doigt et souris

Le projet a `emulate_mouse_from_touch = true` : mesuré, sans cela un `Button` Godot ne réagit pas
au doigt (il consomme le toucher sans émettre `pressed`), et les menus seraient muets sur
téléphone. La vue Entrees ignore les souris émulées depuis un doigt. `emulate_touch_from_mouse`
reste à `false` : la souris n'est pas un doigt.
