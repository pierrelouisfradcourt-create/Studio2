# v2_core_input.gd — ligne core.input, capacite F75.
# Le joueur peut agir sur le jeu. En V2 l'action emise est une INTENTION du vocabulaire
# ferme, sur le canal d'entree public UNIQUE — le meme pour le clavier, la manette, le
# tactile et le bot.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")
const Bindings = preload("res://06_RUNTIME/adapters/input_bindings/input_bindings.gd")
const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const Driver = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	# COMPTAGE STATIQUE : 0 fichier de logique reference une API d'entree.
	h.eq(Purity.entree_dans_logique().size(), 0, "core.input: 0 API d'entree dans la logique")
	h.gt(Purity.entree_dans_runtime().size(), 0, "core.input: controle positif dans le runtime")

	# LE MEME CANAL pour les quatre sources.
	var touche: int = Bindings.liaisons(Intents.Intention.GAUCHE, Bindings.CLAVIER)[0]
	var bouton: int = Bindings.liaisons(Intents.Intention.GAUCHE, Bindings.MANETTE)[0]
	var zone: String = Bindings.liaisons(Intents.Intention.GAUCHE, Bindings.TACTILE)[0]
	h.eq(InputAdapter.intention_de_touche(touche), Intents.Intention.GAUCHE, "core.input: clavier")
	h.eq(InputAdapter.intention_de_bouton(bouton), Intents.Intention.GAUCHE, "core.input: manette")
	h.eq(InputAdapter.intention_de_zone(zone), Intents.Intention.GAUCHE, "core.input: tactile")
	var jeu = State.initial(Maze, 1)
	var action: Vector2i = Driver.choisir_action(jeu)
	h.eq(InputAdapter.normaliser_direction(action), action, "core.input: le bot passe par la meme porte")

	# L'ACTION AGIT reellement sur le jeu.
	var avant = State.initial(Maze, 1)
	var apres = Loop.step_intentions(avant, [Intents.Intention.GAUCHE])["etat"]
	h.ok(apres.pac != avant.pac, "core.input: l'action deplace le joueur")
	h.eq(apres.pac_dir, MazeClass.GAUCHE, "core.input: dans la direction demandee")

	# UNE ENTREE HORS VOCABULAIRE est ignoree sans effet de bord.
	var neutre = Loop.step_intentions(State.initial(Maze, 1), [])["etat"]
	h.eq(neutre.ticks, 1, "core.input: le tick a lieu meme sans intention")
	h.eq(InputAdapter.traduire(KEY_F13)["genre"], "aucune", "core.input: une touche non liee est hors vocabulaire")
