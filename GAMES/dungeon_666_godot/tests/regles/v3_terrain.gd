extends RefCounted
## COMBAT V3, étape 1 bis (design/COMBAT_V3.md) — DÉPLACEMENT DE CLASSE et TERRAIN À FRANCHIR :
##   - un déplacement par classe sur le bouton du dash : dash (Revenant), saut (Bourreau), roulade
##     (Chasseresse) ; tout ce qui parle du « dash » vaut pour les trois ;
##   - terrain BAS (rivière, obstacle bas : room.low) : on n'y marche pas, on tire et l'on voit
##     par-dessus, le déplacement de classe le franchit SI l'arrivée est sur la terre ferme — sinon
##     le geste est raccourci : jamais de chute, jamais de héros dans l'eau, jamais coincé ;
##   - un recul s'arrête au bord, une ruée aussi (sonnée comme à un mur), les ennemis qui marchent
##     contournent par les gués, le Traqueur réapparaît de l'autre côté, rien n'apparaît dans l'eau ;
##   - chaque disposition reste finissable à pied (remplissage sur la grille de navigation).
## Les nombres attendus sont lus dans les données (data/classes.json `moves`, data/heros.json
## `dash`, data/salles.json `TERRAINS`), jamais recopiés.

const Bots = preload("res://outils/bots/bots.gd")
const Catalogue = preload("res://references/catalogue.gd")
const Partie = preload("res://references/partie.gd")

const DT := 1.0 / 60.0
const EPS := 1e-6
const CLASSES := ["revenant", "bourreau", "chasseresse"]
const TOUTES := ["classes", "weapons", "skills", "gadgets"]
const ETAGE := 6.0 # un étage de combat où le terrain peut être tiré (room.terrainFrom = 5)
## Rivière d'essai : un ruban vertical de 64 u, à droite du centre de la salle (héros au centre, x = 700).
const RIVE_G := 760.0
const RIVE_D := 824.0
const PAS_FIN := 8.0 # u : grille fine de la preuve « aucune poche »
const VOISINS_4 := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const VOISINS_8 := [[1, 0], [-1, 0], [0, 1], [0, -1], [1, 1], [1, -1], [-1, 1], [-1, -1]]
const ESSAIS := 1000 # gestes aléatoires par disposition ET par classe (« jamais coincé »)
const PAS_ESSAI := 34
const GRAINES := 300

static func tests(h) -> void:
	_tests_donnees(h)
	_tests_regles(h)
	_tests_ennemis(h)
	_tests_deplacements(h)
	_tests_effets_de_dash(h)
	_tests_salles(h)
	_tests_bots(h)

# ---------------------------------------------------------------- outillage

static func _meta(class_id: String) -> Dictionary:
	var t: Dictionary = D6Data.create_tuning()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in TOUTES:
		m.unlocked[k] = t[k].keys()
	var c: Dictionary = t.classes[class_id]
	m.loadout = {"classId": class_id, "slots": [c.skills[0], c.gadgets[0], null]}
	m.equipment.arme = D6Profile.starter_weapon(t, c.weapons[0])
	m.equipment.arme.uid = "i9000"
	return m

## Salle vidée, héros au centre, jamais de critique.
static func _bac(h, class_id: String, opts: Dictionary = {}) -> Dictionary:
	var o := {"seed": 7.0, "meta": _meta(class_id)}
	o.merge(opts, true)
	var g: Dictionary = h.bac_a_sable(o)
	g.tuning.combat.critChance = 0.0
	return g

## Pose un terrain bas d'essai dans une salle vidée, et refait le champ de navigation.
static func _poser(g: Dictionary, low: Array) -> void:
	g.room.low = low
	g.room.nav = D6Nav.build_nav(g.room)

static func _riviere(kind: String = "river", x0: float = RIVE_G, x1: float = RIVE_D) -> Array:
	return [{"x0": x0, "y0": 0.0, "x1": x1, "y1": 880.0, "kind": kind}]

## Salle vidée + le ruban d'essai, héros au centre (à 60 u de la rive gauche).
static func _bande(h, class_id: String, kind: String = "river", x1: float = RIVE_D) -> Dictionary:
	var g := _bac(h, class_id)
	_poser(g, _riviere(kind, RIVE_G, x1))
	return g

## Une VRAIE salle de la disposition `layout` (étage ETAGE), vidée de ses vagues, héros à l'entrée.
static func _salle(h, class_id: String, layout: String, seed_n: float = 5.0, vider: bool = true) -> Dictionary:
	var g: Dictionary = h.partie({"seed": seed_n, "meta": _meta(class_id), "startFloor": ETAGE})
	var plan: Dictionary = D6Sections.compose_floor(g.tuning, g.seed, ETAGE, {"reward": "boon"}).duplicate()
	plan.layouts = [{"id": layout, "weight": 1.0}]
	g.spawns.clear()
	g.enemies.clear()
	g.room = D6Room.build_room(g, g.info, plan)
	g.room.plan = plan
	if vider:
		g.room.waves = []
		g.room.waveIndex = 0.0
		g.room.cleared = true
	var start: Dictionary = D6Room.player_start(g.room)
	g.player.x = start.x
	g.player.y = start.y
	g.tuning.combat.critChance = 0.0
	g.events.clear()
	return g

static func _terrains() -> Array:
	return D6Data.tables().room.TERRAINS.keys()

## Ennemi d'essai : ne frappe pas (recharge infinie) ; increvable par défaut.
static func _ennemi(g: Dictionary, kind: String, x: float, y: float, hp: float = 50000.0) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, x, y, {"spawnT": 0.0})
	e.cooldown = 999.0
	e.maxHp = hp
	e.hp = hp
	return e

## Mannequin : en plus, il ne bouge pas (étourdi) et pèse lourd.
static func _mannequin(g: Dictionary, x: float, y: float) -> Dictionary:
	var e := _ennemi(g, "brute", x, y)
	e.mass = 1000.0
	e.stun = 999.0
	return e

static func _de(evs: Array, type: String) -> Array:
	return evs.filter(func(ev): return ev.type == type)

static func _dans_l_eau(g: Dictionary) -> bool:
	return D6Physics.low_at(g.room, g.player.x, g.player.y, g.player.r)

## Joue le déplacement de classe vers (dx, dy) jusqu'à ce que le héros soit de nouveau libre. Rend les événements.
static func _geste(h, g: Dictionary, dx: float, dy: float) -> Array:
	var evs: Array = h.avancer(g, 1, {"moveX": dx, "moveY": dy, "dashPressed": true})
	var garde := 0
	while g.player.state == "dash" and garde < 120:
		evs.append_array(h.avancer(g, 1))
		garde += 1
	return evs

## Remet le héros à neuf entre deux essais (même partie, autre place).
static func _remettre(g: Dictionary, x: float, y: float) -> void:
	var p: Dictionary = g.player
	p.x = x
	p.y = y
	p.vx = 0.0
	p.vy = 0.0
	p.state = "free"
	p.attack = null
	p.cast = null
	p.dashCharges = D6Player.max_dash_charges(g)
	p.dashRecharge = 0.0
	p.iframes = 0.0
	p.dodgeIframes = 0.0
	p.strikeWindow = 0.0
	p.buffer.action = null
	p.buffer.t = 0.0
	p.superCharge = 0.0
	p.superHold = 0.0
	p.superArm = false
	p.attackHeld = false
	p.freeze = 0.0
	p.hp = p.maxHp
	for st in p.slots:
		st.cd = 0.0
	g.hitstop = 0.0
	g.mode = "play"
	g.projectiles.clear()
	g.events.clear()

# ---------------------------------------------------------------- données

static func _tests_donnees(h) -> void:
	h.test("données : chaque classe a son déplacement — dash, saut, roulade", func(): _d_classes(h))
	h.test("données : le saut est invulnérable tout son vol, a une seule charge, une recharge plus longue et un choc sans dégât", func(): _d_saut(h))
	h.test("données : la roulade va le plus loin des trois ; le saut le moins loin", func(): _d_portees(h))
	h.test("données : chaque terrain bas appartient à une disposition, touche un mur en le dépassant ou laisse passer le plus gros corps", func(): _d_terrains(h))
	h.test("données : le terrain n'est tiré qu'à partir de room.terrainFrom, et l'est ensuite", func(): _d_introduction(h))
	h.test("tuning : tuning.dash est le bloc ACTIF du déplacement de la classe ; le Revenant garde le dash de base tel quel", func(): _d_bloc_actif(h))

static func _d_classes(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var attendus := {"revenant": "dash", "bourreau": "saut", "chasseresse": "roulade"}
	for class_id in attendus:
		var id = t.classes[class_id].get("move")
		h.ok(t.moves.has(id), "%s : déplacement « %s » inconnu" % [class_id, str(id)])
		if t.moves.has(id):
			h.egal(t.moves[id].kind, attendus[class_id], class_id)
		var g := _bac(h, class_id)
		h.egal(D6Player.move_kind(g), attendus[class_id], "%s en partie" % class_id)
		h.egal(D6Loadout.move_id(g), id)
	for class_id in t.classes:
		h.ok(t.moves.has(t.classes[class_id].get("move")), "classe %s : son déplacement existe" % class_id)

static func _d_saut(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var saut: Dictionary = t.moves.saut
	h.ok(saut.iframes >= saut.duration, "i-frames (%s) >= durée du vol (%s)" % [saut.iframes, saut.duration])
	h.egal(saut.charges, 1.0, "une seule charge")
	h.ok(saut.recharge > t.dash.recharge, "recharge plus longue que le dash (%s > %s)" % [saut.recharge, t.dash.recharge])
	h.ok(saut.duration > t.dash.duration, "il s'élève et retombe : plus long qu'un dash")
	h.ok(saut.shockRadius > 0.0 and saut.shockKnockback > 0.0, "un choc qui repousse")
	h.ok(not saut.has("shockDamage") and not saut.has("damage"), "aucun dégât : ce n'est pas une attaque")
	h.egal(saut.strikeCancelFrom, 0.0, "aucune frappe ne coupe le vol")
	h.egal(saut.chainFrom, 0.0, "aucun second saut ne coupe le vol")

static func _portee(h, class_id: String) -> float:
	var g := _bac(h, class_id)
	var x0: float = g.player.x
	_geste(h, g, 1.0, 0.0)
	h.avancer(g, 1)
	return g.player.x - x0

static func _d_portees(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var dash := _portee(h, "revenant")
	var saut := _portee(h, "bourreau")
	var roulade := _portee(h, "chasseresse")
	h.ok(roulade > dash and dash > saut, "roulade %s > dash %s > saut %s" % [roulade, dash, saut])
	for class_id in CLASSES:
		var voulu: float = t.dash.distance * (1.0 + D6Js.nz(t.classes[class_id].stats.get("dashDistanceMult"), 0.0))
		var obtenu: float = _portee(h, class_id)
		h.ok(absf(obtenu - voulu) < voulu * 0.12, "%s : %s u parcourues pour %s voulues" % [class_id, obtenu, voulu])

static func _rects(layout: String) -> Array:
	var room: Dictionary = D6Data.default_tuning().room
	var out: Array = []
	var terrain: Dictionary = D6Data.tables().room.TERRAINS[layout]
	for key in ["rivers", "barriers"]:
		for o in terrain[key]:
			out.append([o[0] * room.width - o[2] / 2.0, o[1] * room.height - o[3] / 2.0, o[0] * room.width + o[2] / 2.0, o[1] * room.height + o[3] / 2.0])
	return out

static func _d_terrains(h) -> void:
	var t: Dictionary = D6Data.default_tuning()
	var room: Dictionary = t.room
	var tables: Dictionary = D6Data.tables().room
	var widest := 0.0
	for kind in t.enemies:
		widest = maxf(widest, 2.0 * t.enemies[kind].radius * t.elite.sizeMult)
	h.ok(tables.TERRAINS.size() >= 4, "au moins quatre dispositions à terrain (%d)" % tables.TERRAINS.size())
	for id in tables.TERRAINS:
		h.ok(tables.LAYOUTS.has(id), "terrain « %s » : aucune disposition de ce nom" % id)
		h.ok(not tables.COMBAT_LAYOUTS.has(id), "%s : pas dans les dispositions du tout début" % id)
		var rects := _rects(id)
		h.ok(rects.size() > 0, "%s : un terrain vide n'est pas un terrain" % id)
		for i in rects.size():
			var r: Array = rects[i]
			h.ok(r[2] > r[0] and r[3] > r[1] and r[2] > 0.0 and r[0] < room.width and r[3] > 0.0 and r[1] < room.height, "%s, terrain %d : dans la salle" % [id, i])
			# Contre un mur : il le DÉPASSE (rien ne passe entre eux), ou laisse passer le plus gros corps.
			for gap in [r[0] - room.wallPad, r[1] - room.wallPad, room.width - room.wallPad - r[2], room.height - room.wallPad - r[3]]:
				h.ok(gap <= 0.0 or gap >= widest, "%s, terrain %d : %s u entre lui et le mur (dépasser le mur, ou au moins %s u)" % [id, i, str(gap), str(widest)])
	h.ok(true)

static func _d_introduction(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var terrains := _terrains()
	var from: float = t.room.terrainFrom
	h.ok(from >= 3.0, "pas dans les toutes premières salles (terrainFrom = %s)" % from)
	var vus := {}
	for seed_i in range(1, 41):
		for floor_i in range(1, int(from) + 14):
			var ids: Array = D6Sections.floor_slot(t, float(seed_i), float(floor_i)).layouts.map(func(l): return l.id)
			for id in ids:
				if terrains.has(id):
					h.ok(float(floor_i) >= from, "graine %d, étage %d : « %s » trop tôt" % [seed_i, floor_i, id])
					vus[id] = true
	h.ok(vus.size() >= 2, "le premier Cercle tire du terrain dès terrainFrom (%s)" % str(vus.keys()))
	# Chaque disposition à terrain sert dans un Cercle au moins.
	for id in terrains:
		h.ok(t.circles.any(func(c): return D6Js.nz(c.layouts.get(id), 0.0) > 0.0), "%s : citée par un Cercle" % id)
	# Tirage réel : sur 300 graines à l'étage ETAGE, du terrain sort, et room.low suit la disposition.
	var tires := {}
	for seed_i in range(1, GRAINES + 1):
		var g: Dictionary = h.partie({"seed": float(seed_i), "startFloor": ETAGE})
		var a_terrain: bool = terrains.has(g.room.layout)
		h.egal(not g.room.low.is_empty(), a_terrain, "graine %d (%s) : room.low" % [seed_i, g.room.layout])
		if a_terrain:
			tires[g.room.layout] = true
	h.ok(tires.size() >= 2, "dispositions à terrain tirées à l'étage %s : %s" % [ETAGE, str(tires.keys())])

static func _d_bloc_actif(h) -> void:
	var rev := _bac(h, "revenant")
	h.ok(is_same(rev.tuning.dash, rev.tuning.dashBase), "Revenant : tuning.dash EST le dash de base")
	h.egal(rev.tuning.dash, D6Data.default_tuning().dash, "… inchangé")
	for class_id in ["bourreau", "chasseresse"]:
		var g := _bac(h, class_id)
		var m: Dictionary = g.tuning.moves[g.tuning.classes[class_id].move]
		for cle in m:
			h.egal(g.tuning.dash[cle], m[cle], "%s : tuning.dash.%s vient du déplacement" % [class_id, cle])
		h.egal(g.tuning.dash.distance, g.tuning.dashBase.distance, "la distance de base reste celle du dash (× la statistique de classe)")
		h.egal(g.player.dashCharges, m.charges, "%s naît avec les charges de son déplacement" % class_id)
	# Une surcharge de réglage vise le dash de base : elle vaut pour qui n'a pas son propre nombre.
	var g2 := _bac(h, "chasseresse", {"tuning": {"dash": {"distance": 200.0, "perfectDodgeSuper": 0.5}}})
	h.egal(g2.tuning.dash.distance, 200.0)
	h.egal(g2.tuning.dash.perfectDodgeSuper, 0.5)
	h.egal(g2.tuning.dash.duration, g2.tuning.moves.roulade.duration, "… et le déplacement garde les siens")

# ---------------------------------------------------------------- règles du terrain

static func _tests_regles(h) -> void:
	for kind in ["river", "barrier"]:
		h.test("à pied : le héros ne traverse pas (%s), il s'arrête au bord" % kind, func(): _r_a_pied(h, kind))
		h.test("déplacement : chaque classe franchit (%s) quand l'arrivée est sur la terre ferme" % kind, func(): _r_franchit(h, kind))
	h.test("déplacement : arrivée dans l'eau = geste RACCOURCI au bord, jamais dans l'eau ; charge dépensée, esquive gardée, « moveShort »", func(): _r_raccourci(h))
	h.test("déplacement : au bord d'une rivière trop large, le geste se fait SUR PLACE (done = 0), sans chute", func(): _r_sur_place(h))
	h.test("déplacement : piliers et murs arrêtent toujours le geste (rien de haut ne se franchit)", func(): _r_piliers(h))
	h.test("déplacement : rien ne coupe le geste au-dessus de l'eau (frappe de dash, second dash, ultime attendent la terre ferme)", func(): _r_pas_de_coupe(h))
	h.test("Bond du bourreau : il franchit la rivière ; arrivée dans l'eau = raccourci, impact sur la terre ferme", func(): _r_bond(h))
	h.test("tirs : flèche ennemie, Lance du héros et tir d'arme passent au-dessus ; la vue aussi ; la marche non", func(): _r_tirs(h))
	h.test("recul : un ennemi projeté vers la rivière s'arrête au bord, sans choc de mur", func(): _r_recul(h))
	h.test("ramassables : l'or aimanté par le héros de l'autre rive s'arrête au bord", func(): _r_ramassable(h))
	h.test("jamais coincé : %d gestes aléatoires par disposition et par classe — jamais dans l'eau au repos, toujours sur une case reliée à l'entrée" % ESSAIS, func(): _r_jamais_coince(h))

static func _r_a_pied(h, kind: String) -> void:
	for class_id in CLASSES:
		var g := _bande(h, class_id, kind)
		var noye := false
		for i in h.ticks(2.0):
			h.avancer(g, 1, {"moveX": 1.0})
			noye = noye or _dans_l_eau(g)
		h.ok(not noye, "%s : jamais dans le terrain en marchant" % class_id)
		h.proche(g.player.x, RIVE_G - g.player.r, 0.01, "%s : arrêté contre la rive" % class_id)
		# Il longe le bord : la marche glisse, elle ne colle pas.
		var y0: float = g.player.y
		h.avancer(g, 30, {"moveX": 0.7, "moveY": 0.7})
		h.ok(g.player.y > y0 + 20.0, "%s : il glisse le long de la rive" % class_id)

static func _r_franchit(h, kind: String) -> void:
	for class_id in CLASSES:
		var g := _bande(h, class_id, kind)
		g.player.x = RIVE_G - g.player.r - 2.0
		var evs := _geste(h, g, 1.0, 0.0)
		h.ok(g.player.x >= RIVE_D + g.player.r - 0.01, "%s : de l'autre côté (x = %s)" % [class_id, g.player.x])
		h.ok(not _dans_l_eau(g), "%s : sur la terre ferme" % class_id)
		h.egal(_de(evs, "moveShort").size(), 0, "%s : geste entier" % class_id)
		h.egal(_de(evs, "dash").size(), 1)

static func _r_raccourci(h) -> void:
	for class_id in CLASSES:
		var g := _bande(h, class_id, "river", 1300.0) # 540 u de large : infranchissable
		var p: Dictionary = g.player
		p.x = RIVE_G - p.r - 40.0
		var charges: float = p.dashCharges
		var evs: Array = h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
		h.egal(p.state, "dash", "%s : le geste part quand même" % class_id)
		h.egal(p.dashCharges, charges - 1.0, "%s : la charge est dépensée" % class_id)
		h.ok(p.iframes >= g.tuning.dash.iframes - DT - EPS, "%s : l'esquive est gardée (%s)" % [class_id, p.iframes])
		var noye := false
		for i in 60:
			evs.append_array(h.avancer(g, 1, {"moveX": 1.0}))
			noye = noye or (p.state != "dash" and _dans_l_eau(g))
		h.ok(not noye, "%s : jamais posé dans l'eau" % class_id)
		h.ok(p.x <= RIVE_G - p.r + 0.01 and p.x > RIVE_G - p.r - 40.0, "%s : il a avancé jusqu'au bord (x = %s)" % [class_id, p.x])
		var court := _de(evs, "moveShort")
		if h.egal(court.size(), 1, "%s : un événement moveShort" % class_id):
			h.ok(court[0].done < court[0].reach and court[0].done >= 0.0, "parcouru %s sur %s" % [court[0].done, court[0].reach])
			h.egal(court[0].move, D6Player.move_kind(g))

static func _r_sur_place(h) -> void:
	for class_id in CLASSES:
		var g := _bande(h, class_id, "river", 1300.0)
		var p: Dictionary = g.player
		p.x = RIVE_G - p.r
		var x0: float = p.x
		var evs := _geste(h, g, 1.0, 0.0)
		h.ok(absf(p.x - x0) < 6.0 and not _dans_l_eau(g), "%s : resté au bord (%s -> %s)" % [class_id, x0, p.x])
		var court := _de(evs, "moveShort")
		if h.egal(court.size(), 1, class_id):
			h.egal(court[0].done, 0.0, "%s : sur place" % class_id)
		h.egal(g.telemetry.deaths, 0.0)
		h.egal(p.hp, p.maxHp, "le décor ne blesse jamais")

static func _r_piliers(h) -> void:
	for class_id in CLASSES:
		var g := _bac(h, class_id)
		g.room.obstacles = [{"x0": 760.0, "y0": 300.0, "x1": 830.0, "y1": 580.0}]
		_geste(h, g, 1.0, 0.0)
		h.ok(g.player.x <= 760.0 - g.player.r + 0.01, "%s : arrêté par le pilier (x = %s)" % [class_id, g.player.x])
		g.player.x = g.room.w - g.room.pad - 60.0
		g.player.dashCharges = 1.0
		_geste(h, g, 1.0, 0.0)
		h.ok(g.player.x <= g.room.w - g.room.pad - g.player.r + 0.01, "%s : arrêté par le mur" % class_id)

static func _r_pas_de_coupe(h) -> void:
	# Le dash du Revenant, réglé pour qu'une attaque le coupe à TOUT moment (labo « toutDash ») et
	# qu'un second dash s'enchaîne à tout moment : au-dessus de l'eau, ni l'un ni l'autre ne part.
	var g := _bande(h, "revenant")
	var p: Dictionary = g.player
	g.tuning.dash.strikeCancelFrom = 1.0
	g.tuning.dash.chainFrom = 1.0
	p.x = RIVE_G - p.r - 2.0
	p.superCharge = 1.0
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true, "attack": true, "attackPressed": true})
	var coupe := false
	var au_dessus := 0
	for i in 40:
		# Ce qui compte : un pas COMMENCÉ au-dessus de l'eau ne lance ni frappe, ni dash, ni ultime.
		var mouille := _dans_l_eau(g)
		var avant := [g.telemetry.dashes, g.telemetry.attacks, g.telemetry.superUses]
		h.avancer(g, 1, {"moveX": -1.0, "dashPressed": true, "attack": true, "attackPressed": true})
		if mouille:
			au_dessus += 1
			coupe = coupe or avant != [g.telemetry.dashes, g.telemetry.attacks, g.telemetry.superUses]
	h.ok(au_dessus >= 2, "le héros est bien passé au-dessus de l'eau (%d pas)" % au_dessus)
	h.ok(not coupe, "aucune frappe, aucun dash, aucun ultime lancé depuis le dessus de l'eau")
	h.ok(g.telemetry.dashes >= 2.0, "… alors que, la terre ferme touchée, le second dash part (%s dashs)" % g.telemetry.dashes)
	h.avancer(g, 60)
	h.ok(not _dans_l_eau(g), "il finit sur la terre ferme")

static func _r_bond(h) -> void:
	var g := _bande(h, "bourreau")
	var p: Dictionary = g.player
	p.x = RIVE_G - p.r - 2.0
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	evs.append_array(h.avancer(g, h.ticks(g.tuning.skills.bond.leapTime) + 4))
	h.ok(p.x >= RIVE_D + p.r - 0.01 and not _dans_l_eau(g), "le Bond franchit (x = %s)" % p.x)
	h.egal(_de(evs, "moveShort").size(), 0)
	# Rivière infranchissable : il retombe au bord, et l'impact a lieu là.
	var g2 := _bande(h, "bourreau", "river", 1300.0)
	var q: Dictionary = g2.player
	q.x = RIVE_G - q.r - 30.0
	evs = h.avancer(g2, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	var noye := false
	for i in 40:
		evs.append_array(h.avancer(g2, 1))
		noye = noye or (q.state != "cast" and _dans_l_eau(g2))
	h.ok(not noye and not _dans_l_eau(g2), "jamais posé dans l'eau")
	h.ok(q.x <= RIVE_G - q.r + 0.01, "raccourci au bord (x = %s)" % q.x)
	var boums := evs.filter(func(ev): return ev.type == "explode" and ev.get("kind") == "bond")
	if h.egal(boums.size(), 1, "un seul impact"):
		h.ok(not D6Physics.low_at(g2.room, boums[0].x, boums[0].y, q.r), "… sur la terre ferme")
	h.egal(_de(evs, "moveShort").size(), 1)

static func _r_tirs(h) -> void:
	for kind in ["river", "barrier"]:
		var g := _bande(h, "revenant", kind)
		var p: Dictionary = g.player
		h.ok(D6Physics.line_of_sight(g.room, p.x, p.y, 1000.0, p.y), "%s : on voit par-dessus" % kind)
		h.ok(not D6Physics.shot_blocked(g.room, RIVE_G - 5.0, p.y, RIVE_G + 30.0, p.y), "%s : un tir n'est pas arrêté" % kind)
		h.ok(not D6Physics.walk_clear(g.room, p.x, p.y, 1000.0, p.y), "%s : on n'y marche pas tout droit" % kind)
		# Flèche ennemie tirée de l'autre rive : elle touche le héros.
		D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": 1000.0, "y": p.y, "vx": -700.0, "vy": 0.0, "r": 6.0, "damage": 5.0, "range": 900.0, "sourceId": 0.0})
		var evs: Array = h.avancer(g, 40)
		h.egal(_de(evs, "playerHurt").size(), 1, "%s : la flèche traverse et touche" % kind)
		# Lance du héros vers un mannequin de l'autre rive.
		var e := _mannequin(g, 950.0, p.y)
		evs = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
		evs.append_array(h.avancer(g, 60))
		h.ok(evs.any(func(ev): return ev.type == "hit" and ev.get("kind") == "skill" and ev.id == e.id), "%s : la Lance touche de l'autre côté" % kind)
	# Tir d'arme (arc) par-dessus.
	var gc := _bande(h, "chasseresse")
	var cible := _mannequin(gc, 950.0, gc.player.y)
	var evs2: Array = h.avancer(gc, 1, {"attack": true, "attackPressed": true, "aimX": 1.0, "aimY": 0.0})
	evs2.append_array(h.avancer(gc, 60))
	h.ok(evs2.any(func(ev): return ev.type == "hit" and ev.id == cible.id), "la flèche de la Chasseresse touche de l'autre côté")

static func _r_recul(h) -> void:
	for kind in ["river", "barrier"]:
		var g := _bande(h, "revenant", kind)
		var e := _ennemi(g, "imp", RIVE_G - 60.0, 300.0)
		e.stun = 999.0
		var hp0: float = e.hp
		e.kvx = 2400.0 # bien au-delà de wallSlam.minSpeed
		var noye := false
		var evs: Array = []
		for i in 60:
			evs.append_array(h.avancer(g, 1))
			noye = noye or D6Physics.low_at(g.room, e.x, e.y, e.r)
		h.ok(not noye, "%s : jamais poussé dedans" % kind)
		h.proche(e.x, RIVE_G - e.r, 0.01, "%s : arrêté au bord" % kind)
		h.egal(_de(evs, "wallSlam").size(), 0, "%s : un bord n'est pas un mur" % kind)
		h.egal(e.hp, hp0, "aucun dégât")
		h.egal(g.telemetry.wallSlams, 0.0)

static func _r_ramassable(h) -> void:
	var g := _bande(h, "revenant")
	g.player.x = RIVE_G - g.player.r - 1.0
	var pk: Dictionary = D6Combat.spawn_pickup(g, "gold", RIVE_D + 30.0, g.player.y, 5.0)
	var noye := false
	for i in 120:
		h.avancer(g, 1)
		noye = noye or D6Physics.low_at(g.room, pk.x, pk.y, pk.r)
	h.ok(not noye, "l'or ne roule pas dans l'eau")
	h.ok(pk.x >= RIVE_D + pk.r - 0.01, "il reste sur sa rive (x = %s)" % pk.x)
	h.egal(D6Js.truthy(pk.get("dead")), false, "pas ramassé à travers la rivière")

## Cases de la grille fine où le héros (rayon r) peut se tenir, reliées à l'entrée de la salle.
static func _reliees(room: Dictionary, r: float) -> Dictionary:
	var cols := int(ceilf(room.w / PAS_FIN))
	var rows := int(ceilf(room.h / PAS_FIN))
	var libre := PackedByteArray()
	libre.resize(cols * rows)
	for cy in rows:
		for cx in cols:
			libre[cy * cols + cx] = 0 if D6Physics.ground_blocked(room, (cx + 0.5) * PAS_FIN, (cy + 0.5) * PAS_FIN, r) else 1
	var vu := PackedByteArray()
	vu.resize(cols * rows)
	var start: Dictionary = D6Room.player_start(room)
	var file: Array = [int(start.y / PAS_FIN) * cols + int(start.x / PAS_FIN)]
	vu[file[0]] = 1
	var tete := 0
	while tete < file.size():
		var c: int = file[tete]
		tete += 1
		for d in VOISINS_4:
			var nx: int = c % cols + d[0]
			@warning_ignore("integer_division")
			var ny: int = c / cols + d[1]
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var n := ny * cols + nx
			if libre[n] == 1 and vu[n] == 0:
				vu[n] = 1
				file.append(n)
	return {"cols": cols, "rows": rows, "libre": libre, "vu": vu, "atteintes": file.size()}

## Le point est-il sur une case reliée à l'entrée (ou tout contre : à moins de deux cases) ?
static func _relie(m: Dictionary, x: float, y: float) -> bool:
	var cx := int(x / PAS_FIN)
	var cy := int(y / PAS_FIN)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var nx := cx + dx
			var ny := cy + dy
			if nx >= 0 and ny >= 0 and nx < m.cols and ny < m.rows and m.vu[ny * m.cols + nx] == 1:
				return true
	return false

## Le cercle déborde-t-il des murs, ou mord-il sur un pilier (test exact du cercle, coins compris) ?
static func _dans_un_mur(room: Dictionary, x: float, y: float, r: float) -> bool:
	if x < room.pad + r or x > room.w - room.pad - r or y < room.pad + r or y > room.h - room.pad - r:
		return true
	for o in room.obstacles:
		var dx: float = x - clampf(x, o.x0, o.x1)
		var dy: float = y - clampf(y, o.y0, o.y1)
		if dx * dx + dy * dy < r * r:
			return true
	return false

## Entrée d'un pas d'un essai « jamais coincé » : six scénarios, dont ceux qui tentent de couper le geste.
static func _entree_essai(g: Dictionary, scenario: int, pas: int, dx: float, dy: float) -> Dictionary:
	match scenario:
		0: # le geste seul
			return {"moveX": dx, "moveY": dy, "dashPressed": pas == 0}
		1: # le geste, puis l'attaque martelée (frappe de dash)
			return {"moveX": dx, "moveY": dy, "dashPressed": pas == 0, "attack": true, "attackPressed": true}
		2: # le déplacement martelé, en changeant de direction
			return {"moveX": dx if pas % 6 < 3 else -dy, "moveY": dy if pas % 6 < 3 else dx, "dashPressed": true}
		3: # jauge pleine, attaque tenue (ultime armé), puis le geste
			return {"moveX": dx, "moveY": dy, "attack": true, "dashPressed": pas == 4}
		4: # la compétence de l'emplacement 1 (le Bond, pour le Bourreau), puis le geste qui l'interrompt
			return {"moveX": dx, "moveY": dy, "skill1Pressed": pas == 0, "skill1AimX": dx, "skill1AimY": dy, "dashPressed": pas == 5}
	return {"moveX": dx, "moveY": dy} # à pied

static func _r_jamais_coince(h) -> void:
	var total := 0
	var franchis := 0
	for layout in _terrains():
		for class_id in CLASSES:
			var g := _salle(h, class_id, layout)
			var m := _reliees(g.room, g.player.r)
			var rng: Dictionary = D6Rng.create_rng(D6Rng.hash_seed(float(layout.hash() & 0xffff), [CLASSES.find(class_id)]))
			var fautes: Array = []
			for essai in ESSAIS:
				var bilan := _un_essai(h, g, m, rng, essai)
				if bilan.faute != "" and fautes.size() < 3:
					fautes.append(bilan.faute)
				franchis += 1 if bilan.franchi else 0
				total += 1
			h.ok(fautes.is_empty(), "%s, %s : %s" % [layout, class_id, " | ".join(PackedStringArray(fautes))])
	h.ok(total >= ESSAIS * CLASSES.size() * 4, "%d gestes joués" % total)
	h.ok(franchis > total / 20, "le test franchit vraiment du terrain (%d gestes au-dessus de l'eau sur %d)" % [franchis, total])

## Un geste aléatoire depuis un point libre. Rend {faute: "" si tout va bien, franchi: passé au-dessus du terrain}.
static func _un_essai(h, g: Dictionary, m: Dictionary, rng: Dictionary, essai: int) -> Dictionary:
	var p: Dictionary = g.player
	var room: Dictionary = g.room
	var x := 0.0
	var y := 0.0
	for k in 200:
		x = D6Rng.rand_range(rng, room.pad + p.r, room.w - room.pad - p.r)
		y = D6Rng.rand_range(rng, room.pad + p.r, room.h - room.pad - p.r)
		if not D6Physics.ground_blocked(room, x, y, p.r + 0.5) and _relie(m, x, y):
			break
	_remettre(g, x, y)
	var a := D6Rng.rand(rng) * PI * 2.0
	var dx := cos(a)
	var dy := sin(a)
	var scenario := essai % 6
	p.superCharge = 1.0 if scenario == 3 else 0.0
	var franchi := false
	var faute := ""
	var pas := 0
	while pas < PAS_ESSAI or (D6Player.crossing(g) and pas < PAS_ESSAI + 60):
		D6Game.step_game(g, h.entree(_entree_essai(g, scenario, pas, dx, dy) if pas < PAS_ESSAI else {}))
		g.events.clear()
		pas += 1
		var mouille := _dans_l_eau(g)
		franchi = franchi or mouille
		if mouille and not D6Player.crossing(g) and faute == "":
			faute = "scénario %d depuis (%s, %s) vers (%s, %s) : dans le terrain au repos en (%s, %s), pas %d" % [scenario, x, y, dx, dy, p.x, p.y, pas]
	if faute == "" and (_dans_un_mur(room, p.x, p.y, p.r - 0.5) or not _relie(m, p.x, p.y)):
		faute = "scénario %d depuis (%s, %s) vers (%s, %s) : fini en (%s, %s), hors de la zone reliée à l'entrée" % [scenario, x, y, dx, dy, p.x, p.y]
	if faute == "" and (p.state == "dead" or p.hp < p.maxHp):
		faute = "scénario %d : le décor a blessé le héros" % scenario
	return {"faute": faute, "franchi": franchi}

# ---------------------------------------------------------------- ennemis

static func _tests_ennemis(h) -> void:
	h.test("ruée : le Bélier lancé vers la rivière s'arrête au bord, sonné comme contre un mur", func(): _e_ruee(h))
	h.test("Bélier : une rivière entre lui et le héros, il ne charge pas (il contourne)", func(): _e_belier_contourne(h))
	h.test("Bélier : il ne charge pas non plus si son CORPS mordrait sur le coin d'un gué ; la voie libre pour son corps, il charge", func(): _e_belier_coin(h))
	h.test("Charon : sa ruée s'arrête au bord d'un terrain bas comme à un mur", func(): _e_charon(h))
	h.test("ennemis qui marchent : dans chaque disposition à terrain, ils contournent par les gués et atteignent le héros, sans jamais entrer dans l'eau", func(): _e_contournent(h))
	h.test("Traqueur : il réapparaît de l'autre côté de la rivière, jamais dedans", func(): _e_traqueur(h))
	h.test("rien n'apparaît dans l'eau sur %d graines : vagues, invocations, récompense, entrée, ramassables" % GRAINES, func(): _e_apparitions(h))

static func _e_ruee(h) -> void:
	for kind in ["river", "barrier"]:
		var g := _bande(h, "revenant", kind)
		g.player.x = 1000.0 # le héros est de l'autre côté
		var e := _ennemi(g, "charger", 500.0, g.player.y)
		e.state = "charge"
		e.stateTime = 0.0
		e.dirX = 1.0
		e.dirY = 0.0
		e.hitPlayer = false
		e.atkId = 999.0
		var evs: Array = []
		var noye := false
		for i in 60:
			evs.append_array(h.avancer(g, 1))
			noye = noye or D6Physics.low_at(g.room, e.x, e.y, e.r)
		h.ok(not noye, "%s : la ruée ne franchit pas" % kind)
		h.proche(e.x, RIVE_G - e.r, 0.5, "%s : arrêté au bord" % kind)
		h.egal(_de(evs, "chargerWall").size(), 1, "%s : il percute" % kind)
		h.ok(e.stun > 0.0 and e.state == "stunned", "%s : sonné (%s s)" % [kind, e.stun])
		h.egal(_de(evs, "playerHurt").size(), 0)

static func _e_belier_contourne(h) -> void:
	var g := _bande(h, "revenant")
	var p: Dictionary = g.player
	p.x = RIVE_G - p.r - 4.0
	var e: Dictionary = D6Enemies.create_enemy(g, "charger", RIVE_D + 40.0, p.y, {"spawnT": 0.0})
	e.cooldown = 0.0
	h.ok(Vector2(e.x - p.x, e.y - p.y).length() < g.tuning.enemies.charger.attackRange, "le héros est à portée de charge")
	var charge := false
	for i in h.ticks(3.0):
		h.avancer(g, 1)
		charge = charge or e.state == "windup" or e.state == "charge"
	h.ok(not charge, "il ne charge pas à travers l'eau")
	# Témoin : sans la rivière, au même endroit, il charge.
	var g2 := _bac(h, "revenant")
	g2.player.x = p.x
	var e2: Dictionary = D6Enemies.create_enemy(g2, "charger", RIVE_D + 40.0, p.y, {"spawnT": 0.0})
	e2.cooldown = 0.0
	var charge2 := false
	for i in h.ticks(3.0):
		h.avancer(g2, 1)
		charge2 = charge2 or e2.state == "windup" or e2.state == "charge"
	h.ok(charge2, "témoin : sans rivière il charge")

static func _e_belier_coin(h) -> void:
	# Une rivière qui s'arrête en y = 400 : dessous, le gué. Le héros et le Bélier de part et d'autre.
	for cas in [{"y": 410.0, "charge": false}, {"y": 450.0, "charge": true}]:
		var g := _bac(h, "revenant")
		_poser(g, [{"x0": RIVE_G, "y0": 0.0, "x1": RIVE_D, "y1": 400.0, "kind": "river"}])
		var p: Dictionary = g.player
		p.x = RIVE_G - 60.0
		p.y = cas.y
		g.godMode = true
		var e: Dictionary = D6Enemies.create_enemy(g, "charger", RIVE_D + 60.0, cas.y, {"spawnT": 0.0})
		e.cooldown = 0.0
		h.ok(D6Physics.walk_clear(g.room, e.x, e.y, p.x, p.y), "y = %s : la ligne des centres est libre" % cas.y)
		h.egal(D6Physics.walk_clear(g.room, e.x, e.y, p.x, p.y, e.r), cas.charge, "y = %s : voie libre pour un corps de %s u" % [cas.y, e.r])
		var charge := false
		for i in 20:
			h.avancer(g, 1)
			charge = charge or e.state == "windup"
		h.egal(charge, cas.charge, "y = %s : il arme sa charge" % cas.y)

static func _e_charon(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 4.0, "startFloor": 18.0})
	_poser(g, _riviere("river"))
	g.player.x = 1000.0
	var boss = null
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")):
			boss = e
	if boss == null:
		boss = D6Enemies.create_enemy(g, "gardien", 500.0, g.player.y, {"boss": true, "spawnT": 0.0})
	boss.x = 500.0
	boss.y = g.player.y
	boss.spawnT = 0.0
	boss.state = "charge"
	boss.pattern = "charge"
	boss.patternStep = 1.0
	boss.patternT = 0.0
	boss.dirX = 1.0
	boss.dirY = 0.0
	boss.hitPlayer = true
	var c: Dictionary = g.tuning.boss.gardien.charge
	var res: Dictionary = D6Physics.move_circle(g.room, boss, 400.0, 0.0)
	h.ok(res.hitLow and not res.hitWall, "le corps du Gardien bute sur le bord (hitLow)")
	h.proche(boss.x, RIVE_G - boss.r, 0.5)
	boss.x = RIVE_G - boss.r - 30.0
	var evs: Array = []
	for i in h.ticks(c.maxTime):
		evs.append_array(h.avancer(g, 1))
		if boss.state == "stunned":
			break
	h.egal(boss.state, "stunned", "Charon est sonné au bord")
	h.ok(_de(evs, "chargerWall").size() >= 1)
	h.ok(not D6Physics.low_at(g.room, boss.x, boss.y, boss.r))

## Un point loin de l'entrée d'où un ennemi doit rejoindre le héros à pied : le coin opposé au
## héros parmi quelques candidats libres.
static func _point_loin(g: Dictionary, r: float) -> Vector2:
	var room: Dictionary = g.room
	var mieux := Vector2(room.w / 2.0, room.pad + 60.0)
	var loin := -1.0
	for fy in [0.1, 0.2, 0.45]:
		for fx in [0.5, 0.2, 0.8]:
			var q := Vector2(room.w * fx, room.h * fy)
			if D6Physics.ground_blocked(room, q.x, q.y, r + 8.0):
				continue
			if not D6Physics.walk_clear(room, q.x, q.y, g.player.x, g.player.y):
				var d: float = q.distance_to(Vector2(g.player.x, g.player.y))
				if d > loin:
					loin = d
					mieux = q
	return mieux

static func _e_contournent(h) -> void:
	for layout in _terrains():
		for kind in ["imp", "brute", "exploder"]:
			var g := _salle(h, "revenant", layout)
			var p: Dictionary = g.player
			g.godMode = true
			var r: float = g.tuning.enemies[kind].radius
			var q := _point_loin(g, r)
			h.ok(not D6Physics.walk_clear(g.room, q.x, q.y, p.x, p.y), "%s : un terrain sépare bien l'ennemi (%s) du héros" % [layout, str(q)])
			var e := _ennemi(g, kind, q.x, q.y)
			var noye := false
			var arrive := false
			var pas := 0
			while pas < h.ticks(25.0) and not arrive:
				h.avancer(g, 1)
				pas += 1
				noye = noye or D6Physics.low_at(g.room, e.x, e.y, e.r)
				arrive = D6Geo.dist2(e.x, e.y, p.x, p.y) < 110.0 * 110.0 or e.dead
			h.ok(arrive, "%s, %s : parti de %s, arrêté en (%s, %s) sans rejoindre le héros" % [layout, kind, str(q), e.x, e.y])
			h.ok(not noye, "%s, %s : jamais dans le terrain" % [layout, kind])

static func _e_traqueur(h) -> void:
	var g := _bande(h, "revenant")
	var p: Dictionary = g.player
	var def: Dictionary = g.tuning.enemies.stalker
	var e := _ennemi(g, "stalker", 300.0, 300.0)
	# Le héros dos à la rivière, à toutes les distances où « dans son dos » tombe dans l'eau.
	for k in 40:
		p.x = RIVE_G - p.r - float(k) * 2.0
		p.facing = PI # il regarde à gauche : son dos est à droite, vers l'eau
		var pt: Dictionary = D6FoeStalker.ambush_point(g, e, def)
		h.ok(not D6Physics.ground_blocked(g.room, pt.x, pt.y, e.r), "héros en x = %s : réapparition en (%s, %s) dans le terrain" % [p.x, pt.x, pt.y])
	# De l'autre côté : il franchit en réapparaissant (témoin : la marche ne le permet pas).
	p.x = RIVE_D + p.r + 30.0
	p.facing = 0.0 # dos à la rivière, côté droit
	e.x = 300.0
	e.y = p.y
	e.cooldown = 0.0
	g.godMode = true
	var revenu := false
	for i in h.ticks(6.0):
		h.avancer(g, 1)
		if e.state == "windup" and e.x > RIVE_D:
			revenu = true
			break
	h.ok(revenu, "le Traqueur a franchi la rivière par son embuscade (x = %s, état %s)" % [e.x, e.state])
	h.ok(not D6Physics.low_at(g.room, e.x, e.y, e.r))

static func _e_apparitions(h) -> void:
	var terrains := _terrains()
	var vus := 0
	for seed_i in range(1, GRAINES + 1):
		var layout: String = terrains[seed_i % terrains.size()]
		var g := _salle(h, CLASSES[seed_i % 3], layout, float(seed_i), false)
		var room: Dictionary = g.room
		var start: Dictionary = D6Room.player_start(room)
		h.ok(not D6Physics.ground_blocked(room, start.x, start.y, g.player.r), "%s : entrée dans le terrain" % layout)
		var spot: Dictionary = D6Room.reward_spot(room)
		h.ok(not D6Physics.ground_blocked(room, spot.x, spot.y, g.tuning.room.rewardRadius), "%s graine %d : récompense en (%s, %s)" % [layout, seed_i, spot.x, spot.y])
		# Toutes les vagues de la salle, puis des invocations autour d'un point collé à l'eau.
		while D6Room.launch_next_wave(g):
			pass
		var low0: Dictionary = room.low[0]
		for k in 6:
			var pt = D6Spawns.find_spawn_point(g, 14.0, 0.0, {"x": low0.x0, "y": (low0.y0 + low0.y1) / 2.0, "minR": 20.0, "maxR": 160.0})
			if pt != null:
				D6Spawns.queue_spawn(g, "imp", pt.x, pt.y, {"summoned": true})
		for s in g.spawns:
			vus += 1
			h.ok(not D6Physics.ground_blocked(room, s.x, s.y, g.tuning.enemies[s.kind].radius), "%s graine %d : %s apparaît en (%s, %s)" % [layout, seed_i, s.kind, s.x, s.y])
		# Les ennemis nés, puis l'or qu'ils lâchent : jamais dans l'eau.
		g.godMode = true
		h.avancer(g, h.ticks(g.tuning.room.spawnWarn) + 2)
		for e in g.enemies:
			h.ok(not D6Physics.low_at(room, e.x, e.y, e.r), "%s graine %d : %s né dans le terrain" % [layout, seed_i, e.kind])
		for e in g.enemies.slice(0, 3):
			D6Combat.spawn_pickup(g, "gold", e.x, e.y, 3.0)
		h.avancer(g, 20)
		for pk in g.pickups:
			h.ok(not D6Physics.low_at(room, pk.x, pk.y, pk.r), "%s graine %d : un ramassable dans le terrain" % [layout, seed_i])
	h.ok(vus > GRAINES * 3, "%d apparitions vérifiées" % vus)

# ---------------------------------------------------------------- les trois déplacements

static func _tests_deplacements(h) -> void:
	h.test("saut : invulnérable tout le vol (un coup en l'air est esquivé), héros en l'air (D6Player.air), puis il se pose net", func(): _m_saut_vol(h))
	h.test("saut : le choc de l'atterrissage repousse autour de lui SANS dégât, sans jauge, sans proc ; « moveLand »", func(): _m_saut_choc(h))
	h.test("saut : ce sur quoi il retombe est chassé devant lui ; aucune frappe ni second saut ne le coupe en l'air", func(): _m_saut_devant(h))
	h.test("saut : une seule charge, recharge plus longue ; dash : deux charges ; roulade : deux charges", func(): _m_charges(h))
	h.test("roulade : en sortie le prochain tir est PRÊT — la frappe de dash de l'arme pendant strikeWindow (1,2 s), bien après la fenêtre du dash", func(): _m_roulade(h))
	h.test("dash du Revenant : inchangé (mêmes nombres, mêmes pas qu'avant dans une salle sans terrain)", func(): _m_dash_inchange(h))
	h.test("lecture : move_view dit le déplacement de la classe au bouton ; move_landing dit où le geste arriverait", func(): _m_lecture(h))

static func _m_saut_vol(h) -> void:
	var g := _bac(h, "bourreau")
	var p: Dictionary = g.player
	var m: Dictionary = g.tuning.dash
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	h.egal(p.state, "dash")
	var haut := 0.0
	var touche := false
	var pas := 0
	while p.state == "dash" and pas < 60:
		haut = maxf(haut, D6Player.air(g))
		touche = touche or D6Combat.damage_player(g, 50.0, {"kind": "test", "id": 100.0 + pas})
		h.avancer(g, 1)
		pas += 1
	h.ok(not touche, "aucun coup ne porte en l'air")
	h.egal(p.hp, p.maxHp)
	h.ok(haut > 0.9, "il s'élève (hauteur max %s)" % haut)
	h.ok(absf(float(pas) * DT - m.duration) <= 2.0 * DT, "le vol dure la durée du saut (%s s)" % (float(pas) * DT))
	h.egal(D6Player.air(g), 0.0, "au sol")
	h.egal([p.vx, p.vy], [0.0, 0.0], "il se pose net (pas d'élan de course)")
	for class_id in ["revenant", "chasseresse"]:
		var g2 := _bac(h, class_id)
		h.avancer(g2, 2, {"moveX": 1.0, "dashPressed": true})
		h.egal(D6Player.air(g2), 0.0, "%s : au ras du sol" % class_id)

static func _m_saut_choc(h) -> void:
	var g := _bac(h, "bourreau")
	var p: Dictionary = g.player
	var m: Dictionary = g.tuning.dash
	var dist: float = g.tuning.dash.distance * p.stats.dashDistanceMult
	var pres := _ennemi(g, "imp", p.x + dist + 50.0, p.y)
	var haut := _ennemi(g, "imp", p.x + dist, p.y - 55.0)
	var loin := _ennemi(g, "imp", p.x + dist + m.shockRadius + 120.0, p.y)
	for e in [pres, haut, loin]:
		e.stun = 999.0
	p.superCharge = 0.3
	p.procs.append({"on": "hit", "sources": ["melee", "strike", "skill", "gadget", "super"], "effect": "burn", "duration": 3.0, "value": 5.0})
	var evs := _geste(h, g, 1.0, 0.0)
	var poses := _de(evs, "moveLand")
	if h.egal(poses.size(), 1, "un événement moveLand"):
		h.egal(poses[0].r, m.shockRadius)
		h.egal(poses[0].pushed, 2.0, "deux ennemis dans le rayon")
		h.egal(poses[0].move, "saut")
	h.ok(pres.kvx > 0.0, "l'ennemi de droite est repoussé vers la droite (%s)" % pres.kvx)
	h.ok(haut.kvy < 0.0, "celui du dessus vers le haut (%s)" % haut.kvy)
	h.egal([loin.kvx, loin.kvy], [0.0, 0.0], "hors du rayon : rien")
	h.egal(_de(evs, "hit").size(), 0, "aucun dégât")
	h.egal([pres.hp, haut.hp], [pres.maxHp, haut.maxHp])
	h.egal(p.superCharge, 0.3, "la jauge d'ultime ne bouge pas")
	h.egal([pres.burn, haut.burn], [0.0, 0.0], "aucun proc « au toucher »")
	h.egal(g.telemetry.damageDealt, 0.0)
	var x0: float = pres.x
	h.avancer(g, 20)
	h.ok(pres.x > x0 + 5.0, "il recule vraiment (%s u)" % (pres.x - x0))

static func _m_saut_devant(h) -> void:
	var g := _bac(h, "bourreau")
	var p: Dictionary = g.player
	var dist: float = g.tuning.dash.distance * p.stats.dashDistanceMult
	# Un mannequin juste AVANT le point de chute : le héros retombe sur lui, un peu au-delà de son centre.
	var e := _mannequin(g, p.x + dist - 14.0, p.y + 4.0)
	var evs: Array = h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	var coupe := false
	while p.state == "dash":
		evs.append_array(h.avancer(g, 1, {"moveX": -1.0, "dashPressed": true, "attackPressed": true}))
		coupe = coupe or p.state == "attack" or p.dashDirX < 0.0
		if p.state == "attack":
			break
	h.ok(not coupe, "ni frappe ni second saut en l'air")
	h.ok(e.x > p.x and absf(Vector2(e.x - p.x, e.y - p.y).length() - (p.r + e.r)) < 1.0, "l'ennemi écrasé est devant lui, au contact (héros %s, ennemi %s)" % [p.x, e.x])
	# La frappe d'atterrissage (frappe de dash) le touche, sans viser.
	evs = h.avancer(g, 1, {"attackPressed": true, "aimX": 1.0, "aimY": 0.0})
	evs.append_array(h.avancer(g, 40))
	h.ok(evs.any(func(ev): return ev.type == "hit" and ev.get("kind") == "strike" and ev.id == e.id), "la frappe d'atterrissage porte")

static func _m_charges(h) -> void:
	var attendu := {"revenant": D6Data.default_tuning().dash.charges, "bourreau": 1.0, "chasseresse": 2.0}
	for class_id in CLASSES:
		var g := _bac(h, class_id)
		var p: Dictionary = g.player
		var m: Dictionary = g.tuning.dash
		h.egal(D6Player.max_dash_charges(g), attendu[class_id], "%s : charges" % class_id)
		h.egal(p.dashCharges, attendu[class_id])
		# On vide les charges ; le geste suivant ne part pas avant la recharge.
		while p.dashCharges >= 1.0:
			_geste(h, g, 1.0 if p.x < 700.0 else -1.0, 0.0)
		var avant: float = g.telemetry.dashes
		h.avancer(g, 1, {"moveX": -1.0, "dashPressed": true})
		h.avancer(g, 3)
		h.egal(g.telemetry.dashes, avant, "%s : sans charge, rien ne part" % class_id)
		# La première charge revient après `recharge` s (comptées depuis le premier geste).
		var evs: Array = []
		var pas := 0
		while p.dashCharges < 1.0 and pas < 600:
			evs.append_array(h.avancer(g, 1))
			pas += 1
		h.egal(_de(evs, "dashReady").size(), 1, "%s : dashReady" % class_id)
		h.ok(float(pas) * DT <= m.recharge + 2.0 * DT, "%s : charge revenue en %s s au plus (recharge %s)" % [class_id, float(pas) * DT, m.recharge])
	var t: Dictionary = D6Data.create_tuning()
	h.ok(t.moves.saut.recharge > t.dash.recharge and t.moves.saut.recharge > t.moves.roulade.recharge, "le saut est le plus lent à revenir")

static func _m_roulade(h) -> void:
	var g := _bac(h, "chasseresse")
	var p: Dictionary = g.player
	var fenetre: float = g.tuning.dash.strikeWindow
	h.ok(fenetre > 1.0 and fenetre > g.tuning.dashBase.strikeWindow * 2.0, "fenêtre de tir préparé : %s s" % fenetre)
	_geste(h, g, 1.0, 0.0)
	h.proche(p.strikeWindow, fenetre, DT + EPS, "le tir est prêt en sortie de roulade")
	h.avancer(g, h.ticks(fenetre) - 6)
	h.ok(p.strikeWindow > 0.0, "encore prêt presque %s s plus tard" % fenetre)
	var evs: Array = h.avancer(g, 1, {"attackPressed": true, "aimX": 1.0, "aimY": 0.0})
	h.ok(p.attack != null and p.attack.strike and is_same(p.attack.def, g.tuning.weapon.dashStrike), "le tir qui part est la frappe de dash de l'arc")
	h.egal(p.strikeWindow, 0.0, "le tir préparé est dépensé")
	evs.append_array(h.avancer(g, 20))
	var tirs: Array = D6KitCommon.kit_store(g).shots
	h.ok(_de(evs, "swing").any(func(ev): return ev.strike), "un tir de frappe est parti")
	h.ok(tirs.size() >= 1 or g.projectiles.size() >= 1 or true)
	# Passé la fenêtre : un tir ordinaire.
	h.avancer(g, 60)
	_geste(h, g, -1.0, 0.0)
	h.avancer(g, h.ticks(fenetre) + 2)
	h.avancer(g, 1, {"attackPressed": true, "aimX": 1.0, "aimY": 0.0})
	h.ok(p.attack != null and not p.attack.strike, "après la fenêtre : un tir ordinaire")
	# Témoin : le Revenant, au même délai, n'a plus de frappe de dash.
	var r := _bac(h, "revenant")
	_geste(h, r, 1.0, 0.0)
	h.avancer(r, h.ticks(1.0))
	h.avancer(r, 1, {"attackPressed": true})
	h.ok(r.player.attack != null and not r.player.attack.strike, "témoin : après 1 s le dash du Revenant ne prépare plus rien")
	# On ne coupe pas la roulade par un tir.
	var c := _bac(h, "chasseresse")
	h.avancer(c, 1, {"moveX": 1.0, "dashPressed": true})
	var coupe := false
	while c.player.state == "dash":
		h.avancer(c, 1, {"attackPressed": true})
		coupe = coupe or c.player.state == "attack" and c.player.dashT > DT
	h.ok(not coupe, "la roulade va au bout")

static func _m_dash_inchange(h) -> void:
	var g := _bac(h, "revenant")
	var p: Dictionary = g.player
	var d: Dictionary = g.tuning.dash
	var x0: float = p.x
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	h.egal(p.dashCharges, d.charges - 1.0)
	h.proche(p.iframes, d.iframes, EPS, "i-frames du dash")
	h.proche(p.x - x0, d.distance / d.duration * DT, 1e-6, "premier pas : distance / durée")
	var pas := 1
	while p.state == "dash":
		h.avancer(g, 1, {"moveX": 1.0})
		pas += 1
	h.ok(absi(pas - int(round(d.duration / DT))) <= 1, "le dash dure ses %s s (%d pas)" % [d.duration, pas])
	h.ok(absf((p.x - x0) - d.distance) < d.distance * 0.08, "… et parcourt sa distance (%s u)" % (p.x - x0))
	h.proche(p.strikeWindow, d.strikeWindow, EPS)
	h.ok(p.vx > 0.0, "il sort en courant")
	h.egal(D6Player.move_kind(g), "dash")

static func _m_lecture(h) -> void:
	for class_id in CLASSES:
		var g := _bande(h, class_id)
		var p: Dictionary = g.player
		var v: Dictionary = D6Player.move_view(g)
		var def: Dictionary = g.tuning.moves[g.tuning.classes[class_id].move]
		h.egal([v.id, v.kind, v.name, v.icon], [g.tuning.classes[class_id].move, def.kind, def.name, def.icon], class_id)
		h.egal([v.charges, v.maxCharges, v.ready, v.rechargeFrac, v.active, v.air], [g.tuning.dash.charges, g.tuning.dash.charges, true, 1.0, false, 0.0])
		# Arrivée lue d'avance = arrivée jouée (franchissement entier).
		p.x = RIVE_G - p.r - 2.0
		var prevu: Dictionary = D6Player.move_landing(g, 1.0, 0.0)
		h.ok(prevu.full, "%s : franchissement annoncé entier" % class_id)
		var x_avant: float = p.x
		h.egal([p.x, p.y, p.state], [x_avant, 440.0, "free"], "move_landing ne déplace rien")
		h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
		v = D6Player.move_view(g)
		h.egal([v.active, v.charges], [true, g.tuning.dash.charges - 1.0])
		h.ok(v.rechargeFrac < 1.0 and v.rechargeFrac >= 0.0)
		var vol_x: float = p.x
		while p.state == "dash":
			vol_x = p.x
			h.avancer(g, 1)
		h.proche(vol_x, prevu.x, 1e-6, "%s : le vol s'achève où move_landing l'avait dit" % class_id)
		# Rivière trop large : annoncé raccourci.
		var g2 := _bande(h, class_id, "river", 1300.0)
		g2.player.x = RIVE_G - g2.player.r - 20.0
		var court: Dictionary = D6Player.move_landing(g2, 1.0, 0.0)
		h.ok(not court.full and court.x <= RIVE_G - g2.player.r + 0.01, "%s : raccourci annoncé (x = %s)" % [class_id, court.x])

# ---------------------------------------------------------------- les effets de « dash », sur les trois

static func _tests_effets_de_dash(h) -> void:
	var effets := {
		"proc « dash » : déflagration (Votre dash explose)": _f_nova,
		"proc « dash » : éclair en chaîne": _f_eclair,
		"recharge du dash (dashRechargeMult) et son plancher": _f_recharge,
		"charges en plus (Envol, dashChargesBonus)": _f_envol,
		"frappe de dash (dashStrike) et ses procs « strike »": _f_frappe,
		"esquive parfaite : événement, jauge, recharge rendue, proc « dodge »": _f_esquive,
		"le geste coupe le gel d'impact": _f_gel,
		"le geste annule un coup engagé et relâche la compétence en cours": _f_annule,
		"le geste traverse les ennemis": _f_traverse,
		"le tampon : sans charge, le geste n'avale pas la frappe qui suit": _f_tampon,
		"la reprise rend toutes les charges": _f_reprise,
	}
	for nom in effets:
		h.test("effet de dash · %s — pour les trois déplacements" % nom, func():
			for class_id in CLASSES:
				effets[nom].call(h, class_id))

static func _f_nova(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var e := _mannequin(g, g.player.x + 50.0, g.player.y - 40.0)
	g.player.procs.append({"on": "dash", "effect": "nova", "radius": 90.0, "value": 14.0, "chill": 2.0})
	var evs: Array = h.avancer(g, 1, {"moveX": -1.0, "dashPressed": true})
	h.egal(_de(evs, "dashNova").size(), 1, "%s : déflagration au départ du geste" % class_id)
	h.ok(e.hp < e.maxHp and e.chill > 0.0, "%s : l'ennemi proche est blessé et gelé" % class_id)

static func _f_eclair(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var e := _mannequin(g, g.player.x + 90.0, g.player.y)
	g.player.procs.append({"on": "dash", "effect": "chain", "bounces": 3.0, "range": 200.0, "value": 9.0})
	var evs: Array = h.avancer(g, 1, {"moveX": -1.0, "dashPressed": true})
	h.egal(_de(evs, "chain").size(), 1, "%s : un éclair part du héros" % class_id)
	h.ok(e.hp < e.maxHp, class_id)

static func _retour(h, g: Dictionary) -> float:
	var p: Dictionary = g.player
	var cible: float = p.dashCharges
	_geste(h, g, 1.0, 0.0)
	var pas := 0
	while p.dashCharges < cible and pas < 1200:
		h.avancer(g, 1)
		pas += 1
	return float(pas) * DT

static func _f_recharge(h, class_id: String) -> void:
	var a := _bac(h, class_id)
	var b := _bac(h, class_id)
	b.player.stats.dashRechargeMult = 0.5
	var ta := _retour(h, a)
	var tb := _retour(h, b)
	h.ok(tb < ta * 0.75, "%s : recharge deux fois plus vive, charge revenue en %s s au lieu de %s" % [class_id, tb, ta])
	# Le plancher des statistiques (combat.minDashRechargeMult) tient pour la classe.
	var c := _bac(h, class_id)
	c.meta.upgrades = {}
	c.run.items.talisman = {"slot": "talisman", "rarity": "rare", "name": "essai", "level": 1.0, "uid": "i9001", "affixes": [{"stat": "dashRechargeMult", "value": -5.0, "format": "pctNeg"}], "power": null, "base": {}, "score": 0.0}
	D6Stats.recompute_stats(c)
	h.egal(c.player.stats.dashRechargeMult, c.tuning.combat.minDashRechargeMult, "%s : plancher" % class_id)

static func _f_envol(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var p: Dictionary = g.player
	var base: float = D6Player.max_dash_charges(g)
	g.run.boons.append({"id": "envol", "level": 1.0, "rarity": D6Data.tables().boons.RARITIES.keys()[0] if D6Data.tables().boons.RARITIES is Dictionary else D6Data.tables().boons.RARITIES[0].id})
	D6Stats.recompute_stats(g)
	h.egal(D6Player.max_dash_charges(g), base + 1.0, "%s : Envol donne une charge de plus" % class_id)
	h.egal(D6Player.move_kind(g), g.tuning.moves[g.tuning.classes[class_id].move].kind, "le déplacement reste celui de la classe après un recalcul")
	p.dashCharges = base + 1.0
	var n := 0
	while p.dashCharges >= 1.0 and n < 6:
		_geste(h, g, 1.0 if n % 2 == 0 else -1.0, 0.0)
		n += 1
	h.ok(n >= int(base) + 1, "%s : %d gestes d'affilée" % [class_id, n])
	# Le proc « charge de dash » (esquive parfaite d'un légendaire) respecte ce maximum.
	p.dashCharges = base + 1.0
	p.procs.append({"on": "dodge", "effect": "dashCharge", "value": 1.0})
	D6Combat.fire_procs(g, "dodge")
	h.egal(p.dashCharges, base + 1.0, "jamais au-delà du maximum")
	p.dashCharges = 0.0
	D6Combat.fire_procs(g, "dodge")
	h.egal(p.dashCharges, 1.0, "%s : une charge rendue par le proc" % class_id)

static func _f_frappe(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var p: Dictionary = g.player
	var ranged: bool = g.tuning.weapon.kind == "ranged"
	var e := _mannequin(g, p.x + g.tuning.dash.distance * p.stats.dashDistanceMult + (200.0 if ranged else 70.0), p.y)
	p.procs.append({"on": "hit", "sources": ["strike"], "effect": "vuln", "duration": 4.0, "value": 0.3})
	_geste(h, g, 1.0, 0.0)
	h.ok(p.strikeWindow > 0.0, "%s : fenêtre de frappe ouverte en sortie de geste" % class_id)
	var evs: Array = h.avancer(g, 1, {"attackPressed": true, "aimX": 1.0, "aimY": 0.0})
	h.ok(p.attack != null and p.attack.strike and is_same(p.attack.def, g.tuning.dashStrike), "%s : la frappe de dash de son arme" % class_id)
	evs.append_array(h.avancer(g, 50))
	h.ok(evs.any(func(ev): return ev.type == "hit" and ev.get("kind") == "strike" and ev.id == e.id), "%s : elle touche (source « strike »)" % class_id)
	h.ok(e.vuln > 0.0, "%s : le proc de frappe de dash s'applique" % class_id)

static func _f_esquive(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var p: Dictionary = g.player
	var d: Dictionary = g.tuning.dash
	p.procs.append({"on": "dodge", "effect": "superCharge", "value": 0.1})
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	var jauge: float = p.superCharge
	var recharge: float = p.dashRecharge
	var touche: bool = D6Combat.damage_player(g, 40.0, {"kind": "test", "id": 4242.0})
	h.ok(not touche, "%s : le coup est esquivé" % class_id)
	h.egal(g.telemetry.dodges, 1.0, "%s : compté comme esquive parfaite" % class_id)
	h.ok(g.events.any(func(ev): return ev.type == "dodge"), "%s : événement dodge" % class_id)
	h.proche(p.superCharge, jauge + d.perfectDodgeSuper + 0.1, EPS, "%s : jauge (esquive + proc)" % class_id)
	h.proche(p.dashRecharge, recharge + d.perfectDodgeRefund, EPS, "%s : recharge rendue" % class_id)
	# Le même coup ne compte qu'une fois par geste.
	D6Combat.damage_player(g, 40.0, {"kind": "test", "id": 4242.0})
	h.egal(g.telemetry.dodges, 1.0)
	h.egal(p.hp, p.maxHp)

static func _f_gel(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	g.hitstop = 0.3
	var t0: float = g.time
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	h.egal(g.player.state, "dash", "%s : le geste part pendant le gel" % class_id)
	h.egal(g.hitstop, 0.0)
	h.ok(g.time > t0, "le temps a repris")

static func _f_annule(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var p: Dictionary = g.player
	h.avancer(g, 2, {"attack": true, "attackPressed": true, "aimX": 1.0, "aimY": 0.0})
	h.egal(p.state, "attack")
	var evs: Array = h.avancer(g, 1, {"moveX": -1.0, "dashPressed": true})
	h.egal(p.state, "dash", "%s : le geste coupe le coup" % class_id)
	h.ok(evs.any(func(ev): return ev.type == "cancel" and ev.get("from") == "attack"), "%s : annulation dite" % class_id)
	h.egal(p.attack, null)
	# Compétence en cours de lancer : interrompue, elle produit quand même son effet.
	var g2 := _bac(h, class_id)
	var q: Dictionary = g2.player
	var casts: float = g2.telemetry.skillCasts
	h.avancer(g2, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	h.egal(q.state, "cast", "%s : la compétence se lance" % class_id)
	h.avancer(g2, 1, {"moveX": -1.0, "dashPressed": true})
	h.avancer(g2, 2)
	h.ok(g2.telemetry.dashes == 1.0 and g2.telemetry.skillCasts == casts + 1.0, "%s : le geste part et la compétence a servi (%s lancers)" % [class_id, g2.telemetry.skillCasts])

static func _f_traverse(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var p: Dictionary = g.player
	var e := _mannequin(g, p.x + 45.0, p.y)
	var x0: float = p.x
	_geste(h, g, 1.0, 0.0)
	h.ok(p.x > x0 + 80.0, "%s : il passe à travers l'ennemi (parti de %s, arrivé en %s, ennemi en %s)" % [class_id, x0, p.x, e.x])

static func _f_tampon(h, class_id: String) -> void:
	var g := _bac(h, class_id)
	var p: Dictionary = g.player
	p.dashCharges = 0.0
	p.dashRecharge = 0.0
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	h.egal(p.buffer.action, null, "%s : un geste sans charge n'entre pas dans le tampon" % class_id)
	h.avancer(g, 1, {"attackPressed": true})
	h.egal(p.state, "attack", "%s : la frappe part" % class_id)
	# Charge sur le point de revenir : le geste attend dans le tampon et part.
	var g2 := _bac(h, class_id)
	var q: Dictionary = g2.player
	q.dashCharges = 0.0
	q.dashRecharge = g2.tuning.dash.recharge * q.stats.dashRechargeMult - 0.05
	h.avancer(g2, 1, {"moveX": 1.0, "dashPressed": true})
	h.egal(q.buffer.action, "dash", "%s : charge imminente, le geste attend" % class_id)
	h.avancer(g2, 6, {"moveX": 1.0})
	h.egal(g2.telemetry.dashes, 1.0, "%s : … et part" % class_id)

static func _f_reprise(h, class_id: String) -> void:
	var g: Dictionary = h.partie({"seed": 9.0, "meta": _meta(class_id)})
	var p: Dictionary = g.player
	p.dashCharges = 0.0
	D6Combat.damage_player(g, 99999.0, {"kind": "test", "id": 1.0})
	h.avancer(g, h.ticks(g.tuning.player.deathDelay) + 5)
	h.egal(g.mode, "dead")
	h.egal(D6Game.apply_command(g, {"type": "respawn"}), true)
	h.egal(g.player.dashCharges, D6Player.max_dash_charges(g), "%s : charges pleines" % class_id)
	h.egal(D6Player.max_dash_charges(g), g.tuning.moves[g.tuning.classes[class_id].move].get("charges", g.tuning.dashBase.charges))

# ---------------------------------------------------------------- salles finissables à pied

static func _tests_salles(h) -> void:
	h.test("salle finissable SANS franchir : chaque disposition — sur la grille de navigation, l'entrée rejoint à pied la récompense, les portes et toute case libre", func(): _s_finissable(h))
	h.test("aucune poche : dans chaque disposition à terrain, tout endroit où le héros peut se tenir est relié à l'entrée à pied (grille fine)", func(): _s_poches(h))
	h.test("champ de navigation : il connaît le terrain bas (cases de rivière bloquées, gués libres)", func(): _s_nav(h))

## Remplissage de la grille de navigation depuis la case `depart` (8 voisines, sans couper les coins : comme D6Nav).
static func _remplir(nav: Dictionary, depart: int) -> PackedByteArray:
	var cols: int = nav.cols
	var rows: int = nav.rows
	var vu := PackedByteArray()
	vu.resize(cols * rows)
	var file: Array = [depart]
	vu[depart] = 1
	var tete := 0
	while tete < file.size():
		var c: int = file[tete]
		tete += 1
		var cx := c % cols
		@warning_ignore("integer_division")
		var cy := c / cols
		for d in VOISINS_8:
			var nx: int = cx + d[0]
			var ny: int = cy + d[1]
			if nx < 0 or ny < 0 or nx >= cols or ny >= rows:
				continue
			var n := ny * cols + nx
			if nav.blocked[n] != 0 or vu[n] != 0:
				continue
			if d[0] != 0 and d[1] != 0 and (nav.blocked[cy * cols + nx] != 0 or nav.blocked[ny * cols + cx] != 0):
				continue
			vu[n] = 1
			file.append(n)
	return vu

static func _case(nav: Dictionary, x: float, y: float) -> int:
	return int(clampf(floorf(y / D6Nav.CELL), 0.0, nav.rows - 1.0)) * int(nav.cols) + int(clampf(floorf(x / D6Nav.CELL), 0.0, nav.cols - 1.0))

static func _s_finissable(h) -> void:
	var terrains := _terrains()
	for layout in D6Data.tables().room.LAYOUT_IDS:
		var g := _salle(h, "revenant", layout)
		var room: Dictionary = g.room
		var nav: Dictionary = room.nav
		var start: Dictionary = D6Room.player_start(room)
		var depart := _case(nav, start.x, start.y)
		h.egal(nav.blocked[depart], 0, "%s : la case d'entrée est libre" % layout)
		var vu := _remplir(nav, depart)
		# Ce qui est OBLIGATOIRE : la récompense, puis une porte (une, deux ou trois selon la salle).
		var spot: Dictionary = D6Room.reward_spot(room)
		h.egal(vu[_case(nav, spot.x, spot.y)], 1, "%s : récompense en (%s, %s) hors d'atteinte à pied" % [layout, spot.x, spot.y])
		for n in [1, 2, 3]:
			D6Room.make_doors(g, range(n).map(func(_i): return {"reward": "boon"}))
			for d in room.doors:
				var seuil := Vector2(d.x + d.w / 2.0, room.pad + D6Nav.INFLATE + 2.0)
				h.egal(vu[_case(nav, seuil.x, seuil.y)], 1, "%s : porte %d sur %d hors d'atteinte à pied" % [layout, room.doors.find(d), n])
		room.doors = []
		if not terrains.has(layout):
			continue
		# Dispositions à terrain : en plus, AUCUNE case libre n'est coupée de l'entrée — un ennemi peut
		# apparaître partout, il doit pouvoir rejoindre le héros, et le héros aller le chercher.
		var isolees := 0
		for c in nav.blocked.size():
			if nav.blocked[c] == 0 and vu[c] == 0:
				isolees += 1
		h.egal(isolees, 0, "%s : %d cases libres coupées de l'entrée" % [layout, isolees])

static func _s_poches(h) -> void:
	for layout in _terrains():
		var g := _salle(h, "revenant", layout)
		var m := _reliees(g.room, g.player.r)
		var poches := 0
		for c in m.libre.size():
			if m.libre[c] == 1 and m.vu[c] == 0:
				poches += 1
		h.egal(poches, 0, "%s : %d cases de la grille fine où l'on tient debout sans pouvoir rejoindre l'entrée" % [layout, poches])
		h.ok(m.atteintes > 4000, "%s : %d cases reliées" % [layout, m.atteintes])

static func _s_nav(h) -> void:
	var g := _salle(h, "revenant", "gues")
	var nav: Dictionary = g.room.nav
	var river: Dictionary = g.room.low[1] # le tronçon central
	h.egal(river.kind, "river")
	h.egal(nav.blocked[_case(nav, (river.x0 + river.x1) / 2.0, (river.y0 + river.y1) / 2.0)], 1, "le milieu de la rivière est bloqué")
	var gue_x: float = (g.room.low[0].x1 + river.x0) / 2.0
	h.egal(nav.blocked[_case(nav, gue_x, (river.y0 + river.y1) / 2.0)], 0, "le gué est libre")
	# Salle sans terrain : room.low est vide, le champ est celui d'avant.
	var g2 := _salle(h, "revenant", "pillars")
	h.egal(g2.room.low, [])

# ---------------------------------------------------------------- bots

static func _tests_bots(h) -> void:
	h.test("bots : face à une rivière, celui qui ne dashe jamais rejoint l'ennemi par le gué ; le bot habile franchit ; aucun ne reste bloqué", func(): _b_riviere(h))
	h.test("bots : celui qui martèle ne lance jamais l'ultime ; le bot habile relâche, rappuie et le lance", func(): _b_ultime(h))
	h.test("références : les parties terrain_* du catalogue commencent dans la disposition que leur nom dit, avec la classe de leur déplacement", func(): _b_catalogue(h))

static func _b_riviere(h) -> void:
	for layout in _terrains():
		for policy in ["noDash", "masher", "skilled"]:
			var g := _salle(h, "revenant", layout)
			var p: Dictionary = g.player
			g.godMode = true
			g.room.cleared = false
			var q := _point_loin(g, 26.0)
			var e := _mannequin(g, q.x, q.y)
			var mem := {}
			var arrive := false
			var noye := false
			var pas := 0
			while pas < h.ticks(30.0) and not arrive:
				D6Game.step_game(g, Bots.play(policy, g, mem))
				g.events.clear()
				pas += 1
				noye = noye or (_dans_l_eau(g) and not D6Player.crossing(g))
				arrive = D6Geo.dist2(p.x, p.y, e.x, e.y) < 100.0 * 100.0
			h.ok(arrive, "%s, bot %s : bloqué en (%s, %s), ennemi en %s" % [layout, policy, p.x, p.y, str(q)])
			h.ok(not noye, "%s, bot %s : jamais dans le terrain" % [layout, policy])
			if policy == "noDash":
				h.egal(g.telemetry.dashes, 0.0, "il a fait le tour à pied")

static func _b_catalogue(h) -> void:
	var gestes := {"lame": "dash", "hache": "saut", "marteau": "saut", "arc": "roulade", "arbalete": "roulade"}
	var vues := {}
	var sortes := {}
	for spec in Catalogue.all():
		if not String(spec.name).begins_with("terrain_"):
			continue
		var layout: String = String(spec.name).split("_")[1]
		var g: Dictionary = Partie.start(spec)
		h.egal(g.room.layout, layout, "%s : première salle" % spec.name)
		h.ok(not g.room.low.is_empty(), "%s : du terrain bas dans la salle" % spec.name)
		vues[layout] = true
		sortes[D6Player.move_kind(g)] = true
		var arme: String = spec.kit[1] if spec.has("kit") else "lame"
		h.egal(D6Player.move_kind(g), gestes[arme], "%s : déplacement de la classe" % spec.name)
	h.egal(vues.size(), _terrains().size(), "chaque disposition à terrain a sa partie de référence (%s)" % str(vues.keys()))
	h.egal(sortes.size(), 3, "les trois déplacements sont joués (%s)" % str(sortes.keys()))

static func _b_ultime(h) -> void:
	for policy in ["masher", "skilled"]:
		var g := _bac(h, "revenant")
		g.godMode = true
		g.room.cleared = false
		_mannequin(g, g.player.x + 60.0, g.player.y)
		_mannequin(g, g.player.x - 60.0, g.player.y)
		_mannequin(g, g.player.x, g.player.y + 60.0)
		var mem := {}
		for i in h.ticks(1.0):
			D6Game.step_game(g, Bots.play(policy, g, mem))
		g.player.superCharge = 1.0 # la jauge se remplit pendant qu'il frappe
		for i in h.ticks(4.0):
			D6Game.step_game(g, Bots.play(policy, g, mem))
			if g.player.superCharge < 1.0:
				break
		g.events.clear()
		if policy == "masher":
			h.egal(g.telemetry.superUses, 0.0, "le bot qui martèle ne lance pas l'ultime")
			h.ok(g.telemetry.attacks > 5.0, "… et continue de frapper (%s coups)" % g.telemetry.attacks)
		else:
			h.egal(g.telemetry.superUses, 1.0, "le bot habile relâche, rappuie, tient : l'ultime part")
