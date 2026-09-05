# progression.gd — LOGIQUE PURE (category system, allowed_deps [collection, world_content]).
# Suit le palier de progression et decide le deblocage des lieux : au palier requis atteint
# par les adoptions, le second lieu (`lieu_2`) devient disponible. Proprietaire unique de la
# logique de deblocage de lieu. `places_array` INJECTE par l'appelant (world_content).
extends RefCounted

const Collection = preload("res://05_SYSTEMS/collection/collection.gd")

# Palier de progression = nombre de chatons adoptes. C'est la grandeur que le bot de
# solvabilite doit porter jusqu'a 3.
static func tier(state: Dictionary) -> int:
	return Collection.count(state)

# Cherche la place d'id donne dans le registre injecte (ordre d'iteration deterministe :
# la liste est parcourue dans l'ordre du registre, jamais l'ordre d'un Dictionary).
static func _place_by_id(places_array: Array, id: String) -> Dictionary:
	for p in places_array:
		if p is Dictionary and String(p.get("id", "")) == id:
			return p
	return {}

# Le second lieu est-il debloque ? Vrai quand le palier atteint son `unlock_tier`.
static func lieu2_unlocked(state: Dictionary, places_array: Array) -> bool:
	var lieu2: Dictionary = _place_by_id(places_array, "lieu_2")
	if lieu2.is_empty():
		return false
	return tier(state) >= int(lieu2.get("unlock_tier", 999999))

# Nombre de lieux DISPONIBLES (refuge + lieu_2 si debloque) — sert au HUD `lieux`.
static func available_places(state: Dictionary, places_array: Array) -> int:
	var n: int = 0
	for p in places_array:
		if not (p is Dictionary):
			continue
		if int(p.get("unlock_tier", 0)) <= tier(state):
			n += 1
	return n
