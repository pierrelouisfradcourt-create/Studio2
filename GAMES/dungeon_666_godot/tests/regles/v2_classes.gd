extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_classes.test.mjs.
## Tests du lot CLASSES (V2, D11) : les deux défauts relevés par la relecture adversariale.
##
##   - GARDE : un ennemi qui sort d'un étourdissement n'est pas ré-étourdi par un coup d'arme
##     pendant combat.stunGuard. Sans elle, la Hache et le Maillet maintenus sur place
##     étourdissaient en boucle : plus aucun dégât de mêlée.
##   - CHASSERESSE : on ne distance pas la mêlée en tirant ; pour fuir, il faut cesser de tirer
##     ou dasher (le dash reste la fuite).
## La mesure sur une section entière (bots, 20 graines) est dans outils/classes.gd.

const Classes = preload("res://outils/classes.gd")

const EXIT_COOLDOWN := 0.3 # enemies.mjs : recharge imposée en sortie d'étourdissement
const DUMMY_HP := 5000.0
const DUMMY_DISTANCE := 300.0
const SHOOT_SECONDS := 2.0

static func tests(h) -> void:
	h.test("garde : un ennemi qui sort d'un étourdissement n'est pas ré-étourdi par un coup d'arme, mais il est blessé et repoussé", func(): _garde_arme(h))
	h.test("garde : compétence, gadget, Super et mur étourdissent malgré la garde (ressources comptées, placement)", func(): _garde_ressources(h))
	h.test("garde : elle dure combat.stunGuard, puis un coup d'arme étourdit de nouveau", func(): _garde_duree(h))
	h.test("garde : assez longue pour placer une attaque (recharge de sortie + télégraphe le plus long de la mêlée)", func(): _garde_assez_longue(h))
	h.test("garde : réglée à 0, elle n'existe pas (le réglage commande la règle)", func(): _garde_nulle(h))
	h.test("mêlée : attaque maintenue sur place, les brutes placent leurs coups avec chaque arme (pas d'étourdissement en boucle)", func(): _melee_sur_place(h))
	h.test("Maillet : c'est la garde qui rend les coups aux brutes (sans elle, le fracas les étourdit en boucle)", func(): _maillet(h))
	h.test("Chasseresse : en tirant, elle avance moins vite qu'un diablotin ; en cessant de tirer, plus vite", func(): _chasseresse_vitesse(h))
	h.test("Chasseresse : le dash reste la fuite — pressé en plein tir, il part et couvre au moins la distance de base", func(): _chasseresse_dash(h))

# ---------------------------------------------------------------- outillage (celui du fichier web)

static func _ticks(seconds: float) -> int:
	return int(ceilf(seconds / D6Data.DT))

## Partie de test : salle vidée (aucune vague, aucun obstacle), héros au centre.
static func _sandbox(class_id: String, weapon_type: String, tuning = null) -> Dictionary:
	var opts := {"seed": 11.0, "meta": Classes.kit_profile(D6Data.create_tuning(), class_id, weapon_type)}
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
	g.player.x = g.room.w / 2.0
	g.player.y = g.room.h / 2.0
	g.tuning.combat.critChance = 0.0
	g.events.clear()
	return g

static func _run(g: Dictionary, n: int, over: Dictionary = {}) -> void:
	for i in n:
		var input: Dictionary = D6Game.empty_input()
		input.merge(over, true)
		D6Game.step_game(g, input)
		g.events.clear()

## Mannequin loin du héros : ne riposte pas, ne meurt pas.
static func _dummy(g: Dictionary, kind: String = "brute") -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + DUMMY_DISTANCE, g.player.y, {"spawnT": 0.0})
	e.cooldown = 999.0
	e.hp = DUMMY_HP
	e.maxHp = DUMMY_HP
	return e

## Étourdit le mannequin par une source comptée, puis attend la fin de l'étourdissement.
static func _stun_then_recover(h, g: Dictionary, e: Dictionary, stun: float = 0.2) -> void:
	D6Combat.damage_enemy(g, e, {"kind": "gadget", "amount": 1.0, "stun": stun, "canCrit": false})
	h.ok(e.stun > 0.0, "étourdi")
	_run(g, _ticks(stun) + 1)
	h.ok(e.stun <= 0.0, "l'étourdissement est fini")

## Coups reçus sur place, en moyenne sur HOLD_SEEDS graines (holdHits de tools/classes.mjs ;
## outils/classes.gd n'expose que hold_trial).
static func _hold_hits(class_id: String, weapon_type: String, pack: Array, tuning = null) -> float:
	var somme := 0.0
	for s in range(1, Classes.HOLD_SEEDS + 1):
		somme += Classes.hold_trial(class_id, weapon_type, pack, float(s), tuning)
	return somme / float(Classes.HOLD_SEEDS)

# ---------------------------------------------------------------- garde

static func _garde_arme(h) -> void:
	var g := _sandbox("bourreau", "hache")
	var e := _dummy(g)
	h.egal(e.get("guard"), 0.0, "aucune garde tant qu'il n'a pas été étourdi")
	_stun_then_recover(h, g, e)
	h.ok(e.guard > 0.0 and e.guard <= g.tuning.combat.stunGuard, "la garde commence à la fin de l'étourdissement")
	for kind in g.tuning.combat.stunGuardSources:
		var hp: float = e.hp
		e.kvx = 0.0
		e.kvy = 0.0
		D6Combat.damage_enemy(g, e, {"kind": kind, "amount": 20.0, "stun": 0.7, "knockback": 800.0, "dirX": 1.0, "dirY": 0.0, "canCrit": false})
		h.ok(e.stun <= 0.0, "%s : pas de ré-étourdissement pendant la garde" % kind)
		h.different(e.state, "stunned", "%s : il garde son état" % kind)
		h.ok(e.hp < hp, "%s : le coup blesse" % kind)
		h.ok(e.kvx > 0.0, "%s : le coup repousse" % kind)

static func _garde_ressources(h) -> void:
	for kind in ["skill", "gadget", "super", "wall"]:
		var g := _sandbox("bourreau", "hache")
		var e := _dummy(g)
		_stun_then_recover(h, g, e)
		h.ok(not g.tuning.combat.stunGuardSources.has(kind), "%s n'est pas une source gardée" % kind)
		D6Combat.damage_enemy(g, e, {"kind": kind, "amount": 1.0, "stun": 0.5, "canCrit": false})
		h.ok(e.stun > 0.0, "%s étourdit un ennemi en garde" % kind)

static func _garde_duree(h) -> void:
	var g := _sandbox("bourreau", "hache")
	var e := _dummy(g)
	_stun_then_recover(h, g, e)
	_run(g, _ticks(g.tuning.combat.stunGuard * 0.8))
	h.ok(e.guard > 0.0, "encore en garde à 80 % de sa durée")
	_run(g, _ticks(g.tuning.combat.stunGuard * 0.3))
	h.egal(e.guard, 0.0, "garde épuisée")
	D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 1.0, "stun": 0.5, "canCrit": false})
	h.ok(e.stun > 0.0, "le coup d'arme étourdit de nouveau")

static func _garde_assez_longue(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	for kind in t.enemies:
		var def: Dictionary = t.enemies[kind]
		if not def.has("windup") or not def.has("attackRange"):
			continue # archétypes de mêlée
		h.ok(t.combat.stunGuard >= EXIT_COOLDOWN + def.windup, "%s : %s + %s s tiennent dans la garde" % [kind, str(EXIT_COOLDOWN), str(def.windup)])

static func _garde_nulle(h) -> void:
	var g := _sandbox("bourreau", "hache", {"combat": {"stunGuard": 0.0}})
	var e := _dummy(g)
	_stun_then_recover(h, g, e)
	D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 1.0, "stun": 0.5, "canCrit": false})
	h.ok(e.stun > 0.0, "sans garde, le coup d'arme ré-étourdit aussitôt")

# ---------------------------------------------------------------- Bourreau : attaque maintenue sur place

static func _melee_sur_place(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	for kit in Classes.all_kits(t):
		if t.weapons[kit.weaponType].kind != "melee":
			continue
		var hits := _hold_hits(kit.classId, kit.weaponType, Classes.HOLD_PACKS.brutes)
		h.ok(hits >= Classes.MIN_HOLD_HITS, "%s : %.1f coups reçus en moyenne (seuil %s)" % [kit.id, hits, str(Classes.MIN_HOLD_HITS)])

static func _maillet(h) -> void:
	var guarded := _hold_hits("bourreau", "marteau", Classes.HOLD_PACKS.brutes)
	var unguarded := _hold_hits("bourreau", "marteau", Classes.HOLD_PACKS.brutes, {"combat": {"stunGuard": 0.0}})
	h.ok(guarded > unguarded, "avec la garde %.1f coups, sans %.1f" % [guarded, unguarded])

# ---------------------------------------------------------------- Chasseresse : on ne distance pas la mêlée en tirant

static func _chasseresse_vitesse(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var imp_speed: float = t.enemies.imp.speed
	for weapon_type in t.classes.chasseresse.weapons:
		var g := _sandbox("chasseresse", weapon_type)
		var p: Dictionary = g.player
		var x0: float = p.x
		_run(g, _ticks(SHOOT_SECONDS), {"moveX": -1.0, "attack": true, "aimX": 1.0}) # elle recule en tirant devant elle
		var shooting: float = (x0 - p.x) / SHOOT_SECONDS
		h.ok(shooting > 0.0, "%s : elle se déplace encore en tirant" % weapon_type)
		h.ok(shooting < imp_speed, "%s : %.0f u/s en tirant < diablotin %s u/s" % [weapon_type, shooting, str(imp_speed)])

		var g2 := _sandbox("chasseresse", weapon_type)
		var x1: float = g2.player.x
		_run(g2, _ticks(SHOOT_SECONDS), {"moveX": -1.0})
		var running: float = (x1 - g2.player.x) / SHOOT_SECONDS
		h.ok(running > imp_speed, "%s : %.0f u/s en courant > diablotin %s u/s" % [weapon_type, running, str(imp_speed)])

static func _chasseresse_dash(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	for weapon_type in t.classes.chasseresse.weapons:
		var g := _sandbox("chasseresse", weapon_type)
		var p: Dictionary = g.player
		_run(g, _ticks(0.3), {"attack": true, "aimX": 1.0}) # en plein tir
		var x0: float = p.x
		_run(g, 1, {"moveX": -1.0, "dashPressed": true})
		_run(g, _ticks(g.tuning.dash.duration), {"moveX": -1.0})
		var dashed: float = x0 - p.x
		h.ok(dashed >= g.tuning.dash.distance, "%s : dash de %.0f u (classe : +30 %%)" % [weapon_type, dashed])
