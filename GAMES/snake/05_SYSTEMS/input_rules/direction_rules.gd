# direction_rules.gd — ligne core.direction_rules. Vocabulaire ferme de directions +
# garde de demi-tour + champ unique "direction demandee" ecrasable (profondeur 1, PAS
# une file). RefCounted, pur, ne connait ni touche ni Input.
extends RefCounted

const HAUT := Vector2i(0, -1)
const BAS := Vector2i(0, 1)
const GAUCHE := Vector2i(-1, 0)
const DROITE := Vector2i(1, 0)
const DIRECTIONS := [HAUT, BAS, GAUCHE, DROITE]

# Une direction est-elle du vocabulaire ferme ?
static func est_direction(d: Vector2i) -> bool:
	return d in DIRECTIONS

# Demi-tour = direction OPPOSEE. Compare a la DERNIERE DIRECTION EFFECTUEE, jamais
# a une direction en attente (contrainte 8, ratifiee Pierre 2026-07-28).
static func est_demi_tour(nouvelle: Vector2i, dir_effectuee: Vector2i) -> bool:
	return nouvelle == -dir_effectuee

# Applique une demande de direction a l'etat (mute state deja clone).
# Ecrase dir_en_attente (profondeur 1). Ignore : hors vocabulaire, ou demi-tour.
# Renvoie true si la demande a ete retenue.
static func demander(state, d: Vector2i) -> bool:
	if not est_direction(d):
		return false
	if est_demi_tour(d, state.dir_effectuee):
		return false
	state.dir_en_attente = d
	return true

# Direction a appliquer au prochain tick : la direction en attente si elle n'est pas
# un demi-tour de la direction effectuee, sinon on continue tout droit.
static func direction_du_tick(state) -> Vector2i:
	if est_demi_tour(state.dir_en_attente, state.dir_effectuee):
		return state.dir_effectuee
	return state.dir_en_attente
