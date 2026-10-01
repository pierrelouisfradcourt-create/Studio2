extends RefCounted
## Écrire des nombres COMME JavaScript : les oracles de jouabilité (outils/solvabilite.gd,
## outils/classes.gd) écrivent leur ligne FORGE_ORACLE au format de leurs modèles web.
##   to_fixed(x, n)  — x.toFixed(n)
##   fixed(x, n)     — Number(x.toFixed(n))
##   js_num(x)       — String(x) : le plus court décimal qui redonne x (Godot en écrit 14 chiffres)
##   to_json(v)      — JSON.stringify(v) (clés dans l'ordre d'insertion, Infinity -> null)
## Et les résultats PARTIELS des mesures réparties sur plusieurs processus : write_exact écrit
## les nombres non entiers sous leur forme exacte (« ~ » + 16 chiffres hexadécimaux, la convention
## de tools/export_godot.mjs), D6Js.read_exact les relit au bit près.

const SPLIT := 134217729.0 # 2^27 + 1 (découpe de Dekker)
const CHUNK := 100000000 # 10^8
const DIGITS := 17 # chiffres significatifs qui suffisent toujours à redonner un double
const MAX_EXACT_POW := 22 # 10^22 est la dernière puissance de dix exacte en double

static func to_fixed(x: float, decimals: int) -> String:
	if is_nan(x):
		return "NaN"
	if is_inf(x):
		return "Infinity" if x > 0.0 else "-Infinity"
	if x < 0.0:
		var neg := to_fixed(-x, decimals)
		return neg if float(neg) == 0.0 else "-" + neg
	# Godot arrondit le texte de 17 chiffres (double arrondi) : on recale sur la valeur exacte.
	# JavaScript prend l'entier n le plus proche de x × 10^d, le plus grand en cas d'égalité.
	var n := int(("%.*f" % [decimals, x]).replace(".", ""))
	if decimals <= MAX_EXACT_POW and x < 1e15:
		var g := _gap(x, n, decimals)
		if g >= 0.5:
			n += 1
		elif g < -0.5:
			n -= 1
	var s := str(n).lpad(decimals + 1, "0")
	if decimals == 0:
		return s
	return s.substr(0, s.length() - decimals) + "." + s.substr(s.length() - decimals)

## Number(x.toFixed(n)) : le double le plus proche du texte arrondi.
static func fixed(x: float, decimals: int) -> float:
	if is_nan(x) or is_inf(x):
		return x
	var s := to_fixed(x, decimals)
	var negative := s.begins_with("-")
	var n := float(int(s.replace("-", "").replace(".", "")))
	var v := n / _pow10(decimals)
	return -v if negative else v

static func _pow10(d: int) -> float:
	var p := 1.0
	for i in d:
		p *= 10.0
	return p

static func _ipow10(d: int) -> int:
	var p := 1
	for i in d:
		p *= 10
	return p

static func _hi(a: float) -> float:
	var c := SPLIT * a
	return c - (c - a)

## x × 10^d − n, calculé sans perte (produit exact de Dekker, n découpé en deux morceaux exacts).
static func _gap(x: float, n: int, d: int) -> float:
	var pw := _pow10(d)
	var p := x * pw
	var ah := _hi(x)
	var al := x - ah
	var bh := _hi(pw)
	var bl := pw - bh
	var err := ((ah * bh - p) + ah * bl + al * bh) + al * bl
	return ((p - float(n / CHUNK) * float(CHUNK)) - float(n % CHUNK)) + err

## Demi-écart entre x et son voisin (2^(e-53)), et x est-il une puissance de deux ?
static func _half_ulp(x: float) -> float:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, x)
	var e := ((b.decode_u64(0) >> 52) & 0x7FF) - 1023 - 53
	var h := 1.0
	for i in absi(e):
		h = h * 2.0 if e > 0 else h / 2.0
	return h

static func _plain(n: int, d: int) -> String:
	var s := str(n)
	if d <= 0:
		return s
	s = s.lpad(d + 1, "0")
	s = s.substr(0, s.length() - d) + "." + s.substr(s.length() - d)
	return s.rstrip("0").rstrip(".")

## Les 17 chiffres significatifs de x > 0 : [entier de 17 chiffres, nombre de décimales].
static func _digits17(x: float) -> Array:
	var dec := DIGITS - 1 - int(floorf(log(x) / log(10.0)))
	var lo := _ipow10(DIGITS - 1)
	for attempt in 4:
		var n := int(("%.*f" % [maxi(dec, 0), x]).replace(".", ""))
		if n >= lo * 10:
			dec -= 1
		elif n < lo:
			dec += 1
		else:
			return [n, dec]
	return [int(("%.*f" % [maxi(dec, 0), x]).replace(".", "")), dec]

## String(x) de JavaScript pour un nombre fini (notation décimale ; l'exposant de JavaScript, en
## deçà de 1e-6 ou au-delà de 1e21, n'est pas reproduit : aucune mesure n'y arrive).
static func js_num(x: float) -> String:
	if is_nan(x):
		return "NaN"
	if is_inf(x):
		return "Infinity" if x > 0.0 else "-Infinity"
	if x < 0.0:
		return "-" + js_num(-x)
	if x == floorf(x) and x < 1e18:
		return str(int(x))
	var d17: Array = _digits17(x)
	var half := _half_ulp(x)
	for nd in range(1, DIGITS + 1):
		var drop := DIGITS - nd
		var d: int = d17[1] - drop
		if d < 0 or d > MAX_EXACT_POW:
			continue
		var n: int = d17[0] / _ipow10(drop)
		var best := n
		var best_gap := _gap(x, n, d)
		for cand in [n - 1, n + 1]:
			var g := _gap(x, cand, d)
			# À égale distance, JavaScript garde le chiffre pair.
			if absf(g) < absf(best_gap) or (absf(g) == absf(best_gap) and cand % 2 == 0):
				best = cand
				best_gap = g
		if nd == DIGITS or absf(best_gap) < half * _pow10(d):
			return _plain(best, d)
	return _plain(d17[0], d17[1])

static func _json_string(s: String) -> String:
	return JSON.stringify(s)

## JSON.stringify(v) : nombres comme JavaScript, clés dans l'ordre d'insertion.
static func to_json(v) -> String:
	match typeof(v):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if v else "false"
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			return "null" if is_nan(v) or is_inf(v) else js_num(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return _json_string(str(v))
		TYPE_DICTIONARY:
			var parts: Array = []
			for k in v:
				parts.append(_json_string(str(k)) + ":" + to_json(v[k]))
			return "{" + ",".join(parts) + "}"
	var items: Array = []
	for x in v:
		items.append(to_json(x))
	return "[" + ",".join(items) + "]"

## Copie de `v` où chaque nombre non entier devient sa forme exacte (tools/export_godot.mjs, exact).
static func exact(v):
	match typeof(v):
		TYPE_FLOAT:
			if is_nan(v):
				return "~nan"
			if is_inf(v):
				return "~inf" if v > 0.0 else "~-inf"
			if v == floorf(v) and absf(v) < 9007199254740992.0:
				return int(v)
			var b := PackedByteArray()
			b.resize(8)
			b.encode_double(0, v)
			return D6Js.EXACT_PREFIX + b.hex_encode()
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = exact(v[k])
			return d
		TYPE_ARRAY:
			return v.map(exact)
	return v

## Écrit un résultat partiel relisible au bit près par D6Js.read_exact. Rend false si l'écriture échoue.
static func write_exact(path: String, v) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(exact(v), "", false)) # clés dans l'ordre d'insertion
	f.close()
	return true
