extends RefCounted
## COMBAT V3, étape 4 — les COMPÉTENCES NEUVES (design/COMBAT_V3.md, sim/kit_neuves.gd et ses trois
## familles, data/classes.json, data/arbres.json). Pour chacune : l'effet de base, les rangs, les
## deux améliorations et leur exclusion, les cas limites (salle vide, Gardien, terrain bas, mort,
## changement de salle), une bénédiction de compétence, le déterminisme ; et les alliés neufs
## (le leurre) : jamais dans l'eau, jamais comptés comme ennemis.
## Les nombres attendus sont LUS dans les données (jamais recopiés) : régler une compétence ne
## casse pas ces tests, changer une règle si.

const Arbre = preload("res://sim/tree.gd")
const Meute = preload("res://sim/ult_meute.gd")
const Catalogue = preload("res://references/catalogue.gd")
const Neuves = preload("res://sim/kit_neuves.gd")

const TOUTES := ["classes", "weapons", "skills", "gadgets"]
const NEUVES := {"revenant": ["sillage", "sceau", "riposte"], "bourreau": ["faille", "hachette", "garde"], "chasseresse": ["proie", "leurre", "trait"]}
const ETAGES := {"sillage": 0.0, "sceau": 1.0, "riposte": 2.0, "faille": 0.0, "hachette": 1.0, "garde": 2.0, "proie": 0.0, "leurre": 1.0, "trait": 2.0}
const ENTREE := ["moveX", "moveY", "aimX", "aimY", "attack", "attackPressed", "dashPressed", "skill1Pressed", "skill1AimX", "skill1AimY", "skill2Pressed", "skill2AimX", "skill2AimY", "skill3Pressed", "skill3AimX", "skill3AimY"]
const VUE := ["id", "name", "icon", "kind", "ready", "cooldownFrac", "charges", "maxCharges", "aimed"]
const GRAINES_EAU := 300

static func tests(h) -> void:
	_tests_arbre(h)
	_tests_revenant(h)
	_tests_bourreau(h)
	_tests_chasseresse(h)
	_tests_communs(h)

# ---------------------------------------------------------------- outillage

static func _t() -> Dictionary:
	return D6Data.create_tuning()

static func _base() -> Dictionary:
	return D6Data.default_tuning()

static func _cfg() -> Dictionary:
	return D6Data.default_tuning().tree

## Réglages de base (rang 1) d'une compétence, dans sa table.
static func _def(id: String) -> Dictionary:
	var t := _base()
	return t[Arbre.table_of(t, id)][id]

static func _classe(id: String) -> String:
	for class_id in NEUVES:
		if NEUVES[class_id].has(id):
			return class_id
	return ""

## Profil d'essai : tout possédé, niveau maximum, les rangs et améliorations demandés, trois emplacements.
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

## Salle vidée, héros au centre tourné vers la droite, jamais de critique (montants exacts).
static func _bac(h, class_id: String, slots: Array, rangs: Dictionary = {}, choix: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var o := {"seed": 7.0, "meta": _meta(class_id, slots, rangs, choix)}
	o.merge(opts, true)
	var g: Dictionary = h.bac_a_sable(o)
	g.tuning.combat.critChance = 0.0
	g.player.facing = 0.0
	return g

## La compétence `id` seule, au rang 1 ("" : aucune amélioration, sinon au rang du choix avec elle).
static func _jeu(h, id: String, choix: String = "", opts: Dictionary = {}) -> Dictionary:
	var rangs := {id: _cfg().choiceRank} if choix != "" else {}
	return _bac(h, _classe(id), [id, null, null], rangs, {id: choix} if choix != "" else {}, opts)

## Les nombres qu'une amélioration pose (`set` des données).
static func _pose(class_id: String, node_id: String, choice_id: String) -> Dictionary:
	for ch in Arbre.node(_base(), class_id, node_id).choices:
		if ch.id == choice_id:
			return ch.set
	return {}

## Ennemi d'essai : ne riposte pas, ne bouge pas (étourdi), increvable par défaut.
static func _cible(g: Dictionary, dx: float, dy: float, masse: float = 1000.0) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, "brute", g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.cooldown = 999.0
	e.maxHp = 50000.0
	e.hp = 50000.0
	e.mass = masse
	e.stun = 999.0
	return e

## Ennemi ÉVEILLÉ (il joue son IA) qui n'attaque pas avant longtemps sauf demande, increvable.
static func _vif(g: Dictionary, dx: float, dy: float, kind: String = "imp", attaque: bool = false) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.maxHp = 50000.0
	e.hp = 50000.0
	if not attaque:
		e.cooldown = 999.0
	return e

## Appuie sur l'emplacement 0 en visant (ax, ay) (0, 0 = visée assistée), puis laisse passer `secondes`.
static func _lancer(h, g: Dictionary, secondes: float = 0.0, ax: float = 1.0, ay: float = 0.0) -> Array:
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": ax, "skill1AimY": ay})
	if secondes > 0.0:
		evs.append_array(h.avancer(g, h.ticks(secondes)))
	return evs

static func _de(evs: Array, type: String, kind = null) -> Array:
	return evs.filter(func(ev): return ev.type == type and (kind == null or ev.get("kind") == kind))

## Montants des coups portés à l'ennemi `e` (de la source `kind` si elle est donnée).
static func _coups(evs: Array, e: Dictionary, kind = null) -> Array:
	return evs.filter(func(ev): return ev.type == "hit" and ev.id == e.id and (kind == null or ev.kind == kind)).map(func(ev): return ev.amount)

## Dégâts d'un coup de `montant` sur une cible ÉTOURDIE (celles de _cible) ; `vif` : cible éveillée.
static func _sur(g: Dictionary, montant: float, vif: bool = false) -> float:
	return maxf(1.0, D6Js.jround(montant * (1.0 if vif else g.tuning.combat.stunDamageTakenMult)))

static func _zones(g: Dictionary, kind: String) -> Array:
	return D6KitZones.zones_of(g, kind)

static func _braises(g: Dictionary) -> Array:
	return _zones(g, "brasier").filter(func(z): return D6Js.truthy(z.get("trail")))

static func _tirs(g: Dictionary) -> Array:
	return D6KitCommon.kit_store(g).shots

static func _leurres(g: Dictionary) -> Array:
	return g.allies.filter(func(a): return a.kind == "leurre" and not a.dead)

static func _dist(g: Dictionary, e: Dictionary) -> float:
	return sqrt(D6Geo.dist2(g.player.x, g.player.y, e.x, e.y))

## Un coup d'ennemi porté au héros depuis le point (x, y), sans i-frames en cours. Rend les PV perdus.
static func _frapper(g: Dictionary, montant: float, x: float, y: float, kind: String = "imp") -> float:
	var p: Dictionary = g.player
	p.iframes = 0.0
	var avant: float = p.hp
	D6Combat.damage_player(g, montant, {"kind": kind, "id": D6State.new_id(g), "x": x, "y": y})
	return avant - p.hp

static func _riviere(g: Dictionary, x0: float, largeur: float = 64.0) -> void:
	g.room.low = [{"x0": x0, "y0": 0.0, "x1": x0 + largeur, "y1": g.room.h, "kind": "river"}]

static func _benir(g: Dictionary, id: String) -> void:
	D6Boons.add_boon(g.run, {"id": id, "rarity": "commun"})
	D6Stats.recompute_stats(g)

static func _talisman(g: Dictionary, stat: String, value: float) -> void:
	g.run.items.talisman = {"id": 9001.0, "slot": "talisman", "rarity": "rare", "name": "Relique d'essai", "level": 1.0, "affixes": [{"stat": stat, "value": value}], "power": null, "base": {}, "score": 0.0}
	D6Stats.recompute_stats(g)

# ---------------------------------------------------------------- arbre : nœuds, rangs, exclusion

static func _tests_arbre(h) -> void:
	h.test("arbre : huit compétences par classe, dont trois neuves, chacune à son étage et dans sa table", func(): _a_noeuds(h))
	h.test("arbre : une compétence neuve se débloque au rang 1 de son nœud et devient plaçable", func(): _a_debloque(h))
	h.test("données : chaque sorte (kind) de compétence a sa règle, chaque sorte neuve a sa compétence", func(): _a_sortes(h))
	for class_id in NEUVES:
		for id in NEUVES[class_id]:
			h.test("rangs : %s — chaque rang écrit ses nombres dans la partie, et le texte de l'arbre les cite" % id, func(): _a_rangs(h, class_id, id))
			h.test("améliorations : %s — l'une OU l'autre ; celle qui est prise est la seule appliquée en partie" % id, func(): _a_exclusion(h, class_id, id))
	h.test("Chaîne et Bombe : une version par classe — rang 1 commun, rangs du Bourreau et une amélioration sur deux différents", func(): _a_versions(h))

static func _a_noeuds(h) -> void:
	var t := _base()
	for class_id in NEUVES:
		var c: Dictionary = t.classes[class_id]
		h.egal((c.skills + c.gadgets).size(), 8, "%s : huit compétences" % class_id)
		for id in NEUVES[class_id]:
			var n = Arbre.skill_node(t, class_id, id)
			h.ok(n != null and (c.skills + c.gadgets).has(id), "%s / %s : dans la liste de la classe, avec son nœud" % [class_id, id])
			h.egal(n.tier, ETAGES[id], "%s : son étage" % id)
			h.egal(n.choices.size(), 2, "%s : deux améliorations" % id)
		# Un mélange : deux à recharge, une à charges.
		h.egal(NEUVES[class_id].filter(func(id): return Arbre.table_of(t, id) == "gadgets").size(), 1, "%s : une compétence neuve à charges" % class_id)
	h.egal(_base().classes.revenant.skills.slice(0, 3) + _base().classes.revenant.gadgets.slice(0, 2), ["lance", "chaine", "colere", "nova", "bombe"], "les cinq d'avant gardent leur place (le kit de départ ne bouge pas)")

## Sortes jouées par les règles d'avant l'étape 4 (player, kit_skills, kit_gadgets).
const SORTES_D_AVANT := {"skills": ["lance", "chain", "bond", "brasier", "volee", "canal"], "gadgets": ["nova", "bombe", "piege", "cri", "totem"]}

static func _a_sortes(h) -> void:
	var t := _base()
	var neuves := {"skills": Neuves.SKILLS, "gadgets": Neuves.GADGETS}
	var vues: Array = []
	for table in SORTES_D_AVANT:
		for id in t[table]:
			var kind: String = t[table][id].kind
			h.ok(SORTES_D_AVANT[table].has(kind) or neuves[table].has(kind), "%s.%s : la sorte « %s » n'est jouée par aucune règle" % [table, id, kind])
			if neuves[table].has(kind):
				vues.append(kind)
				h.egal(_classe(id) != "", true, "%s : une compétence de sorte neuve est dans la liste d'une classe" % id)
				h.ok(t[table][id].get("icon") is String and t[table][id].text != "", "%s : pictogramme et texte" % id)
	vues.sort()
	var attendues: Array = Neuves.SKILLS + Neuves.GADGETS
	attendues.sort()
	h.egal(vues, attendues, "chaque sorte neuve des règles a sa compétence dans les données, une seule")
	# Les améliorations des neuves ne posent que des nombres que leurs règles lisent (gardé aussi par donnees.gd).
	for class_id in NEUVES:
		for id in NEUVES[class_id]:
			for ch in Arbre.node(t, class_id, id).choices:
				for field in ch.set:
					h.ok(_def(id).has(field) or Arbre.EXTRA_FIELDS.has(field), "%s / %s : %s n'est lu par aucune règle" % [id, ch.id, field])

static func _a_debloque(h) -> void:
	var t := _t()
	for class_id in NEUVES:
		var p: Dictionary = D6Profile.new_profile(t)
		p.souls = 1e6
		D6Profile.unlock(p, t, "classes", class_id)
		D6Profile.select_class(p, t, class_id)
		Arbre.state(p, class_id).level = _cfg().maxLevel
		var id: String = NEUVES[class_id][0] # celle de l'étage de base
		h.egal(D6Profile.select_slot(p, t, 2, id).ok, false, "%s : verrouillée, elle ne se place pas" % id)
		h.egal(D6Profile.tree_buy(p, t, class_id, id).ok, true, "%s : le rang 1 s'achète" % id)
		h.egal(D6Profile.select_slot(p, t, 2, id).ok, true, "%s : débloquée, elle se place" % id)
		var g: Dictionary = h.bac_a_sable({"seed": 3.0, "meta": p})
		h.egal(g.kit.slots[2], id, "%s : en partie dans son emplacement" % id)
		h.egal(D6Loadout.slot_view(g, 2).name, _def(id).name)
		h.egal(D6Profile.tree_buy(p, t, class_id, NEUVES[class_id][2]).ok, false, "%s : l'étage de maîtrise reste fermé" % NEUVES[class_id][2])

static func _a_rangs(h, class_id: String, id: String) -> void:
	var t := _t()
	var n: Dictionary = Arbre.node(t, class_id, id)
	for rang in range(1, int(_cfg().skillRanks) + 1):
		var g := _bac(h, class_id, [id, null, null], {id: float(rang)})
		var def: Dictionary = D6Loadout.slot_def(g, 0)
		var texte: String = Arbre.rank_text(t, class_id, n, float(rang))
		for field in n.ranks:
			var v = Arbre.rank_value(n, field, float(rang))
			if v == null:
				v = _def(id)[field]
			h.egal(def[field], v, "%s rang %d : %s en partie" % [id, rang, field])
			h.ok(Arbre.fr(v * 100.0 if _cfg().pctFields.has(field) else v) in texte, "%s rang %d : « %s » cite %s" % [id, rang, texte, field])
		if rang > 1:
			for field in n.ranks:
				h.ok(Arbre.rank_value(n, field, float(rang)) != null, "%s : %s a un nombre au rang %d" % [id, field, rang])
	# Le dernier rang vaut mieux que le premier, sur chaque nombre (une recharge baisse, le reste monte).
	for field in n.ranks:
		var dernier: float = n.ranks[field][n.ranks[field].size() - 1]
		h.ok(dernier < _def(id)[field] if field == "cooldown" else dernier > _def(id)[field], "%s : %s s'améliore du rang 1 au rang 5" % [id, field])

static func _a_exclusion(h, class_id: String, id: String) -> void:
	var t := _t()
	var n: Dictionary = Arbre.node(t, class_id, id)
	var a: Dictionary = n.choices[0]
	var b: Dictionary = n.choices[1]
	var m := _meta(class_id, [id, null, null], {id: _cfg().choiceRank})
	h.egal(D6Profile.tree_choose(m, t, class_id, id, a.id).ok, true, "%s : la première se prend au rang du choix" % id)
	h.egal(D6Profile.tree_choose(m, t, class_id, id, b.id), {"ok": false, "reason": "l'autre amélioration est prise"}, "%s : pas la seconde" % id)
	var sous := _meta(class_id, [id, null, null], {id: _cfg().choiceRank - 1.0})
	h.egal(D6Profile.tree_choose(sous, t, class_id, id, a.id).ok, false, "%s : pas avant le rang du choix" % id)
	for paire in [[a, b], [b, a]]:
		var g: Dictionary = h.bac_a_sable({"seed": 7.0, "meta": _meta(class_id, [id, null, null], {id: _cfg().choiceRank}, {id: paire[0].id})})
		var def: Dictionary = D6Loadout.slot_def(g, 0)
		for field in paire[0].set:
			h.egal(def.get(field), paire[0].set[field], "%s / %s : %s posé en partie" % [id, paire[0].id, field])
		for field in paire[1].set:
			if not paire[0].set.has(field):
				h.egal(def.get(field), _rang3(n, id, field), "%s / %s : %s de l'autre amélioration n'est pas appliqué" % [id, paire[0].id, field])
		h.ok(Arbre.choice_text(t, paire[0]) != Arbre.choice_text(t, paire[1]), "%s : deux textes différents" % id)

## Valeur d'un nombre de la compétence au rang du choix, sans amélioration (null s'il n'existe pas).
static func _rang3(n: Dictionary, id: String, field: String):
	if n.ranks.has(field):
		return Arbre.rank_value(n, field, _cfg().choiceRank)
	return _def(id).get(field)

static func _a_versions(h) -> void:
	var t := _base()
	for id in ["chaine", "bombe"]:
		var r: Dictionary = Arbre.node(t, "revenant", id)
		var b: Dictionary = Arbre.node(t, "bourreau", id)
		var ids_r: Array = r.choices.map(func(ch): return ch.id)
		var ids_b: Array = b.choices.map(func(ch): return ch.id)
		h.ok(ids_r != ids_b and ids_r.filter(func(x): return ids_b.has(x)).is_empty(), "%s : aucune amélioration commune (%s / %s)" % [id, str(ids_r), str(ids_b)])
		h.different(r.ranks, b.ranks, "%s : les rangs du Bourreau ne sont pas ceux du Revenant" % id)
		for class_id in ["revenant", "bourreau"]:
			var g := _bac(h, class_id, [id, null, null])
			h.egal(D6Loadout.slot_def(g, 0), t[Arbre.table_of(t, id)][id], "%s / %s : le rang 1 est celui des données, le même pour les deux" % [class_id, id])
	# Rafle (Bourreau) : la chaîne ramène tout un groupe ; sans elle, un seul.
	var rafle := _pose("bourreau", "chaine", "rafle")
	for cas in [["rafle", int(rafle.pierce) + 1], ["", 1]]:
		var g := _bac(h, "bourreau", ["chaine", null, null], {"chaine": _cfg().choiceRank}, {"chaine": cas[0]} if cas[0] != "" else {})
		var file: Array = [_cible(g, 130.0, 0.0, 1.0), _cible(g, 200.0, 0.0, 1.0), _cible(g, 270.0, 0.0, 1.0)]
		var evs := _lancer(h, g, 0.7)
		h.egal(_de(evs, "hook").size(), cas[1], "chaîne du Bourreau « %s » : %d ennemi(s) harponné(s)" % [cas[0], cas[1]])
		var departs := [130.0, 200.0, 270.0]
		var ramenes := 0
		for i in 3:
			if _dist(g, file[i]) < departs[i] - 50.0:
				ramenes += 1
		h.egal(ramenes, cas[1], "… et ramené(s) vers lui")
	# Croc de boucher (Revenant) : courte, brutale.
	var croc := _pose("revenant", "chaine", "croc")
	var g2 := _bac(h, "revenant", ["chaine", null, null], {"chaine": _cfg().choiceRank}, {"chaine": "croc"})
	var e2 := _vif(g2, 150.0, 0.0, "brute")
	var evs2: Array = h.avancer(g2, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	var portee: float = -1.0
	for i in h.ticks(0.5):
		evs2.append_array(h.avancer(g2, 1))
		if portee < 0.0 and not _tirs(g2).is_empty():
			portee = _tirs(g2)[0].range
	h.egal(portee, croc.range, "croc de boucher : portée courte")
	h.egal(_coups(evs2, e2, "skill"), [_sur(g2, croc.damage, true)], "… gros dégâts")
	h.ok(e2.stun > croc.stun - 0.6 and e2.stun <= croc.stun, "… long étourdissement (%s)" % str(e2.stun))
	_a_bombes(h)

static func _a_bombes(h) -> void:
	# Baril (Bourreau) : mèche longue, souffle large. Poix ardente (Revenant) : le sol brûle après.
	var baril := _pose("bourreau", "bombe", "baril")
	var g := _bac(h, "bourreau", ["bombe", null, null], {"bombe": _cfg().choiceRank}, {"bombe": "baril"})
	h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	h.egal(_zones(g, "bombe").map(func(z): return [z.r, z.fuse, z.knockback]), [[baril.radius, baril.fuse, baril.knockback]], "baril : rayon, mèche, recul des données")
	var evs: Array = h.avancer(g, h.ticks(g.tuning.gadgets.bombe.flight + baril.fuse + 0.1))
	h.egal(_de(evs, "explode", "bombe").map(func(ev): return ev.r), [baril.radius], "il explose à son grand rayon")
	h.egal(_zones(g, "brasier").size(), 0, "baril : aucun feu")
	var poix := _pose("revenant", "bombe", "poix")
	var g2 := _bac(h, "revenant", ["bombe", null, null], {"bombe": _cfg().choiceRank}, {"bombe": "poix"})
	var e := _cible(g2, 200.0, 0.0)
	var b: Dictionary = g2.tuning.gadgets.bombe
	_lancer(h, g2, b.flight + b.fuse + 0.5)
	h.egal(_zones(g2, "brasier").map(func(z): return [z.r, z.duration, z.burnDps]), [[b.radius, poix.fireDuration, poix.fireDps]], "poix ardente : le cercle du souffle brûle")
	h.egal(e.burnDps, poix.fireDps, "l'ennemi qui y reste brûle")
	h.avancer(g2, h.ticks(poix.fireDuration))
	h.egal(_zones(g2, "brasier").size(), 0, "le feu s'éteint après sa durée")

# ---------------------------------------------------------------- Revenant : sillage, stigmate, contre-taille

static func _tests_revenant(h) -> void:
	h.test("Sillage de braise : une braise à ses pieds, puis une tous les `step` u de marche, pendant `duration` s", func(): _s_base(h))
	h.test("Sillage : le dash sème aussi ; au rang 5 les braises brûlent plus fort et il y a plus de charges", func(): _s_dash_rang(h))
	h.test("Sillage : « braises tenaces » durent et s'étalent ; « détonation » les fait exploser, une fois par ennemi", func(): _s_choix(h))
	h.test("Sillage : jamais une braise dans une rivière ; mort ou changement de salle, il s'arrête", func(): _s_limites(h))
	h.test("Stigmate : le trait marque le premier touché ; le marqué qui meurt explose ; la marque s'efface à son heure", func(): _g_base(h))
	h.test("Stigmate : un ennemi achevé par le trait lui-même explose ; au rang 5 le trait et l'explosion frappent plus fort", func(): _g_acheve(h))
	h.test("Stigmate : « contagion » marque les survivants de l'explosion ; « moisson » soigne et réduit la recharge", func(): _g_choix(h))
	h.test("Stigmate : salle vide (rien, la recharge part), Gardien (marqué, blessé, jamais d'explosion sans mort)", func(): _g_limites(h))
	h.test("Contre-taille : la taillade blesse, puis le premier coup reçu pendant la garde est paré et rendu", func(): _p_base(h))
	h.test("Contre-taille : un tir paré est détruit ; sans coup reçu la garde s'éteint et le coup suivant porte", func(): _p_tir(h))
	h.test("Contre-taille : « miroir » renvoie le tir à son tireur, garde plus longue ; « représailles » rend de la recharge et un élan", func(): _p_choix(h))
	h.test("Contre-taille : un Gardien est blessé par la riposte, jamais étourdi ; mort ou changement de salle, la garde tombe", func(): _p_limites(h))

static func _s_base(h) -> void:
	var s := _def("sillage")
	var g := _jeu(h, "sillage")
	var p: Dictionary = g.player
	var evs := _lancer(h, g)
	h.egal(p.slots[0].charges, s.chargesPerSection - 1.0, "une charge dépensée")
	h.egal(_de(evs, "gadget").map(func(ev): return [ev.gadget, ev.r]), [["sillage", s.radius]], "événement de la compétence à charges")
	h.egal(_braises(g).map(func(z): return [z.x, z.y, z.r, z.duration, z.burnDps]), [[p.x, p.y, s.radius, s.life, s.burnDps]], "une braise à ses pieds, aux nombres des données")
	h.egal(D6Loadout.slot_state(g, 0).active, true, "slot_state : le sillage dure")
	var x0: float = p.x
	h.avancer(g, h.ticks(1.0), {"moveX": 1.0})
	var braises: Array = _braises(g)
	var parcouru: float = p.x - x0
	h.ok(parcouru > 150.0, "le héros a marché (%s u)" % str(parcouru))
	h.ok(braises.size() >= int(parcouru / (s.step + 6.0)) + 1 and braises.size() <= int(parcouru / s.step) + 1, "une braise tous les %s u : %d pour %s u" % [str(s.step), braises.size(), str(parcouru)])
	for i in range(1, braises.size()):
		h.ok(braises[i].x - braises[i - 1].x >= s.step, "deux braises ne sont jamais plus proches que `step`")
	# Elles brûlent ce qui s'y tient, comme un brasier.
	var e := _cible(g, 0.0, 0.0)
	h.avancer(g, h.ticks(0.3))
	h.egal(e.burnDps, s.burnDps, "l'ennemi dans la braise brûle")
	# À la fin de `duration`, plus rien n'est semé ; chaque braise s'éteint après `life`.
	h.avancer(g, h.ticks(s.duration))
	h.egal(p.get("sillage"), null, "le sillage est fini")
	h.egal(D6Loadout.slot_state(g, 0).active, false)
	var avant: int = _braises(g).size()
	h.avancer(g, h.ticks(0.5), {"moveX": -1.0})
	h.ok(_braises(g).size() <= avant, "plus aucune braise semée")
	h.avancer(g, h.ticks(s.life))
	h.egal(_braises(g).size(), 0, "toutes éteintes")

static func _s_dash_rang(h) -> void:
	var s := _def("sillage")
	var g := _jeu(h, "sillage")
	_lancer(h, g)
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	h.avancer(g, h.ticks(g.tuning.dash.duration + 0.05), {"moveX": 1.0})
	h.ok(_braises(g).size() >= int(g.tuning.dash.distance / (s.step + 20.0)) + 1, "le dash laisse son sillage (%d braises)" % _braises(g).size())
	var n: Dictionary = Arbre.node(_base(), "revenant", "sillage")
	var g5 := _bac(h, "revenant", ["sillage", null, null], {"sillage": _cfg().skillRanks})
	h.egal(g5.player.slots[0].charges, Arbre.rank_value(n, "chargesPerSection", _cfg().skillRanks), "rang 5 : charges")
	_lancer(h, g5)
	var e := _cible(g5, 20.0, 0.0)
	h.avancer(g5, h.ticks(0.3))
	h.egal(e.burnDps, Arbre.rank_value(n, "burnDps", _cfg().skillRanks), "rang 5 : la braise brûle plus fort")
	h.ok(e.burnDps > s.burnDps)

static func _s_choix(h) -> void:
	var s := _def("sillage")
	var tenaces := _pose("revenant", "sillage", "tenaces")
	var g := _jeu(h, "sillage", "tenaces")
	_lancer(h, g)
	h.egal(_braises(g).map(func(z): return [z.r, z.duration]), [[tenaces.radius, tenaces.life]], "braises tenaces : plus larges, plus longues")
	h.avancer(g, h.ticks(s.life + 0.5))
	h.egal(_braises(g).size(), 1, "… encore allumée quand une braise ordinaire serait éteinte")
	var det := _pose("revenant", "sillage", "detonation")
	var g2 := _jeu(h, "sillage", "detonation")
	_lancer(h, g2)
	h.avancer(g2, h.ticks(s.duration - 1.1)) # seules les braises ENCORE allumées à la fin explosent
	h.avancer(g2, h.ticks(0.5), {"moveX": 1.0}) # trois ou quatre braises qui se chevauchent
	g2.player.x -= 400.0 # le héros part au loin : aucune autre braise près de la cible
	var e := _cible(g2, 360.0, 20.0)
	var pres: int = _braises(g2).filter(func(z): return D6Geo.dist2(z.x, z.y, e.x, e.y) < (det.blastRadius + e.r) * (det.blastRadius + e.r)).size()
	h.ok(pres >= 2, "cas choisi : la cible est dans le souffle de plusieurs braises (%d)" % pres)
	var evs: Array = h.avancer(g2, h.ticks(0.7))
	h.egal(_coups(evs, e, "gadget"), [_sur(g2, det.blastDamage)], "détonation : UN coup, même dans plusieurs souffles")
	h.ok(_de(evs, "explode", "sillage").size() >= 2, "chaque braise explose")
	h.egal(_braises(g2).filter(func(z): return D6Geo.dist2(z.x, z.y, e.x, e.y) < 200.0 * 200.0).size(), 0, "les braises explosées ont disparu")
	var g0 := _jeu(h, "sillage")
	_lancer(h, g0)
	h.egal(_de(h.avancer(g0, h.ticks(s.duration + 0.2)), "explode").size(), 0, "sans amélioration : aucune explosion")

static func _s_limites(h) -> void:
	var s := _def("sillage")
	var g := _jeu(h, "sillage")
	var p: Dictionary = g.player
	_riviere(g, p.x + 30.0)
	_lancer(h, g)
	# Deux dashs par-dessus la rivière, aller et retour, puis de la marche le long du bord.
	for dir in [1.0, -1.0, 1.0]:
		h.avancer(g, 1, {"moveX": dir, "dashPressed": true})
		h.avancer(g, h.ticks(0.5), {"moveX": dir})
	h.avancer(g, h.ticks(0.6), {"moveY": 1.0})
	h.ok(_braises(g).size() >= 4, "des braises ont été semées (%d)" % _braises(g).size())
	for z in _braises(g):
		h.ok(not D6Physics.ground_blocked(g.room, z.x, z.y, 0.0), "aucune braise dans l'eau (x = %s)" % str(z.x))
	# Salle vide : rien ne casse. Mort : le sillage s'arrête. Changement de salle : aussi.
	var g2 := _jeu(h, "sillage")
	_lancer(h, g2)
	D6Combat.damage_player(g2, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	h.avancer(g2, h.ticks(0.5)) # le gel du coup reçu passe d'abord
	h.egal([g2.player.state, g2.player.get("sillage")], ["dead", null], "mort : plus de sillage")
	var g3 := _jeu(h, "sillage")
	_lancer(h, g3)
	D6Run.enter_floor(g3, g3.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(g3.player.get("sillage"), null, "changement de salle : plus de sillage")
	h.egal(_braises(g3).size(), 0, "… et la salle neuve n'a aucune braise")
	h.ok(s.duration > 0.0)

static func _g_base(h) -> void:
	var s := _def("sceau")
	var g := _jeu(h, "sceau")
	var a := _cible(g, 200.0, 0.0)
	var voisin := _cible(g, 200.0 + s.radius * 0.6, 0.0)
	var loin := _cible(g, 200.0, s.radius + 200.0)
	var evs := _lancer(h, g, 0.5)
	h.egal(g.player.slots[0].cd > 0.0, true, "la recharge est partie")
	h.egal(_coups(evs, a, "skill"), [_sur(g, s.damage)], "le trait blesse le premier touché")
	h.egal(_coups(evs, voisin).size(), 0, "il s'arrête au premier")
	h.ok(a.get("stigmate") != null and a.stigmate.t > s.duration - 0.6 and a.stigmate.t <= s.duration, "il porte la marque, pour la durée des données")
	h.egal(_de(evs, "marked").map(func(ev): return [ev.id, ev.mark]), [[a.id, "stigmate"]], "événement de marque")
	D6Combat.kill_enemy(g, a, {"kind": "melee"})
	evs = g.events.duplicate()
	h.egal(_de(evs, "explode", "stigmate").map(func(ev): return ev.r), [s.radius], "le marqué qui meurt explose, au rayon des données")
	h.egal(_coups(evs, voisin, "skill"), [_sur(g, s.damage * s.blastMult)], "le voisin prend `damage` × `blastMult`")
	h.egal(_coups(evs, loin).size(), 0, "hors du rayon : rien")
	# La marque s'efface : un ennemi qui meurt APRÈS n'explose pas.
	var g2 := _jeu(h, "sceau")
	var b := _cible(g2, 200.0, 0.0)
	_lancer(h, g2, s.duration + 0.5)
	h.egal(b.get("stigmate"), null, "la marque est tombée après sa durée")
	D6Combat.kill_enemy(g2, b, {"kind": "melee"})
	h.egal(_de(g2.events, "explode").size(), 0, "plus d'explosion")

static func _g_acheve(h) -> void:
	var s := _def("sceau")
	var g := _jeu(h, "sceau")
	var a := _cible(g, 150.0, 0.0)
	a.hp = 1.0
	var voisin := _cible(g, 150.0 + s.radius * 0.5, 0.0)
	var evs := _lancer(h, g, 0.4)
	h.egal(a.dead, true, "cas choisi : le trait l'achève")
	h.egal(_de(evs, "explode", "stigmate").size(), 1, "achevé par le trait : il explose quand même (la marque est posée avant le coup)")
	h.egal(_coups(evs, voisin, "skill"), [_sur(g, s.damage * s.blastMult)])
	var n: Dictionary = Arbre.node(_base(), "revenant", "sceau")
	var fort: float = Arbre.rank_value(n, "damage", _cfg().skillRanks)
	var g5 := _bac(h, "revenant", ["sceau", null, null], {"sceau": _cfg().skillRanks})
	var a5 := _cible(g5, 150.0, 0.0)
	var v5 := _cible(g5, 150.0 + s.radius * 0.5, 0.0)
	var evs5 := _lancer(h, g5, 0.4)
	h.egal(_coups(evs5, a5, "skill"), [_sur(g5, fort)], "rang 5 : le trait")
	D6Combat.kill_enemy(g5, a5, {"kind": "melee"})
	h.egal(_coups(g5.events, v5, "skill"), [_sur(g5, fort * s.blastMult)], "rang 5 : l'explosion suit")

static func _g_choix(h) -> void:
	var s := _def("sceau")
	var g := _jeu(h, "sceau", "contagion")
	var a := _cible(g, 150.0, 0.0)
	var b := _cible(g, 150.0 + s.radius * 0.5, 0.0)
	var c := _cible(g, 150.0 + s.radius * 1.4, 0.0) # hors du souffle de a, dans celui de b
	_lancer(h, g, 0.4)
	D6Combat.kill_enemy(g, a, {"kind": "melee"})
	h.ok(b.get("stigmate") != null and c.get("stigmate") == null, "contagion : le survivant du souffle est marqué, pas celui qui est hors du rayon")
	g.events.clear()
	D6Combat.kill_enemy(g, b, {"kind": "melee"})
	h.egal(_de(g.events, "explode", "stigmate").size(), 1, "… et il explose à son tour")
	h.ok(c.get("stigmate") != null, "… en marquant le suivant")
	var g0 := _jeu(h, "sceau")
	var a0 := _cible(g0, 150.0, 0.0)
	var b0 := _cible(g0, 150.0 + s.radius * 0.5, 0.0)
	_lancer(h, g0, 0.4)
	D6Combat.kill_enemy(g0, a0, {"kind": "melee"})
	h.egal(b0.get("stigmate"), null, "sans amélioration : l'explosion ne marque personne")
	var m := _pose("revenant", "sceau", "moisson")
	var g2 := _jeu(h, "sceau", "moisson")
	var a2 := _cible(g2, 150.0, 0.0)
	_lancer(h, g2, 0.4)
	g2.player.hp = 50.0
	var cd: float = g2.player.slots[0].cd
	D6Combat.kill_enemy(g2, a2, {"kind": "melee"})
	h.egal(g2.player.hp, 50.0 + m.healOnBlast, "moisson : soin")
	h.proche(g2.player.slots[0].cd, cd * (1.0 - m.refund), 1e-9, "moisson : la recharge restante est réduite")

static func _g_limites(h) -> void:
	var s := _def("sceau")
	var g := _jeu(h, "sceau")
	var evs := _lancer(h, g, 1.0)
	h.egal(_de(evs, "hit").size() + _de(evs, "marked").size(), 0, "salle vide : le trait part et ne touche rien")
	h.proche(g.player.slots[0].cd, s.cooldown - 1.0, 0.05, "la recharge est dépensée")
	h.egal(_tirs(g).size(), 0, "le trait a fini sa course")
	var g2 := _jeu(h, "sceau")
	var boss: Dictionary = D6Enemies.create_enemy(g2, "gardien", g2.player.x + 220.0, g2.player.y, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	var hp0: float = boss.hp
	evs = _lancer(h, g2, 0.5)
	h.ok(boss.hp < hp0 and boss.get("stigmate") != null, "Gardien : blessé et marqué")
	h.egal(_de(evs, "explode").size(), 0, "aucune explosion tant qu'il vit")
	# Le marqué meurt pendant une AUTRE salle : la marque est partie avec lui (ennemis effacés).
	D6Run.enter_floor(g2, g2.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(g2.enemies.filter(func(e): return e.get("stigmate") != null).size(), 0, "changement de salle : aucune marque ne suit")

static func _p_base(h) -> void:
	var s := _def("riposte")
	var g := _jeu(h, "riposte")
	var p: Dictionary = g.player
	var e := _cible(g, 60.0, 0.0)
	e.stun = 0.0
	var evs := _lancer(h, g)
	evs.append_array(h.avancer(g, 1))
	h.egal(_coups(evs, e, "skill"), [_sur(g, s.damage, true)], "la taillade blesse ce qui est devant")
	h.ok(p.get("parry") != null and D6Loadout.slot_state(g, 0).active, "la garde est levée")
	h.egal(_de(evs, "parryStart").size(), 1)
	g.events.clear()
	var perdu := _frapper(g, 25.0, e.x, e.y)
	h.egal(perdu, 0.0, "le coup reçu pendant la garde est paré : aucun dégât")
	h.egal(_de(g.events, "parry").size(), 1, "événement de parade")
	h.egal(_coups(g.events, e, "skill"), [_sur(g, s.damage * s.riposteMult, true)], "la riposte rend `damage` × `riposteMult`")
	h.ok(e.stun > 0.0 and e.stun <= s.stun, "… et étourdit")
	h.egal(p.get("parry"), null, "une seule parade par garde")
	h.ok(p.iframes >= s.parryIframes, "de courtes i-frames couvrent les coups simultanés")
	h.ok(_frapper(g, 25.0, e.x, e.y) > 0.0, "le coup suivant porte")

static func _p_tir(h) -> void:
	var s := _def("riposte")
	var g := _jeu(h, "riposte")
	var p: Dictionary = g.player
	_lancer(h, g)
	h.avancer(g, 1)
	var hp0: float = p.hp
	var tir: Dictionary = D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x + 200.0, "y": p.y, "vx": -900.0, "vy": 0.0, "r": 6.0, "damage": 15.0, "range": 900.0})
	var evs: Array = h.avancer(g, h.ticks(0.4))
	h.egal(p.hp, hp0, "le tir est paré")
	h.ok(D6Js.truthy(tir.get("dead")) and not g.projectiles.has(tir), "… et détruit")
	h.egal(_de(evs, "parry").size(), 1)
	# Sans coup reçu : la garde s'éteint à `window`, et le coup suivant porte.
	var g2 := _jeu(h, "riposte")
	var evs2 := _lancer(h, g2, s.window + 0.1)
	h.egal(_de(evs2, "parryEnd").size(), 1, "la garde s'éteint seule")
	h.egal(g2.player.get("parry"), null)
	h.ok(_frapper(g2, 25.0, g2.player.x + 40.0, g2.player.y) > 0.0, "garde tombée : le coup porte")
	h.egal(_de(g2.events, "parry").size(), 0)

static func _p_choix(h) -> void:
	var s := _def("riposte")
	var miroir := _pose("revenant", "riposte", "miroir")
	var g := _jeu(h, "riposte", "miroir")
	var p: Dictionary = g.player
	var tireur := _cible(g, 420.0, 0.0)
	_lancer(h, g)
	h.avancer(g, 1)
	h.proche(p.parry.t, miroir.window, 0.05, "miroir : garde plus longue")
	var autre: Dictionary = D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x + 60.0, "y": p.y + 90.0, "vx": 0.0, "vy": 1.0, "r": 6.0, "damage": 15.0, "range": 900.0})
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x + 200.0, "y": p.y, "vx": -900.0, "vy": 0.0, "r": 6.0, "damage": 15.0, "range": 900.0, "sourceId": tireur.id})
	var evs: Array = h.avancer(g, h.ticks(1.0))
	h.egal(_de(evs, "parry").size(), 1, "cas choisi : le tir est paré")
	h.ok(D6Js.truthy(autre.get("dead")), "miroir : le tir voisin est effacé")
	h.egal(_coups(evs, tireur, "skill"), [_sur(g, D6Loadout.slot_def(g, 0).damage * s.riposteMult)], "miroir : le tireur, hors de portée de la riposte, reçoit le tir renvoyé")
	var rep := _pose("revenant", "riposte", "represailles")
	var g2 := _jeu(h, "riposte", "represailles")
	_lancer(h, g2)
	h.avancer(g2, 1)
	var cd: float = g2.player.slots[0].cd
	_frapper(g2, 25.0, g2.player.x + 40.0, g2.player.y)
	h.proche(g2.player.slots[0].cd, cd * (1.0 - rep.refund), 1e-9, "représailles : recharge réduite")
	h.egal([g2.player.surge, g2.player.surgeMult], [rep.surge, rep.surgeMult], "… et élan de dégâts")
	var g0 := _jeu(h, "riposte")
	_lancer(h, g0)
	h.avancer(g0, 1)
	var cd0: float = g0.player.slots[0].cd
	_frapper(g0, 25.0, g0.player.x + 40.0, g0.player.y)
	h.egal([g0.player.slots[0].cd, g0.player.surge], [cd0, 0.0], "sans amélioration : ni recharge rendue, ni élan")

static func _p_limites(h) -> void:
	var s := _def("riposte")
	var g := _jeu(h, "riposte")
	var boss: Dictionary = D6Enemies.create_enemy(g, "gardien", g.player.x + 90.0, g.player.y, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	_lancer(h, g)
	h.avancer(g, 1)
	var hp0: float = boss.hp
	h.egal(_frapper(g, 40.0, boss.x, boss.y, "bossCharge"), 0.0, "le coup d'un Gardien se pare aussi")
	h.ok(boss.hp < hp0, "la riposte le blesse")
	h.ok(boss.stun <= 0.0, "… sans l'étourdir")
	var g2 := _jeu(h, "riposte")
	_lancer(h, g2)
	h.avancer(g2, 1)
	h.egal(_frapper(g2, 1e6, g2.player.x + 40.0, g2.player.y), 0.0, "même un coup mortel est paré")
	_frapper(g2, 1e6, g2.player.x + 40.0, g2.player.y)
	h.egal(g2.player.state, "dead", "le suivant tue")
	h.avancer(g2, 1, {"skill1Pressed": true})
	h.avancer(g2, h.ticks(0.5))
	h.egal(g2.player.get("parry"), null, "mort : aucune garde")
	var g3 := _jeu(h, "riposte")
	_lancer(h, g3)
	h.avancer(g3, 1)
	h.ok(g3.player.get("parry") != null)
	D6Run.enter_floor(g3, g3.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(g3.player.get("parry"), null, "changement de salle : la garde tombe")
	# Salle vide : la taillade dans le vide ne casse rien, la recharge part.
	var g4 := _jeu(h, "riposte")
	var evs := _lancer(h, g4, 0.2)
	h.egal(_de(evs, "hit").size(), 0)
	h.proche(g4.player.slots[0].cd, s.cooldown - 0.2, 0.05, "salle vide : recharge dépensée")

# ---------------------------------------------------------------- Bourreau : faille, hache qui revient, garde

static func _tests_bourreau(h) -> void:
	h.test("Faille : la fissure frappe et étourdit tout ce qui se tient sur sa ligne, rien à côté ni au-delà", func(): _f_base(h))
	h.test("Faille : un pilier l'arrête, une rivière non ; au rang 5 elle frappe plus fort et revient plus vite", func(): _f_terrain_rang(h))
	h.test("Faille : « réplique » secoue une seconde fois ; « gouffre » reste ouverte et ralentit ceux qui s'y tiennent", func(): _f_choix(h))
	h.test("Hache du supplice : elle frappe à l'aller, fait demi-tour à sa portée, frappe au retour et revient dans la main", func(): _h_base(h))
	h.test("Hache : un pilier la fait revenir plus tôt ; elle rejoint le héros où qu'il soit ; salle vide, Gardien, changement de salle", func(): _h_limites(h))
	h.test("Hache : « reprise » réduit la recharge quand il la rattrape ; « tournoiement » la fait frapper sur place", func(): _h_choix(h))
	h.test("Garde de fer : le coup de bouclier repousse, puis un coup reçu de face est réduit et son auteur repoussé ; de dos, rien", func(): _d_base(h))
	h.test("Garde : un tir de face est réduit aussi ; elle dure `duration` s ; au rang 5, plus de charges et un bouclier plus large", func(): _d_tir_rang(h))
	h.test("Garde : « épines » blessent et étourdissent l'attaquant paré ; « contrecoup » rend en onde ce qui a été encaissé", func(): _d_choix(h))
	h.test("Garde : mort ou changement de salle, elle tombe ; salle vide, rien ne casse", func(): _d_limites(h))

static func _f_base(h) -> void:
	var s := _def("faille")
	var g := _jeu(h, "faille")
	var pres := _cible(g, 80.0, 0.0)
	var bout := _cible(g, s.range - 10.0, 0.0)
	var a_cote := _cible(g, 200.0, 0.0)
	a_cote.y = g.player.y + s.radius + a_cote.r + 12.0
	var au_dela := _cible(g, 0.0, 0.0)
	au_dela.x = g.player.x + s.range + au_dela.r + 20.0
	var derriere := _cible(g, -80.0, 0.0)
	var evs := _lancer(h, g, s.castTime + 0.1)
	h.egal(_de(evs, "fissure").map(func(ev): return [ev.length, ev.width]), [[s.range, s.radius * 2.0]], "une fissure longue de `range`, large de 2 × `radius`")
	for e in [pres, bout]:
		h.egal(_coups(evs, e, "skill"), [_sur(g, s.damage)], "sur la ligne : frappé")
	for e in [a_cote, au_dela, derriere]:
		h.egal(_coups(evs, e).size(), 0, "à côté, au-delà, derrière : rien")
	var g2 := _jeu(h, "faille")
	var vif := _vif(g2, 120.0, 0.0, "brute")
	_lancer(h, g2, s.castTime + 0.05)
	h.ok(vif.stun > s.stun - 0.2 and vif.stun <= s.stun, "elle étourdit (%s)" % str(vif.stun))
	h.egal(_zones(g2, "faille").size(), 0, "sans amélioration : aucune zone ne reste")
	var g3 := _jeu(h, "faille")
	var evs3 := _lancer(h, g3, 0.5)
	h.egal([_de(evs3, "fissure").size(), _de(evs3, "hit").size()], [1, 0], "salle vide : la fissure part, ne touche rien")
	h.proche(g3.player.slots[0].cd, s.cooldown - 0.5, 0.05)

static func _f_terrain_rang(h) -> void:
	var s := _def("faille")
	var g := _jeu(h, "faille")
	var p: Dictionary = g.player
	g.room.obstacles = [{"x0": p.x + 150.0, "y0": p.y - 50.0, "x1": p.x + 200.0, "y1": p.y + 50.0}]
	var devant := _cible(g, 90.0, 0.0)
	var cache := _cible(g, 260.0, 0.0)
	var evs := _lancer(h, g, s.castTime + 0.1)
	var longueur: float = _de(evs, "fissure")[0].length
	h.ok(longueur <= 150.0 and longueur > 130.0, "le pilier arrête la fissure (%s u)" % str(longueur))
	h.egal([_coups(evs, devant).size(), _coups(evs, cache).size()], [1, 0], "devant le pilier : frappé ; derrière : à l'abri")
	var g2 := _jeu(h, "faille")
	_riviere(g2, g2.player.x + 100.0)
	var rive := _cible(g2, 250.0, 0.0)
	var evs2 := _lancer(h, g2, s.castTime + 0.1)
	h.egal(_de(evs2, "fissure")[0].length, s.range, "une rivière ne l'arrête pas")
	h.egal(_coups(evs2, rive, "skill"), [_sur(g2, s.damage)], "l'ennemi de l'autre rive est frappé")
	var n: Dictionary = Arbre.node(_base(), "bourreau", "faille")
	var g5 := _bac(h, "bourreau", ["faille", null, null], {"faille": _cfg().skillRanks})
	var e5 := _cible(g5, 100.0, 0.0)
	var evs5 := _lancer(h, g5, s.castTime + 0.1)
	h.egal(_coups(evs5, e5, "skill"), [_sur(g5, Arbre.rank_value(n, "damage", _cfg().skillRanks))], "rang 5 : dégâts")
	h.ok(g5.player.slots[0].cd < s.cooldown - 1.0, "rang 5 : recharge plus courte")

static func _f_choix(h) -> void:
	var s := _def("faille")
	var rep := _pose("bourreau", "faille", "replique")
	var g := _jeu(h, "faille", "replique")
	var fort: float = D6Loadout.slot_def(g, 0).damage
	var e := _cible(g, 100.0, 0.0)
	var evs := _lancer(h, g, s.castTime + rep.aftershock + 0.2)
	h.egal(_coups(evs, e, "skill"), [_sur(g, fort), _sur(g, fort * rep.aftershockMult)], "réplique : un second coup, plus faible")
	h.egal(_de(evs, "fissure").size(), 2, "deux secousses sur la même ligne")
	h.egal(_zones(g, "faille").size(), 0, "la réplique passée, rien ne reste")
	var gouffre := _pose("bourreau", "faille", "gouffre")
	var g2 := _jeu(h, "faille", "gouffre")
	var dedans := _vif(g2, 150.0, 0.0, "brute")
	var dehors := _vif(g2, 150.0, 200.0, "brute")
	_lancer(h, g2, s.castTime + 0.1)
	h.egal(_zones(g2, "faille").size(), 1, "gouffre : la fissure reste ouverte")
	h.egal([dedans.chillMult, dehors.chillMult], [1.0 - gouffre.chillMult, 1.0], "qui s'y tient est ralenti, pas son voisin")
	dedans.x = g2.player.x - 300.0 # il en sort
	h.avancer(g2, h.ticks(0.2))
	h.egal(dedans.chillMult, 1.0, "sorti de la fissure : il repart")
	h.avancer(g2, h.ticks(gouffre.fissureTime))
	h.egal(_zones(g2, "faille").size(), 0, "elle se referme après sa durée")

static func _h_base(h) -> void:
	var s := _def("hachette")
	var g := _jeu(h, "hachette")
	var p: Dictionary = g.player
	var e := _cible(g, 180.0, 0.0)
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	var loin := 0.0
	var vus := 0
	for i in h.ticks(2.0):
		evs.append_array(h.avancer(g, 1))
		for tir in _tirs(g):
			vus += 1
			loin = maxf(loin, tir.x - p.x)
			h.egal([tir.kind, tir.damage], ["hache", s.damage])
	h.ok(vus > 20, "la hache a volé")
	h.ok(loin > s.range - 10.0 and loin <= s.range + s.speed * D6Data.DT + p.r, "elle va jusqu'à sa portée, pas plus loin (%s u)" % str(loin))
	h.egal(_coups(evs, e, "skill"), [_sur(g, s.damage), _sur(g, s.damage)], "un coup à l'aller, un coup au retour")
	h.egal([_de(evs, "axeTurn").size(), _de(evs, "axeCatch").size()], [1, 1], "un demi-tour, une main qui la rattrape")
	h.egal(_tirs(g).size(), 0, "elle n'est plus en l'air")
	h.proche(g.player.slots[0].cd, s.cooldown - 2.0, 0.3, "sans amélioration : la recharge suit son cours (aux gels d'impact près)")

static func _h_limites(h) -> void:
	var s := _def("hachette")
	var g := _jeu(h, "hachette")
	var p: Dictionary = g.player
	g.room.obstacles = [{"x0": p.x + 120.0, "y0": p.y - 60.0, "x1": p.x + 170.0, "y1": p.y + 60.0}]
	var cache := _cible(g, 230.0, 0.0)
	var evs := _lancer(h, g, 1.5)
	h.ok(_de(evs, "axeTurn")[0].x < p.x + 120.0, "le pilier la renvoie avant sa portée")
	h.egal([_coups(evs, cache).size(), _de(evs, "axeCatch").size()], [0, 1], "rien derrière le pilier ; elle revient")
	# Le héros s'en va pendant le vol : elle le rejoint.
	var g2 := _jeu(h, "hachette")
	var evs2 := _lancer(h, g2)
	evs2.append_array(h.avancer(g2, h.ticks(2.5), {"moveY": 1.0}))
	h.egal([_de(evs2, "axeCatch").size(), _tirs(g2).size()], [1, 0], "elle revient au héros qui a marché")
	# Gardien : blessé deux fois, sans rien d'autre. Changement de salle en plein vol : la hache est perdue.
	var g3 := _jeu(h, "hachette")
	var boss: Dictionary = D6Enemies.create_enemy(g3, "gardien", g3.player.x + 200.0, g3.player.y, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	h.egal(_coups(_lancer(h, g3, 1.5), boss, "skill").size(), 2, "Gardien : deux coups")
	var g4 := _jeu(h, "hachette")
	_lancer(h, g4, 0.2)
	h.egal(_tirs(g4).size(), 1, "cas choisi : en vol")
	D6Run.enter_floor(g4, g4.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(_tirs(g4).size(), 0, "changement de salle : plus de hache")
	h.egal(_de(h.avancer(g4, h.ticks(1.0)), "axeCatch").size(), 0)
	h.ok(s.range > 0.0)

static func _h_choix(h) -> void:
	var s := _def("hachette")
	var reprise := _pose("bourreau", "hachette", "reprise")
	var restes: Array = []
	for choix in ["reprise", ""]:
		var g := _bac(h, "bourreau", ["hachette", null, null], {"hachette": _cfg().choiceRank}, {"hachette": choix} if choix != "" else {})
		_lancer(h, g)
		for i in h.ticks(3.0):
			if not _de(h.avancer(g, 1), "axeCatch").is_empty():
				restes.append(g.player.slots[0].cd + D6Data.DT) # la recharge au moment où il la rattrape
				break
	h.egal(restes.size(), 2, "cas choisi : rattrapée dans les deux parties")
	h.proche(restes[0], restes[1] * (1.0 - reprise.refund), 1e-6, "reprise : la recharge restante est réduite")
	var tour := _pose("bourreau", "hachette", "tournoiement")
	var g2 := _jeu(h, "hachette", "tournoiement")
	var fort: float = D6Loadout.slot_def(g2, 0).damage
	var e := _cible(g2, s.range + 30.0, 0.0)
	var evs := _lancer(h, g2, 3.5)
	var pulses: int = _de(evs, "kitPulse", "hache").size()
	h.ok(pulses >= int(tour.spin / tour.spinEvery) and pulses <= int(tour.spin / tour.spinEvery) + 1, "tournoiement : un coup toutes les `spinEvery` s pendant `spin` s (%d)" % pulses)
	h.egal(_coups(evs, e, "skill").count(_sur(g2, fort * tour.spinMult)), pulses, "… chacun de `spinMult` des dégâts, à `spinRadius` u")
	h.egal(_de(evs, "axeCatch").size(), 1, "puis elle revient")

static func _d_base(h) -> void:
	var s := _def("garde")
	var g := _jeu(h, "garde")
	var p: Dictionary = g.player
	var e := _vif(g, 50.0, 0.0, "brute")
	var hors := _cible(g, s.radius + 120.0, 0.0)
	var evs := _lancer(h, g)
	h.egal(p.slots[0].charges, s.chargesPerSection - 1.0)
	h.egal(_coups(evs, e, "gadget"), [_sur(g, s.damage, true)], "le coup de bouclier blesse ce qui est à portée")
	h.egal(_coups(evs, hors).size(), 0)
	h.ok(e.kvx > 0.0, "… et repousse")
	h.ok(p.get("guard") != null and D6Loadout.slot_state(g, 0).active, "la garde est levée")
	e.kvx = 0.0
	p.facing = 0.0
	var armure: float = 1.0 - D6Geo.clampv(p.stats.armor, 0.0, g.tuning.combat.armorCap)
	var perdu := _frapper(g, 40.0, e.x, e.y)
	h.egal(perdu, maxf(1.0, D6Js.jround(40.0 * (1.0 - s.reduce) * armure)), "un coup de FACE est réduit de `reduce`")
	h.ok(e.kvx > 0.0, "son auteur est repoussé")
	h.egal(_de(g.events, "guardBlock").size(), 1)
	h.egal(_coups(g.events, e).size(), 0, "sans amélioration : l'attaquant n'est pas blessé")
	g.events.clear()
	h.egal(_frapper(g, 40.0, p.x - 50.0, p.y), maxf(1.0, D6Js.jround(40.0 * armure)), "un coup dans le DOS passe entier")
	h.egal(_de(g.events, "guardBlock").size(), 0)
	h.egal(_frapper(g, 40.0, p.x, p.y), maxf(1.0, D6Js.jround(40.0 * (1.0 - s.reduce) * armure)), "un coup sans origine compte comme de face")

static func _d_tir_rang(h) -> void:
	var s := _def("garde")
	var g := _jeu(h, "garde")
	var p: Dictionary = g.player
	var evs := _lancer(h, g)
	p.facing = 0.0
	var hp0: float = p.hp
	var armure: float = 1.0 - D6Geo.clampv(p.stats.armor, 0.0, g.tuning.combat.armorCap)
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x + 200.0, "y": p.y, "vx": -900.0, "vy": 0.0, "r": 6.0, "damage": 30.0, "range": 900.0})
	h.avancer(g, h.ticks(0.4))
	h.egal(hp0 - p.hp, maxf(1.0, D6Js.jround(30.0 * (1.0 - s.reduce) * armure)), "un tir de face est réduit")
	evs = h.avancer(g, h.ticks(s.duration))
	h.egal([_de(evs, "guardEnd").size(), p.get("guard")], [1, null], "la garde tombe après `duration` s")
	h.egal(_de(evs, "explode").size(), 0, "sans amélioration : aucune onde à la fin")
	h.egal(_frapper(g, 40.0, p.x + 50.0, p.y), maxf(1.0, D6Js.jround(40.0 * armure)), "garde tombée : le coup de face passe entier")
	var n: Dictionary = Arbre.node(_base(), "bourreau", "garde")
	var g5 := _bac(h, "bourreau", ["garde", null, null], {"garde": _cfg().skillRanks})
	h.egal(g5.player.slots[0].charges, Arbre.rank_value(n, "chargesPerSection", _cfg().skillRanks), "rang 5 : charges")
	var large: float = Arbre.rank_value(n, "radius", _cfg().skillRanks)
	var e5 := _cible(g5, 0.0, 0.0)
	e5.x = g5.player.x + s.radius + e5.r + 8.0 # hors du bouclier de base, dans celui du rang 5
	h.ok(large > s.radius + 8.0, "cas choisi")
	h.egal(_coups(_lancer(h, g5), e5, "gadget").size(), 1, "rang 5 : le coup de bouclier porte plus loin")

static func _d_choix(h) -> void:
	var s := _def("garde")
	var epines := _pose("bourreau", "garde", "epines")
	var g := _jeu(h, "garde", "epines")
	var p: Dictionary = g.player
	var e := _vif(g, 50.0, 0.0, "brute")
	_lancer(h, g)
	p.facing = 0.0
	g.events.clear()
	_frapper(g, 40.0, e.x, e.y)
	h.egal(_coups(g.events, e, "gadget"), [_sur(g, epines.thorns, true)], "épines : l'attaquant paré est blessé")
	h.ok(e.stun > 0.0 and e.stun <= epines.thornStun, "… et étourdi")
	var contre := _pose("bourreau", "garde", "contrecoup")
	var g2 := _jeu(h, "garde", "contrecoup")
	var e2 := _cible(g2, contre.burstRadius - 20.0, 0.0)
	_lancer(h, g2)
	g2.player.facing = 0.0
	_frapper(g2, 40.0, g2.player.x + 50.0, g2.player.y)
	var echelle: float = D6Floors.floor_scaling(g2.tuning, g2.run.floor).damage
	var rendu: float = minf(contre.burstCap, 40.0 * s.reduce / echelle * contre.burstMult)
	var evs: Array = h.avancer(g2, h.ticks(s.duration + 0.1))
	h.egal(_de(evs, "explode", "garde").map(func(ev): return ev.r), [contre.burstRadius], "contrecoup : une onde à la fin de la garde")
	h.egal(_coups(evs, e2, "gadget"), [_sur(g2, rendu)], "… qui rend `burstMult` fois ce qui a été encaissé")
	# Plafond, et rien si rien n'a été encaissé.
	var g3 := _jeu(h, "garde", "contrecoup", {"godMode": false})
	var e3 := _cible(g3, contre.burstRadius - 20.0, 0.0)
	_lancer(h, g3)
	g3.player.facing = 0.0
	g3.player.hp = 1e6
	_frapper(g3, 5000.0, g3.player.x + 50.0, g3.player.y)
	h.egal(_coups(h.avancer(g3, h.ticks(s.duration + 0.1)), e3, "gadget"), [_sur(g3, contre.burstCap)], "jamais plus de `burstCap`")
	var g4 := _jeu(h, "garde", "contrecoup")
	_lancer(h, g4)
	h.egal(_de(h.avancer(g4, h.ticks(s.duration + 0.1)), "explode").size(), 0, "rien encaissé : aucune onde")

static func _d_limites(h) -> void:
	var s := _def("garde")
	var g := _jeu(h, "garde")
	var evs := _lancer(h, g)
	h.egal(_de(evs, "gadget").map(func(ev): return ev.r), [s.radius], "salle vide : le coup de bouclier part dans le vide")
	g.player.facing = 0.0
	_frapper(g, 1e6, g.player.x - 40.0, g.player.y)
	h.avancer(g, h.ticks(0.5)) # le gel du coup reçu passe d'abord
	h.egal([g.player.state, g.player.get("guard")], ["dead", null], "mort (frappé dans le dos) : la garde tombe")
	var g2 := _jeu(h, "garde")
	_lancer(h, g2)
	D6Run.enter_floor(g2, g2.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(g2.player.get("guard"), null, "changement de salle : la garde tombe")
	# Gardien : son coup de face est réduit, il n'est pas repoussé comme un ennemi ordinaire (masse de Gardien).
	var g3 := _jeu(h, "garde")
	var boss: Dictionary = D6Enemies.create_enemy(g3, "gardien", g3.player.x + 150.0, g3.player.y, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	_lancer(h, g3)
	g3.player.facing = 0.0
	var armure: float = 1.0 - D6Geo.clampv(g3.player.stats.armor, 0.0, g3.tuning.combat.armorCap)
	h.egal(_frapper(g3, 60.0, boss.x, boss.y, "bossCharge"), maxf(1.0, D6Js.jround(60.0 * (1.0 - s.reduce) * armure)), "Gardien : son coup de face est réduit")
	h.ok(boss.stun <= 0.0, "… et il n'est pas étourdi")

# ---------------------------------------------------------------- Chasseresse : marque, leurre, trait

static func _tests_chasseresse(h) -> void:
	h.test("Marque de la proie : le marqué subit `vulnMult` de dégâts en plus pendant `vuln` s ; la visée assistée le préfère", func(): _m_base(h))
	h.test("Marque : les limiers de la Meute prennent la proie pour cible ; au rang 5 elle fait subir plus et revient plus vite", func(): _m_meute_rang(h))
	h.test("Marque : « curée » saute sur le plus proche quand la proie meurt, deux fois au plus ; « battue » marque tout le groupe", func(): _m_choix(h))
	h.test("Marque : salle vide, Gardien (marqué, vulnérable), changement de salle", func(): _m_limites(h))
	h.test("Leurre d'os : un allié posé, jamais un ennemi ; la mêlée s'y jette et le frappe ; il disparaît après `life` s", func(): _l_base(h))
	h.test("Leurre : il arrête les tirs ; un tireur et un Gardien ne se détournent pas ; `maxActive` au plus", func(): _l_regles(h))
	h.test("Leurre : il n'est pas un ultime — la jauge se remplit, l'ultime se lance, la meute garde sa minuterie", func(): _l_pas_ultime(h))
	h.test("Leurre : jamais dans l'eau, un mur ni un obstacle, sur %d graines de salles à terrain ; sans place, la charge reste" % GRAINES_EAU, func(): _l_eau(h))
	h.test("Leurre : la salle est nettoyée quand le dernier ENNEMI tombe, leurre debout ou non ; il part avec la salle et à la mort", func(): _l_salle(h))
	h.test("Leurre : « piégé » explose, détruit ou à bout de temps ; « épouvantail » étourdit en apparaissant et encaisse le double", func(): _l_choix(h))
	h.test("Trait de Nemrod : un appui bande l'arc, le trait part seul à pleine charge et traverse tout ; l'entrée d'un pas n'a pas changé", func(): _t_base(h))
	h.test("Trait : un second appui le lâche aussitôt, d'autant moins fort qu'il est tôt ; un dash le lâche aussi", func(): _t_second(h))
	h.test("Trait : sans visée manuelle il vise au moment de partir ; « clouage » n'étourdit qu'à pleine charge ; « trait vif » se bande plus vite", func(): _t_choix(h))
	h.test("Trait : mort pendant la charge, rien ne part ; salle vide ; Gardien ; rang 5", func(): _t_limites(h))

static func _m_base(h) -> void:
	var s := _def("proie")
	var g := _jeu(h, "proie")
	var p: Dictionary = g.player
	var pres := _cible(g, 120.0, -50.0)
	var proie := _cible(g, 250.0, 40.0)
	h.egal(D6Aim.compute_aim(g, 0.0, 0.0, 600.0).targetId, pres.id, "avant la marque : la visée assistée prend le plus proche")
	var evs := _lancer(h, g, 0.4, 250.0, 40.0)
	h.egal(_coups(evs, proie, "skill"), [_sur(g, s.damage * (1.0 + s.vulnMult))], "le trait touche la proie visée (déjà marquée : la marque est posée avant le coup)")
	h.ok(proie.get("proie") != null and pres.get("proie") == null, "elle seule est marquée")
	h.egal(proie.vulnMult, s.vulnMult, "vulnérabilité des données")
	h.ok(proie.vuln > s.vuln - 0.6 and proie.vuln <= s.vuln, "pour la durée des données (%s)" % str(proie.vuln))
	var marque: float = D6Combat.damage_enemy(g, proie, {"kind": "melee", "amount": 22.0, "canCrit": false})
	var nu: float = D6Combat.damage_enemy(g, pres, {"kind": "melee", "amount": 22.0, "canCrit": false})
	h.egal([nu, marque], [_sur(g, 22.0), _sur(g, 22.0 * (1.0 + s.vulnMult))], "un coup d'arme lui fait `vulnMult` de plus")
	p.facing = 0.0
	p.lastTargetAt = -99.0
	h.egal(D6Aim.compute_aim(g, 0.0, 0.0, 600.0).targetId, proie.id, "après : la visée assistée préfère la proie, même plus loin")
	h.avancer(g, h.ticks(s.vuln + 0.2))
	h.egal([proie.get("proie"), proie.vulnMult], [null, 0.0], "la marque tombe après sa durée")
	p.lastTargetAt = -99.0
	h.egal(D6Aim.compute_aim(g, 0.0, 0.0, 600.0).targetId, pres.id, "… et la visée revient au plus proche")

static func _m_meute_rang(h) -> void:
	var s := _def("proie")
	var g := _jeu(h, "proie")
	var p: Dictionary = g.player
	var pres := _cible(g, -90.0, 0.0)
	var proie := _cible(g, 0.0, 300.0)
	Meute.summon(g, Meute.def_of(g))
	h.avancer(g, 3)
	h.egal(g.allies.map(func(a): return a.targetId), [pres.id, pres.id, pres.id], "cas choisi : sans marque, les limiers vont au plus proche")
	_lancer(h, g, 0.5, 0.0, 1.0)
	h.ok(proie.get("proie") != null, "cas choisi : la proie est marquée")
	h.egal(g.allies.map(func(a): return a.targetId), [proie.id, proie.id, proie.id], "les limiers se jettent sur la proie marquée")
	var n: Dictionary = Arbre.node(_base(), "chasseresse", "proie")
	var g5 := _bac(h, "chasseresse", ["proie", null, null], {"proie": _cfg().skillRanks})
	var e5 := _cible(g5, 200.0, 0.0)
	_lancer(h, g5, 0.4)
	h.egal(e5.vulnMult, Arbre.rank_value(n, "vulnMult", _cfg().skillRanks), "rang 5 : vulnérabilité")
	h.ok(g5.player.slots[0].cd < s.cooldown - 1.5, "rang 5 : recharge plus courte")
	h.ok(p.hp > 0.0)

static func _m_choix(h) -> void:
	var curee := _pose("chasseresse", "proie", "curee")
	var g := _jeu(h, "proie", "curee")
	var file: Array = [_cible(g, 200.0, 0.0), _cible(g, 200.0, 100.0), _cible(g, 200.0, 200.0), _cible(g, 200.0, 300.0)]
	var loin := _cible(g, 200.0, -(curee.jumpRange + 150.0))
	_lancer(h, g, 0.4)
	h.ok(file[0].get("proie") != null and file[0].proie.jumps == curee.jumps, "cas choisi : la première est marquée")
	for i in int(curee.jumps):
		g.events.clear()
		D6Combat.kill_enemy(g, file[i], {"kind": "melee"})
		h.ok(file[i + 1].get("proie") != null and file[i + 1].vulnMult > 0.0, "curée : saut %d sur le plus proche" % (i + 1))
		h.egal(_de(g.events, "markJump").size(), 1)
	D6Combat.kill_enemy(g, file[int(curee.jumps)], {"kind": "melee"})
	h.egal(file[int(curee.jumps) + 1].get("proie"), null, "… pas plus de `jumps` fois")
	h.egal(loin.get("proie"), null, "jamais au-delà de `jumpRange`")
	var battue := _pose("chasseresse", "proie", "battue")
	var g2 := _jeu(h, "proie", "battue")
	var a := _cible(g2, 200.0, 0.0)
	var b := _cible(g2, 200.0 + battue.blastRadius * 0.6, 0.0)
	var c := _cible(g2, 200.0, battue.blastRadius + 120.0)
	_lancer(h, g2, 0.4)
	h.ok(a.get("proie") != null and b.get("proie") != null and c.get("proie") == null, "battue : le voisin est marqué, pas celui qui est hors du rayon")
	h.egal(b.vulnMult, D6Loadout.slot_def(g2, 0).vulnMult)
	var g0 := _jeu(h, "proie")
	var a0 := _cible(g0, 200.0, 0.0)
	var b0 := _cible(g0, 260.0, 0.0)
	_lancer(h, g0, 0.4)
	D6Combat.kill_enemy(g0, a0, {"kind": "melee"})
	h.egal(b0.get("proie"), null, "sans amélioration : ni saut, ni groupe")

static func _m_limites(h) -> void:
	var s := _def("proie")
	var g := _jeu(h, "proie")
	var evs := _lancer(h, g, 1.0)
	h.egal(_de(evs, "hit").size() + _de(evs, "marked").size(), 0, "salle vide : rien")
	h.proche(g.player.slots[0].cd, s.cooldown - 1.0, 0.05)
	var g2 := _jeu(h, "proie")
	var boss: Dictionary = D6Enemies.create_enemy(g2, "gardien", g2.player.x + 220.0, g2.player.y, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	_lancer(h, g2, 0.5)
	h.ok(boss.get("proie") != null and boss.vulnMult == s.vulnMult, "Gardien : marqué, vulnérable")
	D6Run.enter_floor(g2, g2.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(g2.enemies.filter(func(e): return e.get("proie") != null).size(), 0, "changement de salle : aucune marque ne suit")

static func _l_base(h) -> void:
	var s := _def("leurre")
	var g := _jeu(h, "leurre")
	var p: Dictionary = g.player
	var evs := _lancer(h, g)
	var leurres := _leurres(g)
	h.egal(leurres.size(), 1, "un leurre dans game.allies")
	var a: Dictionary = leurres[0]
	h.egal(g.enemies.size(), 0, "jamais dans game.enemies")
	h.egal(D6Enemies.alive_enemies(g), 0.0, "« ennemis restants » ne le voit pas")
	h.proche(a.x - p.x, s.throwDist, 1e-6, "lancé devant elle, à `throwDist` sans cible")
	h.egal([a.hp, a.lifeMax, a.r], [maxf(1.0, D6Js.jround(s.hp * D6Floors.floor_scaling(g.tuning, g.run.floor).damage)), s.life, s.bodyRadius], "vie (à l'échelle de l'étage), durée, corps")
	h.proche(a.life, s.life, 0.02, "sa durée court dès la pose")
	h.egal(p.slots[0].charges, s.chargesPerSection - 1.0)
	h.egal(_de(evs, "allySpawn").map(func(ev): return ev.get("kind")), ["leurre"])
	h.egal(_de(evs, "gadget").map(func(ev): return ev.r), [s.radius])
	# Un diablotin en chasse, plus près du leurre que d'elle : il s'y jette et le frappe.
	var imp := _vif(g, s.throwDist + 90.0, 0.0, "imp", true)
	evs = h.avancer(g, h.ticks(2.5))
	h.egal(imp.get("allyId"), a.id, "l'ennemi de mêlée s'est tourné vers le leurre")
	h.ok(_de(evs, "allyHurt").size() >= 1 and a.hp < a.maxHp, "… et le frappe")
	h.egal(_de(evs, "playerHurt").size(), 0, "elle n'est pas touchée")
	evs = h.avancer(g, h.ticks(s.life))
	h.egal(_leurres(g).size(), 0, "il disparaît après `life` s (ou détruit)")
	h.ok(_de(evs, "allyGone").size() + _de(evs, "allyDeath").size() >= 1)

static func _l_regles(h) -> void:
	var s := _def("leurre")
	var g := _jeu(h, "leurre")
	var p: Dictionary = g.player
	_lancer(h, g)
	var a: Dictionary = _leurres(g)[0]
	var hp0: float = p.hp
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": a.x + 200.0, "y": a.y, "vx": -900.0, "vy": 0.0, "r": 6.0, "damage": 5.0, "range": 900.0})
	h.avancer(g, h.ticks(0.5))
	h.egal([p.hp, g.projectiles.size()], [hp0, 0], "le tir s'arrête sur le leurre")
	h.ok(a.hp < a.maxHp, "… qui encaisse")
	var archer := _vif(g, s.throwDist + 80.0, 60.0, "archer")
	var boss: Dictionary = D6Enemies.create_enemy(g, "gardien", a.x + 120.0, a.y - 80.0, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	h.avancer(g, 5)
	h.egal([D6Js.nz(archer.get("allyId"), 0.0), D6Js.nz(boss.get("allyId"), 0.0)], [0.0, 0.0], "ni un tireur ni un Gardien ne se détournent")
	# Au-delà de maxActive, le plus ancien disparaît.
	var g2 := _jeu(h, "leurre")
	g2.player.slots[0].charges = s.maxActive + 1.0
	var ids: Array = []
	for dir in [[1.0, 0.0], [0.0, 1.0], [-1.0, 0.0]]:
		_lancer(h, g2, 0.0, dir[0], dir[1])
		ids.append(g2.allies[g2.allies.size() - 1].id)
		h.avancer(g2, 2)
	h.egal(_leurres(g2).map(func(x): return x.id), ids.slice(1), "`maxActive` au plus : le plus ancien a disparu")

static func _l_pas_ultime(h) -> void:
	var g := _jeu(h, "leurre")
	var p: Dictionary = g.player
	_lancer(h, g)
	h.egal([D6KitSupers.acting(g), D6Player.ultimate_view(g).allies, D6Player.ultimate_view(g).active], [false, 0.0, false], "un leurre debout : aucun ultime n'agit")
	p.superCharge = 0.2
	var e := _cible(g, 60.0, 0.0)
	D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 30.0, "canCrit": false})
	h.ok(p.superCharge > 0.2, "la jauge d'ultime se remplit, leurre debout")
	h.avancer(g, 3)
	h.ok(p.superCharge > 0.2, "… et le leurre ne la vide pas")
	p.superCharge = 1.0
	h.avancer(g, 1)
	h.ultime(g)
	h.egal(Meute.hounds(g), g.tuning["super"].count, "l'ultime se lance : la meute apparaît à côté du leurre")
	h.egal(D6Player.ultimate_view(g).allies, g.tuning["super"].count, "ultimate_view ne compte que les limiers")
	h.egal(_leurres(g).size(), 1)
	h.avancer(g, h.ticks(1.0))
	h.ok(p.superCharge < 1.0 and p.superCharge > 0.5, "la jauge est la minuterie de la MEUTE (%s)" % str(p.superCharge))

static func _dans_le_dur(room: Dictionary, a: Dictionary) -> bool:
	return D6Physics.point_blocked(room, a.x, a.y, 0.0)

static func _l_eau(h) -> void:
	var s := _def("leurre")
	var meta := _meta("chasseresse", ["leurre", null, null])
	var avec_terrain := 0
	var poses := 0
	var fautes := 0
	for graine in GRAINES_EAU:
		var g: Dictionary = h.partie({"seed": 9000.0 + graine, "startFloor": 5.0 + float(graine % 60) * 7.0, "meta": meta, "godMode": true})
		if g.room.low.is_empty():
			continue
		avec_terrain += 1
		var r: Dictionary = D6Rng.create_rng(graine + 1)
		var p: Dictionary = g.player
		for essai in 60:
			var x: float = g.room.pad + D6Rng.rand(r) * (g.room.w - 2.0 * g.room.pad)
			var y: float = g.room.pad + D6Rng.rand(r) * (g.room.h - 2.0 * g.room.pad)
			if not D6Physics.ground_blocked(g.room, x, y, p.r + 1.0):
				p.x = x
				p.y = y
				break
		for k in 8:
			p.slots[0].charges = 1.0
			var ang: float = float(k) / 8.0 * TAU + D6Rng.rand(r)
			D6Game.step_game(g, h.entree({"skill1Pressed": true, "skill1AimX": D6Trig.cos(ang), "skill1AimY": D6Trig.sin(ang)}))
			g.events.clear()
			for a in _leurres(g):
				poses += 1
				if D6Physics.ground_blocked(g.room, a.x, a.y, a.r) and fautes == 0:
					h.ok(false, "graine %d : leurre posé où rien ne se pose (%s, %s)" % [graine, str(a.x), str(a.y)])
				if D6Physics.ground_blocked(g.room, a.x, a.y, a.r):
					fautes += 1
	h.ok(avec_terrain >= 30, "assez de salles à terrain bas dans l'échantillon (%d)" % avec_terrain)
	h.ok(poses > avec_terrain * 4, "les leurres ont bien été posés (%d)" % poses)
	h.egal(fautes, 0, "aucun leurre dans l'eau, un mur ou un obstacle")
	# Le lancer par-dessus une rivière trop large recule jusqu'à la rive ; sans aucune place, la charge reste.
	var g2 := _jeu(h, "leurre")
	var p2: Dictionary = g2.player
	_riviere(g2, p2.x + 60.0, 400.0)
	_lancer(h, g2)
	var a2: Dictionary = _leurres(g2)[0]
	h.ok(a2.x + a2.r <= p2.x + 60.0, "posé sur la rive, devant l'eau (x = %s)" % str(a2.x - p2.x))
	var g3 := _jeu(h, "leurre")
	g3.room.low = [{"x0": 0.0, "y0": 0.0, "x1": g3.room.w, "y1": g3.room.h, "kind": "river"}]
	var evs := _lancer(h, g3)
	h.egal([_leurres(g3).size(), g3.player.slots[0].charges, _de(evs, "gadget").size()], [0, s.chargesPerSection, 0], "aucune place : rien n'est posé, la charge n'est pas dépensée")

static func _l_salle(h) -> void:
	var meta := _meta("chasseresse", ["leurre", null, null])
	var g: Dictionary = h.partie({"seed": 31.0, "startFloor": 2.0, "meta": meta, "godMode": true})
	var debout_a_la_fin := false
	var pas := 0
	while not g.room.cleared and pas < 3000:
		pas += 1
		g.player.slots[0].charges = 1.0
		D6Game.step_game(g, h.entree({"skill1Pressed": _leurres(g).is_empty(), "skill1AimX": 1.0}))
		for e in g.enemies:
			if not e.dead and e.spawnT <= 0.0:
				D6Combat.kill_enemy(g, e, {"kind": "melee"})
		debout_a_la_fin = not _leurres(g).is_empty()
		if g.mode != "play":
			break
	D6Game.step_game(g, D6Game.empty_input())
	h.egal(g.room.cleared, true, "la salle est nettoyée (en %d pas)" % pas)
	h.egal(g.telemetry.roomsCleared, 1.0, "… comptée une fois")
	h.ok(debout_a_la_fin, "cas choisi : un leurre était debout quand le dernier ennemi est tombé")
	# Changement de salle, puis mort : plus aucun allié.
	var g2 := _jeu(h, "leurre")
	_lancer(h, g2)
	D6Run.enter_floor(g2, g2.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(g2.allies.size(), 0, "changement de salle : le leurre ne suit pas")
	var g3 := _jeu(h, "leurre")
	_lancer(h, g3)
	g3.player.superCharge = 0.7
	D6Combat.damage_player(g3, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	h.avancer(g3, h.ticks(0.5)) # le gel du coup reçu passe d'abord
	h.egal(g3.allies.size(), 0, "mort : le leurre disparaît")
	h.egal(g3.player.superCharge, 0.7, "… sans toucher à la jauge d'ultime (ce n'est pas la meute)")

static func _l_choix(h) -> void:
	var s := _def("leurre")
	var piege := _pose("chasseresse", "leurre", "piege")
	var g := _jeu(h, "leurre", "piege")
	_lancer(h, g)
	var a: Dictionary = _leurres(g)[0]
	var e := _cible(g, 0.0, 0.0)
	e.x = a.x + 60.0
	var evs: Array = h.avancer(g, h.ticks(s.life + 0.1))
	h.egal(_de(evs, "explode", "leurre").map(func(ev): return ev.r), [piege.blastRadius], "piégé : à bout de temps, il explose")
	h.egal(_coups(evs, e, "gadget"), [_sur(g, piege.blastDamage)])
	var g2 := _jeu(h, "leurre", "piege")
	_lancer(h, g2)
	Meute.hurt(g2, _leurres(g2)[0], 1e6, "imp")
	h.egal(_de(h.avancer(g2, 2), "explode", "leurre").size(), 1, "piégé : détruit, il explose aussi")
	var g0 := _jeu(h, "leurre")
	_lancer(h, g0)
	h.egal(_de(h.avancer(g0, h.ticks(s.life + 0.1)), "explode").size(), 0, "sans amélioration : il s'éteint sans bruit")
	var peur := _pose("chasseresse", "leurre", "epouvantail")
	var g3 := _jeu(h, "leurre", "epouvantail")
	var pres := _vif(g3, s.throwDist + 100.0, 0.0, "imp")
	var loin := _vif(g3, s.throwDist, D6Loadout.slot_def(g3, 0).radius + 200.0, "imp")
	_lancer(h, g3)
	h.ok(pres.stun > 0.0 and pres.stun <= peur.fear and loin.stun <= 0.0, "épouvantail : étourdit ce qui est à sa portée, pas plus loin")
	h.egal(pres.hp, pres.maxHp, "… sans blesser")
	h.egal(_leurres(g3)[0].maxHp, maxf(1.0, D6Js.jround(s.hp * peur.hpMult * D6Floors.floor_scaling(g3.tuning, g3.run.floor).damage)), "… et encaisse `hpMult` fois plus")

static func _t_base(h) -> void:
	var s := _def("trait")
	h.egal(D6Game.empty_input().keys(), ENTREE, "l'entrée d'un pas n'a AUCUN champ de plus : le trait se bande d'un appui")
	var g := _jeu(h, "trait")
	var p: Dictionary = g.player
	var file: Array = [_cible(g, 150.0, 0.0), _cible(g, 300.0, 0.0), _cible(g, 450.0, 0.0)]
	var evs := _lancer(h, g)
	h.egal([p.state, D6Loadout.slot_state(g, 0).charging], ["cast", true], "un appui : elle bande son arc")
	h.egal(_tirs(g).size(), 0, "rien n'est parti")
	h.avancer(g, h.ticks(s.castTime * 0.5))
	var mi: float = D6Loadout.slot_state(g, 0).chargeFrac
	h.ok(mi > 0.4 and mi < 0.65, "slot_state : la charge monte (%s à mi-course)" % str(mi))
	evs = h.avancer(g, h.ticks(s.castTime * 0.5 + 0.5))
	h.egal(_de(evs, "traitShot").map(func(ev): return [ev.charge, ev.full]), [[1.0, true]], "à pleine charge il part seul")
	for e in file:
		h.egal(_coups(evs, e, "skill"), [_sur(g, s.damage)], "il traverse toute la file, à pleins dégâts")
	h.egal([p.state, D6Loadout.slot_state(g, 0).charging], ["free", false])
	h.egal(_de(evs, "skill").map(func(ev): return ev.skill), ["trait"], "événement de compétence, une fois")
	h.proche(p.slots[0].cd, s.cooldown - s.castTime - 0.5, 0.3, "la recharge court depuis l'appui (aux gels d'impact près)")

static func _t_second(h) -> void:
	var s := _def("trait")
	var avant := 1e9
	for attente in [0, 20, 40]:
		var g := _jeu(h, "trait")
		var e := _cible(g, 200.0, 0.0)
		_lancer(h, g)
		h.avancer(g, attente)
		var frac: float = D6Geo.clampv(1.0 - g.player.castT / s.castTime, 0.0, 1.0)
		var evs: Array = h.avancer(g, 1, {"skill1Pressed": true})
		evs.append_array(h.avancer(g, h.ticks(0.4)))
		var attendu: float = s.damage * (s.minCharge + (1.0 - s.minCharge) * frac)
		h.egal(_coups(evs, e, "skill"), [_sur(g, attendu)], "second appui après %d pas : dégâts à la charge du moment (%s)" % [attente, str(frac)])
		h.egal(_de(evs, "traitShot").map(func(ev): return ev.full), [false])
		h.ok(attendu < s.damage and (attente == 0 or attendu > avant) and attendu >= s.damage * s.minCharge, "plus on attend, plus il frappe ; jamais moins que `minCharge`")
		avant = attendu
		h.egal(_de(h.avancer(g, h.ticks(s.castTime)), "traitShot").size(), 0, "un seul trait par lancer")
	# Un dash pendant la charge : le trait part (comme toute compétence interrompue), puis elle roule.
	var g2 := _jeu(h, "trait")
	var e2 := _cible(g2, 200.0, 0.0)
	_lancer(h, g2)
	h.avancer(g2, 15)
	var evs2: Array = h.avancer(g2, 1, {"moveY": 1.0, "dashPressed": true})
	evs2.append_array(h.avancer(g2, h.ticks(0.4)))
	h.egal(_de(evs2, "traitShot").size(), 1, "le dash lâche le trait")
	h.egal(_coups(evs2, e2, "skill").size(), 1)
	h.egal(_de(evs2, "dash").size(), 1)

static func _t_choix(h) -> void:
	var s := _def("trait")
	# Visée assistée : la cible s'est déplacée pendant la charge, le trait part vers où elle EST.
	var g := _bac(h, "chasseresse", ["trait", null, null])
	var e := _cible(g, 200.0, 0.0)
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true})
	e.x = g.player.x
	e.y = g.player.y + 220.0
	evs = h.avancer(g, h.ticks(s.castTime + 0.4))
	h.egal(_coups(evs, e, "skill"), [_sur(g, s.damage)], "il vise au moment de partir")
	var clou := _pose("chasseresse", "trait", "clouage")
	var g2 := _jeu(h, "trait", "clouage")
	var vif := _vif(g2, 200.0, 0.0, "brute")
	_lancer(h, g2, D6Loadout.slot_def(g2, 0).castTime + 0.2)
	h.ok(vif.stun > clou.stun - 0.4 and vif.stun <= clou.stun, "clouage : à pleine charge, il étourdit (%s)" % str(vif.stun))
	var g3 := _jeu(h, "trait", "clouage")
	var vif3 := _vif(g3, 200.0, 0.0, "brute")
	_lancer(h, g3)
	h.avancer(g3, 10)
	var evs3: Array = h.avancer(g3, 1, {"skill1Pressed": true})
	evs3.append_array(h.avancer(g3, h.ticks(0.3)))
	h.egal([_coups(evs3, vif3, "skill").size(), vif3.stun <= 0.0], [1, true], "… lâché avant, il blesse sans étourdir")
	var rapide := _pose("chasseresse", "trait", "vif")
	var g4 := _jeu(h, "trait", "vif")
	var e4 := _cible(g4, 200.0, 0.0)
	var evs4: Array = h.avancer(g4, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
	var portee := -1.0
	for i in h.ticks(rapide.castTime + 0.4):
		evs4.append_array(h.avancer(g4, 1))
		if portee < 0.0 and not _tirs(g4).is_empty():
			portee = _tirs(g4)[0].range
	h.egal(_de(evs4, "traitShot").map(func(ev): return ev.full), [true], "trait vif : parti en `castTime` court, à pleine charge")
	h.egal(portee, rapide.range, "… à portée réduite")
	h.egal(_coups(evs4, e4, "skill"), [_sur(g4, D6Loadout.slot_def(g4, 0).damage)])
	h.ok(rapide.castTime < s.castTime)

static func _t_limites(h) -> void:
	var s := _def("trait")
	var g := _jeu(h, "trait")
	_lancer(h, g)
	h.avancer(g, 10)
	D6Combat.damage_player(g, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	var evs: Array = h.avancer(g, h.ticks(s.castTime + 0.5))
	h.egal([g.player.state, _de(evs, "traitShot").size(), _tirs(g).size()], ["dead", 0, 0], "mort pendant la charge : rien ne part")
	var g2 := _jeu(h, "trait")
	var evs2 := _lancer(h, g2, s.castTime + 1.0)
	h.egal([_de(evs2, "traitShot").size(), _de(evs2, "hit").size(), _tirs(g2).size()], [1, 0, 0], "salle vide : il part devant elle et finit sa course")
	var g3 := _jeu(h, "trait")
	var boss: Dictionary = D6Enemies.create_enemy(g3, "gardien", g3.player.x + 250.0, g3.player.y, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	h.egal(_coups(_lancer(h, g3, s.castTime + 0.4), boss, "skill").size(), 1, "Gardien : un coup")
	var n: Dictionary = Arbre.node(_base(), "chasseresse", "trait")
	var g5 := _bac(h, "chasseresse", ["trait", null, null], {"trait": _cfg().skillRanks})
	var e5 := _cible(g5, 200.0, 0.0)
	h.egal(_coups(_lancer(h, g5, s.castTime + 0.4), e5, "skill"), [_sur(g5, Arbre.rank_value(n, "damage", _cfg().skillRanks))], "rang 5 : dégâts")
	# Changement de salle pendant la charge : l'arc est détendu, rien ne part dans la salle neuve.
	var g6 := _jeu(h, "trait")
	_lancer(h, g6)
	h.avancer(g6, 10)
	D6Run.enter_floor(g6, g6.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(_de(h.avancer(g6, h.ticks(s.castTime + 0.3)), "traitShot").size(), 0, "changement de salle : rien ne part")

# ---------------------------------------------------------------- ce qui vaut pour toutes

static func _tests_communs(h) -> void:
	h.test("bénédictions et objets : dégâts des compétences, recharge, charges en plus et procs « de compétence » valent pour les neuves", func(): _c_build(h))
	h.test("slot_view : forme inchangée, visée dite pour chaque compétence neuve ; slot_state : toujours la même forme", func(): _c_vues(h))
	h.test("déterminisme : même graine, mêmes entrées → même partie, avec les neuf compétences neuves", func(): _c_determinisme(h))
	h.test("références : le catalogue joue chaque compétence neuve, et les versions par classe de Chaîne et Bombe", func(): _c_references(h))

static func _c_build(h) -> void:
	# « dégâts des compétences » : les compétences à recharge, pas celles à charges.
	for id in ["faille", "hachette", "sceau", "riposte", "trait"]:
		var s := _def(id)
		var g := _jeu(h, id)
		_talisman(g, "skillDamageMult", 0.5)
		var e := _cible(g, 80.0, 0.0)
		var evs := _lancer(h, g, s.castTime + 0.5)
		h.egal(_coups(evs, e, "skill")[0], _sur(g, s.damage * 1.5), "%s : +50 %% de dégâts des compétences" % id)
	var garde := _jeu(h, "garde")
	_talisman(garde, "skillDamageMult", 0.5)
	var eg := _cible(garde, 60.0, 0.0)
	h.egal(_coups(_lancer(h, garde), eg, "gadget"), [_sur(garde, _def("garde").damage)], "garde (à charges) : pas concernée")
	# Recharge des compétences (Rancœur) : posée au lancer.
	for id in ["faille", "hachette", "sceau", "riposte", "trait", "proie"]:
		var g := _jeu(h, id)
		_benir(g, "rancoeur")
		h.ok(g.player.stats.skillCooldownMult < 1.0, "cas choisi")
		h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
		h.proche(g.player.slots[0].cd, _def(id).cooldown * g.player.stats.skillCooldownMult, 1e-9, "%s : recharge réduite par Rancœur" % id)
	# Charges en plus, charge rendue par un élite tué.
	for id in ["sillage", "garde", "leurre"]:
		var g := _jeu(h, id)
		_talisman(g, "gadgetChargesBonus", 1.0)
		h.egal(D6Loadout.max_charges(g, 0), _def(id).chargesPerSection + 1.0, "%s : une charge de plus au maximum" % id)
		_lancer(h, g)
		var restant: float = g.player.slots[0].charges
		D6Loadout.grant_gadget_charges(g, null)
		h.egal(g.player.slots[0].charges, restant + _def(id).chargeOnEliteKill, "%s : charge rendue (élite tué)" % id)
	# Proc « de compétence » (Charme fatal : rend vulnérable) sur un coup de la Faille.
	var g2 := _jeu(h, "faille")
	_benir(g2, "charme")
	var e2 := _cible(g2, 100.0, 0.0)
	_lancer(h, g2, _def("faille").castTime + 0.1)
	h.ok(e2.vuln > 0.0 and e2.vulnMult > 0.0, "Charme fatal : la Faille rend vulnérable")

static func _c_vues(h) -> void:
	var visee := {"sceau": true, "riposte": true, "sillage": false, "faille": true, "hachette": true, "garde": false, "proie": true, "trait": true, "leurre": true}
	for class_id in NEUVES:
		var g := _bac(h, class_id, NEUVES[class_id])
		for i in 3:
			var id: String = NEUVES[class_id][i]
			var vue: Dictionary = D6Loadout.slot_view(g, i)
			h.egal(vue.keys(), VUE, "%s : slot_view garde sa forme" % id)
			h.egal([vue.id, vue.name, vue.icon, vue.aimed], [id, _def(id).name, _def(id).icon, visee[id]], "%s : nom, pictogramme, visée" % id)
			h.egal(vue.kind, "gadget" if Arbre.table_of(_base(), id) == "gadgets" else "skill")
			h.egal(D6Loadout.slot_state(g, i), {"charging": false, "chargeFrac": 0.0, "active": false, "activeFrac": 0.0}, "%s : slot_state au repos" % id)
	var vide := _bac(h, "revenant", ["lance", null, null])
	h.egal(D6Loadout.slot_state(vide, 1).keys(), ["charging", "chargeFrac", "active", "activeFrac"], "emplacement vide : même forme")
	h.egal(D6Loadout.slot_state(vide, 0).active, false, "compétence d'avant : rien")

## Empreinte large : l'empreinte d'état, plus ce que les compétences neuves ajoutent.
static func _empreinte(g: Dictionary) -> Array:
	var p: Dictionary = g.player
	var store: Dictionary = D6KitCommon.kit_store(g)
	return [
		D6Game.state_hash(g), p.hp, p.slots.map(func(st): return [st.cd, st.charges]),
		g.allies.map(func(a): return [a.id, a.kind, a.x, a.y, a.hp, a.life]),
		store.shots.map(func(s): return [s.kind, s.x, s.y]), store.zones.map(func(z): return [z.kind, z.x, z.y, z.t]),
		g.enemies.map(func(e): return [e.id, e.get("stigmate") != null, e.get("proie") != null, e.vuln, e.stun]),
		p.get("parry") != null, p.get("guard") != null, p.get("sillage") != null, g.telemetry.skillCasts, g.telemetry.gadgetUses,
	]

static func _jouer(h, class_id: String, graine: float) -> Dictionary:
	var g: Dictionary = h.partie({"seed": graine, "startFloor": 6.0, "meta": _meta(class_id, NEUVES[class_id]), "godMode": true})
	var r: Dictionary = D6Rng.create_rng(77)
	for i in 900:
		var input: Dictionary = D6Game.empty_input()
		var a: float = D6Rng.rand(r) * TAU
		input.moveX = D6Trig.cos(a)
		input.moveY = D6Trig.sin(a)
		input.attack = D6Rng.rand(r) < 0.5
		input.attackPressed = D6Rng.rand(r) < 0.1
		input.dashPressed = D6Rng.rand(r) < 0.03
		for k in ["skill1", "skill2", "skill3"]:
			input[k + "Pressed"] = D6Rng.rand(r) < 0.06
			input[k + "AimX"] = D6Rng.rand(r) * 2.0 - 1.0
			input[k + "AimY"] = D6Rng.rand(r) * 2.0 - 1.0
		D6Game.step_game(g, input)
		g.events.clear()
		if g.mode == "choice":
			D6Game.apply_command(g, {"type": "choose", "index": 0})
	return g

static func _c_determinisme(h) -> void:
	for class_id in NEUVES:
		var a := _jouer(h, class_id, 4242.0)
		var b := _jouer(h, class_id, 4242.0)
		h.egal(_empreinte(a), _empreinte(b), "%s : deux parties identiques" % class_id)
		h.ok(a.telemetry.skillCasts >= 4.0 and a.telemetry.gadgetUses >= 1.0, "%s : les compétences neuves ont vraiment été jouées (%s lancers, %s charges)" % [class_id, str(a.telemetry.skillCasts), str(a.telemetry.gadgetUses)])
		h.different(_empreinte(a), _empreinte(_jouer(h, class_id, 4243.0)), "%s : une autre graine donne une autre partie" % class_id)

static func _c_references(h) -> void:
	var jouees := {}
	var choisies := {}
	for spec in Catalogue.all():
		if not String(spec.name).begins_with("competences_"):
			continue
		for id in spec.slots:
			jouees[id] = true
		for id in spec.get("tree", {}).get("choices", {}):
			choisies["%s/%s/%s" % [spec.kit[0], id, spec.tree.choices[id]]] = true
		for id in spec.slots:
			h.ok((_base().classes[spec.kit[0]].skills + _base().classes[spec.kit[0]].gadgets).has(id), "%s : %s est une compétence de %s" % [spec.name, id, spec.kit[0]])
	for class_id in NEUVES:
		for id in NEUVES[class_id]:
			h.ok(jouees.has(id), "une partie competences_* joue %s" % id)
	for cle in ["revenant/chaine/croc", "revenant/bombe/poix", "bourreau/chaine/rafle", "bourreau/bombe/baril"]:
		h.ok(choisies.has(cle), "une partie competences_* joue %s" % cle)
	for spec in Catalogue.all():
		var tree = spec.get("tree")
		if tree == null:
			continue
		for id in tree.get("choices", {}):
			var n = Arbre.node(_base(), spec.kit[0], id)
			h.ok(n != null and n.choices.map(func(ch): return ch.id).has(tree.choices[id]), "%s : l'amélioration %s/%s existe" % [spec.name, id, tree.choices[id]])
