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
│       │   ├─ Barrieres    jeu/monde/barrieres.gd   un nœud par obstacle BAS (palissade), dessiné une fois par salle
│       │   ├─ Ennemis                               un nœud par corps
│       │   ├─ Limiers      jeu/monde/creatures/limiers.gd  les ALLIÉS (game.allies) : limiers de la Meute, leurre d'os — un nœud chacun
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

## Terrain à franchir et déplacement de classe (combat V3, étape 1 bis)

- `game.room.low` : le terrain BAS de la salle, `[{x0, y0, x1, y1, kind}]` — `kind` `river` (rivière,
  dessinée au sol par `jeu/monde/terrain.gd`, entre le sol et les murs) ou `barrier` (obstacle bas,
  dressé par `jeu/monde/barrieres.gd` dans le groupe trié). Les deux calques ne sont redessinés
  qu'au changement de salle. Ce qui coule dépend du Cercle (`Terrain.FLUIDE_DU_CERCLE`).
- `D6Player.move_view(game)` : ce qu'un bouton de DÉPLACEMENT doit montrer —
  `{id, kind ("dash" | "saut" | "roulade"), name, icon, text, charges, maxCharges, ready,
  rechargeFrac, active, air}`. `icon` vaut `dash`, `saut` ou `roulade` (`data/classes.json`, `moves`).
- `D6Player.air(game)` : hauteur du héros en l'air (0..1), le saut du Bourreau ; le calque du
  héros s'en sert (`envol_heros`) comme pour le Bond.
- `D6Player.move_landing(game, dx, dy)` : où le déplacement poserait le héros dans cette
  direction — `{x, y, time, full}` (`full` faux : l'arrivée tombait dans l'eau, le geste sera
  raccourci). Lecture pure, pour un retour de visée.
- Événements : `moveShort` `{x, y, dirX, dirY, reach, done, move}` (déplacement raccourci ou fait sur
  place : `jeu/effets/` dessine une croix rouge sur l'arrivée refusée) ; `moveLand` `{x, y, r, move,
  pushed}` (atterrissage du saut : onde froide, sans dégât).

## Ultimes de classe (combat V3, étape 2)

- `D6Player.ultimate_view(game)` : ce qu'un HUD ou le Grimoire doit lire de l'ULTIME, sans connaître
  l'intérieur — `{id, kind, name, icon, text, charge, ready, holdFrac, active, timeFrac, timeLeft, allies}` :
  `kind` vaut `"forme"` (Revenant), `"magie"` (Bourreau) ou `"invocation"` (Chasseresse) ; `charge` la
  jauge (0..1) ; `ready` jauge pleine ET lançable ; `holdFrac` l'avancement du maintien ; `active` un
  ultime agit (geste, forme, limier vivant) ; `timeFrac` / `timeLeft` la part et les secondes qui
  RESTENT ; `allies` les limiers vivants. `icon` : `forme`, `sentence`, `meute` (`jeu/interface/icones.gd`).
- Pendant qu'une forme ou une meute agit, `player.superCharge` EST sa minuterie (elle se vide) : le
  bouton d'attaque-jauge la montre sans rien changer.
- Forme du Damné : `D6Loadout.slot_view` rend les trois ACTIONS DE FORME (`ruee`, `roar`, `burst` pour
  pictogrammes ; `aimed` faux pour celles qui ne se visent pas) ; `game.tuning.weapon` est le bloc des
  griffes. `D6KitSupers.form_of(game)` (non null = en forme) et `player.ult` `{t, max}` pour le dessin.
- Meute des Limbes : `game.allies`, `[{id, kind: "limier", x, y, r, hp, maxHp, life, lifeMax, state
  ("heel" | "chase" | "bite"), targetId, face, flash, dead}]`. Un ennemi accaparé porte `allyId`.
- Événements : `super` `{x, y, r, super: "forme" | "magie" | "meute"}` au lancement ; Sentence capitale :
  `ultFreeze` `{x, y, time}`, `ultStrike` `{x, y, r, hits, executed, shake}`, `ultBolt` `{id, x, y, r,
  executed}` (un par ennemi touché) ; forme : `formStart` `{x, y, time}`, `formEnd` `{x, y, reason}`
  (`temps`, `embrasement`, `mort`, `etage`, `reprise`), `formRush` `{x0, y0, x, y, width}`, `formHowl`
  `{x, y, r}`, `formBurst` `{x, y, r, frac, amount}` ; meute : `allySpawn` `{id, x, y, life}`, `allyBite`
  `{id, x, y, tx, ty, angle}`, `allyHurt` `{id, x, y, amount, source}`, `allyDeath`, `allyGone` `{…, reason}`.
  Une morsure est aussi un `hit` de sorte `ally`. Effets : `jeu/effets/ultimes.gd` ; sons : `jeu/son/routage.gd`.
- Dessin : le spectre de braise, les griffes, la lame levée sont au calque du héros
  (`jeu/monde/creatures/heros.gd`, `armes.gd`) ; les limiers ont leur calque (`limiers.gd`), 1 appel
  de dessin par limier, barre de vie et repère de durée compris. Banc : `jeu/essai/ultimes.tscn`.

## Arbre de compétences (combat V3, étape 3)

- `D6Profile.tree_view(profil, contenu, classe)` : TOUT ce que le Grimoire montre de l'arbre —
  `{level, maxLevel, xp, xpNext, points, spent, choiceRank, respecCost, tiers: [{name, need, open,
  nodes: [{id, kind ("skill" | "passive" | "move" | "ultimate"), name, icon, text, now, next, rank,
  maxRank, free, canBuy, reason, choices: [{id, name, text, taken, canTake, reason}]}]}]}`. `now` /
  `next` : le texte du rang actuel et du suivant, déjà chiffré ; `text` les deux ; `reason` : pourquoi
  « + » est grisé ; `xpNext` vaut 0 au niveau maximum. Une vue n'additionne rien, ne compare aucun rang.
- Opérations (par `app.operation_ville`) : `tree_buy [classe, nœud]`, `tree_choose [classe, nœud,
  amélioration]`, `tree_respec [classe]` ; `D6Profile.tree_points(profil, contenu, classe)` pour un repère.
- `D6Profile.slot_choices` rend `rank` (0 = à débloquer dans l'arbre) ; il n'y a plus de `cost`.
- En partie : événements `levelUp {classId, level, levels, points}` et `treePoint {classId, guardian,
  points}` ; bilan `D6Run.tree_recap(game)` = `game.run.deathRecap.tree` = `{classId, xpEarned,
  levelsGained, level, points}`. Une compétence `canal` émet `skill {skill: "canal", super, r, slot}`
  puis les `superTick` de l'ancien Super ; pendant son geste `player.channel` porte ses réglages.
- Améliorations exclusives : elles réutilisent les événements existants (`explode` de sorte `lance`,
  zone `brasier` sous la Nova, `hook` absent pour la Chaîne traversante…) ; aucun effet neuf.
- Grimoire = l'écran de l'arbre (`jeu/ville/onglet_grimoire.gd`, détail et choix : `design/COMBAT_V3.md`,
  « Écran de l'arbre »). Trois colonnes : points, niveau, expérience et l'arc des emplacements
  (`arc_emplacements.gd`) ; l'arbre dessiné (`arbre.gd` : mise en page seule pour n'importe quel nombre
  de nœuds par étage, un bouton nu par nœud — clé `noeud:<id>` — ; `arbre_dessin.gd` : tout l'arbre en
  UN lot de triangles ; `icones_arbre.gd` : formes et pictogrammes des passifs) ; le panneau de détail
  (`panneau_noeud.gd` : achat — clé `arbre:<nœud>`, action `plus` —, améliorations — clé
  `arbre:<nœud>:<amélioration>`, action `choix:<amélioration>`, deux appuis —, « Placer en N » — clé
  `placer:<nœud>:<n>` —, « Vider » — clé `slots:<n>`). « Tout rendre » : `%Rendre`, clé `arbre:rendre`,
  deux appuis. Pour un essai : `page.arbre()`, `page.panneau()`, `page.selectionner(id)`,
  `page.selection()`, `arbre.bouton(id)`, `arbre.boite(id)`, `arbre.etat_de(id)`,
  `arbre.etats_des_choix(id)` ; `page.vue_forcee` remplace `tree_view` (arbre factice :
  `jeu/ville/arbre_factice.gd`). À l'ouverture, le nœud choisi est le premier où un point peut être
  dépensé : son bouton d'achat existe sans rien toucher (le parcours s'en sert).
- La Ville dit à chaque onglet la place qu'il a (`tenir_dans(place)`) et où rendre le focus quand un
  bouton a disparu (`repli_du_focus()`) ; dans le Grimoire la note de pied s'efface. L'onglet Grimoire
  prend le texte `REPERE_POINTS` et une pastille au nombre de points (`jeu/theme/pastille.gd`,
  `ville.pastille()`) ; la consigne de l'accueil « Dépense ton point au Grimoire » est une consigne de
  VILLE (`Consignes.VILLE`, hors de la table du HUD), retenue dans `reglages.accueil.acquis`.
- Retours de progression : barre d'expérience `jeu/interface/barre_xp.gd` (HUD sous la vie, écran de
  mort, Grimoire) ; bandeau de niveau `jeu/interface/niveau.gd` (HUD, `levelUp` et `treePoint`) ;
  écran titre : pastille sur « Entrer dans Dité ». Un bouton d'emplacement montre aussi
  `D6Loadout.slot_state` (`etat_commandes.gd` : `charge`, `duree` ; `commande.gd` : anneau d'or qui se
  remplit, anneau froid qui se vide).
- Bancs : `jeu/ville/banc_arbre.tscn` (`D666_CLASSE`, `D666_ARBRE`, `D666_NOEUD`, `D666_GESTE`,
  `D666_FACTICE`, `D666_ONGLET`), `D666_CONSIGNE=niveau` (`jeu/interface/banc_accueil.gd`), `D666_XP` et
  `D666_RICHE` (`jeu/ecrans/banc.gd`).

## Compétences neuves (combat V3, étape 4)

- `D6Loadout.slot_view(game, i)` garde EXACTEMENT sa forme (un test de règles la fige). Ce que les
  compétences neuves ajoutent se lit par `D6Loadout.slot_state(game, i)` = `{charging, chargeFrac,
  active, activeFrac}` — toujours cette forme, tout à zéro pour une action sans état ou un
  emplacement vide : `charging` / `chargeFrac` (0..1) : le Trait de Nemrod se BANDE sur ce bouton ;
  `active` / `activeFrac` (part qui reste) : l'effet de l'action dure (sillage, garde, parade).
- Pictogrammes neufs (`icon` des données, `jeu/interface/icones.gd`) : `sillage`, `stigmate`,
  `riposte`, `faille`, `hachette`, `garde`, `proie`, `leurre`, `trait`.
- Dans le monde, tout est LU : `jeu/monde/competences.gd` (calque `Competences`, au-dessus des
  créatures, sous les tirs) dessine les marques des ennemis (`e.stigmate`, `e.proie` : `{t, max, …}`)
  et ce que le héros porte (`player.parry`, `player.guard`, `player.sillage` : `{t, def, …}` ; arc
  bandé : `slot_state`) ; `tirs.gd` les tirs neufs (`kind` : `stigmate`, `marque`, `renvoi`, `trait`,
  `hache` — celle-ci tourne, `phase` `out` | `spin` | `back`) ; `zones_heros.gd` la zone `faille`
  (`{angle, length, width, open, aftershock, shaken}`) et les braises (zone `brasier` marquée
  `trail`) ; `creatures/limiers.gd` le leurre (allié de `kind` `leurre`, champ `lure.range`).
- Événements neufs : `parryStart {x, y, angle, arc, range, window}`, `parry {x, y, srcX, srcY, r}`,
  `parryEnd`, `marked {id, x, y, mark ("stigmate" | "proie"), time}`, `markJump {x0, y0, x1, y1}`,
  `sillageEnd`, `fissure {x, y, angle, length, width}`, `axeTurn {x, y, spin}`, `axeCatch`,
  `guardStart {x, y, time, arc}`, `guardBlock {x, y, srcX, srcY, amount}`, `guardEnd`, `traitShot {x,
  y, angle, charge, full}`. Événements existants réutilisés : `skill {skill: "sceau" | "riposte" |
  "faille" | "hachette" | "proie" | "trait"}`, `gadget {gadget: "sillage" | "garde" | "leurre", r}`,
  `explode {hero, kind: "stigmate" | "sillage" | "garde" | "leurre"}`, `kitPulse {kind: "hache" |
  "proie"}`, `allySpawn {kind: "leurre"}` et les autres événements d'alliés.
  Effets : `jeu/effets/competences.gd` (forme neuve `fissure` dans `formes.gd`) ; sons : `jeu/son/routage.gd`.
- `D6Player.ultimate_view(game).allies` ne compte que les limiers : un leurre n'est pas un ultime.
- Banc : `jeu/essai/competences.tscn` (`D666_CLASSE`, `D666_CHOIX`), captures dans
  `_dev/captures/lot_v3_competences/`.

## Quatrième compétence de chaque classe et sons du combat V3 (étape 5)

- **Ombre jumelle** (Revenant) : un allié de `game.allies`, `kind` `"ombre"`, marqué `ghost`
  (intangible) : `{x, y, r, life, lifeMax, face, biteT (éclat du coup qu'elle répète), swapped}` ;
  dessiné par `creatures/limiers.gd` (`_ombre_jumelle`). `D6Loadout.slot_state(game, i)` rend
  `active` / `activeFrac` tant qu'elle est debout. Événements : `allySpawn {kind: "ombre"}`,
  `explode {hero, kind: "ombre"}` (elle surgit), `echo {id, x, y, angle, arc, range}` (elle répète
  un coup), `shadeSwap {x0, y0, x1, y1}` (« Transposition »), `allyGone {kind: "ombre", reason}`.
- **Décollation** (Bourreau) : aucun état. Événements : `grace {x, y, r, angle}` (le coup, à son
  point d'impact), `graceKill {x, y, kills, slot}` (il a tué : la recharge est tombée),
  `kitPulse {kind: "grace"}` (« Effroi »).
- **Grêle des Limbes** (Chasseresse) : zone `grele` de `room.kitFx.zones` `{x, y, r, t, delay, wave,
  waves, interval}` — le TÉLÉGRAPHE allié, dessiné par `zones_heros.gd` (`_grele`). Événements :
  `hailCall {x, y, tx, ty, r, delay}` (le tir vers le ciel), `hail {x, y, r, wave, last}` (chaque chute).
- Pictogrammes neufs : `ombre`, `grace`, `grele`. Effets : `jeu/effets/competences.gd`.
- L'événement `dash` porte `move` (`"dash"` | `"saut"` | `"roulade"`) : le son du déplacement de la classe.
- **Son.** Chaque événement de la simulation est routé ou silencieux à dessein (`jeu/son/routage.gd`,
  gardé par `jeu/son/test_son.gd`). Trois sons n'ont PAS d'événement : la vue Son lit l'état à chaque
  image de physique (`son.gd`, `_suivre_etat` ; table `Routage.SONS_VUE`) — `ultime_armement`
  (`player.superHold` monte ; coupé si l'on relâche), `franchissement` (`D6Player.crossing` et
  `D6Physics.low_at`), `point_arbre` (signal `app.profil_change` : les rangs achetés de
  `app.profil.tree` ont augmenté). Aucune règle : elle lit, comme le HUD.
- Banc : `jeu/essai/competences.tscn` avec `D666_LOT=5` ; captures dans `_dev/captures/lot_v3_lot5/`.

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
  aucun bouton Super — clavier : clic droit / E / F (visés à la souris) ; manette : B / Y / RB
  (visés au stick droit) ; tactile : le gros bouton d'attaque, les trois emplacements en ARC
  autour de lui (ids `skill1`, `skill2`, `skill3` dans `interface_tactile()`), le dash à part, à
  droite. C'est `jeu/entrees/tactile.gd` qui connaît les places ; le HUD, sa disposition de repli
  (`jeu/interface/disposition.gd`) et le Grimoire les LISENT. Gestes au doigt : un emplacement
  part au relâcher (tap = visée assistée, glisser = viser, retour au centre = annuler) ; sur
  l'attaque, RIEN ne part à l'appui — appui bref = un coup au relâcher ; glisser = viser, un coup
  au relâcher (ou annulé au centre), l'attaque n'étant jamais tenue ; pouce maintenu sans glisser
  (150 ms) = attaque TENUE. L'attaque tenue (clic gauche, J, X, gâchette, pouce maintenu) est ce
  qui lance l'ultime, jauge pleine : la règle est dans `sim/`, la vue ne fait que dire « tenu ».
  Elle demande la position du héros à l'écran à `app.vues.monde.monde_vers_ecran(...)`.
  Pour l'AFFICHAGE seulement (le jeu, lui, lit `lire()`) : le signal `commande_enfoncee(id)` (une
  touche, un bouton de souris ou de manette vient d'enfoncer la commande), `tenues() -> Dictionary`
  ({id: true} des commandes tenues au clavier, à la souris, à la manette) et
  `visee_bureau() -> Vector2` (stick droit, sinon souris ; ZERO en visée assistée).
- **Effets** et **Son** n'exposent rien : ils écoutent `partie.evenements`. Effets appelle la
  caméra du Monde pour les secousses.
- **Hud** laisse la zone des commandes tactiles libre (il lit `app.vues.entrees.tactile()`). Hors
  tactile, il écrit sous chaque commande la touche du DERNIER périphérique utilisé (clavier et
  souris, ou manette : X, A, B, Y, RB) ; `peripherique()` le dit, `montrer_peripherique(nom)` l'impose.
  Ses commandes : attaque, dash, et les trois emplacements (`skill1`…`skill3`), dont l'état vient de
  `jeu/interface/etat_commandes.gd`, qui lit `D6Loadout.slot_view(game, i)` sans connaître
  l'intérieur (recharge d'une compétence, charges d'un gadget, emplacement vide : bouton éteint,
  cerclé de tirets, sans pictogramme, qui ne réagit à aucun toucher). Même langage sur les trois
  appareils (`jeu/interface/commande.gd`) : le bouton d'ATTAQUE est la jauge d'ultime (un niveau
  monte dans le bouton ; pleine, il devient braise et bat ; maintenue, un anneau se ferme
  autour), les trois emplacements sont groupés (arc au doigt, rangée au bureau), le dash est à
  part. Au doigt, `jeu/interface/tactile.gd` trace aussi la LIGNE DE VISÉE, du héros vers où le
  pouce glisse (attaque, ou emplacement dont l'action se vise) : une direction, pas une portée.
  Le bouton « dash » est le DÉPLACEMENT DE CLASSE : pictogramme (`dash`, `saut`, `roulade`), nom,
  charges et recharge viennent de `D6Player.move_view(game)`. Au clavier et à la manette, un bouton
  se dessine ENFONCÉ tant que sa touche est tenue (0,14 s au moins : `enfoncer(id)`, branché sur
  `commande_enfoncee` et `tenues()` d'Entrees), et une compétence visée tenue montre la même ligne
  de visée (`visee_bureau()`). `jeu/interface/reperes.gd` (nœud `Reperes` du HUD) porte le tracé
  commun de la ligne et le REPÈRE D'ARRIVÉE d'un déplacement qui serait raccourci par le terrain
  bas (`D6Player.move_landing(...).full == false`, héros en marche) : le HUD lit, le nœud dessine.
  Le détail et les choix : `design/COMBAT_V3.md`, « Affichage — ce qui est FAIT » ; pour juger à
  l'écran, le banc `res://jeu/interface/banc_v3.tscn` (chaque état, par variables `D666_…`).
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
fait. La liste est une TABLE (`jeu/interface/consignes.gd` : identifiant, texte par appareil ou
par DÉPLACEMENT DE CLASSE — « Dashe », « Saute », « Roule » —, quand elle se montre, quel
événement ou quelle lecture de l'état la tient pour acquise ; la consigne `terrain` lit
`room.low`, `D6Player.crossing` et `D6Physics.low_at`). L'acquis vit dans les RÉGLAGES
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
