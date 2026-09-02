# v2_maze_derived_dimensions.test.gd — ligne maze.derived_dimensions, capacite F96.
# Les grandeurs autrefois figees en constantes sont DERIVEES du descripteur : une carte
# de dimensions differentes ne demande AUCUNE modification de la logique.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
const Schema = preload("res://05_SYSTEMS/map_schema/map_schema.gd")

var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# Carte nominale : les valeurs derivees egalent celles que V1 declarait en dur.
	h.eq(Maze.LARGEUR, 28, "maze.derived: largeur derivee")
	h.eq(Maze.HAUTEUR, 36, "maze.derived: hauteur derivee")
	h.eq(Maze.LIGNE_TUNNEL, 17, "maze.derived: ligne de bouclage derivee du plan")
	h.eq(Maze.LABY_PREMIERE_LIGNE, 3, "maze.derived: premiere ligne jouable derivee")
	h.eq(Maze.LABY_DERNIERE_LIGNE, 33, "maze.derived: derniere ligne jouable derivee")

	# Seconde carte : les MEMES derivations donnent d'AUTRES valeurs, sans code modifie.
	h.eq(Alt.LARGEUR, 21, "maze.derived: largeur de la seconde carte")
	h.eq(Alt.HAUTEUR, 24, "maze.derived: hauteur de la seconde carte")
	h.eq(Alt.LIGNE_TUNNEL, 11, "maze.derived: ligne de bouclage de la seconde carte")
	h.eq(Alt.LABY_PREMIERE_LIGNE, 2, "maze.derived: premiere ligne jouable de la seconde carte")
	h.eq(Alt.LABY_DERNIERE_LIGNE, 21, "maze.derived: derniere ligne jouable de la seconde carte")

	# Les COINS suivent les dimensions : ils ne sont pas declares.
	h.eq(Maze.COINS[0], Vector2i(27, 0), "maze.derived: coin de la carte nominale")
	h.eq(Alt.COINS[0], Vector2i(20, 0), "maze.derived: coin de la seconde carte")
	h.ok(Maze.COINS != Alt.COINS, "maze.derived: les coins different avec les dimensions")
	h.eq(Maze.nb_cases(), 28 * 36, "maze.derived: nombre de cases derive")
	h.eq(Alt.nb_cases(), 21 * 24, "maze.derived: nombre de cases de la seconde carte")

	# FRONTIERES : assertees AUX frontieres, jamais par un intervalle confortable.
	h.eq(Maze.dans_grille(Vector2i(27, 35)), true, "maze.derived: derniere case dans la grille")
	h.eq(Maze.dans_grille(Vector2i(28, 35)), false, "maze.derived: une colonne au-dela est hors grille")
	h.eq(Maze.dans_labyrinthe(Vector2i(0, 3)), true, "maze.derived: premiere ligne jouable incluse")
	h.eq(Maze.dans_labyrinthe(Vector2i(0, 2)), false, "maze.derived: la ligne au-dessus est exclue")
	h.eq(Maze.dans_labyrinthe(Vector2i(0, 33)), true, "maze.derived: derniere ligne jouable incluse")
	h.eq(Maze.dans_labyrinthe(Vector2i(0, 34)), false, "maze.derived: la ligne en dessous est exclue")

	# Une carte SANS tunnel rend la valeur d'absence declaree, jamais un 0 trompeur.
	var sans_tunnel = MazeClass.depuis_descripteur({
		"id": "x", "nom": "x", "plan": ["###", "#.#", "###"],
		"depart_pacman": [1, 1], "depart_direction": [1, 0],
		"maison_centre": [1, 1], "sortie_maison": [1, 1], "places_maison": [],
	})
	h.eq(sans_tunnel.LIGNE_TUNNEL, Schema.LIGNE_ABSENTE, "maze.derived: absence de tunnel nommee")
