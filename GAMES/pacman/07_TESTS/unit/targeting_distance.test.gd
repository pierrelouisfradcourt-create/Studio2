# targeting_distance.test.gd — ligne targeting.distance, capacite F14.
# La distance de grille utilisee par les quatre ciblages est UNIQUE : la bascule du
# fantome orange est assertee a une distance de 9, de 8 et de 7 sur CETTE meme mesure.
extends RefCounted

const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	# Proprietes de la mesure, valeurs exactes.
	h.eq(Targeting.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "targeting.distance: nulle sur place")
	h.eq(Targeting.distance(Vector2i(0, 0), Vector2i(3, 4)), 7, "targeting.distance: 3 + 4 = 7")
	h.eq(Targeting.distance(Vector2i(3, 4), Vector2i(0, 0)), 7, "targeting.distance: symetrique")
	h.eq(Targeting.distance(Vector2i(5, 5), Vector2i(-2, 1)), 11, "targeting.distance: coordonnees negatives")

	# La mesure du module de ciblage EST celle de la carte : une seule implementation.
	var ecarts: int = 0
	for x in range(0, 28, 3):
		for y in range(0, 36, 5):
			var p := Vector2i(x, y)
			if Targeting.distance(p, Maze.MAISON_CENTRE) != Maze.distance(p, Maze.MAISON_CENTRE):
				ecarts += 1
	h.eq(ecarts, 0, "targeting.distance: mesure unique, partagee avec la carte")

	# Seuil du fantome orange asserte EXACTEMENT a 9, 8 et 7 sur cette mesure.
	var pac := Vector2i(13, 20)
	var fantomes: Array = [Vector2i(0, 0), Vector2i(0, 0), Vector2i(0, 0), Vector2i(13, 11)]
	h.eq(Targeting.distance(fantomes[3], pac), 9, "targeting.distance: fixture a distance 9")
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ORANGE, pac, Maze.GAUCHE, fantomes), pac,
		"targeting.distance: a 9, l'orange vise Pac-Man")

	fantomes[3] = Vector2i(13, 12)
	h.eq(Targeting.distance(fantomes[3], pac), 8, "targeting.distance: fixture a distance 8")
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ORANGE, pac, Maze.GAUCHE, fantomes),
		Targeting.cible_dispersion(Maze, Targeting.ORANGE),
		"targeting.distance: a 8, l'orange vise son coin")

	fantomes[3] = Vector2i(13, 13)
	h.eq(Targeting.distance(fantomes[3], pac), 7, "targeting.distance: fixture a distance 7")
	h.eq(Targeting.cible_poursuite(Maze, Targeting.ORANGE, pac, Maze.GAUCHE, fantomes),
		Targeting.cible_dispersion(Maze, Targeting.ORANGE),
		"targeting.distance: a 7, l'orange vise son coin")

	h.eq(Targeting.SEUIL_ORANGE, 8, "targeting.distance: seuil declare a 8")
