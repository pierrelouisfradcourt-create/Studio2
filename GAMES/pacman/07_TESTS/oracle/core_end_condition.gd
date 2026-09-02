# core_end_condition.gd — ligne CORE core.end_condition.
# Un bot pilotant l'entree publique ATTEINT une fin de partie : l'etat final vaut
# EXACTEMENT GAGNE ou EXACTEMENT PERDU, jamais indefini ; le nombre de sorties de boucle
# sans issue nommee est EXACTEMENT 0. La victoire est asseree par EGALITE STRICTE
# (consommes == total pose) et l'etat reste EN COURS a total - 1.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const Targeting = preload("res://05_SYSTEMS/ghost_targeting/ghost_targeting.gd")
const Planner = preload("res://06_RUNTIME/adapters/solvability_bot/route_planner.gd")

const BUDGET_VICTOIRE: int = 4000
const BUDGET_DEFAITE: int = 1500


# Pilote SUICIDAIRE : il pilote le meme canal d'entree public, mais vise le fantome
# hostile le plus proche au lieu de le fuir. C'est ainsi que la DEFAITE est atteinte
# reellement, par le jeu, et non en forcant le compteur de vies a zero.
func _pas_vers_le_fantome(s) -> Vector2i:
	var menace: PackedInt32Array = Planner.distances_depuis(Maze, Planner.poursuivants(s))
	var meilleure: Vector2i = Maze.AUCUNE
	var meilleure_d: int = Planner.nb_cases(Maze)
	for dir in Maze.DIRECTIONS:
		var v: Vector2i = Maze.case_suivante(s.pac, dir)
		if not Maze.praticable(v):
			continue
		var d: int = menace[Maze.index_de(v)]
		if d == Planner.INACCESSIBLE:
			continue
		if d < meilleure_d:
			meilleure_d = d
			meilleure = dir
	return meilleure


func run(h) -> void:
	# ISSUE 1 — VICTOIRE atteinte par un bot pilotant l'entree publique.
	var victoire: Dictionary = Bot.jouer_depuis_graine(Maze, 1, BUDGET_VICTOIRE)
	var gagne = victoire["etat"]
	h.eq(gagne.statut, State.Statut.GAGNE, "core.end: l'etat final vaut EXACTEMENT GAGNE")
	h.eq(Observable.projeter(gagne)["statut_nom"], "GAGNE", "core.end: l'issue est NOMMEE")
	h.eq(gagne.consommees, gagne.total_pose, "core.end: victoire par EGALITE STRICTE")
	h.eq(gagne.total_pose - gagne.consommees, 0, "core.end: restantes egal 0")
	h.lt(victoire["ticks"], BUDGET_VICTOIRE, "core.end: la victoire tient dans le budget")

	# A total - 1, l'etat reste STRICTEMENT EN COURS : c'est ce qui tue un mutant >=.
	var presque = gagne.clone()
	presque.consommees = presque.total_pose - 1
	h.eq(Status.appliquer(presque), State.Statut.EN_COURS, "core.end: EN COURS a total - 1")
	presque.consommees = presque.total_pose
	h.eq(Status.appliquer(presque), State.Statut.GAGNE, "core.end: GAGNE a total")

	# ISSUE 2 — DEFAITE atteinte REELLEMENT, par un pilote qui joue le canal public.
	var s = State.initial(Maze, 1)
	var ticks: int = 0
	while ticks < BUDGET_DEFAITE and s.statut == State.Statut.EN_COURS:
		s = Loop.step(s, _pas_vers_le_fantome(s))["etat"]
		ticks += 1
	h.eq(s.statut, State.Statut.PERDU, "core.end: l'etat final vaut EXACTEMENT PERDU")
	h.eq(Observable.projeter(s)["statut_nom"], "PERDU", "core.end: l'issue de defaite est NOMMEE")
	h.eq(s.vies, 0, "core.end: la defaite survient a zero vie")
	h.lt(ticks, BUDGET_DEFAITE, "core.end: la defaite est atteinte dans le budget")
	h.gt(ticks, 0, "core.end: la partie a reellement ete jouee")

	# ZERO SORTIE DE BOUCLE SANS ISSUE NOMMEE : les deux parties menees a terme portent
	# un statut terminal, et une partie arretee par budget porte EN COURS — jamais rien.
	var sans_issue: int = 0
	for final in [gagne, s]:
		if not Status.est_terminal(final.statut):
			sans_issue += 1
		if not (final.statut in State.STATUTS_VALIDES):
			sans_issue += 1
	h.eq(sans_issue, 0, "core.end: 0 sortie de boucle sans issue nommee")

	var budget_court: Dictionary = Bot.jouer_depuis_graine(Maze, 1, 25)
	h.ok(budget_court["etat"].statut in State.STATUTS_VALIDES,
		"core.end: une sortie par budget porte un statut du vocabulaire")
	h.eq(budget_court["etat"].statut, State.Statut.EN_COURS, "core.end: et ce statut est EN COURS")

	# Les deux issues terminales sont DIFFERENTES : elles ne se confondent pas.
	h.ok(gagne.statut != s.statut, "core.end: victoire et defaite sont deux issues distinctes")
