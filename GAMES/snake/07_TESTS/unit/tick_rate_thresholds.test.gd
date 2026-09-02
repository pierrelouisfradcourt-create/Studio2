# tick_rate_thresholds.test.gd — ligne speed.tick_rate_curve. Table de valeurs STRICTES
# de part et d'autre de chaque palier, saturation STRICTE au plancher, monotonie non
# croissante (compte de violations = 0), premier tick = periode initiale.
extends RefCounted

const TickRate = preload("res://05_SYSTEMS/tick_rate/tick_rate.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

func run(h) -> void:
	# Premier tick de toute partie : periode STRICTEMENT egale a la periode initiale.
	h.eq(TickRate.periode(0), P.VITESSE_INITIALE_MS, "periode(0) = vitesse initiale")
	# Palier tous les 5 fruits : juste avant / au seuil / juste apres.
	h.eq(TickRate.periode(4), 200.0, "periode(4) = 200 (palier 0)")
	h.ok(is_equal_approx(TickRate.periode(5), 184.0), "periode(5) = 184 (palier 1)")
	h.ok(is_equal_approx(TickRate.periode(9), 184.0), "periode(9) = 184 (encore palier 1)")
	h.ok(is_equal_approx(TickRate.periode(10), 169.28), "periode(10) = 169.28 (palier 2)")
	h.ok(is_equal_approx(TickRate.periode(15), 155.7376), "periode(15) = 155.7376 (palier 3)")
	h.ok(is_equal_approx(TickRate.periode(20), 143.278592), "periode(20) = 143.278592 (palier 4)")
	# Numeros de palier stricts.
	h.eq(TickRate.palier(0), 0, "palier(0) = 0")
	h.eq(TickRate.palier(4), 0, "palier(4) = 0")
	h.eq(TickRate.palier(5), 1, "palier(5) = 1")
	h.eq(TickRate.palier(54), 10, "palier(54) = 10")
	h.eq(TickRate.palier(55), 11, "palier(55) = 11")
	# Saturation STRICTE au plancher : atteint a 55 fruits, jamais en-dessous.
	h.eq(TickRate.periode(55), P.PERIODE_PLANCHER_MS, "periode(55) = plancher 80")
	h.eq(TickRate.periode(100), P.PERIODE_PLANCHER_MS, "periode(100) = plancher 80")
	h.eq(TickRate.periode(1000), P.PERIODE_PLANCHER_MS, "periode(1000) = plancher 80")
	# Juste avant le plancher : STRICTEMENT au-dessus de 80.
	h.ok(TickRate.periode(50) > P.PERIODE_PLANCHER_MS, "periode(50) > plancher")
	# Monotonie NON CROISSANTE : nombre de ticks ou periode(t+1) > periode(t) = 0.
	var violations := 0
	for t in range(0, 120):
		if TickRate.periode(t + 1) > TickRate.periode(t):
			violations += 1
	h.eq(violations, 0, "monotonie non croissante (0 violation sur 120 fruits)")
