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
| `references/` | 70 parties enregistrées par Godot et rejouées : la simulation n'a pas changé sans qu'on le veuille. |
| `jeu/` | Ce qui se voit, s'entend, se touche (contrat : `jeu/ARCHITECTURE.md`), avec ses tests headless. |
| `outils/` | `verifier.sh` (l'oracle), `jouabilite.sh` (bots : solvabilité, classes), `donnees.gd` (écriture des données), `capture.gd`. |
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
3. **règles** — `tests/regles/*.gd` : 333 tests, dont les références croisées des données
   (`donnees.gd`) ;
4. **références** — les 70 parties de `references/parties/` sont rejouées, 10 729 points de
   contrôle comparés ;
5. **vues** — les tests headless de `jeu/` (entrées, écrans, Ville, son, effets, thème) ;
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
bash references/enregistrer.sh          # 70 parties, ~20 s ; sans changement : mêmes fichiers au bit près
bash outils/verifier.sh
```

Chercher où une partie a changé : `"$G" --headless --path . --script res://references/verifier.gd
-- detail <partie>` affiche l'empreinte complète de chaque image entre le dernier point de
contrôle identique et le premier différent ; la même commande sur le code d'avant donne l'autre
moitié de la comparaison.

## Régler un nombre

Tout est dans `data/`, un fichier par domaine : `heros`, `classes` (armes, compétences, gadgets,
Supers), `bestiaire`, `gardiens`, `salles`, `etages` (sections, Cercles), `benedictions`, `butin`,
`autels`, `ville`, `labo`. Chaque nombre n'y est écrit **qu'une fois** ; une clé en minuscules est
un bloc de réglages, une clé en MAJUSCULES une table, `_note` dit à quoi sert le fichier.

1. Modifier le nombre dans le fichier (JSON ordinaire : `0.42`, pas de forme codée).
2. Le validateur dit tout de suite si la donnée tient debout :
   `"$G" --headless --path . --script res://addons/studio_kit/outils/valider.gd` — il nomme le
   chemin exact d'une faute (`$.enemies.imp.windup : 0.3 < minimum 0.4`).
3. `bash outils/verifier.sh` : les tests de règles disent ce que le nombre casse, les références
   rougissent (le jeu a changé). Si c'est voulu : réenregistrer et le dire, comme pour une règle.
4. `bash outils/verifier.sh --jouabilite` si le nombre touche l'équilibre (PV, dégâts, télégraphes).

Ajouter un champ ou un identifiant : le déclarer aussi dans `data/schemas/<domaine>.json` ; les
identifiants qui se répondent d'un fichier à l'autre sont gardés par `tests/regles/donnees.gd`.
Après une édition à la main, `"$G" --headless --path . --script res://outils/donnees.gd --
reecrire` remet les fichiers à la mise en forme du studio (aucune valeur ne change).
