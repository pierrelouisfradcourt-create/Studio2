# pause.gd — ligne pause.state. Transitions en-cours <-> en-pause dans la machine a
# etats PURE. Aucune horloge, aucun arret de rendu, aucun rattrapage. RefCounted.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

# Bascule pause. Mute state deja clone. N'agit que sur un statut non terminal :
# EN_COURS <-> EN_PAUSE, et ne touche a AUCUN autre champ.
static func basculer(state) -> void:
	if state.statut == State.Statut.EN_COURS:
		state.statut = State.Statut.EN_PAUSE
	elif state.statut == State.Statut.EN_PAUSE:
		state.statut = State.Statut.EN_COURS
