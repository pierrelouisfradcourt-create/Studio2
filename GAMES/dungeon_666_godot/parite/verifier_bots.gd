extends SceneTree
## Les bots Godot (outils/bots/) jouent-ils EXACTEMENT comme les bots web (tools/bots.mjs) ?
##   <godot> --headless --path . --script res://parite/verifier_bots.gd [-- nom_de_trace …]
##
## Chaque partie notée de parite/traces a été jouée côté web par un bot (`policy`) ; ses pas
## [0, mx, my, ax, ay, drapeaux, sx, sy] sont les entrées du bot, quantifiées au 1/1024. Ici la
## partie est rejouée et, À CHAQUE image, le bot Godot calcule son entrée sur l'état Godot (le
## même que l'état web à cet instant : bash outils/verifier.sh), la quantifie de la même façon
## et la compare à celle de la trace. Égalité EXACTE attendue. La partie avance toujours avec
## l'entrée de la TRACE : la première image différente localise l'écart de portage.
## Les menus et les reprises sont ceux de la trace (menuCandidates) : resolve_choice n'est pas
## vérifié ici, il l'est par les oracles (mêmes nombres que le web sur les mêmes graines).
## Sortie 0 = aucune image différente, 1 = au moins un écart, 2 = aucune trace à vérifier.

const Rejeu = preload("res://parite/rejeu.gd")
const Bots = preload("res://outils/bots/bots.gd")

const Q := 1024.0
const ANALOG := ["moveX", "moveY", "aimX", "aimY", "skillAimX", "skillAimY"]
const ANALOG_STEP := [1, 2, 3, 4, 6, 7] # rang de chaque analogique dans un pas de trace
const FLAG_STEP := 5

## Math.round de JavaScript, exact (la demie monte).
static func _js_round(x: float) -> float:
	var f := floorf(x)
	return f + 1.0 if x - f >= 0.5 else f

## L'entrée du bot sous la forme d'un pas de trace (tools/traces.mjs : quantize puis inputStep).
static func _quantized(input: Dictionary) -> Array:
	var step: Array = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	for i in ANALOG.size():
		var v = input.get(ANALOG[i])
		step[ANALOG_STEP[i]] = _js_round((float(v) if D6Js.truthy(v) else 0.0) * Q)
	var flags := 0
	for i in Rejeu.FLAGS.size():
		if D6Js.truthy(input.get(Rejeu.FLAGS[i])):
			flags |= 1 << i
	step[FLAG_STEP] = float(flags)
	return step

static func _same(mine: Array, step: Array) -> bool:
	for i in range(1, 8):
		if mine[i] != step[i]:
			return false
	return true

## Rejoue une trace en interrogeant le bot à chaque image. Rend {frames, ok, message}.
static func check(trace: Dictionary) -> Dictionary:
	var res := {"frames": 0, "ok": true, "message": ""}
	var game: Dictionary = D6Game.create_game(Rejeu._options(trace.options))
	if trace.options.get("build") is Dictionary:
		Rejeu._apply_build(game, trace.options.build)
	var mem := {}
	for step in trace.steps:
		match int(step[0]):
			0:
				var mine := _quantized(Bots.play(trace.policy, game, mem))
				res.frames += 1
				if not _same(mine, step):
					res.ok = false
					res.message = "image %d (tick %s, étage %s) : bot Godot %s, bot web %s" % [res.frames, D6Js.num_str(game.tick), D6Js.num_str(game.run.floor), str(mine.slice(1)), str(step.slice(1))]
					return res
				D6Game.step_game(game, Rejeu._input(step))
				game.events.clear()
			1:
				D6Game.apply_command(game, step[1])
	return res

func _initialize() -> void:
	var wanted: Array = Array(OS.get_cmdline_user_args())
	var names: Array = wanted if not wanted.is_empty() else Rejeu.names()
	var t0 := Time.get_ticks_msec()
	var traces := 0
	var frames := 0
	var bad := 0
	for n in names:
		var trace = Rejeu.load_trace(n)
		if trace == null or not Bots.has_policy(str(trace.get("policy"))):
			continue # « hasard » : aucune politique de bot à comparer
		traces += 1
		var r: Dictionary = check(trace)
		frames += r.frames
		if r.ok:
			print("  ok   — %s (%s) : %d images" % [n, trace.policy, r.frames])
		else:
			bad += 1
			print("  ROUGE — %s (%s) : %s" % [n, trace.policy, r.message])
	var seconds := (Time.get_ticks_msec() - t0) / 1000.0
	if traces == 0:
		print("aucune trace jouée par un bot (champ `policy`) : relancer node tools/export_godot.mjs traces")
		quit(2)
		return
	print("%d parties, %d images comparées, %d parties en écart — %.1f s (%.0f images/s)" % [traces, frames, bad, seconds, frames / maxf(seconds, 0.001)])
	print("BOTS: %s" % ("PASS" if bad == 0 else "FAIL"))
	quit(0 if bad == 0 else 1)
