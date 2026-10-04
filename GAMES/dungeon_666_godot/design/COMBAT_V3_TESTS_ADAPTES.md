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
