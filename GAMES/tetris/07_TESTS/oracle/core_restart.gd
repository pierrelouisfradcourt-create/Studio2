# core_restart.gd — oracle produit de la ligne core.restart. SceneTree headless.
# Observable : apres une partie, la relance rend un etat initial PROPRE — aucun residu de la partie precedente.
# Sortie : "FORGE_ORACLE core_restart {json}", exit 0 si vert.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")
const RL = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")

func _initialize() -> void:
	var fails: Array = []
	var data: Dictionary = {}
	var rl = RL.new()
	rl.start_game()
	var s0 = rl._state
	if s0 == null:
		fails.append("start_game ne produit aucun etat")
		rl.free()
		_emit(fails, data)
		return
	var grille_vide := true
	for row in s0.grid:
		for c in row:
			if c != 0:
				grille_vide = false
	if not grille_vide:
		fails.append("grille non vide au demarrage")
	# Salit REELLEMENT l'etat : hard-drops successifs pour verrouiller des pieces.
	# Sans cela l'assertion de proprete ci-dessous serait vide — elle passerait meme si
	# start_game() ne faisait rien. Un test qui ne peut pas echouer ne prouve rien.
	var s = s0
	for i in range(400):
		if s.status != State.Statut.EN_COURS:
			break
		s = Loop.step(s, InputRules.HARD_DROP)["state"]
	var sale: int = s.pieces_spawned
	var cellules_sales := 0
	for row in s.grid:
		for c in row:
			if c != 0:
				cellules_sales += 1
	# GARDE D'AUTO-VACUITE : si l'etat n'a pas ete sali, le reste du volet ne prouve rien.
	if sale <= 2 or (cellules_sales == 0 and s.ticks == 0):
		fails.append("etat non sali avant relance (pieces=%d, cellules=%d) — volet vide" % [sale, cellules_sales])
	rl.start_game()
	var s1 = rl._state
	if s1.score != 0 or s1.lines_cleared != 0 or s1.ticks != 0:
		fails.append("residu apres relance (score/lignes/ticks non remis a zero)")
	if s1.status != State.Statut.EN_COURS:
		fails.append("statut non remis a EN_COURS")
	var propre := true
	for row in s1.grid:
		for c in row:
			if c != 0:
				propre = false
	if not propre:
		fails.append("grille non vide apres relance")
	rl.free()
	data = {"pieces_avant_relance": sale, "cellules_avant_relance": cellules_sales, "score_apres": s1.score, "ticks_apres": s1.ticks}
	_emit(fails, data)

func _emit(fails: Array, data: Dictionary) -> void:
	print("FORGE_ORACLE core_restart " + JSON.stringify({"ok": fails.is_empty(), "fails": fails, "data": data}))
	quit(0 if fails.is_empty() else 1)
