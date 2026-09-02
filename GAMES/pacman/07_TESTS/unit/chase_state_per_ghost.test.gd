# chase_state_per_ghost.test.gd — ligne chase.state_per_ghost, capacite F26.
# A chaque tick, l'etat expose de CHACUN des quatre fantomes appartient a l'ensemble des
# trois valeurs — sans valeur vide, sans combinaison de drapeaux.
extends RefCounted

const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")


func run(h) -> void:
	h.eq(Chase.MODES_VALIDES.size(), 3, "chase.per_ghost: vocabulaire ferme de trois valeurs")

	# Etat d'UN fantome : exactement une valeur, jamais une combinaison.
	h.eq(Chase.etat_fantome(0, false), Chase.Mode.POURSUITE, "chase.per_ghost: poursuite si non effraye")
	h.eq(Chase.etat_fantome(0, true), Chase.Mode.EFFRAYE, "chase.per_ghost: effraye prime sur le mode global")
	h.eq(Chase.etat_fantome(140, false), Chase.Mode.DISPERSION, "chase.per_ghost: dispersion au segment 2")
	h.eq(Chase.etat_fantome(140, true), Chase.Mode.EFFRAYE, "chase.per_ghost: effraye prime en dispersion")

	# Sur une partie reelle : les QUATRE fantomes portent toujours une valeur valide.
	var s = State.initial(Maze, 4)
	h.eq(s.etats_fantomes.size(), 4, "chase.per_ghost: exactement quatre etats exposes")
	var hors_vocabulaire: int = 0
	var ticks: int = 0
	for _t in range(300):
		if s.statut != State.Statut.EN_COURS:
			break
		s = Loop.step(s, Maze.AUCUNE)["etat"]
		ticks += 1
		for e in s.etats_fantomes:
			if not (e in Chase.MODES_VALIDES):
				hors_vocabulaire += 1
	h.gt(ticks, 0, "chase.per_ghost: la partie a reellement avance")
	h.eq(hors_vocabulaire, 0, "chase.per_ghost: aucun etat hors vocabulaire sur la partie")

	# L'etat expose porte quatre noms lisibles, un par fantome.
	var releve: Dictionary = Observable.projeter(s)
	h.eq(releve["etats_fantomes"].size(), 4, "chase.per_ghost: quatre etats dans le releve")
	var noms_valides: Array = ["DISPERSION", "POURSUITE", "EFFRAYE"]
	var noms_hors: int = 0
	for n in releve["etats_fantomes"]:
		if not noms_valides.has(n):
			noms_hors += 1
	h.eq(noms_hors, 0, "chase.per_ghost: noms exposes dans le vocabulaire ferme")

	# Armement et expiration : les quatre passent en Effraye, puis aucun n'y reste.
	var f = State.initial(Maze, 4)
	Chase.armer_effraye(f)
	var non_effrayes: int = 0
	for e in f.etats_fantomes:
		if e != Chase.Mode.EFFRAYE:
			non_effrayes += 1
	h.eq(non_effrayes, 0, "chase.per_ghost: les quatre sont Effrayes a l'armement")
	Chase.expirer(f)
	Chase.rafraichir_etats(f)
	var restes_effrayes: int = 0
	for e in f.etats_fantomes:
		if e == Chase.Mode.EFFRAYE:
			restes_effrayes += 1
	h.eq(restes_effrayes, 0, "chase.per_ghost: aucun ne reste Effraye a l'expiration")
