# solvability_broken_map.gd — ligne solvability.verdict, capacites F55 et F56.
# [F55] Sur la carte de reference : verdict SOLVABLE avec consommes egal 244 et
# restantes egal 0 dans le budget declare. [F56] Sur la carte CASSEE : statut final
# different de GAGNE, sortie INJOUABLE.
#
# CORRECTION M4 (red-team s6) : la contre-epreuve est evaluee PAR LE BOT, jamais
# court-circuitee en amont par le verificateur d'invariants de carte. Un rouge produit
# par pellets.map_invariants prouverait seulement que le verificateur d'invariants
# fonctionne — pas que l'oracle de solvabilite detecte un jeu ingagnable. Ici le bot joue
# reellement la carte cassee, pendant tout le budget, et c'est SON echec qui est mesure.
#
# CORRECTION B2 : le verdict s'exprime par `succeeded: false`, jamais par un code de
# retour non nul — l'executeur reel leve sur tout statut non nul et rendrait BLOCKED.
extends RefCounted

const Verdict = preload("res://06_RUNTIME/adapters/solvability_bot/verdict.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Pellets = preload("res://05_SYSTEMS/pellets/pellets.gd")

const GRAINE_REFERENCE: int = 1
# Budget de la contre-epreuve : quatre fois la duree mesuree d'une victoire de reference
# (777 ticks sur la graine 1). Assez large pour qu'un echec ne puisse pas etre impute a
# un budget trop court.
const BUDGET_CONTRE_EPREUVE: int = 3200
# Case de MUR sur laquelle un collectible est pose : il devient inatteignable, donc
# l'egalite stricte consommes == total pose devient impossible a satisfaire.
const CASE_MUREE := Vector2i(0, 0)


func _carte_cassee() -> Object:
	var s = State.initial(Maze, GRAINE_REFERENCE)
	s.pastilles[Maze.index_de(CASE_MUREE)] = Pellets.Contenu.PASTILLE
	s.total_pose = Pellets.total_pose(s.pastilles)
	return s


func run(h) -> void:
	# F55 — CARTE DE REFERENCE : le bot gagne, le verdict est SOLVABLE.
	var reference: Dictionary = Bot.jouer_depuis_graine(Maze, GRAINE_REFERENCE, BUDGET_CONTRE_EPREUVE)
	var v_ref: Dictionary = Verdict.evaluer(reference["etat"], reference["ticks"])
	h.eq(v_ref["succeeded"], true, "solvability.verdict: la carte de reference est gagnee")
	h.eq(v_ref["libelle"], Verdict.LIBELLE_SOLVABLE, "solvability.verdict: libelle SOLVABLE")
	h.eq(v_ref["consommees"], 244, "solvability.verdict: consommes egal 244")
	h.eq(v_ref["total_pose"] - v_ref["consommees"], 0, "solvability.verdict: restantes egal 0")
	h.eq(v_ref["ticks"], reference["ticks"], "solvability.verdict: le recu porte le nombre de ticks")

	# La fixture cassee est bien cassee : un collectible de plus, sur une case de mur.
	var cassee = _carte_cassee()
	h.eq(cassee.total_pose, 245, "solvability.verdict: la carte cassee porte 245 collectibles")
	h.eq(Maze.praticable(CASE_MUREE), false, "solvability.verdict: le collectible ajoute est dans un mur")
	h.eq(Pellets.tous_atteignables(Maze, cassee.pastilles, Maze.DEPART_PACMAN), false,
		"solvability.verdict: l'invariant d'atteignabilite tombe sur la carte cassee")

	# F56 — CARTE CASSEE, EVALUEE PAR LE BOT : il joue tout le budget et ne gagne pas.
	var brisee: Dictionary = Bot.jouer(cassee, BUDGET_CONTRE_EPREUVE)
	var v_cassee: Dictionary = Verdict.evaluer(brisee["etat"], brisee["ticks"])
	h.eq(v_cassee["succeeded"], false, "solvability.verdict: la carte cassee n'est PAS gagnee")
	h.eq(v_cassee["libelle"], Verdict.LIBELLE_INJOUABLE, "solvability.verdict: libelle INJOUABLE")
	h.eq(v_cassee["ticks"], null, "solvability.verdict: aucun nombre de ticks sur un echec")
	h.ok(brisee["etat"].statut != State.Statut.GAGNE, "solvability.verdict: statut final different de GAGNE")

	# Le bot a REELLEMENT joue : il a consomme les collectibles atteignables, et c'est
	# l'INATTEIGNABLE qui l'arrete — pas un budget trop court ni un arret precoce.
	h.gt(brisee["etat"].consommees, 200, "solvability.verdict: le bot a bien joue la carte cassee")
	h.lt(brisee["etat"].consommees, brisee["etat"].total_pose,
		"solvability.verdict: il reste strictement des collectibles inatteignables")

	# PROTOCOLE DE SORTIE : le recu est une ligne UNIQUE, prefixee, ou l'echec s'exprime
	# par `succeeded: false` — jamais par un code de retour.
	var recu: String = Verdict.recu(v_cassee)
	h.ok(recu.begins_with(Verdict.PREFIXE_RECU), "solvability.verdict: le recu porte le prefixe attendu")
	h.ok(recu.contains("\"succeeded\":false"), "solvability.verdict: l'echec s'exprime dans le recu")
	h.eq(recu.split("\n").size(), 1, "solvability.verdict: le recu tient sur une seule ligne")
	var recu_ok: String = Verdict.recu(v_ref)
	h.ok(recu_ok.contains("\"succeeded\":true"), "solvability.verdict: la reussite s'exprime dans le recu")
