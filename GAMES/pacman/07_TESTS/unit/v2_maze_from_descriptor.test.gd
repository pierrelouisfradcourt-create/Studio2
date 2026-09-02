# v2_maze_from_descriptor.test.gd — ligne maze.from_descriptor, capacite F95.
# La topologie est construite par LECTURE du descripteur RECU, et non d'un plan litteral
# compile dans le module. Premiere des quatre causes mesurees de la baseline V1.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# Le module de topologie ne porte AUCUN plan litteral : le texte du fichier ne
	# contient plus de ligne de labyrinthe. C'est un comptage, pas une intention.
	var f := FileAccess.open("res://05_SYSTEMS/maze/maze.gd", FileAccess.READ)
	h.ok(f != null, "maze.from_descriptor: le module est lisible")
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("const PLAN"), false, "maze.from_descriptor: aucun plan constant")
	h.eq(texte.contains("const DEPART_PACMAN"), false, "maze.from_descriptor: aucun depart constant")
	h.eq(texte.contains("const MAISON_CENTRE"), false, "maze.from_descriptor: aucune maison constante")
	h.eq(texte.contains("############"), false, "maze.from_descriptor: aucune ligne de labyrinthe")

	# La carte est CONSTRUITE depuis un descripteur remis en argument.
	var mini: Dictionary = {
		"id": "mini", "nom": "Mini", "plan": ["#####", "#.T.#", "#####"],
		"depart_pacman": [1, 1], "depart_direction": [1, 0],
		"maison_centre": [2, 1], "sortie_maison": [1, 1],
		"places_maison": [[1, 1], [1, 1], [1, 1], [1, 1]],
	}
	var carte = MazeClass.depuis_descripteur(mini)
	h.eq(carte.LARGEUR, 5, "maze.from_descriptor: largeur du descripteur recu")
	h.eq(carte.HAUTEUR, 3, "maze.from_descriptor: hauteur du descripteur recu")
	h.eq(carte.type_case(Vector2i(0, 0)), MazeClass.Type.MUR, "maze.from_descriptor: mur lu")
	h.eq(carte.type_case(Vector2i(1, 1)), MazeClass.Type.COULOIR, "maze.from_descriptor: couloir lu")
	h.eq(carte.type_case(Vector2i(2, 1)), MazeClass.Type.TUNNEL, "maze.from_descriptor: tunnel lu")
	h.eq(carte.praticable(Vector2i(1, 1)), true, "maze.from_descriptor: couloir praticable")
	h.eq(carte.praticable(Vector2i(0, 0)), false, "maze.from_descriptor: mur impraticable")
	h.eq(carte.ID, "mini", "maze.from_descriptor: identifiant porte par la carte")

	# Deux cartes construites depuis deux descripteurs sont DEUX cartes, jamais une seule.
	var autre = MazeClass.depuis_descripteur(ContentV2.descripteur(1))
	h.eq(Maze.meme_carte(autre), false, "maze.from_descriptor: deux cartes ne se confondent pas")
	h.eq(Maze.meme_carte(MazeClass.depuis_descripteur(ContentV2.descripteur(0))), true,
		"maze.from_descriptor: deux lectures du meme descripteur donnent la meme carte")
	h.eq(Maze.meme_carte(null), false, "maze.from_descriptor: l'absence de carte n'est pas une carte")
