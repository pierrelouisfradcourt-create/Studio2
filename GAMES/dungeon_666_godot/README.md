# Dungeon 666 — version Godot

`statut_artefact : PROPOSED` · `claim_verdict : NO_CLAIM_ALLOWED`. Demande de Pierre du
2026-10-01 : « une version plus propre sur Godot », puis le même jour : « ne t'embête plus avec
la version web, continue le dev en local ».

**Godot est la source des règles et des nombres.** Ce projet est né comme le portage au bit près
du prototype web (`GAMES/dungeon_666/`, figé le 2026-10-01, archive jouable et origine des
règles). Il ne se compare plus à lui : il se garde lui-même. L'histoire du passage et ses preuves :
`parite/LISEZ_MOI.md`.

| Dossier | Rôle |
|---|---|
| `sim/` | La simulation : les règles. Ne connaît pas Godot (ni nœud, ni scène). Conventions : `PORTAGE.md`. |
| `data/` | Tous les nombres et tables du jeu, en JSON ordinaire, un fichier par domaine. `validation.json` + `schemas/` : leur garde. |
| `tests/regles/` | Les tests de règles (une règle, un test), lancés par `tests/regles.gd`. Outils : `tests/harnais.gd`. |
| `references/` | 100 parties enregistrées par Godot et rejouées : la simulation n'a pas changé sans qu'on le veuille. |
| `jeu/` | Ce qui se voit, s'entend, se touche (contrat : `jeu/ARCHITECTURE.md`), avec ses tests headless. |
| `outils/` | `verifier.sh` (l'oracle), `jouabilite.sh` (bots : solvabilité, classes), `arbre.sh` (mesure : puissance de l'arbre, valeur de chaque compétence neuve), `donnees.gd` (écriture des données), `capture.gd`. |
| `parite/` | Héritage : les outils de comparaison au web, plus lancés (`comparer.gd` sert encore). |
| `addons/studio_kit/` | Le socle du studio (sauvegarde, thème, réglages, validation des données). |

## Vérifier

```
bash outils/verifier.sh                 # environ 2 minutes sur 8 cœurs ; sortie 0 = VERT
bash outils/verifier.sh --jouabilite    # … puis les bots : solvabilité et classes (~5 minutes de plus)
```

1. **import** — Godot enregistre ses classes ;
2. **données** — chaque fichier de `data/` contre son schéma (types, bornes, un télégraphe
   d'ennemi d'au moins 0,4 s), et se réécrit sans rien perdre ;
3. **règles** — `tests/regles/*.gd` : 652 tests, dont les références croisées des données
   (`donnees.gd`) ;
4. **références** — les 100 parties de `references/parties/` sont rejouées, point de contrôle
   par point de contrôle (un toutes les 30 images) ;
5. **vues** — les tests headless de `jeu/` (entrées, écrans, Ville, son, effets, thème), et le
   **parcours** (`jeu/essai/test_parcours.gd`) : le vrai jeu assemblé, toutes ses vues montées,
   joué de bout en bout par le bot — titre, Ville, descentes des trois classes, menus (chambre
   forte et fontaine comprises), pause, le Gardien de l'étage 18 battu, le portail de la Ville
   et la reprise depuis son point, la dernière section jusqu'à l'écran de victoire, morts,
   abandons, profil relu du disque d'essai, aucun nœud qui s'accumule ;
6. **jouabilité** (sur demande) — un bot bat la section 1, le dash compte, chaque classe se joue.

Toute « SCRIPT ERROR » est un rouge. Ce que l'oracle prouve : les règles font ce que leurs tests
disent, les données sont cohérentes, la simulation est celle qui a été enregistrée. Ce qu'il ne
prouve pas : le rendu, les commandes en main, le son, le plaisir de jeu — à juger à l'écran.

Une étape seule (`G` = l'exécutable Godot en console) :

```
"$G" --headless --path . --script res://addons/studio_kit/outils/valider.gd      # données : schémas
"$G" --headless --path . --script res://tests/regles.gd -- donnees logic         # deux fichiers de tests
"$G" --headless --path . --script res://references/verifier.gd -- kit_lame       # une partie de référence
```

## Les commandes (combat V3, étape 1)

Demande et plan : `design/COMBAT_V3.md`. Une entrée d'un pas (`D6Game.empty_input`) porte le
déplacement, la visée, l'attaque (tenue et front), le dash, et **trois emplacements d'action**
(`skill1Pressed`…`skill3Pressed`, chacun avec sa visée). Chaque emplacement porte une compétence
(sa recharge) ou un gadget (ses charges) de la classe : `profil.loadout.slots`, choisi au Grimoire
(`D6Profile.select_slot`), lu en partie par `game.kit.slots` et, pour l'affichage, par
`D6Loadout.slot_view`. **L'ultime n'a pas de bouton** : jauge pleine, garder l'attaque appuyée
`super.holdTime` (0,4 s, `data/classes.json`) le lance ; relâcher annule. Seul un appui COMMENCÉ
jauge pleine l'arme : tenir l'attaque depuis avant enchaîne le combo, sans ultime. Clavier : clic gauche
attaque, Espace dash, clic droit / E / F les emplacements 1 / 2 / 3. Manette : X, A, B / Y / RB.

## Le déplacement de classe et le terrain à franchir (combat V3, étape 1 bis)

Le bouton du dash joue le DÉPLACEMENT de la classe (`data/classes.json` : `move` de la classe,
table `moves`) : **dash** du Revenant, **saut** du Bourreau (invulnérable en l'air, choc qui
repousse à l'atterrissage, une charge), **roulade** de la Chasseresse (la plus longue ; son
prochain tir est prêt en sortie). Les trois partagent l'état `dash` du héros et le bloc de réglage
actif `tuning.dash` : tout ce qui parle du dash (charges, recharge, esquive parfaite, frappe de
dash, bénédictions) vaut pour les trois. L'affichage lit `D6Player.move_view(game)`.

Les salles peuvent porter du TERRAIN BAS (`data/salles.json`, table `TERRAINS` ; en partie :
`room.low`) : **rivières** et **obstacles bas**. On n'y marche pas ; les tirs et la vue passent
au-dessus ; le déplacement de classe les franchit si l'arrivée est sur la terre ferme, sinon il
est raccourci au bord (jamais de chute). Les ennemis qui marchent contournent par les gués ;
chaque disposition reste finissable à pied. Le terrain entre à l'étage `room.terrainFrom` (5).
Règles et choix : `design/COMBAT_V3.md`, « Étape 1 bis » ; gardes : `tests/regles/v3_terrain.gd`.
Juger à l'écran : `jeu/essai/terrain.tscn` (banc ; mode d'emploi en tête de `jeu/essai/terrain.gd`).

## Les ultimes de classe (combat V3, étape 2)

Un TYPE d'ultime par classe (`data/classes.json` : `super` de la classe, table `supers`), lancé comme
avant (jauge pleine, appui commencé jauge pleine, maintien `holdTime`) ; il commence par un geste
invulnérable (`duration`). Façade : `sim/kit_supers.gd` (`D6KitSupers`) ; une règle par fichier :

- **Revenant — Forme du Damné** (`sim/ult_forme.gd`, sorte `forme`) : transformation de `formTime`
  secondes. Les griffes remplacent l'arme équipée, trois actions de forme remplacent les trois
  emplacements (`D6Loadout.slot_view` les rend : le HUD n'a rien à savoir), la jauge se vide et sert
  de minuterie. À la fin, le kit d'origine revient tel qu'il était (ses recharges n'ont pas couru).
- **Bourreau — Sentence capitale** (`sim/ult_magie.gd`, sorte `magie`) : lame levée, temps figé, puis
  un fracas sur TOUS les ennemis présents ; exécution sous `executeBelow`, jamais un Gardien (`bossCap`).
- **Chasseresse — Meute des Limbes** (`sim/ult_meute.gd`, sorte `meute`) : `count` limiers alliés dans
  `game.allies` (jamais dans `game.enemies`) ; ils mordent ce qu'elle désigne, attirent les ennemis
  de mêlée, arrêtent les tirs, contournent le terrain bas par les gués.

Tant qu'un ultime AGIT (`D6KitSupers.acting`), il ne se relance pas et rien ne remplit la jauge.
Mort, changement de salle, reprise : tout est remis en ordre (`D6KitSupers.reset`). L'affichage lit
`D6Player.ultimate_view(game)`. Les trois anciens Supers (Colère, Sentence, Nuée) restent dans la
table, marqués `reserve` : leur code joue toujours, ils ne sont l'ultime d'aucune classe. Règles,
choix et nombres : `design/COMBAT_V3.md`, « Étape 2 » ; gardes : `tests/regles/v3_ultimes.gd`.
Juger à l'écran : `jeu/essai/ultimes.tscn` (mode d'emploi en tête de `jeu/essai/ultimes.gd`).

## Les compétences neuves (combat V3, étape 4)

Trois compétences neuves par classe (huit en tout par classe, pour trois emplacements), chacune une
entrée de `data/classes.json` (`skills` : à recharge ; `gadgets` : à charges) et un nœud de
`data/arbres.json`. Façade : `sim/kit_neuves.gd` (chargée par `preload`, sans `class_name`) ; une
famille par fichier :

- **Revenant** (`sim/neuves_revenant.gd`) : `sillage` (braises semées par ses pas et son dash),
  `sceau` (Stigmate : marque qui explose à la mort du marqué), `riposte` (Contre-taille : taillade,
  puis garde qui pare et rend le premier coup reçu).
- **Bourreau** (`sim/neuves_bourreau.gd`) : `faille` (fissure en ligne), `hachette` (hache lancée qui
  revient), `garde` (Garde de fer : coups de face réduits, attaquant repoussé).
- **Chasseresse** (`sim/neuves_chasseresse.gd`) : `proie` (marque : dégâts subis en plus, visée et
  limiers), `leurre` (allié posé dans `game.allies`, qui attire la mêlée), `trait` (Trait de Nemrod :
  il se BANDE d'un appui, part seul à pleine charge, ou tout de suite au second appui).

Elles passent par les chemins communs (état `cast` et recharge, charges, tirs et zones de la salle,
alliés) : l'entrée d'un pas n'a pas changé, et tout ce qui parle « des compétences » (bénédictions,
objets, procs) s'y applique. Un leurre est un allié, pas un ultime : il ne tient pas la jauge
(`D6KitSupers.acting` ne compte que les limiers). L'affichage lit `D6Loadout.slot_view` (forme
inchangée) et, en plus, `D6Loadout.slot_state(game, i)` (charge du Trait, effet qui dure). La Chaîne
et la Bombe ont une version par classe (rang 1 commun, rangs et une amélioration sur deux propres).
Règles, tableaux et nombres : `design/COMBAT_V3.md`, « Étape 4 » ; gardes :
`tests/regles/v3_competences.gd` ; mesure : `bash outils/arbre.sh` (`_dev/rapports/arbre.md`) ;
juger à l'écran : `jeu/essai/competences.tscn` (mode d'emploi en tête de `jeu/essai/competences.gd`).

## Changer une règle

1. Modifier la règle dans `sim/` (conventions : `PORTAGE.md`) ou son nombre dans `data/`.
2. Ajouter son test dans `tests/regles/`, ou adapter celui qui la décrit (un test existant ne se
   modifie qu'avec l'accord de Pierre : règle du studio).
3. `bash outils/verifier.sh`. L'étape **références** rougit : c'est attendu, la simulation a changé.
   Si elle rougit ailleurs que là où la règle joue, c'est une régression — on corrige, on ne
   réenregistre pas.
4. Le changement est bien celui voulu : réenregistrer, relancer, et **le dire dans le commit**
   (« références réenregistrées : <la règle changée> »).

```
bash references/enregistrer.sh          # 100 parties, ~30 s ; sans changement : mêmes fichiers au bit près
bash outils/verifier.sh
```

Chercher où une partie a changé : `"$G" --headless --path . --script res://references/verifier.gd
-- detail <partie>` affiche l'empreinte complète de chaque image entre le dernier point de
contrôle identique et le premier différent ; la même commande sur le code d'avant donne l'autre
moitié de la comparaison.

## Régler un nombre

Tout est dans `data/`, un fichier par domaine : `heros`, `classes` (armes, compétences, gadgets,
ultimes), `bestiaire`, `gardiens`, `salles`, `etages` (sections, Cercles), `benedictions`, `butin`,
`autels`, `ville`, `labo`, `arbres` (l'arbre de compétences). Chaque nombre n'y est écrit **qu'une fois** ; une clé en minuscules est
un bloc de réglages, une clé en MAJUSCULES une table, `_note` dit à quoi sert le fichier. Le libellé
d'une option d'autel reprend ses nombres par `{champ}` (`"Boire — rend {pct} % des PV"`, `"pct": 40`) :
il ne s'écrit jamais en chiffres. Ce qui reste en constantes dans `sim/` est technique (tolérances,
garde-fous, marges de contact) : liste et raisons dans `DEFAUTS.md`, troisième lot.

1. Modifier le nombre dans le fichier (JSON ordinaire : `0.42`, pas de forme codée).
2. Le validateur dit tout de suite si la donnée tient debout :
   `"$G" --headless --path . --script res://addons/studio_kit/outils/valider.gd` — il nomme le
   chemin exact d'une faute (`$.enemies.imp.windup : 0.3 < minimum 0.4`).
3. `bash outils/verifier.sh` : les tests de règles disent ce que le nombre casse, les références
   rougissent (le jeu a changé). Si c'est voulu : réenregistrer et le dire, comme pour une règle.
4. `bash outils/verifier.sh --jouabilite` si le nombre touche l'équilibre (PV, dégâts, télégraphes).

**L'arbre de compétences** (`data/arbres.json`, mode d'emploi dans sa `_note`) : l'expérience par
ennemi et son plafond de profondeur (`xp`), la courbe des niveaux (`curve`), le niveau maximum, les
points, les seuils des étages (`tiers`), le rang du choix exclusif (`choiceRank`), le prix de la
respécialisation (`respec`), puis par classe la liste des nœuds. Le RANG 1 d'une compétence, ce sont
ses nombres de `classes.json` ; `ranks` donne chaque nombre aux rangs 2 à 5 ; une amélioration
exclusive remplace des nombres (`set`) et son texte les cite par `{champ}` ; un passif cite son total
par `{v}`. Ajouter une compétence : une entrée dans `classes.json` (et dans la liste de sa classe), un
nœud ici — aucun code si elle réutilise une sorte (`kind`) existante. `tests/regles/donnees.gd` garde
les renvois, les textes et le budget de points ; `outils/arbre.gd` (`bash outils/arbre.sh`) mesure
arbre vide contre arbre plein, et la valeur de chaque compétence neuve (`_dev/rapports/arbre.md`).
Une compétence d'une sorte (`kind`) NEUVE demande aussi sa règle (`sim/kit_neuves.gd`), son dessin
(`jeu/monde/`, `jeu/effets/`), son pictogramme, et ses champs dans `data/schemas/classes.json` ; un
champ de rang hors de ceux que `tests/regles/v3_arbre.gd` sait vérifier en jeu (dégâts, recharge,
charges, rayon d'une compétence à charges, portée, vulnérabilité, étourdissement, brûlure, durée)
fera rougir ce test : c'est voulu.

Ajouter un champ ou un identifiant : le déclarer aussi dans `data/schemas/<domaine>.json` ; les
identifiants qui se répondent d'un fichier à l'autre sont gardés par `tests/regles/donnees.gd`.
Après une édition à la main, `"$G" --headless --path . --script res://outils/donnees.gd --
reecrire` remet les fichiers à la mise en forme du studio (aucune valeur ne change).
