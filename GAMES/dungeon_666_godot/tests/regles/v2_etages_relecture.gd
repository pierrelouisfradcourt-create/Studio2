extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_etages_relecture.test.mjs.
## Tests issus de la relecture adversariale du lot ÉTAGES (V2) : un test par défaut corrigé.
##
##   - la jauge de Super suit l'arme portée (même nombre de coups à l'étage 1 et en profondeur) ;
##   - victoire au 666 : aucun checkpoint sur le Gardien final, et l'écran a une issue (la Ville) ;
##   - salle d'élite : le champion sort du bestiaire de l'étage (entrée progressive en section 1) ;
##   - fontaine : une bénédiction sans niveau (Envol) ne se médite pas, et ne vaut jamais 1,5 charge ;
##   - chambre forte : la bourse verse exactement le montant annoncé ;
##   - un numéro d'étage illisible vaut l'étage 1 (ni plantage, ni NaN).

const STEP_CAP := 600
const ELITE_SEEDS := 300 # graines du test du champion (valeur web : 300)
const PURSE_SEEDS := 60 # graines du test de la bourse (valeur web : 60)
const BIG_HP := 1e9

static func tests(h) -> void:
	h.test("Super : la jauge demande le même nombre de coups quelle que soit l'arme portée (étage 1 comme étage 649)", func(): _super_jauge(h))
	h.test("victoire au 666 : aucun checkpoint n'est posé sur le Gardien final", func(): _victoire_checkpoint(h))
	h.test("victoire au 666 : l'écran a une issue — retour en Ville accepté, profil conservé", func(): _victoire_issue(h))
	h.test("salle d'élite en section 1 : le champion appartient au bestiaire de l'étage (aucun archétype en avance)", func(): _champion(h))
	h.test("fontaine : Envol (bénédiction sans niveau) ne se médite pas ; une autre bénédiction, oui", func(): _fontaine_envol(h))
	h.test("Envol : +1 charge de dash, entière, quel que soit son niveau", func(): _envol_charge(h))
	h.test("chambre forte : la bourse verse exactement le montant annoncé", func(): _bourse(h))
	h.test("étage illisible (NaN, texte, infini) : vaut l'étage 1 — ni plantage, ni NaN", func(): _etage_illisible(h))

# ---------------------------------------------------------------- outillage

static func _step_until(g: Dictionary, done: Callable) -> bool:
	var i := 0
	while i < STEP_CAP and not done.call(g):
		D6Game.step_game(g, D6Game.empty_input())
		i += 1
	return done.call(g)

static func _touch_interact(g: Dictionary) -> bool:
	g.player.x = g.room.interact.x
	g.player.y = g.room.interact.y
	return _step_until(g, func(x): return x.mode == "choice")

static func _has_num(arr: Array, v: float) -> bool:
	for x in arr:
		if float(x) == v:
			return true
	return false

static func _option(options: Array, id: String):
	for o in options:
		if o.id == id:
			return o
	return null

static func _option_index(options: Array, id: String) -> float:
	for i in options.size():
		if options[i].id == id:
			return float(i)
	return -1.0

static func _boon(run: Dictionary, id: String):
	for b in run.boons:
		if b.id == id:
			return b
	return null

# ---------------------------------------------------------------- jauge de Super

## Jauge gagnée par UN coup de base (10 de dégâts) avec une arme `mult` fois plus forte que l'arme de base.
static func _super_gain_per_hit(T: Dictionary, mult: float) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": 7.0})
	g.spawns.clear()
	g.enemies.clear()
	g.room.waves = []
	g.tuning.combat.critChance = 0.0
	g.run.items.arme.base.damage = T.weaponBase * mult
	D6Stats.recompute_stats(g)
	var e: Dictionary = D6Enemies.create_enemy(g, "brute", g.player.x + 60.0, g.player.y, {"spawnT": 0.0})
	e.hp = BIG_HP
	e.maxHp = BIG_HP
	g.player.superCharge = 0.0
	var dealt: float = D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 10.0, "canCrit": false})
	return {"gain": g.player.superCharge, "dealt": dealt}

static func _super_jauge(h) -> void:
	var T: Dictionary = D6Data.create_tuning()
	var base := _super_gain_per_hit(T, 1.0)
	h.ok(base.gain > 0.0, "un coup remplit la jauge")
	h.ok(absf(base.gain - 10.0 / T["super"].chargeDamage) < 1e-9, "arme de base : dégâts ÷ chargeDamage, comme avant")
	var deep_level: float = D6Floors.floor_scaling(T, 649.0).level # niveau d'objet en fin de descente
	var deep := _super_gain_per_hit(T, deep_level)
	h.ok(deep.dealt > base.dealt * 10.0, "l'arme de niveau %.1f frappe bien plus fort (%s contre %s)" % [deep_level, str(deep.dealt), str(base.dealt)])
	h.ok(absf(deep.gain - base.gain) < base.gain * 0.02, "jauge par coup : %.5f contre %.5f" % [deep.gain, base.gain])

# ---------------------------------------------------------------- victoire au 666

static func _win_the_game(h, T: Dictionary, seed_n: float = 3.0) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed_n, "startFloor": T.floors.total})
	var boss = null
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")):
			boss = e
			break
	if not h.ok(boss != null, "le Gardien final est là"):
		return g
	g.spawns.clear()
	D6Combat.kill_enemy(g, boss, {"kind": "melee"})
	_step_until(g, func(x): return x.mode != "play")
	return g

static func _victoire_checkpoint(h) -> void:
	var T: Dictionary = D6Data.create_tuning()
	var g := _win_the_game(h, T)
	h.egal(g.mode, "victory")
	h.ok(not _has_num(g.meta.checkpoints, T.floors.total), "checkpoints : %s" % str(g.meta.checkpoints))
	for cp in g.meta.checkpoints:
		h.egal(D6Floors.floor_info(T, cp).indexInSection, 1.0, "le checkpoint %s est un début de section" % D6Js.num_str(cp))
	h.ok(g.meta.souls > 0.0, "les Âmes du Gardien final sont gagnées")

static func _victoire_issue(h) -> void:
	var T: Dictionary = D6Data.create_tuning()
	var g := _win_the_game(h, T)
	var souls: float = g.meta.souls
	h.egal(D6Game.apply_command(g, {"type": "returnToTown"}), true, "la commande est acceptée en mode victoire")
	h.egal(g.mode, "town")
	h.egal(g.meta.souls, souls, "le retour ne coûte rien")
	# Hors victoire, mort ou portail, quitter reste refusé (ce serait un abandon).
	var g2: Dictionary = D6Game.create_game({"seed": 3.0})
	h.egal(D6Game.apply_command(g2, {"type": "returnToTown"}), false)

# ---------------------------------------------------------------- champion des salles d'élite

static func _champion_of(waves: Array):
	for w in waves:
		for s in w:
			if D6Js.truthy(s.get("elite")):
				return s
	return null

static func _champion(h) -> void:
	var rooms := 0
	for seed_i in range(1, ELITE_SEEDS + 1):
		for floor in [2.0, 3.0, 4.0]:
			var g: Dictionary = D6Game.create_game({"seed": float(seed_i), "startFloor": floor - 1.0})
			D6Run.enter_floor(g, floor, {"reward": "elite"})
			if g.room.kind != "elite":
				continue
			rooms += 1
			var roster: Array = g.room.plan.roster.map(func(r): return r.kind)
			var champion = _champion_of(g.room.waves)
			var where := "graine %d étage %s" % [seed_i, D6Js.num_str(floor)]
			if not h.ok(champion != null, "%s : la salle d'élite a son champion" % where):
				continue
			h.ok(roster.has(champion.kind), "%s : champion « %s » hors du bestiaire [%s]" % [where, champion.kind, ", ".join(roster)])
	h.ok(rooms > 100, "%d salles d'élite examinées" % rooms)

# ---------------------------------------------------------------- fontaine : méditation

static func _fountain(h, boons: Array) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": 5.0, "startFloor": 3.0})
	g.run.boons = boons.map(func(id): return {"id": id, "rarity": "commun", "level": 1.0})
	D6Stats.recompute_stats(g)
	D6Run.enter_floor(g, 4.0, {"reward": "rest"})
	h.egal(g.room.kind, "rest")
	return g

static func _fontaine_envol(h) -> void:
	var alone := _fountain(h, ["envol"])
	var opt = _option(D6CalmRooms.describe_calm(alone, alone.room.interact).options, "mediter")
	h.egal(opt.disabled, true, "Envol seul : rien à approfondir")

	var g := _fountain(h, ["envol", "furie"])
	var med := _option_index(D6CalmRooms.describe_calm(g, g.room.interact).options, "mediter")
	h.ok(_touch_interact(g))
	h.egal(D6Game.apply_command(g, {"type": "choose", "index": med}), true)
	h.egal(_boon(g.run, "furie").level, 2.0, "la méditation va à Furie")
	h.egal(_boon(g.run, "envol").level, 1.0, "Envol garde son niveau")

static func _envol_charge(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 5.0})
	var base: float = D6Player.max_dash_charges(g)
	for level in [1.0, 2.0, 3.0]:
		g.run.boons = [{"id": "envol", "rarity": "commun", "level": level}]
		D6Stats.recompute_stats(g)
		h.egal(D6Player.max_dash_charges(g), base + 1.0, "niveau %s" % D6Js.num_str(level))

# ---------------------------------------------------------------- chambre forte : bourse

static func _gold_on_floor(g: Dictionary) -> float:
	var s := 0.0
	for k in g.pickups:
		if k.kind == "gold":
			s += k.value
	return s

static func _bourse(h) -> void:
	var T: Dictionary = D6Data.create_tuning()
	var n: float = T.economy.treasure.goldPickups
	for seed_i in range(1, PURSE_SEEDS + 1):
		var g: Dictionary = D6Game.create_game({"seed": float(seed_i), "startFloor": 3.0})
		D6Run.enter_floor(g, 4.0, {"reward": "treasure"})
		var it: Dictionary = g.room.interact
		var gold_txt := D6Js.num_str(it.gold)
		h.egal(fmod(it.gold, n), 0.0, "graine %d : %s or se partage en %s pièces égales" % [seed_i, gold_txt, D6Js.num_str(n)])
		var label = _option(D6CalmRooms.describe_calm(g, it).options, "bourse").label
		h.egal(label, "+%s or" % gold_txt)
		var gold0: float = g.run.gold
		h.ok(_touch_interact(g))
		h.egal(D6Game.apply_command(g, {"type": "choose", "index": 1.0}), true)
		h.egal(_gold_on_floor(g), it.gold, "graine %d : pièces au sol" % seed_i)
		h.ok(_step_until(g, func(x): return x.pickups.size() == 0), "les pièces sont ramassées")
		h.egal(g.run.gold - gold0, it.gold, "graine %d : annoncé %s" % [seed_i, gold_txt])

# ---------------------------------------------------------------- numéro d'étage illisible

static func _etage_illisible(h) -> void:
	var T: Dictionary = D6Data.create_tuning()
	# `undefined` de JavaScript = null.
	for bad in [NAN, "abc", null, INF, -INF]:
		var info: Dictionary = D6Floors.floor_info(T, bad)
		h.ok(is_finite(info.floor) and info.floor >= 1.0 and info.floor <= T.floors.total, "floorInfo(%s) -> %s" % [str(bad), str(info.floor)])
		var s: Dictionary = D6Floors.floor_scaling(T, bad)
		h.ok(is_finite(s.hp) and is_finite(s.damage), "floorScaling(%s)" % str(bad))
	h.egal(D6Floors.floor_info(T, NAN).floor, 1.0)
	h.egal(D6Floors.floor_info(T, "abc").floor, 1.0)
	var g: Dictionary = D6Game.create_game({"seed": 9.0, "startFloor": NAN})
	h.egal(g.run.floor, 1.0)
	for i in 120:
		D6Game.step_game(g, D6Game.empty_input())
	h.ok(is_finite(g.player.x) and is_finite(g.player.hp))
