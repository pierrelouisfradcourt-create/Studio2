# loop.gd — ligne core.game_loop. Le TICK PUR : step(etat, intention) -> {state, events}.
# SEUL orchestrateur (INV-6) : il ORDONNE les systemes sur un tick, il n'implemente aucune regle.
# Ordre canonique : entree -> gravite auto -> (verrou -> nettoyage -> score -> spawn suivant).
# Ne mute JAMAIS l'entree (clone d'abord). RefCounted (logique pure, aucune horloge).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")
const Gravity = preload("res://05_SYSTEMS/gravity/gravity.gd")
const Lock = preload("res://05_SYSTEMS/lock_rules/lock.gd")
const LineClear = preload("res://05_SYSTEMS/line_clear/line_clear.gd")
const Scoring = preload("res://05_SYSTEMS/scoring/scoring.gd")

static func step(state, intent: int) -> Dictionary:
	var s = state.clone()
	if s.status != State.Statut.EN_COURS:
		return {"state": s, "events": []}
	var events: Array = []

	# (1) Entree : appliquee a la SEULE piece active (la pile n'est jamais touchee).
	var res: Dictionary = InputRules.move_active_piece(s.grid, s.active, intent)
	s.active = res["piece"]
	var landed: bool = res["landed"]

	# (2) Gravite AUTO : la piece descend d'une case tous les GRAVITY_PERIOD ticks, sauf si un
	# hard-drop l'a deja fait atterrir ce tick.
	if not landed:
		s.gravity_counter += 1
		if s.gravity_counter >= P.GRAVITY_PERIOD:
			s.gravity_counter = 0
			var g: Dictionary = Gravity.apply_gravity(s.grid, s.active)
			s.active = g["piece"]
			landed = g["landed"]

	# (3) Atterrissage : verrou -> nettoyage -> score -> apparition de la piece suivante.
	if landed:
		s.grid = Lock.lock_piece(s.grid, s.active)
		var lc: Dictionary = LineClear.clear_lines(s.grid)
		s.grid = lc["grid"]
		var n: int = lc["cleared"]
		s.lines_cleared += n
		s.score += Scoring.score_for(n)
		events.append({"kind": "lock"})
		if n > 0:
			events.append({"kind": "clear", "lines": n})
		s.gravity_counter = 0
		var ok: bool = s.spawn_piece(s.next_type())
		if not ok:
			events.append({"kind": "game_over"})

	s.ticks += 1
	return {"state": s, "events": events}
