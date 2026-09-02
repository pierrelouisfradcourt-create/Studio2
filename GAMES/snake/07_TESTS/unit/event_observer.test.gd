# event_observer.test.gd — ligne arch.event_socket. Un observateur de TEST branche sur
# la liste d'evenements retournee par le tick recoit EXACTEMENT N nourriture_mangee,
# P palier_franchi et 1 fin_partie. Forme imposee : liste de Dictionary (jamais un signal).
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const DR = preload("res://05_SYSTEMS/input_rules/direction_rules.gd")
const Events = preload("res://05_SYSTEMS/game_loop/events.gd")

# Observateur de test : comptabilise par type. La logique pure ne le connait pas.
class Observateur:
	var comptes := {"nourriture_mangee": 0, "palier_franchi": 0, "fin_partie": 0}
	func absorber(evenements: Array) -> void:
		for ev in evenements:
			if comptes.has(ev["type"]):
				comptes[ev["type"]] += 1

func run(h) -> void:
	# La forme du canal est une liste de Dictionary.
	var s0 = State.initial(5)
	var r0 = Loop.step(s0, Loop.AUCUNE)
	h.ok(r0["evenements"] is Array, "les evenements sont une liste (jamais un signal)")

	var obs = Observateur.new()

	# Un tick qui mange : exactement 1 nourriture_mangee, 0 palier (fruits=1).
	var s = State.initial(5)
	s.segments = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)]
	s.longueur = 3
	s.dir_effectuee = DR.DROITE
	s.dir_en_attente = DR.DROITE
	s.nourriture = Vector2i(6, 5)
	s.fruits = 0
	var r = Loop.step(s, Loop.AUCUNE)
	obs.absorber(r["evenements"])
	h.eq(obs.comptes["nourriture_mangee"], 1, "1 evenement nourriture_mangee")
	h.eq(obs.comptes["palier_franchi"], 0, "0 palier a fruits=1")

	# Un tick qui mange ET franchit un palier (fruits 4->5).
	var s2 = State.initial(5)
	s2.segments = [Vector2i(5, 5), Vector2i(4, 5), Vector2i(3, 5)]
	s2.longueur = 3
	s2.dir_effectuee = DR.DROITE
	s2.dir_en_attente = DR.DROITE
	s2.nourriture = Vector2i(6, 5)
	s2.fruits = 4
	var r2 = Loop.step(s2, Loop.AUCUNE)
	obs.absorber(r2["evenements"])
	h.eq(obs.comptes["nourriture_mangee"], 2, "2e nourriture_mangee cumulee")
	h.eq(obs.comptes["palier_franchi"], 1, "1 palier_franchi au tick de franchissement")

	# Un tick mortel : exactement 1 fin_partie.
	var s3 = State.initial(5)
	s3.segments = [Vector2i(0, 5), Vector2i(1, 5), Vector2i(2, 5)]
	s3.longueur = 3
	s3.dir_effectuee = DR.GAUCHE
	s3.dir_en_attente = DR.GAUCHE
	s3.nourriture = Vector2i(10, 10)
	var r3 = Loop.step(s3, Loop.AUCUNE)
	obs.absorber(r3["evenements"])
	h.eq(obs.comptes["fin_partie"], 1, "1 fin_partie au tick mortel")

	# Vocabulaire ferme : les 3 types declares.
	h.eq(Events.VOCABULAIRE.size(), 3, "vocabulaire ferme de 3 evenements")
