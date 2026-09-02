# core_render.gd — oracle produit de la ligne core.render. SceneTree headless.
#
# CE VOLET NE PROUVE PAS, ET LE DECLARE LUI-MEME.
#
# core_requirements.yaml exige pour core.render une preuve `pixel` : « deux captures a
# des etats differents different ; aucune capture n'est monochrome ». En --headless, le
# driver dummy rend une texture NULLE — aucune capture n'existe, donc aucune de ces deux
# assertions ne peut etre evaluee (mesure du 2026-07-22, memoire
# godot_capture_requires_gpu_window).
#
# Le payload porte donc `requires_gpu_window: true` : la cle de marqueur
# (product_oracle_godot._GPU_WINDOW_MARKER_KEY) par laquelle un volet declare LUI-MEME
# qu'il n'a pas pu etre mesure. Le collecteur rend alors NOT_MEASURED motive, JAMAIS
# FAIL — lecon forge.oracle_fail_vs_not_measured_marker : un oracle qui rend FAIL sur ce
# qu'il ne peut pas mesurer envoie reparer la mauvaise chose. Ici le jeu n'est pas en
# cause ; c'est le MODE D'EXECUTION qui ne permet pas la preuve.
#
# NOMMAGE DELIBERE : `core_render` et non `core_render_frame`. Ce dernier appartient au
# FILET en dur GPU_WINDOW_REQUIRED_VOLETS, que le collecteur ne lance jamais — le volet
# serait alors exempte SANS AVOIR RIEN DIT. Ici il s'execute, et sa raison entre dans le
# recu, tracable par Observer. Choix ratifie Pierre 2026-08-10 (option (a)).
#
# CE QUI EST QUAND MEME ETABLI, et qui prepare l'option (c) : que les deux etats compares
# DIFFERENT REELLEMENT. Si un jour un run en fenetre GPU produit deux captures, ce volet
# aura deja montre que la comparaison est signifiante — deux etats identiques rendraient
# la preuve pixel vide meme avec une vraie fenetre. Ce n'est PAS la preuve pixel, et ce
# n'est pas presente comme telle : `ok` reste false.
#
# Sortie : "FORGE_ORACLE core_render {json}", NOT_MEASURED cote collecteur.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const InputRules = preload("res://05_SYSTEMS/input_rules/input.gd")
const Debug = preload("res://05_SYSTEMS/debug_state/debug_state.gd")

func _initialize() -> void:
	# Deux etats a comparer : l'etat initial, et un etat obtenu apres des pieces posees.
	var s0 = State.initial(1)
	var s = s0
	for i in range(400):
		if s.status != State.Statut.EN_COURS:
			break
		s = Loop.step(s, InputRules.HARD_DROP)["state"]

	var a: Dictionary = Debug.snapshot(s0)
	var b: Dictionary = Debug.snapshot(s)

	# Les deux etats different-ils ? Si non, comparer leurs rendus ne prouverait rien,
	# meme avec une vraie fenetre GPU.
	var cellules_a := _occupees(a["grid"])
	var cellules_b := _occupees(b["grid"])
	var etats_differents: bool = cellules_a != cellules_b or a["score"] != b["score"]

	var notes: Array = []
	if not etats_differents:
		notes.append("les deux etats compares sont identiques — la comparaison pixel serait vide")

	var data := {
		"preuve_exigee": "pixel (core_requirements.core.render)",
		"mode_execution": "headless — driver dummy, texture nulle",
		"captures_possibles": 0,
		"etats_differents": etats_differents,
		"cellules_etat_initial": cellules_a,
		"cellules_etat_avance": cellules_b,
		"score_etat_avance": b["score"],
		"notes": notes,
	}
	# `ok: false` — ce volet n'a rien prouve. Le marqueur ci-dessous fait autorite et le
	# collecteur rendra NOT_MEASURED ; si un jour ce routage disparaissait, `false`
	# resterait la lecture SURE (jamais un faux vert).
	print("FORGE_ORACLE core_render " + JSON.stringify({
		"ok": false,
		"requires_gpu_window": true,
		"fails": ["preuve pixel impossible en headless — aucune capture disponible"],
		"data": data,
	}))
	quit(0)

func _occupees(grid: Array) -> int:
	var n := 0
	for row in grid:
		for c in row:
			if c != 0:
				n += 1
	return n
