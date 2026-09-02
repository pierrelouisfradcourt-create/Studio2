# status.gd — statut de partie dans un vocabulaire ferme de trois valeurs
# (ligne state.status). Traduit l'issue calculee par end_conditions en statut de
# game_state : un seul endroit ou cette traduction existe.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const End = preload("res://05_SYSTEMS/end_conditions/end_conditions.gd")

# Correspondance issue -> statut, exhaustive par construction.
const CORRESPONDANCE: Dictionary = {
	End.Issue.EN_COURS: State.Statut.EN_COURS,
	End.Issue.GAGNE: State.Statut.GAGNE,
	End.Issue.PERDU: State.Statut.PERDU,
}


static func calculer(vies: int, consommees: int, total_pose: int) -> int:
	return CORRESPONDANCE[End.issue(vies, consommees, total_pose)]


# Applique le statut a l'etat. Appele a CHAQUE fin de tick ET apres la derniere
# iteration de la boucle : aucun chemin de sortie ne laisse la partie sans statut.
static func appliquer(s) -> int:
	s.statut = calculer(s.vies, s.consommees, s.total_pose)
	return s.statut


static func est_terminal(statut: int) -> bool:
	return statut == State.Statut.GAGNE or statut == State.Statut.PERDU


static func nom(statut: int) -> String:
	if statut == State.Statut.GAGNE:
		return "GAGNE"
	if statut == State.Statut.PERDU:
		return "PERDU"
	return "EN COURS"
