extends SceneTree
## Porté de tools/classes.mjs (version web, figée le 2026-10-01).
## Mesure des CLASSES (D11) : chaque kit (classe + arme) joué par les bots sur la section 1, et
## une expérience contrôlée « attaque maintenue sur place ». Écrit _dev/rapports/classes.md.
##
##   <godot> --headless --path . --script res://outils/classes.gd -- [graines=20] [--md chemin] [--no-md] [--tuning '{json}']
##
## --tuning : surcharges de réglage, pour un CONTREFACTUEL (le rapport n'est alors pas écrit) :
##   … -- --tuning '{"combat":{"stunGuard":0}}'    le jeu sans la garde -> ROUGE
##
## Quatre volets BLOQUANTS, par kit (ils gardent les deux défauts relevés par la relecture de
## la V2 : Hache et Maillet qui étourdissaient en boucle, Chasseresse qui se passait du dash) :
##   1. jouable     : le bot skilled bat la section 1 sur au moins MIN_CLEAR_RATE des graines ;
##   2. le dash compte : sans dash, au moins MIN_DASH_VALUE fois plus de dégâts par salle ;
##   3. sans dash, on paie : au moins MIN_NODASH_SHARE des dégâts par salle de l'étalon
##      (Revenant, Lame) joué sans dash — un kit ne remplace pas le dash par sa portée ;
##   4. sur place : attaque maintenue sans bouger, des brutes increvables placent au moins
##      MIN_HOLD_HITS coups en HOLD_SECONDS (armes de mêlée) — pas d'étourdissement en boucle.
## MESURES non bloquantes : section battue sans dash, mort du joueur qui martèle, durée, écart
## de dégâts reçus entre classes. Elles ne tranchent pas l'équilibrage : D11 se juge en main.
##
## Sortie 0 = PASS, 1 = FAIL, 2 = mesure incomplète ou arguments invalides.
## Réparti sur plusieurs PROCESSUS par outils/jouabilite.sh (voir outils/solvabilite.gd) :
##   … -- 20 --tranche 3/8 --sortie dossier/classes_3.json     … -- 20 --agreger dossier

const Episode = preload("res://outils/bots/episode.gd")
const Format = preload("res://outils/bots/format.gd")

const DEFAULT_SEEDS := 20
const DEFAULT_MD := "_dev/rapports/classes.md"
const MAX_MINUTES := 30.0
const REFERENCE_KIT := "revenant/lame" # l'étalon : les autres kits se lisent par rapport à lui
const POLICIES := ["skilled", "noDash", "masher"]
const MIN_CLEAR_RATE := 0.9
const MIN_DASH_VALUE := 2.0
const MIN_NODASH_SHARE := 0.7
const HOLD_SECONDS := 30.0
const MIN_HOLD_HITS := 3.0
const HOLD_SEEDS := 10
const HOLD_RING := 160.0 # u : distance de départ des ennemis autour du héros
const HOLD_HP := 1e9 # increvables : on mesure les coups placés, pas la vitesse de mise à mort
const HOLD_PACKS := {
	"brutes": ["brute", "brute"],
	"diablotins": ["imp", "imp", "imp"],
	"mêlée": ["brute", "imp", "brute", "imp", "imp"],
}
const HOLD_GATING_PACK := "brutes" # les diablotins sont tenus à distance par le RECUL : mesure seulement
const PARTIAL_PREFIX := "classes_"
const EXIT_INCOMPLETE := 2

func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("error"):
		print(args.error)
		quit(EXIT_INCOMPLETE)
		return
	if args.has("agreger"):
		quit(_report(args, _load_partials(args.agreger)))
		return
	var played := _play(args)
	if args.has("sortie"):
		var ok: bool = Format.write_exact(args.sortie, played)
		print("partiel : %s (%d parties, %d essais sur place)" % [args.sortie, played.episodes.size(), played.holds.size()])
		quit(0 if ok else EXIT_INCOMPLETE)
		return
	quit(_report(args, [played]))

## [graines] [--md chemin] [--no-md] [--tuning json] [--tranche i/n] [--sortie fichier] [--agreger dossier]
static func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {"seeds": DEFAULT_SEEDS, "slice": 0, "slices": 1, "md": DEFAULT_MD, "tuning": null}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		var value := argv[i + 1] if i + 1 < argv.size() else ""
		if a.is_valid_int():
			out.seeds = int(a)
		elif a == "--no-md":
			out.md = ""
		elif a == "--tranche":
			var parts := value.split("/")
			out.slice = int(parts[0])
			out.slices = int(parts[1]) if parts.size() > 1 else 0
			i += 1
		elif a == "--tuning":
			out.tuning = D6Js.decode(JSON.parse_string(value))
			if not (out.tuning is Dictionary):
				out.error = "--tuning attend un objet JSON"
			i += 1
		elif a in ["--md", "--sortie", "--agreger"] and value != "":
			out[a.trim_prefix("--")] = value
			i += 1
		else:
			out.error = "argument inconnu : %s" % a
		i += 1
	if out.seeds < 1 or out.slices < 1 or out.slice < 0 or out.slice >= out.slices:
		out.error = "graines >= 1 et tranche i/n avec 0 <= i < n attendus"
	if out.tuning != null:
		out.md = "" # un contrefactuel ne remplace jamais le rapport de référence
	return out

## Tous les kits jouables : [{id, classId, weaponType}], dans l'ordre des classes.
static func all_kits(tuning: Dictionary) -> Array:
	var out: Array = []
	for class_id in tuning.classes:
		for weapon_type in tuning.classes[class_id].weapons:
			out.append({"id": "%s/%s" % [class_id, weapon_type], "classId": class_id, "weaponType": weapon_type})
	return out

## Profil permanent : tout débloqué, la classe et l'arme demandées, compétence et gadget de départ
## dans les deux premiers emplacements. `slots` (facultatif) : trois emplacements choisis.
static func kit_profile(tuning: Dictionary, class_id: String, weapon_type, slots = null) -> Dictionary:
	var m: Dictionary = D6Profile.create_profile(tuning)
	for k in ["classes", "weapons", "skills", "gadgets"]:
		m.unlocked[k] = tuning[k].keys()
	var c: Dictionary = tuning.classes[class_id]
	m.loadout = {"classId": class_id, "slots": slots if slots is Array else [c.skills[0], c.gadgets[0], null]}
	m.equipment.arme = D6Profile.starter_weapon(tuning, D6Js.nz(weapon_type, c.weapons[0]))
	m.equipment.arme.uid = "i9000"
	return m

static func _mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x) if x != null else 0.0
	return s / xs.size() if not xs.is_empty() else 0.0

## [cos, sin] de l'angle (i / n) × 2π : la direction du i-ième ennemi d'une meute de n, en cercle.
## Par D6Trig, comme toute la simulation (jusqu'au 2026-10-01 : une table des valeurs de V8, pour
## égaler la version web ; 9 des 20 valeurs ont changé au dernier bit, voir parite/LISEZ_MOI.md).
static func _ring_dir(i: int, n: int) -> Array:
	var a := (float(i) / float(n)) * PI * 2.0
	return [D6Trig.cos(a), D6Trig.sin(a)]

## Salle vide, héros au centre, increvable, entouré de la meute `pack` increvable elle aussi.
static func _hold_arena(class_id: String, weapon_type: String, pack: Array, seed_n: float, tuning) -> Dictionary:
	var t: Dictionary = D6Data.create_tuning()
	var opts := {"seed": seed_n, "meta": kit_profile(t, class_id, weapon_type)}
	if tuning != null:
		opts.tuning = tuning
	var g: Dictionary = D6Game.create_game(opts)
	g.spawns.clear()
	g.enemies.clear()
	g.room.waves = []
	g.room.waveIndex = 0.0
	g.room.obstacles = []
	g.room.cleared = true
	g.room.interact = null
	g.room.doors = []
	var p: Dictionary = g.player
	p.x = g.room.w / 2.0
	p.y = g.room.h / 2.0
	p.maxHp = HOLD_HP
	p.hp = HOLD_HP
	for i in pack.size():
		var dir := _ring_dir(i, pack.size())
		var e: Dictionary = D6Enemies.create_enemy(g, pack[i], p.x + dir[0] * HOLD_RING, p.y + dir[1] * HOLD_RING, {"spawnT": 0.0})
		e.hp = HOLD_HP
		e.maxHp = HOLD_HP
	g.events.clear()
	return g

## Expérience contrôlée : le héros MAINTIENT l'attaque sans bouger. Rend le nombre de coups reçus
## en HOLD_SECONDS. `tuning` : surcharges (ex. {combat: {stunGuard: 0}} : le jeu sans la garde).
static func hold_trial(class_id: String, weapon_type: String, pack: Array, seed_n: float, tuning) -> float:
	var g := _hold_arena(class_id, weapon_type, pack, seed_n, tuning)
	var input: Dictionary = D6Game.empty_input()
	input.attack = true
	var hits := 0.0
	var i := 0.0
	while i < HOLD_SECONDS / Episode.DT:
		D6Game.step_game(g, input)
		for ev in g.events:
			if ev.type == "playerHurt":
				hits += 1.0
		g.events.clear()
		i += 1.0
	return hits

## Toutes les mesures, dans l'ordre du modèle web : par kit, les parties (politique, graine),
## puis les essais sur place (meute, graine).
static func _tasks(seeds: int) -> Array:
	var out: Array = []
	for kit in all_kits(D6Data.default_tuning()):
		for policy in POLICIES:
			for s in range(1, seeds + 1):
				out.append({"kit": kit, "policy": policy, "seed": float(s)})
		for pack in HOLD_PACKS:
			for s in range(1, HOLD_SEEDS + 1):
				out.append({"kit": kit, "pack": pack, "seed": float(s)})
	return out

## Joue les mesures de la tranche demandée. Rend {episodes, holds, ticks, ms}.
static func _play(args: Dictionary) -> Dictionary:
	var floors: float = D6Data.default_tuning().floors.sectionLength
	var tasks := _tasks(args.seeds)
	var out := {"episodes": [], "holds": [], "ticks": 0.0, "ms": 0.0}
	var t0 := Time.get_ticks_msec()
	for i in tasks.size():
		if i % int(args.slices) != int(args.slice):
			continue
		var task: Dictionary = tasks[i]
		var kit: Dictionary = task.kit
		if task.has("pack"):
			var hits := hold_trial(kit.classId, kit.weaponType, HOLD_PACKS[task.pack], task.seed, args.tuning)
			out.holds.append({"kit": kit.id, "pack": task.pack, "seed": task.seed, "hits": hits})
			continue
		var options := {"floors": floors, "minutes": MAX_MINUTES, "meta": kit_profile(D6Data.create_tuning(), kit.classId, kit.weaponType)}
		if args.tuning != null:
			options.tuning = args.tuning
		var r: Dictionary = Episode.run_episode(task.policy, task.seed, options)
		out.ticks += r.simSeconds / Episode.DT
		out.episodes.append({
			"kit": kit.id, "policy": r.policy, "seed": r.seed, "sectionCleared": r.sectionCleared, "deaths": r.deaths,
			"damagePerRoom": r.damagePerRoom, "floorReached": r.floorReached, "simSeconds": r.simSeconds,
		})
		print("  %s %s graine %s : %s, étage %s" % [kit.id, r.policy, D6Js.num_str(r.seed), r.outcome, D6Js.num_str(r.floorReached)])
	out.ms = float(Time.get_ticks_msec() - t0)
	return out

static func _load_partials(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(PARTIAL_PREFIX) and f.ends_with(".json"):
			var part = D6Js.read_exact(dir.path_join(f))
			if part is Dictionary:
				out.append(part)
	return out

## Les `count` mesures de clé `prefix` (graines 1 à count), dans l'ordre ; null s'il en manque.
static func _ordered(index: Dictionary, prefix: String, count: int):
	var out: Array = []
	for s in range(1, count + 1):
		var r = index.get("%s|%d" % [prefix, s])
		if r == null:
			return null
		out.append(r)
	return out

## Les mesures d'un bot sur un kit (playKit de classes.mjs), à partir de ses parties.
static func _kit_stats(runs: Array) -> Dictionary:
	var n := float(runs.size())
	return {
		"clearRate": runs.filter(func(r): return r.sectionCleared).size() / n,
		"deathRate": runs.filter(func(r): return r.deaths > 0.0).size() / n,
		"damagePerRoom": _mean(runs.map(func(r): return r.damagePerRoom)),
		"floorReached": _mean(runs.map(func(r): return r.floorReached)),
		"minutes": _mean(runs.map(func(r): return r.simSeconds)) / 60.0,
	}

## Index des mesures partielles : « kit|politique|graine » et « kit|meute|graine ».
static func _index(partials: Array) -> Dictionary:
	var index := {}
	for part in partials:
		for r in part.episodes:
			index["%s|%s|%d" % [r.kit, r.policy, int(r.seed)]] = r
		for h in part.holds:
			index["%s|%s|%d" % [h.kit, h.pack, int(h.seed)]] = h
	return index

## Une ligne de kit {id, melee, skilled, noDash, masher, dashValue, hold} ; null si incomplète.
static func _kit_row(kit: Dictionary, index: Dictionary, seeds: int, tuning: Dictionary):
	var row: Dictionary = kit.duplicate()
	row.melee = tuning.weapons[kit.weaponType].kind == "melee"
	for policy in POLICIES:
		var runs = _ordered(index, "%s|%s" % [kit.id, policy], seeds)
		if runs == null:
			return null
		row[policy] = _kit_stats(runs)
	row.dashValue = row.noDash.damagePerRoom / row.skilled.damagePerRoom if row.skilled.damagePerRoom > 0.0 else INF
	row.hold = {}
	for pack in HOLD_PACKS:
		var trials = _ordered(index, "%s|%s" % [kit.id, pack], HOLD_SEEDS)
		if trials == null:
			return null
		row.hold[pack] = _mean(trials.map(func(h): return h.hits))
	return row

static func _pct(x: float) -> String:
	return "%s %%" % Format.to_fixed(x * 100.0, 0)

## Les seuils bloquants franchis par le kit `k` (textes de classes.mjs).
static func _kit_failures(k: Dictionary) -> Array:
	var out: Array = []
	if k.skilled.clearRate < MIN_CLEAR_RATE:
		out.append("%s : section battue %s < %s %%" % [k.id, _pct(k.skilled.clearRate), Format.js_num(MIN_CLEAR_RATE * 100.0)])
	if k.dashValue < MIN_DASH_VALUE:
		out.append("%s : valeur du dash %s < %s" % [k.id, Format.to_fixed(k.dashValue, 2), Format.js_num(MIN_DASH_VALUE)])
	if k.noDashShare < MIN_NODASH_SHARE:
		out.append("%s : sans dash, %s des dégâts de l'étalon < %s %%" % [k.id, _pct(k.noDashShare), Format.js_num(MIN_NODASH_SHARE * 100.0)])
	if k.melee and k.hold[HOLD_GATING_PACK] < MIN_HOLD_HITS:
		out.append("%s : sur place, %s coups de brutes en %s s < %s" % [k.id, Format.to_fixed(k.hold[HOLD_GATING_PACK], 1), Format.js_num(HOLD_SECONDS), Format.js_num(MIN_HOLD_HITS)])
	return out

## Mesure complète (measureClasses) : {seeds, kits, failures} ; null si des mesures manquent.
static func measure(seeds: int, partials: Array):
	var tuning: Dictionary = D6Data.default_tuning()
	var index := _index(partials)
	var kits: Array = []
	var ref = null
	for kit in all_kits(tuning):
		var row = _kit_row(kit, index, seeds, tuning)
		if row == null:
			return null
		kits.append(row)
		if row.id == REFERENCE_KIT:
			ref = row
	var failures: Array = []
	for k in kits:
		k.noDashShare = k.noDash.damagePerRoom / ref.noDash.damagePerRoom if ref != null and ref.noDash.damagePerRoom > 0.0 else 1.0
		failures.append_array(_kit_failures(k))
	return {"seeds": float(seeds), "kits": kits, "failures": failures}

static func _kit_name(k: Dictionary) -> String:
	var t: Dictionary = D6Data.default_tuning()
	return "%s · %s" % [t.classes[k.classId].name, t.weapons[k.weaponType].name]

static func _md_section(report: Dictionary, floors: float) -> Array:
	var seeds := Format.js_num(report.seeds)
	var lines: Array = [
		"# Dungeon 666 — mesure des classes (bots)",
		"",
		"Généré par `outils/classes.gd %s` (version Godot) : %s graines par kit et par bot, section 1 (%s étages)." % [seeds, seeds, Format.js_num(floors)],
		"Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni",
		"l'équilibrage ressenti : **D11 se juge en main**.",
		"",
		"## Section 1 jouée par les bots",
		"",
		"| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |",
		"|---|---|---|---|---|---|---|---|---|---|",
	]
	for k in report.kits:
		lines.append("| %s | %s | %s | %s | ×%s | %s | %s | %s | %s | %s min |" % [
			_kit_name(k), _pct(k.skilled.clearRate), Format.to_fixed(k.skilled.damagePerRoom, 1), Format.to_fixed(k.noDash.damagePerRoom, 1),
			Format.to_fixed(k.dashValue, 1), _pct(k.noDashShare), _pct(k.noDash.clearRate), _pct(k.masher.deathRate),
			Format.to_fixed(k.masher.floorReached, 1), Format.to_fixed(k.skilled.minutes, 1),
		])
	lines.append_array([
		"",
		"Seuils bloquants : section battue ≥ %s ; valeur du dash ≥ ×%s ; sans dash, au moins %s des dégâts/salle de l'étalon (%s)." % [_pct(MIN_CLEAR_RATE), Format.js_num(MIN_DASH_VALUE), _pct(MIN_NODASH_SHARE), REFERENCE_KIT],
		"",
	])
	return lines

static func _md_hold(report: Dictionary) -> Array:
	var heads: Array = []
	var rules: Array = []
	for pack in HOLD_PACKS:
		heads.append("%s (%d)" % [pack, HOLD_PACKS[pack].size()])
		rules.append("---")
	var lines: Array = [
		"## Attaque maintenue sur place (ennemis increvables)",
		"",
		"Le héros ne bouge pas et maintient l'attaque %s s. Coups reçus, moyenne de %d graines." % [Format.js_num(HOLD_SECONDS), HOLD_SEEDS],
		"",
		"| Kit | %s |" % " | ".join(heads),
		"|---|%s|" % "|".join(rules),
	]
	for k in report.kits:
		var cells: Array = []
		for pack in HOLD_PACKS:
			cells.append(Format.to_fixed(k.hold[pack], 1))
		lines.append("| %s%s | %s |" % [_kit_name(k), "" if k.melee else " (à distance)", " | ".join(cells)])
	lines.append_array([
		"",
		"Seuil bloquant (armes de mêlée) : au moins %s coups de brutes en %s s. Les diablotins restent une mesure :" % [Format.js_num(MIN_HOLD_HITS), Format.js_num(HOLD_SECONDS)],
		"une arme lourde les tient à distance par son recul, pas par l'étourdissement.",
		"",
	])
	return lines

static func render_markdown(report: Dictionary) -> String:
	var lines := _md_section(report, D6Data.default_tuning().floors.sectionLength)
	lines.append_array(_md_hold(report))
	lines.append_array(["## Verdict : %s" % ("ROUGE" if not report.failures.is_empty() else "VERT"), ""])
	if report.failures.is_empty():
		lines.append("Tous les seuils bloquants passent.")
	else:
		for f in report.failures:
			lines.append("- %s" % f)
	lines.append("")
	return "\n".join(lines)

static func _write_md(md: String, text: String) -> void:
	var path := md if md.is_absolute_path() else ProjectSettings.globalize_path("res://").path_join(md)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("  rapport NON écrit : %s" % md)
		return
	f.store_string(text)
	f.close()
	print("  rapport : %s" % md)

## La ligne FORGE_ORACLE de classes.mjs, clé pour clé.
static func _verdict(report: Dictionary) -> Dictionary:
	var kits := {}
	for k in report.kits:
		kits[k.id] = {
			"clearRate": k.skilled.clearRate, "dashValue": Format.fixed(k.dashValue, 2), "noDashShare": Format.fixed(k.noDashShare, 2),
			"noDashClearRate": k.noDash.clearRate, "masherDeathRate": k.masher.deathRate, "holdHits": Format.fixed(k.hold[HOLD_GATING_PACK], 1),
		}
	return {"seeds": report.seeds, "kits": kits, "failures": report.failures}

## Écrit la mesure comme classes.mjs. Rend le code de sortie.
static func _report(args: Dictionary, partials: Array) -> int:
	var report = measure(args.seeds, partials)
	if report == null:
		print("mesure incomplète : il manque des parties ou des essais sur place (graines 1 à %d)" % args.seeds)
		return EXIT_INCOMPLETE
	for k in report.kits:
		print("  %s battue %s · dash ×%s · sans dash %s de l'étalon (battue %s) · martèle : étage %s · sur place (brutes) %s" % [
			k.id.rpad(22), _pct(k.skilled.clearRate).lpad(5), Format.to_fixed(k.dashValue, 1).lpad(4), _pct(k.noDashShare).lpad(5),
			_pct(k.noDash.clearRate), Format.to_fixed(k.masher.floorReached, 1), Format.to_fixed(k.hold[HOLD_GATING_PACK], 1),
		])
	if args.md != "":
		_write_md(args.md, render_markdown(report))
	print("FORGE_ORACLE classes %s" % Format.to_json(_verdict(report)))
	for f in report.failures:
		print("  ROUGE — %s" % f)
	var ticks := 0.0
	var ms := 0.0
	for part in partials:
		ticks += part.ticks
		ms += part.ms
	print("  calcul : %d processus, %.0f s cumulées" % [partials.size(), ms / 1000.0])
	print("CLASSES: %s" % ("FAIL" if not report.failures.is_empty() else "PASS"))
	return 1 if not report.failures.is_empty() else 0
