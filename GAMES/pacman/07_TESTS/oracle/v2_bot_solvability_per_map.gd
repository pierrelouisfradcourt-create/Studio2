# v2_bot_solvability_per_map.gd — ligne bot.solvability_per_map, capacite F103.
# Le bot planifie l'itineraire de CHAQUE carte du catalogue et emet des INTENTIONS sur
# le meme canal que le joueur. Une deuxieme carte non prouvee solvable serait un jeu
# injouable certifie.
extends RefCounted

const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/solvability_bot.gd")
const Driver = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const Planner = preload("res://06_RUNTIME/adapters/solvability_bot/route_planner.gd")
const Shell = preload("res://06_RUNTIME/adapters/app_shell/app_shell.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
var Alt = MazeClass.depuis_descripteur(ContentV2.descripteur(1))


func run(h) -> void:
	# LA GRAINE SELECTIONNE LA CARTE : les essais couvrent REELLEMENT chaque carte.
	var n: int = ContentV2.nb_niveaux()
	h.eq(Bot.index_de_la_graine(1, n), 0, "bot.per_map: la graine 1 exerce la premiere carte")
	h.eq(Bot.index_de_la_graine(2, n), 1, "bot.per_map: la graine 2 exerce la seconde")
	h.eq(Bot.index_de_la_graine(n + 1, n), 0, "bot.per_map: l alternance boucle sur le catalogue")
	h.eq(Bot.index_de_la_graine(0, n), n - 1, "bot.per_map: une graine 0 reste dans les bornes")
	h.eq(Bot.cartes_non_exercees(50, n), 0, "bot.per_map: 0 carte non exercee sur 50 essais")
	var repartition: Array = Bot.repartition(50, n)
	h.eq(repartition.size(), n, "bot.per_map: une repartition par carte")
	# REPARTITION EQUILIBREE, quel que soit le nombre de cartes du catalogue : aucune
	# carte laissee de cote, et un ecart d au plus un essai entre la plus et la moins
	# exercee. La propriete vaut pour deux cartes comme pour trois.
	var minimum: int = 50
	var maximum: int = 0
	var somme: int = 0
	for c in repartition:
		minimum = min(minimum, int(c))
		maximum = max(maximum, int(c))
		somme += int(c)
	h.eq(somme, 50, "bot.per_map: les 50 essais sont tous attribues")
	h.ok(maximum - minimum <= 1, "bot.per_map: repartition equilibree entre les cartes")
	h.gt(minimum, 0, "bot.per_map: aucune carte laissee de cote")

	# LE BOT GAGNE sur CHAQUE carte du catalogue.
	for i in range(n):
		var carte = Shell.carte(i)
		var r: Dictionary = Bot.jouer_carte(carte, i + 1, Bot.BUDGET_DEFAUT, Shell.cadence(i))
		h.eq(r["succeeded"], true, "bot.per_map: la carte %s est prouvee solvable" % carte.ID)
		h.eq(r["consommees"], r["total_pose"], "bot.per_map: tous les collectibles sont ramasses")
		h.eq(r["statut"], State.Statut.GAGNE, "bot.per_map: le statut final est GAGNE")
		h.gt(int(r["ticks"]), 0, "bot.per_map: la partie a reellement dure")

	# UNE CARTE ABSENTE rend un verdict d'echec NOMME, jamais une exception.
	var rien: Dictionary = Bot.jouer_carte(null, 1)
	h.eq(rien["succeeded"], false, "bot.per_map: aucune carte, aucun succes")
	h.eq(rien["carte"], "", "bot.per_map: le verdict le dit")

	# LE BOT EMET DES INTENTIONS sur le canal public : il ne force aucun champ.
	var jeu = State.initial(Alt, 2)
	var action: Vector2i = Driver.choisir_action(jeu)
	h.eq(MazeClass.DIRECTIONS.has(action) or action == MazeClass.AUCUNE, true,
		"bot.per_map: l'action appartient au vocabulaire ferme")
	h.eq(Planner.prochain_pas(jeu), Planner.prochain_pas(jeu), "bot.per_map: le pas est deterministe")

	# LES TABLES du planificateur suivent la CARTE, pas une topologie figee.
	h.eq(Planner.nb_cases(Maze), Maze.nb_cases(), "bot.per_map: tables de la premiere carte")
	h.eq(Planner.nb_cases(Alt), Alt.nb_cases(), "bot.per_map: tables de la seconde carte")
	h.ok(Planner.cases_praticables(Maze).size() != Planner.cases_praticables(Alt).size(),
		"bot.per_map: les deux topologies different reellement")
