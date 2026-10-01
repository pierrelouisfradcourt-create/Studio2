extends RefCounted
## Adaptateurs des vecteurs « combat » (src/sim/combat.mjs) : pour chaque fonction exportée par la
## simulation web, l'appel équivalent côté Godot. `adapters()` rend {nom JavaScript: Callable(args) -> sortie}.
##
## `scenario` (partagé avec parite/adaptateurs/projectiles.gd) : une partie synthétique + une suite
## d'opérations [nom, arguments…] ; la sortie est la partie entière après coup (tools/vecteurs/
## physique_combat.mjs). Les réglages sont ceux de data/tuning.json, plus `hitstopMode`.

static func _snap(game: Dictionary, target) -> Dictionary:
	return {
		"hitstop": game.hitstop, "hitstopBank": game.hitstopBank, "playerFreeze": game.player.freeze,
		"targetFreeze": target.get("freeze") if target != null else null,
	}

static func _apply_hitstop(a: Array) -> Dictionary:
	var game: Dictionary = a[0].duplicate(true)
	var target = a[2].duplicate() if a[2] != null else null
	D6Combat.apply_hitstop(game, a[1], target)
	return _snap(game, target)

static func _force_hitstop(a: Array) -> Dictionary:
	var game: Dictionary = a[0].duplicate(true)
	D6Combat.force_hitstop(game, a[1])
	return _snap(game, null)

static func _heal_player(a: Array) -> float:
	var game: Dictionary = a[0].duplicate(true)
	D6Combat.heal_player(game, a[1], a[2])
	return game.player.hp

## Joue une opération de scénario ; rend ce que rend la fonction (null si elle ne rend rien d'utile).
static func _play(game: Dictionary, op: Array):
	match op[0]:
		"damageEnemy":
			return D6Combat.damage_enemy(game, game.enemies[int(op[1])], op[2])
		"killEnemy":
			D6Combat.kill_enemy(game, game.enemies[int(op[1])], op[2])
		"damagePlayer":
			return D6Combat.damage_player(game, op[1], op[2])
		"healPlayer":
			D6Combat.heal_player(game, op[1], op[2])
		"spawnPickup":
			D6Combat.spawn_pickup(game, op[1], op[2], op[3], op[4], op[5] if op.size() > 5 else null)
		"spawnHazard":
			D6Combat.spawn_hazard(game, op[1])
		"spawnProjectile":
			D6Projectiles.spawn_projectile(game, op[1])
		"destroy":
			return D6Projectiles.destroy_enemy_projectiles_in_circle(game, op[1], op[2], op[3])
		"tick":
			for i in range(int(op[1])):
				game.tick += 1.0
				game.time += op[2]
				D6Projectiles.update_projectiles(game, op[2])
				D6Projectiles.update_hazards(game, op[2])
		"iframes":
			game.player.iframes = op[1]
			game.player.dodgeIframes = op[2]
		"stun":
			game.enemies[int(op[1])].stun = op[2]
		"cleared":
			game.room.cleared = true
		_:
			assert(false, "opération de scénario inconnue : %s" % str(op[0]))
	return null

static func scenario(a: Array) -> Dictionary:
	var game: Dictionary = a[0].duplicate(true)
	game.tuning = D6Data.create_tuning({"hitstopMode": a[1]})
	var ret: Array = []
	for op in a[2]:
		ret.append(_play(game, op.duplicate(true)))
	game.erase("tuning")
	return {"game": game, "ret": ret}

static func adapters() -> Dictionary:
	return {
		"isPlayerSource": func(a): return D6Combat.is_player_source(a[0]),
		"applyHitstop": _apply_hitstop,
		"forceHitstop": _force_hitstop,
		"healPlayer": _heal_player,
		"scenario": scenario,
	}
