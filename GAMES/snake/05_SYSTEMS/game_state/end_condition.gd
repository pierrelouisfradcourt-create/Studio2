# end_condition.gd — ligne core.end_condition. Decide le statut terminal
# (perdu par collision / gagne par cible atteinte) et gele l'etat. RefCounted, pur.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

# La longueur atteint-elle la cible de victoire ? (egalite ou depassement de la cible).
static func est_gagne(longueur: int) -> bool:
	return longueur >= P.CIBLE_VICTOIRE

# Fige l'etat sur un statut terminal (mute state deja clone).
static func terminer(state, statut_terminal: int) -> void:
	state.statut = statut_terminal
