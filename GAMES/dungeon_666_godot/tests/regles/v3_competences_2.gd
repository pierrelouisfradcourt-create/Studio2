extends RefCounted
## COMBAT V3, étape 5 — la QUATRIÈME compétence neuve de chaque classe (design/COMBAT_V3.md,
## « Étape 5 » ; sim/kit_neuves.gd et ses trois familles ; data/classes.json, data/arbres.json) :
##   ombre — Ombre jumelle (Revenant) : alliée intangible qui répète ses coups d'arme ;
##   grace — Décollation (Bourreau) : le coup qui tue se relance ;
##   grele — Grêle des Limbes (Chasseresse) : frappe de zone à retardement.
## Pour chacune : l'effet de base, les rangs, les deux améliorations et leur exclusion, les cas
## limites (salle vide, Gardien, terrain bas, mort pendant, changement de salle), une bénédiction de
## compétence, le déterminisme ; l'ombre : jamais dans l'eau sur 300 graines.
## Les nombres attendus sont LUS dans les données (jamais recopiés). L'outillage commun est celui de
## tests/regles/v3_competences.gd (étape 4), appelé tel quel.

const Arbre = preload("res://sim/tree.gd")
const Meute = preload("res://sim/ult_meute.gd")
const Catalogue = preload("res://references/catalogue.gd")
const Neuves = preload("res://sim/kit_neuves.gd")
const V3 = preload("res://tests/regles/v3_competences.gd")
const Partie = preload("res://references/partie.gd")
const Bots = preload("res://outils/bots/bots.gd")

const QUATRIEMES := {"revenant": "ombre", "bourreau": "grace", "chasseresse": "grele"}
const ETAGE := 2.0 # maîtrise
const GRAINES_EAU := 300
const PAS_EAU := 90 # pas joués par graine, l'ombre debout
const ELAN := 8.0 # u : ce que le héros parcourt encore le pas où il cesse de marcher
const GESTE := 0.3 # s laissées après le geste de la Décollation : le gel d'impact du coup retient le temps

static func tests(h) -> void:
	_tests_arbre(h)
	_tests_ombre(h)
	_tests_grace(h)
	_tests_grele(h)
	_tests_communs(h)

# ---------------------------------------------------------------- outillage

static func _classe(id: String) -> String:
	for class_id in QUATRIEMES:
		if QUATRIEMES[class_id] == id:
			return class_id
	return ""

## La compétence `id` seule, au rang 1 ("" : aucune amélioration, sinon au rang du choix avec elle).
static func _jeu(h, id: String, choix: String = "", opts: Dictionary = {}) -> Dictionary:
	var rangs := {id: V3._cfg().choiceRank} if choix != "" else {}
	return V3._bac(h, _classe(id), [id, null, null], rangs, {id: choix} if choix != "" else {}, opts)

static func _pose(id: String, choix: String) -> Dictionary:
	return V3._pose(_classe(id), id, choix)

static func _appui(h, g: Dictionary, secondes: float = 0.0, ax: float = 0.0, ay: float = 0.0) -> Array:
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": ax, "skill1AimY": ay})
	if secondes > 0.0:
		evs.append_array(h.avancer(g, h.ticks(secondes)))
	return evs

static func _ombres(g: Dictionary) -> Array:
	return g.allies.filter(func(a): return a.kind == "ombre" and not a.dead)

static func _gardien(g: Dictionary, dx: float, dy: float) -> Dictionary:
	var boss: Dictionary = D6Enemies.create_enemy(g, "gardien", g.player.x + dx, g.player.y + dy, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0
	return boss

## Un allié est-il là où rien ne marche ? Son corps chevauche un terrain bas, ou son centre est dans
## un mur ou un pilier (la même lecture que pour les limiers : tests/regles/v3_ultimes.gd).
static func _dans_le_dur(room: Dictionary, a: Dictionary) -> bool:
	return D6Physics.low_at(room, a.x, a.y, a.r) or D6Physics.point_blocked(room, a.x, a.y, 0.0)

static func _entre(a: Dictionary, b: Dictionary) -> float:
	return sqrt(D6Geo.dist2(a.x, a.y, b.x, b.y))

# ---------------------------------------------------------------- arbre : nœuds, rangs, exclusion

static func _tests_arbre(h) -> void:
	h.test("arbre : la quatrième compétence neuve de chaque classe — son nœud à l'étage de maîtrise, deux améliorations ; seuils et points inchangés", func(): _a_noeuds(h))
	for class_id in QUATRIEMES:
		var id: String = QUATRIEMES[class_id]
		h.test("rangs : %s — chaque rang écrit ses nombres dans la partie, et le texte de l'arbre les cite" % id, func(): _a_rangs(h, class_id, id))
		h.test("améliorations : %s — l'une OU l'autre ; celle qui est prise est la seule appliquée en partie" % id, func(): _a_exclusion(h, class_id, id))

static func _a_noeuds(h) -> void:
	var t := V3._base()
	var sortes: Array = []
	for class_id in QUATRIEMES:
		var id: String = QUATRIEMES[class_id]
		var c: Dictionary = t.classes[class_id]
		var n = Arbre.skill_node(t, class_id, id)
		h.ok(n != null and c.skills.has(id), "%s / %s : dans la liste de la classe, avec son nœud" % [class_id, id])
		h.egal([n.tier, n.choices.size(), Arbre.table_of(t, id)], [ETAGE, 2, "skills"], "%s : étage de maîtrise, deux améliorations, à recharge" % id)
		h.ok(t.skills[id].get("icon") is String and t.skills[id].text != "" and t.skills[id].name != "", "%s : nom, pictogramme, texte" % id)
		h.egal((c.skills + c.gadgets).size(), 9, "%s : neuf compétences" % class_id)
		h.egal(t.tree.classes[class_id].fullyBuyable, false, "%s : l'arbre ne se remplit pas en entier" % class_id)
		sortes.append(t.skills[id].kind)
	h.egal(sortes, Neuves.SKILLS_2, "une sorte (kind) par compétence, celles que jouent les règles")
	h.egal(t.tree.tiers.map(func(x): return x.need), [0.0, 5.0, 12.0, 20.0], "seuils des étages inchangés")
	h.egal([t.tree.maxLevel, t.tree.pointsPerLevel, t.tree.pointsPerGuardian], [30.0, 1.0, 1.0], "points inchangés (33 au plus)")
	# Verrouillée tant que l'étage est fermé ; au rang 1 elle se place et se joue.
	var tt := V3._t()
	for class_id in QUATRIEMES:
		var id: String = QUATRIEMES[class_id]
		var p: Dictionary = D6Profile.new_profile(tt)
		p.souls = 1e6
		D6Profile.unlock(p, tt, "classes", class_id)
		D6Profile.select_class(p, tt, class_id)
		Arbre.state(p, class_id).level = V3._cfg().maxLevel
		h.egal(D6Profile.tree_buy(p, tt, class_id, id).ok, false, "%s : étage de maîtrise fermé au départ" % id)
		h.egal(D6Profile.select_slot(p, tt, 2, id).ok, false, "%s : verrouillée, elle ne se place pas" % id)

static func _a_rangs(h, class_id: String, id: String) -> void:
	var t := V3._t()
	var n: Dictionary = Arbre.node(t, class_id, id)
	for rang in range(1, int(V3._cfg().skillRanks) + 1):
		var g := V3._bac(h, class_id, [id, null, null], {id: float(rang)})
		var def: Dictionary = D6Loadout.slot_def(g, 0)
		var texte: String = Arbre.rank_text(t, class_id, n, float(rang))
		for field in n.ranks:
			var v = Arbre.rank_value(n, field, float(rang))
			if v == null:
				v = V3._def(id)[field]
			h.egal(def[field], v, "%s rang %d : %s en partie" % [id, rang, field])
			h.ok(Arbre.fr(v) in texte, "%s rang %d : « %s » cite %s" % [id, rang, texte, field])
	for field in n.ranks:
		var dernier: float = n.ranks[field][n.ranks[field].size() - 1]
		h.ok(dernier < V3._def(id)[field] if field == "cooldown" else dernier > V3._def(id)[field], "%s : %s s'améliore du rang 1 au rang 5" % [id, field])

static func _a_exclusion(h, class_id: String, id: String) -> void:
	var t := V3._t()
	var n: Dictionary = Arbre.node(t, class_id, id)
	var a: Dictionary = n.choices[0]
	var b: Dictionary = n.choices[1]
	var m := V3._meta(class_id, [id, null, null], {id: V3._cfg().choiceRank})
	h.egal(D6Profile.tree_choose(m, t, class_id, id, a.id).ok, true, "%s : la première se prend au rang du choix" % id)
	h.egal(D6Profile.tree_choose(m, t, class_id, id, b.id), {"ok": false, "reason": "l'autre amélioration est prise"}, "%s : pas la seconde" % id)
	var sous := V3._meta(class_id, [id, null, null], {id: V3._cfg().choiceRank - 1.0})
	h.egal(D6Profile.tree_choose(sous, t, class_id, id, a.id).ok, false, "%s : pas avant le rang du choix" % id)
	for paire in [[a, b], [b, a]]:
		var g := V3._bac(h, class_id, [id, null, null], {id: V3._cfg().choiceRank}, {id: paire[0].id})
		var def: Dictionary = D6Loadout.slot_def(g, 0)
		for field in paire[0].set:
			h.egal(def.get(field), paire[0].set[field], "%s / %s : %s posé en partie" % [id, paire[0].id, field])
			h.ok(V3._def(id).has(field) or Arbre.EXTRA_FIELDS.has(field), "%s / %s : %s est lu par une règle" % [id, paire[0].id, field])
		for field in paire[1].set:
			if not paire[0].set.has(field):
				h.egal(def.get(field), V3._rang3(n, id, field), "%s / %s : %s de l'autre amélioration n'est pas appliqué" % [id, paire[0].id, field])
		h.ok(Arbre.choice_text(t, paire[0]) != Arbre.choice_text(t, paire[1]), "%s : deux textes différents" % id)

# ---------------------------------------------------------------- Revenant : Ombre jumelle

static func _tests_ombre(h) -> void:
	h.test("ombre : elle surgit où il se tient (dégâts autour), alliée de game.allies, jamais un ennemi ; elle répète son coup d'arme de sa place", func(): _o_base(h))
	h.test("ombre : intangible — aucun ennemi ne se tourne vers elle, un tir la traverse, rien ne la blesse ; elle n'est pas un ultime", func(): _o_intangible(h))
	h.test("ombre : elle dure `life` s, se dissipe s'il s'éloigne de plus de `range` u ; une seule à la fois ; rang 5", func(): _o_duree(h))
	h.test("ombre / Ombre liée : elle le suit à pied et se rattache à lui ; sans elle, elle reste où il l'a laissée", func(): _o_liee(h))
	h.test("ombre / Transposition : un second appui échange leurs places, invulnérable, une fois par ombre ; sans elle, rien", func(): _o_echange(h))
	h.test("ombre : salle vide, Gardien, mort pendant, changement de salle", func(): _o_limites(h))
	h.test("ombre : terrain bas — l'ombre liée attend sur la rive puis se rattache ; l'échange ne pose personne dans l'eau", func(): _o_terrain(h))
	h.test("ombre : jamais dans l'eau, un mur ni un obstacle, sur %d graines (liée et transposée)" % GRAINES_EAU, func(): _o_eau(h))

static func _o_base(h) -> void:
	var s := V3._def("ombre")
	var g := _jeu(h, "ombre")
	var p: Dictionary = g.player
	var x0: float = p.x
	var a := V3._cible(g, 60.0, 0.0)
	var loin := V3._cible(g, s.radius + 80.0, 0.0)
	var evs := _appui(h, g, s.castTime + 0.05)
	var ombres := _ombres(g)
	h.egal(ombres.size(), 1, "une ombre dans game.allies")
	var o: Dictionary = ombres[0]
	h.egal([o.x, o.y, o.ghost, o.lifeMax], [x0, p.y, true, s.life], "là où il se tient, intangible, pour `life` s")
	h.egal(g.enemies.filter(func(e): return e.kind == "ombre").size(), 0, "jamais dans game.enemies")
	h.egal(V3._coups(evs, a, "skill"), [V3._sur(g, s.damage)], "elle blesse en surgissant, à `radius` u")
	h.egal(V3._coups(evs, loin).size(), 0, "… pas plus loin")
	h.egal(V3._de(evs, "allySpawn").map(func(ev): return ev.get("kind")), ["ombre"])
	h.egal(V3._de(evs, "explode", "ombre").map(func(ev): return ev.r), [s.radius])
	h.proche(p.slots[0].cd, s.cooldown - s.castTime - 0.05, 0.05, "la recharge est partie")
	# Il s'éloigne et frappe un autre ennemi : l'ombre porte le même coup, de sa place, sur le sien.
	loin.dead = true
	p.x = x0 + 300.0
	var b := V3._cible(g, 60.0, 0.0)
	evs = h.avancer(g, 1, {"attackPressed": true})
	evs.append_array(h.avancer(g, h.ticks(0.4)))
	var coup: Dictionary = g.tuning.combo[0]
	h.egal(V3._de(evs, "echo").map(func(ev): return [ev.id, ev.range]), [[o.id, coup.range]], "un coup du héros, un écho de l'ombre")
	h.egal(V3._coups(evs, a, "skill"), [V3._sur(g, coup.damage * s.echoMult)], "l'ombre porte le coup à `echoMult` des dégâts, sur l'ennemi près d'elle")
	h.egal(V3._coups(evs, b, "melee").size(), 1, "le héros a porté le sien")
	h.egal(V3._coups(evs, b, "skill").size(), 0, "l'ombre ne frappe pas ce qui est hors de sa portée")

static func _o_intangible(h) -> void:
	var s := V3._def("ombre")
	var g := _jeu(h, "ombre")
	var p: Dictionary = g.player
	_appui(h, g, s.castTime + 0.05)
	var o: Dictionary = _ombres(g)[0]
	p.x += 320.0
	var imp := V3._vif(g, -320.0 + 90.0, 0.0, "imp", true) # tout près de l'ombre, loin de lui
	h.avancer(g, h.ticks(0.6))
	h.egal(D6Js.nz(imp.get("allyId"), 0.0), 0.0, "l'ennemi de mêlée ne se tourne pas vers elle")
	imp.dead = true
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": o.x + 120.0, "y": o.y, "vx": -900.0, "vy": 0.0, "r": 6.0, "damage": 5.0, "range": 900.0})
	h.avancer(g, h.ticks(0.2))
	h.ok(g.projectiles.size() == 1 and g.projectiles[0].x < o.x, "un tir la traverse sans s'arrêter")
	h.egal([Meute.hurt(g, o, 50.0, "imp"), o.dead, o.hp], [false, false, o.maxHp], "rien ne la blesse")
	h.egal([D6KitSupers.acting(g), D6Player.ultimate_view(g).allies, Meute.hounds(g)], [false, 0.0, 0.0], "l'ombre debout : aucun ultime n'agit")
	p.superCharge = 0.2
	var e := V3._cible(g, 60.0, 0.0)
	D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 30.0, "canCrit": false})
	h.ok(p.superCharge > 0.2, "la jauge d'ultime se remplit, ombre debout")
	var etat: Dictionary = D6Loadout.slot_state(g, 0)
	h.ok(etat.active and etat.activeFrac > 0.5 and etat.activeFrac < 1.0, "slot_state : l'effet dure, sa part qui reste (%s)" % str(etat.activeFrac))

static func _o_duree(h) -> void:
	var s := V3._def("ombre")
	var g := _jeu(h, "ombre")
	_appui(h, g, s.castTime + 0.05)
	h.avancer(g, h.ticks(s.life - 0.5))
	h.egal(_ombres(g).size(), 1, "encore là avant la fin")
	var evs: Array = h.avancer(g, h.ticks(0.6))
	h.egal([_ombres(g).size(), g.allies.size()], [0, 0], "partie après `life` s")
	h.egal(V3._de(evs, "allyGone").map(func(ev): return ev.reason), ["temps"])
	h.egal(D6Loadout.slot_state(g, 0).active, false)
	# Trop loin : elle se dissipe.
	var g2 := _jeu(h, "ombre")
	var p2: Dictionary = g2.player
	p2.x = g2.room.pad + 40.0
	_appui(h, g2, s.castTime + 0.05)
	h.ok(g2.room.w - g2.room.pad > p2.x + s.range + 40.0, "cas choisi : la salle est assez large")
	p2.x += s.range - 20.0
	h.avancer(g2, 3)
	h.egal(_ombres(g2).size(), 1, "à moins de `range` u : elle reste")
	p2.x += 40.0
	h.egal(V3._de(h.avancer(g2, 3), "allyGone").map(func(ev): return ev.reason), ["loin"], "au-delà de `range` u : elle se dissipe")
	# Une seule à la fois : relancée (recharge remise à zéro pour l'essai), l'ancienne disparaît.
	var g3 := _jeu(h, "ombre")
	_appui(h, g3, s.castTime + 0.05)
	var premiere: float = _ombres(g3)[0].id
	g3.player.slots[0].cd = 0.0
	g3.player.x += 100.0
	_appui(h, g3, s.castTime + 0.05)
	h.egal(_ombres(g3).size(), 1, "une seule ombre")
	h.ok(_ombres(g3)[0].id != premiere and _ombres(g3)[0].x == g3.player.x, "… la nouvelle, là où il se tient")
	var n: Dictionary = Arbre.node(V3._base(), "revenant", "ombre")
	var g5 := V3._bac(h, "revenant", ["ombre", null, null], {"ombre": V3._cfg().skillRanks})
	var e5 := V3._cible(g5, 50.0, 0.0)
	h.egal(V3._coups(_appui(h, g5, s.castTime + 0.05), e5, "skill"), [V3._sur(g5, Arbre.rank_value(n, "damage", V3._cfg().skillRanks))], "rang 5 : dégâts en surgissant")

static func _o_liee(h) -> void:
	var s := V3._def("ombre")
	var liee := _pose("ombre", "liee")
	var g := _jeu(h, "ombre", "liee")
	var p: Dictionary = g.player
	var x0: float = p.x
	_appui(h, g, s.castTime + 0.05)
	var o: Dictionary = _ombres(g)[0]
	h.avancer(g, h.ticks(1.5), {"moveX": 1.0})
	h.ok(p.x > x0 + 300.0, "cas choisi : il a marché")
	h.proche(_entre(o, p), liee.follow, 6.0, "elle le suit à `follow` u")
	h.avancer(g, h.ticks(1.0))
	h.proche(_entre(o, p), liee.follow, 1.5, "… et s'arrête à sa place quand il s'arrête")
	# Trop loin d'un coup (au-delà de `range` aussi) : elle ne se dissipe pas, elle se rattache.
	p.x = g.room.pad + 40.0
	h.ok(_entre(o, p) > liee.follow * 4.0, "cas choisi : il est loin")
	h.avancer(g, 2)
	h.egal(_ombres(g).size(), 1, "liée : elle ne se dissipe pas")
	h.ok(_entre(o, p) <= liee.follow + 1.0, "… elle s'est rattachée à lui (%s u)" % str(_entre(o, p)))
	# Sans l'amélioration : elle reste où il l'a laissée.
	var g0 := _jeu(h, "ombre")
	var y0: float = g0.player.y
	_appui(h, g0, s.castTime + 0.05)
	var o0: Dictionary = _ombres(g0)[0]
	var ox: float = o0.x
	h.avancer(g0, h.ticks(1.0), {"moveX": 1.0})
	h.egal([o0.x, o0.y], [ox, y0], "sans « Ombre liée » : elle ne bouge pas")

static func _o_echange(h) -> void:
	var s := V3._def("ombre")
	var tr := _pose("ombre", "transposition")
	var g := _jeu(h, "ombre", "transposition")
	var p: Dictionary = g.player
	var x0: float = p.x
	_appui(h, g, s.castTime + 0.05)
	var o: Dictionary = _ombres(g)[0]
	h.avancer(g, h.ticks(0.8), {"moveX": 1.0})
	var x1: float = p.x
	h.ok(x1 > x0 + 150.0, "cas choisi : il s'est éloigné de son ombre")
	p.iframes = 0.0
	var evs := _appui(h, g)
	h.proche(p.x, x0, ELAN, "second appui : il est à la place de l'ombre (à un reste d'élan près)")
	h.proche(o.x, x1, ELAN, "… et elle à la sienne")
	h.ok(p.iframes >= tr.swap - D6Data.DT * 2.0, "invulnérable `swap` s")
	h.egal(V3._de(evs, "shadeSwap").size(), 1)
	h.egal(V3._de(evs, "castStart").size(), 0, "ce n'est pas un nouveau lancer")
	evs = _appui(h, g, 0.1)
	h.egal(V3._de(evs, "shadeSwap").size(), 0, "une fois par ombre")
	h.proche(p.x, x0, ELAN)
	# Sans l'amélioration : le second appui ne fait rien (la compétence recharge).
	var g0 := _jeu(h, "ombre")
	_appui(h, g0, s.castTime + 0.05)
	h.avancer(g0, h.ticks(0.5), {"moveX": 1.0})
	var avant: float = g0.player.x
	h.egal(V3._de(_appui(h, g0), "shadeSwap").size(), 0, "sans « Transposition » : aucun échange")
	h.proche(g0.player.x, avant, ELAN)

static func _o_limites(h) -> void:
	var s := V3._def("ombre")
	var g := _jeu(h, "ombre")
	var evs := _appui(h, g, s.castTime + 0.05)
	h.egal([_ombres(g).size(), V3._de(evs, "hit").size()], [1, 0], "salle vide : elle surgit, rien n'est touché")
	evs = h.avancer(g, 1, {"attackPressed": true})
	evs.append_array(h.avancer(g, h.ticks(0.4)))
	h.egal([V3._de(evs, "echo").size(), V3._de(evs, "hit").size()], [1, 0], "… et son coup répété fend l'air")
	var g2 := _jeu(h, "ombre")
	var boss := _gardien(g2, 70.0, 0.0)
	var hp0: float = boss.hp
	_appui(h, g2, s.castTime + 0.05)
	h.ok(boss.hp < hp0, "Gardien : blessé quand elle surgit")
	var hp1: float = boss.hp
	h.avancer(g2, 1, {"attackPressed": true})
	evs = h.avancer(g2, h.ticks(0.4))
	h.ok(V3._coups(evs, boss, "skill").size() == 1 and boss.hp < hp1, "… et par le coup répété")
	D6Run.enter_floor(g2, g2.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(g2.allies.size(), 0, "changement de salle : l'ombre ne suit pas")
	h.egal(D6Loadout.slot_state(g2, 0).active, false)
	var g3 := _jeu(h, "ombre")
	_appui(h, g3, s.castTime + 0.05)
	g3.player.superCharge = 0.7
	D6Combat.damage_player(g3, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	h.avancer(g3, h.ticks(0.5))
	h.egal([g3.player.state, g3.allies.size()], ["dead", 0], "mort : l'ombre disparaît")
	h.egal(g3.player.superCharge, 0.7, "… sans toucher à la jauge d'ultime")
	# Mort PENDANT le lancer : rien ne surgit.
	var g4 := _jeu(h, "ombre")
	h.avancer(g4, 1, {"skill1Pressed": true})
	D6Combat.damage_player(g4, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	h.avancer(g4, h.ticks(0.5))
	h.egal([g4.player.state, g4.allies.size()], ["dead", 0], "mort pendant le lancer : aucune ombre")

static func _o_terrain(h) -> void:
	var s := V3._def("ombre")
	var liee := _pose("ombre", "liee")
	var g := _jeu(h, "ombre", "liee")
	var p: Dictionary = g.player
	_appui(h, g, s.castTime + 0.05)
	var o: Dictionary = _ombres(g)[0]
	var bord: float = p.x + 40.0
	V3._riviere(g, bord)
	var fautes := 0
	for i in h.ticks(1.2):
		D6Game.step_game(g, h.entree({"moveX": 1.0, "dashPressed": i == 0}))
		g.events.clear()
		if _dans_le_dur(g.room, o):
			fautes += 1
	h.ok(p.x > bord + 64.0, "cas choisi : il a franchi la rivière")
	h.egal(fautes, 0, "l'ombre liée n'est jamais dans l'eau")
	h.ok(o.x > bord + 64.0 and _entre(o, p) <= liee.follow * 4.0, "… elle s'est rattachée à lui, sur l'autre rive")
	# Transposition par-dessus la rivière : chacun sur la terre ferme.
	var g2 := _jeu(h, "ombre", "transposition")
	var p2: Dictionary = g2.player
	var x0: float = p2.x
	_appui(h, g2, s.castTime + 0.05)
	var o2: Dictionary = _ombres(g2)[0]
	V3._riviere(g2, x0 + 40.0)
	h.avancer(g2, 1, {"moveX": 1.0, "dashPressed": true})
	h.egal(V3._de(_appui(h, g2), "shadeSwap").size(), 0, "en plein franchissement : pas d'échange")
	h.avancer(g2, h.ticks(0.6), {"moveX": 1.0})
	h.egal(V3._de(_appui(h, g2), "shadeSwap").size(), 1, "sur la terre ferme : l'échange part")
	h.proche(p2.x, x0, ELAN, "il est revenu de l'autre côté de l'eau")
	h.egal([_dans_le_dur(g2.room, p2), _dans_le_dur(g2.room, o2)], [false, false], "ni lui ni l'ombre dans l'eau")

static func _o_eau(h) -> void:
	var metas := [
		V3._meta("revenant", ["ombre", null, null], {"ombre": V3._cfg().choiceRank}, {"ombre": "liee"}),
		V3._meta("revenant", ["ombre", null, null], {"ombre": V3._cfg().choiceRank}, {"ombre": "transposition"}),
	]
	var avec_terrain := 0
	var vues := 0
	var echanges := 0
	var fautes := 0
	for graine in GRAINES_EAU:
		var g: Dictionary = h.partie({"seed": 9000.0 + graine, "startFloor": 5.0 + float(graine % 60) * 7.0, "meta": metas[graine % 2], "godMode": true})
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
		var ang: float = D6Rng.rand(r) * TAU
		for i in PAS_EAU:
			if i % 20 == 19:
				ang = D6Rng.rand(r) * TAU
			var entree := {"moveX": D6Trig.cos(ang), "moveY": D6Trig.sin(ang), "skill1Pressed": i == 0 or D6Rng.rand(r) < 0.05, "dashPressed": D6Rng.rand(r) < 0.08}
			D6Game.step_game(g, h.entree(entree))
			for ev in g.events:
				if ev.type == "shadeSwap":
					echanges += 1
			g.events.clear()
			for a in _ombres(g):
				vues += 1
				if _dans_le_dur(g.room, a):
					if fautes == 0:
						h.ok(false, "graine %d, pas %d : ombre où rien ne se pose (%s, %s)" % [graine, i, str(a.x), str(a.y)])
					fautes += 1
			if _dans_le_dur(g.room, p) and not D6Player.crossing(g) and fautes == 0:
				fautes += 1
				h.ok(false, "graine %d, pas %d : le héros à l'arrêt dans l'eau après un échange" % [graine, i])
	h.ok(avec_terrain >= 30, "assez de salles à terrain bas dans l'échantillon (%d)" % avec_terrain)
	h.ok(vues > avec_terrain * 40, "l'ombre a bien été jouée (%d pas avec une ombre debout)" % vues)
	h.ok(echanges >= 10, "des échanges ont eu lieu (%d)" % echanges)
	h.egal(fautes, 0, "aucune ombre dans l'eau, un mur ou un obstacle")

# ---------------------------------------------------------------- Bourreau : Décollation

static func _tests_grace(h) -> void:
	h.test("grace : la hache s'abat à `range` u devant lui, sur ce qui est à `radius` u du point d'impact ; un ennemi affaibli prend `executeMult` fois plus", func(): _d_base(h))
	h.test("grace : le coup qui TUE fait tomber la recharge à `resetCd` — il enchaîne ; sans tuer, la recharge reste ; rang 5", func(): _d_tue(h))
	h.test("grace / Ivresse du billot : un coup qui tue donne un élan de dégâts ; / Effroi : il étourdit autour de la victime, sans blesser", func(): _d_choix(h))
	h.test("grace : salle vide, Gardien (jamais tué d'office, jamais étourdi), par-dessus un terrain bas, mort pendant, changement de salle", func(): _d_limites(h))

static func _d_base(h) -> void:
	var s := V3._def("grace")
	var g := _jeu(h, "grace")
	var p: Dictionary = g.player
	var devant := V3._cible(g, s.range, 0.0)
	var loin := V3._cible(g, s.range + s.radius + 60.0, 0.0)
	var dos := V3._cible(g, -60.0, 0.0)
	var evs := _appui(h, g, s.castTime + 0.1, 1.0, 0.0)
	h.egal(V3._coups(evs, devant, "skill"), [V3._sur(g, s.damage)], "devant lui : `damage`")
	h.egal([V3._coups(evs, loin).size(), V3._coups(evs, dos).size()], [0, 0], "ni plus loin, ni dans son dos")
	h.egal(V3._de(evs, "grace").map(func(ev): return [ev.x - p.x > s.range - 30.0, ev.r]), [[true, s.radius]], "l'impact est dit, à `range` u devant")
	h.ok(p.slots[0].cd > s.cooldown - 1.0, "personne n'est mort : la recharge entière (%s)" % str(p.slots[0].cd))
	h.egal(V3._de(evs, "graceKill").size(), 0)
	# Affaibli : au seuil ou dessous, `executeMult` fois les dégâts ; juste au-dessus, non.
	for cas in [[s.executeBelow, s.executeMult], [s.executeBelow - 0.1, s.executeMult], [s.executeBelow + 0.02, 1.0]]:
		var g2 := _jeu(h, "grace")
		var e := V3._cible(g2, s.range, 0.0)
		e.hp = e.maxHp * cas[0]
		h.egal(V3._coups(_appui(h, g2, s.castTime + 0.1, 1.0, 0.0), e, "skill"), [V3._sur(g2, s.damage * cas[1])], "à %s de sa vie : × %s" % [str(cas[0]), str(cas[1])])

static func _d_tue(h) -> void:
	var s := V3._def("grace")
	var g := _jeu(h, "grace")
	var p: Dictionary = g.player
	var a := V3._cible(g, s.range, 0.0)
	var b := V3._cible(g, s.range, 30.0)
	a.hp = 3.0
	b.hp = 3.0
	var evs := _appui(h, g, s.castTime + GESTE, 1.0, 0.0)
	h.egal([a.dead, b.dead], [true, true], "cas choisi : les deux meurent du coup")
	h.egal(V3._de(evs, "graceKill").map(func(ev): return ev.kills), [2.0], "le coup qui tue est dit, avec le nombre de victimes")
	h.ok(p.slots[0].cd <= s.resetCd and p.slots[0].cd > 0.0, "la recharge tombe à `resetCd` (%s)" % str(p.slots[0].cd))
	# Il enchaîne : une victime de plus, une relance de plus.
	h.avancer(g, h.ticks(s.resetCd + 0.3))
	var c := V3._cible(g, s.range, 0.0)
	c.hp = 3.0
	evs = _appui(h, g, s.castTime + GESTE, 1.0, 0.0)
	h.egal([c.dead, V3._de(evs, "graceKill").size(), p.slots[0].cd <= s.resetCd], [true, 1, true], "enchaîné")
	# Puis un coup qui ne tue pas : la recharge entière revient.
	h.avancer(g, h.ticks(s.resetCd + 0.3))
	V3._cible(g, s.range, 0.0)
	_appui(h, g, s.castTime + GESTE, 1.0, 0.0)
	h.ok(p.slots[0].cd > s.cooldown - 1.0, "sans tuer : recharge entière")
	var n: Dictionary = Arbre.node(V3._base(), "bourreau", "grace")
	var g5 := V3._bac(h, "bourreau", ["grace", null, null], {"grace": V3._cfg().skillRanks})
	var e5 := V3._cible(g5, s.range, 0.0)
	h.egal(V3._coups(_appui(h, g5, s.castTime + 0.1, 1.0, 0.0), e5, "skill"), [V3._sur(g5, Arbre.rank_value(n, "damage", V3._cfg().skillRanks))], "rang 5 : dégâts")
	h.proche(g5.player.slots[0].cd, Arbre.rank_value(n, "cooldown", V3._cfg().skillRanks) - s.castTime - 0.1, 0.15, "rang 5 : recharge")

static func _d_choix(h) -> void:
	var s := V3._def("grace")
	var ivre := _pose("grace", "ivresse")
	var g := _jeu(h, "grace", "ivresse")
	var e := V3._cible(g, s.range, 0.0)
	_appui(h, g, s.castTime + GESTE, 1.0, 0.0)
	h.egal([e.dead, g.player.surge], [false, 0.0], "ivresse : sans tuer, aucun élan")
	g.player.slots[0].cd = 0.0
	e.hp = 3.0
	_appui(h, g, s.castTime + GESTE, 1.0, 0.0)
	h.ok(e.dead and g.player.surge > ivre.surge - 0.5 and g.player.surge <= ivre.surge, "ivresse : le coup qui tue donne `surge` s d'élan (%s)" % str(g.player.surge))
	h.egal(g.player.surgeMult, ivre.surgeMult)
	var temoin := V3._cible(g, s.range, 0.0)
	var coup: float = D6Combat.damage_enemy(g, temoin, {"kind": "melee", "amount": 20.0, "canCrit": false})
	h.egal(coup, V3._sur(g, 20.0 * (1.0 + ivre.surgeMult)), "… +`surgeMult` de dégâts tant qu'il dure")
	# Effroi : étourdit autour de la VICTIME, sans dégât ; rien si personne ne meurt.
	var peur := _pose("grace", "effroi")
	var g2 := _jeu(h, "grace", "effroi")
	var v := V3._cible(g2, s.range, 0.0)
	var evs := _appui(h, g2, s.castTime + GESTE, 1.0, 0.0)
	h.egal([v.dead, V3._de(evs, "kitPulse", "grace").size()], [false, 0], "effroi : personne n'est mort, aucune onde")
	g2.player.slots[0].cd = 0.0
	v.hp = 3.0
	# Deux témoins ÉVEILLÉS (ils marchent vers lui pendant le geste) : l'un près de la victime, hors du coup ; l'autre loin.
	var pres := V3._vif(g2, s.range + 100.0, 100.0, "imp")
	var loin := V3._vif(g2, s.range, peur.blastRadius + 320.0, "imp")
	evs = _appui(h, g2, s.castTime + GESTE, 1.0, 0.0)
	h.ok(v.dead and pres.stun > 0.0 and pres.stun <= peur.blastStun, "effroi : le témoin proche est étourdi (%s s)" % str(pres.stun))
	h.egal([loin.stun, pres.hp, V3._de(evs, "kitPulse", "grace").map(func(ev): return ev.r)], [0.0, pres.maxHp, [peur.blastRadius]], "… pas au-delà de `blastRadius`, et sans blesser")
	var g0 := _jeu(h, "grace")
	var v0 := V3._cible(g0, s.range, 0.0)
	var p0 := V3._vif(g0, s.range + 100.0, 0.0, "imp")
	v0.hp = 3.0
	_appui(h, g0, s.castTime + GESTE, 1.0, 0.0)
	h.egal([v0.dead, p0.stun, g0.player.surge], [true, 0.0, 0.0], "sans amélioration : ni effroi ni élan")

static func _d_limites(h) -> void:
	var s := V3._def("grace")
	var g := _jeu(h, "grace")
	var evs := _appui(h, g, s.castTime + 0.1, 1.0, 0.0)
	h.egal([V3._de(evs, "grace").size(), V3._de(evs, "hit").size(), V3._de(evs, "graceKill").size()], [1, 0, 0], "salle vide : la hache fend l'air")
	h.proche(g.player.slots[0].cd, s.cooldown - s.castTime - 0.1, 0.05, "la recharge est dépensée (aucun coup, aucun gel)")
	# Gardien affaibli : il prend le coup multiplié, il n'est ni tué d'office ni étourdi par l'effroi.
	var g2 := _jeu(h, "grace", "effroi")
	var boss := _gardien(g2, s.range + 20.0, 0.0)
	boss.hp = boss.maxHp * (s.executeBelow - 0.05)
	var victime := V3._cible(g2, s.range, 40.0)
	victime.hp = 3.0
	evs = _appui(h, g2, s.castTime + GESTE, 1.0, 0.0)
	h.egal(V3._coups(evs, boss, "skill"), [V3._sur(g2, D6Loadout.slot_def(g2, 0).damage * s.executeMult, true)], "Gardien affaibli : `executeMult` fois les dégâts")
	h.ok(not boss.dead and boss.hp > 0.0 and victime.dead, "… jamais tué d'office")
	h.egal(boss.stun, 0.0, "… ni étourdi par l'effroi")
	# Terrain bas : la hache frappe par-dessus un obstacle bas (comme tout coup), il ne bouge pas.
	var g3 := _jeu(h, "grace")
	var x3: float = g3.player.x
	g3.room.low = [{"x0": x3 + 24.0, "y0": 0.0, "x1": x3 + 56.0, "y1": g3.room.h, "kind": "barrier"}]
	var e3 := V3._cible(g3, s.range + 20.0, 0.0)
	h.egal(V3._coups(_appui(h, g3, s.castTime + 0.1, 1.0, 0.0), e3, "skill"), [V3._sur(g3, s.damage)], "par-dessus un obstacle bas : le coup porte")
	h.proche(g3.player.x, x3, 12.0, "… et il reste de son côté")
	# Mort pendant le geste : le coup ne part pas.
	var g4 := _jeu(h, "grace")
	var e4 := V3._cible(g4, s.range, 0.0)
	h.avancer(g4, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
	D6Combat.damage_player(g4, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	evs = h.avancer(g4, h.ticks(s.castTime + 0.5))
	h.egal([g4.player.state, V3._de(evs, "grace").size(), e4.hp], ["dead", 0, e4.maxHp], "mort pendant le geste : rien ne part")
	# Changement de salle en plein geste : rien ne part dans la salle neuve.
	var g5 := _jeu(h, "grace")
	h.avancer(g5, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
	D6Run.enter_floor(g5, g5.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal(V3._de(h.avancer(g5, h.ticks(s.castTime + 0.3)), "grace").size(), 0, "changement de salle : rien ne part")

# ---------------------------------------------------------------- Chasseresse : Grêle des Limbes

static func _tests_grele(h) -> void:
	h.test("grele : le télégraphe d'abord (`delay` s, rien n'est touché), puis les traits tombent à `radius` u ; qui est sorti n'est pas touché", func(): _g_base(h))
	h.test("grele : sur la cible à portée, sinon à `throwDist` u devant elle ; jamais dans un mur ; rang 5", func(): _g_visee(h))
	h.test("grele / Déluge : elle retombe `waves` fois, les suivantes à `waveMult` ; / Givre des Limbes : ce qu'elle touche est ralenti", func(): _g_choix(h))
	h.test("grele : salle vide, Gardien, au-dessus d'une rivière, mort pendant (une grêle tirée tombe), changement de salle", func(): _g_limites(h))

static func _greles(g: Dictionary) -> Array:
	return V3._zones(g, "grele")

static func _g_base(h) -> void:
	var s := V3._def("grele")
	var g := _jeu(h, "grele")
	var p: Dictionary = g.player
	var e := V3._cible(g, 200.0, 0.0)
	var bord := V3._cible(g, 200.0 + s.radius - 10.0, 0.0)
	var sorti := V3._cible(g, 200.0, 60.0)
	var dehors := V3._cible(g, 200.0, s.radius + 80.0)
	var evs := _appui(h, g, s.castTime + 0.05)
	var zones := _greles(g)
	h.egal(zones.size(), 1, "une zone `grele` : le télégraphe")
	h.egal([zones[0].x, zones[0].y, zones[0].r], [e.x, e.y, s.radius], "sur la cible visée, à `radius` u")
	h.egal(V3._de(evs, "hailCall").map(func(ev): return [ev.tx, ev.r, ev.delay]), [[e.x, s.radius, s.delay]], "le tir vers le ciel est dit")
	evs = h.avancer(g, h.ticks(s.delay - 0.2))
	h.egal([V3._de(evs, "hit").size(), _greles(g).size()], [0, 1], "pendant `delay` s : rien n'est touché")
	sorti.y = p.y + s.radius + 80.0 # il sort de la zone avant la chute
	evs = h.avancer(g, h.ticks(0.3))
	h.egal(V3._coups(evs, e, "skill"), [V3._sur(g, s.damage)], "les traits tombent : `damage`")
	h.egal(V3._coups(evs, bord, "skill"), [V3._sur(g, s.damage)], "… à tout ce qui est dans le rayon")
	h.egal([V3._coups(evs, sorti).size(), V3._coups(evs, dehors).size()], [0, 0], "qui est sorti, ou n'y était pas, n'est pas touché")
	h.egal(V3._de(evs, "hail").map(func(ev): return [ev.wave, ev.last, ev.r]), [[1.0, true, s.radius]])
	h.egal(_greles(g).size(), 0, "la zone a disparu")
	h.proche(p.slots[0].cd, s.cooldown - s.castTime - s.delay - 0.15, 0.1)

static func _g_visee(h) -> void:
	var s := V3._def("grele")
	var g := _jeu(h, "grele")
	var p: Dictionary = g.player
	V3._cible(g, s.range + 200.0, 0.0) # hors de portée : elle ne la vise pas
	_appui(h, g, s.castTime + 0.05, 1.0, 0.0)
	h.proche(_greles(g)[0].x - p.x, s.throwDist, 1e-6, "sans cible à portée : à `throwDist` u dans la direction visée")
	var g2 := _jeu(h, "grele")
	var p2: Dictionary = g2.player
	g2.room.obstacles = [{"x0": p2.x + s.throwDist - 30.0, "y0": p2.y - 60.0, "x1": p2.x + s.throwDist + 40.0, "y1": p2.y + 60.0}]
	_appui(h, g2, s.castTime + 0.05, 1.0, 0.0)
	var z: Dictionary = _greles(g2)[0]
	h.ok(z.x <= p2.x + s.throwDist - 30.0 and not D6Physics.point_blocked(g2.room, z.x, z.y, 0.0), "jamais dans un pilier : elle tombe devant (%s)" % str(z.x - p2.x))
	var n: Dictionary = Arbre.node(V3._base(), "chasseresse", "grele")
	var g5 := V3._bac(h, "chasseresse", ["grele", null, null], {"grele": V3._cfg().skillRanks})
	var e5 := V3._cible(g5, 200.0, 0.0)
	h.egal(V3._coups(_appui(h, g5, s.castTime + s.delay + 0.2), e5, "skill"), [V3._sur(g5, Arbre.rank_value(n, "damage", V3._cfg().skillRanks))], "rang 5 : dégâts")

static func _g_choix(h) -> void:
	var s := V3._def("grele")
	var del := _pose("grele", "deluge")
	var n: Dictionary = Arbre.node(V3._base(), "chasseresse", "grele")
	var d3: float = Arbre.rank_value(n, "damage", V3._cfg().choiceRank)
	var g := _jeu(h, "grele", "deluge")
	var e := V3._cible(g, 200.0, 0.0)
	var evs := _appui(h, g, s.castTime + s.delay + 0.1)
	h.egal(V3._coups(evs, e, "skill"), [V3._sur(g, d3)], "déluge : la première chute, entière")
	h.egal(_greles(g).size(), 1, "… la zone reste")
	evs = h.avancer(g, h.ticks(del.interval * (del.waves - 1.0) + 0.1))
	var suites: Array = []
	for i in int(del.waves) - 1:
		suites.append(V3._sur(g, d3 * del.waveMult))
	h.egal(V3._coups(evs, e, "skill"), suites, "… puis `waves` − 1 chutes à `waveMult`")
	h.egal(V3._de(evs, "hail").map(func(ev): return ev.last), suites.map(func(_x): return false).slice(1) + [true], "la dernière est dite")
	h.egal(_greles(g).size(), 0)
	var givre := _pose("grele", "givre")
	var g2 := _jeu(h, "grele", "givre")
	var imp := V3._vif(g2, 200.0, 0.0, "imp")
	imp.stun = 5.0 # il reste sous la grêle
	evs = _appui(h, g2, s.castTime + s.delay + 0.1)
	h.egal(V3._coups(evs, imp, "skill").size(), 1, "givre : une seule chute")
	h.ok(imp.chill > givre.chill - 0.2 and imp.chill <= givre.chill, "givre : ralenti `chill` s (%s)" % str(imp.chill))
	h.proche(imp.chillMult, maxf(g2.tuning.combat.minChillMult, 1.0 - givre.chillMult), 1e-9, "… de `chillMult`")
	var g0 := _jeu(h, "grele")
	var imp0 := V3._vif(g0, 200.0, 0.0, "imp")
	imp0.stun = 5.0
	evs = _appui(h, g0, s.castTime + s.delay + 1.5)
	h.egal([V3._coups(evs, imp0, "skill").size(), imp0.chill], [1, 0.0], "sans amélioration : une chute, aucun ralentissement")

static func _g_limites(h) -> void:
	var s := V3._def("grele")
	var g := _jeu(h, "grele")
	var evs := _appui(h, g, s.castTime + s.delay + 0.2, 1.0, 0.0)
	h.egal([V3._de(evs, "hail").size(), V3._de(evs, "hit").size(), _greles(g).size()], [1, 0, 0], "salle vide : elle tombe sur rien et s'efface")
	var g2 := _jeu(h, "grele")
	var boss := _gardien(g2, 220.0, 0.0)
	evs = _appui(h, g2, s.castTime + s.delay + 0.2)
	h.egal(V3._coups(evs, boss, "skill"), [V3._sur(g2, s.damage, true)], "Gardien : un coup, à `damage`")
	# Au-dessus d'une rivière : ce sont des tirs, la grêle tombe sur l'eau et frappe l'autre rive.
	var g3 := _jeu(h, "grele")
	var p3: Dictionary = g3.player
	V3._riviere(g3, p3.x + s.throwDist - 32.0)
	var rive := V3._cible(g3, s.throwDist + 32.0 + 30.0, 0.0)
	_appui(h, g3, 0.0, 1.0, 0.0)
	evs = h.avancer(g3, h.ticks(s.castTime + s.delay + 0.2))
	h.ok(V3._de(evs, "hail").size() == 1, "cas choisi : elle est tombée")
	h.egal(V3._coups(evs, rive, "skill").size(), 1, "au-dessus de l'eau : l'ennemi de l'autre rive est touché")
	# Mort après le tir : la grêle déjà tirée tombe quand même.
	var g4 := _jeu(h, "grele")
	var e4 := V3._cible(g4, 200.0, 0.0)
	_appui(h, g4, s.castTime + 0.05)
	D6Combat.damage_player(g4, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	evs = h.avancer(g4, h.ticks(s.delay + 1.0))
	h.egal([g4.player.state, V3._coups(evs, e4, "skill").size()], ["dead", 1], "morte après le tir : la grêle tombe")
	# Mort PENDANT le geste : rien n'est tiré.
	var g5 := _jeu(h, "grele")
	h.avancer(g5, 1, {"skill1Pressed": true})
	D6Combat.damage_player(g5, 1e6, {"kind": "imp", "id": -1.0, "x": 0.0, "y": 0.0})
	evs = h.avancer(g5, h.ticks(s.castTime + s.delay + 0.5))
	h.egal([V3._de(evs, "hailCall").size(), _greles(g5).size()], [0, 0], "morte pendant le geste : rien n'est tiré")
	# Changement de salle : la zone ne suit pas.
	var g6 := _jeu(h, "grele")
	_appui(h, g6, s.castTime + 0.05, 1.0, 0.0)
	h.egal(_greles(g6).size(), 1, "cas choisi : en attente")
	D6Run.enter_floor(g6, g6.run.floor + 1.0, {"reward": "boon", "family": "colere"})
	h.egal([_greles(g6).size(), V3._de(h.avancer(g6, h.ticks(s.delay + 0.3)), "hail").size()], [0, 0], "changement de salle : plus de grêle")

# ---------------------------------------------------------------- ce qui vaut pour les trois

static func _tests_communs(h) -> void:
	h.test("bénédictions et objets : dégâts des compétences, recharge (Rancœur) et proc « de compétence » valent pour les trois", func(): _c_build(h))
	h.test("vues : l'entrée d'un pas et slot_view gardent leur forme ; visée dite ; slot_state au repos", func(): _c_vues(h))
	h.test("déterminisme : même graine, mêmes entrées → même partie, avec la quatrième compétence de chaque classe", func(): _c_determinisme(h))
	h.test("bots : le bot habile se sert de chacune des trois", func(): _c_bots(h))
	h.test("références : le catalogue joue chacune des trois, avec chaque amélioration", func(): _c_references(h))

static func _attente(id: String) -> float:
	var s := V3._def(id)
	return s.castTime + D6Js.nz(s.get("delay"), 0.0) + 0.2

static func _c_build(h) -> void:
	for id in ["ombre", "grace", "grele"]:
		var s := V3._def(id)
		var g := _jeu(h, id)
		V3._talisman(g, "skillDamageMult", 0.5)
		var e := V3._cible(g, 60.0, 0.0)
		var evs := _appui(h, g, _attente(id))
		h.egal(V3._coups(evs, e, "skill")[0], V3._sur(g, s.damage * 1.5), "%s : +50 %% de dégâts des compétences" % id)
		var g2 := _jeu(h, id)
		V3._benir(g2, "rancoeur")
		h.ok(g2.player.stats.skillCooldownMult < 1.0, "cas choisi")
		h.avancer(g2, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
		h.proche(g2.player.slots[0].cd, s.cooldown * g2.player.stats.skillCooldownMult, 1e-9, "%s : recharge réduite par Rancœur" % id)
		var g3 := _jeu(h, id)
		V3._benir(g3, "charme")
		var e3 := V3._cible(g3, 60.0, 0.0)
		_appui(h, g3, _attente(id))
		h.ok(e3.vuln > 0.0 and e3.vulnMult > 0.0, "%s : Charme fatal rend vulnérable" % id)
	# Le coup répété de l'ombre est un coup de compétence : le même bonus.
	var s := V3._def("ombre")
	var g := _jeu(h, "ombre")
	_appui(h, g, s.castTime + 0.05)
	V3._talisman(g, "skillDamageMult", 0.5)
	var e := V3._cible(g, 60.0, 0.0)
	h.avancer(g, 1, {"attackPressed": true})
	var evs: Array = h.avancer(g, h.ticks(0.4))
	h.egal(V3._coups(evs, e, "skill"), [V3._sur(g, g.tuning.combo[0].damage * s.echoMult * 1.5)], "ombre : son coup répété en profite")

static func _c_vues(h) -> void:
	h.egal(D6Game.empty_input().keys(), V3.ENTREE, "l'entrée d'un pas n'a pas changé")
	var visee := {"ombre": false, "grace": true, "grele": true}
	for class_id in QUATRIEMES:
		var id: String = QUATRIEMES[class_id]
		var g := V3._bac(h, class_id, [id, null, null])
		var vue: Dictionary = D6Loadout.slot_view(g, 0)
		h.egal(vue.keys(), V3.VUE, "%s : slot_view garde sa forme" % id)
		h.egal([vue.id, vue.name, vue.icon, vue.aimed, vue.kind, vue.ready], [id, V3._def(id).name, V3._def(id).icon, visee[id], "skill", true], "%s : nom, pictogramme, visée" % id)
		h.egal(D6Loadout.slot_state(g, 0), {"charging": false, "chargeFrac": 0.0, "active": false, "activeFrac": 0.0}, "%s : slot_state au repos" % id)

static func _empreinte(g: Dictionary) -> Array:
	var p: Dictionary = g.player
	var store: Dictionary = D6KitCommon.kit_store(g)
	return [
		D6Game.state_hash(g), p.hp, p.x, p.y, p.slots.map(func(st): return [st.cd, st.charges]),
		g.allies.map(func(a): return [a.id, a.kind, a.x, a.y, a.life]),
		store.zones.map(func(z): return [z.kind, z.x, z.y, z.t]), g.telemetry.skillCasts, g.telemetry.damageDealt, p.surge,
	]

static func _jouer(h, class_id: String, graine: float, compte: Dictionary) -> Dictionary:
	var id: String = QUATRIEMES[class_id]
	var choix: String = Arbre.node(V3._base(), class_id, id).choices[1].id
	var meta := V3._meta(class_id, [id, V3.NEUVES[class_id][0], V3.NEUVES[class_id][1]], {id: V3._cfg().choiceRank}, {id: choix})
	var g: Dictionary = h.partie({"seed": graine, "startFloor": 6.0, "meta": meta, "godMode": true})
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
		for ev in g.events:
			if ["allySpawn", "grace", "hail", "echo", "shadeSwap", "graceKill"].has(ev.type):
				compte[ev.type] = compte.get(ev.type, 0) + 1
		g.events.clear()
		if g.mode == "choice":
			D6Game.apply_command(g, {"type": "choose", "index": 0})
	return g

static func _c_determinisme(h) -> void:
	var preuve := {"revenant": "allySpawn", "bourreau": "grace", "chasseresse": "hail"}
	for class_id in QUATRIEMES:
		var compte := {}
		var a := _jouer(h, class_id, 4242.0, compte)
		var b := _jouer(h, class_id, 4242.0, {})
		h.egal(_empreinte(a), _empreinte(b), "%s : deux parties identiques" % class_id)
		h.ok(compte.get(preuve[class_id], 0) >= 2, "%s : %s a vraiment été jouée (%s)" % [class_id, QUATRIEMES[class_id], str(compte)])
		h.different(_empreinte(a), _empreinte(_jouer(h, class_id, 4243.0, {})), "%s : une autre graine donne une autre partie" % class_id)

## Le bot habile (celui des oracles et des références), 40 s à l'étage 7, la compétence seule.
static func _c_bots(h) -> void:
	var preuve := {"revenant": "allySpawn", "bourreau": "grace", "chasseresse": "hail"}
	for spec in Catalogue.all():
		if not String(spec.name).begins_with("competences2_") or spec.policy != "skilled":
			continue
		var class_id: String = spec.kit[0]
		var compte := {}
		var g: Dictionary = Partie.start(spec)
		var mem := {}
		for i in h.ticks(45.0):
			if g.mode != "play":
				if not Bots.resolve_choice(g, "skilled"):
					break
				continue
			D6Game.step_game(g, Bots.play("skilled", g, mem))
			for ev in g.events:
				compte[ev.type] = compte.get(ev.type, 0) + 1
			g.events.clear()
		h.ok(compte.get(preuve[class_id], 0) >= 2, "%s : le bot habile s'en sert (%s fois)" % [spec.name, str(compte.get(preuve[class_id], 0))])
		h.ok(compte.get("hit", 0) > 0, "%s : la partie a été jouée" % spec.name)

static func _c_references(h) -> void:
	var jouees := {}
	var choisies := {}
	for spec in Catalogue.all():
		if not String(spec.name).begins_with("competences2_"):
			continue
		for id in spec.slots:
			jouees[id] = true
			h.ok((V3._base().classes[spec.kit[0]].skills + V3._base().classes[spec.kit[0]].gadgets).has(id), "%s : %s est une compétence de %s" % [spec.name, id, spec.kit[0]])
		for id in spec.get("tree", {}).get("choices", {}):
			choisies["%s/%s" % [id, spec.tree.choices[id]]] = true
	for class_id in QUATRIEMES:
		var id: String = QUATRIEMES[class_id]
		h.ok(jouees.has(id), "une partie competences2_* joue %s" % id)
		for ch in Arbre.node(V3._base(), class_id, id).choices:
			h.ok(choisies.has("%s/%s" % [id, ch.id]), "une partie competences2_* joue %s/%s" % [id, ch.id])
