extends RefCounted
## Portage de GAMES/dungeon_666/tests/logic.test.mjs.
## Tests unitaires des RÈGLES (une règle, un test). Les valeurs sont lues dans le tuning,
## jamais recopiées : un réglage de feel ne casse pas un test, une règle cassée oui.

static func tests(h) -> void:
	_tests_dash(h)
	_tests_combo(h)
	_tests_kit(h)
	_tests_ennemis(h)
	_tests_etages(h)
	_tests_progression(h)
	_tests_gardien(h)
	_tests_tampons(h)

static func _tests_dash(h) -> void:
	h.test("dash : déplace de la distance réglée et consomme une charge", func(): _dash_distance(h))
	h.test("dash : pendant les i-frames, aucun dégât n'est appliqué et l'esquive est comptée", func(): _dash_iframes(h))
	h.test("dash : i-frames expirées -> le coup porte", func(): _dash_iframes_expirees(h))
	h.test("dash : les charges se rechargent une par une", func(): _dash_recharge(h))
	h.test("dash : sans charge, rien ne part", func(): _dash_sans_charge(h))
	h.test("dash : annule la récupération d'une attaque, immédiatement", func(): _dash_annule_attaque(h))
	h.test("dash : un appui pendant le gel d'impact l'interrompt", func(): _dash_interrompt_gel(h))
	h.test("frappe de dash : une attaque juste après un dash utilise le profil dashStrike", func(): _frappe_de_dash(h))

static func _tests_combo(h) -> void:
	h.test("combo : trois coups enchaînés, le 3e est le coup lourd, puis retour au 1er", func(): _combo(h))
	h.test("coup qui touche : dégâts, knockback, gel d'impact", func(): _coup_qui_touche(h))
	h.test("gel d'impact : la simulation est figée (le temps de jeu n'avance pas)", func(): _gel_fige(h))
	h.test("tampon d'entrée : une attaque pressée pendant un dash part à la sortie du dash", func(): _tampon_entree(h))
	h.test("visée assistée : vise l'ennemi le plus proche quand on ne vise pas", func(): _visee_assistee(h))
	h.test("visée manuelle : l'emporte toujours sur la visée assistée", func(): _visee_manuelle(h))

static func _tests_kit(h) -> void:
	h.test("gadget : consomme une charge, repousse, étourdit, détruit les projectiles ennemis", func(): _gadget(h))
	h.test("esquive parfaite : jauge de Super et recharge du dash récompensées", func(): _esquive_parfaite(h))
	h.test("frappe de dash : attaquer en fin de dash coupe la ruée et frappe", func(): _frappe_fin_de_dash(h))
	h.test("Super : se charge en infligeant des dégâts, puis rend invulnérable", func(): _super(h))
	h.test("compétence : la lance part dans la direction glissée et transperce", func(): _competence(h))

static func _tests_ennemis(h) -> void:
	h.test("aucun dégât de contact : un ennemi collé au héros sans attaquer ne blesse pas", func(): _pas_de_contact(h))
	h.test("jetons d'attaque : jamais plus de maxAttackers ennemis de mêlée en attaque simultanée", func(): _jetons(h))
	h.test("télégraphe : un ennemi tué pendant sa préparation n'inflige rien (zone annulée)", func(): _telegraphe(h))
	h.test("wall slam : un ennemi projeté contre un mur est étourdi et blessé", func(): _wall_slam(h))

static func _tests_etages(h) -> void:
	# Gate Pierre 2026-10-01 (spec V2 : « Tous les 18 étages : Gardien ») — voir 01_DESIGN/GATE_TESTS_V2.md.
	h.test("666 étages : 37 sections de 18, Gardien au 18e étage de chaque section", func(): _etages_666(h))
	h.test("checkpoint : battre le Gardien de l'étage 18 ouvre la reprise à l'étage 19", func():
		h.egal(D6Floors.checkpoint_after_boss(_sandbox().tuning, 18.0), 19.0))
	h.test("difficulté : croissante et finie jusqu'à 666", func(): _difficulte(h))

static func _tests_progression(h) -> void:
	h.test("butin : le nombre d'affixes suit la rareté, les légendaires ont un pouvoir", func(): _butin(h))
	h.test("bénédictions : un emplacement exclusif remplace l'ancien, les passifs s'empilent", func(): _benedictions(h))
	h.test("arme : une arme plus forte augmente les dégâts de tous les coups", func(): _arme(h))
	h.test("équipement : les affixes modifient les statistiques du héros", func(): _equipement(h))
	h.test("mort sans instantané : bénédictions perdues, équipement conservé, moitié de l'or, reprise au checkpoint", func(): _mort(h))
	h.test("salle nettoyée : récompense posée, portes fermées tant qu'elle n'est pas prise", func(): _salle_nettoyee(h))
	h.test("portes : l'étage 17 mène au Gardien, l'antichambre propose marchand ou autel", func(): _portes(h))

static func _tests_gardien(h) -> void:
	# Gate Pierre 2026-10-01 (spec V2 : « reset des bonus temporaires », « ne pas figer le build ») :
	# la règle s'inverse — le checkpoint s'ouvre, mais la mort vide toujours le build temporaire.
	h.test("checkpoint : vaincre un Gardien ouvre la reprise ; mourir ensuite vide le build temporaire, garde le permanent", func(): _checkpoint_gardien(h))
	h.test("Gardien vaincu : ses impacts en attente et ses orbes en vol ne blessent plus", func(): _gardien_vaincu(h))
	# Gate Pierre 2026-10-01 : « Réessayer le Gardien » gardait le build temporaire (contraire à la V2) ;
	# on répète un Gardien en ENTRAÎNEMENT (Ville), sans build, sans récompense ni risque.
	h.test("entraînement : mourir face au Gardien le relance aussitôt, sans build ni récompense", func(): _entrainement(h))

static func _tests_tampons(h) -> void:
	h.test("tampon : un dash à vide ou un Super pas prêt n'avalent pas la frappe suivante", func(): _tampon_a_vide(h))
	h.test("Lance interrompue par un dash : la Lance part quand même (recharge jamais perdue)", func(): _lance_interrompue(h))
	h.test("esquive parfaite : deux projectiles superposés pendant un dash = exactement 2 esquives", func(): _deux_esquives(h))
	# Gate Pierre 2026-10-01 : les instantanés de build (ancienne sauvegarde) sont abandonnés.
	h.test("relance de l'appli au checkpoint : aucune bénédiction, même équipement permanent", func(): _relance(h))

# ---------------------------------------------------------------- outillage (celui du fichier web)

## Partie de test : salle vidée (aucune vague), héros au centre.
static func _sandbox(opts: Dictionary = {}) -> Dictionary:
	var o := {"seed": 11.0}
	o.merge(opts, true)
	var g: Dictionary = D6Game.create_game(o)
	g.spawns.clear()
	g.enemies.clear()
	g.room.waves = []
	g.room.waveIndex = 0.0
	g.room.obstacles = []
	# Salle déclarée nettoyée, sans récompense ni porte : rien ne vient interrompre le test.
	g.room.cleared = true
	g.room.interact = null
	g.room.doors = []
	g.player.x = g.room.w / 2.0
	g.player.y = g.room.h / 2.0
	g.events.clear()
	return g

static func _input(over: Dictionary = {}) -> Dictionary:
	var input: Dictionary = D6Game.empty_input()
	input.merge(over, true)
	return input

## Comme `steps` du fichier web : n pas, SANS vider les événements.
static func _steps(g: Dictionary, n: int, over: Dictionary = {}) -> void:
	for i in n:
		D6Game.step_game(g, _input(over))

static func _dummy(g: Dictionary, dx: float, dy: float, kind: String = "brute") -> Dictionary:
	var e: Dictionary = D6Enemies.create_enemy(g, kind, g.player.x + dx, g.player.y + dy, {"spawnT": 0.0})
	e.cooldown = 99.0 # ne riposte pas : on teste le héros
	return e

static func _ticks(seconds: float) -> int:
	return int(ceilf(seconds / D6Data.DT))

static func _boons() -> Array:
	return D6Data.tables().boons.BOONS

static func _boss(g: Dictionary):
	for e in g.enemies:
		if D6Js.truthy(e.get("boss")):
			return e
	return null

static func _a_nombre(arr: Array, v: float) -> bool:
	for x in arr:
		if float(x) == v:
			return true
	return false

static func _hazard_joueur(g: Dictionary) -> bool:
	return g.hazards.any(func(hz): return D6Js.truthy(hz.get("hitsPlayer")))

## Attaque maintenue vers la droite jusqu'au premier coup porté ; rend les PV perdus par `e`.
static func _degats_premier_coup(g: Dictionary, e: Dictionary) -> float:
	var i := 0
	while i < 20 and e.hp == e.maxHp:
		D6Game.step_game(g, _input({"attack": true, "aimX": 1.0, "aimY": 0.0}))
		i += 1
	return e.maxHp - e.hp

# ---------------------------------------------------------------- dash

static func _dash_distance(h) -> void:
	var g := _sandbox()
	var t: Dictionary = g.tuning.dash
	var x0: float = g.player.x
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	h.egal(g.player.state, "dash")
	h.egal(g.player.dashCharges, t.charges - 1.0)
	_steps(g, _ticks(t.duration) - 1, {"moveX": 1.0})
	var traveled: float = g.player.x - x0
	h.ok(absf(traveled - t.distance) < 12.0, "parcouru %.1f u, attendu ~%s" % [traveled, D6Js.num_str(t.distance)])

static func _dash_iframes(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	var hp: float = g.player.hp
	var landed: bool = D6Combat.damage_player(g, 30.0, {"kind": "test", "id": 999.0, "x": g.player.x, "y": g.player.y})
	h.egal(landed, false)
	h.egal(g.player.hp, hp)
	h.egal(g.telemetry.dodges, 1.0)

static func _dash_iframes_expirees(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	_steps(g, _ticks(g.tuning.dash.iframes) + 2)
	var hp: float = g.player.hp
	h.egal(D6Combat.damage_player(g, 10.0, {"kind": "test", "id": 1.0}), true)
	h.ok(g.player.hp < hp)

static func _dash_recharge(h) -> void:
	var g := _sandbox()
	var t: Dictionary = g.tuning.dash
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	_steps(g, _ticks(t.duration * (1.0 - 0.35)) + 1)
	D6Game.step_game(g, _input({"moveX": -1.0, "dashPressed": true}))
	h.egal(g.player.dashCharges, t.charges - 2.0)
	_steps(g, _ticks(t.recharge) + 2)
	h.egal(g.player.dashCharges, t.charges - 1.0)
	_steps(g, _ticks(t.recharge) + 2)
	h.egal(g.player.dashCharges, t.charges)

static func _dash_sans_charge(h) -> void:
	var g := _sandbox()
	g.player.dashCharges = 0.0
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	h.different(g.player.state, "dash")

static func _dash_annule_attaque(h) -> void:
	var g := _sandbox()
	_dummy(g, 50.0, 0.0)
	D6Game.step_game(g, _input({"attackPressed": true}))
	h.egal(g.player.state, "attack")
	D6Game.step_game(g, _input({"moveX": -1.0, "dashPressed": true}))
	# Le gel d'impact a pu se déclencher : le dash l'interrompt (réactivité avant emphase).
	h.egal(g.player.state, "dash")

static func _dash_interrompt_gel(h) -> void:
	var g := _sandbox()
	g.hitstop = 0.1
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	h.egal(g.hitstop, 0.0)
	h.egal(g.player.state, "dash")

static func _frappe_de_dash(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	_steps(g, _ticks(g.tuning.dash.duration))
	h.ok(g.player.strikeWindow > 0.0, "fenêtre de frappe ouverte après le dash")
	D6Game.step_game(g, _input({"attackPressed": true}))
	h.egal(g.player.state, "attack")
	h.egal(g.player.attack.strike, true)

# ---------------------------------------------------------------- combo, gel, tampon

static func _combo(h) -> void:
	var g := _sandbox()
	var seen: Array = []
	var i := 0
	while i < 240 and seen.size() < 4:
		D6Game.step_game(g, _input({"attack": true}))
		for ev in g.events:
			if ev.type == "attackStart":
				seen.append(ev.index)
		g.events.clear()
		i += 1
	h.egal(seen.slice(0, 4), [0.0, 1.0, 2.0, 0.0])

static func _coup_qui_touche(h) -> void:
	var g := _sandbox()
	var e := _dummy(g, 40.0, 0.0)
	var hp: float = e.hp
	g.player.facing = 0.0
	var i := 0
	while i < 20 and e.hp == hp:
		D6Game.step_game(g, _input({"attack": true, "aimX": 1.0, "aimY": 0.0}))
		i += 1
	h.ok(e.hp < hp, "l'ennemi a perdu des PV")
	h.ok(e.kvx > 0.0, "repoussé dans l'axe du coup")
	h.ok(g.hitstop > 0.0, "gel d'impact déclenché")

static func _gel_fige(h) -> void:
	var g := _sandbox()
	g.hitstop = 0.05
	var t0: float = g.time
	D6Game.step_game(g, _input({"moveX": 1.0}))
	h.egal(g.time, t0)

static func _tampon_entree(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	D6Game.step_game(g, _input({"attackPressed": true}))
	h.egal(g.player.state, "dash")
	_steps(g, _ticks(g.tuning.dash.duration))
	h.egal(g.player.state, "attack")

static func _visee_assistee(h) -> void:
	var g := _sandbox()
	_dummy(g, -200.0, 0.0)
	var near := _dummy(g, 0.0, 90.0)
	D6Game.step_game(g, _input({"attackPressed": true}))
	var a: Dictionary = g.player.attack
	h.egal(a.targetId, near.id)
	h.ok(a.dirY > 0.9)

static func _visee_manuelle(h) -> void:
	var g := _sandbox()
	_dummy(g, 0.0, 90.0)
	D6Game.step_game(g, _input({"attackPressed": true, "aimX": -1.0, "aimY": 0.0}))
	h.ok(g.player.attack.dirX < -0.99)

# ---------------------------------------------------------------- gadget, Super, compétence

static func _gadget(h) -> void:
	var g := _sandbox()
	var e := _dummy(g, 60.0, 0.0, "imp")
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "arrow", "x": g.player.x - 50.0, "y": g.player.y, "vx": 300.0, "vy": 0.0, "r": 7.0, "damage": 10.0, "range": 600.0})
	var charges: float = g.player.slots[1].charges
	D6Game.step_game(g, _input({"skill2Pressed": true}))
	h.egal(g.player.slots[1].charges, charges - 1.0)
	h.ok(e.get("stun", 0.0) > 0.0 or D6Js.truthy(e.get("dead")))
	var restants: Array = g.projectiles.filter(func(p): return p.owner == "enemy" and not D6Js.truthy(p.get("dead")))
	h.egal(restants.size(), 0)

static func _esquive_parfaite(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	var sup: float = g.player.superCharge
	var rec: float = g.player.dashRecharge
	D6Combat.damage_player(g, 10.0, {"kind": "test", "id": 4242.0})
	h.ok(g.player.superCharge > sup)
	h.ok(g.player.dashRecharge >= rec + g.tuning.dash.perfectDodgeRefund - 1e-9)

static func _frappe_fin_de_dash(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	var t: Dictionary = g.tuning.dash
	_steps(g, _ticks(t.duration * (1.0 - t.strikeCancelFrom)) + 1, {"moveX": 1.0})
	h.egal(g.player.state, "dash")
	D6Game.step_game(g, _input({"attackPressed": true}))
	h.egal(g.player.state, "attack")
	h.egal(g.player.attack.strike, true)

static func _super(h) -> void:
	# Combat V3, étape 2 : la Colère n'est plus l'ultime du Revenant ; elle est lancée directement.
	var g := _sandbox({"tuning": {"classes": {"revenant": {"super": "colere"}}}})
	g.player.superCharge = 1.0
	h.ultime(g)
	h.egal(g.player.state, "super")
	h.egal(g.player.superCharge, 0.0)
	var hp: float = g.player.hp
	D6Combat.damage_player(g, 50.0, {"kind": "test", "id": 5.0})
	h.egal(g.player.hp, hp)

static func _competence(h) -> void:
	var g := _sandbox()
	var a := _dummy(g, 120.0, 0.0, "imp")
	var b := _dummy(g, 220.0, 0.0, "imp")
	D6Game.step_game(g, _input({"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0}))
	_steps(g, 30)
	h.ok(a.hp < a.maxHp and b.hp < b.maxHp, "les deux ennemis alignés sont touchés")
	h.ok(g.player.slots[0].cd > 0.0)

# ---------------------------------------------------------------- ennemis : équité

static func _pas_de_contact(h) -> void:
	var g := _sandbox()
	var e := _dummy(g, 20.0, 0.0, "brute")
	e.cooldown = 999.0
	var hp: float = g.player.hp
	_steps(g, 120)
	h.egal(g.player.hp, hp)

static func _jetons(h) -> void:
	var g := _sandbox()
	for i in 8:
		# Math.cos / Math.sin natifs côté web : cos / sin natifs ici (placement d'ennemis du test).
		var a := (float(i) / 8.0) * PI * 2.0
		var e: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x + cos(a) * 45.0, g.player.y + sin(a) * 45.0, {"spawnT": 0.0})
		e.cooldown = 0.0
	g.godMode = true
	var worst := 0
	for i in 400:
		D6Game.step_game(g, _input())
		var n: int = g.enemies.filter(func(e): return not D6Js.truthy(e.get("dead")) and (e.state == "windup" or e.state == "strike")).size()
		worst = maxi(worst, n)
	h.ok(worst <= g.tuning.combat.maxAttackers, "pire cas %d" % worst)
	h.ok(worst >= 1, "les ennemis attaquent bien")

static func _telegraphe(h) -> void:
	var g := _sandbox()
	var e := _dummy(g, 60.0, 0.0, "brute")
	e.cooldown = 0.0
	var i := 0
	while i < 60 and g.hazards.size() == 0:
		D6Game.step_game(g, _input())
		i += 1
	h.egal(g.hazards.size(), 1, "la brute prépare son impact")
	e.hp = 1.0
	e.dead = true
	var hp: float = g.player.hp
	_steps(g, _ticks(g.tuning.enemies.brute.windup) + 2)
	h.egal(g.player.hp, hp)

static func _wall_slam(h) -> void:
	var g := _sandbox()
	var e := _dummy(g, 0.0, 0.0, "imp")
	e.x = g.room.pad + e.r + 30.0
	e.y = g.room.h / 2.0
	g.player.x = e.x + 200.0
	e.kvx = -900.0
	var hp: float = e.hp
	_steps(g, 10)
	h.ok(e.hp < hp)
	h.ok(g.telemetry.wallSlams >= 1.0)

# ---------------------------------------------------------------- structure des 666 étages

static func _etages_666(h) -> void:
	var g := _sandbox()
	var t: Dictionary = g.tuning
	var bosses := 0
	for f in range(1, 667):
		if D6Js.truthy(D6Floors.floor_info(t, float(f)).isBoss):
			bosses += 1
	h.egal(bosses, 37)
	h.egal(D6Floors.floor_info(t, 17.0).isBoss, false)
	h.egal(D6Floors.floor_info(t, 18.0).isBoss, true)
	h.egal(D6Floors.floor_info(t, 19.0).indexInSection, 1.0)
	h.egal(D6Floors.floor_info(t, 666.0).isFinal, true)
	h.egal(D6Floors.floor_info(t, 1.0).circleName, t.floors.circleNames[0])
	h.egal(D6Floors.floor_info(t, 648.0).circle, 9.0)
	h.egal(D6Floors.floor_info(t, 649.0).inFinale, true)

static func _difficulte(h) -> void:
	var t: Dictionary = _sandbox().tuning
	var prev: Dictionary = D6Floors.floor_scaling(t, 1.0)
	for f in [6.0, 30.0, 72.0, 333.0, 666.0]:
		var s: Dictionary = D6Floors.floor_scaling(t, f)
		h.ok(s.hp > prev.hp and s.damage > prev.damage and is_finite(s.hp))
		prev = s

# ---------------------------------------------------------------- progression

static func _butin(h) -> void:
	var g := _sandbox()
	for r in D6Data.tables().loot.ITEM_RARITIES:
		var it: Dictionary = D6Loot.generate_item(g, {"rarity": r.id, "slot": "arme"})
		h.egal(it.affixes.size(), r.affixes)
		h.egal(D6Js.truthy(it.get("power")), r.id == "legendaire")

static func _nb_boons(g: Dictionary, slot: String) -> int:
	return g.run.boons.filter(func(b): return D6Boons.boon_def(b.id).get("slot") == slot).size()

static func _benedictions(h) -> void:
	var g := _sandbox()
	var attacks: Array = _boons().filter(func(b): return b.get("slot") == "attack")
	D6Boons.add_boon(g.run, {"id": attacks[0].id, "rarity": "commun"})
	D6Boons.add_boon(g.run, {"id": attacks[1].id, "rarity": "commun"})
	h.egal(_nb_boons(g, "attack"), 1)
	var passives: Array = _boons().filter(func(b): return b.get("slot") == "passive" and D6Js.truthy(b.get("stat")))
	D6Boons.add_boon(g.run, {"id": passives[0].id, "rarity": "commun"})
	D6Boons.add_boon(g.run, {"id": passives[1].id, "rarity": "commun"})
	h.egal(_nb_boons(g, "passive"), 2)

static func _arme(h) -> void:
	var g := _sandbox()
	var base := _degats_premier_coup(g, _dummy(g, 40.0, 0.0))
	var g2 := _sandbox()
	var arme: Dictionary = g2.run.items.arme.duplicate()
	arme.base = {"damage": g2.tuning.weaponBase * 2.0}
	g2.run.items.arme = arme
	D6Stats.recompute_stats(g2)
	var doubled := _degats_premier_coup(g2, _dummy(g2, 40.0, 0.0))
	h.ok(doubled >= base * 1.8, "dégâts %s -> %s" % [D6Js.num_str(base), D6Js.num_str(doubled)])

static func _equipement(h) -> void:
	var g := _sandbox()
	var item: Dictionary = D6Loot.generate_item(g, {"slot": "armure", "rarity": "rare"})
	item.base = {"hp": g.run.items.armure.base.hp} # même base : on isole l'affixe
	item.affixes = [{"stat": "maxHpBonus", "value": 25.0, "format": "flat"}]
	var before: float = g.player.maxHp
	g.run.items.armure = item
	D6Stats.recompute_stats(g)
	h.egal(g.player.maxHp, before + 25.0)

static func _mort(h) -> void:
	var g := _sandbox()
	g.meta.checkpoints = [1.0, 7.0]
	g.run.gold = 100.0
	D6Boons.add_boon(g.run, {"id": _boons()[0].id, "rarity": "commun"})
	var item: Dictionary = D6Loot.generate_item(g, {"slot": "arme", "rarity": "magique"})
	g.run.items.arme = item
	g.godMode = false
	D6Combat.damage_player(g, 9999.0, {"kind": "test", "id": 77.0})
	_steps(g, _ticks(2.0))
	h.egal(g.mode, "dead")
	h.egal(D6Game.apply_command(g, {"type": "respawn", "floor": 7.0}), true)
	h.egal(g.mode, "play")
	h.egal(g.run.floor, 7.0)
	h.egal(g.run.boons.size(), 0)
	h.ok(is_same(g.run.items.arme, item), "l'arme équipée est le même objet")
	h.egal(g.run.gold, floorf(100.0 * g.tuning.economy.deathGoldKeep))
	h.egal(g.player.hp, g.player.maxHp)

static func _salle_nettoyee(h) -> void:
	var g := _sandbox()
	g.room.plan = {"kind": "combat", "reward": "boon", "family": "colere"}
	D6Run.on_room_clear(g)
	h.ok(g.room.interact != null and g.room.interact.kind == "boon")
	h.ok(g.room.doors.size() >= 1)
	h.ok(g.room.doors.all(func(d): return not D6Js.truthy(d.get("open"))))
	# Le héros touche la récompense -> menu -> choix -> portes ouvertes.
	g.player.x = g.room.interact.x
	g.player.y = g.room.interact.y
	# Le dernier ennemi tombé déclenche un gel d'impact : quelques pas avant le contact.
	var i := 0
	while i < 30 and g.mode == "play":
		D6Game.step_game(g, _input())
		i += 1
	h.egal(g.mode, "choice")
	var tick: float = g.tick
	D6Game.step_game(g, _input())
	h.egal(g.tick, tick, "la simulation est en pause pendant un choix")
	D6Game.apply_command(g, {"type": "choose", "index": 0.0})
	h.egal(g.mode, "play")
	h.egal(g.run.boons.size(), 1)
	h.ok(g.room.doors.all(func(d): return D6Js.truthy(d.get("open"))))

static func _portes(h) -> void:
	var g := _sandbox()
	D6Run.enter_floor(g, 16.0, {"reward": "gold"})
	g.room.plan = {"kind": "combat", "reward": "gold"}
	D6Run.on_room_clear(g)
	var rewards: Array = g.room.doors.map(func(d): return d.reward)
	rewards.sort()
	h.egal(rewards, ["event", "shop"])
	D6Run.enter_floor(g, 17.0, {"reward": "shop"})
	h.egal(g.room.doors.map(func(d): return d.reward), ["boss"])

# ---------------------------------------------------------------- Gardien, checkpoint, entraînement

static func _checkpoint_gardien(h) -> void:
	var g := _sandbox()
	D6Run.enter_floor(g, 18.0, null)
	g.spawns.clear()
	g.enemies.clear()
	D6Boons.add_boon(g.run, {"id": _boons()[0].id, "rarity": "rare"})
	var arme = g.run.items.arme
	g.run.gold = 80.0
	g.room.plan = {"kind": "boss", "reward": "boss"}
	g.room.kind = "boss"
	D6Run.on_room_clear(g)
	h.ok(_a_nombre(g.meta.checkpoints, 19.0))
	# Après le checkpoint, le build continue de grandir, puis le héros meurt.
	D6Boons.add_boon(g.run, {"id": _boons()[3].id, "rarity": "commun"})
	D6Combat.damage_player(g, 99999.0, {"kind": "test", "id": 31.0})
	_steps(g, _ticks(2.0))
	h.egal(g.mode, "dead")
	D6Game.apply_command(g, {"type": "respawn", "floor": 19.0})
	h.egal(g.run.boons, [], "le temporaire repart de zéro")
	h.ok(is_same(g.run.items.arme, arme), "l'équipement (permanent) est conservé")
	h.egal(g.run.gold, floorf(80.0 * g.tuning.economy.deathGoldKeep), "Charon prélève sa part")
	h.egal(g.run.floor, 19.0)

static func _gardien_vaincu(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 1.0, "startFloor": 18.0})
	g.events.clear()
	var i := 0
	while i < 1200 and not _hazard_joueur(g):
		D6Game.step_game(g, _input())
		i += 1
	h.ok(_hazard_joueur(g), "le Gardien a lancé une attaque")
	D6Projectiles.spawn_projectile(g, {"owner": "enemy", "kind": "bossOrb", "x": g.player.x + 200.0, "y": g.player.y, "vx": -300.0, "vy": 0.0, "r": 9.0, "damage": 12.0, "range": 900.0})
	var boss = _boss(g)
	if not h.ok(boss != null, "Gardien présent"):
		return
	boss.hp = 0.0
	boss.dead = true
	var hp0: float = g.player.hp
	_steps(g, 120)
	h.ok(g.player.hp >= hp0, "PV %s -> %s" % [D6Js.num_str(hp0), D6Js.num_str(g.player.hp)])
	var actifs: Array = g.hazards.filter(func(hz): return D6Js.truthy(hz.get("hitsPlayer")) and not D6Js.truthy(hz.get("done")))
	h.egal(actifs.size(), 0)

static func _entrainement(h) -> void:
	var g: Dictionary = D6Game.create_game({"seed": 2.0, "startFloor": 18.0, "practice": true})
	h.egal(g.info.isBoss, true)
	D6Boons.add_boon(g.run, {"id": _boons()[0].id, "rarity": "commun"})
	var souls: float = g.meta.souls
	var cps: Array = g.meta.checkpoints.duplicate()
	D6Combat.damage_player(g, 99999.0, {"kind": "test", "id": 66.0})
	_steps(g, _ticks(2.0))
	h.egal(g.mode, "dead")
	h.egal(D6Game.apply_command(g, {"type": "respawn"}), true)
	h.egal(g.mode, "play")
	h.egal(g.run.floor, 18.0)
	h.ok(_boss(g) != null or g.spawns.size() > 0, "le Gardien est de retour")
	h.egal(g.run.boons, [])
	h.egal(g.player.hp, g.player.maxHp)
	h.egal(g.meta.souls, souls)
	h.egal(g.meta.checkpoints, cps)

# ---------------------------------------------------------------- tampons, Lance, esquives, relance

static func _tampon_a_vide(h) -> void:
	var g := _sandbox()
	g.player.dashCharges = 0.0
	g.player.dashRecharge = 0.0
	g.player.superCharge = 0.0
	g.player.slots[0].cd = 99.0 # compétence en recharge : elle ne partira pas pendant la fenêtre du tampon
	D6Game.step_game(g, _input({"dashPressed": true}))
	D6Game.step_game(g, _input({"skill1Pressed": true}))
	D6Game.step_game(g, _input({"attackPressed": true}))
	_steps(g, 3)
	h.ok(g.telemetry.attacks >= 1.0, "la frappe est partie")

static func _lance_interrompue(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"skill1Pressed": true, "skill1AimX": 1.0, "skill1AimY": 0.0}))
	h.egal(g.player.state, "cast")
	D6Game.step_game(g, _input({"moveX": -1.0, "dashPressed": true}))
	h.egal(g.player.state, "dash")
	h.egal(g.telemetry.skillCasts, 1.0)
	h.ok(g.projectiles.any(func(p): return p.owner == "player"))

static func _deux_esquives(h) -> void:
	var g := _sandbox()
	D6Game.step_game(g, _input({"moveX": 1.0, "dashPressed": true}))
	for i in 4:
		D6Combat.damage_player(g, 5.0, {"kind": "test", "id": 900.0, "x": g.player.x, "y": g.player.y})
		D6Combat.damage_player(g, 5.0, {"kind": "test", "id": 901.0, "x": g.player.x, "y": g.player.y})
	h.egal(g.telemetry.dodges, 2.0)

static func _relance(h) -> void:
	var snapshot := {"boons": [{"id": _boons()[0].id, "rarity": "rare", "level": 1.0}], "gold": 120.0}
	var meta := {"checkpoints": [1.0, 19.0], "bestFloor": 19.0, "snapshots": {"19": snapshot}}
	var g: Dictionary = D6Game.create_game({"seed": 4.0, "startFloor": 19.0, "meta": meta})
	h.egal(g.run.floor, 19.0)
	h.egal(g.run.boons, [])
	h.egal(g.run.gold, 0.0)
	h.ok(D6Js.truthy(g.run.items.get("arme")) and D6Js.truthy(g.run.items.get("armure")), "équipement présent")
