extends RefCounted
## Adaptateurs des vecteurs « sections » (src/sim/sections.mjs). Arguments : [surcharge de tuning, …].

const Outils := preload("res://parite/adaptateurs/state.gd")

static func adapters() -> Dictionary:
	var direct := {
		"sectionCount": D6Sections.section_count,
		"circleTheme": D6Sections.circle_theme,
		"sectionPlan": D6Sections.section_plan,
		"floorSlot": D6Sections.floor_slot,
		"composeFloor": D6Sections.compose_floor,
	}
	var out := {}
	for k in direct:
		var f: Callable = direct[k]
		out[k] = func(a): return f.callv([Outils.tuning(a[0])] + a.slice(1))
	return out
