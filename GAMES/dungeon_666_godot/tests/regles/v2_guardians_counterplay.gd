extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_guardians_counterplay.test.mjs.
## Contrat du CONTRE-JEU des Gardiens ajoutés, tel que le joueur le LIT à l'écran :
##   - une zone 'line' touche exactement le RECTANGLE dessiné, corps du héros compris : la brèche
##     de la sentence de Minos est une vraie brèche, le dos du souffle de Cerbère et du poing
##     d'Éphialte est sûr, le bord rouge touche ;
##   - une morsure de Cerbère ne mord que dans son cône dessiné ;
##   - une transition de phase éteint aussi les braises d'Éphialte ;
##   - les geôliers d'Éphialte : un appel par phase (le bouclier ne se recycle pas) ;
##   - le point faible (exposition) est un statut propre, qui finit avec la fenêtre de punition
##     et ne se mélange pas à la vulnérabilité d'une bénédiction ;
##   - le tremblement des zones (caméra et effets du rendu web) : sans équivalent ici.

const UNIT_FLOOR := 18.0
const SPAWN_WAIT := 240 # pas d'attente au plus de l'apparition du Gardien
const DT := 1.0 / 60.0
const U32 := 4294967296.0
const LCG_MULT := 1103515245
const LCG_ADD := 12345
const LCG_SEED := 12345
const LINE_CASES := 600
const EDGE_SKIP := 0.5 # u : pile sur le bord, arrondi flottant, sans objet
const CHARM := 0.3
const BITE_DISTS := [55.0, 65.0, 75.0, 90.0, 110.0, 140.0]
const BITE_OFFSETS := [0.0, 15.0, 40.0, 50.0, 60.0, 75.0, 90.0, 120.0]

static func tests(h) -> void:
	h.test("zones 'line' : la touche suit exactement le rectangle dessiné, corps du héros compris (propriété)", func(): _t_zones_line(h))
	h.test("minos : la brèche DESSINÉE de la sentence protège sur toute sa largeur ; le bord rouge touche", func(): _t_minos_breche(h))
	for cas in [["cerbere", "souffle", "cerbereFlame"], ["colosse", "poing", "colosseFist"]]:
		h.test("%s : %s — collé au DOS du Gardien, épargné ; dans la bande, touché" % [cas[0], cas[1]], func(): _t_dos(h, cas[0], cas[1], cas[2]))
	h.test("cerbere : une morsure ne mord JAMAIS hors de son cône dessiné (corps compris), et mord dedans", func(): _t_morsures(h))
	h.test("colosse : la transition de phase éteint les braises — aucune ne pulse ni ne frappe pendant le rugissement", func(): _t_braises_transition(h))
	h.test("colosse : geôliers, un appel par phase (le bouclier ne se recycle pas dès la chute des archers)", func(): _t_geoliers(h))
	h.test("point faible : statut propre, fini avec la fenêtre de punition, cumulé sans mélange avec le Charme fatal", func(): _t_point_faible(h))
	h.test("tremblement : une zone loin du héros secoue moins ; un lot de zones = une secousse ; les braises ne secouent pas", func():
		h.non_portable("teste la caméra et les effets du rendu web (src/render/camera.mjs, fx.mjs : trauma)"))
	h.test("tremblement mesuré en combat : jamais saturé plus de 5 % du temps contre Minos et Éphialte (bot skilled)", func():
		h.non_portable("mesure le trauma de la caméra du rendu web (src/render/camera.mjs, fx.mjs) pendant un combat"))

# ---------------------------------------------------------------- outillage

static func _n(d: Dictionary, key: String) -> float:
	var v = d.get(key)
	return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) else 0.0

static func _step(g: Dictionary) -> void:
	D6Game.step_game(g, D6Game.empty_input())

static func _count(evs: Array, type: String, champ: String = "", valeur = null) -> int:
	return evs.filter(func(ev): return ev.type == type and (champ == "" or ev.get(champ) == valeur)).size()

static func _of_kind(g: Dictionary, kind: String) -> Array:
	return g.hazards.filter(func(z): return z.get("kind") == kind)

static func _wall(amount: float) -> Dictionary:
	return {"kind": "wall", "amount": amount}

static func _find_boss(g: Dictionary):
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")):
			return e
	return null

## Partie d'entraînement contre le modèle `kind` (rotation forcée), Gardien apparu.
## Rend {g, boss} ; boss est null (et le test rouge) s'il manque.
static func _boss_game(h, kind: String) -> Dictionary:
	var g: Dictionary = h.partie({"seed": 3.0, "startFloor": UNIT_FLOOR, "practice": true, "tuning": {"guardians": {"rotation": [kind]}}})
	var i := 0
	while i < SPAWN_WAIT and not g.enemies.any(func(e): return D6Js.truthy(e.get("boss")) and not (e.spawnT > 0.0)):
		_step(g)
		i += 1
	var boss = _find_boss(g)
	if not h.ok(boss != null and boss.kind == kind, "%s : Gardien présent" % kind):
		boss = null
	return {"g": g, "boss": boss}

## Gardien seul, phase et pattern imposés ; héros à distance (invulnérable si demandé).
static func _isolate(g: Dictionary, boss: Dictionary, phase: float = 1.0, pattern: String = "rest", invulnerable: bool = true) -> void:
	g.enemies = [boss]
	g.spawns.clear()
	g.hazards.clear()
	g.projectiles.clear()
	g.pickups.clear()
	boss.phase = phase
	boss.invuln = 0.0
	boss.tele = null
	boss.restFor = null
	D6BossCommon.set_state(boss, pattern)
	boss.pattern = pattern
	var p: Dictionary = g.player
	p.x = minf(g.room.w - 120.0, boss.x + 260.0)
	p.y = minf(g.room.h - 120.0, boss.y + 160.0)
	p.iframes = 1e9 if invulnerable else 0.0
	g.events.clear()

## Joue tant que `keep()` est vrai en clouant le héros en (x, y) ; rend les coups reçus de `source`.
static func _hold_and_count(h, g: Dictionary, x: float, y: float, seconds: float, keep: Callable, source: String) -> int:
	var p: Dictionary = g.player
	var hurt := 0
	for i in h.ticks(seconds):
		if not keep.call():
			break
		p.x = x
		p.y = y
		p.vx = 0.0
		p.vy = 0.0
		_step(g)
		hurt += _count(g.events, "playerHurt", "source", source)
		g.events.clear()
	return hurt

# ---------------------------------------------------------------- géométrie des zones 'line'

## Référence INDÉPENDANTE du code de simulation : les quatre coins tracés par le rendu
## (lineEdge), puis « le disque mord-il ce polygone ? » (centre dedans, ou plus près d'un bord
## que son rayon).
static func _drawn_corners(z: Dictionary) -> Array:
	var c := D6Trig.cos(z.angle)
	var s := D6Trig.sin(z.angle)
	var hw: float = z.width / 2.0
	return [
		[z.x - s * hw, z.y + c * hw],
		[z.x + c * z.length - s * hw, z.y + s * z.length + c * hw],
		[z.x + c * z.length + s * hw, z.y + s * z.length - c * hw],
		[z.x + s * hw, z.y - c * hw],
	]

static func _disc_touches_drawn(z: Dictionary, x: float, y: float, r: float) -> Dictionary:
	var q := _drawn_corners(z)
	var sign_seen := 0.0
	var inside := true
	var best := INF
	for i in 4:
		var a: Array = q[i]
		var b: Array = q[(i + 1) % 4]
		var cross: float = (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])
		var sg := signf(cross)
		if sg != 0.0:
			if sign_seen == 0.0:
				sign_seen = sg
			elif sg != sign_seen:
				inside = false
		best = minf(best, sqrt(D6Geo.point_seg_dist2(x, y, a[0], a[1], b[0], b[1])))
	return {"touches": inside or best < r, "margin": -best if inside else best - r}

## Générateur déterministe propre au test (le RNG de la partie n'est pas touché) :
## s = (Math.imul(s, 1103515245) + 12345) >>> 0, rendu dans [0, 1).
static func _rnd(etat: Dictionary) -> float:
	etat.s = (D6Js.imul(etat.s, LCG_MULT) + LCG_ADD) & D6Js.MASK
	return etat.s / U32

## Une bande tirée au hasard, et un point tiré autour d'elle (souvent près de ses bords et de ses bouts).
static func _tirer_cas(etat: Dictionary, r: float) -> Dictionary:
	# Tirages dans l'ordre du littéral JavaScript : x, y, angle, length, width.
	var zx := 300.0 + _rnd(etat) * 600.0
	var zy := 250.0 + _rnd(etat) * 400.0
	var angle := _rnd(etat) * PI * 2.0
	var length := 80.0 + _rnd(etat) * 400.0
	var width := 40.0 + _rnd(etat) * 160.0
	var z := {"shape": "line", "x": zx, "y": zy, "angle": angle, "length": length, "width": width}
	var u: float = -z.width + _rnd(etat) * (z.length + 2.0 * z.width)
	var v: float = (_rnd(etat) - 0.5) * (z.width + 4.0 * r)
	var c := D6Trig.cos(z.angle)
	var s := D6Trig.sin(z.angle)
	return {"zone": z, "x": z.x + c * u - s * v, "y": z.y + s * u + c * v}

static func _t_zones_line(h) -> void:
	var g: Dictionary = h.partie({"seed": 21.0, "startFloor": 2.0})
	g.enemies.clear()
	g.spawns.clear()
	var p: Dictionary = g.player
	var etat := {"s": LCG_SEED}
	var hits := 0
	var misses := 0
	var checked := 0
	for k in LINE_CASES:
		var cas := _tirer_cas(etat, p.r)
		var z: Dictionary = cas.zone
		var ref := _disc_touches_drawn(z, cas.x, cas.y, p.r)
		if absf(ref.margin) < EDGE_SKIP:
			continue
		checked += 1
		g.hazards.clear()
		var probe: Dictionary = z.duplicate()
		probe.merge({"delay": 0.0, "damage": 1.0, "kind": "probeLine"}, true)
		D6Combat.spawn_hazard(g, probe)
		p.x = cas.x
		p.y = cas.y
		p.iframes = 0.0
		p.hp = p.maxHp
		p.state = "idle"
		g.events.clear()
		D6Projectiles.update_hazards(g, D6Data.DT)
		var hurt: bool = _count(g.events, "playerHurt", "source", "probeLine") > 0
		h.egal(hurt, ref.touches, "bande %s ; héros (%.1f, %.1f) : marge %.2f u" % [str(z), cas.x, cas.y, ref.margin])
		if hurt:
			hits += 1
		else:
			misses += 1
	h.ok(checked > 500 and hits > 100 and misses > 100, "échantillon : %d cas, %d touchés, %d épargnés" % [checked, hits, misses])

## Coups de la sentence reçus par un héros dont le corps est à `offset_from_edge` u du bord rouge
## de la brèche du milieu (négatif = il mord dessus). -1 si la situation n'a pas pu être posée.
static func _sentence_hits(h, offset_from_edge: float) -> int:
	var b := _boss_game(h, "minos")
	if b.boss == null:
		return -1
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, 1.0, "sentence", false)
	_step(g)
	g.events.clear()
	var s: Dictionary = g.tuning.boss.minos.sentence
	var bands := _of_kind(g, "minosSentence")
	if not h.ok(bands.size() > 0, "la sentence est posée"):
		return -1
	var horiz: bool = absf(D6Trig.sin(bands[0].angle)) < 1e-9
	var axis := func(z): return z.y if horiz else z.x
	var along := func(z): return z.x if horiz else z.y
	# Bande du milieu : ses deux segments encadrent la brèche (phase 1 : brèches alignées).
	var axes: Array = []
	for z in bands:
		if not axes.has(axis.call(z)):
			axes.append(axis.call(z))
	axes.sort()
	var mid: float = axes[axes.size() / 2]
	var segs: Array = bands.filter(func(z): return axis.call(z) == mid)
	segs.sort_custom(func(a, c): return along.call(a) < along.call(c))
	if not h.egal(segs.size(), 2, "une bande = deux segments autour de sa brèche"):
		return -1
	var gap0: float = along.call(segs[0]) + segs[0].length
	h.ok(absf(along.call(segs[1]) - gap0 - s.breach) < 1e-6, "brèche dessinée de la largeur du tuning")
	var c: float = gap0 + g.player.r + offset_from_edge
	var x: float = c if horiz else mid
	var y: float = mid if horiz else c
	return _hold_and_count(h, g, x, y, 4.0, func(): return boss.state == "sentence", "minosSentence")

static func _t_minos_breche(h) -> void:
	for off in [1.0, 10.0, 40.0, 80.0, 150.0]:
		h.egal(_sentence_hits(h, off), 0, "corps à %s u du bord rouge, dans la brèche : épargné" % D6Js.num_str(off))
	h.ok(_sentence_hits(h, -4.0) >= 1, "corps qui mord de 4 u sur le bord rouge : touché")

## Coups reçus de `source` : collé au dos du Gardien (à `gap` u de son corps) ou devant, dans la bande.
static func _line_hits(h, kind: String, pattern: String, source: String, behind: bool, gap: float) -> int:
	var b := _boss_game(h, kind)
	if b.boss == null:
		return -1
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, 1.0, "rest", false)
	var p: Dictionary = g.player
	p.x = boss.x + 220.0
	p.y = boss.y
	boss.restFor = 99.0
	_step(g)
	D6BossCommon.set_state(boss, pattern)
	boss.pattern = pattern
	_step(g)
	g.events.clear()
	var lines := _of_kind(g, source)
	if not h.ok(lines.size() > 0, "%s : %s posé" % [kind, pattern]):
		return -1
	var aim: float = lines[lines.size() / 2].angle
	var a: float = aim + PI if behind else aim
	var d: float = boss.r + p.r + gap if behind else boss.r + p.r + 120.0
	return _hold_and_count(h, g, boss.x + D6Trig.cos(a) * d, boss.y + D6Trig.sin(a) * d, 3.0, func(): return boss.state == pattern, source)

static func _t_dos(h, kind: String, pattern: String, source: String) -> void:
	for gap in [1.0, 10.0, 25.0]:
		h.egal(_line_hits(h, kind, pattern, source, true, gap), 0, "dos, à %s u de son corps : épargné" % D6Js.num_str(gap))
	h.ok(_line_hits(h, kind, pattern, source, false, 0.0) >= 1, "devant, dans la bande : touché")

# ---------------------------------------------------------------- morsures de Cerbère

## Une morsure, héros figé à (dist, off_deg) de l'axe du cône affiché une fois la visée
## verrouillée. Rend {placed, inCone, bitten}.
static func _une_morsure(h, dist: float, off_deg: float) -> Dictionary:
	var out := {"placed": false, "inCone": false, "bitten": 0}
	var b := _boss_game(h, "cerbere")
	if b.boss == null:
		return out
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	var m: Dictionary = g.tuning.boss.cerbere.morsures
	_isolate(g, boss, 1.0, "morsures", false)
	var p: Dictionary = g.player
	p.x = boss.x + 120.0
	p.y = boss.y
	var px := 0.0
	var py := 0.0
	for i in h.ticks(2.5):
		if not (boss.patternStep < 1.0):
			break
		var t = boss.get("tele")
		if not out.placed and t != null and boss.get("sub") == "windup" and boss.subT >= m.windup * m.lockAt + DT:
			# Visée verrouillée : le héros se fige à (dist, off_deg) de l'axe du cône affiché.
			var a: float = t.angle + (off_deg * PI) / 180.0
			px = boss.x + D6Trig.cos(a) * dist
			py = boss.y + D6Trig.sin(a) * dist
			out.placed = true
			out.inCone = D6Geo.in_sector(px, py, boss.x, boss.y, t.range, t.angle, t.arc, p.r)
		if out.placed:
			p.x = px
			p.y = py
			p.vx = 0.0
			p.vy = 0.0
		_step(g)
		out.bitten += _count(g.events, "playerHurt", "source", "cerbereBite")
		g.events.clear()
	return out

static func _t_morsures(h) -> void:
	var outside := 0
	var inside_bitten := 0
	var inside_count := 0
	for dist in BITE_DISTS:
		for off_deg in BITE_OFFSETS:
			var r := _une_morsure(h, dist, off_deg)
			if not h.ok(r.placed, "la morsure a été armée"):
				continue
			if not r.inCone:
				h.egal(r.bitten, 0, "hors du cône (dist %s, %s°) : mordu" % [D6Js.num_str(dist), D6Js.num_str(off_deg)])
				outside += 1
			elif off_deg <= 15.0 and dist <= 110.0:
				inside_count += 1
				if r.bitten > 0:
					inside_bitten += 1
	h.ok(outside >= 15, "cas hors du cône : %d" % outside)
	h.egal(inside_bitten, inside_count, "dans l'axe du cône et à portée : mordu %d/%d" % [inside_bitten, inside_count])

# ---------------------------------------------------------------- Éphialte : braises et geôliers

static func _t_braises_transition(h) -> void:
	var b := _boss_game(h, "colosse")
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	var d: Dictionary = g.tuning.boss.colosse
	_isolate(g, boss, 2.0, "eboulis")
	for i in h.ticks(d.eboulis.delayMax + 0.2):
		_step(g)
		g.events.clear()
	var lit: Array = D6Js.nz(boss.get("pools"), []).filter(func(pool): return not D6Js.truthy(pool.get("rock")))
	if not h.ok(lit.size() > 0, "des braises brûlent avant la transition"):
		return
	# Le héros se tient sur une braise allumée, vulnérable : ce qui y frapperait le toucherait.
	var spot: Dictionary = lit[0]
	boss.hp = floorf(boss.maxHp * d.phase3At) - 1.0
	_step(g)
	h.egal(boss.phase, 3.0)
	h.egal(boss.state, "roar")
	h.egal(D6Js.nz(boss.get("pools"), []).size(), 0, "braises éteintes")
	g.events.clear()
	h.egal(_braises_pendant_le_rugissement(h, g, boss, spot), 0, "aucune braise télégraphiée pendant le rugissement")

static func _braises_pendant_le_rugissement(h, g: Dictionary, boss: Dictionary, spot: Dictionary) -> int:
	var p: Dictionary = g.player
	var embers := 0
	for i in h.ticks(g.tuning.boss.colosse.transition + 0.1):
		if boss.state != "roar":
			break
		p.x = spot.x
		p.y = spot.y
		p.iframes = 0.0
		_step(g)
		embers += g.hazards.filter(func(z): return z.get("kind") == "colosseEmber" and not D6Js.truthy(z.get("done"))).size()
		for ev in g.events:
			h.ok(not (ev.type == "hazardFire" and ev.get("kind") == "colosseEmber"), "braise qui frappe pendant la transition")
			h.ok(not (ev.type == "playerHurt" and ev.get("source") == "colosseEmber"), "brûlé par une braise pendant la transition")
		g.events.clear()
	return embers

## Appels de geôliers en `seconds` ; les geôliers tombent dès qu'ils apparaissent (rien
## n'empêcherait un nouvel appel) et le Gardien reste dans sa phase.
static func _calls_during(h, g: Dictionary, boss: Dictionary, seconds: float) -> int:
	var calls := 0
	for i in h.ticks(seconds):
		_step(g)
		calls += _count(g.events, "bossSummon", "id", boss.id)
		g.events.clear()
		for e in g.enemies:
			if D6Js.truthy(e.get("summoned")) and not e.dead and not (e.spawnT > 0.0):
				D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 1e9, "dirX": 1.0, "dirY": 0.0})
		boss.hp = boss.maxHp # reste dans sa phase
	return calls

static func _t_geoliers(h) -> void:
	var b := _boss_game(h, "colosse")
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	var d: Dictionary = g.tuning.boss.colosse
	h.egal(d.geoliers.callsPerPhase, 1.0)
	_isolate(g, boss, 2.0, "rest")
	h.egal(_calls_during(h, g, boss, 60.0), 1, "phase 2 : un seul appel en 60 s")
	# Phase 3 : un nouvel appel est permis, une fois.
	boss.hp = floorf(boss.maxHp * d.phase3At) - 1.0
	boss.phase = 2.0
	_step(g)
	h.egal(boss.phase, 3.0)
	g.events.clear()
	g.spawns.clear()
	g.enemies = [boss]
	h.egal(_calls_during(h, g, boss, 60.0), 1, "phase 3 : un seul appel en 60 s")

# ---------------------------------------------------------------- point faible et vulnérabilité

static func _t_point_faible(h) -> void:
	var b := _boss_game(h, "colosse")
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, 1.0, "rest")
	boss.restFor = 99.0
	var base: float = D6Combat.damage_enemy(g, boss, _wall(100.0))
	# Charme seul : vulnérable, mais aucun point faible (rien de doré à frapper).
	boss.vuln = 4.0
	boss.vulnMult = CHARM
	h.ok(not (_n(boss, "exposed") > 0.0), "Charme seul : pas de point faible exposé")
	h.ok(absf(D6Combat.damage_enemy(g, boss, _wall(100.0)) - base * (1.0 + CHARM)) <= 1.0)
	_point_faible_et_charme(h, g, boss, base)
	_point_faible_et_transition(h, g, boss)

## Poing : le bras se coince ; on pose un Charme de 4 s au début de la récupération exposée.
static func _point_faible_et_charme(h, g: Dictionary, boss: Dictionary, base: float) -> void:
	var d: Dictionary = g.tuning.boss.colosse
	_isolate(g, boss, 1.0, "poing")
	boss.vuln = 0.0
	boss.vulnMult = 0.0
	var charmed := false
	for i in h.ticks(8.0):
		if boss.state != "poing":
			break
		_step(g)
		g.events.clear()
		if boss.get("sub") == "recover" and not charmed:
			charmed = true
			h.ok(_n(boss, "exposed") > 0.0 and boss.vuln > 0.0, "bras coincé : exposé (et statut « vulnérable » levé)")
			boss.vuln = maxf(boss.vuln, 4.0)
			boss.vulnMult = maxf(boss.vulnMult, CHARM)
			var both: float = D6Combat.damage_enemy(g, boss, _wall(100.0))
			h.ok(absf(both - base * (1.0 + CHARM) * (1.0 + d.poing.exposedMult)) <= 2.0, "exposé + Charme : %s contre %s" % [both, base])
	h.ok(charmed, "la récupération exposée a eu lieu")
	h.egal(boss.state, "rest", "fenêtre de punition terminée")
	h.ok(not (_n(boss, "exposed") > 0.0), "le point faible s'éteint avec la fenêtre")
	h.ok(boss.vuln > 0.0, "le Charme, lui, court encore sur sa propre durée")
	var after: float = D6Combat.damage_enemy(g, boss, _wall(100.0))
	h.ok(absf(after - base * (1.0 + CHARM)) <= 1.0, "après la fenêtre : seulement +%s %% (%s contre %s)" % [D6Js.num_str(CHARM * 100.0), after, base])

## Exposition seule, puis transition de phase en pleine fenêtre : rien ne survit.
static func _point_faible_et_transition(h, g: Dictionary, boss: Dictionary) -> void:
	var d: Dictionary = g.tuning.boss.colosse
	_isolate(g, boss, 1.0, "poing")
	boss.vuln = 0.0
	boss.vulnMult = 0.0
	for i in h.ticks(8.0):
		if boss.get("sub") == "recover":
			break
		_step(g)
		g.events.clear()
	h.ok(_n(boss, "exposed") > 0.0)
	boss.hp = floorf(boss.maxHp * d.phase2At) - 1.0
	_step(g)
	h.egal(boss.state, "roar")
	h.ok(not (_n(boss, "exposed") > 0.0) and not (boss.vuln > 0.0), "transition : exposition et drapeau éteints")
