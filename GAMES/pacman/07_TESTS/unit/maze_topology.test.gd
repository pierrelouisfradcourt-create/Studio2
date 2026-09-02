# maze_topology.test.gd — ligne maze.topology, capacite F5.
# Les dimensions exposees valent EXACTEMENT 28 x 36 et le type de chaque case est
# lisible depuis la description unique de la carte.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const P = preload("res://05_SYSTEMS/params/params.gd")


func run(h) -> void:
	h.eq(Maze.LARGEUR, 28, "maze.topology: largeur exposee")
	h.eq(Maze.HAUTEUR, 36, "maze.topology: hauteur exposee")
	h.eq(Maze.PLAN.size(), 36, "maze.topology: le plan porte 36 lignes")

	var lignes_mal_dimensionnees: int = 0
	for y in range(Maze.HAUTEUR):
		if Maze.PLAN[y].length() != Maze.LARGEUR:
			lignes_mal_dimensionnees += 1
	h.eq(lignes_mal_dimensionnees, 0, "maze.topology: toute ligne fait 28 caracteres")

	# Le type de CHAQUE case appartient au vocabulaire ferme de quatre valeurs.
	var valides: Array = [Maze.Type.MUR, Maze.Type.COULOIR, Maze.Type.MAISON, Maze.Type.TUNNEL]
	var hors_vocabulaire: int = 0
	for y in range(Maze.HAUTEUR):
		for x in range(Maze.LARGEUR):
			if not (Maze.type_case(Vector2i(x, y)) in valides):
				hors_vocabulaire += 1
	h.eq(hors_vocabulaire, 0, "maze.topology: aucun type hors du vocabulaire ferme")

	# Les quatre types sont REELLEMENT presents : une carte qui n'aurait que des murs
	# satisferait le vocabulaire sans decrire un labyrinthe.
	var comptes: Dictionary = {Maze.Type.MUR: 0, Maze.Type.COULOIR: 0, Maze.Type.MAISON: 0, Maze.Type.TUNNEL: 0}
	for y in range(Maze.HAUTEUR):
		for x in range(Maze.LARGEUR):
			comptes[Maze.type_case(Vector2i(x, y))] += 1
	h.gt(comptes[Maze.Type.MUR], 0, "maze.topology: des murs existent")
	h.gt(comptes[Maze.Type.COULOIR], 0, "maze.topology: des couloirs existent")
	h.eq(comptes[Maze.Type.MAISON], 20, "maze.topology: la maison compte 20 cases (18 + 2 portes)")
	h.eq(comptes[Maze.Type.TUNNEL], 12, "maze.topology: deux tunnels de 6 cases")

	# Zone de labyrinthe JOUABLE : 28 x 31, distincte de la grille d'ecran 28 x 36.
	h.eq(Maze.LABY_PREMIERE_LIGNE, 3, "maze.topology: premiere ligne de labyrinthe")
	h.eq(Maze.LABY_DERNIERE_LIGNE, 33, "maze.topology: derniere ligne de labyrinthe")
	h.eq(Maze.LABY_DERNIERE_LIGNE - Maze.LABY_PREMIERE_LIGNE + 1, 31,
		"maze.topology: 31 lignes de labyrinthe jouable")
	h.eq(Maze.HAUTEUR - (Maze.LABY_DERNIERE_LIGNE - Maze.LABY_PREMIERE_LIGNE + 1), 5, "maze.topology: 5 rangees de bandeau hors labyrinthe")

	# Aucune case praticable hors de la zone de labyrinthe : le bandeau n'est jamais
	# confondu avec un couloir.
	var praticables_hors_zone: int = 0
	for y in range(Maze.HAUTEUR):
		for x in range(Maze.LARGEUR):
			var p := Vector2i(x, y)
			if Maze.praticable(p) and not Maze.dans_labyrinthe(p):
				praticables_hors_zone += 1
	h.eq(praticables_hors_zone, 0, "maze.topology: rien de praticable hors du labyrinthe")

	# --- APPARTENANCE A LA GRILLE : la FRONTIERE EXACTE, bord par bord ----------------
	# Ces assertions existent parce que le gate de mutation a montre qu'aucune ne les
	# portait : `>=` mute en `>` survivait, faute d'un test sur le bord lui-meme. Un
	# seuil dont la borne n'est jamais assertee est exactement le « >= tautologique »
	# que le charter interdit.
	h.eq(Maze.dans_grille(Vector2i(0, 0)), true, "maze.grille: le coin (0,0) est DANS la grille")
	h.eq(Maze.dans_grille(Vector2i(0, 17)), true, "maze.grille: la colonne 0 est DANS la grille")
	h.eq(Maze.dans_grille(Vector2i(13, 0)), true, "maze.grille: la ligne 0 est DANS la grille")
	h.eq(Maze.dans_grille(Vector2i(Maze.LARGEUR - 1, Maze.HAUTEUR - 1)), true,
		"maze.grille: la derniere case est DANS la grille")

	# Debordement sur UN SEUL axe a la fois : c'est le cas que `and` mute en `or` laisse
	# passer, et qu'aucune fixture n'exercait.
	h.eq(Maze.dans_grille(Vector2i(-1, 17)), false, "maze.grille: colonne -1, ligne valide -> DEHORS")
	h.eq(Maze.dans_grille(Vector2i(Maze.LARGEUR, 17)), false, "maze.grille: colonne 28, ligne valide -> DEHORS")
	h.eq(Maze.dans_grille(Vector2i(13, -1)), false, "maze.grille: ligne -1, colonne valide -> DEHORS")
	h.eq(Maze.dans_grille(Vector2i(13, Maze.HAUTEUR)), false, "maze.grille: ligne 36, colonne valide -> DEHORS")
	h.eq(Maze.dans_grille(Vector2i(-1, -1)), false, "maze.grille: les deux axes dehors -> DEHORS")

	# --- ZONE DE LABYRINTHE : les DEUX frontieres, dedans ET juste dehors -------------
	h.eq(Maze.dans_labyrinthe(Vector2i(13, Maze.LABY_PREMIERE_LIGNE)), true,
		"maze.zone: la premiere ligne de labyrinthe est DEDANS")
	h.eq(Maze.dans_labyrinthe(Vector2i(13, Maze.LABY_DERNIERE_LIGNE)), true,
		"maze.zone: la derniere ligne de labyrinthe est DEDANS")
	h.eq(Maze.dans_labyrinthe(Vector2i(13, Maze.LABY_PREMIERE_LIGNE - 1)), false,
		"maze.zone: la ligne juste au-dessus est DEHORS")
	h.eq(Maze.dans_labyrinthe(Vector2i(13, Maze.LABY_DERNIERE_LIGNE + 1)), false,
		"maze.zone: la ligne juste en dessous est DEHORS")
	# Hors grille mais dans la plage de lignes jouables : seul le premier `and` l'attrape.
	h.eq(Maze.dans_labyrinthe(Vector2i(-1, 17)), false,
		"maze.zone: hors grille reste hors labyrinthe, meme sur une ligne jouable")
	h.eq(Maze.dans_labyrinthe(Vector2i(Maze.LARGEUR, 17)), false,
		"maze.zone: hors grille a droite reste hors labyrinthe")
	# Dans la grille mais dans le bandeau : seul le test de ligne l'attrape.
	h.eq(Maze.dans_labyrinthe(Vector2i(13, 0)), false, "maze.zone: la premiere ligne d'ecran est du bandeau")
	h.eq(Maze.dans_labyrinthe(Vector2i(13, Maze.HAUTEUR - 1)), false,
		"maze.zone: la derniere ligne d'ecran est du bandeau")

	# Comptage EXACT des lignes reconnues comme jouables : 31 sur 36.
	var lignes_jouables: int = 0
	for y in range(Maze.HAUTEUR):
		if Maze.dans_labyrinthe(Vector2i(13, y)):
			lignes_jouables += 1
	h.eq(lignes_jouables, 31, "maze.zone: exactement 31 lignes reconnues comme jouables")
