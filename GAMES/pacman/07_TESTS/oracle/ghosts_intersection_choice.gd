# ghosts_intersection_choice.gd — ligne ghosts.intersection_choice, capacite F20.
# Pac-Man ARRETE contre un mur, AUCUNE entree, etat de poursuite actif : la sortie
# retenue est la plus proche de la cible, et la distance Pac-Man / fantome rouge decroit
# STRICTEMENT a chacun de ses deplacements.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Ghosts = preload("res://05_SYSTEMS/ghost_movement/ghost_movement.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const RedClosing = preload("res://06_RUNTIME/adapters/proof_harness/red_closing.gd")


func run(h) -> void:
	# La sortie retenue est la PLUS PROCHE de la cible, valeur exacte.
	var choix: Vector2i = Ghosts.choisir_direction(Maze, Vector2i(6, 23), Maze.DROITE, Vector2i(6, 4))
	h.eq(choix, Maze.HAUT, "ghosts.choice: la sortie la plus proche de la cible est retenue")
	var choix2: Vector2i = Ghosts.choisir_direction(Maze, Vector2i(6, 23), Maze.DROITE, Vector2i(6, 32))
	h.eq(choix2, Maze.BAS, "ghosts.choice: cible en bas -> sortie du bas")

	# DEMI-TOUR EXCLU : la direction inverse n'est jamais candidate hors cul-de-sac.
	var candidates: Array = Ghosts.sorties_candidates(Maze, Vector2i(6, 23), Maze.DROITE)
	h.eq(candidates.has(Maze.GAUCHE), false, "ghosts.choice: le demi-tour n'est pas candidat")
	h.eq(candidates.size(), 3, "ghosts.choice: trois sorties sur les quatre d'un vrai carrefour")
	h.eq(Maze.voisins_praticables(Vector2i(6, 23)).size(), 4, "ghosts.choice: le carrefour a bien 4 sorties")

	# EGALITES departagees par l'ORDRE DECLARE (haut, gauche, bas, droite).
	# Depuis (6,11) avec une cible equidistante en haut et en bas, le haut gagne.
	var haut: Vector2i = Maze.case_suivante(Vector2i(6, 23), Maze.HAUT)
	var bas: Vector2i = Maze.case_suivante(Vector2i(6, 23), Maze.BAS)
	var cible_equidistante := Vector2i(6, 23)
	h.eq(Targeting.distance(haut, cible_equidistante), Targeting.distance(bas, cible_equidistante),
		"ghosts.choice: fixture — haut et bas equidistants de la cible")
	h.eq(Ghosts.choisir_direction(Maze, Vector2i(6, 23), Maze.DROITE, cible_equidistante), Maze.HAUT,
		"ghosts.choice: egalite departagee par l'ordre declare")

	# CUL-DE-SAC : le demi-tour redevient possible, sinon le fantome serait fige.
	var impasse := Vector2i(1, 4)
	var sorties_impasse: Array = Ghosts.sorties_candidates(Maze, impasse, Maze.HAUT)
	h.gt(sorties_impasse.size(), 0, "ghosts.choice: un fantome n'est jamais sans sortie")

	# SUR UNE PARTIE : Pac-Man immobile contre un mur, mode POURSUITE, aucune entree.
	h.eq(Chase.mode_global(0), Chase.Mode.POURSUITE, "ghosts.choice: mode POURSUITE au depart de la fixture")
	var mesure: Dictionary = RedClosing.mesurer(Maze)
	h.eq(mesure["pac_immobile"], true, "ghosts.choice: Pac-Man reste immobile pendant la mesure")
	h.gt(mesure["deplacements"], 0, "ghosts.choice: le fantome rouge s'est reellement deplace")
	h.eq(mesure["non_decroissances"], 0,
		"ghosts.choice: la distance decroit STRICTEMENT a chaque deplacement du rouge")
	h.lt(mesure["distance_fin"], mesure["distance_debut"],
		"ghosts.choice: la distance finale est strictement inferieure a la distance initiale")
