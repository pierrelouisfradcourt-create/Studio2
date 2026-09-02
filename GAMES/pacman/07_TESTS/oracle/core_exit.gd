# core_exit.gd — ligne CORE core.exit.
# Sortie demandee par le canal PUBLIC -> le processus est TERMINE, le code de sortie est
# EXACTEMENT 0, la boucle de tick est ARRETEE.
#
# CE QUI EST MESURE ICI, ET CE QUI NE L'EST PAS : ce harnais s'execute DANS le processus
# Godot lance par l'oracle maitre. Appeler reellement la sortie ici tuerait le harnais et
# rendrait un vert silencieux sur tous les tests suivants. Ce test constate donc, du
# canal public jusqu'au code de sortie declare, TOUTE la chaine sauf l'appel terminal
# lui-meme. Le volet « le processus a reellement disparu » n'est PAS mesure ici : il est
# remonte dans la section SKIPPED_VALIDATION du rapport d'etape.
#
# GAP CONNU, REMONTE PAR LA CARTE ELLE-MEME : la featuremap de ce run ne declare AUCUNE
# capacite de sortie. La ligne core.exit est un point de controle du STANDARD, pas une
# capacite du jeu — le fait est rapporte, jamais comble par invention.
extends RefCounted

const InputAdapter = preload("res://06_RUNTIME/adapters/input_adapter/input_adapter.gd")
const RuntimeLoop = preload("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")


func run(h) -> void:
	# LE CANAL PUBLIC porte la commande de sortie, dans un vocabulaire ferme.
	h.eq(InputAdapter.est_sortie(KEY_ESCAPE), true, "core.exit: echap demande la sortie")
	h.eq(InputAdapter.traduire(KEY_ESCAPE)["genre"], "commande", "core.exit: c'est une commande")
	h.eq(InputAdapter.traduire(KEY_ESCAPE)["commande"], InputAdapter.CMD_SORTIE,
		"core.exit: la commande est nommee")
	h.eq(InputAdapter.est_sortie(KEY_R), false, "core.exit: la relance n'est pas la sortie")
	h.eq(InputAdapter.est_sortie(KEY_UP), false, "core.exit: une direction n'est pas la sortie")
	h.eq(InputAdapter.est_sortie(KEY_F7), false, "core.exit: une touche non liee n'est pas la sortie")

	# LE CODE DE SORTIE est DECLARE et vaut EXACTEMENT 0.
	h.eq(RuntimeLoop.CODE_SORTIE, 0, "core.exit: le code de sortie declare vaut exactement 0")

	# LA BOUCLE DE TICK EST ARRETABLE : gelee, elle ne produit plus aucun tick et
	# n'accumule plus aucun temps. Le nombre de ressources laissees actives est 0.
	var gele: Dictionary = RuntimeLoop.avancer(120.0, P.PERIODE_TICK_MS * 5.0, P.PERIODE_TICK_MS, true)
	h.eq(gele["ticks"], 0, "core.exit: boucle arretee -> 0 tick produit")
	h.eq(gele["accumulateur"], 0.0, "core.exit: boucle arretee -> 0 temps accumule")
	var repete: Dictionary = RuntimeLoop.avancer(gele["accumulateur"], P.PERIODE_TICK_MS * 50.0,
		P.PERIODE_TICK_MS, true)
	h.eq(repete["ticks"], 0, "core.exit: la boucle arretee ne repart pas d'elle-meme")

	# LA SORTIE EST OBSERVABLE : le dernier releve est emis sur le canal public avant que
	# le processus ne se termine. Une commande dont l'effet n'est pas observable est un
	# FAIL (defaut « Quitter inerte », playtest Pong 2026-07-27).
	var s = State.initial(Maze, 1)
	for _t in range(20):
		s = Loop.step(s, Maze.GAUCHE)["etat"]
	var dernier: Dictionary = Probe.relire(Probe.ligne(Observable.projeter(s)))
	h.eq(dernier.is_empty(), false, "core.exit: un dernier releve est emis sur le canal public")
	h.eq(int(dernier["tick"]), s.ticks, "core.exit: ce releve porte l'etat au moment de la sortie")
	h.eq(int(dernier["score"]), s.score, "core.exit: et le score au moment de la sortie")

	# La commande de sortie est distincte des quatre directions ET de la relance : le
	# vocabulaire ferme compte bien six entrees, sans recouvrement.
	var vocabulaire := {}
	for touche in [KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT]:
		vocabulaire[str(InputAdapter.direction_de_touche(touche))] = true
	vocabulaire[InputAdapter.CMD_RELANCE] = true
	vocabulaire[InputAdapter.CMD_SORTIE] = true
	h.eq(vocabulaire.size(), 6, "core.exit: six entrees dans le vocabulaire ferme, sans recouvrement")
	h.ok(InputAdapter.CMD_SORTIE != InputAdapter.CMD_RELANCE, "core.exit: sortie et relance sont distinctes")
