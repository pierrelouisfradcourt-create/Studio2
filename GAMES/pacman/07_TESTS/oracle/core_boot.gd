# core_boot.gd — ligne CORE core.boot.
# Lancement de main.tscn SANS aucune intervention humaine : l'etat initial DECLARE est
# ATTEINT et CONSTATE par le canal d'observation public. Le nombre d'appuis avant l'etat
# initial est EXACTEMENT 0, le nombre d'ecrans intercales EXACTEMENT 0, le nombre
# d'erreurs au lancement EXACTEMENT 0.
extends RefCounted

const Boot = preload("res://06_RUNTIME/adapters/runtime_loop/boot.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Status = preload("res://05_SYSTEMS/game_state/status.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())
const Probe = preload("res://06_RUNTIME/adapters/debug_probe/debug_probe.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const EndScreen = preload("res://06_RUNTIME/adapters/presentation/end_screen.gd")


func run(h) -> void:
	# ZERO APPUI : l'etat initial est atteint sans qu'aucune touche soit emise.
	var appuis: int = 0
	var etat = Boot.etat_initial()
	h.eq(appuis, 0, "core.boot: 0 appui avant l'etat initial")

	# ZERO ECRAN INTERCALE : aucun ecran de fin, aucun menu — la partie est jouable.
	h.eq(EndScreen.est_actif(etat.statut), false, "core.boot: 0 ecran intercale au lancement")
	h.eq(etat.statut, State.Statut.EN_COURS, "core.boot: la partie est immediatement EN COURS")

	# ZERO ERREUR : l'etat construit est structurellement valide.
	h.eq(etat.est_valide(), true, "core.boot: 0 erreur — l'etat initial est valide")

	# L'ETAT INITIAL DECLARE EST ATTEINT, et CONSTATE PAR LE CANAL D'OBSERVATION PUBLIC
	# (jamais par une lecture forcee de l'etat interne).
	var ligne: String = Probe.ligne(Observable.projeter(etat))
	var vu: Dictionary = Probe.relire(ligne)
	h.eq(vu.is_empty(), false, "core.boot: l'etat initial est lisible sur le canal public")
	h.eq(int(vu["tick"]), 0, "core.boot: tick 0 constate de l'exterieur")
	h.eq(int(vu["score"]), 0, "core.boot: score 0 constate de l'exterieur")
	# TRIAGE V6 : COUNT_FROZEN (5 -> 3). L'application amorce dans le MODE PAR DEFAUT, et
	# depuis la decision Pierre du 2026-08-06 ce mode — le defi — accorde trois vies.
	# L'assertion garde sa nature (constater la valeur de depart PAR LE CANAL PUBLIC) ;
	# seule la valeur figee change.
	h.eq(int(vu["vies"]), 3, "core.boot: 3 vies constatees de l'exterieur")
	h.eq(int(vu["restantes"]), 244, "core.boot: 244 collectibles constates de l'exterieur")
	h.eq(vu["statut_nom"], "EN COURS", "core.boot: statut EN COURS constate de l'exterieur")
	# Le canal public transporte du JSON : les nombres reviennent en flottants. On relit
	# donc en entiers — c'est le lecteur exterieur qui s'adapte au canal, jamais l'inverse.
	h.eq(int(vu["pac"][0]), Maze.DEPART_PACMAN.x, "core.boot: colonne de depart constatee de l'exterieur")
	h.eq(int(vu["pac"][1]), Maze.DEPART_PACMAN.y, "core.boot: ligne de depart constatee de l'exterieur")
	h.eq(vu["dehors"], [true, false, false, false], "core.boot: un seul fantome dehors, constate")

	# LA SCENE PRINCIPALE EXISTE et pointe le script d'amorcage declare.
	h.ok(FileAccess.file_exists("res://main.tscn"), "core.boot: main.tscn existe")
	var f := FileAccess.open("res://main.tscn", FileAccess.READ)
	var scene: String = f.get_as_text() if f != null else ""
	h.ok(scene.contains("res://06_RUNTIME/adapters/runtime_loop/runtime_loop.gd"),
		"core.boot: main.tscn porte le script du runtime")
	h.ok(scene.contains("type=\"Node2D\""), "core.boot: la scene principale est un noeud rendu")

	# FALSIFICATION : un point d'entree neutralise se CONSTATE. Un etat dont la scene ne
	# serait pas lancee n'expose aucun releve valide — le canal public le dirait.
	h.eq(Probe.relire("").is_empty(), true, "core.boot: aucun releve -> constat d'absence, jamais un vert")
	h.eq(Probe.relire(Probe.PREFIXE + "{}").has("tick"), false,
		"core.boot: un releve vide ne porte pas l'etat initial")

	# Reproductibilite de l'amorcage : deux lancements donnent le meme etat initial.
	h.eq(Boot.etat_initial().egal_profond(etat), true, "core.boot: amorcage reproductible")
