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
- **La jauge se remplit pendant que le joueur tient déjà l'attaque** : l'armement commence à ce
  moment, sans relâcher. Conséquence À JUGER EN MAIN : un joueur qui garde le bouton enfoncé pour
  enchaîner voit l'ultime partir 0,4 s après que la jauge est pleine. S'il veut garder son ultime,
  il frappe par appuis. (Variante possible si cela gêne : n'armer que si l'appui a COMMENCÉ jauge
  pleine. Un test le fixe aujourd'hui dans l'autre sens : `v3_combat`, « la jauge qui se remplit
  pendant le maintien ».)
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
tient l'attaque : son ultime part tout seul. Les 70 parties sont réenregistrées (format 2 du
codec) ; les parties `kit_*` et `hasard_*` jouent trois emplacements remplis.

## Tests existants et combat V3

GO de Pierre le 2026-10-04 (« GO tests V3 ») : les tests existants qui décrivent l'ancien système
de commandes (un bouton compétence, un bouton gadget, un bouton Super) peuvent être ADAPTÉS au
combat V3. Chaque test modifié est listé dans le commit avec la raison (la liste :
`design/COMBAT_V3_TESTS_ADAPTES.md`). Ce GO ne couvre que cela :
un test qui rougit pour une autre raison n'est pas modifié sans un accord séparé.
