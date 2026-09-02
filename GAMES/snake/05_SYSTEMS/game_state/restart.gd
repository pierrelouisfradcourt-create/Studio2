# restart.gd — ligne core.restart. Reconstruit un etat initial neuf. Aucun champ de
# l'etat de partie ne survit d'une partie a l'autre : le meilleur score ne fait PAS
# partie de l'etat de partie (unique valeur qui perdure, hors de cet etat). RefCounted.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

# Relance : renvoie un etat initial neuf, deterministe pour une graine donnee.
# Ne lit ni ne recopie aucun champ de l'ancienne partie.
static func relancer(seed_val: int) -> Object:
	return State.initial(seed_val)
