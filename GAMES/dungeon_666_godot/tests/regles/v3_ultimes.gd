extends RefCounted
## COMBAT V3, étape 2 « Ultimes » (design/COMBAT_V3.md) — un TYPE d'ultime par classe :
##   Bourreau    — GROSSE MAGIE    « Sentence capitale » (sim/ult_magie.gd)
##   Chasseresse — INVOCATION      « Meute des Limbes »  (sim/ult_meute.gd)
##   Revenant    — TRANSFORMATION  « Forme du Damné »    (sim/ult_forme.gd)
## Les trois se lancent comme avant (jauge pleine, appui commencé jauge pleine, maintien holdTime).
## Règles communes : un ultime ne se relance pas pendant qu'il agit, la jauge ne se remplit pas
## pendant ce temps ; mort, changement de salle et reprise remettent tout en ordre ; les effets qui
## parlent du « Super » (bénédictions, objets, autels, repos) valent pour les trois.
## Les nombres attendus sont lus dans les données (data/classes.json), jamais recopiés.

const DT := 1.0 / 60.0
const EPS := 1e-6
const TOUTES := ["classes", "weapons", "skills", "gadgets"]
const PORTE := {"reward": "boon", "family": "colere"}
const KITS := {
	"revenant": ["lance", "nova", "chaine"], "bourreau": ["bond", "cri", "chaine"], "chasseresse": ["volee", "piege", "brasier"],
}
const ULTIMES := {"revenant": "forme_damne", "bourreau": "sentence_capitale", "chasseresse": "meute_limbes"}
const SORTES := {"revenant": "forme", "bourreau": "magie", "chasseresse": "meute"}
const VUES := {"revenant": "forme", "bourreau": "magie", "chasseresse": "invocation"}
const GRAINES_EAU := 300

static func tests(h) -> void:
	_tests_communs(h)
	_tests_magie(h)
	_tests_meute(h)
	_tests_forme(h)
	_tests_effets(h)

# ---------------------------------------------------------------- outillage

## Profil permanent : tout débloqué, la classe, ses trois emplacements, l'arme demandée.
static func _meta(class_id: String, arme = null) -> Dictionary:
	var t: Dictionary = D6Data.create_tuning()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in TOUTES:
		m.unlocked[k] = t[k].keys()
	m.loadout = {"classId": class_id, "slots": KITS[class_id]}
	m.equipment.arme = D6Profile.starter_weapon(t, arme if arme != null else t.classes[class_id].weapons[0])
	return m

## Salle vidée, héros au centre, jamais de critique (les montants attendus sont exacts).
static func _bac(h, class_id: String, opts: Dictionary = {}, arme = null) -> Dictionary:
	var o := {"seed": 7.0, "meta": _meta(class_id, arme)}
	o.merge(opts, true)
	var g: Dictionary = h.bac_a_sable(o)
	g.tuning.combat.critChance = 0.0
	return g

## Ennemi d'essai apparu : ne riposte pas, ne bouge pas (sonné), increvable par défaut.
static func _cible(g: Dictionary, dx: float, dy: float, kind: String = "brute", hp: float = 50000.0, opts: Dictionary = {}) -> Dictionary:
	var o := {"spawnT": 0.0}
	o.merge(opts, true)
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, o)
	e.cooldown = 999.0
	e.maxHp = hp
	e.hp = hp
	e.mass = 1000.0
	e.stun = 999.0
	return e

## Ennemi d'essai ÉVEILLÉ (il joue son IA), apparu, à sa vie d'origine sauf demande.
static func _vif(g: Dictionary, dx: float, dy: float, kind: String, hp = null) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	if hp != null:
		e.maxHp = hp
		e.hp = hp
	return e

static func _de(evs: Array, type: String) -> Array:
	return evs.filter(func(ev): return ev.type == type)

static func _coups(evs: Array, kind: String) -> Array:
	return evs.filter(func(ev): return ev.type == "hit" and ev.get("kind") == kind)

## Jauge pleine puis lancement par maintien : rend les événements (arrêt au pas d'entrée en 'super').
## L'attaque est d'abord relâchée un pas : seul un appui COMMENCÉ jauge pleine arme l'ultime.
static func _lancer(h, g: Dictionary, sur: Dictionary = {}) -> Array:
	h.avancer(g, 1)
	g.player.superCharge = 1.0
	return h.ultime(g, sur)

## Dégâts attendus d'un coup du héros de montant de base `base`, sur un ennemi sans état : arme et
## build, plus le bonus du Super pour les sources 'super' et 'ally'.
## `sonne` : la cible est étourdie (les cibles de _cible le sont) : dégâts × stunDamageTakenMult.
static func _attendu(g: Dictionary, base: float, du_super: bool = true, sonne: bool = true) -> float:
	var st: Dictionary = g.player.stats
	var v: float = base * st.damageMult * (st.weaponDamage / g.tuning.weaponBase)
	if du_super:
		v *= st.superDamageMult
	if sonne:
		v *= g.tuning.combat.stunDamageTakenMult
	return maxf(1.0, D6Js.jround(v))

static func _benir(g: Dictionary, id: String) -> void:
	D6Boons.add_boon(g.run, {"id": id, "rarity": "commun"})
	D6Stats.recompute_stats(g)

static func _valeur(id: String) -> float:
	return D6Boons.boon_value(D6Boons.boon_def(id), "commun")

static func _talisman(g: Dictionary, stat: String, value: float) -> void:
	g.run.items.talisman = {"id": 9001.0, "slot": "talisman", "rarity": "rare", "name": "Relique d'essai", "level": 1.0, "affixes": [{"stat": stat, "value": value}], "power": null, "base": {}, "score": 0.0}
	D6Stats.recompute_stats(g)

## Empreinte large de la partie pour le déterminisme : l'empreinte d'état, plus les limiers et la forme.
static func _empreinte(g: Dictionary) -> Array:
	var p: Dictionary = g.player
	var u = p.get("ult")
	var out: Array = [D6Game.state_hash(g), p.superCharge, p.state, u.t if u != null else -1.0, g.kit.slots.duplicate()]
	for a in g.allies:
		out.append([a.id, a.x, a.y, a.hp, a.life, a.state, a.targetId])
	return out

# ---------------------------------------------------------------- règles communes

static func _tests_communs(h) -> void:
	h.test("ultimes : un type par classe — forme (Revenant), magie (Bourreau), invocation (Chasseresse)", func(): _c_types(h))
	h.test("ultimes : chaque classe lance le SIEN par le maintien, jauge vidée, compté une fois", func(): _c_lancement(h))
	h.test("ultimes : les anciens Supers (Colère, Sentence, Nuée) restent jouables, hors de toute classe", func(): _c_reserve(h))
	h.test("ultimes : ultimate_view dit la sorte, la jauge, le maintien, la durée restante", func(): _c_vue(h))
	h.test("ultimes : arène d'essai et entraînement contre un Gardien — les trois partent et finissent", func(): _c_modes(h))
	h.test("ultimes : au-dessus d'une rivière (déplacement en cours), aucun ne part ; il part sur la terre ferme", func(): _c_terrain(h))
	h.test("ultimes : déterminisme — deux parties identiques jouant chaque ultime, même empreinte à chaque pas", func(): _c_determinisme(h))
	h.test("références : les parties ultime_* du catalogue jouent vraiment l'ultime que leur nom dit", func(): _c_catalogue(h))

static func _c_types(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	for class_id in ULTIMES:
		h.egal(t.classes[class_id]["super"], ULTIMES[class_id], "l'ultime de %s" % class_id)
		h.egal(t.supers[ULTIMES[class_id]].kind, SORTES[class_id], "sa sorte")
		var g := _bac(h, class_id)
		h.ok(is_same(g.tuning["super"], g.tuning.supers[ULTIMES[class_id]]), "%s : le bloc actif EST l'entrée du registre" % class_id)
		h.egal(g.kit.superId, ULTIMES[class_id])

static func _c_lancement(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		var s: Dictionary = g.tuning["super"]
		g.player.superCharge = 1.0
		# Avant holdTime : rien n'est parti.
		var evs: Array = h.avancer(g, h.ticks(s.holdTime) - 2, {"attack": true})
		h.egal(_de(evs, "super").size(), 0, "%s : pas avant holdTime" % class_id)
		evs = h.ultime(g)
		var lances := _de(evs, "super")
		h.egal(lances.size(), 1, "%s : un événement « super »" % class_id)
		h.egal(lances[0].get("super"), SORTES[class_id], "%s : il dit sa sorte" % class_id)
		h.egal(g.player.state, "super", "%s : le geste de lancement (invulnérable)" % class_id)
		h.ok(g.player.superCharge < 1.0, "%s : la jauge n'est plus pleine" % class_id)
		h.egal(g.telemetry.superUses, 1.0)
		h.egal(D6Combat.damage_player(g, 50.0, {"kind": "imp", "id": 1.0}), false, "%s : invulnérable pendant le geste" % class_id)
		h.proche(g.player.superT, s.duration, 2.0 * DT, "%s : le geste dure `duration`" % class_id)

static func _c_reserve(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	for id in ["colere", "sentence", "nuee"]:
		h.egal(t.supers[id].get("reserve"), true, "%s : marqué « reserve »" % id)
		for class_id in t.classes:
			h.different(t.classes[class_id]["super"], id, "%s n'est l'ultime d'aucune classe" % id)
		# Lancé directement (réglage d'essai : la classe le nomme), son code joue toujours.
		var g := _bac(h, "revenant", {"tuning": {"classes": {"revenant": {"super": id}}}})
		_cible(g, 90.0, 0.0)
		var evs: Array = _lancer(h, g)
		evs.append_array(h.avancer(g, h.ticks(t.supers[id].duration + 0.6)))
		h.egal(_de(evs, "super")[0].get("super"), t.supers[id].kind, "%s : lancé" % id)
		h.ok(_coups(evs, "super").size() + _coups(evs, "melee").size() > 0, "%s : il frappe" % id)
		h.egal(g.player.state, "free", "%s : il finit" % id)
		h.egal(D6KitSupers.acting(g), false)

static func _c_vue(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		var s: Dictionary = g.tuning["super"]
		var v: Dictionary = D6Player.ultimate_view(g)
		h.egal([v.id, v.kind, v.name, v.icon, v.text], [ULTIMES[class_id], VUES[class_id], s.name, s.icon, s.text], "%s : identité" % class_id)
		h.egal([v.active, v.ready, v.timeFrac, v.allies], [false, false, 0.0, 0.0], "%s : au repos" % class_id)
		h.proche(v.charge, s.startCharge, EPS, "jauge de départ")
		g.player.superCharge = 1.0
		h.egal(D6Player.ultimate_view(g).ready, true, "jauge pleine : prêt")
		h.avancer(g, h.ticks(s.holdTime / 2.0), {"attack": true})
		h.proche(D6Player.ultimate_view(g).holdFrac, 0.5, 0.1, "%s : le maintien se lit" % class_id)
		h.ultime(g)
		v = D6Player.ultimate_view(g)
		h.egal([v.active, v.ready], [true, false], "%s : il agit, il n'est plus « prêt »" % class_id)
		h.ok(v.timeFrac > 0.9 and v.timeFrac <= 1.0 and v.timeLeft > 0.0, "%s : la durée restante part de 1 (%s)" % [class_id, str(v.timeFrac)])
	var g2 := _bac(h, "chasseresse")
	_lancer(h, g2)
	h.egal(D6Player.ultimate_view(g2).allies, g2.tuning["super"].count, "invocation : le nombre de limiers")

## Joue la partie `secondes` en tenant l'attaque, jauge forcée pleine au début ; rend les événements.
static func _jouer_ultime(h, g: Dictionary, secondes: float) -> Array:
	var evs: Array = _lancer(h, g)
	evs.append_array(h.avancer(g, h.ticks(secondes)))
	return evs

static func _c_modes(h) -> void:
	for class_id in ULTIMES:
		for mode in [{"sandbox": true}, {"practice": true, "startFloor": 18.0}]:
			var o := {"seed": 11.0, "meta": _meta(class_id), "godMode": true}
			o.merge(mode, true)
			var g: Dictionary = h.partie(o)
			h.avancer(g, h.ticks(2.0))
			var s: Dictionary = g.tuning["super"]
			var evs := _jouer_ultime(h, g, D6Js.nz(s.get("formTime"), D6Js.nz(s.get("life"), 0.0)) + s.duration + 1.5)
			h.egal(_de(evs, "super").size(), 1, "%s %s : lancé" % [class_id, str(mode)])
			h.egal(D6KitSupers.acting(g), false, "%s %s : fini" % [class_id, str(mode)])
			h.egal(g.allies.size(), 0)
			h.egal(g.player.get("ult"), null)
			h.egal(g.kit.slots, KITS[class_id], "le kit d'origine")
			h.ok(g.mode == "play" or g.mode == "choice", "la partie continue (%s)" % g.mode)

static func _c_terrain(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		var p: Dictionary = g.player
		# Une rivière large juste à droite : le déplacement de classe la survole.
		g.room.low = [{"x0": p.x + 30.0, "y0": 0.0, "x1": p.x + 30.0 + 64.0, "y1": g.room.h, "kind": "river"}]
		g.room.nav = D6Nav.build_nav(g.room)
		p.superCharge = 1.0
		var evs: Array = h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
		var vus_au_dessus := 0
		for i in h.ticks(g.tuning.dash.duration + 0.6):
			if D6Physics.low_at(g.room, p.x, p.y, p.r):
				vus_au_dessus += 1
				h.different(p.state, "super", "%s : jamais d'ultime au-dessus de l'eau" % class_id)
			evs.append_array(h.avancer(g, 1, {"attack": true, "moveX": 1.0}))
		h.ok(vus_au_dessus > 0, "%s : le déplacement a bien survolé la rivière" % class_id)
		evs.append_array(h.ultime(g))
		h.egal(_de(evs, "super").size(), 1, "%s : il part une fois sur la terre ferme" % class_id)
		h.egal(D6Physics.low_at(g.room, p.x, p.y, p.r), false)
		for a in g.allies:
			h.egal(D6Physics.ground_blocked(g.room, a.x, a.y, a.r), false, "limier sur la terre ferme")

static func _c_determinisme(h) -> void:
	var Bots = load("res://outils/bots/bots.gd")
	for class_id in ULTIMES:
		var parties: Array = []
		var mems: Array = [{}, {}]
		for k in 2:
			parties.append(h.partie({"seed": 4242.0, "startFloor": 6.0, "meta": _meta(class_id), "godMode": true}))
		var lances := 0.0
		for i in h.ticks(40.0):
			for k in 2:
				var g: Dictionary = parties[k]
				if g.mode == "choice":
					Bots.resolve_choice(g, "skilled")
				if g.mode != "play":
					continue
				if i % 600 == 0:
					g.player.superCharge = 1.0 # la jauge est offerte toutes les 10 s : l'ultime est joué
				D6Game.step_game(g, Bots.play("skilled", g, mems[k]))
				g.events.clear()
			if _empreinte(parties[0]) != _empreinte(parties[1]):
				h.ok(false, "%s : écart au pas %d" % [class_id, i])
				return
			lances = parties[0].telemetry.superUses
		h.ok(lances >= 2.0, "%s : l'ultime a été joué (%s fois)" % [class_id, str(lances)])
		h.egal(_empreinte(parties[0]), _empreinte(parties[1]), "%s : même empreinte" % class_id)

## Chaque partie ultime_<sorte>_… du catalogue des références est rejouée par sa politique : les
## événements de SON ultime doivent s'y produire (sinon la partie ne garde rien de l'ultime).
static func _c_catalogue(h) -> void:
	var Partie = load("res://references/partie.gd")
	var Catalogue = load("res://references/catalogue.gd")
	var attendus := {
		"forme": ["formStart", "formEnd", "formRush"], "sentence": ["ultFreeze", "ultStrike", "ultBolt"],
		"meute": ["allySpawn", "allyBite", "allyHurt"],
	}
	var parties := {}
	var actions := {}
	for spec in Catalogue.all():
		var nom := String(spec.name)
		if not nom.begins_with("ultime_"):
			continue
		var sorte: String = nom.split("_")[1]
		parties[sorte] = parties.get(sorte, 0) + 1
		var vus := {}
		for pas in Partie.record(spec).steps:
			if int(pas[0]) == 2:
				for type in pas[1].ev:
					vus[type] = true
		h.ok(attendus.has(sorte), "%s : sorte d'ultime connue" % nom)
		for type in attendus.get(sorte, []):
			h.ok(vus.has(type), "%s : « %s » se produit" % [nom, type])
		for type in ["formRush", "formHowl", "formBurst"]:
			if vus.has(type):
				actions[type] = true
	for sorte in attendus:
		h.ok(parties.get(sorte, 0) >= 2, "au moins deux parties de référence pour l'ultime « %s »" % sorte)
	h.egal(actions.size(), 3, "les trois actions de forme sont jouées par les parties de référence (%s)" % str(actions.keys()))

# ---------------------------------------------------------------- Sentence capitale (Bourreau)

static func _tests_magie(h) -> void:
	h.test("Sentence capitale : lame levée (rien ne porte), le temps se fige, puis UN fracas", func(): _m_deroule(h))
	h.test("Sentence capitale : frappe TOUS les ennemis présents — loin, derrière un pilier, par-dessus une rivière", func(): _m_toute_la_salle(h))
	h.test("Sentence capitale : dégâts et étourdissement lus dans les données ; un pavois de face ne l'arrête pas", func(): _m_nombres(h))
	h.test("Sentence capitale : exécute au seuil et dessous (champion compris), jamais au-dessus, jamais sous une bulle", func(): _m_execution(h))
	h.test("Sentence capitale : un ennemi exécuté compte — tué, butin, Âmes, récompense d'élite", func(): _m_execution_compte(h))
	h.test("Sentence capitale : un Gardien n'est JAMAIS exécuté, ni étourdi, et ne perd pas plus de bossCap de sa vie", func(): _m_gardien(h))
	h.test("Sentence capitale : efface les projectiles ennemis en vol", func(): _m_projectiles(h))
	h.test("Sentence capitale : invulnérable pendant tout le geste ; à la fin, libre, jauge vide, relançable", func(): _m_fin(h))
	h.test("Sentence capitale : salle vide — elle part, frappe dans le vide, finit", func(): _m_vide(h))
	h.test("Sentence capitale : changer de salle pendant le geste — pas de fracas dans la salle suivante", func(): _m_salle(h))
	h.test("Sentence capitale : ses coups ne remplissent pas la jauge ; les coups d'arme suivants, si", func(): _m_jauge(h))

## Lance la Sentence et la joue jusqu'au bout ; rend les événements.
static func _sentence(h, g: Dictionary) -> Array:
	var s: Dictionary = g.tuning["super"]
	var evs: Array = _lancer(h, g)
	evs.append_array(h.avancer(g, h.ticks(s.duration + s.freeze + 0.3)))
	return evs

static func _m_deroule(h) -> void:
	var g := _bac(h, "bourreau")
	var s: Dictionary = g.tuning["super"]
	var e := _cible(g, 400.0, 0.0)
	_lancer(h, g)
	# Télégraphe : jusqu'à strikeAt, rien ne porte et le héros ne bouge pas.
	var x0: float = g.player.x
	var evs: Array = h.avancer(g, h.ticks(s.strikeAt) - 2, {"moveX": 1.0})
	h.egal(e.hp, e.maxHp, "lame levée : aucun dégât")
	h.egal(_de(evs, "ultFreeze").size() + _de(evs, "ultStrike").size(), 0)
	h.proche(g.player.x, x0, EPS, "il ne marche pas pendant le geste")
	h.ok(s.strikeAt >= 0.4, "le télégraphe dure au moins 0,4 s")
	# Le temps se fige : le gel imposé de la sim, de `freeze` s, pendant lequel le temps n'avance pas.
	evs = h.avancer(g, 3)
	h.egal(_de(evs, "ultFreeze").size(), 1, "le temps se fige")
	h.ok(g.hitstop > 0.0 and g.hitstop <= s.freeze, "gel d'impact imposé (%s)" % str(g.hitstop))
	var temps: float = g.time
	evs = h.avancer(g, h.ticks(s.freeze) - 4)
	h.egal(g.time, temps, "pendant le gel, le temps de la partie n'avance pas")
	h.egal(e.hp, e.maxHp, "pendant le gel : pas encore de dégât")
	# Puis le fracas, une seule fois.
	evs = h.avancer(g, h.ticks(s.duration))
	h.egal(_de(evs, "ultStrike").size(), 1, "un seul fracas")
	h.egal(_de(evs, "ultBolt").size(), 1, "un éclair par ennemi touché")
	h.egal(e.maxHp - e.hp, _attendu(g, s.damage), "dégâts du fracas")
	h.egal(_de(evs, "superEnd").size(), 1)

static func _m_toute_la_salle(h) -> void:
	var g := _bac(h, "bourreau")
	var p: Dictionary = g.player
	g.room.obstacles = [{"x0": p.x + 100.0, "y0": p.y - 80.0, "x1": p.x + 160.0, "y1": p.y + 80.0}]
	g.room.low = [{"x0": 0.0, "y0": p.y + 100.0, "x1": g.room.w, "y1": p.y + 164.0, "kind": "river"}]
	var derriere := _cible(g, 300.0, 0.0)
	var outre_eau := _cible(g, 0.0, 300.0)
	var loin := _cible(g, -640.0, -380.0)
	var a_naitre: Dictionary = D6Enemies.create_enemy(g, "imp", p.x - 200.0, p.y, {"spawnT": 5.0})
	h.egal(D6Physics.line_of_sight(g.room, p.x, p.y, derriere.x, derriere.y), false, "le pilier cache bien la cible")
	var evs := _sentence(h, g)
	for e in [derriere, outre_eau, loin]:
		h.ok(e.hp < e.maxHp, "touché à (%d, %d)" % [int(e.x), int(e.y)])
	h.egal(a_naitre.hp, a_naitre.maxHp, "un ennemi pas encore apparu n'est pas touché")
	h.egal(_de(evs, "ultStrike")[0].hits, 3.0, "le fracas dit combien il a touché")
	h.ok(g.tuning["super"].radius >= sqrt(g.room.w * g.room.w + g.room.h * g.room.h), "la portée couvre la diagonale de la salle")

static func _m_nombres(h) -> void:
	var g := _bac(h, "bourreau")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	var e: Dictionary = _vif(g, 300.0, 0.0, "brute", 5000.0)
	e.cooldown = 999.0
	var pavois: Dictionary = _vif(g, -200.0, 0.0, "pavois", 5000.0)
	pavois.cooldown = 999.0
	pavois.face = 0.0 # le pavois regarde le héros, qui est à sa droite
	var evs := _sentence(h, g)
	var coups := _coups(evs, "super")
	h.egal(coups.size(), 2, "deux coups de sorte « super »")
	h.egal(coups[0].amount, _attendu(g, s.damage, true, false), "montant")
	h.egal(coups[0].crit, false, "jamais de critique : le nombre est le nombre")
	h.egal(e.maxHp - e.hp, _attendu(g, s.damage, true, false))
	h.egal(pavois.maxHp - pavois.hp, _attendu(g, s.damage, true, false), "le pavois de face ne l'arrête pas (elle tombe d'en haut)")
	# Étourdi `stun` s à partir du fracas : encore sonné juste avant, libre après.
	var g2 := _bac(h, "bourreau")
	var e2: Dictionary = _vif(g2, 300.0, 0.0, "brute", 5000.0)
	e2.cooldown = 999.0
	_lancer(h, g2)
	var evs2: Array = []
	while _de(evs2, "ultStrike").is_empty() and evs2.size() < 5000:
		evs2.append_array(h.avancer(g2, 1))
	h.proche(e2.stun, s.stun, 2.0 * DT, "étourdi `stun` s au fracas")
	h.egal(e2.state, "stunned")
	h.avancer(g2, h.ticks(s.stun) + 3)
	h.ok(e2.stun <= 0.0, "puis il se relève")
	h.ok(p.superCharge < 1.0)

static func _m_execution(h) -> void:
	var g := _bac(h, "bourreau")
	var s: Dictionary = g.tuning["super"]
	var au_seuil := _cible(g, 200.0, 0.0, "brute", 4000.0)
	au_seuil.hp = au_seuil.maxHp * s.executeBelow
	var dessous := _cible(g, -200.0, 0.0, "imp", 4000.0)
	dessous.hp = 3.0
	var au_dessus := _cible(g, 0.0, 200.0, "brute", 4000.0)
	au_dessus.hp = au_dessus.maxHp * s.executeBelow + 1.0
	var champion := _cible(g, 0.0, -200.0, "brute", 4000.0, {"elite": "blinde"})
	champion.hp = champion.maxHp * s.executeBelow
	var bulle := _cible(g, 300.0, 300.0, "brute", 4000.0)
	bulle.hp = 10.0
	bulle.invuln = 99.0
	var hp_au_dessus: float = au_dessus.hp
	var evs := _sentence(h, g)
	h.egal([au_seuil.dead, dessous.dead, champion.dead], [true, true, true], "exécutés : au seuil, dessous, champion")
	h.egal(au_dessus.dead, false, "au-dessus du seuil : blessé, pas exécuté")
	h.egal(hp_au_dessus - au_dessus.hp, _attendu(g, s.damage))
	h.egal([bulle.dead, bulle.hp], [false, 10.0], "sous une bulle d'immunité : ni exécuté, ni blessé")
	var eclairs := _de(evs, "ultBolt")
	h.egal(eclairs.filter(func(ev): return ev.executed).size(), 3, "trois marques d'exécution")
	h.egal(_de(evs, "ultStrike")[0].executed, 3.0)
	h.egal(_de(evs, "kill").filter(func(ev): return ev.kind == "super").size(), 3, "morts de sorte « super »")

static func _m_execution_compte(h) -> void:
	var g := _bac(h, "bourreau")
	var s: Dictionary = g.tuning["super"]
	g.player.slots[1].charges = 0.0 # le Cri : une charge rendue par l'élite abattu
	var champion := _cible(g, 150.0, 0.0, "brute", 4000.0, {"elite": "rapide"})
	champion.hp = champion.maxHp * s.executeBelow
	var ames: float = g.meta.souls
	var evs := _sentence(h, g)
	h.egal(champion.dead, true)
	h.egal(g.telemetry.kills, 1.0, "compté comme tué")
	h.egal(g.meta.souls - ames, g.tuning.progression.souls.elite, "Âmes d'un élite")
	h.ok(g.pickups.any(func(k): return k.kind == "gold") or _de(evs, "pickup").size() > 0, "il lâche son or")
	h.egal(g.player.slots[1].charges, g.tuning.gadgets.cri.chargeOnEliteKill, "récompense d'élite : une charge")

static func _m_gardien(h) -> void:
	var g := _bac(h, "bourreau")
	var s: Dictionary = g.tuning["super"]
	# Un Gardien presque mort : jamais exécuté. Sa vie est petite : le plafond joue.
	var boss: Dictionary = D6Enemies.create_enemy(g, "gardien", g.player.x, g.player.y - 250.0, {"boss": true, "spawnT": 0.0})
	boss.cooldown = 999.0
	boss.phase = 3.0 # dernière phase : aucune transition invulnérable ne vient brouiller la mesure
	boss.maxHp = 400.0
	boss.hp = boss.maxHp * 0.2 # sous le seuil d'exécution, au-dessus du plafond
	var hp0: float = boss.hp
	h.ok(boss.hp / boss.maxHp <= s.executeBelow and boss.hp > boss.maxHp * s.bossCap, "cas choisi")
	var evs := _sentence(h, g)
	var plafond: float = D6Js.jround(boss.maxHp * s.bossCap)
	h.ok(plafond < _attendu(g, s.damage, true, false), "cas choisi : le plafond est sous les dégâts du fracas")
	h.egal(boss.dead, false, "un Gardien n'est jamais exécuté")
	h.egal(hp0 - boss.hp, plafond, "il perd au plus bossCap de sa vie max")
	h.egal(boss.stun <= 0.0, true, "un Gardien n'est pas étourdi")
	h.egal(_de(evs, "ultBolt")[0].executed, false)
	# Un Gardien à la vie longue : le plafond est au-dessus, il prend le fracas ordinaire.
	var g2 := _bac(h, "bourreau")
	var gros: Dictionary = D6Enemies.create_enemy(g2, "gardien", g2.player.x, g2.player.y - 250.0, {"boss": true, "spawnT": 0.0})
	gros.cooldown = 999.0
	gros.maxHp = 100000.0
	gros.hp = 100000.0
	_sentence(h, g2)
	h.egal(gros.maxHp - gros.hp, _attendu(g2, s.damage, true, false), "vie longue : les dégâts du fracas, sans bonus")
	# Même sous le seuil et exposé (point faible), le plafond tient.
	var g3 := _bac(h, "bourreau")
	var expose: Dictionary = D6Enemies.create_enemy(g3, "gardien", g3.player.x, g3.player.y - 250.0, {"boss": true, "spawnT": 0.0})
	expose.cooldown = 999.0
	expose.phase = 3.0
	expose.maxHp = 400.0
	expose.hp = 400.0
	expose.exposed = 99.0
	expose.exposedMult = 5.0
	_sentence(h, g3)
	h.egal(expose.maxHp - expose.hp, plafond, "exposé : le plafond tient")

static func _m_projectiles(h) -> void:
	var g := _bac(h, "bourreau")
	var p: Dictionary = g.player
	for i in 4:
		D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x + 300.0 + 40.0 * i, "y": p.y - 300.0, "vx": 0.0, "vy": 1.0, "r": 6.0, "damage": 10.0, "range": 5000.0})
	var a_moi: Dictionary = D6Projectiles.spawn_projectile(g, {"owner": "player", "kind": "lance", "x": p.x, "y": p.y - 200.0, "vx": 0.0, "vy": -1.0, "r": 6.0, "damage": 1.0, "range": 5000.0})
	var evs := _sentence(h, g)
	h.egal(g.projectiles.filter(func(pr): return pr.get("owner") == "enemy").size(), 0, "plus aucun tir ennemi")
	h.egal(g.projectiles.any(func(pr): return is_same(pr, a_moi)), true, "les tirs du héros restent")
	h.egal(_de(evs, "deflect").size(), 4, "quatre tirs effacés, vus")

static func _m_fin(h) -> void:
	var g := _bac(h, "bourreau")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	_cible(g, 200.0, 0.0)
	_lancer(h, g)
	var portes := 0
	var pas := 0
	while p.state == "super" and pas < 600:
		if D6Combat.damage_player(g, 30.0, {"kind": "imp", "id": 900.0 + pas}):
			portes += 1
		h.avancer(g, 1)
		pas += 1
	h.egal(portes, 0, "aucun coup ne porte pendant le geste (%d pas)" % pas)
	h.egal(p.hp, p.maxHp)
	h.egal(p.state, "free", "libre à la fin")
	h.proche(float(pas) * DT, s.duration + s.freeze, 4.0 * DT, "le geste dure `duration`, plus le temps figé")
	h.egal(p.superCharge, 0.0, "jauge vide")
	h.egal(D6KitSupers.acting(g), false)
	var evs: Array = _sentence(h, g)
	h.egal(_de(evs, "ultStrike").size(), 1, "relançable une fois la jauge de nouveau pleine")

static func _m_vide(h) -> void:
	var g := _bac(h, "bourreau")
	var evs := _sentence(h, g)
	h.egal(_de(evs, "ultStrike").size(), 1)
	h.egal(_de(evs, "ultStrike")[0].hits, 0.0, "personne à frapper")
	h.egal(_de(evs, "ultBolt").size(), 0)
	h.egal(g.player.state, "free")
	h.egal(g.player.superCharge, 0.0)

static func _m_salle(h) -> void:
	var g := _bac(h, "bourreau", {"godMode": true})
	var s: Dictionary = g.tuning["super"]
	_lancer(h, g)
	h.avancer(g, h.ticks(s.strikeAt / 2.0))
	h.egal(g.player.state, "super")
	D6Run.enter_floor(g, g.run.floor + 1.0, PORTE)
	h.egal(g.player.state, "free", "nouvelle salle : le geste est abandonné")
	var evs: Array = h.avancer(g, h.ticks(s.duration + s.freeze + 2.0))
	h.egal(_de(evs, "ultStrike").size() + _de(evs, "ultFreeze").size(), 0, "aucun fracas dans la salle suivante")
	h.egal(_coups(evs, "super").size(), 0)
	h.egal(D6KitSupers.acting(g), false)
	h.egal(g.player.superCharge, 0.0, "la jauge dépensée reste dépensée")

static func _m_jauge(h) -> void:
	var g := _bac(h, "bourreau")
	_cible(g, 70.0, 0.0)
	_cible(g, 300.0, 100.0)
	var evs := _sentence(h, g)
	h.ok(_coups(evs, "super").size() >= 2)
	h.egal(g.player.superCharge, 0.0, "le fracas ne recharge pas la jauge")
	h.avancer(g, h.ticks(1.0), {"attack": true, "aimX": 1.0})
	h.ok(g.player.superCharge > 0.0, "les coups d'arme la remplissent de nouveau")

# ---------------------------------------------------------------- Meute des Limbes (Chasseresse)

static func _tests_meute(h) -> void:
	h.test("Meute : `count` limiers apparaissent près d'elle, avec leur vie et leur durée ; jamais dans game.enemies", func(): _l_apparition(h))
	h.test("Meute : apparition jamais dans un mur, un pilier ni de l'autre côté de l'eau (héroïne acculée)", func(): _l_apparition_coincee(h))
	h.test("Meute : la jauge est leur minuterie, ne se remplit pas, l'ultime ne se relance pas ; après eux, si", func(): _l_jauge(h))
	h.test("Meute : ils disparaissent à la fin de `life` (événement), pas avant", func(): _l_duree(h))
	h.test("Meute : cible — ce qu'elle vient de blesser, sinon ce qu'elle vise, sinon le plus proche du limier", func(): _l_cibles(h))
	h.test("Meute : morsure — montant, rythme, source « ally » : ni jauge, ni proc au toucher, ni vol de vie", func(): _l_morsure(h))
	h.test("Meute : un ennemi tué par un limier compte — tué, or, Âmes, procs « à la mort »", func(): _l_mort_ennemi(h))
	h.test("Meute : une vraie salle se nettoie par leurs morsures ; ennemis restants, vagues, invocations ne les comptent jamais", func(): _l_salle(h))
	h.test("Meute : un ennemi de mêlée se tourne vers le limier nettement plus près, et le frappe à son rythme", func(): _l_distraction(h))
	h.test("Meute : l'ennemi ne se détourne pas si l'héroïne est aussi près, ni un tireur, ni un Gardien", func(): _l_pas_distrait(h))
	h.test("Meute : un tir ennemi s'arrête sur un limier ; une zone qui frappe le héros frappe le limier", func(): _l_encaisse(h))
	h.test("Meute : un limier meurt à 0 PV (événement), les autres continuent", func(): _l_mort_limier(h))
	h.test("Meute : mort de l'héroïne — limiers retirés ; reprise propre", func(): _l_mort_heroine(h))
	h.test("Meute : changer de salle — limiers retirés, jauge à zéro", func(): _l_salle_suivante(h))
	h.test("Meute : ils contournent une rivière par le gué pour mordre de l'autre côté", func(): _l_gue(h))
	h.test("Meute : jamais dans l'eau ni dans un mur — %d graines de salles à terrain" % GRAINES_EAU, func(): _l_jamais_dans_l_eau(h))

static func _l_apparition(h) -> void:
	var g := _bac(h, "chasseresse", {"startFloor": 40.0})
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	var evs: Array = _lancer(h, g)
	h.egal(g.allies.size(), int(s.count), "le nombre de limiers")
	h.egal(_de(evs, "allySpawn").size(), int(s.count))
	h.egal(g.enemies.size(), 0, "aucun n'est un ennemi")
	var vie: float = D6Js.jround(s.hp * D6Floors.floor_scaling(g.tuning, 40.0).damage)
	h.ok(vie > s.hp, "à l'étage 40, leur vie suit l'échelle de dégâts de l'étage")
	var ids: Array = []
	for a in g.allies:
		h.egal([a.kind, a.hp, a.maxHp, a.r, a.dead], ["limier", vie, vie, s.houndRadius, false])
		h.proche(a.lifeMax, s.life, EPS, "durée")
		h.ok(sqrt(D6Geo.dist2(a.x, a.y, p.x, p.y)) <= s.spawnDist + EPS, "près d'elle")
		h.egal(D6Physics.ground_blocked(g.room, a.x, a.y, a.r), false)
		h.egal(ids.has(a.id), false, "identifiants distincts")
		ids.append(a.id)

static func _l_apparition_coincee(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	# Acculée dans un coin, un pilier d'un côté, une rivière de l'autre.
	p.x = g.room.pad + p.r + 1.0
	p.y = g.room.pad + p.r + 1.0
	g.room.obstacles = [{"x0": p.x + 30.0, "y0": 0.0, "x1": p.x + 70.0, "y1": p.y + 20.0}]
	g.room.low = [{"x0": 0.0, "y0": p.y + 30.0, "x1": 400.0, "y1": p.y + 94.0, "kind": "river"}]
	_lancer(h, g)
	h.egal(g.allies.size(), int(s.count), "ils apparaissent quand même")
	for a in g.allies:
		h.egal(D6Physics.ground_blocked(g.room, a.x, a.y, a.r), false, "terre ferme, hors des murs (%d, %d)" % [int(a.x), int(a.y)])
		h.egal(D6Physics.walk_clear(g.room, p.x, p.y, a.x, a.y), true, "du même côté de l'eau et du pilier qu'elle")

static func _l_jauge(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	_cible(g, 200.0, 0.0)
	_lancer(h, g)
	h.avancer(g, h.ticks(1.0))
	var attendue: float = g.allies[0].life / g.allies[0].lifeMax
	h.proche(p.superCharge, attendue, EPS, "la jauge suit la durée restante des limiers")
	h.ok(p.superCharge < 1.0 and p.superCharge > 0.8)
	# Elle tire sur la cible : la jauge ne monte pas, elle continue de descendre.
	var evs: Array = h.avancer(g, h.ticks(2.0), {"attack": true, "aimX": 1.0})
	h.ok(_coups(evs, "melee").size() > 0, "ses tirs portent")
	h.proche(p.superCharge, g.allies[0].life / g.allies[0].lifeMax, EPS, "ses coups ne la remplissent pas")
	# Jauge forcée pleine : l'ultime ne repart pas tant qu'un limier vit.
	p.superCharge = 1.0
	evs = h.avancer(g, h.ticks(s.holdTime + 0.5), {"attack": true})
	h.egal(_de(evs, "super").size(), 0, "il ne se relance pas pendant qu'il agit")
	h.egal(g.allies.size(), int(s.count))
	# Après eux : jauge vide, elle se remplit de nouveau, l'ultime repart.
	h.avancer(g, h.ticks(s.life))
	h.egal([g.allies.size(), p.superCharge], [0, 0.0], "fin : plus de limier, jauge vide")
	h.avancer(g, h.ticks(1.0), {"attack": true, "aimX": 1.0})
	h.ok(p.superCharge > 0.0, "la jauge se remplit de nouveau")
	evs = _lancer(h, g)
	h.egal(_de(evs, "super").size(), 1, "une nouvelle meute")
	h.egal(g.allies.size(), int(s.count))

static func _l_duree(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	_lancer(h, g)
	var evs: Array = h.avancer(g, h.ticks(s.life) - 3)
	h.egal(g.allies.size(), int(s.count), "encore là juste avant `life`")
	h.egal(_de(evs, "allyGone").size(), 0)
	evs = h.avancer(g, 6)
	h.egal(g.allies.size(), 0, "partis à `life`")
	var partis := _de(evs, "allyGone")
	h.egal(partis.size(), int(s.count))
	h.egal(partis[0].reason, "temps")
	h.egal(D6KitSupers.acting(g), false)

static func _l_cibles(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	var pres := _cible(g, 0.0, 160.0)
	var loin := _cible(g, 380.0, 0.0)
	_lancer(h, g, {"aimX": -1.0}) # son tir du maintien part dans le vide
	h.avancer(g, h.ticks(s.duration) + 2)
	for a in g.allies:
		h.egal(a.targetId, pres.id, "sans désignation : le plus proche du limier")
	# Elle blesse la cible lointaine : toute la meute s'y jette.
	D6Combat.damage_enemy(g, loin, {"kind": "melee", "amount": 1.0})
	h.avancer(g, 2)
	for a in g.allies:
		h.egal(a.targetId, loin.id, "ce qu'elle vient de blesser")
	# La désignation s'éteint après markTime : retour au plus proche de chacun.
	h.avancer(g, h.ticks(s.markTime) + 2)
	for a in g.allies:
		var plus_proche: Dictionary = pres if D6Geo.dist2(a.x, a.y, pres.x, pres.y) < D6Geo.dist2(a.x, a.y, loin.x, loin.y) else loin
		h.egal(a.targetId, plus_proche.id, "désignation éteinte : le plus proche")
	# Une morsure ne désigne rien : seuls SES coups à elle comptent.
	h.egal(p.markId, loin.id, "les morsures n'ont pas changé la désignation")
	# Ce qu'elle VISE (cible de sa visée assistée), sans l'avoir blessé.
	p.lastTargetId = pres.id
	p.lastTargetAt = g.time
	p.markAt = -99.0
	h.avancer(g, 1)
	for a in g.allies:
		h.egal(a.targetId, pres.id, "ce qu'elle vise")
	# Une cible morte n'est plus suivie.
	D6Combat.kill_enemy(g, pres)
	h.avancer(g, 2)
	for a in g.allies:
		h.egal(a.targetId, loin.id)

static func _l_morsure(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	_benir(g, "coup_de_sang") # un proc « au toucher » d'arme, s'il existe : il ne doit pas jouer
	_talisman(g, "lifesteal", 0.1)
	p.hp = p.maxHp - 30.0
	var hp0: float = p.hp
	var e := _cible(g, 0.0, -120.0)
	_lancer(h, g, {"aimY": 1.0}) # son tir du maintien part dans le vide
	var evs: Array = h.avancer(g, h.ticks(4.0))
	var morsures := _coups(evs, "ally")
	h.ok(morsures.size() >= int(s.count) * 3, "ils mordent (%d morsures en 4 s)" % morsures.size())
	h.egal(morsures[0].amount, _attendu(g, s.biteDamage), "montant d'une morsure")
	h.egal(_de(evs, "allyBite").size(), morsures.size(), "un événement par morsure")
	h.egal(_coups(evs, "melee").size() + _coups(evs, "super").size(), 0, "aucun coup de l'héroïne dans cette mesure")
	h.egal(p.hp, hp0, "pas de vol de vie sur une morsure")
	h.egal([e.burn, e.vuln, e.chill], [0.0, 0.0, 0.0], "aucun proc « au toucher »")
	h.egal(p.markId, 0.0, "une morsure ne désigne pas de cible")
	# Rythme : un même limier ne mord pas plus d'une fois par biteEvery.
	var par_limier := {}
	for ev in _de(evs, "allyBite"):
		if par_limier.has(ev.id):
			h.ok((ev.tick - par_limier[ev.id]) * DT >= s.biteEvery - 1.5 * DT, "au moins biteEvery entre deux morsures")
		par_limier[ev.id] = ev.tick
	# La jauge ne monte pas par eux (elle est leur minuterie), ni après s'ils mordent seuls.
	h.proche(p.superCharge, g.allies[0].life / g.allies[0].lifeMax, EPS)

static func _l_mort_ennemi(h) -> void:
	var g := _bac(h, "chasseresse")
	var p: Dictionary = g.player
	g.player.stats.healOnKill = 5.0
	p.hp = p.maxHp - 20.0
	var e := _cible(g, 0.0, -100.0, "imp", 3.0)
	var ames: float = g.meta.souls
	_lancer(h, g, {"aimY": 1.0}) # son tir du maintien part dans le vide
	var evs: Array = h.avancer(g, h.ticks(3.0))
	h.egal(e.dead, true, "tué par les limiers")
	h.egal(_de(evs, "kill")[0].kind, "ally", "mort de sorte « ally »")
	h.egal(g.telemetry.kills, 1.0)
	h.egal(g.meta.souls - ames, g.tuning.progression.souls.kill, "Âmes")
	h.ok(g.pickups.any(func(k): return k.kind == "gold") or _de(evs, "pickup").size() > 0, "son or tombe")
	h.egal(_de(evs, "heal").size(), 1, "les procs « à la mort » jouent (soin par ennemi tué)")

static func _l_salle(h) -> void:
	var g: Dictionary = h.partie({"seed": 21.0, "meta": _meta("chasseresse"), "godMode": true, "tuning": {"supers": {"meute_limbes": {"life": 59.0, "biteDamage": 400.0}}}})
	h.avancer(g, h.ticks(1.5))
	_lancer(h, g)
	var vus := false
	var evs: Array = []
	for i in h.ticks(50.0):
		evs.append_array(h.avancer(g, 1))
		if g.mode != "play" or g.room.cleared:
			break
		if not g.allies.is_empty():
			vus = true
			for e in g.enemies:
				h.different(e.kind, "limier", "aucun limier parmi les ennemis")
			var vivants := 0.0
			for e in g.enemies:
				if not e.dead:
					vivants += 1.0
			h.egal(D6Enemies.alive_enemies(g), vivants, "« ennemis restants » ne compte que des ennemis")
			h.egal(D6AiCommon.summoned_count(g), 0.0, "ils ne sont pas des invocations d'ennemis")
	h.ok(vus, "la meute a combattu")
	h.egal(g.room.cleared, true, "la salle est nettoyée par leurs morsures (héroïne immobile)")
	h.egal(_de(evs, "roomClear").size(), 1)
	h.ok(_coups(evs, "ally").size() > 0 and _coups(evs, "melee").size() == 0, "elle n'a pas frappé")
	h.ok(g.telemetry.kills >= 2.0, "tués comptés (%s)" % str(g.telemetry.kills))

## Meute posée à la main : un limier à (dx, dy) de l'héroïne, immobile si `fige` (pas de cible à mordre).
static func _limier(g: Dictionary, dx: float, dy: float) -> Dictionary:
	var s: Dictionary = g.tuning["super"]
	var a := {
		"id": D6State.new_id(g), "kind": "limier", "x": g.player.x + dx, "y": g.player.y + dy, "vx": 0.0, "vy": 0.0, "r": s.houndRadius,
		"hp": s.hp, "maxHp": s.hp, "life": 999.0, "lifeMax": 999.0, "state": "heel", "targetId": 0.0, "biteT": 999.0,
		"face": 0.0, "flash": 0.0, "slot": 0.0, "dead": false, "nav": null,
	}
	g.allies.append(a)
	return a

static func _l_distraction(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	var def: Dictionary = g.tuning.enemies.imp
	var a := _limier(g, 300.0, 0.0)
	var imp := _vif(g, 360.0, 0.0, "imp", 99999.0)
	imp.cooldown = 0.0
	g.tuning.supers.meute_limbes.speed = 0.0 # le limier reste où il est : seule la règle de l'ennemi joue
	var evs: Array = h.avancer(g, h.ticks(def.cooldown * 3.0 + 0.5))
	h.egal(imp.get("allyId"), a.id, "il s'est tourné vers le limier")
	h.egal(p.hp, p.maxHp, "l'héroïne n'est pas attaquée")
	h.egal(_de(evs, "playerHurt").size(), 0)
	var coups := _de(evs, "allyHurt")
	h.ok(coups.size() >= 3 and coups.size() <= 4, "il frappe à SON rythme (recharge %s s) : %d coups" % [str(def.cooldown), coups.size()])
	h.egal(coups[0].amount, D6Js.jround(def.damage * imp.dmgScale), "à SES dégâts")
	h.egal(s.hp - a.hp, coups.size() * D6Js.jround(def.damage * imp.dmgScale), "la vie du limier baisse d'autant")
	h.ok(sqrt(D6Geo.dist2(imp.x, imp.y, a.x, a.y)) <= imp.r + a.r + 10.0, "au contact du limier")
	h.ok(D6AiCommon.active_attackers(g) == 0.0, "il ne tient pas de jeton d'attaque contre l'héroïne")

static func _l_pas_distrait(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	g.tuning.supers.meute_limbes.speed = 0.0
	# Héroïne à 100 u, limier à 80 u : pas « nettement plus près » (il faudrait moins de 100 × ratio).
	var a := _limier(g, 180.0, 0.0)
	var imp := _vif(g, 100.0, 0.0, "imp", 99999.0)
	h.ok(80.0 > 100.0 * s.distractRatio, "cas choisi : au-dessus du rapport")
	var tireur := _vif(g, 320.0, 0.0, "archer", 99999.0) # à 140 u du limier, 320 u d'elle : un tireur ne se détourne pas
	var boss: Dictionary = D6Enemies.create_enemy(g, "gardien", p.x + 200.0, p.y + 30.0, {"boss": true, "spawnT": 0.0})
	h.avancer(g, h.ticks(1.5))
	h.egal(D6Js.nz(imp.get("allyId"), 0.0), 0.0, "l'ennemi de mêlée reste sur l'héroïne")
	h.egal(D6Js.nz(tireur.get("allyId"), 0.0), 0.0, "le tireur ne se détourne pas")
	h.egal(D6Js.nz(boss.get("allyId"), 0.0), 0.0, "le Gardien ignore les limiers")
	h.egal(a.dead, false)
	# Trop loin (au-delà de distractRange) : pas distrait non plus, même si l'héroïne est très loin.
	var g2 := _bac(h, "chasseresse")
	g2.tuning.supers.meute_limbes.speed = 0.0
	g2.player.x = 100.0
	_limier(g2, 500.0, 0.0)
	var loin := _vif(g2, 500.0 + s.distractRange + 60.0, 0.0, "imp", 99999.0)
	h.avancer(g2, 3)
	h.egal(D6Js.nz(loin.get("allyId"), 0.0), 0.0, "au-delà de distractRange : il vise l'héroïne")

static func _l_encaisse(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	g.tuning.supers.meute_limbes.speed = 0.0
	var a := _limier(g, 150.0, 0.0)
	# Un tir ennemi vers l'héroïne, le limier sur le trajet.
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x + 300.0, "y": p.y, "vx": -400.0, "vy": 0.0, "r": 6.0, "damage": 9.0, "range": 900.0})
	var evs: Array = h.avancer(g, h.ticks(1.2))
	h.egal(s.hp - a.hp, 9.0, "le limier prend le tir")
	h.egal(p.hp, p.maxHp, "l'héroïne ne le prend pas")
	h.egal(g.projectiles.size(), 0, "le tir s'arrête sur lui")
	h.egal(_de(evs, "allyHurt")[0].source, "arrow")
	# Une zone télégraphiée qui frappe le héros frappe aussi le limier qui s'y trouve — pas celui dehors.
	var dehors := _limier(g, -300.0, 0.0)
	D6Combat.spawn_hazard(g, {"shape": "circle", "x": a.x, "y": a.y, "r": 60.0, "delay": 0.2, "damage": 12.0, "kind": "brute"})
	h.avancer(g, h.ticks(0.4))
	h.egal(s.hp - a.hp, 9.0 + 12.0, "le limier dans la zone est frappé")
	h.egal(dehors.hp, s.hp, "celui qui est dehors, non")
	# Une zone qui ne frappe que les ennemis (explosion du héros) ne les touche pas.
	D6Combat.spawn_hazard(g, {"shape": "circle", "x": a.x, "y": a.y, "r": 60.0, "delay": 0.1, "damage": 50.0, "hitsPlayer": false, "hitsEnemies": true, "kind": "sinBlast"})
	h.avancer(g, h.ticks(0.3))
	h.egal(s.hp - a.hp, 21.0, "les explosions du héros ne blessent pas ses limiers")

static func _l_mort_limier(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	_lancer(h, g)
	var premier: Dictionary = g.allies[0]
	h.egal(D6KitSupers.hurt_ally(g, premier, premier.hp - 1.0, "essai"), true)
	h.egal([premier.dead, premier.hp], [false, 1.0], "blessé, pas mort")
	D6KitSupers.hurt_ally(g, premier, 5.0, "essai")
	h.egal([premier.dead, premier.hp], [true, 0.0], "mort à 0 PV")
	h.egal(D6KitSupers.hurt_ally(g, premier, 5.0, "essai"), false, "un limier mort ne prend plus rien")
	var evs: Array = g.events.duplicate()
	h.egal(_de(evs, "allyDeath").size(), 1)
	h.avancer(g, 2)
	h.egal(g.allies.size(), int(s.count) - 1, "il est retiré, les autres restent")
	h.egal(D6KitSupers.acting(g), true, "l'ultime agit tant qu'il en reste un")
	for a in g.allies.duplicate():
		D6KitSupers.hurt_ally(g, a, 9999.0, "essai")
	h.avancer(g, h.ticks(s.duration) + 2) # le geste de lancement finit aussi
	h.egal([g.allies.size(), D6KitSupers.acting(g), g.player.superCharge], [0, false, 0.0], "tous morts : l'ultime est fini, jauge vide")

static func _l_mort_heroine(h) -> void:
	var g := _bac(h, "chasseresse")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	_cible(g, 200.0, 0.0)
	_lancer(h, g)
	h.avancer(g, h.ticks(s.duration) + 5)
	p.iframes = 0.0
	h.egal(D6Combat.damage_player(g, 9999.0, {"kind": "imp", "id": 77.0}), true)
	h.egal(p.state, "dead")
	var evs: Array = h.avancer(g, h.ticks(0.3)) # le gel d'impact de la blessure d'abord
	h.egal(g.allies.size(), 0, "elle meurt : la meute disparaît")
	h.egal(_de(evs, "allyGone").size(), int(s.count))
	h.egal(_de(evs, "allyGone")[0].reason, "mort")
	h.avancer(g, h.ticks(g.tuning.player.deathDelay) + 2)
	h.egal(g.mode, "dead")
	h.egal(D6Run.respawn(g), true)
	h.egal([g.allies.size(), p.state, D6KitSupers.acting(g)], [0, "free", false], "reprise propre")
	h.proche(p.superCharge, s.startCharge, EPS, "jauge de départ")
	h.avancer(g, 30)
	_lancer(h, g)
	h.egal(g.allies.size(), int(s.count), "et la meute revient à la prochaine jauge pleine")

static func _l_salle_suivante(h) -> void:
	var g := _bac(h, "chasseresse", {"godMode": true})
	var s: Dictionary = g.tuning["super"]
	_lancer(h, g)
	h.avancer(g, h.ticks(1.0))
	g.events.clear()
	D6Run.enter_floor(g, g.run.floor + 1.0, PORTE)
	h.egal(g.allies.size(), 0, "ils ne suivent pas dans la salle suivante")
	h.egal(_de(g.events, "allyGone").size(), int(s.count))
	h.egal(g.player.superCharge, 0.0)
	h.egal(D6KitSupers.acting(g), false)
	var evs: Array = h.avancer(g, h.ticks(1.0))
	h.egal(_coups(evs, "ally").size(), 0)

static func _l_gue(h) -> void:
	var g := _bac(h, "chasseresse")
	var p: Dictionary = g.player
	# Une rivière en travers de la salle, un seul gué tout à gauche. La cible est juste en face, de l'autre côté.
	var ry: float = p.y - 140.0
	g.room.low = [{"x0": 200.0, "y0": ry, "x1": g.room.w, "y1": ry + 64.0, "kind": "river"}]
	g.room.nav = D6Nav.build_nav(g.room)
	var e := _cible(g, 0.0, -300.0)
	h.egal(D6Physics.walk_clear(g.room, p.x, p.y, e.x, e.y), false, "la rivière coupe le chemin direct")
	_lancer(h, g)
	var mordu_a := -1
	for i in h.ticks(9.0):
		var evs: Array = h.avancer(g, 1)
		for a in g.allies:
			if D6Physics.low_at(g.room, a.x, a.y, a.r):
				h.ok(false, "limier dans l'eau au pas %d (%d, %d)" % [i, int(a.x), int(a.y)])
				return
		if mordu_a < 0 and _coups(evs, "ally").size() > 0:
			mordu_a = i
	h.ok(mordu_a > 0, "ils ont rejoint et mordu la cible de l'autre côté")
	h.ok(mordu_a * DT > 2.0, "en faisant le tour par le gué (%s s : pas à vol d'oiseau)" % str(mordu_a * DT))

## Le corps mord-il sur un pilier (cercle contre rectangle, à 1e-3 près) ou sort-il des murs ?
static func _dans_le_dur(room: Dictionary, a: Dictionary) -> bool:
	var m: float = room.pad + a.r - 1e-3
	if a.x < m or a.x > room.w - m or a.y < m or a.y > room.h - m:
		return true
	for o in room.obstacles:
		var dx: float = a.x - D6Geo.clampv(a.x, o.x0, o.x1)
		var dy: float = a.y - D6Geo.clampv(a.y, o.y0, o.y1)
		if dx * dx + dy * dy < (a.r - 1e-3) * (a.r - 1e-3):
			return true
	return false

static func _l_jamais_dans_l_eau(h) -> void:
	var meta := _meta("chasseresse")
	var avec_terrain := 0
	var morsures := 0
	var fautes := 0
	for graine in GRAINES_EAU:
		var g: Dictionary = h.partie({"seed": 9000.0 + graine, "startFloor": 5.0 + float(graine % 60) * 7.0, "meta": meta, "godMode": true})
		if g.room.low.is_empty():
			continue
		avec_terrain += 1
		# L'héroïne quelque part sur la terre ferme (tirage propre au test, jamais celui de la partie).
		var r: Dictionary = D6Rng.create_rng(graine + 1)
		var p: Dictionary = g.player
		for essai in 60:
			var x: float = g.room.pad + D6Rng.rand(r) * (g.room.w - 2.0 * g.room.pad)
			var y: float = g.room.pad + D6Rng.rand(r) * (g.room.h - 2.0 * g.room.pad)
			if not D6Physics.ground_blocked(g.room, x, y, p.r + 1.0):
				p.x = x
				p.y = y
				break
		h.avancer(g, h.ticks(1.2)) # la première vague apparaît
		_lancer(h, g)
		for i in h.ticks(3.0):
			D6Game.step_game(g, D6Game.empty_input())
			for ev in g.events:
				if ev.type == "hit" and ev.get("kind") == "ally":
					morsures += 1
			g.events.clear()
			for a in g.allies:
				if D6Physics.low_at(g.room, a.x, a.y, a.r) or _dans_le_dur(g.room, a):
					fautes += 1
					if fautes == 1:
						h.ok(false, "graine %d, pas %d : limier en (%s, %s), salle %s" % [9000 + graine, i, str(a.x), str(a.y), g.room.layout])
	h.ok(avec_terrain >= GRAINES_EAU / 6, "assez de salles à terrain jouées (%d sur %d graines)" % [avec_terrain, GRAINES_EAU])
	h.ok(morsures > avec_terrain, "les limiers ont vraiment couru et mordu (%d morsures)" % morsures)
	h.egal(fautes, 0, "aucun limier dans l'eau, dans un pilier ni hors des murs")

# ---------------------------------------------------------------- Forme du Damné (Revenant)

static func _tests_forme(h) -> void:
	h.test("Forme : au lancement, les griffes remplacent l'arme et slot_view rend les trois actions de forme", func(): _f_lancement(h))
	h.test("Forme : la jauge se vide et sert de minuterie ; rien ne la remplit ; l'ultime ne se relance pas", func(): _f_jauge(h))
	h.test("Forme : à la fin de `formTime`, kit d'origine rendu à l'IDENTIQUE (recharges et charges figées)", func(): _f_fin(h))
	h.test("Forme : l'attaque est celle des griffes quelle que soit l'arme équipée, avec leur vol de vie", func(): _f_griffes(h))
	h.test("Forme : Ruée spectrale — traverse, blesse ce qui est sur le passage, sa recharge", func(): _f_ruee(h))
	h.test("Forme : Ruée spectrale — s'arrête au mur, ne finit jamais dans une rivière", func(): _f_ruee_terrain(h))
	h.test("Forme : Hurlement — étourdit autour, pas au-delà", func(): _f_hurlement(h))
	h.test("Forme : Embrasement — met fin à la forme, explosion proportionnelle au temps restant", func(): _f_embrasement(h))
	h.test("Forme : le déplacement reste le dash", func(): _f_dash(h))
	h.test("Forme : mourir pendant la forme rend le kit d'origine ; reprise propre", func(): _f_mort(h))
	h.test("Forme : changer de salle pendant la forme la termine, kit d'origine rendu", func(): _f_salle(h))
	h.test("Forme : un recalcul du build pendant la forme (bénédiction, objet) garde le kit de forme", func(): _f_recalcul(h))
	h.test("Forme : salle vide — elle dure, se termine, rend le kit", func(): _f_vide(h))

## Entre en forme et laisse finir le geste de lancement ; rend les événements.
static func _forme(h, g: Dictionary) -> Array:
	var evs: Array = _lancer(h, g)
	var garde := 0
	while g.player.state == "super" and garde < 600: # le geste peut être allongé (Gloire charnelle)
		evs.append_array(h.avancer(g, 1))
		garde += 1
	return evs

static func _f_lancement(h) -> void:
	for arme in ["lame", "dagues"]:
		var g := _bac(h, "revenant", {}, arme)
		var s: Dictionary = g.tuning["super"]
		var avant: Array = [g.kit.slots.duplicate(), g.kit.weaponType]
		h.ok(is_same(g.tuning.combo, g.tuning.weapons[arme].combo), "avant : le combo de l'arme (%s)" % arme)
		var evs: Array = _lancer(h, g)
		h.egal(_de(evs, "formStart").size(), 1)
		h.egal(D6KitSupers.form_of(g) != null, true, "en forme dès le geste")
		h.ok(is_same(g.tuning.combo, s.weapon.combo) and is_same(g.tuning.dashStrike, s.weapon.dashStrike) and is_same(g.tuning.weapon, s.weapon), "les griffes sont l'arme active")
		h.egal(g.kit.slots, s.slots, "les trois emplacements portent les actions de forme")
		h.egal(g.kit.weaponType, avant[1], "l'arme ÉQUIPÉE n'a pas changé")
		for i in D6Loadout.SLOTS:
			var v = D6Loadout.slot_view(g, i)
			var a: Dictionary = s.actions[s.slots[i]]
			h.egal([v.id, v.name, v.icon, v.kind, v.ready, v.cooldownFrac, v.charges, v.maxCharges], [s.slots[i], a.name, a.icon, "skill", true, 0.0, null, null], "slot_view %d" % i)
			h.egal(v.aimed, a.get("aimed", true), "se vise ou non : dit par les données")
			h.egal(v.keys(), D6Loadout.slot_view(_bac(h, "revenant"), 0).keys(), "mêmes champs qu'une compétence ordinaire")
		h.egal(g.player.ult.slots, avant[0], "les emplacements d'origine sont gardés")

static func _f_jauge(h) -> void:
	var g := _bac(h, "revenant")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	_cible(g, 70.0, 0.0)
	_forme(h, g)
	h.proche(p.superCharge, p.ult.t / p.ult.max, EPS, "jauge = part de forme restante")
	h.proche(p.ult.max, s.formTime, EPS)
	var c0: float = p.superCharge
	var evs: Array = h.avancer(g, h.ticks(2.0), {"attack": true, "aimX": 1.0})
	h.ok(_coups(evs, "melee").size() >= 6, "les griffes portent (%d coups en 2 s)" % _coups(evs, "melee").size())
	h.ok(p.superCharge < c0, "la jauge descend")
	h.proche(p.superCharge, p.ult.t / p.ult.max, EPS, "les coups en forme ne la remplissent pas")
	h.ok(c0 - p.superCharge <= 2.0 / s.formTime + EPS and c0 - p.superCharge > 1.0 / s.formTime, "elle se vide au rythme du temps de jeu ; un gel d'impact la retient d'autant (%s)" % str(c0 - p.superCharge))
	p.superCharge = 1.0
	evs = h.avancer(g, h.ticks(s.holdTime + 0.4), {"attack": true})
	h.egal(_de(evs, "super").size() + _de(evs, "formStart").size(), 0, "elle ne se relance pas pendant qu'elle agit")
	h.egal(D6Player.ultimate_view(g).active, true)

static func _f_fin(h) -> void:
	var g := _bac(h, "revenant", {}, "dagues")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	# État d'origine marqué : une recharge en cours, des charges entamées.
	p.slots[0].cd = 2.75
	p.slots[1].charges = 1.0
	p.slots[2].cd = 0.5
	var kit_avant: Array = g.kit.slots.duplicate()
	var evs: Array = _forme(h, g)
	# L'état gardé est celui du pas où la forme commence (le maintien de 0,4 s a couru avant).
	var avant: Array = D6Js.clone(p.ult.states)
	h.ok(avant[0].cd < 2.75 and avant[0].cd > 2.75 - 1.0, "la recharge a couru pendant le maintien seulement (%s)" % str(avant[0].cd))
	h.egal([avant[1].charges, avant[2].charges], [1.0, 0.0], "charges gardées")
	evs.append_array(h.avancer(g, h.ticks(s.formTime - s.duration) - 8))
	h.egal(D6KitSupers.form_of(g) != null, true, "encore en forme juste avant formTime")
	h.egal(_de(evs, "formEnd").size(), 0)
	evs = h.avancer(g, 12)
	var fins := _de(evs, "formEnd")
	h.egal(fins.size(), 1, "la forme finit à formTime")
	h.egal(fins[0].reason, "temps")
	h.egal([p.get("ult"), D6KitSupers.acting(g), p.superCharge], [null, false, 0.0], "plus de forme, jauge vide")
	h.egal(g.kit.slots, kit_avant, "les trois emplacements d'origine")
	# (la forme a fini quelques pas avant la fin de la mesure : la recharge n'a repris que depuis)
	h.egal(p.slots.map(func(st): return st.charges), avant.map(func(st): return st.charges), "charges telles qu'avant la forme")
	h.ok(p.slots[0].cd <= avant[0].cd and p.slots[0].cd >= avant[0].cd - 12.0 * DT, "recharge telle qu'avant la forme : elle n'a pas couru pendant (%s pour %s)" % [str(p.slots[0].cd), str(avant[0].cd)])
	h.egal(p.slots[1].cd, 0.0)
	h.ok(is_same(g.tuning.combo, g.tuning.weapons.dagues.combo) and is_same(g.tuning.weapon, g.tuning.weapons.dagues), "l'arme équipée est de nouveau l'arme active")
	h.egal(D6Loadout.slot_view(g, 0).id, "lance")
	avant = D6Js.clone(avant) # la suite modifie p.slots, qui EST le tableau rendu
	# Le kit d'origine se rejoue : la recharge reprend là où elle était, le gadget part sur sa charge.
	var cd_rendu: float = p.slots[0].cd
	h.avancer(g, h.ticks(1.0))
	h.proche(p.slots[0].cd, cd_rendu - h.ticks(1.0) * DT, 1e-3, "la recharge reprend son cours")
	evs = h.avancer(g, 1, {"skill2Pressed": true})
	h.egal(_de(evs, "gadget").size(), 1)
	h.egal(p.slots[1].charges, 0.0)
	# Après la forme, la jauge se remplit de nouveau et un coup d'arme part avec l'arme.
	_cible(g, 60.0, 0.0)
	evs = h.avancer(g, h.ticks(0.6), {"attack": true, "aimX": 1.0})
	h.ok(p.superCharge > 0.0)
	h.egal(_de(evs, "swing")[0].range, g.tuning.weapons.dagues.combo[0].range)

static func _f_griffes(h) -> void:
	var portees: Array = []
	for arme in ["lame", "dagues"]:
		var g := _bac(h, "revenant", {}, arme)
		var s: Dictionary = g.tuning["super"]
		var p: Dictionary = g.player
		var e := _cible(g, 70.0, 0.0)
		_forme(h, g)
		p.hp = p.maxHp - 50.0
		var hp0: float = p.hp
		var evs: Array = h.avancer(g, 1, {"attackPressed": true, "aimX": 1.0})
		evs.append_array(h.avancer(g, h.ticks(0.25), {"aimX": 1.0}))
		var gestes := _de(evs, "swing")
		h.egal(gestes.size(), 1, "%s : un coup" % arme)
		h.egal([gestes[0].range, gestes[0].arc], [s.weapon.combo[0].range, s.weapon.combo[0].arc * D6Data.DEG], "%s : le coup 1 des griffes" % arme)
		var coup: Dictionary = _coups(evs, "melee")[0]
		h.egal(coup.amount, _attendu(g, s.weapon.combo[0].damage, false), "%s : dégâts des griffes" % arme)
		h.proche(p.hp - hp0, coup.amount * s.lifesteal, EPS, "%s : vol de vie des griffes" % arme)
		h.ok(e.hp < e.maxHp)
		portees.append(gestes[0].range)
		# Le combo des griffes s'enchaîne et boucle sans erreur (3 coups, quel que soit le combo de l'arme).
		evs = h.avancer(g, h.ticks(2.0), {"attack": true, "aimX": 1.0})
		var rangs: Array = _de(evs, "attackStart").map(func(ev): return ev.index)
		h.ok(rangs.has(float(s.weapon.combo.size()) - 1.0) and rangs.max() == float(s.weapon.combo.size()) - 1.0, "%s : le combo des griffes boucle (%s)" % [arme, str(rangs.slice(0, 6))])
	h.egal(portees[0], portees[1], "mêmes griffes avec la Lame et avec les Dagues")
	# Hors forme, pas de vol de vie des griffes.
	var g2 := _bac(h, "revenant")
	_cible(g2, 70.0, 0.0)
	g2.player.hp = 20.0
	h.avancer(g2, h.ticks(0.5), {"attack": true, "aimX": 1.0})
	h.egal(g2.player.hp, 20.0, "hors forme : aucun vol de vie")

## Presse l'emplacement de l'action de forme `id` en visant (ax, ay) ; rend les événements du lancer.
static func _action(h, g: Dictionary, id: String, ax: float = 0.0, ay: float = 0.0) -> Array:
	var s: Dictionary = g.tuning["super"]
	var i: int = s.slots.find(id)
	var n := "skill%d" % (i + 1)
	var evs: Array = h.avancer(g, 1, {n + "Pressed": true, n + "AimX": ax, n + "AimY": ay})
	evs.append_array(h.avancer(g, h.ticks(s.actions[id].castTime) + 3))
	return evs

static func _f_ruee(h) -> void:
	var g := _bac(h, "revenant")
	var s: Dictionary = g.tuning["super"]
	var a: Dictionary = s.actions.ruee_spectrale
	var p: Dictionary = g.player
	_forme(h, g)
	var sur_le_passage := _cible(g, 120.0, 10.0)
	var au_bout := _cible(g, 250.0, -20.0)
	var a_cote := _cible(g, 120.0, 140.0)
	var derriere := _cible(g, -80.0, 0.0)
	var x0: float = p.x
	var y0: float = p.y
	var evs := _action(h, g, "ruee_spectrale", 1.0, 0.0)
	h.egal(_de(evs, "formRush").size(), 1)
	h.proche(p.x - x0, a.range, RUEE_TOL, "il traverse `range` u")
	h.proche(p.y, y0, 1.0)
	for e in [sur_le_passage, au_bout]:
		h.egal(e.maxHp - e.hp, _attendu(g, a.damage), "blessé sur le passage")
	h.egal([a_cote.hp, derriere.hp], [a_cote.maxHp, derriere.maxHp], "ni à côté, ni derrière")
	h.egal(_coups(evs, "super").size(), 2, "source « super »")
	h.ok(a.width / 2.0 + sur_le_passage.r > 10.0 and a.width / 2.0 + a_cote.r < 140.0, "cas choisis de part et d'autre de la demi-largeur")
	h.proche(p.slots[0].cd, a.cooldown * p.stats.skillCooldownMult, 0.2, "sa recharge part")
	h.egal(D6Loadout.slot_view(g, 0).ready, false)
	h.egal(D6Combat.damage_player(g, 10.0, {"kind": "imp", "id": 5.0}), false, "invulnérable un instant")
	h.egal(D6KitSupers.form_of(g) != null, true, "la forme continue")

const RUEE_TOL := 12.0 # u : le héros est repoussé hors de l'ennemi sur lequel il se pose

static func _f_ruee_terrain(h) -> void:
	var g := _bac(h, "revenant")
	var a: Dictionary = g.tuning["super"].actions.ruee_spectrale
	var p: Dictionary = g.player
	_forme(h, g)
	# Un mur : il s'y arrête, dans la salle.
	p.x = g.room.w - g.room.pad - p.r - 60.0
	_action(h, g, "ruee_spectrale", 1.0, 0.0)
	h.proche(p.x, g.room.w - g.room.pad - p.r, 1.0, "arrêté au mur")
	# Des rivières de toutes largeurs, toutes distances : jamais posé dans l'eau.
	var r: Dictionary = D6Rng.create_rng(77)
	var raccourcies := 0
	for essai in 200:
		p.slots[0].cd = 0.0
		p.x = g.room.w / 2.0
		p.y = g.room.h / 2.0
		var debut: float = p.x + 30.0 + D6Rng.rand(r) * 200.0
		g.room.low = [{"x0": debut, "y0": 0.0, "x1": debut + 20.0 + D6Rng.rand(r) * 200.0, "y1": g.room.h, "kind": "river"}]
		var ang: float = (D6Rng.rand(r) - 0.5) * 1.2
		_action(h, g, "ruee_spectrale", D6Trig.cos(ang), D6Trig.sin(ang))
		if D6Physics.low_at(g.room, p.x, p.y, p.r):
			h.ok(false, "essai %d : posé dans l'eau en x = %s (rivière %s → %s)" % [essai, str(p.x), str(debut), str(g.room.low[0].x1)])
			return
		if p.x - g.room.w / 2.0 < a.range * D6Trig.cos(ang) - 2.0:
			raccourcies += 1
	h.ok(raccourcies > 20, "des ruées raccourcies au bord de l'eau ont été jouées (%d)" % raccourcies)
	h.ok(raccourcies < 200, "et des ruées entières par-dessus l'eau (%d)" % (200 - raccourcies))

static func _f_hurlement(h) -> void:
	var g := _bac(h, "revenant")
	var a: Dictionary = g.tuning["super"].actions.hurlement
	_forme(h, g)
	var dedans: Dictionary = _vif(g, a.radius - 30.0, 0.0, "brute", 5000.0)
	var dehors: Dictionary = _vif(g, 0.0, a.radius + 80.0, "brute", 5000.0)
	dedans.cooldown = 999.0
	dehors.cooldown = 999.0
	var evs := _action(h, g, "hurlement")
	h.egal(_de(evs, "formHowl").size(), 1)
	h.ok(dedans.stun > a.stun - 0.2 and dedans.stun <= a.stun, "étourdi `stun` s (%s)" % str(dedans.stun))
	h.egal(dedans.maxHp - dedans.hp, _attendu(g, a.damage, true, false))
	h.egal([dehors.stun <= 0.0, dehors.hp], [true, dehors.maxHp], "hors du rayon : rien")
	h.egal(D6Loadout.slot_view(g, 1).aimed, false, "il ne se vise pas")

static func _f_embrasement(h) -> void:
	var montants: Array = []
	for attente in [0.5, 7.0]:
		var g := _bac(h, "revenant")
		var s: Dictionary = g.tuning["super"]
		var a: Dictionary = s.actions.embrasement
		var p: Dictionary = g.player
		var e := _cible(g, a.radius - 40.0, 0.0)
		var loin := _cible(g, 0.0, a.radius + 90.0)
		D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": p.x - 60.0, "y": p.y - 60.0, "vx": 0.0, "vy": 0.0, "r": 6.0, "damage": 10.0, "range": 5000.0})
		p.slots[0].cd = 1.5
		_forme(h, g)
		var avant: Array = D6Js.clone(p.ult.states)
		h.avancer(g, h.ticks(attente))
		var hp0: float = e.hp
		var evs := _action(h, g, "embrasement")
		var explosion: Dictionary = _de(evs, "formBurst")[0]
		var attendu: float = _attendu(g, D6Geo.lerpv(a.damage, a.damageMax, explosion.frac))
		h.egal(hp0 - e.hp, attendu, "dégâts selon le temps restant (part %s)" % str(explosion.frac))
		h.proche(explosion.frac, 1.0 - (attente + s.duration + a.castTime) / s.formTime, 0.03, "la part restante est la bonne")
		h.egal(loin.hp, loin.maxHp)
		h.egal(_de(evs, "formEnd")[0].reason, "embrasement", "il met fin à la forme")
		h.egal([p.get("ult"), p.superCharge, p.state], [null, 0.0, "free"])
		h.egal(p.slots, avant, "kit d'origine rendu tel quel")
		h.ok(is_same(g.tuning.combo, g.tuning.weapons.lame.combo))
		h.egal(g.projectiles.size(), 0, "il efface les tirs ennemis de son rayon")
		montants.append(hp0 - e.hp)
	h.ok(montants[0] > montants[1] * 2.0, "tôt : bien plus fort que tard (%s contre %s)" % [str(montants[0]), str(montants[1])])
	var t: Dictionary = D6Data.create_tuning()
	h.ok(t.supers.forme_damne.actions.embrasement.damageMax > t.supers.forme_damne.actions.embrasement.damage)

static func _f_dash(h) -> void:
	var g := _bac(h, "revenant")
	var p: Dictionary = g.player
	var vue_avant: Dictionary = D6Player.move_view(g)
	_forme(h, g)
	var vue: Dictionary = D6Player.move_view(g)
	h.egal([vue.id, vue.kind, vue.maxCharges], [vue_avant.id, "dash", vue_avant.maxCharges], "même déplacement en forme")
	var x0: float = p.x
	var evs: Array = h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	evs.append_array(h.avancer(g, h.ticks(g.tuning.dash.duration) + 2, {"moveX": 1.0}))
	h.egal(_de(evs, "dash").size(), 1)
	h.ok(p.x - x0 >= g.tuning.dash.distance * 0.95, "le dash porte à sa distance")

static func _f_mort(h) -> void:
	var g := _bac(h, "revenant", {}, "dagues")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	p.slots[1].charges = 2.0
	var kit_avant: Array = g.kit.slots.duplicate()
	_forme(h, g)
	p.iframes = 0.0
	h.egal(D6Combat.damage_player(g, 9999.0, {"kind": "imp", "id": 31.0}), true, "il meurt en forme")
	var evs: Array = h.avancer(g, h.ticks(0.3)) # le gel d'impact de la blessure d'abord
	h.egal(_de(evs, "formEnd")[0].reason, "mort")
	h.egal(p.get("ult"), null)
	h.egal(g.kit.slots, kit_avant, "kit d'origine rendu")
	h.ok(is_same(g.tuning.combo, g.tuning.weapons.dagues.combo))
	h.avancer(g, h.ticks(g.tuning.player.deathDelay) + 2)
	h.egal(g.mode, "dead")
	h.egal(D6Run.respawn(g), true)
	h.egal([p.state, p.get("ult"), D6KitSupers.acting(g), g.kit.slots], ["free", null, false, kit_avant], "reprise propre")
	h.proche(p.superCharge, s.startCharge, EPS)
	h.egal(p.slots.map(func(st): return st.cd), [0.0, 0.0, 0.0], "recharges à zéro")
	h.egal(p.slots[1].charges, D6Loadout.max_charges(g, 1), "charges pleines")
	h.ok(is_same(g.tuning.combo, g.tuning.weapons.dagues.combo), "l'arme équipée, pas les griffes")

static func _f_salle(h) -> void:
	var g := _bac(h, "revenant", {"godMode": true})
	var p: Dictionary = g.player
	p.slots[0].cd = 3.0
	var kit_avant: Array = g.kit.slots.duplicate()
	_forme(h, g)
	var cd_garde: float = p.ult.states[0].cd
	h.avancer(g, 1, {"skill2Pressed": true}) # un hurlement en cours de lancer au moment de sortir
	g.events.clear()
	D6Run.enter_floor(g, g.run.floor + 1.0, PORTE)
	h.egal(_de(g.events, "formEnd").size(), 1)
	h.egal(_de(g.events, "formEnd")[0].reason, "etage")
	h.egal([p.get("ult"), p.state, p.superCharge, g.kit.slots], [null, "free", 0.0, kit_avant], "forme terminée, kit rendu")
	h.proche(p.slots[0].cd, cd_garde, EPS, "la recharge d'origine, telle qu'au début de la forme")
	h.ok(cd_garde > 2.0 and cd_garde < 3.0)
	h.ok(is_same(g.tuning.combo, g.tuning.weapons.lame.combo))
	var evs: Array = h.avancer(g, h.ticks(1.0), {"attack": true})
	h.egal(_de(evs, "formHowl").size(), 0, "l'action de forme en cours ne part pas dans la salle suivante")

static func _f_recalcul(h) -> void:
	var g := _bac(h, "revenant")
	var s: Dictionary = g.tuning["super"]
	var p: Dictionary = g.player
	_forme(h, g)
	_benir(g, "rancoeur") # recalcule le build : resolve_kit repasse
	h.egal(g.kit.slots, s.slots, "toujours les actions de forme")
	h.ok(is_same(g.tuning.combo, s.weapon.combo), "toujours les griffes")
	h.egal(D6KitSupers.form_of(g) != null, true)
	# La recharge réduite (Rancœur) vaut aussi pour une action de forme.
	_action(h, g, "hurlement")
	h.ok(p.slots[1].cd <= s.actions.hurlement.cooldown * p.stats.skillCooldownMult and p.stats.skillCooldownMult < 1.0)
	# Changer d'arme pendant la forme : les griffes restent ; à la fin, la NOUVELLE arme est en main.
	g.run.items.arme = D6Profile.starter_weapon(g.tuning, "dagues")
	D6Stats.recompute_stats(g)
	h.ok(is_same(g.tuning.combo, s.weapon.combo), "arme changée en forme : toujours les griffes")
	D6KitSupers.reset(g, "essai")
	h.ok(is_same(g.tuning.combo, g.tuning.weapons.dagues.combo), "fin de forme : l'arme équipée à ce moment-là")
	h.egal(g.kit.slots, KITS.revenant)

static func _f_vide(h) -> void:
	var g := _bac(h, "revenant")
	var s: Dictionary = g.tuning["super"]
	var evs: Array = _forme(h, g)
	evs.append_array(h.avancer(g, h.ticks(s.formTime) + 5, {"attack": true}))
	h.egal(_de(evs, "formEnd").size(), 1)
	h.egal(g.kit.slots, KITS.revenant)
	h.egal(g.player.get("ult"), null)
	h.egal(g.player.superCharge, 0.0, "des coups dans le vide ne remplissent rien")

# ---------------------------------------------------------------- effets qui parlent du « Super »

static func _tests_effets(h) -> void:
	h.test("effet Ripaille (lancer le Super rend des PV) : sur les trois ultimes", func(): _e_ripaille(h))
	h.test("effet Passion brûlante (lancer le Super enflamme autour) : sur les trois ultimes", func(): _e_passion(h))
	h.test("effet Gloire charnelle (dégâts du Super) : fracas, actions de forme, morsures — pas les griffes", func(): _e_gloire_degats(h))
	h.test("effet Gloire charnelle (durée +0,4 s) : geste de la Sentence, durée de la forme, durée de la meute", func(): _e_gloire_duree(h))
	h.test("effet Extase et affixe de la Rage (le Super se charge plus vite) : sur les trois classes", func(): _e_charge(h))
	h.test("effet Ivresse (l'esquive parfaite charge le Super) : hors ultime oui, pendant un ultime non", func(): _e_ivresse(h))
	h.test("effet Trop-plein (le soin en trop charge le Super) : hors ultime oui, pendant un ultime non", func(): _e_trop_plein(h))
	h.test("effet autel de la Clepsydre et repos (jauge pleine, jauge +) : l'ultime de la classe part ensuite", func(): _e_autel_repos(h))
	h.test("effet esquive parfaite de base (perfectDodgeSuper) : ne remplit pas la jauge pendant un ultime", func(): _e_esquive(h))

static func _e_ripaille(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		_benir(g, "ripaille")
		g.player.hp = g.player.maxHp - 40.0
		var hp0: float = g.player.hp
		_lancer(h, g)
		h.egal(g.player.hp, hp0 + _valeur("ripaille"), "%s : soigné au lancer" % class_id)

static func _e_passion(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		_benir(g, "passion_brulante")
		var pres := _cible(g, 150.0, 0.0)
		var loin := _cible(g, 400.0, 0.0)
		_lancer(h, g)
		h.ok(pres.burn > 0.0, "%s : l'ennemi proche brûle" % class_id)
		h.proche(pres.burnDps, _valeur("passion_brulante"), EPS)
		h.egal(loin.burn, 0.0, "%s : pas au-delà du rayon" % class_id)

static func _e_gloire_degats(h) -> void:
	var bonus: float = 1.0 + _valeur("gloire_charnelle") / 100.0
	# Sentence capitale.
	var gb := _bac(h, "bourreau")
	_benir(gb, "gloire_charnelle")
	h.proche(gb.player.stats.superDamageMult, bonus, EPS)
	var eb := _cible(gb, 300.0, 0.0)
	_sentence(h, gb)
	h.egal(eb.maxHp - eb.hp, _attendu(gb, gb.tuning["super"].damage), "le fracas")
	h.ok(_attendu(gb, gb.tuning["super"].damage) > _attendu(gb, gb.tuning["super"].damage, false), "le bonus compte dans l'attendu")
	# Forme : les actions (source « super ») oui, les griffes (coups d'arme) non.
	var gr := _bac(h, "revenant")
	_benir(gr, "gloire_charnelle")
	var s: Dictionary = gr.tuning["super"]
	var er := _cible(gr, 70.0, 0.0)
	_forme(h, gr)
	var evs := _action(h, gr, "hurlement")
	h.egal(_coups(evs, "super")[0].amount, _attendu(gr, s.actions.hurlement.damage), "le hurlement")
	evs = h.avancer(gr, 1, {"attackPressed": true, "aimX": 1.0})
	evs.append_array(h.avancer(gr, h.ticks(0.25)))
	h.egal(_coups(evs, "melee")[0].amount, _attendu(gr, s.weapon.combo[0].damage, false), "les griffes sont des coups d'arme : pas de bonus du Super")
	h.ok(er.hp < er.maxHp)
	# Meute : les morsures.
	var gc := _bac(h, "chasseresse")
	_benir(gc, "gloire_charnelle")
	_cible(gc, 0.0, -110.0)
	_lancer(h, gc, {"aimY": 1.0})
	evs = h.avancer(gc, h.ticks(2.5))
	h.egal(_coups(evs, "ally")[0].amount, _attendu(gc, gc.tuning["super"].biteDamage), "les morsures")

static func _e_gloire_duree(h) -> void:
	var plus: float = D6Boons.boon_def("gloire_charnelle").superDurationBonus
	var gb := _bac(h, "bourreau")
	_benir(gb, "gloire_charnelle")
	_lancer(h, gb)
	h.proche(gb.player.superT, gb.tuning["super"].duration + plus, 2.0 * DT, "Sentence : geste invulnérable allongé")
	var gr := _bac(h, "revenant")
	_benir(gr, "gloire_charnelle")
	_lancer(h, gr)
	h.proche(gr.player.ult.max, gr.tuning["super"].formTime + plus, EPS, "forme allongée")
	var gc := _bac(h, "chasseresse")
	_benir(gc, "gloire_charnelle")
	_lancer(h, gc)
	h.proche(gc.allies[0].lifeMax, gc.tuning["super"].life + plus, EPS, "meute allongée")

## Part de jauge gagnée par UN coup d'arme de 10 PV retirés, pour la classe (jauge partie de zéro).
static func _gain(h, class_id: String, boon, affixe: float) -> float:
	var g := _bac(h, class_id)
	if boon != null:
		_benir(g, boon)
	if affixe != 0.0:
		_talisman(g, "superChargeMult", affixe)
	var e := _cible(g, 60.0, 0.0)
	g.player.superCharge = 0.0
	var hp0: float = e.hp
	D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": 10.0})
	var s: Dictionary = g.tuning["super"]
	var st: Dictionary = g.player.stats
	h.proche(g.player.superCharge, (hp0 - e.hp) / (s.chargeDamage * st.weaponDamage / g.tuning.weaponBase) * st.superChargeMult, EPS, "%s : gain = PV retirés ÷ chargeDamage × superChargeMult" % class_id)
	return g.player.superCharge

static func _e_charge(h) -> void:
	for class_id in ULTIMES:
		var base := _gain(h, class_id, null, 0.0)
		h.ok(base > 0.0)
		h.proche(_gain(h, class_id, "extase", 0.0) / base, 1.0 + _valeur("extase") / 100.0, 1e-3, "%s : Extase" % class_id)
		h.proche(_gain(h, class_id, null, 0.2) / base, 1.2, 1e-3, "%s : affixe de la Rage" % class_id)

## Une esquive parfaite jouée : dash, puis un coup reçu pendant ses i-frames.
static func _esquive(h, g: Dictionary) -> void:
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	g.player.iframes = maxf(g.player.iframes, 0.1)
	g.player.dodgeIframes = maxf(g.player.dodgeIframes, 0.1)
	D6Combat.damage_player(g, 5.0, {"kind": "imp", "id": 4000.0 + g.tick})

static func _e_ivresse(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		_benir(g, "ivresse")
		g.player.superCharge = 0.0
		_esquive(h, g)
		h.proche(g.player.superCharge, g.tuning.dash.perfectDodgeSuper + _valeur("ivresse") / 100.0, EPS, "%s : hors ultime, l'esquive charge" % class_id)
		_lancer(h, g)
		h.avancer(g, 2)
		var avant: float = g.player.superCharge
		var esquives: float = g.telemetry.dodges
		_esquive(h, g)
		h.egal(g.telemetry.dodges, esquives + 1.0, "%s : l'esquive est bien comptée" % class_id)
		h.ok(g.player.superCharge <= avant, "%s : pendant l'ultime, elle ne charge pas (%s → %s)" % [class_id, str(avant), str(g.player.superCharge)])

static func _e_trop_plein(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		_benir(g, "trop_plein")
		g.player.superCharge = 0.0
		D6Combat.heal_player(g, 10.0, false)
		h.proche(g.player.superCharge, 10.0 * _valeur("trop_plein") / 100.0, EPS, "%s : hors ultime, le soin en trop charge" % class_id)
		_lancer(h, g)
		h.avancer(g, 2)
		var avant: float = g.player.superCharge
		D6Combat.heal_player(g, 50.0, false)
		h.ok(g.player.superCharge <= avant, "%s : pendant l'ultime, non" % class_id)

static func _e_autel_repos(h) -> void:
	var repos: float = D6Data.create_tuning().economy.rest.superCharge
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		var p: Dictionary = g.player
		p.superCharge = 0.3
		# Le repos (« Remplir les fioles ») ajoute sa part ; la clepsydre brisée la remplit.
		p.superCharge = minf(1.0, p.superCharge + repos)
		h.proche(p.superCharge, 0.3 + repos, EPS)
		g.choice = null
		D6Run._apply_event(g, {"effect": "hpToSuper", "hp": 5.0})
		h.egal(p.superCharge, 1.0, "%s : clepsydre brisée, jauge pleine" % class_id)
		var evs: Array = h.ultime(g)
		h.egal(_de(evs, "super")[0].get("super"), SORTES[class_id], "%s : son ultime part" % class_id)
		# « Boire le temps » demande une jauge : pendant l'ultime elle vaut ce que dit la minuterie.
		h.egal(D6KitSupers.acting(g), true)

static func _e_esquive(h) -> void:
	for class_id in ULTIMES:
		var g := _bac(h, class_id)
		g.player.superCharge = 0.5
		_esquive(h, g)
		h.proche(g.player.superCharge, 0.5 + g.tuning.dash.perfectDodgeSuper, EPS, "%s : hors ultime, +perfectDodgeSuper" % class_id)
		_lancer(h, g)
		h.avancer(g, 2)
		var avant: float = g.player.superCharge
		_esquive(h, g)
		h.ok(g.player.superCharge <= avant, "%s : pendant l'ultime, rien" % class_id)
