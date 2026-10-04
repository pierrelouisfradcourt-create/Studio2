extends RefCounted
## Portage de tools/bots.mjs — utilitaires, géométrie et navigation.
## Les bots sont des « joueurs » automatiques qui ne lisent que ce qui se VOIT à l'écran. Ce
## fichier porte le bas de la pile : hachage, RNG local, normalisation, obstacles, contournement.
## Règles de portage : PORTAGE.md (tout nombre est un float, D6Trig, .get pour les clés absentes).

const U32 := 4294967296.0
const WALL_COMFORT := 70.0 # u : finir un mouvement près d'un mur est pénalisé
const WALL_PENALTY := 0.35
const NAV_MARGIN := 2.0 # u ajoutées au rayon pour les tests de passage
const NAV_CORNER := 16.0 # u de marge autour des coins d'obstacle
const ARRIVE_DIST := 6.0
const BLOCKED_CORNER_COST := 400.0 # u : un coin qu'on ne voit pas directement coûte un détour
const GRID_CELL := 40.0 # u : case de la grille de marche (salles à terrain bas)
const GRID_PULL := 8 # cases de chemin regardées pour viser droit devant (au lieu de zigzaguer de case en case)
const GRID_FAR := 0x7fff
const GRID_NEIGHBORS := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]
const HASH_BASIS := 2166136261
const HASH_PRIME := 16777619
const HASH_FINAL := 2246822519

## Hachage entier déterministe (variété des choix sans toucher au RNG de la partie).
static func mix_hash(values: Array) -> int:
	var h := HASH_BASIS
	for v in values:
		h = D6Js.imul(h ^ D6Js.u32(v), HASH_PRIME)
	h ^= h >> 15
	return D6Js.imul(h, HASH_FINAL)

## Champ numérique d'un objet ; absent = NaN (comme `undefined` dans une comparaison JavaScript :
## toujours fausse).
static func num(d: Dictionary, key: String) -> float:
	var v = d.get(key)
	return NAN if v == null else float(v)

## {x, y, l} : direction unitaire et longueur d'origine ; vecteur nul -> (0, 0, 0).
static func norm(x: float, y: float) -> Dictionary:
	var l := sqrt(x * x + y * y)
	if l > 1e-6:
		return {"x": x / l, "y": y / l, "l": l}
	return {"x": 0.0, "y": 0.0, "l": 0.0}

static func visible_enemies(game: Dictionary) -> Array:
	var out: Array = []
	for e in game.enemies:
		if not D6Js.truthy(e.get("dead")) and num(e, "spawnT") <= 0.0:
			out.append(e)
	return out

static func dist_to(p: Dictionary, o: Dictionary) -> float:
	return sqrt(D6Geo.dist2(p.x, p.y, o.x, o.y))

# ---------------------------------------------------------------- géométrie et navigation

## Une dalle de la méthode des dalles : resserre [tmin, tmax] (dans `span`) ; false = à côté.
static func _slab(o: float, d: float, lo: float, hi: float, span: PackedFloat64Array) -> bool:
	if absf(d) < 1e-9:
		return not (o < lo or o > hi)
	var t1 := (lo - o) / d
	var t2 := (hi - o) / d
	if t1 > t2:
		var sw := t1
		t1 = t2
		t2 = sw
	span[0] = maxf(span[0], t1)
	span[1] = minf(span[1], t2)
	return not (span[0] > span[1])

## Le segment [a, b] traverse-t-il le rectangle (méthode des dalles) ?
static func seg_hits_rect(ax: float, ay: float, bx: float, by: float, x0: float, y0: float, x1: float, y1: float) -> bool:
	var span := PackedFloat64Array([0.0, 1.0])
	if not _slab(ax, bx - ax, x0, x1, span):
		return false
	return _slab(ay, by - ay, y0, y1, span)

static func first_blocker(room: Dictionary, ax: float, ay: float, bx: float, by: float, margin: float):
	var best = null
	var best_d := INF
	for o in room.obstacles:
		if not seg_hits_rect(ax, ay, bx, by, o.x0 - margin, o.y0 - margin, o.x1 + margin, o.y1 + margin):
			continue
		var d := D6Geo.dist2(ax, ay, (o.x0 + o.x1) / 2.0, (o.y0 + o.y1) / 2.0)
		if d < best_d:
			best_d = d
			best = o
	return best

## Ligne de tir dégagée (aucun obstacle sur le segment).
static func clear_shot(room: Dictionary, ax: float, ay: float, bx: float, by: float) -> bool:
	return first_blocker(room, ax, ay, bx, by, 0.0) == null

## Direction de marche vers (tx, ty) en contournant un obstacle par le meilleur coin.
static func nav_dir(room: Dictionary, px: float, py: float, tx: float, ty: float, r: float) -> Dictionary:
	var margin := r + NAV_MARGIN
	var o = first_blocker(room, px, py, tx, ty, margin)
	if o == null:
		return norm(tx - px, ty - py)
	var c := r + NAV_CORNER
	var corners := [[o.x0 - c, o.y0 - c], [o.x1 + c, o.y0 - c], [o.x0 - c, o.y1 + c], [o.x1 + c, o.y1 + c]]
	var best = null
	var best_cost := INF
	for corner in corners:
		var cx: float = corner[0]
		var cy: float = corner[1]
		var leg := sqrt(D6Geo.dist2(px, py, cx, cy))
		if leg < ARRIVE_DIST:
			continue
		var direct: bool = first_blocker(room, px, py, cx, cy, margin) == null
		var cost := leg + sqrt(D6Geo.dist2(cx, cy, tx, ty)) + (0.0 if direct else BLOCKED_CORNER_COST)
		if cost < best_cost:
			best_cost = cost
			best = corner
	if best != null:
		return norm(best[0] - px, best[1] - py)
	return norm(tx - px, ty - py)

# ---------------------------------------------------------------- terrain bas (rivières, obstacles bas)
#
# Une rivière ou un obstacle bas se VOIT : le bot sait qu'on n'y marche pas. Les longs rubans d'eau
# ne se contournent pas « par le meilleur coin » comme un pilier : dans une salle à terrain bas, la
# marche suit un champ de distance (grille de GRID_CELL u) vers la cible, par les gués. Une salle
# sans terrain bas garde nav_dir, inchangé.

static var _grid := {"sig": "", "cols": 0, "rows": 0, "blocked": PackedByteArray(), "dist": PackedInt32Array(), "target": -1}

static func has_low(room: Dictionary) -> bool:
	var low = room.get("low")
	return low is Array and not low.is_empty()

## Le corps (rayon r) posé en (x, y) chevauche-t-il un terrain bas ?
static func inside_low(room: Dictionary, x: float, y: float, r: float) -> bool:
	var low = room.get("low")
	if low == null:
		return false
	for o in low:
		if x > o.x0 - r and x < o.x1 + r and y > o.y0 - r and y < o.y1 + r:
			return true
	return false

## Peut-on marcher tout droit de a à b (corps de rayon `margin`) : ni pilier ni terrain bas en travers ?
static func walk_clear(room: Dictionary, ax: float, ay: float, bx: float, by: float, margin: float) -> bool:
	if first_blocker(room, ax, ay, bx, by, margin) != null:
		return false
	var low = room.get("low")
	if low != null:
		for o in low:
			if seg_hits_rect(ax, ay, bx, by, o.x0 - margin, o.y0 - margin, o.x1 + margin, o.y1 + margin):
				return false
	return true

## Direction de MARCHE vers (tx, ty). Salle sans terrain bas : nav_dir (contournement par un coin).
## Avec terrain bas : tout droit si la voie est libre, sinon le long du champ de distance.
static func walk_dir(room: Dictionary, px: float, py: float, tx: float, ty: float, r: float) -> Dictionary:
	if not has_low(room):
		return nav_dir(room, px, py, tx, ty, r)
	var margin := r + NAV_MARGIN
	if walk_clear(room, px, py, tx, ty, margin):
		return norm(tx - px, ty - py)
	_grid_field(room, tx, ty, margin)
	var cols: int = _grid.cols
	var c := _grid_cell(px, py)
	var aim_x := tx
	var aim_y := ty
	var found := false
	for k in GRID_PULL:
		var n := _grid_next(c)
		if n < 0:
			break
		var nx := (float(n % cols) + 0.5) * GRID_CELL
		@warning_ignore("integer_division")
		var ny := (float(n / cols) + 0.5) * GRID_CELL
		if found and not walk_clear(room, px, py, nx, ny, margin):
			break
		aim_x = nx
		aim_y = ny
		found = true
		c = n
	return norm(aim_x - px, aim_y - py)

## Distance de marche (u, à la case près) du point à la cible du dernier champ calculé ; INF si
## la case n'est pas reliée. À lire juste après walk_dir ou grid_field vers la même cible.
static func grid_distance(x: float, y: float) -> float:
	var d: int = _grid.dist[_grid_cell(x, y)] if _grid.cols > 0 else GRID_FAR
	return INF if d >= GRID_FAR else float(d) * GRID_CELL

## Prépare le champ de distance de marche vers (tx, ty) (grid_distance le lit).
static func grid_field(room: Dictionary, tx: float, ty: float, r: float) -> void:
	_grid_field(room, tx, ty, r + NAV_MARGIN)

static func _grid_cell(x: float, y: float) -> int:
	var cx := int(clampf(floorf(x / GRID_CELL), 0.0, float(_grid.cols) - 1.0))
	var cy := int(clampf(floorf(y / GRID_CELL), 0.0, float(_grid.rows) - 1.0))
	return cy * int(_grid.cols) + cx

## Voisine de la case `c` la plus proche de la cible (sans couper un coin bloqué), ou -1.
static func _grid_next(c: int) -> int:
	var cols: int = _grid.cols
	var rows: int = _grid.rows
	var blocked: PackedByteArray = _grid.blocked
	var dist: PackedInt32Array = _grid.dist
	var cx := c % cols
	@warning_ignore("integer_division")
	var cy := c / cols
	var best: int = dist[c]
	var out := -1
	for d in GRID_NEIGHBORS:
		var nx: int = cx + d[0]
		var ny: int = cy + d[1]
		if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
			continue
		var n := ny * cols + nx
		if blocked[n] != 0 or dist[n] >= best:
			continue
		if d[0] != 0 and d[1] != 0 and (blocked[cy * cols + nx] != 0 or blocked[ny * cols + cx] != 0):
			continue
		best = dist[n]
		out = n
	return out

## (Re)calcule, si la salle ou la case cible a changé, les cases où l'on peut se tenir et la
## distance de chacune à la cible (parcours en largeur, 8 voisines, sans couper les coins).
static func _grid_field(room: Dictionary, tx: float, ty: float, margin: float) -> void:
	var sig := _grid_signature(room, margin)
	if sig != _grid.sig:
		_grid_build(room, margin)
		_grid.sig = sig
		_grid.target = -1
	var target := _grid_free_near(_grid_cell(tx, ty))
	if target == _grid.target:
		return
	_grid.target = target
	var cols: int = _grid.cols
	var rows: int = _grid.rows
	var blocked: PackedByteArray = _grid.blocked
	var dist: PackedInt32Array = _grid.dist
	dist.fill(GRID_FAR)
	var queue := PackedInt32Array()
	queue.resize(cols * rows)
	var head := 0
	var tail := 1
	queue[0] = target
	dist[target] = 0
	while head < tail:
		var c := queue[head]
		head += 1
		var cx := c % cols
		@warning_ignore("integer_division")
		var cy := c / cols
		for d in GRID_NEIGHBORS:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var n := ny * cols + nx
			if blocked[n] != 0 or dist[n] != GRID_FAR:
				continue
			if d[0] != 0 and d[1] != 0 and (blocked[cy * cols + nx] != 0 or blocked[ny * cols + cx] != 0):
				continue
			dist[n] = dist[c] + 1
			queue[tail] = n
			tail += 1
	_grid.dist = dist

static func _grid_signature(room: Dictionary, margin: float) -> String:
	var parts := PackedStringArray([str(room.w), str(room.h), str(margin)])
	for list in [room.obstacles, room.low]:
		for o in list:
			parts.append("%s,%s,%s,%s" % [o.x0, o.y0, o.x1, o.y1])
	return ";".join(parts)

static func _grid_build(room: Dictionary, margin: float) -> void:
	var cols := int(ceilf(room.w / GRID_CELL))
	var rows := int(ceilf(room.h / GRID_CELL))
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	for cy in rows:
		for cx in cols:
			var x := (float(cx) + 0.5) * GRID_CELL
			var y := (float(cy) + 0.5) * GRID_CELL
			var b: bool = x < room.pad + margin or x > room.w - room.pad - margin or y < room.pad + margin or y > room.h - room.pad - margin
			b = b or inside_obstacle(room, x, y, margin) or inside_low(room, x, y, margin)
			blocked[cy * cols + cx] = 1 if b else 0
	var dist := PackedInt32Array()
	dist.resize(cols * rows)
	_grid.cols = cols
	_grid.rows = rows
	_grid.blocked = blocked
	_grid.dist = dist

## La case elle-même si l'on peut s'y tenir, sinon la case libre la plus proche (anneaux croissants).
static func _grid_free_near(c: int) -> int:
	var cols: int = _grid.cols
	var rows: int = _grid.rows
	var blocked: PackedByteArray = _grid.blocked
	if blocked[c] == 0:
		return c
	var cx := c % cols
	@warning_ignore("integer_division")
	var cy := c / cols
	for ring in range(1, maxi(cols, rows)):
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue
				var nx := cx + dx
				var ny := cy + dy
				if nx >= 0 and ny >= 0 and nx < cols and ny < rows and blocked[ny * cols + nx] == 0:
					return ny * cols + nx
	return c

## Premier emplacement dont le bouton montre un gadget prêt (une charge au moins), ou -1.
static func ready_gadget(game: Dictionary) -> int:
	for i in D6Loadout.SLOTS:
		var view = D6Loadout.slot_view(game, i)
		if view != null and view.kind == "gadget" and view.ready:
			return i
	return -1

static func inside_obstacle(room: Dictionary, x: float, y: float, r: float) -> bool:
	for o in room.obstacles:
		if x > o.x0 - r and x < o.x1 + r and y > o.y0 - r and y < o.y1 + r:
			return true
	return false

static func wall_penalty(room: Dictionary, x: float, y: float) -> float:
	var m := minf(minf(x - room.pad, room.w - room.pad - x), minf(y - room.pad, room.h - room.pad - y))
	return WALL_PENALTY * (1.0 - m / WALL_COMFORT) if m < WALL_COMFORT else 0.0
