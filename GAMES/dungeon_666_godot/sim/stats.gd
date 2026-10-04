class_name D6Stats
extends RefCounted
## Portage de src/sim/stats.mjs.
## Statistiques dérivées du héros : base + équipement + bénédictions. Recalculées à chaque
## changement de build (jamais à chaque image). Produit aussi la liste des procs.

static func _add_stat(st: Dictionary, stat: String, v: float) -> void:
	if stat.ends_with("Mult"):
		# multiplicateurs additifs entre eux (1 + somme) ; clé absente : undefined + v = NaN
		st[stat] = (st[stat] if st.get(stat) != null else NAN) + v
	else:
		st[stat] = D6Js.nz(st.get(stat), 0.0) + v

static func recompute_stats(game: Dictionary) -> void:
	var st := D6State.base_stats()
	st.superDamageMult = 1.0
	st.superDurationBonus = 0.0
	st.extraGoldOnKill = 0.0
	var procs: Array = []

	# Kit équipé (classe, arme portée, emplacements, Super) : l'arme peut avoir changé.
	D6Loadout.resolve_kit(game)
	_add_permanent(game, st)
	_add_items(game, st, procs)
	_add_boons(game, st, procs)

	# Bornes de sécurité : aucune combinaison ne peut casser la boucle de jeu.
	var caps: Dictionary = game.tuning.combat
	st.dashRechargeMult = maxf(caps.minDashRechargeMult, st.dashRechargeMult)
	st.skillCooldownMult = maxf(caps.minSkillCooldownMult, st.skillCooldownMult)
	st.critChance = minf(caps.maxCritChance, st.critChance)
	st.lifesteal = minf(caps.maxLifesteal, st.lifesteal)
	_apply_to_player(game, st, procs)

## PERMANENT : bonus de la classe et améliorations du Sanctuaire (profil).
static func _add_permanent(game: Dictionary, st: Dictionary) -> void:
	var t: Dictionary = game.tuning
	var class_stats = D6Loadout.class_of(game).get("stats")
	if class_stats is Dictionary:
		for k in class_stats:
			_add_stat(st, k, class_stats[k])
	var upgrades = game.meta.get("upgrades")
	if not (upgrades is Dictionary):
		return
	var town = t.get("town")
	var known = town.get("upgrades") if town is Dictionary else null
	for id in upgrades:
		var lv = upgrades[id]
		var up = known.get(id) if known is Dictionary else null
		if up != null and lv > 0.0:
			_add_stat(st, up.stat, up.perLevel * lv)

## Équipement porté : base de l'arme et de l'armure, affixes, pouvoir légendaire.
static func _add_items(game: Dictionary, st: Dictionary, procs: Array) -> void:
	var t: Dictionary = game.tuning
	var items: Dictionary = game.run.items
	var arme = items.get("arme")
	st.weaponDamage = D6Js.nz(_base_field(arme, "damage"), t.weaponBase)
	var armure = items.get("armure")
	st.armorHp = D6Js.nz(_base_field(armure, "hp"), t.armorBase) if armure != null else 0.0
	for slot in items:
		var item = items[slot]
		if item == null:
			continue
		for a in item.affixes:
			_add_stat(st, a.stat, a.value)
		if D6Js.truthy(item.get("power")):
			var pw = _legendary_power(item.power)
			if pw == null:
				continue
			var pw_stats = pw.get("stats")
			if pw_stats is Dictionary:
				for k in pw_stats:
					_add_stat(st, k, pw_stats[k])
			var pw_procs = pw.get("procs")
			if pw_procs is Array:
				for pr in pw_procs:
					var copy := {"chance": 1.0}
					copy.merge(pr, true)
					procs.append(copy)

## item?.base?.<key> : null si l'objet, sa base ou la clé manque.
static func _base_field(item, key: String):
	if not (item is Dictionary):
		return null
	var base = item.get("base")
	return base.get(key) if base is Dictionary else null

static func _legendary_power(id):
	for x in D6Data.tables().loot.LEGENDARY_POWERS:
		if x.id == id:
			return x
	return null

## TEMPORAIRE : bénédictions du run (stats et procs).
static func _add_boons(game: Dictionary, st: Dictionary, procs: Array) -> void:
	for b in game.run.boons:
		var def = D6Boons.boon_def(b.id)
		if def == null:
			continue
		# Une bénédiction `noScale` vaut sa valeur entière quel que soit son niveau (jamais 1,5 charge de dash) ;
		# les autres gagnent boons.levelStep de leur valeur par niveau supplémentaire.
		var lv: float = 1.0 if D6Js.truthy(def.get("noScale")) else 1.0 + game.tuning.boons.levelStep * (b.level - 1.0)
		var raw: float = D6Boons.boon_value(def, b.rarity) * lv
		var pct: bool = D6Js.truthy(def.get("pct"))
		var v: float = raw / 100.0 if pct else raw
		if D6Js.truthy(def.get("stat")):
			_add_stat(st, def.stat, -v if D6Js.truthy(def.get("negative")) else v)
		# Contreparties fixes d'un pacte (valeurs brutes, jamais mises à l'échelle).
		var extra = def.get("stats")
		if extra is Dictionary:
			for k in extra:
				_add_stat(st, k, extra[k])
		if D6Js.truthy(def.get("superDurationBonus")):
			st.superDurationBonus += def.superDurationBonus
		if D6Js.truthy(def.get("extraGoldOnKill")):
			st.extraGoldOnKill += def.extraGoldOnKill
		if def.get("proc") is Dictionary:
			var pr := {"chance": 1.0}
			pr.merge(def.proc, true)
			pr.boon = def.id
			if def.proc.has("valueFixed"):
				# La valeur de la bénédiction est une CHANCE ; l'effet, lui, a un montant fixe.
				pr.chance = minf(1.0, v)
				pr.value = def.proc.get("valueFixed")
			else:
				pr.value = v if pct else raw # pourcentage → fraction ; sinon la valeur telle quelle
			procs.append(pr)

## Pose les stats sur le héros et ramène ses PV et ses charges dans leurs nouvelles bornes.
static func _apply_to_player(game: Dictionary, st: Dictionary, procs: Array) -> void:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	var old_max: float = p.maxHp
	p.stats = st
	p.procs = procs
	p.maxHp = D6Js.jround(t.player.innateHp + st.armorHp + st.maxHpBonus)
	if p.maxHp > old_max:
		p.hp += p.maxHp - old_max
	p.hp = minf(p.hp, p.maxHp)
	var max_dash: float = t.dash.charges + st.dashChargesBonus
	p.dashCharges = minf(p.dashCharges, max_dash)
	D6Loadout.clamp_gadgets(game)
