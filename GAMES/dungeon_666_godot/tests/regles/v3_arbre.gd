extends RefCounted
## COMBAT V3, étape 3 — l'ARBRE DE COMPÉTENCES (design/COMBAT_V3.md, sim/tree.gd, data/arbres.json).
## Expérience et niveaux de classe, points, étages, rangs, améliorations exclusives, passifs,
## respécialisation, migration du profil, kit en partie, déterminisme.
## Les nombres attendus sont LUS dans les données (jamais recopiés) : régler l'arbre ne casse pas
## ces tests, changer une règle si.

const Arbre = preload("res://sim/tree.gd")

const TOUTES := ["classes", "weapons", "skills", "gadgets"]
const CLASSES := ["revenant", "bourreau", "chasseresse"]
const LOIN := 2.5 # s : assez pour qu'une mèche, un piège, un totem ou un ancien Super ait agi
const PRES := 40.0 # u : la cible d'essai, juste devant le héros

## Un VRAI profil de joueur (relevé le 2026-10-04, réduit et anonyme : coffre et équipement
## abrégés). Il est au schéma 3 sur le disque ; la migration le porte au schéma courant.
const PROFIL_REEL := {
	"schema": 3.0, "bestFloor": 126.0, "checkpoints": [1.0, 19.0, 37.0, 55.0, 73.0, 91.0, 109.0, 127.0],
	"souls": 1183.0, "gold": 5047.0, "itemSeq": 29.0,
	"unlocked": {
		"classes": ["revenant", "bourreau", "chasseresse"], "weapons": ["lame", "hache", "arc", "dagues", "marteau"],
		"skills": ["lance", "bond", "volee", "chaine"], "gadgets": ["nova", "cri", "piege", "bombe"],
	},
	"upgrades": {"arsenal": 1.0, "avidite": 2.0, "celerite": 3.0, "ferocite": 4.0, "fortune": 3.0, "vitalite": 5.0},
	"loadout": {"classId": "bourreau", "gadgetId": "cri", "skillId": "bond"},
	"equipment": {
		"arme": {"slot": "arme", "weaponType": "hache", "rarity": "rare", "name": "Couperet", "level": 115.0, "uid": "i7", "affixes": [], "power": null, "base": {"damage": 77.7}, "score": 44.52},
		"armure": null, "talisman": null,
	},
	"stash": [],
	"guardians": {"cerbere": 3.0, "colosse": 1.0, "gardien": 2.0, "minos": 2.0},
	"stats": {"deaths": 3.0, "guardianKills": 8.0, "kills": 1598.0, "runs": 7.0},
}

static func tests(h) -> void:
	_tests_experience(h)
	_tests_arbre(h)
	_tests_rangs(h)
	_tests_choix(h)
	_tests_passifs(h)
	_tests_migration(h)
	_tests_partie(h)

# ---------------------------------------------------------------- outillage

static func _t() -> Dictionary:
	return D6Data.create_tuning()

static func _cfg() -> Dictionary:
	return D6Data.default_tuning().tree

## Profil d'un joueur qui possède les trois classes (rien d'autre), sur la classe demandée.
static func _profil(class_id: String) -> Dictionary:
	var t := _t()
	var p: Dictionary = D6Profile.new_profile(t)
	p.souls = 1e6
	for id in CLASSES:
		D6Profile.unlock(p, t, "classes", id)
	D6Profile.select_class(p, t, class_id)
	return p

## Profil d'essai en partie : tout possédé (chaque compétence a donc son rang 1 offert), niveau
## maximum, les rangs et améliorations demandés ({nœud: rang}, {nœud: amélioration}), trois emplacements.
static func _meta(class_id: String, slots: Array, rangs: Dictionary = {}, choix: Dictionary = {}) -> Dictionary:
	var t := _t()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in TOUTES:
		m.unlocked[k] = t[k].keys()
	m.loadout = {"classId": class_id, "slots": slots}
	m.equipment.arme = D6Profile.starter_weapon(t, t.classes[class_id].weapons[0])
	m.equipment.arme.uid = "i9000"
	var st: Dictionary = Arbre.state(m, class_id)
	st.level = _cfg().maxLevel
	for id in rangs:
		var n: Dictionary = Arbre.node(t, class_id, id)
		var achetes: float = rangs[id] - (1.0 if Arbre.is_free(m, t, n) else 0.0)
		if achetes > 0.0:
			st.ranks[id] = achetes
	st.choices = choix.duplicate()
	return m

## Salle vidée, héros au centre, jamais de critique (les montants attendus sont exacts).
static func _bac(h, class_id: String, slots: Array, rangs: Dictionary = {}, choix: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var o := {"seed": 7.0, "meta": _meta(class_id, slots, rangs, choix)}
	o.merge(opts, true)
	var g: Dictionary = h.bac_a_sable(o)
	g.tuning.combat.critChance = 0.0
	return g

## Ennemi d'essai : ne riposte pas, ne bouge pas (étourdi), increvable par défaut.
static func _cible(g: Dictionary, dx: float, dy: float, masse: float = 1000.0) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, "brute", g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.cooldown = 999.0
	e.maxHp = 50000.0
	e.hp = 50000.0
	e.mass = masse
	e.stun = 999.0
	return e

## Appuie sur l'emplacement 0 en visant à droite, puis laisse passer `secondes`. Rend les événements.
static func _lancer(h, g: Dictionary, secondes: float = LOIN) -> Array:
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	evs.append_array(h.avancer(g, h.ticks(secondes)))
	return evs

static func _de(evs: Array, type: String) -> Array:
	return evs.filter(func(ev): return ev.type == type)

static func _coups(evs: Array) -> Array:
	return evs.filter(func(ev): return ev.type == "hit").map(func(ev): return ev.amount)

## Dégâts qu'un coup de `montant` inflige à la cible d'essai (elle est étourdie : dégâts majorés).
static func _sur_cible(g: Dictionary, montant: float) -> float:
	return maxf(1.0, D6Js.jround(montant * g.tuning.combat.stunDamageTakenMult))

static func _zones(g: Dictionary, kind: String) -> Array:
	return D6KitZones.zones_of(g, kind)

static func _dist(g: Dictionary, e: Dictionary) -> float:
	return sqrt(D6Geo.dist2(g.player.x, g.player.y, e.x, e.y))

## Les nœuds d'une sorte de l'arbre d'une classe.
static func _noeuds(class_id: String, kind: String) -> Array:
	return Arbre.nodes(D6Data.default_tuning(), class_id).filter(func(n): return n.kind == kind)

# ---------------------------------------------------------------- expérience, niveaux, points

static func _tests_experience(h) -> void:
	h.test("expérience : un ennemi tué, un élite, un Gardien versent au profil ce que disent les données", func(): _x_sources(h))
	h.test("expérience : elle grandit avec la profondeur, jamais au-delà du plafond", func(): _x_profondeur(h))
	h.test("expérience : rien en arène d'essai, rien à l'entraînement, rien pour une invocation", func(): _x_rien(h))
	h.test("niveaux : la courbe des données, un point par niveau, l'événement levelUp, un plafond", func(): _x_niveaux(h))
	h.test("Gardien : un point de plus la PREMIÈRE fois avec la classe, pas la seconde ni pour une autre classe", func(): _x_gardien(h))
	h.test("bilan : la mort dit l'expérience gagnée et les niveaux passés ; elle est déjà au profil", func(): _x_bilan(h))

static func _tuer(g: Dictionary, elite: bool = false, opts: Dictionary = {}) -> void:
	var o := {"spawnT": 0.0}
	o.merge(opts, true)
	var e: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x + 200.0, g.player.y, o)
	if elite:
		e.eliteMod = "blinde"
	D6Combat.kill_enemy(g, e)

static func _x_sources(h) -> void:
	var xp: Dictionary = _cfg().xp
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	var st: Dictionary = g.meta.tree.revenant
	h.egal([st.level, st.xp], [1.0, 0.0], "profil neuf : niveau 1, aucune expérience")
	_tuer(g)
	h.egal(st.xp, xp.kill, "un ennemi tué")
	_tuer(g, true)
	h.egal(st.xp, xp.kill + xp.elite, "un élite")
	h.egal(g.telemetry.xpEarned, xp.kill + xp.elite, "la descente compte ce qu'elle a gagné")
	h.ok(xp.kill < xp.elite and xp.elite < xp.guardian, "plus pour un élite, beaucoup pour un Gardien")
	# Le Gardien : par la vraie règle de fin de salle.
	var gb: Dictionary = h.partie({"seed": 5.0, "startFloor": gb_etage()})
	h.avancer(gb, h.ticks(gb.tuning.guardians.spawnTime) + 2)
	var boss: Dictionary = gb.enemies.filter(func(e): return D6Js.truthy(e.get("boss")))[0]
	D6Combat.kill_enemy(gb, boss)
	var fin: Array = h.avancer(gb, h.ticks(3.0))
	h.egal(_de(fin, "checkpoint").size(), 1, "le Gardien est vaincu")
	h.egal(gb.meta.tree.revenant.xp + _niveaux_passes(gb.meta.tree.revenant.level), xp.guardian, "un Gardien (section 1)")

static func gb_etage() -> float:
	return D6Data.default_tuning().floors.sectionLength

## Expérience avalée par les niveaux déjà passés (pour comparer un total).
static func _niveaux_passes(level: float) -> float:
	var total := 0.0
	var n := 1.0
	while n < level:
		total += Arbre.xp_need(D6Data.default_tuning(), n)
		n += 1.0
	return total

static func _x_profondeur(h) -> void:
	var c := _cfg()
	var longueur: float = D6Data.default_tuning().floors.sectionLength
	var vus: Array = []
	for section in [1.0, 3.0, 8.0, 30.0]:
		var g: Dictionary = h.bac_a_sable({"seed": 3.0, "startFloor": (section - 1.0) * longueur + 1.0})
		_tuer(g, true)
		var attendu: float = D6Js.jround(c.xp.elite * minf(c.xp.depthCap, 1.0 + c.xp.depthStep * (section - 1.0)))
		h.egal(g.meta.tree.revenant.xp, attendu, "élite en section %s" % D6Js.num_str(section))
		vus.append(attendu)
	h.ok(vus[0] < vus[1] and vus[1] < vus[2], "plus profond, plus d'expérience")
	h.egal(vus[3], D6Js.jround(c.xp.elite * c.xp.depthCap), "en section 30 : le plafond")
	# Borné : même au plafond, il faut plusieurs élites pour le premier niveau, et bien plus ensuite.
	h.ok(c.xp.elite * c.xp.depthCap < Arbre.xp_need(D6Data.default_tuning(), 1.0), "un élite profond ne donne pas un niveau entier")
	h.ok(c.xp.guardian * c.xp.depthCap < Arbre.xp_need(D6Data.default_tuning(), 1.0) * 10.0, "un Gardien profond ne donne pas dix niveaux")

static func _x_rien(h) -> void:
	for mode in ["sandbox", "practice"]:
		var g: Dictionary = h.bac_a_sable({"seed": 3.0, mode: true, "startFloor": gb_etage() if mode == "practice" else 1.0})
		_tuer(g)
		_tuer(g, true)
		Arbre.gain(g, "guardian")
		Arbre.guardian_down(g, "gardien")
		h.egal([g.meta.tree.revenant.xp, g.meta.tree.revenant.level, g.meta.tree.revenant.guardians, g.telemetry.xpEarned], [0.0, 1.0, [], 0.0], mode)
	var g2: Dictionary = h.bac_a_sable({"seed": 3.0})
	_tuer(g2, false, {"summoned": true})
	h.egal(g2.meta.tree.revenant.xp, 0.0, "une invocation ne rapporte rien (comme pour les Âmes)")

static func _x_niveaux(h) -> void:
	var t := _t()
	var c := _cfg()
	h.egal(Arbre.xp_need(t, 1.0), c.curve.base, "niveau 1 → 2")
	h.egal(Arbre.xp_need(t, 4.0), c.curve.base + 3.0 * c.curve.perLevel, "niveau 4 → 5")
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	var st: Dictionary = g.meta.tree.revenant
	st.xp = Arbre.xp_need(t, 1.0) - c.xp.kill
	g.events.clear()
	_tuer(g)
	var ups: Array = _de(g.events, "levelUp")
	h.egal(ups.size(), 1, "un événement levelUp")
	h.egal([st.level, st.xp], [2.0, 0.0], "niveau 2, l'expérience repart de zéro")
	h.egal([ups[0].get("level"), ups[0].get("levels"), ups[0].get("points"), ups[0].get("classId")], [2.0, 1.0, c.pointsPerLevel, "revenant"])
	h.egal(D6Profile.tree_view(g.meta, t, "revenant").points, c.pointsPerLevel, "un point par niveau")
	h.egal(g.telemetry.levelsGained, 1.0)
	# Plusieurs niveaux d'un coup, puis le plafond.
	var seul := Arbre.new_state()
	h.egal(Arbre.add_xp(seul, t, Arbre.xp_need(t, 1.0) + Arbre.xp_need(t, 2.0) + 3.0), 2.0, "deux niveaux d'un coup")
	h.egal([seul.level, seul.xp], [3.0, 3.0])
	h.egal(Arbre.add_xp(seul, t, 1e9), c.maxLevel - 3.0, "jusqu'au niveau maximum")
	h.egal([seul.level, seul.xp], [c.maxLevel, 0.0], "au plafond, l'expérience ne s'accumule plus")
	var vue: Dictionary = Arbre.view({"tree": {"revenant": seul}, "unlocked": D6Profile.new_profile(t).unlocked, "gold": 0.0}, t, "revenant")
	h.egal([vue.level, vue.xpNext, vue.points], [c.maxLevel, 0.0, (c.maxLevel - 1.0) * c.pointsPerLevel])

static func _x_gardien(h) -> void:
	var c := _cfg()
	var g: Dictionary = h.bac_a_sable({"seed": 3.0, "meta": _profil("revenant")})
	g.events.clear()
	Arbre.guardian_down(g, "gardien")
	h.egal(g.meta.tree.revenant.guardians, ["gardien"])
	h.egal(_de(g.events, "treePoint").size(), 1, "événement treePoint")
	h.egal(Arbre.points(g.meta, g.tuning, "revenant"), c.pointsPerGuardian, "un point")
	Arbre.guardian_down(g, "gardien")
	h.egal(Arbre.points(g.meta, g.tuning, "revenant"), c.pointsPerGuardian, "la seconde fois : rien")
	Arbre.guardian_down(g, "cerbere")
	h.egal(Arbre.points(g.meta, g.tuning, "revenant"), 2.0 * c.pointsPerGuardian, "un autre Gardien : un autre point")
	h.egal(Arbre.points(g.meta, g.tuning, "bourreau"), 0.0, "les points sont ceux de la classe jouée")
	D6Profile.select_class(g.meta, g.tuning, "bourreau")
	var g2: Dictionary = h.bac_a_sable({"seed": 3.0, "meta": g.meta})
	Arbre.guardian_down(g2, "gardien")
	h.egal(g2.meta.tree.bourreau.guardians, ["gardien"], "le même Gardien compte de nouveau avec une AUTRE classe")

static func _x_bilan(h) -> void:
	var t := _t()
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.meta.tree.revenant.xp = Arbre.xp_need(t, 1.0) - 1.0
	_tuer(g)
	_tuer(g)
	D6Run.on_death(g)
	var bilan: Dictionary = g.run.deathRecap.tree
	h.egal(bilan.keys(), ["classId", "xpEarned", "levelsGained", "level", "points"])
	h.egal([bilan.classId, bilan.xpEarned, bilan.levelsGained, bilan.level, bilan.points], ["revenant", 2.0 * _cfg().xp.kill, 1.0, 2.0, _cfg().pointsPerLevel])
	h.egal(D6Run.tree_recap(g), bilan, "la même lecture hors de la mort (victoire, retour en Ville)")
	# Versée comme les Âmes : le profil de la partie la porte déjà, la mort ne reprend rien.
	h.egal([g.meta.tree.revenant.level, g.meta.tree.revenant.xp], [2.0, 1.0])
	var relu: Dictionary = D6Profile.sanitize_profile(D6Js.clone(g.meta), t)
	h.egal(relu.tree, g.meta.tree, "relu du disque : identique")

# ---------------------------------------------------------------- l'arbre dans la Ville

static func _tests_arbre(h) -> void:
	h.test("tree_view : niveau, points, étages et nœuds, dans la forme annoncée", func(): _a_vue(h))
	h.test("étages : l'étage suivant s'ouvre quand assez de points sont dépensés dans la classe", func(): _a_etages(h))
	h.test("tree_buy : refuse sans point, étage fermé, rang maximal, nœud inconnu ; un refus ne change rien", func(): _a_refus(h))
	h.test("tree_buy : le rang 1 débloque la compétence, qui devient plaçable dans un emplacement", func(): _a_debloque(h))
	h.test("tree_choose : offert au rang des données, l'une OU l'autre, jamais les deux", func(): _a_choix(h))
	h.test("tree_respec : rend tous les points contre de l'or, vide les emplacements redevenus verrouillés", func(): _a_respec(h))

## Donne `n` points à dépenser à la classe (des niveaux).
static func _points(p: Dictionary, class_id: String, n: float) -> void:
	Arbre.state(p, class_id).level = 1.0 + n / _cfg().pointsPerLevel

static func _acheter(h, p: Dictionary, class_id: String, node_id: String, fois: int) -> void:
	for i in fois:
		h.egal(D6Profile.tree_buy(p, _t(), class_id, node_id), {"ok": true}, "%s, achat %d" % [node_id, i + 1])

static func _noeud_vu(p: Dictionary, class_id: String, node_id: String) -> Dictionary:
	for tier in D6Profile.tree_view(p, _t(), class_id).tiers:
		for n in tier.nodes:
			if n.id == node_id:
				return n
	return {}

static func _a_vue(h) -> void:
	var t := _t()
	var c := _cfg()
	for class_id in CLASSES:
		var p := _profil(class_id)
		var v: Dictionary = D6Profile.tree_view(p, t, class_id)
		h.egal(v.keys(), ["level", "maxLevel", "xp", "xpNext", "points", "spent", "choiceRank", "tiers", "respecCost"], class_id)
		h.egal([v.level, v.xp, v.xpNext, v.points, v.spent], [1.0, 0.0, c.curve.base, 0.0, 0.0], "%s : départ" % class_id)
		h.egal(v.tiers.map(func(x): return [x.name, x.need]), c.tiers.map(func(x): return [x.name, x.need]), "%s : les étages des données" % class_id)
		var vus := 0
		for tier in v.tiers:
			for n in tier.nodes:
				vus += 1
				h.egal(n.keys(), ["id", "kind", "name", "icon", "text", "now", "next", "rank", "maxRank", "free", "canBuy", "reason", "choices"], "%s/%s" % [class_id, n.id])
				h.ok(n.name != "" and n.text != "" and not ("{" in n.text), "%s/%s : nom et texte lisibles (%s)" % [class_id, n.id, n.text])
				h.egal(n.canBuy, false, "%s/%s : sans point, rien ne s'achète" % [class_id, n.id])
				h.ok(n.reason != "", "%s/%s : le refus dit pourquoi" % [class_id, n.id])
				for ch in n.choices:
					h.egal(ch.keys(), ["id", "name", "text", "taken", "canTake", "reason"])
					h.ok(not ("{" in ch.text), "%s/%s/%s : texte chiffré (%s)" % [class_id, n.id, ch.id, ch.text])
		h.egal(vus, Arbre.nodes(t, class_id).size(), "%s : tous les nœuds sont montrés" % class_id)
		var cl: Dictionary = t.classes[class_id]
		for id in [cl.skills[0], cl.gadgets[0]]:
			var n := _noeud_vu(p, class_id, id)
			h.egal([n.rank, n.free], [1.0, true], "%s : %s, le départ, a son rang 1 offert" % [class_id, id])

static func _a_etages(h) -> void:
	var t := _t()
	var c := _cfg()
	var p := _profil("revenant")
	_points(p, "revenant", 29.0)
	h.egal(D6Profile.tree_view(p, t, "revenant").tiers.map(func(x): return x.open), [true, false, false, false], "au départ : la base seule")
	var besoins: Array = c.tiers.map(func(x): return x.need)
	h.ok(besoins[0] == 0.0 and besoins[1] > 0.0 and besoins[1] < besoins[2] and besoins[2] < besoins[3], "seuils croissants : %s" % str(besoins))
	# On dépense dans la base jusqu'au seuil du cœur, pas un point de moins.
	var bases: Array = Arbre.nodes(t, "revenant").filter(func(n): return n.tier == 0.0)
	var depense := 0.0
	for n in bases:
		while depense < besoins[1] and D6Js.truthy(D6Profile.tree_buy(p, t, "revenant", n.id).ok):
			depense += 1.0
			h.egal(Arbre.tier_open(p, t, "revenant", 1.0), depense >= besoins[1], "%s points dépensés" % D6Js.num_str(depense))
	h.egal(depense, besoins[1])
	h.egal(D6Profile.tree_view(p, t, "revenant").tiers.map(func(x): return x.open), [true, true, false, false])
	# Les points OFFERTS (rang 1 du départ) ne comptent pas dans la dépense.
	h.egal(D6Profile.tree_view(p, t, "revenant").spent, besoins[1])

static func _a_refus(h) -> void:
	var t := _t()
	var p := _profil("revenant")
	var avant: Dictionary = D6Js.clone(p)
	h.egal(D6Profile.tree_buy(p, t, "revenant", "lance"), {"ok": false, "reason": "aucun point à dépenser"})
	h.egal(D6Profile.tree_buy(p, t, "revenant", "introuvable"), {"ok": false, "reason": "inconnu"})
	h.egal(D6Profile.tree_buy(p, t, "introuvable", "lance"), {"ok": false, "reason": "inconnu"})
	h.egal(D6Profile.tree_buy(p, t, "revenant", "bond"), {"ok": false, "reason": "inconnu"}, "le nœud d'une autre classe")
	h.egal(p, avant, "un refus ne change rien")
	_points(p, "revenant", 29.0)
	var ferme: Dictionary = D6Profile.tree_buy(p, t, "revenant", "chaine")
	h.ok(not ferme.ok and "étage" in ferme.reason and D6Js.num_str(_cfg().tiers[1].need) in ferme.reason, "étage fermé : %s" % ferme.reason)
	_acheter(h, p, "revenant", "lance", int(_cfg().skillRanks) - 1)
	h.egal(D6Profile.tree_buy(p, t, "revenant", "lance"), {"ok": false, "reason": "rang maximal"})
	h.egal(_noeud_vu(p, "revenant", "lance").rank, _cfg().skillRanks)
	h.egal(D6Profile.tree_view(p, t, "revenant").points, 29.0 - (_cfg().skillRanks - 1.0), "chaque rang acheté coûte un point")
	# Une classe que le profil ne possède pas.
	var seul: Dictionary = D6Profile.new_profile(t)
	h.egal(D6Profile.tree_buy(seul, t, "bourreau", "bond"), {"ok": false, "reason": "inconnu"})

static func _a_debloque(h) -> void:
	var t := _t()
	var p := _profil("revenant")
	_points(p, "revenant", 29.0)
	h.egal(D6Profile.select_slot(p, t, 2.0, "chaine"), {"ok": false, "reason": "indisponible"}, "verrouillée : pas plaçable")
	h.egal(D6Profile.unlock(p, t, "skills", "chaine"), {"ok": false, "reason": "se débloque dans l'arbre"}, "plus de déblocage en Âmes")
	_acheter(h, p, "revenant", "sang_vif", 3)
	_acheter(h, p, "revenant", "nova", 2)
	_acheter(h, p, "revenant", "chaine", 1)
	h.egal(_noeud_vu(p, "revenant", "chaine").rank, 1.0)
	h.ok(D6Profile.slot_choices(p, t).filter(func(x): return x.id == "chaine")[0].unlocked, "slot_choices la dit débloquée")
	h.egal(D6Profile.select_slot(p, t, 2.0, "chaine"), {"ok": true}, "rang 1 : plaçable")
	var g: Dictionary = D6Game.create_game({"seed": 4.0, "meta": p})
	h.egal(g.kit.slots, ["lance", "nova", "chaine"], "et jouée à la partie suivante")
	# La même Chaîne n'est PAS débloquée pour le Bourreau : chaque classe a son arbre.
	D6Profile.select_class(p, t, "bourreau")
	h.ok(not D6Profile.slot_choices(p, t).filter(func(x): return x.id == "chaine")[0].unlocked, "l'arbre du Bourreau est à part")

static func _a_choix(h) -> void:
	var t := _t()
	var rang: float = _cfg().choiceRank
	var p := _profil("revenant")
	_points(p, "revenant", 29.0)
	var n: Dictionary = Arbre.node(t, "revenant", "lance")
	h.egal(n.choices.size(), 2, "deux améliorations")
	var a: String = n.choices[0].id
	var b: String = n.choices[1].id
	h.egal(D6Profile.tree_choose(p, t, "revenant", "lance", a), {"ok": false, "reason": "rang %s requis" % D6Js.num_str(rang)}, "pas avant le rang du choix")
	_acheter(h, p, "revenant", "lance", int(rang) - 1)
	h.egal(_noeud_vu(p, "revenant", "lance").choices.map(func(x): return [x.taken, x.canTake]), [[false, true], [false, true]], "offertes toutes les deux")
	h.egal(D6Profile.tree_choose(p, t, "revenant", "lance", "introuvable"), {"ok": false, "reason": "inconnu"})
	h.egal(D6Profile.tree_choose(p, t, "revenant", "lance", a), {"ok": true})
	h.egal(D6Profile.tree_choose(p, t, "revenant", "lance", b), {"ok": false, "reason": "l'autre amélioration est prise"}, "exclusives")
	h.egal(D6Profile.tree_choose(p, t, "revenant", "lance", a), {"ok": false, "reason": "déjà prise"})
	h.egal(_noeud_vu(p, "revenant", "lance").choices.map(func(x): return [x.taken, x.canTake]), [[true, false], [false, false]])
	h.egal(p.tree.revenant.choices, {"lance": a})
	h.egal(D6Profile.tree_view(p, t, "revenant").points, 29.0 - (rang - 1.0), "le choix ne coûte aucun point")

static func _a_respec(h) -> void:
	var t := _t()
	var r: Dictionary = _cfg().respec
	var p := _profil("revenant")
	h.egal(D6Profile.tree_respec(p, t, "revenant"), {"ok": false, "reason": "rien à rendre"})
	_points(p, "revenant", 29.0)
	_acheter(h, p, "revenant", "sang_vif", 3)
	_acheter(h, p, "revenant", "lance", 2)
	_acheter(h, p, "revenant", "chaine", 1)
	D6Profile.tree_choose(p, t, "revenant", "lance", "explose")
	D6Profile.select_slot(p, t, 2.0, "chaine")
	var prix: float = r.base + r.perPoint * 6.0
	h.egal(D6Profile.tree_view(p, t, "revenant").respecCost, prix, "prix : base + par point dépensé")
	p.gold = prix - 1.0
	h.egal(D6Profile.tree_respec(p, t, "revenant"), {"ok": false, "reason": "or insuffisant"})
	h.egal(p.tree.revenant.ranks.size(), 3, "un refus ne rend rien")
	p.gold = prix + 7.0
	h.egal(D6Profile.tree_respec(p, t, "revenant"), {"ok": true})
	h.egal(p.gold, 7.0, "l'or est payé")
	h.egal([p.tree.revenant.ranks, p.tree.revenant.choices], [{}, {}], "rangs achetés et amélioration rendus")
	h.egal(D6Profile.tree_view(p, t, "revenant").points, 29.0, "tous les points reviennent")
	h.egal(p.tree.revenant.level, 30.0, "le niveau reste")
	h.egal(p.loadout.slots, ["lance", "nova", null], "l'emplacement de la Chaîne, redevenue verrouillée, est VIDÉ")
	h.egal(_noeud_vu(p, "revenant", "lance").rank, 1.0, "le rang offert du départ reste")
	h.egal(D6Profile.tree_respec(p, t, "bourreau").ok, false, "une classe sans rien à rendre")

# ---------------------------------------------------------------- rangs des compétences, en partie

static func _tests_rangs(h) -> void:
	for class_id in CLASSES:
		for n in _noeuds(class_id, "skill"):
			h.test("rangs : %s / %s — chaque rang change EN JEU les nombres que disent les données" % [class_id, n.skill], func(): _r_competence(h, class_id, n))
	h.test("rangs : un arbre vide laisse les réglages de la partie tels que dans les données", func(): _r_vide(h))
	h.test("rangs : l'arbre ne touche que la classe jouée ; les textes de tree_view citent les nombres", func(): _r_textes(h))

## Nombre de base (rang 1) d'un champ d'une compétence : le sien, ou celui de l'ancien Super qu'elle joue.
static func _base(n: Dictionary, field: String):
	var t: Dictionary = D6Data.default_tuning()
	var def: Dictionary = t[Arbre.table_of(t, n.skill)][n.skill]
	if def.has(field):
		return def[field]
	return t.supers[def["super"]].get(field) if def.has("super") else null

static func _attendu(n: Dictionary, field: String, rang: float):
	var v = Arbre.rank_value(n, field, rang)
	return _base(n, field) if v == null else v

static func _r_competence(h, class_id: String, n: Dictionary) -> void:
	for rang in range(1, int(_cfg().skillRanks) + 1):
		var g := _bac(h, class_id, [n.skill, null, null], {n.id: float(rang)})
		var def: Dictionary = D6Loadout.slot_def(g, 0)
		var e := _cible(g, PRES, 0.0)
		var charges: float = g.player.slots[0].charges
		var evs: Array = h.avancer(g, 1, {"skill1Pressed": true}) # visée assistée : sur la cible
		var recharge: float = g.player.slots[0].cd
		var canal = g.player.get("channel")
		var tirs: Array = []
		for i in h.ticks(LOIN):
			evs.append_array(h.avancer(g, 1))
			if tirs.is_empty():
				tirs = D6KitCommon.kit_store(g).shots.duplicate()
		for field in n.ranks:
			var v = _attendu(n, field, float(rang))
			var ou := "%s/%s rang %d, %s" % [class_id, n.skill, rang, field]
			if def.kind != "canal" or def.has(field):
				h.egal(def.get(field), v, "%s : réglage de la partie" % ou)
			_r_effet(h, g, {"field": field, "v": v, "ou": ou, "evs": evs, "e": e, "charges": charges, "recharge": recharge, "tirs": tirs, "canal": canal, "def": def})

## L'effet RÉEL d'un nombre de rang, lu dans ce que la partie a fait.
static func _r_effet(h, g: Dictionary, x: Dictionary) -> void:
	var coups: Array = _coups(x.evs)
	match x.field:
		"cooldown":
			h.proche(x.recharge, x.v * g.player.stats.skillCooldownMult, 1e-9, "%s : recharge posée au lancer" % x.ou)
		"chargesPerSection":
			h.egal(x.charges, x.v, "%s : charges au départ" % x.ou)
		"damage", "damagePerTick":
			h.ok(coups.has(_sur_cible(g, x.v)), "%s : un coup de %s parmi %s" % [x.ou, str(_sur_cible(g, x.v)), str(coups)])
		"damageMult":
			var mult: float = 1.0 if x.v == null else x.v # rang 1 : la Sentence telle quelle
			var frappes: Array = x.canal.strikes.map(func(s): return _sur_cible(g, s.damage * mult))
			h.egal(coups, frappes, "%s : les trois coups de la Sentence" % x.ou)
		"radius":
			h.egal(_de(x.evs, "gadget")[0].r, x.v, "%s : rayon de l'effet" % x.ou)
		"range":
			h.egal(x.tirs[0].range, x.v, "%s : portée du crochet" % x.ou)
		"vulnMult":
			h.egal(x.e.vulnMult, x.v, "%s : vulnérabilité posée" % x.ou)
		"stun", "burnDps", "life":
			h.ok(x.evs.size() > 0, x.ou)
			_r_zone(h, g, x)
		_:
			h.ok(false, "%s : champ de rang sans vérification en jeu" % x.ou)

## Nombres portés par une zone posée (piège, pot, totem) : lus sur la zone, ou sur son effet.
static func _r_zone(h, g: Dictionary, x: Dictionary) -> void:
	match x.field:
		"stun":
			h.ok(_de(x.evs, "explode").size() >= 1, "%s : le piège s'est refermé" % x.ou)
			h.egal(x.def.stun, x.v, x.ou)
		"burnDps":
			var feux: Array = _zones(g, "brasier")
			h.ok(feux.size() == 1 and feux[0].burnDps == x.v and x.e.burnDps == x.v, "%s : le sol brûle à %s (%s)" % [x.ou, str(x.v), str(x.e.burnDps)])
		"life":
			var totems: Array = _zones(g, "totem")
			h.ok(totems.size() == 1 and totems[0].life == x.v, "%s : totem posé pour %s s" % [x.ou, str(x.v)])

static func _r_vide(h) -> void:
	var base: Dictionary = D6Data.default_tuning()
	for class_id in CLASSES:
		var c: Dictionary = base.classes[class_id]
		var g: Dictionary = D6Game.create_game({"seed": 9.0, "meta": _profil(class_id)})
		for table in ["skills", "gadgets", "supers", "moves"]:
			h.egal(g.tuning[table], base[table], "%s : %s inchangés" % [class_id, table])
		# Le rang 1 seul (tout possédé, rien d'acheté) ne change rien non plus.
		var g1 := _bac(h, class_id, [c.skills[0], c.gadgets[0], c.skills[1]])
		for table in ["skills", "gadgets", "supers"]:
			h.egal(g1.tuning[table], base[table], "%s, rang 1 partout : %s inchangés" % [class_id, table])
		h.egal(g1.player.stats, D6Game.create_game({"seed": 7.0, "meta": _meta(class_id, [c.skills[0], c.gadgets[0], c.skills[1]])}).player.stats)

static func _r_textes(h) -> void:
	var t := _t()
	# Le Bourreau joue avec SA Chaîne au rang 1, même si celle du Revenant est au rang 5.
	var m := _meta("bourreau", ["chaine", null, null])
	Arbre.state(m, "revenant").level = _cfg().maxLevel
	Arbre.state(m, "revenant").ranks.chaine = 4.0
	var g: Dictionary = h.bac_a_sable({"seed": 7.0, "meta": m})
	h.egal(g.tuning.skills.chaine, D6Data.default_tuning().skills.chaine, "la Chaîne du Bourreau reste au rang 1")
	for class_id in CLASSES:
		for n in _noeuds(class_id, "skill"):
			for rang in range(2, int(_cfg().skillRanks) + 1):
				var texte: String = Arbre.rank_text(t, class_id, n, float(rang))
				for field in n.ranks:
					var v: float = _attendu(n, field, float(rang))
					h.ok(Arbre.fr(v * 100.0 if _cfg().pctFields.has(field) else v) in texte, "%s/%s rang %d : « %s » cite %s" % [class_id, n.id, rang, texte, str(v)])

# ---------------------------------------------------------------- améliorations exclusives

static func _tests_choix(h) -> void:
	h.test("amélioration : sans le rang du choix, elle n'est ni prise ni appliquée", func(): _c_rang(h))
	h.test("Lance : « transperce tout » traverse une file entière ; « explose » souffle autour du premier touché", func(): _c_lance(h))
	h.test("Nova : « aspiration » attire au lieu de repousser ; « sol en feu » laisse un brasier", func(): _c_nova(h))
	h.test("Chaîne : « ferrage » rend vulnérable ; « traversante » traverse et étourdit sans tirer", func(): _c_chaine(h))
	h.test("Bombe : « grappe » en lance trois ; « fumigène » étourdit longtemps sans blesser", func(): _c_bombe(h))
	h.test("Tourbillon de colère : « œil du cyclone » aspire ; « soif » soigne à chaque ennemi touché", func(): _c_colere(h))
	h.test("Bond : « double saut » rend le suivant prêt aussitôt, une fois ; « onde de choc » frappe plus large", func(): _c_bond(h))
	h.test("Cri : « cri de guerre » galvanise le héros ; « terreur » repousse", func(): _c_cri(h))
	h.test("Triple sentence : « verdict » frappe une seule fois, vite ; « dîme de sang » soigne", func(): _c_sentence(h))
	h.test("Volée : « rafale droite » part serrée et traverse ; « tempête » tire neuf épines en large", func(): _c_volee(h))
	h.test("Piège : « explosif » souffle large ; « champ de pièges » en pose trois par charge", func(): _c_piege(h))
	h.test("Brasier : « poix » ralentit dans les flammes ; « pot explosif » étourdit sans laisser de feu", func(): _c_brasier(h))
	h.test("Totem : « foudre » frappe fort sans ralentir ; « gardien » efface les tirs ennemis", func(): _c_totem(h))
	h.test("Nuée : « acharnement » vise une seule cible ; « averse » en arrose six, plus vite", func(): _c_nuee(h))

## Le `set` d'une amélioration, lu dans les données.
static func _reglage(class_id: String, node_id: String, choice_id: String) -> Dictionary:
	for ch in Arbre.node(D6Data.default_tuning(), class_id, node_id).choices:
		if ch.id == choice_id:
			return ch.set
	return {}

## Partie avec la compétence `id` au rang du choix et l'amélioration `choix` prise ("" : aucune).
static func _avec(h, class_id: String, id: String, choix: String) -> Dictionary:
	return _bac(h, class_id, [id, null, null], {id: _cfg().choiceRank}, {id: choix} if choix != "" else {})

static func _c_rang(h) -> void:
	var g := _bac(h, "revenant", ["lance", null, null], {"lance": _cfg().choiceRank - 1.0}, {"lance": "transperce"})
	h.egal(g.meta.tree.revenant.choices, {}, "relue du profil : une amélioration sans son rang est écartée")
	h.egal(g.tuning.skills.lance.pierce, D6Data.default_tuning().skills.lance.pierce, "et rien n'est appliqué")
	var g2 := _avec(h, "revenant", "lance", "transperce")
	h.egal(g2.tuning.skills.lance.pierce, _reglage("revenant", "lance", "transperce").pierce, "au rang du choix : appliquée")

static func _c_lance(h) -> void:
	var base: Dictionary = D6Data.default_tuning().skills.lance
	var s := _reglage("revenant", "lance", "transperce")
	var g := _avec(h, "revenant", "lance", "transperce")
	var file: int = int(base.pierce) + 3
	for i in file:
		_cible(g, 60.0 + 45.0 * i, 0.0)
	h.egal(_coups(_lancer(h, g, 1.5)).size(), file, "les %d ennemis de la file sont touchés (sans l'amélioration : %d)" % [file, int(base.pierce) + 1])
	h.ok(s.pierce > base.pierce and s.range > base.range)
	var x := _reglage("revenant", "lance", "explose")
	var g2 := _avec(h, "revenant", "lance", "explose")
	var premier := _cible(g2, 80.0, 0.0)
	var a_cote := _cible(g2, 80.0, x.blastRadius - 30.0)
	var derriere := _cible(g2, 80.0 + x.blastRadius + 80.0, 0.0)
	var evs := _lancer(h, g2, 1.5)
	h.egal(_de(evs, "explode").map(func(ev): return [ev.kind, ev.r]), [["lance", x.blastRadius]], "une explosion, au rayon des données")
	h.egal(a_cote.maxHp - a_cote.hp, _sur_cible(g2, x.blastDamage), "l'ennemi à côté prend le souffle")
	h.egal(premier.maxHp - premier.hp, _sur_cible(g2, g2.tuning.skills.lance.damage) + _sur_cible(g2, x.blastDamage), "le premier : la lance, puis le souffle")
	h.egal(derriere.hp, derriere.maxHp, "la lance s'arrête là : celui de derrière n'est pas touché")

static func _c_nova(h) -> void:
	var g0 := _avec(h, "revenant", "nova", "")
	var loin0 := _cible(g0, 110.0, 0.0, 1.0)
	_lancer(h, g0, 0.6)
	h.ok(_dist(g0, loin0) > 110.0, "sans amélioration, la nova repousse")
	var s := _reglage("revenant", "nova", "attire")
	var g := _avec(h, "revenant", "nova", "attire")
	var e := _cible(g, 110.0, 0.0, 1.0)
	_lancer(h, g, 0.6)
	h.proche(_dist(g, e), g.player.r + e.r + s.pullGap, 3.0, "« aspiration » : l'ennemi finit contre le héros")
	var f := _reglage("revenant", "nova", "feu")
	var g2 := _avec(h, "revenant", "nova", "feu")
	var e2 := _cible(g2, 60.0, 0.0)
	_lancer(h, g2, 0.5)
	var feux: Array = _zones(g2, "brasier")
	h.egal(feux.map(func(z): return [z.r, z.duration, z.burnDps]), [[g2.tuning.gadgets.nova.radius, f.fireDuration, f.fireDps]], "un sol en feu, au rayon de la nova")
	h.egal(e2.burnDps, f.fireDps, "l'ennemi qui y reste brûle")
	h.avancer(g2, h.ticks(f.fireDuration))
	h.egal(_zones(g2, "brasier").size(), 0, "le feu s'éteint après sa durée")
	h.egal(_zones(g0, "brasier").size(), 0, "sans amélioration : aucun feu")

static func _c_chaine(h) -> void:
	var s := _reglage("revenant", "chaine", "ferrage")
	var g := _avec(h, "revenant", "chaine", "ferrage")
	var e := _cible(g, 150.0, 0.0)
	_lancer(h, g, 0.5)
	h.egal(e.vulnMult, s.vulnMult, "« ferrage » : vulnérable")
	h.ok(e.vuln > s.vuln - 0.6 and e.vuln <= s.vuln, "pour la durée des données (%s)" % str(e.vuln))
	var x := _reglage("bourreau", "chaine", "traversante")
	var g2 := _avec(h, "bourreau", "chaine", "traversante")
	var a := _cible(g2, 120.0, 0.0, 1.0)
	var b := _cible(g2, 220.0, 0.0, 1.0)
	a.stun = 0.0
	b.stun = 0.0
	var evs := _lancer(h, g2, 0.4)
	h.egal(_coups(evs).size(), 2, "« traversante » : les deux ennemis de la file sont touchés")
	h.egal(_de(evs, "hook").size(), 0, "aucun n'est tiré")
	h.ok(a.stun > 0.0 and b.stun > 0.0 and a.stun <= x.stun, "les deux sont étourdis")
	h.ok(_dist(g2, a) > 80.0, "le premier reste à sa place (%s)" % str(_dist(g2, a)))
	var g3 := _avec(h, "bourreau", "chaine", "")
	var c := _cible(g3, 120.0, 0.0, 1.0)
	h.egal(_de(_lancer(h, g3, 0.4), "hook").size(), 1, "sans amélioration : le crochet tire")
	h.ok(_dist(g3, c) < 70.0 and c.vulnMult == 0.0, "tiré contre le héros (%s), sans vulnérabilité" % str(_dist(g3, c)))

static func _c_bombe(h) -> void:
	var s := _reglage("revenant", "bombe", "grappe")
	var g := _avec(h, "revenant", "bombe", "grappe")
	h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	var bombes: Array = _zones(g, "bombe")
	h.egal(bombes.size(), int(s.count), "« grappe » : trois bombes")
	h.egal(bombes.map(func(z): return [z.damage, z.r]), [[s.damage, s.radius], [s.damage, s.radius], [s.damage, s.radius]])
	h.ok(bombes[0].ty < bombes[1].ty and bombes[1].ty < bombes[2].ty, "en éventail")
	h.egal(g.player.slots[0].charges, g.tuning.gadgets.bombe.chargesPerSection - 1.0, "pour UNE charge")
	var f := _reglage("bourreau", "bombe", "fumigene")
	var g2 := _avec(h, "bourreau", "bombe", "fumigene")
	var e := _cible(g2, 150.0, 0.0, 1.0)
	e.stun = 0.0
	var evs := _lancer(h, g2, 1.2)
	h.egal(_coups(evs), [f.damage], "« fumigène » : presque aucun dégât")
	h.ok(e.stun > f.stun - 1.0 and e.stun <= f.stun, "mais un long étourdissement (%s)" % str(e.stun))
	h.egal(_de(evs, "explode")[0].r, f.radius)

static func _c_colere(h) -> void:
	var s := _reglage("revenant", "colere", "aspire")
	var g := _avec(h, "revenant", "colere", "aspire")
	var e := _cible(g, 110.0, 0.0, 1.0)
	_lancer(h, g, 1.0)
	h.proche(_dist(g, e), g.player.r + e.r + s.pullGap, 4.0, "« œil du cyclone » : l'ennemi est aspiré contre le héros")
	var g0 := _avec(h, "revenant", "colere", "")
	var e0 := _cible(g0, 110.0, 0.0, 1.0)
	_lancer(h, g0, 1.0)
	h.ok(_dist(g0, e0) > 110.0, "sans amélioration, le tourbillon repousse")
	var x := _reglage("revenant", "colere", "soif")
	var g2 := _avec(h, "revenant", "colere", "soif")
	_cible(g2, 60.0, 0.0)
	_cible(g2, -60.0, 0.0)
	g2.player.hp = 10.0
	var evs := _lancer(h, g2, LOIN)
	var tics: int = _de(evs, "superTick").size()
	h.egal(g2.player.hp, 10.0 + 2.0 * x.healPerHit * tics, "« soif » : deux ennemis touchés à chacun des %d tics" % tics)
	g0.player.hp = 10.0
	h.avancer(g0, h.ticks(LOIN))
	h.egal(g0.player.hp, 10.0, "sans amélioration : aucun soin")

static func _c_bond(h) -> void:
	var s := _reglage("bourreau", "bond", "double")
	var g := _avec(h, "bourreau", "bond", "double")
	_cible(g, 200.0, 0.0)
	var plein: float = g.tuning.skills.bond.cooldown
	_lancer(h, g, g.tuning.skills.bond.leapTime + 0.1)
	h.ok(g.player.slots[0].cd <= s.rebound and g.player.slots[0].cd > 0.0, "« double saut » : le Bond suivant est prêt en %s s (%s)" % [str(s.rebound), str(g.player.slots[0].cd)])
	h.avancer(g, h.ticks(s.rebound))
	_lancer(h, g, g.tuning.skills.bond.leapTime + 0.1)
	h.ok(g.player.slots[0].cd > plein - 1.0, "une fois seulement : le second Bond retrouve sa recharge (%s)" % str(g.player.slots[0].cd))
	var x := _reglage("bourreau", "bond", "onde")
	var g2 := _avec(h, "bourreau", "bond", "onde")
	_cible(g2, 200.0, 0.0)
	var bord := _cible(g2, 200.0, x.radius - 40.0)
	var evs := _lancer(h, g2, 0.6)
	h.egal(_de(evs, "explode")[0].r, x.radius, "« onde de choc » : le rayon des données")
	h.ok(bord.hp < bord.maxHp and x.radius - 40.0 > D6Data.default_tuning().skills.bond.radius, "un ennemi hors du rayon de base est frappé")

static func _c_cri(h) -> void:
	var s := _reglage("bourreau", "cri", "guerre")
	var g := _avec(h, "bourreau", "cri", "guerre")
	_cible(g, 80.0, 0.0)
	var loin := _cible(g, 500.0, 0.0) # hors du cri : ni étourdi de plus, ni vulnérable
	h.avancer(g, 1, {"skill1Pressed": true})
	h.proche(g.player.surge, s.surge, 0.02, "« cri de guerre » : élan du héros")
	h.egal(g.player.surgeMult, s.surgeMult)
	var avant: float = D6Combat._scaled_amount(g, loin, {"kind": "melee", "amount": 10.0})
	h.avancer(g, h.ticks(s.surge + 0.5)) # un gel d'impact retarde un peu la fin
	h.proche(avant / D6Combat._scaled_amount(g, loin, {"kind": "melee", "amount": 10.0}), 1.0 + s.surgeMult, 1e-9, "dégâts en plus tant qu'il dure, plus après")
	var g2 := _avec(h, "bourreau", "cri", "terreur")
	var e := _cible(g2, 80.0, 0.0, 1.0)
	_lancer(h, g2, 0.5)
	var g0 := _avec(h, "bourreau", "cri", "")
	var e0 := _cible(g0, 80.0, 0.0, 1.0)
	_lancer(h, g0, 0.5)
	h.proche(_dist(g0, e0), 80.0, 1e-6, "sans amélioration : le cri ne repousse pas")
	h.ok(_dist(g2, e) > 120.0, "« terreur » : il repousse (%s u)" % str(_dist(g2, e)))

static func _c_sentence(h) -> void:
	var s := _reglage("bourreau", "sentence", "verdict")
	var g := _avec(h, "bourreau", "sentence", "verdict")
	_cible(g, 60.0, 0.0)
	var derriere := _cible(g, -100.0, 0.0)
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
	h.proche(g.player.superT, s.duration, 0.02, "« verdict » : un geste court")
	evs.append_array(h.avancer(g, h.ticks(LOIN)))
	h.egal(_de(evs, "superTick").size(), 1, "un seul coup")
	h.egal(derriere.maxHp - derriere.hp, _sur_cible(g, s.strikes[0].damage * g.tuning.skills.sentence.damageMult), "tout autour, au montant des données × le rang")
	var x := _reglage("bourreau", "sentence", "soif")
	var g2 := _avec(h, "bourreau", "sentence", "soif")
	_cible(g2, 60.0, 0.0)
	g2.player.hp = 10.0
	_lancer(h, g2, LOIN)
	h.egal(g2.player.hp, 10.0 + 3.0 * x.healPerHit, "« dîme de sang » : un ennemi frappé par chacun des trois coups")

static func _c_volee(h) -> void:
	var base: Dictionary = D6Data.default_tuning().skills.volee
	var s := _reglage("chasseresse", "volee", "rafale")
	var g := _avec(h, "chasseresse", "volee", "rafale")
	h.avancer(g, h.ticks(base.castTime) + 2, func(i): return {"skill1Pressed": i == 0, "skill1AimX": 1.0})
	var tirs: Array = D6KitCommon.kit_store(g).shots
	h.egal(tirs.size(), int(base.count), "« rafale droite » : autant d'épines")
	h.ok(tirs.all(func(t): return t.pierce == s.pierce and t.range == s.range), "qui traversent et portent plus loin")
	var ouverture: float = D6Trig.atan2(tirs[-1].vy, tirs[-1].vx) - D6Trig.atan2(tirs[0].vy, tirs[0].vx)
	h.proche(ouverture, s.spread * D6Data.DEG, 1e-4, "serrées : %s° au lieu de %s°" % [str(s.spread), str(base.spread)])
	var x := _reglage("chasseresse", "volee", "tempete")
	var g2 := _avec(h, "chasseresse", "volee", "tempete")
	h.avancer(g2, h.ticks(base.castTime) + 2, func(i): return {"skill1Pressed": i == 0, "skill1AimX": 1.0})
	var larges: Array = D6KitCommon.kit_store(g2).shots
	h.egal([larges.size(), larges[0].damage], [int(x.count), x.damage], "« tempête » : neuf épines, aux dégâts des données")
	h.proche(D6Trig.atan2(larges[-1].vy, larges[-1].vx) - D6Trig.atan2(larges[0].vy, larges[0].vx), x.spread * D6Data.DEG, 1e-4, "en large")

static func _c_piege(h) -> void:
	var s := _reglage("chasseresse", "piege", "explosif")
	var g := _avec(h, "chasseresse", "piege", "explosif")
	_cible(g, PRES, 0.0)
	var bord := _cible(g, 0.0, s.blastRadius - 20.0)
	var evs := _lancer(h, g, 1.0)
	h.egal(_de(evs, "explode")[0].r, s.blastRadius, "« explosif » : le rayon des données")
	h.egal(bord.maxHp - bord.hp, _sur_cible(g, s.damage), "un ennemi loin du piège est pris dans le souffle")
	var x := _reglage("chasseresse", "piege", "champ")
	var g2 := _avec(h, "chasseresse", "piege", "champ")
	h.avancer(g2, 1, {"skill1Pressed": true})
	var poses: Array = _zones(g2, "piege")
	h.egal(poses.size(), int(x.count), "« champ de pièges » : trois pièges pour une charge")
	h.ok(poses.all(func(z): return absf(sqrt(D6Geo.dist2(z.x, z.y, g2.player.x, g2.player.y)) - x.ringDist) < 1e-6), "autour d'elle")
	h.egal(g2.player.slots[0].charges, g2.tuning.gadgets.piege.chargesPerSection - 1.0)
	h.avancer(g2, 1, {"skill1Pressed": true})
	h.avancer(g2, 1, {"skill1Pressed": true})
	h.egal(_zones(g2, "piege").size(), int(x.maxActive), "jamais plus que le maximum des données")

static func _c_brasier(h) -> void:
	var s := _reglage("chasseresse", "brasier", "poix")
	var g := _avec(h, "chasseresse", "brasier", "poix")
	var e := _cible(g, 150.0, 0.0)
	_lancer(h, g, 1.0)
	h.egal(e.chillMult, s.chillMult, "« poix » : ralenti dans les flammes")
	h.ok(e.chill > 0.0 and e.burnDps > 0.0, "et il brûle toujours")
	var x := _reglage("chasseresse", "brasier", "explosif")
	var g2 := _avec(h, "chasseresse", "brasier", "explosif")
	var e2 := _cible(g2, 150.0, 0.0)
	e2.stun = 0.0
	var evs := _lancer(h, g2, 0.8)
	h.egal(_coups(evs), [maxf(1.0, D6Js.jround(x.damage))], "« pot explosif » : le montant des données")
	h.ok(e2.stun > 0.0 and e2.stun <= x.stun, "étourdi")
	h.egal([_zones(g2, "brasier").size(), e2.burnDps], [0, 0.0], "aucune flamme ne reste")
	var g0 := _avec(h, "chasseresse", "brasier", "")
	var e0 := _cible(g0, 150.0, 0.0)
	_lancer(h, g0, 1.0)
	h.ok(not D6Js.truthy(e0.get("chillMult")) or e0.chillMult == 1.0, "sans amélioration : pas de ralentissement")

static func _c_totem(h) -> void:
	var s := _reglage("chasseresse", "totem", "foudre")
	var g := _avec(h, "chasseresse", "totem", "foudre")
	var e := _cible(g, 60.0, 0.0)
	var evs := _lancer(h, g, 1.0)
	h.ok(_coups(evs).has(_sur_cible(g, s.damage)), "« foudre » : %s par impulsion (%s)" % [str(s.damage), str(_coups(evs))])
	h.ok(not D6Js.truthy(e.get("chillMult")) or e.chillMult == 1.0, "il ne ralentit plus")
	h.ok(_coups(evs).size() >= int(1.0 / s.pulse), "à la cadence des données")
	var g2 := _avec(h, "chasseresse", "totem", "gardien")
	var g0 := _avec(h, "chasseresse", "totem", "")
	for partie in [g2, g0]:
		h.avancer(partie, 1, {"skill1Pressed": true})
		D6Projectiles.spawn_projectile(partie, {"owner": "enemy", "kind": "arrow", "x": partie.player.x + 90.0, "y": partie.player.y, "vx": 0.0, "vy": 0.0, "r": 6.0, "damage": 1.0})
		h.avancer(partie, h.ticks(partie.tuning.gadgets.totem.pulse) + 2)
	h.egal(g2.projectiles.size(), 0, "« gardien » : le tir ennemi dans son rayon est effacé")
	h.egal(g0.projectiles.size(), 1, "sans amélioration : il reste")

static func _c_nuee(h) -> void:
	var s := _reglage("chasseresse", "nuee", "acharnement")
	var x := _reglage("chasseresse", "nuee", "averse")
	var touches := {}
	for choix in ["", "acharnement", "averse"]:
		var g := _avec(h, "chasseresse", "nuee", choix)
		var cibles: Array = []
		for i in 6: # six directions, de plus en plus loin : aucun trait n'en croise une autre
			var d: float = 80.0 + 30.0 * i
			cibles.append(_cible(g, D6Trig.cos(i * PI / 3.0) * d, D6Trig.sin(i * PI / 3.0) * d))
		_lancer(h, g, LOIN)
		touches[choix] = cibles.map(func(e): return e.maxHp - e.hp)
	var base: Dictionary = D6Data.default_tuning().supers.nuee
	h.egal(touches[""].filter(func(d): return d > 0.0).size(), int(base.targets), "sans amélioration : %d cibles" % int(base.targets))
	h.egal(touches["acharnement"].filter(func(d): return d > 0.0).size(), int(s.targets), "« acharnement » : la plus proche seule")
	h.ok(touches["acharnement"][0] > touches[""][0], "elle prend tout")
	h.egal(touches["averse"].filter(func(d): return d > 0.0).size(), int(x.targets), "« averse » : six cibles")

# ---------------------------------------------------------------- passifs, déplacement, ultime

static func _tests_passifs(h) -> void:
	for class_id in CLASSES:
		h.test("passifs : %s — chaque rang de chaque passif (et du nœud de déplacement) change la statistique dite" % class_id, func(): _p_stats(h, class_id))
		h.test("ultime : %s — chaque rang du nœud d'ultime change le nombre dit, et l'ultime le joue" % class_id, func(): _p_ultime(h, class_id))
	h.test("passif « dégâts aux ennemis étourdis » : appliqué aux étourdis seulement", func(): _p_sonnes(h))
	h.test("passifs : ils s'ajoutent au Sanctuaire et aux bénédictions, sans les remplacer", func(): _p_cumul(h))

static func _p_stats(h, class_id: String) -> void:
	var c: Dictionary = D6Data.default_tuning().classes[class_id]
	var slots := [c.skills[0], c.gadgets[0], null]
	var nu: Dictionary = _bac(h, class_id, slots)
	var vus := 0
	for n in _noeuds(class_id, "passive") + _noeuds(class_id, "move"):
		if n.get("stat") == null:
			continue
		for rang in range(1, int(n.maxRank) + 1):
			var g := _bac(h, class_id, slots, {n.id: float(rang)})
			vus += 1
			h.proche(g.player.stats[n.stat] - nu.player.stats[n.stat], n.perRank * rang, 1e-9, "%s/%s rang %d : %s" % [class_id, n.id, rang, n.stat])
			if n.stat == "maxHpBonus":
				h.egal(g.player.maxHp - nu.player.maxHp, n.perRank * rang, "%s : les PV max suivent" % n.id)
			if n.stat == "dashChargesBonus":
				h.egal(D6Player.move_view(g).maxCharges - D6Player.move_view(nu).maxCharges, n.perRank * rang, "%s : une charge de déplacement de plus" % n.id)
			if n.stat == "gadgetChargesBonus":
				h.egal(D6Loadout.max_charges(g, 1) - D6Loadout.max_charges(nu, 1), n.perRank * rang, "%s : une charge de plus" % n.id)
			if n.stat == "skillCooldownMult":
				h.proche(D6Loadout.slot_view(g, 0).cooldownFrac, 0.0, 1e-9)
				h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
				h.proche(g.player.slots[0].cd, g.tuning.skills[c.skills[0]].cooldown * (1.0 + n.perRank * rang), 1e-9, "%s : la recharge posée est plus courte" % n.id)
	h.ok(vus >= 6, "%s : %d rangs de passifs vérifiés" % [class_id, vus])
	h.ok(_noeuds(class_id, "passive").size() >= 4 and _noeuds(class_id, "passive").size() <= 6, "4 à 6 passifs")

static func _p_ultime(h, class_id: String) -> void:
	var c: Dictionary = D6Data.default_tuning().classes[class_id]
	for n in _noeuds(class_id, "ultimate"):
		for rang in range(0, int(n.maxRank) + 1):
			var g := _bac(h, class_id, [c.skills[0], c.gadgets[0], null], {n.id: float(rang)} if rang > 0 else {})
			for field in n.ranks:
				var v: float = n.ranks[field][rang - 1] if rang > 0 else D6Data.default_tuning().supers[c["super"]][field]
				h.egal(g.tuning["super"][field], v, "%s/%s rang %d : %s" % [class_id, n.id, rang, field])
				g.player.superCharge = 1.0
				_cible(g, 120.0, 0.0)
				var bas := _cible(g, -120.0, 0.0)
				var haut := _cible(g, 0.0, 120.0)
				if field == "executeBelow":
					bas.hp = 50000.0 * (v - 0.01)
					haut.hp = 50000.0 * (v + 0.02)
				h.ultime(g)
				h.avancer(g, h.ticks(1.0))
				match field:
					"formTime":
						h.egal(g.player.ult.max, v, "la forme dure ce que dit le rang")
					"count":
						h.egal(g.allies.size(), int(v), "autant de limiers")
					"executeBelow":
						h.ok(bas.dead and not haut.dead, "exécuté sous %s de vie, pas au-dessus" % str(v))
	h.egal(_noeuds(class_id, "ultimate").size(), 1, "%s : un nœud d'ultime" % class_id)

static func _p_sonnes(h) -> void:
	var n: Dictionary = Arbre.node(D6Data.default_tuning(), "bourreau", "bourreau_des_sonnes")
	for rang in range(1, int(n.maxRank) + 1):
		var g := _bac(h, "bourreau", ["bond", "cri", null], {n.id: float(rang)})
		var nu := _bac(h, "bourreau", ["bond", "cri", null])
		var e := _cible(g, 60.0, 0.0)
		var e0 := _cible(nu, 60.0, 0.0)
		var coup := {"kind": "melee", "amount": 100.0}
		h.proche(D6Combat._scaled_amount(g, e, coup) / D6Combat._scaled_amount(nu, e0, coup), 1.0 + n.perRank * rang, 1e-9, "rang %d : étourdi" % rang)
		e.stun = 0.0
		e0.stun = 0.0
		h.proche(D6Combat._scaled_amount(g, e, coup), D6Combat._scaled_amount(nu, e0, coup), 1e-9, "rang %d : pas étourdi, aucun bonus" % rang)

static func _p_cumul(h) -> void:
	var t := _t()
	var n: Dictionary = Arbre.node(t, "revenant", "sang_vif")
	var m := _meta("revenant", ["lance", "nova", null], {"sang_vif": n.maxRank})
	m.upgrades = {"vitalite": 2.0}
	var g: Dictionary = h.bac_a_sable({"seed": 7.0, "meta": m})
	var attendu: float = n.perRank * n.maxRank + t.town.upgrades.vitalite.perLevel * 2.0
	h.egal(g.player.stats.maxHpBonus, attendu, "arbre + Sanctuaire")
	var avant: float = g.player.stats.skillDamageMult
	D6Boons.add_boon(g.run, {"id": "rancoeur", "rarity": "commun"})
	D6Stats.recompute_stats(g)
	h.egal(g.player.stats.maxHpBonus, attendu, "une bénédiction ne retire rien à l'arbre")
	h.ok(g.player.stats.skillCooldownMult < 1.0 and g.player.stats.skillDamageMult == avant, "et s'ajoute par-dessus")

# ---------------------------------------------------------------- migration du profil

static func _tests_migration(h) -> void:
	h.test("migration : le vrai profil d'un joueur (réduit) arrive au schéma courant sans rien perdre", func(): _m_reel(h))
	h.test("migration : compétences déjà débloquées = rang 1 offert, Âmes non reprises, emplacements gardés", func(): _m_offert(h))
	h.test("migration : l'avance vient du record (ennemis tués, Gardiens vaincus), à la classe portée seulement", func(): _m_avance(h))
	h.test("migration : faite une fois ; un profil au schéma courant est relu tel quel", func(): _m_stable(h))
	h.test("sauvegarde : un arbre illisible ou qui dépasse ses points est remis d'aplomb", func(): _m_illisible(h))

static func _m_reel(h) -> void:
	var t := _t()
	var c := _cfg()
	var p: Dictionary = D6Profile.sanitize_profile(D6Js.clone(PROFIL_REEL), t)
	h.egal(p.schema, D6Data.tables().profile.PROFILE_SCHEMA, "schéma courant")
	for cle in ["bestFloor", "checkpoints", "souls", "gold", "unlocked", "upgrades", "guardians", "stats"]:
		h.egal(p[cle], PROFIL_REEL[cle], "« %s » relu sans perte" % cle)
	h.egal(p.loadout, {"classId": "bourreau", "slots": ["bond", "cri", "chaine"]}, "ses trois emplacements")
	var xp: float = PROFIL_REEL.stats.kills * c.xp.kill + 8.0 * c.xp.guardian
	var st: Dictionary = p.tree.bourreau
	h.egal(_niveaux_passes(st.level) + st.xp, xp, "expérience : %s ennemis tués et 8 Gardiens vaincus" % D6Js.num_str(PROFIL_REEL.stats.kills))
	h.ok(st.level > 1.0 and st.level < c.maxLevel, "niveau %s : ni zéro, ni tout" % D6Js.num_str(st.level))
	h.egal(st.guardians, ["cerbere", "colosse", "gardien", "minos"], "quatre modèles de Gardien déjà vaincus")
	var v: Dictionary = D6Profile.tree_view(p, t, "bourreau")
	h.egal(v.points, (st.level - 1.0) * c.pointsPerLevel + 4.0 * c.pointsPerGuardian, "points : ses niveaux + ses Gardiens, rien de dépensé")
	h.egal([p.tree.revenant.level, p.tree.chasseresse.level], [1.0, 1.0], "les autres classes partent du niveau 1")
	for id in ["bond", "cri", "chaine", "bombe"]:
		h.egal([_noeud_vu(p, "bourreau", id).rank, _noeud_vu(p, "bourreau", id).free], [1.0, true], "%s : rang 1 offert" % id)
	h.egal(_noeud_vu(p, "bourreau", "sentence").rank, 0.0, "la compétence neuve reste à débloquer")
	h.egal(D6Profile.sanitize_profile(D6Js.clone(p), t), p, "relu une seconde fois : plus rien ne bouge")
	var g: Dictionary = D6Game.create_game({"seed": 12.0, "meta": D6Js.clone(PROFIL_REEL), "startFloor": 127.0})
	h.egal(g.kit.slots, ["bond", "cri", "chaine"], "et la partie suivante se joue")
	h.egal(g.tuning.skills.bond, D6Data.default_tuning().skills.bond, "au rang 1 : les nombres d'avant")

static func _m_offert(h) -> void:
	var t := _t()
	var u := {"classes": ["revenant"], "skills": ["lance", "chaine"], "gadgets": ["nova", "bombe"]}
	var p: Dictionary = D6Profile.sanitize_profile({"schema": 4.0, "souls": 77.0, "unlocked": u, "loadout": {"classId": "revenant", "slots": ["chaine", "bombe", "lance"]}}, t)
	h.egal(p.schema, 5.0)
	h.egal(p.souls, 77.0, "les Âmes ne sont ni reprises ni rendues")
	h.egal(p.loadout.slots, ["chaine", "bombe", "lance"], "emplacements gardés")
	h.egal(["lance", "chaine", "nova", "bombe", "colere"].map(func(id): return _noeud_vu(p, "revenant", id).rank), [1.0, 1.0, 1.0, 1.0, 0.0])
	h.egal([p.tree.revenant.ranks, D6Profile.tree_view(p, t, "revenant").spent], [{}, 0.0], "offerts : hors budget, aucun point dépensé")
	# Le rang offert se complète en payant un rang de moins.
	Arbre.state(p, "revenant").level = 30.0
	for i in int(_cfg().skillRanks) - 1:
		D6Profile.tree_buy(p, t, "revenant", "lance")
	h.egal([_noeud_vu(p, "revenant", "lance").rank, D6Profile.tree_view(p, t, "revenant").spent], [_cfg().skillRanks, _cfg().skillRanks - 1.0])

static func _m_avance(h) -> void:
	var t := _t()
	var c := _cfg()
	var brut := {"schema": 4.0, "unlocked": {"classes": ["revenant", "chasseresse"]}, "loadout": {"classId": "chasseresse", "slots": ["volee", "piege", null]}, "stats": {"kills": 100.0}, "guardians": {"gardien": 2.0, "minos": 0.0}}
	var p: Dictionary = D6Profile.sanitize_profile(brut, t)
	var st: Dictionary = p.tree.chasseresse
	h.egal(_niveaux_passes(st.level) + st.xp, 100.0 * c.xp.kill + 2.0 * c.xp.guardian, "ennemis tués + Gardiens vaincus, au tarif de base")
	h.egal(st.guardians, ["gardien"], "un point par modèle VAINCU (pas pour un compteur à zéro)")
	h.egal([p.tree.revenant.level, p.tree.revenant.xp, p.tree.revenant.guardians], [1.0, 0.0, []], "l'autre classe : niveau 1")
	var neuf: Dictionary = D6Profile.sanitize_profile({"schema": 4.0}, t)
	h.egal(neuf.tree, {"revenant": Arbre.new_state()}, "un profil sans record : niveau 1, rien")
	h.egal(D6Profile.sanitize_profile(null, t).tree, {"revenant": Arbre.new_state()}, "aucune sauvegarde : pareil")

static func _m_stable(h) -> void:
	var t := _t()
	var p := _profil("revenant")
	p.stats.kills = 5000.0
	p.guardians = {"gardien": 3.0}
	var relu: Dictionary = D6Profile.sanitize_profile(D6Js.clone(p), t)
	h.egal(relu.tree.revenant, Arbre.new_state(), "schéma courant : aucune avance n'est redonnée")
	h.egal(relu.tree.keys(), CLASSES, "un arbre par classe possédée")
	_points(p, "revenant", 10.0)
	_acheter(h, p, "revenant", "lance", 3)
	D6Profile.tree_choose(p, t, "revenant", "lance", "explose")
	p.tree.revenant.xp = 12.0
	p.tree.revenant.guardians = ["gardien"]
	h.egal(D6Profile.sanitize_profile(D6Js.clone(p), t).tree, p.tree, "rangs, amélioration, expérience et Gardiens relus tels quels")

static func _m_illisible(h) -> void:
	var t := _t()
	var p := _profil("revenant")
	p.tree.revenant = {"level": 4.0, "xp": -3.0, "ranks": {"lance": 9.0, "sang_vif": 2.0, "introuvable": 1.0, "nova": "x"}, "choices": {"lance": "explose", "nova": "rien"}, "guardians": ["gardien", "gardien", "licorne", 7.0]}
	var st: Dictionary = D6Profile.sanitize_profile(D6Js.clone(p), t).tree.revenant
	h.egal(st, {"xp": 0.0, "level": 4.0, "ranks": {"sang_vif": 2.0}, "choices": {}, "guardians": ["gardien"]}, "rang hors bornes, nœud inconnu, amélioration sans son rang : écartés")
	p.tree.revenant = {"level": 2.0, "ranks": {"sang_vif": 3.0, "lance": 4.0}, "choices": {"lance": "explose"}}
	st = D6Profile.sanitize_profile(D6Js.clone(p), t).tree.revenant
	h.egal([st.ranks, st.choices, st.level], [{}, {}, 2.0], "plus de points dépensés que gagnés : tout est rendu, le niveau reste")
	p.tree = "illisible"
	h.egal(D6Profile.sanitize_profile(D6Js.clone(p), t).tree.revenant, Arbre.new_state())
	p.tree = {"revenant": {"level": 99.0, "xp": 1e12}}
	st = D6Profile.sanitize_profile(D6Js.clone(p), t).tree.revenant
	h.egal([st.level, st.xp], [_cfg().maxLevel, 0.0], "niveau borné au maximum")

# ---------------------------------------------------------------- en partie : compétence canalisée, déterminisme

static func _tests_partie(h) -> void:
	for class_id in CLASSES:
		h.test("ancien Super en compétence : %s — invulnérable le temps du geste, sur sa recharge, sans toucher à la jauge d'ultime" % class_id, func(): _g_canal(h, class_id))
	h.test("kit : une partie joue les rangs, l'amélioration et les passifs de la classe ; resolve_kit ne les perd pas", func(): _g_kit(h))
	h.test("déterminisme : même graine, mêmes entrées, même arbre → même partie ; l'arbre plein change la partie", func(): _g_determinisme(h))
	h.test("références : les parties arbre_* partent bien avec l'arbre rempli que dit leur spec", func(): _g_references(h))

static func _g_canal(h, class_id: String) -> void:
	var t: Dictionary = D6Data.default_tuning()
	var id: String = t.classes[class_id].skills[2]
	var def: Dictionary = t.skills[id]
	var ancien: Dictionary = t.supers[def["super"]]
	h.egal([def.kind, ancien.get("reserve")], ["canal", true], "%s joue un ancien Super gardé en réserve" % id)
	var g := _bac(h, class_id, [id, null, null])
	var e := _cible(g, 70.0, 0.0)
	var jauge: float = g.player.superCharge
	var vue: Dictionary = D6Loadout.slot_view(g, 0)
	h.egal([vue.kind, vue.ready, vue.aimed, vue.name], ["skill", true, false, def.name])
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
	h.egal(g.player.state, "super", "le héros joue le Super")
	h.egal(g.player.slots[0].cd, def.cooldown, "sa recharge longue part")
	h.egal(_de(evs, "super").size(), 0, "ce n'est PAS l'ultime qui part")
	h.egal(_de(evs, "skill").map(func(ev): return [ev.skill, ev.get("super"), ev.slot]), [["canal", ancien.kind, 0.0]])
	h.egal(D6Combat.damage_player(g, 50.0, {"kind": "test", "id": 1.0}), false, "invulnérable pendant le geste")
	h.egal(D6Player.ultimate_view(g).timeLeft, 0.0, "la minuterie d'ultime ne bouge pas")
	evs.append_array(h.avancer(g, h.ticks(ancien.duration + 1.0))) # les gels d'impact allongent un peu le geste
	h.egal([g.player.state, g.player.channel], ["free", null], "fini après la durée du Super")
	h.ok(e.hp < e.maxHp and evs.filter(func(ev): return ev.type == "hit").all(func(ev): return ev.kind == "super"), "il frappe, source « super »")
	h.egal(g.player.superCharge, jauge, "la jauge d'ultime n'est ni dépensée ni remplie")
	h.egal(D6Loadout.slot_view(g, 0).ready, false, "en recharge")
	# L'ultime de la classe se lance toujours, par le maintien.
	g.player.superCharge = 1.0
	h.egal(_de(h.ultime(g), "super").map(func(ev): return ev.get("super")), [t.supers[t.classes[class_id]["super"]].kind], "l'ultime de la classe reste le sien")

static func _g_kit(h) -> void:
	var g := _bac(h, "revenant", ["lance", "nova", "chaine"], {"lance": 5.0, "nova": 4.0, "sang_vif": 3.0}, {"lance": "explose"})
	var lance: Dictionary = Arbre.node(g.tuning, "revenant", "lance")
	var attendu: Dictionary = D6Js.clone(g.tuning.skills.lance)
	h.egal([attendu.damage, attendu.cooldown, attendu.get("blastRadius")], [lance.ranks.damage[3], lance.ranks.cooldown[3], _reglage("revenant", "lance", "explose").blastRadius])
	h.egal(D6Loadout.max_charges(g, 1), Arbre.node(g.tuning, "revenant", "nova").ranks.chargesPerSection[2], "charges du rang")
	h.egal(g.player.slots[1].charges, D6Loadout.max_charges(g, 1), "pleines au départ")
	D6Stats.recompute_stats(g)
	D6Loadout.resolve_kit(g)
	h.egal(g.tuning.skills.lance, attendu, "recalculer les statistiques ne défait pas l'arbre")
	h.egal(g.tuning.skills.chaine, D6Data.default_tuning().skills.chaine, "une compétence au rang 1 garde ses nombres")
	# Mourir et repartir : l'arbre est permanent.
	g.player.hp = 0.0
	g.player.state = "dead"
	h.avancer(g, h.ticks(g.tuning.player.deathDelay) + 2)
	h.egal(g.mode, "dead")
	D6Game.apply_command(g, {"type": "respawn"})
	h.egal([g.tuning.skills.lance, g.player.stats.maxHpBonus], [attendu, Arbre.node(g.tuning, "revenant", "sang_vif").perRank * 3.0], "après la mort : mêmes rangs, mêmes passifs")

static func _g_references(h) -> void:
	var Catalogue = load("res://references/catalogue.gd")
	var Partie = load("res://references/partie.gd")
	var specs: Array = Catalogue.all().filter(func(s): return s.has("tree"))
	h.ok(specs.size() >= 4, "au moins quatre parties à arbre rempli (%d)" % specs.size())
	var classes := {}
	for spec in specs:
		var g: Dictionary = Partie.start(spec)
		var class_id: String = spec.kit[0]
		classes[class_id] = true
		h.egal(g.kit.slots, spec.slots, "%s : ses trois emplacements" % spec.name)
		for id in spec.tree.ranks:
			var n: Dictionary = Arbre.node(g.tuning, class_id, id)
			h.egal(Arbre.rank(g.meta, g.tuning, class_id, n), float(spec.tree.ranks[id]), "%s : %s au rang %s" % [spec.name, id, str(spec.tree.ranks[id])])
		for id in spec.tree.choices:
			var regle: Dictionary = _reglage(class_id, id, spec.tree.choices[id])
			var def: Dictionary = g.tuning[Arbre.table_of(g.tuning, id)][id]
			for field in regle:
				h.egal(def.get(field), regle[field], "%s : %s joue « %s » (%s)" % [spec.name, id, spec.tree.choices[id], field])
			h.ok(spec.slots.has(id), "%s : %s est dans un emplacement (l'amélioration est jouée)" % [spec.name, id])
	h.egal(classes.size(), 3, "les trois classes")

static func _g_jouer(h, meta: Dictionary) -> Array:
	var g: Dictionary = D6Game.create_game({"seed": 21.0, "meta": D6Js.clone(meta)})
	var marques: Array = []
	for i in 600:
		D6Game.step_game(g, h.entree({
			"moveX": 1.0 if i % 120 < 60 else -1.0, "moveY": 0.4, "attack": i % 9 < 5, "attackPressed": i % 9 == 0,
			"dashPressed": i % 97 == 0, "skill1Pressed": i % 61 == 0, "skill2Pressed": i % 83 == 0, "skill3Pressed": i % 131 == 0,
		}))
		g.events.clear()
		if i % 100 == 99:
			marques.append(D6Game.state_hash(g))
	marques.append(g.meta.tree.revenant.xp)
	return marques

static func _g_determinisme(h) -> void:
	var vide := _meta("revenant", ["lance", "nova", "chaine"])
	var plein := _meta("revenant", ["lance", "nova", "chaine"], {"lance": 5.0, "nova": 5.0, "chaine": 5.0, "sang_vif": 3.0, "tranchant": 3.0}, {"lance": "explose", "nova": "feu", "chaine": "ferrage"})
	h.egal(_g_jouer(h, plein), _g_jouer(h, plein), "arbre plein : deux fois la même partie")
	h.egal(_g_jouer(h, vide), _g_jouer(h, vide), "arbre vide : deux fois la même partie")
	h.different(_g_jouer(h, plein), _g_jouer(h, vide), "l'arbre plein change bien la partie")
	# Rang 1 partout (arbre vide) = le profil d'avant l'arbre, à l'empreinte près.
	var avant: Dictionary = D6Js.clone(vide)
	avant.erase("tree")
	avant.schema = 4.0
	h.egal(_g_jouer(h, avant).slice(0, 6), _g_jouer(h, vide).slice(0, 6), "un profil d'avant l'arbre joue la même partie")
