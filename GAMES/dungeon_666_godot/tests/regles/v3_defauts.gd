extends RefCounted
## DÉFAUTS DE RÈGLES CORRIGÉS LE 2026-10-02 (liste et constats : DEFAUTS.md). Un test par défaut :
## rouge sur le code d'avant, vert après. Les numéros sont ceux de DEFAUTS.md.
## Outils : v2_contenu.gd (autels, ennemi d'essai).

const C = preload("res://tests/regles/v2_contenu.gd")

const FREE_TIMEOUT := 3.0 # s : un coup du héros est fini bien avant
const BLOOD_SEEDS := 300 # graines essayées pour trouver un tirage épique (6 % par tirage) et un commun
const DOOR_SEEDS := 12 # graines essayées pour le tirage des portes
const DOOR_HEAVY := 1e12 # poids écrasant : les 21 tirages donnent la même récompense
const DOOR_LIGHT := 1e-12 # poids infime, mais récompense POSSIBLE
const CHARGE_RUN := 240.0 # u entre Charon et le héros adossé au mur : la charge l'atteint, puis le mur
const CHARGE_TIMEOUT := 8.0 # s : télégraphe de la charge de Charon + traversée de la salle
const FOE_TIMEOUT := 20.0 # s : deux attaques d'un ennemi, recharge comprise
const SHORT_STUN := 0.3 # s : plus court que toute récupération + recharge du bestiaire
const RECOVERY_FOES := [["imp", 60.0], ["brute", 50.0], ["archer", 220.0], ["pavois", 60.0], ["stalker", 150.0]] # [archétype, distance au héros]
const SKILL_STATS := ["skillDamageMult", "skillCooldownMult"]

# ---------------------------------------------------------------- outils

static func _choose(g: Dictionary, index: float) -> bool:
	return D6Game.apply_command(g, {"type": "choose", "index": index})

## Équipe une arme par le vrai chemin : butin trouvé, commande « equip ».
static func _equip_weapon(h, g: Dictionary, weapon_type: String) -> void:
	var item: Dictionary = D6Loot.generate_item(g, {"slot": "arme", "weaponType": weapon_type, "rarity": "commun"})
	g.room.interact = {"kind": "loot", "x": g.player.x, "y": g.player.y, "r": 30.0, "used": false, "item": item}
	D6Run.open_interact(g)
	h.egal(D6Game.apply_command(g, {"type": "equip"}), true, "équiper : %s" % weapon_type)
	h.egal(g.kit.weaponType, weapon_type)

## Un coup complet (appui, puis attente du retour à l'état libre).
static func _one_hit(h, g: Dictionary) -> void:
	D6Game.step_game(g, h.entree({"attackPressed": true}))
	for i in h.ticks(FREE_TIMEOUT):
		if g.player.state == "free":
			return
		D6Game.step_game(g, h.entree())

# ---------------------------------------------------------------- 1. combo et changement d'arme

static func _t_combo(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 5.0})
	_equip_weapon(h, g, "dagues")
	var long_combo: int = g.tuning.combo.size()
	for i in long_combo - 1:
		_one_hit(h, g)
	h.egal(g.player.comboIndex, float(long_combo - 1), "le dernier coup des Dagues est le prochain")
	h.ok(g.player.comboTimer <= g.tuning.comboResetTime, "l'enchaînement est encore ouvert")
	_equip_weapon(h, g, "lame")
	var size: int = g.tuning.combo.size()
	h.ok(size < long_combo, "la Lame a moins de coups que les Dagues")
	if not h.ok(g.player.comboIndex < float(size), "rang %s hors du combo de la Lame (%d coups)" % [str(g.player.comboIndex), size]):
		return # attaquer ici lirait hors du tableau (le défaut d'origine)
	D6Game.step_game(g, h.entree({"attackPressed": true}))
	h.egal(g.player.state, "attack")
	h.egal(g.player.attack.index if g.player.attack != null else null, 0.0, "nouvelle arme : l'enchaînement repart du coup 1")
	# Même arme rééquipée (autre exemplaire) : l'enchaînement en cours n'est pas perdu.
	var g2: Dictionary = h.bac_a_sable({"seed": 5.0})
	_one_hit(h, g2)
	_equip_weapon(h, g2, "lame")
	h.egal(g2.player.comboIndex, 1.0, "même type d'arme : le rang est gardé")

# ---------------------------------------------------------------- 2. autel de sang

## Rareté que l'autel de sang tirerait dans cette partie (mêmes tirages, sur une copie).
static func _blood_draw(g: Dictionary) -> String:
	var probe := {"rng": D6Js.clone(g.rng), "run": D6Js.clone(g.run)}
	var fam = D6Boons.random_family(probe)
	return D6Boons.roll_boon_offer(probe, fam)[0].rarity

static func _blood_game(h, seed: float) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed, "startFloor": 5.0})
	C.altar(h, g, "autel_sang")
	return g

static func _t_sang_rarete(h) -> void:
	var seen := {}
	for seed in range(1, BLOOD_SEEDS + 1):
		if seen.has("epique") and seen.has("commun"):
			break
		var g: Dictionary = _blood_game(h, float(seed))
		var drawn := _blood_draw(g)
		if seen.has(drawn):
			continue
		seen[drawn] = true
		h.egal(_choose(g, 0.0), true)
		var got = g.run.boons[0].rarity if g.run.boons.size() == 1 else null
		# La promesse de l'autel est « rare » : jamais moins, et jamais moins que le tirage.
		h.egal(got, "rare" if drawn == "commun" else drawn, "graine %d : tirage %s" % [seed, drawn])
	h.ok(seen.has("epique") and seen.has("commun"), "tirages vus en %d graines : %s" % [BLOOD_SEEDS, str(seen.keys())])

static func _t_sang_un_pv(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 43.0, "startFloor": 5.0})
	g.player.hp = 1.0
	var ch: Dictionary = C.altar(h, g, "autel_sang")
	h.egal(ch.options[0].get("disabled"), true, "à 1 PV il n'y a plus de sang à offrir : option grisée")
	h.egal(_choose(g, 0.0), false, "et refusée")
	h.egal(g.run.boons, [])
	h.egal(g.player.hp, 1.0)
	h.egal(_choose(g, 1.0), true, "passer son chemin reste possible")
	# Tant qu'il reste du sang à verser, l'offrande est acceptée et coûte vraiment des PV.
	var g2: Dictionary = D6Game.create_game({"seed": 43.0, "startFloor": 5.0})
	g2.player.hp = 2.0
	h.egal(C.altar(h, g2, "autel_sang").options[0].get("disabled"), false)
	h.egal(_choose(g2, 0.0), true)
	h.egal(g2.player.hp, 1.0)
	h.egal(g2.run.boons.size(), 1)

# ---------------------------------------------------------------- 3. portes distinctes

static func _door_rewards(g: Dictionary) -> Array:
	return g.room.doors.map(func(d): return d.reward)

## Poids des portes : `heavy` écrase tout, `light` reste possible (ou non), le reste est exclu.
static func _door_game(seed: float, heavy: String, light) -> Dictionary:
	var g: Dictionary = D6Game.create_game({"seed": seed})
	var weights: Dictionary = g.tuning.section.doorWeights
	for k in weights.keys():
		weights[k] = 0.0
	weights[heavy] = DOOR_HEAVY
	if light != null:
		weights[light] = DOOR_LIGHT
	return g

static func _t_portes(h) -> void:
	var drawn := 0
	for seed in range(1, DOOR_SEEDS + 1):
		var g: Dictionary = _door_game(float(seed), "gold", "heal")
		var next: Dictionary = D6Sections.floor_slot(g.tuning, g.seed, g.run.floor + 1.0)
		if next.get("doors") != null or next.get("guarantee") != null:
			continue
		drawn += 1
		var rng_before = g.rng.gen.s
		D6Run.on_room_clear(g)
		h.egal(_door_rewards(g), ["gold", "heal"], "graine %d : deux récompenses possibles, deux portes distinctes" % seed)
		# Le repli ne tire rien de plus : même état du générateur qu'avec deux portes identiques.
		var same: Dictionary = _door_game(float(seed), "gold", null)
		h.egal(same.rng.gen.s, rng_before)
		D6Run.on_room_clear(same)
		h.egal(_door_rewards(same), ["gold", "gold"], "une seule récompense possible : les deux portes la portent")
		h.egal(g.rng.gen.s, same.rng.gen.s, "graine %d : le repli ne consomme aucun tirage" % seed)
	h.ok(drawn >= 3, "portes tirées dans %d parties sur %d" % [drawn, DOOR_SEEDS])

# ---------------------------------------------------------------- 5. identifiants d'objets du profil

static func _with_uid(g: Dictionary, slot: String, uid) -> Dictionary:
	var it: Dictionary = D6Loot.generate_item(g, {"slot": slot, "rarity": "rare"})
	if uid != null:
		it.uid = uid
	return it

static func _t_uids(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 21.0})
	var raw: Dictionary = D6Js.clone(g.meta)
	raw.equipment.arme.uid = "i5"
	raw.equipment.armure.uid = "i5" # doublon de l'arme
	raw.stash = [
		_with_uid(g, "talisman", 12.0), # un nombre
		_with_uid(g, "talisman", null), # absent
		_with_uid(g, "armure", "i5"), # doublon
		_with_uid(g, "armure", "i2"), # valide, mais itemSeq (2) le redonnerait
		_with_uid(g, "talisman", ""), # vide
		_with_uid(g, "talisman", "u-ancien"), # valide, autre forme
	]
	raw.itemSeq = 2.0
	var names: Array = raw.stash.map(func(it): return it.name)
	var p: Dictionary = D6Profile.sanitize_profile(raw, g.tuning)
	h.egal(p.stash.map(func(it): return it.name), names, "aucun objet perdu, ordre gardé")
	h.ok(p.equipment.arme != null and p.equipment.armure != null, "équipement gardé")
	var items: Array = [p.equipment.arme, p.equipment.armure] + p.stash
	var seen := {}
	for it in items:
		var uid = it.get("uid")
		h.ok(uid is String and uid != "", "%s : identifiant %s (texte non vide attendu)" % [it.name, var_to_str(uid)])
		h.ok(not seen.has(uid), "%s : identifiant %s en double" % [it.name, var_to_str(uid)])
		seen[uid] = true
	h.egal(p.equipment.arme.uid, "i5", "le premier porteur garde son identifiant")
	h.egal(p.stash[3].uid, "i2", "un identifiant valide et unique est gardé")
	h.egal(p.stash[5].uid, "u-ancien")
	# Les objets suivants ne retombent pas sur un identifiant pris.
	var fresh: Dictionary = _with_uid(g, "talisman", null)
	D6Profile.stash_loot(p, fresh)
	h.ok(not seen.has(fresh.uid), "nouvel objet : identifiant %s déjà pris" % var_to_str(fresh.get("uid")))
	# Chaque objet se retrouve par son identifiant : c'est bien lui qu'on recycle.
	var target: Dictionary = p.stash[2]
	h.egal(D6Profile.salvage_from_stash(p, g.tuning, target.uid).ok, true)
	h.ok(not p.stash.any(func(it): return is_same(it, target)), "l'objet recyclé est celui désigné")

# ---------------------------------------------------------------- 6. Charon : charge au mur

static func _t_charon(h) -> void:
	var g: Dictionary = h.bac_a_sable({"seed": 9.0, "godMode": true})
	var room: Dictionary = g.room
	g.player.x = room.w - room.pad - 60.0
	var e: Dictionary = D6Enemies.create_enemy(g, "gardien", g.player.x - CHARGE_RUN, g.player.y, {"boss": true, "spawnT": 0.0})
	D6BossCommon.set_state(e, "charge")
	e.pattern = "charge"
	var walled := false
	for i in h.ticks(CHARGE_TIMEOUT):
		D6Game.step_game(g, h.entree())
		if e.state == "charge" and e.patternStep == 1.0:
			g.player.y = room.pad + 60.0 # la ruée est partie : le héros sort de la ligne (son corps arrêterait Charon)
		if e.state == "stunned":
			walled = true
			break
	h.ok(walled, "Charon n'a pas percuté le mur en %s s (état : %s)" % [str(CHARGE_TIMEOUT), str(e.state)])
	h.ok(e.stun > 0.0, "sonné")
	h.egal([e.patternStep, e.patternT], [0.0, 0.0], "sonné : l'étape et le chronomètre de la charge sont remis à zéro")
	h.egal(e.get("tele"), null)
	# Il se relève et reprend ses attaques.
	h.avancer(g, h.ticks(g.tuning.boss.gardien.charge.wallStun + 0.1))
	h.different(e.state, "stunned")

# ---------------------------------------------------------------- 7. étourdi pendant sa récupération

## Image de la 2e attaque d'un ennemi seul face au héros immobile ; avec `stun` > 0, il est
## étourdi dès qu'il récupère de la 1re. -1 : pas de 2e attaque avant FOE_TIMEOUT.
static func _second_attack_tick(h, kind: String, dist: float, stun: float) -> int:
	var g: Dictionary = h.bac_a_sable({"seed": 7.0, "godMode": true})
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dist, g.player.y, {"spawnT": 0.0})
	e.cooldown = 0.0
	e.maxHp = 1e6
	e.hp = 1e6
	var attacks := 0
	var stunned := false
	for i in h.ticks(FOE_TIMEOUT):
		D6Game.step_game(g, h.entree())
		for ev in g.events:
			if ev.type == "enemyAttack" and ev.get("id") == e.id:
				attacks += 1
		g.events.clear()
		if attacks >= 2:
			return i
		if stun > 0.0 and not stunned and attacks == 1 and e.state == "recover":
			stunned = true
			D6Combat.damage_enemy(g, e, {"kind": "gadget", "amount": 1.0, "stun": stun, "canCrit": false})
			if e.state != "stunned":
				return -2
	return -1

static func _t_etourdi(h) -> void:
	for foe in RECOVERY_FOES:
		var kind: String = foe[0]
		var plain := _second_attack_tick(h, kind, foe[1], 0.0)
		var stunned := _second_attack_tick(h, kind, foe[1], SHORT_STUN)
		h.ok(plain > 0, "%s : pas de 2e attaque sans étourdissement (%d)" % [kind, plain])
		h.ok(stunned > 0, "%s : pas de 2e attaque après étourdissement (%d)" % [kind, stunned])
		h.ok(stunned >= plain, "%s : étourdi en récupération, il ré-attaque à l'image %d ; sans étourdissement, %d" % [kind, stunned, plain])

# ---------------------------------------------------------------- 8. dégâts infligés sans overkill

static func _t_overkill(h) -> void:
	var g: Dictionary = C.arena(h)
	var tough: Dictionary = C.dummy(g, 80.0, 0.0, "brute", 500.0)
	var dealt: float = D6Combat.damage_enemy(g, tough, {"kind": "melee", "amount": 40.0, "canCrit": false})
	h.ok(dealt > 0.0 and tough.hp == 500.0 - dealt, "coup non létal")
	h.egal(g.telemetry.damageDealt, dealt, "coup non létal : compté en entier")
	var weak: Dictionary = C.dummy(g, -80.0, 0.0, "brute", 5.0)
	var charge0: float = g.player.superCharge
	var blow: float = D6Combat.damage_enemy(g, weak, {"kind": "melee", "amount": 40.0, "canCrit": false})
	h.ok(weak.dead and blow > 5.0, "coup de grâce de %s dégâts sur 5 PV" % str(blow))
	h.egal(g.telemetry.damageDealt, dealt + 5.0, "coup de grâce : seuls les PV retirés comptent")
	# … comme pour la jauge de Super : les deux mesurent la même chose.
	var need: float = g.tuning["super"].chargeDamage * (g.player.stats.weaponDamage / g.tuning.weaponBase)
	h.proche(g.player.superCharge - charge0, (5.0 / need) * g.player.stats.superChargeMult, 1e-9, "jauge de Super")

# ---------------------------------------------------------------- 9. textes de la compétence

## Premier mot du nom de chaque compétence du jeu (« Lance », « Chaîne », « Bond »…).
static func _skill_words(t: Dictionary) -> Array:
	var out: Array = []
	for id in t.skills:
		out.append(String(t.skills[id].name).split(" ")[0])
	return out

static func _names_a_skill(text: String, words: Array) -> String:
	for w in words:
		if w in text:
			return w
	return ""

static func _about_skill(def: Dictionary) -> bool:
	var pr = def.get("proc")
	var only_skill: bool = pr is Dictionary and pr.get("sources") == ["skill"]
	return def.get("slot") == "skill" or only_skill or SKILL_STATS.has(def.get("stat"))

static func _t_textes(h) -> void:
	var t: Dictionary = D6Data.create_tuning()
	var words := _skill_words(t)
	h.ok(words.has("Lance") and words.size() >= 5, "compétences du jeu : %s" % str(words))
	var boons: Dictionary = C.boons_t()
	var checked := 0
	for def in boons.BOONS + boons.DUOS + boons.PACTS:
		if _about_skill(def):
			checked += 1
			h.egal(_names_a_skill(def.text, words), "", "bénédiction %s : « %s »" % [def.id, def.text])
	h.ok(checked >= 3, "bénédictions de compétence vérifiées : %d" % checked)
	var loot: Dictionary = D6Data.tables().loot
	for stat in SKILL_STATS:
		h.egal(_names_a_skill(loot.STAT_LABELS[stat], words), "", "libellé de %s : « %s »" % [stat, loot.STAT_LABELS[stat]])
	for slot in loot.AFFIXES:
		for a in loot.AFFIXES[slot]:
			if SKILL_STATS.has(a[0]):
				h.egal(_names_a_skill("%s %s" % [a[3], a[4]], words), "", "affixe de %s : « %s », « %s »" % [a[0], a[3], a[4]])
	# Dans une vraie partie, avec une AUTRE compétence que la Lance : ce que les écrans affichent.
	var meta: Dictionary = D6Profile.new_profile(t)
	meta.unlocked.skills.append("chaine")
	meta.loadout.slots[0] = "chaine"
	var g: Dictionary = D6Game.create_game({"seed": 3.0, "meta": meta})
	h.egal(g.kit.slots[0], "chaine")
	for id in ["charme", "convoitise"]:
		var shown: Dictionary = D6Run.describe_boon({"id": id, "rarity": "commun", "level": 1.0})
		h.ok(not ("Lance" in shown.text) and C.no_braces(shown.text), "%s, Chaîne équipée : « %s »" % [id, shown.text])
	for stat in SKILL_STATS:
		var line: String = D6Loot.affix_text({"stat": stat, "value": -0.1 if stat == "skillCooldownMult" else 0.1, "format": "pctNeg" if stat == "skillCooldownMult" else "pct"})
		h.ok(not ("Lance" in line), "ligne d'objet, Chaîne équipée : « %s »" % line)

static func tests(h) -> void:
	h.test("défaut 1 · changer d'arme remet l'enchaînement au coup 1 (Dagues à 4 coups -> Lame à 3 coups, sans lire hors du combo)", func(): _t_combo(h))
	h.test("défaut 2 · autel de sang : la bénédiction garde la meilleure rareté entre « rare » et son tirage (épique reste épique)", func(): _t_sang_rarete(h))
	h.test("défaut 2 · autel de sang : à 1 PV l'offrande est grisée et refusée ; tant qu'elle coûte des PV, elle est acceptée", func(): _t_sang_un_pv(h))
	h.test("défaut 3 · portes : deux récompenses distinctes dès que deux sont possibles, même après 21 tirages identiques, sans tirage de plus", func(): _t_portes(h))
	h.test("défaut 5 · profil : un identifiant d'objet absent, vide, non textuel ou en double est réattribué, sans perdre l'objet", func(): _t_uids(h))
	h.test("défaut 6 · Charon : la charge qui percute un mur remet l'étape et le chronomètre du pattern à zéro", func(): _t_charon(h))
	h.test("défaut 7 · étourdir un ennemi pendant sa récupération ne lui fait jamais ré-attaquer plus tôt (diablotin, brute, archer, pavois, traqueur)", func(): _t_etourdi(h))
	h.test("défaut 8 · dégâts infligés : l'overkill ne compte pas, comme pour la jauge de Super", func(): _t_overkill(h))
	h.test("défaut 9 · aucun texte de compétence (bénédiction, libellé, affixe) ne nomme une compétence précise", func(): _t_textes(h))
