extends RefCounted
## État d'affichage d'une commande (attaque, dash, et les trois emplacements skill1..skill3), LU
## dans la simulation. Aucune règle ici : un emplacement se lit par D6Loadout.slot_view, le bouton
## « dash » (le DÉPLACEMENT DE CLASSE : dash, saut ou roulade) par D6Player.move_view.
##   pret    : 0..1 (1 = utilisable)        charges, max : charges restantes / maximum (max 0 = sans charges)
##   partiel : 0..1, avancement de la charge en cours de recharge
##   recharge : vrai pour une compétence (anneau de recharge)      vide : emplacement sans action
##   jauge, maintien (attaque) : la jauge d'ultime 0..1 et l'avancement 0..1 du maintien qui le lance
##   eclat   : la commande brille (ultime prêt)      icone : nom du pictogramme (icones.gd)
##   nom, geste (déplacement) : son nom (« Saut ») et sa sorte (dash | saut | roulade)
##   visee   : l'action de l'emplacement se VISE (slot_view.aimed) : glisser le pouce montre une ligne

const Icones = preload("res://jeu/interface/icones.gd")
const EMPLACEMENTS := {"skill1": 0, "skill2": 1, "skill3": 2}

static func etat(game: Dictionary, id: String) -> Dictionary:
	var e := _mesure(game, id)
	e["icone"] = _icone(game, id)
	return e

static func _mesure(game: Dictionary, id: String) -> Dictionary:
	var p: Dictionary = game.player
	var t: Dictionary = game.tuning
	match id:
		"dash":
			var geste: Dictionary = D6Player.move_view(game)
			var part: float = geste.rechargeFrac if geste.charges < geste.maxCharges else 0.0
			return {"pret": 1.0 if geste.ready else part, "charges": geste.charges, "max": geste.maxCharges, "partiel": part, "nom": geste.name, "geste": geste.kind}
		"attack":
			var tenir: float = t["super"].holdTime
			return {"pret": 1.0, "jauge": clampf(p.superCharge, 0.0, 1.0), "eclat": p.superCharge >= 1.0, "maintien": clampf(p.superHold / tenir, 0.0, 1.0) if tenir > 0.0 else 0.0}
	if EMPLACEMENTS.has(id):
		return _emplacement(game, EMPLACEMENTS[id])
	return {"pret": 1.0}

## Un emplacement d'action, d'après ce que la simulation en dit (slot_view) ; vide : rien à lancer.
static func _emplacement(game: Dictionary, index: int) -> Dictionary:
	var vue = D6Loadout.slot_view(game, index)
	if vue == null:
		return {"pret": 0.0, "vide": true}
	if vue.charges != null:
		return {"pret": 1.0 if vue.ready else 0.0, "charges": vue.charges, "max": vue.maxCharges, "partiel": 0.0, "visee": vue.aimed}
	return {"pret": 1.0 - vue.cooldownFrac, "recharge": true, "visee": vue.aimed}

## Pictogramme : celui de l'arme portée (attaque), de l'action équipée (emplacement) ; à défaut,
## celui du bouton. Un emplacement vide n'en a pas ("").
static func _icone(game: Dictionary, id: String) -> String:
	var nom = null
	if EMPLACEMENTS.has(id):
		var vue = D6Loadout.slot_view(game, EMPLACEMENTS[id])
		if vue == null:
			return ""
		nom = vue.icon
	elif id == "dash":
		nom = D6Player.move_view(game).icon
	elif id == "attack":
		var arme = game.tuning.get("weapon")
		nom = arme.get("icon") if arme is Dictionary else null
	return nom if Icones.connue(nom) else id
