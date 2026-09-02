# wall_reflection.gd — ligne physics.wall_reflection. Reflexion sur murs lateraux et plafond
# par INVERSION STRICTE de la composante perpendiculaire. La limite BASSE n'est PAS un mur
# (elle est traitee par life_rules). Physique CONTINUE (flottants). RefCounted, pur.
# Capacite proposee hors registre : game.wall_reflection.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Faces de mur touchees (donnees, pas d'effet de bord).
const AUCUN := 0
const GAUCHE := 1
const DROITE := 2
const PLAFOND := 3

# Quelle face de mur la balle franchit-elle, compte tenu de sa vitesse ? (une seule a la fois,
# priorite laterale puis plafond ; la limite basse est explicitement exclue).
static func face_touchee(pos: Vector2, vel: Vector2) -> int:
	var r := P.BALLE_RAYON
	if pos.x - r <= 0.0 and vel.x < 0.0:
		return GAUCHE
	if pos.x + r >= P.TERRAIN_LARGEUR and vel.x > 0.0:
		return DROITE
	if pos.y - r <= 0.0 and vel.y < 0.0:
		return PLAFOND
	return AUCUN

# Vitesse apres reflexion : SEULE la composante perpendiculaire est inversee (negation
# exacte -> norme conservee bit a bit, composante parallele inchangee). Valeurs STRICTES.
static func reflechir_vitesse(vel: Vector2, face: int) -> Vector2:
	match face:
		GAUCHE, DROITE:
			return Vector2(-vel.x, vel.y)
		PLAFOND:
			return Vector2(vel.x, -vel.y)
		_:
			return vel

# Repositionne la balle exactement au contact du mur touche (jamais au-dela) : evite le
# collage. Ne touche que l'axe concerne.
static func corriger_position(pos: Vector2, face: int) -> Vector2:
	var r := P.BALLE_RAYON
	match face:
		GAUCHE:
			return Vector2(r, pos.y)
		DROITE:
			return Vector2(P.TERRAIN_LARGEUR - r, pos.y)
		PLAFOND:
			return Vector2(pos.x, r)
		_:
			return pos
