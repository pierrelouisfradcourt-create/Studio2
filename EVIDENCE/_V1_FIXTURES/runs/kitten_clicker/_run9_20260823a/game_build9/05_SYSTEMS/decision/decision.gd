# decision.gd — LOGIQUE PURE (category system, allowed_deps [economy, collection, upgrades,
# pricing]). Materialise le POINT DE DECISION significatif du premier achat : arbitrer entre
# ADOPTER un chaton (production passive) et AMELIORER la pelote (rendement au clic). N'ecrit
# AUCUN etat : il EVALUE (cout, effet, projection) pour que le controleur affiche les labels
# cout_<x>/effet_<x> et pour prouver que la meilleure option depend de la politique de jeu.
extends RefCounted

const Economy = preload("res://05_SYSTEMS/economy/economy.gd")
const Collection = preload("res://05_SYSTEMS/collection/collection.gd")
const Upgrades = preload("res://05_SYSTEMS/upgrades/upgrades.gd")
const Pricing = preload("res://05_SYSTEMS/pricing/pricing.gd")

const OPTION_KITTEN: String = "acheter_chaton"
const OPTION_UPGRADE: String = "acheter_amelioration"

# Cout courant d'une option (lit la courbe unique de pricing selon l'etat).
static func cost(state: Dictionary, option: String) -> int:
	if option == OPTION_KITTEN:
		return Pricing.kitten_cost(Collection.count(state))
	if option == OPTION_UPGRADE:
		return Pricing.upgrade_cost(Upgrades.level(state))
	return 0

# Taux passif ajoute par la PROCHAINE adoption (ronrons_per_sec du chaton a venir).
# Garde en DEUX temps, sur DEUX lignes distinctes : la borne d'index (`has_next`)
# puis le typage. Motif mutation (non cosmetique) : un `if a and b and c` unique
# poserait DEUX mutants de meme regle sur la MEME ligne -> cle (name,line) partagee
# -> check_mutation_gate les marque "ambigu" et INTRIABLES (un triage masquerait un
# vrai bug). Separees, chaque occurrence est atteignable seule : le mutant de borne
# reste TUE par le test du premier chaton (idx==0), le survivant restant est un
# equivalent isole et triable. Comportement strictement identique a la garde unique.
static func _next_kitten_rate(state: Dictionary, kittens_array: Array) -> float:
	var idx: int = Collection.count(state)
	var has_next: bool = idx >= 0 and idx < kittens_array.size()
	if not has_next:
		return 0.0
	if not (kittens_array[idx] is Dictionary):
		return 0.0
	return float(kittens_array[idx].get("ronrons_per_sec", 0))

# Valeur d'un clic APRES l'option (compose base x multiplicateur d'amelioration).
static func _click_value_after_upgrade(state: Dictionary) -> int:
	return Economy.base_click() * (Upgrades.click_multiplier(state) * 2)

# Texte d'effet d'une option (affiche a cote de son affordance, jamais vide).
static func effect_text(state: Dictionary, kittens_array: Array, option: String) -> String:
	if option == OPTION_KITTEN:
		return "+%d ronron/s (production passive)" % int(_next_kitten_rate(state, kittens_array))
	if option == OPTION_UPGRADE:
		return "clic x2 -> %d par caresse (rendement)" % _click_value_after_upgrade(state)
	return ""

# Projection de ronrons gagnes sur `frames` trames selon une politique de `clicks` clics,
# APRES avoir pris l'option. Rend visible que ADOPTER domine si le joueur laisse tourner et
# qu'AMELIORER domine s'il clique — la sonde le MESURE sur la vraie scene, ici on l'expose.
static func projected_gain(state: Dictionary, kittens_array: Array, option: String,
		clicks: int, frames: int) -> float:
	var rate: float = Collection.passive_rate(state, kittens_array)
	var click_value: int = Economy.base_click() * Upgrades.click_multiplier(state)
	if option == OPTION_KITTEN:
		rate += _next_kitten_rate(state, kittens_array)
	elif option == OPTION_UPGRADE:
		click_value = _click_value_after_upgrade(state)
	var passive: float = rate * Economy.PASSIVE_UNIT * float(frames)
	return passive + float(click_value) * float(clicks) - float(cost(state, option))
