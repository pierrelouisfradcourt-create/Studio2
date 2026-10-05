extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_kits.test.mjs.
## Tests du lot KITS (V2) : classes, armes, compétences, gadgets, Supers.
##
##   - le kit par défaut (Revenant, Lame, Lance, Nova, Colère) est IDENTIQUE : mêmes valeurs
##     qu'avant les classes (recopiées ici), mêmes références dans le tuning de la partie ;
##   - chaque classe / arme / compétence / gadget / Super fonctionne en partie réelle (dégâts,
##     projectiles, zones, effets), sans erreur ;
##   - les statistiques de classe s'appliquent ; une arme d'une autre classe ne se manie pas ;
##   - les bénédictions (attaque, dash, compétence, Super) s'appliquent aux nouveaux kits ;
##   - déterminisme et invariants par classe (bot skilled) ;
##   - registre de la Ville (prix, listes) ; rendu et sons des kits : sans équivalent Godot.

const Bots = preload("res://outils/bots/bots.gd")

const WALL_EPS := 0.5
const DEFAULT_SEED := 11.0
const DUMMY_HP := 5000.0
const REAL_SEED := 7.0
const REAL_STEPS := 5000
const DETERMINISM_STEPS := 1800
const LOADOUTS := [
	["revenant", {"weapon": "dagues", "skill": "chaine", "gadget": "bombe"}],
	["bourreau", {"weapon": "hache", "skill": "bond", "gadget": "bombe"}],
	["bourreau", {"weapon": "marteau", "skill": "chaine", "gadget": "nova"}],
	["chasseresse", {"weapon": "arc", "skill": "volee", "gadget": "piege"}],
	["chasseresse", {"weapon": "arbalete", "skill": "brasier", "gadget": "totem"}],
]

static var _tuning = null

static func tests(h) -> void:
	_tests_defaut_et_registre(h)
	_tests_classes(h)
	_tests_armes(h)
	_tests_competences(h)
	_tests_gadgets_et_supers(h)
	_tests_benedictions(h)
	_tests_parties_reelles(h)
	h.test("rendu : monde, HUD et effets de chaque kit se dessinent sans erreur (contexte factice)", func():
		h.non_portable("teste le rendu web (src/render : drawWorld, drawHud, fx) sur un contexte 2D factice"))
	h.test("sons : chaque variante de kit (tir, compétence, gadget, Super, explosion du héros) joue sans erreur", func():
		h.non_portable("teste l'audio web (src/audio/sfx.mjs) sur un faux WebAudio"))

# ---------------------------------------------------------------- outillage

## T du fichier web : `createTuning()` partagé par tous les tests (jamais modifié).
static func _t() -> Dictionary:
	if _tuning == null:
		_tuning = D6Data.create_tuning()
	return _tuning

static func _kits() -> Dictionary:
	return D6Data.tables().kits

## Profil permanent : tout débloqué, la classe et le kit demandés équipés.
static func _kit_meta(class_id: String, kit: Dictionary = {}) -> Dictionary:
	var t := _t()
	var m: Dictionary = D6Profile.create_profile(t)
	for k in ["classes", "weapons", "skills", "gadgets"]:
		m.unlocked[k] = t[k].keys()
	var c: Dictionary = t.classes[class_id]
	m.loadout = {"classId": class_id, "slots": [kit.get("skill", c.skills[0]), kit.get("gadget", c.gadgets[0]), null]}
	m.equipment.arme = D6Profile.starter_weapon(t, kit.get("weapon", c.weapons[0]))
	m.equipment.arme.uid = "i9000"
	return m

## Partie de test : salle vidée (aucune vague), héros au centre, sans porte ni récompense.
static func _sandbox(h, meta: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var options := {"seed": DEFAULT_SEED, "meta": meta}
	options.merge(opts, true)
	var g: Dictionary = h.bac_a_sable(options)
	g.tuning.combat.critChance = 0.0 # dégâts lisibles : aucun critique aléatoire
	g.events.clear()
	return g

## Mannequin (create_enemy l'ajoute à la salle) : ne riposte pas, PV au choix.
static func _dummy(g: Dictionary, dx: float, dy: float, kind: String = "brute", hp: float = DUMMY_HP) -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.cooldown = 999.0
	e.hp = hp
	e.maxHp = hp
	return e

static func _hits(evs: Array, kind = null) -> Array:
	return evs.filter(func(e): return e.type == "hit" and (kind == null or e.get("kind") == kind))

static func _shots(g: Dictionary) -> Array:
	var fx = g.room.get("kitFx")
	return fx.shots if fx != null else []

static func _zones(g: Dictionary) -> Array:
	var fx = g.room.get("kitFx")
	return fx.zones if fx != null else []

static func _zones_of(g: Dictionary, kind: String) -> Array:
	return _zones(g).filter(func(z): return z.get("kind") == kind)

static func _has_event(evs: Array, type: String, champ: String = "", valeur = null) -> bool:
	return evs.any(func(ev): return ev.type == type and (champ == "" or ev.get(champ) == valeur))

static func _hit_ids(evs: Array, kind: String) -> Array:
	var ids: Array = []
	for ev in _hits(evs, kind):
		if not ids.has(ev.id):
			ids.append(ev.id)
	return ids

static func _hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)

static func _fini(v) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))

static func _num(d, key: String) -> float:
	if d == null:
		return 0.0
	var v = d.get(key)
	return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) else 0.0

# ---------------------------------------------------------------- kit par défaut : identique

## Valeurs du kit d'avant les classes (commit 680fa57), recopiées : le kit par défaut ne bouge pas.
static func _historic() -> Dictionary:
	return {
		"combo": [
			{"startup": 0.05, "active": 0.07, "recovery": 0.12, "range": 84.0, "arc": 140.0, "damage": 10.0, "knockback": 240.0, "lunge": 36.0, "hitstop": 0.04, "shake": 0.2},
			{"startup": 0.05, "active": 0.07, "recovery": 0.12, "range": 84.0, "arc": 140.0, "damage": 11.0, "knockback": 240.0, "lunge": 36.0, "hitstop": 0.04, "shake": 0.2},
			{"startup": 0.09, "active": 0.09, "recovery": 0.24, "range": 104.0, "arc": 220.0, "damage": 22.0, "knockback": 560.0, "lunge": 64.0, "hitstop": 0.085, "shake": 0.45},
		],
		"dashStrike": {"startup": 0.04, "active": 0.08, "recovery": 0.16, "range": 96.0, "arc": 120.0, "damage": 18.0, "knockback": 420.0, "lunge": 90.0, "hitstop": 0.06, "shake": 0.35},
		"lance": {"name": "Lance infernale", "kind": "lance", "text": "Projectile qui transperce 3 ennemis.", "cooldown": 4.0, "damage": 30.0, "speed": 900.0, "radius": 12.0, "range": 540.0, "pierce": 3.0, "knockback": 300.0, "hitstop": 0.05, "castTime": 0.08},
		"nova": {"name": "Nova de cendres", "kind": "nova", "text": "Onde qui repousse, étourdit et efface les projectiles.", "chargesPerSection": 3.0, "chargeOnEliteKill": 1.0, "radius": 150.0, "damage": 20.0, "knockback": 900.0, "stun": 0.9, "iframes": 0.25, "hitstop": 0.07, "shake": 0.4},
		"colere": {"name": "Colère", "kind": "colere", "text": "Tourbillon invulnérable de 1,4 s.", "startCharge": 0.4, "chargeDamage": 900.0, "duration": 1.4, "tickInterval": 0.12, "radius": 130.0, "damagePerTick": 9.0, "knockback": 260.0, "speedMult": 0.85, "shakePerTick": 0.1},
	}

static func _without_cost(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out.erase("cost")
	return out

static func _tests_defaut_et_registre(h) -> void:
	h.test("kit par défaut : Revenant, Lame, Lance, Nova et Colère gardent leurs valeurs d'origine", func(): _t_defaut_valeurs(h))
	h.test("kit par défaut : la partie résout des RÉFÉRENCES vers les entrées du registre", func(): _t_defaut_references(h))
	h.test("kit par défaut : une partie jouée ne crée jamais de tir ou de zone de kit", func(): _t_defaut_sans_kitfx(h))
	h.test("registre : 3 classes, 2 armes, 2 compétences et 2 gadgets par classe, un Super chacune", func(): _t_registre_listes(h))
	h.test("registre : chaque entrée a un prix en Âmes ; le départ de chaque classe est gratuit", func(): _t_registre_prix(h))
	h.test("registre : données pures (le tuning se clone et se sérialise)", func(): _t_registre_pur(h))
	h.test("Ville : débloquer une classe puis la choisir forge son arme de départ ; une arme débloquée va au coffre", func(): _t_ville(h))

static func _t_defaut_valeurs(h) -> void:
	var k := _kits()
	var hist := _historic()
	h.egal(k.DEFAULT_LOADOUT, {"classId": "revenant", "slots": ["lance", "nova", null]})
	h.egal(k.CLASSES.keys()[0], "revenant", "le Revenant reste la classe de départ")
	var rev: Dictionary = k.CLASSES.revenant
	h.egal(rev.stats, {})
	h.egal(rev.weapons[0], "lame")
	h.egal(rev.skills[0], "lance")
	h.egal(rev.gadgets[0], "nova")
	h.egal(rev["super"], "forme_damne") # combat V3, étape 2 : l'ultime du Revenant est la Forme du Damné
	h.egal(k.WEAPONS.lame.combo, hist.combo)
	h.egal(k.WEAPONS.lame.dashStrike, hist.dashStrike)
	h.egal(k.WEAPONS.lame.baseMult, 1.0)
	h.ok(not k.WEAPONS.lame.has("moveMult"), "la Lame ne module pas la vitesse du combo")
	h.ok(not k.WEAPONS.lame.has("aimRange"), "la Lame garde la visée assistée de mêlée")
	h.egal(_without_cost(k.SKILLS.lance), hist.lance)
	h.egal(_without_cost(k.GADGETS.nova), hist.nova)
	# Combat V3 : la Colère a gagné `holdTime` (le maintien qui la lance) ; le reste est l'historique.
	# Étape 2 : elle n'est plus l'ultime d'aucune classe (`reserve`) ; ses nombres n'ont pas bougé.
	var colere: Dictionary = k.SUPERS.colere.duplicate()
	h.ok(colere.erase("holdTime"), "la Colère porte holdTime")
	h.egal(colere.get("reserve"), true, "la Colère est gardée en réserve")
	colere.erase("reserve")
	h.egal(colere, hist.colere)
	# Le tuning par défaut pointe sur les entrées du kit (références, pas copies). Côté Godot, le
	# registre (tables) et le tuning sont deux fichiers de données : la référence se juge DANS le
	# tuning (t.combo EST t.weapons.lame.combo), l'identité avec le registre se juge par valeur.
	var t: Dictionary = D6Data.create_tuning()
	h.ok(is_same(t.combo, t.weapons.lame.combo), "combo : référence")
	h.ok(is_same(t.dashStrike, t.weapons.lame.dashStrike), "dashStrike : référence")
	h.ok(not t.has("skill") and not t.has("gadget"), "combat V3 : compétence et gadget n'ont plus de bloc actif (emplacements)")
	h.ok(is_same(t["super"], t.supers.colere), "super : référence")
	h.egal(t.combo, k.WEAPONS.lame.combo)
	h.egal(t.dashStrike, k.WEAPONS.lame.dashStrike)
	h.egal(t.skills.lance, k.SKILLS.lance)
	h.egal(t.gadgets.nova, k.GADGETS.nova)
	h.egal(t["super"], k.SUPERS.colere)

static func _t_defaut_references(h) -> void:
	var g: Dictionary = h.partie({"seed": 3.0})
	var t: Dictionary = g.tuning
	h.egal(g.kit, {"classId": "revenant", "weaponType": "lame", "slots": ["lance", "nova", null], "superId": "forme_damne"})
	h.ok(is_same(t.combo, t.weapons.lame.combo), "combo")
	h.ok(is_same(t.dashStrike, t.weapons.lame.dashStrike), "dashStrike")
	h.ok(is_same(t.weapon, t.weapons.lame), "weapon")
	h.ok(is_same(D6Loadout.slot_def(g, 0), t.skills.lance), "skill")
	h.ok(is_same(D6Loadout.slot_def(g, 1), t.gadgets.nova), "gadget")
	h.ok(is_same(t["super"], t.supers.forme_damne), "super")
	h.egal(g.player.maxHp, 100.0)
	h.egal(g.room.get("kitFx"), null, "le kit d'origine ne pose ni tir ni zone de kit")

static func _t_defaut_sans_kitfx(h) -> void:
	var g: Dictionary = h.partie({"seed": 5.0})
	var mem := {}
	for i in 3000:
		if g.mode == "dead":
			break
		if g.mode == "choice":
			Bots.resolve_choice(g, "skilled")
		D6Game.step_game(g, Bots.play("skilled", g, mem))
		g.events.clear()
		h.egal(g.room.get("kitFx"), null, "tick %s" % D6Js.num_str(g.tick))

# ---------------------------------------------------------------- registre (Ville)

static func _t_registre_listes(h) -> void:
	var k := _kits()
	h.ok(k.CLASSES.size() >= 3)
	h.ok(k.SKILLS.size() >= 4)
	h.ok(k.GADGETS.size() >= 3)
	h.egal(k.SUPERS.size(), 6) # trois ultimes de classe, trois anciens Supers en réserve
	h.egal(k.SUPERS.values().filter(func(s): return D6Js.truthy(s.get("reserve"))).size(), 3)
	var supers: Array = []
	for id in k.CLASSES:
		var c: Dictionary = k.CLASSES[id]
		h.ok(c.weapons.size() >= 2 and c.skills.size() >= 2 and c.gadgets.size() >= 2, "%s : listes trop courtes" % id)
		for w in c.weapons:
			h.ok(k.WEAPONS.get(w) != null, "%s : arme inconnue %s" % [id, w])
			h.egal(k.WEAPONS[w].className, id, "%s appartient à %s" % [w, id])
		for s in c.skills:
			h.ok(k.SKILLS.get(s) != null, "%s : compétence inconnue %s" % [id, s])
		for gd in c.gadgets:
			h.ok(k.GADGETS.get(gd) != null, "%s : gadget inconnu %s" % [id, gd])
		h.ok(k.SUPERS.get(c["super"]) != null, "%s : Super inconnu" % id)
		if not supers.has(c["super"]):
			supers.append(c["super"])
		var passive = c.get("passive")
		h.ok(passive != null and D6Js.truthy(passive.get("name")) and D6Js.truthy(passive.get("text")), "%s : passif lisible" % id)
	h.egal(supers.size(), 3, "un Super propre à chaque classe")

static func _t_registre_prix(h) -> void:
	var k := _kits()
	var tables := {"classes": k.CLASSES, "weapons": k.WEAPONS, "skills": k.SKILLS, "gadgets": k.GADGETS}
	for kind in tables:
		for id in tables[kind]:
			var d: Dictionary = tables[kind][id]
			var cost = d.get("cost")
			if kind == "skills" or kind == "gadgets":
				# Combat V3, étape 3 : une compétence n'a plus de prix en Âmes, l'arbre la débloque.
				h.egal(cost, null, "%s.%s : plus de cost" % [kind, id])
				h.egal(D6Profile.unlock_cost(_t(), kind, id), 0.0)
				continue
			h.ok(_fini(cost) and cost == floorf(cost) and cost >= 0.0, "%s.%s : cost %s" % [kind, id, str(cost)])
			h.egal(D6Profile.unlock_cost(_t(), kind, id), cost)
	h.egal(k.CLASSES.revenant.cost, 0.0)
	var p: Dictionary = D6Profile.new_profile(_t())
	p.souls = 1e6
	for class_id in k.CLASSES:
		var c: Dictionary = k.CLASSES[class_id]
		h.egal(k.WEAPONS[c.weapons[0]].cost, 0.0)
		# Le départ de la classe (1re compétence, 1re compétence à charges) est offert : rang 1 sans point.
		D6Profile.unlock(p, _t(), "classes", class_id)
		D6Profile.select_class(p, _t(), class_id)
		for x in D6Profile.slot_choices(p, _t()):
			h.egal(x.unlocked, x.id == c.skills[0] or x.id == c.gadgets[0], "%s : %s" % [class_id, x.id])
	for w in k.WEAPONS.values():
		_verifier_arme_du_registre(h, w)

static func _verifier_arme_du_registre(h, w: Dictionary) -> void:
	var bases = w.get("bases")
	h.ok(D6Js.truthy(w.get("starterName")) and bases is Array and bases.size() >= 1 and _num(w, "baseMult") > 0.0, "%s : starterName / bases / baseMult" % w.name)
	for def in w.combo + [w.dashStrike]:
		for key in ["startup", "active", "recovery", "range", "arc", "damage", "knockback", "lunge", "hitstop", "shake"]:
			h.ok(_fini(def.get(key)), "%s : %s manquant" % [w.name, key])
		if w.kind == "ranged":
			h.ok(_num(def.get("shot"), "speed") > 0.0 and _num(def.get("shot"), "radius") > 0.0, "%s : coup à distance sans shot" % w.name)

static func _t_registre_pur(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	for bloc in ["classes", "weapons", "skills", "gadgets", "supers"]:
		# JSON.parse(JSON.stringify(x)) : pleine précision, sinon l'aller-retour arrondit les doubles.
		h.egal(JSON.parse_string(JSON.stringify(t[bloc], "", false, true)), t[bloc], bloc)

static func _t_ville(h) -> void:
	var t := _t()
	var k := _kits()
	var p: Dictionary = D6Profile.create_profile(t)
	p.souls = 1000.0
	h.egal(D6Profile.select_class(p, t, "bourreau").ok, false, "classe verrouillée")
	h.egal(D6Profile.unlock(p, t, "classes", "bourreau").ok, true)
	h.egal(p.souls, 1000.0 - k.CLASSES.bourreau.cost)
	h.egal(D6Profile.select_class(p, t, "bourreau").ok, true)
	h.egal(p.equipment.arme.weaponType, "hache")
	h.egal(p.loadout.slots[0], "bond")
	h.egal(p.loadout.slots[1], "cri")
	var before: float = p.souls
	h.egal(D6Profile.unlock(p, t, "weapons", "marteau").ok, true)
	h.egal(p.souls, before - k.WEAPONS.marteau.cost)
	var marteau = null
	for it in p.stash:
		if it.get("weaponType") == "marteau":
			marteau = it
			break
	if not h.ok(marteau != null, "un maillet commun est forgé au coffre"):
		return
	h.egal(D6Profile.equip_from_stash(p, t, marteau.uid).ok, true)
	var g: Dictionary = h.partie({"seed": 2.0, "meta": p})
	h.egal(g.kit.classId, "bourreau")
	h.egal(g.kit.weaponType, "marteau")
	h.ok(is_same(g.tuning.combo, g.tuning.weapons.marteau.combo), "combo du marteau")
	h.ok(is_same(g.tuning["super"], g.tuning.supers.sentence_capitale), "Super du Bourreau")

# ---------------------------------------------------------------- statistiques de classe

static func _tests_classes(h) -> void:
	h.test("classes : statistiques appliquées (PV, armure, vitesse, longueur du dash)", func(): _t_classes_stats(h))
	h.test("classes : une arme d'une autre classe ne se manie pas", func(): _t_classes_arme_etrangere(h))

static func _dash_len(h, class_id: String) -> float:
	var g := _sandbox(h, _kit_meta(class_id))
	var x0: float = g.player.x
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	h.avancer(g, h.ticks(g.tuning.dash.duration), {"moveX": 0.0})
	return g.player.x - x0

static func _t_classes_stats(h) -> void:
	var classes: Dictionary = _kits().CLASSES
	var rev := _sandbox(h, _kit_meta("revenant"))
	var bou := _sandbox(h, _kit_meta("bourreau"))
	var cha := _sandbox(h, _kit_meta("chasseresse"))
	h.egal(rev.player.maxHp, 100.0)
	h.egal(bou.player.maxHp, 100.0 + classes.bourreau.stats.maxHpBonus)
	h.egal(cha.player.maxHp, 100.0 + classes.chasseresse.stats.maxHpBonus)
	h.egal(bou.player.hp, bou.player.maxHp)
	h.ok(absf(bou.player.stats.armor - classes.bourreau.stats.armor) < 1e-9)
	h.ok(absf(cha.player.stats.moveSpeedMult - (1.0 + classes.chasseresse.stats.moveSpeedMult)) < 1e-9)
	var base: float = _t().dash.distance
	var dr := _dash_len(h, "revenant")
	var db := _dash_len(h, "bourreau")
	var dc := _dash_len(h, "chasseresse")
	h.ok(absf(dr - base) < 12.0, "Revenant : dash %s" % dr)
	h.ok(absf(db - base * (1.0 + classes.bourreau.stats.dashDistanceMult)) < 12.0, "Bourreau : dash %s" % db)
	h.ok(absf(dc - base * (1.0 + classes.chasseresse.stats.dashDistanceMult)) < 15.0, "Chasseresse : dash %s" % dc)
	h.ok(db < dr and dr < dc, "dash court < étalon < dash long")
	# L'armure du Bourreau réduit vraiment un coup reçu.
	bou.player.iframes = 0.0
	rev.player.iframes = 0.0
	var hb: float = bou.player.hp
	var hr: float = rev.player.hp
	D6Combat.damage_player(bou, 40.0, {"kind": "test", "id": 1.0})
	D6Combat.damage_player(rev, 40.0, {"kind": "test", "id": 1.0})
	h.ok(hb - bou.player.hp < hr - rev.player.hp, "le Bourreau encaisse moins")

static func _t_classes_arme_etrangere(h) -> void:
	var t := _t()
	var rev: Dictionary = h.partie({"seed": 1.0})
	var cha: Dictionary = h.partie({"seed": 1.0, "meta": _kit_meta("chasseresse")})
	var arc: Dictionary = D6Profile.starter_weapon(t, "arc")
	h.egal(D6Run.can_wield(rev, arc), false)
	h.egal(D6Run.can_wield(cha, arc), true)
	h.egal(D6Run.can_wield(cha, D6Profile.starter_weapon(t, "lame")), false)
	# Le coffre refuse de l'équiper ; un profil qui la porterait la range au coffre.
	var p := _kit_meta("revenant")
	var hache: Dictionary = D6Profile.starter_weapon(t, "hache")
	hache.uid = "i77"
	p.stash.append(hache)
	h.egal(D6Profile.equip_from_stash(p, t, "i77").ok, false)
	var m := _kit_meta("revenant")
	var arbalete: Dictionary = D6Profile.starter_weapon(t, "arbalete")
	arbalete.uid = "i78"
	m.equipment.arme = arbalete
	var g: Dictionary = h.partie({"seed": 1.0, "meta": m})
	h.egal(g.kit.weaponType, "lame", "retour à une arme de la classe")
	h.ok(g.meta.stash.any(func(it): return D6Comparer.diff(it.get("uid"), "i78") == ""), "l'arbalète est au coffre, pas perdue")

# ---------------------------------------------------------------- armes en partie réelle

static func _tests_armes(h) -> void:
	var weapons: Dictionary = _kits().WEAPONS
	for wt in weapons:
		var w: Dictionary = weapons[wt]
		h.test("arme %s : le combo enchaîne tous ses coups et blesse (%s)" % [wt, w.kind], func(): _t_arme_combo(h, wt, w))
		h.test("arme %s : frappe de dash propre (source 'strike')" % wt, func(): _t_arme_frappe_de_dash(h, wt, w))
	h.test("arme à distance : visée manuelle (le trait part dans la direction visée, même sans cible)", func(): _t_visee_manuelle(h))
	h.test("arme à distance : visée assistée vers un ennemi hors de portée de mêlée", func(): _t_visee_assistee(h))
	h.test("arme lourde : le finisher de la hache étourdit ; l'arme règle la mobilité du combo", func(): _t_arme_lourde(h))

static func _t_arme_combo(h, wt: String, w: Dictionary) -> void:
	var g := _sandbox(h, _kit_meta(w.className, {"weapon": wt}))
	h.egal(g.kit.weaponType, wt)
	h.ok(is_same(g.tuning.combo, g.tuning.weapons[wt].combo), "le combo actif est celui de l'arme")
	var ranged: bool = w.kind == "ranged"
	var e := _dummy(g, 220.0 if ranged else 60.0, 0.0)
	e.mass = 1000.0 # le recul ne l'éjecte pas de la portée
	var max_shots := 0
	var evs: Array = []
	for i in h.ticks(3.0):
		max_shots = maxi(max_shots, _shots(g).size())
		evs.append_array(h.avancer(g, 1, {"attack": true, "attackPressed": i == 0, "aimX": 1.0, "aimY": 0.0}))
	var indices: Array = evs.filter(func(ev): return ev.type == "attackStart").map(func(ev): return float(ev.index))
	for i in w.combo.size():
		h.ok(indices.has(float(i)), "coup %d jamais joué" % i)
	h.ok(e.hp < e.maxHp, "le mannequin est blessé")
	var melee := _hits(evs, "melee")
	h.ok(melee.size() >= w.combo.size(), "%d coups portés" % melee.size())
	if ranged:
		h.ok(max_shots >= 1, "des traits sont en vol")
		h.ok(evs.any(func(ev): return ev.type == "swing" and D6Js.truthy(ev.get("ranged"))), "swing marqué ranged (son, effet)")
	else:
		h.egal(max_shots, 0, "une arme de mêlée ne tire pas")
	# Les dégâts suivent le coup joué (dégâts de base × arme de base).
	var amounts: Array = melee.map(func(ev): return float(ev.amount))
	for def in w.combo:
		h.ok(amounts.has(float(def.damage)), "dégâts %s jamais vus (%s)" % [str(def.damage), str(amounts)])

static func _t_arme_frappe_de_dash(h, wt: String, w: Dictionary) -> void:
	var g := _sandbox(h, _kit_meta(w.className, {"weapon": wt}))
	var e := _dummy(g, 260.0 if w.kind == "ranged" else 150.0, 0.0)
	e.mass = 1000.0
	h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	var t: Dictionary = g.tuning.dash
	h.avancer(g, h.ticks(t.duration * (1.0 - t.strikeCancelFrom)) + 1, {"moveX": 1.0})
	h.avancer(g, 1, {"attackPressed": true, "aimX": 1.0, "aimY": 0.0})
	var attack = g.player.get("attack")
	if not h.ok(attack != null and attack.get("strike") == true, "une frappe de dash est en cours"):
		return
	h.ok(is_same(attack.def, g.tuning.weapons[wt].dashStrike), "le coup joué est la frappe de dash de l'arme")
	var evs: Array = h.avancer(g, h.ticks(0.6))
	var strikes := _hits(evs, "strike")
	if h.ok(strikes.size() >= 1, "la frappe de dash touche"):
		h.egal(strikes[0].amount, w.dashStrike.damage)

static func _t_visee_manuelle(h) -> void:
	var g := _sandbox(h, _kit_meta("chasseresse"))
	h.avancer(g, 1, {"attack": true, "attackPressed": true, "aimX": 0.0, "aimY": 1.0})
	h.avancer(g, h.ticks(_kits().WEAPONS.arc.combo[0].startup) + 1, {"attack": true, "aimX": 0.0, "aimY": 1.0})
	if not h.ok(_shots(g).size() > 0, "un trait est parti"):
		return
	var s: Dictionary = _shots(g)[0]
	h.ok(s.vy > 0.0 and absf(s.vx) < 1e-6, "direction (%s, %s)" % [s.vx, s.vy])

static func _t_visee_assistee(h) -> void:
	var g := _sandbox(h, _kit_meta("chasseresse"))
	var e := _dummy(g, -300.0, 0.0, "imp", 100.0)
	h.avancer(g, 1, {"attack": true, "attackPressed": true})
	h.avancer(g, h.ticks(0.15), {"attack": true})
	h.ok(_shots(g).size() > 0 and _shots(g)[0].vx < 0.0, "le trait part vers l'ennemi à 300 u")
	h.avancer(g, h.ticks(0.5), {"attack": true})
	h.ok(e.hp < e.maxHp)

## Vitesse pendant un coup : hache 0,5 × 0,7 ; dagues min(1, 0,5 × 1,5) ; Lame 0,5.
static func _speed_during(h, class_id: String, weapon: String) -> float:
	var g := _sandbox(h, _kit_meta(class_id, {"weapon": weapon}))
	h.avancer(g, 1, {"attackPressed": true, "aimX": 0.0, "aimY": -1.0})
	h.avancer(g, 2, {"moveX": 1.0, "attack": true, "aimX": 0.0, "aimY": -1.0})
	return absf(g.player.vx) if g.player.get("attack") != null else NAN

static func _t_arme_lourde(h) -> void:
	var t := _t()
	var g := _sandbox(h, _kit_meta("bourreau"))
	var e := _dummy(g, 70.0, 0.0, "imp", 5000.0)
	e.mass = 1000.0
	var stunned := false
	for i in h.ticks(2.0):
		if e.stun > 0.0:
			stunned = true
		h.avancer(g, 1, {"attack": true, "attackPressed": i == 0, "aimX": 1.0, "aimY": 0.0})
	h.ok(stunned, "le 3e coup étourdit")
	var lame := _speed_during(h, "revenant", "lame")
	var dagues := _speed_during(h, "revenant", "dagues")
	var hache := _speed_during(h, "bourreau", "hache")
	h.ok(absf(lame - t.player.speed * t.player.attackMoveMult) < 1e-6, "Lame %s" % lame)
	h.ok(dagues > lame and hache < lame, "dagues %s, hache %s" % [dagues, hache])

# ---------------------------------------------------------------- compétences

static func _tests_competences(h) -> void:
	h.test("compétence Chaîne d'Enfer : harponne, étourdit et TIRE l'ennemi contre le héros", func(): _t_chaine(h))
	h.test("compétence Chaîne d'Enfer : un Gardien n'est pas tiré", func(): _t_chaine_gardien(h))
	h.test("compétence Bond : saut invulnérable vers la cible, impact qui blesse et étourdit", func(): _t_bond(h))
	h.test("compétence Bond : interrompue par un dash, elle atterrit quand même (recharge jamais perdue)", func(): _t_bond_interrompu(h))
	h.test("compétence Brasier d'âmes : pot lancé sur la cible, impact puis sol qui brûle, puis s'éteint", func(): _t_brasier(h))
	h.test("compétence Volée d'épines : éventail de traits de compétence", func(): _t_volee(h))

static func _t_chaine(h) -> void:
	var g := _sandbox(h, _kit_meta("revenant", {"skill": "chaine"}))
	var e := _dummy(g, 300.0, 0.0, "imp", 500.0)
	var d0: float = e.x - g.player.x
	var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	evs.append_array(h.avancer(g, h.ticks(0.6)))
	h.ok(_has_event(evs, "hook"), "événement hook")
	h.ok(_hits(evs, "skill").size() >= 1, "dégâts de compétence")
	var d1 := _hypot(e.x - g.player.x, e.y - g.player.y)
	h.ok(d1 < d0 * 0.4, "tiré : %s -> %.0f" % [d0, d1])
	h.ok(d1 > g.player.r + e.r - 1.0, "pas à travers le héros")
	h.ok(g.player.slots[0].cd > 0.0)
	h.egal(g.telemetry.skillCasts, 1.0)

static func _t_chaine_gardien(h) -> void:
	var g := _sandbox(h, _kit_meta("revenant", {"skill": "chaine"}))
	var b: Dictionary = D6Enemies.create_enemy(g, "gardien", g.player.x + 300.0, g.player.y, {"boss": true, "spawnT": 0.0})
	b.cooldown = 999.0
	b.state = "rest"
	b.restFor = 99.0
	h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	var max_pull := 0.0
	for i in h.ticks(0.5):
		h.avancer(g, 1)
		max_pull = maxf(max_pull, _hypot(b.kvx, b.kvy))
	h.ok(b.hp < b.maxHp, "le Gardien est touché")
	h.ok(max_pull < 1.0, "le Gardien n'est pas tiré (élan %s)" % max_pull)

static func _t_bond(h) -> void:
	var g := _sandbox(h, _kit_meta("bourreau"))
	var e := _dummy(g, 220.0, 0.0, "imp", 500.0)
	var x0: float = g.player.x
	h.avancer(g, 1, {"skill1Pressed": true})
	h.egal(g.player.state, "cast")
	h.ok(g.player.iframes > 0.0, "invulnérable dès le saut")
	h.avancer(g, 3)
	h.egal(D6Combat.damage_player(g, 30.0, {"kind": "test", "id": 9.0}), false, "aucun coup ne porte pendant le saut")
	var evs: Array = h.avancer(g, h.ticks(_kits().SKILLS.bond.leapTime) + 2)
	h.egal(g.player.state, "free")
	h.ok(g.player.x - x0 > 120.0, "le héros a bondi (%.0f u)" % (g.player.x - x0))
	h.ok(evs.any(func(ev): return ev.type == "explode" and D6Js.truthy(ev.get("hero")) and ev.get("kind") == "bond"), "impact")
	h.ok(_hits(evs, "skill").size() >= 1)
	h.ok(e.stun > 0.0 or e.hp < e.maxHp)

static func _t_bond_interrompu(h) -> void:
	var g := _sandbox(h, _kit_meta("bourreau"))
	_dummy(g, 200.0, 0.0, "imp", 500.0)
	h.avancer(g, 1, {"skill1Pressed": true})
	h.avancer(g, 4)
	var evs: Array = h.avancer(g, 1, {"moveX": -1.0, "dashPressed": true})
	h.egal(g.player.state, "dash")
	h.ok(_has_event(evs, "explode", "kind", "bond"), "impact au moment du dash")
	h.egal(g.player.get("cast"), null)

static func _t_brasier(h) -> void:
	var sk: Dictionary = _kits().SKILLS.brasier
	var g := _sandbox(h, _kit_meta("chasseresse", {"skill": "brasier"}))
	var e := _dummy(g, 200.0, 0.0, "brute", 2000.0)
	e.mass = 1000.0
	e.stun = 99.0 # immobile : on juge le point de chute
	h.avancer(g, 1, {"skill1Pressed": true})
	var evs: Array = h.avancer(g, h.ticks(sk.castTime + sk.flight) + 3)
	h.ok(_has_event(evs, "explode", "kind", "brasier"), "le pot éclate")
	h.ok(_hits(evs, "skill").size() >= 1, "impact de compétence")
	var zs := _zones_of(g, "brasier")
	if h.ok(zs.size() > 0, "le sol brûle"):
		h.ok(_hypot(zs[0].x - e.x, zs[0].y - e.y) < 40.0, "le pot est tombé sur la cible")
	evs = h.avancer(g, h.ticks(1.0))
	h.ok(e.burn > 0.0, "l'ennemi dans la zone brûle")
	h.ok(_hits(evs, "burn").size() >= 1, "la brûlure inflige des dégâts")
	h.avancer(g, h.ticks(sk.duration))
	h.egal(_zones(g).size(), 0, "la zone s'éteint")

static func _t_volee(h) -> void:
	var g := _sandbox(h, _kit_meta("chasseresse"))
	var e := _dummy(g, 60.0, 0.0, "brute", 2000.0)
	e.mass = 1000.0
	h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	var evs: Array = h.avancer(g, h.ticks(_kits().SKILLS.volee.castTime) + 1)
	var fan: Array = _shots(g).filter(func(s): return s.get("kind") == "thorn")
	h.egal(fan.size() + _hit_ids(evs, "skill").size() > 0, true)
	evs.append_array(h.avancer(g, h.ticks(0.4)))
	h.ok(_hits(evs, "skill").size() >= 3, "%d épines ont touché" % _hits(evs, "skill").size())
	h.egal(g.telemetry.skillCasts, 1.0)

# ---------------------------------------------------------------- gadgets et Supers

static func _tests_gadgets_et_supers(h) -> void:
	h.test("gadget Bombe : lancée sur l'ennemi, explose après la mèche, étourdit, efface les tirs ennemis", func(): _t_bombe(h))
	h.test("gadget Piège : se referme sur le premier ennemi qui passe ; trois pièges au plus", func(): _t_piege(h))
	h.test("gadget Cri du bourreau : étourdit et rend vulnérable autour du héros, sans repousser", func(): _t_cri(h))
	h.test("gadget Totem de givre : impulsions qui blessent et ralentissent à portée", func(): _t_totem(h))
	h.test("Super Sentence : invulnérable, trois exécutions, la dernière à 360° étourdit", func(): _t_sentence(h))
	h.test("Super Nuée de traits : invulnérable, tirs en rotation sur les ennemis proches", func(): _t_nuee(h))

static func _t_bombe(h) -> void:
	var gd: Dictionary = _kits().GADGETS.bombe
	var g := _sandbox(h, _kit_meta("bourreau", {"gadget": "bombe"}))
	var e := _dummy(g, 200.0, 0.0, "imp", 500.0)
	var c0: float = g.player.slots[1].charges
	h.avancer(g, 1, {"skill2Pressed": true})
	h.egal(g.player.slots[1].charges, c0 - 1.0)
	var bombes := _zones_of(g, "bombe")
	h.ok(bombes.size() > 0 and _hypot(bombes[0].tx - e.x, bombes[0].ty - e.y) < 20.0, "visée sur l'ennemi")
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": e.x, "y": e.y - 40.0, "vx": 0.0, "vy": 0.0, "r": 7.0, "damage": 10.0, "range": 600.0})
	var evs: Array = h.avancer(g, h.ticks(gd.flight + gd.fuse) + 2)
	h.ok(_has_event(evs, "explode", "kind", "bombe"), "explosion")
	h.ok(_hits(evs, "gadget").any(func(ev): return ev.id == e.id), "la cible est touchée")
	h.ok(e.stun > 0.0, "étourdi")
	h.egal(g.projectiles.filter(func(p): return p.get("owner") == "enemy" and not D6Js.truthy(p.get("dead"))).size(), 0, "le souffle efface les tirs")
	h.egal(_zones(g).size(), 0)

static func _t_piege(h) -> void:
	var gd: Dictionary = _kits().GADGETS.piege
	var g := _sandbox(h, _kit_meta("chasseresse"))
	h.avancer(g, 1, {"skill2Pressed": true})
	if not h.ok(_zones(g).size() > 0, "un piège est posé"):
		return
	var trap: Dictionary = _zones(g)[0]
	h.egal(trap.kind, "piege")
	h.avancer(g, h.ticks(gd.armTime) + 1)
	var e := _dummy(g, 0.0, 0.0, "imp", 500.0)
	e.x = trap.x + 200.0
	e.y = trap.y
	e.cooldown = 999.0
	var evs: Array = []
	for i in h.ticks(1.0):
		e.x -= 8.0 # l'ennemi marche sur le piège
		evs.append_array(h.avancer(g, 1))
		if e.stun > 0.0:
			break
	h.ok(_has_event(evs, "explode", "kind", "piege"), "le piège se referme")
	h.ok(e.stun > 1.0, "immobilisé")
	h.ok(_hits(evs, "gadget").size() >= 1)
	# Pose de 4 pièges : le plus ancien se désarme.
	var g2 := _sandbox(h, _kit_meta("chasseresse"))
	for i in 4:
		g2.player.x += 80.0
		h.avancer(g2, 1, {"skill2Pressed": true})
		h.avancer(g2, 2)
	h.egal(_zones_of(g2, "piege").size(), gd.maxActive)

static func _t_cri(h) -> void:
	var g := _sandbox(h, _kit_meta("bourreau"))
	h.egal(g.kit.slots[1], "cri", "gadget de départ du Bourreau")
	var near := _dummy(g, 120.0, 0.0, "imp", 500.0)
	var far := _dummy(g, 420.0, 0.0, "imp", 500.0)
	var evs: Array = h.avancer(g, 1, {"skill2Pressed": true})
	h.ok(_has_event(evs, "gadget", "gadget", "cri"))
	h.ok(near.stun > 0.0 and near.vuln > 0.0 and near.vulnMult > 0.0, "proche : étourdi et vulnérable")
	h.ok(_hypot(near.kvx, near.kvy) < 1.0, "aucun recul")
	h.egal(far.vuln, 0.0, "lointain : intact")

static func _t_totem(h) -> void:
	var g := _sandbox(h, _kit_meta("chasseresse", {"gadget": "totem"}))
	var near := _dummy(g, 100.0, 0.0, "imp", 500.0)
	var far := _dummy(g, 400.0, 0.0, "imp", 500.0)
	near.stun = 99.0 # immobiles : la portée du totem se juge sur place
	far.stun = 99.0
	h.avancer(g, 1, {"skill2Pressed": true})
	var evs: Array = h.avancer(g, h.ticks(1.2))
	h.ok(evs.filter(func(ev): return ev.type == "kitPulse").size() >= 2, "impulsions")
	h.ok(near.hp < near.maxHp and near.chillMult < 1.0, "proche : blessé et ralenti")
	h.egal(far.hp, far.maxHp, "lointain : intact")
	h.avancer(g, h.ticks(_kits().GADGETS.totem.life))
	h.egal(_zones(g).size(), 0, "le totem s'efface")

static func _t_sentence(h) -> void:
	var sup: Dictionary = _kits().SUPERS.sentence
	# Combat V3, étape 2 : la Sentence n'est plus l'ultime du Bourreau ; elle est lancée directement.
	var g := _sandbox(h, _kit_meta("bourreau"), {"tuning": {"classes": {"bourreau": {"super": "sentence"}}}})
	var e := _dummy(g, 90.0, 0.0, "brute", 5000.0)
	e.mass = 1000.0
	var back := _dummy(g, -100.0, 0.0, "imp", 5000.0)
	back.mass = 1000.0
	g.player.superCharge = 1.0
	var evs: Array = h.ultime(g)
	h.egal(g.player.state, "super")
	var hp: float = g.player.hp
	D6Combat.damage_player(g, 50.0, {"kind": "test", "id": 5.0})
	h.egal(g.player.hp, hp, "invulnérable")
	# Les exécutions gèlent la scène (gel d'impact) : le Super dure plus de pas que sa durée.
	for i in h.ticks(sup.duration + 1.0):
		if g.player.state != "super":
			break
		evs.append_array(h.avancer(g, 1))
	var ticks_ev: Array = evs.filter(func(ev): return ev.type == "superTick" and ev.get("super") == "sentence")
	h.egal(ticks_ev.size(), sup.strikes.size())
	var touches := _hit_ids(evs, "super")
	h.ok(touches.has(e.id) and touches.has(back.id), "le fracas final touche aussi derrière")
	h.ok(back.stun > 0.0, "étourdi par le fracas")
	h.egal(g.player.state, "free")
	h.egal(g.player.superCharge, 0.0, "les coups du Super ne rechargent pas la jauge")

static func _t_nuee(h) -> void:
	# Combat V3, étape 2 : la Nuée n'est plus l'ultime de la Chasseresse ; elle est lancée directement.
	var g := _sandbox(h, _kit_meta("chasseresse"), {"tuning": {"classes": {"chasseresse": {"super": "nuee"}}}})
	var a := _dummy(g, 200.0, 0.0, "imp", 5000.0)
	var b := _dummy(g, -200.0, 50.0, "imp", 5000.0)
	g.player.superCharge = 1.0
	h.ultime(g)
	h.egal(g.player.state, "super")
	h.egal(D6Combat.damage_player(g, 50.0, {"kind": "test", "id": 6.0}), false)
	var evs: Array = []
	for i in h.ticks(_kits().SUPERS.nuee.duration + 1.0):
		if g.player.state != "super":
			break
		evs.append_array(h.avancer(g, 1, {"moveX": 0.5}))
	var sup := _hits(evs, "super")
	var touches := _hit_ids(evs, "super")
	h.ok(touches.has(a.id) and touches.has(b.id), "les deux cibles reçoivent des traits")
	h.ok(sup.size() >= 8, "%d traits ont touché" % sup.size())
	h.egal(g.player.state, "free")

# ---------------------------------------------------------------- bénédictions sur les kits

static func _tests_benedictions(h) -> void:
	h.test("bénédictions : attaque (brûlure) sur les traits de l'arc, compétence (vulnérabilité) sur la Chaîne", func(): _t_boons_attaque_competence(h))
	h.test("bénédictions : dash (Pas de braise) pour toute classe ; Super (Gloire charnelle) sur la Sentence", func(): _t_boons_dash_super(h))

static func _t_boons_attaque_competence(h) -> void:
	var g := _sandbox(h, _kit_meta("chasseresse"))
	D6Boons.add_boon(g.run, {"id": "lame_ardente", "rarity": "commun"})
	D6Stats.recompute_stats(g)
	var e := _dummy(g, 200.0, 0.0, "brute", 5000.0)
	e.mass = 1000.0
	h.avancer(g, h.ticks(0.6), func(i): return {"attack": true, "attackPressed": i == 0, "aimX": 1.0, "aimY": 0.0})
	h.ok(e.burn > 0.0, "les traits (source melee) enflamment")

	var g2 := _sandbox(h, _kit_meta("revenant", {"skill": "chaine"}))
	D6Boons.add_boon(g2.run, {"id": "charme", "rarity": "commun"})
	D6Stats.recompute_stats(g2)
	var f := _dummy(g2, 250.0, 0.0, "imp", 500.0)
	h.avancer(g2, 1, {"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0})
	h.avancer(g2, h.ticks(0.4))
	h.ok(f.vuln > 0.0, "la Chaîne (source skill) rend vulnérable")

## Premier coup de la Sentence, avec ou sans Gloire charnelle : {amount, superT}.
static func _first_strike(h, boon: bool) -> Dictionary:
	var g := _sandbox(h, _kit_meta("bourreau"), {"tuning": {"classes": {"bourreau": {"super": "sentence"}}}}) # l'ancienne Sentence, lancée directement
	if boon:
		D6Boons.add_boon(g.run, {"id": "gloire_charnelle", "rarity": "commun"})
		D6Stats.recompute_stats(g)
	var e := _dummy(g, 90.0, 0.0, "brute", 5000.0)
	e.mass = 1000.0
	g.player.superCharge = 1.0
	var evs: Array = h.ultime(g) # le pas où le Super part, puis le reste des 0,4 s
	evs.append_array(h.avancer(g, h.ticks(0.4) - 1))
	var sup := _hits(evs, "super")
	if not h.ok(sup.size() > 0, "le Super porte un premier coup"):
		return {"amount": NAN, "superT": NAN}
	return {"amount": sup[0].amount, "superT": g.player.superT}

static func _t_boons_dash_super(h) -> void:
	var g := _sandbox(h, _kit_meta("bourreau"))
	D6Boons.add_boon(g.run, {"id": "pas_de_braise", "rarity": "commun"})
	D6Stats.recompute_stats(g)
	var evs: Array = h.avancer(g, 1, {"moveX": 1.0, "dashPressed": true})
	h.ok(_has_event(evs, "dashNova"))
	var plain := _first_strike(h, false)
	var boosted := _first_strike(h, true)
	h.ok(boosted.amount > plain.amount * 1.3, "%s -> %s" % [plain.amount, boosted.amount])
	h.ok(boosted.superT > plain.superT, "le Super dure plus longtemps")

# ---------------------------------------------------------------- parties réelles par classe

static func _inside_obstacle(room: Dictionary, x: float, y: float, tol: float) -> bool:
	return room.obstacles.any(func(o): return x > o.x0 + tol and x < o.x1 - tol and y > o.y0 + tol and y < o.y1 - tol)

static func _check_invariants(h, g: Dictionary, where: String) -> void:
	var p: Dictionary = g.player
	var room: Dictionary = g.room
	h.ok(_fini(p.x) and _fini(p.y) and _fini(p.vx) and _fini(p.vy), "%s : héros non fini" % where)
	var lo: float = room.pad + p.r - WALL_EPS
	h.ok(p.x >= lo and p.x <= room.w - lo and p.y >= lo and p.y <= room.h - lo, "%s : héros hors des murs" % where)
	h.ok(not _inside_obstacle(room, p.x, p.y, p.r * 0.5), "%s : héros dans un obstacle" % where)
	h.ok(p.hp >= 0.0 and p.hp <= p.maxHp, "%s : PV %s/%s" % [where, p.hp, p.maxHp])
	h.egal(p.hp <= 0.0, p.state == "dead", "%s : PV et état incohérents" % where)
	h.ok(p.dashCharges >= 0.0 and p.dashCharges <= D6Player.max_dash_charges(g), "%s : charges de dash" % where)
	h.ok(p.slots.all(func(s): return s.charges >= 0.0), "%s : charges de gadget" % where)
	h.ok(p.superCharge >= 0.0 and p.superCharge <= 1.0, "%s : jauge de Super" % where)
	for e in g.enemies:
		if e.dead:
			continue
		h.ok(_fini(e.x) and _fini(e.y) and _fini(e.kvx) and _fini(e.kvy), "%s : %s non fini" % [where, e.kind])
		h.ok(not _inside_obstacle(room, e.x, e.y, 6.0), "%s : %s dans un obstacle (traction ?)" % [where, e.kind])
		h.ok(e.hp > 0.0 and e.hp <= e.maxHp, "%s : %s PV %s" % [where, e.kind, e.hp])
	for s in _shots(g):
		h.ok(_fini(s.x) and _fini(s.y) and _fini(s.vx) and _fini(s.vy) and s.traveled <= s.range + 60.0, "%s : tir %s" % [where, s.kind])
	for z in _zones(g):
		h.ok(_fini(z.get("x")) and _fini(z.get("y")) and _fini(z.get("t")), "%s : zone %s" % [where, z.kind])

static func _play_class(h, meta: Dictionary, seed_n: float, steps: int, check: bool) -> Dictionary:
	var g: Dictionary = h.partie({"seed": seed_n, "meta": meta})
	var mem := {}
	for i in steps:
		if g.mode == "dead":
			break
		var k := 0
		while k < 8 and g.mode == "choice":
			Bots.resolve_choice(g, "skilled")
			k += 1
		if g.mode != "play":
			break
		D6Game.step_game(g, Bots.play("skilled", g, mem))
		h.ok(g.events.size() <= 500, "trop d'événements en une image")
		g.events.clear()
		if check:
			_check_invariants(h, g, "tick %s étage %s" % [D6Js.num_str(g.tick), D6Js.num_str(g.run.floor)])
	return g

static func _tests_parties_reelles(h) -> void:
	for entry in LOADOUTS:
		var cls: String = entry[0]
		var kit: Dictionary = entry[1]
		h.test("partie réelle %s (%s) : invariants tenus, chaque aptitude sert" % [cls, ", ".join(PackedStringArray(kit.values()))], func(): _t_partie_reelle(h, cls, kit))
	h.test("déterminisme par classe : même graine => même partie (tirs et zones compris) ; graines différentes => parties différentes", func(): _t_determinisme(h))

static func _t_partie_reelle(h, cls: String, kit: Dictionary) -> void:
	var g := _play_class(h, _kit_meta(cls, kit), REAL_SEED, REAL_STEPS, true)
	var tel: Dictionary = g.telemetry
	h.ok(g.run.floor >= 4.0, "le bot progresse (étage %s)" % g.run.floor)
	h.ok(tel.kills >= 15.0, "tués %s" % tel.kills)
	h.ok(tel.hitsLanded > 0.0 and tel.skillCasts > 0.0 and tel.superUses > 0.0, "coups %s, compétence %s, Super %s" % [tel.hitsLanded, tel.skillCasts, tel.superUses])

## Signature d'une partie : empreinte d'état, tirs et zones de kit, dégâts infligés, abscisse du héros.
static func _sig(h, cls: String, kit: Dictionary, seed_n: float) -> Array:
	var g := _play_class(h, _kit_meta(cls, kit), seed_n, DETERMINISM_STEPS, false)
	return [D6Game.state_hash(g), D6Js.clone(g.room.get("kitFx")), g.telemetry.damageDealt, "%.3f" % g.player.x]

static func _t_determinisme(h) -> void:
	for entry in LOADOUTS:
		var cls: String = entry[0]
		var kit: Dictionary = entry[1]
		h.egal(_sig(h, cls, kit, 3.0), _sig(h, cls, kit, 3.0), "%s : même graine, partie différente" % cls)
		h.different(_sig(h, cls, kit, 3.0), _sig(h, cls, kit, 4.0), "%s : graines différentes, même partie" % cls)
