# Oracle headless pour grid_nav.gd — déterministe, pur.
# Lancer : godot --headless --path games/grid_nav_probe --script res://tests/run_tests.gd
# exit 0 = tous verts, 1 = échec.
extends SceneTree

const GridNav = preload("res://core/grid_nav.gd")
const Trial = preload("res://trial.gd")

# Nombre d'assertions attendu — garde anti-faux-vert.
const EXPECTED_ASSERTS := 39

var _passed := 0
var _failed := 0
var _fails: Array = []

func _initialize() -> void:
	test_next_step_adjacent_north()
	test_next_step_adjacent_south()
	test_next_step_adjacent_east()
	test_next_step_adjacent_west()
	test_next_step_same_position()
	test_path_length_adjacent()
	test_path_length_straight_line()
	test_path_length_unreachable()
	test_path_length_same()
	test_path_length_diagonal_obstacle()
	test_next_step_avoids_wall_north()
	test_next_step_avoids_wall_south()
	test_next_step_reduces_distance()
	test_next_step_determinism()
	test_path_purity_walls_unmodified()
	test_path_length_complex_maze()
	test_next_step_away_then_toward()
	test_path_length_surrounded()
	test_edge_wrapping_not_allowed()
	test_path_length_large_distance()
	test_next_step_multiple_steps()
	test_path_length_L_shape()
	test_next_step_consistency()
	test_bfs_revisit_detection()
	test_path_long_exploration()
	# --- escalade Task 8, défaut 2 : compteur d'expansions observant le TRAVAIL
	# du BFS de next_step, pas seulement son résultat (cf. mutation_triage.json) ---
	test_next_step_expansions_immediate_direction()
	test_next_step_expansions_two_steps()
	test_next_step_expansions_open_grid_exact()
	test_next_step_expansions_bounded_large_grid()
	test_next_step_expansions_consistent_with_next_step()
	# --- escalade Task 8fix, defaut CRITIQUE : controle negatif de l'oracle de
	# solvabilite. Sans ces deux tests, "succeeded=false" ne serait jamais prouve
	# ATTEIGNABLE par la boucle de simulation extraite (Trial.run_simulation_with_walls) ---
	test_trial_walled_target_unreachable_fails()
	test_trial_clear_corridor_succeeds_exact_ticks()

	var total := _passed + _failed
	if total != EXPECTED_ASSERTS:
		_failed += 1
		_fails.append("META: %d/%d assertions exécutées (coeur non chargé ?)" % [total, EXPECTED_ASSERTS])

	print("\n=== RESULT: %d passed, %d failed ===" % [_passed, _failed])
	for f in _fails:
		print("  FAIL: ", f)
	quit(0 if _failed == 0 else 1)

func ok(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_fails.append(name)

# === Test suite ===

func test_next_step_adjacent_north() -> void:
	var from = Vector2i(5, 5)
	var to = Vector2i(5, 4)  # une case vers le nord
	var walls = {}
	var step = GridNav.next_step(from, to, walls)
	ok(step == to, "next_step adjacent north reaches target")

func test_next_step_adjacent_south() -> void:
	var from = Vector2i(5, 5)
	var to = Vector2i(5, 6)  # une case vers le sud
	var walls = {}
	var step = GridNav.next_step(from, to, walls)
	ok(step == to, "next_step adjacent south reaches target")

func test_next_step_adjacent_east() -> void:
	var from = Vector2i(5, 5)
	var to = Vector2i(6, 5)  # une case vers l'est
	var walls = {}
	var step = GridNav.next_step(from, to, walls)
	ok(step == to, "next_step adjacent east reaches target")

func test_next_step_adjacent_west() -> void:
	var from = Vector2i(5, 5)
	var to = Vector2i(4, 5)  # une case vers l'ouest
	var walls = {}
	var step = GridNav.next_step(from, to, walls)
	ok(step == to, "next_step adjacent west reaches target")

func test_next_step_same_position() -> void:
	var pos = Vector2i(3, 3)
	var walls = {}
	var step = GridNav.next_step(pos, pos, walls)
	ok(step == pos, "next_step(p, p, {}) returns p")

func test_path_length_adjacent() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(1, 0)
	var walls = {}
	var length = GridNav.path_length(from, to, walls)
	ok(length == 1, "path_length adjacent = 1")
	ok(length > 0, "path_length adjacent is positive")

func test_path_length_straight_line() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(5, 0)
	var walls = {}
	var length = GridNav.path_length(from, to, walls)
	ok(length == 5, "path_length straight line = 5")

func test_path_length_unreachable() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(5, 5)
	# entourer to de murs
	var walls = {}
	walls[Vector2i(4, 5)] = true
	walls[Vector2i(6, 5)] = true
	walls[Vector2i(5, 4)] = true
	walls[Vector2i(5, 6)] = true
	var length = GridNav.path_length(from, to, walls)
	ok(length == -1, "path_length unreachable = -1")

func test_path_length_same() -> void:
	var pos = Vector2i(2, 2)
	var walls = {}
	var length = GridNav.path_length(pos, pos, walls)
	ok(length == 0, "path_length same position = 0")
	ok(length >= 0, "path_length is non-negative for reachable target")

func test_path_length_diagonal_obstacle() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(2, 0)
	var walls = {}
	walls[Vector2i(1, 0)] = true
	# doit aller via (0,1) -> (1,1) -> (2,1) -> (2,0) = 4 pas
	var length = GridNav.path_length(from, to, walls)
	ok(length == 4, "path_length with direct obstacle = 4")

func test_next_step_avoids_wall_north() -> void:
	var from = Vector2i(5, 5)
	var to = Vector2i(5, 0)  # loin au nord
	var walls = {}
	walls[Vector2i(5, 4)] = true  # mur directement au nord
	var step = GridNav.next_step(from, to, walls)
	# doit contourner -> aller à l'est ou l'ouest
	ok(step != from, "next_step avoids wall north (moves away)")
	ok(step == Vector2i(6, 5) or step == Vector2i(4, 5), "next_step avoids wall north and detours")

func test_next_step_avoids_wall_south() -> void:
	var from = Vector2i(5, 5)
	var to = Vector2i(5, 10)
	var walls = {}
	walls[Vector2i(5, 6)] = true  # mur directement au sud
	var step = GridNav.next_step(from, to, walls)
	ok(step == Vector2i(6, 5) or step == Vector2i(4, 5), "next_step avoids wall south")

func test_next_step_reduces_distance() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(10, 10)
	var walls = {}
	var step = GridNav.next_step(from, to, walls)
	var dist_before = from.distance_to(to)
	var dist_after = step.distance_to(to)
	ok(dist_after < dist_before, "next_step reduces Manhattan distance to target")
	ok(step != from, "next_step produces different position")
	ok(step.distance_to(to) >= 0, "distance is non-negative")

func test_next_step_determinism() -> void:
	var from = Vector2i(7, 7)
	var to = Vector2i(3, 2)
	var walls = {}
	walls[Vector2i(6, 6)] = true
	walls[Vector2i(5, 5)] = true
	# 100 appels identiques doivent donner 100 résultats identiques
	var first = GridNav.next_step(from, to, walls)
	var all_same = true
	for i in range(100):
		var result = GridNav.next_step(from, to, walls)
		if result != first:
			all_same = false
			break
	ok(all_same, "next_step determinism 100 calls identical")

func test_path_purity_walls_unmodified() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(3, 3)
	var walls = {}
	walls[Vector2i(1, 1)] = true
	walls[Vector2i(2, 2)] = true
	var walls_before = walls.duplicate()
	var _length = GridNav.path_length(from, to, walls)
	var walls_after = walls.duplicate()
	ok(walls_before == walls_after, "path_length does not modify walls dictionary")

func test_path_length_complex_maze() -> void:
	# S-shaped path: go right 2, up 2, right 2
	var from = Vector2i(0, 0)
	var to = Vector2i(4, 2)
	var walls = {}
	walls[Vector2i(2, 1)] = true
	walls[Vector2i(3, 0)] = true
	walls[Vector2i(3, 1)] = true
	# Path: (0,0)->(1,0)->(2,0)->(2,1 blocked)->(2,2)->(3,2)->(4,2)
	# Length should be 6
	var length = GridNav.path_length(from, to, walls)
	ok(length == 6, "path_length complex maze = 6")

func test_next_step_away_then_toward() -> void:
	# If direct path blocked, move perpendicular then converge
	var from = Vector2i(5, 5)
	var to = Vector2i(5, 0)
	var walls = {}
	walls[Vector2i(5, 4)] = true
	walls[Vector2i(5, 3)] = true
	walls[Vector2i(5, 2)] = true
	walls[Vector2i(5, 1)] = true
	# Must go around
	var step = GridNav.next_step(from, to, walls)
	ok(step != from, "next_step moves away from deadlock")

func test_path_length_surrounded() -> void:
	var from = Vector2i(5, 5)
	var to = Vector2i(6, 6)
	var walls = {}
	# Surround from but not completely
	walls[Vector2i(4, 4)] = true
	walls[Vector2i(4, 5)] = true
	walls[Vector2i(4, 6)] = true
	# Still reachable via (5,6) -> (6,6)
	var length = GridNav.path_length(from, to, walls)
	ok(length == 2, "path_length surrounded = 2")

func test_edge_wrapping_not_allowed() -> void:
	# Grid allows negative indices but paths respect walls
	var from = Vector2i(0, 0)
	var to = Vector2i(10, 10)
	var walls = {}
	# Create a wall barrier
	for i in range(11):
		walls[Vector2i(5, i)] = true
	# Path must go around
	var length = GridNav.path_length(from, to, walls)
	ok(length > 10, "path_length around barrier > 10")

func test_path_length_large_distance() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(20, 20)
	var walls = {}
	var length = GridNav.path_length(from, to, walls)
	ok(length == 40, "path_length Manhattan distance 20+20 = 40")

func test_next_step_multiple_steps() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(5, 5)
	var walls = {}
	var step1 = GridNav.next_step(from, to, walls)
	var step2 = GridNav.next_step(step1, to, walls)
	var step3 = GridNav.next_step(step2, to, walls)
	ok(step1 != from and step2 != step1 and step3 != step2, "next_step sequence progresses toward target")

func test_path_length_L_shape() -> void:
	var from = Vector2i(0, 0)
	var to = Vector2i(3, 2)
	var walls = {}
	walls[Vector2i(1, 1)] = true
	walls[Vector2i(2, 1)] = true
	var length = GridNav.path_length(from, to, walls)
	ok(length == 5, "path_length L-shape with obstacle = 5")

func test_next_step_consistency() -> void:
	var from = Vector2i(2, 2)
	var to = Vector2i(10, 10)
	var walls = {}
	walls[Vector2i(5, 5)] = true
	var step1 = GridNav.next_step(from, to, walls)
	var step2 = GridNav.next_step(from, to, walls)
	ok(step1 == step2, "next_step is consistent for same inputs")

func test_bfs_revisit_detection() -> void:
	# Test that BFS properly marks visited cells and doesn't revisit
	# This catches mutations where visited[cell] = false fails
	var from = Vector2i(0, 0)
	var to = Vector2i(10, 0)  # 10 steps away
	var walls = {}
	# No walls, so BFS explores in all 4 directions
	var length = GridNav.path_length(from, to, walls)
	ok(length == 10, "BFS finds correct distance without revisiting cells")

func test_path_long_exploration() -> void:
	# Another test to ensure visited tracking works correctly
	var from = Vector2i(0, 0)
	var to = Vector2i(5, 5)
	var walls = {}
	var length = GridNav.path_length(from, to, walls)
	ok(length == 10, "path_length handles explorations correctly")

# --- escalade Task 8, défaut 2 : compteur d'expansions de next_step ---
# Ces tests observent le TRAVAIL du BFS (nombre d'itérations de la boucle de
# voisinage), pas seulement le résultat final. Valeurs exactes vérifiées par
# exécution réelle (cf. task-8-report.md, section escalade), pas déduites.
# NOTE HONNÊTE : ces tests NE TUENT PAS les 2 survivants historiques
# (visited[from]/visited[neighbor] : true->false, dans _bfs_next_step) --
# voir mutation_triage.json pour la preuve que ces deux mutants précis sont
# authentiquement équivalents (Dictionary.has() en GDScript ignore la valeur
# stockée, seule la présence de la clé compte ; ces tests le confirment
# empiriquement : les expansions restent identiques avec le mutant appliqué).
# Ils restent utiles en défense en profondeur contre un VRAI bug de marquage
# (ex. suppression de la clé, inversion du test .has()), qui ferait exploser
# ce compteur de façon flagrante.

func test_next_step_expansions_immediate_direction() -> void:
	# Nord est la première direction testée (ordre FIXE) ; si la cible est au
	# nord immédiat, elle est trouvée dès la 1ère itération de la boucle.
	var from = Vector2i(5, 5)
	var to = Vector2i(5, 4)
	var exp = GridNav.next_step_expansions(from, to, {})
	ok(exp == 1, "next_step_expansions: cible au nord immédiat = 1 expansion")

func test_next_step_expansions_two_steps() -> void:
	# Est est la 2e direction testée ; nord (nul résultat) puis est (trouvé).
	var from = Vector2i(0, 0)
	var to = Vector2i(1, 0)
	var exp = GridNav.next_step_expansions(from, to, {})
	ok(exp == 2, "next_step_expansions: cible à l'est = 2 expansions (nord puis est)")

func test_next_step_expansions_open_grid_exact() -> void:
	# Grille 10x10 ouverte (aucun mur), coin à coin : valeur exacte mesurée par
	# exécution réelle du BFS non muté.
	var from = Vector2i(0, 0)
	var to = Vector2i(9, 9)
	var exp = GridNav.next_step_expansions(from, to, {})
	ok(exp == 2347, "next_step_expansions: grille ouverte 10x10 coin-à-coin = 2347")

func test_next_step_expansions_bounded_large_grid() -> void:
	# Grille 20x20 ouverte : borne large (mesuré 11027) pour attraper une
	# explosion réelle (un vrai bug de marquage ferait exploser ce compteur
	# bien au-delà de cette borne, pas y flirter de peu).
	var from = Vector2i(0, 0)
	var to = Vector2i(19, 19)
	var exp = GridNav.next_step_expansions(from, to, {})
	ok(exp <= 15000, "next_step_expansions: grille ouverte 20x20 bornée (<=15000, mesuré 11027)")

func test_next_step_expansions_consistent_with_next_step() -> void:
	# next_step et next_step_expansions partagent la même implémentation
	# (_bfs_next_step) : le pas retourné doit être identique.
	var from = Vector2i(2, 3)
	var to = Vector2i(8, 1)
	var walls = {Vector2i(5, 2): true}
	var step_via_next_step = GridNav.next_step(from, to, walls)
	var exp = GridNav.next_step_expansions(from, to, walls)
	ok(step_via_next_step != from and exp > 0, "next_step_expansions cohérent avec next_step (même code partagé)")

# --- escalade Task 8fix : contrôle négatif de l'oracle de solvabilité ---
# Le défaut CRITIQUE corrigé (solvability.gd + trial.gd) était que le générateur
# de labyrinthe interrogeait GridNav.path_length — la brique même qu'on teste —
# pour décider s'il fallait un chemin de secours. "succeeded=false" n'était donc
# jamais ATTEIGNABLE par construction : ces deux tests le prouvent.

func test_trial_walled_target_unreachable_fails() -> void:
	# Cible entièrement murée (encerclée des 4 côtés) : aucun chemin ne peut
	# exister vers elle, quel que soit `walls` par ailleurs. C'est le cœur du
	# correctif : il prouve que succeeded=false est ATTEIGNABLE par la boucle
	# de simulation extraite, indépendamment de tout générateur de labyrinthe.
	var target := Vector2i(5, 5)
	var walls := {}
	walls[Vector2i(4, 5)] = true
	walls[Vector2i(6, 5)] = true
	walls[Vector2i(5, 4)] = true
	walls[Vector2i(5, 6)] = true
	var result := Trial.run_simulation_with_walls(walls, Vector2i(0, 0), target, 200)
	ok(result["succeeded"] == false, "trial: cible entièrement murée => succeeded=false")
	ok(result["ticks"] == null, "trial: cible entièrement murée => ticks=null")

func test_trial_clear_corridor_succeeds_exact_ticks() -> void:
	# Couloir dégagé trivial, aucun mur : nombre de pas exact et vérifiable
	# (distance de Manhattan = 3), aucune ambiguïté possible sur le résultat.
	var start := Vector2i(0, 0)
	var target := Vector2i(3, 0)
	var walls := {}
	var result := Trial.run_simulation_with_walls(walls, start, target, 200)
	ok(result["succeeded"] == true, "trial: couloir dégagé => succeeded=true")
	ok(result["ticks"] == 3, "trial: couloir dégagé => ticks=3 exact")
