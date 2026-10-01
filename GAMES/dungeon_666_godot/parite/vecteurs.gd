class_name D6Vecteurs
extends RefCounted
## Rejoue les vecteurs de test exportés par la simulation web (tools/export_godot.mjs) :
## pour chaque fonction pure, des entrées et la sortie de référence. Chaque module a son fichier
## d'adaptateurs : parite/adaptateurs/<module>.gd.

const DIR := "res://parite/vecteurs/"

## Rend {cases, fails: [texte…], missing: [fonction sans adaptateur…]} pour un module.
static func run(module: String) -> Dictionary:
	var res := {"cases": 0, "fails": [], "missing": []}
	var groups = D6Js.read_exact(DIR + module + ".json")
	if groups == null:
		res.fails.append("fichier de vecteurs illisible : %s" % module)
		return res
	var adapters: Dictionary = _adapters(module)
	for g in groups:
		if not adapters.has(g.fn):
			res.missing.append(g.fn)
			continue
		var f: Callable = adapters[g.fn]
		for i in g.cases.size():
			var c = g.cases[i]
			res.cases += 1
			var d := D6Comparer.diff(f.call(c.args), c.out, D6Comparer.TOL, "%s.%s#%d" % [module, g.fn, i])
			if d != "" and res.fails.size() < 20:
				res.fails.append(d)
	return res

static func modules() -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out

static func _adapters(module: String) -> Dictionary:
	var path := "res://parite/adaptateurs/%s.gd" % module
	if not ResourceLoader.exists(path):
		return {}
	return load(path).adapters()
