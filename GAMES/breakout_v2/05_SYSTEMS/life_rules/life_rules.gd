# life_rules.gd — ligne life.loss_and_serve. Perte de vie a la sortie basse du terrain et
# remise en jeu d'une balle s'il reste des vies. Ne dessine rien, ne lit aucune touche.
# RefCounted, pur. Capacite proposee hors registre : game.lives.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Ball = preload("res://05_SYSTEMS/game_state/ball.gd")

# La balle a-t-elle franchi la LIMITE BASSE (sous la raquette) ? La limite basse n'est jamais
# un mur : elle ne reflechit pas, elle coute une vie.
static func balle_perdue(pos: Vector2) -> bool:
	return pos.y - P.BALLE_RAYON > P.TERRAIN_HAUTEUR

# Applique la perte de vie (mute un state deja clone). Decremente de EXACTEMENT 1 ; si des
# vies restent, remet une balle a l'etat de SERVICE ; sinon aucune balle n'est remise en jeu.
# Renvoie true si une vie a ete perdue.
static func perdre_et_servir(state) -> bool:
	if not balle_perdue(state.ball_pos):
		return false
	state.vies -= 1
	if state.vies > 0:
		state.ball_pos = Ball.position_service()
		state.ball_vel = Ball.vitesse_service()
	return true
