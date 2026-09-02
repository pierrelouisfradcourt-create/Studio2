# restart.gd — ligne core.restart. Reconstruit un etat initial neuf, deterministe pour une
# graine donnee. Aucun champ de l'ancienne partie ne survit (aucun residu). RefCounted, pur.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

static func relancer(seed_val: int) -> Object:
	return State.initial(seed_val)
