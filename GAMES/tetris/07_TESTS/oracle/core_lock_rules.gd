# core_lock_rules.gd — oracle produit de la ligne core.lock_rules. SceneTree headless.
# Observable : la piece figee rejoint la pile et n'en ressort jamais ; la grille d'entree n'est jamais mutee.
# Sortie : "FORGE_ORACLE core_lock_rules {json}", exit 0 si vert.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Lock = preload("res://05_SYSTEMS/lock_rules/lock.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var grid: Array = State.empty_grid()
	var avant := 0
	for row in grid:
		for c in row:
			if c != 0:
				avant += 1
	var p := Collision.make_piece(1, 0, Vector2i(3, 5))
	var g2: Array = Lock.lock_piece(grid, p)
	var apres := 0
	for row in g2:
		for c in row:
			if c != 0:
				apres += 1
	if apres - avant != Collision.piece_cells(p).size():
		fails.append("cellules ajoutees != cellules de la piece")
	# La grille SOURCE ne doit pas avoir bouge (nouvelle grille rendue).
	var source := 0
	for row in grid:
		for c in row:
			if c != 0:
				source += 1
	if source != avant:
		fails.append("grille d'entree MUTEE par lock_piece")
	data = {"avant": avant, "apres": apres, "source_apres_appel": source}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_lock_rules " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
