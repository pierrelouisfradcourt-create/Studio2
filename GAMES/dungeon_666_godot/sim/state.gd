class_name D6State
extends RefCounted
## Portage de src/sim/state.mjs.
## Briques d'état partagées par tous les modules de simulation : identifiants, événements,
## création du héros, statistiques dérivées par défaut. Aucune dépendance vers les autres
## modules de sim.

static func new_id(game: Dictionary):
	var id = game.nextId
	game.nextId = id + 1
	return id

## Événement de simulation, consommé par le rendu, l'audio et la télémétrie.
## La sim ne sait pas qui l'écoute ; `main` vide la liste après chaque image.
static func emit(game: Dictionary, type: String, data = null) -> Dictionary:
	var ev := {"type": type, "tick": game.tick}
	if data is Dictionary:
		ev.merge(data, true)
	game.events.append(ev)
	return ev

## Statistiques dérivées : bases + équipement + bénédictions (recalculées par stats.mjs).
static func base_stats() -> Dictionary:
	return {
		"damageMult": 1.0,
		"attackSpeedMult": 1.0,
		"critChance": 0.0,
		"critMult": 0.0,
		"maxHpBonus": 0.0,
		"armor": 0.0, # fraction de dégâts réduite, plafonnée
		"moveSpeedMult": 1.0,
		"dashChargesBonus": 0.0,
		"dashRechargeMult": 1.0,
		"skillDamageMult": 1.0,
		"skillCooldownMult": 1.0,
		"superChargeMult": 1.0,
		"gadgetChargesBonus": 0.0,
		"healOnKill": 0.0,
		"lifesteal": 0.0,
		"goldFindMult": 1.0,
		"knockbackMult": 1.0,
		"weaponDamage": 0.0, # dégâts de base de l'arme portée (W)
		"armorHp": 0.0, # PV apportés par l'armure portée
		"dashDistanceMult": 1.0, # classe : longueur du dash
		"deathGoldKeepBonus": 0.0, # Sanctuaire : part de la bourse épargnée par Charon à la mort
	}

static func create_player(tuning: Dictionary, x, y) -> Dictionary:
	var p: Dictionary = tuning.player
	return {
		"x": x,
		"y": y,
		"vx": 0.0,
		"vy": 0.0,
		"r": p.radius,
		"hp": p.maxHp,
		"maxHp": p.maxHp,
		"facing": -PI / 2.0,
		"aimX": 0.0,
		"aimY": -1.0,
		"moveX": 0.0,
		"moveY": 0.0,
		"manualAimX": 0.0,
		"manualAimY": 0.0,
		"attackHeld": false,
		"state": "free", # free | attack | dash | cast | super | dead
		"stateTime": 0.0,
		"attack": null,
		"comboIndex": 0.0,
		"comboTimer": 99.0,
		"swingSeq": 0.0,
		"dashCharges": tuning.dash.charges,
		"dashRecharge": 0.0,
		"dashDirX": 0.0,
		"dashDirY": -1.0,
		"dashT": 0.0,
		"strikeWindow": 0.0,
		"iframes": 0.0,
		"freeze": 0.0, # gel d'impact LOCAL restant (D8, mode local) ; le mode global gèle toute la scène
		"dodgeIframes": 0.0, # part des i-frames qui vient d'un dash (sert l'événement « esquive »)
		"hurtFlash": 0.0,
		# Les trois emplacements d'action (kit.slots) : recharge restante d'une compétence, charges
		# d'un gadget. Remplis par D6Loadout.reset_slots (le héros naît avant de connaître son kit).
		"slots": [{"cd": 0.0, "charges": 0.0}, {"cd": 0.0, "charges": 0.0}, {"cd": 0.0, "charges": 0.0}],
		"castSlot": 0.0, # emplacement de la compétence en cours de lancer (état 'cast')
		"castT": 0.0,
		"castDirX": 0.0,
		"castDirY": -1.0,
		"superCharge": D6Js.nz(tuning["super"].get("startCharge"), 0.0),
		"superHold": 0.0, # s d'attaque maintenue, jauge pleine : à super.holdTime l'ultime part
		"superT": 0.0,
		"superTick": 0.0,
		"surge": 0.0, # élan passager (proc « surge ») : secondes restantes…
		"surgeMult": 0.0, # … et dégâts en plus tant qu'il dure
		"buffer": {"action": null, "t": 0.0, "aimX": 0.0, "aimY": 0.0, "slot": 0.0},
		"dodgedIds": [], # attaques déjà esquivées pendant le dash en cours
		"lastTargetId": 0.0, # cible « collante » de la visée assistée
		"lastTargetAt": -99.0,
		"stats": base_stats(),
		"procs": [], # effets déclenchés des bénédictions (données interprétées par combat.mjs)
	}

## Statistiques de télémétrie : lues par les bots, les tests et le rapport de playtest.
static func create_telemetry() -> Dictionary:
	return {
		"damageDealt": 0.0,
		"damageTaken": 0.0,
		"hitsTaken": 0.0,
		"dodges": 0.0,
		"dashes": 0.0,
		"attacks": 0.0,
		"hitsLanded": 0.0,
		"kills": 0.0,
		"deaths": 0.0,
		"roomsCleared": 0.0,
		"skillCasts": 0.0,
		"gadgetUses": 0.0,
		"superUses": 0.0,
		"deflects": 0.0,
		"wallSlams": 0.0,
		"roomTimes": [],
		"killTimes": [], # durée de vie (s) des ennemis tués, par type
		"deathCauses": {},
		"soulsEarned": 0.0, # Âmes gagnées pendant ce run (permanentes)
	}
