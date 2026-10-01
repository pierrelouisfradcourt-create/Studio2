extends RefCounted
## Adaptateurs des vecteurs « rng » (src/core/rng.mjs) : pour chaque fonction exportée par la simulation
## web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.

static func _seq(seed, f: Callable, n: int = 8) -> Array:
	var r := D6Rng.create_rng(seed)
	var out: Array = []
	for i in n:
		out.append(f.call(r))
	return out

static func adapters() -> Dictionary:
	return {
		"nextU32": func(a): return _seq(a[0], D6Rng.next_u32),
		"rand": func(a): return _seq(a[0], D6Rng.rand),
		"randRange": func(a): return _seq(a[0], func(r): return D6Rng.rand_range(r, a[1], a[2])),
		"randInt": func(a): return _seq(a[0], func(r): return D6Rng.rand_int(r, a[1], a[2])),
		"pick": func(a): return _seq(a[0], func(r): return D6Rng.pick(r, a[1])),
		"shuffle": func(a): return D6Rng.shuffle(D6Rng.create_rng(a[0]), a[1].duplicate()),
		"weightedPick": func(a): return _seq(a[0], func(r): return D6Rng.weighted_pick(r, a[1], func(it): return it.w).id),
		"hashSeed": func(a): return D6Rng.hash_seed(a[0], [a[1], a[2]]),
	}
