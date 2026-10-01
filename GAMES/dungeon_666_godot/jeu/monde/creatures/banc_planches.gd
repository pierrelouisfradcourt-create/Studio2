extends RefCounted
## Planches du banc des créatures : une partie dont on vide les vagues, puis des créatures
## posées côte à côte par D6Enemies.create_enemy, immobiles (la partie est en pause).
## OUTIL D'ESSAI : c'est le seul endroit qui écrit dans l'état d'une partie, pour forcer un état
## rare (statut, bouclier, bond) et le montrer. Aucune vue du jeu ne fait cela.

const ARCHETYPES := ["imp", "brute", "archer", "charger", "exploder", "pyromancer", "necromancer"]
const ELITES := [["rapide", "imp"], ["blinde", "brute"], ["ardent", "charger"], ["vampirique", "archer"], ["bouclier", "pyromancer"], ["invocateur", "imp"]]
const GARDIENS := ["gardien", "cerbere", "minos", "colosse"]

const STATUTS := [
	["brute", "blessée", {"hp": 0.4}],
	["imp", "étourdi", {"hp": 0.6, "stun": 1.0}],
	["imp", "en garde", {"hp": 0.6, "guard": 1.0}],
	["brute", "froid", {"chill": 2.0}],
	["brute", "brûlure", {"burn": 2.0}],
	["brute", "vulnérable", {"vuln": 3.0}],
	["imp", "apparition", {"spawnT": 0.1}],
	["brute", "touchée", {"hp": 0.8, "flash": 0.1, "hitDirX": 1.0, "hitDirY": 0.0}],
	["brute", "tout à la fois", {"hp": 0.5, "stun": 1.0, "chill": 2.0, "burn": 2.0, "vuln": 3.0}],
]
const ATTAQUES := [
	["imp", "arme son coup", {"state": "windup", "stateTime": 0.05}],
	["archer", "vise", {"state": "windup", "stateTime": 0.4}],
	["brute", "lève les poings", {"state": "windup", "stateTime": 0.05}],
	["charger", "charge", {"state": "charge", "dirX": 0.6, "dirY": 0.8}],
	["exploder", "va exploser", {"state": "windup", "stateTime": 0.46}],
	["pyromancer", "incante", {"state": "windup", "stateTime": 0.2}],
	["necromancer", "canalise", {"state": "channel", "stateTime": 0.5}],
]
const POUVOIRS := [
	["bouclier", "brute", "bulle annoncée", {"modPhase": "warn", "modT": 0.25, "modDur": 0.6}],
	["bouclier", "brute", "bulle active", {"modPhase": "up", "modT": 1.0, "modDur": 1.8, "invuln": 1.0}],
	["invocateur", "archer", "canalise", {"modPhase": "channel", "modT": 0.4, "modDur": 1.2}],
	["vampirique", "imp", "draine", {"hp": 0.7, "leechFlash": 0.5}],
]
const ETATS_GARDIENS := [
	["gardien", "Charon charge (phase 2)", {"phase": 2.0, "state": "charge"}],
	["gardien", "Charon, transition (phase 3)", {"phase": 3.0, "state": "roar", "invuln": 1.0}],
	["cerbere", "Cerbère bondit", {"airborne": true, "leapK": 0.5}],
	["cerbere", "Cerbère mord (phase 3)", {"phase": 3.0, "tele": {"shape": "cone", "progress": 0.5}}],
	["minos", "Minos dissous", {"hidden": true, "invuln": 1.0}],
	["minos", "Minos fouette, exposé", {"phase": 2.0, "exposed": 1.0, "tele": {"shape": "cone", "area": true, "progress": 0.6}}],
	["colosse", "Colosse enchaîné", {"phase": 2.0, "shielded": true, "invuln": 1.0}],
	["colosse", "Colosse, bras coincé", {"phase": 3.0, "state": "poing", "sub": "recover", "exposed": 1.0}],
]

## Remplit la partie et rend les légendes [{pos, texte}] à écrire sous les créatures.
static func composer(g: Dictionary, planche: int) -> Array:
	for liste in [g.enemies, g.spawns, g.hazards, g.projectiles, g.pickups]:
		liste.clear()
	g.room.waves = []
	var c := Vector2(g.room.w, g.room.h) * 0.5
	var legendes: Array = []
	if planche == 2:
		g.player.x = c.x
		g.player.y = c.y + 45.0
		_etats(g, c, legendes)
	else:
		# Le héros est posé loin sous la planche : toutes les créatures regardent vers le bas.
		g.player.x = c.x
		g.player.y = c.y + 6000.0
		_bestiaire(g, c, legendes)
	g.events.clear()
	return legendes

static func _poser(g: Dictionary, kind: String, pos: Vector2, opts: Dictionary, etat: Dictionary, texte: String, legendes: Array) -> void:
	opts["spawnT"] = 0.0
	var e: Dictionary = D6Enemies.create_enemy(g, kind, pos.x, pos.y, opts)
	for cle in etat:
		e[cle] = e.maxHp * etat[cle] if cle == "hp" else etat[cle]
	var marge: float = e.r * (1.5 if e.boss else 1.0) + 26.0
	legendes.append({"pos": pos + Vector2(0.0, marge), "texte": texte})

static func _nom(g: Dictionary, kind: String, boss: bool = false) -> String:
	var def: Dictionary = g.tuning.boss[kind] if boss else g.tuning.enemies[kind]
	return String(def.name).get_slice(",", 0)

static func _rang(n: int, i: int, pas: float, centre: Vector2, y: float) -> Vector2:
	return Vector2(centre.x + (i - (n - 1) * 0.5) * pas, centre.y + y)

static func _bestiaire(g: Dictionary, c: Vector2, legendes: Array) -> void:
	for i in ARCHETYPES.size():
		_poser(g, ARCHETYPES[i], _rang(7, i, 125.0, c, -195.0), {}, {}, _nom(g, ARCHETYPES[i]), legendes)
	for i in ELITES.size():
		_poser(g, ELITES[i][1], _rang(6, i, 140.0, c, -42.0), {"elite": ELITES[i][0]}, {}, "élite · " + _nom(g, ELITES[i][1]), legendes)
	for i in GARDIENS.size():
		_poser(g, GARDIENS[i], _rang(4, i, 215.0, c, 105.0), {"boss": true}, {}, _nom(g, GARDIENS[i], true), legendes)

static func _etats(g: Dictionary, c: Vector2, legendes: Array) -> void:
	for i in STATUTS.size():
		_poser(g, STATUTS[i][0], _rang(STATUTS.size(), i, 130.0, c, -280.0), {}, STATUTS[i][2], STATUTS[i][1], legendes)
	for i in ATTAQUES.size():
		_poser(g, ATTAQUES[i][0], _rang(ATTAQUES.size(), i, 150.0, c, -140.0), {}, ATTAQUES[i][2], _nom(g, ATTAQUES[i][0]) + " " + ATTAQUES[i][1], legendes)
	for i in POUVOIRS.size():
		var x := (i - 1.5) * 190.0 + (-60.0 if i < 2 else 60.0)
		_poser(g, POUVOIRS[i][1], c + Vector2(x, 35.0), {"elite": POUVOIRS[i][0]}, POUVOIRS[i][3], POUVOIRS[i][2], legendes)
	for i in ETATS_GARDIENS.size():
		_poser(g, ETATS_GARDIENS[i][0], _rang(ETATS_GARDIENS.size(), i, 165.0, c, 235.0), {"boss": true}, ETATS_GARDIENS[i][2], ETATS_GARDIENS[i][1], legendes)
