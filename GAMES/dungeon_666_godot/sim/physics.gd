class_name D6Physics
extends RefCounted
## Portage de src/sim/physics.mjs.
## Déplacement d'un cercle dans la salle : murs extérieurs + obstacles rectangulaires.
## Sous-pas automatiques pour les objets rapides (dash, charge) : jamais de traversée de mur.
## Regards et tirs : test EXACT du segment contre les obstacles (un coin de pilier arrête).
##
## TERRAIN BAS (room.low : rivières et obstacles bas, mêmes rectangles que les obstacles, avec
## `kind`) : il arrête qui MARCHE (héros, ennemis, ramassables), jamais un tir ni un regard. Le
## déplacement de classe du héros le FRANCHIT (move_circle, `over_low`) ; fly_plan dit d'avance
## jusqu'où, pour que le vol finisse toujours sur la terre ferme. Murs et piliers arrêtent tout.

const MIN_STEP := 4.0 # u : longueur plancher d'un sous-pas
const STEP_RADIUS_FRAC := 0.75 # un sous-pas ne dépasse pas cette fraction du rayon
const LOW_EPS := 1e-3 # u : un corps posé contre une rive (à l'arrondi près) est sur la terre ferme

static var _scratch := {"x": 0.0, "y": 0.0, "nx": 0.0, "ny": 0.0}
static var _result := {"hitWall": false, "hitLow": false, "nx": 0.0, "ny": 0.0}
static var _probe := {"x": 0.0, "y": 0.0, "r": 0.0}
## Où le dernier fly_plan pose le corps (son dernier pas sur la terre ferme) : lu par D6Player.move_landing.
static var fly_end := {"x": 0.0, "y": 0.0}

## Bornes jouables (intérieur des murs).
static func room_bounds(room: Dictionary) -> Dictionary:
	return {"x0": room.pad, "y0": room.pad, "x1": room.w - room.pad, "y1": room.h - room.pad}

static func _resolve(room: Dictionary, ent: Dictionary, over_low: bool) -> bool:
	var hit := false
	var x0: float = room.pad + ent.r
	var y0: float = room.pad + ent.r
	var x1: float = room.w - room.pad - ent.r
	var y1: float = room.h - room.pad - ent.r
	if ent.x < x0:
		ent.x = x0
		_result.nx = 1.0
		_result.ny = 0.0
		hit = true
	if ent.x > x1:
		ent.x = x1
		_result.nx = -1.0
		_result.ny = 0.0
		hit = true
	if ent.y < y0:
		ent.y = y0
		_result.ny = 1.0
		_result.nx = 0.0
		hit = true
	if ent.y > y1:
		ent.y = y1
		_result.ny = -1.0
		_result.nx = 0.0
		hit = true
	for o in room.obstacles:
		if _push_out(ent, o, x0, y0, x1, y1):
			hit = true
	# Terrain bas : il arrête qui marche (signalé à part : ce n'est pas un mur), pas qui le franchit.
	var low = room.get("low")
	if low != null and not over_low:
		for o in low:
			if _push_out(ent, o, x0, y0, x1, y1):
				_result.hitLow = true
	return hit

## Sort le cercle du rectangle `o` s'il le chevauche (position et normale du contact écrites dans
## ent et _result). Rend true s'il y avait contact.
static func _push_out(ent: Dictionary, o: Dictionary, x0: float, y0: float, x1: float, y1: float) -> bool:
	if not D6Geo.push_circle_out_of_rect(_scratch, ent.x, ent.y, ent.r, o.x0, o.y0, o.x1, o.y1):
		return false
	# Sortie qui mènerait dans un mur (obstacle collé au mur, centre pris dedans) : une autre.
	if _scratch.x < x0 or _scratch.x > x1 or _scratch.y < y0 or _scratch.y > y1:
		_exit_inside_room(ent, o, x0, y0, x1, y1)
	ent.x = _scratch.x
	ent.y = _scratch.y
	_result.nx = _scratch.nx
	_result.ny = _scratch.ny
	return true

## Sortie d'un obstacle par le bord le plus proche qui laisse le cercle DANS la salle (bornes de
## son centre : x0..x1, y0..y1), à égalité dans l'ordre gauche, droite, haut, bas. Écrit _scratch.
## Aucun bord possible (obstacle plus large que la salle) : le cercle reste où les murs l'ont mis.
static func _exit_inside_room(ent: Dictionary, o: Dictionary, x0: float, y0: float, x1: float, y1: float) -> void:
	var r: float = ent.r
	var exits := [[o.x0 - r, ent.y, -1.0, 0.0], [o.x1 + r, ent.y, 1.0, 0.0], [ent.x, o.y0 - r, 0.0, -1.0], [ent.x, o.y1 + r, 0.0, 1.0]]
	var best := INF
	_scratch.x = ent.x
	_scratch.y = ent.y
	_scratch.nx = 0.0
	_scratch.ny = 0.0
	for c in exits:
		if c[0] < x0 or c[0] > x1 or c[1] < y0 or c[1] > y1:
			continue
		var d: float = absf(c[0] - ent.x) + absf(c[1] - ent.y)
		if d < best:
			best = d
			_scratch.x = c[0]
			_scratch.y = c[1]
			_scratch.nx = c[2]
			_scratch.ny = c[3]

## Déplace `ent` ({x, y, r}) de (dx, dy) avec collisions. Rend un objet PARTAGÉ (ne pas le
## conserver) : {hitWall, hitLow, nx, ny} — mur ou pilier touché, bord d'un terrain bas touché, et
## la normale du dernier contact. `over_low` : le corps franchit le terrain bas (déplacement de
## classe du héros) ; murs et piliers l'arrêtent toujours.
static func move_circle(room: Dictionary, ent: Dictionary, dx: float, dy: float, over_low: bool = false) -> Dictionary:
	_result.hitWall = false
	_result.hitLow = false
	_result.nx = 0.0
	_result.ny = 0.0
	var distance := sqrt(dx * dx + dy * dy)
	var steps := maxf(1.0, ceilf(distance / maxf(MIN_STEP, ent.r * STEP_RADIUS_FRAC)))
	var sx := dx / steps
	var sy := dy / steps
	for i in range(int(steps)):
		ent.x += sx
		ent.y += sy
		if _resolve(room, ent, over_low):
			_result.hitWall = true
	return _result

## Le cercle chevauche-t-il un terrain bas (rivière, obstacle bas) ? Faux = terre ferme.
static func low_at(room: Dictionary, x: float, y: float, r: float) -> bool:
	var low = room.get("low")
	if low == null:
		return false
	var rr := maxf(0.0, r - LOW_EPS)
	for o in low:
		var dx: float = x - D6Geo.clampv(x, o.x0, o.x1)
		var dy: float = y - D6Geo.clampv(y, o.y0, o.y1)
		if dx * dx + dy * dy < rr * rr:
			return true
	return false

## VOL au-dessus du terrain bas : `moves` pas de (dx, dy) depuis la place de `ent`, sans le
## déplacer (murs et piliers arrêtent le vol comme la marche). Rend le nombre de pas après lequel
## le corps est pour la DERNIÈRE fois sur la terre ferme : `moves` si l'arrivée est bonne, moins si
## elle tomberait dans une rivière ou sur un obstacle bas (le geste est raccourci), 0 = sur place.
static func fly_plan(room: Dictionary, ent: Dictionary, dx: float, dy: float, moves: int) -> int:
	_probe.x = ent.x
	_probe.y = ent.y
	_probe.r = ent.r
	var last := 0
	fly_end.x = ent.x
	fly_end.y = ent.y
	for i in moves:
		move_circle(room, _probe, dx, dy, true)
		if not low_at(room, _probe.x, _probe.y, _probe.r):
			last = i + 1
			fly_end.x = _probe.x
			fly_end.y = _probe.y
	return last

## Vrai si le point est dans un obstacle ou hors des murs (avec marge `r`).
static func point_blocked(room: Dictionary, x: float, y: float, r: float) -> bool:
	if x < room.pad + r or x > room.w - room.pad - r or y < room.pad + r or y > room.h - room.pad - r:
		return true
	for o in room.obstacles:
		if x > o.x0 - r and x < o.x1 + r and y > o.y0 - r and y < o.y1 + r:
			return true
	return false

## Vrai si rien ne peut se POSER là (corps qui marche, apparition, récompense, objet) : hors des
## murs, dans un obstacle, ou sur un terrain bas (avec marge `r`). Les tirs, eux, lisent point_blocked.
static func ground_blocked(room: Dictionary, x: float, y: float, r: float) -> bool:
	if point_blocked(room, x, y, r):
		return true
	var low = room.get("low")
	if low != null:
		for o in low:
			if x > o.x0 - r and x < o.x1 + r and y > o.y0 - r and y < o.y1 + r:
				return true
	return false

## Le segment (a → b) passe-t-il par l'INTÉRIEUR d'un obstacle ? Calcul exact : [t0, t1] est la part
## du segment comprise entre les bords gauche et droit, puis haut et bas, du rectangle. Raser un bord
## ou toucher un coin n'est pas traverser. Additions, divisions, comparaisons : mêmes bits partout.
static func segment_hits_obstacle(room: Dictionary, ax: float, ay: float, bx: float, by: float) -> bool:
	return _segment_hits(room.obstacles, ax, ay, bx, by)

## Le même calcul sur une liste de rectangles (obstacles hauts, ou terrain bas).
static func _segment_hits(rects: Array, ax: float, ay: float, bx: float, by: float) -> bool:
	var dx := bx - ax
	var dy := by - ay
	for o in rects:
		var t0 := 0.0
		var t1 := 1.0
		if dx == 0.0:
			if ax <= o.x0 or ax >= o.x1:
				continue
		else:
			var ta: float = (o.x0 - ax) / dx
			var tb: float = (o.x1 - ax) / dx
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		if dy == 0.0:
			if ay <= o.y0 or ay >= o.y1:
				continue
		else:
			var tc: float = (o.y0 - ay) / dy
			var td: float = (o.y1 - ay) / dy
			t0 = maxf(t0, minf(tc, td))
			t1 = minf(t1, maxf(tc, td))
		if t0 < t1:
			return true
	return false

## Ligne de vue entre deux points : les obstacles bloquent, coins compris.
static func line_of_sight(room: Dictionary, ax: float, ay: float, bx: float, by: float) -> bool:
	return not segment_hits_obstacle(room, ax, ay, bx, by)

## Peut-on MARCHER tout droit d'un point à l'autre ? Comme la ligne de vue, mais une rivière ou un
## obstacle bas coupe aussi le chemin (on voit et l'on tire par-dessus, on ne passe pas à pied).
## `r` > 0 : pour un corps de ce rayon — ses deux flancs ne doivent pas non plus mordre sur le
## terrain bas (une ruée ne rase pas le coin d'un gué). Les piliers, eux, se lisent au centre, comme
## la ligne de vue.
static func walk_clear(room: Dictionary, ax: float, ay: float, bx: float, by: float, r: float = 0.0) -> bool:
	if segment_hits_obstacle(room, ax, ay, bx, by):
		return false
	var low = room.get("low")
	if low == null or low.is_empty():
		return true
	if _segment_hits(low, ax, ay, bx, by):
		return false
	var l := sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))
	if r <= 0.0 or l < 1e-6:
		return true
	var nx := -(by - ay) / l * r
	var ny := (bx - ax) / l * r
	return not _segment_hits(low, ax + nx, ay + ny, bx + nx, by + ny) and not _segment_hits(low, ax - nx, ay - ny, bx - nx, by - ny)

## Un tir qui va de (ax, ay) à (bx, by) en un pas est-il arrêté ? Oui s'il finit hors des murs ou
## dans un obstacle, ou si son trajet en a traversé un (un coin, entre deux positions).
static func shot_blocked(room: Dictionary, ax: float, ay: float, bx: float, by: float) -> bool:
	return point_blocked(room, bx, by, 0.0) or segment_hits_obstacle(room, ax, ay, bx, by)
