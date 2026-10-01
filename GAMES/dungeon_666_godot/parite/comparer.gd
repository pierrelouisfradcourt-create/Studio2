class_name D6Comparer
extends RefCounted
## Comparaison d'une valeur Godot à la valeur de référence produite par la simulation web.
## Égalité EXACTE, au bit près (TOL = 0) : c'est possible parce que les deux simulations ne calculent
## leurs sinus, cosinus, exponentielles… que par la même bibliothèque déterministe (D6Trig, portage
## de src/core/trig.mjs). Une tolérance non nulle ne sert qu'à diagnostiquer un écart.

const TOL := 0.0

## Rend "" si les deux valeurs sont les mêmes, sinon le chemin et les deux valeurs du 1er écart.
static func diff(got, want, tol: float = TOL, path: String = "") -> String:
	if _is_num(want):
		if not _is_num(got):
			return "%s : %s au lieu du nombre %s" % [path, _show(got), _show(want)]
		var a := float(got)
		var b := float(want)
		if is_nan(a) and is_nan(b):
			return ""
		if a == b or absf(a - b) <= tol:
			return ""
		return "%s : %s au lieu de %s (écart %s)" % [path, _show(got), _show(want), str(absf(a - b))]
	if want is Array:
		if not (got is Array):
			return "%s : %s au lieu d'un tableau" % [path, _show(got)]
		if got.size() != want.size():
			return "%s : %d éléments au lieu de %d" % [path, got.size(), want.size()]
		for i in want.size():
			var d := diff(got[i], want[i], tol, "%s[%d]" % [path, i])
			if d != "":
				return d
		return ""
	if want is Dictionary:
		if not (got is Dictionary):
			return "%s : %s au lieu d'un dictionnaire" % [path, _show(got)]
		for k in want:
			if not got.has(k):
				# JavaScript écrit une clé « undefined » comme null : absente ou nulle, c'est pareil.
				if want[k] == null:
					continue
				return "%s.%s : clé absente (attendu %s)" % [path, k, _show(want[k])]
			var d := diff(got[k], want[k], tol, "%s.%s" % [path, k])
			if d != "":
				return d
		for k in got:
			if not want.has(k) and got[k] != null:
				return "%s.%s : clé en trop (%s)" % [path, k, _show(got[k])]
		return ""
	if want is bool or got is bool:
		if (want is bool) and (got is bool) and want == got:
			return ""
		return "%s : %s au lieu de %s" % [path, _show(got), _show(want)]
	if want == null and got == null:
		return ""
	if typeof(got) == typeof(want) and got == want:
		return ""
	if (got is String or got is StringName) and (want is String or want is StringName) and String(got) == String(want):
		return ""
	return "%s : %s au lieu de %s" % [path, _show(got), _show(want)]

static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT

static func _show(v) -> String:
	var s := str(v) if v != null else "null"
	return s if s.length() <= 80 else s.substr(0, 77) + "…"
