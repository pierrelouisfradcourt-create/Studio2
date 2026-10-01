extends RefCounted
## Adaptateurs des vecteurs « trig » (src/core/trig.mjs) : la bibliothèque mathématique
## déterministe doit rendre exactement les mêmes bits que la version web.

static func adapters() -> Dictionary:
	return {
		"sin": func(a): return D6Trig.sin(a[0]),
		"cos": func(a): return D6Trig.cos(a[0]),
		"atan": func(a): return D6Trig.atan(a[0]),
		"atan2": func(a): return D6Trig.atan2(a[0], a[1]),
		"asin": func(a): return D6Trig.asin(a[0]),
		"exp": func(a): return D6Trig.exp(a[0]),
		"log": func(a): return D6Trig.log(a[0]),
		"pow": func(a): return D6Trig.pow(a[0], a[1]),
		"constants": func(_a): return {"PIO2_HI": D6Trig.PIO2_HI, "PIO2_LO": D6Trig.PIO2_LO, "LN2": D6Trig.LN2},
	}
