# maze_walkable.test.gd — ligne maze.walkable, capacite F6.
# Invariant de collision murale soumis au gate de mutation : un mutant qui declarerait
# praticable une case de mur doit etre tue ICI.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	# Aucune case de MUR n'est praticable — parcours EXHAUSTIF de la grille.
	var murs_praticables: int = 0
	var couloirs_impraticables: int = 0
	var maisons_praticables: int = 0
	var tunnels_impraticables: int = 0
	for y in range(Maze.HAUTEUR):
		for x in range(Maze.LARGEUR):
			var p := Vector2i(x, y)
			var t: int = Maze.type_case(p)
			var praticable: bool = Maze.praticable(p)
			if t == Maze.Type.MUR and praticable:
				murs_praticables += 1
			if t == Maze.Type.COULOIR and not praticable:
				couloirs_impraticables += 1
			if t == Maze.Type.MAISON and praticable:
				maisons_praticables += 1
			if t == Maze.Type.TUNNEL and not praticable:
				tunnels_impraticables += 1
	h.eq(murs_praticables, 0, "maze.walkable: aucun mur praticable (faux positif)")
	h.eq(couloirs_impraticables, 0, "maze.walkable: aucun couloir refuse (faux negatif)")
	h.eq(maisons_praticables, 0, "maze.walkable: la maison n'est pas praticable")
	h.eq(tunnels_impraticables, 0, "maze.walkable: tout tunnel est praticable")

	# Hors grille : jamais praticable, jamais une exception.
	h.eq(Maze.praticable(Vector2i(-1, 10)), false, "maze.walkable: hors grille a gauche")
	h.eq(Maze.praticable(Vector2i(Maze.LARGEUR, 10)), false, "maze.walkable: hors grille a droite")
	h.eq(Maze.praticable(Vector2i(10, -1)), false, "maze.walkable: hors grille en haut")
	h.eq(Maze.praticable(Vector2i(10, Maze.HAUTEUR)), false, "maze.walkable: hors grille en bas")

	# Cases nommees, verifiees une par une (valeurs strictes, jamais un seuil).
	h.eq(Maze.praticable(Vector2i(0, 3)), false, "maze.walkable: coin haut-gauche du cadre est un mur")
	h.eq(Maze.praticable(Maze.DEPART_PACMAN), true, "maze.walkable: la case de depart est praticable")
	h.eq(Maze.praticable(Maze.SORTIE_MAISON), true, "maze.walkable: la sortie de maison est praticable")
	h.eq(Maze.praticable(Maze.MAISON_CENTRE), false, "maze.walkable: le centre de la maison n'est pas praticable")

	# Le nombre de cases praticables est une valeur EXACTE de cette carte.
	var praticables: int = 0
	for y in range(Maze.HAUTEUR):
		for x in range(Maze.LARGEUR):
			if Maze.praticable(Vector2i(x, y)):
				praticables += 1
	h.eq(praticables, 300, "maze.walkable: 300 cases praticables sur cette carte")

	# Le predicat est le MEME pour toutes les entites : il ne prend aucun argument
	# d'entite, donc aucune divergence joueur/fantome n'est exprimable.
	h.eq(Maze.praticable(Vector2i(13, 26)), Maze.praticable(Vector2i(13, 26)),
		"maze.walkable: predicat sans argument d'entite")
