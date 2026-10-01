class_name D6Physics
extends RefCounted
## Portage de src/sim/physics.mjs.
## Déplacement d'un cercle dans la salle : murs extérieurs + obstacles rectangulaires.
## Sous-pas automatiques pour les objets rapides (dash, charge) : jamais de traversée de mur.

const MIN_STEP := 4.0 # u : longueur plancher d'un sous-pas
const STEP_RADIUS_FRAC := 0.75 # un sous-pas ne dépasse pas cette fraction du rayon
const SIGHT_STEP := 16.0 # u : pas d'échantillonnage de la ligne de vue

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
			ent.x = _scratch.x
			ent.y = _scratch.y
			_result.nx = _scratch.nx
			_result.ny = _scratch.ny
			hit = true
	return hit

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

## Ligne de vue entre deux points (les obstacles bloquent). Échantillonnage, suffisant ici.
static func line_of_sight(room: Dictionary, ax: float, ay: float, bx: float, by: float) -> bool:
	var dx := bx - ax
	var dy := by - ay
	var d := sqrt(dx * dx + dy * dy)
	var steps := ceilf(d / SIGHT_STEP)
	var i := 1.0
	while i < steps:
		var t := i / steps
		var x := ax + dx * t
		var y := ay + dy * t
		for o in room.obstacles:
			if x > o.x0 and x < o.x1 and y > o.y0 and y < o.y1:
				return false
		i += 1.0
	return true
