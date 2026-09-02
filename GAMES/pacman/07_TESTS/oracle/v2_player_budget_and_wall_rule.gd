# v2_player_budget_and_wall_rule.gd — ligne player.budget_and_wall_rule, capacites F85/F86.
# Pac-Man avance du NOMBRE DE CASES fourni par le budget du tick, ou bute contre le mur.
# La regle de butee est la MEME quel que soit le budget : c'est la raison STRUCTURELLE
# pour laquelle le comportement face aux murs est declare inchange par conception.
extends RefCounted

const Player = preload("res://05_SYSTEMS/player_movement/player_movement.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# BUDGET : n cases au plus, en couloir libre.
	var depart: Vector2i = Maze.DEPART_PACMAN
	var d: Vector2i = Maze.DEPART_DIRECTION
	h.eq(Player.avancer_budget(Maze, depart, d, 1), Player.avancer(Maze, depart, d),
		"player.budget: un budget de 1 vaut le pas simple")
	var trois: Vector2i = Player.avancer_budget(Maze, depart, d, P.PAS_DASH)
	h.eq(MazeClass.distance(depart, trois), P.PAS_DASH, "player.budget: un budget de 3 avance de 3 cases")
	h.eq(Player.avancer_budget(Maze, depart, d, 0), depart, "player.budget: un budget nul n'avance pas")
	h.eq(Player.avancer_budget(Maze, depart, MazeClass.AUCUNE, 3), depart,
		"player.budget: sans direction, aucun deplacement")

	# BUTEE : la MEME regle a chaque case du budget. Contre un mur, 3 ne franchit pas
	# plus que 1 — sur les DEUX cartes, donc ce n'est pas une propriete d'une carte.
	for carte in [Maze, Alt]:
		var mur_trouve: bool = false
		for dir in MazeClass.DIRECTIONS:
			if carte.praticable(carte.case_suivante(carte.DEPART_PACMAN, dir)):
				continue
			mur_trouve = true
			var a: Vector2i = Player.avancer_budget(carte, carte.DEPART_PACMAN, dir, 1)
			var b: Vector2i = Player.avancer_budget(carte, carte.DEPART_PACMAN, dir, P.PAS_DASH)
			h.eq(a, carte.DEPART_PACMAN, "player.budget: budget 1 bute contre le mur")
			h.eq(b, carte.DEPART_PACMAN, "player.budget: budget 3 bute au meme endroit")
			break
		h.eq(mur_trouve, true, "player.budget: un mur adjacent au depart existe sur la carte")

	# DIRECTION RESOLUE : la demande n'est retenue que si le virage est praticable.
	var r: Dictionary = Player.direction_resolue(Maze, depart, MazeClass.GAUCHE, MazeClass.HAUT)
	h.ok(r.has("direction"), "player.budget: la resolution rend une direction")
	h.ok(r.has("attente"), "player.budget: elle rend aussi la file d'attente")
	var bloque: Dictionary = Player.direction_resolue(Maze, Vector2i(1, 4), MazeClass.DROITE, MazeClass.HAUT)
	h.eq(bloque["direction"], MazeClass.DROITE, "player.budget: un virage impraticable conserve la direction")
	h.eq(bloque["attente"], MazeClass.HAUT, "player.budget: la demande RESTE en attente")

	# La butee est appliquee case par case : un budget long ne traverse jamais un mur.
	var loin: Vector2i = Player.avancer_budget(Maze, depart, d, 40)
	h.eq(Maze.praticable(loin), true, "player.budget: la case atteinte reste praticable")
	h.eq(Maze.dans_grille(loin), true, "player.budget: elle reste dans la grille")
