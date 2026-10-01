class_name D6Js
extends RefCounted
## Arithmétique et conventions héritées de JavaScript : la simulation a été portée de la version
## web (GAMES/dungeon_666, figée le 2026-10-01) et garde ses habitudes de calcul — arrondi dont la
## demie monte, entiers de 32 bits du générateur aléatoire, valeurs « vraies ». Ce module les tient.
##
## Règle n°1 de sim/ : TOUT nombre de la simulation est un float. Les données lues par D6Data
## sont des floats ; une division entre deux entiers GDScript tronquerait. On ne convertit en int
## qu'au moment d'indexer un tableau.

const U32 := 4294967296.0
const MASK := 0xFFFFFFFF
const EXACT_PREFIX := "~"
const EXACT_HEX_DIGITS := 16

## Math.round de JavaScript : la demie monte TOUJOURS (round(-2.5) = -2 ; GDScript rendrait -3).
static func jround(x: float) -> float:
	return floorf(x + 0.5)

## x >>> 0 : les 32 bits bas, non signés.
static func u32(x) -> int:
	return int(x) & MASK

## Math.imul : produit sur 32 bits, rendu non signé. Découpé en moitiés de 16 bits : le produit
## direct de deux entiers de 32 bits déborderait l'entier 64 bits de GDScript.
static func imul(a: int, b: int) -> int:
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	var bl := b & 0xFFFF
	var bh := (b >> 16) & 0xFFFF
	return (al * bl + (((ah * bl + al * bh) & 0xFFFF) << 16)) & MASK

## Texte d'un nombre comme l'écrit JavaScript dans une chaîne : 50 et non « 50.0 ».
static func num_str(x) -> String:
	var f := float(x)
	if f == floorf(f) and absf(f) < 1e15:
		return str(int(f))
	return str(f)

## a ?? b : `b` si `a` est null.
static func nz(a, b):
	return b if a == null else a

## Valeur « vraie » au sens de JavaScript (null, false, 0, NaN et "" sont faux).
static func truthy(v) -> bool:
	if v == null:
		return false
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT:
			return v != 0
		TYPE_FLOAT:
			return v != 0.0 and not is_nan(v)
		TYPE_STRING, TYPE_STRING_NAME:
			return v != ""
	return true

## Met une donnée JSON à la forme que lit la simulation : tous les nombres en float.
## Accepte encore la forme EXACTE — « ~ » + 16 chiffres hexadécimaux = les 8 octets d'un double,
## « ~inf », « ~-inf », « ~nan » — qu'écrivaient les exports de la version web et qu'écrivent
## toujours les résultats partiels des oracles de jouabilité (outils/bots/format.gd, write_exact).
## Les fichiers de data/ sont du JSON ordinaire ; un texte qui commence par « ~ » sans être de
## cette forme reste un texte.
static func decode(v):
	match typeof(v):
		TYPE_STRING:
			if (v as String).begins_with(EXACT_PREFIX):
				return _exact(v)
			return v
		TYPE_INT:
			return float(v)
		TYPE_ARRAY:
			var out: Array = []
			out.resize(v.size())
			for i in v.size():
				out[i] = decode(v[i])
			return out
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = decode(v[k])
			return d
	return v

static func _exact(s: String):
	var h := s.substr(1)
	if h == "inf":
		return INF
	if h == "-inf":
		return -INF
	if h == "nan":
		return NAN
	if h.length() != EXACT_HEX_DIGITS or not h.is_valid_hex_number():
		return s
	return h.hex_decode().decode_double(0)

## Lit un fichier JSON et le décode (decode). Rend null si le fichier manque ou est illisible.
static func read_exact(path: String):
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return null if parsed == null else decode(parsed)

## structuredClone.
static func clone(v):
	if v is Dictionary or v is Array:
		return v.duplicate(true)
	return v

## Fusion profonde de `src` dans `target` (config.mjs deepMerge) : les tableaux sont remplacés.
static func deep_merge(target: Dictionary, src: Dictionary) -> void:
	for k in src:
		var v = src[k]
		if v is Dictionary and target.get(k) is Dictionary:
			deep_merge(target[k], v)
		else:
			target[k] = v
