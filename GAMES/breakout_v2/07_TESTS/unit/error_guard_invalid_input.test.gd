# error_guard_invalid_input.test.gd — ligne core.error_handling. Une entree hors domaine est
# ABSORBEE en AUCUNE (jamais une exception, jamais un etat invalide).
extends RefCounted

const ErrorGuard = preload("res://05_SYSTEMS/input_rules/error_guard.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")

func run(h) -> void:
	# --- actions valides : passent inchangees ---
	h.eq(ErrorGuard.normaliser(-1), -1, "GAUCHE passe")
	h.eq(ErrorGuard.normaliser(0), 0, "AUCUNE passe")
	h.eq(ErrorGuard.normaliser(1), 1, "DROITE passe")

	# --- actions hors domaine : absorbees en AUCUNE ---
	h.eq(ErrorGuard.normaliser(2), InputRules.AUCUNE, "action inconnue 2 -> AUCUNE")
	h.eq(ErrorGuard.normaliser(-99), InputRules.AUCUNE, "action inconnue -99 -> AUCUNE")
	h.eq(ErrorGuard.normaliser(2147483647), InputRules.AUCUNE, "action extreme -> AUCUNE")

	# --- l'etat ne casse jamais : un tick avec action invalide reste valide et immobile ---
	var s = State.initial(1)
	var x0: float = s.paddle_x
	var r: Dictionary = Loop.step(s, 999)
	h.ok(r["etat"].est_valide(), "step avec action invalide -> etat structurellement valide")
	h.eq(r["etat"].paddle_x, x0, "action invalide normalisee en AUCUNE -> raquette immobile")
