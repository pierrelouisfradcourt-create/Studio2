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
`ville.json`), « dégâts / recharge de la compétence » (`butin.json`).

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

## Tests existants et combat V3

GO de Pierre le 2026-10-04 (« GO tests V3 ») : les tests existants qui décrivent l'ancien système
de commandes (un bouton compétence, un bouton gadget, un bouton Super) peuvent être ADAPTÉS au
combat V3. Chaque test modifié est listé dans le commit avec la raison (la liste :
`design/COMBAT_V3_TESTS_ADAPTES.md`). Ce GO ne couvre que cela :
un test qui rougit pour une autre raison n'est pas modifié sans un accord séparé.
