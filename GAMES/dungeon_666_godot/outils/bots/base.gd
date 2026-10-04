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
