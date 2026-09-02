# harness_red_ghost_closing.gd — ligne harness.red_ghost_closing, capacite F59.
# Pac-Man ARRETE contre un mur, AUCUNE entree, etat de poursuite actif : la distance
# Pac-Man / fantome rouge decroit STRICTEMENT a chacun de ses deplacements sur une
# fenetre declaree.
extends RefCounted

const RedClosing = preload("res://06_RUNTIME/adapters/proof_harness/red_closing.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	# Le protocole est TENU : Pac-Man ne bouge pas de toute la fenetre.
	var mesure: Dictionary = RedClosing.mesurer(Maze)
	h.eq(mesure["pac_immobile"], true,
		"harness.closing: Pac-Man reste immobile — un joueur qui bouge rend la mesure ambigue")

	# L'etat de poursuite est bien actif pendant la fenetre mesuree.
	h.eq(Chase.mode_global(0), Chase.Mode.POURSUITE, "harness.closing: poursuite au debut de la fenetre")
	h.eq(Chase.mode_global(RedClosing.FENETRE), Chase.Mode.POURSUITE,
		"harness.closing: poursuite encore active a la fin de la fenetre")

	# Le fantome s'est REELLEMENT deplace : sans deplacement, l'assertion serait vide.
	h.gt(mesure["deplacements"], 0, "harness.closing: le fantome rouge s'est deplace")
	h.eq(mesure["deplacements"], RedClosing.FENETRE,
		"harness.closing: un deplacement par tick sur cette fenetre (aucun tick saute)")

	# DECROISSANCE STRICTE a CHAQUE deplacement.
	h.eq(mesure["non_decroissances"], 0,
		"harness.closing: 0 deplacement sans decroissance stricte de la distance")
	h.lt(mesure["distance_fin"], mesure["distance_debut"],
		"harness.closing: distance finale strictement inferieure a la distance initiale")
	h.eq(mesure["distance_debut"] - mesure["distance_fin"], mesure["deplacements"],
		"harness.closing: la distance a baisse d'exactement un par deplacement")

	# La fixture est bien un couloir droit, et la mesure est celle de ghost_targeting.
	var pac := Vector2i(RedClosing.PAC_X, RedClosing.LIGNE_COULOIR)
	var rouge := Vector2i(RedClosing.ROUGE_X, RedClosing.LIGNE_COULOIR)
	h.eq(mesure["distance_debut"], Targeting.distance(pac, rouge),
		"harness.closing: la distance de depart est celle de la mesure unique")
	h.eq(Maze.praticable(pac), true, "harness.closing: la case de Pac-Man est praticable")
	h.eq(Maze.praticable(Maze.case_suivante(pac, Maze.DROITE)), false,
		"harness.closing: Pac-Man est bien bute contre un mur")

	# La suite des distances est strictement decroissante, terme a terme.
	var suite: Array = RedClosing.distances(Maze)
	h.gt(suite.size(), 1, "harness.closing: la suite de distances porte plusieurs termes")
	h.eq(RedClosing.non_decroissances(suite), 0, "harness.closing: suite strictement decroissante")

	# CONTRE-EPREUVE du detecteur : une suite non decroissante est REFUSEE.
	h.gt(RedClosing.non_decroissances([5, 5, 4]), 0, "harness.closing: un palier est detecte")
	h.gt(RedClosing.non_decroissances([5, 6]), 0, "harness.closing: une remontee est detectee")
	h.eq(RedClosing.non_decroissances([5, 4, 3]), 0, "harness.closing: une vraie decroissance passe")
