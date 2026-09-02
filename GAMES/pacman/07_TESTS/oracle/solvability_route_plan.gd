# solvability_route_plan.gd — ligne solvability.route_plan, capacite F53.
# Execution du bot sur la carte et la graine de reference : l'itineraire REELLEMENT
# parcouru couvre les 244 collectibles, retours en arriere compris, dans le budget de
# ticks DECLARE en entree.
#
# CORRECTION B1 (red-team s6) : l'itineraire n'est PAS pre-calcule. Il est produit tick
# apres tick par une politique en BOUCLE FERMEE qui relit l'etat courant, positions et
# etats des quatre fantomes compris. Ce test mesure donc la COUVERTURE reelle.
extends RefCounted

const Planner = preload("res://06_RUNTIME/adapters/solvability_bot/route_planner.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")

const GRAINE_REFERENCE: int = 1
const BUDGET_DECLARE: int = 4000


func run(h) -> void:
	# Le planificateur LIT l'etat des fantomes : sans cela il serait en boucle ouverte.
	var s = State.initial(Maze, GRAINE_REFERENCE)
	h.eq(Planner.poursuivants(s).size(), 1, "solvability.route: un seul poursuivant au tick 0")
	h.eq(Planner.proies(s).size(), 0, "solvability.route: aucune proie Effrayee au tick 0")
	Chase.armer_effraye(s)
	h.eq(Planner.poursuivants(s).size(), 0, "solvability.route: un fantome Effraye n'est plus un poursuivant")
	h.eq(Planner.proies(s).size(), 1, "solvability.route: il devient une proie")

	# Les distances sont calculees sur les cases praticables, bouclage de tunnel compris.
	var d: PackedInt32Array = Planner.distances_depuis(Maze, [Maze.DEPART_PACMAN])
	h.eq(d[Maze.index_de(Maze.DEPART_PACMAN)], 0, "solvability.route: distance nulle au depart")
	h.eq(d[Maze.index_de(Vector2i(0, 0))], Planner.INACCESSIBLE, "solvability.route: un mur est inaccessible")
	var atteignables: int = 0
	var libres: PackedInt32Array = Planner.cases_praticables(Maze)
	for n in range(libres.size()):
		if d[libres[n]] != Planner.INACCESSIBLE:
			atteignables += 1
	h.eq(atteignables, libres.size(), "solvability.route: toutes les cases praticables sont atteignables")
	h.eq(libres.size(), 300, "solvability.route: 300 cases praticables")

	# Le bouclage de tunnel est EMPRUNTE par le planificateur : la distance entre les deux
	# extremites du tunnel vaut 1, pas la largeur de la grille.
	var dt: PackedInt32Array = Planner.distances_depuis(Maze, [Vector2i(0, Maze.LIGNE_TUNNEL)])
	h.eq(dt[Maze.index_de(Vector2i(Maze.LARGEUR - 1, Maze.LIGNE_TUNNEL))], 1,
		"solvability.route: le tunnel est emprunte par la planification")

	# Le pas est DETERMINISTE : meme etat, meme pas.
	var t = State.initial(Maze, GRAINE_REFERENCE)
	h.eq(Planner.prochain_pas(t), Planner.prochain_pas(t), "solvability.route: pas deterministe")
	h.ok(Maze.DIRECTIONS.has(Planner.prochain_pas(t)) or Planner.prochain_pas(t) == Maze.AUCUNE,
		"solvability.route: le pas appartient au vocabulaire ferme")

	# COUVERTURE REELLE sur la carte et la graine de reference, dans le budget declare.
	var couverture: Dictionary = Planner.couverture(State.initial(Maze, GRAINE_REFERENCE), BUDGET_DECLARE)
	h.eq(couverture["total_pose"], 244, "solvability.route: 244 collectibles a couvrir")
	h.eq(couverture["consommees"], 244, "solvability.route: l'itineraire couvre les 244 collectibles")
	h.lt(couverture["ticks"], BUDGET_DECLARE, "solvability.route: dans le budget de ticks declare")
	h.gt(couverture["ticks"], 244,
		"solvability.route: l'itineraire comporte des retours en arriere (plus de ticks que de collectibles)")
