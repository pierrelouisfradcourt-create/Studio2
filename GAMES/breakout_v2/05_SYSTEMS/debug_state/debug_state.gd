# debug_state.gd — ligne debug.observation_point. Projection PURE de l'etat DEJA tenu vers le
# dictionnaire du point d'observation. EXACTEMENT les 6 champs nommes par le charter (position
# balle, vitesse balle, position raquette, briques restantes, vies restantes, statut). Aucune
# structure parallele : ne detient rien que game_state ne detienne deja. RefCounted.
extends RefCounted

# Renvoie EXACTEMENT les 6 champs decisifs, sans effet de bord (deux lectures consecutives
# sans tick renvoient des valeurs strictement identiques).
static func projeter(state) -> Dictionary:
	return {
		"balle_pos": state.ball_pos,
		"balle_vel": state.ball_vel,
		"raquette_x": state.paddle_x,
		"briques_restantes": state.briques_restantes,
		"vies": state.vies,
		"statut": state.statut,
	}
