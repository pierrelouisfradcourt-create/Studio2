extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_floors.test.mjs.
## Tests V2 — ÉTAGES : le système qui COMPOSE les 666 étages à partir de briques réutilisables,
## au lieu de les écrire à la main (demande de Pierre, priorité 6).
##   floors      structure (sections de 18, Gardien au 18e, checkpoints) et scaling ;
##   sections    plan PUR d'une section : rythme, portes imposées, vagues, budget,
##               dispositions, thème du Cercle, Gardien ;
##   room        dispositions et vagues ; run : composition de l'étage et des portes ;
##   calm_rooms  salles calmes réutilisables (chambre forte, fontaine de repos).
## Des lois, pas des valeurs : les seuils sont lus dans le tuning, sauf les exigences de la
## demande (666 étages, Gardien tous les 18).

const Bots = preload("res://outils/bots/bots.gd")
const Episode = preload("res://outils/bots/episode.gd")

# Exigences de la demande (pas des réglages) : 666 étages, un Gardien tous les 18.
const TOTAL_FLOORS := 666.0
const GUARDIAN_EVERY := 18.0
const SECTIONS := TOTAL_FLOORS / GUARDIAN_EVERY # 37
const PLAN_SEEDS := [1.0, 7.0, 12345.0]
const FLOOR_TYPES := ["combat", "elite", "boss", "shop", "event", "treasure", "rest"]
const ALL_OFFERS_EVERY := 7 # étages dont on construit la salle pour CHAQUE porte possible
const PATH_CELL := 8.0 # u : grille de la recherche de chemin à pied
const GEOM_EPS := 0.5 # u : arrondi toléré sur un contact mur / obstacle
const GEOMETRY_STEPS := 1800 # 30 s de combat par disposition nouvelle
const STEP_CAP := 600 # pas de sim pour franchir une porte / ouvrir un menu
const RHYTHM_SEEDS := [1.0, 2.0, 3.0, 4.0] # valeur web : [1, 2, 3, 4]
const DEEP_SECTIONS := [2.0, 20.0]
const DEEP_SEEDS := [1.0, 2.0] # valeur web : [1, 2]
const DEEP_MINUTES := 30.0
const SECONDS_PER_MINUTE := 60.0
const SPAWN_RADIUS := 30.0
const NEIGHBOURS := [[1, 0], [-1, 0], [0, 1], [0, -1]]

static func tests(h) -> void:
	var T: Dictionary = D6Game.create_game().tuning
	h.test("structure : 666 étages, 37 sections de 18, un Gardien tous les 18 étages (18, 36, …, 666)", func(): _structure(h, T))
	h.test("checkpoints : chaque Gardien ouvre le checkpoint 19, 37, … — le premier étage de la section suivante", func(): _checkpoints(h, T))
	h.test("Gardien de section : vaincu, il ouvre le checkpoint et le portail ; la porte suivante entre dans la nouvelle section", func(): _gardien_de_section(h, T))
	h.test("plan de section : pur, déterministe et complet pour les 37 sections", func(): _plan_de_section(h, T))
	h.test("portes imposées : Gardien au 18e, halte et antichambre imposées, élite et chambre forte garanties", func(): _portes_imposees(h, T))
	h.test("portes à l'exécution : chaque sortie respecte le plan de l'étage suivant (sections 1 et 2)", func(): _portes_execution(h, T))
	h.test("chaque étage 1..666 est composable : la salle se construit sans erreur, pour chaque porte possible", func(): _composable(h, T))
	h.test("répartition des types d'étage : chaque section offre combats, élites, chambre forte, repos, marchand/autel, Gardien", func(): _repartition(h, T))
	h.test("rythme : vagues par index — départ de section court, jamais deux assauts de suite, une pause avant le Gardien", func(): _rythme(h, T))
	h.test("rythme mobile mesuré : le bot boucle la section 1 en une session courte (estimation humaine ≤ tuning)", func(): _rythme_mobile(h, T))
	h.test("scaling : fini jusqu'à 666, croissant dans chaque section, Gardien le plus coriace, débuts de section croissants", func(): _scaling(h, T))
	h.test("début de section abordable : face au seul équipement permanent (aucune bénédiction), difficulté bornée", func(): _debut_abordable(h, T))
	h.test("reprise profonde jouable : le bot repart d'un checkpoint profond, équipement commun à niveau, et bat la section", func(): _reprise_profonde(h, T))
	h.test("chambre forte : salle sans combat, trois trésors annoncés, un seul pris (objet, bourse ou relique)", func(): _chambre_forte(h, T))
	h.test("fontaine de repos : boire soigne, méditer fait monter une bénédiction, les fioles rechargent ; jamais sans issue", func(): _fontaine(h, T))
	h.test("salles calmes : le bot les traverse (menus résolus, portes franchies)", func(): _bot_salles_calmes(h))
	h.test("dispositions : chacune (anciennes et nouvelles) laisse l'entrée libre, la récompense et les portes atteignables à pied", func(): _dispositions_atteignables(h, T))
	h.test("dispositions nouvelles : combat réel (bot, ennemis, charges) sans jamais entrer dans un obstacle ni un mur", func(): _dispositions_combat(h, T))
	h.test("dispositions : l'étage 1 est ouvert, l'étage 2 tire parmi exactement les 6 d'origine, les nouvelles servent plus bas", func(): _dispositions_usage(h, T))
	h.test("thèmes des Cercles : 9 Cercles + finale, bestiaire pondéré par coût sans nom d'archétype, tout le bestiaire présent", func(): _themes(h, T))
	h.test("arène d'essai : les vagues sans fin suivent le plan d'un étage de début de section", func(): _arene(h))

# ---------------------------------------------------------------- outillage

static func _layout_ids() -> Array:
	return D6Data.tables().room.LAYOUT_IDS

static func _combat_layouts() -> Array:
	return D6Data.tables().room.COMBAT_LAYOUTS

## Tous les flux RNG de la partie (pour prouver qu'un calcul ne les consomme pas).
static func _rng_state(g: Dictionary) -> String:
	return ":".join([str(g.rng.gen.s), str(g.rng.combat.s), str(g.rng.ai.s)])

## Pas de sim jusqu'à ce que `done(g)` soit vrai (ou STEP_CAP).
static func _step_until(g: Dictionary, done: Callable) -> bool:
	var i := 0
	while i < STEP_CAP and not done.call(g):
		D6Game.step_game(g, D6Game.empty_input())
		i += 1
	return done.call(g)

## Salle de combat vidée et terminée par la sim (récompense posée, portes préparées). Le gel
## d'impact de la salle précédente peut retarder la fin de quelques images.
static func _clear_combat(g: Dictionary) -> void:
	g.enemies.clear()
	g.spawns.clear()
	g.room.waveIndex = float(g.room.waves.size()) - 1.0
	_step_until(g, func(x): return D6Js.truthy(x.room.cleared))
	g.events.clear()

## Gardien abattu : la sim termine la salle (après un éventuel gel d'impact).
static func _kill_guardian(g: Dictionary) -> void:
	for e in g.enemies:
		e.dead = true
	g.spawns.clear()
	_step_until(g, func(x): return D6Js.truthy(x.room.cleared))
	g.events.clear()

## Le héros marche jusqu'à l'objet d'interaction (placé dessus) et le menu s'ouvre.
static func _touch_interact(g: Dictionary) -> bool:
	g.player.x = g.room.interact.x
	g.player.y = g.room.interact.y
	return _step_until(g, func(x): return x.mode == "choice")

## Recherche en largeur : le héros peut-il MARCHER de (x0, y0) jusqu'à toucher `goal` ?
static func _walkable(room: Dictionary, r: float, x0: float, y0: float, goal: Callable) -> bool:
	var cols := int(ceilf(room.w / PATH_CELL))
	var rows := int(ceilf(room.h / PATH_CELL))
	var seen := PackedByteArray()
	seen.resize(cols * rows)
	var start := int(floorf(y0 / PATH_CELL)) * cols + int(floorf(x0 / PATH_CELL))
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	while head < queue.size():
		var c: int = queue[head] % cols
		@warning_ignore("integer_division")
		var rw: int = queue[head] / cols
		head += 1
		if goal.call((c + 0.5) * PATH_CELL, (rw + 0.5) * PATH_CELL):
			return true
		for d in NEIGHBOURS:
			var nc: int = c + d[0]
			var nr: int = rw + d[1]
			if nc < 0 or nr < 0 or nc >= cols or nr >= rows or seen[nr * cols + nc] != 0:
				continue
			if D6Js.truthy(D6Physics.point_blocked(room, (nc + 0.5) * PATH_CELL, (nr + 0.5) * PATH_CELL, r)):
				continue
			seen[nr * cols + nc] = 1
			queue.append(nr * cols + nc)
	return false

static func _has_num(arr: Array, v: float) -> bool:
	for x in arr:
		if float(x) == v:
			return true
	return false

## new Set(arr) : les valeurs distinctes.
static func _unique(arr: Array) -> Array:
	var out: Array = []
	for v in arr:
		if not out.has(v):
			out.append(v)
	return out

static func _sorted(arr: Array) -> Array:
	var out := arr.duplicate()
	out.sort()
	return out

static func _find_boss(g: Dictionary):
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")):
			return e
	return null

# ---------------------------------------------------------------- structure

static func _structure(h, T: Dictionary) -> void:
	h.egal(T.floors.total, TOTAL_FLOORS)
	h.egal(T.floors.sectionLength, GUARDIAN_EVERY)
	h.egal(D6Sections.section_count(T), SECTIONS)
	var bosses: Array = []
	for f in range(1, int(TOTAL_FLOORS) + 1):
		if D6Floors.floor_info(T, float(f)).isBoss:
			bosses.append(float(f))
	var expected: Array = []
	for i in int(SECTIONS):
		expected.append((float(i) + 1.0) * GUARDIAN_EVERY)
	h.egal(bosses, expected)
	for si in range(1, int(SECTIONS) + 1):
		var s := float(si)
		var b: Dictionary = D6Floors.section_bounds(T, s)
		h.egal(b.first, (s - 1.0) * GUARDIAN_EVERY + 1.0)
		h.egal(b.guardian, s * GUARDIAN_EVERY)
		h.egal(D6Floors.floor_info(T, b.first).indexInSection, 1.0)
		h.egal(D6Floors.floor_info(T, b.guardian).section, s)
	h.egal(D6Floors.floor_info(T, TOTAL_FLOORS).isFinal, true)

static func _checkpoints(h, T: Dictionary) -> void:
	for si in range(1, int(SECTIONS)):
		var s := float(si)
		var g: float = s * GUARDIAN_EVERY
		h.egal(D6Floors.checkpoint_after_boss(T, g), g + 1.0)
		h.egal(D6Floors.section_bounds(T, s).checkpoint, g + 1.0)
		h.egal(D6Floors.section_bounds(T, s + 1.0).first, g + 1.0, "le checkpoint est le début de la section suivante")
	h.ok(D6Floors.checkpoint_after_boss(T, TOTAL_FLOORS) <= TOTAL_FLOORS, "aucun checkpoint au-delà du 666e étage")

static func _gardien_de_section(h, T: Dictionary) -> void:
	for s in [1.0, 2.0]:
		var b: Dictionary = D6Floors.section_bounds(T, s)
		var checkpoint: float = b.checkpoint
		var g: Dictionary = D6Game.create_game({"seed": 9.0, "startFloor": b.guardian})
		h.egal(g.room.kind, "boss")
		var boss = _find_boss(g)
		if h.ok(boss != null, "la salle du Gardien a son Gardien"):
			h.egal(boss.kind, D6Floors.guardian_for(T, s))
		_kill_guardian(g)
		h.ok(_has_num(g.meta.checkpoints, checkpoint), "checkpoint %s débloqué" % D6Js.num_str(checkpoint))
		if not h.egal(g.room.doors.size(), 2):
			continue
		h.egal(g.room.doors[1].reward, "town", "point de téléportation vers la Ville")
		# Le butin du Gardien pris, la porte « section suivante » mène au checkpoint.
		if _touch_interact(g):
			D6Game.apply_command(g, {"type": "salvage"})
		var d: Dictionary = g.room.doors[0]
		g.player.x = d.x + d.w / 2.0
		g.player.y = d.h
		h.ok(_step_until(g, func(x): return x.run.floor == checkpoint), "la porte mène au checkpoint")
		h.egal(g.info.section, s + 1.0)
		h.egal(g.info.indexInSection, 1.0)

# ---------------------------------------------------------------- plan de section

static func _check_plan_entry(h, T: Dictionary, e: Dictionary, i: int, first: float, where: String) -> void:
	h.egal(e.index, float(i) + 1.0, where)
	h.egal(e.floor, first + float(i), where)
	h.ok(is_finite(e.waves) and e.waves == floorf(e.waves) and e.waves >= 1.0, "%s : vagues %s" % [where, str(e.waves)])
	h.ok(is_finite(e.budget) and e.budget >= 1.0, "%s : budget %s" % [where, str(e.budget)])
	var ids := _layout_ids()
	h.ok(e.layouts.size() > 0 and e.layouts.all(func(l): return ids.has(l.id) and l.weight > 0.0), "%s : dispositions" % where)
	h.ok(e.roster.size() > 0 and e.roster.all(func(r): return D6Js.truthy(T.enemies.get(r.kind)) and r.weight > 0.0 and is_finite(r.weight)), "%s : bestiaire" % where)
	h.ok(e.offers.size() > 0 and e.types.all(func(k): return FLOOR_TYPES.has(k)), "%s : types %s" % [where, str(e.types)])

static func _check_plan(h, T: Dictionary, seed_n: float, s: float) -> void:
	var plan: Dictionary = D6Sections.section_plan(T, seed_n, s)
	h.egal(plan, D6Sections.section_plan(T, seed_n, s), "section %s : même graine, même plan" % D6Js.num_str(s))
	var b: Dictionary = D6Floors.section_bounds(T, s)
	h.egal(plan.section, s)
	h.egal(float(plan.floors.size()), GUARDIAN_EVERY)
	for i in plan.floors.size():
		var where := "graine %s section %s index %d" % [D6Js.num_str(seed_n), D6Js.num_str(s), i + 1]
		_check_plan_entry(h, T, plan.floors[i], i, b.first, where)
	var last: Dictionary = plan.floors[int(GUARDIAN_EVERY) - 1]
	h.egal(last.slot, "gardien")
	h.egal(last.doors, ["boss"])
	h.egal(last.guardian, D6Floors.guardian_for(T, s))
	h.egal(plan.guardian, D6Floors.guardian_for(T, s))

static func _plan_de_section(h, T: Dictionary) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 4.0})
	var before := _rng_state(g)
	for seed_n in PLAN_SEEDS:
		for si in range(1, int(SECTIONS) + 1):
			_check_plan(h, T, seed_n, float(si))
	h.egal(_rng_state(g), before, "le plan ne consomme aucun flux RNG de la partie")
	# Des graines différentes donnent des sections différentes (rythme, halte, chambre forte).
	var shapes := {}
	for seed_i in range(1, 21):
		var p: Dictionary = D6Sections.section_plan(T, float(seed_i), 5.0)
		shapes[JSON.stringify([p.rhythmId, p.treasureAt, p.floors.map(func(e): return e.doors)])] = true
	h.ok(shapes.size() > 1, "les sections varient avec la graine")

static func _check_imposed_entry(h, sec: Dictionary, e: Dictionary) -> void:
	if e.slot == "halte":
		h.egal(float(e.doors.size()), sec.halte.doors)
		h.egal(float(_unique(e.doors).size()), sec.halte.doors, "portes distinctes")
		var fixed: Array = D6Js.nz(sec.halte.get("fixed"), [])
		h.ok(fixed.all(func(r): return e.doors.has(r)), "la halte propose toujours ses portes fixes (repos)")
		h.ok(e.doors.all(func(r): return sec.halte.pool.get(r, 0.0) > 0.0 or fixed.has(r)))
	elif e.slot == "antichambre":
		h.egal(e.doors, sec.antichambre)
	elif e.slot != "gardien":
		h.egal(e.doors, null, "index %s : portes tirées" % D6Js.num_str(e.index))
	if sec.eliteAt.has(e.index) and e.doors == null:
		h.egal(e.guarantee, "elite")

static func _portes_imposees(h, T: Dictionary) -> void:
	var sec: Dictionary = T.section
	for seed_n in PLAN_SEEDS:
		for si in range(1, int(SECTIONS) + 1):
			var plan: Dictionary = D6Sections.section_plan(T, seed_n, float(si))
			var treasures := 0
			for e in plan.floors:
				_check_imposed_entry(h, sec, e)
				if e.guarantee is String and e.guarantee == "treasure":
					treasures += 1
					h.ok(e.index >= sec.treasure.from and e.index <= sec.treasure.to)
			h.egal(treasures, 1, "graine %s section %d : une chambre forte garantie" % [D6Js.num_str(seed_n), si])

static func _portes_execution(h, T: Dictionary) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 3.0})
	for fi in range(1, 2 * int(GUARDIAN_EVERY)):
		var f := float(fi)
		D6Run.enter_floor(g, f, {"reward": "gold"})
		if g.room.kind == "boss":
			_kill_guardian(g)
		else:
			_clear_combat(g)
		var next: Dictionary = D6Sections.floor_slot(T, g.seed, f + 1.0)
		var rewards: Array = g.room.doors.map(func(d): return d.reward)
		var where := "étage %d -> %d" % [fi, fi + 1]
		if g.room.kind == "boss":
			h.egal(rewards[1] if rewards.size() > 1 else null, "town", where)
			h.ok(rewards.size() > 0 and next.offers.has(rewards[0]), where)
		elif next.doors != null:
			h.egal(rewards, next.doors, where)
		else:
			if not h.egal(rewards.size(), 2, where):
				continue
			h.different(rewards[0], rewards[1], where)
			h.ok(rewards.all(func(r): return next.offers.has(r)), "%s : %s" % [where, str(rewards)])
			if next.guarantee != null:
				h.ok(rewards.has(next.guarantee), "%s : %s garanti" % [where, str(next.guarantee)])

# ---------------------------------------------------------------- composition des 666 étages

static func _last_wave_has_elite(room: Dictionary) -> bool:
	if room.waves.is_empty():
		return false
	return room.waves[-1].any(func(s): return D6Js.truthy(s.get("elite")))

static func _check_composed(h, T: Dictionary, g: Dictionary, f: float, reward) -> void:
	var where := "étage %s, porte %s" % [D6Js.num_str(f), str(reward)]
	D6Run.enter_floor(g, f, {"reward": reward})
	var slot: Dictionary = D6Sections.floor_slot(T, g.seed, f)
	var info: Dictionary = D6Floors.floor_info(T, f)
	var expected = "boss" if info.isBoss else D6Js.nz(D6Data.tables().sections.FLOOR_TYPE_OF_REWARD.get(reward), "combat")
	h.egal(g.room.kind, expected, where)
	h.egal(g.run.floor, f, where)
	var start: Dictionary = D6Room.player_start(g.room)
	h.ok(not D6Js.truthy(D6Physics.point_blocked(g.room, start.x, start.y, g.player.r)), "%s : entrée bouchée" % where)
	if expected == "boss":
		var kind = D6Floors.guardian_for(T, info.section)
		h.egal(g.enemies.filter(func(e): return D6Js.truthy(e.get("boss")) and e.kind == kind).size(), 1, where)
	elif expected == "combat" or expected == "elite":
		h.ok(slot.layouts.any(func(l): return l.id == g.room.layout), "%s : disposition %s" % [where, str(g.room.layout)])
		h.egal(float(g.room.waves.size()), slot.waves, where)
		h.ok(g.room.waves.all(func(w): return w.size() > 0), "%s : vague vide" % where)
		h.ok(g.spawns.size() > 0, "%s : la première vague apparaît" % where)
		if expected == "elite":
			h.ok(_last_wave_has_elite(g.room), "%s : champion" % where)
	else:
		var it = g.room.get("interact")
		h.egal(it.kind if it is Dictionary else null, expected, where)
		h.ok(g.room.doors.size() > 0 and g.room.doors.all(func(d): return D6Js.truthy(d.open)), "%s : salle calme, portes ouvertes" % where)

static func _composable(h, T: Dictionary) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 21.0})
	g.godMode = true
	for fi in range(1, int(TOTAL_FLOORS) + 1):
		var f := float(fi)
		var slot: Dictionary = D6Sections.floor_slot(T, g.seed, f)
		var offers: Array = slot.offers if fi % ALL_OFFERS_EVERY == 0 else [slot.offers[(fi * 7) % slot.offers.size()]]
		for reward in offers:
			_check_composed(h, T, g, f, reward)
		# Composition pure : même résultat, pour toutes les portes.
		for reward in slot.offers:
			h.egal(D6Sections.compose_floor(T, g.seed, f, {"reward": reward}), D6Sections.compose_floor(T, g.seed, f, {"reward": reward}))

static func _repartition(h, T: Dictionary) -> void:
	var totals := {}
	for k in FLOOR_TYPES:
		totals[k] = 0
	var paces := {}
	for si in range(1, int(SECTIONS) + 1):
		var plan: Dictionary = D6Sections.section_plan(T, 1.0, float(si))
		var types := {}
		for e in plan.floors:
			for k in e.types:
				types[k] = true
		for k in ["combat", "elite", "treasure", "rest", "boss"]:
			h.ok(types.has(k), "section %d : aucun étage %s" % [si, k])
		h.ok(types.has("shop") or types.has("event"), "section %d : ni marchand ni autel" % si)
		for e in plan.floors:
			for k in e.types:
				totals[k] += 1
			paces[e.slot] = paces.get(e.slot, 0) + 1
		var combat_slots: int = plan.floors.filter(func(e): return D6Js.truthy(T.section.paces.get(e.slot))).size()
		var calm_slots: int = plan.floors.filter(func(e): return e.slot == "halte" or e.slot == "antichambre").size()
		h.ok(combat_slots >= GUARDIAN_EVERY / 2.0, "section %d : %d combats seulement" % [si, combat_slots])
		h.ok(calm_slots >= 2, "section %d : au moins deux haltes" % si)
	h.egal(paces.get("gardien"), SECTIONS)
	for k in FLOOR_TYPES:
		h.ok(totals[k] > 0, "type %s jamais proposé" % k)

# ---------------------------------------------------------------- rythme

static func _waves_of(paces: Dictionary, slot) -> float:
	var p = paces.get(slot)
	return p.waves if p is Dictionary else 0.0

static func _check_rhythm(h, paces: Dictionary, r: Array, i: int) -> void:
	var all_waves: Array = paces.values().map(func(p): return p.waves)
	var max_waves: float = all_waves.max()
	h.egal(float(r.size()), GUARDIAN_EVERY, "rythme %d" % i)
	h.egal(r[-1], "gardien", "rythme %d : le 18e est le Gardien" % i)
	h.egal(_waves_of(paces, r[0]), all_waves.min(), "rythme %d : on repart du checkpoint par un étage court" % i)
	h.egal(_waves_of(paces, r[-2]), 0.0, "rythme %d : l'antichambre du Gardien est calme" % i)
	h.ok(r.slice(2, -2).any(func(slot): return not D6Js.truthy(paces.get(slot))), "rythme %d : une halte au milieu" % i)
	for k in range(1, r.size()):
		h.ok(not (_waves_of(paces, r[k]) == max_waves and _waves_of(paces, r[k - 1]) == max_waves), "rythme %d : deux assauts de suite (index %d)" % [i, k])

static func _rythme(h, T: Dictionary) -> void:
	var paces: Dictionary = T.section.paces
	var rhythms: Array = T.section.rhythms
	for i in rhythms.size():
		_check_rhythm(h, paces, rhythms[i], i)
	# Le plan applique le rythme : vagues de l'index = vagues de son allure ; budget croissant à allure égale.
	for si in range(1, int(SECTIONS) + 1):
		var plan: Dictionary = D6Sections.section_plan(T, 5.0, float(si))
		var last_budget := {}
		for e in plan.floors:
			var where := "section %d index %s" % [si, D6Js.num_str(e.index)]
			h.egal(e.waves, paces[e.pace].waves, where)
			if last_budget.has(e.pace):
				h.ok(e.budget > last_budget[e.pace], "%s : budget non croissant" % where)
			last_budget[e.pace] = e.budget

static func _rythme_mobile(h, T: Dictionary) -> void:
	var ses: Dictionary = T.section.session
	for seed_n in RHYTHM_SEEDS:
		var r: Dictionary = Episode.run_episode("skilled", seed_n, {"floors": GUARDIAN_EVERY, "minutes": DEEP_MINUTES})
		var who := "graine %s" % D6Js.num_str(seed_n)
		h.ok(r.sectionCleared, "%s : %s à l'étage %s" % [who, str(r.outcome), D6Js.num_str(r.floorReached)])
		var menus: float = D6Js.nz(r.eventCounts.get("choiceOpen"), 0.0)
		var human: float = (r.simSeconds * ses.humanPace + menus * ses.menuSeconds) / SECONDS_PER_MINUTE
		h.ok(human <= ses.maxMinutes, "%s : section estimée à %.1f min (bot %.1f min, %s menus)" % [who, human, r.simSeconds / SECONDS_PER_MINUTE, D6Js.num_str(menus)])

# ---------------------------------------------------------------- scaling jusqu'à 666

static func _scaling(h, T: Dictionary) -> void:
	var prev_start = null
	var prev = null
	for si in range(1, int(SECTIONS) + 1):
		var b: Dictionary = D6Floors.section_bounds(T, float(si))
		var last = null
		for fi in range(int(b.first), int(b.guardian) + 1):
			var sc: Dictionary = D6Floors.floor_scaling(T, float(fi))
			for k in ["hp", "damage", "density"]:
				h.ok(is_finite(sc[k]) and sc[k] >= 1.0, "étage %d : %s = %s" % [fi, k, str(sc[k])])
			if last != null:
				h.ok(sc.hp > last.hp and sc.damage > last.damage, "étage %d : la difficulté recule dans la section" % fi)
			if prev != null:
				h.ok(sc.damage >= prev.damage and sc.density >= prev.density, "étage %d : dégâts ou densité en recul" % fi)
			last = sc
			prev = sc
		var start: Dictionary = D6Floors.floor_scaling(T, b.first)
		if prev_start != null:
			h.ok(start.hp > prev_start.hp and start.damage > prev_start.damage, "section %d : plus facile que la précédente" % si)
		prev_start = start

static func _debut_abordable(h, T: Dictionary) -> void:
	# Temps pour tuer : croissant d'une section à l'autre. Part des PV par coup : elle plafonne
	# (D sature) — bornée, sans exiger de croissance (l'écart d'un étage d'équipement s'amenuise).
	var mx: Dictionary = T.floors.sectionStartMax
	var prev = null
	for si in range(1, int(SECTIONS) + 1):
		var d: Dictionary = D6Floors.section_start_difficulty(T, float(si))
		h.ok(d.toughness <= mx.toughness and d.lethality <= mx.lethality, "section %d : %s" % [si, str(d)])
		h.ok(d.toughness >= 1.0 and d.lethality >= 1.0, "section %d : plus facile que l'étage 1 (%s)" % [si, str(d)])
		if prev != null:
			h.ok(d.toughness >= prev.toughness - 1e-9, "section %d : le temps pour tuer recule" % si)
		prev = d
	h.egal(D6Floors.section_start_difficulty(T, 1.0), {"floor": 1.0, "toughness": 1.0, "lethality": 1.0})

## Équipement permanent « à niveau » : objets communs de l'étage précédant le checkpoint.
static func _level_gear(level: float) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": 77.0})
	var out := {}
	for slot in ["arme", "armure", "talisman"]:
		out[slot] = D6Loot.generate_item(g, {"slot": slot, "rarity": "commun", "floor": level})
	return out

static func _reprise_profonde(h, T: Dictionary) -> void:
	var max_tick: float = (DEEP_MINUTES * SECONDS_PER_MINUTE) / D6Data.DT
	for s in DEEP_SECTIONS:
		var b: Dictionary = D6Floors.section_bounds(T, s)
		for seed_n in DEEP_SEEDS:
			var g: Dictionary = D6Game.create_game({"seed": seed_n, "startFloor": b.first, "items": _level_gear(b.first - 1.0)})
			var mem := {}
			while g.tick < max_tick and g.run.floor <= b.guardian and (g.mode == "play" or g.mode == "choice"):
				if g.mode == "choice":
					if not h.ok(Bots.resolve_choice(g, "skilled"), "menu sans issue"):
						break # (le test web s'arrête ici sur une exception)
					continue
				D6Game.step_game(g, Bots.play("skilled", g, mem))
				g.events.clear()
			h.ok(g.run.floor > b.guardian or g.mode == "victory", "section %s graine %s : %s à l'étage %s" % [D6Js.num_str(s), D6Js.num_str(seed_n), g.mode, D6Js.num_str(g.run.floor)])

# ---------------------------------------------------------------- salles calmes

static func _calm_room(kind: String, seed_n: float = 5.0) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed_n, "startFloor": 3.0})
	D6Run.enter_floor(g, 4.0, {"reward": kind})
	g.events.clear()
	return g

static func _chambre_forte(h, T: Dictionary) -> void:
	var g := _calm_room("treasure")
	h.egal(g.room.kind, "treasure")
	h.egal(g.enemies.size() + g.spawns.size(), 0, "aucun combat")
	h.ok(g.room.doors.all(func(d): return D6Js.truthy(d.open)), "les portes ne retiennent pas le joueur")
	var it: Dictionary = g.room.interact
	h.ok(D6Js.truthy(it.get("item")) and it.gold > 0.0 and D6Js.truthy(it.get("family")), "contenu tiré à l'entrée")
	h.ok(_touch_interact(g))
	h.egal(g.choice.kind, "treasure")
	h.egal(g.choice.options.size(), 3)
	# Bourse : l'or tombe au sol et rejoint la bourse.
	var gold0: float = g.run.gold
	h.egal(D6Game.apply_command(g, {"type": "choose", "index": 1.0}), true)
	h.egal(g.mode, "play")
	h.ok(g.room.interact.used, "le coffre ne s'ouvre qu'une fois")
	_step_until(g, func(x): return x.pickups.size() == 0)
	var n: float = T.economy.treasure.goldPickups
	var each := maxf(1.0, D6Js.jround(it.gold / n))
	h.egal(g.run.gold - gold0, each * n)
	_chambre_forte_objet(h)
	_chambre_forte_relique(h)

## Objet : il attend d'être touché, puis rejoint l'équipement PERMANENT.
static func _chambre_forte_objet(h) -> void:
	var g2 := _calm_room("treasure")
	var item: Dictionary = g2.room.interact.item
	_touch_interact(g2)
	h.egal(D6Game.apply_command(g2, {"type": "choose", "index": 0.0}), true)
	h.egal(g2.room.interact.kind, "loot")
	h.ok(_step_until(g2, func(x): return x.mode == "choice"))
	h.egal(g2.choice.kind, "loot")
	var wieldable = g2.choice.get("wieldable")
	if not (wieldable is bool and wieldable == false):
		D6Game.apply_command(g2, {"type": "equip"})
		h.ok(is_same(g2.run.items[item.slot], item), "l'objet du coffre est porté (le même objet)")
		h.ok(is_same(g2.meta.equipment[item.slot], item), "équipement du profil (permanent)")

## Relique : une bénédiction (TEMPORAIRE) de la famille annoncée.
static func _chambre_forte_relique(h) -> void:
	var g3 := _calm_room("treasure")
	var fam = g3.room.interact.family
	_touch_interact(g3)
	D6Game.apply_command(g3, {"type": "choose", "index": 2.0})
	h.ok(_step_until(g3, func(x): return x.mode == "choice"))
	h.egal(g3.choice.kind, "boon")
	h.egal(g3.choice.family, fam)
	D6Game.apply_command(g3, {"type": "choose", "index": 0.0})
	h.egal(g3.run.boons.size(), 1)

static func _fontaine(h, T: Dictionary) -> void:
	var g := _calm_room("rest")
	h.egal(g.room.kind, "rest")
	h.egal(g.enemies.size() + g.spawns.size(), 0)
	var p: Dictionary = g.player
	p.hp = D6Js.jround(p.maxHp * 0.3)
	var hp0: float = p.hp
	_touch_interact(g)
	h.egal(g.choice.kind, "rest")
	h.egal(g.choice.options[1].disabled, true, "méditer exige une bénédiction")
	h.egal(D6Game.apply_command(g, {"type": "choose", "index": 1.0}), false)
	h.egal(D6Game.apply_command(g, {"type": "choose", "index": 0.0}), true)
	h.egal(p.hp, minf(p.maxHp, hp0 + p.maxHp * T.economy.rest.heal))
	h.ok(g.room.interact.used, "une seule grâce")
	# Méditer : la bénédiction la moins avancée gagne un niveau.
	var g2 := _calm_room("rest")
	D6Boons.add_boon(g2.run, {"id": D6Data.tables().boons.BOONS[0].id, "rarity": "commun"})
	_touch_interact(g2)
	h.egal(D6Game.apply_command(g2, {"type": "choose", "index": 1.0}), true)
	h.egal(g2.run.boons[0].level, 2.0)
	# Fioles : gadget plein, jauge de Super remontée.
	var g3 := _calm_room("rest")
	g3.player.gadgetCharges = 0.0
	g3.player.superCharge = 0.0
	_touch_interact(g3)
	h.egal(D6Game.apply_command(g3, {"type": "choose", "index": 2.0}), true)
	h.egal(g3.player.gadgetCharges, T.gadget.chargesPerSection + g3.player.stats.gadgetChargesBonus)
	h.egal(g3.player.superCharge, T.economy.rest.superCharge)
	# Pleine santé, aucune bénédiction, fioles pleines : un choix reste possible.
	var g4 := _calm_room("rest")
	g4.player.superCharge = 1.0
	_touch_interact(g4)
	h.ok(g4.choice.options.any(func(o): return not D6Js.truthy(o.get("disabled"))))

static func _bot_salles_calmes(h) -> void:
	for kind in D6Data.tables().calm_rooms.CALM_KINDS:
		var g := _calm_room(kind, 8.0)
		var mem := {}
		var i := 0
		while i < STEP_CAP * 4 and g.run.floor == 4.0:
			i += 1
			if g.mode == "choice":
				if not h.ok(Bots.resolve_choice(g, "skilled"), "%s : menu sans issue pour le bot" % kind):
					break
			else:
				D6Game.step_game(g, Bots.play("skilled", g, mem))
		h.egal(g.run.floor, 5.0, "%s : le bot reste bloqué" % kind)

# ---------------------------------------------------------------- dispositions et thèmes

## Salle de l'étage `floor` reconstruite avec la disposition `id` imposée.
static func _force_layout(T: Dictionary, g: Dictionary, floor: float, id: String) -> void:
	var plan: Dictionary = D6Sections.compose_floor(T, g.seed, floor, {"reward": "boon"}).duplicate()
	plan.layouts = [{"id": id, "weight": 1.0}]
	g.room = D6Room.build_room(g, g.info, plan)
	g.room.plan = plan

static func _dispositions_atteignables(h, T: Dictionary) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 2.0, "startFloor": 2.0})
	for id in _layout_ids():
		_force_layout(T, g, 2.0, id)
		h.egal(g.room.layout, id)
		var start: Dictionary = D6Room.player_start(g.room)
		g.player.merge(start, true)
		h.ok(not D6Js.truthy(D6Physics.point_blocked(g.room, start.x, start.y, g.player.r)), "%s : entrée bouchée" % id)
		h.ok(D6Js.truthy(D6Spawns.find_spawn_point(g, SPAWN_RADIUS, T.room.spawnMinPlayerDist)), "%s : aucun point d'apparition" % id)
		g.room.waveIndex = float(g.room.waves.size()) - 1.0
		D6Run.on_room_clear(g)
		var it = g.room.get("interact")
		if not h.ok(it is Dictionary, "%s : récompense posée" % id):
			continue
		var spot: Dictionary = D6Room.reward_spot(g.room)
		h.egal([it.x, it.y], [spot.x, spot.y])
		var r: float = g.player.r
		h.ok(_walkable(g.room, r, start.x, start.y, func(x, y): return sqrt((x - it.x) * (x - it.x) + (y - it.y) * (y - it.y)) < r + it.r), "%s : récompense hors d'atteinte" % id)
		for d in g.room.doors:
			h.ok(_walkable(g.room, r, start.x, start.y, func(x, y): return x > d.x and x < d.x + d.w and y - r < d.y + d.h), "%s : porte %s hors d'atteinte" % [id, str(d.reward)])

## Profondeur d'un cercle dans un rectangle (> 0 : chevauchement).
static func _rect_depth(o: Dictionary, x: float, y: float, r: float) -> float:
	var inside: bool = x > o.x0 and x < o.x1 and y > o.y0 and y < o.y1
	if inside:
		return r + minf(minf(x - o.x0, o.x1 - x), minf(y - o.y0, o.y1 - y))
	var dx: float = x - minf(maxf(x, o.x0), o.x1)
	var dy: float = y - minf(maxf(y, o.y0), o.y1)
	return r - sqrt(dx * dx + dy * dy)

## Premier corps (héros, ennemi vivant) hors des murs ou dans un obstacle : "" si aucun.
static func _body_fault(g: Dictionary, id: String) -> String:
	var room: Dictionary = g.room
	var bodies: Array = [g.player] + g.enemies.filter(func(e): return not D6Js.truthy(e.get("dead")))
	for b in bodies:
		var who = D6Js.nz(b.get("kind"), "héros")
		var lo: float = room.pad + b.r - GEOM_EPS
		if not (b.x >= lo and b.x <= room.w - lo and b.y >= lo and b.y <= room.h - lo):
			return "%s : %s hors des murs" % [id, who]
		for o in room.obstacles:
			if not (_rect_depth(o, b.x, b.y, b.r) <= GEOM_EPS):
				return "%s : %s dans un obstacle" % [id, who]
	return ""

static func _dispositions_combat(h, T: Dictionary) -> void:
	var combat := _combat_layouts()
	var fresh: Array = _layout_ids().filter(func(id): return not combat.has(id))
	h.ok(fresh.size() > 0)
	for id in fresh:
		var g: Dictionary = D6Game.create_game({"seed": 6.0, "startFloor": 300.0, "godMode": true})
		g.enemies.clear()
		g.spawns.clear()
		_force_layout(T, g, 300.0, id)
		g.player.merge(D6Room.player_start(g.room), true)
		D6Room.launch_next_wave(g)
		var mem := {}
		var seen := 0
		var i := 0
		while i < GEOMETRY_STEPS and g.mode != "dead":
			i += 1
			if g.mode == "choice":
				Bots.resolve_choice(g, "skilled")
			else:
				D6Game.step_game(g, Bots.play("skilled", g, mem))
			g.events.clear()
			# Une affirmation par image (le test web en pose une par corps et par obstacle) :
			# même loi, le message n'est composé qu'en cas de faute.
			var fault := _body_fault(g, id)
			h.ok(fault == "", fault)
			seen += g.enemies.filter(func(e): return not D6Js.truthy(e.get("dead"))).size()
		h.ok(seen > 0, "%s : aucun ennemi n'a été exercé" % id)

static func _dispositions_usage(h, T: Dictionary) -> void:
	var used := {}
	for seed_n in PLAN_SEEDS:
		h.egal(D6Sections.floor_slot(T, seed_n, 1.0).layouts.map(func(l): return l.id), ["open"])
		h.egal(_sorted(D6Sections.floor_slot(T, seed_n, 2.0).layouts.map(func(l): return l.id)), _sorted(_combat_layouts()))
		for si in range(1, int(SECTIONS) + 1):
			for e in D6Sections.section_plan(T, seed_n, float(si)).floors:
				for l in e.layouts:
					used[l.id] = true
	h.egal(_sorted(used.keys()), _sorted(_layout_ids()), "toute disposition sert quelque part")

static func _cheapest(roster: Array, sign: float) -> Dictionary:
	# roster.reduce((a, b) => (b.cost < a.cost ? b : a)) ; sign = -1 : le plus cher.
	var best: Dictionary = roster[0]
	for b in roster:
		if (b.cost - best.cost) * sign < 0.0:
			best = b
	return best

static func _check_theme(h, T: Dictionary, s: float, present: Array, base: Dictionary) -> void:
	var plan: Dictionary = D6Sections.section_plan(T, 3.0, s)
	var theme: Dictionary = D6Sections.circle_theme(T, plan.circle)
	var roster: Array = plan.floors[0].roster
	var txt := D6Js.num_str(s)
	h.egal(_sorted(roster.map(func(r): return r.kind)), _sorted(present.map(func(r): return r.kind)), "section %s : un archétype présent manque au tirage" % txt)
	h.egal(float(plan.theme.featured.size()), minf(theme.featured, float(present.size())))
	# Biais de coût : à poids de base égal, le plus cher gagne si costBias > 0, perd si < 0.
	var ratio := func(r): return r.weight / base[r.kind] / (theme.featuredMult if plan.theme.featured.has(r.kind) else 1.0)
	var cheap := _cheapest(roster, 1.0)
	var dear := _cheapest(roster, -1.0)
	var sign := signf(ratio.call(dear) - ratio.call(cheap))
	h.egal(sign, signf(theme.costBias), "section %s : biais de coût %s" % [txt, str(theme.costBias)])

static func _themes(h, T: Dictionary) -> void:
	h.egal(T.circles.size(), T.floors.circleNames.size() + 1)
	var present: Array = D6Data.tables().room.ROSTER.filter(func(r): return D6Js.truthy(T.enemies.get(r.kind)))
	var base := {}
	for r in present:
		base[r.kind] = r.weight
	# Cercle 1 neutre : les poids d'origine, à l'identique.
	for r in D6Sections.section_plan(T, 1.0, 1.0).floors[-2].roster:
		h.egal(r.weight, base[r.kind])
	for si in range(2, int(SECTIONS) + 1):
		_check_theme(h, T, float(si), present, base)
	# Aucun nom d'archétype dans le plan ni dans les thèmes : un archétype ajouté y entre seul.
	h.non_portable("la lecture du fichier source src/sim/sections.mjs (aucun nom d'archétype dans le code du plan) n'a pas d'équivalent ; le reste du test est porté")
	var themes := JSON.stringify(T.circles)
	for kind in T.enemies.keys():
		h.ok(not themes.contains("\"%s\"" % kind), "tuning.circles nomme l'archétype %s" % kind)

static func _arene(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 2.0, "sandbox": true})
	var refill = g.room.get("refill")
	if not h.ok(refill is Dictionary and refill.waves >= 1.0):
		return
	g.enemies.clear()
	g.spawns.clear()
	g.room.waveIndex = float(g.room.waves.size()) - 1.0
	D6Game.step_game(g, D6Game.empty_input())
	h.ok(g.spawns.size() > 0, "nouvelles vagues")
	h.egal(float(g.room.waves.size()), g.room.refill.waves)
