class_name D6Nav
extends RefCounted
## Portage de src/sim/nav.mjs.
## Navigation : champ de distance (BFS) vers le héros sur une grille de la salle, recalculé
## quelques fois par seconde. Un ennemi sans ligne de vue suit la pente du champ et
## contourne les piliers au lieu de pousser contre eux. Déterministe, sans allocation
## par image (tableaux typés réutilisés). Le champ connaît le TERRAIN BAS (room.low : rivières,
## obstacles bas) : un ennemi qui marche le contourne par les gués.
##
## Les tableaux typés JavaScript (Uint8Array, Int16Array, Int32Array) deviennent des tableaux
## compacts ; `cols`, `rows` et les indices de case sont des ENTIERS (ils ne servent qu'à indexer).

const CELL := 40.0 # u — taille d'une case de navigation
const INFLATE := 18.0 # u — marge autour des obstacles (rayon moyen d'un ennemi)
const REFRESH_TICKS := 15.0 # le champ est recalculé 4 fois par seconde
const UNREACHED := 0x7fff
const NEVER := -1e9 # lastTick d'un champ jamais calculé
const NEIGHBORS := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]

static func build_nav(room: Dictionary) -> Dictionary:
	var cols := int(ceilf(room.w / CELL))
	var rows := int(ceilf(room.h / CELL))
	var blocked := PackedByteArray()
	blocked.resize(cols * rows)
	for cy in range(rows):
		for cx in range(cols):
			var x := (cx + 0.5) * CELL
			var y := (cy + 0.5) * CELL
			var b: bool = x < room.pad + INFLATE or x > room.w - room.pad - INFLATE or y < room.pad + INFLATE or y > room.h - room.pad - INFLATE
			for o in room.obstacles:
				if x > o.x0 - INFLATE and x < o.x1 + INFLATE and y > o.y0 - INFLATE and y < o.y1 + INFLATE:
					b = true
			if not b and D6Physics.ground_blocked(room, x, y, INFLATE):
				b = true # terrain bas : on n'y marche pas
			blocked[cy * cols + cx] = 1 if b else 0
	var dist := PackedInt32Array()
	dist.resize(cols * rows)
	dist.fill(UNREACHED)
	var queue := PackedInt32Array()
	queue.resize(cols * rows)
	return {"cols": cols, "rows": rows, "blocked": blocked, "dist": dist, "queue": queue, "lastTick": NEVER}

static func _cell_of(nav: Dictionary, x: float, y: float) -> int:
	var cols: int = nav.cols
	var rows: int = nav.rows
	var cx := int(minf(cols - 1.0, maxf(0.0, floorf(x / CELL))))
	var cy := int(minf(rows - 1.0, maxf(0.0, floorf(y / CELL))))
	return cy * cols + cx

## Recalcule le champ de distance depuis la case du héros (BFS 8-connexe).
static func update_nav(game: Dictionary) -> void:
	var nav = game.room.get("nav")
	if nav == null or game.tick - nav.lastTick < REFRESH_TICKS:
		return
	nav.lastTick = game.tick
	var cols: int = nav.cols
	var rows: int = nav.rows
	var blocked: PackedByteArray = nav.blocked
	var dist: PackedInt32Array = nav.dist
	var queue: PackedInt32Array = nav.queue
	dist.fill(UNREACHED)
	var start := _cell_of(nav, game.player.x, game.player.y)
	var head := 0
	var tail := 0
	dist[start] = 0
	queue[tail] = start
	tail += 1
	while head < tail:
		var c := queue[head]
		head += 1
		var cx := c % cols
		@warning_ignore("integer_division")
		var cy := (c - cx) / cols
		for d in NEIGHBORS:
			var dx: int = d[0]
			var dy: int = d[1]
			var nx := cx + dx
			var ny := cy + dy
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var n := ny * cols + nx
			if blocked[n] != 0 or dist[n] != UNREACHED:
				continue
			# Pas de coupe de coin entre deux cases bloquées.
			if dx != 0 and dy != 0 and (blocked[cy * cols + nx] != 0 or blocked[ny * cols + cx] != 0):
				continue
			dist[n] = dist[c] + 1
			queue[tail] = n
			tail += 1
	# Rendus au champ : le portage ne dépend pas du partage par référence des tableaux compacts.
	nav.dist = dist
	nav.queue = queue

## Direction (unitaire, écrite dans out) vers la case voisine la plus proche du héros.
## Rend false si aucune pente utilisable (on garde alors la poursuite directe).
static func nav_direction(game: Dictionary, x: float, y: float, out: Dictionary) -> bool:
	var nav = game.room.get("nav")
	if nav == null:
		return false
	var cols: int = nav.cols
	var rows: int = nav.rows
	var dist: PackedInt32Array = nav.dist
	var blocked: PackedByteArray = nav.blocked
	var c := _cell_of(nav, x, y)
	var cx := c % cols
	@warning_ignore("integer_division")
	var cy := (c - cx) / cols
	var best := dist[c]
	var bx := -1
	var by := -1
	for d in NEIGHBORS:
		var dx: int = d[0]
		var dy: int = d[1]
		var nx := cx + dx
		var ny := cy + dy
		if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
			continue
		var n := ny * cols + nx
		if blocked[n] != 0 or dist[n] >= best:
			continue
		if dx != 0 and dy != 0 and (blocked[cy * cols + nx] != 0 or blocked[ny * cols + cx] != 0):
			continue
		best = dist[n]
		bx = nx
		by = ny
	if bx < 0:
		return false
	var tx := (bx + 0.5) * CELL - x
	var ty := (by + 0.5) * CELL - y
	var l := sqrt(tx * tx + ty * ty)
	if l == 0.0:
		l = 1.0
	out.x = tx / l
	out.y = ty / l
	return true
