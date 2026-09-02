# end_condition.gd — ligne core.end_condition. DECIDE le statut terminal : VICTOIRE ssi
# briques_restantes == 0 ; DEFAITE ssi vies == 0. Les deux issues sont mutuellement
# exclusives (la victoire prime : detruire la derniere brique gagne). RefCounted, pur.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

static func est_gagne(briques_restantes: int) -> bool:
	return briques_restantes == 0

static func est_perdu(vies: int) -> bool:
	return vies == 0

# Fige l'etat sur un statut terminal (mute un state deja clone).
static func terminer(state, statut_terminal: int) -> void:
	state.statut = statut_terminal

# Applique la regle de fin a un etat EN_COURS (mute un state deja clone). Exclusif :
# victoire testee d'abord, defaite ensuite. Sans objet si deja terminal.
static func appliquer(state) -> void:
	if state.statut != State.Statut.EN_COURS:
		return
	if est_gagne(state.briques_restantes):
		state.statut = State.Statut.GAGNE
	elif est_perdu(state.vies):
		state.statut = State.Statut.PERDU
