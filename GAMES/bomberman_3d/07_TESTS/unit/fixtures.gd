# fixtures.gd — arenes minuscules et deterministes pour les tests.
#
# N'est PAS un test : le harnais n'enumere que `test_*.gd`, ce fichier n'est donc jamais
# execute seul. Il existe pour que les tests decrivent un SCENARIO et non une carte.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")


# Descripteur minimal valide : 5x4, deux spawns non adjacents, aucun destructible.
static func desc_simple() -> Dictionary:
	return {
		"id": "t_simple", "nom": "simple",
		"plan": [
			"#####",
			"#S.S#",
			"#...#",
			"#####",
		],
		"powerup_rules": {}, "victory_rule": P.VICTOIRE_LAST_STANDING,
	}


# Descripteur avec destructibles : 7x5.
static func desc_blocs() -> Dictionary:
	return {
		"id": "t_blocs", "nom": "blocs",
		"plan": [
			"#######",
			"#S.+.S#",
			"#.+.+.#",
			"#.....#",
			"#######",
		],
		"powerup_rules": {P.PU_FIRE_UP: 1}, "powerup_densite": 100,
		"victory_rule": P.VICTOIRE_LAST_STANDING,
	}


# Descripteur large et vide : 9x9, pour les chaines d'explosion.
static func desc_vide() -> Dictionary:
	var plan: Array = []
	for y in range(9):
		var ligne := ""
		for x in range(9):
			if x == 0 or y == 0 or x == 8 or y == 8:
				ligne += "#"
			elif (x == 1 and y == 1) or (x == 7 and y == 7):
				ligne += "S"
			else:
				ligne += "."
		plan.append(ligne)
	return {
		"id": "t_vide", "nom": "vide", "plan": plan,
		"powerup_rules": {}, "victory_rule": P.VICTOIRE_LAST_STANDING,
	}


# Etat neuf a partir d'un descripteur. Passe par le point de passage oblige (carte_validee) :
# un test qui contournerait le verdict testerait autre chose que le jeu.
static func etat(desc: Dictionary, graine: int, nb_acteurs: int) -> Object:
	return State.initial(Validator.carte_validee(desc), desc, graine, nb_acteurs)
