# end_screen.gd — ligne render.end_screen. Ecran de fin PARAMETRE par le statut terminal :
# la mention differe entre termine-perdu et termine-gagne, et le recap fige l'etat au moment
# de la fin (score, longueur). Ne s'affiche QUE sur un statut terminal. Logique PURE,
# testable en headless ; le pilote de scene pose les Labels. RefCounted.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

const MESSAGE_PERDU := "Partie perdue"
const MESSAGE_GAGNE := "Victoire !"

# L'ecran de fin est-il actif ? Uniquement sur un statut terminal.
static func est_actif(statut: int) -> bool:
	return statut == State.Statut.TERMINE_PERDU or statut == State.Statut.TERMINE_GAGNE

# Message PARAMETRE par le statut terminal. Distinct perdu / gagne ; vide hors terminal.
static func message(statut: int) -> String:
	match statut:
		State.Statut.TERMINE_PERDU:
			return MESSAGE_PERDU
		State.Statut.TERMINE_GAGNE:
			return MESSAGE_GAGNE
		_:
			return ""

# Recap fige de l'etat de fin (lu, jamais recalcule). Reflet STRICT de l'etat expose.
static func recap(state) -> Dictionary:
	return {
		"score": state.score,
		"longueur": state.longueur,
		"statut": state.statut,
	}
