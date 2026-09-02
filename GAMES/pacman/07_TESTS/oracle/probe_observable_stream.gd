# probe_observable_stream.gd — ligne probe.observable_stream, capacite F50.
# A chaque tick d'une partie complete, l'etat expose de chacun des quatre fantomes est
# LISIBLE par un lecteur EXTERIEUR au runtime : sans ce point de sortie, l'assertion
# n'a pas d'observateur.
extends RefCounted

const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())

const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


func run(h) -> void:
	var s = State.initial(Maze, 1)
	var releve: Dictionary = Observable.projeter(s)
	var ligne: String = Probe.ligne(releve)

	# Le canal est DECLARE et distinct : une ligne prefixee, lisible sans acces a l'etat.
	h.ok(ligne.begins_with(Probe.PREFIXE), "probe.stream: la ligne porte le prefixe du canal declare")
	h.ok(ligne.length() > Probe.PREFIXE.length(), "probe.stream: la ligne porte une charge utile")

	# UN LECTEUR EXTERIEUR relit la ligne sans toucher a l'etat interne.
	var relu: Dictionary = Probe.relire(ligne)
	h.eq(relu.is_empty(), false, "probe.stream: la ligne est relisible de l'exterieur")
	h.eq(int(relu["tick"]), releve["tick"], "probe.stream: le tick traverse le canal")
	h.eq(int(relu["score"]), releve["score"], "probe.stream: le score traverse le canal")
	h.eq(int(relu["vies"]), releve["vies"], "probe.stream: les vies traversent le canal")
	h.eq(relu["statut_nom"], releve["statut_nom"], "probe.stream: le statut traverse le canal")
	h.eq(relu["etats_fantomes"].size(), 4, "probe.stream: les quatre etats de fantomes traversent le canal")

	# Une ligne qui n'est pas du canal est REFUSEE : le lecteur ne lit pas n'importe quoi.
	h.eq(Probe.relire("autre chose").is_empty(), true, "probe.stream: une ligne etrangere est refusee")
	h.eq(Probe.relire(Probe.PREFIXE + "pas du json").is_empty(), true,
		"probe.stream: une charge illisible est refusee")

	# A CHAQUE TICK d'une partie : l'etat des quatre fantomes est lisible de l'exterieur.
	var jeu = State.initial(Maze, 1)
	var etats: Array = [jeu]
	for _t in range(200):
		if jeu.statut != State.Statut.EN_COURS:
			break
		jeu = Loop.step(jeu, Bot.choisir_action(jeu))["etat"]
		etats.append(jeu)
	var trace: Array = Probe.trace(etats)
	h.eq(trace.size(), etats.size(), "probe.stream: un releve par tick, sans trou")

	var noms_valides: Array = ["DISPERSION", "POURSUITE", "EFFRAYE"]
	var illisibles: int = 0
	for r in trace:
		var relu_r: Dictionary = Probe.relire(Probe.ligne(r))
		if relu_r.is_empty():
			illisibles += 1
			continue
		if relu_r["etats_fantomes"].size() != 4:
			illisibles += 1
			continue
		for e in relu_r["etats_fantomes"]:
			if not noms_valides.has(e):
				illisibles += 1
	h.eq(illisibles, 0, "probe.stream: 0 releve illisible sur toute la partie")
	h.gt(trace.size(), 100, "probe.stream: la partie mesuree est reellement longue")

	# La sonde NE CALCULE RIEN : elle recopie la projection pure.
	h.eq(Observable.egaux(trace[0], Observable.projeter(etats[0])), true,
		"probe.stream: la sonde recopie la projection, sans rien recalculer")
