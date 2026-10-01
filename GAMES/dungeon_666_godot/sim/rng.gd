class_name D6Rng
extends RefCounted
## RNG déterministe (mulberry32) — portage de src/core/rng.mjs. L'état tient dans un entier de
## 32 bits : {s}. La simulation n'appelle JAMAIS randf : c'est ce qui rend une partie rejouable.

const GOLDEN := 0x6d2b79f5

static func create_rng(seed) -> Dictionary:
	return {"s": D6Js.u32(seed)}

static func clone_rng(r: Dictionary) -> Dictionary:
	return {"s": r.s}

static func next_u32(r: Dictionary) -> int:
	r.s = (int(r.s) + GOLDEN) & D6Js.MASK
	var t: int = r.s
	t = D6Js.imul(t ^ (t >> 15), t | 1)
	t = t ^ ((t + D6Js.imul(t ^ (t >> 7), t | 61)) & D6Js.MASK)
	return (t ^ (t >> 14)) & D6Js.MASK

## Flottant uniforme dans [0, 1).
static func rand(r: Dictionary) -> float:
	return float(next_u32(r)) / D6Js.U32

## Flottant uniforme dans [a, b).
static func rand_range(r: Dictionary, a: float, b: float) -> float:
	return a + (b - a) * rand(r)

## Entier uniforme dans [a, b] (bornes incluses), rendu en float comme tout nombre de la sim.
static func rand_int(r: Dictionary, a: float, b: float) -> float:
	return a + floorf(rand(r) * (b - a + 1.0))

static func chance(r: Dictionary, p: float) -> bool:
	return rand(r) < p

static func pick(r: Dictionary, arr: Array):
	return arr[int(floorf(rand(r) * arr.size()))]

## Tirage pondéré : `weight_of.call(item)` rend un poids >= 0. Rend null si tout est nul.
static func weighted_pick(r: Dictionary, items: Array, weight_of: Callable):
	var total := 0.0
	for it in items:
		total += maxf(0.0, weight_of.call(it))
	if total <= 0.0:
		return null
	var x := rand(r) * total
	for it in items:
		x -= maxf(0.0, weight_of.call(it))
		if x < 0.0:
			return it
	return items[items.size() - 1]

## Mélange de Fisher-Yates, en place.
static func shuffle(r: Dictionary, arr: Array) -> Array:
	var i := arr.size() - 1
	while i > 0:
		var j := int(floorf(rand(r) * (i + 1)))
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
		i -= 1
	return arr

## Dérive une graine stable à partir d'une graine et de sels (étage, salle…).
static func hash_seed(seed, salts: Array = []) -> int:
	var h: int = D6Js.u32(seed) ^ 0x9e3779b9
	for s in salts:
		h = D6Js.imul(h ^ D6Js.u32(s), 0x85ebca6b)
		h ^= h >> 13
		h = D6Js.imul(h, 0xc2b2ae35)
		h ^= h >> 16
	return h & D6Js.MASK
