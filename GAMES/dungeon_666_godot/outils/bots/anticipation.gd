extends RefCounted
## Portage de tools/bots.mjs — ANTICIPATION (planner) : la trajectoire du héros est échantillonnée
## pour chaque geste candidat (16 directions, l'immobilité, le dash) et confrontée aux menaces
## perçues ; on retient le geste le moins dangereux et le plus proche du plan.

const Base = preload("res://outils/bots/base.gd")
const Perception = preload("res://outils/bots/perception.gd")

const SAMPLE_HZ := 30.0 # résolution temporelle de l'anticipation
const HORIZON := 0.7 # s d'anticipation des menaces
const SAMPLES := 21 # Math.round(HORIZON * SAMPLE_HZ)
const DIRECTION_COUNT := 16 # directions candidates pour marcher / dasher
const DASH_TRIGGER := 0.25 # s : on dashe quand l'impact est plus proche que ça
const GADGET_TRIGGER := 0.2 # s : gadget en dernier recours (sans charge de dash)
const ZONE_SLACK := 0.07 # s de marge avant l'impact d'une zone
const FRAME_SPAN := 1.0 / SAMPLE_HZ
const LUNGE_TIME := 0.15 # s : durée d'une ruée de diablotin (vue à l'écran)
const DANGER_WEIGHT := 100.0
const DEPTH_BASE := 0.5 # poids d'un coup reçu, + sa profondeur dans la zone (0..1)
const COMMIT_TIME := 0.25 # s : on garde une direction d'esquive (évite les hésitations)
const COMMIT_MIN := 0.12 # s minimum d'une esquive avant de revenir au plan
const DASH_CANCEL_MARGIN := 0.1 # s : avec un dash en poche, on frappe jusqu'au dernier moment
const POOL_WEIGHT := 1.5 # poids d'une seconde passée dans une flaque brûlante (vs un coup)
const IDLE_MOVE_COST := 0.2 # sans intention, bouger coûte un peu plus que rester

static var _dirs: Array = _make_dirs()
static var _dirs_and_still: Array = _dirs + [{"x": 0.0, "y": 0.0}]
static var _hit_depth := 0.0 # profondeur du dernier contact trouvé par _threat_hit_time

static func _make_dirs() -> Array:
	var out: Array = []
	for i in DIRECTION_COUNT:
		var a := (float(i) / float(DIRECTION_COUNT)) * PI * 2.0
		out.append({"x": D6Trig.cos(a), "y": D6Trig.sin(a)})
	return out

## Temps pendant lequel le héros reste freiné par son action en cours (attaque, lancer).
static func lock_remaining(p: Dictionary) -> float:
	if p.state == "attack" and p.get("attack") != null:
		var a: Dictionary = p.attack
		var d: Dictionary = a.dur
		if a.phase == "startup":
			return d.startup - a.t + d.active + d.recovery
		if a.phase == "active":
			return d.active - a.t + d.recovery
		return maxf(0.0, d.recovery - a.t)
	if p.state == "cast":
		return p.castT
	return 0.0

static func invulnerability(p: Dictionary) -> float:
	return maxf(p.iframes, p.superT) if p.state == "super" else p.iframes

## Trajectoire échantillonnée du héros (x, y tous les 1/SAMPLE_HZ s) pour un geste donné.
static func simulate_move(game: Dictionary, out: PackedFloat64Array, dx: float, dy: float, lock_t: float, dash: bool) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var room: Dictionary = game.room
	var run: float = t.player.speed * p.stats.moveSpeedMult
	# Vitesse pendant un coup : celle de l'arme en main (player attackMoveFactor), pas l'étalon.
	var weapon = t.get("weapon")
	var move_mult: float = D6Js.nz(weapon.get("moveMult"), 1.0) if weapon is Dictionary else 1.0
	var slow: float = run * minf(1.0, t.player.attackMoveMult * move_mult)
	var dash_speed: float = (t.dash.distance * D6Js.nz(p.stats.get("dashDistanceMult"), 1.0)) / t.dash.duration # dash de la classe
	var dash_dur: float = t.dash.duration
	var step := 1.0 / SAMPLE_HZ
	var r: float = p.r
	var lo: float = room.pad + r
	var hi_x: float = room.w - lo
	var hi_y: float = room.h - lo
	var x: float = p.x
	var y: float = p.y
	for k in SAMPLES + 1:
		out[2 * k] = x
		out[2 * k + 1] = y
		var tau := k * step
		var v := slow if tau < lock_t else run
		if dash and tau < dash_dur:
			v = dash_speed
		var nx := D6Geo.clampv(x + dx * v * step, lo, hi_x)
		var ny := D6Geo.clampv(y + dy * v * step, lo, hi_y)
		if not Base.inside_obstacle(room, nx, ny, r):
			x = nx
			y = ny

static func _lunge_center_depth(th: Dictionary, x: float, y: float, tau: float) -> float:
	var f := D6Geo.clampv((tau - th.t0) / LUNGE_TIME, 0.0, 1.0)
	return Perception.disc_depth(x, y, th.x + th.dx * th.len * f, th.y + th.dy * th.len * f, th.rad)

## Premier instant (s) où la trajectoire est touchée par la menace, ou -1.
static func _threat_hit_time(th: Dictionary, traj: PackedFloat64Array, invul_t: float) -> float:
	var type: int = th.type
	var k0 := 0
	var k1 := SAMPLES
	if type == Perception.T_ZONE:
		k0 = int(maxf(0.0, floorf(th.t0 * SAMPLE_HZ)))
		k1 = int(minf(SAMPLES, ceilf(th.t1 * SAMPLE_HZ)))
	elif type == Perception.T_LUNGE:
		k0 = int(maxf(0.0, floorf((th.t0 - ZONE_SLACK) * SAMPLE_HZ)))
		k1 = int(minf(SAMPLES, ceilf((th.t0 + LUNGE_TIME) * SAMPLE_HZ)))
	for k in range(k0, k1 + 1):
		var tau := k / SAMPLE_HZ
		if tau < invul_t:
			continue
		var x := traj[2 * k]
		var y := traj[2 * k + 1]
		var depth: float
		if type == Perception.T_ZONE:
			depth = Perception.zone_depth(th, x, y)
		elif type == Perception.T_LUNGE:
			depth = _lunge_center_depth(th, x, y, tau)
		else:
			depth = Perception.disc_depth(x, y, th.x + th.vx * tau, th.y + th.vy * tau, th.rad)
		if depth > 0.0:
			_hit_depth = depth
			return tau
	return -1.0

## Secondes (pondérées par la profondeur) passées dans une flaque, hors invulnérabilité.
static func _pool_exposure(th: Dictionary, traj: PackedFloat64Array, invul_t: float) -> float:
	if is_nan(th.t1):
		return 0.0 # borne inconnue : en JavaScript la boucle `k <= NaN` ne tourne pas
	var k0 := int(maxf(0.0, floorf(th.t0 * SAMPLE_HZ)))
	var k1 := int(minf(SAMPLES, ceilf(th.t1 * SAMPLE_HZ)))
	var s := 0.0
	for k in range(k0, k1 + 1):
		if k / SAMPLE_HZ < invul_t:
			continue
		var depth := Perception.zone_depth(th, traj[2 * k], traj[2 * k + 1])
		if depth > 0.0:
			s += (DEPTH_BASE + depth) * FRAME_SPAN
	return s

## {danger, firstHit, pooled} d'une trajectoire face aux menaces.
static func evaluate(traj: PackedFloat64Array, threats: Array, invul_t: float) -> Dictionary:
	var danger := 0.0
	var first_hit := INF
	var pooled := 0.0 # part du danger qui vient des flaques (on en sort à pied, jamais en dash)
	for th in threats:
		if th.type == Perception.T_POOL:
			var s := _pool_exposure(th, traj, invul_t)
			danger += s * POOL_WEIGHT
			pooled += s
			continue
		var hit := _threat_hit_time(th, traj, invul_t)
		if hit < 0.0:
			continue
		# Un coup proche pèse plus lourd ; être au bord de la zone vaut mieux qu'en son cœur.
		danger += (DEPTH_BASE + _hit_depth) * (1.0 + HORIZON - hit)
		first_hit = minf(first_hit, hit)
	return {"danger": danger, "firstHit": first_hit, "pooled": pooled}

## Balaye les directions (et l'immobilité) ; rend le meilleur geste au sens danger + écart au plan.
static func scan_moves(game: Dictionary, mem: Dictionary, threats: Array, intent_dir: Dictionary, lock_t: float, dash: bool, invul_t: float) -> Dictionary:
	var room: Dictionary = game.room
	var buf: PackedFloat64Array = mem.buf
	var best = null
	var candidates: Array = _dirs if dash else _dirs_and_still
	for d in candidates:
		simulate_move(game, buf, d.x, d.y, lock_t, dash)
		var ev := evaluate(buf, threats, invul_t)
		var still: bool = d.x == 0.0 and d.y == 0.0
		var deviation: float
		if intent_dir.l > 0.0:
			deviation = 1.0 if still else 1.0 - (d.x * intent_dir.x + d.y * intent_dir.y)
		else:
			deviation = 0.0 if still else IDLE_MOVE_COST
		var score: float = ev.danger * DANGER_WEIGHT + deviation + Base.wall_penalty(room, buf[2 * SAMPLES], buf[2 * SAMPLES + 1])
		if best == null or score < best.score:
			best = {"x": d.x, "y": d.y, "score": score, "danger": ev.danger, "firstHit": ev.firstHit, "pooled": ev.pooled}
	return best

static func can_dash_now(game: Dictionary) -> bool:
	var p: Dictionary = game.player
	return p.dashCharges >= 1.0 and (p.state == "free" or p.state == "attack" or p.state == "cast")

static func _plan_is_safe(game: Dictionary, mem: Dictionary, threats: Array, intent: Dictionary, dir: Dictionary, lock: float, invul: float, opts: Dictionary) -> bool:
	simulate_move(game, mem.buf, dir.x, dir.y, HORIZON if D6Js.truthy(intent.get("attack")) else lock, false)
	var plan := evaluate(mem.buf, threats, invul)
	if plan.danger == 0.0:
		return true
	# Un dash disponible annule n'importe quelle attaque : on continue de frapper tant que
	# le coup adverse n'est pas imminent (le jeu « attaque puis dash » à la Hades). Une flaque,
	# elle, brûle tant qu'on y reste : le dash n'y change rien, le plan n'est pas sûr.
	return opts.dash and can_dash_now(game) and plan.pooled == 0.0 and plan.firstHit > DASH_TRIGGER + DASH_CANCEL_MARGIN

## Retient une direction d'esquive sûre pour COMMIT_TIME (anti-hésitation).
static func _commit_evade(game: Dictionary, mem: Dictionary, walk: Dictionary, committed: bool) -> void:
	if walk.danger != 0.0 or (walk.x == 0.0 and walk.y == 0.0):
		return
	if not committed:
		mem.evadeStart = game.time
	mem.evadeUntil = game.time + COMMIT_TIME
	mem.evadeX = walk.x
	mem.evadeY = walk.y

## Aucune marche n'évite le coup imminent : dash (i-frames + distance), sinon gadget.
static func _emergency_dodge(game: Dictionary, mem: Dictionary, threats: Array, ref: Dictionary, walk: Dictionary, invul: float, opts: Dictionary, input: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	if opts.dash and can_dash_now(game):
		var dash_invul := maxf(invul, game.tuning.dash.iframes)
		var dash := scan_moves(game, mem, threats, ref, 0.0, true, dash_invul)
		if dash.danger < walk.danger:
			input.moveX = dash.x
			input.moveY = dash.y
			input.dashPressed = true
			return input
	if opts.gadget and p.gadgetCharges > 0.0 and walk.firstHit <= GADGET_TRIGGER and p.state != "super":
		input.gadgetPressed = true
		mem.lastGadget = game.time
	return input

## Si le plan courant mène sous un coup : esquive en marchant si possible, sinon dash (au
## dernier moment), sinon gadget. Rend un InputFrame, ou null si le plan est sûr.
static func plan_evasion(game: Dictionary, mem: Dictionary, threats: Array, intent: Dictionary, opts: Dictionary):
	var lock := lock_remaining(game.player)
	var invul := invulnerability(game.player)
	var dir := Base.norm(intent.mx, intent.my)
	var committed: bool = game.time < mem.evadeUntil
	if _plan_is_safe(game, mem, threats, intent, dir, lock, invul, opts):
		# Plan sûr : on y revient, sauf esquive toute fraîche (évite d'osciller à chaque image).
		if not committed or game.time - mem.evadeStart >= COMMIT_MIN:
			mem.evadeUntil = -1.0
			return null
	# Référence : l'esquive en cours (on ne change pas d'avis à chaque image), sinon le plan.
	var ref: Dictionary = {"x": mem.evadeX, "y": mem.evadeY, "l": 1.0} if committed else dir
	var walk := scan_moves(game, mem, threats, ref, lock, false, invul)
	_commit_evade(game, mem, walk, committed)
	var input := D6Game.empty_input()
	input.moveX = walk.x
	input.moveY = walk.y
	# Contourner une flaque n'empêche pas de frapper ce qui est à portée (aucun coup n'arrive).
	if walk.firstHit == INF:
		input.attack = intent.get("attack")
	if walk.danger == 0.0 or walk.firstHit > DASH_TRIGGER:
		return input
	return _emergency_dodge(game, mem, threats, ref, walk, invul, opts, input)
