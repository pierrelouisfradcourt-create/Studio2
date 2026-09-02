# end_screen.gd — ligne render.end_screen (volet logique). Ecran de fin PARAMETRE par le
# statut terminal : la mention differe entre GAGNE et PERDU, et ne s'affiche que sur un statut
# terminal. Logique PURE ; le pilote de scene pose les Labels. RefCounted.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

const MESSAGE_GAGNE := "Victoire !"
const MESSAGE_PERDU := "Partie perdue"

# Actif uniquement sur un statut terminal.
static func est_actif(statut: int) -> bool:
	return statut == State.Statut.GAGNE or statut == State.Statut.PERDU

# Message PARAMETRE par le statut : distinct gagne / perdu ; vide hors terminal.
static func message(statut: int) -> String:
	match statut:
		State.Statut.GAGNE:
			return MESSAGE_GAGNE
		State.Statut.PERDU:
			return MESSAGE_PERDU
		_:
			return ""
