# end_screen.test.gd — ligne render.end_screen (volet logique). L'ecran de fin est PARAMETRE
# par le statut terminal : actif seulement en fin, message distinct gagne/perdu.
extends RefCounted

const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	# --- actif uniquement en fin ---
	h.eq(EndScreen.est_actif(State.Statut.EN_COURS), false, "EN_COURS -> ecran inactif")
	h.eq(EndScreen.est_actif(State.Statut.GAGNE), true, "GAGNE -> ecran actif")
	h.eq(EndScreen.est_actif(State.Statut.PERDU), true, "PERDU -> ecran actif")

	# --- message parametre par le statut ---
	h.eq(EndScreen.message(State.Statut.GAGNE), EndScreen.MESSAGE_GAGNE, "message GAGNE")
	h.eq(EndScreen.message(State.Statut.PERDU), EndScreen.MESSAGE_PERDU, "message PERDU")
	h.eq(EndScreen.message(State.Statut.EN_COURS), "", "EN_COURS -> message vide")
	h.ok(EndScreen.MESSAGE_GAGNE != EndScreen.MESSAGE_PERDU, "victoire et defaite -> messages distincts")
