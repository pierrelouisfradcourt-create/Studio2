class_name D6Geo
extends RefCounted
## Utilitaires géométriques — portage de src/core/math.mjs. Les fonctions travaillent sur des
## nombres, ou écrivent dans un dictionnaire `out` fourni par l'appelant.

const EPS := 1e-9

static func clampv(v: float, lo: float, hi: float) -> float:
	return lo if v < lo else (hi if v > hi else v)

static func lerpv(a: float, b: float, t: float) -> float:
	return a + (b - a) * t

static func length(x: float, y: float) -> float:
	return sqrt(x * x + y * y)

static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	return sqrt(dx * dx + dy * dy)

static func dist2(ax: float, ay: float, bx: float, by: float) -> float:
	var dx := bx - ax
	var dy := by - ay
	return dx * dx + dy * dy

## Normalise (x, y) dans out ; vecteur nul -> (0, 0). Rend la longueur d'origine.
static func normalize_into(out: Dictionary, x: float, y: float) -> float:
	var l := sqrt(x * x + y * y)
	if l < EPS:
		out.x = 0.0
		out.y = 0.0
		return 0.0
	out.x = x / l
	out.y = y / l
	return l

## Rapproche v de target d'au plus max_delta.
static func approach(v: float, target: float, max_delta: float) -> float:
	if v < target:
		return minf(v + max_delta, target)
	return maxf(v - max_delta, target)

## Différence d'angle signée dans (-PI, PI].
static func angle_diff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	if d <= -PI:
		d += TAU
	return d

## Vrai si le point (px, py) est dans le secteur circulaire centré en (cx, cy), de rayon r
## (agrandi de `pad`, typiquement le rayon de la cible), orienté `dir`, d'ouverture totale `arc`.
static func in_sector(px: float, py: float, cx: float, cy: float, r: float, dir: float, arc: float, pad: float = 0.0) -> bool:
	var dx := px - cx
	var dy := py - cy
	var d := sqrt(dx * dx + dy * dy)
	if d > r + pad:
		return false
	if d <= pad:
		return true # cible qui chevauche l'origine : toujours touchée
	var half := arc / 2.0
	if half >= PI:
		return true
	var diff := absf(angle_diff(dir, D6Trig.atan2(dy, dx)))
	# Tolérance angulaire liée au rayon de la cible : un gros ennemi au bord de l'arc est touché.
	var slack := D6Trig.asin(clampv(pad / d, 0.0, 1.0))
	return diff <= half + slack

static func circles_overlap(ax: float, ay: float, ar: float, bx: float, by: float, br: float) -> bool:
	var r := ar + br
	return dist2(ax, ay, bx, by) < r * r

## Distance au carré d'un point à un segment [a, b].
static func point_seg_dist2(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
	var abx := bx - ax
	var aby := by - ay
	var l2 := abx * abx + aby * aby
	var t := ((px - ax) * abx + (py - ay) * aby) / l2 if l2 > EPS else 0.0
	t = clampv(t, 0.0, 1.0)
	return dist2(px, py, ax + abx * t, ay + aby * t)

## Distance au carré d'un point à une BANDE : rectangle orienté qui part de (ax, ay) dans la
## direction `angle`, long de `length`, large de `width` (centré sur son axe). 0 à l'intérieur.
static func point_band_dist2(px: float, py: float, ax: float, ay: float, angle: float, length: float, width: float) -> float:
	var c := D6Trig.cos(angle)
	var s := D6Trig.sin(angle)
	var dx := px - ax
	var dy := py - ay
	var u := dx * c + dy * s # le long de l'axe
	var v := absf(-dx * s + dy * c) # en travers
	var du := -u if u < 0.0 else (u - length if u > length else 0.0)
	var dv := v - width / 2.0 if v > width / 2.0 else 0.0
	return du * du + dv * dv

## Point de l'AABB [x0,y0,x1,y1] le plus proche de (px, py), écrit dans out.
static func closest_on_rect(out: Dictionary, px: float, py: float, x0: float, y0: float, x1: float, y1: float) -> Dictionary:
	out.x = clampv(px, x0, x1)
	out.y = clampv(py, y0, y1)
	return out

## Repousse un cercle hors d'un AABB. Rend true s'il y avait chevauchement ; out = nouvelle
## position du centre, nx/ny = normale de sortie.
static func push_circle_out_of_rect(out: Dictionary, cx: float, cy: float, r: float, x0: float, y0: float, x1: float, y1: float) -> bool:
	var qx := clampv(cx, x0, x1)
	var qy := clampv(cy, y0, y1)
	var dx := cx - qx
	var dy := cy - qy
	var d2 := dx * dx + dy * dy
	if d2 >= r * r:
		return false
	if d2 > EPS:
		var d := sqrt(d2)
		out.nx = dx / d
		out.ny = dy / d
		out.x = qx + out.nx * r
		out.y = qy + out.ny * r
		return true
	# Centre à l'intérieur du rectangle : sortie par le bord le plus proche.
	var left := cx - x0
	var right := x1 - cx
	var top := cy - y0
	var bottom := y1 - cy
	var m := minf(minf(left, right), minf(top, bottom))
	out.nx = 0.0
	out.ny = 0.0
	out.x = cx
	out.y = cy
	if m == left:
		out.nx = -1.0
		out.x = x0 - r
	elif m == right:
		out.nx = 1.0
		out.x = x1 + r
	elif m == top:
		out.ny = -1.0
		out.y = y0 - r
	else:
		out.ny = 1.0
		out.y = y1 + r
	return true

## Repousse un cercle hors d'un autre cercle (obstacle fixe).
static func push_circle_out_of_circle(out: Dictionary, cx: float, cy: float, r: float, ox: float, oy: float, o_r: float) -> bool:
	var dx := cx - ox
	var dy := cy - oy
	var rr := r + o_r
	var d2 := dx * dx + dy * dy
	if d2 >= rr * rr:
		return false
	var d := sqrt(d2)
	if d < EPS:
		out.nx = 1.0
		out.ny = 0.0
	else:
		out.nx = dx / d
		out.ny = dy / d
	out.x = ox + out.nx * rr
	out.y = oy + out.ny * rr
	return true

static func ease_out_cubic(t: float) -> float:
	var u := 1.0 - t
	return 1.0 - u * u * u

static func ease_in_quad(t: float) -> float:
	return t * t
