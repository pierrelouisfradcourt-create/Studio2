# end_screen.test.gd — ligne render.end_screen. L'ecran de fin est PARAMETRE par le statut
# terminal (mention differente perdu/gagne), ne s'affiche que sur un statut terminal, et son
# recap reflete STRICTEMENT l'etat fige. Testable en headless.
extends RefCounted

const ES = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	# Message parametre par le statut : perdu != gagne, tous deux non vides.
	h.ok(ES.message(State.Statut.TERMINE_PERDU) != ES.message(State.Statut.TERMINE_GAGNE), "perdu != gagne")
	h.ok(ES.message(State.Statut.TERMINE_PERDU) != "", "message perdu non vide")
	h.ok(ES.message(State.Statut.TERMINE_GAGNE) != "", "message gagne non vide")
	h.eq(ES.message(State.Statut.EN_COURS), "", "aucun message hors terminal")
	# Actif UNIQUEMENT sur statut terminal.
	h.ok(ES.est_actif(State.Statut.TERMINE_PERDU), "actif sur perdu")
	h.ok(ES.est_actif(State.Statut.TERMINE_GAGNE), "actif sur gagne")
	h.ok(not ES.est_actif(State.Statut.EN_COURS), "inactif en cours")
	h.ok(not ES.est_actif(State.Statut.EN_PAUSE), "inactif en pause")
	# Recap reflete STRICTEMENT l'etat fige.
	var s = State.initial(2)
	s.score = 13
	s.longueur = 9
	s.statut = State.Statut.TERMINE_GAGNE
	var r = ES.recap(s)
	h.eq(r["score"], 13, "recap score strict")
	h.eq(r["longueur"], 9, "recap longueur stricte")
	h.eq(r["statut"], State.Statut.TERMINE_GAGNE, "recap statut strict")
