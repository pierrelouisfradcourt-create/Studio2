extends RefCounted
## Portage de GAMES/dungeon_666/tests/feel_review.test.mjs.
## Règles issues de la revue « game feel » et lisibilité (2026-10-01) : chaque test fige un
## correctif. Les valeurs sont lues dans le tuning.

const FINISHER_SEARCH_STEPS := 240
const BOSS_SPAWN_STEPS := 200
const RING_MAX_STEPS := 600

static func tests(h) -> void:
	h.test("tampon : un tap d'attaque au tout début du finisher fait partir le coup suivant", func(): _tap_au_finisher(h))
	h.test("tampon : une Lance tapée au début du finisher part pendant sa récupération", func(): _lance_au_finisher(h))
	h.test("anneau du Gardien : le cercle d'alerte reste affiché entre les vagues", func(): _anneau(h))
	h.test("invocation du Gardien : alerte marquée inoffensive (le rouge reste « ça fait mal »)", func(): _invocation(h))
	h.test("gel d'impact sur le Gardien : plafonné par le tuning, le finisher pèse plus qu'un coup léger", func(): _gel_gardien(h))

# ---------------------------------------------------------------- outillage (celui du fichier web)

static func _ticks(seconds: float) -> int:
	return int(ceilf(seconds / D6Data.DT))

static func _input(over: Dictionary = {}) -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	input.merge(over, true)
	return input

## Partie vide (aucune vague), héros au centre.
static func _sandbox() -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": 11.0})
	g.spawns.clear()
	g.enemies.clear()
	g.room.waves = []
	g.room.waveIndex = 0.0
	g.room.obstacles = []
	g.room.cleared = true
	g.room.interact = null
	g.room.doors = []
	g.player.x = g.room.w / 2.0
	g.player.y = g.room.h / 2.0
	g.events.clear()
	return g

static func _a_evenement(g: Dictionary, type: String) -> bool:
	return g.events.any(func(ev): return ev.type == type)

## Attaque maintenue jusqu'au premier tick du finisher (coup 3), puis relâchée.
## (assert.fail du web : une affirmation fausse, et le test s'arrête là.)
static func _to_finisher(h, g: Dictionary) -> bool:
	for i in FINISHER_SEARCH_STEPS:
		D6Game.step_game(g, _input({"attack": true}))
		var started: bool = g.events.any(func(ev): return ev.type == "attackStart" and ev.get("index") == 2.0)
		g.events.clear()
		if started:
			return true
	h.ok(false, "le finisher n'a jamais démarré")
	return false

## Durée pendant laquelle le finisher interdit le coup suivant.
static func _finisher_lock(t: Dictionary) -> float:
	var f: Dictionary = t.combo[2]
	return f.startup + f.active + f.recovery * t.comboCancelFrom.hits[2]

static func _boss_arrive(g: Dictionary) -> bool:
	return g.enemies.any(func(e): return D6Js.truthy(e.get("boss")) and not (float(D6Js.nz(e.get("spawnT"), 0.0)) > 0.0))

static func _boss(g: Dictionary):
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")):
			return e
	return null

## Gardien seul, en début de pattern donné. Rend {g, boss} (boss null : affirmation déjà fausse).
static func _boss_in(h, pattern: String, phase: float = 1.0) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": 3.0, "startFloor": 18.0}) # gate Pierre 2026-10-01 : Gardien tous les 18 étages
	g.spawns.clear()
	var i := 0
	while i < BOSS_SPAWN_STEPS and not _boss_arrive(g):
		D6Game.step_game(g, _input())
		i += 1
	var boss = _boss(g)
	if not h.ok(boss != null, "Gardien présent"):
		return {"g": g, "boss": null}
	g.enemies = [boss]
	boss.phase = phase
	boss.state = pattern
	boss.stateTime = 0.0
	boss.patternStep = 0.0
	boss.patternT = 0.0
	boss.tele = null
	# Héros loin et invulnérable : on observe le boss.
	g.player.x = boss.x + 400.0
	g.player.y = boss.y
	g.player.iframes = 99.0
	g.events.clear()
	return {"g": g, "boss": boss}

static func _alerte_anneau(boss: Dictionary, rayon: float) -> bool:
	var tele = boss.get("tele")
	return tele != null and tele.get("shape") == "circle" and tele.get("r") == rayon

# ---------------------------------------------------------------- tests

static func _tap_au_finisher(h) -> void:
	var g := _sandbox()
	if not _to_finisher(h, g):
		return
	D6Game.step_game(g, _input({"attackPressed": true}))
	var next := -1
	var limit := _ticks(_finisher_lock(g.tuning)) + 3
	var i := 1
	while i <= limit and next < 0:
		D6Game.step_game(g, _input())
		if _a_evenement(g, "attackStart"):
			next = i
		g.events.clear()
		i += 1
	h.ok(next > 0, "le tap a été perdu (aucune attaque en %d ticks)" % limit)

static func _lance_au_finisher(h) -> void:
	var g := _sandbox()
	if not _to_finisher(h, g):
		return
	D6Game.step_game(g, _input({"skillPressed": true, "skillAimX": 1.0, "skillAimY": 0.0}))
	var cast := false
	var f: Dictionary = g.tuning.combo[2]
	var limit := _ticks(f.startup + f.active + f.recovery) + 3
	var i := 0
	while i < limit and not cast:
		D6Game.step_game(g, _input())
		cast = _a_evenement(g, "castStart")
		g.events.clear()
		i += 1
	h.ok(cast, "la Lance a été perdue")

static func _anneau(h) -> void:
	var ctx := _boss_in(h, "ring")
	if ctx.boss == null:
		return
	var g: Dictionary = ctx.g
	var boss: Dictionary = ctx.boss
	var r: Dictionary = g.tuning.boss[boss.kind].ring
	var waves := 0
	var missing := 0
	var i := 0
	while i < RING_MAX_STEPS and boss.state == "ring":
		D6Game.step_game(g, _input())
		var fired: int = g.events.filter(func(ev): return ev.type == "enemyAttack" and ev.get("enemy") == "bossRing").size()
		g.events.clear()
		waves += fired
		# Après la 1re vague et tant qu'une autre doit partir : l'alerte est visible.
		if waves >= 1 and boss.state == "ring" and fired == 0 and not _alerte_anneau(boss, r.teleRadius):
			missing += 1
		i += 1
	h.egal(waves, r.waves, "toutes les vagues de la phase 1 sont parties")
	h.egal(missing, 0, "%d ticks sans alerte entre deux vagues" % missing)

static func _invocation(h) -> void:
	var ctx := _boss_in(h, "summon", 3.0)
	if ctx.boss == null:
		return
	var boss: Dictionary = ctx.boss
	D6Game.step_game(ctx.g, _input())
	if h.ok(boss.get("tele") != null, "alerte affichée"):
		h.egal(boss.tele.get("harmless"), true)

static func _gel_gardien(h) -> void:
	var ctx := _boss_in(h, "rest")
	if ctx.boss == null:
		return
	var g: Dictionary = ctx.g
	var boss: Dictionary = ctx.boss
	var t: Dictionary = g.tuning
	var cap: float = t.boss[boss.kind].hitstopCap
	boss.invuln = 0.0
	g.hitstop = 0.0
	D6Combat.damage_enemy(g, boss, {"kind": "melee", "amount": 1.0, "dirX": 1.0, "dirY": 0.0, "hitstop": t.combo[0].hitstop})
	var light: float = g.hitstop
	g.hitstop = 0.0
	g.hitstopBank = 1.0
	D6Combat.damage_enemy(g, boss, {"kind": "melee", "amount": 1.0, "dirX": 1.0, "dirY": 0.0, "hitstop": t.combo[2].hitstop})
	var heavy: float = g.hitstop
	h.ok(heavy <= cap + 1e-9, "gel %s > plafond %s" % [str(heavy), str(cap)])
	h.ok(heavy > light, "finisher %s vs coup léger %s" % [str(heavy), str(light)])
