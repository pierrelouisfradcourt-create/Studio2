extends RefCounted
## COMPÉTENCES NEUVES DU BOURREAU (combat V3, étape 4) — chargé par sim/kit_neuves.gd, sans class_name.
## Nombres : data/classes.json (`faille`, `hachette`, `garde`), rangs et améliorations : data/arbres.json.
##
##   faille   — Faille (recharge) : il frappe le sol, une fissure court devant lui sur `range` u
##              (large de 2 × `radius`), arrêtée par un mur ou un pilier, pas par une rivière (elle
##              passe dessous) : dégâts, étourdissement. Améliorations : `aftershock` (une réplique
##              sur la même fissure, `aftershockMult` des dégâts) ; `fissureTime` (elle reste
##              ouverte et ralentit de `chillMult` ceux qui s'y tiennent). Zone `faille`.
##   hachette — Hache du supplice (recharge) : une hache lancée jusqu'à `range` u qui REVIENT dans
##              sa main ; elle traverse tout et frappe à l'aller, puis au retour. Un mur la fait
##              revenir plus tôt ; au retour rien ne l'arrête. Améliorations : `refund` (la
##              rattraper réduit la recharge) ; `spin` (au bout de sa course elle tournoie `spin` s
##              et frappe autour d'elle). Tir `hache`, joué ici (update_axe).
##   garde    — Garde de fer (à charges) : un coup de bouclier (dégâts, recul à `radius` u), puis
##              `duration` s de garde : un coup reçu de FACE (dans `arc` degrés autour du regard)
##              est réduit de `reduce` et son auteur est repoussé (`pushback`). Améliorations :
##              `thorns` / `thornStun` (l'attaquant paré est blessé, étourdi) ; `burstMult` (à la
##              fin, une onde rend les dégâts encaissés, ramenés à l'échelle de l'étage 1,
##              `burstCap` au plus).
## État : player.guard = {t, def, absorbed}.

const REACH_STEP := 8.0 # u : pas de la recherche du mur qui arrête la fissure
const MUZZLE := 0.5 # × rayon du héros : point de départ de la hache
const Revenant := preload("res://sim/neuves_revenant.gd")

# ---------------------------------------------------------------- Faille

## Longueur de la fissure : `max_len`, ou moins si un mur ou un pilier l'arrête.
static func _reach(game: Dictionary, x: float, y: float, dir_x: float, dir_y: float, max_len: float) -> float:
	var d := 0.0
	while d < max_len:
		var step := minf(REACH_STEP, max_len - d)
		if D6Physics.point_blocked(game.room, x + dir_x * (d + step), y + dir_y * (d + step), 0.0):
			break
		d += step
	return d

static func release_faille(game: Dictionary, s: Dictionary, angle: float) -> void:
	var p: Dictionary = game.player
	var length := _reach(game, p.x, p.y, p.castDirX, p.castDirY, s.range)
	var width: float = s.radius * 2.0
	_quake(game, {"x": p.x, "y": p.y, "angle": angle, "length": length, "width": width}, s.damage, D6Js.nz(s.get("stun"), 0.0), s)
	var after: float = D6Js.nz(s.get("aftershock"), 0.0)
	var open: float = D6Js.nz(s.get("fissureTime"), 0.0)
	if after <= 0.0 and open <= 0.0:
		return
	D6KitZones.spawn_zone(game, {
		"kind": "faille", "x": p.x, "y": p.y, "r": s.radius, "angle": angle, "length": length, "width": width, "life": maxf(after, open),
		"aftershock": after, "damage": s.damage * D6Js.nz(s.get("aftershockMult"), 0.0), "stun": D6Js.nz(s.get("stun"), 0.0),
		"knockback": s.knockback, "hitstop": s.hitstop, "shake": D6Js.nz(s.get("shake"), 0.0), "open": open, "chillMult": D6Js.nz(s.get("chillMult"), 1.0),
	})

## La secousse : tout ennemi dont le corps mord sur la bande `band` est frappé, poussé dans l'axe.
static func _quake(game: Dictionary, band: Dictionary, damage: float, stun: float, src: Dictionary) -> void:
	var dir_x := D6Trig.cos(band.angle)
	var dir_y := D6Trig.sin(band.angle)
	D6State.emit(game, "fissure", {"x": band.x, "y": band.y, "angle": band.angle, "length": band.length, "width": band.width})
	for e in _in_band(game, band):
		D6Combat.damage_enemy(game, e, {
			"kind": "skill", "amount": damage, "dirX": dir_x, "dirY": dir_y, "knockback": src.knockback, "stun": stun,
			"hitstop": src.hitstop, "canCrit": true, "shake": D6Js.nz(src.get("shake"), 0.0),
		})

static func _in_band(game: Dictionary, band: Dictionary) -> Array:
	var out: Array = []
	for e in game.enemies:
		if e.dead or e.spawnT > 0.0:
			continue
		var d2 := D6Geo.point_band_dist2(e.x, e.y, band.x, band.y, band.angle, band.length, band.width)
		if d2 == 0.0 or d2 < e.r * e.r:
			out.append(e)
	return out

## Zone `faille` : la réplique à son heure, puis la fissure ouverte qui ralentit.
static func zone_faille(game: Dictionary, z: Dictionary) -> void:
	if z.aftershock > 0.0 and not D6Js.truthy(z.get("shaken")) and z.t >= z.aftershock:
		z.shaken = true
		_quake(game, z, z.damage, z.stun, z)
	if z.t >= z.life:
		z.dead = true
		return
	if z.open <= 0.0:
		return
	var floor_mult: float = maxf(game.tuning.combat.minChillMult, 1.0 - z.chillMult)
	for e in _in_band(game, z):
		e.chill = maxf(e.chill, D6Data.DT * 2.0) # tant qu'il s'y tient : le ralentissement cesse dès qu'il en sort
		var cur: float = e.chillMult if D6Js.truthy(e.get("chillMult")) else 1.0
		e.chillMult = minf(cur, floor_mult)

# ---------------------------------------------------------------- Hache du supplice

static func release_hachette(game: Dictionary, s: Dictionary) -> void:
	var p: Dictionary = game.player
	var axe := {
		"kind": "hache", "custom": true, "phase": "out", "x": p.x + p.castDirX * p.r * MUZZLE, "y": p.y + p.castDirY * p.r * MUZZLE,
		"vx": p.castDirX * s.speed, "vy": p.castDirY * s.speed, "speed": s.speed, "r": s.radius, "range": s.range, "pierce": s.pierce,
		"damage": s.damage, "source": "skill", "knockback": s.knockback, "hitstop": s.hitstop, "heavy": true,
		"refund": D6Js.nz(s.get("refund"), 0.0), "slot": p.castSlot, "spin": D6Js.nz(s.get("spin"), 0.0),
	}
	if axe.spin > 0.0:
		axe.merge({"spinT": 0.0, "spinEvery": s.spinEvery, "spinRadius": s.spinRadius, "spinDamage": s.damage * s.spinMult})
	D6KitShots.spawn_shot(game, axe)

## Un pas de la hache : l'aller, le tournoiement (amélioration), le retour dans la main.
static func update_axe(game: Dictionary, s: Dictionary, dt: float) -> void:
	match s.phase:
		"out":
			_axe_out(game, s, dt)
		"spin":
			_axe_spin(game, s, dt)
		_:
			_axe_back(game, s, dt)

static func _axe_out(game: Dictionary, s: Dictionary, dt: float) -> void:
	var ox: float = s.x
	var oy: float = s.y
	s.x += s.vx * dt
	s.y += s.vy * dt
	s.traveled += s.speed * dt
	var walled: bool = D6Physics.shot_blocked(game.room, ox, oy, s.x, s.y)
	if walled:
		s.x = ox # elle rebondit sur le mur : elle n'y entre pas
		s.y = oy
	else:
		D6KitShots.hit_segment(game, s, ox, oy, s.speed)
	if walled or s.traveled >= s.range:
		s.hitIds.clear() # chaque ennemi peut être frappé de nouveau au retour
		s.phase = "spin" if s.spin > 0.0 else "back"
		D6State.emit(game, "axeTurn", {"x": s.x, "y": s.y, "spin": s.spin})

static func _axe_spin(game: Dictionary, s: Dictionary, dt: float) -> void:
	s.vx = 0.0
	s.vy = 0.0
	s.spin -= dt
	s.spinT -= dt
	if s.spinT <= 0.0:
		s.spinT += s.spinEvery
		D6KitCommon.hit_circle(game, s.x, s.y, s.spinRadius, {"kind": "skill", "amount": s.spinDamage, "knockback": 0.0, "hitstop": 0.0, "canCrit": false})
		D6State.emit(game, "kitPulse", {"x": s.x, "y": s.y, "r": s.spinRadius, "kind": "hache"})
	if s.spin <= 0.0:
		s.phase = "back"

static func _axe_back(game: Dictionary, s: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var dx: float = p.x - s.x
	var dy: float = p.y - s.y
	var d := maxf(1e-6, sqrt(dx * dx + dy * dy))
	var step: float = s.speed * dt
	if d <= p.r + s.r + step:
		s.dead = true
		D6State.emit(game, "axeCatch", {"x": p.x, "y": p.y})
		if s.refund > 0.0 and D6KitSupers.form_of(game) == null:
			p.slots[int(s.slot)].cd *= 1.0 - s.refund # « Reprise »
		return
	var ox: float = s.x
	var oy: float = s.y
	s.vx = dx / d * s.speed
	s.vy = dy / d * s.speed
	s.x += s.vx * dt
	s.y += s.vy * dt
	D6KitShots.hit_segment(game, s, ox, oy, s.speed)

# ---------------------------------------------------------------- Garde de fer

static func use_garde(game: Dictionary, g: Dictionary) -> void:
	var p: Dictionary = game.player
	D6KitCommon.hit_circle(game, p.x, p.y, g.radius, {
		"kind": "gadget", "amount": g.damage, "knockback": g.knockback, "stun": D6Js.nz(g.get("stun"), 0.0), "hitstop": g.hitstop,
		"canCrit": false, "shake": D6Js.nz(g.get("shake"), 0.0),
	})
	p.guard = {"t": g.duration, "max": g.duration, "def": g, "absorbed": 0.0}
	D6State.emit(game, "guardStart", {"x": p.x, "y": p.y, "time": g.duration, "arc": g.arc * D6Data.DEG})

static func tick_guard(game: Dictionary, dt: float) -> void:
	var p: Dictionary = game.player
	var st = p.get("guard")
	if st == null:
		return
	st.t -= dt
	if st.t > 0.0:
		return
	p.guard = null
	D6State.emit(game, "guardEnd", {"x": p.x, "y": p.y})
	_backlash(game, st)

## « Contrecoup » (amélioration) : la garde finie rend ce qu'elle a encaissé, en une onde.
static func _backlash(game: Dictionary, st: Dictionary) -> void:
	var g: Dictionary = st.def
	if g.get("burstMult") == null or st.absorbed <= 0.0:
		return
	var p: Dictionary = game.player
	# Les coups ennemis grandissent avec l'étage, ceux du héros avec son arme : on ramène ce qui a
	# été encaissé à l'échelle de l'étage 1 avant de le rendre (sinon l'onde compterait deux fois la profondeur).
	var scale: float = D6Floors.floor_scaling(game.tuning, game.run.floor).damage
	var amount: float = minf(g.burstCap, st.absorbed / maxf(1e-6, scale) * g.burstMult)
	D6KitCommon.hit_circle(game, p.x, p.y, g.burstRadius, {"kind": "gadget", "amount": amount, "knockback": g.knockback, "hitstop": g.hitstop, "canCrit": false})
	D6State.emit(game, "explode", {"x": p.x, "y": p.y, "r": g.burstRadius, "hero": true, "kind": "garde"})

## Un coup de `amount` va toucher le héros : rend ce qu'il en reste. En garde, un coup venu de face
## est réduit, et son auteur repoussé (blessé, étourdi : « Épines »). Un coup sans origine connue
## (il vient du point où se tient le héros) compte comme de face.
static func absorb(game: Dictionary, amount: float, src: Dictionary) -> float:
	var p: Dictionary = game.player
	var st = p.get("guard")
	if st == null:
		return amount
	var g: Dictionary = st.def
	var dx: float = D6Js.nz(src.get("x"), p.x) - p.x
	var dy: float = D6Js.nz(src.get("y"), p.y) - p.y
	var d := sqrt(dx * dx + dy * dy)
	if d > 1e-6 and absf(D6Geo.angle_diff(p.facing, D6Trig.atan2(dy, dx))) > g.arc * D6Data.DEG / 2.0:
		return amount # dans le dos : la garde ne couvre pas
	var kept: float = amount * (1.0 - g.reduce)
	st.absorbed += amount - kept
	D6State.emit(game, "guardBlock", {"x": p.x, "y": p.y, "srcX": p.x + dx, "srcY": p.y + dy, "amount": D6Js.jround(amount - kept)})
	var foe = Revenant.attacker(game, src)
	if foe != null:
		var fx: float = foe.x - p.x
		var fy: float = foe.y - p.y
		var fl := maxf(1e-6, sqrt(fx * fx + fy * fy))
		D6Combat.push_enemy(game, foe, fx / fl, fy / fl, g.pushback, 0.0)
		if g.get("thorns") != null:
			D6Combat.damage_enemy(game, foe, {"kind": "gadget", "amount": g.thorns, "dirX": fx / fl, "dirY": fy / fl, "stun": D6Js.nz(g.get("thornStun"), 0.0), "canCrit": false})
	return kept
