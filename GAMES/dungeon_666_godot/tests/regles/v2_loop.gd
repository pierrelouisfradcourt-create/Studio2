extends RefCounted
## Portage de GAMES/dungeon_666/tests/v2_loop.test.mjs.
## Tests V2 — LA BOUCLE : Ville → donjon → Gardien → checkpoint, PERMANENT vs TEMPORAIRE, et
## le LABO du feel (D5, D8, D9 restent ouvertes : on teste que chaque variante fait ce qu'elle dit,
## jamais laquelle est « la bonne »).
##
## Les valeurs viennent du tuning ou du profil, jamais recopiées : un réglage ne casse pas un
## test, une règle cassée oui. Le contenu d'essai (classe, arme, compétence, gadget payants) est
## AJOUTÉ à une copie du tuning sous des identifiants « v2t_* » : ces tests ne dépendent pas du
## catalogue réel des kits, qui évolue en parallèle.

const Bots = preload("res://outils/bots/bots.gd")
const Episode = preload("res://outils/bots/episode.gd")

const SETTLE_TICKS := 240 # garde-fou des boucles « jusqu'à ce que… »
const DETERMINISM_TICKS := 1800 # 30 s de jeu
const DEFAULT_LAB_TICKS := 900 # partie « labo par défaut » comparée à la partie nue
const HASH_EVERY := 120
const SANDBOX_SEED := 21.0
const BIG := 99999.0
const LAB_DEFAULTS := {"dashStrike": "fin", "hitstop": "global", "comboMobility": "mobile"}

static func tests(h) -> void:
	_tests_profil(h)
	_tests_mort(h)
	_tests_gardien(h)
	_tests_ville(h)
	_tests_labo(h)
	h.test("bots : le portail de la Ville n'est jamais pris sans demande ; sur demande, l'épisode finit proprement en Ville", func(): _bots_portail(h))

static func _tests_profil(h) -> void:
	h.test("profil neuf : schéma courant, checkpoint 1, kit de départ de la 1re classe, rien dans le coffre", func(): _profil_neuf(h))
	h.test("profil : migration d'une sauvegarde schéma 2 {checkpoints, bestFloor, items, snapshots}", func(): _profil_migration(h))
	h.test("profil : données corrompues ou hostiles → défauts, jamais de blocage", func(): _profil_corrompu(h))
	h.test("profil : un aller-retour JSON (sauvegarde puis relance) ne change rien", func(): _profil_aller_retour(h))

static func _tests_mort(h) -> void:
	h.test("mort : bénédictions remises à zéro ; équipement, coffre, kit, Âmes, déblocages, améliorations conservés ; taxe de Charon", func(): _mort_temporaire_perdu(h))
	h.test("mort : l'amélioration « Avidité de Charon » réduit la taxe (bornée à 100 %)", func(): _mort_avidite(h))
	h.test("mort : reprise au DERNIER checkpoint par défaut ; un point de TP débloqué peut être choisi ; un étage non débloqué est refusé", func(): _mort_reprise(h))

static func _tests_gardien(h) -> void:
	h.test("Gardien vaincu (étage 18) : checkpoint 19 + point de TP, Âmes, butin, portes [suite, Ville]", func(): _gardien_vaincu(h))
	h.test("après le Gardien, « suite » garde le build (pas d'instantané) ; mourir plus loin le vide quand même", func(): _suite_garde_le_build(h))
	h.test("retour en Ville par le portail : fin du run sans taxe, checkpoint gardé, nouvelle descente sans bénédiction", func(): _retour_portail(h))
	h.test("retour en Ville par la commande : depuis l'écran de mort, ou au portail ouvert ; jamais en plein combat", func(): _retour_commande(h))
	h.test("abandon : compte comme une mort (taxe, récap, bénédictions perdues) et ramène en Ville", func(): _abandon(h))
	h.test("entraînement (Ville → « Défier ») : ni Âmes, ni checkpoint, ni taxe ; seule porte : la Ville", func(): _entrainement(h))
	h.test("Âmes : chaque ennemi tué en donjon en rapporte (pas les invocations, pas l'arène, pas l'entraînement)", func(): _ames(h))

static func _tests_ville(h) -> void:
	h.test("Ville · déblocage : refus (Âmes insuffisantes, inconnu, déjà débloqué), paiement, arme forgée au coffre", func(): _ville_deblocage(h))
	h.test("Ville · classe : verrouillée refusée ; choisie, elle apporte son arme (l'ancienne au coffre) et son kit de départ", func(): _ville_classe(h))
	h.test("Ville · compétence et gadget : seulement ceux de la classe, et débloqués", func(): _ville_competence_gadget(h))
	h.test("Ville · Sanctuaire : refus (Âmes insuffisantes, niveau maximal), prix par niveau, effet sur la partie suivante", func(): _ville_sanctuaire(h))
	h.test("Ville · coffre : équiper (l'objet porté prend sa place), refus d'une arme d'une autre classe, recycler en Âmes", func(): _ville_coffre(h))
	h.test("butin en donjon : équiper envoie l'ancien au coffre ; « garder » le range ; arme d'une autre classe refusée", func(): _butin_donjon(h))

static func _tests_labo(h) -> void:
	h.test("labo : la variante par défaut de chaque axe redonne EXACTEMENT les valeurs d'origine du tuning", func(): _labo_defaut(h))
	h.test("labo : setLab change la variante en cours de partie ; une variante inconnue est refusée sans effet", func(): _labo_set_lab(h))
	h.test("labo D5 · toutDash : une attaque au DÉBUT du dash le coupe aussitôt en frappe de dash", func(): _d5_tout_dash(h))
	h.test("labo D5 · fin (référence) : la même attaque attend la fin du dash (dernier 45 %) puis le coupe en frappe", func(): _d5_fin(h))
	h.test("labo D5 · apresDash : le dash n'est JAMAIS coupé ; la frappe part après, à sa sortie", func(): _d5_apres_dash(h))
	h.test("labo D8 · local : le héros et l'ennemi touché se figent ; le projectile ennemi et les autres ennemis continuent", func(): _d8_local(h))
	h.test("labo D8 · global (référence) : toute la scène se fige, projectiles compris", func(): _d8_global(h))
	h.test("labo D8 · local : le dash interrompt le gel du héros (le dash reste roi)", func(): _d8_dash_roi(h))
	h.test("labo D8 · local : partie déterministe (même graine + mêmes entrées = même état, à l'octet)", func(): _d8_deterministe(h))
	h.test("labo D9 : préréglages appliqués (vitesse et annulations) et effet mesurable ancré < mobile < fluide", func(): _d9(h))

# ---------------------------------------------------------------- outils

static func _section() -> float:
	return D6Data.default_tuning().floors.sectionLength

static func _guardian_floor() -> float:
	return _section() # 18

static func _checkpoint() -> float:
	return _section() + 1.0 # 19

static func _step(h, g: Dictionary, over: Dictionary = {}) -> void:
	D6Game.step_game(g, h.entree(over))

## n pas avec la même entrée, SANS vider les événements (comme `steps` du test web).
static func _steps(h, g: Dictionary, n: int, over: Dictionary = {}) -> void:
	for i in n:
		_step(h, g, over)

## Partie de test : salle vidée (aucune vague), héros au centre, rien ne l'interrompt.
static func _sandbox(h, opts: Dictionary = {}) -> Dictionary:
	var o := {"seed": SANDBOX_SEED}
	o.merge(opts, true)
	return h.bac_a_sable(o)

## Ennemi immobile au combat (ne riposte pas), très résistant : on teste le héros.
static func _dummy(g: Dictionary, dx: float, dy: float, kind: String = "brute") -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.cooldown = 99.0
	e.hp = BIG
	e.maxHp = BIG
	return e

## Tue le Gardien de la salle et laisse la salle se résoudre (checkpoint, portes).
static func _defeat_guardian(h, g: Dictionary) -> void:
	var boss = null
	for e in g.enemies:
		if boss == null and D6Js.truthy(e.get("boss")):
			boss = e
	if not h.ok(boss != null, "un Gardien doit être présent"):
		return
	for e in g.enemies:
		if not D6Js.truthy(e.get("dead")) and not D6Js.truthy(e.get("boss")):
			e.dead = true
	g.spawns.clear()
	D6Combat.kill_enemy(g, boss, {"kind": "melee"})
	var i := 0
	while i < SETTLE_TICKS and not D6Js.truthy(g.room.cleared):
		_step(h, g)
		i += 1
	h.egal(g.room.cleared, true, "la salle du Gardien doit être nettoyée")

## Pose le héros dans la porte d'indice i et laisse la simulation la franchir.
static func _take_door(h, g: Dictionary, i: int) -> void:
	var d = g.room.doors[i] if i < g.room.doors.size() else null
	if not h.ok(d != null and D6Js.truthy(d.open), "porte %d ouverte" % i):
		return
	g.room.interact = null # le butin du Gardien n'est pas sur le chemin du test
	g.player.x = d.x + d.w / 2.0
	g.player.y = d.y + d.h + g.player.r - 2.0
	_step(h, g)

static func _kill(h, g: Dictionary, source: String = "test") -> void:
	g.godMode = false
	g.player.iframes = 0.0
	D6Combat.damage_player(g, BIG, {"kind": source, "id": 4242.0})
	var i := 0
	while i < SETTLE_TICKS and g.mode == "play":
		_step(h, g)
		i += 1
	h.egal(g.mode, "dead")

## { ...base, ...over } : copie de surface puis surcharge.
static func _with(base: Dictionary, over: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(over, true)
	return out

## Copie du tuning avec du contenu d'essai payant (une classe, son arme, sa compétence, son gadget).
static func _content_with_extras() -> Dictionary:
	var dt: Dictionary = D6Data.default_tuning()
	var lame: Dictionary = dt.weapons[dt.classes[dt.classes.keys()[0]].weapons[0]]
	var skill: Dictionary = dt.skills.values()[0]
	var gadget: Dictionary = dt.gadgets.values()[0]
	var super_id = dt.supers.keys()[0]
	return D6Data.create_tuning(D6Js.clone({
		"weapons": {
			"v2t_faux": _with(lame, {"name": "Faux d'essai", "className": "v2t_faucheur", "starterName": "Faux d'essai", "cost": 30.0}),
			"v2t_serpe": _with(lame, {"name": "Serpe d'essai", "className": "v2t_faucheur", "starterName": "Serpe d'essai", "cost": 25.0}),
		},
		"skills": {"v2t_trait": _with(skill, {"name": "Trait d'essai", "cost": 20.0})},
		"gadgets": {"v2t_fiole": _with(gadget, {"name": "Fiole d'essai", "cost": 10.0})},
		"classes": {
			"v2t_faucheur": {
				"name": "Faucheur d'essai", "text": "Classe de test.", "stats": {"maxHpBonus": 7.0}, "cost": 50.0,
				"weapons": ["v2t_faux", "v2t_serpe"], "skills": ["v2t_trait"], "gadgets": ["v2t_fiole"], "super": super_id,
			},
		},
	}))

static func _first_class_id(t: Dictionary):
	return t.classes.keys()[0]

static func _boons() -> Array:
	return D6Data.tables().boons.BOONS

## Deux bénédictions d'emplacements différents (une bénédiction d'attaque en remplace une autre).
static func _boon_of_slot(slot: String) -> Dictionary:
	for b in _boons():
		if b.get("slot") == slot:
			return b
	return {}

## JSON.parse(JSON.stringify(v)) : ce que fait la sauvegarde.
static func _json_round_trip(v):
	return JSON.parse_string(JSON.stringify(v, "", false, true))

## arr.includes(objet) : le MÊME objet (identité), pas un objet de même valeur.
static func _includes(arr: Array, item) -> bool:
	for x in arr:
		if is_same(x, item):
			return true
	return false

static func _has_num(arr: Array, v: float) -> bool:
	for x in arr:
		if (typeof(x) == TYPE_FLOAT or typeof(x) == TYPE_INT) and float(x) == v:
			return true
	return false

static func _has_event(evs: Array, type: String) -> bool:
	for ev in evs:
		if ev.type == type:
			return true
	return false

static func _permanent(meta: Dictionary) -> Dictionary:
	return {"loadout": meta.loadout, "unlocked": meta.unlocked, "upgrades": meta.upgrades, "checkpoints": meta.checkpoints}

# ---------------------------------------------------------------- profil

static func _profil_neuf(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var p: Dictionary = D6Profile.create_profile(t)
	var first = _first_class_id(t)
	var c: Dictionary = t.classes[first]
	h.egal(p.schema, D6Data.tables().profile.PROFILE_SCHEMA)
	h.egal(p.checkpoints, [1.0])
	h.egal(p.souls, 0.0)
	h.egal(p.gold, 0.0)
	h.egal(p.unlocked, {"classes": [first], "weapons": [c.weapons[0]], "skills": [c.skills[0]], "gadgets": [c.gadgets[0]]})
	h.egal(p.loadout, {"classId": first, "skillId": c.skills[0], "gadgetId": c.gadgets[0]})
	h.egal(p.stash, [])
	# La 1re partie complète l'équipement vide avec l'équipement de départ (permanent).
	var g: Dictionary = D6Game.create_game({"seed": 1.0, "meta": p})
	h.ok(D6Js.truthy(g.meta.equipment.arme) and D6Js.truthy(g.meta.equipment.armure))
	h.ok(is_same(g.run.items, g.meta.equipment), "run.items EST l'équipement du profil")

static func _profil_migration(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var cp := _checkpoint()
	var g0: Dictionary = D6Game.create_game({"seed": 3.0})
	var arme: Dictionary = D6Loot.generate_item(g0, {"slot": "arme", "rarity": "rare"})
	var armure: Dictionary = D6Loot.generate_item(g0, {"slot": "armure", "rarity": "magique"})
	var old := {
		"checkpoints": [1.0, 7.0, 13.0, cp],
		"bestFloor": 22.0,
		"items": {"arme": arme, "armure": armure, "talisman": null},
		"snapshots": {"7": {"boons": [{"id": _boons()[0].id, "rarity": "rare", "level": 1.0}], "gold": 120.0}},
	}
	var p: Dictionary = D6Profile.sanitize_profile(_json_round_trip(old), t)
	h.egal(p.schema, D6Data.tables().profile.PROFILE_SCHEMA)
	# Les checkpoints d'avant la V2 (Gardien tous les 6 étages : 7, 13) ne sont plus des points de
	# reprise : seuls restent l'étage 1 et les débuts de section (étage qui suit un Gardien).
	h.egal(p.checkpoints, [1.0, cp])
	for f in p.checkpoints:
		h.egal(D6Floors.floor_info(t, f).indexInSection, 1.0)
	h.egal(p.bestFloor, 22.0)
	h.egal(p.equipment.arme.name, arme.name, "l'équipement de l'ancien champ `items` est repris")
	h.egal(p.equipment.armure.name, armure.name)
	h.ok(D6Js.truthy(p.equipment.arme.get("uid")) and D6Js.truthy(p.equipment.armure.get("uid")), "chaque objet repris reçoit un identifiant stable")
	h.egal(p.get("snapshots"), null, "les instantanés de build sont abandonnés")
	# Repartir du checkpoint migré : aucune bénédiction (le temporaire ne survit pas), l'équipement est là.
	var g: Dictionary = D6Game.create_game({"seed": 3.0, "meta": old, "startFloor": cp})
	h.egal(g.run.boons, [])
	h.egal(g.run.items.arme.name, arme.name)

static func _bad_profile(t: Dictionary) -> Dictionary:
	return {
		"checkpoints": "x", "bestFloor": 1e9, "souls": -50.0, "gold": NAN,
		"unlocked": {"classes": ["inconnue", 42.0, null], "weapons": "lame", "skills": [{}], "gadgets": null},
		"upgrades": {"vitalite": 99.0, "inconnue": 1.0, "celerite": -1.0, "ferocite": 1.5},
		"loadout": {"classId": "inconnue", "skillId": 7.0, "gadgetId": "nope"},
		"equipment": {"arme": {"slot": "armure", "name": "x", "affixes": [], "base": {}}, "armure": "chaîne", "talisman": {"slot": "talisman"}},
		"stash": [1.0, null, {}, {"slot": "arme", "name": "bonne", "affixes": [], "base": {"damage": 3.0}}],
		"itemSeq": -4.0, "guardians": {"inconnu": 3.0, t.boss.keys()[0]: "x"}, "stats": {"runs": -1.0, "deaths": "beaucoup", "kills": 5.0},
	}

static func _profil_corrompu(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	# (`undefined` de JavaScript = null : il figure deux fois, comme dans le test web.)
	for raw in [null, null, 42.0, "texte", [], [1.0, 2.0]]:
		h.egal(D6Profile.sanitize_profile(raw, t), D6Profile.create_profile(t))
	var bad := _bad_profile(t)
	var p: Dictionary = D6Profile.sanitize_profile(D6Js.clone(bad), t)
	h.egal(p.checkpoints, [1.0])
	h.egal(p.bestFloor, 1.0)
	h.egal(p.souls, 0.0)
	h.egal(p.gold, 0.0)
	h.egal(p.unlocked, D6Profile.create_profile(t).unlocked)
	h.egal(p.upgrades, {})
	h.egal(p.loadout, D6Profile.create_profile(t).loadout)
	h.egal(p.equipment, {"arme": null, "armure": null, "talisman": null})
	h.egal(p.stash.size(), 1)
	if p.stash.size() > 0:
		h.egal(p.stash[0].name, "bonne")
	h.egal(p.guardians, {})
	h.egal(p.stats, {"runs": 0.0, "deaths": 0.0, "kills": 5.0, "guardianKills": 0.0})
	# Une partie démarre avec ce profil réparé.
	var g: Dictionary = D6Game.create_game({"seed": 5.0, "meta": bad})
	h.egal(g.mode, "play")
	h.ok(g.player.hp > 0.0)
	# Coffre plein : la migration le borne.
	var stash_max: float = D6Data.tables().profile.STASH_MAX
	var many: Array = []
	for i in int(stash_max) + 10:
		many.append({"slot": "armure", "name": "a%d" % i, "affixes": [], "base": {"hp": 1.0}})
	h.egal(float(D6Profile.sanitize_profile({"stash": many}, t).stash.size()), stash_max)

static func _profil_aller_retour(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var cp := _checkpoint()
	var g: Dictionary = D6Game.create_game({"seed": 8.0})
	g.meta.souls = 77.0
	g.meta.upgrades.vitalite = 2.0
	g.meta.checkpoints.append(cp)
	var p: Dictionary = D6Profile.sanitize_profile(_json_round_trip(g.meta), t)
	h.egal(D6Profile.sanitize_profile(_json_round_trip(p), t), p)
	h.egal(p.souls, 77.0)
	h.egal(p.upgrades.vitalite, 2.0)
	h.egal(p.checkpoints, [1.0, cp])

# ---------------------------------------------------------------- mort : temporaire perdu, permanent gardé

static func _mort_temporaire_perdu(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 12.0})
	var meta: Dictionary = g.meta
	meta.souls = 120.0
	meta.upgrades.vitalite = 1.0
	var arme: Dictionary = D6Loot.generate_item(g, {"slot": "arme", "rarity": "rare"})
	var coffre: Dictionary = D6Loot.generate_item(g, {"slot": "talisman", "rarity": "magique"})
	g.run.items.arme = arme
	meta.stash.append(coffre)
	D6Boons.add_boon(g.run, {"id": _boon_of_slot("attack").id, "rarity": "rare"})
	D6Boons.add_boon(g.run, {"id": _boon_of_slot("passive").id, "rarity": "commun"})
	g.run.gold = 101.0
	var before: Dictionary = D6Js.clone(_permanent(meta))
	_kill(h, g)
	# Récapitulatif de mort : ce qui est perdu (temporaire) et ce qui est gardé (permanent).
	var r: Dictionary = g.run.deathRecap
	var kept := floorf(101.0 * g.tuning.economy.deathGoldKeep)
	h.egal(r.boonsLost, 2.0)
	h.egal(r.goldLost, 101.0 - kept)
	h.egal(g.run.gold, kept, "Charon prélève sa part")
	h.egal(meta.gold, g.run.gold, "la bourse du profil suit")
	h.egal(meta.stats.deaths, 1.0)
	h.egal(D6Game.apply_command(g, {"type": "respawn"}), true)
	h.egal(g.mode, "play")
	h.egal(g.run.boons, [], "le temporaire repart de zéro")
	h.ok(is_same(g.run.items.arme, arme), "équipement conservé")
	h.ok(_includes(meta.stash, coffre), "coffre conservé")
	h.egal(meta.souls, 120.0, "Âmes conservées")
	h.egal(_permanent(meta), before)
	h.egal(g.player.hp, g.player.maxHp)
	# Les PV max après la reprise = ceux d'une partie neuve avec le même profil (Vitalité comprise).
	var ref: Dictionary = D6Game.create_game({"seed": 12.0, "meta": meta})
	h.egal(g.player.maxHp, ref.player.maxHp)
	h.ok(g.player.stats.maxHpBonus >= g.tuning.town.upgrades.vitalite.perLevel, "l'amélioration de Vitalité compte toujours")

static func _mort_avidite(h) -> void:
	var up: Dictionary = D6Data.default_tuning().town.upgrades.avidite
	for lvi in int(up.max) + 1:
		var lv := float(lvi)
		var meta: Dictionary = D6Profile.create_profile(D6Data.create_tuning())
		meta.upgrades.avidite = lv
		var g2: Dictionary = D6Game.create_game({"seed": 13.0, "meta": meta})
		g2.run.gold = 200.0
		_kill(h, g2)
		var keep: float = minf(1.0, g2.tuning.economy.deathGoldKeep + up.perLevel * lv)
		h.egal(g2.run.gold, floorf(200.0 * keep), "Avidité niveau %d" % lvi)

static func _mort_reprise(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var cp := _checkpoint()
	var cp2: float = D6Floors.section_bounds(t, 2.0).checkpoint # 37
	var g: Dictionary = D6Game.create_game({"seed": 14.0, "startFloor": cp2 + 3.0, "meta": {"checkpoints": [1.0, cp, cp2]}})
	h.egal(g.meta.checkpoints, [1.0, cp, cp2])
	_kill(h, g)
	h.egal(g.run.deathRecap.checkpoint, cp2)
	D6Game.apply_command(g, {"type": "respawn"})
	h.egal(g.run.floor, cp2, "dernier checkpoint")
	_kill(h, g)
	D6Game.apply_command(g, {"type": "respawn", "floor": cp})
	h.egal(g.run.floor, cp, "point de téléportation choisi")
	_kill(h, g)
	D6Game.apply_command(g, {"type": "respawn", "floor": cp2 + 5.0})
	h.egal(g.run.floor, cp2, "un étage non débloqué retombe sur le dernier checkpoint")
	h.egal(D6Game.apply_command(g, {"type": "respawn"}), false, "pas de reprise sans être mort")

# ---------------------------------------------------------------- Gardien, checkpoint, téléportation

static func _gardien_vaincu(h) -> void:
	var cp := _checkpoint()
	var g: Dictionary = D6Game.create_game({"seed": 15.0, "startFloor": _guardian_floor()})
	h.egal(g.info.isBoss, true)
	var kind = D6Floors.guardian_for(g.tuning, 1.0)
	h.ok(g.enemies.any(func(e): return D6Js.truthy(e.get("boss")) and e.kind == kind), "le Gardien de la section 1")
	var souls0: float = g.meta.souls
	_defeat_guardian(h, g)
	h.ok(_has_num(g.meta.checkpoints, cp), "checkpoint 19")
	h.egal(g.meta.guardians.get(kind), 1.0)
	h.egal(g.meta.stats.guardianKills, 1.0)
	h.egal(g.meta.souls, souls0 + g.tuning.progression.souls.guardian)
	h.ok(g.events.any(func(e): return e.type == "checkpoint" and e.get("floor") == cp))
	var it = g.room.get("interact")
	h.egal(it.kind if it is Dictionary else null, "loot", "butin du Gardien")
	var rewards: Array = g.room.doors.map(func(d): return d.reward)
	if h.egal(rewards.size(), 2):
		h.egal(rewards[1], "town", "portail de la Ville")
		h.ok(not ["town", "boss"].has(rewards[0]), "porte de la section suivante : %s" % str(rewards[0]))
	h.ok(g.room.doors.all(func(d): return D6Js.truthy(d.open)))
	# Point de téléportation : une nouvelle descente peut partir de l'étage 19.
	var tp: Dictionary = D6Game.create_game({"seed": 16.0, "meta": g.meta, "startFloor": cp})
	h.egal(tp.run.floor, cp)
	h.egal(tp.info.indexInSection, 1.0)

static func _suite_garde_le_build(h) -> void:
	var cp := _checkpoint()
	var g: Dictionary = D6Game.create_game({"seed": 17.0, "startFloor": _guardian_floor()})
	D6Boons.add_boon(g.run, {"id": _boons()[0].id, "rarity": "rare"})
	_defeat_guardian(h, g)
	_take_door(h, g, 0)
	h.egal(g.run.floor, cp)
	h.egal(g.mode, "play")
	h.egal(g.run.boons.size(), 1, "le run continue avec son build")
	D6Boons.add_boon(g.run, {"id": _boon_of_slot("passive").id, "rarity": "commun"})
	h.egal(g.run.boons.size(), 2)
	_kill(h, g)
	D6Game.apply_command(g, {"type": "respawn"})
	h.egal(g.run.floor, cp)
	h.egal(g.run.boons, [], "aucun build figé au Gardien")

static func _retour_portail(h) -> void:
	var cp := _checkpoint()
	var g: Dictionary = D6Game.create_game({"seed": 18.0, "startFloor": _guardian_floor()})
	D6Boons.add_boon(g.run, {"id": _boons()[0].id, "rarity": "rare"})
	g.run.gold = 90.0
	_defeat_guardian(h, g)
	var arme: Dictionary = g.run.items.arme
	_take_door(h, g, 1)
	h.egal(g.mode, "town")
	h.ok(_has_event(g.events, "returnTown"))
	h.egal(g.meta.gold, 90.0, "le portail n'est pas une mort : Charon ne prend rien")
	h.egal(g.meta.stats.deaths, 0.0)
	h.ok(_has_num(g.meta.checkpoints, cp))
	# La partie terminée ne bouge plus.
	var tick: float = g.tick
	_steps(h, g, 30)
	h.egal(g.tick, tick)
	# Ville → nouvelle descente depuis le checkpoint (ce que fait le programme principal avec le profil sauvegardé).
	var saved = _json_round_trip(g.meta)
	var g2: Dictionary = D6Game.create_game({"seed": 19.0, "meta": saved, "startFloor": cp})
	h.egal(g2.run.floor, cp)
	h.egal(g2.run.boons, [])
	h.egal(g2.run.gold, 90.0)
	h.egal(g2.run.items.arme.name, arme.name)

static func _retour_commande(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 20.0, "startFloor": 2.0})
	h.egal(D6Game.apply_command(g, {"type": "returnToTown"}), false, "pas de sortie gratuite en plein combat (c'est « abandon »)")
	h.egal(g.mode, "play")
	g.run.gold = 50.0
	_kill(h, g)
	var taxed: float = g.run.gold
	h.egal(D6Game.apply_command(g, {"type": "returnToTown"}), true)
	h.egal(g.mode, "town")
	h.egal(g.meta.gold, taxed, "la taxe a été payée une seule fois, à la mort")
	# Au portail du Gardien, la commande équivaut à franchir la porte « Ville ».
	var b: Dictionary = D6Game.create_game({"seed": 20.0, "startFloor": _guardian_floor()})
	_defeat_guardian(h, b)
	h.egal(D6Game.apply_command(b, {"type": "returnToTown"}), true)
	h.egal(b.mode, "town")
	h.egal(D6Game.apply_command(b, {"type": "returnToTown"}), false, "déjà en Ville")

static func _abandon(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 22.0, "startFloor": 3.0})
	D6Boons.add_boon(g.run, {"id": _boons()[0].id, "rarity": "commun"})
	g.run.gold = 80.0
	h.egal(D6Game.apply_command(g, {"type": "abandon"}), true)
	h.egal(g.mode, "town")
	h.egal(g.meta.gold, floorf(80.0 * g.tuning.economy.deathGoldKeep))
	h.egal(g.meta.stats.deaths, 1.0)
	h.egal(g.run.deathRecap.boonsLost, 1.0)
	h.egal(D6Game.apply_command(g, {"type": "abandon"}), false, "rien à abandonner hors partie")
	# Abandon pendant un menu de choix.
	var c: Dictionary = D6Game.create_game({"seed": 23.0})
	c.mode = "choice"
	c.choice = {"kind": "boon", "options": []}
	h.egal(D6Game.apply_command(c, {"type": "abandon"}), true)
	h.egal(c.mode, "town")

static func _practice_ledger(g: Dictionary) -> Dictionary:
	return {"souls": g.meta.souls, "checkpoints": g.meta.checkpoints, "guardians": g.meta.guardians, "kills": g.meta.stats.guardianKills}

static func _entrainement(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var meta: Dictionary = D6Profile.create_profile(t)
	meta.gold = 60.0
	var g: Dictionary = D6Game.create_game({"seed": 24.0, "startFloor": _guardian_floor(), "practice": true, "meta": meta})
	h.egal(g.practice, true)
	h.egal(g.meta.stats.runs, 0.0, "un entraînement n'est pas une descente")
	var before: Dictionary = D6Js.clone(_practice_ledger(g))
	# Mourir à l'entraînement : aucune taxe, aucune mort comptée.
	_kill(h, g)
	h.egal(g.run.gold, 60.0)
	h.egal(g.meta.stats.deaths, 0.0)
	D6Game.apply_command(g, {"type": "respawn"})
	h.egal(g.run.floor, _guardian_floor())
	_defeat_guardian(h, g)
	h.egal(_practice_ledger(g), before)
	h.egal(g.room.doors.map(func(d): return d.reward), ["town"])
	h.egal(g.room.get("interact"), null, "aucun butin")
	_take_door(h, g, 0)
	h.egal(g.mode, "town")

static func _souls_for_kill(h, opts: Dictionary, summoned: bool = false) -> float:
	var g := _sandbox(h, opts)
	var e: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x + 300.0, g.player.y, {"spawnT": 0.0, "summoned": summoned})
	var s0: float = g.meta.souls
	D6Combat.kill_enemy(g, e, {"kind": "melee"})
	return g.meta.souls - s0

static func _ames(h) -> void:
	var souls: Dictionary = D6Data.default_tuning().progression.souls
	h.egal(_souls_for_kill(h, {}), souls.kill)
	h.egal(_souls_for_kill(h, {}, true), 0.0)
	h.egal(_souls_for_kill(h, {"sandbox": true}), 0.0)
	h.egal(_souls_for_kill(h, {"practice": true}), 0.0)

# ---------------------------------------------------------------- opérations de la Ville

static func _ville_deblocage(h) -> void:
	var t := _content_with_extras()
	var p: Dictionary = D6Profile.create_profile(t)
	var first = _first_class_id(t)
	h.egal(D6Profile.unlock_cost(t, "classes", "v2t_faucheur"), 50.0)
	h.egal(D6Profile.unlock_cost(t, "classes", first), D6Js.nz(t.classes[first].get("cost"), 0.0))
	h.egal(D6Profile.unlock(p, t, "classes", "v2t_faucheur"), {"ok": false, "reason": "Âmes insuffisantes"})
	h.egal(D6Profile.unlock(p, t, "classes", "introuvable"), {"ok": false, "reason": "inconnu"})
	h.egal(D6Profile.unlock(p, t, "pouvoirs", "v2t_faucheur"), {"ok": false, "reason": "inconnu"})
	h.egal(D6Profile.unlock(p, t, "classes", first), {"ok": false, "reason": "déjà débloqué"})
	p.souls = 75.0
	h.egal(D6Profile.unlock(p, t, "classes", "v2t_faucheur"), {"ok": true})
	h.egal(p.souls, 25.0)
	h.ok(p.unlocked.classes.has("v2t_faucheur"))
	h.egal(D6Profile.unlock(p, t, "classes", "v2t_faucheur"), {"ok": false, "reason": "déjà débloqué"})
	# Le kit de départ de la classe vient avec elle ; le reste de son arsenal se paie.
	h.egal(D6Profile.unlock(p, t, "skills", "v2t_trait"), {"ok": false, "reason": "déjà débloqué"})
	h.egal(D6Profile.unlock(p, t, "gadgets", "v2t_fiole"), {"ok": false, "reason": "déjà débloqué"})
	h.egal(D6Profile.unlock(p, t, "weapons", "v2t_faux"), {"ok": false, "reason": "déjà débloqué"})
	p.souls = 24.0
	h.egal(D6Profile.unlock(p, t, "weapons", "v2t_serpe"), {"ok": false, "reason": "Âmes insuffisantes"})
	h.egal(p.souls, 24.0, "un refus ne prélève rien")
	# Arme : forgée en exemplaire commun et rangée au coffre.
	p.souls = 25.0
	var stash0: int = p.stash.size()
	h.egal(D6Profile.unlock(p, t, "weapons", "v2t_serpe"), {"ok": true})
	h.egal(p.souls, 0.0)
	if not h.egal(p.stash.size(), stash0 + 1):
		return
	var forged: Dictionary = p.stash[p.stash.size() - 1]
	h.egal(forged.get("weaponType"), "v2t_serpe")
	h.egal(forged.get("rarity"), "commun")
	h.ok(D6Js.truthy(forged.get("uid")))

static func _ville_classe(h) -> void:
	var t := _content_with_extras()
	var p: Dictionary = D6Profile.create_profile(t)
	var g: Dictionary = D6Game.create_game({"seed": 30.0, "tuning": t, "meta": p}) # 1re partie : équipement de départ
	var profile: Dictionary = D6Js.clone(g.meta)
	var old_weapon: Dictionary = profile.equipment.arme
	h.egal(D6Profile.select_class(profile, t, "v2t_faucheur"), {"ok": false, "reason": "classe verrouillée"})
	profile.souls = 50.0
	h.egal(D6Profile.unlock(profile, t, "classes", "v2t_faucheur").ok, true)
	h.egal(D6Profile.select_class(profile, t, "v2t_faucheur"), {"ok": true})
	h.egal(profile.loadout.classId, "v2t_faucheur")
	h.egal(profile.equipment.arme.get("weaponType"), "v2t_faux", "arme de départ de la classe")
	h.ok(profile.stash.any(func(it): return it.name == old_weapon.name and it.get("weaponType") == old_weapon.get("weaponType")), "l'ancienne arme est au coffre")
	# Le kit de départ de la classe (1re arme, 1re compétence, 1er gadget) est possédé, pas « à débloquer ».
	h.ok(profile.unlocked.weapons.has("v2t_faux"))
	h.ok(profile.unlocked.skills.has("v2t_trait"))
	h.ok(profile.unlocked.gadgets.has("v2t_fiole"))
	h.egal(profile.loadout.skillId, "v2t_trait")
	h.egal(profile.loadout.gadgetId, "v2t_fiole")
	# La 2e arme de la classe reste à forger.
	h.ok(not profile.unlocked.weapons.has("v2t_serpe"))
	# La partie suivante joue le kit choisi (permanent).
	var g2: Dictionary = D6Game.create_game({"seed": 31.0, "tuning": t, "meta": profile})
	h.egal(g2.kit.classId, "v2t_faucheur")
	h.egal(g2.kit.weaponType, "v2t_faux")
	h.egal(g2.player.stats.maxHpBonus, 7.0, "bonus permanent de la classe")
	# Revenir à la classe de départ : son arme ressort du coffre.
	h.egal(D6Profile.select_class(profile, t, _first_class_id(t)), {"ok": true})
	h.egal(profile.equipment.arme.name, old_weapon.name)

static func _ville_competence_gadget(h) -> void:
	var t := _content_with_extras()
	var p: Dictionary = D6Profile.create_profile(t)
	var c0: Dictionary = t.classes[_first_class_id(t)]
	h.egal(D6Profile.select_skill(p, t, "v2t_trait"), {"ok": false, "reason": "indisponible"})
	h.egal(D6Profile.select_gadget(p, t, "v2t_fiole"), {"ok": false, "reason": "indisponible"})
	h.egal(D6Profile.select_skill(p, t, c0.skills[0]), {"ok": true})
	h.egal(D6Profile.select_gadget(p, t, c0.gadgets[0]), {"ok": true})
	p.souls = 999.0
	D6Profile.unlock(p, t, "skills", "v2t_trait")
	h.egal(D6Profile.select_skill(p, t, "v2t_trait"), {"ok": false, "reason": "indisponible"}, "débloquée mais d'une autre classe")

static func _ville_sanctuaire(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var up: Dictionary = t.town.upgrades.vitalite
	var p: Dictionary = D6Profile.create_profile(t)
	h.egal(D6Profile.buy_upgrade(p, t, "vitalite"), {"ok": false, "reason": "Âmes insuffisantes"})
	h.egal(D6Profile.buy_upgrade(p, t, "inconnue"), {"ok": false, "reason": "inconnu"})
	var total := 0.0
	for c in up.costs:
		total += c
	p.souls = total + 3.0
	for lvi in int(up.max):
		var lv := float(lvi)
		h.egal(D6Profile.upgrade_cost(t, "vitalite", lv), up.costs[lvi])
		h.egal(D6Profile.buy_upgrade(p, t, "vitalite"), {"ok": true})
		h.egal(p.upgrades.get("vitalite"), lv + 1.0)
	h.egal(p.souls, 3.0)
	h.egal(D6Profile.upgrade_cost(t, "vitalite", up.max), null)
	h.egal(D6Profile.buy_upgrade(p, t, "vitalite"), {"ok": false, "reason": "niveau maximal"})
	var base: Dictionary = D6Game.create_game({"seed": 32.0})
	var boosted: Dictionary = D6Game.create_game({"seed": 32.0, "meta": p})
	h.egal(boosted.player.maxHp - base.player.maxHp, up.perLevel * up.max)
	h.egal(boosted.player.hp, boosted.player.maxHp)

static func _ville_coffre(h) -> void:
	var t := _content_with_extras()
	var g: Dictionary = D6Game.create_game({"seed": 33.0, "tuning": t})
	var p: Dictionary = D6Js.clone(g.meta)
	var worn = p.equipment.armure
	var armure := _with(D6Loot.generate_item(g, {"slot": "armure", "rarity": "rare"}), {"uid": "u-armure"})
	var faux := _with(D6Profile.starter_weapon(t, "v2t_faux"), {"uid": "u-faux"})
	var tal := _with(D6Loot.generate_item(g, {"slot": "talisman", "rarity": "legendaire"}), {"uid": "u-tal"})
	p.stash.append_array([armure, faux, tal])
	h.egal(D6Profile.equip_from_stash(p, t, "absent"), {"ok": false, "reason": "objet introuvable"})
	h.egal(D6Profile.equip_from_stash(p, t, "u-faux"), {"ok": false, "reason": "arme réservée à une autre classe"})
	h.egal(D6Profile.equip_from_stash(p, t, "u-armure"), {"ok": true})
	h.ok(is_same(p.equipment.armure, armure), "l'armure du coffre est portée (le même objet)")
	h.ok(_includes(p.stash, worn), "l'armure portée part au coffre")
	h.ok(not _includes(p.stash, armure))
	var s0: float = p.souls
	h.egal(D6Profile.salvage_from_stash(p, t, "u-tal"), {"ok": true})
	h.egal(p.souls, s0 + D6Profile.salvage_souls(t, tal))
	h.egal(D6Profile.salvage_souls(t, tal), t.town.salvageSouls.legendaire)
	h.egal(D6Profile.salvage_from_stash(p, t, "u-tal"), {"ok": false, "reason": "objet introuvable"})

static func _offer_loot(g: Dictionary, item: Dictionary) -> void:
	g.room.interact = {"kind": "loot", "x": g.player.x, "y": g.player.y, "r": 30.0, "used": false, "item": item}
	D6Run.open_interact(g)

static func _butin_donjon(h) -> void:
	var t := _content_with_extras()
	var g := _sandbox(h, {"tuning": t})
	var old: Dictionary = g.run.items.arme
	var found: Dictionary = D6Loot.generate_item(g, {"slot": "arme", "rarity": "rare", "weaponType": g.kit.weaponType})
	_offer_loot(g, found)
	h.egal(g.mode, "choice")
	h.egal(D6Game.apply_command(g, {"type": "equip"}), true)
	h.ok(is_same(g.run.items.arme, found), "l'arme trouvée est portée (le même objet)")
	h.ok(is_same(g.meta.equipment.arme, found), "équipement PERMANENT")
	h.ok(_includes(g.meta.stash, old), "l'ancienne arme est au coffre, jamais perdue")
	h.ok(D6Js.truthy(old.get("uid")), "rangée avec un identifiant stable")
	# « Garder au coffre ».
	var tal: Dictionary = D6Loot.generate_item(g, {"slot": "talisman", "rarity": "magique"})
	_offer_loot(g, tal)
	h.egal(D6Game.apply_command(g, {"type": "stash"}), true)
	h.ok(_includes(g.meta.stash, tal))
	# Arme d'une autre classe : on ne l'équipe pas, on peut la garder pour plus tard.
	var faux: Dictionary = D6Loot.generate_item(g, {"slot": "arme", "rarity": "magique", "weaponType": "v2t_faux"})
	_offer_loot(g, faux)
	h.egal(g.choice.get("wieldable"), false)
	h.egal(D6Game.apply_command(g, {"type": "equip"}), false)
	h.egal(D6Game.apply_command(g, {"type": "stash"}), true)
	h.ok(_includes(g.meta.stash, faux))
	# Tout survit à la mort.
	_kill(h, g)
	D6Game.apply_command(g, {"type": "respawn"})
	h.ok(is_same(g.run.items.arme, found), "l'arme équipée survit à la mort")
	h.ok(_includes(g.meta.stash, tal) and _includes(g.meta.stash, faux) and _includes(g.meta.stash, old))

# ---------------------------------------------------------------- labo du feel

static func _axes() -> Dictionary:
	return D6Data.tables().lab.LAB_AXES

static func _read_path(obj: Dictionary, path: String):
	var o = obj
	for k in path.split("."):
		o = o[k]
	return o

## Deux parties (labo implicite, labo par défaut explicite) jouées par le même bot : même empreinte.
static func _labo_defaut_parties(h) -> void:
	var a: Dictionary = D6Game.create_game({"seed": 40.0})
	var b: Dictionary = D6Game.create_game({"seed": 40.0, "tuning": {"lab": LAB_DEFAULTS.duplicate()}})
	var games := [a, b]
	var mem := [{}, {}]
	for i in DEFAULT_LAB_TICKS:
		for k in 2:
			var g: Dictionary = games[k]
			if g.mode == "choice":
				Bots.resolve_choice(g, "skilled")
			D6Game.step_game(g, Bots.play("skilled", g, mem[k]))
	h.egal(D6Game.state_hash(a), D6Game.state_hash(b))

static func _labo_defaut(h) -> void:
	var dt: Dictionary = D6Data.default_tuning()
	var axes := _axes()
	h.egal(dt.lab, LAB_DEFAULTS)
	for axis in axes:
		var def: Dictionary = axes[axis]
		h.egal(def.reference, dt.lab[axis], "%s : la référence du labo est le réglage de config.mjs" % axis)
		var sets: Dictionary = def.options[def.reference].set
		for path in sets:
			h.egal(_read_path(dt, path), sets[path], "%s : %s" % [axis, path])
	var raw: Dictionary = D6Data.create_tuning()
	var applied: Dictionary = D6Lab.apply_lab(D6Data.create_tuning())
	h.egal(applied, raw, "appliquer le labo par défaut ne change aucune valeur")
	# Labo absent, partiel ou illisible (vieille sauvegarde de réglages) : retour aux références.
	for lab in [null, {}, {"comboMobility": "inconnu", "hitstop": 42.0}]:
		var t: Dictionary = D6Data.create_tuning()
		t.lab = lab
		D6Lab.apply_lab(t)
		t.lab = raw.lab
		h.egal(t, raw, "labo %s : valeurs d'origine" % JSON.stringify(lab))
	# Une partie avec le labo explicite par défaut = la même partie, à l'octet près.
	_labo_defaut_parties(h)

static func _labo_set_lab(h) -> void:
	var g := _sandbox(h)
	var axes := _axes()
	var before: Dictionary = D6Js.clone(g.tuning)
	h.egal(D6Lab.set_lab(g.tuning, "hitstop", "nimporte"), false)
	h.egal(D6Lab.set_lab(g.tuning, "axeInconnu", "local"), false)
	h.egal(g.tuning, before)
	h.egal(D6Lab.set_lab(g.tuning, "hitstop", "local"), true)
	h.egal(g.tuning.hitstopMode, "local")
	h.egal(g.tuning.lab.hitstop, "local")
	var sum: Array = D6Lab.lab_summary(g.tuning)
	h.egal(sum.map(func(s): return s.axis), axes.keys())
	var choice_label = null
	for s in sum:
		if s.axis == "hitstop":
			choice_label = s.choiceLabel
	h.egal(choice_label, axes.hitstop.options.local.label)

## Relève, dans les événements de l'image, ce qui arrive au dash et à la frappe.
static func _read_dash_events(g: Dictionary, trace: Dictionary) -> void:
	for ev in g.events:
		if ev.type == "cancel" and ev.get("from") == "dash":
			trace.cancels += 1
		if ev.type == "dashEnd":
			trace.dashEndBeforeStrike = true
		if ev.type == "attackStart":
			trace.strikeAt = g.player.x - trace.x0
			trace.strike = ev.get("strike")

## Dash vers la droite, puis attaque pressée à l'image suivante. Rend la trace du héros.
static func _dash_then_attack(h, variant: String) -> Dictionary:
	var g := _sandbox(h, {"tuning": {"lab": {"dashStrike": variant}}})
	var p: Dictionary = g.player
	var x0: float = p.x
	_step(h, g, {"moveX": 1.0, "dashPressed": true})
	h.egal(p.state, "dash")
	_step(h, g, {"moveX": 1.0, "attackPressed": true})
	var trace := {"g": g, "x0": x0, "stateAfterPress": p.state, "strikeAt": null, "strike": null, "cancels": 0, "dashEndBeforeStrike": false}
	var i := 0
	while i < SETTLE_TICKS and trace.strikeAt == null:
		_read_dash_events(g, trace)
		g.events.clear()
		if trace.strikeAt == null:
			_step(h, g, {"moveX": 1.0})
		i += 1
	if trace.strikeAt == null:
		trace.strikeAt = NAN # aucune frappe : toute comparaison de distance est fausse (null en JavaScript)
	return trace

static func _d5_tout_dash(h) -> void:
	var tr := _dash_then_attack(h, "toutDash")
	var dist: float = tr.g.tuning.dash.distance
	h.egal(tr.stateAfterPress, "attack", "la frappe part à l'image même")
	h.egal(tr.strike, true, "c'est une frappe de dash")
	h.egal(tr.cancels, 1, "le dash est coupé")
	h.egal(tr.dashEndBeforeStrike, false)
	h.ok(tr.strikeAt < dist * 0.3, "frappe après %.0f u (dash : %s u)" % [tr.strikeAt, D6Js.num_str(dist)])

static func _d5_fin(h) -> void:
	var tr := _dash_then_attack(h, "fin")
	var t: Dictionary = tr.g.tuning.dash
	h.egal(tr.stateAfterPress, "dash", "au début du dash, l'attaque attend dans le tampon")
	h.egal(tr.strike, true)
	h.egal(tr.cancels, 1)
	h.ok(tr.strikeAt >= t.distance * (1.0 - t.strikeCancelFrom) - 20.0, "frappe après %.0f u" % tr.strikeAt)
	h.ok(tr.strikeAt < t.distance, "le dash est tout de même coupé avant son terme")

static func _d5_apres_dash(h) -> void:
	var tr := _dash_then_attack(h, "apresDash")
	var dist: float = tr.g.tuning.dash.distance
	h.egal(tr.stateAfterPress, "dash")
	h.egal(tr.cancels, 0, "aucune annulation du dash")
	h.egal(tr.dashEndBeforeStrike, true, "le dash va à son terme")
	h.egal(tr.strike, true, "l'attaque qui suit est une frappe de dash")
	h.ok(tr.strikeAt >= dist - 12.0, "frappe après %.0f u (dash complet : %s u)" % [tr.strikeAt, D6Js.num_str(dist)])
	# Et une attaque tardive, dans la fenêtre d'après-dash, reste une frappe (même règle pour les trois variantes).
	for variant in _axes().dashStrike.options.keys():
		var g := _sandbox(h, {"tuning": {"lab": {"dashStrike": variant}}})
		_step(h, g, {"moveX": 1.0, "dashPressed": true})
		_steps(h, g, h.ticks(g.tuning.dash.duration) + 2, {"moveX": 1.0})
		h.egal(g.player.state, "free")
		g.events.clear()
		_step(h, g, {"attackPressed": true})
		_step(h, g)
		var strike = null
		for ev in g.events:
			if ev.type == "attackStart":
				strike = ev.get("strike")
				break
		h.egal(strike, true, "%s : attaque dans la fenêtre d'après-dash = frappe" % variant)

static func _snap(g: Dictionary, brute: Dictionary, imp: Dictionary, arrow: Dictionary) -> Dictionary:
	var p: Dictionary = g.player
	var attack = p.get("attack")
	return {"time": g.time, "px": p.x, "aT": attack.get("t") if attack is Dictionary else null, "bx": brute.x, "by": brute.y, "ix": imp.x, "iy": imp.y, "ax": arrow.x, "ay": arrow.y}

## Scène D8 : le héros frappe une brute ; un diablotin marche au loin ; un projectile ennemi vole
## ailleurs. Rend l'état juste après l'impact, et une image plus tard.
static func _hitstop_scene(h, mode: String) -> Dictionary:
	var g := _sandbox(h, {"tuning": {"lab": {"hitstop": mode}}})
	var p: Dictionary = g.player
	var brute := _dummy(g, 60.0, 0.0)
	var imp: Dictionary = D6Enemies.create_enemy(g, "imp", p.x - 420.0, p.y + 200.0, {"spawnT": 0.0})
	imp.cooldown = 99.0
	var arrow: Dictionary = D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": 160.0, "y": 120.0, "vx": 300.0, "vy": 0.0, "r": 7.0, "damage": 5.0, "range": 5000.0})
	var hit_tick := -1.0
	var i := 0
	while i < SETTLE_TICKS and hit_tick < 0.0:
		_step(h, g, {"attackPressed": i == 0, "aimX": 1.0})
		if g.events.any(func(e): return e.type == "hit" or e.type == "enemyHit") or brute.hp < brute.maxHp:
			hit_tick = g.tick
		g.events.clear()
		i += 1
	h.ok(hit_tick > 0.0, "le coup doit porter")
	var at := _snap(g, brute, imp, arrow)
	_step(h, g, {"aimX": 1.0})
	return {"g": g, "at": at, "next": _snap(g, brute, imp, arrow), "brute": brute, "imp": imp}

static func _d8_local(h) -> void:
	var sc := _hitstop_scene(h, "local")
	var at: Dictionary = sc.at
	var next: Dictionary = sc.next
	h.egal(sc.g.hitstop, 0.0, "aucun gel global")
	h.ok(next.time > at.time, "le temps du monde avance")
	h.egal(next.aT, at.aT, "le coup du héros est figé")
	h.egal(next.px, at.px)
	h.egal(next.bx, at.bx)
	h.egal(next.by, at.by)
	h.ok(absf(next.ax - at.ax - 300.0 * D6Data.DT) < 1e-6, "le projectile ennemi avance pendant le gel")
	var dx: float = next.ix - at.ix
	var dy: float = next.iy - at.iy
	h.ok(sqrt(dx * dx + dy * dy) > 0.0, "un autre ennemi bouge pendant le gel")

static func _d8_global(h) -> void:
	var sc := _hitstop_scene(h, "global")
	var at: Dictionary = sc.at
	var next: Dictionary = sc.next
	h.egal(next.time, at.time, "le temps du monde s'arrête")
	h.egal(next.aT, at.aT)
	h.egal(next.ax, at.ax, "le projectile ennemi est figé lui aussi")
	h.egal(next.ix, at.ix)
	h.egal(next.iy, at.iy)

static func _d8_dash_roi(h) -> void:
	var g := _sandbox(h, {"tuning": {"lab": {"hitstop": "local"}}})
	_dummy(g, 60.0, 0.0)
	var i := 0
	while i < SETTLE_TICKS and g.player.freeze <= 0.0:
		_step(h, g, {"attackPressed": i == 0, "aimX": 1.0})
		i += 1
	h.ok(g.player.freeze > 0.0)
	_step(h, g, {"moveX": -1.0, "dashPressed": true})
	h.egal(g.player.freeze, 0.0)
	h.egal(g.player.state, "dash")

static func _deterministic_run() -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": 44.0, "tuning": {"lab": {"hitstop": "local", "dashStrike": "toutDash", "comboMobility": "fluide"}}})
	var mem := {}
	var hashes: Array = []
	for i in DETERMINISM_TICKS:
		if g.mode == "choice":
			Bots.resolve_choice(g, "skilled")
		D6Game.step_game(g, Bots.play("skilled", g, mem))
		g.events.clear()
		if i % HASH_EVERY == 0:
			hashes.append(D6Game.state_hash(g))
	return {"hashes": hashes, "frozen": g.telemetry.attacks}

static func _d8_deterministe(h) -> void:
	var a := _deterministic_run()
	var b := _deterministic_run()
	h.egal(a.hashes, b.hashes)
	h.ok(a.frozen > 0.0, "le héros a frappé (le gel local a été exercé)")

## Combo maintenu sur une cible : intervalle (s) entre le coup 1 et le coup 2, et vitesse en frappant.
static func _combo_profile(h, variant: String) -> Dictionary:
	var g := _sandbox(h, {"tuning": {"lab": {"comboMobility": variant}}})
	_dummy(g, 70.0, 0.0)
	var starts: Array = []
	var i := 0
	while i < h.ticks(1.5) and starts.size() < 2:
		_step(h, g, {"attack": true, "aimX": 1.0})
		for ev in g.events:
			if ev.type == "attackStart":
				starts.append(g.time)
		g.events.clear()
		i += 1
	# Vitesse pendant un coup : on marche vers le bas en frappant dans le vide.
	var m := _sandbox(h, {"tuning": {"lab": {"comboMobility": variant}}})
	var y0: float = m.player.y
	_step(h, m, {"attackPressed": true, "aimX": 1.0})
	var moved := 0.0
	var k := 0
	while k < 6 and m.player.state == "attack":
		var y: float = m.player.y
		_step(h, m, {"moveY": 1.0, "aimX": 1.0})
		moved += m.player.y - y
		k += 1
	# Moins de deux coups : NaN (comme en JavaScript), toute comparaison d'intervalle est fausse.
	var gap: float = starts[1] - starts[0] if starts.size() >= 2 else NAN
	return {"gap": gap, "moved": moved, "y0": y0, "t": g.tuning.player}

static func _d9(h) -> void:
	var options: Dictionary = _axes().comboMobility.options
	var prof := {}
	for variant in ["ancre", "mobile", "fluide"]:
		var set_: Dictionary = options[variant].set
		var g: Dictionary = D6Game.create_game({"seed": 45.0, "tuning": {"lab": {"comboMobility": variant}}})
		h.egal(g.tuning.player.attackMoveMult, set_["player.attackMoveMult"], "%s : vitesse en frappant" % variant)
		h.egal(g.tuning.player.cancelMult, set_["player.cancelMult"], "%s : annulations" % variant)
		prof[variant] = _combo_profile(h, variant)
	h.ok(prof.fluide.gap < prof.mobile.gap and prof.mobile.gap < prof.ancre.gap, "coup 2 après : ancre %.3f s, mobile %.3f s, fluide %.3f s" % [prof.ancre.gap, prof.mobile.gap, prof.fluide.gap])
	h.ok(prof.ancre.moved < prof.mobile.moved and prof.mobile.moved < prof.fluide.moved, "déplacement en frappant : ancre %.1f u, mobile %.1f u, fluide %.1f u" % [prof.ancre.moved, prof.mobile.moved, prof.fluide.moved])
	# Le dash annule toujours tout, quelle que soit la variante (le dash reste roi).
	for variant in ["ancre", "mobile", "fluide"]:
		var g := _sandbox(h, {"tuning": {"lab": {"comboMobility": variant}}})
		_step(h, g, {"attackPressed": true, "aimX": 1.0})
		_step(h, g, {"moveX": -1.0, "dashPressed": true})
		h.egal(g.player.state, "dash", "%s : le dash coupe le coup" % variant)

# ---------------------------------------------------------------- bots et oracles

static func _bots_portail(h) -> void:
	var cp := _checkpoint()
	var g: Dictionary = D6Game.create_game({"seed": 50.0, "startFloor": _guardian_floor()})
	_defeat_guardian(h, g)
	g.room.interact = null
	var mem := {}
	var floor: float = g.run.floor
	var i := 0
	while i < h.ticks(20.0) and g.mode != "town" and floor == g.run.floor:
		if g.mode == "choice":
			Bots.resolve_choice(g, "skilled")
		D6Game.step_game(g, Bots.play("skilled", g, mem))
		i += 1
	h.different(g.mode, "town", "le bot ne rentre pas en Ville de lui-même")
	h.egal(g.run.floor, cp, "il descend dans la section suivante")
	var g2: Dictionary = D6Game.create_game({"seed": 50.0, "startFloor": _guardian_floor()})
	_defeat_guardian(h, g2)
	g2.room.interact = null
	var want := {"wantTown": true}
	i = 0
	while i < h.ticks(20.0) and g2.mode != "town":
		D6Game.step_game(g2, Bots.play("skilled", g2, want))
		i += 1
	h.egal(g2.mode, "town", "sur demande, le bot prend le portail")
	# runEpisode : une section, puis la Ville sur demande — l'épisode se termine (pas de boucle infinie).
	var r: Dictionary = Episode.run_episode("skilled", 1.0, {"floors": _section(), "minutes": 30.0, "town": true})
	h.egal(r.outcome, "town")
	h.egal(r.sectionCleared, true, "le Gardien est tombé, le checkpoint est ouvert")
	h.ok(_has_num(r.checkpoints, cp))
