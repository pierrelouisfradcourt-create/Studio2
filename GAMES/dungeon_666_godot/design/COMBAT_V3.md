# Dungeon 666 — combat V3 : attaque façon Brawl Stars, trois compétences, ultime de classe, arbre

`statut_artefact : PROPOSED` · 2026-10-04 · demande de Pierre, à corriger par lui.

## Ce que Pierre a demandé (ses mots, ses réponses)

- « Un système comme à Brawl Stars pour attaquer, mais tu charges l'attaque principale pour faire
  le super et le décharger, et il y a 3 boutons de compétences en cercle autour. »
- « Ça débloque une transformation limitée qui change les skills / l'attaque principale quand tu
  as l'ultime, ou une grosse magie, ou une invocation, selon les classes. »
- Super : **les coups le remplissent**, et **le bouton d'attaque se remplit à vue d'œil comme
  une jauge**. Pour le lancer : **laisser appuyé** sur le bouton d'attaque (« comme ça il n'y a
  pas d'ambiguïté » — précision de Pierre, 2026-10-04).
- « Il faut juste garder le dash / déplacement pour tout le monde et ajouter les compétences. »
- Dash : **il garde son bouton**.
- Ultime : **un type par classe** — Revenant : transformation ; Bourreau : grosse magie ;
  Chasseresse : invocation.
- Compétences : **3 emplacements choisis**, « mais il faut des compétences et un arbre de
  compétences comme à Diablo ».

## Ce qui existe déjà et sert

- Le joystick d'attaque glissé existe (visée manuelle, sinon visée automatique).
- La jauge de Super se remplit déjà avec les dégâts infligés.
- Chaque classe a 2 compétences et 2 gadgets, soit 4 actions ; il en faut davantage.
- Un Super par classe (Colère, Sentence, Nuée) : ils deviennent la base des trois ultimes.

## 1. Les commandes

```
                      [C2]
                [C1]        [C3]
   (joystick)                    [ATTAQUE]   [DASH]
```

- **Attaque** : gros bouton. Appui bref = coup, visée automatique. Glisser = viser, relâcher = frapper.
- **Jauge d'ultime** : c'est le bouton d'attaque lui-même qui se REMPLIT au fur et à mesure
  (un niveau qui monte dans le bouton), nourri par les coups de l'attaque principale (les
  compétences la remplissent moins : réglage). Pleine : le bouton bat. **Laisser appuyé** lance
  l'ultime : un petit anneau se ferme pendant le maintien (réglage, environ 0,4 s), relâcher
  avant annule. Un appui bref ou un glisser-relâcher reste toujours un coup normal.
- **Trois compétences** en arc autour du bouton d'attaque, chacune avec sa recharge. Même geste :
  appui = visée automatique, glisser = viser.
- **Dash et déplacement** : inchangés, les mêmes pour toutes les classes.
- Clavier : clic gauche attaque (jauge pleine : maintenir le clic gauche = ultime), Espace dash,
  clic droit / E / F les trois compétences. Manette : même logique.
- Le « gadget » à charges disparaît comme catégorie : nova, bombe, piège, cri, totem deviennent
  des compétences. Choix par défaut : ils gardent leurs **charges** (rechargées par section et
  par élite tué), affichées sur le bouton ; les autres compétences ont une recharge en secondes.

## 2. L'ultime de chaque classe

| Classe | Type | Proposition | Durée |
|---|---|---|---|
| Revenant | Transformation | **Forme du Damné** : il devient un spectre de braise. Attaque principale remplacée (griffes rapides à vol de vie), les 3 compétences remplacées par 3 compétences de forme (ruée spectrale, hurlement, explosion finale). La jauge se vide : c'est la durée de la forme. | 10 s |
| Bourreau | Grosse magie | **Sentence capitale** : il lève sa lame, l'écran se fige un instant, puis un fracas frappe tout l'écran visible ; les ennemis sous 25 % de vie sont exécutés. Un seul coup, invulnérable pendant le geste. | instantané |
| Chasseresse | Invocation | **Meute des Limbes** : trois limiers d'os se battent à ses côtés, ciblent ce qu'elle vise, et encaissent à sa place. | 12 s |

Les trois Supers actuels (Colère, Sentence, Nuée) deviennent des compétences de l'arbre ou la
base de ces ultimes : rien n'est jeté.

## 3. Les compétences et l'arbre (façon Diablo)

- **8 compétences par classe** (les 4 actuelles + 4 nouvelles), rangées en **4 étages** de l'arbre :
  base, cœur, maîtrise, ultime. On en équipe 3.
- Chaque compétence : **5 rangs** (plus de dégâts / moins de recharge) puis **2 améliorations
  au choix exclusif** (exemple, Lance infernale : « transperce tout » OU « explose à l'impact »).
- Des **passifs** entre les étages (exemple : « +10 % de dégâts aux ennemis étourdis »).
- **Points de compétence** : la classe gagne de l'expérience en tuant, et un point par niveau
  (choix par défaut : niveau 30 au maximum, 1 point par niveau, plus 1 par Gardien vaincu pour
  la première fois). L'arbre est PERMANENT (comme la Ville), respécialisable contre de l'or.
- L'étage suivant de l'arbre s'ouvre après N points dépensés (5, 12, 20).
- Les **bénédictions** restent le TEMPORAIRE d'une descente ; elles s'appliquent aux
  compétences équipées quelles qu'elles soient (« votre compétence 1 »).
- Le **Grimoire** de la Ville devient l'écran de l'arbre.

## 4. Le déplacement de classe et le terrain à franchir

Demande de Pierre (2026-10-04) : « Chaque classe a un dash / déplacement. Il faudrait rajouter
des rivières à sauter et traverser les obstacles avec le dash. Mais ça peut être un jump pour le
guerrier, ou autre chose selon la classe. »

**Un bouton de déplacement par classe**, à la même place pour tous, même rôle (esquiver,
franchir), geste différent :

| Classe | Déplacement | Ce qui le distingue |
|---|---|---|
| Revenant | **Dash** (l'actuel) | Rapide, court, traverse les attaques ; plusieurs charges. |
| Bourreau (le guerrier) | **Saut** | Il s'élève et retombe : invulnérable en l'air, petit choc à l'atterrissage qui repousse. Plus lent à repartir, une seule charge. |
| Chasseresse | **Roulade longue** | La plus grande distance ; elle recharge son prochain tir en roulant. |

**Terrain à franchir**, nouveau dans les salles :

- **Rivière / gouffre** : on ne la traverse PAS à pied ; le déplacement de classe la franchit si
  l'arrivée est sur la terre ferme (sinon le geste est refusé : jamais de chute, jamais de mort
  par le décor). Les tirs passent au-dessus. Des **gués / ponts** existent toujours : une salle
  reste finissable sans franchir.
- **Obstacle bas** (barrière, décombres, autel renversé) : bloque la marche, se franchit au
  déplacement de classe. Bloque les tirs ? Choix par défaut : non (il est bas).
- **Pilier et mur** (hauts) : inchangés, rien ne les traverse.
- **Ennemis** : ceux qui marchent contournent par les gués (la rivière devient un abri contre la
  mêlée et un piège contre les tireurs) ; ceux qui volent ou qui bondissent (Traqueur, Cerbère)
  la franchissent.
- Lisibilité : le bord franchissable d'une rivière porte une marque claire ; pendant la visée du
  déplacement, le point d'arrivée s'affiche vert (valide) ou rouge (refusé).

## 5. Ordre de construction (chaque étape jouable et vérifiée)

1. **Commandes** : 3 emplacements de compétence, gadgets fondus dans les compétences, ultime
   lancé par le bouton d'attaque, nouvelle disposition tactile / clavier / manette. Contenu
   inchangé (les 4 actions actuelles par classe, on en équipe 3). → à jouer par Pierre.
1 bis. **Déplacement de classe et terrain** : saut du Bourreau, roulade de la Chasseresse,
   rivières, obstacles bas, gués ; ennemis qui contournent ; nouvelles dispositions de salle
   avec rivière. → à jouer par Pierre.
2. **Ultimes** : Forme du Damné, Sentence capitale, Meute des Limbes. → à jouer.
3. **Arbre** : expérience et niveaux de classe, points, rangs, améliorations exclusives,
   passifs, écran du Grimoire ; d'abord avec les compétences existantes.
4. **Contenu** : les 4 compétences nouvelles par classe (12 au total) et leurs améliorations.
5. Bots, références, équilibrage : à chaque étape les bots apprennent le nouveau système et
   l'oracle reste vert ; les parties de référence sont réenregistrées (changement voulu).

## Choix par défaut pris sans Pierre (à corriger s'ils ne conviennent pas)

- Les anciens gadgets gardent leurs charges.
- Durée du maintien qui lance l'ultime : environ 0,4 s (réglage), avec un anneau qui se ferme.
- 8 compétences par classe, 5 rangs, 2 améliorations exclusives, niveau 30.
- Les points viennent de l'expérience de classe, pas des Âmes (les Âmes gardent le Sanctuaire).
- Rivière jamais mortelle (franchissement refusé si l'arrivée n'est pas sur la terre ferme) ;
  un gué existe toujours ; l'obstacle bas ne bloque pas les tirs ; les piliers restent infranchissables.
- Déplacements : saut pour le Bourreau, roulade longue pour la Chasseresse, dash pour le Revenant.
- Noms et effets des ultimes et des compétences nouvelles : propositions, à nommer par Pierre.

## Étape 1 « Commandes » — ce qui est FAIT (2026-10-04)

Côté règles (`sim/`, `data/`), avec l'affichage minimum pour que le jeu se joue. Contenu inchangé :
chaque classe garde ses 2 compétences et ses 2 gadgets ; on en équipe 3.

**L'entrée d'un pas** (`D6Game.empty_input`) : `moveX, moveY, aimX, aimY, attack, attackPressed,
dashPressed, skill1Pressed, skill1AimX, skill1AimY, skill2…, skill3…`. Les boutons compétence,
gadget et Super ont disparu, sans alias.

**L'ultime par maintien.** Jauge pleine et attaque tenue sans interruption : `player.superHold`
monte ; à `tuning.super.holdTime` (0,4 s, le même pour les trois Supers, `data/classes.json`)
l'ultime part — le Super de la classe, inchangé. Relâcher remet `superHold` à zéro. Jauge non
pleine : tenir l'attaque enchaîne le combo, comme avant. Choix pris :

- **Le combo pendant l'armement** : le premier appui donne son coup normal ; ce coup se joue
  jusqu'au bout ; aucun NOUVEAU coup ne part tant que `superHold` monte. Arrivé à `holdTime`,
  l'ultime part aussitôt : s'il reste un bout du coup (une arme lente), il le coupe, comme le
  faisait l'ancien bouton. Avec la Lame, le coup 1 (0,24 s) finit avant.
- **La jauge se remplit pendant que le joueur tient déjà l'attaque** : RIEN ne s'arme (décision de
  Pierre, étape 1 bis : « pas d'ambiguïté »). L'ultime ne s'arme que si l'APPUI A COMMENCÉ jauge
  pleine (`player.superArm`) : qui garde le bouton enfoncé pour enchaîner continue son combo ;
  pour l'ultime, il relâche et rappuie. L'appui qui vient de lancer un ultime n'en arme pas un
  second. (Jusqu'à l'étape 1 bis, l'armement commençait sans relâcher : le bot qui martèle
  lançait ainsi 1 à 5 ultimes par partie.)
- **Au doigt** : poser le pouce frappe ; le garder posé sans glisser tient l'attaque (donc arme
  l'ultime) ; GLISSER vise sans tenir l'attaque, et le coup part au relâcher, dans la direction
  visée. Un glisser-relâcher ne lance donc jamais l'ultime. Effet de bord à juger : un
  glisser donne deux coups (un à l'appui, un au relâcher).

**Trois emplacements.** `profil.loadout.slots` : trois identifiants (ou null) parmi les
compétences ET les gadgets possédés de la classe, jamais deux fois le même. En partie :
`game.kit.slots` ; l'état est par emplacement (`player.slots[i] = {cd, charges}`) : deux
compétences équipées ont chacune leur recharge, deux gadgets chacun leurs charges (rendues par
section et par élite tué, comme avant). `D6Profile.select_slot(profil, tuning, emplacement, id)`
place, échange (action déjà placée ailleurs) ou vide (`id` null) ; `D6Profile.slot_choices` liste
ce qui se place ; `D6Loadout.slot_view(game, i)` dit à l'affichage `{id, name, icon, kind, ready,
cooldownFrac, charges, maxCharges, aimed}` (null si vide ; `maxCharges` est un ajout au contrat,
pour dessiner les segments de charges). Les événements `castStart`, `skill`, `gadget`,
`gadgetCharge` portent `slot` (0, 1, 2). Choix pris :

- Un gadget part tout de suite (comme avant) ; une compétence passe par le tampon. Une compétence
  demandée pendant le lancer d'une autre attend son tour. Le tampon ne garde qu'UNE action : deux
  compétences pressées au même pas, la dernière l'emporte.
- Un gadget LANCÉ (la bombe) suit la visée de son bouton ; sans visée, celle de l'attaque, sinon
  la visée assistée.
- `tuning.skill` et `tuning.gadget` (blocs actifs uniques) n'existent plus.

**Migration du profil** (`PROFILE_SCHEMA` 3 → 4, `sanitize_profile`) : `{skillId, gadgetId}`
devient `[skillId, gadgetId, première autre action possédée de la classe, sinon null]`. Un
emplacement vidé exprès reste vide ; une action perdue, en double ou d'une autre classe est
remplacée par la première action possédée pas encore placée. Changer de CLASSE refait les trois
emplacements (une action commune aux deux classes reste à sa place, tout le reste est rempli par
ce que la classe possède). Test sur un vrai profil de joueur au schéma 3 : rien n'est perdu.

**Bénédictions, objets, autels, repos** : ce qui parle de « la compétence » vaut pour TOUTE
compétence équipée, ce qui parle « du gadget » pour TOUT gadget équipé (liste et tests :
`tests/regles/v3_combat.gd`, « effet … »).

**Affichage minimum** : clavier clic droit / E / F, manette B / Y / RB, tactile les trois boutons
d'avant (compétence, gadget, Super) devenus emplacements 1, 2, 3 ; HUD : les trois emplacements,
la jauge d'ultime en anneau autour du bouton d'attaque ; Grimoire : trois emplacements à remplir ;
accueil : « Jauge pleine : garde le bouton d'attaque appuyé ». PAS FAIT (lot suivant) : l'arc de
trois boutons, le bouton d'attaque qui se remplit, l'anneau qui se ferme, les textes des
bénédictions (« Votre compétence… » au singulier).

**Bots et références** : les bots lisent les trois boutons (`slot_view`) et tiennent l'attaque
pour l'ultime ; jauge pleine sans vouloir l'ultime, ils frappent par appuis. Le bot qui martèle
tient l'attaque : son ultime partait tout seul (plus depuis l'étape 1 bis : l'appui doit commencer
jauge pleine). Les 70 parties sont réenregistrées (format 2 du codec) ; les parties `kit_*` et
`hasard_*` jouent trois emplacements remplis.

## Affichage — ce qui est FAIT (2026-10-04)

L'affichage et les gestes de l'étape 1 (`jeu/interface/`, `jeu/entrees/`, `jeu/ville/`). Aucune
règle ici : l'affichage LIT `slot_view`, `superCharge`, `superHold`, `holdTime` ; le geste ne
produit que les champs de l'entrée d'un pas. Preuves à l'écran : `_dev/captures/lot_v3_affichage/`
(`capturer.sh`, banc `jeu/interface/banc_v3.tscn`). TOUT ce qui suit est à juger par Pierre.

**Disposition tactile** (`jeu/entrees/tactile.gd`, seule à connaître les places ; px à l'échelle
960 × 540) :

```
              [C2]  [C3]
          [C1]
   (joystick)        [ATTAQUE]  [DASH]
```

- **Attaque** : le plus gros bouton (104 px), à 168 × 100 px du coin bas-droit.
- **Trois emplacements** : cibles de 60 px, sur un même arc autour de l'attaque (rayon 106), de
  45° en 45°, à gauche et au-dessus (190°, 235°, 280°) ; 21 px de vide entre deux voisins, 24 px
  entre eux et l'attaque.
- **Dash** (76 px) : À DROITE de l'attaque, un peu plus bas, contre le bord. Pourquoi là : c'est
  le croquis du plan ci-dessus (`[ATTAQUE] [DASH]`) ; il est de l'autre côté de l'arc, donc un
  dash d'urgence ne lance jamais une compétence par erreur (et l'inverse) ; le pouce y va en se
  REPLIANT depuis l'attaque (16 px de vide), sans traverser un autre bouton ; il reste le bouton
  le plus près du pouce au repos. Prix : l'attaque recule de 50 px vers le centre.
- Portrait (toléré) : pas de place à droite, le dash passe au-dessus de l'arc.
- Gaucher : aucun réglage de main n'existe dans le jeu, aucun n'a été inventé (piste : un
  réglage « main » qui retourne `disposer()` ; tout le reste suit, puisque le HUD et le Grimoire
  lisent les places).

**Le bouton d'attaque est la jauge d'ultime** (`jeu/interface/commande.gd`) : un niveau braise
monte DANS le bouton, du bas vers le haut, avec sa surface en trait clair ; trois petits repères
au bord marquent le quart, la moitié, les trois quarts. Pleine : tout le disque devient braise, le
pictogramme passe au sombre, le cercle à l'or, un halo bat. Maintenue jauge pleine : un anneau
clair se FERME autour du bouton en `holdTime` (lu : `superHold / holdTime`) ; relâcher l'efface
(la règle remet `superHold` à zéro). Rien n'est calculé ici.

**Un emplacement** montre son pictogramme, sa recharge (balayage sombre qui se vide + anneau) OU
ses charges (segments dorés, `charges` / `maxCharges`), l'état prêt (cercle et pictogramme
clairs, une onde quand il le redevient). Vide : un socle éteint cerclé de tirets, sans
pictogramme, qui ne réagit à aucun toucher.

**Gestes** (`jeu/entrees/tactile.gd`). Sur l'attaque (ou un toucher dans la moitié droite, hors
bouton) :

- appui BREF = un coup, visée automatique. Il part AU RELÂCHER (plus à l'appui) ;
- GLISSER (plus de 18 px) = une ligne de visée part du héros ; UN coup part au relâcher, dans
  cette direction ; revenir au centre du bouton avant de relâcher ANNULE. L'attaque n'est jamais
  « tenue » pendant un glisser : il ne lance jamais l'ultime ;
- pouce MAINTENU sans glisser plus de 150 ms (`APPUI_BREF_MS`) = le coup part, puis l'attaque
  est TENUE (elle enchaîne, et arme l'ultime jauge pleine). Tenir, puis glisser : on vise, et le
  coup visé part au relâcher.
- Le défaut « un glisser donne deux coups » est corrigé : rien ne part plus à l'appui. Prix, À
  JUGER EN MAIN : un appui bref frappe à la levée du pouce, un appui maintenu frappe après
  150 ms. Si cela se sent, baisser `APPUI_BREF_MS`.

Sur un emplacement : tap = visée automatique ; glisser = viser (la ligne ne s'affiche que si
l'action se vise, `aimed`) ; relâcher lance ; revenir au centre annule. Dash : à l'appui.

**La ligne de visée** (`jeu/interface/tactile.gd`) part du héros, dans la direction du pouce.
Elle montre une DIRECTION, pas la portée (longueur fixe) : la portée est une règle, l'affichage
ne la calcule pas (piste : la lire dans le kit).

**Clavier / souris et manette** : même langage, en rangée en bas — les trois emplacements
groupés, le bouton d'attaque-jauge plus gros, le dash à part — avec les libellés (Clic D, E, F,
Clic G, Espace ; B, Y, RB, X, A). Un emplacement vise où pointe la souris ; à la manette, où
pointe le stick droit.

**Grimoire** (`jeu/ville/onglet_grimoire.gd`, `arc_emplacements.gd`) : en haut, les trois
emplacements dessinés comme en jeu (le même arc, lu de la même disposition, les mêmes
pictogrammes ; attaque et dash en filigrane) et leur légende (« 1 · Lance infernale », Vider) ;
dessous, les compétences de la classe avec leur pictogramme. On touche une compétence puis un
emplacement, ou l'inverse ; rien n'est écrit au premier toucher ; une compétence placée est
marquée « ● Emplacement N ». Opérations inchangées (`select_slot`).

**Textes** : « compétences » au pluriel là où il y en a trois (écran titre, consignes,
bénédictions : « Compétences ») ; les anciens gadgets sont dits « compétences à charges »
(Grimoire, consigne). RESTENT FAUX, parce qu'ils viennent de `data/` (non touché) : « Votre
compétence… » (`benedictions.json`), « charge de gadget » (`autels.json`, `butin.json`,
`ville.json`), « dégâts / recharge de la compétence » (`butin.json`). → corrigés depuis à la
source : voir « Finitions — ce qui est FAIT ».

**Coût de dessin** : inchangé. Banc du HUD, 960 × 540 : 39,2 appels au doigt et 51,1 au bureau,
avant comme après ; banc de coût (10 ennemis) : 67,8 avant, 67,8 après. Chaque bouton reste un
lot de triangles (un appel) ; la ligne de visée part dans l'appel du joystick.

## Étape 1 bis « Déplacement de classe et terrain » — ce qui est FAIT (2026-10-04)

Règles (`sim/`, `data/`), bots, affichage du terrain (`jeu/monde/`, `jeu/effets/`). L'affichage des
COMMANDES (pictogramme du bouton de déplacement) n'est pas de ce lot : il lira `D6Player.move_view(game)`.

**Réglage de l'ultime.** L'appui doit COMMENCER jauge pleine (voir « L'ultime par maintien »). Le
bot habile relâche puis rappuie pour l'ultime ; le bot qui martèle n'en lance plus.

**Un déplacement par classe, sur le bouton du dash** (`data/classes.json` : `move` de la classe,
table `moves`). Les trois passent par le même état (`dash`) et le même bloc de réglage actif
(`tuning.dash` : le dash de base de `data/heros.json`, recouvert par les nombres du déplacement
de la classe) : charges, recharge, i-frames, esquive parfaite, frappe de dash, bénédictions et
objets « de dash » valent donc pour les trois. Nombres PROPOSÉS, à juger en main :

| | Revenant — **dash** | Bourreau — **saut** | Chasseresse — **roulade** |
|---|---|---|---|
| Distance (dash 165 u × statistique de classe) | 165 u | 132 u (−20 %) | 214 u (+30 %) |
| Durée du geste | 0,15 s | 0,34 s | 0,26 s |
| Invulnérable | 0,18 s | 0,40 s (tout le vol) | 0,22 s |
| Charges / recharge | 2 / 0,9 s | 1 / 1,3 s | 2 / 1,0 s |
| Coupé par une frappe ; enchaîné | oui (fin du dash) ; oui | non, non (rien ne coupe le vol) | non ; oui |
| Fenêtre de frappe en sortie | 0,3 s | 0,3 s | **1,2 s** |
| En plus | — | choc à l'atterrissage : repousse dans 80 u (recul 420), **aucun dégât** ; ce sur quoi il retombe est chassé devant lui | « tir prêt » : pendant 1,2 s son prochain tir est la frappe de dash de son arme |

Choix pris :

- **Effet de la roulade** — « elle prépare son prochain tir » : le plus simple qui se sente est
  la règle qui existe déjà. En sortie de roulade, la fenêtre de frappe de dash dure 1,2 s au lieu
  de 0,3 s : son prochain tir est le tir lourd de l'arme (trois flèches perçantes de l'Arc, le
  carreau perçant de l'Arbalète). Elle ne peut pas couper la roulade par un tir.
- **Le saut n'est pas une attaque** : son choc pousse (`D6Combat.push_enemy`) sans dégât, sans
  jauge d'ultime, sans proc « au toucher ». Un ennemi projeté contre un mur prend le choc de mur
  habituel. L'ennemi sur lequel le Bourreau retombe est posé DEVANT lui (dans le sens du saut) :
  sa frappe d'atterrissage porte.
- **Bond du bourreau et saut** : ils partagent le vol au-dessus du terrain (`D6KitCommon.flight_moves`,
  `D6Physics.fly_plan`). Le Bond reste une compétence offensive (260 u, vise un ennemi, 34 dégâts,
  étourdit, recharge 6 s) ; le saut est le déplacement (132 u, sans dégât, 1,3 s). **Ils font en
  partie double emploi** (deux sauts invulnérables sur la même classe) : à trancher par Pierre —
  le Bond n'a pas été retiré.
- La statistique de classe `dashDistanceMult` règle la longueur des trois gestes : un test
  existant (`v2_kits`, « statistiques appliquées ») mesure la distance du déplacement de chaque
  classe à partir d'elle.

**Terrain à franchir** (`data/salles.json` : table `TERRAINS`, par disposition `rivers` et
`barriers` ; en partie : `room.low`).

- À PIED, on ne traverse ni rivière ni obstacle bas (héros, ennemis, ramassables). Les tirs, les
  lancers et la vue passent au-dessus. Piliers et murs : inchangés.
- Le déplacement de classe (et le Bond) FRANCHIT si l'arrivée est sur la terre ferme. **Arrivée
  dans l'eau : le geste est RACCOURCI** au dernier point de terre ferme de sa trajectoire (au pire
  il se fait sur place) : la charge est dépensée et l'esquive (i-frames) gardée — refuser le geste
  aurait privé le joueur d'une esquive au bord de l'eau. Jamais de chute, jamais de dégât du décor.
  Événement `moveShort` : croix rouge sur l'arrivée refusée, barre au bord, « AU BORD » / « TROP LOIN ».
- Rien ne coupe un geste au-dessus de l'eau : frappe de dash, second dash et ultime attendent la
  terre ferme.
- **Recul** : un ennemi projeté s'arrête au bord et glisse le long (pas de choc de mur).
- **Ruées** (Bélier, Charon) : elles ne franchissent RIEN — au bord d'une rivière ou d'un obstacle
  bas, la ruée s'arrête et le chargeur est SONNÉ, comme contre un mur (une seule règle : « ce qui
  arrête une ruée la sonne »). Le Bélier ne charge que si la voie est libre à pied pour son corps ;
  sinon il contourne.
- **Ennemis qui marchent** : ils contournent par les gués (le champ de navigation connaît le
  terrain). **Traqueur** : il franchit en réapparaissant dans le dos du héros, jamais dans l'eau.
  **Cerbère** (bond) : il franchirait, mais **les salles de Gardien n'ont pas de terrain** — leurs
  attaques sont écrites pour une arène dégagée.
- Rien n'apparaît dans une rivière ni sur un obstacle bas : vagues, invocations, récompense,
  entrée, ramassables.
- **Toute salle reste finissable à pied** : chaque disposition a ses gués ou ses ponts ; un test
  le prouve par remplissage de la grille de navigation, et un second qu'aucun endroit où le héros
  tient debout n'est coupé de l'entrée.
- **Cinq dispositions** (`data/salles.json`) : `gues` (rivière en travers, deux gués), `douve`
  (îlot central entouré d'eau, deux ponts), `fosse` (fossé devant le fond de la salle, passages
  sur les côtés), `barrieres` (palissades en chicane), `torrent` (rivière en long, deux
  palissades). Rivières larges de 60 à 64 u : le plus court des trois déplacements les franchit
  (gardé par `donnees.gd`). Elles entrent dans le tirage des Cercles par `data/etages.json`, **à
  partir de l'étage 5** (`room.terrainFrom`) : les quatre premières salles restent sans terrain.
- **Affichage** : rivière = canal creusé, liseré clair (« ici, on franchit »), eau noire, sang,
  lave ou glace selon le Cercle ; obstacle bas = palissade de pieux, deux fois moins haute qu'un
  pilier, même liseré, triée en profondeur avec les créatures. Le Bourreau en plein saut est
  dessiné en l'air ; la Chasseresse fait un tour sur elle-même. Le terrain n'est redessiné qu'au
  changement de salle. PAS FAIT : le point d'arrivée vert / rouge pendant la visée du déplacement
  (le déplacement ne se vise pas : il part dans la direction de la marche).

**Bots.** Ils voient le terrain : marche par les gués (champ de distance), esquive qui sait
qu'un déplacement passe au-dessus de l'eau ; le bot habile franchit pour rejoindre quand le détour
est long et la cible encore loin.

**À juger en main par Pierre** : les nombres des trois déplacements ; le saut (trop lent ? une
seule charge ?) ; la roulade et son « tir prêt » ; le geste raccourci plutôt que refusé ; la ruée
sonnée au bord de l'eau ; les cinq dispositions et l'étage où elles entrent ; le dessin (couleurs
de ce qui coule, palissades) ; le double emploi Bond / saut.

## Finitions — ce qui est FAIT (2026-10-04)

Lot court d'affichage et de textes (`jeu/interface/`, `jeu/entrees/`, `jeu/ville/`, `jeu/ecrans/`,
textes de `data/` et de `sim/calm_rooms.gd`). Aucun nombre, aucun identifiant, aucune règle
changés. Preuves à l'écran : `_dev/captures/lot_v3_finitions/` (`capturer.sh`). TOUT est à juger
par Pierre.

**1. Le bouton de déplacement est celui de la classe.** Pictogramme propre à chacun
(`jeu/interface/icones.gd`, noms `dash`, `saut`, `roulade` = le champ `icon` de `moves`) : les
chevrons du dash ; les mêmes chevrons DRESSÉS au-dessus d'un sol pour le saut ; une boucle qui
tourne au ras du sol pour la roulade. Charges et recharge sont lues par `D6Player.move_view(game)`
(`jeu/interface/etat_commandes.gd` ne lit plus `dashCharges` ni `dashRecharge`). Les consignes
de l'accueil parlent du geste de la classe (`jeu/interface/consignes.gd`, champ `gestes`) :

| Consigne | Revenant | Bourreau | Chasseresse |
|---|---|---|---|
| `dash` | Dashe à travers les attaques | Saute par-dessus les attaques | Roule à travers les attaques |
| `rouge` | Esquive le rouge : dashe | Esquive le rouge : saute | Esquive le rouge : roule |
| `terrain` | Franchis la rivière d'un dash | Franchis la rivière d'un saut | Franchis la rivière d'une roulade |

Ville : l'onglet Classe écrit « Déplacement · Saut : … » (nom et texte de `moves`) sur chaque
classe ; le Grimoire montre une carte « Déplacement · <classe> » (pictogramme, nom, texte) à côté
de l'ultime. L'écran titre nomme le geste de la classe choisie (DASH / SAUT / ROULADE). Le libellé
sous le bouton reste la TOUCHE (Espace, A).

**2. Le terrain dans l'accueil.** Onzième consigne, `terrain` : elle se montre la première fois
que le héros est à moins de 120 u du bord d'une rivière ou d'un obstacle bas (lu : `room.low`),
dit « la rivière » ou « l'obstacle » selon ce qui est le plus près, et désigne le bouton de
déplacement. Acquise quand le héros en a FRANCHI une : lu à chaque image,
`D6Player.crossing(game)` et `D6Physics.low_at(...)` (il est au-dessus du terrain bas ; la règle
ne l'y laisse jamais). Comme les autres consignes de circonstance, elle est aussi tenue pour vue
après 14 s d'affichage cumulées. Le seuil de 120 u est un seuil d'affichage, pas une règle.

**3. Textes au singulier, corrigés à la source.**

| Fichier | Avant | Après |
|---|---|---|
| `data/benedictions.json` (charme) | Votre compétence rend vulnérable : +{v} % de dégâts subis, 4 s. | Vos compétences rendent vulnérable : +{v} % de dégâts subis, 4 s. |
| `data/benedictions.json` (convoitise) | Votre compétence déclenche un éclair : {v} dégâts, 3 rebonds. | Vos compétences déclenchent un éclair : {v} dégâts, 3 rebonds. |
| `data/benedictions.json` (rancoeur) | Compétence : recharge −{v} %. | Compétences : recharge −{v} %. |
| `data/autels.json` (fontaine) | Remplir une fiole — +{gain} charge de gadget | Remplir une fiole — +{gain} charge à chaque compétence à charges |
| `data/butin.json` (affixe `skillDamageMult`) | dégâts de la compétence | dégâts des compétences |
| `data/butin.json` (affixe `skillCooldownMult`) | recharge de la compétence | recharge des compétences |
| `data/butin.json` (main_de_gloire) | Salle nettoyée sans être touché : +1 charge de gadget | Salle nettoyée sans être touché : +1 charge à chaque compétence à charges |
| `data/ville.json` (arsenal) | +1 charge de gadget par section. | +1 charge par section à chaque compétence à charges. |
| `sim/calm_rooms.gd` (fioles) | Charges de gadget pleines, jauge de Super +N %. | Charges des compétences pleines, jauge de Super +N %. |
| `jeu/ville/onglet_classe.tscn` | La classe fixe les armes, compétences et gadgets disponibles, et son Super. | La classe fixe le déplacement, les armes et les compétences disponibles, et son Super. |
| `jeu/ville/onglet_grimoire.tscn` (titre de section) | Ultime | Déplacement et ultime |
| `jeu/ecrans/titre.gd` | … DASH … | … le nom du déplacement de la classe … ; « invulnérable pendant la ruée » → « pendant le geste » |

Les règles derrière ces textes ont été relues, pas changées : `grant_gadget_charges` et
`gadgetChargesBonus` valent pour CHAQUE action à charges équipée (d'où « à chaque »). À SAVOIR :
« Vos compétences rendent vulnérable », « … déclenchent un éclair » et « dégâts des compétences »
ne valent que pour les compétences qui se RECHARGENT (source `skill`), pas pour les compétences à
charges (source `gadget`) : la formule demandée par Pierre est gardée, la nuance est à trancher
par lui (« Vos compétences à recharge… » ?). Le mot « gadget » n'est plus dans aucun texte vu par
le joueur de `data/` (hors `classes.json`, tenu par un autre lot), `sim/` et `jeu/` ; il reste dans
les noms de champs, d'événements et les commentaires.

**4. Clavier et manette : retour « enfoncé » et ligne de visée.** La vue Entrees dit, pour
l'affichage seulement, quelle commande vient d'être enfoncée (signal `commande_enfoncee(id)`),
lesquelles sont tenues (`tenues()`) et où vise le bureau (`visee_bureau()` : stick droit, sinon
souris ; ZERO en visée assistée). Le HUD dessine le bouton enfoncé (le même dessin qu'au doigt)
tant que la touche est tenue, 0,14 s au moins. Une compétence qui se vise (`slot_view.aimed`),
tenue, montre la même ligne de visée qu'au doigt, du héros vers la souris ou le stick
(`jeu/interface/reperes.gd`, qui porte désormais le tracé commun de la ligne). En visée assistée,
aucune ligne : la simulation choisit la cible, l'affichage ne la devine pas. Au clavier la
compétence part À L'APPUI : la ligne montre donc où elle vient de partir, tant qu'on tient.

**5. Geste raccourci : un repère AVANT qu'il parte.** Quand le héros marche franchement vers une
rivière ou un obstacle bas (norme du déplacement voulu ≥ 0,5), que le geste est prêt et que
`D6Player.move_landing(game, dx, dy).full` est faux, un petit anneau rouge barré est posé au sol
à l'endroit où il s'arrêterait (`jeu/interface/reperes.gd`, dans le HUD, par
`monde_vers_ecran`). Rien quand le geste irait au bout, ni dans une salle sans terrain bas.
`jeu/monde/` n'est pas touché ; la visée du déplacement n'a pas changé.

**Coût de dessin** : chaque bouton reste un lot de triangles. Le nœud `Reperes` ne dessine que
s'il a quelque chose à montrer (un appel, le temps d'une visée au bureau ou d'un repère d'arrivée).

**Vérifications ajoutées** : `test_accueil` (consigne du terrain ; pictogramme, nom, charges et
phrases par classe ; boutons enfoncés, bref ; ligne de visée du bureau), `test_entrees`
(`commande_enfoncee`, `tenues()`, `visee_bureau()`, aucun front consommé), `test_ville`
(« Déplacement · … » dans Classe et Grimoire).

**PAS FAIT.** Les textes de `data/classes.json` qui disent encore « dash » pour les trois classes
(« frappe de dash », passif du Revenant) et les bénédictions du dash (« Dash », écran de choix) :
`classes.json` est tenu par un autre lot, et « dash » y nomme une règle commune aux trois gestes.
À la manette, le repère d'arrivée et la ligne de visée n'ont pas été capturés (même code que le
clavier).

**À juger en main par Pierre** : les deux pictogrammes neufs ; les phrases par classe ; le seuil
de 120 u et la patience de 14 s de la consigne du terrain ; la durée du retour « enfoncé » ; la
ligne de visée au clavier (utile, ou de trop ?) ; l'anneau d'arrivée (assez discret, assez lisible ?).

## Étape 2 « Ultimes » — ce qui est FAIT (2026-10-04)

Règles (`sim/`, `data/classes.json`), bots, affichage dans le monde, pictogrammes du HUD et du
Grimoire. Un type par classe ; les trois se lancent comme avant (jauge pleine, appui commencé jauge
pleine, maintien `holdTime`) et commencent par un geste invulnérable. TOUT ce qui suit est PROPOSÉ :
noms, durées, nombres sont dans `data/classes.json`, à juger en main par Pierre.

**Règles communes** (`sim/kit_supers.gd`, `D6KitSupers`).

- Un ultime qui AGIT (geste en cours, forme active, limier vivant) ne se relance pas. Pendant ce
  temps la jauge ne se remplit par rien (coups, esquive parfaite, bénédictions) : pour la forme et
  la meute elle SE VIDE et sert de minuterie — le bouton d'attaque la montre sans rien savoir.
- Mourir, changer de salle ou d'étage, reprendre après la mort : forme terminée (kit d'origine
  rendu), limiers retirés, jauge à zéro (à sa valeur de départ après une reprise).
- Jamais lancé au-dessus d'une rivière (comme avant) ; arène d'essai et entraînement : ils marchent.
- Les trois anciens Supers (Colère, Sentence, Nuée) restent dans les données, marqués `reserve` :
  leur code joue toujours (testé), ils ne sont plus l'ultime d'aucune classe et attendent l'arbre.
- Lecture pour l'affichage : `D6Player.ultimate_view(game)` (`jeu/ARCHITECTURE.md`).

**Revenant — transformation « Forme du Damné »** (`sim/ult_forme.gd`).

| Réglage | Proposé |
|---|---|
| Geste de lancement (invulnérable) | 0,25 s |
| Durée de la forme (`formTime`) | 10 s de temps de jeu (un gel d'impact la retient d'autant) |
| Griffes (remplacent l'arme, quelle qu'elle soit) | 3 coups : 11, 11, 18 dégâts ; portée 96 / 96 / 110 u ; arcs 170° / 170° / 230° ; un tour en 0,68 s (la Lame : 0,90 s) ; frappe de dash 22 |
| Vol de vie des griffes (`lifesteal`) | 5 % des dégâts, en plus de celui du build |
| Ruée spectrale | 260 u d'un trait, 26 dégâts à tout ce qui est sur le passage (bande de 70 u), invulnérable 0,25 s, recharge 2,5 s |
| Hurlement | étourdit 1,3 s à 180 u, 8 dégâts, recharge 5 s |
| Embrasement | met fin à la forme ; explosion à 210 u, de 30 dégâts (forme presque finie) à 160 (à peine commencée), étourdit 0,6 s, efface les tirs |

- La jauge est la minuterie ; les coups en forme ne la remplissent pas.
- `slot_view` et `game.kit.slots` rendent les trois actions de FORME pendant la forme ; elles se
  lancent comme des compétences (tampon, lancer, recharge propre, réduite par les mêmes bonus).
- **Kit d'origine : FIGÉ pendant la forme.** Ses recharges ne courent pas, ses charges ne bougent
  pas (ni gagnées, ni perdues) ; à la fin il revient tel qu'il était au lancement. Choix : c'est le
  plus simple à lire (« je retrouve ce que j'ai laissé ») et à tester à l'identique.
- Une action de forme en cours de lancer finit avant la fin de la forme ; l'arme équipée au moment
  de la fin est celle qui revient (changer d'arme pendant la forme garde les griffes).
- Le déplacement reste le dash. Dégâts des actions : source « super » (bonus de Gloire charnelle) ;
  les griffes sont des coups d'arme ordinaires.

**Bourreau — grosse magie « Sentence capitale »** (`sim/ult_magie.gd`).

| Réglage | Proposé |
|---|---|
| Geste entier (invulnérable, immobile) | 1 s, plus le temps figé |
| Lame levée avant le fracas (`strikeAt`) | 0,5 s |
| Temps figé (`freeze`, le gel d'impact de la sim) | 0,3 s |
| Fracas (`damage`, `stun`) | 85 dégâts, étourdit 1,2 s |
| Exécution (`executeBelow`) | à 25 % de vie ou moins |
| Gardien (`bossCap`) | jamais exécuté ; au plus 10 % de sa vie maximale par fracas |

- **Qui est touché** : tout ennemi PRÉSENT dans la salle (apparu, non dissous), sans visée ni ligne
  de vue — derrière un pilier, de l'autre côté d'une rivière, face à un pavois. Choix : « visible »
  est lu comme « à l'écran », pas « en ligne de vue » ; la foudre tombe d'en haut.
- **Exécution** : tout ennemi qui n'est pas un Gardien, champions compris ; une bulle d'immunité
  protège. L'exécuté compte comme tué (or, Âmes, récompense d'élite, procs « à la mort »).
- Pas de recul (étourdis sur place : la suite du combat se lit), pas de critique (85 est 85).
- Les projectiles ennemis en vol sont effacés. Le fracas ne recharge pas la jauge.

**Chasseresse — invocation « Meute des Limbes »** (`sim/ult_meute.gd`).

| Réglage | Proposé |
|---|---|
| Geste de lancement (invulnérable) | 0,3 s |
| Limiers (`count`), durée (`life`) | 3, pendant 12 s |
| Vie d'un limier (`hp`) | 45 × l'échelle de dégâts de l'étage (comme les coups ennemis) |
| Vitesse, morsure | 340 u/s ; 7 dégâts toutes les 0,6 s, à l'échelle de l'arme de l'héroïne |
| Cible désignée (`markTime`) | 2,5 s après son dernier coup à elle |
| Ennemi accaparé (`distractRange`, `distractRatio`) | limier à moins de 240 u ET de 60 % de sa distance à l'héroïne |

- Les limiers vivent dans `game.allies`, JAMAIS dans `game.enemies` : vagues, ennemis restants,
  invocations, élites, salle nettoyée ne les voient pas (testé).
- **Cible** : ce qu'elle vient de blesser elle-même, sinon ce qu'elle vient de viser, sinon le plus
  proche de chaque limier.
- **Terrain** : ils MARCHENT et contournent par les gués (chacun son champ de navigation vers sa
  cible, sur la grille des ennemis) ; jamais dans l'eau, un mur ni un pilier (300 graines).
- **Ils encaissent** : un ennemi de MÊLÉE en chasse se tourne vers le limier nettement plus près
  que l'héroïne et le frappe au contact, à ses dégâts et à son rythme ; un tir ennemi s'arrête sur
  un limier ; une zone qui frappe le héros frappe aussi les limiers. Tireurs et Gardiens ne se
  détournent pas.
- **Leurs morsures ne sont pas des coups de l'héroïne** : ni jauge, ni proc « au toucher », ni vol de
  vie, ni désignation de cible. La MORT d'un ennemi compte : or, Âmes, procs « à la mort », salle.
  Le bonus de dégâts du Super (Gloire charnelle) s'y applique.
- La jauge est leur minuterie ; tous morts avant la fin : la jauge est vide et se remplit de nouveau.

**Effets qui parlent du « Super »**, revérifiés un par un sur les trois ultimes (`v3_ultimes.gd`,
« effet … ») : Ripaille (soin au lancer), Passion brûlante (enflamme autour au lancer), Gloire
charnelle (dégâts : fracas, actions de forme, morsures — pas les griffes ; durée +0,4 s : geste de la
Sentence, forme, meute), Extase et affixe « de la Rage » (`superChargeMult`), Ivresse et esquive
parfaite de base, Trop-plein (hors ultime oui, pendant non), autel de la Clepsydre, repos
(« Remplir les fioles »), jauge de départ à la reprise.

**Bots.** Le bot habile lance la forme quand la mêlée est là, la Sentence capitale quand deux
ennemis sont en vue (ou un Gardien, ou PV bas), la meute au premier ennemi à sa portée ; en forme
il lit les trois boutons : ruée sur une ligne d'ennemis, hurlement à deux ennemis dans le rayon,
embrasement quand la jauge-minuterie est presque vide. Le bot qui martèle ne lance pas d'ultime.

**Affichage** (`jeu/monde/creatures/`, `jeu/effets/ultimes.gd`, `jeu/son/routage.gd`,
`jeu/interface/icones.gd`). Forme : spectre de braise (corps de charbon et de feu, flammes, griffes
à la place de l'arme, pas de pieds), traînée et taillades de braise, anneau de braise qui se vide.
Sentence capitale : lame levée au ciel, colonne et cercle d'or qui se resserrent, écran qui blanchit
au temps figé, onde d'or, un éclair par ennemi, marque « EXÉCUTÉ ». Limiers : chiens d'os à la
teinte froide de l'héroïne (jamais de rouge), triés en profondeur, barre de vie fine, arc de durée
à leurs pieds. Pictogrammes neufs : `forme`, `meute`, `ruee`, `burst`. Preuves :
`_dev/captures/lot_v3_ultimes/` (banc `jeu/essai/ultimes.tscn`).

**À juger en main par Pierre** : les trois noms ; tous les nombres ci-dessus ; la forme (trop
forte avec son vol de vie et son hurlement ?) ; le kit figé pendant la forme ; la ruée « posée » ;
le fracas sans ligne de vue ni recul ; le seuil de 25 % et le plafond de 10 % sur un Gardien ; la
taille et la lisibilité des limiers, leur règle d'attirance ; le mot « Super » dans les textes des
bénédictions.

## Étape 3 « Arbre de compétences » — ce qui est FAIT (2026-10-04)

Règles (`sim/tree.gd`, `data/arbres.json`), affichage SIMPLE au Grimoire, bots, références. Avec les
compétences qui existent ; le contenu neuf (étape 4) s'ajoute par les données : une entrée dans
`data/classes.json`, un nœud dans `data/arbres.json`. TOUS les nombres sont des PROPOSITIONS.

**Expérience et niveaux de classe (permanents).** Chaque classe a son niveau, de 1 à **30**.

| Réglage (`data/arbres.json`) | Proposé |
|---|---|
| Expérience : ennemi tué / élite / Gardien (`xp`) | 1 / 6 / 60 |
| Profondeur (`depthStep`, `depthCap`) | × (1 + 0,25 × (section − 1)), jamais plus de × 4 (atteint en section 13) |
| Courbe (`curve`) | passer du niveau N au suivant : 40 + 25 × (N − 1) ; niveau 30 = 11 310 d'expérience |
| Points | 1 par niveau gagné (29), + 1 par MODÈLE de Gardien vaincu pour la première fois avec la classe (4 modèles) : 33 au plus |

- L'expérience est versée au profil À CHAQUE ennemi tué, exactement là où le sont les Âmes : mourir,
  abandonner, rentrer ou gagner ne la reprend pas. Rien en arène d'essai, rien à l'entraînement,
  rien pour une invocation ; le Gardien verse la sienne à sa mort (pas à l'entraînement).
- Borne : un élite au plafond vaut 24, un Gardien 240 ; le premier niveau en demande 40, le 29e 740.
- Événements : `levelUp {classId, level, levels, points}`, `treePoint {guardian, points}`. Bilan :
  `game.run.deathRecap.tree` et `D6Run.tree_recap(game)` = `{classId, xpEarned, levelsGained, level, points}`.

**L'arbre** : 4 étages, ouverts après 0 / 5 / 12 / 20 points DÉPENSÉS dans la classe (les rangs
offerts ne comptent pas). Trois sortes de nœuds :

- **Compétence** : 5 rangs. Le rang 1 DÉBLOQUE (elle devient plaçable) avec les nombres de
  `classes.json` ; les rangs 2 à 5 l'améliorent (table `ranks`). **Au rang 3**, deux améliorations
  EXCLUSIVES : on prend l'une OU l'autre, gratuitement ; seule la respécialisation défait le choix.
  Choix du rang 3 plutôt que 5 : le joueur choisit tôt, et les rangs 4 et 5 améliorent ce qu'il a pris.
- **Passif** (5 par classe, 1 à 3 rangs) et **déplacement** (1 nœud au sommet) : une statistique.
- **Ultime** (1 nœud au sommet, 2 rangs) : un nombre de l'ultime de la classe.
- La première compétence et la première compétence à charges de chaque classe ont leur rang 1
  OFFERT (aucun point, il survit à la respécialisation). Le prix en Âmes des compétences a disparu
  (plus de `cost` ; `D6Profile.unlock` d'une compétence répond « se débloque dans l'arbre »).
- **L'arbre entier coûte EXPRÈS plus de points qu'un héros n'en aura** (37 ou 38 contre 33) : il
  faut choisir. Écrit dans les données (`fullyBuyable: false`), gardé par `donnees.gd`.

**Les anciens Supers sont la 5e compétence de chaque classe** (faisable proprement : fait). Sorte
`canal` : la compétence joue Colère, Sentence ou Nuée dans l'état « super » sur SA recharge longue
(20 / 24 / 22 s), invulnérable le temps du geste, dégâts de source « super » (ils ne chargent pas la
jauge) ; la jauge d'ultime n'est ni dépensée ni remplie pendant le geste. À JUGER : une invulnérabilité
de 1,4 à 1,6 s toutes les 20 s, en plus de l'ultime.

> Tableaux de l'ÉTAPE 3, gardés tels quels. Depuis l'étape 4 : trois compétences neuves par classe,
> et la Chaîne et la Bombe ont une version par classe — l'arbre à jour est plus bas, « Étape 4 ».

**Revenant**

| Nœud | Étage | Rangs | Ce que donnent les rangs | Amélioration A | Amélioration B |
|---|---|---|---|---|---|
| Lance infernale (offerte) | Base | 5 | dégâts 30 → 34, 38, 42, 46 ; recharge 4 → 3,8, 3,6, 3,4, 3,2 s | **Transperce tout** : traverse 99 ennemis, porte à 760 u | **Explose à l'impact** : 26 dégâts à 110 u autour du premier touché, et elle s'arrête là |
| Nova de cendres (offerte) | Base | 5 | dégâts 20 → 36 ; rayon 150 → 182 u ; 4 charges aux rangs 4 et 5 | **Aspiration** : attire contre vous au lieu de repousser | **Sol en feu** : 4 s de flammes, 14 dégâts/s |
| Sang vif (passif) | Base | 3 | +8 PV max par rang | | |
| Chaîne d'Enfer | Cœur | 5 | dégâts 16 → 32 ; recharge 5 → 3,8 s ; portée 430 → 510 u | **Ferrage** : le harponné subit +30 % de dégâts 4 s | **Chaîne traversante** : ne tire plus, traverse 5 ennemis, étourdit 1,2 s |
| Bombe de soufre | Cœur | 5 | dégâts 45 → 69 ; rayon 120 → 144 u | **Grappe** : 3 bombes de 26 dégâts à 90 u | **Fumigène** : 1 dégât, étourdit 2,5 s à 170 u, sans repousser |
| Grimoire brûlant (passif) | Cœur | 3 | recharge des compétences −5 % par rang | | |
| Pas de l'ombre (passif) | Cœur | 1 | +1 charge de dash | | |
| Tourbillon de colère (ancien Super) | Maîtrise | 5 | recharge 20 → 16 s ; 9 → 13 dégâts par coup | **Œil du cyclone** : aspire au lieu de repousser | **Soif** : +1 PV par ennemi touché, à chaque coup |
| Fureur damnée (passif) | Maîtrise | 2 | l'ultime se charge 10 % plus vite par rang | | |
| Tranchant (passif) | Maîtrise | 3 | +4 % de critique par rang | | |
| Dash long (déplacement) | Sommet | 1 | le dash va 15 % plus loin | | |
| Forme tenace (ultime) | Sommet | 2 | Forme du Damné : 10 → 12, 14 s | | |

**Bourreau**

| Nœud | Étage | Rangs | Ce que donnent les rangs | Amélioration A | Amélioration B |
|---|---|---|---|---|---|
| Bond du bourreau (offert) | Base | 5 | dégâts 34 → 54 ; recharge 6 → 4,8 s | **Double saut** : le Bond suivant est prêt en 0,5 s, une fois | **Onde de choc** : frappe à 200 u, recul 900 |
| Cri du bourreau (offert) | Base | 5 | rayon 200 → 240 u ; vulnérable +30 → +42 % ; 4 charges aux rangs 4 et 5 | **Cri de guerre** : +25 % de dégâts 5 s pour le héros | **Terreur** : le cri repousse (recul 900) |
| Cuir épais (passif) | Base | 3 | +12 PV max par rang | | |
| Chaîne d'Enfer | Cœur | 5 | comme celle du Revenant (arbre à part : chaque classe monte la sienne) | Ferrage | Chaîne traversante |
| Bombe de soufre | Cœur | 5 | comme celle du Revenant | Grappe | Fumigène |
| Bourreau des sonnés (passif) | Cœur | 3 | +10 % de dégâts aux ennemis étourdis par rang | | |
| Bras de fer (passif) | Cœur | 2 | recul infligé +15 % par rang | | |
| Triple sentence (ancien Super) | Maîtrise | 5 | recharge 24 → 20 s ; dégâts × 1,08 → × 1,32 | **Verdict** : un seul fracas de 120 tout autour, en 0,6 s | **Dîme de sang** : +4 PV par ennemi frappé |
| Billot (passif) | Maîtrise | 2 | +4 % d'armure par rang | | |
| Jugement hâtif (passif) | Maîtrise | 2 | l'ultime se charge 10 % plus vite par rang | | |
| Saut leste (déplacement) | Sommet | 1 | le saut revient 20 % plus vite | | |
| Sentence sans appel (ultime) | Sommet | 2 | Sentence capitale : exécute sous 25 → 30, 35 % de vie | | |

**Chasseresse**

| Nœud | Étage | Rangs | Ce que donnent les rangs | Amélioration A | Amélioration B |
|---|---|---|---|---|---|
| Volée d'épines (offerte) | Base | 5 | dégâts 14 → 22 ; recharge 3,5 → 2,7 s | **Rafale droite** : épines serrées (8°), traversent 4 ennemis, portent à 620 u | **Tempête d'épines** : 9 épines sur 120°, 11 dégâts |
| Piège à mâchoires (offert) | Base | 5 | dégâts 30 → 50 ; immobilise 1,6 → 2 s | **Piège explosif** : souffle à 140 u, 55 dégâts, étourdit 0,8 s | **Champ de pièges** : 3 pièges par charge, 6 au plus |
| Œil de lynx (passif) | Base | 3 | +4 % de critique par rang | | |
| Brasier d'âmes | Cœur | 5 | brûlure 12 → 20 dégâts/s ; recharge 7 → 5,8 s | **Poix** : ralentit de 50 % dans les flammes | **Pot explosif** : 60 dégâts à 120 u, étourdit 1 s, plus de flammes |
| Totem de givre | Cœur | 5 | dégâts 7 → 11 ; dure 6 → 8 s | **Totem de foudre** : ne ralentit plus, 16 dégâts toutes les 0,4 s | **Totem gardien** : efface les tirs ennemis à chaque impulsion |
| Traits lourds (passif) | Cœur | 3 | dégâts des compétences à recharge +8 % par rang | | |
| Carquois profond (passif) | Cœur | 1 | +1 charge à chaque compétence à charges | | |
| Nuée de traits (ancien Super) | Maîtrise | 5 | recharge 22 → 18 s ; dégâts 8 → 12 | **Acharnement** : tout sur la cible la plus proche, 13 dégâts | **Averse** : 6 cibles, un trait toutes les 0,06 s, 7 dégâts |
| Jambes de biche (passif) | Maîtrise | 2 | la roulade revient 8 % plus vite par rang | | |
| Souffle long (passif) | Maîtrise | 2 | vitesse +4 % par rang | | |
| Troisième roulade (déplacement) | Sommet | 1 | +1 charge de roulade | | |
| Grande meute (ultime) | Sommet | 2 | Meute des Limbes : 3 → 4, 5 limiers | | |

**Respécialisation** : « Tout rendre » rend tous les points de la classe contre **80 + 30 × points
dépensés** en or. Rangs achetés et améliorations s'effacent, les rangs offerts restent ; un
emplacement qui tenait une compétence redevenue verrouillée est VIDÉ.

**Migration du profil** (`PROFILE_SCHEMA` 4 → 5, `sim/tree.gd : migrate`) :

- chaque compétence déjà débloquée garde son rang 1, OFFERT (hors budget) ; les Âmes dépensées ne
  sont ni reprises ni rendues ; les emplacements ne bougent pas ;
- l'AVANCE, pour ne pas repartir de zéro : la classe PORTÉE reçoit l'expérience que le profil
  prouve — chaque ennemi tué (`stats.kills`) et chaque Gardien vaincu (`guardians`), au tarif de base,
  sans bonus de profondeur — et un point par modèle de Gardien déjà vaincu. Les autres classes
  partent du niveau 1 : le profil ne dit pas avec laquelle il a joué. (La proposition de départ ne
  comptait que les Gardiens : le vrai profil aurait eu le niveau 6 au lieu de 12. À TRANCHER.)
- le vrai profil du joueur (au schéma 3 sur le disque : étage 126, Bourreau, 1 598 ennemis tués,
  8 Gardiens vaincus de 4 modèles) arrive au schéma 5 avec : Bourreau **niveau 12** (263 / 315),
  **15 points** à dépenser (11 de niveaux, 4 de Gardiens), Bond, Cri, Chaîne et Bombe au rang 1
  offert, emplacements Bond / Cri / Chaîne inchangés, Âmes, or et coffre intacts ; Revenant et
  Chasseresse au niveau 1.

**En partie.** À la création de la partie, les rangs et l'amélioration de chaque compétence de la
classe jouée sont écrits dans les réglages de la partie ; les passifs s'ajoutent aux statistiques à
chaque calcul, à côté du Sanctuaire ; les bénédictions s'ajoutent par-dessus comme avant. Un arbre
vide ne change RIEN (prouvé : `v3_arbre`, « un arbre vide laisse les réglages… », et les références).

**Lecture pour l'affichage** (aucune règle dans l'UI) : `D6Profile.tree_view`, `tree_buy`,
`tree_choose`, `tree_respec`, `tree_points` ; `D6Profile.slot_choices` rend `rank` à la place de `cost`.

**Affichage (simple, exprès).** Grimoire : les trois emplacements en haut (inchangés), puis « Arbre
de compétences » — niveau, barre d'expérience, points — et l'arbre en liste par étage : une carte par
nœud (rang, texte du rang actuel et du suivant, « + » grisé avec sa raison, les deux améliorations),
« Tout rendre (N or) » en deux appuis. L'onglet devient « Grimoire ● » quand des points attendent.
Écran de mort : « Expérience de classe : +N » et « Niveau N ! +1 point à dépenser au Grimoire » ;
écran de victoire : l'expérience et le niveau. Un niveau passé sonne l'accord du checkpoint.
Captures : `_dev/captures/lot_v3_arbre/` (`capturer.sh`).

**Bots, puissance, références.** Les oracles de jouabilité jouent toujours l'arbre vide (base
comparable). `outils/arbre.gd` mesure arbre vide contre arbre plein (`_dev/rapports/arbre.md`) : en
section 1, l'arbre plein nettoie une salle 11 à 19 % plus vite, bat le Gardien 27 à 42 % plus vite,
et prend 2 à 10 fois moins de dégâts. Références : l'expérience entre dans l'empreinte par les
événements `levelUp` et `treePoint` (17 parties sur 85 en écart, AUCUNE hors de ces deux événements :
prouvé partie par partie avant de réenregistrer) ; 6 parties `arbre_*` ajoutées, jouées avec un arbre
rempli (91 au total).

**PAS FAIT** (lot suivant, « le bel écran ») : un vrai dessin d'arbre (étages en colonnes, liens,
pictogrammes des passifs) ; un retour en jeu au niveau passé (rien ne s'affiche pendant le combat) ;
l'expérience dans le HUD ; un dessin propre à chaque amélioration (l'explosion de la Lance, le sol en
feu de la Nova réutilisent les effets existants ; la Chaîne traversante, l'aspiration, le Totem
gardien n'ont pas d'effet à eux) ; la confirmation d'une amélioration exclusive (elle se prend en un
appui) ; la capture d'une compétence au rang 1 et au rang 5 en jeu.

**À juger par Pierre** : tous les nombres ci-dessus ; le rang 3 pour le choix ; les 26 améliorations
(noms, effets) ; l'ancien Super en compétence invulnérable ; le double emploi Chaîne / Bombe entre
Revenant et Bourreau (mêmes nœuds, arbres séparés) ; l'arbre qui ne se remplit pas en entier ; le
prix de la respécialisation ; l'avance donnée à la migration (ennemis tués + Gardiens, ou Gardiens
seuls) ; la puissance de l'arbre plein.

## Étape 4 « Contenu » — ce qui est FAIT (2026-10-05)

Règles (`sim/kit_neuves.gd` et une famille par classe : `sim/neuves_revenant.gd`,
`sim/neuves_bourreau.gd`, `sim/neuves_chasseresse.gd`), données (`data/classes.json`,
`data/arbres.json`), bots, affichage dans le monde, pictogrammes, sons, tests, références.
**Trois compétences neuves par classe : neuf en tout** (le plan en visait douze : trois finies par
classe ont été préférées à quatre bâclées — ce qui manque est dit plus bas). Chaque classe a
maintenant **huit compétences** dans son arbre, pour trois emplacements. TOUS les noms et TOUS les
nombres sont des PROPOSITIONS, à renommer et à régler par Pierre.

**Revenant** (mêlée vive, mobile)

| Compétence | Sorte | Étage | Ce qu'elle fait | Rang 1 | Rang 5 | Amélioration A | Amélioration B |
|---|---|---|---|---|---|---|---|
| **Sillage de braise** | charges | Base | Pendant 5 s, ses pas et son dash sèment des braises au sol : ce qui y passe brûle. | 3 charges ; braises de 14 dégâts/s, 3 s chacune | 4 charges ; 22 dégâts/s | **Braises tenaces** : elles brûlent 6 s et s'étalent à 62 u | **Détonation** : quand le sillage s'éteint, chaque braise encore allumée explose (30 dégâts à 70 u, une fois par ennemi) |
| **Stigmate** | recharge | Cœur | Un trait MARQUE le premier ennemi touché pendant 6 s ; s'il meurt marqué, il explose. | trait 18, explosion 45 à 110 u ; recharge 8 s | trait 34, explosion 85 ; 6 s | **Contagion** : l'explosion marque à son tour ses survivants | **Moisson** : le marqué qui explose rend 6 PV et la moitié de la recharge |
| **Contre-taille** | recharge | Maîtrise | Une taillade, puis 0,6 s de garde : le premier coup reçu est PARÉ (aucun dégât) et rendu autour de lui ; le tir paré est détruit. | taillade 20, riposte 50 à 130 u, étourdit 0,8 s ; recharge 6 s | taillade 36, riposte 90 ; 4,4 s | **Miroir des damnés** : garde de 1 s, le tir paré est renvoyé à son tireur, les tirs proches sont effacés | **Représailles** : parade réussie = recharge −75 % et +30 % de dégâts pendant 4 s |

**Bourreau** (lourd, contrôle)

| Compétence | Sorte | Étage | Ce qu'elle fait | Rang 1 | Rang 5 | Amélioration A | Amélioration B |
|---|---|---|---|---|---|---|---|
| **Faille** | recharge | Base | Il frappe le sol : une fissure court sur 360 u devant lui, blesse et étourdit 0,6 s tout ce qui s'y tient. Un pilier l'arrête, pas une rivière. | 28 dégâts ; recharge 7 s | 48 ; 5,8 s | **Réplique** : une seconde secousse sur la même ligne 0,7 s plus tard (60 % des dégâts) | **Gouffre** : la fissure reste ouverte 4 s et ralentit de 50 % ceux qui s'y tiennent |
| **Hache du supplice** | recharge | Cœur | Une hache lancée à 380 u qui REVIENT dans sa main : elle traverse tout, frappe à l'aller puis au retour. | 24 + 24 dégâts ; recharge 6 s | 40 + 40 ; 4,8 s | **Reprise** : la rattraper réduit la recharge de 50 % | **Tournoiement** : au bout de sa course elle tournoie 1,5 s (50 % des dégâts toutes les 0,3 s, à 70 u) |
| **Garde de fer** | charges | Maîtrise | Un coup de bouclier qui repousse, puis 3,5 s de garde : un coup reçu de FACE est réduit de 60 % et son auteur repoussé. Le dos reste nu. | 2 charges ; bouclier 12 dégâts à 110 u | 3 charges ; à 150 u | **Épines de fer** : l'attaquant paré prend 14 dégâts et est étourdi 0,5 s | **Contrecoup** : à la fin, une onde rend 1,5 fois ce qui a été encaissé (120 au plus) à 170 u |

**Chasseresse** (distance, placement)

| Compétence | Sorte | Étage | Ce qu'elle fait | Rang 1 | Rang 5 | Amélioration A | Amélioration B |
|---|---|---|---|---|---|---|---|
| **Marque de la proie** | recharge | Base | Un trait MARQUE le premier ennemi touché pendant 6 s : il subit plus de dégâts, la visée assistée le préfère, les limiers de la Meute se jettent sur lui. | +25 % de dégâts subis ; recharge 9 s | +45 % ; 7 s | **Curée** : si la proie meurt, la marque saute sur le plus proche (320 u), deux fois au plus | **Battue** : tous les ennemis à 150 u du premier touché sont marqués |
| **Leurre d'os** | charges | Cœur | Un épouvantail d'os lancé jusqu'à 300 u, pour 6 s : les ennemis de mêlée proches se jettent sur lui, il arrête les tirs. Deux au plus. | 2 charges ; attire à 260 u | 3 charges ; à 340 u | **Leurre piégé** : détruit ou à bout de temps, il explose (50 dégâts à 120 u, étourdit 0,8 s) | **Épouvantail** : il étourdit 1,2 s ce qui l'entoure en apparaissant, et encaisse le double |
| **Trait de Nemrod** | recharge | Maîtrise | Un appui : elle BANDE son arc 0,9 s (elle marche au ralenti), puis le trait part seul et traverse tout jusqu'à 720 u. Un second appui le lâche tout de suite, moins fort. | 80 dégâts ; recharge 7 s | 112 ; 5,8 s | **Clouage** : à pleine charge, il étourdit 1,4 s ce qu'il traverse | **Trait vif** : l'arc se bande en 0,45 s, le trait ne porte plus qu'à 560 u |

**Chaîne et Bombe : à chaque classe sa version.** Elles étaient identiques chez le Revenant et le
Bourreau. Choix pris : on garde les deux compétences chez les deux (le vrai profil du joueur les
possède), le RANG 1 reste commun (les nombres de `classes.json`), et ce qui se CHOISIT diffère :

| | Revenant | Bourreau |
|---|---|---|
| Chaîne — rangs 2 à 5 | dégâts 20 → 32 ; recharge 4,7 → 3,8 s ; portée 450 → 510 u (inchangé) | dégâts 22 → 40 ; recharge 4,8 → 4,2 s ; portée fixe (plus lourde, moins vive) |
| Chaîne — améliorations | **Ferrage** (gardé) OU **Croc de boucher** (neuf) : chaîne courte de 280 u, 46 dégâts, étourdit 1,4 s | **Chaîne traversante** (gardée) OU **Rafle** (neuf) : elle ramène contre lui jusqu'à 3 ennemis — le crochet de groupe |
| Bombe — rangs 2 à 5 | dégâts 51 → 69 ; rayon 126 → 144 u (inchangé) | dégâts 55 → 85 ; étourdit 0,7 → 1 s ; rayon fixe |
| Bombe — améliorations | **Grappe** (gardée) OU **Poix ardente** (neuf) : le sol brûle 4 s après le souffle (16 dégâts/s) | **Fumigène** (gardé) OU **Baril** (neuf) : mèche de 0,7 s, souffle à 190 u, recul 1 100 |

Des tests existants jouent « ferrage » et « grappe » avec le Revenant, « traversante » et « fumigène »
avec le Bourreau : chaque classe a donc gardé celle-là et reçu une amélioration neuve à la place de
l'autre. Conséquence pour un joueur : un Revenant qui avait pris « Chaîne traversante » ou
« Fumigène » (un Bourreau : « Ferrage » ou « Grappe ») retrouve son choix LIBRE, sans rien perdre
d'autre (une amélioration inconnue est écartée à la lecture du profil).

**L'arbre, mis à jour** (N = compétence neuve ; les passifs, le déplacement et l'ultime n'ont pas bougé)

| Étage (points à dépenser avant) | Revenant | Bourreau | Chasseresse |
|---|---|---|---|
| Base (0) | Lance (offerte), Nova (offerte), **Sillage de braise (N)**, passif Sang vif | Bond (offert), Cri (offert), **Faille (N)**, passif Cuir épais | Volée (offerte), Piège (offert), **Marque de la proie (N)**, passif Œil de lynx |
| Cœur (5) | Chaîne, Bombe, **Stigmate (N)**, passifs Grimoire brûlant, Pas de l'ombre | Chaîne, Bombe, **Hache du supplice (N)**, passifs Bourreau des sonnés, Bras de fer | Brasier, Totem, **Leurre d'os (N)**, passifs Traits lourds, Carquois profond |
| Maîtrise (12) | Tourbillon de colère, **Contre-taille (N)**, passifs Fureur damnée, Tranchant | Triple sentence, **Garde de fer (N)**, passifs Billot, Jugement hâtif | Nuée de traits, **Trait de Nemrod (N)**, passifs Jambes de biche, Souffle long |
| Sommet (20) | Dash long, Forme tenace | Saut leste, Sentence sans appel | Troisième roulade, Grande meute |

Seuils d'étages et total de points : **inchangés** (0 / 5 / 12 / 20 ; 33 points au plus). L'arbre
entier coûte maintenant 52 ou 53 points (il en coûtait 37 ou 38) : on en remplit moins des deux
tiers, exprès — c'est le « vrai choix de trois parmi beaucoup ».

**Le geste du Trait de Nemrod (la compétence qui se charge).** Choix : **l'entrée d'un pas n'a PAS
changé** (aucun champ ajouté à `D6Game.empty_input` : ni `jeu/entrees/`, ni le codec des références,
ni les bots n'ont eu à bouger). Un appui commence la charge ; à pleine charge le trait part seul ;
un SECOND appui sur le même bouton le lâche aussitôt, d'autant moins fort qu'il est tôt (de 35 % à
100 % des dégâts) ; un dash ou l'ultime le lâche de même. Sans visée manuelle, elle vise au moment
où le trait part. Pas de « maintenir puis relâcher » : il aurait fallu un champ « bouton tenu » par
emplacement, de bout en bout. À JUGER EN MAIN : si le maintien manque, c'est un lot à part.

**Règles communes.**

- Les neuves passent par les chemins existants : recharge et tampon des compétences, charges
  rendues par section et par élite tué, tirs et zones de la salle, alliés de `game.allies`. Leurs
  dégâts sont de source « compétence » ou « à charges » : bénédictions, objets et procs (dégâts et
  recharge des compétences, charges en plus, « Vos compétences… ») s'y appliquent sans rien savoir d'elles.
- **Terrain bas** : aucune braise dans une rivière ni sur un obstacle (le dash passe au-dessus : il
  n'y sème rien) ; le leurre lancé par-dessus l'eau recule jusqu'à la rive, et sans aucune place la
  charge n'est PAS dépensée ; la fissure passe sous une rivière mais s'arrête à un pilier ; la hache
  vole au-dessus de l'eau, un mur la renvoie.
- **Le leurre est un allié** (`game.allies`, comme les limiers) : jamais compté comme ennemi (vagues,
  ennemis restants, salle nettoyée). Il n'est PAS un ultime : il ne tient pas la jauge et ne bloque
  pas le lancer de la Meute. Un tireur et un Gardien ne se détournent pas vers lui.
- **Parade et garde** s'interposent dans le seul chemin qui blesse le héros (`D6Combat.damage_player`),
  après l'invulnérabilité : un coup paré ne blesse pas, un coup bloqué de face est réduit avant l'armure.
- **Marques** : posées AVANT le coup du trait qui marque (un ennemi achevé par le Stigmate explose ;
  le trait de la Marque profite déjà de la vulnérabilité qu'il pose).
- Mort, changement de salle, reprise : plus de sillage, de garde, de parade, de leurre ni de hache
  en vol ; l'arc qui se bandait est détendu, rien ne part.
- Lecture pour l'affichage : `D6Loadout.slot_view` garde EXACTEMENT sa forme (un test existant la
  fige) ; ce que les neuves ajoutent se lit par `D6Loadout.slot_state(game, i)` = `{charging,
  chargeFrac, active, activeFrac}`.

**Bots.** Ils jouent les neuves avec ce qu'un joueur voit : une compétence visée part sur la
meilleure ligne (comme la Lance) ; la Contre-taille se lève face à un ennemi qui ARME son coup ;
une marque n'est pas reposée tant qu'un ennemi la porte ; le Sillage se sème dès que deux ennemis
approchent, la Garde de fer aussi ; le Leurre dès deux ennemis s'il reste une place. Le Trait : un
appui, et le bot attend la pleine charge. Les oracles de jouabilité jouent toujours le kit de départ.

**Valeur de chaque compétence neuve** (`outils/arbre.gd`, `bash outils/arbre.sh 10` : 10 graines, bot habile,
section 1 ; kit de départ — deux emplacements — contre le même kit avec la compétence dans le
troisième, au rang 1 puis au rang 5, sans amélioration). Entre parenthèses : rapporté au kit de départ.

| Classe | Compétence | Rang | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien | Lancers |
|---|---|---|---|---|---|---|---|
| Revenant | (kit de départ) | — | 100 % | 4.2 | 15.6 s | 49.0 s | 110 |
| Revenant | Sillage de braise | 1 | 100 % | 3.3 (×0.78) | 14.7 s (×0.94) | 46.3 s (×0.95) | 120 |
| Revenant | Sillage de braise | 5 | 100 % | 4.0 (×0.96) | 13.8 s (×0.88) | 55.2 s (×1.13) | 120 |
| Revenant | Stigmate | 1 | 100 % | 3.7 (×0.88) | 14.9 s (×0.96) | 44.6 s (×0.91) | 133 |
| Revenant | Stigmate | 5 | 100 % | 4.8 (×1.15) | 13.6 s (×0.87) | 44.9 s (×0.92) | 136 |
| Revenant | Contre-taille | 1 | 100 % | 4.1 (×0.97) | 14.8 s (×0.95) | 46.7 s (×0.95) | 130 |
| Revenant | Contre-taille | 5 | 100 % | 4.5 (×1.08) | 14.3 s (×0.91) | 52.3 s (×1.07) | 142 |
| Bourreau | (kit de départ) | — | 100 % | 9.6 | 13.0 s | 42.0 s | 57 |
| Bourreau | Faille | 1 | 100 % | 9.7 (×1.00) | 12.0 s (×0.92) | 39.1 s (×0.93) | 89 |
| Bourreau | Faille | 5 | 90 % | 12.7 (×1.32) | 11.6 s (×0.90) | 37.8 s (×0.90) | 91 |
| Bourreau | Hache du supplice | 1 | 90 % | 9.8 (×1.02) | 11.7 s (×0.90) | 33.9 s (×0.81) | 93 |
| Bourreau | Hache du supplice | 5 | 100 % | 6.3 (×0.66) | 11.2 s (×0.86) | 33.0 s (×0.79) | 100 |
| Bourreau | Garde de fer | 1 | 100 % | 6.4 (×0.66) | 12.7 s (×0.98) | 40.8 s (×0.97) | 65 |
| Bourreau | Garde de fer | 5 | 80 % | 9.3 (×0.97) | 12.7 s (×0.98) | 34.2 s (×0.82) | 67 |
| Chasseresse | (kit de départ) | — | 100 % | 0.6 | 12.2 s | 30.0 s | 76 |
| Chasseresse | Marque de la proie | 1 | 100 % | 0.4 (×0.71) | 11.7 s (×0.96) | 28.3 s (×0.94) | 99 |
| Chasseresse | Marque de la proie | 5 | 100 % | 0.9 (×1.61) | 11.8 s (×0.97) | 23.0 s (×0.77) | 102 |
| Chasseresse | Leurre d'os | 1 | 100 % | 0.3 (×0.51) | 12.0 s (×0.98) | 27.5 s (×0.92) | 79 |
| Chasseresse | Leurre d'os | 5 | 100 % | 0.7 (×1.30) | 12.9 s (×1.06) | 38.0 s (×1.27) | 90 |
| Chasseresse | Trait de Nemrod | 1 | 100 % | 0.8 (×1.51) | 12.2 s (×1.00) | 27.9 s (×0.93) | 109 |
| Chasseresse | Trait de Nemrod | 5 | 100 % | 1.0 (×1.82) | 12.2 s (×1.00) | 28.2 s (×0.94) | 115 |

Lecture, sans embellir. Le TEMPS PAR SALLE est la mesure la plus stable : aucune compétence ne
l'écrase (les plus fortes — Hache du supplice, Stigmate et Sillage au rang 5 — gagnent 12 à 14 %),
aucune ne le dégrade nettement. Les DÉGÂTS REÇUS et la SECTION BATTUE bougent encore beaucoup d'une
mesure à l'autre avec 10 graines (le Bourreau au kit de départ est mesuré à 95 % de sections
battues sur 20 graines par l'oracle des classes) : les trois lignes du Bourreau à 80 ou 90 % sont
deux ou une mort sur dix, pas une preuve — à remesurer avec plus de graines avant de régler. Ce qui
revient dans les DEUX mesures faites (6 puis 10 graines) : le Leurre d'os divise les dégâts reçus au
rang 1 (×0,36 puis ×0,51) ; au rang 5 le combat du Gardien est plus LONG avec lui (×1,59 puis
×1,27) — non expliqué, à regarder ; la Contre-taille ne change presque rien AU BOT (il pare
rarement : c'est une compétence de main, à juger en jouant). Corrections faites après la première
mesure : **Trait de Nemrod 60 → 80 dégâts** (rangs 68…92 → 88…112) — à 60 il rapportait moins que
les flèches que la Chasseresse ne tire pas pendant qu'elle bande l'arc (combat du Gardien ×1,30 ;
après : ×0,93) ; le bot lève la Garde de fer dès deux ennemis proches (il attendait trois ennemis
au contact et ne s'en servait presque pas). Première mesure gardée pour comparaison :
`_dev/rapports/arbre_mesure_1_6_graines.md`.

**Affichage** (`jeu/monde/competences.gd`, `tirs.gd`, `zones_heros.gd`, `creatures/limiers.gd`,
`jeu/effets/competences.gd`, `jeu/son/routage.gd`, `jeu/interface/icones.gd`) — aucune règle dans
l'affichage, tout est lu ; teintes froides du héros, jamais le rouge des dangers.

- Sillage : un chapelet de petits foyers bleus (pas l'anneau des grandes zones), deux flammèches aux
  talons du héros et l'arc du temps qui reste. Stigmate : un fer court en vol, puis sur l'ennemi un
  anneau de braise claire à trois dents qui tourne, avec l'arc du temps ; l'explosion est une onde
  froide. Contre-taille : un cercle blanc tendu autour de lui qui se vide ; « PARÉ » et l'onde de la riposte.
- Faille : une lézarde noire aux lèvres de givre le long de la ligne, des gravats ; ouverte
  (« gouffre »), sa bande sombre reste ; en attente de réplique, son contour bat. Hache : elle tourne
  sur elle-même au-dessus de son ombre ; en tournoiement, le cercle qu'elle fauche est dit. Garde de
  fer : un arc épais DEVANT lui (le dos nu se voit), « BLOQUÉ » à chaque coup réduit.
- Marque de la proie : un réticule cyan à quatre crochets et une pointe au-dessus de la tête. Leurre :
  un épouvantail d'os à la teinte de l'héroïne, sa barre de vie, l'arc de sa durée, le cercle fin de
  son attirance. Trait : la ligne de visée s'allonge et s'épaissit avec la charge, tout blanchit à
  pleine charge ; le trait est le plus long et le plus épais des tirs.
- Neuf pictogrammes : `sillage`, `stigmate`, `riposte`, `faille`, `hachette`, `garde`, `proie`,
  `leurre`, `trait`. Sons : sur les recettes existantes (parade pour un coup paré ou bloqué, choc
  pour la fissure, accord bref pour une marque et la hache rattrapée).
- Captures : `_dev/captures/lot_v3_competences/` (banc `jeu/essai/competences.tscn`, mode d'emploi
  en tête de `jeu/essai/competences.gd`) : chaque classe au rang 1, puis avec chaque jeu d'améliorations.

**Tests.** `tests/regles/v3_competences.gd` : 62 tests (effet de base, rangs, les deux améliorations
et leur exclusion, salle vide, Gardien, terrain bas, mort, changement de salle, bénédictions et
objets, déterminisme ; le leurre : jamais dans l'eau sur 300 graines, salle nettoyée bien comptée).
Le test générique des rangs de `v3_arbre.gd` joue de lui-même les neuf nœuds neufs (+9 tests).
Un test existant adapté (la liste des compétences d'une classe : `design/COMBAT_V3_TESTS_ADAPTES.md`).
Ce que les tests ne disent pas : le plaisir du geste, la lisibilité en plein combat.
652 tests de règles en tout.

**Références.** Arbre vide et kit de départ inchangés : **89 parties existantes sur 91 sont identiques au bit près**. Les 2 en écart, `arbre_hasard_dagues` et `arbre_hasard_marteau`, sont les seules qui jouent la Chaîne et la Bombe au rang 3 avec une amélioration : leur spec a changé d'amélioration de Bombe (« fumigène » et « grappe » ont changé de classe) et les rangs du Bourreau ont changé — écart voulu. 9 parties `competences_*` ajoutées (chaque classe avec ses trois neuves, par le bot habile puis au hasard, chaque amélioration d'un côté ou de l'autre ; les versions par classe de Chaîne et Bombe ; une partie au rang 1 ; deux parties au hasard sans héros invulnérable, où une parade et un blocage réussissent) : **100 parties**. Réenregistrées une fois (`bash references/enregistrer.sh`), puis les deux dernières parties ajoutées seules.

**PAS FAIT.** La quatrième compétence par classe (pistes restantes : double spectral du Revenant,
pluie de flèches à retardement et faucon de la Chasseresse ; pour le Bourreau, le « crochet de
groupe » est devenu l'amélioration Rafle de sa Chaîne). Le maintien du bouton pour charger (voir le
geste ci-dessus). Le HUD ne montre pas encore la charge du Trait ni la durée d'un sillage ou d'une
garde SUR le bouton (`slot_state` le rend ; `jeu/interface/` est tenu par un autre lot) : cela se
lit dans le monde, autour du héros. Le leurre n'attire pas les tireurs. Aucun son propre.

**À juger par Pierre** : les neuf noms et tous les nombres ; l'étage de chacune ; le geste du Trait
(un appui, second appui) ; la Contre-taille qui pare même un coup mortel ; la Garde de fer qui ne
couvre que la face ; le Stigmate inutile contre un Gardien seul (il ne meurt pas) ; le leurre que
les tireurs ignorent ; les versions par classe de la Chaîne et de la Bombe ; les teintes froides de
toutes ces marques et zones ; l'arbre rempli aux deux tiers au plus ; la quatrième compétence.

## Écran de l'arbre — ce qui est FAIT (2026-10-05)

Affichage seulement (`jeu/ville/`, `jeu/interface/`, `jeu/ecrans/`, `jeu/theme/`). Aucune règle, aucun
nombre, aucune donnée changés : tout est LU dans `D6Profile.tree_view`, `slot_choices`, `tree_points`,
`D6Loadout.slot_state`. Preuves à l'écran : `_dev/captures/lot_v3_ecran_arbre/` (`capturer.sh`, banc
`jeu/ville/banc_arbre.tscn`). TOUT ce qui suit est à juger par Pierre.

**Le Grimoire est l'écran de l'arbre** (`jeu/ville/onglet_grimoire.gd`), en trois colonnes qui tiennent
SANS défiler en 1280 × 720 :

```
 [7] points à dépenser   BASE      (o)──(o)──(o)──<>          COMPÉTENCE          ● Emplacement 1
 Niveau 8 / 30           Ouvert     ¦    ¦    ¦               Lance infernale        Rang 3 / 5
 ▬▬▬▬▬▬▬▬▬▬▬▬▬                      °°   °°   °°              Projectile qui transperce…
 0 / 215 d'expérience    CŒUR      (o)──(o)──(o)──<>──<>      Rang 3 : 38 dégâts, recharge 3,6 s.
                         2 / 5 points   │                     → Rang 4 : 42 dégâts, recharge 3,4 s.
   (2)  (3)              dépensés       │                     [        Améliorer        ]
 (1)                     MAÎTRISE  (o)──(o)──<>──<>           AMÉLIORATIONS · UNE SEULE
      (ATT) (DASH)       SOMMET       [▽]──[▽]                ◇ Transperce tout        [Choisir]
                         [Tout rendre (140 or)]               ◇ Explose à l'impact     [Choisir]
                                                              Placer en          [1] [2] [3]
```

- **Sens : étages en BANDES de haut en bas, le long d'un TRONC.** Pourquoi : l'écran est large et bas ;
  une bande par étage laisse jusqu'à 8 nœuds de front, et le panneau de détail garde toute la hauteur à
  droite. Le tronc se REMPLIT D'OR jusqu'où l'arbre est ouvert ; vers le premier étage fermé, la part
  des points déjà dépensés. À gauche de chaque bande : le nom de l'étage, « Ouvert » ou un cadenas et
  « 2 / 5 points dépensés ».
- **Mise en page seule** (`jeu/ville/arbre.gd`) : de 1 à 8 nœuds par étage (et plus : au-delà de ce qui
  tient de front, l'étage se replie sur deux rangées). Médaillons de 27 à 38 px, place d'au moins 44 px
  par nœud (cible du doigt). Le panneau prend la largeur dont l'arbre n'a pas besoin (276 à 360 px).
- **Petit téléphone (844 × 390)** : les mêmes trois colonnes ; SEUL l'arbre défile, de haut en bas ;
  points, niveau, arc des emplacements et panneau restent à l'écran (le panneau défile en lui-même
  quand son texte est long) ; la note d'en-tête cède sa ligne. La note de pied de la Ville s'efface dans le Grimoire, à toute taille.
  Portrait (toléré) : les trois blocs s'empilent et la page de la Ville défile.
- **Un nœud est un médaillon** (`jeu/ville/arbre_dessin.gd`), dessiné par le lot de triangles (tout
  l'arbre : UN appel de dessin, plus ses textes) :

| Se lit | Comment |
|---|---|
| sorte | rond = compétence · losange = passif · écusson = déplacement, ultime |
| pictogramme | celui du bouton en jeu (`jeu/interface/icones.gd`) ; passif : dix pictogrammes neufs (`jeu/ville/icones_arbre.gd` : cœur, cible, sablier, plumes, bouclier, charge, lame, couronne, poing, étoile) |
| rang | compétence : l'anneau, coupé en autant de segments que de rangs, dorés quand ils sont pris ; autres : des pastilles sous la forme |
| verrouillé (étage fermé) | éteint, cerné de gris, pictogramme à peine visible |
| ouvert, rien à dépenser | cerne clair, pictogramme gris |
| acquis | fond de braise, cerne et pictogramme clairs |
| achetable | cerné d'or, il BAT doucement (halo et lueur), qu'il soit déjà acquis ou non |
| au maximum | tout en or, plus rien ne bat |
| choisi (touché, ou sous le focus) | un cercle clair autour |
| placé | une pastille bleue au numéro de l'emplacement (1, 2, 3) |

- **Les deux améliorations exclusives** pendent sous leur compétence, en fourche : pas encore offertes
  (creuses, grises), offertes (cernées d'or, elles battent), prise (pleine, en or), l'autre BARRÉE.
- **Panneau de détail** (`jeu/ville/panneau_noeud.gd`), à droite : sorte, nom, « Rang 3 / 5 », ce que la
  chose EST (texte de la compétence ; nom et texte du déplacement ou de l'ultime de la classe), le rang
  ACTUEL, le rang SUIVANT précédé de « → » avec en or gras les mots qui changent, le bouton
  « Apprendre » / « Améliorer » — grisé avec la raison des règles écrite dessous (« Aucun point à
  dépenser », « Étage Cœur fermé : 5 points à dépenser d'abord », « Rang maximal ») —, les deux
  améliorations (« Choisir »), et pour une compétence acquise « Placer en 1 / 2 / 3 » (celui qu'elle
  occupe est doré). Toucher un emplacement de l'ARC montre l'emplacement : ce qu'il porte, « Vider » ;
  il attend alors une compétence (la toucher dans l'arbre l'y place).
- **Confirmations** : une amélioration exclusive se prend en DEUX appuis — « Choisir » devient
  « Confirmer » (rouge) sous la phrase « Ce choix est définitif, sauf à tout rendre. » ; regarder un
  autre nœud annule. « Tout rendre (N or) » : deux appuis aussi, avec « Tous les points reviennent ; les
  améliorations choisies sont effacées. ».
- **Clavier et manette** : chaque nœud est un vrai bouton ; les flèches ou la croix passent de nœud en
  nœud (voisin de rangée, nœud le plus proche de la rangée voisine) et le panneau suit le focus ; Entrée
  / A sur un nœud porte le focus sur « Apprendre » / « Améliorer », Entrée encore achète ; Échap / B
  depuis le panneau revient au nœud (sans quitter la Ville) ; Page préc. / suiv. changent d'onglet.
- **À l'ouverture**, le nœud choisi est le premier où un point peut être dépensé (sinon le premier).
- L'ancienne liste de cartes (arbre, « Placer une compétence », « Déplacement et ultime ») est RETIRÉE :
  il n'y a qu'un écran. La note d'en-tête (classe et emplacements) reste, sur une ligne.

**Retours de progression.**

- **HUD, barre d'expérience** : « NIV. 7 » et une barre fine, froide (la teinte du héros), SOUS LA VIE,
  de sa largeur. Pourquoi là : la vie et l'expérience sont l'état du HÉROS (coin haut-gauche) ; le
  centre parle du donjon (étage, fil, Gardien), la droite de la bourse. Lue dans `tree_view`, seulement
  quand l'expérience de la descente a bougé. Rien en arène ni à l'entraînement.
- **HUD, bandeau de niveau** (`jeu/interface/niveau.gd`, événements `levelUp` et `treePoint`) :
  « NIVEAU 7 · +1 point », petit, sur une ligne, sous la barre d'expérience, 2,8 s, en fondu ; la barre
  brille. Il prend la place des losanges des bénédictions le temps qu'il passe : il reste dans la bande
  du haut, jamais sur le combat ni dans le couloir des flèches d'ennemis hors champ.
- **Pastille de points** (`jeu/theme/pastille.gd`) : sur l'onglet Grimoire, sur « Entrer dans Dité » à
  l'écran titre, et en tête du Grimoire (« [7] points à dépenser »).
- **Écran de mort** : sous les deux cartes, « Revenant · niveau 2 · 5 / 65 », la barre où la part GAGNÉE
  dans la descente se détache (plus claire, elle se remplit à vue), « Expérience de classe : +45. » et,
  si un niveau est passé, « Niveau 2 ! +1 point à dépenser au Grimoire. ». Rien en arène.
- **Accueil du premier joueur** : en Ville, tant qu'aucun point n'a été dépensé, « Dépense ton point au
  Grimoire » (« tes points » s'il y en a plusieurs) sous les onglets — pas dans le Grimoire. Acquise au
  premier point dépensé ; coupée et revue par le réglage de la pause (`reglages.accueil`).
- **Compétences neuves, sur leur bouton** (`D6Loadout.slot_state`) : une action qui se bande (Trait de
  Nemrod) montre un anneau d'or qui se REMPLIT dans son bouton ; un effet qui dure (Sillage, Garde,
  parade) un anneau froid qui se VIDE.

**Ce que `tree_view` ne donne pas** (contourné dans l'affichage, à ajouter aux règles si l'on veut) :

- le pictogramme d'un PASSIF (`icon` vide), ou au moins sa statistique : il est choisi d'après les mots
  de son texte (« PV », « critique », « recharge »…), à défaut l'étoile ;
- l'identifiant de l'ACTION d'un nœud de compétence (`skill`) : pris égal à l'identifiant du nœud (vrai
  dans les données), à défaut au nom ;
- un LIEN entre nœuds (un passif qui renforce une compétence) et une place dans l'étage : il n'y en a
  pas dans les données ; les nœuds sont posés dans l'ordre rendu, tous sur la branche de leur étage ;
- une teinte par classe : `jeu/theme/couleurs.gd` n'en a pas, l'arbre n'en invente pas.

**Coût de dessin** (vraie fenêtre, mêmes données, `jeu/monde/mesure.gd`) : l'ancien Grimoire, haut de
page : 72 appels en 1280 × 720, 52 en 844 × 390 ; le nouveau, arbre ENTIER : 73 à 84 et 66 à 77 selon
l'état. Temps d'image 0,58 ms avant ; 0,58 ms après quand rien ne bat, 0,69 ms quand des nœuds battent
(l'arbre qui bat n'est redessiné que vingt fois par seconde).

**À juger par Pierre** : le sens (bandes de haut en bas) ; la taille des médaillons ; les trois formes ;
l'or pour « achetable » et « maximum » ; le battement ; les dix pictogrammes de passifs ; la fourche des
améliorations ; l'arc des emplacements réduit (45 % du jeu) ; la note de pied retirée du Grimoire ; les
deux appuis de confirmation ; la place et la taille de la barre d'expérience ; le bandeau de niveau
(assez visible ? trop ?) ; la consigne de la Ville.

## Étape 5 « Quatrième compétence, sons, profondeur » — ce qui est FAIT (2026-10-05)

Trois tâches, dans cet ordre. TOUS les noms et TOUS les nombres sont des PROPOSITIONS, à renommer et à
régler par Pierre.

### 1. La quatrième compétence neuve de chaque classe (neuf compétences par classe)

Mêmes fichiers de règles que l'étape 4 (`sim/kit_neuves.gd` et une famille par classe), données
(`data/classes.json`, `data/arbres.json`), bots, dessin, pictogrammes, sons, tests, références.
Toutes les trois à recharge, à l'étage de MAÎTRISE (12 points dépensés) : ce sont des idées qui
demandent de savoir jouer la classe, et cet étage n'avait que deux compétences. Seuils et total de
points inchangés (0 / 5 / 12 / 20 ; 33 points) : l'arbre entier coûte maintenant 57 ou 58 points.

| Classe | Compétence | Ce qu'elle fait | Rang 1 | Rang 5 | Amélioration A | Amélioration B |
|---|---|---|---|---|---|---|
| Revenant | **Ombre jumelle** (`ombre`) | Son ombre se détache là où il se tient et y reste 6 s : elle répète CHACUN de ses coups d'arme de sa place, vers l'ennemi le plus proche d'elle, à 50 % des dégâts. Intangible (rien ne la vise ni ne la blesse). Elle se dissipe s'il s'éloigne de plus de 520 u. | 22 dégâts à 90 u en surgissant ; recharge 14 s | 38 ; 12 s | **Ombre liée** : elle le SUIT à 44 u au lieu de rester en arrière, et ne se dissipe plus | **Transposition** : un second appui échange leurs places, invulnérable 0,4 s, une fois par ombre |
| Bourreau | **Décollation** (`grace`) | La hache s'abat à 70 u devant lui, sur tout ce qui est à 60 u du point d'impact ; dégâts × 2,5 sur un ennemi à 35 % de vie ou moins. Si le coup TUE, la recharge tombe à 0,5 s : il enchaîne. | 36 dégâts ; recharge 9 s | 60 ; 7 s | **Ivresse du billot** : un coup qui tue donne +30 % de dégâts pendant 4 s | **Effroi** : un coup qui tue étourdit 1,2 s les ennemis à 170 u de la victime |
| Chasseresse | **Grêle des Limbes** (`grele`) | Elle tire vers le ciel : 0,9 s plus tard les traits tombent à 110 u autour du point visé (jusqu'à 420 u). Ce qui s'y tient ENCORE est frappé. Un cercle allié (froid, jamais rouge) l'annonce au sol. | 55 dégâts ; recharge 8 s | 83 ; 6,4 s | **Déluge** : elle retombe 3 fois au même endroit, toutes les 0,5 s, les suivantes à 50 % | **Givre des Limbes** : ce qu'elle touche est ralenti de 50 % pendant 3 s |

Pourquoi ces trois-là.

- **Revenant — le double spectral** (piste du plan). Ce qu'il n'avait pas : un allié, et une raison
  de choisir OÙ il se bat (il revient frapper près de son ombre, ou la fait suivre). La
  « Transposition » en fait un outil de fuite.
- **Bourreau — le coup de grâce plutôt que la provocation.** Il a déjà de quoi encaisser et tenir la
  foule (Garde de fer, Cri, saut) ; une provocation aurait redit la Garde. Ce qui lui manquait : un
  RYTHME — chasser les ennemis affaiblis pour relancer son coup. Ce n'est pas une exécution : un
  Gardien prend le coup multiplié, il n'est jamais tué d'office.
- **Chasseresse — la pluie à retardement plutôt que le faucon.** Elle a déjà deux sortes d'alliés
  (limiers, leurre) ; un troisième n'aurait rien appris. La Grêle se PRÉVOIT : elle récompense le
  placement (piège, leurre, totem qui retiennent l'ennemi dessous).

Règles à savoir. L'ombre vit dans `game.allies` (jamais un ennemi, jamais un ultime : elle ne tient
pas la jauge), marquée `ghost` : aucun ennemi ne se tourne vers elle, un tir la traverse. Son coup
répété est un coup de compétence (bénédictions « de compétence »). L'ombre liée marche (jamais dans
l'eau : 300 graines) ; quand il a franchi une rivière, elle se rattache à ses pieds. L'échange est
refusé en plein franchissement. La Décollation frappe par-dessus un obstacle bas, comme tout coup.
La Grêle tombe où l'on vise, même au-dessus de l'eau (ce sont des tirs), jamais dans un mur ; une
grêle déjà tirée tombe même si elle meurt entre-temps ; visée à la main, elle tombe à 260 u (le bouton
donne une direction, pas un point — comme le Brasier et la Bombe). Mort, changement de salle : plus
d'ombre, plus de grêle en attente.

**Bots.** L'Ombre se détache dès qu'un ennemi est à portée de lame ; la Décollation est gardée pour
l'ennemi affaibli (ou un Gardien) ; la Grêle vise à la main l'endroit où le groupe SERA, et tombe
sur une cible qui ne bouge pas (Gardien, étourdi). Vérifié : le bot se sert de chacune.

**Valeur mesurée** (`bash outils/arbre.sh 10`, section 1, kit de départ contre le même kit avec la
compétence dans le troisième emplacement) :

| Compétence | Rang | Section battue | Dégâts reçus / salle | Temps par salle | Combat du Gardien |
|---|---|---|---|---|---|
| Ombre jumelle | 1 | 100 % | 3,5 (×0,82) | 14,8 s (×0,95) | 46,0 s (×0,94) |
| Ombre jumelle | 5 | 100 % | 3,2 (×0,76) | 14,3 s (×0,92) | 45,6 s (×0,93) |
| Décollation | 1 | 100 % | 8,9 (×0,92) | 12,1 s (×0,93) | 34,0 s (×0,81) |
| Décollation | 5 | 100 % | 8,5 (×0,89) | 12,0 s (×0,92) | 34,7 s (×0,83) |
| Grêle des Limbes | 1 | 100 % | 0,9 (×1,61) | 11,7 s (×0,96) | 30,4 s (×1,01) |
| Grêle des Limbes | 5 | 100 % | 1,0 (×1,71) | 11,3 s (×0,93) | 30,6 s (×1,02) |

Aucune n'écrase, aucune ne dégrade (les dégâts reçus de la Chasseresse sont au niveau du bruit : 0,6
contre 0,9 point de vie par salle). Les neuf d'avant donnent exactement les nombres de l'étape 4.
Le tableau « arbre plein » de `_dev/rapports/arbre.md` a bougé (×0,82 à ×0,90 en temps par salle) :
sa politique dépense un rang par nœud, donc trois points de moins ailleurs — ce n'est pas le jeu qui
a changé (rapport d'avant : `_dev/rapports/arbre_avant_lot5.md`).

**Affichage.** Ombre : la silhouette du héros sans visage, en nuit cernée de sa teinte froide, deux
yeux clairs, une lame qui FAUCHE quand elle répète un coup, l'arc de durée des alliés à ses pieds ;
l'échange est un trait d'éclair entre les deux places. Décollation : une onde courte au point
d'impact, des gravats, « ENCORE ! » quand le coup a tué ; l'Effroi est un anneau autour de la victime.
Grêle : cercle froid au sol, un anneau blanc qui grandit du centre jusqu'au bord (« ça tombe quand
il le touche »), les croix des traits qui descendent, puis les traits plantés. Trois pictogrammes :
`ombre`, `grace`, `grele`. Captures : `_dev/captures/lot_v3_lot5/` (banc `jeu/essai/competences.tscn`,
`D666_LOT=5`) — chaque compétence au rang 1, puis avec chaque amélioration (`_A`, `_B`) ;
`essais_graines/` : d'autres graines, mieux cadrées pour la Grêle et la Transposition.

**Tests.** `tests/regles/v3_competences_2.gd` : 28 tests (nœuds, rangs, les deux améliorations et
leur exclusion ; base ; salle vide, Gardien, terrain bas, mort pendant, changement de salle ;
bénédictions et objets de compétence ; formes de `empty_input`, `slot_view`, `slot_state` ;
déterminisme ; bots ; références ; l'ombre jamais dans l'eau sur 300 graines). Trois tests existants
adaptés, tous pour le NOMBRE de compétences (`design/COMBAT_V3_TESTS_ADAPTES.md`).

**Références.** Les 100 parties existantes sont identiques au bit près ; 6 parties `competences2_*`
ajoutées (chaque compétence par le bot habile avec une amélioration, puis au hasard avec l'autre) : 106.

### 2. Des sons propres au combat V3

38 recettes neuves, synthétisées comme les autres (`jeu/son/recettes.gd`), sobres exprès : niveaux
des recettes voisines, rien de strident, court pour ce qui se répète. `jeu/son/test_son.gd` : vert
(287 vérifications). **Personne ne les a écoutés** : les fichiers sont dans `_dev/sons/` (un `.wav` par
recette, `sommaire.txt` dit ce qui déclenche chacune).

| À écouter (`_dev/sons/<nom>.wav`) | Ce qui le déclenche |
|---|---|
| `ultime_pret` | la jauge d'ultime devient pleine — LE signal : « pense à tenir le bouton » (une charge rendue par un élite garde l'ancien accord, `super_pret`) |
| `ultime_armement` | l'attaque est TENUE jauge pleine : montée de 0,4 s, coupée net si l'on relâche |
| `super_forme`, `forme_hurlement`, `forme_embrasement`, `forme_fin` | Forme du Damné : transformation, hurlement, embrasement, fin de la forme (la ruée garde le son du dash) |
| `super_magie`, `sentence_gel`, `sentence_fracas`, `sentence_eclair`, `sentence_execution` | Sentence capitale : lame levée, temps figé, fracas, un éclair par ennemi, lame qui tombe sur un exécuté |
| `super_meute`, `meute_apparition`, `meute_morsure` | Meute des Limbes : le cor, un limier qui surgit, une morsure (très courte, basse) |
| `deplacement_saut`, `saut_atterrissage`, `deplacement_roulade` | saut du Bourreau (décollage, atterrissage), roulade de la Chasseresse (le dash garde son son) |
| `franchissement` | le héros passe au-dessus d'une rivière ou d'un obstacle bas |
| `niveau` | un niveau de classe est passé (avant : l'accord du checkpoint) |
| `point_arbre` | un point est dépensé dans l'arbre, au Grimoire |
| `gadget_sillage`, `competence_riposte`, `parade_contre_taille`, `stigmate_explosion`, `marque`, `ombre_surgit`, `ombre_echange` | Revenant : Sillage lancé, taillade de la Contre-taille, PARADE réussie, Stigmate qui explose, marque posée (plus aiguë : Marque de la proie), Ombre qui surgit, Transposition |
| `faille_fissure`, `competence_hachette`, `hache_retour`, `gadget_garde`, `garde_blocage`, `decollation`, `decollation_encore` | Bourreau : fissure de la Faille, hache lancée, hache RATTRAPÉE, Garde levée, coup BLOQUÉ, Décollation, « encore » (le coup a tué) |
| `gadget_leurre`, `trait_tir`, `grele_tir`, `grele_chute` | Chasseresse : Leurre posé, Trait de Nemrod lâché (plus aigu et moins fort avant la pleine charge), Grêle tirée, Grêle qui tombe |

Trois sons n'ont pas d'événement de simulation : la vue Son LIT l'état, comme le HUD (armement :
`player.superHold` ; franchissement ; point d'arbre : le profil change). L'événement `dash` porte
maintenant le geste (`move`) : aucune partie de référence ne change. `jeu/ville/` et
`jeu/interface/` ne sont pas touchés (seul ajout : trois pictogrammes dans `icones.gd`).

### 3. Mesure en profondeur

Outil : `bash outils/profondeur.sh 20` (`outils/profondeur.gd`) — chaque classe aux étages 1, 109 et
325, une section entière, arbre vide contre arbre plein (33 points), avec et sans déplacement de
classe ; 20 graines par case, 540 parties. Tableaux : `_dev/rapports/profondeur_mesures.md` ;
lecture, écarts entre graines et recommandations chiffrées : `_dev/rapports/profondeur.md`. En bref :

- **(a) L'arbre plein et la profondeur.** Pour le bot habile la profondeur n'est dangereuse ni à
  vide ni à plein : 0 mort sur 360 parties. À l'étage 325 l'arbre plein divise par quatre les dégâts
  reçus (Revenant 1,5 → 0,4 % de la vie par salle, Bourreau 4,3 → 1,1 %), nettoie les salles 20 à
  23 % plus vite, et tue le Gardien 14 à 51 % plus vite. Le danger se lit sans le déplacement de
  classe : 15 à 23 % de la vie perdus par salle, à toute profondeur.
- **(b) Les classes.** Chasseresse au-dessus (0,1 % de vie par salle ; Gardien en 11 s à l'arbre
  plein, contre 20 à 22 s), Bourreau au-dessous (celui qui encaisse le plus). Le même écart qu'en
  section 1 : ce n'est pas la profondeur qui le crée.
- **(c) L'échelle.** Tout coup du héros est multiplié par l'arme portée : un rang ou un ultime ne
  devient jamais négligeable (compétences : 18 à 26 % des dégâts à l'étage 1, 27 à 31 % au 325 ;
  ultime : 27 → 35 % pour le Revenant, 19 → 34 % pour le Bourreau, 9 → 10 % pour la Chasseresse).
  **Défaut corrigé** : les SOINS en PV de l'arbre (Moisson 6, Dîme de sang 4, Soif 1) ne suivaient
  rien — 6 % de la vie à l'étage 1, 0,5 % au 325. Ils suivent maintenant les PV du héros équipé
  (`D6Combat.heal_scaled` ; 6 % → 4,7 %). Test : `tests/regles/v3_profondeur.gd`. Texte des trois
  améliorations : « … PV (à l'échelle de l'étage) ».
- **(d) Forme du Damné.** Pas « trop forte » pour le bot : ×1,8 de dégâts par seconde à l'étage 1
  avec un arbre vide, mais ×0,86 au 325 avec un arbre plein (le kit au rang 5, figé pendant la forme,
  fait mieux que les griffes) ; et le héros n'y prend pas moins de coups. **Saut du Bourreau** : au
  ras du seuil seulement en section 1 (×2,5 pour un seuil de ×2) ; ×7,2 au 109, ×4,0 au 325.

**Recommandations NON appliquées** (équilibrage de goût) : les PV écrits en dur (classe, passifs,
Ville) qui ne suivent pas la vie du héros — les +40 PV du Bourreau valent +40 % à l'étage 1 et +3 % au
325 ; les soins en PV des bénédictions (même défaut que celui corrigé dans l'arbre) ; la jauge qui se
remplit 1,5 à 1,9 fois plus souvent par section au 325 ; la Forme à relever de 15 à 20 % pour un arbre
plein plutôt qu'à baisser ; la Chasseresse à juger en main avant tout réglage.

**PAS FAIT.** Un geste « maintenir » pour une compétence ; une visée « point » pour ce qui se lance
(Grêle, Brasier, Bombe) ; la provocation du Bourreau et le faucon de la Chasseresse (écartés, voir plus
haut) ; l'Ombre ne répète que la mêlée ; le bot coincé dans la disposition « chicane » (6 parties sur
540, aucune mort : défaut de navigation du bot, vu, non corrigé).

**À juger par Pierre** : les trois noms et tous les nombres ; l'étage de maîtrise pour les trois ;
l'Ombre intangible, sa silhouette, ce qu'elle répète ; le second appui de la Transposition ; le seuil
de 35 % et la recharge de 0,5 s de la Décollation ; le télégraphe de la Grêle (assez lisible ? assez
long ?) ; les 38 sons, à l'oreille, un par un — surtout `ultime_pret` ; les recommandations de la mesure.

## Tests existants et combat V3

GO de Pierre le 2026-10-04 (« GO tests V3 ») : les tests existants qui décrivent l'ancien système
de commandes (un bouton compétence, un bouton gadget, un bouton Super) peuvent être ADAPTÉS au
combat V3. Chaque test modifié est listé dans le commit avec la raison (la liste :
`design/COMBAT_V3_TESTS_ADAPTES.md`). Ce GO ne couvre que cela :
un test qui rougit pour une autre raison n'est pas modifié sans un accord séparé.
