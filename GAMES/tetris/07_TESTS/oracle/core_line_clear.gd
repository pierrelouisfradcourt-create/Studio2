# core_line_clear.gd — oracle produit de la ligne core.line_clear. SceneTree headless.
# Observable : une rangee pleine disparait et tout ce qui est au-dessus descend d'EXACTEMENT autant.
# Sortie : "FORGE_ORACLE core_line_clear {json}", exit 0 si vert.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const LineClear = preload("res://05_SYSTEMS/line_clear/line_clear.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var grid: Array = State.empty_grid()
	# Remplit la derniere rangee, pose un marqueur unique juste au-dessus.
	for x in range(P.COLS):
		grid[P.ROWS - 1][x] = 1
	grid[P.ROWS - 2][0] = 7
	var r: Dictionary = LineClear.clear_lines(grid)
	if r["cleared"] != 1:
		fails.append("rangee pleine non detectee (cleared=%d)" % r["cleared"])
	var g2: Array = r["grid"]
	if g2.size() != P.ROWS:
		fails.append("hauteur de grille modifiee")
	if g2[P.ROWS - 1][0] != 7:
		fails.append("compactage != nombre exact de rangees retirees")
	var restant := 0
	for c in g2[P.ROWS - 1]:
		if c != 0:
			restant += 1
	if restant != 1:
		fails.append("la rangee pleine n'a pas disparu")
	data = {"cleared": r["cleared"], "marqueur_descendu_en": P.ROWS - 1}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_line_clear " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
