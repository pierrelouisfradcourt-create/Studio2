# growth.gd — ligne core.growth_score. Resolution de la consommation de nourriture AU
# SEIN du tick : croissance (deja actee par le loop qui ne retire pas la queue), score,
# franchissement de palier, spawn suivant, emission des evenements. RefCounted, pur.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const TickRate = preload("res://05_SYSTEMS/tick_rate/tick_rate.gd")
const FoodSpawn = preload("res://05_SYSTEMS/food_spawn/food_spawn.gd")
const Events = preload("res://05_SYSTEMS/game_loop/events.gd")

# Mute l'etat DEJA clone (tete deja avancee sur l'ancienne nourriture, queue conservee).
# Incremente score ET fruits au MEME tick, recalcule periode/palier, tire la nourriture
# suivante. Renvoie la liste d'evenements (nourriture_mangee, +palier_franchi si palier).
static func manger(state) -> Array:
	var events: Array = []
	state.score += P.POINTS_PAR_NOURRITURE
	state.fruits += 1
	var ancien_palier: int = state.palier
	state.palier = TickRate.palier(state.fruits)
	state.periode = TickRate.periode(state.fruits)
	events.append(Events.nourriture_mangee(state.segments[0], state.score))
	if state.palier > ancien_palier:
		events.append(Events.palier_franchi(state.palier, state.periode))
	var tirage: Dictionary = FoodSpawn.tirer(state)
	if not tirage["grille_pleine"]:
		state.nourriture = tirage["cellule"]
		state.rng_state = tirage["rng_state"]
	return events
