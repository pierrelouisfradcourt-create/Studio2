# tick_rate.gd — ligne speed.tick_rate_curve. Fonction PURE periode(fruits) -> ms,
# sans etat propre. Bornee au plancher, non croissante, remise a l'initiale a fruits=0.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")

# Numero de palier a partir du nombre de fruits (fonction deterministe, en marches).
static func palier(fruits: int) -> int:
	return int(floor(float(fruits) / float(P.ACCELERATION_PALIER)))

# Periode d'un tick, en ms, pour un nombre de fruits donne. Saturation au plancher.
static func periode(fruits: int) -> float:
	var n := palier(fruits)
	var p := P.VITESSE_INITIALE_MS * pow(P.ACCELERATION_PAS, n)
	return max(P.PERIODE_PLANCHER_MS, p)
