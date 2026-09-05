# upgrades.gd — LOGIQUE PURE (category system, allowed_deps [world_content]).
# Detient le niveau d'amelioration de la pelote et applique son effet : chaque amelioration
# DOUBLE la valeur du clic (multiplicateur 2^niveau). Proprietaire unique de l'effet
# d'amelioration sur le rendement du clic. Le delta de gain APRES achat est STRICTEMENT
# superieur (jamais un >= tautologique) tant que le multiplicateur croit.
extends RefCounted

static func level(state: Dictionary) -> int:
	return int(state["upgrade_level"])

# Achete une amelioration : incremente le niveau. N'applique aucun cout (orchestre par
# l'input_adapter). Rend le nouveau niveau.
static func buy(state: Dictionary) -> int:
	state["upgrade_level"] = level(state) + 1
	return level(state)

# Multiplicateur de la valeur du clic : DOUBLE a chaque niveau. Niveau 0 -> x1.
static func click_multiplier(state: Dictionary) -> int:
	return int(pow(2, level(state)))
