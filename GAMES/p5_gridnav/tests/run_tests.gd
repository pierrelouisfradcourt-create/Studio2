# Test suite pour Patrol — BFS déterministe sur grille 2D.
# Lancer : godot --headless --path games/p5_gridnav --script res://tests/run_tests.gd
# exit 0 = tous verts, 1 = échec.
extends SceneTree

const Patrol = preload("res://core/patrol.gd")

# Nombre d'assertions attendu — garde anti-faux-vert.
const EXPECTED_ASSERTS := 13

var _passed := 0
var _failed := 0
var _fails: Array = []

func _initialize() -> void:
	test_simple_path_no_obstacle()
	test_path_length_simple()
	test_path_unreachable_surrounded()
	test_same_position()
	test_obstacle_contour()
	test_determinism()
	test_path_length_l_shape()
	test_next_step_sequence()
	test_out_of_bounds_treated_as_wall()
	test_path_length_larger_grid()
	test_pure_no_grid_modification()
	test_exact_path_computation()

	var total := _passed + _failed
	if total != EXPECTED_ASSERTS:
		_failed += 1
		_fails.append("META: %d/%d assertions exécutées" % [total, EXPECTED_ASSERTS])

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

## Grille de test 5x5 avec format Array[Array[bool]].
## true = traversable, false = obstacle.
func make_grid_5x5_clear() -> Array:
	var grid = []
	for y in range(5):
		var row = []
		for x in range(5):
			row.append(true)
		grid.append(row)
	return grid

## Grille 5x5 avec obstacle au centre.
func make_grid_5x5_center_obstacle() -> Array:
	var grid = make_grid_5x5_clear()
	grid[2][2] = false
	return grid

## Grille 5x5 avec cible entourée des 4 côtés.
func make_grid_5x5_surrounded() -> Array:
	var grid = make_grid_5x5_clear()
	var target = Vector2i(2, 2)
	grid[1][2] = false  # nord
	grid[3][2] = false  # sud
	grid[2][1] = false  # ouest
	grid[2][3] = false  # est
	return grid

# === Tests ===

func test_simple_path_no_obstacle() -> void:
	var grid = make_grid_5x5_clear()
	var from = Vector2i(0, 0)
	var to = Vector2i(1, 0)
	var step = Patrol.next_step(grid, from, to)
	ok(step == to, "next_step: cible adjacente à l'est => direction atteinte en 1 pas")

func test_path_length_simple() -> void:
	var grid = make_grid_5x5_clear()
	var from = Vector2i(0, 0)
	var to = Vector2i(3, 0)
	var length = Patrol.path_length(grid, from, to)
	ok(length == 3, "path_length: distance Manhattan 3 sur grille dégagée = 3")

func test_path_unreachable_surrounded() -> void:
	var grid = make_grid_5x5_surrounded()
	var from = Vector2i(0, 0)
	var to = Vector2i(2, 2)
	var length = Patrol.path_length(grid, from, to)
	ok(length == -1, "path_length: cible entourée => -1 (inatteignable)")

func test_same_position() -> void:
	var grid = make_grid_5x5_clear()
	var pos = Vector2i(2, 2)
	var step = Patrol.next_step(grid, pos, pos)
	ok(step == pos, "next_step: départ == cible => retourne départ")

func test_obstacle_contour() -> void:
	var grid = make_grid_5x5_center_obstacle()
	var from = Vector2i(0, 0)
	var to = Vector2i(4, 4)
	var step = Patrol.next_step(grid, from, to)
	# Le premier pas vers (4,4) en contournant l'obstacle au centre doit s'éloigner du
	# point (0,0), pas rester au point ou se rapprocher du centre directement bloqué
	ok(step != from, "next_step: contourne obstacle (bouge d'au moins une case)")
	ok(step.distance_to(from) == 1, "next_step: déplace d'exactement 1 case en 4 directions")

func test_determinism() -> void:
	var grid = make_grid_5x5_center_obstacle()
	var from = Vector2i(1, 1)
	var to = Vector2i(4, 4)
	var first = Patrol.next_step(grid, from, to)
	# 100 appels identiques doivent rendre 100 résultats identiques
	var all_same = true
	for i in range(100):
		var result = Patrol.next_step(grid, from, to)
		if result != first:
			all_same = false
			break
	ok(all_same, "next_step: 100 appels identiques rendent le même résultat (déterminisme)")

func test_path_length_l_shape() -> void:
	var grid = make_grid_5x5_clear()
	# Obstacle entre (0,0) et (2,0)
	grid[0][1] = false
	var from = Vector2i(0, 0)
	var to = Vector2i(2, 0)
	var length = Patrol.path_length(grid, from, to)
	# Chemin doit contourner : (0,0)->(0,1)->(1,1)->(2,1)->(2,0) = 4 pas
	ok(length == 4, "path_length: contourner obstacle latéral => 4 pas")

func test_next_step_sequence() -> void:
	var grid = make_grid_5x5_clear()
	var from = Vector2i(0, 0)
	var to = Vector2i(4, 4)
	var current = from
	var step_count = 0
	# Suivre le chemin jusqu'à la cible
	for i in range(20):  # Max 20 étapes pour éviter boucle infinie
		var step = Patrol.next_step(grid, current, to)
		if step == to:
			step_count = i + 1
			break
		if step == current:  # Impossible de progresser
			break
		current = step
	ok(step_count == 8, "next_step: séquence de pas vers (4,4) depuis (0,0) => 8 pas (Manhattan)")

func test_out_of_bounds_treated_as_wall() -> void:
	var grid = make_grid_5x5_clear()
	var from = Vector2i(0, 0)
	var to = Vector2i(10, 10)  # Hors de la grille
	var length = Patrol.path_length(grid, from, to)
	ok(length == -1, "path_length: cible hors grille => -1 (inatteignable)")

func test_path_length_larger_grid() -> void:
	# Grille 10x10 claire
	var grid = []
	for y in range(10):
		var row = []
		for x in range(10):
			row.append(true)
		grid.append(row)
	var from = Vector2i(0, 0)
	var to = Vector2i(9, 9)
	var length = Patrol.path_length(grid, from, to)
	ok(length == 18, "path_length: Manhattan 9+9 sur grille 10x10 = 18")

func test_pure_no_grid_modification() -> void:
	var grid = make_grid_5x5_center_obstacle()
	var grid_before = _grid_deep_copy(grid)
	var from = Vector2i(0, 0)
	var to = Vector2i(4, 4)
	var _step = Patrol.next_step(grid, from, to)
	var grid_after = _grid_deep_copy(grid)
	ok(_grid_equals(grid_before, grid_after), "next_step: ne modifie pas la grille (pureté)")

func test_exact_path_computation() -> void:
	# Chemin exact prévisible sur grille petite sans obstacle
	var grid = make_grid_5x5_clear()
	var from = Vector2i(1, 1)
	var to = Vector2i(3, 1)
	var length = Patrol.path_length(grid, from, to)
	ok(length == 2, "path_length: (1,1) à (3,1) sur grille dégagée = 2 pas")

# === Utilitaires de test ===

func _grid_deep_copy(grid: Array) -> Array:
	var copy = []
	for row in grid:
		copy.append(row.duplicate())
	return copy

func _grid_equals(g1: Array, g2: Array) -> bool:
	if g1.size() != g2.size():
		return false
	for y in range(g1.size()):
		if g1[y].size() != g2[y].size():
			return false
		for x in range(g1[y].size()):
			if g1[y][x] != g2[y][x]:
				return false
	return true
