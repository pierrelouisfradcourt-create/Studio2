class_name D6Physics
extends RefCounted
## Portage de src/sim/physics.mjs.
## Déplacement d'un cercle dans la salle : murs extérieurs + obstacles rectangulaires.
## Sous-pas automatiques pour les objets rapides (dash, charge) : jamais de traversée de mur.
## Regards et tirs : test EXACT du segment contre les obstacles (un coin de pilier arrête).

const MIN_STEP := 4.0 # u : longueur plancher d'un sous-pas
const STEP_RADIUS_FRAC := 0.75 # un sous-pas ne dépasse pas cette fraction du rayon

static var _scratch := {"x": 0.0, "y": 0.0, "nx": 0.0, "ny": 0.0}
static var _result := {"hitWall": false, "nx": 0.0, "ny": 0.0}

## Bornes jouables (intérieur des murs).
static func room_bounds(room: Dictionary) -> Dictionary:
	return {"x0": room.pad, "y0": room.pad, "x1": room.w - room.pad, "y1": room.h - room.pad}

static func _resolve(room: Dictionary, ent: Dictionary) -> bool:
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
		if D6Geo.push_circle_out_of_rect(_scratch, ent.x, ent.y, ent.r, o.x0, o.y0, o.x1, o.y1):
			# Sortie qui mènerait dans un mur (obstacle collé au mur, centre pris dedans) : une autre.
			if _scratch.x < x0 or _scratch.x > x1 or _scratch.y < y0 or _scratch.y > y1:
				_exit_inside_room(ent, o, x0, y0, x1, y1)
			ent.x = _scratch.x
			ent.y = _scratch.y
			_result.nx = _scratch.nx
			_result.ny = _scratch.ny
			hit = true
	return hit

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
## conserver) : {hitWall, nx, ny} — la normale du dernier contact.
static func move_circle(room: Dictionary, ent: Dictionary, dx: float, dy: float) -> Dictionary:
	_result.hitWall = false
	_result.nx = 0.0
	_result.ny = 0.0
	var distance := sqrt(dx * dx + dy * dy)
	var steps := maxf(1.0, ceilf(distance / maxf(MIN_STEP, ent.r * STEP_RADIUS_FRAC)))
	var sx := dx / steps
	var sy := dy / steps
	for i in range(int(steps)):
		ent.x += sx
		ent.y += sy
		if _resolve(room, ent):
			_result.hitWall = true
	return _result

## Vrai si le point est dans un obstacle ou hors des murs (avec marge `r`).
static func point_blocked(room: Dictionary, x: float, y: float, r: float) -> bool:
	if x < room.pad + r or x > room.w - room.pad - r or y < room.pad + r or y > room.h - room.pad - r:
		return true
	for o in room.obstacles:
		if x > o.x0 - r and x < o.x1 + r and y > o.y0 - r and y < o.y1 + r:
			return true
	return false

## Le segment (a → b) passe-t-il par l'INTÉRIEUR d'un obstacle ? Calcul exact : [t0, t1] est la part
## du segment comprise entre les bords gauche et droit, puis haut et bas, du rectangle. Raser un bord
## ou toucher un coin n'est pas traverser. Additions, divisions, comparaisons : mêmes bits partout.
static func segment_hits_obstacle(room: Dictionary, ax: float, ay: float, bx: float, by: float) -> bool:
	var dx := bx - ax
	var dy := by - ay
	for o in room.obstacles:
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

## Un tir qui va de (ax, ay) à (bx, by) en un pas est-il arrêté ? Oui s'il finit hors des murs ou
## dans un obstacle, ou si son trajet en a traversé un (un coin, entre deux positions).
static func shot_blocked(room: Dictionary, ax: float, ay: float, bx: float, by: float) -> bool:
	return point_blocked(room, bx, by, 0.0) or segment_hits_obstacle(room, ax, ay, bx, by)
