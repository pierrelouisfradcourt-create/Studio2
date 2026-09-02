# interception_bot.gd — ligne proof.solvability_interception. Bot d'INTERCEPTION REELLE : il
# PREDIT ou la balle croisera le plan de la raquette (reflexions laterales pliees) et pilote
# la raquette par le MEME canal d'entree public que le clavier (-1/0/+1), en VISANT la balle
# vers les briques restantes pour reellement GAGNER (pas un placement statique chanceux).
# RefCounted, pur, deterministe : aucune horloge, aucun alea.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Paddle = preload("res://05_SYSTEMS/game_state/paddle.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")

# Predit le x ou la balle atteindra le plan y=py, en PLIANT les reflexions sur les murs
# lateraux (onde triangulaire dans [r, W-r]). Determinisme pur (geometrie, pas de simulation).
static func predire_x(bx: float, by: float, vx: float, vy: float, py: float) -> float:
	if vy <= 0.0:
		return bx
	var t: float = (py - by) / vy
	var x: float = bx + vx * t
	var lo: float = P.BALLE_RAYON
	var hi: float = P.TERRAIN_LARGEUR - P.BALLE_RAYON
	var span: float = hi - lo
	if span <= 0.0:
		return bx
	var u: float = fposmod(x - lo, 2.0 * span)
	if u > span:
		u = 2.0 * span - u
	return lo + u

# Centre x de la colonne la PLUS A GAUCHE ayant encore au moins une brique. Vise cette
# colonne : en la martelant on la vide de bas en haut, puis la cible glisse vers la droite —
# balayage deterministe qui clot tout le champ (evite le puits symetrique centre-colonne).
static func cible_briques(state) -> float:
	for colonne in range(P.GRILLE_COLONNES):
		for rangee in range(P.GRILLE_RANGEES):
			var idx := BrickField.index(rangee, colonne)
			if idx < state.bricks.size() and state.bricks[idx]:
				return (float(colonne) + 0.5) * P.BRIQUE_LARGEUR
	return P.TERRAIN_LARGEUR / 2.0

# Action a jouer ce tick : place la raquette pour que le point d'impact envoie la balle vers
# la colonne cible. Renvoie une action du vocabulaire ferme.
static func choisir_action(state) -> int:
	var py: float = P.raquette_y()
	var cible_x: float = predire_x(state.ball_pos.x, state.ball_pos.y, state.ball_vel.x, state.ball_vel.y, py)
	var hw: float = P.raquette_demi_largeur()
	# Offset voulu au contact (-1..1) pour diriger la balle vers la colonne cible.
	var brique_x: float = cible_briques(state)
	var offset: float = clampf((brique_x - cible_x) / (P.TERRAIN_LARGEUR / 2.0), -0.6, 0.6)
	# Position de raquette telle que la balle frappe a cet offset : paddle = impact - offset*hw.
	var raquette_voulue: float = clampf(cible_x - offset * hw, Paddle.borne_min(), Paddle.borne_max())
	var ecart: float = raquette_voulue - state.paddle_x
	var pas_max: float = P.RAQUETTE_VITESSE_MAX * P.dt_s()
	if ecart > pas_max * 0.25:
		return InputRules.DROITE
	if ecart < -pas_max * 0.25:
		return InputRules.GAUCHE
	return InputRules.AUCUNE
