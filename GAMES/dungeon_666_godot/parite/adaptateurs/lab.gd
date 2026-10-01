extends RefCounted
## Adaptateurs des vecteurs « lab » (src/sim/lab.mjs). Le labo ÉCRIT dans le tuning : chaque cas
## reçoit un tuning neuf, et la sortie comparée est la vue des clés que le labo pilote.

const Outils := preload("res://parite/adaptateurs/state.gd")

static func _view(t: Dictionary) -> Dictionary:
	return {
		"strikeCancelFrom": t.dash.strikeCancelFrom, "strikeWindow": t.dash.strikeWindow, "hitstopMode": t.hitstopMode,
		"attackMoveMult": t.player.attackMoveMult, "cancelMult": t.player.cancelMult, "lab": t.get("lab"),
	}

static func _apply_lab(a: Array) -> Dictionary:
	var t := Outils.tuning(a[0], true)
	var ret := D6Lab.apply_lab(t)
	return {"same": is_same(ret, t), "view": _view(t)}

static func _set_lab(a: Array) -> Dictionary:
	var t := Outils.tuning(a[0], true)
	var rets: Array = []
	for op in a[1]:
		rets.append(D6Lab.set_lab(t, op[0], op[1]))
	return {"rets": rets, "view": _view(t)}

static func adapters() -> Dictionary:
	return {
		"applyLab": _apply_lab,
		"setLab": _set_lab,
		"labSummary": func(a): return D6Lab.lab_summary(Outils.tuning(a[0], true)),
	}
