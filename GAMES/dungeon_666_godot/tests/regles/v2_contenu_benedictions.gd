extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_contenu.test.mjs (2/4 : les 14 bénédictions nouvelles,
## famille par famille, et les 4 duos). Outils : v2_contenu.gd.

const C = preload("res://tests/regles/v2_contenu.gd")
const DT := 1.0 / 60.0
const EPS := 1e-9

# ---------------------------------------------------------------- Colère

static func _t_represailles(h) -> void:
	var g: Dictionary = C.arena(h, ["represailles"])
	var e: Dictionary = C.dummy(g, 300.0, 0.0, "brute", 1e6)
	h.egal(C.hit100(g, e), 100.0)
	C.perfect_dodge(h, g)
	var pr: Dictionary = C.proc_of(g, "represailles")
	h.egal(pr.duration, 3.0)
	h.egal(g.player.surge, 3.0)
	h.egal(C.hit100(g, e), D6Js.jround(100.0 * (1.0 + C.V("represailles") / 100.0)))
	C.steps(h, g, h.ticks(3.0) + 2)
	h.egal(g.player.surge, 0.0)
	h.egal(C.hit100(g, e), 100.0, "l'élan retombe")
	# Sans esquive (dash dans le vide), aucun élan.
	var g2: Dictionary = C.arena(h, ["represailles"])
	C.step1(h, g2, {"moveX": 1.0, "dashPressed": true})
	h.egal(g2.player.surge, 0.0)
	C.assert_deterministic(h, ["represailles"])

static func _t_coup_de_sang(h) -> void:
	var g: Dictionary = C.arena(h, ["coup_de_sang"])
	var e: Dictionary = C.dummy(g, 60.0, 0.0, "brute", 1e6)
	var r: Dictionary = C.combo_on(h, g, 1.6, e)
	var finishers: int = r.finishers
	h.ok(finishers >= 2, "finishers portés : %d" % finishers)
	var blasts: Array = r.hits.filter(func(x): return x.get("kind") == "blast")
	h.egal(blasts.size(), finishers, "une explosion par dernier coup porté")
	for b in blasts:
		h.egal(b.amount, C.V("coup_de_sang"))
	h.egal(g.events.filter(func(ev): return ev.type == "hazard" and ev.get("kind") == "sinBlast").size(), finishers)
	h.egal(C.proc_of(g, "coup_de_sang").radius, 70.0)
	C.assert_deterministic(h, ["coup_de_sang"])

# ---------------------------------------------------------------- Paresse

static func _t_baillement(h) -> void:
	var g: Dictionary = C.arena(h, ["baillement"])
	var pr: Dictionary = C.proc_of(g, "baillement")
	var near: Dictionary = C.dummy(g, 0.0, 100.0, "brute", 1000.0)
	var far: Dictionary = C.dummy(g, 0.0, pr.radius + 200.0, "brute", 1000.0)
	C.perfect_dodge(h, g)
	h.egal(near.hp, 1000.0 - C.V("baillement"))
	h.egal(near.chill, 3.0)
	h.egal(near.chillMult, 0.5)
	h.egal(far.hp, 1000.0, "hors du rayon : rien")
	h.egal(far.chill, 0.0)
	h.egal(C.events(g, "dashNova").size(), 1, "l'onde est montrée")
	C.assert_deterministic(h, ["baillement"])

static func _t_mur_du_sommeil(h) -> void:
	var base: Dictionary = C.arena(h)
	var e0: Dictionary = C.dummy(base, 0.0, 0.0, "imp", 500.0)
	h.ok(C.slam(h, base, e0))
	h.ok(e0.stun <= base.tuning.wallSlam.stun and e0.stun > 0.0)
	var g: Dictionary = C.arena(h, ["mur_du_sommeil"])
	var e: Dictionary = C.dummy(g, 0.0, 0.0, "imp", 500.0)
	h.ok(C.slam(h, g, e))
	var v: float = C.V("mur_du_sommeil")
	h.ok(e.stun > v - 3.0 * DT and e.stun <= v, "sonné %s s" % e.stun)
	h.egal(e.state, "stunned")
	h.ok(v > g.tuning.wallSlam.stun)
	C.assert_deterministic(h, ["mur_du_sommeil"])

# ---------------------------------------------------------------- Avarice

static func _t_prime_de_risque(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 21.0, "startFloor": 3.0})
	C.give(h, g, "prime_de_risque")
	g.events.clear()
	C.clear_room(h, g)
	var paid: Array = C.events(g, "gold")
	h.egal(paid.size(), 1)
	if paid.size() > 0:
		h.egal(paid[0].amount, C.V("prime_de_risque"))
	h.egal(g.run.gold, C.V("prime_de_risque"))
	var g2: Dictionary = D6Game.create_game({"seed": 21.0, "startFloor": 3.0})
	C.give(h, g2, "prime_de_risque")
	h.egal(D6Combat.damage_player(g2, 5.0, {"kind": "test", "id": 1.0}), true)
	g2.events.clear()
	C.clear_room(h, g2)
	h.egal(C.events(g2, "gold").size(), 0, "blessé dans la salle : pas de prime")
	h.egal(g2.run.gold, 0.0)
	C.assert_deterministic(h, ["prime_de_risque"])

static func _t_tresor_de_guerre(h) -> void:
	var g: Dictionary = C.arena(h, ["tresor_de_guerre"])
	var pr: Dictionary = C.proc_of(g, "tresor_de_guerre")
	var e: Dictionary = C.dummy(g, 300.0, 0.0, "brute", 1e6)
	var v: float = C.V("tresor_de_guerre")
	h.egal([pr.per, pr.cap], [25.0, 5.0])
	g.run.gold = 24.0
	h.egal(C.hit100(g, e), 100.0)
	g.run.gold = 60.0
	h.egal(C.hit100(g, e), 100.0 + 2.0 * v)
	g.run.gold = 5000.0
	h.egal(C.hit100(g, e), 100.0 + 5.0 * v, "plafond")
	C.assert_deterministic(h, ["tresor_de_guerre"])

# ---------------------------------------------------------------- Gourmandise

static func _t_bouchee_double(h) -> void:
	var g: Dictionary = C.arena(h, ["bouchee_double"])
	var e: Dictionary = C.dummy(g, 60.0, 0.0, "brute", 1e6)
	g.player.hp = g.player.maxHp - 60.0
	var hp0: float = g.player.hp
	var finishers: int = C.combo_on(h, g, 1.6, e).finishers
	h.ok(finishers >= 2)
	h.ok(absf(g.player.hp - hp0 - finishers * C.V("bouchee_double")) < EPS, "soigné de %s pour %d derniers coups" % [g.player.hp - hp0, finishers])
	h.egal(C.events(g, "heal").size(), finishers)
	h.egal(D6Boons.boon_def("bouchee_double").slot, "attack", "emplacement d'attaque : un choix contre Sang dévoré")
	C.assert_deterministic(h, ["bouchee_double"])

static func _t_ripaille(h) -> void:
	var g: Dictionary = C.arena(h, ["ripaille"])
	g.player.hp = g.player.maxHp - 40.0
	var hp0: float = g.player.hp
	g.player.superCharge = 1.0
	C.ultime(h, g)
	h.egal(g.player.state, "super")
	h.egal(g.player.hp, hp0 + C.V("ripaille"))
	var heals: Array = C.events(g, "heal")
	h.egal(heals[0].amount if heals.size() > 0 else null, C.V("ripaille"))
	C.assert_deterministic(h, ["ripaille"])

# ---------------------------------------------------------------- Luxure

static func _t_baiser_vole(h) -> void:
	var g: Dictionary = C.arena(h, ["baiser_vole"])
	var e: Dictionary = C.dummy(g, 200.0, 0.0, "brute", 1e6)
	C.hit100(g, e, "melee")
	h.egal(e.vuln, 0.0, "un coup ordinaire ne marque pas")
	C.dash_strike(h, g)
	var struck: Array = C.events(g, "hit").filter(func(x): return x.get("kind") == "strike")
	h.egal(struck.size(), 1, "la frappe de dash a porté")
	h.ok(e.vuln > 4.0 - 0.5 and e.vuln <= 4.0, "vulnérable encore %s s" % e.vuln)
	h.ok(absf(e.vulnMult - C.V("baiser_vole") / 100.0) < EPS)
	h.egal(C.hit100(g, e), D6Js.jround(100.0 * (1.0 + C.V("baiser_vole") / 100.0)))
	h.egal(D6Boons.boon_def("baiser_vole").slot, "dash")
	C.assert_deterministic(h, ["baiser_vole"])

static func _t_ivresse(h) -> void:
	var g: Dictionary = C.arena(h, ["ivresse"])
	g.player.superCharge = 0.0
	C.perfect_dodge(h, g)
	h.ok(absf(g.player.superCharge - (g.tuning.dash.perfectDodgeSuper + C.V("ivresse") / 100.0)) < EPS, "jauge %s" % g.player.superCharge)
	var g2: Dictionary = C.arena(h)
	g2.player.superCharge = 0.0
	C.perfect_dodge(h, g2)
	h.ok(absf(g2.player.superCharge - g2.tuning.dash.perfectDodgeSuper) < EPS)
	C.assert_deterministic(h, ["ivresse"])

# ---------------------------------------------------------------- Envie

static func _t_eclair_de_depit(h) -> void:
	var g: Dictionary = C.arena(h, ["eclair_de_depit"])
	var pr: Dictionary = C.proc_of(g, "eclair_de_depit")
	var foes: Array = [60.0, 120.0, 180.0, 240.0].map(func(dx): return C.dummy(g, dx, 0.0, "imp", 1000.0))
	var out: Dictionary = C.dummy(g, 0.0, pr["range"] + 300.0, "imp", 1000.0)
	C.step1(h, g, {"moveX": -1.0, "dashPressed": true})
	h.egal(pr.bounces, 3.0)
	var v: float = C.V("eclair_de_depit")
	h.egal(foes.map(func(e): return e.hp), [1000.0 - v, 1000.0 - v, 1000.0 - v, 1000.0])
	h.egal(out.hp, 1000.0, "hors de portée")
	h.egal(C.events(g, "chain").size(), 3)
	h.egal(D6Boons.boon_def("eclair_de_depit").slot, "dash", "emplacement de dash : un choix contre Pas de braise")
	C.assert_deterministic(h, ["eclair_de_depit"])

static func _t_mauvais_oeil(h) -> void:
	var g: Dictionary = C.arena(h, ["mauvais_oeil"])
	var pr: Dictionary = C.proc_of(g, "mauvais_oeil")
	var victim: Dictionary = C.dummy(g, 100.0, 0.0, "imp", 5.0)
	var a: Dictionary = C.dummy(g, 160.0, 0.0, "imp", 1000.0)
	var b: Dictionary = C.dummy(g, 220.0, 0.0, "imp", 1000.0)
	var c: Dictionary = C.dummy(g, 280.0, 0.0, "imp", 1000.0)
	C.hit100(g, victim)
	h.egal(victim.dead, true)
	h.egal(pr.bounces, 2.0)
	var v: float = C.V("mauvais_oeil")
	h.egal([a.hp, b.hp, c.hp], [1000.0 - v, 1000.0 - v, 1000.0])
	h.egal(C.events(g, "chain").size(), 2)
	# Réaction en chaîne bornée : un éclair qui tue relance un éclair, jamais sans fin.
	var g2: Dictionary = C.arena(h, ["mauvais_oeil"])
	var pack: Array = [100.0, 150.0, 200.0, 250.0, 300.0].map(func(dx): return C.dummy(g2, dx, 0.0, "imp", 5.0))
	C.hit100(g2, pack[0])
	h.ok(pack.all(func(e): return e.dead), "la meute fragile tombe en cascade")
	C.assert_deterministic(h, ["mauvais_oeil"])

# ---------------------------------------------------------------- Orgueil

static func _t_invaincu(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 23.0, "startFloor": 3.0})
	g.tuning.combat.critChance = 0.0
	C.give(h, g, "invaincu")
	var v: float = C.V("invaincu")
	h.egal(g.run.streak, 0.0)
	C.clear_room(h, g)
	h.egal(g.run.streak, 1.0)
	var e: Dictionary = D6Enemies.create_enemy(g, "brute", 300.0, 300.0, {"spawnT": 0.0})
	e.maxHp = 1e6
	e.hp = 1e6
	h.egal(C.hit100(g, e), 100.0 + v)
	g.run.streak = 40.0
	h.egal(C.hit100(g, e), 100.0 + C.proc_of(g, "invaincu").cap * v, "plafond à 5 salles")
	h.egal(C.proc_of(g, "invaincu").cap, 5.0)
	g.player.iframes = 0.0
	h.egal(D6Combat.damage_player(g, 3.0, {"kind": "test", "id": 2.0}), true)
	h.egal(g.run.streak, 0.0)
	h.egal(C.hit100(g, e), 100.0, "blessé : l'orgueil retombe")
	# Une salle où le héros a été blessé n'allonge pas la série.
	var g2: Dictionary = D6Game.create_game({"seed": 23.0, "startFloor": 3.0})
	D6Combat.damage_player(g2, 3.0, {"kind": "test", "id": 2.0})
	C.clear_room(h, g2)
	h.egal(g2.run.streak, 0.0)
	C.assert_deterministic(h, ["invaincu"])

static func _t_mepris(h) -> void:
	var g: Dictionary = C.arena(h, ["mepris"])
	h.ok(absf(C.proc_of(g, "mepris").value - C.V("mepris") / 100.0) < EPS)
	# Épique au niveau 2 : 90 % × 1,5 > 100 % — tout coup sur un ennemi sonné est critique.
	var g2: Dictionary = C.arena(h)
	D6Boons.add_boon(g2.run, {"id": "mepris", "rarity": "epique"})
	D6Boons.add_boon(g2.run, {"id": "mepris", "rarity": "epique"})
	D6Stats.recompute_stats(g2)
	h.ok(C.proc_of(g2, "mepris").value >= 1.0)
	var e: Dictionary = C.dummy(g2, 300.0, 0.0, "brute", 1e6)
	for i in 20:
		D6Combat.damage_enemy(g2, e, {"kind": "melee", "amount": 10.0, "canCrit": true})
	h.ok(C.events(g2, "hit").all(func(ev): return not D6Js.truthy(ev.get("crit"))), "debout : jamais critique (chance de base nulle dans ce test)")
	g2.events.clear()
	e.stun = 5.0
	for i in 20:
		D6Combat.damage_enemy(g2, e, {"kind": "melee", "amount": 10.0, "canCrit": true})
	h.ok(C.events(g2, "hit").all(func(ev): return D6Js.truthy(ev.get("crit"))), "sonné : toujours critique")
	C.assert_deterministic(h, ["mepris"])

# ---------------------------------------------------------------- duos

static func _t_passion_brulante(h) -> void:
	var g: Dictionary = C.arena(h, ["passion_brulante"])
	var pr: Dictionary = C.proc_of(g, "passion_brulante")
	var near: Dictionary = C.dummy(g, 150.0, 0.0, "brute", 1e6)
	var far: Dictionary = C.dummy(g, pr.radius + 200.0, 0.0, "brute", 1e6)
	g.player.superCharge = 1.0
	C.ultime(h, g)
	h.ok(near.burn > 4.0 - 2.0 * DT and near.burn <= 4.0, "en feu encore %s s" % near.burn)
	h.egal(pr.duration, 4.0)
	h.egal(near.burnDps, C.V("passion_brulante"))
	h.egal(far.burn, 0.0)
	h.egal(D6Boons.boon_def("passion_brulante").families, ["colere", "luxure"])
	C.assert_deterministic(h, ["passion_brulante"])

static func _t_faire_les_poches(h) -> void:
	var g: Dictionary = C.arena(h, ["faire_les_poches"])
	var e: Dictionary = C.dummy(g, 0.0, 0.0, "imp", 500.0)
	g.events.clear()
	h.ok(C.slam(h, g, e))
	h.egal(g.run.gold, C.V("faire_les_poches"))
	var paid: Array = C.events(g, "gold")
	h.egal(paid[0].amount if paid.size() > 0 else null, C.V("faire_les_poches"))
	h.egal(C.V("faire_les_poches", "epique"), C.V("faire_les_poches"), "montant fixe : l'or reste un entier annoncé")
	C.assert_deterministic(h, ["faire_les_poches"])

static func _t_trop_plein(h) -> void:
	var g: Dictionary = C.arena(h, ["trop_plein"])
	var p: Dictionary = g.player
	p.superCharge = 0.0
	p.hp = p.maxHp - 4.0
	D6Combat.heal_player(g, 14.0, true)
	h.egal(p.hp, p.maxHp)
	h.ok(absf(p.superCharge - 10.0 * (C.V("trop_plein") / 100.0)) < EPS, "jauge %s pour 10 PV de trop" % p.superCharge)
	p.hp = p.maxHp - 20.0
	D6Combat.heal_player(g, 10.0, true)
	h.ok(absf(p.superCharge - 10.0 * (C.V("trop_plein") / 100.0)) < EPS, "un soin qui ne déborde pas ne charge rien")
	# Jamais pendant le Super : il ne se recharge pas lui-même. (Combat V3, étape 2 : la jauge de la
	# Forme du Damné est sa minuterie ; le soin en trop ne doit pas la faire monter.)
	p.superCharge = 1.0
	C.ultime(h, g)
	var pendant: float = p.superCharge
	h.ok(pendant < 1.0, "la jauge n'est plus pleine une fois l'ultime lancé")
	D6Combat.heal_player(g, 500.0, true)
	h.egal(p.superCharge, pendant)
	C.assert_deterministic(h, ["trop_plein", "festin"])

static func _t_foudre_du_dedain(h) -> void:
	var g: Dictionary = C.arena(h, ["eclair_de_depit", "foudre_du_dedain"])
	var limit: float = C.V("foudre_du_dedain") / 100.0
	var weak: Dictionary = C.dummy(g, 60.0, 0.0, "brute", 1000.0)
	weak.hp = floorf(1000.0 * limit) - 1.0 + C.V("eclair_de_depit") # sous le seuil après l'éclair, loin de mourir des dégâts
	var strong: Dictionary = C.dummy(g, 120.0, 0.0, "brute", 1000.0)
	C.step1(h, g, {"moveX": -1.0, "dashPressed": true})
	h.egal(weak.dead, true, "achevé")
	h.egal(strong.dead, false)
	h.egal(strong.hp, 1000.0 - C.V("eclair_de_depit"))
	var g2: Dictionary = C.arena(h, ["eclair_de_depit", "foudre_du_dedain"])
	var boss: Dictionary = D6Enemies.create_enemy(g2, "gardien", g2.player.x + 80.0, g2.player.y, {"boss": true, "spawnT": 0.0})
	boss.hp = boss.maxHp * 0.05
	C.step1(h, g2, {"moveX": -1.0, "dashPressed": true})
	h.egal(boss.dead, false, "un Gardien ne s'achève pas")
	C.assert_deterministic(h, ["jalousie", "foudre_du_dedain"])

# ---------------------------------------------------------------- les tests

static func tests(h) -> void:
	h.test("Représailles (Colère) : une esquive parfaite donne +{v} % de dégâts pendant 3 s, puis plus rien", func(): _t_represailles(h))
	h.test("Coup de sang (Colère) : le dernier coup du combo — et lui seul — fait exploser la cible pour {v} dégâts", func(): _t_coup_de_sang(h))
	h.test("Bâillement (Paresse) : une esquive parfaite blesse de {v} et ralentit de 50 % pendant 3 s autour du héros", func(): _t_baillement(h))
	h.test("Mur du sommeil (Paresse) : un ennemi projeté contre un mur reste sonné {v} s (0,45 s sans elle)", func(): _t_mur_du_sommeil(h))
	h.test("Prime de risque (Avarice) : salle nettoyée sans être touché = +{v} or ; touché, rien", func(): _t_prime_de_risque(h))
	h.test("Trésor de guerre (Avarice) : +{v} % de dégâts par tranche de 25 or en bourse, 5 tranches au plus", func(): _t_tresor_de_guerre(h))
	h.test("Bouchée double (Gourmandise) : le dernier coup du combo rend {v} PV par ennemi touché", func(): _t_bouchee_double(h))
	h.test("Ripaille (Gourmandise) : lancer le Super rend {v} PV", func(): _t_ripaille(h))
	h.test("Baiser volé (Luxure) : la frappe de dash — pas un coup ordinaire — rend vulnérable de {v} % pendant 4 s", func(): _t_baiser_vole(h))
	h.test("Ivresse (Luxure) : une esquive parfaite charge le Super de {v} % en plus des 6 % de base", func(): _t_ivresse(h))
	h.test("Éclair de dépit (Envie) : chaque dash lance un éclair de {v} dégâts sur 3 ennemis au plus, de proche en proche", func(): _t_eclair_de_depit(h))
	h.test("Mauvais œil (Envie) : chaque ennemi tué lance un éclair de {v} dégâts, 2 rebonds", func(): _t_mauvais_oeil(h))
	h.test("Invaincu (Orgueil) : +{v} % de dégâts par salle nettoyée sans être touché (5 au plus) ; une blessure remet à zéro", func(): _t_invaincu(h))
	h.test("Mépris (Orgueil) : +{v} % de chances de critique contre un ennemi sonné, rien contre les autres", func(): _t_mepris(h))
	h.test("duo Passion brûlante (Colère + Luxure) : lancer le Super enflamme les ennemis proches, {v} dégâts/s pendant 4 s", func(): _t_passion_brulante(h))
	h.test("duo Faire les poches (Paresse + Avarice) : un ennemi projeté contre un mur lâche {v} or", func(): _t_faire_les_poches(h))
	h.test("duo Trop-plein (Gourmandise + Orgueil) : chaque PV soigné au-delà du maximum charge le Super de {v} %", func(): _t_trop_plein(h))
	h.test("duo Foudre du dédain (Envie + Orgueil) : un éclair achève un ennemi sous {v} % de PV, jamais un Gardien", func(): _t_foudre_du_dedain(h))
