extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_guardians.test.mjs.
## Contrat des Gardiens ajoutés (Cerbère, Minos, Éphialte) à côté de Charon :
##   - rotation : chaque modèle garde l'étage du Gardien de sa section ;
##   - chaque pattern de chaque phase se joue jusqu'au bout, télégraphié >= GUARDIAN_MIN_TELE ;
##   - tout coup reçu vient d'une attaque télégraphiée (aucun dégât de contact) ;
##   - transitions de phase ; rien ne survit à la mort ; déterminisme ;
##   - la profondeur change PV et dégâts, jamais la durée d'un télégraphe ;
##   - équité mesurée par les bots (le skilled gagne, le sans-dash souffre nettement plus) ;
##   - recréation, pour la V2 (étage 18), des trois tests de feel_review cassés par les sections
##     de 18 (alerte de l'anneau entre les vagues, alerte d'invocation inoffensive, plafond de gel).

const Bots = preload("res://outils/bots/bots.gd")

const EPS := 1e-9
const UNIT_FLOOR := 18.0 # étage du 1er Gardien : les tests unitaires y forcent chaque modèle
const PATTERN_CAP := 12.0 # s : au-delà, un pattern « ne finit pas »
const STRIKE_LAG := 0.25 # s : un coup au corps part au plus tard ce délai après la fin de son télégraphe
const DT := 1.0 / 60.0
const SPAWN_WAIT := 240 # pas d'attente au plus de l'apparition du Gardien
const EQUITE_SEEDS := [1.0, 2.0, 3.0, 4.0, 5.0] # valeur web d'origine : [1, 2, 3, 4, 5]
const MIN_DASH_VALUE := 2.0
const EQUITE_SECONDS := 300.0
const MASHER_SECONDS := 150.0
const DIGEST_SECONDS := 45.0
const AUDIT_SECONDS := 25.0
const DEEP_FLOOR := 666.0

# Sources de dégâts déclarées par modèle : zones (hazard.kind), coups au corps (télégraphe
# e.tele avant), projectiles. Tout autre source de dégâts pendant un combat de Gardien = bug.
const ATTACKS := {
	"gardien": {"hazards": ["bossSlam"], "body": ["bossCharge"], "shots": ["bossOrb"]},
	"cerbere": {"hazards": ["cerbereLand", "cerbereShock", "cerbereFlame", "cerbereFire"], "body": ["cerbereBite"], "shots": []},
	"minos": {"hazards": ["minosSentence", "minosTile", "minosSeal"], "body": ["minosWhip"], "shots": []},
	"colosse": {"hazards": ["colosseFist", "colosseQuake", "colosseRock", "colosseEmber"], "body": [], "shots": []},
}
# Dégâts des serviteurs (renforts, geôliers) : ce sont des ennemis ordinaires, télégraphiés ailleurs.
const ADD_DAMAGE := {"imp": "imp", "archer": "arrow", "exploder": "exploder", "brute": "brute", "charger": "charger"}

static func tests(h) -> void:
	h.test("rotation : section 1 = Charon, puis au moins 3 nouveaux modèles, chacun à l'étage du Gardien de sa section", func(): _t_rotation(h))
	h.test("données : 3 phases (seuils en tuning), 3 à 5 patterns par modèle, chacun chiffré dans le tuning", func(): _t_donnees(h))
	for kind in _new_models():
		h.test("%s : chaque pattern de chaque phase se joue jusqu'au bout, menace télégraphiée >= %s s" % [kind, D6Js.num_str(_min_tele())], func(): _t_patterns(h, kind))
	for kind in _all_models():
		h.test("%s : tout coup reçu vient d'une attaque télégraphiée (zones, coups au corps annoncés, serviteurs)" % kind, func(): _t_coups_telegraphies(h, kind))
	for kind in _new_models():
		h.test("%s : au repos, se coller à lui ne blesse jamais (aucun dégât de contact)" % kind, func(): _t_repos_sans_contact(h, kind))
	for kind in _new_models():
		h.test("%s : transitions de phase (seuils du tuning, invulnérable, menaces effacées, renforts, orbe)" % kind, func(): _t_transitions(h, kind))
	for kind in _new_models():
		h.test("%s : à sa mort, aucune menace ne survit (zones, braises, serviteurs, projectiles)" % kind, func(): _t_mort(h, kind))
	for kind in _new_models():
		h.test("%s : déterministe (même graine, mêmes entrées => même combat)" % kind, func(): _t_deterministe(h, kind))
	h.test("la profondeur change PV et dégâts, JAMAIS la durée d'un télégraphe (phase 3, étage 18 contre 666)", func(): _t_profondeur(h))
	h.test("cerbere : le bond retombe sur le cercle annoncé ; en l'air il ne blesse pas ; épuisé il est exposé", func(): _t_cerbere_bond(h))
	h.test("minos : la brèche du fouet protège, le reste du cercle frappe ; dissous il est intouchable", func(): _t_minos_fouet(h))
	h.test("colosse : geôliers = bouclier tant qu'ils vivent ; poing = point faible ; braises bornées", func(): _t_colosse(h))
	h.test("équité : en entraînement à SA profondeur, le bot skilled bat chaque nouveau Gardien ; sans dash, il souffre nettement plus", func(): _t_equite(h))
	h.test("bots : face aux nouveaux Gardiens, ils ne lisent que ce qui est dessiné et n'écrivent jamais", func(): _t_bots_audit(h))
	h.test("V2 (étage 18) — anneau du Gardien : le cercle d'alerte reste affiché entre les vagues", func(): _t_v2_anneau(h))
	h.test("V2 (étage 18) — invocations des Gardiens : alertes marquées inoffensives (le rouge reste « ça fait mal »)", func(): _t_v2_invocations(h))
	h.test("V2 (étage 18) — gel d'impact sur CHAQUE Gardien : plafonné par le tuning, le finisher pèse plus qu'un coup léger", func(): _t_v2_gel(h))

# ---------------------------------------------------------------- outillage

static func _new_models() -> Array:
	return D6Data.tables().boss_data.EXTRA_BOSSES.keys()

static func _all_models() -> Array:
	return ["gardien"] + _new_models()

static func _min_tele() -> float:
	return D6Data.tables().boss_data.GUARDIAN_MIN_TELE

static func _rotation() -> Array:
	return D6Data.tables().boss_data.GUARDIAN_ROTATION

static func _model(kind: String) -> Dictionary:
	return D6Boss.boss_models()[kind]

static func _by_phase(kind: String, phase: int) -> Array:
	return _model(kind).byPhase[str(phase)]

static func _n(d: Dictionary, key: String) -> float:
	var v = d.get(key)
	return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) else 0.0

static func _hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)

static func _step(g: Dictionary) -> void:
	D6Game.step_game(g, D6Game.empty_input())

static func _count(evs: Array, type: String, champ: String = "", valeur = null) -> int:
	return evs.filter(func(ev): return ev.type == type and (champ == "" or ev.get(champ) == valeur)).size()

static func _find_boss(g: Dictionary):
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")):
			return e
	return null

static func _boss_arrived(g: Dictionary) -> bool:
	return g.enemies.any(func(e): return D6Js.truthy(e.get("boss")) and not (e.spawnT > 0.0))

static func _pending(g: Dictionary) -> int:
	return g.hazards.filter(func(z): return D6Js.truthy(z.get("hitsPlayer")) and not D6Js.truthy(z.get("done"))).size()

static func _enemy_shots(g: Dictionary, alive_only: bool) -> int:
	return g.projectiles.filter(func(pr): return pr.get("owner") == "enemy" and not (alive_only and D6Js.truthy(pr.get("dead")))).size()

static func _melee(amount: float) -> Dictionary:
	return {"kind": "melee", "amount": amount, "dirX": 1.0, "dirY": 0.0}

static func _add_kinds(t: Dictionary, kind: String) -> Array:
	var d: Dictionary = t.boss[kind]
	var kinds: Array = d.reinforcements.get("2", []) + d.reinforcements.get("3", [])
	if D6Js.truthy(d.get("summon")):
		kinds.append(d.summon.kind)
	if D6Js.truthy(d.get("geoliers")):
		kinds.append(d.geoliers.kind)
	return kinds.map(func(k): return ADD_DAMAGE.get(k, k))

## Partie d'entraînement contre le modèle `kind` (rotation forcée), Gardien apparu.
## opts : {seed, floor, items}. Rend {g, boss} ; boss est null (et le test rouge) s'il manque.
static func _boss_game(h, kind: String, opts: Dictionary = {}) -> Dictionary:
	var options := {"seed": opts.get("seed", 3.0), "startFloor": opts.get("floor", UNIT_FLOOR), "practice": true, "tuning": {"guardians": {"rotation": [kind]}}}
	if opts.has("items"):
		options.items = opts.items
	var g: Dictionary = h.partie(options)
	var i := 0
	while i < SPAWN_WAIT and not _boss_arrived(g):
		_step(g)
		i += 1
	var boss = _find_boss(g)
	if h.ok(boss != null, "%s : Gardien présent" % kind):
		h.egal(boss.kind, kind)
	return {"g": g, "boss": boss}

## Gardien seul, phase et pattern imposés ; héros posé à distance (invulnérable si demandé).
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
	if invulnerable:
		p.iframes = 1e9
	g.events.clear()

## Joue la partie en notant ce qu'émet le Gardien : zones (délai de télégraphe), durées de ses
## télégraphes « qui font mal » (e.tele non inoffensif), invocations, cris (son), coups reçus.
## policy : "" = aucune entrée ; until : Callable() -> bool, arrête l'observation.
static func _observe(h, g: Dictionary, boss: Dictionary, seconds: float, policy: String = "", until: Callable = Callable()) -> Dictionary:
	var rec := {"hazards": {}, "teleRuns": [], "summons": 0, "cues": 0, "hurts": [], "finished": false, "events": [], "run": 0.0, "lastEnd": -INF, "lastLen": 0.0}
	var mem := {}
	for i in h.ticks(seconds):
		if g.mode != "play":
			break
		D6Game.step_game(g, Bots.play(policy, g, mem) if policy != "" else D6Game.empty_input())
		_observe_step(rec, g, boss)
		g.events.clear()
		if until.is_valid() and until.call():
			rec.finished = true
			break
	if rec.run > 0.0:
		rec.teleRuns.append(rec.run)
	return rec

static func _observe_step(rec: Dictionary, g: Dictionary, boss: Dictionary) -> void:
	for z in g.hazards:
		if z.get("sourceId") == boss.id and not rec.hazards.has(z.id):
			rec.hazards[z.id] = {"kind": z.get("kind"), "delay": z.get("delay"), "damage": z.get("damage"), "shape": z.get("shape")}
	var tele = boss.get("tele")
	if tele != null and not D6Js.truthy(tele.get("harmless")):
		rec.run += DT
	elif rec.run > 0.0:
		rec.teleRuns.append(rec.run)
		rec.lastEnd = g.time
		rec.lastLen = rec.run
		rec.run = 0.0
	for ev in g.events:
		rec.events.append(ev)
		if ev.type == "enemyAttack" and ev.get("id") == boss.id:
			rec.cues += 1
		if ev.type == "bossSummon" and ev.get("id") == boss.id:
			rec.cues += 1
		if ev.type == "spawnWarn":
			rec.summons += 1
		if ev.type == "playerHurt":
			rec.hurts.append({"source": ev.get("source"), "time": g.time, "teleLen": rec.lastLen, "sinceTele": g.time - rec.lastEnd, "teleNow": rec.run})

static func _section_of(t: Dictionary, kind: String) -> float:
	for s in range(1, int(ceilf(t.floors.total / t.floors.sectionLength)) + 1):
		if D6Floors.guardian_for(t, float(s)) == kind:
			return float(s)
	return -1.0

## Équipement « à la profondeur » : arme et armure communes du niveau de l'étage (le minimum
## qu'un joueur arrivé là porte ; l'entraînement utilise sinon le profil, ici neuf).
static func _depth_items(h, floor_n: float) -> Dictionary:
	var probe: Dictionary = h.partie({"seed": 1.0, "startFloor": 1.0, "practice": true})
	return {
		"arme": D6Loot.generate_item(probe, {"slot": "arme", "rarity": "commun", "floor": floor_n}),
		"armure": D6Loot.generate_item(probe, {"slot": "armure", "rarity": "commun", "floor": floor_n}),
	}

# ---------------------------------------------------------------- rotation et données

static func _t_rotation(h) -> void:
	var t: Dictionary = h.partie({"seed": 1.0}).tuning
	var rotation := _rotation()
	var nouveaux := _new_models()
	h.egal(rotation[0], "gardien")
	h.ok(nouveaux.size() >= 3, "nouveaux modèles : %s" % ", ".join(PackedStringArray(nouveaux)))
	for kind in nouveaux:
		h.ok(rotation.has(kind), "%s absent de la rotation" % kind)
		h.ok(D6Boss.boss_models().get(kind) != null, "%s : modèle non enregistré (boss_models)" % kind)
		h.ok(t.boss.get(kind) != null, "%s : données absentes de tuning.boss (boss_data)" % kind)
	var sections := int(ceilf(t.floors.total / t.floors.sectionLength))
	var seen := {}
	for s in range(1, sections + 1):
		var k = D6Floors.guardian_for(t, float(s))
		seen[k] = seen.get(k, 0) + 1
	for kind in _all_models():
		h.ok(seen.get(kind, 0) >= 9, "%s garde %s sections sur %d" % [kind, str(seen.get(kind)), sections])
	# Le VRAI jeu (sans rotation forcée) : chaque modèle apparaît à l'étage du Gardien de sa section.
	for s in range(1, rotation.size() + 2):
		var floor_n: float = D6Floors.section_bounds(t, float(s)).guardian
		var g: Dictionary = h.partie({"seed": float(s), "startFloor": floor_n})
		h.egal(g.info.isBoss, true, "étage %s : salle de Gardien" % D6Js.num_str(floor_n))
		var boss = _find_boss(g)
		if not h.ok(boss != null, "étage %s : Gardien présent" % D6Js.num_str(floor_n)):
			continue
		h.egal(boss.kind, D6Floors.guardian_for(t, float(s)), "section %d" % s)
		h.egal(boss.kind, rotation[(s - 1) % rotation.size()])

static func _pattern_names(kind: String) -> Array:
	var names: Array = []
	for phase in [1, 2, 3]:
		for pattern_name in _by_phase(kind, phase):
			if not names.has(pattern_name):
				names.append(pattern_name)
	return names

static func _t_donnees(h) -> void:
	var t: Dictionary = h.partie({"seed": 1.0}).tuning
	for kind in _new_models():
		var d: Dictionary = t.boss[kind]
		var model := _model(kind)
		h.ok(d.phase2At > d.phase3At and d.phase3At > 0.0 and d.phase2At < 1.0, "%s : seuils de phase" % kind)
		var names := _pattern_names(kind)
		h.ok(names.size() >= 3 and names.size() <= 5, "%s : %d patterns" % [kind, names.size()])
		for pattern_name in names:
			h.ok(model.patterns.get(pattern_name) is Callable, "%s/%s : pas de code" % [kind, pattern_name])
			h.ok(d.get(pattern_name) is Dictionary, "%s/%s : pas de données de tuning" % [kind, pattern_name])
		for field in ["hp", "radius", "speed", "hitstopCap", "transition", "phaseHealOrb"]:
			h.ok(_n(d, field) > 0.0, "%s.%s" % [kind, field])
		# Les patterns de Charon ne se retrouvent pas tels quels : identité propre.
		for pattern_name in names:
			h.ok(not _model("gardien").patterns.has(pattern_name), "%s/%s : copie d'un pattern de Charon" % [kind, pattern_name])

# ---------------------------------------------------------------- patterns

static func _t_patterns(h, kind: String) -> void:
	var covered: Array = []
	for phase in [1, 2, 3]:
		for pattern_name in _by_phase(kind, phase):
			_jouer_pattern(h, kind, phase, pattern_name)
			if not covered.has(pattern_name):
				covered.append(pattern_name)
	h.egal(covered.size(), _model(kind).patterns.size(), "%s : patterns jamais joués" % kind)

static func _jouer_pattern(h, kind: String, phase: int, pattern_name: String) -> void:
	var b := _boss_game(h, kind)
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, float(phase), pattern_name)
	var rec := _observe(h, g, boss, PATTERN_CAP, "", func(): return boss.state == "rest")
	var where := "%s/%s (phase %d)" % [kind, pattern_name, phase]
	h.ok(rec.finished, "%s : le pattern ne rend jamais la main" % where)
	var threats: int = rec.hazards.size() + rec.teleRuns.size() + rec.summons
	h.ok(threats > 0, "%s : aucune menace produite" % where)
	for z in rec.hazards.values():
		h.ok(z.delay >= _min_tele() - EPS, "%s : zone %s télégraphiée %s s" % [where, z.kind, z.delay])
	for r in rec.teleRuns:
		h.ok(r >= _min_tele() - EPS, "%s : télégraphe affiché %.3f s" % [where, r])
	h.ok(rec.cues > 0, "%s : aucun signal sonore (enemyAttack / bossSummon)" % where)

# ---------------------------------------------------------------- lisibilité : aucun coup sans télégraphe

static func _t_coups_telegraphies(h, kind: String) -> void:
	var b := _boss_game(h, kind, {"seed": 5.0})
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	var p: Dictionary = g.player
	# Héros increvable qui MARTÈLE au contact (le pire cas pour la lisibilité) : il encaisse tout.
	p.maxHp = 1e7
	p.hp = 1e7
	var rec := _observe(h, g, boss, MASHER_SECONDS, "masher", func(): return boss.dead)
	var a: Dictionary = ATTACKS[kind]
	var allowed: Array = a.hazards + a.body + a.shots + _add_kinds(g.tuning, kind)
	h.ok(rec.hurts.size() > 0, "%s : le marteleur n'a jamais été touché (test sans objet)" % kind)
	for hu in rec.hurts:
		h.ok(allowed.has(hu.source), "%s : dégâts de source inattendue « %s » (contact ?)" % [kind, str(hu.source)])
		if a.body.has(hu.source) and hu.source != "bossCharge":
			var tele_len: float = hu.teleNow if hu.teleNow > 0.0 else hu.teleLen
			h.ok(tele_len >= _min_tele() - DT - EPS, "%s : %s après un télégraphe de %.3f s" % [kind, hu.source, tele_len])
			h.ok(hu.teleNow > 0.0 or hu.sinceTele <= STRIKE_LAG + EPS, "%s : %s %.3f s après la fin de son télégraphe" % [kind, hu.source, hu.sinceTele])
	for z in rec.hazards.values():
		h.ok(z.delay >= _min_tele() - EPS, "%s : zone %s de %s s" % [kind, z.kind, z.delay])

static func _t_repos_sans_contact(h, kind: String) -> void:
	var b := _boss_game(h, kind)
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, 3.0, "rest", false)
	boss.restFor = 4.0
	var hurt := 0
	for i in h.ticks(4.0):
		if boss.state != "rest":
			break
		g.player.x = boss.x + boss.r * 0.5
		g.player.y = boss.y
		_step(g)
		hurt += _count(g.events, "playerHurt")
		g.events.clear()
	h.egal(hurt, 0)

# ---------------------------------------------------------------- phases

static func _t_transitions(h, kind: String) -> void:
	var b := _boss_game(h, kind)
	if b.boss == null:
		return
	var d: Dictionary = b.g.tuning.boss[kind]
	_transition(h, b.g, b.boss, kind, 2, d.phase2At)
	_transition(h, b.g, b.boss, kind, 3, d.phase3At)

static func _transition(h, g: Dictionary, boss: Dictionary, kind: String, phase: int, at: float) -> void:
	var d: Dictionary = g.tuning.boss[kind]
	_isolate(g, boss, float(phase - 1), _by_phase(kind, phase - 1)[0])
	_observe(h, g, boss, 0.3)
	h.ok(g.hazards.any(func(z): return D6Js.truthy(z.get("hitsPlayer"))) or boss.get("tele") != null or D6Js.truthy(boss.get("sub")), "%s : un pattern est en cours" % kind)
	boss.hp = floorf(boss.maxHp * at) - 1.0
	var pickups: int = g.pickups.size()
	_step(g)
	h.egal(boss.phase, phase, "%s : phase %d" % [kind, phase])
	h.egal(boss.state, "roar")
	h.ok(_n(boss, "invuln") > 0.0, "invulnérable pendant la transition")
	h.ok(g.events.any(func(ev): return ev.type == "bossPhase" and ev.get("phase") == float(phase)))
	h.egal(_pending(g), 0, "zones effacées")
	h.egal(_enemy_shots(g, false), 0, "projectiles effacés")
	h.ok(g.pickups.size() > pickups, "orbe de soin")
	h.egal(g.spawns.size(), d.reinforcements.get(str(phase), []).size(), "renforts du tuning")
	h.egal(D6Combat.damage_enemy(g, boss, _melee(50.0)), 0.0, "le coup ne porte pas")
	g.events.clear()
	# La transition finie, il reprend un pattern de SA nouvelle phase.
	g.spawns.clear()
	_observe(h, g, boss, d.transition + 0.2, "", func(): return boss.state != "roar")
	h.ok(_by_phase(kind, phase).has(boss.state), "%s : %s hors de la phase %d" % [kind, boss.state, phase])

# ---------------------------------------------------------------- mort

## Phase 3 : on enchaîne ses patterns jusqu'à avoir des menaces en attente. Rend leur nombre.
static func _armer_menaces(h, g: Dictionary, boss: Dictionary, kind: String) -> int:
	var phase3 := _by_phase(kind, 3)
	_isolate(g, boss, 3.0, phase3[0])
	var pending := 0
	for pattern_name in phase3:
		if boss.dead:
			break
		D6BossCommon.set_state(boss, pattern_name)
		boss.pattern = pattern_name
		_observe(h, g, boss, 0.5)
		pending = _pending(g)
	if kind == "colosse":
		# Braises allumées (éboulis en phase 3) et geôliers en jeu.
		D6BossCommon.set_state(boss, "eboulis")
		_observe(h, g, boss, 1.8)
		var pools = boss.get("pools")
		h.ok(pools != null and pools.size() > 0, "des braises brûlent")
		pending = _pending(g)
	return pending

static func _t_mort(h, kind: String) -> void:
	var b := _boss_game(h, kind)
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	var pending := _armer_menaces(h, g, boss, kind)
	h.ok(pending > 0 or boss.get("tele") != null, "%s : aucune menace en attente avant la mort (test sans objet)" % kind)
	boss.invuln = 0.0
	boss.shielded = false
	boss.hidden = false
	D6Combat.damage_enemy(g, boss, _melee(1e9))
	h.ok(boss.dead, "le Gardien est mort")
	g.player.iframes = 0.0
	# Le coup fatal fige la scène (gel de mort du Gardien) : rien n'avance pendant ce gel, puis
	# le premier pas de simulation annule tout ce qu'il avait lancé.
	for i in h.ticks(g.tuning.killHitstop.boss) + 2:
		_step(g)
		h.ok(_count(g.events, "playerHurt") == 0, "%s : coup reçu pendant le gel de mort" % kind)
		g.events.clear()
	h.egal(_pending(g), 0, "zones annulées")
	h.egal(_enemy_shots(g, true), 0, "projectiles annulés")
	h.egal(g.enemies.filter(func(e): return not e.dead).size() + g.spawns.size(), 0, "serviteurs morts avec lui")
	h.ok(g.room.cleared, "salle nettoyée")
	g.events.clear()
	_apres_la_mort(h, g, boss, kind)

static func _apres_la_mort(h, g: Dictionary, boss: Dictionary, kind: String) -> void:
	var kinds: Array = ATTACKS[kind].hazards
	for i in h.ticks(3.0):
		if g.mode != "play":
			break
		_step(g)
		for ev in g.events:
			h.different(ev.type, "playerHurt", "%s : coup reçu après sa mort (%s)" % [kind, str(ev.get("source"))])
			h.ok(not (ev.type == "hazardFire" and kinds.has(ev.get("kind"))), "%s : %s frappe après sa mort" % [kind, str(ev.get("kind"))])
			h.ok(not (ev.type == "enemyAttack" and ev.get("id") == boss.id), "%s : attaque d'un Gardien mort" % kind)
		g.events.clear()

# ---------------------------------------------------------------- déterminisme et profondeur

static func _digest(h, kind: String) -> Array:
	var b := _boss_game(h, kind, {"seed": 11.0})
	var trace: Array = []
	if b.boss == null:
		return trace
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	var mem := {}
	for i in h.ticks(DIGEST_SECONDS):
		if g.mode != "play":
			break
		D6Game.step_game(g, Bots.play("skilled", g, mem))
		g.events.clear()
		if i % 30 == 0:
			trace.append([boss.x, boss.y, boss.hp, boss.phase, boss.state, g.player.x, g.player.y, g.player.hp, g.hazards.size()])
	return trace

static func _t_deterministe(h, kind: String) -> void:
	var first := _digest(h, kind)
	h.ok(first.size() > 0, "%s : un combat a été joué" % kind)
	h.egal(first, _digest(h, kind))

static func _sample(h, kind: String, pattern_name: String, floor_n: float) -> Dictionary:
	var b := _boss_game(h, kind, {"seed": 9.0, "floor": floor_n})
	if b.boss == null:
		return {"delays": [], "teles": [], "damage": 0.0, "hp": 0.0}
	var boss: Dictionary = b.boss
	_isolate(b.g, boss, 3.0, pattern_name)
	var rec := _observe(h, b.g, boss, PATTERN_CAP, "", func(): return boss.state == "rest")
	var delays: Array = rec.hazards.values().map(func(z): return "%.4f" % z.delay)
	delays.sort()
	var damage := 0.0
	for z in rec.hazards.values():
		damage += z.damage
	return {"delays": delays, "teles": rec.teleRuns.map(func(r): return "%.3f" % r), "damage": damage, "hp": boss.maxHp}

static func _t_profondeur(h) -> void:
	for kind in _new_models():
		for pattern_name in _by_phase(kind, 3):
			var shallow := _sample(h, kind, pattern_name, UNIT_FLOOR)
			var deep := _sample(h, kind, pattern_name, DEEP_FLOOR)
			h.egal(deep.delays, shallow.delays, "%s/%s : télégraphes des zones" % [kind, pattern_name])
			h.egal(deep.teles, shallow.teles, "%s/%s : télégraphes au corps" % [kind, pattern_name])
			h.ok(deep.hp > shallow.hp, "%s : PV plus hauts en profondeur" % kind)
			if shallow.damage > 0.0:
				h.ok(deep.damage > shallow.damage, "%s/%s : dégâts plus hauts en profondeur" % [kind, pattern_name])

# ---------------------------------------------------------------- contre-jeu propre à chaque modèle

static func _t_cerbere_bond(h) -> void:
	var b := _boss_game(h, "cerbere")
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, 1.0, "bond", false)
	var p: Dictionary = g.player
	var target := {"x": p.x, "y": p.y}
	var airborne_ticks := 0
	var hurt_in_air := 0
	for i in h.ticks(3.0):
		if boss.state != "bond":
			break
		# Le héros reste dans la trajectoire du bond (sous le saut), hors du cercle d'atterrissage.
		if D6Js.truthy(boss.get("airborne")):
			airborne_ticks += 1
			p.x = boss.x
			p.y = boss.y
		elif g.hazards.is_empty():
			p.x = target.x
			p.y = target.y
		else:
			p.x = maxf(60.0, target.x - 300.0)
		_step(g)
		if D6Js.truthy(boss.get("airborne")):
			hurt_in_air += _count(g.events, "playerHurt")
		g.events.clear()
		if boss.get("sub") == "recover":
			break
	h.ok(airborne_ticks > 0, "il a bondi")
	h.egal(hurt_in_air, 0, "aucun dégât de contact en l'air")
	h.ok(_hypot(boss.x - target.x, boss.y - target.y) < boss.r + 1.0, "il retombe au centre du cercle annoncé")
	h.egal(boss.get("sub"), "recover")
	h.ok(boss.vuln > 0.0, "essoufflé : point faible exposé")

## Coups de fouet reçus en se tenant dans la brèche (ou à l'opposé).
static func _whip_hits(h, in_breach: bool) -> int:
	var b := _boss_game(h, "minos")
	if b.boss == null:
		return -1
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, 1.0, "fouet", false)
	_step(g)
	var p: Dictionary = g.player
	var a: float = boss.breachAngle if in_breach else boss.breachAngle + PI
	var hurt := 0
	for i in h.ticks(1.2):
		if boss.state != "fouet" or boss.patternStep != 0.0:
			break
		p.x = boss.x + D6Trig.cos(a) * 120.0
		p.y = boss.y + D6Trig.sin(a) * 120.0
		_step(g)
		hurt += _count(g.events, "playerHurt", "source", "minosWhip")
		g.events.clear()
	return hurt

static func _t_minos_fouet(h) -> void:
	h.egal(_whip_hits(h, true), 0, "dans la brèche : épargné")
	h.egal(_whip_hits(h, false), 1, "hors de la brèche : touché")
	var b := _boss_game(h, "minos")
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	_isolate(g, boss, 2.0, "sceau")
	_step(g)
	h.egal(boss.get("hidden"), true)
	h.egal(D6Combat.damage_enemy(g, boss, _melee(50.0)), 0.0, "dissous : intouchable")
	var ring = null
	for z in g.hazards:
		if z.get("kind") == "minosSeal":
			ring = z
			break
	h.ok(ring != null and ring.shape == "ring" and ring.inner > g.player.r * 2.0, "couronne avec un centre sûr")

static func _t_colosse(h) -> void:
	var b := _boss_game(h, "colosse")
	if b.boss == null:
		return
	_colosse_geoliers(h, b.g, b.boss)
	_colosse_bouclier_borne(h, b.g, b.boss)
	_colosse_poing(h, b.g, b.boss)
	_colosse_braises(h, b.g, b.boss)

static func _colosse_geoliers(h, g: Dictionary, boss: Dictionary) -> void:
	var d: Dictionary = g.tuning.boss.colosse
	_isolate(g, boss, 2.0, "geoliers")
	_observe(h, g, boss, d.geoliers.windup + 0.1)
	h.egal(boss.get("shielded"), true, "chaînes levées")
	h.egal(D6Combat.damage_enemy(g, boss, _melee(50.0)), 0.0, "invulnérable sous bouclier")
	_observe(h, g, boss, 1.0)
	var jailers: Array = g.enemies.filter(func(e): return D6Js.truthy(e.get("summoned")) and not e.dead)
	h.egal(jailers.size(), d.geoliers.countByPhase[1], "geôliers en jeu")
	for e in jailers:
		D6Combat.damage_enemy(g, e, _melee(1e6))
	_step(g)
	h.egal(boss.get("shielded"), false, "geôliers tombés : chaînes brisées")
	h.ok(D6Combat.damage_enemy(g, boss, _melee(50.0)) > 0.0, "il redevient vulnérable")

## Bouclier borné dans le temps même si un geôlier se cache.
static func _colosse_bouclier_borne(h, g: Dictionary, boss: Dictionary) -> void:
	var d: Dictionary = g.tuning.boss.colosse
	_isolate(g, boss, 2.0, "geoliers")
	_observe(h, g, boss, d.geoliers.windup + d.geoliers.shieldMax + 1.5, "", func():
		return not D6Js.truthy(boss.get("shielded")) and boss.state != "geoliers" and g.enemies.any(func(e): return D6Js.truthy(e.get("summoned"))))
	_observe(h, g, boss, d.geoliers.shieldMax + 0.5)
	h.egal(boss.get("shielded"), false, "bouclier tenu au plus %s s" % D6Js.num_str(d.geoliers.shieldMax))

## Poing : après le dernier coup, point faible exposé — les dégâts reçus sont majorés.
static func _colosse_poing(h, g: Dictionary, boss: Dictionary) -> void:
	var d: Dictionary = g.tuning.boss.colosse
	_isolate(g, boss, 1.0, "poing")
	boss.vuln = 0.0
	boss.vulnMult = 0.0
	var base: float = D6Combat.damage_enemy(g, boss, {"kind": "wall", "amount": 100.0})
	_observe(h, g, boss, PATTERN_CAP, "", func(): return boss.get("sub") == "recover")
	h.ok(boss.vuln > 0.0, "bras coincé : exposé")
	var exposed: float = D6Combat.damage_enemy(g, boss, {"kind": "wall", "amount": 100.0})
	h.ok(exposed >= base * (1.0 + d.poing.exposedMult) - 1.0, "exposé %s contre %s" % [exposed, base])

## Braises : jamais plus de poolMax, et elles s'éteignent.
static func _colosse_braises(h, g: Dictionary, boss: Dictionary) -> void:
	var d: Dictionary = g.tuning.boss.colosse
	_isolate(g, boss, 3.0, "eboulis")
	boss.pools = []
	for k in 3:
		D6BossCommon.set_state(boss, "eboulis")
		_observe(h, g, boss, 1.7)
	h.ok(boss.pools.size() > 0 and boss.pools.size() <= d.eboulis.poolMax, "braises : %d" % boss.pools.size())
	h.ok(g.hazards.any(func(z): return z.get("kind") == "colosseEmber"), "une braise pulse")
	_isolate(g, boss, 3.0, "rest")
	boss.restFor = 99.0
	_observe(h, g, boss, d.eboulis.poolLife + d.eboulis.poolPulse + 0.5)
	h.egal(boss.pools.size(), 0, "braises éteintes après poolLife")

# ---------------------------------------------------------------- équité (bots)

## Un combat d'entraînement à la profondeur du modèle : {won, dps}.
static func _fight(h, kind: String, floor_n: float, items: Dictionary, policy: String, seed_n: float) -> Dictionary:
	var g: Dictionary = h.partie({"seed": seed_n, "startFloor": floor_n, "practice": true, "items": items})
	var boss = _find_boss(g)
	h.ok(boss != null and boss.kind == kind, "étage %s : %s" % [D6Js.num_str(floor_n), kind])
	var mem := {}
	for i in h.ticks(EQUITE_SECONDS):
		if g.mode != "play" or g.room.cleared or g.player.state == "dead":
			break
		D6Game.step_game(g, Bots.play(policy, g, mem))
		g.events.clear()
	return {"won": D6Js.truthy(g.room.cleared), "dps": g.telemetry.damageTaken / maxf(1.0, g.time)}

static func _mean_dps(rs: Array) -> float:
	var total := 0.0
	for r in rs:
		total += r.dps
	return total / rs.size()

static func _t_equite(h) -> void:
	var t: Dictionary = h.partie({"seed": 1.0}).tuning
	for kind in _new_models():
		var floor_n: float = D6Floors.section_bounds(t, _section_of(t, kind)).guardian
		var items := _depth_items(h, floor_n)
		var skilled: Array = EQUITE_SEEDS.map(func(s): return _fight(h, kind, floor_n, items, "skilled", s))
		var no_dash: Array = EQUITE_SEEDS.map(func(s): return _fight(h, kind, floor_n, items, "noDash", s))
		var wins: int = skilled.filter(func(r): return r.won).size()
		h.ok(wins > EQUITE_SEEDS.size() / 2.0, "%s (étage %s) : le skilled gagne %d/%d" % [kind, D6Js.num_str(floor_n), wins, EQUITE_SEEDS.size()])
		var ratio := _mean_dps(no_dash) / maxf(1e-6, _mean_dps(skilled))
		h.ok(ratio >= MIN_DASH_VALUE, "%s : sans dash ×%.2f de dégâts reçus par seconde" % [kind, ratio])
		h.ok(no_dash.filter(func(r): return r.won).size() < wins, "%s : sans dash il gagne autant" % kind)

## Le test web enveloppe la partie dans un Proxy qui note chaque lecture et refuse toute écriture.
## GDScript n'a pas de Proxy : l'audit des LECTURES n'est pas portable. Le refus d'ÉCRIRE l'est :
## l'empreinte de toute la partie ne doit pas changer pendant l'appel de la politique.
static func _t_bots_audit(h) -> void:
	for kind in _new_models():
		for policy in Bots.POLICIES:
			var b := _boss_game(h, kind, {"seed": 4.0})
			if b.boss == null:
				continue
			var g: Dictionary = b.g
			var mem := {}
			var writes := 0
			for i in h.ticks(AUDIT_SECONDS):
				if g.mode != "play":
					break
				var before: int = g.hash()
				var input: Dictionary = Bots.play(policy, g, mem)
				if g.hash() != before:
					writes += 1
				D6Game.step_game(g, input)
				g.events.clear()
			h.egal(writes, 0, "%s contre %s : le bot ÉCRIT dans l'état de la partie" % [policy, kind])
	h.non_portable("audit des LECTURES du bot (champs interdits, lecture des télégraphes) : repose sur un Proxy JavaScript ; seule l'absence d'ÉCRITURE est vérifiée ici, par empreinte de la partie")

# ---------------------------------------------------------------- recréation V2 de feel_review (étage 18)

## Gardien de la section 1 (étage 18, run normal), seul, en début de pattern donné.
static func _guardian_in(h, pattern: String, phase: float = 1.0) -> Dictionary:
	var t: Dictionary = h.partie({"seed": 3.0}).tuning
	var g: Dictionary = h.partie({"seed": 3.0, "startFloor": D6Floors.section_bounds(t, 1.0).guardian})
	g.spawns.clear()
	var i := 0
	while i < 200 and not _boss_arrived(g):
		_step(g)
		i += 1
	var boss = _find_boss(g)
	if not h.ok(boss != null, "Gardien présent à l'étage 18"):
		return {"g": g, "boss": null}
	g.enemies = [boss]
	boss.phase = phase
	boss.state = pattern
	boss.stateTime = 0.0
	boss.patternStep = 0.0
	boss.patternT = 0.0
	boss.tele = null
	g.player.x = boss.x + 400.0
	g.player.y = boss.y
	g.player.iframes = 99.0
	g.events.clear()
	return {"g": g, "boss": boss}

static func _t_v2_anneau(h) -> void:
	var b := _guardian_in(h, "ring")
	if b.boss == null:
		return
	var g: Dictionary = b.g
	var boss: Dictionary = b.boss
	var r: Dictionary = g.tuning.boss[boss.kind].ring
	var waves := 0
	var missing := 0
	for i in 600:
		if boss.state != "ring":
			break
		_step(g)
		var fired := _count(g.events, "enemyAttack", "enemy", "bossRing")
		g.events.clear()
		waves += fired
		var tele = boss.get("tele")
		var shown: bool = tele != null and tele.get("shape") == "circle" and tele.get("r") == r.teleRadius
		if waves >= 1 and boss.state == "ring" and fired == 0 and not shown:
			missing += 1
	h.egal(waves, r.waves, "toutes les vagues de la phase 1 sont parties")
	h.egal(missing, 0, "%d ticks sans alerte entre deux vagues" % missing)

static func _t_v2_invocations(h) -> void:
	var b := _guardian_in(h, "summon", 3.0)
	if b.boss == null:
		return
	_step(b.g)
	if h.ok(b.boss.get("tele") != null, "alerte affichée"):
		h.egal(b.boss.tele.get("harmless"), true)
	# Les autres alertes sans danger des nouveaux Gardiens : appel des geôliers, incantations de Minos.
	for cas in [["colosse", "geoliers", 2.0], ["minos", "sentence", 1.0], ["minos", "jugement", 1.0]]:
		var kind: String = cas[0]
		var pattern: String = cas[1]
		var c := _boss_game(h, kind)
		if c.boss == null:
			continue
		_isolate(c.g, c.boss, cas[2], pattern)
		_step(c.g)
		if not h.ok(c.boss.get("tele") != null, "%s/%s : alerte affichée" % [kind, pattern]):
			continue
		h.egal(c.boss.tele.get("harmless"), true, "%s/%s : alerte inoffensive" % [kind, pattern])
		h.egal(c.boss.tele.get("shape"), "circle")

static func _t_v2_gel(h) -> void:
	for kind in _all_models():
		var b := _boss_game(h, kind)
		if b.boss == null:
			continue
		var g: Dictionary = b.g
		var boss: Dictionary = b.boss
		_isolate(g, boss, 1.0, "rest")
		var t: Dictionary = g.tuning
		var cap: float = t.boss[kind].hitstopCap
		boss.invuln = 0.0
		g.hitstop = 0.0
		D6Combat.damage_enemy(g, boss, {"kind": "melee", "amount": 1.0, "dirX": 1.0, "dirY": 0.0, "hitstop": t.combo[0].hitstop})
		var light: float = g.hitstop
		g.hitstop = 0.0
		g.hitstopBank = 1.0
		D6Combat.damage_enemy(g, boss, {"kind": "melee", "amount": 1.0, "dirX": 1.0, "dirY": 0.0, "hitstop": t.combo[2].hitstop})
		var heavy: float = g.hitstop
		h.ok(heavy <= cap + EPS, "%s : gel %s > plafond %s" % [kind, heavy, cap])
		h.ok(heavy > light, "%s : finisher %s contre coup léger %s" % [kind, heavy, light])
