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
| 4 | `buy_upgrade` : « niveau maximal » pour une amélioration inconnue | **NON corrigé** — bloqué par un test existant | `tests/regles/v2_loop.gd`, ligne 603, attend exactement `{"ok": false, "reason": "niveau maximal"}` pour l'identifiant « inconnue » : la correction le ferait rougir, et un test existant ne se modifie qu'avec l'accord de Pierre. Correction prête : dans `buy_upgrade`, avant le calcul du prix, rendre `{"ok": false, "reason": "inconnu"}` (la raison que `unlock` donne déjà) si `tuning.town.upgrades` n'a pas l'identifiant ; puis changer la ligne 603 du test. | aucun (il ne pourrait pas verdir) |
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

## Vu en passant, non corrigé

| Où | Constat | Pourquoi non corrigé |
|---|---|---|
| `sim/run.gd`, autels `bloodSouls`, `hpToSuper`, `cursedChest` | Même famille que le point 2b : à 1 PV, « Vendre votre sang » donne 20 Âmes PERMANENTES sans rien coûter, « Briser la clepsydre » remplit la jauge sans rien coûter, le coffre maudit ne coûte rien. | Hors de la liste ; `v2_contenu_autels.gd` (« jamais mortel ») décrit le paiement partiel comme voulu. Décision de Pierre. |
| `sim/enemies.gd`, `_separate` ; `sim/boss_charon.gd`, charge | Le corps du héros arrête la charge de Charon : le héros « infiniment lourd » repousse le Gardien à chaque image, qui reste collé à lui jusqu'à la fin de la ruée et n'atteint jamais le mur (mesuré : parti à 240 u, arrêté à 56 u du héros). Probablement pareil pour le Bélier. | Ressenti de combat : décision de Pierre. |
| `data/bestiaire.json`, Bélier | Un Bélier qui percute un mur peut ré-attaquer après 1,4 s (étourdi) + 0,3 s ; un Bélier qui ne percute rien, après 0,6 s + 1,6 s. Rater le mur est donc plus lent que le percuter. De même, étourdir un ennemi pendant son télégraphe annule le coup et lui rend une recharge de 0,3 s. | Équilibrage (hors du point 7, qui ne vise que la récupération). |
| `sim/run.gd`, `_apply_event` | Les nombres des autels d'origine (25 % de PV, 40 % de soin, 20 PV, 25 or) sont dans le code ET dans les libellés de `data/autels.json` : deux sources. La fonction fait 61 lignes (limite : 50). | Hors de la liste ; les autels ajoutés lisent déjà leurs nombres dans les données. |
| `sim/ai_common.gd` | La variation de recharge de l'archer (×0,85 à ×1,25) est une constante du code ; les archétypes ajoutés ont la leur en données (`cooldownJitter`). | Déplacer un nombre vers `data/` change le schéma : à faire à part. |
| `jeu/ville/onglet_grimoire.gd`, ligne 5 | « Compétence (bouton Lance) » : le même défaut que le point 9, côté affichage. | `jeu/` appartient à un autre chantier. |
| Reste du tableau d'origine | Portes ouvertes dès la mort du Gardien, `starterItems` et ses deux identifiants, `stashPush` à scores égaux, tirage perdu de `boss_minos.sweep`, appel perdu de `boss_colosse.geoliers`, obstacles résolus après les murs, recul départagé au dernier bit. | Hors de la liste de cette passe (design, ou sans effet connu). |
