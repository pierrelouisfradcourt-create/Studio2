# collection.gd — LOGIQUE PURE (category system, allowed_deps [world_content]).
# Detient l'ensemble des chatons ADOPTES : adopte le prochain chaton nomme distinct (defini
# par world_content, ordre deterministe) et expose le compte + la production passive totale
# (somme des ronrons_per_sec). Proprietaire unique de « quels chatons sont adoptes ».
# `kittens_array` est INJECTE par l'appelant (le controleur le lit de world_content) : la
# logique reste pure et testable sans FileAccess.
extends RefCounted

static func count(state: Dictionary) -> int:
	return (state["adopted"] as Array).size()

# Adopte le prochain chaton non encore adopte. Reussit tant qu'il en reste dans le monde.
# N'applique AUCUN cout (la transaction cout+adoption est orchestree par l'input_adapter).
static func adopt(state: Dictionary, kittens_array: Array) -> bool:
	var n: int = count(state)
	if n >= kittens_array.size():
		return false
	var k = kittens_array[n]
	if not (k is Dictionary):
		return false
	(state["adopted"] as Array).append(String(k.get("name", "chaton_%d" % n)))
	return true

# Le chaton a l'index donne est-il deja adopte ?
static func is_adopted(state: Dictionary, index: int) -> bool:
	return index >= 0 and index < count(state)

# Production passive totale = somme des ronrons_per_sec des chatons adoptes.
static func passive_rate(state: Dictionary, kittens_array: Array) -> float:
	var total: float = 0.0
	var n: int = count(state)
	for i in range(n):
		if i < kittens_array.size() and kittens_array[i] is Dictionary:
			total += float(kittens_array[i].get("ronrons_per_sec", 0))
	return total
