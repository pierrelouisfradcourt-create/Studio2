# maze_neighbours_tunnel.gd — ligne maze.neighbours, capacite F7.
# L'enumeration des voisins est la MEME pour toutes les entites : un fantome en
# poursuite entre dans le couloir de tunnel et en ressort par l'autre extremite.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")


func run(h) -> void:
	# Ordre FIXE et declare : haut, gauche, bas, droite.
	h.eq(Maze.DIRECTIONS, [Maze.HAUT, Maze.GAUCHE, Maze.BAS, Maze.DROITE],
		"maze.neighbours: ordre de voisins fixe et declare")

	# L'enumeration ne prend AUCUN argument d'entite : joueur et fantomes lisent la meme.
	var carrefour := Vector2i(6, 23)
	h.eq(Maze.voisins_praticables(carrefour).size(), 4, "maze.neighbours: carrefour a 4 sorties")
	h.eq(Maze.voisins_praticables(carrefour)[0], Vector2i(6, 22), "maze.neighbours: premier voisin en haut")
	h.eq(Maze.voisins_praticables(carrefour)[1], Vector2i(5, 23), "maze.neighbours: deuxieme voisin a gauche")
	h.eq(Maze.voisins_praticables(carrefour)[2], Vector2i(6, 24), "maze.neighbours: troisieme voisin en bas")
	h.eq(Maze.voisins_praticables(carrefour)[3], Vector2i(7, 23), "maze.neighbours: quatrieme voisin a droite")

	# Un mur n'a aucun voisin praticable emis depuis lui-meme en tant que case fermee.
	h.eq(Maze.praticable(Vector2i(0, 0)), false, "maze.neighbours: la case (0,0) est un mur")

	# Aux extremites du tunnel, l'enumeration DEBORDE par bouclage : la case a gauche de
	# (0, 17) est (27, 17), pas un mur.
	var gauche_tunnel: Vector2i = Vector2i(0, Maze.LIGNE_TUNNEL)
	h.eq(Maze.type_case(gauche_tunnel), Maze.Type.TUNNEL, "maze.neighbours: bord gauche est un tunnel")
	h.ok(Maze.voisins_praticables(gauche_tunnel).has(Vector2i(Maze.LARGEUR - 1, Maze.LIGNE_TUNNEL)),
		"maze.neighbours: le voisin gauche du bord est l'autre extremite")

	# UN FANTOME en poursuite traverse reellement le tunnel : entree par une extremite,
	# sortie par l'autre. Fixture : Pac-Man reste dans le couloir de tunnel a droite, le
	# fantome rouge arrive par la gauche.
	var s = State.initial(Maze, 1)
	# Pac-Man RESTE dans le couloir de tunnel : sa direction courante bute contre un mur,
	# donc il ne se deplace pas et n'interfere pas avec la traversee mesuree.
	s.pac = Vector2i(24, Maze.LIGNE_TUNNEL)
	s.pac_dir = Maze.HAUT
	s.pac_attente = Maze.AUCUNE
	h.eq(Maze.praticable(Vector2i(24, Maze.LIGNE_TUNNEL - 1)), false,
		"maze.neighbours: fixture — Pac-Man est bute contre un mur")
	s.fantomes[Targeting.ROUGE] = Vector2i(3, Maze.LIGNE_TUNNEL)
	s.dirs_fantomes[Targeting.ROUGE] = Maze.GAUCHE
	s.dehors[Targeting.ROUGE] = true
	for i in range(1, 4):
		s.dehors[i] = false
		s.sorties_maison[i] = 9999

	# Fenetre DECLAREE : 6 ticks. Au-dela, le fantome atteindrait Pac-Man et le contact
	# arreterait la traversee — on mesurerait alors la collision, pas l'enumeration.
	var vu_a_gauche: bool = false
	var vu_a_droite: bool = false
	for _t in range(6):
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		var g: Vector2i = s.fantomes[Targeting.ROUGE]
		if g.y == Maze.LIGNE_TUNNEL and g.x <= 2:
			vu_a_gauche = true
		if g.y == Maze.LIGNE_TUNNEL and g.x >= 25 and vu_a_gauche:
			vu_a_droite = true
	h.eq(vu_a_gauche, true, "maze.neighbours: le fantome atteint l'extremite gauche du tunnel")
	h.eq(vu_a_droite, true, "maze.neighbours: le fantome ressort par l'extremite droite")

	# Le bouclage ne change jamais la ligne : le fantome est reste sur la ligne du tunnel.
	h.eq(s.fantomes[Targeting.ROUGE].y, Maze.LIGNE_TUNNEL, "maze.neighbours: la ligne reste inchangee")
