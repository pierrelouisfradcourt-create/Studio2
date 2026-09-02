# loop.gd — ligne core.main_loop. Le TICK PUR : step(etat, action) -> {etat, evenements}.
# extends RefCounted, jamais Node. Aucune I/O, aucune horloge, aucun alea non seede, aucune
# API de presentation. Ne mute JAMAIS l'entree (clone d'abord). SEUL systeme pur qui compose
# les autres. Capacite : game.loop.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const FixedStep = preload("res://05_SYSTEMS/physics_step/fixed_step.gd")
const Integrate = preload("res://05_SYSTEMS/physics_step/integrate.gd")
const Wall = preload("res://05_SYSTEMS/wall_collision/wall_reflection.gd")
const Brick = preload("res://05_SYSTEMS/brick_collision/brick_collision.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")
const PaddleDefl = preload("res://05_SYSTEMS/paddle_rebound/paddle_deflection.gd")
const Score = preload("res://05_SYSTEMS/game_state/score.gd")
const Life = preload("res://05_SYSTEMS/life_rules/life_rules.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input_rules.gd")
const ErrorGuard = preload("res://05_SYSTEMS/input_rules/error_guard.gd")
const EndCondition = preload("res://05_SYSTEMS/game_state/end_condition.gd")
const Events = preload("res://05_SYSTEMS/game_loop/events.gd")

const AUCUNE := InputRules.AUCUNE

# La balle est-elle en contact avec la raquette ce pas (descend et atteint le plan raquette,
# a portee horizontale) ?
static func _touche_raquette(s) -> bool:
	if s.ball_vel.y <= 0.0:
		return false
	var ry := P.raquette_y()
	var r := P.BALLE_RAYON
	if s.ball_pos.y + r < ry:
		return false
	if s.ball_pos.y - r > ry + P.RAQUETTE_HAUTEUR:
		return false
	var hw := P.raquette_demi_largeur()
	return abs(s.ball_pos.x - s.paddle_x) <= hw + r

# Tick pur. Ordre : entree -> integration -> murs -> briques -> raquette -> vie -> fin.
static func step(state, action: int) -> Dictionary:
	var s = state.clone()
	if s.statut != State.Statut.EN_COURS:
		return {"etat": s, "evenements": []}
	var events: Array = []
	var dt: float = FixedStep.dt()

	# (0) Entree : normalisee puis appliquee a la SEULE raquette (latence 0).
	var act: int = ErrorGuard.normaliser(action)
	s.paddle_x = InputRules.appliquer(s.paddle_x, act, dt)

	# (1) Integration de la balle (physique continue, pas fixe).
	s.ball_pos = Integrate.integrer(s.ball_pos, s.ball_vel, dt)

	# (2) Murs lateraux / plafond : inversion stricte de la composante perpendiculaire.
	var face_mur: int = Wall.face_touchee(s.ball_pos, s.ball_vel)
	if face_mur != Wall.AUCUN:
		s.ball_vel = Wall.reflechir_vitesse(s.ball_vel, face_mur)
		s.ball_pos = Wall.corriger_position(s.ball_pos, face_mur)
		events.append(Events.rebond_mur(face_mur))

	# (3) Briques : au plus UNE detruite ce tick, rebond dans le meme tick.
	var col: Dictionary = Brick.resoudre(s.bricks, s.start_y, s.ball_pos, s.ball_vel)
	if col["hit"]:
		BrickField.detruire(s, col["index"])
		s.ball_vel = col["vel"]
		s.ball_pos = col["pos"]
		s.score = Score.recalculer(s)
		events.append(Events.brique_detruite(col["index"]))

	# (4) Raquette : angle fonction du point d'impact ; la balle repart vers le haut.
	if _touche_raquette(s):
		var offset: float = PaddleDefl.offset_relatif(s.ball_pos.x, s.paddle_x)
		s.ball_vel = PaddleDefl.deflechir(s.ball_vel, offset)
		s.ball_pos = Vector2(s.ball_pos.x, P.raquette_y() - P.BALLE_RAYON)
		events.append(Events.rebond_raquette(offset))

	# (5) Vie : perte a la sortie basse, remise en jeu s'il reste des vies.
	if Life.perdre_et_servir(s):
		events.append(Events.vie_perdue(s.vies))

	# (6) Fin de partie : victoire ssi 0 brique, defaite ssi 0 vie (exclusifs).
	var avant: int = s.statut
	EndCondition.appliquer(s)
	if avant == State.Statut.EN_COURS and s.statut != State.Statut.EN_COURS:
		events.append(Events.fin_partie(s.statut))

	# (7) Un tick de plus.
	s.ticks += 1
	return {"etat": s, "evenements": events}
