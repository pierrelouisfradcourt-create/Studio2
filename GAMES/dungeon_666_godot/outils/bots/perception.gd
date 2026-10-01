extends RefCounted
## Portage de tools/bots.mjs — PERCEPTION : ce que l'œil du joueur lit à l'écran (mouvement des
## ennemis, jauges de télégraphe, zones au sol, projectiles), traduit en « menaces » datées.
##
## Une menace est un dictionnaire {type, …} :
##   T_ZONE  — un coup unique dans une forme, entre t0 et t1 ;
##   T_POOL  — une flaque persistante : le danger est le temps passé dedans entre t0 et t1 ;
##   T_LUNGE — une ruée le long de l'axe d'un cône ;
##   T_MOVER — un corps ou un projectile en mouvement rectiligne.
## Le JavaScript porte le test d'une zone dans une fermeture ; ici la forme est décrite par des
## données (`k` + paramètres) et évaluée par zone_depth : mêmes opérations, même ordre.

const Base = preload("res://outils/bots/base.gd")

const T_ZONE := 0
const T_POOL := 1
const T_LUNGE := 2
const T_MOVER := 3
const K_DISC := 0
const K_RING := 1
const K_BAND := 2
const K_SEG := 3
const K_SECTOR := 4

const SAMPLE_HZ := 30.0 # résolution temporelle de l'anticipation
const REACTION_TIME := 0.15 # s : un danger n'est « vu » qu'après ce délai (réflexe humain)
const HORIZON := 0.7 # s d'anticipation des menaces
const TELE_IMMINENT_PROGRESS := 0.6 # jauge de télégraphe « presque pleine »
const DEFAULT_WINDUP_GUESS := 0.7 # s, durée supposée d'un télégraphe avant d'avoir sa vitesse
const IMMINENT_GUESS := 0.1 # s restantes supposées pour une jauge presque pleine jamais mesurée
const MIN_RATE_WINDOW := 0.05 # s d'observation avant de faire confiance à la vitesse de jauge
const ZONE_SLACK := 0.07 # s de marge avant l'impact d'une zone
const FRAME_SPAN := 1.0 / SAMPLE_HZ
const CHARGE_SPAN := 0.5 # s pendant lesquels une charge en ligne reste dangereuse
const ARROW_SPAN := 0.6 # s pendant lesquels une ligne d'archer reste dangereuse
const SAFETY_MARGIN := 4.0 # u ajoutées au rayon du héros dans les tests de zone
const EDGE_DEPTH := 0.02 # profondeur minimale d'un contact au bout d'une bande (jamais 0 = « dehors »)
const MOVER_PAD := 8.0 # u : portée de contact d'un ennemi lancé (ruée, charge)
const PROJECTILE_PAD := 3.0 # u de marge autour des projectiles
const FAST_MOVER_SPEED := 350.0 # u/s : au-delà, un ennemi « fonce » (ruée, charge)
const TELEPORT_SPEED := 2500.0 # u/s : au-delà, ce n'est pas une course mais une téléportation
const PROJECTILE_ALERT_PAD := 60.0 # u : préfiltre des projectiles qui passeront près
const PROJECTILE_ALERT_LEAD := 0.1 # s de trajet ajoutées au préfiltre des projectiles
const ARROW_LINE_PAD := 80.0 # u : on prolonge la ligne d'archer au-delà du héros (la flèche vole)

## Vitesse observée des ennemis (différence de positions), comme un œil qui suit le sprite.
static func track_motion(game: Dictionary, mem: Dictionary) -> void:
	var motion: Dictionary = mem.motion
	for e in game.enemies:
		if D6Js.truthy(e.get("dead")):
			continue
		var o = motion.get(e.id)
		if o == null:
			motion[e.id] = {"x": e.x, "y": e.y, "t": game.time, "vx": 0.0, "vy": 0.0}
			continue
		var dt: float = game.time - o.t
		if dt > 1e-6:
			o.vx = (e.x - o.x) / dt
			o.vy = (e.y - o.y) / dt
			o.x = e.x
			o.y = e.y
			o.t = game.time

## Temps restant estimé d'un télégraphe, d'après la vitesse de remplissage de sa jauge.
static func tele_remaining(game: Dictionary, mem: Dictionary, e: Dictionary) -> float:
	var prog: float = e.tele.progress
	var rec = mem.tele.get(e.id)
	if rec == null or prog < rec.p0 - 1e-6 or rec.shape != e.tele.get("shape"):
		rec = {"p0": prog, "t0": game.time, "shape": e.tele.get("shape")}
		mem.tele[e.id] = rec
	var elapsed: float = game.time - rec.t0
	if elapsed >= MIN_RATE_WINDOW and prog > rec.p0:
		var rate: float = (prog - rec.p0) / elapsed
		return maxf(0.0, (1.0 - prog) / rate)
	# Pas encore de mesure : jauge presque pleine = imminent.
	return IMMINENT_GUESS if prog > TELE_IMMINENT_PROGRESS else (1.0 - prog) * DEFAULT_WINDUP_GUESS

static func _zone(test: Dictionary, t0: float, t1: float) -> Dictionary:
	var th := test.duplicate()
	th.type = T_ZONE
	th.t0 = maxf(0.0, t0)
	th.t1 = t1
	return th

## Flaque persistante : le danger est le TEMPS passé dedans entre t0 et t1 (pas un coup unique).
static func _pool(test: Dictionary, t0: float, t1: float) -> Dictionary:
	var th := test.duplicate()
	th.type = T_POOL
	th.t0 = maxf(0.0, t0)
	th.t1 = t1
	return th

## Profondeur (0..1) d'un point dans un disque de rayon `rr` ; 0 = dehors.
static func disc_depth(x: float, y: float, cx: float, cy: float, rr: float) -> float:
	var d2 := D6Geo.dist2(x, y, cx, cy)
	return 1.0 - sqrt(d2) / rr if d2 < rr * rr else 0.0

static func _seg_depth(x: float, y: float, th: Dictionary) -> float:
	var hw: float = th.hw
	var d2 := D6Geo.point_seg_dist2(x, y, th.ax, th.ay, th.bx, th.by)
	return 1.0 - sqrt(d2) / hw if d2 < hw * hw else 0.0

static func _ring_depth(x: float, y: float, th: Dictionary) -> float:
	var d := sqrt(D6Geo.dist2(x, y, th.cx, th.cy))
	if d < th.outer + th.r and d > th.inner - th.r:
		return 1.0 - absf(d - (th.outer + th.inner) / 2.0) / ((th.outer - th.inner) / 2.0 + th.r)
	return 0.0

## Profondeur (0..1) d'un corps de rayon r dans une zone 'line' : le RECTANGLE dessiné (même
## géométrie que projectiles in_hazard). Dedans, 1 au milieu de la bande, ~0 à son bord.
## Cosinus et sinus de l'angle sont ceux de D6Trig, calculés une fois à la création de la menace.
static func _band_depth(x: float, y: float, th: Dictionary) -> float:
	var c: float = th.c
	var s: float = th.s
	var r: float = th.r
	var dx: float = x - th.cx
	var dy: float = y - th.cy
	var u := dx * c + dy * s # le long de l'axe
	var v := absf(-dx * s + dy * c) # en travers
	var half: float = th.width / 2.0
	var du: float = -u if u < 0.0 else (u - th.length if u > th.length else 0.0)
	var dv: float = v - half if v > half else 0.0
	var d2 := du * du + dv * dv
	if d2 >= r * r and d2 > 0.0:
		return 0.0
	return maxf(EDGE_DEPTH, 1.0 - v / (half + r))

## Secteur « de zone » (tele.area, ex. le fouet de Minos) : arc et brèche lus sur le dessin.
static func _sector_depth(x: float, y: float, th: Dictionary) -> float:
	var dx: float = x - th.cx
	var dy: float = y - th.cy
	var d := sqrt(dx * dx + dy * dy)
	if d >= th.reach:
		return 0.0
	if d > th.r and th.half < PI:
		var slack := D6Trig.asin(D6Geo.clampv(th.r / d, 0.0, 1.0))
		if absf(D6Geo.angle_diff(th.angle, D6Trig.atan2(dy, dx))) > th.half + slack:
			return 0.0
	return 1.0 - d / th.reach

## Profondeur (0..1) du point dans la forme d'une menace T_ZONE ou T_POOL.
static func zone_depth(th: Dictionary, x: float, y: float) -> float:
	match th.k:
		K_DISC:
			return disc_depth(x, y, th.cx, th.cy, th.rr)
		K_BAND:
			return _band_depth(x, y, th)
		K_SEG:
			return _seg_depth(x, y, th)
		K_RING:
			return _ring_depth(x, y, th)
	return _sector_depth(x, y, th)

## Temps restant d'une zone, lu sur ce que montre l'écran : sa jauge (hazard_progress, celle
## que dessine le rendu) et le temps écoulé depuis son apparition. Jauge linéaire : la règle
## de trois donne le temps restant sans lire la durée cachée du télégraphe.
static func _hazard_remaining(h: Dictionary) -> float:
	var prog := D6Projectiles.hazard_progress(h)
	return 0.0 if prog >= 1.0 else (h.t * (1.0 - prog)) / prog

## Forme de la zone `h`, rayon du héros `r` compris.
static func _hazard_test(h: Dictionary, r: float) -> Dictionary:
	var shape = h.get("shape")
	if shape == "circle":
		return {"k": K_DISC, "cx": h.x, "cy": h.y, "rr": h.r + r}
	if shape == "ring":
		return {"k": K_RING, "cx": h.x, "cy": h.y, "outer": h.r, "inner": h.inner, "r": r}
	# Bande 'line' : le RECTANGLE dessiné (et touché par la sim), pas une capsule.
	return {"k": K_BAND, "cx": h.x, "cy": h.y, "c": D6Trig.cos(h.angle), "s": D6Trig.sin(h.angle), "length": h.length, "width": h.width, "r": r}

## Menaces d'une zone : son impact (télégraphe), puis, pour une zone persistante, la flaque qui
## reste au sol. Une flaque allumée se lit à sa jauge de temps restant (dessinée par le rendu).
static func _hazard_threats(h: Dictionary, r: float, out: Array) -> void:
	if D6Js.truthy(h.get("done")) or not D6Js.truthy(h.get("hitsPlayer")):
		return
	var test := _hazard_test(h, r)
	if D6Js.truthy(h.get("burning")):
		out.append(_pool(test, 0.0, D6Projectiles.linger_left(h) * Base.num(h, "linger")))
		return
	if h.t < REACTION_TIME:
		return
	var t_i := maxf(0.0, _hazard_remaining(h))
	if t_i > HORIZON:
		return
	out.append(_zone(test, t_i - ZONE_SLACK, t_i + FRAME_SPAN))
	if Base.num(h, "linger") > 0.0:
		out.append(_pool(test, t_i, t_i + h.linger))

## Ruée télégraphiée par un cône : le corps de l'ennemi file le long de l'axe du cône.
static func _lunge_threat(e: Dictionary, tele: Dictionary, t_i: float, r: float) -> Dictionary:
	return {
		"type": T_LUNGE, "x": e.x, "y": e.y, "dx": D6Trig.cos(tele.angle), "dy": D6Trig.sin(tele.angle),
		"len": maxf(0.0, tele.range - e.r), "t0": t_i, "rad": e.r + r + MOVER_PAD,
	}

static func _line_threat(game: Dictionary, e: Dictionary, tele: Dictionary, t_i: float, r: float) -> Dictionary:
	var length: float = tele.length
	if e.kind == "archer":
		# La ligne d'un archer est courte, mais la flèche vole au-delà : on l'extrapole.
		length = maxf(length, Base.dist_to(game.player, e) + ARROW_LINE_PAD)
	var ex: float = e.x + D6Trig.cos(tele.angle) * length
	var ey: float = e.y + D6Trig.sin(tele.angle) * length
	var hw: float = tele.width / 2.0 + r
	var span := ARROW_SPAN if e.kind == "archer" else CHARGE_SPAN
	return _zone({"k": K_SEG, "ax": e.x, "ay": e.y, "bx": ex, "by": ey, "hw": hw}, t_i - ZONE_SLACK, t_i + span)

## Secteur « de zone » : le corps ne bouge pas, tout le secteur dessiné frappe d'un coup à la
## fin de la jauge.
static func _sector_threat(e: Dictionary, tele: Dictionary, t_i: float, r: float) -> Dictionary:
	var test := {"k": K_SECTOR, "cx": e.x, "cy": e.y, "half": tele.arc / 2.0, "reach": tele.range + r, "angle": tele.angle, "r": r}
	return _zone(test, t_i - ZONE_SLACK, t_i + FRAME_SPAN)

static func _tele_threat(game: Dictionary, mem: Dictionary, e: Dictionary, r: float):
	var tele: Dictionary = e.tele
	var t_i := tele_remaining(game, mem, e)
	if t_i > HORIZON or game.time - mem.tele[e.id].t0 < REACTION_TIME:
		return null
	var shape = tele.get("shape")
	if shape == "cone" and D6Js.truthy(tele.get("area")):
		return _sector_threat(e, tele, t_i, r)
	if shape == "cone":
		return _lunge_threat(e, tele, t_i, r)
	if shape == "line":
		return _line_threat(game, e, tele, t_i, r)
	# Cercle : celui du possédé (explosion) et ceux du boss (anneau de projectiles qui naît dans
	# le cercle) font mal ; l'alerte d'invocation est marquée inoffensive.
	if D6Js.truthy(tele.get("harmless")) or (e.kind != "exploder" and not D6Js.truthy(e.get("boss"))):
		return null
	return _zone({"k": K_DISC, "cx": e.x, "cy": e.y, "rr": tele.r + r}, t_i - ZONE_SLACK, t_i + FRAME_SPAN)

static func _mover_threat(mem: Dictionary, e: Dictionary, r: float):
	# Un corps EN L'AIR (bond, ombre détachée) ne blesse pas : seul son cercle d'atterrissage compte.
	if D6Js.truthy(e.get("airborne")):
		return null
	var m = mem.motion.get(e.id)
	if m == null or m.vx * m.vx + m.vy * m.vy < FAST_MOVER_SPEED * FAST_MOVER_SPEED:
		return null
	if m.vx * m.vx + m.vy * m.vy > TELEPORT_SPEED * TELEPORT_SPEED:
		return null # il a disparu / réapparu
	return {"type": T_MOVER, "x": e.x, "y": e.y, "vx": m.vx, "vy": m.vy, "rad": e.r + r + MOVER_PAD}

static func _projectile_threat(pr: Dictionary, p: Dictionary):
	var v2: float = pr.vx * pr.vx + pr.vy * pr.vy
	if v2 > 1e-6 and Base.num(pr, "traveled") / sqrt(v2) < REACTION_TIME:
		return null # pas encore vu
	var rad: float = pr.r + p.r + PROJECTILE_PAD
	# Préfiltre : point le plus proche de la trajectoire dans l'horizon.
	var rx: float = pr.x - p.x
	var ry: float = pr.y - p.y
	var tc := D6Geo.clampv(-(rx * pr.vx + ry * pr.vy) / v2, 0.0, HORIZON) if v2 > 1e-6 else 0.0
	var cx: float = rx + pr.vx * tc
	var cy: float = ry + pr.vy * tc
	var alert := rad + PROJECTILE_ALERT_PAD + sqrt(v2) * PROJECTILE_ALERT_LEAD
	if cx * cx + cy * cy > alert * alert:
		return null
	return {"type": T_MOVER, "x": pr.x, "y": pr.y, "vx": pr.vx, "vy": pr.vy, "rad": rad}

## Toutes les menaces visibles qui peuvent frapper dans l'horizon.
static func perceive_threats(game: Dictionary, mem: Dictionary) -> Array:
	var p: Dictionary = game.player
	var r: float = p.r + SAFETY_MARGIN
	var out: Array = []
	for h in game.hazards:
		_hazard_threats(h, r, out)
	for e in game.enemies:
		if D6Js.truthy(e.get("dead")) or Base.num(e, "spawnT") > 0.0:
			continue
		if e.get("tele") != null:
			var th = _tele_threat(game, mem, e, r)
			if th != null:
				out.append(th)
		else:
			mem.tele.erase(e.id)
		var mv = _mover_threat(mem, e, p.r)
		if mv != null:
			out.append(mv)
	for pr in game.projectiles:
		if pr.get("owner") != "enemy" or D6Js.truthy(pr.get("dead")):
			continue
		var th2 = _projectile_threat(pr, p)
		if th2 != null:
			out.append(th2)
	return out
