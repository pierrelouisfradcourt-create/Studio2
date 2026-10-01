class_name D6Trig
extends RefCounted
## Fonctions transcendantes DÉTERMINISTES — portage ligne à ligne de src/core/trig.mjs.
## Sinus, cosinus, arc tangente, exponentielle, logarithme, puissance, écrits avec les seules
## opérations que tous les moteurs calculent à l'identique (+, −, ×, ÷, racine, partie entière).
##
## La simulation n'appelle JAMAIS sin, cos, atan2, exp, asin ni pow natifs : leur dernier bit
## diffère entre Godot et JavaScript (9 % des sinus, mesuré le 2026-10-01), et un combat dense
## amplifie cet écart jusqu'à faire diverger deux parties rejouées. Avec ce module, même graine
## et mêmes entrées donnent la même partie AU BIT PRÈS dans les deux moteurs.
##
## Aucun coefficient décimal écrit en dur (les lecteurs de décimaux diffèrent aussi) : ce sont
## des quotients d'entiers, calculés. L'ordre des opérations est celui du JavaScript, à garder.
##
## PIÈGE : dans ce script, `atan(`, `exp(`, `log(` écrits sans préfixe désignent les fonctions
## NATIVES de Godot, pas celles-ci. Tout appel interne s'écrit `D6Trig.atan(…)`.

const HALF_PI := PI / 2.0
const SIN_TERMS := 10
const EXP_TERMS := 16
const ATAN_TERMS := 14
const LOG_TERMS := 16

# π/2 en deux morceaux (Cody-Waite) : le premier a ses 27 bits bas à zéro, k × HI est exact.
static var PIO2_HI: float = floorf(HALF_PI * 67108864.0) / 67108864.0
static var PIO2_LO: float = HALF_PI - PIO2_HI
static var LN2: float = _ln2_series()

static var _red_q := 0
static var _red_r := 0.0

## ln 2 = 2·atanh(1/3), sommé du plus petit terme au plus grand.
static func _ln2_series() -> float:
	var s := 0.0
	var i := 20
	while i >= 0:
		s = 1.0 / (2.0 * i + 1.0) + s / 9.0
		i -= 1
	return (2.0 * s) / 3.0

static func _jround(x: float) -> float:
	return floorf(x + 0.5)

## Réduit x à r dans [-π/4, π/4] ; quadrant (0..3) dans _red_q, r dans _red_r.
static func _reduce(x: float) -> void:
	var k := _jround(x / HALF_PI)
	_red_r = x - k * PIO2_HI - k * PIO2_LO
	_red_q = int(fmod(fmod(k, 4.0) + 4.0, 4.0))

static func _sin_kernel(r: float) -> float:
	var r2 := r * r
	var s := 0.0
	var i := SIN_TERMS
	while i >= 1:
		s = (1.0 - s) * r2 / ((2.0 * i) * (2.0 * i + 1.0))
		i -= 1
	return r * (1.0 - s)

static func _cos_kernel(r: float) -> float:
	var r2 := r * r
	var s := 0.0
	var i := SIN_TERMS
	while i >= 1:
		s = (1.0 - s) * r2 / ((2.0 * i - 1.0) * (2.0 * i))
		i -= 1
	return 1.0 - s

static func sin(x: float) -> float:
	_reduce(x)
	match _red_q:
		0:
			return _sin_kernel(_red_r)
		1:
			return _cos_kernel(_red_r)
		2:
			return -_sin_kernel(_red_r)
	return -_cos_kernel(_red_r)

static func cos(x: float) -> float:
	_reduce(x)
	match _red_q:
		0:
			return _cos_kernel(_red_r)
		1:
			return -_sin_kernel(_red_r)
		2:
			return -_cos_kernel(_red_r)
	return _sin_kernel(_red_r)

## Arc tangente de z >= 0. Deux demi-angles ramènent z sous tan(π/16), puis la série.
static func _atan_pos(z: float) -> float:
	if z > 1.0:
		return HALF_PI - _atan_pos(1.0 / z)
	var w := z / (1.0 + sqrt(1.0 + z * z))
	w = w / (1.0 + sqrt(1.0 + w * w))
	var w2 := w * w
	var s := 0.0
	var i := ATAN_TERMS
	while i >= 0:
		s = 1.0 / (2.0 * i + 1.0) - w2 * s
		i -= 1
	return 4.0 * w * s

static func atan(z: float) -> float:
	return -_atan_pos(-z) if z < 0.0 else _atan_pos(z)

## Angle du vecteur (x, y) dans (-π, π], conventions de Math.atan2 (hors zéros signés).
static func atan2(y: float, x: float) -> float:
	if x > 0.0:
		return D6Trig.atan(y / x)
	if x < 0.0:
		return D6Trig.atan(y / x) + PI if y >= 0.0 else D6Trig.atan(y / x) - PI
	if y > 0.0:
		return HALF_PI
	if y < 0.0:
		return -HALF_PI
	return 0.0

static func asin(v: float) -> float:
	if v >= 1.0:
		return HALF_PI
	if v <= -1.0:
		return -HALF_PI
	return D6Trig.atan(v / sqrt(1.0 - v * v))

static func exp(x: float) -> float:
	var k := _jround(x / LN2)
	var r := x - k * LN2
	var s := 1.0
	var i := EXP_TERMS
	while i >= 1:
		s = 1.0 + (r / i) * s
		i -= 1
	# × 2^k par doublements (exacts).
	var n := int(absf(k))
	if k > 0.0:
		for j in n:
			s *= 2.0
	else:
		for j in n:
			s /= 2.0
	return s

## Logarithme naturel (x > 0) : x = m × 2^e avec m dans [0,75 ; 1,5), puis 2·atanh((m−1)/(m+1)).
static func log(x: float) -> float:
	var m := x
	var e := 0.0
	while m >= 1.5:
		m /= 2.0
		e += 1.0
	while m < 0.75:
		m *= 2.0
		e -= 1.0
	var u := (m - 1.0) / (m + 1.0)
	var u2 := u * u
	var s := 0.0
	var i := LOG_TERMS
	while i >= 0:
		s = 1.0 / (2.0 * i + 1.0) + u2 * s
		i -= 1
	return 2.0 * u * s + e * LN2

## a^b pour a > 0 (le seul usage de la simulation : un poids).
static func pow(a: float, b: float) -> float:
	if b == 0.0:
		return 1.0
	if a == 1.0:
		return 1.0
	return D6Trig.exp(b * D6Trig.log(a))
