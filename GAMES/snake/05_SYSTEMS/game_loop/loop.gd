# loop.gd — ligne core.main_loop. Le TICK PUR : step(etat, action) -> {etat, evenements}.
# extends RefCounted, jamais Node. Aucune I/O, aucune horloge, aucun alea non seede,
# aucune API de presentation. Ne mute JAMAIS l'entree (clone d'abord).
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Collision = preload("res://05_SYSTEMS/collision/collision.gd")
const DirectionRules = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const EndCondition = preload("res://05_SYSTEMS/game_state/end_condition.gd")
const Growth = preload("res://05_SYSTEMS/game_loop/growth.gd")
const Events = preload("res://05_SYSTEMS/game_loop/events.gd")

# action : une direction du vocabulaire ferme (demande d'entree), ou Vector2i(0,0) pour
# "aucune entree". Le tick applique d'abord la demande, puis avance.
const AUCUNE := Vector2i(0, 0)

static func step(state, action: Vector2i) -> Dictionary:
	var s = state.clone()
	# Etat gele (pause ou terminal) : 0 tick, aucun evenement, AUCUNE mutation — pas meme
	# la prise en compte d'une entree (pause strictement neutre : etat egal a la reprise).
	if s.statut != State.Statut.EN_COURS:
		return {"etat": s, "evenements": []}
	# (0) Applique la demande d'entree (validee vs direction EFFECTUEE) : profondeur 1.
	if action != AUCUNE:
		DirectionRules.demander(s, action)
	# (1) Promotion de la direction en attente en direction effectuee.
	s.dir_effectuee = DirectionRules.direction_du_tick(s)
	s.dir_en_attente = s.dir_effectuee
	var events: Array = []
	# (2) Avance la tete.
	var new_head: Vector2i = s.segments[0] + s.dir_effectuee
	# (3a) Collision mur -> fin de partie ce tick.
	if Collision.hors_grille(new_head):
		EndCondition.terminer(s, State.Statut.TERMINE_PERDU)
		events.append(Events.fin_partie(s.statut))
		s.ticks += 1
		return {"etat": s, "evenements": events}
	# (4-lecture) La tete atteint-elle la nourriture ? (decide si la queue se libere)
	var mange: bool = Collision.sur_nourriture(new_head, s.nourriture)
	# (3b) Collision corps. La case que la queue LIBERE ce tick ne tue pas (sauf croissance).
	var corps_a_verifier: Array = s.segments.duplicate()
	if not mange:
		corps_a_verifier.pop_back()
	if Collision.sur_corps(new_head, corps_a_verifier):
		EndCondition.terminer(s, State.Statut.TERMINE_PERDU)
		events.append(Events.fin_partie(s.statut))
		s.ticks += 1
		return {"etat": s, "evenements": events}
	# (avance) Insere la nouvelle tete.
	s.segments.insert(0, new_head)
	if mange:
		# Croissance : queue conservee. Score/fruits/periode/spawn resolus au meme tick.
		var ev_manger: Array = Growth.manger(s)
		for e in ev_manger:
			events.append(e)
		s.longueur = s.segments.size()
		if EndCondition.est_gagne(s.longueur):
			EndCondition.terminer(s, State.Statut.TERMINE_GAGNE)
			events.append(Events.fin_partie(s.statut))
	else:
		# Pas de nourriture : la queue se retire.
		s.segments.pop_back()
		s.longueur = s.segments.size()
	# (5) Un tick de plus.
	s.ticks += 1
	return {"etat": s, "evenements": events}
