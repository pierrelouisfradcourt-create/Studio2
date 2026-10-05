extends RefCounted
## Une partie de RÉFÉRENCE : la jouer en la notant (record), la rejouer en la comparant (replay).
## Mode d'emploi et consigne : references/enregistrer.gd et references/verifier.gd.
##
## Une partie notée, en mémoire : {name, spec, steps, frames, ticks}. Un pas :
##   [0, mx, my, ax, ay, drapeaux, s1x, s1y, s2x, s2y, s3x, s3y]
##                                          une image d'entrées (analogiques en 1/1024 ; s1..s3 :
##                                          la visée de chacun des trois emplacements)
##   [1, commande, acceptée]                une commande de menu TENTÉE (toutes notées, même
##                                          refusées : le rejeu doit refuser pareil)
##   [2, empreinte]                         un point de contrôle (digest)
## Les entrées sont quantifiées au 1/1024 AVANT d'être jouées : le fichier porte des entiers, le
## rejeu retrouve exactement les mêmes nombres (q / 1024).
##
## Une spec (references/catalogue.gd) : {name, seed, floor, kit: [classe, arme], policy, seconds,
## slots: [trois actions ou null] (avec `kit` ; absent : compétence et gadget de départ),
## tree: {ranks: {nœud: RANG voulu}, choices: {nœud: amélioration}} (avec `kit` : l'arbre de compétences
## de la classe, au niveau maximum), tuning, sandbox, practice, godMode, deaths: "town", build}. `build` est un départ garni posé
## APRÈS create_game : {boons: [identifiants], rarity, power: pouvoir légendaire, souls: Âmes}.

const Bots = preload("res://outils/bots/bots.gd")
const Classes = preload("res://outils/classes.gd")
const Arbre = preload("res://sim/tree.gd")

const Q := 1024.0 # pas de quantification des entrées analogiques
const CHECK_EVERY := 30 # images entre deux points de contrôle
const MAX_STEPS_FACTOR := 4 # garde-fou : pas plus de 4 pas notés par image demandée
const ANALOG := ["moveX", "moveY", "aimX", "aimY", "skill1AimX", "skill1AimY", "skill2AimX", "skill2AimY", "skill3AimX", "skill3AimY"]
const ANALOG_STEP := [1, 2, 3, 4, 6, 7, 8, 9, 10, 11] # rang de chaque analogique dans un pas d'entrées
const FLAGS := ["attack", "attackPressed", "dashPressed", "skill1Pressed", "skill2Pressed", "skill3Pressed"]
const FLAG_STEP := 5
const STEP_SIZE := 12 # le type du pas, puis ses 11 champs
const RANDOM_POLICY := "hasard"
const DEFAULT_POLICY := "skilled"
const HASH_BASIS := 2166136261
const HASH_PRIME := 16777619

# ---------------------------------------------------------------- empreinte d'état

## Empreinte d'état : assez large pour qu'une règle changée se voie dans les 30 images.
static func digest(game: Dictionary, events: Dictionary) -> Dictionary:
	var p: Dictionary = game.player
	var room: Dictionary = game.room
	var doors: Array = []
	for d in room.doors:
		doors.append("%s%s" % [d.reward, "+" if D6Js.truthy(d.get("open")) else "-"])
	var choice = game.get("choice")
	var d := {
		"tick": game.tick, "time": game.time, "mode": game.mode, "floor": game.run.floor,
		"gold": game.run.gold, "souls": game.meta.souls,
		"rng": [game.rng.gen.s, game.rng.combat.s, game.rng.ai.s],
		"nextId": game.nextId, "hitstop": game.hitstop, "bank": game.hitstopBank,
		"p": [p.x, p.y, p.vx, p.vy, p.hp, p.maxHp, p.state, p.facing, p.dashCharges, p.superCharge, p.superHold, p.iframes, p.freeze],
		"slots": p.slots.map(func(s): return [s.cd, s.charges]),
		"e": game.enemies.map(func(e): return [e.id, e.kind, e.state, e.x, e.y, e.hp, e.stun, 1 if D6Js.truthy(e.get("dead")) else 0, D6Js.nz(e.get("eliteMod"), "")]),
		"pr": game.projectiles.map(func(o): return [o.x, o.y]),
		"hz": game.hazards.size(), "pk": game.pickups.size(), "sp": game.spawns.size(),
		"boons": game.run.boons.map(func(b): return "%s:%s:%s" % [b.id, D6Js.num_str(b.level), b.rarity]),
		"room": [room.kind, D6Js.nz(room.get("layout"), ""), room.waveIndex, 1 if D6Js.truthy(room.get("cleared")) else 0, ",".join(doors)],
		"choice": choice.kind if choice is Dictionary else "",
		"ev": events,
		"tel": [game.telemetry.kills, game.telemetry.damageTaken, game.telemetry.damageDealt, game.telemetry.dodges],
	}
	# Limiers de la Meute des Limbes : dans l'empreinte seulement quand il y en a (une partie sans
	# meute garde l'empreinte qu'elle avait). La Forme du Damné se lit déjà : jauge, emplacements.
	if not game.allies.is_empty():
		d["al"] = game.allies.map(func(a): return [a.id, a.x, a.y, a.hp, a.life, a.state, a.targetId, 1 if a.dead else 0])
	return d

static func _drain(game: Dictionary, events: Dictionary) -> void:
	for ev in game.events:
		events[ev.type] = events.get(ev.type, 0) + 1
	game.events.clear()

# ---------------------------------------------------------------- départ d'une partie

## La partie d'une spec, prête à jouer : create_game, puis le départ garni.
static func start(spec: Dictionary) -> Dictionary:
	var options := {
		"seed": float(spec.seed), "startFloor": float(spec.get("floor", 1)),
		"sandbox": spec.get("sandbox", false), "practice": spec.get("practice", false), "godMode": spec.get("godMode", false),
	}
	if spec.has("kit"):
		options.meta = Classes.kit_profile(D6Data.create_tuning(), spec.kit[0], spec.kit[1], spec.get("slots"))
		if spec.has("tree"):
			_apply_tree(options.meta, spec.kit[0], spec.tree)
	if spec.has("tuning"):
		options.tuning = D6Js.decode(spec.tuning)
	var game: Dictionary = D6Game.create_game(options)
	if spec.has("build"):
		_apply_build(game, spec.build)
	return game

## Arbre de compétences d'une spec : la classe au niveau maximum, chaque nœud au RANG demandé (le
## rang offert d'une compétence possédée est déduit), les améliorations exclusives prises.
static func _apply_tree(meta: Dictionary, class_id: String, tree: Dictionary) -> void:
	var t: Dictionary = D6Data.default_tuning()
	var st: Dictionary = Arbre.state(meta, class_id)
	st.level = t.tree.maxLevel
	for id in tree.get("ranks", {}):
		var n: Dictionary = Arbre.node(t, class_id, id)
		st.ranks[id] = float(tree.ranks[id]) - (1.0 if Arbre.is_free(meta, t, n) else 0.0)
	for id in tree.get("choices", {}):
		st.choices[id] = tree.choices[id]

## Les bénédictions passent par add_boon (emplacements exclusifs compris), le pouvoir est porté
## en talisman, puis les stats sont recalculées.
static func _apply_build(game: Dictionary, build: Dictionary) -> void:
	for id in build.get("boons", []):
		D6Boons.add_boon(game.run, {"id": id, "rarity": build.get("rarity", "commun")})
	if build.has("power"):
		game.run.items.talisman = {
			"id": 0.0, "slot": "talisman", "rarity": "legendaire", "name": "Relique de parité", "level": 1.0,
			"affixes": [], "power": build.power, "base": {}, "score": 0.0,
		}
	if build.has("souls"):
		game.meta.souls = float(build.souls)
	D6Stats.recompute_stats(game)

# ---------------------------------------------------------------- entrées

## L'arrondi au plus proche dont la demie monte, exact (floor(x + 0.5) se trompe juste sous la demie).
static func _round_half_up(x: float) -> float:
	var f := floorf(x)
	return f + 1.0 if x - f >= 0.5 else f

## L'entrée d'une politique sous la forme d'un pas : analogiques en 1/1024, boutons en drapeaux.
static func quantized(input: Dictionary) -> Array:
	var step: Array = []
	step.resize(STEP_SIZE)
	step.fill(0.0)
	for i in ANALOG.size():
		var v = input.get(ANALOG[i])
		step[ANALOG_STEP[i]] = _round_half_up((float(v) if D6Js.truthy(v) else 0.0) * Q)
	var flags := 0
	for i in FLAGS.size():
		if D6Js.truthy(input.get(FLAGS[i])):
			flags |= 1 << i
	step[FLAG_STEP] = float(flags)
	return step

## L'entrée jouée pour un pas d'entrées.
static func input_of(step: Array) -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	for i in ANALOG.size():
		input[ANALOG[i]] = step[ANALOG_STEP[i]] / Q
	var flags := int(step[FLAG_STEP])
	for i in FLAGS.size():
		input[FLAGS[i]] = (flags & (1 << i)) != 0
	return input

## Politique « au hasard » : toutes les commandes pressées aléatoirement, par courtes séquences
## tenues. Aucun bot ne joue ainsi ; c'est ce qui exerce les bords du tampon d'entrées (dash
## enchaîné, attaque pendant un dash, compétence pendant une récupération, visées manuelles).
## L'ultime n'a pas de bouton : il part quand plusieurs séquences « attaque tenue » se suivent,
## jauge pleine (0,4 s) ; les trois emplacements sont pressés chacun à son rythme.
## RNG propre à la politique (jamais celui de la partie) ; état dans `mem`.
static func _random_input(mem: Dictionary) -> Dictionary:
	var r: Dictionary = mem.rng
	if mem.hold <= 0:
		mem.hold = int(floorf(D6Rng.rand(r) * 14.0))
		var cur: Dictionary = D6Game.empty_input()
		if D6Rng.rand(r) < 0.8:
			cur.moveX = D6Rng.rand(r) * 2.0 - 1.0
			cur.moveY = D6Rng.rand(r) * 2.0 - 1.0
		if D6Rng.rand(r) < 0.3:
			cur.aimX = D6Rng.rand(r) * 2.0 - 1.0
			cur.aimY = D6Rng.rand(r) * 2.0 - 1.0
		cur.attack = D6Rng.rand(r) < 0.55
		for k in ["skill1Aim", "skill2Aim", "skill3Aim"]:
			cur[k + "X"] = D6Rng.rand(r) * 2.0 - 1.0 if D6Rng.rand(r) < 0.5 else 0.0
			cur[k + "Y"] = D6Rng.rand(r) * 2.0 - 1.0 if D6Rng.rand(r) < 0.5 else 0.0
		mem.cur = cur
	else:
		mem.hold -= 1
	var out: Dictionary = mem.cur.duplicate()
	out.attackPressed = D6Rng.rand(r) < 0.12
	out.dashPressed = D6Rng.rand(r) < 0.1
	out.skill1Pressed = D6Rng.rand(r) < 0.04
	out.skill2Pressed = D6Rng.rand(r) < 0.01
	out.skill3Pressed = D6Rng.rand(r) < 0.03
	return out

static func _policy_input(policy: String, game: Dictionary, mem: Dictionary) -> Dictionary:
	if policy == RANDOM_POLICY:
		return _random_input(mem)
	return Bots.play(policy, game, mem)

# ---------------------------------------------------------------- menus et reprises

static func _mix_hash(values: Array) -> int:
	var h := HASH_BASIS
	for v in values:
		h = D6Js.imul(h ^ D6Js.u32(v), HASH_PRIME)
	return h

## Commandes de menu à tenter, dans l'ordre ; la première acceptée résout le menu.
static func _menu_candidates(game: Dictionary) -> Array:
	var h := _mix_hash([game.seed, game.run.floor, game.run.boons.size(), game.tick])
	return [
		{"type": "choose", "index": float(h % 3)}, {"type": "equip"}, {"type": "choose", "index": 0.0}, {"type": "choose", "index": 1.0},
		{"type": "choose", "index": 2.0}, {"type": "stash"}, {"type": "salvage"}, {"type": "close"},
	]

static func _try_commands(game: Dictionary, steps: Array, cmds: Array) -> bool:
	for cmd in cmds:
		var ok: bool = D6Js.truthy(D6Game.apply_command(game, cmd))
		steps.append([1.0, cmd, 1.0 if ok else 0.0])
		if ok:
			return true
	return false

## Sort d'un menu ou d'une mort ; rend false si la partie notée s'arrête là.
static func _leave_pause(game: Dictionary, spec: Dictionary, steps: Array) -> bool:
	if game.mode == "choice":
		return _try_commands(game, steps, _menu_candidates(game))
	if game.mode == "dead":
		var cmd: Dictionary = {"type": "returnToTown"} if spec.get("deaths") == "town" else {"type": "respawn", "floor": D6Run.last_checkpoint(game)}
		return _try_commands(game, steps, [cmd])
	return false # Ville, victoire : fin de la partie notée

# ---------------------------------------------------------------- jouer en notant

## Joue et note la partie d'une spec. `every` : images entre deux points de contrôle.
static func record(spec: Dictionary, every: int = CHECK_EVERY) -> Dictionary:
	var game := start(spec)
	var policy: String = spec.get("policy", DEFAULT_POLICY)
	var mem := {"rng": D6Rng.create_rng(spec.seed), "hold": 0, "cur": D6Game.empty_input()} if policy == RANDOM_POLICY else {}
	var steps: Array = []
	var events := {}
	_drain(game, events)
	steps.append([2.0, digest(game, events)])
	events = {}
	var frames := int(_round_half_up(float(spec.seconds) / D6Data.DT))
	var played := 0
	while played < frames and steps.size() < frames * MAX_STEPS_FACTOR:
		if game.mode != "play":
			if not _leave_pause(game, spec, steps):
				break
		else:
			var step := quantized(_policy_input(policy, game, mem))
			steps.append(step)
			D6Game.step_game(game, input_of(step))
			played += 1
			_drain(game, events)
			if played % every != 0:
				continue
		_drain(game, events)
		steps.append([2.0, digest(game, events)])
		events = {}
	_drain(game, events)
	steps.append([2.0, digest(game, events)])
	return {"name": spec.name, "spec": spec, "steps": steps, "frames": played, "ticks": game.tick}

# ---------------------------------------------------------------- rejouer

## Rejoue les pas d'une partie notée depuis sa spec. À chaque point de contrôle, `on_check` reçoit
## (rang du point, images jouées, empreinte) et rend "" si elle est la bonne, sinon l'écart.
## `on_frame`, facultatif, reçoit (images jouées, partie, événements) après chaque image.
## Rend {ok, checks, frames, message} ; `message` décrit le premier écart.
static func replay(spec: Dictionary, steps: Array, on_check: Callable, on_frame: Callable = Callable()) -> Dictionary:
	var res := {"ok": true, "checks": 0, "frames": 0, "message": ""}
	var game := start(spec)
	var events := {}
	for step in steps:
		match int(step[0]):
			0:
				D6Game.step_game(game, input_of(step))
				res.frames += 1
				_drain(game, events)
				if on_frame.is_valid():
					on_frame.call(res.frames, game, events)
			1:
				var ok: bool = D6Js.truthy(D6Game.apply_command(game, step[1]))
				if ok != (step[2] != 0.0):
					res.ok = false
					res.message = "image %d : commande %s %s, la référence l'a %s" % [res.frames, JSON.stringify(step[1]), "acceptée" if ok else "refusée", "acceptée" if step[2] != 0.0 else "refusée"]
					return res
			2:
				_drain(game, events)
				var diff: String = on_check.call(res.checks, res.frames, digest(game, events))
				res.checks += 1
				events = {}
				if diff != "":
					res.ok = false
					res.message = "image %d (point de contrôle %d) : %s" % [res.frames, res.checks, diff]
					return res
	return res
