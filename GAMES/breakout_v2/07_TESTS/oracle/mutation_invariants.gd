# mutation_invariants.gd — oracle (test) de la ligne proof.mutation_gate. Le gate a MUTATION
# reel est execute par le DRIVER (forge.mutation.run_mutation_test) sur la logique pure. Ce
# script re-asserte, en un seul point headless, les INVARIANTS CRITIQUES que tout mutant doit
# tuer : inversion stricte aux murs, angle raquette au centre (vx'==0), destruction de brique,
# decrement de vie, victoire (0 brique), defaite (0 vie), pas de temps fixe non contournable.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Wall = preload("res://05_SYSTEMS/wall_collision/wall_reflection.gd")
const PaddleDefl = preload("res://05_SYSTEMS/paddle_rebound/paddle_deflection.gd")
const Brick = preload("res://05_SYSTEMS/brick_collision/brick_collision.gd")
const BrickField = preload("res://05_SYSTEMS/game_state/brick_field.gd")
const Life = preload("res://05_SYSTEMS/life_rules/life_rules.gd")
const End = preload("res://05_SYSTEMS/game_state/end_condition.gd")
const FixedStep = preload("res://05_SYSTEMS/physics_step/fixed_step.gd")

func _initialize() -> void:
	var f: Array = []

	# inversion stricte aux murs
	if Wall.reflechir_vitesse(Vector2(5.0, -3.0), Wall.GAUCHE) != Vector2(-5.0, -3.0):
		f.append("mur GAUCHE n'inverse pas vx strictement")
	if Wall.reflechir_vitesse(Vector2(5.0, -3.0), Wall.PLAFOND) != Vector2(5.0, 3.0):
		f.append("mur PLAFOND n'inverse pas vy strictement")

	# angle raquette au centre : vx' == 0.0
	if PaddleDefl.deflechir(Vector2(0.0, 300.0), 0.0).x != 0.0:
		f.append("rebond raquette au centre : vx' != 0")

	# destruction de brique : -1 exact
	var s = State.initial(1)
	var avant: int = s.briques_restantes
	if not BrickField.detruire(s, 0) or s.briques_restantes != avant - 1:
		f.append("destruction de brique : compte non -1")

	# decrement de vie
	var sl = State.initial(1)
	sl.ball_pos = Vector2(320.0, P.TERRAIN_HAUTEUR + P.BALLE_RAYON + 5.0)
	var v0: int = sl.vies
	if not Life.perdre_et_servir(sl) or sl.vies != v0 - 1:
		f.append("perte de vie : compte non -1")

	# victoire ssi 0 brique ; defaite ssi 0 vie
	var g = State.initial(1); g.briques_restantes = 0; End.appliquer(g)
	if g.statut != State.Statut.GAGNE:
		f.append("0 brique -> pas GAGNE")
	var p = State.initial(1); p.vies = 0; End.appliquer(p)
	if p.statut != State.Statut.PERDU:
		f.append("0 vie -> pas PERDU")

	# pas de temps fixe non contournable
	if FixedStep.dt() != P.dt_s():
		f.append("pas de temps fixe != params.dt_s()")

	print("ORACLE mutation_invariants: %s" % ("PASS" if f.is_empty() else "FAIL"))
	for x in f:
		print("  FAIL: ", x)
	quit(0 if f.is_empty() else 1)
