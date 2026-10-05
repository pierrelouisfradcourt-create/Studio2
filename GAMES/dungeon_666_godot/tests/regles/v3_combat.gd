extends RefCounted
## COMBAT V3, étape 1 « Commandes » (design/COMBAT_V3.md) — les règles :
##   - l'ULTIME part en GARDANT l'attaque appuyée quand la jauge est pleine (super.holdTime) —
##     seulement si l'APPUI A COMMENCÉ jauge pleine (étape 1 bis : relâcher et rappuyer) ;
##   - TROIS emplacements d'action : compétences (chacune sa recharge) et gadgets (chacun ses charges) ;
##   - le profil porte `loadout.slots` (schéma 4), une sauvegarde du schéma 3 est migrée ;
##   - l'affichage lit D6Loadout.slot_view ; les événements d'un emplacement portent `slot` ;
##   - bénédictions, objets, autels et repos qui parlent de « la compétence » ou « du gadget »
##     valent pour TOUTE action équipée de cette sorte.
## Les nombres attendus sont lus dans les données (jamais recopiés), sauf la durée du maintien,
## dite une fois ici comme dans la demande : 0,4 s.

const DT := 1.0 / 60.0
const EPS := 1e-6
const TOUTES := ["classes", "weapons", "skills", "gadgets"]
const PORTE := {"reward": "boon", "family": "colere"}

## Un VRAI profil de joueur au schéma 3 (relevé le 2026-10-04, réduit : équipement et coffre
## abrégés, aucun nom de personne). C'est le cas que la migration ne doit jamais abîmer.
const PROFIL_SCHEMA_3 := {
	"schema": 3.0, "bestFloor": 126.0, "checkpoints": [1.0, 19.0, 37.0, 55.0, 73.0, 91.0, 109.0, 127.0],
	"souls": 1183.0, "gold": 5047.0, "itemSeq": 29.0,
	"unlocked": {
		"classes": ["revenant", "bourreau", "chasseresse"], "weapons": ["lame", "hache", "arc", "dagues", "marteau"],
		"skills": ["lance", "bond", "volee", "chaine"], "gadgets": ["nova", "cri", "piege", "bombe"],
	},
	"upgrades": {"arsenal": 1.0, "avidite": 2.0, "celerite": 3.0, "ferocite": 4.0, "fortune": 3.0, "vitalite": 5.0},
	"loadout": {"classId": "bourreau", "gadgetId": "cri", "skillId": "bond"},
	"equipment": {
		"arme": {"slot": "arme", "weaponType": "hache", "rarity": "rare", "name": "Couperet acéré du Bélier", "level": 115.0, "id": 1224.0, "uid": "i7", "affixes": [{"stat": "critChance", "value": 0.062, "format": "pct", "prefix": "acéré", "suffix": "de Précision"}], "power": null, "base": {"damage": 77.7}, "score": 44.52},
		"armure": {"slot": "armure", "rarity": "magique", "name": "Haubert clouté du Vent", "level": 94.0, "id": 155.0, "uid": "i9", "affixes": [], "power": null, "base": {"hp": 336.0}, "score": 29.6},
		"talisman": {"slot": "talisman", "rarity": "rare", "name": "Amulette chanceux de l'Érudit", "level": 66.0, "id": 2104.0, "uid": "i18", "affixes": [{"stat": "skillCooldownMult", "value": -0.1, "format": "pctNeg", "prefix": "savant", "suffix": "de l'Érudit"}], "power": null, "base": {}, "score": 2.63},
	},
	"stash": [
		{"slot": "arme", "weaponType": "lame", "rarity": "commun", "name": "Lame du Revenant", "level": 1.0, "uid": "i1", "affixes": [], "power": null, "base": {"damage": 10.0}, "score": 0.0},
		{"slot": "arme", "weaponType": "marteau", "rarity": "commun", "name": "Maillet des damnés", "level": 1.0, "uid": "i21", "affixes": [], "power": null, "base": {"damage": 13.0}, "score": 0.0},
	],
	"guardians": {"cerbere": 3.0, "colosse": 1.0, "gardien": 2.0, "minos": 2.0},
	"stats": {"deaths": 3.0, "guardianKills": 8.0, "kills": 1598.0, "runs": 7.0},
}
## Ce que la migration doit rendre tel quel (tout, sauf le loadout et le numéro de schéma).
const INTACTS := ["bestFloor", "checkpoints", "souls", "gold", "itemSeq", "unlocked", "upgrades", "equipment", "stash", "guardians", "stats"]

static func tests(h) -> void:
	_tests_ultime(h)
	_tests_emplacements(h)
	_tests_profil(h)
	_tests_lecture(h)
	_tests_effets(h)

# ---------------------------------------------------------------- outillage

## Profil permanent : tout débloqué, la classe et les trois emplacements demandés.
static func _meta(class_id: String, slots: Array) -> Dictionary:
	var t: Dictionary = D6Data.create_tuning()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in TOUTES:
		m.unlocked[k] = t[k].keys()
	m.loadout = {"classId": class_id, "slots": slots}
	m.equipment.arme = D6Profile.starter_weapon(t, t.classes[class_id].weapons[0])
	m.equipment.arme.uid = "i9000"
	return m

## Salle vidée, héros au centre, jamais de critique (les montants attendus sont exacts).
static func _bac(h, class_id: String, slots: Array, opts: Dictionary = {}) -> Dictionary:
	var o := {"seed": 7.0, "meta": _meta(class_id, slots)}
	o.merge(opts, true)
	var g: Dictionary = h.bac_a_sable(o)
	g.tuning.combat.critChance = 0.0
	return g

## Ennemi d'essai : ne riposte pas, ne bouge pas, increvable par défaut.
static func _cible(g: Dictionary, dx: float, dy: float, kind: String = "brute", hp: float = 50000.0) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.cooldown = 999.0
	e.maxHp = hp
	e.hp = hp
	e.mass = 1000.0
	e.stun = 999.0
	return e

static func _de(evs: Array, type: String) -> Array:
	return evs.filter(func(ev): return ev.type == type)

static func _coups(evs: Array, kind: String) -> Array:
	return evs.filter(func(ev): return ev.type == "hit" and ev.get("kind") == kind)

static func _zones(g: Dictionary, kind: String) -> Array:
	return D6KitZones.zones_of(g, kind)

## Les charges des trois emplacements, pour comparer d'un coup.
static func _charges(g: Dictionary) -> Array:
	return g.player.slots.map(func(s): return s.charges)

static func _recharges(g: Dictionary) -> Array:
	return g.player.slots.map(func(s): return s.cd)

# ---------------------------------------------------------------- ultime par maintien

static func _tests_ultime(h) -> void:
	h.test("ultime : jauge pleine, l'attaque gardée appuyée le lance à holdTime (0,4 s), pas avant", func(): _u_part(h))
	h.test("ultime : relâcher avant holdTime annule, superHold repart de zéro", func(): _u_relache(h))
	h.test("ultime : des appuis brefs, même répétés, ne le lancent jamais", func(): _u_appuis_brefs(h))
	h.test("ultime : glisser pour viser puis relâcher frappe, sans jamais le lancer", func(): _u_glisser(h))
	h.test("ultime : jauge non pleine, maintenir l'attaque enchaîne le combo comme avant", func(): _u_jauge_basse(h))
	h.test("ultime : jauge pleine, le premier appui donne son coup, il finit, aucun autre ne part pendant l'armement", func(): _u_combo_arme(h))
	h.test("ultime : la jauge qui se remplit PENDANT le maintien ne l'arme PAS ; le combo continue", func(): _u_remplie_en_tenant(h))
	h.test("ultime : après une jauge remplie en tenant, relâcher puis rappuyer l'arme et le lance à holdTime", func(): _u_relacher_rappuyer(h))
	h.test("ultime : l'appui qui vient de le lancer n'en arme pas un second, même jauge de nouveau pleine", func(): _u_pas_deux_fois(h))
	h.test("ultime : un front d'attaque répété sans relâcher (appui tenu depuis avant) n'arme rien", func(): _u_front_sans_relacher(h))
	h.test("ultime : holdTime est un réglage lu dans les données, le même pour les trois Supers", func(): _u_reglage(h))
	h.test("ultime : chaque classe lance SON Super par le maintien", func(): _u_par_classe(h))

static func _u_part(h) -> void:
	# Étape 2 : le geste du maintien se juge sur la Colère lancée directement (les trois ultimes de
	# classe ont leurs tests dans v3_ultimes.gd, « chaque classe lance le SIEN par le maintien »).
	var g: Dictionary = h.bac_a_sable({"seed": 3.0, "tuning": {"classes": {"revenant": {"super": "colere"}}}})
	var need: float = g.tuning["super"].holdTime
	h.egal(need, 0.4, "durée du maintien demandée")
	g.player.superCharge = 1.0
	var evs: Array = h.avancer(g, h.ticks(need) - 2, {"attack": true})
	h.different(g.player.state, "super", "pas encore parti deux pas avant holdTime")
	h.ok(g.player.superHold > 0.0 and g.player.superHold < need, "l'armement monte (%s)" % g.player.superHold)
	h.egal(_de(evs, "super").size(), 0)
	h.egal(g.player.superCharge, 1.0, "la jauge reste pleine pendant l'armement")
	evs = h.avancer(g, 4, {"attack": true})
	h.egal(_de(evs, "super").size(), 1, "il part à holdTime")
	h.egal(_de(evs, "super")[0].get("super") if not _de(evs, "super").is_empty() else null, "colere", "le Super de la classe, inchangé")
	h.egal(g.player.state, "super")
	h.egal(g.player.superCharge, 0.0)
	h.egal(g.player.superHold, 0.0)
	h.egal(g.telemetry.superUses, 1.0)

static func _u_relache(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.player.superCharge = 1.0
	h.avancer(g, 15, {"attack": true})
	h.ok(g.player.superHold > 0.0)
	h.avancer(g, 1)
	h.egal(g.player.superHold, 0.0, "relâché : l'armement retombe à zéro")
	h.avancer(g, 15, {"attack": true})
	h.different(g.player.state, "super", "15 + 15 pas séparés par un relâcher ne font pas un maintien")
	h.egal(g.telemetry.superUses, 0.0)
	h.egal(g.player.superCharge, 1.0, "la jauge n'est pas dépensée")
	h.avancer(g, 12, {"attack": true})
	h.egal(g.player.state, "super", "le second maintien, tenu jusqu'au bout, le lance")

static func _u_appuis_brefs(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.player.superCharge = 1.0
	# Trois pas tenus, trois pas lâchés, pendant 3 s : un joueur qui tape vite.
	var evs: Array = h.avancer(g, h.ticks(3.0), func(i): return {"attackPressed": i % 6 == 0, "attack": i % 6 < 3})
	h.egal(_de(evs, "super").size(), 0, "jamais d'ultime")
	h.egal(g.player.superCharge, 1.0)
	h.ok(_de(evs, "attackStart").size() >= 6, "les coups partent (%d)" % _de(evs, "attackStart").size())

static func _u_glisser(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.player.superCharge = 1.0
	# Le pouce glisse une seconde (visée, sans attaque), puis relâche : un coup dans la direction visée.
	var evs: Array = h.avancer(g, h.ticks(1.0), {"aimX": 1.0, "aimY": 0.0})
	h.egal(g.player.superHold, 0.0, "viser n'arme rien")
	evs.append_array(h.avancer(g, 1, {"attackPressed": true, "aimX": 1.0, "aimY": 0.0}))
	h.egal(g.player.state, "attack")
	h.ok(g.player.attack != null and g.player.attack.dirX > 0.99, "le coup part où l'on visait")
	evs.append_array(h.avancer(g, h.ticks(1.0)))
	h.egal(_de(evs, "super").size(), 0, "jamais d'ultime")
	h.egal(_de(evs, "attackStart").size(), 1, "un seul coup")
	h.egal(g.player.superCharge, 1.0)

static func _u_jauge_basse(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.player.superCharge = 0.5
	var tenu := true
	var evs: Array = []
	for i in h.ticks(1.5):
		evs.append_array(h.avancer(g, 1, {"attack": true}))
		tenu = tenu and g.player.superHold == 0.0
	h.ok(tenu, "jauge non pleine : aucun armement")
	h.egal(_de(evs, "super").size(), 0)
	h.ok(_de(evs, "attackStart").size() >= 5, "le combo s'enchaîne (%d coups en 1,5 s)" % _de(evs, "attackStart").size())
	h.egal(g.player.superCharge, 0.5)

static func _u_combo_arme(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.player.superCharge = 1.0
	var evs: Array = []
	var libre_en_armant := false
	for i in h.ticks(g.tuning["super"].holdTime) + 4:
		evs.append_array(h.avancer(g, 1, {"attack": true, "attackPressed": i == 0}))
		libre_en_armant = libre_en_armant or (g.player.state == "free" and g.player.superHold > 0.0)
		if g.player.state == "super":
			break
	h.egal(g.player.state, "super")
	h.egal(_de(evs, "attackStart").size(), 1, "un coup normal au premier appui, aucun autre pendant l'armement")
	h.egal(_de(evs, "swing").size(), 1, "ce coup se joue (il frappe)")
	h.ok(libre_en_armant, "le coup de la Lame finit avant que l'ultime parte")
	h.egal(_de(evs, "cancel").size(), 0, "rien n'a été coupé")

static func _u_remplie_en_tenant(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.player.superCharge = 0.5
	h.avancer(g, 30, {"attack": true})
	h.egal(g.player.superHold, 0.0)
	g.player.superCharge = 1.0 # la jauge se remplit (un coup qui porte) : le joueur tient toujours
	# Il garde le bouton enfoncé trois secondes de plus : jamais d'armement, jamais d'ultime.
	var evs: Array = []
	var arme := false
	for i in h.ticks(3.0):
		evs.append_array(h.avancer(g, 1, {"attack": true}))
		arme = arme or g.player.superHold > 0.0 or g.player.superArm
	h.ok(not arme, "un appui commencé avant que la jauge soit pleine n'arme jamais")
	h.egal(_de(evs, "super").size(), 0, "aucun ultime en gardant l'attaque enfoncée")
	h.egal(g.telemetry.superUses, 0.0)
	h.egal(g.player.superCharge, 1.0, "la jauge reste pleine")
	h.ok(_de(evs, "attackStart").size() >= 10, "le combo continue de s'enchaîner (%d coups en 3 s)" % _de(evs, "attackStart").size())

static func _u_relacher_rappuyer(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	var need: float = g.tuning["super"].holdTime
	g.player.superCharge = 0.5
	h.avancer(g, 30, {"attack": true})
	g.player.superCharge = 1.0
	h.avancer(g, 30, {"attack": true})
	h.different(g.player.state, "super", "tenu depuis avant : rien")
	h.avancer(g, 1) # il relâche un pas…
	h.egal(g.player.superArm, false)
	var pas := 0
	while pas < h.ticks(need) + 30 and g.player.state != "super":
		h.avancer(g, 1, {"attack": true}) # … et rappuie, jauge pleine
		pas += 1
		if pas == 1:
			h.egal(g.player.superArm, true, "l'appui commencé jauge pleine arme")
	h.egal(g.player.state, "super", "l'ultime part")
	h.ok(pas >= h.ticks(need) - 1, "… après un maintien entier compté depuis le nouvel appui (%d pas)" % pas)
	h.egal(g.telemetry.superUses, 1.0)

static func _u_pas_deux_fois(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0, "tuning": {"classes": {"revenant": {"super": "colere"}}}}) # étape 2 : la Colère, lancée directement
	g.player.superCharge = 1.0
	h.ultime(g)
	h.egal(g.player.state, "super")
	h.egal(g.player.superArm, false, "l'appui a servi")
	# Il garde le bouton enfoncé pendant et après l'ultime ; la jauge se remplit de nouveau.
	h.avancer(g, h.ticks(g.tuning["super"].duration) + 5, {"attack": true})
	h.different(g.player.state, "super", "le premier ultime est fini")
	g.player.superCharge = 1.0
	var evs: Array = h.avancer(g, h.ticks(2.0), {"attack": true})
	h.egal(_de(evs, "super").size(), 0, "pas de second ultime sans relâcher")
	h.egal(g.telemetry.superUses, 1.0)
	h.avancer(g, 1)
	evs = h.ultime(g)
	h.egal(_de(evs, "super").size(), 1, "relâcher puis rappuyer : le second part")

static func _u_front_sans_relacher(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 3.0})
	g.player.superCharge = 0.5
	h.avancer(g, 10, {"attack": true})
	g.player.superCharge = 1.0
	# Le bouton reste tenu ; un « front » arrive quand même à chaque pas (autre doigt, répétition clavier).
	var evs: Array = h.avancer(g, h.ticks(1.5), {"attack": true, "attackPressed": true})
	h.egal(_de(evs, "super").size(), 0, "seul un appui qui COMMENCE (bouton relâché avant) arme")
	h.egal(g.player.superHold, 0.0)

static func _u_reglage(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	for id in t.supers:
		h.egal(t.supers[id].get("holdTime"), 0.4, "holdTime du Super %s" % id)
	# Le réglage est LU : avec 1 s, l'ultime ne part pas à 0,5 s, il part à 1 s.
	var g: Dictionary = h.bac_a_sable({"seed": 3.0, "tuning": {"supers": {"forme_damne": {"holdTime": 1.0}}}}) # étape 2 : l'ultime du Revenant
	g.player.superCharge = 1.0
	h.avancer(g, h.ticks(0.5), {"attack": true})
	h.different(g.player.state, "super")
	h.avancer(g, h.ticks(0.5) + 3, {"attack": true})
	h.egal(g.player.state, "super")

static func _u_par_classe(h) -> void:
	for class_id in D6Data.create_tuning().classes:
		var c: Dictionary = D6Data.create_tuning().classes[class_id]
		var g := _bac(h, class_id, [c.skills[0], c.gadgets[0], null])
		g.player.superCharge = 1.0
		var evs: Array = h.ultime(g)
		h.egal(g.player.state, "super", class_id)
		var lances: Array = _de(evs, "super")
		h.egal(lances.size(), 1, "%s : un seul ultime" % class_id)
		if not lances.is_empty():
			h.egal(lances[0].get("super"), g.tuning.supers[c["super"]].kind, "%s : son Super" % class_id)
			h.ok(not lances[0].has("slot"), "l'ultime ne vient d'aucun emplacement")

# ---------------------------------------------------------------- trois emplacements

static func _tests_emplacements(h) -> void:
	h.test("emplacements : deux compétences équipées ont chacune LEUR recharge", func(): _e_recharges(h))
	h.test("emplacements : deux gadgets équipés ont chacun LEURS charges, utilisables au même pas", func(): _e_deux_gadgets(h))
	h.test("emplacements : les charges reviennent à chaque gadget au début d'une section, pas au milieu", func(): _e_section(h))
	h.test("emplacements : un emplacement vide est inoffensif (aucun effet, aucun événement, même partie)", func(): _e_vide(h))
	h.test("emplacements : trois emplacements vides, la partie se joue quand même", func(): _e_tous_vides(h))
	h.test("emplacements : trois actions utilisées dans la même seconde", func(): _e_meme_seconde(h))
	h.test("emplacements : une compétence demandée pendant le lancer d'une autre attend son tour", func(): _e_tampon(h))
	h.test("emplacements : une compétence en recharge n'avale pas la compétence suivante", func(): _e_recharge_tampon(h))
	h.test("emplacements : un gadget lancé part dans la direction de SON bouton", func(): _e_bombe_visee(h))
	h.test("emplacements : le gadget ne part ni mort, ni pendant l'ultime, ni sans charge", func(): _e_gadget_refus(h))
	h.test("emplacements : mort puis reprise, charges pleines et recharges à zéro pour chaque emplacement", func(): _e_reprise(h))

static func _e_recharges(h) -> void:
	var g := _bac(h, "revenant", ["lance", "chaine", "nova"])
	var lance: Dictionary = g.tuning.skills.lance
	var chaine: Dictionary = g.tuning.skills.chaine
	h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
	h.egal(_recharges(g), [lance.cooldown, 0.0, 0.0], "seule la Lance recharge")
	var attente: int = h.ticks(0.5)
	h.avancer(g, attente)
	h.avancer(g, 1, {"skill2Pressed": true, "skill2AimX": 1.0})
	h.egal(g.player.slots[1].cd, chaine.cooldown, "la Chaîne part avec SA recharge")
	h.proche(g.player.slots[0].cd, lance.cooldown - (attente + 1) * DT, EPS, "celle de la Lance continue de son côté")
	h.egal(g.telemetry.skillCasts, 1.0, "la Lance est partie, la Chaîne se prépare")
	# La Lance (4 s) redevient prête avant la Chaîne (5 s, lancée plus tard) : elle repart seule.
	h.avancer(g, h.ticks(lance.cooldown))
	h.egal(g.player.slots[0].cd, 0.0)
	h.ok(g.player.slots[1].cd > 0.0, "la Chaîne recharge encore (%s s)" % g.player.slots[1].cd)
	h.avancer(g, 1, {"skill2Pressed": true})
	h.egal(g.player.state, "free", "une compétence en recharge ne part pas")
	h.avancer(g, 1, {"skill1Pressed": true})
	h.egal(g.player.state, "cast")
	h.egal(g.player.castSlot, 0.0)
	h.avancer(g, h.ticks(0.3))
	h.egal(g.telemetry.skillCasts, 3.0, "Lance, Chaîne, Lance")

static func _e_deux_gadgets(h) -> void:
	var g := _bac(h, "revenant", ["nova", "bombe", "lance"])
	var nova: Dictionary = g.tuning.gadgets.nova
	var bombe: Dictionary = g.tuning.gadgets.bombe
	h.egal(_charges(g), [nova.chargesPerSection, bombe.chargesPerSection, 0.0], "chaque gadget a ses charges, la compétence aucune")
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill2Pressed": true})
	h.egal(_charges(g), [nova.chargesPerSection - 1.0, bombe.chargesPerSection - 1.0, 0.0])
	var gadgets: Array = _de(evs, "gadget")
	h.egal(gadgets.map(func(ev): return ev.get("slot")), [0.0, 1.0], "les deux partent au même pas, dans l'ordre des emplacements")
	h.egal(gadgets.map(func(ev): return ev.get("charges")), [nova.chargesPerSection - 1.0, bombe.chargesPerSection - 1.0])
	h.egal(g.telemetry.gadgetUses, 2.0)
	h.egal(_zones(g, "bombe").size(), 1, "la bombe est en l'air")
	# Vider la Nova ne touche pas la Bombe.
	for i in int(nova.chargesPerSection) + 2:
		h.avancer(g, 1, {"skill1Pressed": true})
	h.egal(_charges(g), [0.0, bombe.chargesPerSection - 1.0, 0.0])
	h.egal(g.telemetry.gadgetUses, 1.0 + nova.chargesPerSection, "sans charge, la Nova ne part plus")

static func _e_section(h) -> void:
	var g := _bac(h, "revenant", ["lance", "nova", "bombe"])
	var pleins: Array = [0.0, D6Loadout.max_charges(g, 1), D6Loadout.max_charges(g, 2)]
	h.egal(_charges(g), pleins)
	var every: float = g.tuning.section.gadgetRefillEvery
	for st in g.player.slots:
		st.charges = 0.0
	D6Run.enter_floor(g, 2.0, PORTE)
	h.egal(_charges(g), [0.0, 0.0, 0.0], "milieu de section : rien n'est rendu")
	D6Run.enter_floor(g, 1.0 + every, PORTE)
	h.egal(_charges(g), pleins, "tous les %s étages : chaque gadget équipé est plein" % D6Js.num_str(every))

static func _e_vide(h) -> void:
	var a := _bac(h, "revenant", ["lance", "nova", null])
	var b := _bac(h, "revenant", ["lance", "nova", null])
	_cible(a, 120.0, 0.0)
	_cible(b, 120.0, 0.0)
	h.egal(a.kit.slots, ["lance", "nova", null])
	h.egal(D6Loadout.slot_view(a, 2), null, "rien à afficher")
	var evs: Array = h.avancer(a, 90, {"skill3Pressed": true, "skill3AimX": 1.0})
	h.avancer(b, 90)
	h.egal(evs.filter(func(ev): return ev.type in ["castStart", "skill", "gadget", "super", "attackStart"]).size(), 0, "aucun événement d'action")
	h.egal(D6Game.state_hash(a), D6Game.state_hash(b), "même partie qu'avec aucune entrée")
	h.egal(a.player.slots, b.player.slots)
	h.egal(a.telemetry.skillCasts + a.telemetry.gadgetUses, 0.0)

static func _e_tous_vides(h) -> void:
	var g := _bac(h, "bourreau", [null, null, null])
	h.egal(g.kit.slots, [null, null, null])
	var e := _cible(g, 80.0, 0.0)
	var evs: Array = h.avancer(g, 60, {"skill1Pressed": true, "skill2Pressed": true, "skill3Pressed": true, "attack": true, "aimX": 1.0})
	h.egal(_de(evs, "gadget").size() + _de(evs, "castStart").size(), 0)
	h.ok(e.hp < e.maxHp, "l'attaque, elle, marche")
	h.egal(D6Loadout.first_gadget(g), -1)
	h.ok(D6Loadout.gadgets_full(g), "aucun gadget : rien à remplir")
	D6Run.enter_floor(g, 19.0, PORTE)
	h.egal(_charges(g), [0.0, 0.0, 0.0])
	h.egal(g.mode, "play")

static func _e_meme_seconde(h) -> void:
	var g := _bac(h, "revenant", ["lance", "nova", "chaine"])
	var e := _cible(g, 120.0, 0.0)
	var evs: Array = h.avancer(g, 60, func(i): return {
		"skill1Pressed": i == 0, "skill1AimX": 1.0, "skill2Pressed": i == 15, "skill3Pressed": i == 30, "skill3AimX": 1.0,
	})
	h.egal(_de(evs, "skill").map(func(ev): return ev.get("slot")), [0.0, 2.0], "Lance (emplacement 1) puis Chaîne (emplacement 3)")
	h.egal(_de(evs, "gadget").map(func(ev): return ev.get("slot")), [1.0], "Nova (emplacement 2) entre les deux")
	h.egal(g.telemetry.skillCasts, 2.0)
	h.egal(g.telemetry.gadgetUses, 1.0)
	h.ok(_coups(evs, "skill").size() >= 2 and _coups(evs, "gadget").size() >= 1, "les trois ont porté sur l'ennemi")
	h.ok(e.hp < e.maxHp)
	h.ok(g.player.slots[0].cd > 0.0 and g.player.slots[2].cd > 0.0 and g.player.slots[0].cd < g.player.slots[2].cd, "deux recharges distinctes en cours")

static func _e_tampon(h) -> void:
	var g := _bac(h, "revenant", ["lance", "nova", "chaine"])
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
	h.egal(g.player.state, "cast")
	evs.append_array(h.avancer(g, 1, {"skill3Pressed": true, "skill3AimX": -1.0}))
	h.egal(g.player.castSlot, 0.0, "la Lance finit son lancer")
	evs.append_array(h.avancer(g, h.ticks(0.4)))
	var parties: Array = _de(evs, "skill")
	h.egal(parties.map(func(ev): return ev.get("slot")), [0.0, 2.0], "la Chaîne part ensuite, sans nouvel appui")
	h.ok(parties.size() == 2 and absf(absf(parties[1].angle) - PI) < 0.01, "…dans la direction demandée par SON bouton")

static func _e_recharge_tampon(h) -> void:
	var g := _bac(h, "revenant", ["lance", "nova", "chaine"])
	g.player.slots[0].cd = 99.0
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true})
	evs.append_array(h.avancer(g, 1, {"skill3Pressed": true, "attackPressed": true}))
	evs.append_array(h.avancer(g, h.ticks(0.6)))
	h.egal(_de(evs, "castStart").map(func(ev): return ev.get("slot")), [2.0], "la Chaîne part, la Lance en recharge non")
	h.egal(g.player.slots[0].cd < 99.0 and g.player.slots[0].cd > 90.0, true, "la recharge de la Lance n'a pas été relancée")

static func _e_bombe_visee(h) -> void:
	for sens in [1.0, -1.0]:
		var g := _bac(h, "revenant", ["lance", "bombe", null])
		_cible(g, 150.0, 0.0) # un ennemi à droite : la visée assistée irait vers lui
		h.avancer(g, 1, {"skill2Pressed": true, "skill2AimX": sens, "aimX": 1.0})
		var z: Array = _zones(g, "bombe")
		if h.egal(z.size(), 1, "une bombe"):
			h.ok((z[0].tx - g.player.x) * sens > 100.0, "bouton glissé vers %s : la bombe y va (%.0f)" % [sens, z[0].tx - g.player.x])
	# Bouton tapé (0, 0) : visée assistée sur l'ennemi, comme avant.
	var g2 := _bac(h, "revenant", ["lance", "bombe", null])
	var e := _cible(g2, -180.0, 0.0)
	h.avancer(g2, 1, {"skill2Pressed": true})
	var z2: Array = _zones(g2, "bombe")
	h.ok(z2.size() == 1 and absf(z2[0].tx - e.x) < 20.0, "tapée : sur l'ennemi")

static func _e_gadget_refus(h) -> void:
	# Étape 2 : « pendant l'ultime » se juge sur la Colère lancée directement (en Forme du Damné, les
	# emplacements portent les actions de forme : v3_ultimes.gd).
	var g := _bac(h, "revenant", ["lance", "nova", null], {"tuning": {"classes": {"revenant": {"super": "colere"}}}})
	var plein: float = g.player.slots[1].charges
	g.player.superCharge = 1.0
	h.ultime(g)
	h.avancer(g, 1, {"skill2Pressed": true})
	h.egal(g.player.slots[1].charges, plein, "pendant l'ultime : refusé, aucune charge perdue")
	h.egal(D6Player.use_gadget(g, 0), false, "l'emplacement d'une compétence n'est pas un gadget")
	h.egal(D6Player.use_gadget(g, 2), false, "un emplacement vide non plus")
	h.avancer(g, h.ticks(g.tuning["super"].duration) + 2)
	g.player.slots[1].charges = 0.0
	h.egal(D6Player.use_gadget(g, 1), false, "sans charge")
	g.player.slots[1].charges = 1.0
	h.egal(D6Player.use_gadget(g, 1), true)
	h.egal(g.player.slots[1].charges, 0.0)

static func _e_reprise(h) -> void:
	var g: Dictionary = h.partie({"seed": 9.0, "meta": _meta("revenant", ["lance", "nova", "bombe"])})
	for st in g.player.slots:
		st.charges = 0.0
		st.cd = 3.0
	g.player.superHold = 0.2
	g.player.superArm = true
	D6Combat.damage_player(g, 99999.0, {"kind": "test", "id": 1.0})
	h.avancer(g, h.ticks(g.tuning.player.deathDelay) + 5)
	h.egal(g.mode, "dead")
	h.egal(D6Game.apply_command(g, {"type": "respawn"}), true)
	h.egal(_charges(g), [0.0, D6Loadout.max_charges(g, 1), D6Loadout.max_charges(g, 2)])
	h.egal(_recharges(g), [0.0, 0.0, 0.0])
	h.egal(g.player.superHold, 0.0)
	h.egal(g.player.superArm, false, "la reprise ne garde pas un appui armé")

# ---------------------------------------------------------------- profil : select_slot, slot_choices, migration

static func _tests_profil(h) -> void:
	h.test("select_slot : refuse un emplacement inconnu, une action inconnue, non débloquée ou d'une autre classe", func(): _p_refus(h))
	h.test("select_slot : place, échange deux emplacements, vide ; jamais deux fois la même action", func(): _p_echange(h))
	h.test("slot_choices : compétences puis gadgets de la classe, avec leur état", func(): _p_choix(h))
	h.test("profil : changer de classe refait des emplacements valides", func(): _p_classe(h))
	h.test("migration : un vrai profil de joueur au schéma 3 est relu sans rien perdre", func(): _p_migration_reelle(h))
	h.test("migration : {skillId, gadgetId} devient [compétence, gadget, première autre action possédée ou vide]", func(): _p_migration_cas(h))
	h.test("migration : un profil au schéma 4 est relu tel quel ; doublon et action perdue sont réparés", func(): _p_schema_4(h))

static func _p_refus(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.new_profile(t)
	var avant: Array = p.loadout.slots.duplicate()
	h.egal(avant, ["lance", "nova", null], "profil neuf : compétence, gadget, vide")
	for index in [3.0, -1.0, 0.5, "0", null]:
		h.egal(D6Profile.select_slot(p, t, index, "lance"), {"ok": false, "reason": "emplacement inconnu"}, "emplacement %s" % str(index))
	h.egal(D6Profile.select_slot(p, t, 2.0, "chaine"), {"ok": false, "reason": "indisponible"}, "de la classe mais pas débloquée")
	p.unlocked.skills.append("bond")
	h.egal(D6Profile.select_slot(p, t, 2.0, "bond"), {"ok": false, "reason": "indisponible"}, "débloquée mais d'une autre classe")
	for id in ["inconnue", 7.0, "", "lame"]:
		h.egal(D6Profile.select_slot(p, t, 2.0, id), {"ok": false, "reason": "indisponible"}, "action %s" % str(id))
	h.egal(p.loadout.slots, avant, "un refus ne change rien")

static func _p_echange(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.new_profile(t)
	p.unlocked.skills.append("chaine")
	p.unlocked.gadgets.append("bombe")
	h.egal(D6Profile.select_slot(p, t, 2.0, "chaine"), {"ok": true})
	h.egal(p.loadout.slots, ["lance", "nova", "chaine"])
	h.egal(D6Profile.select_slot(p, t, 0.0, "chaine"), {"ok": true}, "déjà placée ailleurs : échange")
	h.egal(p.loadout.slots, ["chaine", "nova", "lance"])
	h.egal(D6Profile.select_slot(p, t, 0.0, "chaine"), {"ok": true}, "déjà à cette place : rien ne bouge")
	h.egal(p.loadout.slots, ["chaine", "nova", "lance"])
	h.egal(D6Profile.select_slot(p, t, 1.0, null), {"ok": true}, "vider")
	h.egal(p.loadout.slots, ["chaine", null, "lance"])
	h.egal(D6Profile.select_slot(p, t, 1.0, "lance"), {"ok": true}, "échange avec un emplacement vide")
	h.egal(p.loadout.slots, ["chaine", "lance", null])
	h.egal(D6Profile.select_slot(p, t, 2.0, "bombe"), {"ok": true}, "un gadget va dans n'importe quel emplacement")
	h.egal(D6Profile.select_slot(p, t, 0.0, "nova"), {"ok": true}, "deux gadgets équipés")
	h.egal(p.loadout.slots, ["nova", "lance", "bombe"])
	for id in p.loadout.slots:
		h.egal(p.loadout.slots.count(id), 1, "%s une seule fois" % id)
	# La partie suivante joue ces emplacements.
	var g: Dictionary = D6Game.create_game({"seed": 4.0, "meta": p})
	h.egal(g.kit.slots, ["nova", "lance", "bombe"])
	h.egal([D6Loadout.slot_kind(g, 0), D6Loadout.slot_kind(g, 1), D6Loadout.slot_kind(g, 2)], ["gadget", "skill", "gadget"])

static func _p_choix(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.new_profile(t)
	var choix: Array = D6Profile.slot_choices(p, t)
	var c: Dictionary = t.classes.revenant
	h.egal(choix.map(func(x): return x.id), c.skills + c.gadgets, "compétences puis gadgets de la classe")
	h.egal(choix.map(func(x): return x.kind), ["skill", "skill", "skill", "gadget", "gadget"])
	h.egal(choix.map(func(x): return x.unlocked), [true, false, false, true, false], "le départ possédé, le reste à débloquer (dans l'arbre)")
	h.egal(choix.map(func(x): return x.rank), [1.0, 0.0, 0.0, 1.0, 0.0], "rang dans l'arbre : 1 offert pour le départ, 0 pour le reste")
	for x in choix:
		var def: Dictionary = t.skills[x.id] if x.kind == "skill" else t.gadgets[x.id]
		h.egal(x.keys(), ["id", "name", "text", "icon", "kind", "unlocked", "rank"], "forme de %s" % x.id)
		h.egal([x.name, x.text], [def.name, def.text], x.id)
		h.egal(def.get("cost"), null, "%s : plus de prix en Âmes (l'arbre débloque)" % x.id)
		h.egal(x.icon, def.get("icon", x.kind), "pictogramme de %s (à défaut, celui de sa sorte)" % x.id)
	D6Profile.select_class(p, t, "revenant")
	p.unlocked.classes.append("chasseresse")
	D6Profile.select_class(p, t, "chasseresse")
	h.egal(D6Profile.slot_choices(p, t).map(func(x): return x.id), t.classes.chasseresse.skills + t.classes.chasseresse.gadgets, "celles de la classe COURANTE")

static func _p_classe(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.new_profile(t)
	p.souls = 9999.0
	for class_id in ["bourreau", "chasseresse"]:
		D6Profile.unlock(p, t, "classes", class_id)
	h.egal(D6Profile.unlock(p, t, "skills", "chaine"), {"ok": false, "reason": "se débloque dans l'arbre"}, "une compétence ne s'achète plus en Âmes")
	p.unlocked.skills.append("chaine") # possédée d'office (rang 1 offert), comme sur un ancien profil
	h.egal(D6Profile.select_slot(p, t, 2.0, "chaine"), {"ok": true})
	h.egal(D6Profile.select_class(p, t, "bourreau"), {"ok": true})
	h.egal(p.loadout.slots, ["bond", "cri", "chaine"], "la Chaîne, commune aux deux classes, reste ; le reste devient le départ du Bourreau")
	h.egal(D6Profile.select_class(p, t, "chasseresse"), {"ok": true})
	h.egal(p.loadout.slots, ["volee", "piege", null], "rien de commun : départ de la Chasseresse, troisième emplacement vide")
	h.egal(D6Profile.select_slot(p, t, 0.0, null), {"ok": true})
	h.egal(D6Profile.select_class(p, t, "revenant"), {"ok": true})
	h.egal(p.loadout.slots, ["lance", "nova", "chaine"], "autre classe : les trois emplacements sont refaits, vides compris")
	h.egal(D6Profile.select_slot(p, t, 1.0, null), {"ok": true})
	h.egal(D6Profile.select_class(p, t, "revenant"), {"ok": true})
	h.egal(p.loadout.slots, ["lance", null, "chaine"], "choisir la classe déjà portée ne touche à rien")
	for class_id in t.classes:
		D6Profile.select_class(p, t, class_id)
		var c: Dictionary = t.classes[class_id]
		for id in p.loadout.slots:
			h.ok(id == null or c.skills.has(id) or c.gadgets.has(id), "%s : %s est de la classe" % [class_id, str(id)])

static func _p_migration_reelle(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.sanitize_profile(D6Js.clone(PROFIL_SCHEMA_3), t)
	h.egal(p.schema, 5.0, "le schéma monte au schéma courant (3 → 5 : emplacements, puis arbre)")
	h.egal(p.schema, D6Data.tables().profile.PROFILE_SCHEMA)
	for cle in INTACTS:
		h.egal(p[cle], PROFIL_SCHEMA_3[cle], "« %s » relu sans perte" % cle)
	h.egal(p.loadout, {"classId": "bourreau", "slots": ["bond", "cri", "chaine"]}, "compétence, gadget, puis la première autre action possédée du Bourreau")
	h.ok(not p.loadout.has("skillId") and not p.loadout.has("gadgetId"), "les anciens champs ont disparu")
	h.egal(p.keys(), D6Profile.create_profile(t).keys(), "aucun champ en plus ni en moins qu'un profil neuf")
	# Relu une seconde fois (la sauvegarde suivante) : plus rien ne bouge.
	h.egal(D6Profile.sanitize_profile(D6Js.clone(p), t), p, "la migration est stable")
	# Et la partie suivante se joue avec ce profil : ses trois emplacements, son arme, ses améliorations.
	var g: Dictionary = D6Game.create_game({"seed": 12.0, "meta": D6Js.clone(PROFIL_SCHEMA_3), "startFloor": 127.0})
	h.egal(g.kit, {"classId": "bourreau", "weaponType": "hache", "slots": ["bond", "cri", "chaine"], "superId": "sentence_capitale"})
	h.egal(g.player.slots[1].charges, g.tuning.gadgets.cri.chargesPerSection + 1.0, "Arsenal (+1 charge) vaut pour son gadget")
	h.egal(g.meta.souls, PROFIL_SCHEMA_3.souls)

static func _p_migration_cas(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var neuf := {"schema": 3.0, "loadout": {"classId": "revenant", "skillId": "lance", "gadgetId": "nova"}}
	h.egal(D6Profile.sanitize_profile(neuf, t).loadout.slots, ["lance", "nova", null], "aucune autre action possédée : troisième emplacement vide")
	var avec := {"schema": 3.0, "unlocked": {"skills": ["lance", "chaine"], "gadgets": ["nova", "bombe"]}, "loadout": {"classId": "revenant", "skillId": "chaine", "gadgetId": "bombe"}}
	h.egal(D6Profile.sanitize_profile(avec, t).loadout.slots, ["chaine", "bombe", "lance"], "la première AUTRE action possédée : la Lance")
	var perdue := {"schema": 3.0, "loadout": {"classId": "revenant", "skillId": "chaine", "gadgetId": "nova"}}
	h.egal(D6Profile.sanitize_profile(perdue, t).loadout.slots, ["lance", "nova", null], "compétence équipée mais non possédée : celle de départ")
	var sans := {"schema": 3.0, "souls": 12.0}
	h.egal(D6Profile.sanitize_profile(sans, t).loadout.slots, ["lance", "nova", null], "sauvegarde sans loadout : le départ")
	var moitie := {"schema": 3.0, "loadout": {"classId": "revenant", "gadgetId": "nova"}}
	h.egal(D6Profile.sanitize_profile(moitie, t).loadout.slots, ["lance", "nova", null], "champ manquant : complété")

static func _p_schema_4(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var u := {"skills": ["lance", "chaine"], "gadgets": ["nova", "bombe"]}
	var voulu := {"schema": 4.0, "unlocked": u, "loadout": {"classId": "revenant", "slots": [null, "bombe", "lance"]}}
	h.egal(D6Profile.sanitize_profile(D6Js.clone(voulu), t).loadout.slots, [null, "bombe", "lance"], "un emplacement vidé exprès reste vide")
	var double := {"schema": 4.0, "unlocked": u, "loadout": {"classId": "revenant", "slots": ["chaine", "chaine", "nova"]}}
	h.egal(D6Profile.sanitize_profile(double, t).loadout.slots, ["chaine", "lance", "nova"], "doublon : remplacé par la première action possédée pas encore placée")
	var etrangere := {"schema": 4.0, "unlocked": u, "loadout": {"classId": "revenant", "slots": ["bond", 7.0, "piege"]}}
	h.egal(D6Profile.sanitize_profile(etrangere, t).loadout.slots, ["lance", "nova", "chaine"], "autre classe, illisible : remplacées")
	var courte := {"schema": 4.0, "unlocked": u, "loadout": {"classId": "revenant", "slots": ["chaine"]}}
	h.egal(D6Profile.sanitize_profile(courte, t).loadout.slots, ["chaine", null, null], "liste trop courte : complétée par du vide")
	var longue := {"schema": 4.0, "unlocked": u, "loadout": {"classId": "revenant", "slots": ["chaine", "nova", "lance", "bombe"]}}
	h.egal(D6Profile.sanitize_profile(longue, t).loadout.slots, ["chaine", "nova", "lance"], "jamais plus de trois")
	var illisible := {"schema": 4.0, "unlocked": u, "loadout": {"classId": "revenant", "slots": "lance"}}
	h.egal(D6Profile.sanitize_profile(illisible, t).loadout.slots, ["lance", "nova", null], "forme illisible : le départ")

# ---------------------------------------------------------------- lecture pour l'affichage, événements

static func _tests_lecture(h) -> void:
	h.test("slot_view : une compétence (prête, recharge de 1 à 0, se vise), sans connaître l'intérieur", func(): _l_competence(h))
	h.test("slot_view : un gadget (charges, maximum, prêt), visé seulement s'il se lance", func(): _l_gadget(h))
	h.test("événements : castStart, skill, gadget et gadgetCharge portent leur emplacement", func(): _l_evenements(h))
	h.test("entrée d'un pas : la forme V3, sans aucune ancienne commande", func(): _l_entree(h))

static func _l_competence(h) -> void:
	var g := _bac(h, "revenant", ["nova", "chaine", null])
	var chaine: Dictionary = g.tuning.skills.chaine
	var v: Dictionary = D6Loadout.slot_view(g, 1)
	h.egal(v.keys(), ["id", "name", "icon", "kind", "ready", "cooldownFrac", "charges", "maxCharges", "aimed"])
	h.egal(v, {"id": "chaine", "name": chaine.name, "icon": chaine.icon, "kind": "skill", "ready": true, "cooldownFrac": 0.0, "charges": null, "maxCharges": null, "aimed": true})
	h.avancer(g, 1, {"skill2Pressed": true})
	v = D6Loadout.slot_view(g, 1)
	h.egal([v.ready, v.cooldownFrac], [false, 1.0], "vient de servir")
	h.avancer(g, h.ticks(chaine.cooldown / 2.0))
	v = D6Loadout.slot_view(g, 1)
	h.proche(v.cooldownFrac, 0.5, 0.01, "à mi-recharge")
	h.egal(v.ready, false)
	h.avancer(g, h.ticks(chaine.cooldown / 2.0) + 1)
	v = D6Loadout.slot_view(g, 1)
	h.egal([v.ready, v.cooldownFrac], [true, 0.0], "prête")
	# La Lance n'a pas de pictogramme propre : celui de sa sorte.
	var g2 := _bac(h, "revenant", ["lance", null, null])
	h.egal(D6Loadout.slot_view(g2, 0).icon, "skill")
	h.egal(D6Loadout.slot_view(g2, 1), null)

static func _l_gadget(h) -> void:
	var g := _bac(h, "revenant", ["nova", "chaine", "bombe"])
	var nova: Dictionary = g.tuning.gadgets.nova
	var v: Dictionary = D6Loadout.slot_view(g, 0)
	h.egal(v, {"id": "nova", "name": nova.name, "icon": "gadget", "kind": "gadget", "ready": true, "cooldownFrac": 0.0, "charges": nova.chargesPerSection, "maxCharges": nova.chargesPerSection, "aimed": false})
	h.egal(D6Loadout.slot_view(g, 2).aimed, true, "la bombe se lance : elle se vise")
	h.egal(D6Loadout.slot_view(g, 2).icon, g.tuning.gadgets.bombe.icon)
	h.avancer(g, 1, {"skill1Pressed": true})
	v = D6Loadout.slot_view(g, 0)
	h.egal([v.ready, v.charges, v.cooldownFrac], [true, nova.chargesPerSection - 1.0, 0.0])
	g.player.slots[0].charges = 0.0
	h.egal(D6Loadout.slot_view(g, 0).ready, false, "plus de charge : pas prêt")
	for class_id in ["bourreau", "chasseresse"]:
		var c: Dictionary = g.tuning.classes[class_id]
		var gc := _bac(h, class_id, [c.gadgets[0], c.gadgets[1], c.skills[1]])
		for i in D6Loadout.SLOTS:
			var vue: Dictionary = D6Loadout.slot_view(gc, i)
			h.egal(vue.aimed, vue.kind == "skill" or vue.id == "bombe", "%s : %s" % [class_id, vue.id])
			h.egal(vue.charges != null, vue.kind == "gadget")

static func _l_evenements(h) -> void:
	var g := _bac(h, "bourreau", ["cri", "chaine", "bond"])
	_cible(g, 200.0, 0.0)
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill2Pressed": true, "skill2AimX": 1.0})
	evs.append_array(h.avancer(g, h.ticks(0.5)))
	evs.append_array(h.avancer(g, 1, {"skill3Pressed": true}))
	evs.append_array(h.avancer(g, h.ticks(0.6)))
	h.egal(_de(evs, "gadget").map(func(ev): return [ev.get("gadget"), ev.get("slot")]), [["cri", 0.0]])
	h.egal(_de(evs, "castStart").map(func(ev): return ev.get("slot")), [1.0, 2.0])
	h.egal(_de(evs, "skill").map(func(ev): return [ev.get("skill"), ev.get("slot")]), [["chain", 1.0], ["bond", 2.0]])
	# La charge rendue par un élite abattu nomme l'emplacement du gadget.
	var e: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x + 300.0, g.player.y, {"spawnT": 0.0})
	e.eliteMod = "blinde"
	g.events.clear()
	D6Combat.kill_enemy(g, e, {"kind": "melee"})
	var rendues: Array = _de(g.events, "gadgetCharge")
	h.egal(rendues.map(func(ev): return [ev.get("slot"), ev.get("charges")]), [[0.0, g.tuning.gadgets.cri.chargesPerSection]])

static func _l_entree(h) -> void:
	var cles: Array = D6Game.empty_input().keys()
	h.egal(cles, [
		"moveX", "moveY", "aimX", "aimY", "attack", "attackPressed", "dashPressed",
		"skill1Pressed", "skill1AimX", "skill1AimY", "skill2Pressed", "skill2AimX", "skill2AimY", "skill3Pressed", "skill3AimX", "skill3AimY",
	])
	# Les anciennes commandes n'existent plus : les presser ne fait rien (pas d'alias caché).
	var g := _bac(h, "revenant", ["lance", "nova", null])
	g.player.superCharge = 1.0
	var vieux := {"skillPressed": true, "skillAimX": 1.0, "gadgetPressed": true, "superPressed": true}
	var evs: Array = []
	for i in 30:
		D6Game.step_game(g, vieux)
		evs.append_array(g.events)
		g.events.clear()
	h.egal(evs.filter(func(ev): return ev.type in ["castStart", "skill", "gadget", "super"]).size(), 0)
	h.ok(not g.player.has("skillCd") and not g.player.has("gadgetCharges"), "le héros n'a plus qu'un état : player.slots")
	h.ok(not g.kit.has("skillId") and not g.kit.has("gadgetId"), "le kit n'a plus que kit.slots")

# ---------------------------------------------------------------- bénédictions, objets, autels : toute action de la sorte

static func _tests_effets(h) -> void:
	h.test("effet « recharge de la compétence » (Rancœur, affixe de l'Érudit) : chaque compétence équipée", func(): _f_recharge(h))
	h.test("effet « dégâts de la compétence » (affixe des Runes) : chaque compétence équipée, jamais un gadget", func(): _f_degats(h))
	h.test("effet Charme fatal (vulnérable au toucher d'une compétence) : chaque compétence équipée, pas le gadget", func(): _f_charme(h))
	h.test("effet Convoitise (éclair au toucher d'une compétence) : chaque compétence équipée, pas le gadget", func(): _f_convoitise(h))
	h.test("effet Arsenal (+1 charge par section) : chaque gadget équipé", func(): _f_arsenal(h))
	h.test("effet Main de gloire (salle sans blessure : +1 charge) : chaque gadget équipé, jamais au-delà du plein", func(): _f_main_de_gloire(h))
	h.test("effet élite abattu (charge de gadget) : chaque gadget équipé, de SON chargeOnEliteKill", func(): _f_elite(h))
	h.test("effet autel « Remplir une fiole » : chaque gadget équipé ; grisé quand tous sont pleins ou sans gadget", func(): _f_autel(h))
	h.test("effet repos « Remplir les fioles » : tous les gadgets équipés pleins", func(): _f_repos(h))
	h.test("effets du Super (Ripaille, Passion brûlante, Gloire charnelle) : ils suivent l'ultime lancé par maintien", func(): _f_super(h))

static func _talisman(g: Dictionary, stat: String, value: float) -> void:
	g.run.items.talisman = {"id": 9001.0, "slot": "talisman", "rarity": "rare", "name": "Relique d'essai", "level": 1.0, "affixes": [{"stat": stat, "value": value}], "power": null, "base": {}, "score": 0.0}
	D6Stats.recompute_stats(g)

static func _benir(g: Dictionary, id: String) -> void:
	D6Boons.add_boon(g.run, {"id": id, "rarity": "commun"})
	D6Stats.recompute_stats(g)

static func _f_recharge(h) -> void:
	var g := _bac(h, "revenant", ["lance", "chaine", "nova"])
	_benir(g, "rancoeur")
	var mult: float = g.player.stats.skillCooldownMult
	h.proche(mult, 1.0 - D6Boons.boon_value(D6Boons.boon_def("rancoeur"), "commun") / 100.0, EPS)
	h.avancer(g, 1, {"skill1Pressed": true})
	h.avancer(g, h.ticks(0.3))
	h.avancer(g, 1, {"skill2Pressed": true})
	h.proche(g.player.slots[1].cd, g.tuning.skills.chaine.cooldown * mult, EPS, "la Chaîne")
	h.proche(g.player.slots[0].cd, g.tuning.skills.lance.cooldown * mult - (h.ticks(0.3) + 1) * DT, EPS, "la Lance")
	h.proche(D6Loadout.slot_view(g, 1).cooldownFrac, 1.0, EPS, "la lecture compte la recharge RÉDUITE")
	# L'affixe d'objet porte la même stat : il s'ajoute, pour les deux.
	var g2 := _bac(h, "revenant", ["lance", "chaine", "nova"])
	_talisman(g2, "skillCooldownMult", -0.1)
	h.avancer(g2, 1, {"skill2Pressed": true})
	h.proche(g2.player.slots[1].cd, g2.tuning.skills.chaine.cooldown * 0.9, EPS)

## Dégâts du premier coup de compétence et du premier coup de gadget, pour un emplacement pressé.
static func _premier_coup(h, slots: Array, bouton: String, kind: String, stat: String, value: float) -> float:
	var g := _bac(h, "revenant", slots)
	if stat != "":
		_talisman(g, stat, value)
	_cible(g, 100.0, 0.0)
	var over := {bouton + "Pressed": true, bouton + "AimX": 1.0}
	var evs: Array = h.avancer(g, 1, over)
	evs.append_array(h.avancer(g, h.ticks(0.8)))
	var coups := _coups(evs, kind)
	if not h.ok(coups.size() > 0, "%s : un coup de sorte %s" % [bouton, kind]):
		return NAN
	return coups[0].amount

static func _f_degats(h) -> void:
	var slots := ["lance", "chaine", "nova"]
	for paire in [["skill1", "skill", 1.5], ["skill2", "skill", 1.5], ["skill3", "gadget", 1.0]]:
		var sans := _premier_coup(h, slots, paire[0], paire[1], "", 0.0)
		var avec := _premier_coup(h, slots, paire[0], paire[1], "skillDamageMult", 0.5)
		h.egal(avec, D6Js.jround(sans * paire[2]), "%s : %s -> %s (×%s)" % [paire[0], sans, avec, paire[2]])

static func _f_charme(h) -> void:
	for cas in [["skill1", true], ["skill2", true], ["skill3", false]]:
		var g := _bac(h, "revenant", ["lance", "chaine", "nova"])
		_benir(g, "charme")
		var e := _cible(g, 100.0, 0.0)
		h.avancer(g, 1, {cas[0] + "Pressed": true, cas[0] + "AimX": 1.0})
		h.avancer(g, h.ticks(0.6))
		h.ok(e.hp < e.maxHp, "%s a touché" % cas[0])
		h.egal(e.vuln > 0.0, cas[1], "%s : vulnérable = %s" % [cas[0], cas[1]])

static func _f_convoitise(h) -> void:
	for cas in [["skill1", true], ["skill2", true], ["skill3", false]]:
		var g := _bac(h, "revenant", ["lance", "chaine", "nova"])
		_benir(g, "convoitise")
		_cible(g, 100.0, 0.0)
		_cible(g, 100.0, 120.0)
		var evs: Array = h.avancer(g, 1, {cas[0] + "Pressed": true, cas[0] + "AimX": 1.0})
		evs.append_array(h.avancer(g, h.ticks(0.6)))
		h.egal(_de(evs, "chain").size() > 0, cas[1], "%s : éclair = %s" % [cas[0], cas[1]])

static func _f_arsenal(h) -> void:
	var meta := _meta("revenant", ["nova", "bombe", "lance"])
	meta.upgrades = {"arsenal": 1.0}
	var g: Dictionary = h.partie({"seed": 5.0, "meta": meta})
	var bonus: float = g.tuning.town.upgrades.arsenal.perLevel
	h.egal(g.player.stats.gadgetChargesBonus, bonus)
	h.egal(_charges(g), [g.tuning.gadgets.nova.chargesPerSection + bonus, g.tuning.gadgets.bombe.chargesPerSection + bonus, 0.0])
	h.egal(D6Loadout.slot_view(g, 1).maxCharges, g.tuning.gadgets.bombe.chargesPerSection + bonus)

static func _f_main_de_gloire(h) -> void:
	var C = load("res://tests/regles/v2_contenu.gd")
	var gain: float = C.power_proc("main_de_gloire").value
	var g: Dictionary = D6Game.create_game({"seed": 25.0, "startFloor": 3.0, "meta": _meta("revenant", ["nova", "lance", "bombe"])})
	C.wear(h, g, "main_de_gloire")
	g.player.slots[0].charges = 1.0
	g.player.slots[2].charges = 0.0
	C.clear_room(h, g)
	h.egal(_charges(g), [1.0 + gain, 0.0, gain], "salle sans blessure : chaque gadget gagne sa charge")
	h.egal(C.events(g, "gadgetCharge").size(), 1, "un seul événement pour les deux")
	# Un gadget plein n'en gagne pas, l'autre si.
	var g2: Dictionary = D6Game.create_game({"seed": 25.0, "startFloor": 3.0, "meta": _meta("revenant", ["nova", "lance", "bombe"])})
	C.wear(h, g2, "main_de_gloire")
	var plein: float = g2.player.slots[0].charges
	g2.player.slots[2].charges = 1.0
	C.clear_room(h, g2)
	h.egal(_charges(g2), [plein, 0.0, 1.0 + gain])
	h.egal(C.events(g2, "gadgetCharge").map(func(ev): return ev.get("slot")), [2.0], "l'événement nomme l'emplacement qui a gagné")

static func _f_elite(h) -> void:
	var g := _bac(h, "chasseresse", ["piege", "totem", "volee"])
	g.tuning.gadgets.totem.chargeOnEliteKill = 2.0 # chacun SON réglage
	for st in g.player.slots:
		st.charges = 0.0
	var e: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x + 300.0, g.player.y, {"spawnT": 0.0})
	e.eliteMod = "blinde"
	D6Combat.kill_enemy(g, e, {"kind": "melee"})
	h.egal(_charges(g), [g.tuning.gadgets.piege.chargeOnEliteKill, 2.0, 0.0])
	# Sans gadget équipé : rien, et aucun événement.
	var g2 := _bac(h, "chasseresse", ["volee", "brasier", null])
	var e2: Dictionary = D6Enemies.create_enemy(g2, "imp", g2.player.x + 300.0, g2.player.y, {"spawnT": 0.0})
	e2.eliteMod = "blinde"
	g2.events.clear()
	D6Combat.kill_enemy(g2, e2, {"kind": "melee"})
	h.egal(_de(g2.events, "gadgetCharge").size(), 0)
	h.egal(_charges(g2), [0.0, 0.0, 0.0])

static func _f_autel(h) -> void:
	var opt = null
	for ev in D6Data.tables().run.EVENTS:
		for o in ev.options:
			if o.get("effect") == "gadgetCharge":
				opt = o
	if not h.ok(opt != null, "l'autel qui remplit une fiole existe"):
		return
	var g := _bac(h, "revenant", ["nova", "bombe", "lance"])
	h.egal(D6Run._option_blocked(g, opt), true, "tous pleins : grisé")
	g.player.slots[0].charges = 0.0
	g.player.slots[1].charges = 1.0
	h.egal(D6Run._option_blocked(g, opt), false)
	D6Run._apply_event(g, opt)
	h.egal(_charges(g), [opt.gain, 1.0 + opt.gain, 0.0], "chaque gadget équipé gagne la charge")
	g.player.slots[0].charges = D6Loadout.max_charges(g, 0)
	h.egal(D6Run._option_blocked(g, opt), false, "un seul plein : l'autre peut encore gagner")
	D6Run._apply_event(g, opt)
	h.egal(_charges(g), [D6Loadout.max_charges(g, 0), 1.0 + 2.0 * opt.gain, 0.0], "jamais au-delà du plein")
	var sans := _bac(h, "revenant", ["lance", "chaine", null])
	h.egal(D6Run._option_blocked(sans, opt), true, "aucun gadget équipé : grisé")

static func _f_repos(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 5.0, "startFloor": 3.0, "meta": _meta("revenant", ["nova", "bombe", "lance"])})
	D6Run.enter_floor(g, 4.0, {"reward": "rest"})
	for st in g.player.slots:
		st.charges = 0.0
	g.player.superCharge = 0.0
	g.player.x = g.room.interact.x
	g.player.y = g.room.interact.y
	var i := 0
	while i < 30 and g.mode != "choice":
		h.avancer(g, 1)
		i += 1
	if not h.egal(g.mode, "choice", "le repos s'ouvre"):
		return
	g.events.clear()
	h.egal(D6Game.apply_command(g, {"type": "choose", "index": 2.0}), true)
	h.egal(_charges(g), [D6Loadout.max_charges(g, 0), D6Loadout.max_charges(g, 1), 0.0])
	h.egal(_de(g.events, "gadgetCharge").map(func(ev): return ev.get("slot")), [0.0])

static func _f_super(h) -> void:
	var C = load("res://tests/regles/v2_contenu.gd")
	var g: Dictionary = C.arena(h, ["ripaille", "passion_brulante", "gloire_charnelle"])
	var pres: Dictionary = C.dummy(g, 150.0, 0.0, "brute", 1e6)
	g.player.hp = g.player.maxHp - 40.0
	g.player.superCharge = 1.0
	var hp0: float = g.player.hp
	C.ultime(h, g)
	h.egal(g.player.state, "super")
	h.egal(g.player.hp, hp0 + C.V("ripaille"), "Ripaille soigne au lancer")
	h.ok(pres.burn > 0.0, "Passion brûlante enflamme autour")
	h.proche(g.player.superT, g.tuning["super"].duration + D6Boons.boon_def("gloire_charnelle").superDurationBonus, 2.0 * DT, "Gloire charnelle allonge le Super")
