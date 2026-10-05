# Combat V3, étape 1 — tests existants adaptés

`statut_artefact : PROPOSED` · 2026-10-04 · sous le « GO tests V3 » de Pierre (fin de
`design/COMBAT_V3.md`). Règle suivie : **adapter = remplacer l'ancienne commande par la nouvelle
en gardant ce que le test prouve** (mêmes attentes, mêmes nombres). Aucun test supprimé, vidé ou
affaibli. Aucun test n'a rougi pour une autre raison que le changement de commandes.

## La traduction, une fois pour toutes

Tous les tests existants jouent le kit par défaut : compétence dans l'emplacement 1, gadget dans
l'emplacement 2, emplacement 3 vide. D'où :

| Ancien | Nouveau | Pourquoi |
|---|---|---|
| entrée `skillPressed`, `skillAimX`, `skillAimY` | `skill1Pressed`, `skill1AimX`, `skill1AimY` | la compétence est dans l'emplacement 1 |
| entrée `gadgetPressed` | `skill2Pressed` | le gadget est dans l'emplacement 2 |
| entrée `superPressed` (un pas) | attaque TENUE jusqu'à ce que l'ultime parte : `h.ultime(g)` (`tests/harnais.gd`), `C.ultime(h, g)` (`v2_contenu.gd`, sans vider les événements) | l'ultime n'a plus de bouton ; il part après `super.holdTime` (0,4 s) de maintien, jauge pleine |
| `player.skillCd` | `player.slots[0].cd` | une recharge par emplacement |
| `player.gadgetCharges` | `player.slots[1].charges` | des charges par emplacement |
| `loadout.skillId`, `loadout.gadgetId` | `loadout.slots[0]`, `loadout.slots[1]` | profil au schéma 4 |
| `kit.skillId`, `kit.gadgetId` | `kit.slots[0]`, `kit.slots[1]` | idem en partie |
| `tuning.skill`, `tuning.gadget` (blocs actifs) | `D6Loadout.slot_def(g, 0 / 1)`, ou `tuning.skills.lance`, `tuning.gadgets.nova` | plus de bloc actif unique : trois emplacements |
| `D6Profile.select_skill / select_gadget(p, t, id)` | `D6Profile.select_slot(p, t, emplacement, id)` | une seule opération |

`h.ultime(g)` s'arrête au PAS où le héros entre dans l'état `super` : la suite du test voit le même
instant qu'avant (le pas où l'ancien bouton lançait le Super). Avant ce pas, le maintien a duré
0,4 s et le premier appui a donné un coup normal : les tests concernés ne comptent que les coups
de sorte `super`, ou jouent sans ennemi à portée, donc leurs attentes n'ont pas bougé.

## Tests de règles (`tests/regles/`) — 35 tests retouchés et 4 aides communes, 13 fichiers

| Fichier | Test (fonction) | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `feel_review.gd` | `_lance_au_finisher` | `skillPressed/AimX/AimY` → `skill1…` | traduction |
| `logic.gd` | `_gadget` | `gadgetPressed` → `skill2Pressed` ; `gadgetCharges` → `slots[1].charges` | traduction |
| `logic.gd` | `_super` | `superPressed` → `h.ultime(g)` | ultime par maintien |
| `logic.gd` | `_competence` | `skillPressed…` → `skill1…` ; `skillCd` → `slots[0].cd` | traduction |
| `logic.gd` | `_tampon_a_vide` | l'action infaisable qui ne doit pas avaler la frappe : « Super pas prêt » → « compétence en recharge » (`slots[0].cd = 99`, `skill1Pressed`) ; le dash sans charge reste | il n'existe plus d'appui « Super » à mettre en tampon ; le test prouve toujours qu'une action infaisable n'avale jamais la frappe qui suit |
| `logic.gd` | `_lance_interrompue` | `skillPressed…` → `skill1…` | traduction |
| `properties.gd` | `_random_input` (sert « invariants — entrées aléatoires », déterminisme, graines) | compétence et gadget traduits ; `superPressed` 1 % → au même tirage, 1 % de chances de TENIR l'attaque 30 pas (0,5 s) | sans cela le joueur aléatoire ne lancerait plus jamais d'ultime (24 pas d'affilée à 50 % : jamais) ; même nombre de tirages qu'avant |
| `properties_strict.gd` | `_random_input`, `_all_buttons` (pauses, invariants stricts) | idem ; « tous les boutons » presse les trois emplacements | traduction |
| `properties_strict.gd` | `_check_strict_player` | « charges de gadget jamais négatives » : sur les trois emplacements | charges par emplacement |
| `v2_contenu_benedictions.gd` | `_t_ripaille`, `_t_passion_brulante`, `_t_trop_plein` | `C.step1(h, g, {"superPressed": true})` → `C.ultime(h, g)` | ultime par maintien |
| `v2_contenu_pouvoirs.gd` | `_t_main_de_gloire` | `gadgetCharges` → `slots[1].charges` (6 lignes) | traduction |
| `v2_floors.gd` | `_fontaine` (repos : fioles) | `gadgetCharges` → `slots[1].charges` ; `T.gadget.chargesPerSection` → `T.gadgets.nova.chargesPerSection` | traduction (même nombre : la Nova) |
| `v2_integration.gd` | `_ville` | « compétence / gadget choisi possédé » : `loadout.slots[0]`, `loadout.slots[1]` | traduction |
| `v2_kits.gd` | `_kit_meta` (outil de 19 tests) | `loadout = {classId, slots: [compétence, gadget, null]}` | profil au schéma 4 |
| `v2_kits.gd` | `_t_defaut_valeurs` | `DEFAULT_LOADOUT` attendu : `{classId: "revenant", slots: ["lance", "nova", null]}` ; la Colère est comparée à l'historique SANS son nouveau champ `holdTime` (dont on vérifie la présence) ; « `t.skill` / `t.gadget` sont des références » → « ces blocs n'existent plus », l'identité de valeur avec le registre passe par `t.skills.lance`, `t.gadgets.nova` | même contenu, nouvelle forme ; le réglage `holdTime` est le seul ajout aux données |
| `v2_kits.gd` | `_t_defaut_references` | `g.kit` attendu avec `slots` ; références lues par `D6Loadout.slot_def(g, 0 / 1)` | traduction |
| `v2_kits.gd` | `_t_ville` | `loadout.skillId / gadgetId` → `loadout.slots[0] / [1]` (« bond », « cri ») | traduction |
| `v2_kits.gd` | `_t_chaine`, `_t_chaine_gardien`, `_t_bond`, `_t_bond_interrompu`, `_t_brasier`, `_t_volee`, `_t_boons_attaque_competence` | `skillPressed…` → `skill1…` ; `skillCd` → `slots[0].cd` | traduction |
| `v2_kits.gd` | `_t_bombe`, `_t_piege`, `_t_cri`, `_t_totem` | `gadgetPressed` → `skill2Pressed` ; `gadgetCharges` → `slots[1].charges` ; `kit.gadgetId` → `kit.slots[1]` | traduction |
| `v2_kits.gd` | `_t_sentence`, `_t_nuee` | `superPressed` → `h.ultime(g)` | ultime par maintien |
| `v2_kits.gd` | `_first_strike` (sert `_t_boons_dash_super`) | `superPressed` au pas 0 puis 0,4 s → `h.ultime(g)` puis le reste des 0,4 s (même nombre de pas APRÈS le départ du Super) | ultime par maintien ; `superT` est lu au même instant |
| `v2_kits.gd` | `_check_invariants` (parties réelles par classe) | « charges de gadget ≥ 0 » : sur les trois emplacements | charges par emplacement |
| `v2_loop.gd` | `_profil_neuf` | `loadout` attendu : `{classId, slots: [compétence, gadget, null]}` | profil au schéma 4 |
| `v2_loop.gd` | `_ville_classe` | `loadout.skillId / gadgetId` → `loadout.slots[0] / [1]` | traduction |
| `v2_loop.gd` | `_ville_competence_gadget` | `select_skill / select_gadget` → `select_slot(p, t, 0 / 1, id)` ; mêmes refus (« indisponible »), mêmes acceptations | une seule opération |
| `v3_defauts.gd` | `_t_textes` | `meta.loadout.skillId = "chaine"` → `slots[0]` ; `kit.skillId` → `kit.slots[0]` | traduction |
| `donnees.gd` | `_starter` | `DEFAULT_LOADOUT.skillId / gadgetId` dans la classe → `DEFAULT_LOADOUT.slots` : trois emplacements, chacun une action de la classe ou null, jamais deux fois la même ; un profil neuf le porte | forme des données |
| `donnees.gd` | `_recomposed` | `t.skill == t.skills.lance` → « plus de bloc actif `skill` / `gadget` » | plus de bloc actif |

Non modifié alors qu'il porte encore `skillId` / `gadgetId` : `v2_loop.gd`, `_bad_profile` (une
sauvegarde corrompue de l'ANCIEN format). Il passe tel quel : c'est maintenant aussi un cas de
migration (`{skillId: 7, gadgetId: "nope"}` donne les emplacements de départ).

Outils ajoutés (pas des tests) : `tests/harnais.gd` `ultime()` ; `tests/regles/v2_contenu.gd`
`ultime()`.

## Tests de vues (`jeu/`)

| Fichier | Vérification | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `jeu/entrees/test_entrees.gd` | forme de l'interface tactile | boutons attendus : `attack, dash, skill1, skill3, skill2` (mêmes places que compétence, Super, gadget) | les trois emplacements |
| `jeu/entrees/test_entrees.gd` | compétence (tap, glisser, annuler, ramener à 15 px) ; fronts gardés une image ; `vider()` | `skill` → `skill1`, `gadget` → `skill2` | traduction |
| `jeu/entrees/test_entrees.gd` | « gadget et Super : un tap chacun » | emplacements 2 et 3 : un tap chacun, un front chacun | traduction |
| `jeu/entrees/test_entrees.gd` | « attaque glissée : visée manuelle vers le haut » | la visée est toujours rendue, mais l'attaque n'est PLUS tenue pendant le glisser ; le coup part au relâcher, visé | règle V3 : un glisser-relâcher ne lance jamais l'ultime |
| `jeu/entrees/test_entrees.gd` | « attaque déjà tenue : un autre doigt ne la redéclenche pas » | le premier doigt vise (glisser) : on vérifie que le bouton est pris et qu'aucun front ne repart, plus `attack` tenu | même cause |
| `jeu/entrees/test_entrees.gd` | clavier : L, E, F, R ; manette : B, Y, RB | L / E / F → emplacements 1 / 2 / 3 ; B / Y / RB → emplacements 1 / 2 / 3 ; la touche R (second raccourci du Super) est retirée | l'ancien bouton Super devient l'emplacement 3 |
| `jeu/entrees/test_entrees.gd` | souris : clic droit | `skillPressed…` → `skill1…` | traduction |
| `jeu/interface/test_accueil.gd` | consignes compétence, gadget | commande désignée : `skill1`, `skill2` ; geste : `skill1Pressed`, `skill2Pressed` | traduction |
| `jeu/interface/test_accueil.gd` | consigne Super | phrase « Jauge pleine : garde le bouton d'attaque appuyé », commande désignée `attack`, geste : attaque tenue | ultime par maintien |
| `jeu/ville/test_ville.gd` | opération refusée (« Indisponible ») | `select_skill [id]` → `select_slot [0, id]` | une seule opération |
| `jeu/monde/test_finitions.gd` | note du Grimoire | compétence et gadget équipés lus dans `loadout.slots[0] / [1]` | profil au schéma 4 |
| `jeu/monde/test_profondeur.gd` | héros en plein Bond | le Bond fabriqué par le test est posé dans l'emplacement 1 d'un Bourreau (`tuning.skills.bond.leapTime`) au lieu de `tuning.skill.leapTime` | plus de bloc actif |
| `jeu/son/test_son.gd` | partie jouée pour le son | `skillPressed` / `gadgetPressed` traduits ; `superPressed` retiré (l'attaque y est déjà tenue : l'ultime part de lui-même) | traduction |
| `jeu/essai/parcours_ville.gd` (aide de `test_parcours.gd`) | « la compétence débloquée est équipée » | `select_skill [id]` → `select_slot [2, id]` ; elle est attendue dans l'emplacement 3 | une seule opération |

`jeu/essai/test_parcours.gd` lui-même n'a pas eu à changer : le bot qui le joue a appris le
nouveau système (`outils/bots/`).

## Tests neufs

- `tests/regles/v3_combat.gd` : 41 tests (ultime par maintien, trois emplacements, `select_slot`,
  `slot_choices`, migration d'un vrai profil au schéma 3, `slot_view`, événements avec `slot`,
  chaque bénédiction / objet / autel qui parle de la compétence ou du gadget).
- `tests/regles/donnees.gd` : 1 test (`holdTime` existe et vaut la même durée pour les trois Supers).
- `jeu/entrees/test_entrees.gd` : glisser long sans attaque tenue, coup au relâcher, emplacement 3
  glissé, E et F visés à la souris.
- `jeu/ville/test_ville.gd` : `_emplacements` (placer, échanger, vider, relire du disque d'essai).
- `jeu/interface/test_accueil.gd` : `_commandes_v3` (trois emplacements au HUD, emplacement vide,
  jauge d'ultime et maintien sur le bouton d'attaque).

## Lot « affichage et gestes » (2026-10-04) — vérifications adaptées

Même règle : la vérification garde ce qu'elle prouve, seule la disposition ou le geste décrit
change. Aucune n'est supprimée ; plusieurs sont durcies (signalé). Décompte : `test_entrees`
108 → 157 vérifications, `test_ville` 65 → 76, `test_accueil` 191 → 205.

### `jeu/entrees/test_entrees.gd`

| Vérification | Ce qui a changé | Pourquoi |
|---|---|---|
| forme : « 5 boutons attack, dash, skill1, skill3, skill2 » | ordre `attack, dash, skill1, skill2, skill3` ; un bouton porte aussi `held` | l'arc range les emplacements 1, 2, 3 ; les places héritées (compétence, Super, gadget) n'existent plus |
| « attaque à 118 × 112 px CSS du coin » | 168 × 100 | nouvelle disposition (le dash est à droite de l'attaque) |
| « rayon de l'attaque 48, du dash 40 » | 52 et 38 | gros bouton d'attaque |
| « la zone joystick s'arrête … avant le dash » | avant la zone de toucher de CHAQUE bouton (durcie) | le bouton le plus à gauche n'est plus le dash |
| « deux doigts : joystick + attaque dans le même pas » (pouce posé : `attack` et `attackPressed` au même pas) | pouce posé : rien ne part ; passé l'appui bref (150 ms), `attack` et `attackPressed` dans le même pas, joystick tenu | nouveau geste : rien ne part à l'appui (sinon un glisser donne deux coups) |
| « attaque glissée puis relâchée : le coup part au relâcher » | même attente, libellé précisé (« tenue, puis glissée, puis relâchée ») | la séquence du test commence par une attaque tenue |
| « tap hors bouton dans la moitié droite : attaque » (à l'appui) | un tap = un coup au relâcher ; pouce maintenu = attaque tenue ; la suite (visée depuis le point de contact, second doigt) inchangée | même geste que sur le bouton |
| « vider() efface les fronts » / « ne lâche pas ce qui est tenu » | l'attaque est tenue AVANT les fronts (passé l'appui bref) ; un front d'emplacement tactile et un second doigt s'ajoutent aux fronts à effacer (durcie) | poser le pouce ne tient plus l'attaque tout de suite |
| « perte du focus : plus rien n'est tenu » | on vérifie d'abord que le pouce TIENT l'attaque (durcie) | idem |
| « paysage 844 × 390 : mêmes positions que le web » | positions du combat V3 (attaque 676 × 290, dash 779,68 × 312,04), puis les exigences de l'arc rejouées dans ce format | la disposition n'est plus celle de la version web |
| « zone sûre : les boutons s'écartent de l'encoche » | 676 − 44, 290 − 21 ; et aucun bouton, anneau compris, ne mord sur la zone (ajout) | nouvelles places |
| « portrait : … disposition recalculée » | attaque à 70 px CSS du bord droit (95 avant) | éventail du portrait refait (le dash passe au-dessus de l'arc) |

### `jeu/ville/test_ville.gd` — `_emplacements`

| Vérification | Ce qui a changé | Pourquoi |
|---|---|---|
| « son bouton “→ 1” est grisé » | l'emplacement 1 touché, la carte de l'action qui y est dit « Déjà dans l'emplacement 1 », grisé | plus de boutons « → 1 / → 2 / → 3 » : on touche une compétence puis un emplacement, ou l'inverse |
| « “→ 3” s'appuie », échange 1 ⇄ 3 | « Choisir » la compétence, puis toucher l'emplacement 3 sur l'arc ; même échange attendu | idem |
| « “Vider” : … son bouton a disparu » | le bouton « Vider » de l'emplacement vide est grisé | la légende des trois emplacements est fixe |
| « l'action se replace dans l'emplacement 1 » | l'inverse : l'emplacement 1 touché, puis « Placer dans l'emplacement 1 » | les deux ordres sont couverts |

### `jeu/interface/test_accueil.gd`

| Vérification | Ce qui a changé | Pourquoi |
|---|---|---|
| phrases des consignes compétence et gadget | « Lance une compétence », « Utilise une compétence à charges » | trois emplacements : plus « ta compétence », plus de « gadget » |
| « HUD tactile : les mêmes cinq commandes » | ordre `attack, dash, skill1, skill2, skill3` | l'arc |
| « bouton d'attaque : jauge pleine, le maintien monte » | l'attaque restée tenue depuis l'essai précédent est relâchée, PUIS on rappuie jauge pleine | À SIGNALER : cette vérification a rougi en cours de lot à cause d'un changement de RÈGLE fait en même temps dans `sim/player.gd` (l'ultime ne s'arme que si l'appui commence jauge pleine), pas à cause de l'affichage. Elle prouve toujours la même chose (le bouton montre le maintien qui monte, puis retombe au relâcher) |

## Lot « affichage et gestes » — vérifications ajoutées

- `test_entrees` : `_arc` (attaque plus gros bouton ; cibles ≥ 56 px ; même distance à l'attaque ;
  ordre 1, 2, 3 à gauche et au-dessus ; dash de l'autre côté ; ≥ 12 px de vide entre deux boutons ;
  tout dans l'écran à 8 px du bord, anneau compris ; le centre d'un bouton prend ce bouton), jouée
  en 1280 × 720 et en 844 × 390 ; `_appui_bref` (rien avant le relâcher, exactement un coup,
  jamais tenu, visée assistée) ; `_glisser_relacher` (aucun coup ni attaque tenue pendant 1 s de
  glisser, un seul coup au relâcher, dans la dernière direction visée) ; `_maintien` (attaque
  tenue 60 pas sur 60, un seul front, tient malgré un pouce qui tremble) ; `_attaque_annulee`
  (retour au centre, toucher annulé par le système) ; `_trois_doigts` (joystick + attaque tenue +
  emplacement visé puis lancé) ; `_manette_visee` (stick droit) ;
  `_gestes_dans_la_simulation` : les mêmes gestes joués dans la VRAIE simulation (un appui bref =
  un `attackStart`, zéro `super` ; un glisser-relâcher jauge pleine = un coup vers le haut, zéro
  `super`, `superHold` resté à 0 ; emplacement vide touché = aucun événement, aucun état changé ;
  pouce maintenu jauge pleine = l'ultime part, une fois).
- `test_ville` : rien n'est écrit au premier toucher (emplacement, puis compétence) ; retoucher
  oublie ; changer d'onglet oublie un choix à moitié fait ; les trois emplacements de l'arc sont
  des boutons.
- `test_accueil` : `_jauge_et_visee_v3` (la jauge lue à 0, 25, 50, 75 % ; `visee` d'un
  emplacement ; emplacement vide touché et glissé : ni enfoncé, ni repère, ni ligne ; ligne de
  visée depuis le héros pour un emplacement et pour l'attaque, aucune pour le dash ; chaque
  bouton dessiné là où la disposition le place).

## Étape 1 bis — réglage de l'ultime : un test adapté (`tests/regles/v3_combat.gd`)

Demande de Pierre (2026-10-04, étape 1 bis) : « pas d'ambiguïté » — l'ultime ne s'arme que si
l'APPUI A COMMENCÉ jauge pleine. C'est le seul test existant modifié par ce lot.

| Test | Avant | Après | Pourquoi |
|---|---|---|---|
| « ultime : la jauge qui se remplit PENDANT le maintien l'arme sans relâcher » | attaque tenue, la jauge passe à 1 : l'ultime part après `holdTime`, sans relâcher | renommé « … ne l'arme PAS ; le combo continue » : attaque tenue 3 s de plus, jamais d'armement (`superHold` et `superArm` restent à zéro), aucun ultime, la jauge reste pleine, au moins 10 coups partent | la règle a changé : ce test fixait l'ancienne |
| « emplacements : la reprise… » (`_e_reprise`) | `superHold` remis à zéro à la reprise | en plus : `superArm` posé avant la mort, remis à faux à la reprise | une affirmation AJOUTÉE, aucune retirée |

Tests neufs du même réglage (`v3_combat.gd`) : « relâcher puis rappuyer l'arme et le lance à
holdTime » ; « l'appui qui vient de le lancer n'en arme pas un second » ; « un front d'attaque
répété sans relâcher n'arme rien ». `tests/harnais.gd` (`h.ultime`) n'a pas eu à changer : il
commence son appui jauge pleine.

Aucun autre test existant de `tests/**` n'a été modifié par l'étape 1 bis. `tests/regles/donnees.gd` :
deux tests AJOUTÉS (déplacements, terrain), rien de retiré. Nouveau fichier : `tests/regles/v3_terrain.gd`.

## Finitions — tests de vues retouchés (`jeu/interface/test_accueil.gd`)

Aucun test de `tests/**` n'a été modifié par le lot « Finitions » ; aucun test de règles ne
comparait mot pour mot un des textes corrigés. Dans le test de vue de l'accueil (hors surface
protégée), trois attentes parlaient de l'ancien système (un dash pour tous, dix consignes) :

| Attente | Avant | Après | Pourquoi |
|---|---|---|---|
| phrase de la consigne `dash` | « Traverse les attaques d'un dash » | « Dashe à travers les attaques » | la phrase suit le geste de la classe (Dashe / Saute / Roule) |
| phrase de la consigne `rouge` | « Esquive le rouge » | « Esquive le rouge : dashe » | idem |
| taille de la table | dix consignes | onze | la consigne `terrain` est ajoutée (et acquise par le test avant « les onze consignes sont sur le disque ») |

Ajouts (rien de retiré) : `_terrain`, `_deplacement_de_classe`, `_retours_du_bureau`
(`test_accueil`) ; `_retours_du_bureau` (`test_entrees`) ; `_deplacement` (`test_ville`).

## Étape 2 — les trois ultimes de classe (2026-10-04)

Sous le même « GO tests V3 ». Colère, Sentence et Nuée ne sont plus l'ultime d'aucune classe ; leur
code reste et se lance directement par un réglage d'essai (`tuning.classes.<classe>.super`). Règle
suivie : un test qui prouve quelque chose de l'ANCIEN Super le prouve toujours, sur l'ancien Super
lancé directement, mêmes attentes, mêmes nombres ; un test qui nomme « le Super de la classe »
nomme le nouvel ultime. Aucun test supprimé ni affaibli ; aucun n'a rougi pour une autre raison.

| Fichier | Test (fonction) | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `logic.gd` | `_super` (« Super : se charge…, puis rend invulnérable ») | la partie nomme la Colère comme ultime (`tuning.classes.revenant.super`) | mêmes affirmations (jauge à 0, invulnérable) sur la Colère lancée directement |
| `v2_contenu_benedictions.gd` | `_t_trop_plein` | « jamais pendant le Super » : la jauge attendue n'est plus 0 mais « inchangée par le soin, et plus pleine » | en Forme du Damné la jauge est la minuterie ; ce que le test prouve (le soin en trop ne la remplit pas pendant l'ultime) est gardé |
| `v2_kits.gd` | `_t_defaut_valeurs` | le Super du Revenant attendu : `forme_damne` ; la Colère est comparée à l'historique sans `holdTime` NI `reserve` (dont on vérifie la présence) | la Colère garde tous ses nombres ; `reserve` est le seul ajout |
| `v2_kits.gd` | `_t_defaut_references` | `kit.superId` et le bloc actif attendus : `forme_damne` | l'ultime du Revenant |
| `v2_kits.gd` | `_t_registre_listes` | 6 Supers dans le registre (3 ultimes, 3 en réserve, compté) ; « un Super propre à chaque classe » inchangé | les anciens restent dans la table |
| `v2_kits.gd` | `_t_ville` | « Super du Bourreau » : `sentence_capitale` | l'ultime du Bourreau |
| `v2_kits.gd` | `_t_sentence`, `_t_nuee`, `_first_strike` (sert `_t_boons_dash_super`) | la partie nomme l'ancien Super comme ultime de la classe ; tout le reste identique | les nombres de la Sentence et de la Nuée sont toujours gardés |
| `v3_combat.gd` | `_u_part`, `_u_pas_deux_fois`, `_e_gadget_refus` | idem : la Colère lancée directement | le geste du maintien et « pas de gadget pendant l'ultime » restent prouvés tels quels ; les trois ultimes neufs ont les leurs dans `v3_ultimes.gd` |
| `v3_combat.gd` | `_u_reglage` | le réglage d'essai `holdTime: 1.0` vise `forme_damne` au lieu de `colere` | c'est l'ultime que la partie lance |
| `v3_combat.gd` | `_p_migration_reelle` | `kit.superId` attendu : `sentence_capitale` | l'ultime du Bourreau |
| `donnees.gd` | `_kit_orphans` | un Super sans classe est admis S'IL est marqué `reserve` ; en plus : un Super `reserve` ne doit être nommé par aucune classe | la garde « rien d'orphelin par oubli » tient toujours |

Tests de vues (hors `tests/**`) :

| Fichier | Vérification | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `jeu/interface/test_accueil.gd` | `_commandes_v3`, `_jauge_et_visee_v3` (8 vérifications rouges) | AUCUNE attente changée : avant elles, une étape neuve `_forme_puis_origine` vérifie que le HUD montre les trois actions de forme et la minuterie pendant la forme (6 vérifications AJOUTÉES), puis laisse la forme finir | l'essai de l'ultime lançait une Colère de 1,4 s, il lance une forme de 10 s : les emplacements d'origine se jugent après elle |
| `jeu/essai/test_parcours.gd` | « bout du chemin : la fontaine a été traversée en chemin » (et la garde « menu rest traversé » qui en dépend) | la graine de l'acte, `GRAINE_DE_LA_FIN`, passe de 1 à 2 ; aucune attente changée | graine CHOISIE pour que la fontaine soit sur la route du pilote : avec la Sentence capitale du Bourreau, les tirages de portes de la graine 1 n'offrent plus de fontaine (16 salles, aucune) ; la graine 2 en offre une |
| `jeu/son/test_son.gd` | `_echantillons_heros` | 13 échantillons AJOUTÉS (les trois lancements et les dix types d'événements routés des ultimes), rien de retiré | « chaque type routé a son échantillon » |
| `jeu/effets/echantillons.gd` | table des cas | 15 cas AJOUTÉS | « chaque effet a son événement d'exemple » |

Nouveau fichier : `tests/regles/v3_ultimes.gd` (57 tests). `tests/harnais.gd` n'a pas changé.

## Étape 3 — arbre de compétences (2026-10-04)

Sous le même « GO tests V3 », étendu par Pierre aux tests qui décrivent le DÉBLOCAGE DES COMPÉTENCES
EN ÂMES (`unlock` d'une compétence, `cost`, `slot_choices` avec `cost`). Avec l'arbre, le rang 1 du
nœud débloque ; `cost` a disparu de `skills` et `gadgets` ; chaque classe a une 5e compétence
(l'ancien Super, sorte `canal`). Aucun test supprimé ni affaibli ; aucun n'a rougi pour une autre raison.

| Fichier | Test (fonction) | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `v2_kits.gd` | `_t_registre_prix` (« chaque entrée a un prix en Âmes ; le départ de chaque classe est gratuit ») | classes et armes : inchangé. Compétences et gadgets : on vérifie qu'ils n'ont PLUS de `cost` et que `unlock_cost` vaut 0 ; « le départ est gratuit » se prouve par `slot_choices` : la 1re compétence et la 1re compétence à charges de chaque classe sont débloquées, les autres non | le prix en Âmes n'existe plus ; ce que le test garde (le kit de départ est possédé, rien d'autre) est toujours prouvé, et plus strictement (« les autres non ») |
| `v2_integration.gd` | `_kit_gratuit_possede` (sert `_ville`) | armes : celles de coût 0, comme avant ; compétences et gadgets : la première de chaque liste | sans `cost`, « coût 0 » ne désigne plus le départ ; c'est la place dans la liste de la classe qui le dit |
| `v3_combat.gd` | `_p_choix` (« slot_choices : compétences puis gadgets de la classe, avec leur état ») | 5 choix au lieu de 4 (la 5e compétence) ; forme d'un choix : `rank` à la place de `cost` ; on vérifie en plus les rangs (1 pour le départ, 0 sinon) et l'absence de `cost` dans les données | le contrat de `slot_choices` a changé avec l'arbre |
| `v3_combat.gd` | `_p_classe` (« changer de classe refait des emplacements valides ») | la Chaîne n'est plus débloquée par `unlock(…, "skills", "chaine")` (dont on vérifie maintenant le REFUS, « se débloque dans l'arbre ») mais possédée d'office (`unlocked.skills`), comme sur un ancien profil | tout le reste du test (emplacements au changement de classe) est identique |
| `v3_combat.gd` | `_p_migration_reelle` | le schéma attendu après migration : 5 au lieu de 4 | un profil au schéma 3 passe maintenant par deux migrations (emplacements, puis arbre) ; « aucun champ en plus ni en moins qu'un profil neuf », « la migration est stable » et le kit en partie sont inchangés et verts |

`v2_loop.gd` (`_ville_deblocage`, `_ville_competence_gadget`) n'a PAS été modifié : ses attentes
(« déjà débloqué » pour le kit de départ, « indisponible » pour une compétence d'une autre classe)
tiennent telles quelles.

Tests de vues (hors `tests/**`) :

| Fichier | Vérification | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `jeu/ville/test_ville.gd` | `_sans_ames` : « sans Âmes, « Débloquer » <compétence> est grisé » | devient : la carte d'une compétence verrouillée porte un bouton grisé « À débloquer dans l'arbre », et aucun bouton « Débloquer » en Âmes ; étape `_arbre` AJOUTÉE (niveau, points, repère d'onglet, « + » et sa raison, étage fermé, les deux améliorations, l'exclusion, « Tout rendre » en deux appuis) | le Grimoire ne vend plus de compétence en Âmes |
| `jeu/essai/parcours_ville.gd`, `test_parcours.gd` | « Ville du joueur avancé : unlock ["skills", …] acceptée », « la compétence débloquée est équipée, troisième emplacement » | la compétence est débloquée DANS L'ARBRE (étage fermé refusé, deux rangs, une amélioration prise et l'autre refusée, un passif, l'étage suivant, rang 1 de la compétence), puis placée au troisième emplacement (même vérification), puis tout est rendu contre de l'or (emplacement vidé). AJOUTS : après la première descente, un point est dépensé par le bouton « + » ; la compétence améliorée est vue en jeu ; la garde des opérations exige en plus `tree_buy`, `tree_choose`, `tree_respec` | le parcours joue l'arbre de bout en bout |
| `jeu/ecrans/test_ecrans.gd` | — | étape `_mort_et_experience` AJOUTÉE (4 vérifications), rien de changé | l'écran de mort dit l'expérience et le niveau |
| `jeu/son/test_son.gd` | `_echantillons` | 1 échantillon AJOUTÉ (`levelUp`), rien de retiré | « chaque type routé a son échantillon » |

Nouveau fichier : `tests/regles/v3_arbre.gd` (62 tests). Ajouts à `tests/regles/donnees.gd` : 3 tests
(`_tree_refs`, `_tree_texts`, `_tree_budget`), aucun test existant touché. `tests/harnais.gd` n'a pas changé.

## Étape 4 — compétences neuves (2026-10-05)

Sous le même « GO tests V3 », pour le seul cas prévu : un test qui fige la LISTE ou le NOMBRE des
compétences d'une classe. Chaque classe a huit compétences au lieu de cinq.

| Fichier | Test (fonction) | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `v3_combat.gd` | `_p_choix` (« slot_choices : compétences puis gadgets de la classe, avec leur état ») | les trois listes attendues passent de 5 à 8 éléments : sortes (5 compétences à recharge, 3 à charges), `unlocked` et `rank` (le départ possédé, les trois neuves à 0 comme les autres) | trois compétences neuves par classe ; la forme d'un choix, l'ordre « compétences puis gadgets » et le reste du test sont inchangés |

Aucun autre test existant n'a été touché. Deux tests ont rougi pendant le travail et ont fait
corriger la RÈGLE, pas le test : `v3_combat` « slot_view : une compétence… » et « un gadget… »
exigent la forme exacte de `slot_view` — les champs neufs (`charging`…) ont donc été sortis dans
`D6Loadout.slot_state` ; `v3_arbre` « Chaîne : … » et « Bombe : … » jouent « traversante » et
« fumigène » avec le Bourreau, « ferrage » et « grappe » avec le Revenant — chaque classe a donc
gardé cette amélioration-là.

Nouveau fichier : `tests/regles/v3_competences.gd` (62 tests). Le test générique
`v3_arbre.gd : _r_competence` (« rangs : … chaque rang change EN JEU… ») s'étend de lui-même aux neuf
nœuds neufs (+9 tests, sans modification). Tests de vues (hors `tests/**`), AJOUTS seulement :
`jeu/effets/echantillons.gd` (19 événements d'exemple), `jeu/son/test_son.gd` (7 échantillons).


## Étape 5 — la quatrième compétence de chaque classe (2026-10-05)

Sous le même « GO tests V3 », pour le seul cas prévu : un test qui fige la LISTE ou le NOMBRE des
compétences d'une classe. Chaque classe a neuf compétences au lieu de huit.

| Fichier | Test (fonction) | Ce qui a changé | Pourquoi |
|---|---|---|---|
| `v3_competences.gd` | `_a_noeuds` (« arbre : … compétences par classe … ») | le nombre attendu passe de 8 à 9 ; le titre du test le dit | une compétence de plus par classe (`ombre`, `grace`, `grele`) ; les trois neuves de l'étape 4, leurs étages, « une à charges sur trois » et « les cinq d'avant gardent leur place » sont inchangés |
| `v3_competences.gd` | `_a_sortes` (« données : chaque sorte (kind) de compétence a sa règle… ») | une sorte est aussi « jouée par une règle » si elle est dans `Neuves.SKILLS_2` (les trois sortes de l'étape 5) | la liste des sortes connues grandit ; les sortes de l'étape 4 (`Neuves.SKILLS`, `GADGETS`) et leur vérification « une compétence par sorte » sont inchangées |
| `v3_combat.gd` | `_p_choix` (« slot_choices : compétences puis gadgets de la classe, avec leur état ») | les trois listes attendues passent de 8 à 9 éléments (six compétences à recharge, trois à charges) | même adaptation qu'à l'étape 4, pour la même raison |

Aucun autre test existant n'a été touché. Rien d'autre n'a rougi pour une raison de règle.

Nouveaux fichiers : `tests/regles/v3_competences_2.gd` (28 tests : les trois compétences) et
`tests/regles/v3_profondeur.gd` (5 tests : l'échelle en profondeur). Le test générique
`v3_arbre.gd : _r_competence` s'étend de lui-même aux trois nœuds neufs (+3, sans modification).
Tests de vues (hors `tests/**`), AJOUTS seulement : `jeu/effets/echantillons.gd` (7 événements
d'exemple), `jeu/son/test_son.gd` (21 échantillons : les sons propres du combat V3).


## Écran de l'arbre (2026-10-05) — vérifications adaptées dans `jeu/ville/test_ville.gd`

Le Grimoire n'est plus une liste de cartes mais un arbre dessiné et un panneau de détail (mission
« le bel écran de l'arbre », accord de Pierre pour le combat V3 relayé par la mission). Règle suivie :
**chaque vérification garde ce qu'elle prouve ; seul le chemin d'écran change** (on touche le nœud, on
lit son panneau). Aucune vérification retirée ; aucune autre ne rougissait. `jeu/ecrans/test_ecrans.gd`,
`jeu/interface/test_accueil.gd`, `jeu/monde/test_finitions.gd` : RIEN d'adapté, seulement des ajouts.

À SAVOIR : la mission nommait « les vérifications qui décrivent l'ancienne liste de l'arbre ». Celles de
`_emplacements`, `_sans_ames` et `_deplacement` décrivent les deux AUTRES listes du même écran (« Placer
une compétence », « Déplacement et ultime »), que la mission remplace aussi (« Placer en 1 / 2 / 3 » dans
le panneau, pas de double écran). Elles sont adaptées de la même façon et listées ici une à une : à
ratifier par Pierre, ou à défaire s'il préfère garder ces listes.

| Fonction | Avant | Après | Pourquoi |
|---|---|---|---|
| `_deplacement` | la carte « Déplacement · <classe> », le nom et le texte du geste sont visibles dans le Grimoire | les TROIS mêmes textes, après avoir touché le nœud de déplacement de l'arbre | la carte est devenue le panneau du nœud en écusson |
| `_sans_ames` | compétence verrouillée : bouton grisé « À débloquer dans l'arbre », sans prix en Âmes | son nœud touché : bouton d'achat grisé « Apprendre », aucun « ◆ » à l'écran, et aucun « Placer en » | c'est le nœud qui débloque ; plus de carte de placement |
| `_sans_ames` | opération refusée (clé `skills:<id>`) : « Indisponible » sur la carte | même opération (clé `placer:<id>:0`) : « Indisponible » sur le panneau | le refus s'affiche là où est le bouton |
| `_emplacements` | « ● Emplacement 1 » marque la carte | même texte, sur le panneau du nœud touché | idem |
| `_emplacements` | emplacement touché : le bouton de la carte dit « Déjà dans l'emplacement 1 », grisé | emplacement touché : le panneau montre l'emplacement (« Vider ») ; le nœud sous le focus : « Placer en 1 » grisé, infobulle « Déjà dans l'emplacement 1 » | même garde : on ne replace pas au même endroit |
| `_emplacements` | retoucher l'emplacement dans la LÉGENDE l'oublie ; la carte propose « Choisir » | le retoucher sur l'ARC l'oublie ; le panneau propose de nouveau « Placer en » | la légende n'existe plus (l'arc suffit) |
| `_emplacements` | « Choisir » la carte (profil inchangé, « Choisie — touche un emplacement »), puis l'emplacement 3 sur l'arc : échange | toucher le nœud (profil inchangé, « Placer en 1 / 2 / 3 » offert), puis « Placer en 3 » : même échange, même attente sur `loadout.slots` | compétence d'abord, emplacement ensuite : même opération |
| `_emplacements` | « Vider » sur la ligne 3 de la légende | emplacement 3 touché sur l'arc, « Vider » du panneau ; mêmes attentes (vide, bouton grisé) | idem |
| `_emplacements` | emplacement 1 (légende) puis « Placer dans l'emplacement 1 » de la carte | emplacement 1 (arc) puis le nœud touché dans l'arbre ; même attente | emplacement d'abord, compétence ensuite |
| `_emplacements` | un choix à moitié fait (carte « Choisie ») ne survit pas à un changement d'onglet | un emplacement en attente ne survit pas à un changement d'onglet | même état d'écran |
| `_arbre` | « ● N points à dépenser » écrit | la pastille porte N et « points à dépenser » est écrit | le nombre est dans la pastille |
| `_arbre` | chaque étage titré « Étage <nom> » | chaque étage titré de son NOM, dans sa bande | titre dessiné |
| `_arbre` | chaque nœud : un « + », grisé si `canBuy` est faux | chaque nœud : son médaillon, et son bouton d'achat (panneau) grisé si `canBuy` est faux | un bouton d'achat par nœud choisi |
| `_arbre` | étage fermé : « + » grisé, « Étage … fermé » sur la carte | idem sur le panneau (même texte) | — |
| `_arbre` | « Compétence · rang 3 / … » sur la carte | « Rang 3 / 5 » sur le panneau | — |
| `_arbre` | une amélioration se prend en UN appui | premier appui : rien n'est pris, « Confirmer » et « Ce choix est définitif… » ; second appui : prise | la confirmation est demandée par la mission (plus strict) |
| `_arbre` | l'autre amélioration : bouton présent, grisé | l'autre : plus de bouton, « ✕ », dessinée barrée — et, forcée, refusée par les règles | plus strict (aucun bouton, et le refus des règles est vérifié) |

Inchangées : niveau écrit, repère de l'onglet, « avant le rang du choix aucune amélioration », « elle est
au profil », « prise : marquée, son bouton disparaît », les quatre vérifications de « Tout rendre ».

**Ajoutées** (`test_ville.gd`, 96 de plus) : pastille de l'onglet et consigne de la Ville (montrée, tue
dans le Grimoire, acquise au premier point, coupée par le réglage) ; un médaillon par nœud de `tree_view`
pour les trois classes et cinq états de l'arbre, dans l'état rendu par les règles (les cinq états d'un
médaillon et les quatre d'une amélioration y passent tous) ; la raison des règles sous un bouton grisé ;
un achat refusé affiche leur raison ; la confirmation oubliée quand on regarde un autre nœud ; focus de
nœud en nœud qui les atteint tous, flèches, Entrée (panneau, puis achat), Échap ; mise en page des vrais
arbres des trois classes et de 3 à 8 nœuds par étage, en 1280 × 720 et 844 × 390 (aucun médaillon n'en
touche un autre, rien ne déborde, panneau à l'écran, la page ne défile pas ; en 1280 × 720 tout l'arbre
tient sans défiler).
`test_ecrans.gd` (+10) : barre d'expérience de l'écran de mort avec et sans niveau passé, rien en arène,
pastille du bouton d'entrée en Ville. `test_accueil.gd` (+22) : barre d'expérience du HUD, bandeau de
niveau (texte, place, effacement), rien en arène ; anneau de durée d'une compétence neuve (`slot_state`).
