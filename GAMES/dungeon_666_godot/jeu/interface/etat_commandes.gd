extends RefCounted
## État d'affichage d'une commande (dash, compétence, gadget, Super, attaque), LU dans la
## simulation. Portage de `abilityState` / `kitIcon` de src/render/hud.mjs. Aucune règle ici.
##   pret    : 0..1 (1 = utilisable)        charges, max : charges restantes / maximum (max 0 = sans charges)
##   partiel : 0..1, avancement de la charge en cours de recharge
##   eclat   : la commande brille (Super prêt)      icone : nom du pictogramme (icones.gd)

const Icones = preload("res://jeu/interface/icones.gd")
const BLOC_DU_KIT := {"attack": "weapon", "skill": "skill", "gadget": "gadget", "super": "super"}

static func etat(game: Dictionary, id: String) -> Dictionary:
	var e := _mesure(game, id)
	e["icone"] = _icone(game, id)
	return e

static func _mesure(game: Dictionary, id: String) -> Dictionary:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	match id:
		"dash":
			var maxi: float = D6Player.max_dash_charges(game)
			var besoin: float = t.dash.recharge * p.stats.dashRechargeMult
			var part: float = clampf(p.dashRecharge / besoin, 0.0, 1.0) if besoin > 0.0 else 1.0
			return {"pret": 1.0 if p.dashCharges > 0.0 else part, "charges": p.dashCharges, "max": maxi, "partiel": part if p.dashCharges < maxi else 0.0}
		"skill":
			var attente: float = t.skill.cooldown * p.stats.skillCooldownMult
			return {"pret": clampf(1.0 - p.skillCd / attente, 0.0, 1.0) if attente > 0.0 else 1.0}
		"gadget":
			var maxi: float = t.gadget.chargesPerSection + p.stats.gadgetChargesBonus
			return {"pret": 1.0 if p.gadgetCharges > 0.0 else 0.0, "charges": p.gadgetCharges, "max": maxi, "partiel": 0.0}
		"super":
			return {"pret": clampf(p.superCharge, 0.0, 1.0), "eclat": p.superCharge >= 1.0}
	return {"pret": 1.0}

## Pictogramme du kit équipé (champ `icon`) ; à défaut, celui du bouton.
static func _icone(game: Dictionary, id: String) -> String:
	var bloc = game.tuning.get(BLOC_DU_KIT.get(id, ""))
	var nom = bloc.get("icon") if bloc is Dictionary else null
	return nom if Icones.connue(nom) else id
