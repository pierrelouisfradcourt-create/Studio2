# trajectory_divergence.gd — divergence des QUATRE trajectoires (ligne
# harness.ghost_trajectory_divergence). La grandeur comparee est la SEQUENCE de
# positions sur l'horizon, paire a paire — pas les positions a un instant donne.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")

const GRAINE_MESURE: int = 5
# L'horizon commence APRES la sortie du dernier fantome (delais 0/30/60/90) : mesurer
# avant reviendrait a comparer des fantomes immobiles dans leur maison, ce qui
# constaterait des places de maison distinctes, pas des trajectoires distinctes.
const HORIZON_DEBUT: int = 120
const HORIZON_FIN: int = 260


# Sequences de positions exposees des quatre fantomes sur l'horizon declare.
static func sequences(carte) -> Array:
	var s = State.initial(carte, GRAINE_MESURE)
	var suites: Array = [[], [], [], []]
	for t in range(HORIZON_FIN):
		if s.statut != State.Statut.EN_COURS:
			break
		s = Loop.step(s, Bot.choisir_action(s))["etat"]
		if t < HORIZON_DEBUT:
			continue
		var releve: Dictionary = Observable.projeter(s)
		for g in range(4):
			suites[g].append(releve["fantomes"][g])
	return suites


# Nombre de paires de trajectoires IDENTIQUES sur l'horizon. Zero = les quatre
# sequences sont deux a deux differentes.
static func paires_identiques(suites: Array) -> int:
	var n: int = 0
	for i in range(suites.size()):
		for j in range(i + 1, suites.size()):
			if suites[i] == suites[j]:
				n += 1
	return n


static func mesurer(carte) -> Dictionary:
	var suites: Array = sequences(carte)
	return {
		"longueur": suites[0].size(),
		"paires_identiques": paires_identiques(suites),
	}
