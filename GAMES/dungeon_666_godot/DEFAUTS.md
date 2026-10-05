# Dungeon 666 (Godot) — défauts de règles

`statut_artefact : PROPOSED` · passe du 2026-10-02. Origine des constats : le tableau « Défauts de
la spécification vus en portant » de `../dungeon_666/01_DESIGN/RELECTURES_V2.md` (version web,
figée : ce tableau-là n'est plus tenu à jour). Ici, la suite : ce qui a été corrigé dans `sim/`,
ce qui ne l'a pas été et pourquoi, et ce qui a été vu en passant.

Garde des corrections : `tests/regles/v3_defauts.gd` (9 tests, tous rouges sur le code d'avant,
verts après). Références réenregistrées une fois : voir plus bas.

## Les neuf points de la passe

| # | Défaut | État | Avant → après | Test (`v3_defauts.gd`) |
|---|---|---|---|---|
| 1 | `comboIndex` gardé au changement d'arme | **corrigé** (`sim/loadout.gd`, `resolve_kit`) | Reproduit : 3 coups de Dagues, Lame équipée, attaque → `SCRIPT ERROR: Invalid access of index '3'` dans `player.gd`, `_start_attack` (l'attaque ne part pas). Après : une arme d'un autre type remet l'enchaînement au coup 1 ; un autre exemplaire du même type le garde. | « défaut 1 · changer d'arme… » |
| 2a | Autel de sang : rareté forcée à « rare » | **corrigé** (`sim/run.gd`, `sim/boons.gd` : `best_rarity`) | Un tirage épique devenait rare. Après : la meilleure des deux (commun → rare, rare → rare, épique → épique). | « défaut 2 · … meilleure rareté… » |
| 2b | Autel de sang proposé à 1 PV | **corrigé** (`sim/run.gd`, `_option_blocked`) | À 1 PV l'offrande ne coûtait rien et donnait la bénédiction. Après : option grisée (`disabled`) et refusée quand elle ne retirerait aucun PV — le même mécanisme que les autres options impossibles. Tant qu'elle coûte au moins 1 PV elle reste acceptée (jamais mortelle, comme avant). | « défaut 2 · … à 1 PV… » |
| 3 | `prepare_doors` : deux portes identiques après 20 retirages | **corrigé** (`sim/run.gd`, `_other_reward`) | Après le garde-fou, la seconde porte gardait la récompense de la première. Après : repli sur la première récompense possible (poids > 0) différente, dans l'ordre des poids, sans tirage de plus. Une seule récompense possible : deux portes identiques, comme avant. | « défaut 3 · portes… » |
| 4 | `buy_upgrade` : « niveau maximal » pour une amélioration inconnue | **corrigé au second lot** (voir plus bas) ; d'abord bloqué par un test existant | `tests/regles/v2_loop.gd`, ligne 603, attend exactement `{"ok": false, "reason": "niveau maximal"}` pour l'identifiant « inconnue » : la correction le ferait rougir, et un test existant ne se modifie qu'avec l'accord de Pierre. Correction prête : dans `buy_upgrade`, avant le calcul du prix, rendre `{"ok": false, "reason": "inconnu"}` (la raison que `unlock` donne déjà) si `tuning.town.upgrades` n'a pas l'identifiant ; puis changer la ligne 603 du test. | aucun (il ne pourrait pas verdir) |
| 5 | `sanitize_profile` : `uid` ni typés ni uniques | **corrigé** (`sim/profile.gd`, `_fix_uids`) | Deux objets pouvaient porter le même `uid` (recycler l'un visait le premier trouvé), un `uid` pouvait être un nombre. Après : chaque objet a un identifiant texte, non vide, unique ; le premier porteur garde le sien, les autres sont réattribués, aucun objet n'est perdu ; `itemSeq` passe au-delà de tout « i<n> » présent. | « défaut 5 · profil… » |
| 6 | Charon, charge au mur : `patternStep` / `patternT` non remis à zéro | **corrigé** (`sim/boss_charon.gd`) — sans effet observable | Vérifié : rien ne lit ces deux champs pendant l'étourdissement ni le repos, et le pattern suivant les remet à zéro. Ni l'empreinte des références ni `state_hash` ne les contiennent. Corrigé quand même (l'état sonné passe par `D6BossCommon.set_state`) pour qu'un futur lecteur n'y trouve pas une valeur périmée. | « défaut 6 · Charon… » |
| 7 | Étourdi pendant sa récupération, un ennemi ré-attaque plus tôt | **corrigé** (`sim/ai_common.gd` : `stun`, `recharge_of` ; appelés par `sim/combat.gd`) | La recharge n'était posée qu'à la FIN de la récupération : étourdi avant, l'ennemi repartait avec 0,3 s de recharge. Mesuré sur un diablotin : 2e attaque à l'image 99 étourdi, 161 sans. Après : ce qu'il lui restait à attendre (fin de récupération + recharge) passe dans sa recharge au moment de l'étourdissement ; valable pour tout le bestiaire (diablotin, archer, brute, bélier, pyromancien, nécromancien, pavois, traqueur). | « défaut 7 · étourdir… » |
| 8 | `damageDealt` compte l'overkill, pas la jauge de Super | **corrigé** (`sim/combat.gd`) | Lecteurs de `damageDealt` : l'empreinte des références et un test de déterminisme (`v2_kits.gd`) ; ni les bots, ni les rapports, ni l'écran de mort. Après : une seule valeur, les PV réellement retirés, sert à la télémétrie et à la jauge. Le nombre affiché sur le coup (événement `hit`) et le vol de vie gardent le montant entier. | « défaut 8 · dégâts infligés… » |
| 9 | Textes qui disent « la Lance » quelle que soit la compétence | **corrigé** dans les données (`data/benedictions.json`, `data/butin.json`), aucun code | Textes rendus génériques, comme « Compétence : recharge −{v} % » l'était déjà. Détail ci-dessous. | « défaut 9 · aucun texte… » |

### Point 9 : les textes changés

Même forme qu'avant (un texte simple, lu tel quel par `D6Run.describe_boon` et `D6Loot.affix_text`) :
l'affichage n'a rien à changer.

| Où | Avant | Après |
|---|---|---|
| bénédiction `charme` | La Lance rend vulnérable : +{v} % de dégâts subis, 4 s. | Votre compétence rend vulnérable : +{v} % de dégâts subis, 4 s. |
| bénédiction `convoitise` | La Lance déclenche un éclair : {v} dégâts, 3 rebonds. | Votre compétence déclenche un éclair : {v} dégâts, 3 rebonds. |
| libellé `skillDamageMult` | dégâts de la Lance | dégâts de la compétence |
| libellé `skillCooldownMult` | recharge de la Lance | recharge de la compétence |
| suffixe de nom d'objet (`skillDamageMult`) | de la Lance | des Runes |

Le suffixe « des Runes » est un NOM : à juger par Pierre (goût). Les objets déjà rangés dans une
sauvegarde gardent leur ancien nom (« … de la Lance »), le nom étant écrit dans l'objet.

## Références réenregistrées

Une fois, à la fin : `bash references/enregistrer.sh`. **65 parties sur 70 ont changé**, 5 sont
identiques au bit près (`gardien_36_hache`, `gardien_54_arc`, `gardien_72_lame`,
`gardien_final_666`, `entrainement_cerbere`). Vérifié avant de réenregistrer, correction par
correction :

- points 1, 2, 3, 5, 6 : **0 partie** en écart ;
- point 7 : **14 parties** en écart. Dans chacune, un ennemi est étourdi pendant sa récupération
  avant le premier point de contrôle différent (ex. `bestiaire_elite_traqueur` : à l'image 298 la
  Nova étourdit un traqueur en récupération, l'écart est au point de contrôle de l'image 300) ;
  les 56 autres n'ont pas d'écart ;
- point 8 : **65 parties** en écart, et pour chacune le premier écart tombe exactement au premier
  point de contrôle qui suit son premier coup de grâce avec overkill (`damageDealt` est dans
  l'empreinte). Les 5 parties inchangées n'ont ni overkill ni étourdissement en récupération ;
- point 9 : aucune (les noms ne sont pas dans l'empreinte).

10 728 points de contrôle (10 729 avant).

## Second lot (2026-10-02, sur décision de Pierre)

Garde : `tests/regles/v3_defauts_2.gd` (5 tests, tous rouges avant, verts après).

| # | Défaut | Correction | Avant → après |
|---|---|---|---|
| 4 | `buy_upgrade` : « niveau maximal » pour une amélioration inconnue | `sim/profile.gd` ; la ligne 603 de `tests/regles/v2_loop.gd` (test préexistant) est changée avec l'accord de Pierre | Refus `{"ok": false, "reason": "inconnu"}`, rien n'est débité. |
| 10 | À 1 PV, les options d'autel payées en PV étaient gratuites (registre des âmes, clepsydre, coffre maudit) | `sim/run.gd`, `_option_blocked` : grisées et refusées quand il ne reste que `MIN_HP` | À 1 PV : refus, rien n'est donné. À 2 PV : permise, coûte 1 PV (jamais mortelle, comme avant). |
| 11 | Le corps du héros arrêtait la ruée de Charon et du Bélier, qui n'atteignaient jamais le mur | `sim/enemies.gd`, `_rushing` : pendant la RUÉE (pas le télégraphe), le héros ne repousse plus le chargeur | La ruée touche le héros une fois au passage, le traverse et finit sa course ; au mur, le chargeur est sonné (la fenêtre de punition existe enfin quand on encaisse ou qu'on esquive sur place). |
| 12 | Un Bélier qui percute un mur ré-attaquait après 1,7 s, contre 2,2 s sans rien percuter | `sim/enemies.gd`, `_charger_charge` : au mur, sa recharge vaut récupération + recharge et court pendant qu'il est sonné | Mesuré : 102 images avant, 132 après (2,2 s dans les deux cas ; au mur il en passe 1,4 sonné). |

Références réenregistrées une seconde fois : **32 parties sur 70 ont changé**, 10 712 points de
contrôle. Attribution vérifiée : avec les corrections 11 et 12 désactivées (4 et 10 gardées), les
70 parties se rejouaient sans aucun écart ; tout l'écart vient donc des ruées et du Bélier au mur.
Jouabilité après correction (20 et 20 graines) : solvabilité et classes PASS.

Reste de la même famille, NON corrigé (équilibrage) : étourdir un ennemi pendant son TÉLÉGRAPHE
annule le coup et lui rend une recharge de 0,3 s.

## Troisième lot (2026-10-02) : une seule source pour les nombres, reste du tableau d'origine

### Partie 1 — les nombres de réglage quittent le code (aucun changement de comportement)

Preuve : `bash outils/verifier.sh` VERT avec les 70 parties de référence **inchangées** (0 en écart,
10 712 points, sans réenregistrer). En plus, mesuré avant / après sur une copie du code d'avant :
les 245 textes vus par le joueur (libellés d'autel dans deux états du héros, marchand, salles
calmes, objets, bénédictions) sont identiques ; l'effet de chaque option de chaque autel et de
l'élixir du marchand est identique sur 12 graines et deux états (468 cas) ; chacun des 71 nombres
déplacés vaut, au bit près, le littéral qu'il remplace.

**Autels d'origine** (`data/autels.json`, `sim/run.gd`). Leurs nombres sont dans l'option, le
libellé les reprend par `{champ}` comme pour les autels ajoutés, le code n'en écrit plus aucun :
autel de sang `pct` 25 et `rarity` rare ; fontaine `pct` 40 et `gain` 1 ; coffre maudit `hp` 20 et
`rarity` rare ; Mammon `cost` 40, `family` avarice, `gain` 25 ; Registre `rarity` epique. Trois
effets changent de nom (ils portaient un nombre) : `heal40` → `heal`, `gadget1` → `gadgetCharge`,
`gold25` → `gold`. `_apply_event` (61 lignes) est découpée : `_apply_event`, `_event_boon`,
`_event_chest`. Aucun libellé ne mentait. Gardes ajoutées à `tests/regles/donnees.gd` : chaque effet a
les champs qu'il lit, raretés et familles existent, tout chiffre d'un libellé vient d'un `{champ}`
et tout nombre d'option y est dit ; le schéma liste les effets connus.

**Nombres déplacés vers `data/`** (71, autels à part) :

| Fichier | Réglages (valeur) |
|---|---|
| `bestiaire.json` | archer : `cooldownJitter` [0,85 ; 1,25], `approachSlack` 60, `strafeMult` 0,7, `strafeFlip` 0,01, `fireRangeFrac` 0,9 (son déplacement passe par `D6AiCommon.keep_distance`, comme les archétypes ajoutés) ; diablotin : `lockAt` 0,7, `circleDist` 1,25, `circleWithin` 1,6, `flankSpeed` 0,6 ; brute : `triggerFrac` 0,85 ; bélier : `lockAt` 0,7 ; `elite.massMult` 1,5 |
| `heros.json` | `player.lungeStretch` 1,5, `player.deathDelay` 1,4 ; `dash.chainFrom` 0,35 ; `autoAim` : `outOfConePenalty` 0,6, `stickyTime` 0,4, `stickyBonus` 60, `threatBonus` 40, `eliteBonus` 25 ; `combat` : `novaChillMult` 0,5, `armorCap` 0,6, `minDashRechargeMult` 0,35, `minSkillCooldownMult` 0,35, `maxCritChance` 0,75, `maxLifesteal` 0,15, `firstAttackDelay` 0,4, `firstAttackSpread` 0,8, `stunExitCooldown` 0,3, `burnTick` 0,25, `procBlastDelay` 0,12, `blastKnockback` 260 |
| `gardiens.json` | Charon : `slam.approachMult` 0,5, `charge.lockAt` 0,7, `ring.range` 1400, `summon` : `teleRadius` 70, `minPlayerDist` 150, `minR` 40, `maxR` 160 ; `guardians` : `spawnTime` 1,2, `clearHeal` 0,5, `knockbackMult` 0,15, `restApproachDist` 160, `reinforce` {180, 60, 260} |
| `salles.json` | `room` : `spawnTime` 0,25, `rewardRadius` 30, `calmRadius` 34, `pickupSettle` 0,35, `pickupFriction` 6, `pickupSpeed` 80, `pickupSpeedSpread` 120, `pickupRadius` 10, `goldRadius` 6 |
| `etages.json` | `encounter.nextWaveAt` 0,25 |
| `butin.json` | `economy` : `goldReward` {×3, 6 pièces}, `healReward` 0,3, `shopHeal` 0,4 (le texte « Rend 40 % des PV. » de l'élixir en est tiré), `shopPriceJitter` 9, `shopRareChance` 0,25, `salvage` {5, 10, 3} ; `loot` : `bossLegendaryChance` 0,2, `affixFloorScale` 0,012 |
| `benedictions.json` | bloc `boons` (nouveau, `tuning.boons`) : `offerSize` 3, `duoChance` 0,6, `levelStep` 0,5 |

`stunExitCooldown` (0,3 s) est la recharge rendue après un étourdissement : la valeur n'a pas
changé, c'est une décision de Pierre ; elle est seulement devenue réglable. `D6Profile.salvage_souls`
n'a plus sa copie de la table des Âmes (elle lit `town.salvageSouls`). `D6Loot.salvage_value` prend
maintenant la partie en premier argument (appelée seulement par `sim/run.gd`).

**Laissés dans le code**, et pourquoi :

| Nombres | Raison |
|---|---|
| Recul de la Lance (120, `player.gd`) | **Bloqué par un test existant** : `tests/regles/v2_kits.gd`, ligne 132, compare la Lance à un dictionnaire exact ; y ajouter `recoil` le fait rougir. À déplacer dans `skills.lance.recoil` (le champ existe pour d'autres compétences) quand la ligne pourra être changée. |
| Tolérances et sentinelles : `1e-6`, `1e-9`, `1e-3`, `TINY`, `EPS`, `MIN_DIR`, `NEVER_TARGETED`, `COMBO_EXPIRED` (99), `UNREACHED`, `NEVER`, bornes de `sanitize_profile` (1e6, 1e9), arrondis d'affichage (×10, ×100, ×1000), seuil d'un tic de brûlure (0,5 PV) | Technique : aucun n'est un réglage. |
| Garde-fous : `DOOR_GUARD`, `WAVE_GUARD`, `PLACEMENT_TRIES`, 4 retirages d'attaque de Gardien, `ROOM_POINT_STEPS` | Bornes de boucles. |
| Résolution des calculs : `MIN_STEP`, `STEP_RADIUS_FRAC` (physique), `CELL`, `INFLATE`, `REFRESH_TICKS` (navigation), `THROW_STEP`, `SIM_HZ`, `DT`, sels et constantes d'empreinte | Technique. |
| Marges de contact et de dessin d'un télégraphe : +4, +8, +10, +14 u, arc 0,9 du diablotin, `CHARGE_HIT_PAD`, bouche d'un tir (`MUZZLE`, rayon + 4), `LAND_OVERLAP`, `CLEARANCE`, marge d'allonge (6 u) | Géométrie d'équité (« esquiver au pixel le bord rouge suffit ») liée au dessin, pas un réglage d'équilibre. |
| Placement : `REWARD_CLEARANCE`, `PLACEMENT_MARGIN`, `CROWD_DIST`, rayon 14 / 30 passé à la recherche d'un point d'apparition, spirale de la récompense, entrée du héros (−70 u), place du Gardien (35 % de la hauteur), répartition des portes (32 % + 36 %), orbe de phase (+30 u), `DOOR_W`, `DOOR_H` | Mise en place de la salle. `DOOR_H` est recopié dans `jeu/monde/portes.gd` (`SEUIL`) : le déplacer seul ne ferait pas une source unique. |
| Seuils d'entrée : `MANUAL_DEADZONE` 0,15, `MOVE_DEADZONE` 0,2 (`aim.gd`), et leurs jumeaux écrits en dur dans `player.gd` (0,15 ; 0,04 = 0,2² ; 0,2 ; 0,0001) | Lecture des commandes. Les réunir changerait un bit (0,2 × 0,2 ≠ 0,04) : pas sans décision. |
| Axe du recul : `KNOCK_AXIS` 0,7 (`kit_common.gd`) et 0,7 / 0,3 (`player.gd`) | Forme d'une formule, écrite deux fois ; 1 − 0,7 ≠ 0,3 au dernier bit, les réunir changerait les parties. |
| Poids du score d'objet (`item_score` : /2, /12, /25, ×8, +2) | Formule de comparaison « mieux / moins bien », pas un réglage de jeu — mais voir le point 15 plus bas. |
| `HIT_FLASH` 0,1, `HURT_FLASH` 0,35, frein du corps mort (0,85), hauteur de cloche d'un lancer | Retour visuel : aucune règle ne les lit. |
| `MIN_HP` 1 (`run.gd`) | Une règle (« un paiement en PV n'est jamais mortel »), pas un réglage. |
| Pile ou face (`< 0,5`) | Tirages équiprobables. |

### Partie 2 — défauts restants du tableau d'origine

Garde : `tests/regles/v3_defauts_3.gd` (7 tests : 5 rouges sur le code d'avant, verts après ; 2 témoins).

| # | Point | Verdict | Avant → après | Test |
|---|---|---|---|---|
| 13 | `boss_minos`, `_sweep` : un tirage pour rien | **défaut, corrigé** | Dès la phase 2 (une brèche par bande), la brèche commune était tirée puis jetée : 9 tirages au lieu de 8 pour un balayage de 6 bandes. Après : elle n'est tirée que si elle sert. Rien ne change pour le joueur, sauf la suite des tirages. | « défaut 13 » |
| 14 | `boss_colosse`, `geoliers` : appel consommé sans geôlier | **défaut, corrigé** | Sans point d'apparition libre, l'appel de la phase était compté, le bouclier levé puis aussitôt retombé, « invocation » et « bouclier » annoncés pour rien. Après : un appel qui ne fait venir personne ne compte pas et n'annonce rien ; le Colosse pourra rappeler. Un appel partiel (un geôlier sur deux) compte. `geoliers` est découpée (`_call_jailers`, `_raise_shield`). | « défaut 14 » |
| 15 | `profile`, `_stash_push` : à scores égaux le plus ancien part | **départage laissé tel quel ; un vrai problème en amont, à trancher par Pierre** | Mesuré sur 300 coffres de 24 objets trouvés : dans 292, le plus bas score est partagé — le départage joue presque à chaque éviction. La raison : 20 % des objets trouvés ont un score de 0 (talismans communs, sans base ni affixe), et les exemplaires forgés (arme de départ, arme débloquée en Ville) ainsi que l'armure de départ portent un score de 0 **écrit en dur**. Conséquence mesurée : les « Dagues ébréchées » forgées au déblocage (payé en Âmes) quittent un coffre plein avant des amulettes vides plus récentes, et ne se reforgent pas (« déjà débloqué »). Le départage n'en est pas la cause (n'importe quel ordre perdrait un objet de score 0) ; la corriger demande un choix — donner aux exemplaires forgés leur vrai score (5 pour une arme de base : change les comparaisons affichées), ou protéger le dernier exemplaire d'un type débloqué. Non corrigé. | « point 15 » (témoin) |
| 16 | `game`, `create_game` : deux identifiants pris à chaque partie | **pas un défaut, non corrigé** | Les identifiants de l'équipement de départ sont pris même si le profil a déjà son équipement. Seul effet : la numérotation commence à 3. C'est ce qui fait qu'une même graine donne la même partie (mêmes identifiants, même empreinte) avec un profil neuf ou repris ; ne plus les prendre décalerait tous les identifiants selon le profil et changerait les 70 références sans rien apporter. | « point 16 » (témoin) |
| 17 | `physics`, obstacles résolus après les murs | **défaut de la physique, corrigé par précaution** | Les salles « alcoves » et « goulet » ont des obstacles collés au mur. Un corps dont le centre est DANS un tel obstacle, plus près du mur que des autres bords, en était sorti… dans le mur, et y retombait à chaque image (reproduit : diablotin rendu en x = 11, hors de la salle). Après : sortie par le bord le plus proche qui reste dans la salle. **Aucun chemin de jeu trouvé pour y arriver** : les déplacements sont sous-découpés, et la seule poussée sans collision (le héros qui repousse un ennemi) n'y mène pas — 62,9 millions de couples héros/ennemi valides essayés autour de ces obstacles, 0 cas. Correction sans effet sur les références (0 partie). Garde de données ajoutée (`donnees.gd`) : entre un obstacle et un mur, rien ne passe ou le plus gros corps passe. | « défaut 17 » |
| 18 | `physics`, ligne de vue échantillonnée tous les 16 u ; tirs testés au point d'arrivée | **défaut, corrigé** | Regard : sur 20 000 regards au hasard entre deux points libres, 0,6 à 2 % selon la salle passaient à travers un coin de pilier (corde de moins de 16 u entre deux échantillons) : un ennemi « voyait » le héros et marchait, tirait ou chargeait droit dans le coin ; la visée assistée prenait une cible cachée. Tir : la collision ne regardait que le point d'arrivée de l'image ; une flèche (6,3 u par image), une Lance (15 u), un carreau d'arbalète (1400 u/s : 23,3 u) traversaient un coin (5 flèches sur 12 dans le test). Après : test exact du segment contre chaque obstacle (`D6Physics.segment_hits_obstacle`), pour les regards (`line_of_sight`) et pour les tirs (`shot_blocked` : projectiles et tirs du héros). Raser un bord ou toucher un coin n'est pas traverser. | « défaut 18 » (deux tests) |

Références réenregistrées une fois : **64 parties sur 70 ont changé**, 10 714 points de contrôle
(10 712 avant). Six sont identiques au bit près : `arene`, `entrainement_cerbere`, `gardien_36_hache`,
`gardien_54_arc`, `gardien_54_sans_dash`, `gardien_72_lame`. Attribution vérifiée avant de
réenregistrer, sur onze copies du projet (une seule correction active, puis toutes sauf une) :

- aucune correction : 0 partie en écart ;
- 13 seule : 1 partie (`phases_minos`, image 2440 : un tirage de moins dans le générateur de l'IA) ;
- 14 seule, 17 seule : 0 partie ;
- 18, regards seuls : 63 parties (ex. `etage_14_martele`, image 70 : un diablotin en (768, 136)
  voyait le héros en (451, 619) à travers le coin haut-gauche du pilier central, corde de 7,8 u ;
  il le contourne maintenant) ;
- 18, tirs seuls : 13 parties, dont une que les regards ne touchent pas (`gardien_final_666`,
  image 2052 : un orbe de Charon passait le coin d'un pilier de l'arène, il s'y arrête) ;
- les cinq ensemble : 64 parties, exactement la réunion des précédentes.

## Quatrième lot (2026-10-04) : le parcours étendu, et ce qu'il a fait corriger

Garde : `tests/regles/v3_defauts_4.gd` (3 tests, tous rouges sur le code d'avant, verts après).

| # | Défaut | Correction | Avant → après |
|---|---|---|---|
| 19 | Un objet ÉQUIPÉ en donjon (butin pris, objet acheté au marchand) entrait dans le profil sans identifiant (`uid`) ; l'équipement de départ d'un profil neuf non plus. Ils ne le recevaient qu'à la relecture du profil (`sanitize_profile`) : le profil en mémoire et le profil relu du disque différaient. | `sim/run.gd` (`_wear`, appelée par `_apply_loot` et `_apply_shop`) et `sim/game.gd` (`create_game`, quand l'équipement de départ entre dans le profil) : l'objet reçoit son identifiant en entrant dans le profil, par `D6Profile.ensure_uid`, comme un objet rangé au coffre. | Avant : `uid` absent en mémoire (test : « uid : <null> », puis « .equipment.arme.uid : clé en trop » à la relecture). Après : identifiant posé, unique ; le profil relu est le profil en mémoire, tel quel. |

Références : **non réenregistrées**. Les 70 parties se rejouent sans écart avec la correction
(10 714 points de contrôle identiques) : ni `uid` ni `itemSeq` ne sont dans l'empreinte. Le
parcours (`jeu/essai/test_parcours.gd`) compare maintenant le profil du disque d'essai au profil
en mémoire sans passer par `sanitize_profile`.

Hors des règles, le même jour :

| Où | Constat | État |
|---|---|---|
| `jeu/principal.gd`, `demarrer_entrainement` | Ne prenait pas de graine (`randi()`) : un entraînement n'était pas reproductible par l'API. | **Corrigé** : graine optionnelle en dernier argument, comme `demarrer_descente` ; sans elle, rien ne change. Le parcours s'en sert (et vérifie que la partie porte la graine demandée). |
| `jeu/essai/assemblage.gd`, `cout.gd`, `profondeur.gd` | Ces trois bancs montent le VRAI jeu (`jeu/principal.tscn`) sans poser `D666_DONNEES` : ils comptaient sur `outils/capture.gd`. Ouverts seuls (scène lancée à la main, éditeur), ils lisaient et écrivaient le vrai `profil.json` et le vrai `reglages_jeu.json` du joueur (une descente y est lancée : le profil est enregistré dès l'entrée dans l'étage). | **Corrigé** : chacun pose son dossier d'essai (`user://essais`) s'il n'y en a pas, avant de monter le jeu. Les autres bancs et tests le faisaient déjà. |
| `addons/studio_kit/ecran/transitions.gd`, `fondu` ; `jeu/ecrans/ecrans.gd`, `_fondre` | Message « ObjectDB instances leaked at exit » à la sortie des tests sans fenêtre. Ce qui reste : l'interpolation (`Tween`) et les coroutines (`GDScriptFunctionState`) d'un fondu d'écran coupé net, quand le nœud est libéré pendant le fondu (0,3 s). Reproduit hors du jeu en vingt lignes avec le seul `StudioTransitions`. Dans le jeu, cela n'arrive que si l'on ferme la fenêtre pendant un fondu, à l'instant où tout est rendu au système : rien ne s'accumule en jouant (le parcours le mesure). Dans les tests : à chaque `app.free()`. | **Tests corrigés** (`jeu/essai/fondus.gd` : laisser finir les fondus avant de libérer ; parcours, `test_ecrans.gd`, `test_accueil.gd`, `jeu/theme/verifier.gd`). **Cause laissée** : elle est dans le kit du studio (une coroutine qui attend `finished` d'une interpolation), à corriger là-bas. Restent : `test_ville.gd` (un son encore en lecture à la sortie) et `test_finitions.gd` (une coroutine), non traités ; le parcours a montré le message une fois sur huit lancements, cause non établie. |

## Cinquième lot (2026-10-04) : combat V3, étape 1 bis — déplacement de classe, terrain à franchir

Ce n'est pas une passe de défauts : c'est une règle neuve (`design/COMBAT_V3.md`, « Étape 1 bis »).
Gardes : `tests/regles/v3_terrain.gd` (50 tests), `tests/regles/v3_combat.gd` (un test adapté, trois
neufs : l'ultime ne s'arme que si l'appui a commencé jauge pleine), `tests/regles/donnees.gd` (deux
tests ajoutés), `jeu/monde/test_terrain.gd`.

Références réenregistrées une fois : **61 parties sur 70 ont changé**, 9 sont identiques au bit
près (`arene`, `bestiaire_pavois_habile`, `entrainement_cerbere`, `gardien_36_sans_dash`,
`gardien_54_sans_dash`, `gardien_72_sans_dash`, `hasard_lame`, `kit_dagues`, `kit_lame`) ; 8 parties
`terrain_*` ajoutées (78 au total). Attribution vérifiée avant de réenregistrer, sur une copie du
projet (le code du lot, une partie du changement désactivée) :

- tout désactivé (ultime armé comme avant, les trois classes au dash, terrain jamais tiré) :
  **0 partie** en écart — rien d'autre n'a changé (la physique, la navigation et les bots rendent
  les mêmes parties dans une salle sans terrain) ;
- l'ultime seul : 39 parties (le bot habile relâche un pas avant l'ultime, le bot qui martèle n'en
  lance plus) ;
- les déplacements de classe seuls : 19 parties, toutes de Bourreau ou de Chasseresse ;
- le terrain seul : 48 parties (dès qu'une salle de combat est tirée à l'étage 5 ou plus, le
  tirage des dispositions n'est plus le même ; ex. `etage_5_martele_ville`, image 0) ;
- les trois ensemble : 61 parties, exactement la réunion des trois listes.

Vu en faisant ce lot, non tranché :

| Où | Constat | Pourquoi laissé |
|---|---|---|
| `data/classes.json`, Bourreau | Le **Bond du bourreau** (compétence) et le **saut** (déplacement) sont deux sauts invulnérables sur la même classe. Ils partagent le vol (`D6KitCommon.flight_moves`) mais pas le rôle : le Bond frappe (34 dégâts, étourdit, 260 u, 6 s), le saut repousse sans dégât (132 u, 1,3 s). | Double emploi partiel : décision de Pierre. Le Bond n'a pas été retiré. |
| Jouabilité, Bourreau | Mesure des bots (20 graines) : la valeur du déplacement du Bourreau passe de ×10,2 et ×12,1 à ×2,1 et ×2,2 (seuil ×2) et sa section 1 battue de 100 % à 95 % (Hache) et 90 % (Maillet ; seuil 90 %). Une seule charge, plus lente à revenir : le bot esquive moins. | C'est la demande (« une seule charge, recharge plus longue ») ; les nombres sont à juger en main. Marge faible sur l'oracle : si le saut est encore ralenti, il rougira. |
| `sim/kit_common.gd`, `throw_point` | Un objet LANCÉ (bombe, pot du Brasier) peut retomber sur une rivière : il passe au-dessus du terrain bas comme un tir. Le piège et le totem, posés aux pieds du héros, sont toujours sur la terre ferme. | Lisible (ça explose au-dessus de l'eau) ; un sol qui brûle sur l'eau est à juger à l'écran. |
| `sim/enemies.gd`, `_separate` | Le héros « infiniment lourd » qui retombe contre un gros ennemi au bord de l'eau peut le pousser de quelques unités dans la rivière ; la collision de marche l'en ressort à l'image suivante, par le bord le plus proche (très rarement l'autre rive pour un champion). | Aucun cas trouvé par les tests (recul, contournement, 300 graines) ; pas de règle simple sans toucher à la séparation. |
| `sim/boss_*.gd` | Les salles de Gardien n'ont pas de terrain. La ruée de Charon s'arrête pourtant au bord d'un terrain bas (testé), et le Traqueur franchit ; le bond de Cerbère n'a pas été adapté. | À faire si un jour une arène de Gardien reçoit une rivière. |
| `jeu/` | Le point d'arrivée vert / rouge pendant la visée du déplacement (`design/COMBAT_V3.md`, §4) n'existe pas : le déplacement ne se vise pas, il part dans le sens de la marche. `D6Player.move_landing` donne déjà le point. | Lot « affichage des commandes ». |

## Sixième lot (2026-10-04) : combat V3, étape 2 — les trois ultimes de classe

Règle neuve (`design/COMBAT_V3.md`, « Étape 2 »), pas une passe de défauts. Gardes :
`tests/regles/v3_ultimes.gd` (57 tests), 14 tests existants adaptés (`design/COMBAT_V3_TESTS_ADAPTES.md`).

Références réenregistrées une fois : **66 parties sur 78 ont changé**, 12 sont identiques au bit
près (`bestiaire_pavois_marteau_martele`, `contenu_murs_marteau`, `entrainement_cerbere`,
`etage_14_martele`, `etage_5_martele_ville`, `gardien_36_sans_dash`, `gardien_54_sans_dash`,
`hasard_dagues`, `hasard_lame`, `section_marteau_martele`, `terrain_gues_hasard_arbalete`,
`terrain_torrent_marteau_martele` : aucune n'y lance d'ultime) ; 7 parties `ultime_*` ajoutées (85 au
total, 12 984 points de contrôle). Attribution vérifiée avant de réenregistrer : avec tout le code
du lot en place mais les trois anciens Supers rebranchés sur les classes (un seul champ de données
par classe), les 78 parties se rejouaient **sans aucun écart** — physique, navigation, combat et
bots rendent les mêmes parties tant qu'aucun ultime neuf n'est lancé ; tout l'écart vient donc des
trois ultimes. L'empreinte d'une partie ne porte les limiers (`al`) que s'il y en a.

Vu en faisant ce lot, non tranché :

| Où | Constat | Pourquoi laissé |
|---|---|---|
| `data/benedictions.json`, `data/butin.json`, `data/autels.json` | Les textes disent « le Super » (Ripaille, Passion brûlante, Gloire charnelle, Extase, Ivresse, Trop-plein, affixe « charge du Super », clepsydre) ; le jeu dit maintenant « l'ultime ». Les effets valent pour les trois ultimes (testé un par un). | Un mot à choisir une fois pour tout le jeu : à Pierre. |
| Gloire charnelle, « dure 0,4 s de plus » | Sur la Sentence capitale, la durée allongée est celle du geste invulnérable (rien de plus ne frappe) ; sur la forme et la meute, 0,4 s sur 10 et 12 s. | Le bonus de dégâts, lui, compte pour les trois. À rééquilibrer avec l'arbre. |
| Autel « Boire le temps » (vider la jauge contre des PV) | Pris pendant une forme ou une meute, il n'arriverait qu'en salle calme, où aucun ultime n'agit (ils finissent au changement de salle). | Sans effet aujourd'hui. |
| `sim/ult_meute.gd` | Un ennemi de mêlée accaparé par un limier le frappe au contact SANS télégraphe (la règle « tout coup ennemi est télégraphié » protège le héros, pas ses invocations). Les tireurs et les Gardiens ne se détournent jamais. | Règle simple et lisible ; à juger en main. |
| `sim/ult_forme.gd`, Ruée spectrale | Le héros est POSÉ à l'arrivée d'un trait (pas de vol image par image) : il traverse les ennemis et le terrain bas, un mur l'arrête. | Le plus simple qui se lise (un trait de braise) ; à juger à l'écran. |
| Jouabilité, Revenant | Le bot sans dash bat la section 1 bien plus souvent qu'avant (voir le rapport du lot) : la forme soigne (vol de vie) et étourdit. | Nombres proposés : à juger en main, avant de toucher l'oracle. |
| `jeu/partie.gd` | Les limiers ne sont pas interpolés entre deux pas de simulation (ils ne sont pas dans la table des positions d'avant) : à 60 images par seconde cela ne se voit pas. | Hors du périmètre du lot (`jeu/partie.gd`). |

## Septième lot (2026-10-04) : combat V3, étape 3 — l'arbre de compétences

Règle neuve (`design/COMBAT_V3.md`, « Étape 3 »), pas une passe de défauts. Gardes :
`tests/regles/v3_arbre.gd` (62 tests), 3 tests ajoutés à `donnees.gd`, 5 tests existants adaptés
(`design/COMBAT_V3_TESTS_ADAPTES.md`).

Références réenregistrées une fois : **17 parties sur 85 ont changé**, et seulement par les deux
événements neufs comptés dans l'empreinte (`levelUp`, `treePoint`) — vérifié partie par partie en
rejouant les 85 avec ces deux événements retirés de l'empreinte : 0 écart. L'arbre vide ne change
donc rien d'autre à la simulation. 6 parties `arbre_*` ajoutées (arbre rempli) : 91 au total.

Jouabilité : les oracles jouent l'arbre vide ; `outils/arbre.gd` (mesure, pas oracle) compare
arbre vide et arbre plein.

Constantes laissées dans le code (techniques) : `sim/tree.gd` — `TREE_SCHEMA` (version du profil qui
porte l'arbre : marqueur de migration), `FIRST_RANKED` (le rang 1 d'une compétence est dans
`classes.json`), `EXTRA_FIELDS` (les nombres qu'une amélioration peut ajouter : liste de ce que le
code sait lire, gardée par `donnees.gd`) ; `sim/kit_skills.gd` — `CHANNEL_OWN` (champs d'une
compétence `canal` qui ne règlent pas le Super joué).

| Où | Ce qui reste | Suite |
|---|---|---|
| `sim/player.gd` | Une compétence `canal` (ancien Super) rend invulnérable tout le geste et bloque la jauge d'ultime pendant ce temps (elle passe par l'état « super ») ; ses dégâts sont de source « super » : le bonus « Gloire charnelle » s'y applique, « dégâts des compétences » non. | À juger par Pierre ; sinon un état propre à écrire. |
| `sim/kit_gadgets.gd` | Le « sol en feu » de la Nova brûle au rythme du Brasier d'âmes (`skills.brasier.tick`, `burnRefresh`) : la Nova n'a pas ces deux nombres à elle. | Les lui donner si on veut les régler à part. |
| `data/arbres.json` | **Traité au huitième lot.** Chaîne et Bombe ont le même nœud (mêmes rangs, mêmes améliorations) chez le Revenant et le Bourreau, écrit deux fois. | Étape 4 (contenu) : les différencier, ou partager le nœud. |
| `jeu/` | Rien ne se voit en jeu quand un niveau est passé (un son seulement) ; l'arbre est une liste de cartes. | Lot « bel écran de l'arbre ». |
| `sim/tree.gd` | La migration donne l'avance à la seule classe portée : un joueur qui a surtout joué une autre classe la retrouve au niveau 1. | Le profil ne garde pas ses ennemis tués par classe ; à trancher par Pierre. |

## Huitième lot (2026-10-05) : combat V3, étape 4 — les compétences neuves

Contenu neuf (`design/COMBAT_V3.md`, « Étape 4 »), pas une passe de défauts. Gardes :
`tests/regles/v3_competences.gd` (62 tests) ; le test générique des rangs de `v3_arbre.gd` joue de
lui-même les neuf nœuds neufs (+9) ; 1 test existant adapté (`design/COMBAT_V3_TESTS_ADAPTES.md`).

Le défaut « Chaîne et Bombe ont le même nœud chez le Revenant et le Bourreau » (septième lot) est
traité : une version par classe (rang 1 commun, rangs du Bourreau et une amélioration sur deux propres).

Références réenregistrées une fois : **2 parties existantes sur 91 ont changé**, `arbre_hasard_dagues`
et `arbre_hasard_marteau` — les deux seules qui jouent la Chaîne et la Bombe au rang 3 avec une
amélioration (leur spec a dû changer d'amélioration de Bombe, « fumigène » et « grappe » ayant changé
de classe ; les rangs du Bourreau ont changé). Les 89 autres — arbre vide, kit de départ, ultimes,
arbres pleins sans Chaîne ni Bombe — sont identiques au bit près : les compétences neuves ne
changent rien à qui ne les équipe pas. 9 parties `competences_*` ajoutées : 100 au total (deux d'entre elles, au hasard et sans héros
invulnérable, pour qu'une parade et un blocage RÉUSSIS soient dans les références).

Constantes laissées dans le code (techniques) : `sim/neuves_revenant.gd` — `RETURN_SPEED`,
`RETURN_RANGE`, `RETURN_RADIUS` (le tir renvoyé par « Miroir » : il doit seulement rattraper un
tireur), `MUZZLE` ; `sim/neuves_bourreau.gd` — `REACH_STEP` (pas de la recherche du mur) ;
`sim/neuves_chasseresse.gd` — `PLACE_STEP`, `PLACE_MARGIN` (recul d'un leurre posé où rien ne se pose).

| Où | Ce qui reste | Suite |
|---|---|---|
| `data/arbres.json` | Trois compétences neuves par classe, pas quatre. | Pistes : double spectral (Revenant), pluie de flèches à retardement ou faucon (Chasseresse), une quatrième pour le Bourreau. |
| `sim/neuves_chasseresse.gd` | Le Trait se bande d'un appui (second appui : tir immédiat) ; il ne se charge pas en MAINTENANT le bouton. | Le maintien demande un champ « bouton tenu » par emplacement dans l'entrée d'un pas (entrées, bots, codec des références) : lot à part, si le geste manque en main. |
| `sim/neuves_revenant.gd` | La Contre-taille pare TOUT coup pendant sa garde, même mortel, même d'un Gardien. | À juger : plafonner, ou excepter les Gardiens. |
| `sim/neuves_revenant.gd` | Le Stigmate ne sert à rien contre un Gardien seul (il n'explose qu'à la mort du marqué). | À juger : un effet à l'expiration de la marque. |
| `sim/neuves_revenant.gd`, `sim/kit_zones.gd` | Les braises du Sillage et la « Poix ardente » brûlent au rythme du Brasier d'âmes (`skills.brasier.tick`, `burnRefresh`), comme le sol en feu de la Nova. | Les leur donner si on veut les régler à part. |
| `sim/ult_meute.gd` | Le leurre n'attire que la mêlée en chasse qui peut l'atteindre tout droit ; tireurs et Gardiens l'ignorent. | Règle des limiers, gardée telle quelle. |
| `sim/neuves_bourreau.gd` | La Garde de fer ne dit pas au HUD combien elle a encaissé ; le « Contrecoup » ramène l'encaissé à l'échelle de l'étage 1 (sinon l'onde compterait deux fois la profondeur). | À juger en profondeur. |
| `jeu/interface/` | Le bouton d'une compétence ne montre ni la charge du Trait ni la durée d'un sillage ou d'une garde (`D6Loadout.slot_state` les rend). | Lot d'affichage du HUD (tenu par un autre chantier). |
| `outils/arbre.gd` | Avec 10 graines, les dégâts reçus par salle varient encore beaucoup d'une mesure à l'autre. | Plus de graines pour trancher un nombre. |

## Neuvième lot (2026-10-05) : combat V3, étape 5 — quatrième compétence, sons, mesure en profondeur

Contenu neuf et une passe d'échelle (`design/COMBAT_V3.md`, « Étape 5 »). Gardes :
`tests/regles/v3_competences_2.gd` (28 tests), `tests/regles/v3_profondeur.gd` (5 tests) ; le test
générique des rangs de `v3_arbre.gd` joue de lui-même les trois nœuds neufs (+3) ; 3 tests existants
adaptés, tous pour le NOMBRE de compétences d'une classe (`design/COMBAT_V3_TESTS_ADAPTES.md`).

**Défaut d'échelle corrigé.** Les soins que l'arbre donne en PV ne suivaient pas les PV du héros (100 à
l'étage 1, 1 260 à l'étage 325 avec une armure rare) : Moisson (6 PV), Dîme de sang (4 PV par ennemi),
Soif (1 PV par ennemi) valaient douze fois moins au 325 qu'à l'étage 1. Ils passent par
`D6Combat.heal_scaled` (× `hpGrowth` de l'étage : ×1, ×4,0 au 109, ×9,9 au 325). À l'étage 1 rien ne
change. Les dégâts, eux, n'avaient pas ce défaut : tout coup du héros est multiplié par l'arme portée
(`D6Combat._scaled_amount`), la jauge d'ultime aussi.

Références réenregistrées une fois : **aucune des 100 parties existantes n'a changé** (rejouées
identiques avant d'écrire : la quatrième compétence ne change rien à qui ne l'équipe pas, l'événement
`dash` a gagné un champ que l'empreinte ne lit pas, et aucune partie ne soigne avec Moisson, Soif ou
Dîme en étant blessée). 6 parties `competences2_*` ajoutées : 106 au total.

Constantes laissées dans le code (techniques) : `sim/neuves_revenant.gd` — `SHADE_SIDE`, `SHADE_SNAP`,
`SHADE_STOP` (place et rattachement de l'ombre liée), `ECHO_SHOW` (durée d'affichage du coup répété).

| Où | Ce qui reste | Suite |
|---|---|---|
| `data/classes.json`, `data/arbres.json`, `data/ville.json`, `data/benedictions.json` | Les bonus de PV écrits en dur (Bourreau +40, Chasseresse −20, Sang vif +8 par rang, Cuir épais +12, Vitalité, Voracité +30) ne suivent pas la vie du héros : +40 PV = +40 % à l'étage 1, +3 % au 325. | Équilibrage (force relative des classes) : à Pierre. Proposition chiffrée : `_dev/rapports/profondeur.md`. |
| `data/benedictions.json` | Les soins en PV des bénédictions (Festin : 2 PV par ennemi tué…) ont le défaut d'échelle corrigé dans l'arbre. | Contenu d'avant le combat V3, non touché : les passer par `D6Combat.heal_scaled` si Pierre le veut. |
| `sim/combat.gd`, `_charge_super` | La jauge suit l'arme ; les PV des ennemis montent plus vite et les salles sont plus peuplées : 1,5 à 1,9 fois plus d'ultimes par section au 325 (mesuré). | À juger ; piste : `chargeDamage` × l'échelle des PV ennemis de l'étage. |
| `sim/ult_forme.gd` | Arbre plein, la Forme du Damné fait moins de dégâts que le kit qu'elle remplace (×0,93 au 109, ×0,86 au 325) : les compétences au rang 5 sont figées, les griffes ne profitent d'aucun rang. | Équilibrage : à Pierre (pistes dans le rapport). |
| `outils/bots/base.gd`, `nav_dir` | Le bot habile reste parfois coincé au coin d'un mur de la disposition « chicane », salle nettoyée, sans rejoindre la récompense : 6 parties sur 540 de la mesure en profondeur (aucune mort). | Lot à part : ce bot joue les oracles et les références (à réenregistrer). Graines dans le rapport. |
| `sim/neuves_revenant.gd` | L'Ombre jumelle répète les coups de MÊLÉE seulement (les deux armes du Revenant) ; son coup répété balaie aussi les tirs ennemis, comme un coup d'arme. | À juger. |
| `sim/neuves_chasseresse.gd`, `sim/kit_common.gd` | Visée à la main, la Grêle (comme le Brasier et la Bombe) tombe à une distance FIXE (`throwDist`) : le bouton donne une direction, pas un point. | Demande une visée « point » dans l'entrée d'un pas : lot à part. |
| `jeu/son/` | Personne n'a encore écouté les sons : 38 recettes neuves, sobres exprès. | Écoute par Pierre : `_dev/sons/` (liste dans `design/COMBAT_V3.md`). |

## Vu en passant, non corrigé

| Où | Constat | Pourquoi non corrigé |
|---|---|---|
| `sim/run.gd`, autels `bloodSouls`, `hpToSuper`, `cursedChest` | Même famille que le point 2b : à 1 PV, « Vendre votre sang » donne 20 Âmes PERMANENTES sans rien coûter, « Briser la clepsydre » remplit la jauge sans rien coûter, le coffre maudit ne coûte rien. | Hors de la liste ; `v2_contenu_autels.gd` (« jamais mortel ») décrit le paiement partiel comme voulu. Décision de Pierre. |
| `sim/enemies.gd`, `_separate` ; `sim/boss_charon.gd`, charge | Le corps du héros arrête la charge de Charon : le héros « infiniment lourd » repousse le Gardien à chaque image, qui reste collé à lui jusqu'à la fin de la ruée et n'atteint jamais le mur (mesuré : parti à 240 u, arrêté à 56 u du héros). Probablement pareil pour le Bélier. | Ressenti de combat : décision de Pierre. |
| `data/bestiaire.json`, Bélier | Un Bélier qui percute un mur peut ré-attaquer après 1,4 s (étourdi) + 0,3 s ; un Bélier qui ne percute rien, après 0,6 s + 1,6 s. Rater le mur est donc plus lent que le percuter. De même, étourdir un ennemi pendant son télégraphe annule le coup et lui rend une recharge de 0,3 s. | Équilibrage (hors du point 7, qui ne vise que la récupération). |
| `sim/run.gd`, `_apply_event` ; `sim/ai_common.gd` | Nombres des autels d'origine et variation de recharge de l'archer écrits dans le code. | **Fait au troisième lot** (partie 1). |
| `jeu/ville/onglet_grimoire.gd`, ligne 5 | « Compétence (bouton Lance) » : le même défaut que le point 9, côté affichage. | `jeu/` appartient à un autre chantier. |
| Reste du tableau d'origine | `starterItems`, `stashPush`, `boss_minos.sweep`, `boss_colosse.geoliers`, obstacles et murs : **traités au troisième lot** (points 13 à 18). Restent : portes ouvertes dès la mort du Gardien, recul départagé au dernier bit. | Design (décision de Pierre) ; sans effet connu. |
| `sim/profile.gd`, `sim/loot.gd` : score des objets forgés | Arme de départ, arme débloquée en Ville et armure de départ portent `score: 0.0` écrit en dur, comme un talisman commun vide : premiers évincés d'un coffre plein, et toujours « moins bien » dans les comparaisons. Détail : point 15. | Choix de règle (vrai score, ou dernier exemplaire protégé) : décision de Pierre. |
| `data/autels.json`, mots des libellés | Les nombres d'un libellé viennent des champs ; les MOTS non : « bénédiction rare », « épique », « objet rare », « d'Avarice » sont écrits à la main à côté des champs `rarity` et `family`. Changer le champ sans le mot ferait mentir le libellé. « +{gain} charge » ne s'accorde pas au pluriel. | Demande un libellé composé de noms (raretés, familles) : à décider. |
| `data/autels.json`, Miroir d'orgueil | `hp` 20 et `pct` 25 de l'option redisent les nombres du pacte `reflet_brise` (`data/benedictions.json`) : deux sources, tenues égales par `tests/regles/v2_contenu_autels.gd` (« le libellé et le pacte disent les mêmes… »). | Le test existant lit ces deux champs : les retirer le ferait rougir. |
| `tests/regles/v2_contenu_autels.gd`, Forge | Le test écrit `0.5` en dur pour le gain par niveau, maintenant réglable (`boons.levelStep`) : changer le réglage le fera rougir. | Test existant. |
| `data/butin.json`, `loot.bossGuaranteedRare` | Réglage que rien ne lit : après un Gardien, l'objet est « rare » (ou légendaire) par le code de `sim/run.gd`, quel que soit ce booléen. | Le brancher ou le retirer : à décider (le schéma l'exige). |
| `sim/boss*.gd` | Les invocations de Gardien cherchent un point d'apparition pour un corps de 14 u, quel que soit l'ennemi invoqué (un renfort plus gros qu'un archer apparaîtrait trop près d'un obstacle). | Sans effet avec les renforts actuels (rayons 12 à 14). |
| `sim/projectiles.gd`, `sim/kit_shots.gd` | Un tir arrêté par un coin garde sa position d'arrivée (au plus un pas après le coin) : l'impact s'affiche là, pas sur le pilier. | Affichage ; le point d'entrée exact demanderait de le calculer. |
| `sim/state.gd`, `create_player` | 51 lignes (limite : 50) : un seul dictionnaire. 56 depuis le combat V3 (`slots`, `castSlot`, `superHold`), 58 depuis l'étape 1 bis (`superArm`, `dashDur`). | Hors de la liste. |
| Combat V3, étape 1 : ultime par maintien | Un joueur qui GARDE l'attaque enfoncée pour enchaîner voyait l'ultime partir tout seul 0,4 s après que la jauge est pleine (le bot qui martèle lançait ainsi 1 à 5 ultimes par partie). | **Corrigé à l'étape 1 bis** sur décision de Pierre : l'ultime ne s'arme que si l'appui a COMMENCÉ jauge pleine (`player.superArm`). |
| Combat V3, étape 1 : attaque glissée au doigt | Glisser sur le bouton d'attaque donne deux coups : un à l'appui (visée assistée), un au relâcher (visé). | Geste à trancher au lot « affichage » (frapper seulement au relâcher ?). |
| `data/benedictions.json`, `data/butin.json`, `data/autels.json`, `sim/calm_rooms.gd` | Textes au singulier (« Votre compétence… », « charge de gadget », « Charges de gadget pleines ») alors que l'effet vaut maintenant pour toute compétence / tout gadget équipé. | Mots : au lot « affichage », ou à Pierre. |
| `sim/player.gd`, tampon | Une seule action en attente : deux compétences pressées au même pas, seule la dernière part. | Règle du tampon d'origine ; à revoir si l'arc de trois boutons le rend gênant. |
