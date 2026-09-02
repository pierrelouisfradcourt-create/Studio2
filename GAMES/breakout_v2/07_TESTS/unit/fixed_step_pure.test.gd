# fixed_step_pure.test.gd — ligne physics.fixed_timestep. Le pas est une CONSTANTE nommee
# derivee de params, jamais une horloge : dt() == P.dt_s() EXACTEMENT, et est stable entre
# deux appels (aucune dependance temps/framerate).
extends RefCounted

const FixedStep = preload("res://05_SYSTEMS/physics_step/fixed_step.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	h.eq(FixedStep.dt(), P.dt_s(), "dt() == params.dt_s() (unique porteur du pas)")
	h.eq(FixedStep.dt(), P.TICK_DT_FIXED_MS / 1000.0, "dt() == TICK_DT_FIXED_MS/1000 (nomme)")
	# Stabilite : deux lectures consecutives strictement identiques (aucune horloge).
	h.eq(FixedStep.dt(), FixedStep.dt(), "dt() stable entre deux appels")
	# Positif et non nul (un pas nul figerait la simulation).
	h.eq(FixedStep.dt() > 0.0, true, "dt() strictement positif")
