# ball.gd — ligne state.ball. Detient la cinematique PURE de la balle (position et vitesse,
# flottants a deux composantes) et le service. Ne decide d'AUCUN rebond. RefCounted.
#
# Le joueur n'agit JAMAIS sur la balle : aucune fonction d'entree ne vit ici (invariant du
# charter, verifie par ball_kinematics.test.gd : le vocabulaire d'entree ne touche pas la balle).
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Position de service : centre du terrain.
static func position_service() -> Vector2:
	return Vector2(P.TERRAIN_LARGEUR / 2.0, P.TERRAIN_HAUTEUR / 2.0)

# Vitesse de service : vers le BAS, a la vitesse initiale (constante toute la partie, V1).
static func vitesse_service() -> Vector2:
	return Vector2(0.0, P.BALLE_VITESSE_INITIALE)

# Avance la balle d'un pas de temps fixe SANS collision : p' = p + v * dt.
# Expression PARTAGEE avec ball_kinematics.test.gd et integrate.gd -> egalite flottante
# stricte exacte (meme suite d'operations IEEE754).
static func pas_libre(pos: Vector2, vel: Vector2, dt: float) -> Vector2:
	return pos + vel * dt
