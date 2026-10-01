extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_integration.test.mjs.
## Règles vérifiées à l'INTÉGRATION des lots V2 (2026-10-01).

const IMP_STEPS := 600 # 10 s
const MIN_IMP_ATTACKS := 3

static func tests(h) -> void:
	h.test("diablotin : un héros immobile est attaqué régulièrement (plus d'orbite hors de portée)", func(): _diablotin(h))
	h.test("Ville : débloquer une classe donne aussi son kit gratuit (arme, compétence, gadget de coût 0)", func(): _ville(h))

## Salle vide, héros immobile au centre.
static func _empty_room(seed_n: float = 5.0) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed_n})
	g.spawns.clear()
	g.enemies.clear()
	g.room.waves = []
	g.room.cleared = true
	g.room.interact = null
	g.room.doors = []
	g.room.obstacles = []
	g.player.x = g.room.w / 2.0
	g.player.y = g.room.h / 2.0
	g.events.clear()
	return g

static func _diablotin(h) -> void:
	var g := _empty_room()
	D6Enemies.create_enemy(g, "imp", g.player.x + 150.0, g.player.y + 40.0, {"spawnT": 0.0})
	var attacks := 0
	for i in IMP_STEPS:
		D6Game.step_game(g, D6Game.empty_input())
		attacks += g.events.filter(func(ev): return ev.type == "enemyAttack").size()
		g.events.clear()
	# 10 s, recharge de 0,9 s + télégraphe + récupération : bien plus d'une attaque.
	h.ok(attacks >= MIN_IMP_ATTACKS, "attaques en 10 s : %d" % attacks)

## Les objets de coût 0 du kit de la classe sont possédés.
static func _kit_gratuit_possede(h, p: Dictionary, t: Dictionary, class_id: String) -> void:
	var c: Dictionary = t.classes[class_id]
	for kind in ["weapons", "skills", "gadgets"]:
		for id in c[kind]:
			if D6Profile.unlock_cost(t, kind, id) == 0.0:
				h.ok(p.unlocked[kind].has(id), "%s : %s/%s gratuit mais verrouillé" % [class_id, kind, id])

static func _ville(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.sanitize_profile({"souls": 1000.0}, t)
	for class_id in t.classes.keys():
		if not p.unlocked.classes.has(class_id):
			h.egal(D6Profile.unlock(p, t, "classes", class_id).get("ok"), true)
		_kit_gratuit_possede(h, p, t, class_id)
		h.egal(D6Profile.select_class(p, t, class_id).get("ok"), true)
		h.ok(p.unlocked.skills.has(p.loadout.skillId), "%s : compétence choisie possédée" % class_id)
		h.ok(p.unlocked.gadgets.has(p.loadout.gadgetId), "%s : gadget choisi possédé" % class_id)
