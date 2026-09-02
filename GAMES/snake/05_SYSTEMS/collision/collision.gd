# collision.gd — ligne core.collision. Predicats PURS sur Vector2i, sans tolerance
# ni seuil, ecrits sans dimension de grille en dur (lue depuis params). RefCounted.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Vrai si la position sort du cadre carre de la grille.
static func hors_grille(pos: Vector2i) -> bool:
	return pos.x < 0 or pos.x >= P.TAILLE_GRILLE or pos.y < 0 or pos.y >= P.TAILLE_GRILLE

# Vrai si la position coincide avec l'un des segments fournis (comparaison exacte).
static func sur_corps(pos: Vector2i, segments: Array) -> bool:
	return pos in segments

# Vrai si la position coincide exactement avec la nourriture.
static func sur_nourriture(pos: Vector2i, nourriture: Vector2i) -> bool:
	return pos == nourriture
