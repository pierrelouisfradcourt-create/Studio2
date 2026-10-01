# Dungeon 666 — relectures adversariales de la V2 (reprise du 2026-10-01)

`statut_artefact : PROPOSED` · rien n'est ratifié. Ce fichier existe parce que les constats des
relectures de la passe précédente n'avaient été écrits nulle part : ils ont été perdus à la
clôture, il a fallu relancer les relectures. Chaque constat a ici son statut et sa preuve.

État de sortie : `node run-oracle.mjs` VERT — 260 tests, solvabilité, classes, e2e 39/39.
Chaque test neuf a été rejoué sur le code d'avant correction : il y échoue.

## Lot CLASSES

| Constat | Mesure avant | Correction | Mesure après | Garde |
|---|---|---|---|---|
| Hache et Maillet maintenus sur place étourdissent en boucle | Maillet : 0 coup de brute reçu en 30 s | **Garde** : 1,5 s après un étourdissement, un coup d'arme ne ré-étourdit plus (`combat.stunGuard`) ; écu dessiné au bout de la barre de vie | Maillet 8,0 coups, Hache 13,9 (Lame : 15,0) | `tests/v2_classes.test.mjs`, `tools/classes.mjs` |
| La Chasseresse se passe du dash | Sans dash : 66 % (arc) et 61 % (arbalète) des dégâts de l'étalon ; elle recule de 185 u/s en tirant, un diablotin court à 150 | Vitesse en tirant (`moveMult` 1,1 → 0,6 ; 0,8 → 0,4) et recul des tirs réduit | Sans dash : 94 % et 87 % de l'étalon | idem |

Reste à juger en main (D11) : la Chasseresse bien jouée ne prend presque rien (0,3 dégât par
salle contre 2,7 pour le Revenant) ; les diablotins restent tenus à distance par le RECUL du
Maillet (2,1 coups en 30 s) ; le Bourreau qui martèle sans lire tient jusqu'à l'étage 15.

## Lot ÉTAGES

| # | Constat | Statut |
|---|---|---|
| 1 | La jauge de Super ne suivait pas l'arme : 90 coups pour un Super à l'étage 1, 3 à l'étage 649 ; 43 % du temps en Super en section 37 | **Corrigé** (`combat.mjs`). Après : 5 à 9 % à toute profondeur. Test `v2_etages_relecture`. |
| 2 | Victoire au 666 : écran sans issue, « checkpoint » posé sur le Gardien final | **Corrigé** (`run.mjs`, `ui/menus.mjs`). Vérifié en navigateur. Test. |
| 3 | Salle d'élite : champion hors du bestiaire de l'étage (Pyromancienne à l'étage 2) | **Corrigé** (`room.mjs`). Test sur 300 graines. |
| 4 | Valeurs plates et or laissés derrière par le scaling (Festin 2 PV = 0,1 % des PV au 649 ; bourse de chambre forte dominée par le recyclage) | **À Pierre** — économie (D10). |
| 5 | « Méditer » sur Envol donnait 3,5 charges de dash | **Corrigé** (`calm_rooms.mjs`, `stats.mjs`). Test. |
| 6 | Chambre forte : la bourse annonçait un montant et en versait un autre (89 % des coffres) | **Corrigé** (`calm_rooms.mjs`). Test sur 60 graines. |
| 7 | `?floor=abc` plantait la sim ; le repli de `main.mjs` pouvait remplacer le profil | **Corrigé** : étage illisible = étage 1 ; un profil n'est remplacé qu'après archivage. README mis à jour. Test + navigateur. |
| 8 | Mort après une téléportation en arrière : reprise imposée au checkpoint le plus profond | **À Pierre** — choix de design (pilier 5). |

## Lot BESTIAIRE

| # | Constat | Statut |
|---|---|---|
| 1 | Champion d'élite hors bestiaire | **Corrigé** (même correction que Étages 3). |
| 2 | Archer et Pyromancienne inertes derrière un obstacle (fuite et approche s'annulaient) | **Corrigé** : on ne fuit que ce qu'on voit. Test `v2_bestiaire_relecture`. |
| 3 | Invocations « fermées » : or de Main avide sans fin tant que l'invocateur vit | **Corrigé** pour l'or. Les soins au kill sur invocation restent : **à Pierre** (toucherait aussi les renforts des Gardiens). |
| 4 | L'arène d'essai ne montre jamais le Nécromancien ni les trois champions V2 | **À Pierre** (le test existant fige « étage de début de section »). |
| 5 | La flaque brûle toutes les 1,0 s au lieu de 0,5 s (l'invulnérabilité après coup avale un tick sur deux) | **À Pierre** — réglage. |
| 6 | Le disque de contact du Bélier et du Diablotin déborde parfois le télégraphe (4 coups sur 354) | **Ouvert** — cause non isolée. |
| 7 | Le souffle d'un élite ardent frappait après « salle nettoyée » | **Corrigé** (`run.mjs`). Test. |
| 8 | `burnDps` jamais remis à zéro | **Corrigé** (`enemies.mjs`). Test. |

Observé en passant, non corrigé : étourdir un ennemi pendant sa récupération lui fait sauter sa
recharge (il ré-attaque plus tôt que si on ne l'avait pas étourdi).

Scripts de reproduction des relectures : hors dépôt (dossier de travail de la session du
2026-10-01). Les tests ci-dessus en sont la forme durable.

## Portage Godot (2026-10-01) : ce que le portage a fait remonter

Décision de Pierre : « une version plus propre sur Godot ». La simulation web reste la
spécification ; la version Godot (`GAMES/dungeon_666_godot/`) la rejoue et doit retrouver les
mêmes états AU BIT PRÈS (`bash outils/verifier.sh` : 44 parties, 7 373 points de contrôle).

Changement fait côté web pour rendre cette égalité possible : la simulation ne calcule plus ses
sinus, cosinus, arcs tangentes, exponentielles et puissances par `Math.*` (dont le dernier bit
change d'un moteur à l'autre) mais par `src/core/trig.mjs`, écrit avec les seules quatre
opérations. Effet de bord utile : une partie est désormais identique quel que soit le navigateur.

Défauts de la spécification vus en portant, **portés tels quels, non corrigés** (à trier) :

| Où | Constat |
|---|---|
| `combat.mjs`, recul | `if (kb * kb > cur2)` : deux tirs de même recul à la même image se départagent au dernier bit (tir roulé de l'arc, éventail de l'arbalète). Sans effet depuis `trig.mjs`, mais fragile. |
| `player.mjs` | `comboIndex` n'est pas remis à zéro au changement d'arme : passer d'une arme à 3 coups à une arme à 2 coups et attaquer dans les 0,32 s planterait. Non reproduit en partie réelle. |
| `run.mjs`, Gardien vaincu | Les portes s'ouvrent tout de suite alors qu'un butin vient d'être posé : on peut partir sans le prendre. |
| `run.mjs`, autel `bloodBoon` | Force la rareté « rare » même si le tirage était épique ; reste proposé à 1 PV. |
| `run.mjs`, `prepareDoors` | Après 20 tirages identiques, deux portes peuvent porter la même récompense. |
| `game.mjs`, `createGame` | `starterItems` consomme deux identifiants à chaque partie, même quand le profil a déjà son équipement. |
| `profile.mjs`, `buyUpgrade` | Répond « niveau maximal » pour une amélioration inconnue. |
| `profile.mjs`, `sanitizeProfile` | Ne vérifie ni le type ni l'unicité des `uid` des objets. |
| `profile.mjs`, `stashPush` | À scores égaux, c'est toujours le plus ancien objet du coffre qui part. |
| `boons.mjs`, `loot.mjs` | Les textes disent « la Lance » quelle que soit la compétence équipée. |
| `boss_charon.mjs`, charge | Au mur, l'état passe à « stunned » sans remettre `patternStep` / `patternT` à zéro. |
| `boss_minos.mjs`, `sweep` | Un tirage aléatoire consommé pour rien en phase 2 et plus. |
| `boss_colosse.mjs`, `geoliers` | L'appel de la phase est consommé même si aucun point d'apparition n'est trouvé. |
| `physics.mjs` | Les obstacles sont résolus après les murs, sans re-bornage ; la ligne de vue échantillonne tous les 16 u. |
| `combat.mjs` | `damageDealt` compte l'overkill, alors que la jauge de Super l'exclut. |

## Contenu ajouté (2026-10-01)

`statut : PROPOSED` — demande de Pierre : « go améliorer le contenu ». Rien n'est équilibré « en
main » : chaque nombre ci-dessous vient d'un ordre de grandeur pris sur le contenu d'origine, et
le fun reste une gate Pierre. Garde : `tests/v2_contenu.test.mjs` (40 tests, un par élément) ;
parité Godot : 15 parties notées de plus (`tools/traces.mjs`, noms `contenu_*`, `autel_*`, `salle_*`).

Avant → après : 21 → **35 bénédictions** (5 par famille), 4 → **8 duos**, 0 → **1 pacte**,
4 → **10 pouvoirs légendaires**, 4 → **8 autels**, 9 → **13 dispositions de salle**.

### Nouveaux types d'effet (tous interprétés dans `src/sim/combat.mjs`, portés dans `sim/combat.gd`)

Une bénédiction reste une DONNÉE. Le vocabulaire des procs s'est élargi, sans aucun cas
particulier par identifiant :

| Champ | Valeurs nouvelles | Où c'est déclenché |
|---|---|---|
| `on` (quand) | `dodge` (esquive parfaite) | `combat.damagePlayer` |
| | `wallSlam` (ennemi projeté contre un mur) | `enemies.integrate` |
| | `super` (Super lancé) | `player.startSuper` |
| | `roomClear` (salle nettoyée) | `run.onRoomClear` |
| | `overheal` (soin au-delà des PV max) | `combat.healPlayer` |
| | `dash` et `kill` : généralisés (n'importe quel effet, plus seulement `nova` / `heal` / `blast`) | `player.startDash`, `combat.killEnemy` |
| `when` (condition) | `finisher` (dernier coup du combo : `attack.finisher`, porté par les tirs) ; `untouched` (salle sans blessure : `room.hurt`) | `fireProcs` / `applyHitProcs` |
| `effect` sur la cible | `stun` (respecte la garde et les Gardiens), `blast` (explosion télégraphiée 0,12 s), `cull` (achève sous un seuil), `gold` | `applyTargetEffect` |
| `effect` sur le héros | `surge` (dégâts en plus pendant n s : `player.surge`), `superCharge` (fixe ou par unité), `dashCharge`, `gadgetCharge`, `heal`, `gold` | `applyProc` |
| `effect` autour du héros | `around` + `apply` (pose un effet de cible à tout ennemi dans le rayon) ; `nova` existait | `aroundHero`, `heroNova` |
| `effect` passif | `goldPower` (par tranche d'or portée), `streakBonus` (`run.streak` : salles d'affilée sans blessure), `stunnedCrit` | `damageEnemy` |

`stats.mjs` : la valeur d'un proc est `pct ? v / 100 : v` pour tous les effets (plus de liste
d'effets) ; `valueFixed` dit qu'elle est une chance ; `stats: {…}` porte les contreparties d'un pacte.
Aucun nouvel événement de simulation : les effets réutilisent `dashNova`, `chain`, `hazard`
(`sinBlast`), `heal`, `gold`, `souls`, `superReady`, `dashReady`, `gadgetCharge`, `boonGain`.

### Bénédictions (valeur de base = commun ; rare ×1,4 ; épique ×1,8)

| Nom | Famille · emplacement | Effet chiffré | Intention de jeu | D'où vient le nombre |
|---|---|---|---|---|
| Représailles | Colère · passif | Après une esquive parfaite : +40 % de dégâts pendant 3 s | Esquiver PUIS punir : le dash devient l'ouverture du combo | Furie = +20 % permanent ; ici le double, mais seulement 3 s après une esquive réussie |
| Coup de sang | Colère · attaque | Le dernier coup du combo fait exploser la cible : 12 dégâts, rayon 70 | Finir ses combos au milieu d'un groupe ; exclut Lame ardente | Lame ardente = 18 dégâts par cible sur 3 s ; 12 de zone, une fois par combo |
| Bâillement | Paresse · passif | Esquive parfaite : 8 dégâts et −50 % de vitesse pendant 3 s, rayon 150 | L'esquive gèle la mêlée autour de soi | Brume lente = 8 dégâts, rayon 90, 2 s à chaque dash ; ici plus large et plus long, mais rare |
| Mur du sommeil | Paresse · passif | Un ennemi projeté contre un mur reste sonné 1,2 s | « L'environnement est une arme » devient un build (armes à recul) | Mur seul = 0,45 s ; un Bélier au mur = 1,4 s |
| Prime de risque | Avarice · passif | Salle nettoyée sans être touché : +10 or | Jouer propre paie | Une salle rapporte 8 à 14 or : la prime la double |
| Trésor de guerre | Avarice · passif | +4 % de dégâts par tranche de 25 or en bourse, 5 tranches au plus | Thésauriser ou dépenser au marchand | Plafond +20 % = Furie, atteint à 125 or (une bénédiction du marchand = 70) |
| Bouchée double | Gourmandise · attaque | Le dernier coup du combo rend 1,5 PV par ennemi touché | Soin au rythme du combo ; exclut Sang dévoré | Sang dévoré = 5 % des dégâts ≈ 1,1 PV sur un 3ᵉ coup de Lame |
| Ripaille | Gourmandise · passif | Lancer le Super rend 15 PV | Le Super devient une potion ; synergie Extase | Élixir du marchand = 40 % des PV pour 40 or ; le bot lance 1 à 2 Supers par minute de combat |
| Baiser volé | Luxure · dash | La frappe de dash rend vulnérable : +25 %, 4 s | Ouvrir chaque échange par dash + frappe ; exclut les déflagrations de dash | Charme fatal = +30 % sur la compétence (à recharge) ; la frappe de dash est plus fréquente |
| Ivresse | Luxure · passif | Une esquive parfaite charge le Super de 8 % en plus | Esquiver nourrit le Super | Base = 6 % par esquive parfaite : ×2,3 |
| Éclair de dépit | Envie · dash | Chaque dash lance un éclair : 9 dégâts, 3 ennemis au plus | Le dash comme attaque à distance | Pas de braise = 12 dégâts dans 80 u ; ici moins fort mais porte à 200 u |
| Mauvais œil | Envie · passif | Chaque ennemi tué lance un éclair : 8 dégâts, 2 rebonds | Tuer le plus faible d'abord, réactions en chaîne | Jalousie = 10 dégâts, 25 % de chances par coup |
| Invaincu | Orgueil · passif | +6 % de dégâts par salle nettoyée sans être touché (5 au plus) ; une blessure remet à zéro | Un build « sans faute » qui se perd d'un coup | Plafond +30 % = Superbe (à PV pleins) |
| Mépris | Orgueil · passif | +50 % de chances de critique contre les ennemis sonnés | Sonner (murs, Hache, Maillet, gadgets) puis frapper | Fortune = +10 % permanent ; ici ×5, mais sur une fenêtre d'étourdissement |

### Duos

| Nom | Familles | Effet chiffré | Intention de jeu | D'où vient le nombre |
|---|---|---|---|---|
| Passion brûlante | Colère + Luxure | Lancer le Super enflamme les ennemis proches : 10 dégâts/s pendant 4 s, rayon 220 | Le Super ouvre le combat | Orage ardent = 8 dégâts/s, 3 s |
| Faire les poches | Paresse + Avarice | Un ennemi projeté contre un mur lâche 2 or (fixe) | Les murs rapportent | Un diablotin lâche 1 à 3 or |
| Trop-plein | Gourmandise + Orgueil | Chaque PV soigné au-delà du maximum charge le Super de 1 % (jamais pendant le Super) | Rester à PV pleins nourrit le Super | Festin (2 PV par mort) à PV pleins = 2 % par ennemi tué |
| Foudre du dédain | Envie + Orgueil | Les éclairs achèvent les ennemis sous 15 % de PV (sauf Gardiens) | Les éclairs finissent le travail | Coup de grâce = +50 % sous 30 % de PV |

### Pacte (accordé par un autel, jamais offert)

| Nom | Famille | Effet chiffré | Intention de jeu |
|---|---|---|---|
| Reflet brisé | Orgueil (compte pour ses duos) | +25 % de dégâts, −20 PV max, jusqu'à la mort | Puissance contre marge d'erreur ; listé avec les bénédictions, donc sur l'écran de mort |

### Pouvoirs légendaires (objets, PERMANENTS)

| Nom | Effet chiffré | Intention de jeu | D'où vient le nombre |
|---|---|---|---|
| … d'Alastor | Une esquive parfaite rend 1 charge de dash | Enchaîner les esquives | Base : 0,5 s rendues sur 0,9 s de recharge |
| … de Bélial | Le dernier coup du combo étourdit 0,6 s (la garde de 1,5 s tient) | Toute arme devient une arme lourde | Hache = 0,5 s, Maillet = 0,7 s |
| … de Lilith | La frappe de dash lance un éclair en chaîne : 16 dégâts, 3 rebonds | Build « dash + frappe » | Azazel = 12 dégâts, 30 % de chances par coup |
| … de la Main de gloire | Salle nettoyée sans être touché : +1 charge de gadget (jusqu'au plein) | Le gadget à chaque salle pour qui joue propre | Un élite tué rend déjà 1 charge |
| … de Moloch | Un ennemi projeté contre un mur explose : 20 dégâts, rayon 90 | Viser les murs | Mur seul = 8 dégâts à la cible |
| … d'Abaddon | Les ennemis tués explosent : 12 dégâts, rayon 80 | Réactions en chaîne dans les nuées | Cœur de braise = 14 dégâts, rayon 85, par dash |

### Autels (libellés chiffrés par les champs de l'option ; une option impossible est grisée)

| Autel | Options | Dilemme | D'où viennent les nombres |
|---|---|---|---|
| Registre des âmes | Céder 40 Âmes → bénédiction épique · Vendre son sang : −25 PV → +20 Âmes · Refermer | PERMANENT contre TEMPORAIRE, dans les deux sens | 40 Âmes ≈ Vitalité 1 + 2 (15 + 30) ; 20 Âmes = 20 ennemis tués |
| Forge des regrets | Fondre la bénédiction la moins avancée → la plus avancée gagne 2 niveaux (les deux sont NOMMÉES) · Garder | TEMPORAIRE : largeur contre profondeur | 2 niveaux = +100 % de la valeur ; la Fontaine en donne 1 sans rien prendre |
| Miroir d'orgueil | Briser : −20 PV max et +25 % de dégâts jusqu'à la mort (pacte Reflet brisé) · Baisser les yeux | TEMPORAIRE : marge d'erreur contre puissance | Furie = +20 % ; Voracité = +30 PV max |
| Clepsydre de Charon | Boire : vider la jauge de Super (50 % au moins) → +35 % des PV · Briser : −15 PV → jauge pleine · Passer | Une ressource de combat contre l'autre | Fontaine des âmes = 40 % des PV, gratuits |

### Dispositions de salle (jamais dans les Limbes, qui gardent les six d'origine)

| Disposition | Forme | Cercles (poids) | Intention de jeu |
|---|---|---|---|
| `colonnade` | Deux rangées de trois colonnes (50 u) autour d'une nef | Luxure 1, Hérésie 2, Trahison 1, Abîme 1 | Six murs où projeter, lignes de tir hachées |
| `chicane` | Deux longs murs décalés (520 × 40) : traversée en S | Colère 1, Violence 1, Fraude 2, Trahison 1, Abîme 1 | Coupe les archers, piège les Béliers |
| `goulet` | Deux massifs collés aux murs latéraux, col central de 470 u | Gourmandise 2, Violence 1, Trahison 1, Abîme 1 | Tenir le col ou se faire prendre en tenaille |
| `ilots` | Deux gros blocs (220 × 120) en diagonale | Avarice 1, Fraude 1, Trahison 1, Abîme 1 | Tourner autour d'un couvert épais |

Entrée, portes et centre (récompense à sa place naturelle) dégagés : vérifié par
`tests/v2_floors.test.mjs` (accessibilité, combat réel du bot) et `tests/v2_contenu.test.mjs`.

### Incertain (à juger en main)

- **Les bots n'esquivent presque jamais « parfaitement »** (0 à 3 esquives par minute) : Représailles,
  Bâillement, Ivresse et Alastor ne sont mesurés ni par la solvabilité ni par `tools/classes.mjs`.
- **Coup de sang** en groupe serré : chaque cible touchée explose, les explosions se recouvrent.
- **Mauvais œil / Abaddon** : réactions en chaîne (bornées par le nombre d'ennemis) — nuées de diablotins.
- **Mur du sommeil** + armes à fort recul : un ennemi peut être reprojeté pendant qu'il est sonné.
- **Trésor de guerre** : la bourse suit le héros d'un run à l'autre (Charon n'en prend que la moitié) ; un profil riche prend la bénédiction déjà au plafond.
- **Registre des âmes** : le taux 25 PV → 20 Âmes peut encourager à « traire » chaque autel avant un soin.
- **Main de gloire** : un gadget par salle propre, c'est peut-être trop pour les gadgets forts.
- **Représailles n'a pas d'indicateur à l'écran** (`player.surge` existe, aucun rendu ne le montre) : à
  ajouter côté affichage pour respecter « le temporaire se lit ».
- Le pacte porte la famille Orgueil pour s'afficher comme les autres bénédictions : il rend donc
  éligibles les duos d'Orgueil.

## Bestiaire ajouté (2026-10-01)

`statut : PROPOSED` — même demande de Pierre (« go améliorer le contenu »). 7 → **10 archétypes**.
Les trois nouveaux comblent trois vides du bestiaire : aucun ennemi ne demandait de se PLACER
(pavois), aucun ne frappait d'où l'on ne regarde pas (traqueur), aucun ne changeait l'ORDRE dans
lequel tuer la vague sans rien invoquer (étendard). Chacun fait travailler le dash (pilier 1) et
tient les règles de lisibilité (pilier 2) : aucun dégât de contact, tout coup télégraphié en rouge
au moins 0,4 s, durées identiques à toute profondeur et pour un champion « rapide », alerte
inoffensive marquée `harmless`. Rien n'est équilibré « en main » : le fun reste une gate Pierre.

Garde : `tests/v2_foes_2.test.mjs` (27 tests). Parité Godot : 11 parties notées de plus
(`tools/traces.mjs`, noms `bestiaire_*` : bots habile / sans dash / martèle / hasard, deux champions,
deux étages profonds) — `bash outils/verifier.sh` : **70 parties, 10 729 points de contrôle, VERT**.
Dix erreurs introduites exprès dans une copie du portage (arc de garde, pivot, secteur du coup,
dos / face du traqueur, image de retour, jeton d'embuscade, rayon et effet de l'aura…) : les dix
sont détectées par ces parties.

| | Porte-pavois (`pavois`) | Traqueur (`stalker`) | Porte-étendard (`banner`) |
|---|---|---|---|
| Rôle | Garde de face : mêlée lourde qu'on ne blesse pas de front | Embuscade : il disparaît et resurgit dans le dos | Soutien : il protège les autres, ne frappe jamais |
| Entrée (section 1) | étage **10** | étage **12** | étage **14** |
| Coût de vague · poids | 2,5 · 1,5 | 2 · 1,5 | 2 · 1,2 |
| Jeton | mêlée | mêlée (tenu de la dissolution à la frappe) | aucun |
| Champion | oui — jamais `blinde` ni `bouclier` | oui — jamais `bouclier` ni `invocateur` | non |
| Fichiers | `foe_pavois.mjs` | `foe_stalker.mjs` | `foe_banner.mjs` |

Règles de défense partagées : `src/sim/foe_defense.mjs` (lu par `combat.damageEnemy`), porté dans
`sim/foe_defense.gd`. Code commun touché, des deux côtés : `combat` (coup arrêté, protection),
`ai_common.activeAttackers` (les états `fade` et `ambush` tiennent un jeton), `enemies` (un ennemi
`hidden` revient à l'image même où son délai s'achève), `foes` (inscription).

### Porte-pavois

- **Règle.** Il porte un pavois tourné vers `e.face`. Un coup d'ARME ou de COMPÉTENCE (`melee`,
  `strike`, `skill`) qui arrive de face, dans un arc de 126° (`guardArc` 2,2 rad), ne porte pas : ni
  dégât, ni recul, ni étourdissement, et le coup sonne (événement `deflect` avec `guard: true`, au
  point de contact). De dos et de flanc, tout passe. Gadget, Super, brûlure, éclairs et murs passent
  toujours. Le pavois est BAISSÉ quand il est étourdi, et ÉCARTÉ pendant la récupération de son
  propre coup (0,9 s).
- **Son coup.** À portée et devant lui : télégraphe rouge en secteur de 86° et 96 u pendant 0,6 s,
  face VERROUILLÉE (télégraphe et récupération : 1,5 s sans pivoter), puis tout le secteur frappe
  d'un bloc (15 dégâts). Le secteur dessiné est le secteur qui touche.
- **Contre-jeu.** Dasher à travers lui : on est dans son dos, il lui faut ~1 s pour se retourner
  (115°/s). Ou sortir du secteur pendant son télégraphe et le punir dans sa récupération. Ou
  l'étourdir (mur, gadget). L'étourdir ou le tuer pendant le télégraphe annule le coup.
- **Nombres.** PV 56 et dégâts 15 : ceux du Bélier (52 ; 14), la moitié des coups rebondissant. Vitesse 96
  et masse 3 : entre le Bélier (115 ; 2) et la Brute (92 ; 4). Télégraphe 0,6 s : entre le Diablotin
  (0,42) et la Brute (0,7). Récupération 0,9 s : celle de la Brute (0,95). Recharge 1,5 s. Or 3-5.
  Pivot 2 rad/s : un demi-tour en 1,6 s, quand un dash (165 u en 0,15 s) le traverse.
- **Mesuré (bots, 150 salles des étages 10 à 16).** Habile : 0 dégât reçu de lui, 320 coups arrêtés,
  il vit 10 s (Brute : 14 s). Sans dash : 405 dégâts. Qui martèle de face : 3 523 dégâts, sa première
  cause de blessure — et il finit quand même par le tuer (pavois écarté après chaque coup).

**Description visuelle (pour le lot des créatures).** Silhouette trapue, plus large qu'un Bélier
(rayon 20), couleur rouille sombre (`#8a4a2a`). Devant lui un grand PAVOIS de bronze (`#e0b24a`,
cerné de sombre) : un arc épais qui couvre exactement `guardArc` (126°), centré sur `e.face` — et non
sur le héros : il ne regarde PAS toujours le héros, c'est tout l'intérêt. Un bossage clair au
centre du pavois dit où il regarde. Le DOS (à l'opposé de `e.face`) doit se lire comme nu et
vulnérable : échine sombre, pas d'armure. À lire à l'écran :
`e.face` (rad) = orientation du pavois ; `D6FoeDefense.guard_up(game, e)` = pavois levé ; faux
quand `e.stun > 0` (pavois tombé) ou `e.state == "recover"` (pavois écarté sur le côté, terni :
« frappe maintenant ») ; `e.state == "windup"` = il arme (pavois ramené en arrière puis projeté),
le secteur rouge est dans `e.tele` (`shape: "cone"`, `area: true`) ; événement `deflect` avec
`guard: true` = étincelles et mot « PARÉ » au point (`x`, `y`) du pavois.

### Traqueur

- **Règle.** Il rôde à distance (250 u), puis : **dissolution** 0,35 s (immobile, visible,
  vulnérable) → **disparu** 0,5 s (`e.hidden`, ni ciblable ni touchable) → il **resurgit dans le dos
  du héros** (à 62 u, à l'opposé de l'orientation du héros ; sur son flanc si le dos est un mur) et
  un cercle rouge de 82 u s'arme autour de lui pendant **0,55 s** → frappe (14 dégâts) → longue
  **récupération** 1 s, collé au héros.
- **Contre-jeu.** Lire la dissolution, puis sortir du cercle : 36 u suffisent droit devant soi, mais
  en plein combo (héros ralenti) c'est le dash qui sort — ou qui traverse la frappe (esquive
  parfaite). Puis le punir : il reste là 1 s. Le tuer ou l'étourdir pendant la dissolution annule
  l'embuscade ; pendant le télégraphe, annule la frappe (`hazardCancel`).
- **Nombres.** PV 30 : ceux de la Pyromancienne (assassin fragile). Vitesse 150 : le Diablotin.
  Dégâts 14 : le Bélier. Télégraphe 0,55 s : au-dessus du seuil (0,4) et du Diablotin (0,42).
  Rayon 82 : sous la Brute (105). Recharge 3,2 s ± : entre la Pyromancienne (3,4) et l'Archer (1,7).
  Or 2-4. De la dissolution à la frappe : 1,4 s, dont 0,55 s en rouge.
- **Mesuré.** Habile : 50 dégâts sur 121 traqueurs. Sans dash : 702 (5,8 par traqueur). Il vit 6 s.

**Description visuelle.** Silhouette MINCE et allongée vers le héros (une amande, rayon 14), prune
sombre (`#5a1f4a`), deux yeux magenta (`#ff3cbe`), deux lames fines le long du corps. À lire :
`e.state == "fade"` = il se dissout : opacité qui tombe de 1 à ~0,1 sur `fade` (0,35 s), fumée ;
`e.hidden == true` (état `ambush`, et `e.spawnT > 0`) = **ne rien dessiner du tout** à son ancienne
place (pas d'ombre, pas de barre de vie, pas l'animation d'apparition) ; `e.state == "windup"` = il
vient de resurgir, lames écartées et levées, le cercle rouge est une ZONE (`game.hazards`,
`kind: "stalker"`, liée à lui par `sourceId`) ; `e.state == "recover"` = essoufflé, lames basses :
« punis-le ». Un souffle de fumée au point de réapparition aide à se retourner (son cri d'attaque
part au même instant : `enemyAttack`, `enemy: "stalker"`).

### Porte-étendard

- **Règle.** Il n'attaque jamais. Tant qu'il est debout (ni mort, ni étourdi), les AUTRES ennemis à
  moins de 260 u de lui ne prennent que **60 %** des dégâts (`wardMult`), toutes sources confondues.
  Lui-même, les Gardiens et un autre porte-étendard ne sont jamais protégés ; les auras ne se
  cumulent pas. Il suit la mêlée à 170-200 u du héros et recule (lentement) quand on le serre.
- **Contre-jeu.** Le tuer d'abord : il se tient derrière la mêlée, il faut la traverser (dash). Ou
  entraîner le combat hors de son aura (il marche à 105 u/s). L'étourdir fait tomber l'étendard :
  la protection cesse le temps de l'étourdissement.
- **Nombres.** PV 46 : entre l'Archer (20) et le Bélier (52). Vitesse 105 : sous le Nécromancien (118).
  Protection ×0,6 : plus forte que l'élite blindé (×0,8), mais elle tombe avec lui. Rayon 260 : un
  ennemi au contact du héros reste couvert quand le porteur se tient à 200 u. Or 3-5.
- **Mesuré.** Les bots le visent en priorité : il vit 7 s. Sans dash, 6 s.

**Description visuelle.** Porteur rond (rayon 17), ocre (`#b5872f`), yeux sombres ; derrière
l'épaule une HAMPE haute (presque 3 rayons) et un étendard cramoisi (`#e0283c`) à deux pointes qui
flotte. Son AURA est déjà dans l'état : `e.tele` = `{shape: "circle", r: 260, harmless: true}`, donc
dessinée comme une alerte INOFFENSIVE (violet), jamais en rouge. Chaque ennemi couvert porte une
marque : `D6FoeDefense.ward_of(game, ennemi)` rend le porteur qui le protège (ou null) — chevron
violet au-dessus de lui, ou fil ténu vers l'étendard. Étourdi (`e.stun > 0`) : `e.tele` est nul,
l'étendard est couché et terne, les marques disparaissent.

### Ce que les bots ont appris (`tools/bots.mjs`, sans tricher : ils ne lisent que ce qui se voit)

- **Pavois vu de face** (`e.face`, largeur dessinée, levé ou non) : la cible perd sa priorité ; visée,
  le bot ne frappe pas (les coups rebondiraient), il la contourne au plus près, et la traverse d'un
  dash s'il lui reste deux charges (une gardée pour esquiver).
- **Étendard** : cible prioritaire. **Traqueur et pavois en récupération** : fenêtre de punition.
- Le cercle du traqueur est une zone ordinaire, le coup de pavois un secteur « de zone » (celui du
  fouet de Minos) : déjà lus. Un traqueur disparu n'est pas vu (comme une apparition en attente).

### Oracles (2026-10-01)

`node --test tests/*.test.mjs` : 327 tests, **326 verts, 1 rouge** — un test EXISTANT, non modifié :
`disposition chicane : pondérée dans les thèmes…` (`tests/v2_contenu.test.mjs`). Il exige que le bot
tue au moins un ennemi en 20 s dans la première salle « chicane » trouvée (graine 1, étage 291,
équipement de départ, ennemis à 500-1 300 PV). Ajouter trois lignes au bestiaire change les tirages
de vagues : cette salle tirait dix ennemis dont quatre Possédés (qui se tuent entre eux : 3 morts en
20 s) ; elle en tire maintenant huit dont un Nécromancien — aucun des trois nouveaux — et le premier
tombe à 22,5 s. Fenêtre figée sur un tirage : **à Pierre** (surface protégée).
Solvabilité : PASS (section 1 battue à 95 %, dash ×5,95). Classes : PASS (6 kits, 95 à 100 %).

Effet de bord de ces mêmes tirages : trois des cinq parties notées `autel_*` ne rencontraient plus
leur autel ; leurs graines ont été rechoisies (`tools/traces.mjs`), les cinq autels sont de nouveau joués.

### Incertain (à juger en main)

- **Le pavois punit durement qui martèle** : première cause de blessure du bot qui tape sans lire.
  C'est voulu (pilier 1), mais à l'étage 10 un joueur neuf peut le vivre comme un mur. Leviers :
  `guardArc`, `recover` (fenêtre où le pavois est écarté), `turnRate`.
- **Contourner le pavois à pied marche presque aussi bien que le dash** pour un bot précis (il pivote
  à 115°/s). Au pouce, tourner serré autour d'un ennemi est plus dur : à vérifier sur téléphone.
- **Le traqueur ne touche presque jamais le bot habile** (50 dégâts en 121 rencontres) : le bot voit
  derrière lui, un joueur regarde devant. Le rayon (82) et le télégraphe (0,55 s) sont à régler à la main.
- **Le traqueur disparu emporte son jeton de mêlée** 1,4 s : avec deux traqueurs, les autres ennemis
  de mêlée attendent. Rythme à juger.
- **L'aura (260 u) est un grand cercle violet permanent** : lisible, mais peut-être envahissant avec
  deux porteurs. Et ×0,6 allonge chaque combat tant qu'on ne va pas le chercher.
- **Défaut hérité, non corrigé** : étourdir un ennemi pendant sa récupération lui fait sauter sa
  recharge — vrai aussi pour le pavois et le traqueur.
- **Affichage Godot** : les trois archétypes ne sont pas encore dessinés (lot des créatures). Le jeu
  ne plante pas (captures aux étages 14, 15 et 16 : aucune erreur de script) ; d'ici là, un traqueur
  disparu peut rester montré à son ancienne place (l'affichage ne lit pas encore `e.hidden`).
