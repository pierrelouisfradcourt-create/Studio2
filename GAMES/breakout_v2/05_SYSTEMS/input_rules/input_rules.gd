# input_rules.gd — ligne input.closed_vocabulary. Regles PURES d'entree : vocabulaire FERME
# d'actions raquette (EXACTEMENT 3), traduction en deplacement borne. Ne connait ni touche,
# ni InputEvent, ni code de touche. RefCounted, pur.
extends RefCounted

const Paddle = preload("res://05_SYSTEMS/game_state/paddle.gd")

# Vocabulaire FERME d'actions : exactement 3 valeurs.
const GAUCHE := -1
const AUCUNE := 0
const DROITE := 1
const VOCABULAIRE := [GAUCHE, AUCUNE, DROITE]

# Une action appartient-elle au vocabulaire ferme ?
static func est_action(action: int) -> bool:
	return action in VOCABULAIRE

# Traduit une action NORMALISEE (supposee du vocabulaire) en position bornee de raquette.
# La seule chose que le joueur touche est la raquette : cette fonction ne modifie ni balle,
# ni briques, ni vies, ni score.
static func appliquer(paddle_x: float, action: int, dt: float) -> float:
	return Paddle.deplacer(paddle_x, action, dt)
