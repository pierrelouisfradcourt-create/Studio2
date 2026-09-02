# restart.gd — relance par RECONSTRUCTION INTEGRALE (lignes state.restart, core.restart).
# Aucune valeur de la partie precedente ne survit, parce que RIEN n'est reutilise :
# l'etat neuf est construit par le meme constructeur que le tout premier.
#
# V2 : la CARTE est REMISE en argument, comme pour toute construction d'etat.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")


static func relancer(carte, graine: int, cadence: int = 0, reglages: Dictionary = {}) -> Object:
	return State.initial(carte, graine, cadence, reglages)


# Constate qu'aucun champ n'a fuite d'une partie a l'autre : l'etat relance est
# STRICTEMENT egal, champ par champ, a l'etat initial de meme carte et meme graine.
static func aucune_fuite(nouvel_etat: Object, carte, graine: int, cadence: int = 0, reglages: Dictionary = {}) -> bool:
	return nouvel_etat.egal_profond(State.initial(carte, graine, cadence, reglages))
