# solvability.gd — POINT D'ENTREE de l'oracle R8 (descripteur proof.solvability, racine du
# projet, categorie godot.project_root). Charge par scripts/forge/solvability_godot.mjs via
# `--seed=<n> --max_ticks=<m>`. Un bot SCRIPTE DETERMINISTE joue une partie complete par le MEME
# canal public que le clavier (intentions passees a Loop.step, jamais de forcage d'etat).
#
# HONNETETE DE GENRE (genre.tetris.no_victory_in_marathon) : Tetris n'a PAS d'etat gagne. La
# solvabilite ne peut donc PAS etre « le bot gagne ». Critere : le bot SURVIT >= N pieces ET
# nettoie >= 1 ligne — une preuve que le systeme est jouable et que l'objectif (nettoyer) est
# atteignable, jamais un « gagne ». Sortie : une ligne `FORGE_TRIAL {"succeeded":bool,"ticks":n|null}`.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const Lock = preload("res://05_SYSTEMS/lock_rules/lock.gd")
const LineClear = preload("res://05_SYSTEMS/line_clear/line_clear.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")

# Plancher de survie exige. CALIBRE PAR MESURE le 2026-08-10, ratifie Pierre.
# Preuve : lab/forge_evidence/TETRIS_SOLVABILITY_N_20260810/ (18 graines, Godot v4.6.3
# headless, harnais inchange). Ce qui a ete mesure, et qui a decide ces deux valeurs :
#   - a max_ticks=20000 : 6 graines sur 18 meurent naturellement, la plus courte survie
#     observee est 702 pieces. N=100 est donc 7x sous le minimum d'un systeme SAIN —
#     marge voulue contre le faux negatif (lecon Snake : max_ticks=200 rendait 0/50).
#   - cadence mesuree : 4,448 ticks/piece (ecart-type 0,016). 100 pieces exigent ~445
#     ticks, d'ou max_ticks=500.
#   - verification a max_ticks=500 sur les 18 graines : 109 a 119 pieces atteintes,
#     41 a 46 lignes. Aucune graine sous le plancher ; marge de la PIRE graine = 9 %.
#
# LES DEUX CONSTANTES SONT COUPLEES : a 4,448 ticks/piece, max_ticks borne mecaniquement
# le nombre de pieces atteignables (200 ticks -> ~45 pieces). Relever N sans relever
# max_ticks fabrique un faux negatif certain. Ne jamais toucher l'une seule.
#
# CE QUI N'EST PAS PROUVE : aucun controle negatif. On a mesure ce que fait un systeme
# sain, jamais ce qu'un systeme casse produirait. N=100 est une BORNE SURE, pas un seuil
# dont le pouvoir discriminant a ete demontre.
const N_SURVIVE: int = 100
const MAX_TICKS_DEFAUT: int = 500
const ACTIONS_CAP: int = 24            # garde anti-blocage : force le hard-drop apres N actions

var _plan: Dictionary = {}
var _planned_for: int = -1
var _actions: int = 0

func _initialize() -> void:
	var seed_val := _lire_arg("--seed", 1)
	var max_ticks := _lire_arg("--max_ticks", MAX_TICKS_DEFAUT)
	if max_ticks <= 0:
		max_ticks = MAX_TICKS_DEFAUT
	var recu := run_solvability(seed_val, max_ticks)
	print("FORGE_TRIAL " + JSON.stringify(recu))
	quit(0)

# Joue une partie pilotee par le bot deterministe. Rend le recu de solvabilite.
func run_solvability(seed_val: int, max_ticks: int) -> Dictionary:
	var s = State.initial(seed_val)
	_plan = {}
	_planned_for = -1
	_actions = 0
	var t := 0
	while t < max_ticks and s.status == State.Statut.EN_COURS:
		var intent := _choose_intent(s)
		s = Loop.step(s, intent)["state"]
		t += 1
	var survived: int = s.pieces_spawned - 1
	var succeeded: bool = survived >= N_SURVIVE and s.lines_cleared >= 1
	var recu := {
		"succeeded": succeeded,
		"ticks": (t if succeeded else null),
		"pieces": survived,
		"lines": s.lines_cleared,
	}
	return recu

# --- Bot : planifie une cible par piece, puis emet l'intention qui rapproche de la cible. ---

func _choose_intent(s) -> int:
	if s.active.is_empty():
		return InputRules.NONE
	if s.pieces_spawned != _planned_for:
		_plan = _compute_plan(s)
		_planned_for = s.pieces_spawned
		_actions = 0
	_actions += 1
	if _actions >= ACTIONS_CAP:
		return InputRules.HARD_DROP
	var piece: Dictionary = s.active
	if piece["rot"] != int(_plan["rot"]):
		return InputRules.ROTATE_CW
	if piece["pos"].x < int(_plan["x"]):
		return InputRules.RIGHT
	if piece["pos"].x > int(_plan["x"]):
		return InputRules.LEFT
	return InputRules.HARD_DROP

# Cherche la meilleure (orientation, colonne d'origine) : simule l'atterrissage sur la grille
# courante, evalue le terrain resultant, garde le meilleur (tie-break deterministe : rot puis x
# croissants). Le generateur d'instances ne consulte JAMAIS la brique testee : le bot rejoue la
# logique reelle (drop + lock + clear), il ne devine pas.
func _compute_plan(s) -> Dictionary:
	var piece: Dictionary = s.active
	var best := {"rot": piece["rot"], "x": piece["pos"].x, "score": -INF}
	for rot in range(4):
		for x in range(-1, P.COLS):
			var cand := Collision.make_piece(piece["type"], rot, Vector2i(x, 0))
			if not Collision.piece_fits(s.grid, cand):
				continue
			var landed := _drop_to_bottom(s.grid, cand)
			var g2: Array = Lock.lock_piece(s.grid, landed)
			var lc: Dictionary = LineClear.clear_lines(g2)
			var sc: float = _evaluate(lc["grid"], lc["cleared"])
			if sc > float(best["score"]):
				best = {"rot": rot, "x": x, "score": sc}
	return best

func _drop_to_bottom(grid: Array, piece: Dictionary) -> Dictionary:
	var cur := piece
	while true:
		var d := Collision.make_piece(cur["type"], cur["rot"], cur["pos"] + Vector2i(0, 1))
		if Collision.piece_fits(grid, d):
			cur = d
		else:
			break
	return cur

# Heuristique classique (Dellacherie simplifiee) : recompense forte des lignes nettoyees,
# penalise hauteur cumulee, trous et rugosite. Deterministe (memes entrees -> meme score).
func _evaluate(grid: Array, cleared: int) -> float:
	var heights: Array = []
	for x in range(P.COLS):
		heights.append(_col_height(grid, x))
	var agg := 0
	for h in heights:
		agg += h
	var holes := _count_holes(grid, heights)
	var bump := 0
	for x in range(P.COLS - 1):
		bump += abs(int(heights[x]) - int(heights[x + 1]))
	return 3.0 * float(cleared) - 0.5 * float(agg) - 0.7 * float(holes) - 0.2 * float(bump)

func _col_height(grid: Array, x: int) -> int:
	for y in range(P.ROWS):
		if grid[y][x] != 0:
			return P.ROWS - y
	return 0

func _count_holes(grid: Array, heights: Array) -> int:
	var holes := 0
	for x in range(P.COLS):
		var top: int = P.ROWS - int(heights[x])
		for y in range(top, P.ROWS):
			if grid[y][x] == 0:
				holes += 1
	return holes

func _lire_arg(nom: String, defaut: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(nom + "="):
			var v := a.substr((nom + "=").length())
			if v.is_valid_int():
				return int(v)
	return defaut
