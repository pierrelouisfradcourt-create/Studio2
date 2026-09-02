# core_game_state.test.gd — ligne CORE core.game_state.
# A tout instant le statut vaut EXACTEMENT une valeur parmi {EN COURS, GAGNE, PERDU}, et
# le nombre de chemins de sortie de la boucle sans statut terminal est EXACTEMENT 0 —
# y compris apres la derniere iteration.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")


# Enumere les trois SORTIES DE BOUCLE possibles et constate que chacune laisse un
# statut nomme. C'est un test, pas une relecture : chaque sortie est reellement atteinte.
func run(h) -> void:
	# Sortie 1 — la boucle rend la main sur VICTOIRE.
	var g = State.initial(Maze, 1)
	g.consommees = g.total_pose - 1
	h.eq(Status.appliquer(g), State.Statut.EN_COURS, "core.game_state: EN COURS a total - 1")
	g.consommees = g.total_pose
	h.eq(Status.appliquer(g), State.Statut.GAGNE, "core.game_state: sortie sur victoire nommee")
	h.eq(Status.est_terminal(g.statut), true, "core.game_state: la victoire est terminale")

	# Sortie 2 — la boucle rend la main sur DEFAITE.
	var p = State.initial(Maze, 1)
	p.vies = 1
	h.eq(Status.appliquer(p), State.Statut.EN_COURS, "core.game_state: EN COURS a 1 vie")
	p.vies = 0
	h.eq(Status.appliquer(p), State.Statut.PERDU, "core.game_state: sortie sur defaite nommee")
	h.eq(Status.est_terminal(p.statut), true, "core.game_state: la defaite est terminale")

	# Sortie 3 — la boucle rend la main sur EPUISEMENT DU BUDGET de ticks : le statut est
	# alors EN COURS, une valeur du vocabulaire — jamais une absence de statut.
	var partie: Dictionary = Bot.jouer_depuis_graine(Maze, 1, 60)
	h.eq(partie["ticks"], 60, "core.game_state: le budget a bien ete consomme")
	h.ok(partie["etat"].statut in State.STATUTS_VALIDES,
		"core.game_state: sortie sur budget -> statut du vocabulaire")

	# Aucun tick d'une partie complete ne laisse le statut hors du vocabulaire.
	var s = State.initial(Maze, 2)
	var sans_statut: int = 0
	for _t in range(200):
		s = Loop.step(s, Bot.choisir_action(s))["etat"]
		if not (s.statut in State.STATUTS_VALIDES):
			sans_statut += 1
		if Status.est_terminal(s.statut):
			break
	h.eq(sans_statut, 0, "core.game_state: 0 chemin sans statut terminal sur 200 ticks")

	# EXACTEMENT une valeur : le statut est un entier unique, pas une combinaison.
	var t = State.initial(Maze, 3)
	var compte: int = 0
	for v in State.STATUTS_VALIDES:
		if t.statut == v:
			compte += 1
	h.eq(compte, 1, "core.game_state: le statut vaut EXACTEMENT une valeur")
