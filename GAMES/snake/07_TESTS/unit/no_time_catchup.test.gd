# no_time_catchup.test.gd — ligne runtime.loop_no_catchup. Apres une privation d'execution
# de duree D (0,1 s / 5 s / 60 s) OU une pause de duree quelconque, le nombre de ticks
# appliques est BORNE (au plus 1), jamais D/periode. Assertions STRICTES, aucune tolerance.
extends RefCounted

const RL = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	var periode := P.VITESSE_INITIALE_MS  # 200 ms
	# D = 0,1 s : sous le seuil d'un tick -> 0 tick.
	h.eq(RL.avancer(0.0, 100.0, periode, false)["ticks"], 0, "D=0,1s sous periode -> 0 tick")
	# D = 5 s : rattrapage naif = 25 ticks ; sans rattrapage -> EXACTEMENT 1.
	h.eq(RL.avancer(0.0, 5000.0, periode, false)["ticks"], 1, "D=5s -> 1 tick (pas 25)")
	# D = 60 s : rattrapage naif = 300 ticks ; sans rattrapage -> EXACTEMENT 1.
	h.eq(RL.avancer(0.0, 60000.0, periode, false)["ticks"], 1, "D=60s -> 1 tick (pas 300)")
	# Le surplus d'accumulateur est JETE (remis a 0), jamais banque.
	h.eq(RL.avancer(0.0, 60000.0, periode, false)["accumulateur"], 0.0, "surplus jete -> accumulateur 0")
	# Pause de duree quelconque : 0 tick, accumulateur inchange (reprise neutre).
	h.eq(RL.avancer(50.0, 5000.0, periode, true)["ticks"], 0, "pause -> 0 tick")
	h.eq(RL.avancer(50.0, 5000.0, periode, true)["accumulateur"], 50.0, "pause -> accumulateur fige")
	# Au PLANCHER de periode : le seuil atteint donne toujours EXACTEMENT 1 tick.
	h.eq(RL.avancer(0.0, P.PERIODE_PLANCHER_MS, P.PERIODE_PLANCHER_MS, false)["ticks"], 1, "au plancher -> 1 tick au seuil")
