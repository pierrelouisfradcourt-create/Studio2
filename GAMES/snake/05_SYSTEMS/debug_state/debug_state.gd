# debug_state.gd — ligne debug.state_projection. Projection PURE de l'etat DEJA tenu
# vers le dictionnaire du point d'observation. EXACTEMENT 7 grandeurs decisives, rien
# d'invente, aucune structure parallele. RefCounted.
extends RefCounted

# Renvoie EXACTEMENT les 7 champs decisifs. meilleur_score est fourni de l'exterieur
# (il ne fait pas partie de l'etat de partie).
static func projeter(state, meilleur_score: int) -> Dictionary:
	return {
		"longueur": state.longueur,
		"score": state.score,
		"meilleur_score": meilleur_score,
		"tete": state.segments[0],
		"nourriture": state.nourriture,
		"periode": state.periode,
		"statut": state.statut,
	}
