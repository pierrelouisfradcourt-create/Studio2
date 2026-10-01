extends "res://tests/regles.gd"
## Point d'entrée conventionnel des tests du jeu (l'oracle Godot du studio attend tests/run_tests.gd).
##   <godot> --headless --path GAMES/dungeon_666_godot --script res://tests/run_tests.gd [-- nom_de_fichier …]
## Sortie 0 = tout vert, 1 = au moins un rouge (ou aucun test trouvé).
##
## C'est le lanceur des tests de RÈGLES (tests/regles.gd, tests/regles/*.gd), en un seul processus
## (environ 5 minutes). L'oracle complet et rapide du jeu reste `bash outils/verifier.sh` : il
## ajoute les données, les parties de référence et les vues, en parallèle.
##
## Jusqu'au 2026-10-01, ce fichier comparait la simulation Godot à la version web. La version web
## est figée et Godot est seul maître de ses règles : cette comparaison n'a plus d'objet
## (parite/LISEZ_MOI.md). Remplacé sur décision de Pierre le 2026-10-02.
