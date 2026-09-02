# paddle.gd — ligne state.paddle. Detient la position (centre x) de la raquette et applique
# son BORNAGE au terrain. Ne lit AUCUNE touche. La raquette ne bouge que sur l'axe horizontal.
# RefCounted, pur.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Bornes du centre de la raquette : la raquette entiere reste dans le terrain.
static func borne_min() -> float:
	return P.raquette_demi_largeur()

static func borne_max() -> float:
	return P.TERRAIN_LARGEUR - P.raquette_demi_largeur()

# Borne une position de centre a l'intervalle jouable.
static func borner(x: float) -> float:
	return clampf(x, borne_min(), borne_max())

# Deplace la raquette d'un pas fixe dans une direction (-1 gauche, +1 droite, 0 immobile),
# a la vitesse max, puis borne. Latence 0 : le deplacement s'applique au meme pas.
static func deplacer(x: float, direction: int, dt: float) -> float:
	return borner(x + float(direction) * P.RAQUETTE_VITESSE_MAX * dt)
