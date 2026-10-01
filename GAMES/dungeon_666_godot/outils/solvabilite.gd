extends SceneTree
## Portage de solvability.mjs.
## Solvabilité (convention du studio : forge/contracts/s9-build.yaml) — un bot JOUE et GAGNE.
## « Gagner », dans un jeu de 666 étages, c'est ici battre la section 1 : vaincre le premier
## Gardien (étage 18, tuning.floors.sectionLength) et atteindre le checkpoint de l'étage 19.
##
## Le bot `skilled` (outils/bots/) ne lit que ce que voit un joueur (télégraphes, zones,
## projectiles), avec un temps de réaction de 0,15 s ; il ne lit jamais le RNG.
##
## Deux volets BLOQUANTS :
##   1. jouable  : le bot skilled bat la section 1 sur au moins MIN_CLEAR_RATE des graines ;
##   2. le dash compte : sans dash, on encaisse au moins MIN_DASH_VALUE fois plus de dégâts
##      par salle (pilier n°1 de la charte — mesure de plausibilité, pas une preuve de fun).
## Un volet de MESURE, non bloquant : taux de mort d'un joueur qui « martèle » sans lire.
##
##   <godot> --headless --path . --script res://outils/solvabilite.gd -- [graines=20]
## Sortie 0 = PASS, 1 = FAIL, 2 = mesure incomplète ou arguments invalides.
##
## Le GDScript joue ~3 000 pas par seconde (V8 : ~100 fois plus) : 60 parties dans un seul
## processus prennent un quart d'heure. outils/jouabilite.sh répartit donc les parties sur
## plusieurs PROCESSUS (jamais de fils : la simulation a des variables statiques partagées) :
##   … -- 20 --tranche 3/8 --sortie dossier/solvabilite_3.json   joue une partie sur huit, écrit un partiel
##   … -- 20 --agreger dossier                                    relit les partiels, rend le verdict

const Episode = preload("res://outils/bots/episode.gd")
const Format = preload("res://outils/bots/format.gd")

const DEFAULT_SEEDS := 20
const FIRST_SEED := 1
const MAX_MINUTES := 30.0 # une section de 18 étages : ~12-15 min de jeu pour le bot
const MIN_CLEAR_RATE := 0.9
const MIN_DASH_VALUE := 2.0
const POLICIES := ["skilled", "noDash", "masher"]
const PARTIAL_PREFIX := "solvabilite_"
const EXIT_INCOMPLETE := 2

func _initialize() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	if args.has("error"):
		print(args.error)
		quit(EXIT_INCOMPLETE)
		return
	if args.has("agreger"):
		quit(_report(args.seeds, _load_partials(args.agreger)))
		return
	var played := _play(args)
	if args.has("sortie"):
		var ok: bool = Format.write_exact(args.sortie, played)
		print("partiel : %s (%d parties, %.0f pas/s)" % [args.sortie, played.runs.size(), _rate(played)])
		quit(0 if ok else EXIT_INCOMPLETE)
		return
	quit(_report(args.seeds, [played]))

## [graines] [--tranche i/n] [--sortie fichier] [--agreger dossier]
static func _parse_args(argv: PackedStringArray) -> Dictionary:
	var out := {"seeds": DEFAULT_SEEDS, "slice": 0, "slices": 1}
	var i := 0
	while i < argv.size():
		var a := argv[i]
		if a.is_valid_int():
			out.seeds = int(a)
		elif a == "--tranche" and i + 1 < argv.size():
			i += 1
			var parts := argv[i].split("/")
			out.slice = int(parts[0])
			out.slices = int(parts[1]) if parts.size() > 1 else 0
		elif (a == "--sortie" or a == "--agreger") and i + 1 < argv.size():
			i += 1
			out[a.trim_prefix("--")] = argv[i]
		else:
			out.error = "argument inconnu : %s\nusage : -- [graines] [--tranche i/n --sortie fichier] [--agreger dossier]" % a
		i += 1
	if out.seeds < 1 or out.slices < 1 or out.slice < 0 or out.slice >= out.slices:
		out.error = "graines >= 1 et tranche i/n avec 0 <= i < n attendus"
	return out

## Toutes les parties de la mesure, dans l'ordre du modèle web : politique, puis graine.
static func _tasks(seeds: int) -> Array:
	var out: Array = []
	for policy in POLICIES:
		for s in range(FIRST_SEED, FIRST_SEED + seeds):
			out.append({"policy": policy, "seed": float(s)})
	return out

## Joue les parties de la tranche demandée. Rend {runs, ticks, ms}.
static func _play(args: Dictionary) -> Dictionary:
	var floors: float = D6Data.default_tuning().floors.sectionLength
	var tasks := _tasks(args.seeds)
	var runs: Array = []
	var ticks := 0.0
	var t0 := Time.get_ticks_msec()
	for i in tasks.size():
		if i % int(args.slices) != int(args.slice):
			continue
		var task: Dictionary = tasks[i]
		var r: Dictionary = Episode.run_episode(task.policy, task.seed, {"floors": floors, "minutes": MAX_MINUTES})
		ticks += r.simSeconds / Episode.DT
		runs.append({
			"policy": r.policy, "seed": r.seed, "sectionCleared": r.sectionCleared, "damagePerRoom": r.damagePerRoom,
			"deaths": r.deaths, "floorReached": r.floorReached, "outcome": r.outcome, "deathCauses": r.deathCauses,
		})
		print("  %s graine %s : %s, étage %s" % [r.policy, D6Js.num_str(r.seed), r.outcome, D6Js.num_str(r.floorReached)])
	return {"runs": runs, "ticks": ticks, "ms": float(Time.get_ticks_msec() - t0)}

static func _rate(played: Dictionary) -> float:
	return played.ticks / maxf(played.ms / 1000.0, 0.001)

static func _load_partials(dir: String) -> Array:
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(PARTIAL_PREFIX) and f.ends_with(".json"):
			var part = D6Js.read_exact(dir.path_join(f))
			if part is Dictionary:
				out.append(part)
	return out

## Les parties d'une politique, dans l'ordre des graines ; null s'il en manque ou s'il y en a trop.
static func _runs_of(partials: Array, policy: String, seeds: int):
	var by_seed := {}
	for part in partials:
		for r in part.runs:
			if r.policy == policy:
				by_seed[int(r.seed)] = r
	var out: Array = []
	for s in range(FIRST_SEED, FIRST_SEED + seeds):
		if not by_seed.has(s):
			return null
		out.append(by_seed[s])
	return out if by_seed.size() == seeds else null

static func _mean(xs: Array) -> float:
	var s := 0.0
	for x in xs:
		s += float(x) if x != null else 0.0 # `0 + null` vaut 0 en JavaScript
	return s / xs.size() if not xs.is_empty() else 0.0

## Le verdict, clé pour clé celui de solvability.mjs.
static func _verdict(seeds: int, skilled: Array, no_dash: Array, masher: Array) -> Dictionary:
	var n := float(seeds)
	var dmg_skilled := _mean(skilled.map(func(r): return r.damagePerRoom))
	var dmg_no_dash := _mean(no_dash.map(func(r): return r.damagePerRoom))
	var dash_value := dmg_no_dash / dmg_skilled if dmg_skilled > 0.0 else INF
	var failed: Array = []
	for r in skilled:
		if not r.sectionCleared:
			failed.append({"seed": r.seed, "floor": r.floorReached, "outcome": r.outcome, "causes": r.deathCauses})
	return {
		"seeds": n,
		"clearRate": skilled.filter(func(r): return r.sectionCleared).size() / n,
		"dashValue": Format.fixed(dash_value, 2),
		"damagePerRoom": {"skilled": Format.fixed(dmg_skilled, 1), "noDash": Format.fixed(dmg_no_dash, 1)},
		"masherDeathRate": masher.filter(func(r): return r.deaths > 0.0).size() / n,
		"failedSeeds": failed,
		"_dashValue": dash_value, # valeur non arrondie : sert au seuil et à l'affichage, pas à la ligne FORGE_ORACLE
	}

## Écrit le verdict comme solvability.mjs. Rend le code de sortie.
static func _report(seeds: int, partials: Array) -> int:
	var runs := {}
	for policy in POLICIES:
		runs[policy] = _runs_of(partials, policy, seeds)
		if runs[policy] == null:
			print("mesure incomplète : il manque des parties de %s (graines %d à %d)" % [policy, FIRST_SEED, FIRST_SEED + seeds - 1])
			return EXIT_INCOMPLETE
	var verdict := _verdict(seeds, runs.skilled, runs.noDash, runs.masher)
	var dash_value: float = verdict._dashValue
	verdict.erase("_dashValue")
	print("FORGE_ORACLE solvability %s" % Format.to_json(verdict))
	print("  section 1 battue par le bot skilled : %s %% (seuil %s %%)" % [Format.to_fixed(verdict.clearRate * 100.0, 0), Format.js_num(MIN_CLEAR_RATE * 100.0)])
	print("  valeur du dash (dégâts/salle sans dash ÷ avec) : %s (seuil %s)" % [Format.to_fixed(dash_value, 2), Format.js_num(MIN_DASH_VALUE)])
	print("  mesure : un joueur qui martèle sans lire meurt dans %s %% des parties" % Format.to_fixed(verdict.masherDeathRate * 100.0, 0))
	var ticks := 0.0
	var ms := 0.0
	for part in partials:
		ticks += part.ticks
		ms += part.ms
	print("  débit : %.0f pas de simulation par seconde et par processus (%d processus, %.0f s de calcul cumulé)" % [ticks / maxf(ms / 1000.0, 0.001), partials.size(), ms / 1000.0])
	var ok: bool = verdict.clearRate >= MIN_CLEAR_RATE and dash_value >= MIN_DASH_VALUE
	print("SOLVABILITY: %s" % ("PASS" if ok else "FAIL"))
	return 0 if ok else 1
