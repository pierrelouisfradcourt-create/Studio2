# test_game_loop.gd — l'orchestrateur du tick. Etat terminal inerte ; avance stricte du tick ;
# gravite auto a EXACTEMENT GRAVITY_PERIOD (borne >=) ; atterrissage -> verrou+nettoyage+score.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")

func run(h) -> void:
	# Etat terminal : step inerte (aucune avance de tick).
	var s = State.initial(1)
	s.status = State.Statut.GAME_OVER
	var r: Dictionary = Loop.step(s, InputRules.NONE)
	h.eq(r["state"].ticks, s.ticks, "etat terminal : pas d'avance de tick")
	# Etat en cours : le tick avance d'exactement 1.
	var s2 = State.initial(1)
	var t0: int = s2.ticks
	var r2: Dictionary = Loop.step(s2, InputRules.NONE)
	h.eq(r2["state"].ticks, t0 + 1, "step normal : tick +1")
	# Gravite auto : rien avant GRAVITY_PERIOD, descente d'exactement 1 A GRAVITY_PERIOD (borne >=).
	var s3 = State.initial(1)
	var y0: int = s3.active["pos"].y
	var cur = s3
	for i in range(P.GRAVITY_PERIOD - 1):
		cur = Loop.step(cur, InputRules.NONE)["state"]
	h.eq(cur.active["pos"].y, y0, "aucune descente auto avant GRAVITY_PERIOD")
	h.eq(cur.gravity_counter, P.GRAVITY_PERIOD - 1, "compteur incremente a chaque tick (+=)")
	cur = Loop.step(cur, InputRules.NONE)["state"]
	h.eq(cur.active["pos"].y, y0 + 1, "descente auto d'exactement 1 a GRAVITY_PERIOD")
	h.eq(cur.gravity_counter, 0, "compteur remis a zero apres descente")
	# Atterrissage : hard-drop qui complete une rangee -> verrou + nettoyage + score.
	var s4 = State.initial(1)
	s4.grid = State.empty_grid()
	for x in range(P.COLS):
		if x != 4 and x != 5:
			s4.grid[P.ROWS - 1][x] = 3
	s4.active = Collision.make_piece(1, 0, P.SPAWN)   # O -> colonnes 4 et 5
	s4.gravity_counter = 0
	var lines0: int = s4.lines_cleared
	var score0: int = s4.score
	var r4: Dictionary = Loop.step(s4, InputRules.HARD_DROP)
	var s4b = r4["state"]
	h.eq(s4b.lines_cleared, lines0 + 1, "hard-drop qui complete une rangee -> +1 ligne")
	h.eq(s4b.score, score0 + 100, "score += 100 pour un simple")
