extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_contenu.test.mjs (3/4 : les 6 pouvoirs légendaires).
## Outils : v2_contenu.gd.

const C = preload("res://tests/regles/v2_contenu.gd")
const DT := 1.0 / 60.0

static func _t_alastor(h) -> void:
	var g: Dictionary = C.arena(h)
	C.wear(h, g, "eperons_alastor")
	var max_charges: float = g.tuning.dash.charges
	C.perfect_dodge(h, g)
	h.egal(g.player.dashCharges, max_charges - 1.0 + C.power_proc("eperons_alastor").value)
	h.ok(C.events(g, "dashReady").size() >= 1)
	var g2: Dictionary = C.arena(h)
	C.perfect_dodge(h, g2)
	h.egal(g2.player.dashCharges, max_charges - 1.0, "sans le pouvoir : la charge reste dépensée")
	C.assert_deterministic(h, [], {"power": "eperons_alastor"})

## Tient l'attaque jusqu'au premier étourdissement ; rend le pas où il arrive (-1 : jamais).
static func _attack_until_stun(h, g: Dictionary, e: Dictionary) -> int:
	var i := 0
	while i < h.ticks(1.2):
		C.step1(h, g, {"attack": true})
		if e.stun > 0.0:
			return i
		i += 1
	return -1

static func _t_belial(h) -> void:
	var g: Dictionary = C.arena(h)
	C.wear(h, g, "marteau_belial")
	var stun: float = C.power_proc("marteau_belial").value
	var e: Dictionary = C.dummy(g, 60.0, 0.0, "brute", 1e6)
	var stunned_at := _attack_until_stun(h, g, e)
	h.ok(stunned_at >= 0, "le dernier coup a étourdi")
	h.ok(e.stun <= stun and e.stun > stun - 3.0 * DT, "étourdi %s s" % e.stun)
	var combo: Array = g.tuning.combo
	var fin: float = combo[combo.size() - 1].damage
	var melee: Array = C.events(g, "hit").filter(func(x): return x.get("kind") == "melee")
	h.egal(melee[melee.size() - 1].amount if melee.size() > 0 else null, fin, "c'est le dernier coup du combo qui a étourdi")
	# Au réveil, l'ennemi est en garde : les derniers coups suivants blessent sans ré-étourdir.
	var i := 0
	while i < 300 and e.stun > 0.0:
		C.step1(h, g)
		i += 1
	C.step1(h, g)
	h.ok(e.guard > 0.0, "réveillé en garde")
	var restunned := false
	for k in h.ticks(1.2):
		C.step1(h, g, {"attack": true})
		if e.guard > 0.0 and e.stun > 0.0:
			restunned = true
	h.egal(restunned, false)
	C.assert_deterministic(h, [], {"power": "marteau_belial"})

static func _t_lilith(h) -> void:
	var g: Dictionary = C.arena(h)
	C.wear(h, g, "dard_lilith")
	var pr: Dictionary = C.power_proc("dard_lilith")
	C.dummy(g, 200.0, 0.0, "brute", 1e6)
	var others: Array = [1.0, 2.0, 3.0, 4.0].map(func(k): return C.dummy(g, 200.0 + 100.0 * k, 200.0, "imp", 1000.0))
	C.dash_strike(h, g)
	h.egal(C.events(g, "hit").filter(func(x): return x.get("kind") == "strike").size(), 1)
	h.egal(C.events(g, "chain").size(), pr.bounces)
	h.egal(others.filter(func(e): return e.hp == 1000.0 - pr.value).size(), pr.bounces)
	C.assert_deterministic(h, [], {"power": "dard_lilith"})

static func _t_main_de_gloire(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 25.0, "startFloor": 3.0})
	C.wear(h, g, "main_de_gloire")
	g.player.slots[1].charges = 1.0
	C.clear_room(h, g)
	h.egal(g.player.slots[1].charges, 1.0 + C.power_proc("main_de_gloire").value)
	var g2: Dictionary = D6Game.create_game({"seed": 25.0, "startFloor": 3.0})
	C.wear(h, g2, "main_de_gloire")
	g2.player.slots[1].charges = 1.0
	D6Combat.damage_player(g2, 3.0, {"kind": "test", "id": 3.0})
	C.clear_room(h, g2)
	h.egal(g2.player.slots[1].charges, 1.0)
	# Jamais au-delà du plein.
	var g3: Dictionary = D6Game.create_game({"seed": 25.0, "startFloor": 3.0})
	C.wear(h, g3, "main_de_gloire")
	var full: float = g3.player.slots[1].charges
	C.clear_room(h, g3)
	h.egal(g3.player.slots[1].charges, full)
	C.assert_deterministic(h, [], {"power": "main_de_gloire"})

static func _sin_blast(g: Dictionary):
	for hz in g.hazards:
		if hz.get("kind") == "sinBlast":
			return hz
	return null

static func _blast_shape(blast) -> Array:
	return [blast.get("r"), blast.get("damage"), blast.get("hitsPlayer")] if blast is Dictionary else []

static func _t_moloch(h) -> void:
	var g: Dictionary = C.arena(h)
	C.wear(h, g, "fracas_moloch")
	var pr: Dictionary = C.power_proc("fracas_moloch")
	var e: Dictionary = C.dummy(g, 0.0, 0.0, "imp", 500.0)
	h.ok(C.slam(h, g, e))
	var neighbor: Dictionary = D6Enemies.create_enemy(g, "brute", e.x + 40.0, e.y + 60.0, {"spawnT": 0.0})
	neighbor.cooldown = 99.0
	neighbor.maxHp = 1000.0
	neighbor.hp = 1000.0
	var blast = _sin_blast(g)
	h.ok(blast != null, "explosion posée")
	h.egal(_blast_shape(blast), [pr.radius, pr.value, false])
	C.steps(h, g, h.ticks(0.2))
	h.egal(neighbor.hp, 1000.0 - pr.value)
	C.assert_deterministic(h, [], {"power": "fracas_moloch"})

static func _t_abaddon(h) -> void:
	var g: Dictionary = C.arena(h)
	C.wear(h, g, "linceul_abaddon")
	var pr: Dictionary = C.power_proc("linceul_abaddon")
	var victim: Dictionary = C.dummy(g, 200.0, 0.0, "imp", 5.0)
	var neighbor: Dictionary = C.dummy(g, 250.0, 0.0, "brute", 1000.0)
	var far: Dictionary = C.dummy(g, 200.0 + pr.radius + 120.0, 0.0, "brute", 1000.0)
	C.hit100(g, victim)
	h.egal(victim.dead, true)
	h.egal(_blast_shape(_sin_blast(g)), [pr.radius, pr.value, false])
	var hp: float = g.player.hp
	C.steps(h, g, h.ticks(0.2))
	h.egal(neighbor.hp, 1000.0 - pr.value)
	h.egal(far.hp, 1000.0)
	h.egal(g.player.hp, hp, "jamais le héros")
	C.assert_deterministic(h, [], {"power": "linceul_abaddon"})

static func tests(h) -> void:
	h.test("pouvoir d'Alastor : une esquive parfaite rend 1 charge de dash", func(): _t_alastor(h))
	h.test("pouvoir de Bélial : le dernier coup du combo étourdit 0,6 s ; la garde tient (pas de ré-étourdissement en boucle)", func(): _t_belial(h))
	h.test("pouvoir de Lilith : la frappe de dash lance un éclair en chaîne (16 dégâts, 3 rebonds)", func(): _t_lilith(h))
	h.test("pouvoir de la Main de gloire : salle nettoyée sans être touché = +1 charge de gadget ; touché, rien", func(): _t_main_de_gloire(h))
	h.test("pouvoir de Moloch : un ennemi projeté contre un mur explose (20 dégâts, rayon 90)", func(): _t_moloch(h))
	h.test("pouvoir d'Abaddon : les ennemis tués explosent (12 dégâts, rayon 80)", func(): _t_abaddon(h))
