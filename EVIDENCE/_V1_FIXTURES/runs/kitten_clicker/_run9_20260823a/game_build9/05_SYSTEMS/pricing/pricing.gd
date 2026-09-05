# pricing.gd — LOGIQUE PURE (category system, allowed_deps []).
# Source UNIQUE de la courbe de couts. Deux courbes DISTINCTES (chatons vs ameliorations)
# pour que le point de decision porte des trajectoires de cout divergentes. La courbe des
# paliers porte >= 3 valeurs distinctes et strictement croissantes (regle de variance
# ratifiee Pierre 2026-07-21). Aucun cout n'est recopie ailleurs.
extends RefCounted

# --- parametres de gameplay ISOLES (garde-fou (d)) --------------------------------
const KITTEN_BASE: int = 5      # cout du 1er chaton
const KITTEN_STEP: int = 5      # increment par chaton adopte
const UPGRADE_BASE: int = 8     # cout de la 1ere amelioration
const UPGRADE_STEP: int = 4     # increment par niveau d'amelioration

# Cout d'adoption du (n+1)-eme chaton, n = nombre deja adopte. Strictement croissant.
static func kitten_cost(n: int) -> int:
	return KITTEN_BASE + KITTEN_STEP * n

# Cout de l'amelioration au niveau `level` (0 = premiere). Courbe DISTINCTE de kitten_cost.
static func upgrade_cost(level: int) -> int:
	return UPGRADE_BASE + UPGRADE_STEP * level

# Les 3 premiers couts de palier (adoption) : >= 3 valeurs distinctes strictement
# croissantes. C'est la courbe que le bot de solvabilite doit gravir jusqu'au 3e palier.
static func paliers() -> Array:
	return [kitten_cost(0), kitten_cost(1), kitten_cost(2)]

# Combien de paliers de la courbe portent une valeur DISTINCTE (mesure de variance) :
# vaut 3 par construction (5, 10, 15), jamais 1 — une courbe plate serait un mensonge.
static func distinct_paliers() -> int:
	var seen: Array = []
	for c in paliers():
		if not seen.has(c):
			seen.append(c)
	return seen.size()
