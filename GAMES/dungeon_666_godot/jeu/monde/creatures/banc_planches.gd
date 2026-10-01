extends RefCounted
## Planches du banc des créatures : une partie dont on vide les vagues, puis des créatures
## posées côte à côte par D6Enemies.create_enemy, immobiles (la partie est en pause).
## OUTIL D'ESSAI : c'est le seul endroit qui écrit dans l'état d'une partie, pour forcer un état
## rare (statut, bouclier, bond) et le montrer. Aucune vue du jeu ne fait cela.
##   1  le bestiaire : 10 archétypes, 6 élites, 4 Gardiens
##   2  les états : statuts, attaques armées, pouvoirs d'élite, Gardiens
##   3  les états des trois nouveaux : pavois, traqueur, étendard et ses protégés
##   4  une pose du héros (D666_POSE, voir _pose_heros) devant un ennemi
##   9  une foule de 40 ennemis, pour mesurer le coût du dessin (jeu/monde/mesure.gd)

const ARCHETYPES := ["imp", "brute", "archer", "charger", "exploder", "pyromancer", "necromancer", "pavois", "stalker", "banner"]
const ELITES := [["rapide", "imp"], ["blinde", "brute"], ["ardent", "charger"], ["vampirique", "archer"], ["bouclier", "pyromancer"], ["invocateur", "imp"]]
const GARDIENS := ["gardien", "cerbere", "minos", "colosse"]
const BAS := PI / 2.0 # une planche regarde vers le bas de l'écran

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
	["imp", "arme son coup", {"state": "windup", "stateTime": 0.3, "tele": {"shape": "cone", "progress": 0.7}}],
	["archer", "vise", {"state": "windup", "stateTime": 0.4, "tele": {"shape": "line", "progress": 0.8}}],
	["brute", "lève les poings", {"state": "windup", "stateTime": 0.5, "tele": {"shape": "circle", "progress": 0.8}}],
	["charger", "charge", {"state": "charge", "dirX": 0.6, "dirY": 0.8}],
	["exploder", "va exploser", {"state": "windup", "stateTime": 0.46}],
	["pyromancer", "incante", {"state": "windup", "stateTime": 0.2, "tele": {"shape": "circle", "progress": 0.6}}],
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
const PAVOIS := [
	["pavois levé (de face)", {"face": BAS}],
	["vu de dos : c'est là", {"face": -BAS}],
	["de profil", {"face": 0.0}],
	["il arme (0,6 s)", {"face": BAS, "state": "windup", "stateTime": 0.45, "tele": {"shape": "cone", "area": true, "progress": 0.75}}],
	["écarté : frappe !", {"face": BAS, "state": "recover", "stateTime": 0.3, "hp": 0.7}],
	["étourdi : tombé", {"face": BAS, "stun": 1.0, "hp": 0.7}],
]
const TRAQUEUR := [
	["il rôde", {}],
	["se dissout (début)", {"state": "fade", "stateTime": 0.08}],
	["se dissout (fin)", {"state": "fade", "stateTime": 0.28}],
	["disparu : rien", {"state": "ambush", "hidden": true, "spawnT": 0.3}],
	["resurgit", {"state": "windup", "stateTime": 0.1}],
	["lames levées", {"state": "windup", "stateTime": 0.48}],
	["récupère : punis-le", {"state": "recover", "stateTime": 0.4, "hp": 0.7}],
]

## Remplit la partie et rend les légendes [{pos, texte}] à écrire sous les créatures.
static func composer(g: Dictionary, planche: int) -> Array:
	for liste in [g.enemies, g.spawns, g.hazards, g.projectiles, g.pickups]:
		liste.clear()
	g.room.waves = []
	var c := Vector2(g.room.w, g.room.h) * 0.5
	var legendes: Array = []
	# Le héros est posé loin sous la planche : toutes les créatures regardent vers le bas.
	g.player.x = c.x
	g.player.y = c.y + 6000.0
	match planche:
		2:
			g.player.y = c.y + 45.0
			_etats(g, c, legendes)
		3:
			_nouveaux(g, c, legendes)
		4:
			g.player.y = c.y
			_pose_heros(g, c)
		9:
			g.player.y = c.y + 230.0
			_foule(g, c)
		_:
			_bestiaire(g, c, legendes)
	g.events.clear()
	return legendes

static func _poser(g: Dictionary, kind: String, pos: Vector2, opts: Dictionary, etat: Dictionary, texte: String, legendes: Array) -> Dictionary:
	opts["spawnT"] = 0.0
	var e: Dictionary = D6Enemies.create_enemy(g, kind, pos.x, pos.y, opts)
	if kind == "pavois":
		e.face = BAS
	for cle in etat:
		e[cle] = e.maxHp * etat[cle] if cle == "hp" else etat[cle]
	var marge: float = e.r * (1.5 if e.boss else 1.0) + 26.0
	legendes.append({"pos": pos + Vector2(0.0, marge), "texte": texte})
	return e

static func _nom(g: Dictionary, kind: String, boss: bool = false) -> String:
	var def: Dictionary = g.tuning.boss[kind] if boss else g.tuning.enemies[kind]
	return String(def.name).get_slice(",", 0)

static func _rang(n: int, i: int, pas: float, centre: Vector2, y: float) -> Vector2:
	return Vector2(centre.x + (i - (n - 1) * 0.5) * pas, centre.y + y)

static func _bestiaire(g: Dictionary, c: Vector2, legendes: Array) -> void:
	var n := ARCHETYPES.size()
	for i in n:
		_poser(g, ARCHETYPES[i], _rang(n, i, 116.0, c, -225.0), {}, {}, _nom(g, ARCHETYPES[i]), legendes)
	for i in ELITES.size():
		_poser(g, ELITES[i][1], _rang(6, i, 175.0, c, -55.0), {"elite": ELITES[i][0]}, {}, "élite · " + _nom(g, ELITES[i][1]), legendes)
	for i in GARDIENS.size():
		_poser(g, GARDIENS[i], _rang(4, i, 255.0, c, 125.0), {"boss": true}, {}, _nom(g, GARDIENS[i], true), legendes)

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

## Les trois nouveaux, état par état. Dernier rang : un étendard debout et ses protégés (chevron,
## fil), puis un étendard étourdi dont les voisins ne sont plus couverts.
static func _nouveaux(g: Dictionary, c: Vector2, legendes: Array) -> void:
	for i in PAVOIS.size():
		_poser(g, "pavois", _rang(PAVOIS.size(), i, 170.0, c, -260.0), {}, PAVOIS[i][1], PAVOIS[i][0], legendes)
	for i in TRAQUEUR.size():
		_poser(g, "stalker", _rang(TRAQUEUR.size(), i, 150.0, c, -140.0), {}, TRAQUEUR[i][1], TRAQUEUR[i][0], legendes)
	for cote: float in [-1.0, 1.0]:
		var centre := c + Vector2(290.0 * cote, 150.0)
		var debout := cote < 0.0
		_poser(g, "banner", centre, {}, {} if debout else {"stun": 1.0}, "étendard debout : il protège" if debout else "étendard étourdi : plus rien", legendes)
		var voisins := ["brute", "imp", "archer", "pavois"]
		for i in voisins.size():
			var pos := centre + Vector2((i - 1.5) * 105.0, 95.0 if i == 1 or i == 2 else 40.0)
			_poser(g, voisins[i], pos, {}, {"hp": 0.7}, "protégé" if debout else "à découvert", legendes)

## Une pose du héros, choisie par D666_POSE :
##   coup:<phase>:<part>:<rang>   coup en cours (startup | active | recovery ; part 0..1 ; rang du combo)
##   frappe:<phase>:<part>        frappe de dash
##   dash | touche | elan | lancer | colere | sentence | nuee | repos
static func _pose_heros(g: Dictionary, c: Vector2) -> void:
	_poser(g, "brute", c + Vector2(70.0, -40.0), {}, {"hp": 0.6}, "", [])
	var h: Dictionary = g.player
	var mots := OS.get_environment("D666_POSE").split(":")
	h.facing = Vector2(70.0, -40.0).angle()
	match mots[0]:
		"coup", "frappe":
			_coup(g, mots)
		"dash":
			h.state = "dash"
			h.dashDirX = cos(h.facing)
			h.dashDirY = sin(h.facing)
			h.iframes = 0.1
		"touche":
			h.iframes = 0.4
		"elan":
			h.surge = 2.0
			h.surgeMult = 0.4
		"lancer":
			h.state = "cast"
			h.castT = 0.02
			h.castDirX = cos(h.facing)
			h.castDirY = sin(h.facing)
		"colere", "sentence", "nuee":
			h.state = "super"
			h.superClock = 0.45
			h.superStep = 1.0

static func _coup(g: Dictionary, mots: PackedStringArray) -> void:
	var h: Dictionary = g.player
	var frappe := mots[0] == "frappe"
	var rang := 0.0 if frappe or mots.size() < 4 else mots[3].to_float()
	var def: Dictionary = g.tuning.dashStrike if frappe else g.tuning.combo[int(rang)]
	var phase := "active" if mots.size() < 2 else mots[1]
	var dur := {"startup": def.startup, "active": def.active, "recovery": def.recovery}
	h.state = "attack"
	h.attack = {"def": def, "index": rang, "strike": frappe, "phase": phase, "t": dur[phase] * (0.5 if mots.size() < 3 else mots[2].to_float()),
		"dur": dur, "dirX": cos(h.facing), "dirY": sin(h.facing), "angle": h.facing, "hitIds": []}

## Foule de mesure : 40 ennemis des sept premiers archétypes, en grille (coût du dessin).
static func _foule(g: Dictionary, c: Vector2) -> void:
	for i in 40:
		var pos := c + Vector2((i % 8 - 3.5) * 70.0, ((i >> 3) - 2.5) * 70.0)
		_poser(g, ARCHETYPES[i % 7], pos, {}, {"hp": 0.5 if i % 3 == 0 else 1.0}, "", [])
