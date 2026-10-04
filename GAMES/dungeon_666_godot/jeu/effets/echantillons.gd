extends RefCounted
## Un événement d'exemple par cas que la vue Effets traite (mêmes champs que les `emit` de
## GAMES/dungeon_666/src/sim). Sert au banc (planche d'effets) et à la vérification : ces
## événements sont donnés à la vue seule, jamais à la simulation.

const CAS: Array[Dictionary] = [
	{"type": "swing", "angle": 0.4, "arc": 2.1, "range": 78.0, "index": 0.0, "strike": false, "ranged": false},
	{"type": "swing", "angle": 2.0, "arc": 2.4, "range": 90.0, "index": 2.0, "strike": true, "ranged": false},
	{"type": "swing", "angle": 1.0, "arc": 0.2, "range": 300.0, "index": 1.0, "strike": false, "ranged": true},
	{"type": "hit", "id": 9001.0, "amount": 12.0, "crit": false, "kind": "melee", "dirX": 1.0, "dirY": 0.0, "enemy": "imp", "shake": 0.0},
	{"type": "hit", "id": 9002.0, "amount": 47.0, "crit": true, "kind": "strike", "dirX": 0.0, "dirY": -1.0, "enemy": "brute", "shake": 0.0},
	{"type": "hit", "id": 9003.0, "amount": 3.0, "crit": false, "kind": "burn", "dirX": 0.0, "dirY": 0.0, "enemy": "archer", "shake": 0.0},
	{"type": "kill", "id": 9004.0, "r": 14.0, "enemy": "imp", "elite": false, "boss": false, "kind": "melee"},
	{"type": "kill", "id": 9005.0, "r": 20.0, "enemy": "charger", "elite": true, "boss": false, "kind": "melee"},
	{"type": "kill", "id": 9006.0, "r": 46.0, "enemy": "gardien", "elite": false, "boss": true, "kind": "melee"},
	{"type": "dash", "dirX": 1.0, "dirY": 0.0, "charges": 1.0},
	{"type": "dashEnd"},
	{"type": "dashNova", "r": 90.0},
	{"type": "dodge"},
	{"type": "deflect"},
	{"type": "playerHurt", "amount": 14.0, "source": "imp", "decalage_source": -60.0},
	{"type": "playerDeath", "source": "imp"},
	{"type": "hazardFire", "id": 9007.0, "kind": "bossSlam", "shape": "circle", "r": 70.0, "angle": null, "length": null, "width": null},
	{"type": "hazardFire", "id": 9008.0, "kind": "sinBlast", "shape": "circle", "r": 50.0, "angle": null, "length": null, "width": null},
	{"type": "hazardFire", "id": 9009.0, "kind": "sweep", "shape": "line", "r": null, "angle": 0.3, "length": 160.0, "width": 40.0},
	{"type": "explode", "id": 9010.0, "r": 80.0},
	{"type": "explode", "r": 90.0, "hero": true, "kind": "bombe"},
	{"type": "explode", "r": 60.0, "hero": true, "kind": "piege"},
	{"type": "explode", "r": 100.0, "hero": true, "kind": "bond"},
	{"type": "explode", "r": 70.0, "hero": true, "kind": "brasier"},
	{"type": "hook", "boss": false, "segment": Vector2(120.0, -40.0)},
	{"type": "chain", "segment": Vector2(110.0, 50.0)},
	{"type": "kitPulse", "r": 80.0, "kind": "totem"},
	{"type": "skill", "angle": 0.0, "skill": "bond"},
	{"type": "skill", "angle": 0.5, "skill": "volee"},
	{"type": "skill", "angle": -0.5},
	{"type": "gadget", "r": 120.0, "charges": 0.0, "gadget": "cri"},
	{"type": "gadget", "r": 90.0, "charges": 0.0, "gadget": "bombe"},
	{"type": "gadget", "r": 110.0, "charges": 0.0},
	{"type": "super", "r": 100.0, "super": "tourbillon"},
	{"type": "super", "r": 400.0, "super": "nuee"},
	{"type": "superTick", "r": 150.0, "super": "sentence", "angle": 0.0, "arc": 2.6, "step": 0.0},
	{"type": "superTick", "r": 150.0, "super": "sentence", "angle": 0.0, "arc": TAU, "step": 2.0},
	{"type": "superTick", "r": 8.0, "super": "nuee", "angle": 1.0},
	{"type": "superTick", "r": 100.0},
	{"type": "pickup", "kind": "gold", "amount": 6.0},
	{"type": "pickup", "kind": "heal", "amount": 10.0},
	{"type": "gold", "amount": 25.0},
	{"type": "heal", "amount": 12.0},
	{"type": "souls", "amount": 3.0},
	{"type": "wallSlam", "id": 9011.0},
	{"type": "chargerWall", "id": 9012.0},
	{"type": "chargerWall", "id": 9013.0, "boss": true},
	{"type": "spawn", "id": 9014.0, "enemy": "imp", "elite": false, "boss": false},
	{"type": "spawn", "id": 9015.0, "enemy": "gardien", "elite": false, "boss": true},
	{"type": "bossPhase", "id": 9016.0, "phase": 2.0},
	{"type": "boonGain", "id": "soif", "rarity": "rare"},
	{"type": "immune"},
	{"type": "moveShort", "dirX": 1.0, "dirY": 0.0, "reach": 150.0, "done": 30.0, "move": "dash"},
	{"type": "moveShort", "dirX": 0.0, "dirY": -1.0, "reach": 130.0, "done": 0.0, "move": "saut"},
	{"type": "moveLand", "r": 80.0, "move": "saut", "pushed": 2.0},
]

## Les cas dont le type est dans `types` (tous si vide), posés en grille autour de `centre`.
static func poses(centre: Vector2, types: PackedStringArray = PackedStringArray(), pas: Vector2 = Vector2(150.0, 120.0), colonnes: int = 5) -> Array[Dictionary]:
	var sortie: Array[Dictionary] = []
	for cas in CAS:
		if types.is_empty() or cas.type in types:
			sortie.append(cas.duplicate())
	var lignes := ceili(sortie.size() / float(colonnes))
	for i in sortie.size():
		var ligne := i / colonnes
		var dans_ligne := mini(colonnes, sortie.size() - ligne * colonnes)
		_poser(sortie[i], centre + Vector2((i % colonnes - (dans_ligne - 1) * 0.5) * pas.x, (ligne - (lignes - 1) * 0.5) * pas.y))
	return sortie

static func _poser(ev: Dictionary, p: Vector2) -> void:
	ev["tick"] = 0.0
	ev["x"] = p.x
	ev["y"] = p.y
	if ev.has("segment"):
		var s: Vector2 = ev.segment
		ev.erase("segment")
		ev.merge({"x0": p.x - s.x * 0.5, "y0": p.y - s.y * 0.5, "x1": p.x + s.x * 0.5, "y1": p.y + s.y * 0.5})
	if ev.has("decalage_source"):
		ev["srcX"] = p.x + ev.decalage_source
		ev["srcY"] = p.y
		ev.erase("decalage_source")
