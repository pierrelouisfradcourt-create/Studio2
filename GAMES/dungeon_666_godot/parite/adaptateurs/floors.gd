extends RefCounted
## Adaptateurs des vecteurs « floors » (src/sim/floors.mjs). Arguments : [surcharge de tuning, …].

const Outils := preload("res://parite/adaptateurs/state.gd")

static func adapters() -> Dictionary:
	var direct := {
		"floorInfo": D6Floors.floor_info,
		"checkpointAfterBoss": D6Floors.checkpoint_after_boss,
		"floorScaling": D6Floors.floor_scaling,
		"playerHpGrowth": D6Floors.player_hp_growth,
		"sectionStartDifficulty": D6Floors.section_start_difficulty,
		"guardianFor": D6Floors.guardian_for,
		"sectionBounds": D6Floors.section_bounds,
	}
	var out := {}
	for k in direct:
		var f: Callable = direct[k]
		out[k] = func(a): return f.callv([Outils.tuning(a[0])] + a.slice(1))
	return out
