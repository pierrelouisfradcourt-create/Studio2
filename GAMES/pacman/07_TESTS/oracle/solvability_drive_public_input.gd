# solvability_drive_public_input.gd — ligne solvability.drive_public_input, capacite F54.
# Execution du bot sur la carte et la graine de reference : statut final GAGNE,
# consommes egal 244, restantes egal 0, ATTEINTS PAR LE SEUL CANAL D'ENTREE PUBLIC.
extends RefCounted

const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")

const GRAINE_REFERENCE: int = 1
const BUDGET_DECLARE: int = 4000


func run(h) -> void:
	# L'action du bot passe par la NORMALISATION du canal public : il ne peut pas emettre
	# autre chose qu'une touche du clavier.
	var s = State.initial(Maze, GRAINE_REFERENCE)
	var action: Vector2i = Bot.choisir_action(s)
	h.ok(Maze.DIRECTIONS.has(action) or action == Maze.AUCUNE,
		"solvability.drive: l'action appartient au vocabulaire ferme")
	h.eq(InputAdapter.normaliser_direction(action), action,
		"solvability.drive: l'action est deja normalisee par le canal public")

	# Le bot est DETERMINISTE : meme etat, meme action.
	h.eq(Bot.choisir_action(s), Bot.choisir_action(s), "solvability.drive: action deterministe")

	# BOUCLE FERMEE : le bot relit l'etat courant. Deplacer un fantome change son action —
	# sans quoi il serait en boucle ouverte et ne verrait jamais les poursuivants.
	var t = State.initial(Maze, GRAINE_REFERENCE)
	for _t in range(60):
		t = Loop.step(t, Bot.choisir_action(t))["etat"]
	var action_libre: Vector2i = Bot.choisir_action(t)
	h.ok(Maze.DIRECTIONS.has(action_libre), "solvability.drive: le bot a une action franche sans menace")
	# Un poursuivant est pose EXACTEMENT sur la case ou le bot allait poser le pied. S'il
	# etait en boucle ouverte, il y irait quand meme.
	var barre = t.clone()
	var case_visee: Vector2i = Maze.case_suivante(barre.pac, action_libre)
	h.eq(Maze.praticable(case_visee), true, "solvability.drive: la case visee est bien praticable")
	for i in range(4):
		barre.dehors[i] = true
		barre.effrayes[i] = false
		barre.fantomes[i] = case_visee
	barre.effraye_restant = 0
	h.ok(Bot.choisir_action(barre) != action_libre,
		"solvability.drive: l'action DEPEND de la position des fantomes")

	# PARTIE COMPLETE pilotee par le seul canal public.
	var partie: Dictionary = Bot.jouer_depuis_graine(Maze, GRAINE_REFERENCE, BUDGET_DECLARE)
	var final = partie["etat"]
	var releve: Dictionary = Observable.projeter(final)

	h.eq(final.statut, State.Statut.GAGNE, "solvability.drive: statut final GAGNE")
	h.eq(releve["statut_nom"], "GAGNE", "solvability.drive: l'issue exposee est GAGNE")
	h.eq(final.consommees, 244, "solvability.drive: consommes egal 244")
	h.eq(releve["restantes"], 0, "solvability.drive: restantes egal 0")
	h.eq(final.consommees, final.total_pose, "solvability.drive: egalite stricte consommes / total pose")
	h.lt(partie["ticks"], BUDGET_DECLARE, "solvability.drive: victoire dans le budget declare")
	h.gt(final.score, 0, "solvability.drive: un score reel a ete accumule")

	# L'ETAT N'A JAMAIS ETE FORCE : Pac-Man est reste sur des cases praticables et le
	# nombre de collectibles conserve son invariant a l'arrivee.
	h.eq(Maze.praticable(final.pac), true, "solvability.drive: Pac-Man est sur une case praticable")
	h.eq(final.est_valide(), true, "solvability.drive: l'etat final est structurellement valide")
	h.gt(final.vies, 0, "solvability.drive: la partie n'est pas gagnee par epuisement des vies")
