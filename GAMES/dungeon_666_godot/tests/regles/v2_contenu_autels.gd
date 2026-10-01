extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_contenu.test.mjs (4/4 : les événements d'autel).
## Outils : v2_contenu.gd.

const C = preload("res://tests/regles/v2_contenu.gd")
const EPS := 1e-9
const ALTAR_DRAW_SEEDS := 80 # valeur web : 80

static func _event(id: String) -> Dictionary:
	return C.by_id(C.events_t(), id)

static func _choose(g: Dictionary, index: float) -> bool:
	return D6Game.apply_command(g, {"type": "choose", "index": index})

static func _is_num(v) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT

static func _die(g: Dictionary) -> void:
	g.player.hp = 0.0
	g.player.state = "dead"
	g.mode = "dead"
	D6Run.respawn(g, 1.0)

static func _labels_case(h, ev: Dictionary) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 31.0, "startFloor": 5.0})
	C.give(h, g, "furie")
	C.give(h, g, "voracite")
	var ch: Dictionary = C.altar(h, g, ev.id)
	h.egal(ch.get("title"), ev.title)
	h.egal(ch.options.size(), ev.options.size())
	for i in mini(ch.options.size(), ev.options.size()):
		var o: Dictionary = ch.options[i]
		var src: Dictionary = ev.options[i]
		h.ok(C.no_braces(o.label), "%s option %d : « %s »" % [ev.id, i, o.label])
		for k in src:
			var v = src[k]
			if _is_num(v) and ("{%s}" % k) in src.label:
				h.ok(D6Js.num_str(v) in o.label, "%s : %s = %s absent de « %s »" % [ev.id, k, v, o.label])
	h.ok(ch.options.any(func(o): return not D6Js.truthy(o.get("disabled"))), "%s : toujours une issue" % ev.id)

static func _t_libelles(h) -> void:
	for ev in C.events_t():
		_labels_case(h, ev)

static func _t_tirage(h) -> void:
	var seen := {}
	for seed in range(1, ALTAR_DRAW_SEEDS + 1):
		var g: Dictionary = D6Game.create_game({"seed": float(seed), "startFloor": 5.0})
		D6Run.enter_floor(g, 6.0, {"reward": "event"})
		seen[g.room.interact.event] = true
	for id in C.NEW_EVENTS:
		h.ok(seen.has(id), "%s : jamais tiré en %d parties" % [id, ALTAR_DRAW_SEEDS])

static func _t_registre(h) -> void:
	var buy: Dictionary = _event("pacte_ames").options[0]
	var sell: Dictionary = _event("pacte_ames").options[1]
	# Pas assez d'Âmes : l'option est grisée et refusée.
	var poor: Dictionary = D6Game.create_game({"seed": 33.0, "startFloor": 5.0})
	poor.meta.souls = buy.souls - 1.0
	h.egal(C.altar(h, poor, "pacte_ames").options[0].disabled, true)
	h.egal(_choose(poor, 0.0), false)
	h.egal(poor.meta.souls, buy.souls - 1.0)
	# Céder des Âmes : une bénédiction ÉPIQUE, les Âmes du profil baissent du prix affiché.
	var g: Dictionary = D6Game.create_game({"seed": 33.0, "startFloor": 5.0})
	g.meta.souls = 100.0
	var ch: Dictionary = C.altar(h, g, "pacte_ames")
	h.ok(("%s Âmes" % D6Js.num_str(buy.souls)) in ch.options[0].label)
	h.egal(_choose(g, 0.0), true)
	h.egal(g.meta.souls, 100.0 - buy.souls)
	h.egal(g.run.boons.map(func(b): return b.rarity), ["epique"])
	h.egal(g.mode, "play")
	# Vendre son sang : des PV de ce run contre des Âmes qui restent après la mort.
	var g2: Dictionary = D6Game.create_game({"seed": 33.0, "startFloor": 5.0})
	var hp0: float = g2.player.hp
	var souls0: float = g2.meta.souls
	C.altar(h, g2, "pacte_ames")
	h.egal(_choose(g2, 1.0), true)
	h.egal(g2.player.hp, hp0 - sell.hp)
	h.egal(g2.meta.souls, souls0 + sell.gain)
	_die(g2)
	h.egal(g2.meta.souls, souls0 + sell.gain, "les Âmes survivent à la mort")

static func _t_forge(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 35.0, "startFloor": 5.0})
	C.give(h, g, "furie")
	h.egal(C.altar(h, g, "forge").options[0].disabled, true, "une seule bénédiction : rien à fondre")
	h.egal(_choose(g, 0.0), false)
	var g2: Dictionary = D6Game.create_game({"seed": 35.0, "startFloor": 5.0})
	C.give(h, g2, "furie")
	C.give(h, g2, "lame_ardente")
	C.give(h, g2, "lame_ardente")
	C.give(h, g2, "envol") # sans niveau : ni fondue ni approfondie
	var dmg0: float = g2.player.stats.damageMult
	var t = D6Run.forge_targets(g2)
	h.egal([t.lost.id, t.gained.id] if t != null else null, ["furie", "lame_ardente"])
	var ch: Dictionary = C.altar(h, g2, "forge")
	var levels: float = _event("forge").options[0].levels
	var label: String = ch.options[0].label
	h.ok("« Furie »" in label and "« Lame ardente »" in label and D6Js.num_str(levels) in label, label)
	h.egal(_choose(g2, 0.0), true)
	h.egal(g2.run.boons.map(func(b): return [b.id, b.level]), [["lame_ardente", 2.0 + levels], ["envol", 1.0]])
	h.ok(g2.player.stats.damageMult < dmg0, "Furie est vraiment perdue")
	var pr = C.proc_of(g2, "lame_ardente")
	var burn: float = pr.value if pr != null else NAN
	h.ok(absf(burn - C.V("lame_ardente") * (1.0 + 0.5 * (1.0 + levels))) < EPS, "Lame ardente vraiment approfondie")

static func _t_miroir(h) -> void:
	var opt: Dictionary = _event("miroir").options[0]
	var pact: Dictionary = C.by_id(C.boons_t().PACTS, opt.pact)
	h.egal(opt.pct, pact.value, "le libellé et le pacte disent les mêmes dégâts")
	h.egal(-opt.hp, pact.stats.maxHpBonus, "le libellé et le pacte disent les mêmes PV")
	var g: Dictionary = D6Game.create_game({"seed": 37.0, "startFloor": 5.0})
	var max0: float = g.player.maxHp
	var dmg0: float = g.player.stats.damageMult
	var ch: Dictionary = C.altar(h, g, "miroir")
	var label: String = ch.options[0].label
	h.ok(("−%s PV max" % D6Js.num_str(opt.hp)) in label and ("+%s %%" % D6Js.num_str(opt.pct)) in label, label)
	h.egal(_choose(g, 0.0), true)
	h.egal(g.player.maxHp, max0 - opt.hp)
	h.ok(g.player.hp <= g.player.maxHp)
	h.ok(absf(g.player.stats.damageMult - dmg0 - opt.pct / 100.0) < EPS)
	h.egal(g.run.boons.map(func(b): return b.id), [opt.pact])
	# Déjà brisé : l'option est grisée (un pacte ne se cumule pas).
	h.egal(C.altar(h, g, "miroir").options[0].disabled, true)
	h.egal(_choose(g, 1.0), true)
	# TEMPORAIRE : la mort le reprend, PV max et dégâts reviennent.
	_die(g)
	h.egal(g.run.boons, [])
	h.egal(g.player.maxHp, max0)
	h.ok(absf(g.player.stats.damageMult - dmg0) < EPS)

static func _t_clepsydre(h) -> void:
	var drink: Dictionary = _event("clepsydre").options[0]
	var smash: Dictionary = _event("clepsydre").options[1]
	var g: Dictionary = D6Game.create_game({"seed": 39.0, "startFloor": 5.0})
	g.player.superCharge = drink.need / 100.0 - 0.01
	h.egal(C.altar(h, g, "clepsydre").options[0].disabled, true, "jauge trop basse : grisé")
	h.egal(_choose(g, 0.0), false)
	_choose(g, 2.0)
	g.player.superCharge = drink.need / 100.0
	g.player.hp = 10.0
	C.altar(h, g, "clepsydre")
	h.egal(_choose(g, 0.0), true)
	h.egal(g.player.superCharge, 0.0)
	h.ok(absf(g.player.hp - (10.0 + g.player.maxHp * drink.pct / 100.0)) < EPS)
	# Briser : des PV contre une jauge pleine.
	var g2: Dictionary = D6Game.create_game({"seed": 39.0, "startFloor": 5.0})
	g2.player.superCharge = 0.2
	var hp0: float = g2.player.hp
	C.altar(h, g2, "clepsydre")
	h.egal(_choose(g2, 1.0), true)
	h.egal(g2.player.hp, hp0 - smash.hp)
	h.egal(g2.player.superCharge, 1.0)
	# Jauge déjà pleine : briser ne donnerait rien, l'option est grisée ; jamais mortel.
	h.egal(C.altar(h, g2, "clepsydre").options[1].disabled, true)
	_choose(g2, 2.0)
	var low: Dictionary = D6Game.create_game({"seed": 39.0, "startFloor": 5.0})
	low.player.hp = 3.0
	C.altar(h, low, "clepsydre")
	_choose(low, 1.0)
	h.egal(low.player.hp, 1.0)

static func _altar_play(h) -> Array:
	var out: Array = []
	for id in C.NEW_EVENTS:
		for index in [0.0, 1.0]:
			var g: Dictionary = D6Game.create_game({"seed": 41.0, "startFloor": 5.0})
			g.meta.souls = 90.0
			g.player.superCharge = 0.7
			C.give(h, g, "furie")
			C.give(h, g, "torpeur")
			C.altar(h, g, id)
			_choose(g, index)
			out.append([id, index, D6Game.state_hash(g), g.rng.gen.s, g.meta.souls, g.player.hp, g.player.maxHp, g.player.superCharge, g.run.boons.map(func(b): return [b.id, b.level, b.rarity])])
	return out

static func _t_determinisme(h) -> void:
	h.egal(_altar_play(h), _altar_play(h))

static func tests(h) -> void:
	h.test("autels : tout libellé est chiffré par les données de son option (aucune accolade restante), dans une vraie partie", func(): _t_libelles(h))
	h.test("autels : les quatre nouveaux se rencontrent en descente (tirage de la salle d'autel)", func(): _t_tirage(h))
	h.test("autel Registre des âmes : le PERMANENT (Âmes) s'échange contre le TEMPORAIRE, dans les deux sens, aux prix affichés", func(): _t_registre(h))
	h.test("autel Forge des regrets : la bénédiction la moins avancée est fondue, la plus avancée gagne 2 niveaux — toutes deux nommées", func(): _t_forge(h))
	h.test("autel Miroir d'orgueil : −PV max et +dégâts aux nombres affichés, jusqu'à la mort ; une seule fois", func(): _t_miroir(h))
	h.test("autel Clepsydre de Charon : la jauge de Super contre des PV, ou des PV contre la jauge, aux nombres affichés", func(): _t_clepsydre(h))
	h.test("autels : même graine et mêmes choix = même partie (déterminisme des quatre nouveaux)", func(): _t_determinisme(h))
