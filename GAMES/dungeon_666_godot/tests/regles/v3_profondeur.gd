extends RefCounted
## COMBAT V3, étape 5 — L'ÉCHELLE EN PROFONDEUR (design/COMBAT_V3.md, « Étape 5 » ; mesure :
## outils/profondeur.gd). Le combat V3 a été réglé en section 1 ; le joueur joue cent étages plus
## bas. Ces tests gardent ce qui doit SUIVRE la profondeur :
##   - tout coup du héros (arme, compétence à tout rang, ultime, limier) est multiplié par le même
##     facteur, celui de l'arme portée : un nombre de dégâts « fixe » des données ne devient jamais
##     négligeable ;
##   - la jauge d'ultime demande le même nombre de coups à toute profondeur ;
##   - les SOINS que donne l'arbre de compétences en PV (Soif, Dîme de sang, Moisson) suivent les PV
##     d'un héros équipé du niveau de l'étage (D6Combat.heal_scaled) — défaut d'échelle corrigé à
##     l'étape 5 : 6 PV valaient 6 % de la vie à l'étage 1 et 0,5 % à l'étage 325.
## Le héros « en profondeur » est fabriqué par les règles : trois objets rares du niveau de l'étage
## qui précède (comme la mesure), SANS leurs affixes (seule leur base grandit avec la profondeur).

const Arbre = preload("res://sim/tree.gd")
const V3 = preload("res://tests/regles/v3_competences.gd")

const PROFOND := 325.0 # premier étage de la section 19
const RARETE := "rare"
const GRAINE_OBJETS := 666.0
const SOURCES := ["melee", "strike", "skill", "gadget", "super", "ally"]

static func tests(h) -> void:
	h.test("échelle : à l'étage 325, coup d'arme, compétence, compétence à charges, ultime et limier sont multipliés par le même facteur — l'arme portée", func(): _facteur(h))
	h.test("échelle : une compétence au rang 1 et au rang 5 pèse autant sur un ennemi de l'étage 325 que sur un ennemi de l'étage 1 (à moitié près)", func(): _poids(h))
	h.test("échelle : la jauge d'ultime demande les mêmes coups à l'étage 1 et à l'étage 325 (l'arme portée se simplifie)", func(): _jauge(h))
	h.test("échelle : heal_scaled suit les PV du héros équipé — un soin de l'arbre vaut la même part de vie à l'étage 1 et à l'étage 325 (à moitié près)", func(): _soin(h))
	h.test("échelle : Moisson (Stigmate), Soif (Tourbillon) et Dîme de sang (Triple sentence) soignent à l'échelle de l'étage ; à l'étage 1, le nombre des données", func(): _soins_de_l_arbre(h))

# ---------------------------------------------------------------- outillage

## Profil d'essai de `class_id` avec trois objets RARETE du niveau `etage` − 1 (rien à l'étage 1).
static func _meta(class_id: String, etage: float, slots: Array, rangs: Dictionary = {}, choix: Dictionary = {}) -> Dictionary:
	var m: Dictionary = V3._meta(class_id, slots, rangs, choix)
	if etage <= 1.0:
		return m
	var jetable: Dictionary = D6Game.create_game({"seed": GRAINE_OBJETS, "startFloor": 1.0, "meta": m, "sandbox": true})
	for slot in m.equipment:
		var voeu := {"slot": slot, "rarity": RARETE, "floor": etage - 1.0}
		if slot == "arme":
			voeu.weaponType = D6Data.default_tuning().classes[class_id].weapons[0]
		var objet: Dictionary = D6Loot.generate_item(jetable, voeu)
		objet.affixes = [] # la BASE seule (dégâts de l'arme, PV de l'armure) : les affixes tirés au hasard ajouteraient leurs bonus aux montants attendus
		objet.power = null
		D6Profile.ensure_uid(m, objet)
		m.equipment[slot] = objet
	return m

static func _bac(h, class_id: String, etage: float, slots: Array, rangs: Dictionary = {}, choix: Dictionary = {}) -> Dictionary:
	var g: Dictionary = h.bac_a_sable({"seed": 7.0, "startFloor": etage, "meta": _meta(class_id, etage, slots, rangs, choix)})
	g.tuning.combat.critChance = 0.0
	g.player.stats.critChance = 0.0
	g.player.facing = 0.0
	return g

## Facteur de l'arme portée : ce par quoi tout coup du héros est multiplié.
static func _arme(g: Dictionary) -> float:
	return g.player.stats.damageMult * g.player.stats.weaponDamage / g.tuning.weaponBase

static func _echelle(g: Dictionary) -> float:
	return D6Floors.floor_scaling(g.tuning, g.run.floor).hpGrowth

# ---------------------------------------------------------------- dégâts

static func _facteur(h) -> void:
	var g1 := _bac(h, "revenant", 1.0, ["lance", null, null])
	var g := _bac(h, "revenant", PROFOND, ["lance", null, null])
	h.egal(g.run.floor, PROFOND, "cas choisi : la partie est bien à l'étage 325")
	h.ok(_arme(g) > 10.0 * _arme(g1), "cas choisi : l'arme portée a grandi (×%s)" % str(_arme(g) / _arme(g1)))
	var e1: Dictionary = V3._vif(g1, 200.0, 0.0, "imp")
	var e: Dictionary = V3._vif(g, 200.0, 0.0, "imp")
	for kind in SOURCES:
		var coup := {"kind": kind, "amount": 30.0}
		var a1: float = D6Combat._scaled_amount(g1, e1, coup)
		var a: float = D6Combat._scaled_amount(g, e, coup)
		h.proche(a / a1, _arme(g) / _arme(g1), 1e-9, "source « %s » : multipliée par le facteur de l'arme" % kind)

static func _poids(h) -> void:
	var n: Dictionary = Arbre.node(V3._base(), "revenant", "lance")
	for rang in [1.0, V3._cfg().skillRanks]:
		var parts: Array = []
		for etage in [1.0, PROFOND]:
			var g := _bac(h, "revenant", etage, ["lance", null, null], {"lance": rang})
			var imp: Dictionary = D6Enemies.create_enemy(g, "imp", g.player.x + 400.0, g.player.y + 300.0, {"spawnT": 0.0})
			var e := V3._cible(g, 120.0, 0.0)
			var evs: Array = h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
			evs.append_array(h.avancer(g, h.ticks(0.6)))
			var coups: Array = V3._coups(evs, e)
			var attendu: float = D6Loadout.slot_def(g, 0).damage
			h.egal(attendu, Arbre.rank_value(n, "damage", rang) if rang > 1.0 else V3._def("lance").damage, "cas choisi : la Lance au rang %d" % int(rang))
			h.egal(coups, [maxf(1.0, D6Js.jround(attendu * _arme(g) * g.tuning.combat.stunDamageTakenMult))], "étage %d, rang %d : le nombre des données × l'arme" % [int(etage), int(rang)])
			parts.append(attendu * _arme(g) / imp.maxHp)
		h.ok(parts[1] >= 0.5 * parts[0], "rang %d : %s %% d'un diablotin à l'étage 325 contre %s %% à l'étage 1" % [int(rang), str(snappedf(parts[1] * 100.0, 0.1)), str(snappedf(parts[0] * 100.0, 0.1))])

## La jauge demande `chargeDamage` de dégâts « de l'arme de base » : l'arme portée se simplifie. Ce
## qui reste ne dépend que du BUILD (dégâts en plus, charge en plus des objets), pas de la profondeur.
static func _jauge(h) -> void:
	for etage in [1.0, PROFOND]:
		var g := _bac(h, "revenant", etage, ["lance", null, null])
		var st: Dictionary = g.player.stats
		var e := V3._vif(g, 60.0, 0.0, "brute")
		e.maxHp = 1e9
		e.hp = 1e9
		g.player.superCharge = 0.0
		var coup: float = g.tuning.combo[0].damage
		var inflige: float = D6Combat.damage_enemy(g, e, {"kind": "melee", "amount": coup, "canCrit": false})
		h.ok(g.player.superCharge > 0.0, "cas choisi : un coup d'arme remplit la jauge")
		h.proche(g.player.superCharge, inflige / (g.tuning["super"].chargeDamage * st.weaponDamage / g.tuning.weaponBase) * st.superChargeMult, 1e-9, "étage %d : dégâts infligés ÷ (chargeDamage × l'arme portée)" % int(etage))
		h.proche(g.player.superCharge, coup * st.damageMult * st.superChargeMult / g.tuning["super"].chargeDamage, 0.002, "étage %d : la part de jauge d'un coup ne dépend que du build, pas de la profondeur (%s)" % [int(etage), str(g.player.superCharge)])

# ---------------------------------------------------------------- soins de l'arbre

static func _soin(h) -> void:
	var parts: Array = []
	for etage in [1.0, PROFOND]:
		var g := _bac(h, "revenant", etage, ["lance", null, null])
		var p: Dictionary = g.player
		p.hp = 1.0
		D6Combat.heal_scaled(g, 6.0, false)
		h.proche(p.hp - 1.0, 6.0 * _echelle(g), 1e-9, "étage %d : 6 PV × l'échelle des PV du héros (×%s)" % [int(etage), str(snappedf(_echelle(g), 0.01))])
		parts.append((p.hp - 1.0) / p.maxHp)
	h.egal(_echelle(_bac(h, "revenant", 1.0, ["lance", null, null])), 1.0, "à l'étage 1 : le nombre des données, tel quel")
	h.ok(parts[1] >= 0.5 * parts[0] and parts[1] <= 2.0 * parts[0], "le même soin : %s %% des PV max à l'étage 325 contre %s %% à l'étage 1" % [str(snappedf(parts[1] * 100.0, 0.1)), str(snappedf(parts[0] * 100.0, 0.1))])

static func _soins_de_l_arbre(h) -> void:
	var rang: float = V3._cfg().choiceRank
	for etage in [1.0, PROFOND]:
		# Moisson : le marqué qui explose rend `healOnBlast` PV.
		var moisson: Dictionary = V3._pose("revenant", "sceau", "moisson")
		var g := _bac(h, "revenant", etage, ["sceau", null, null], {"sceau": rang}, {"sceau": "moisson"})
		var e := V3._cible(g, 150.0, 0.0)
		h.avancer(g, 1, {"skill1Pressed": true, "skill1AimX": 1.0})
		h.avancer(g, h.ticks(0.5))
		h.ok(e.get("stigmate") != null, "cas choisi : l'ennemi est marqué")
		g.player.hp = 1.0
		D6Combat.kill_enemy(g, e, {"kind": "melee"})
		h.proche(g.player.hp - 1.0, moisson.healOnBlast * _echelle(g), 1e-6, "étage %d, Moisson : `healOnBlast` × l'échelle de l'étage" % int(etage))
		# Soif (Tourbillon de colère) et Dîme de sang (Triple sentence) : `healPerHit` PV par ennemi touché.
		for cas in [["revenant", "colere", "soif"], ["bourreau", "sentence", "soif"]]:
			var pose: Dictionary = V3._pose(cas[0], cas[1], cas[2])
			var g2 := _bac(h, cas[0], etage, [cas[1], null, null], {cas[1]: rang}, {cas[1]: cas[2]})
			var cible := V3._cible(g2, 50.0, 0.0)
			g2.player.hp = 1.0
			var evs: Array = h.avancer(g2, 1, {"skill1Pressed": true})
			evs.append_array(h.avancer(g2, h.ticks(2.5)))
			var touches: int = V3._coups(evs, cible, "super").size()
			h.ok(touches >= 1, "cas choisi : %s touche (%d fois)" % [cas[1], touches])
			h.proche(g2.player.hp - 1.0, float(touches) * pose.healPerHit * _echelle(g2), 1e-6, "étage %d, %s / %s : `healPerHit` × l'échelle de l'étage, par ennemi touché" % [int(etage), cas[1], cas[2]])
