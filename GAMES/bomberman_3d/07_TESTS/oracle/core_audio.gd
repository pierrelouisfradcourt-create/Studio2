# core_audio.gd — oracle produit de la ligne core.audio.
#
# `core_requirements.core.audio` exige : « Au moins un retour sonore est declenche par une
# action de jeu », preuve de type `artifact` : « un asset audio existe, est reference par le
# contrat, et son declenchement est TRACE ».
#
# LECTURE ASSUMEE, et elle suit le precedent Pacman (v2_audio_runtime_synthesis) : l'artefact
# n'est PAS un fichier .wav mais le DESCRIPTEUR DE SYNTHESE, qui vit dans les regles et est
# reference par le contrat. Aucun fichier audio n'entre dans le depot. Ce que ce volet
# prouve, c'est le TROISIEME terme de l'exigence, le seul qui puisse mentir : le
# declenchement est reellement trace, sur une partie reellement jouee.
#
# MODE HEADLESS, et c'est une MESURE, pas une hypothese. J'avais d'abord marque ce volet
# `gpu_window` en supposant qu'aucun peripherique audio n'existe en headless. Mesure du
# 2026-08-10 : les deux modes synthetisent (16 639 echantillons en fenetre, 16 383 en
# headless) — le tampon accepte les trames sans peripherique. Le mode GPU coutait donc un
# lancement pour rien. Une supposition sur la plateforme se verifie avant d'etre inscrite
# dans un contrat de mode.
extends SceneTree

const P = preload("res://05_SYSTEMS/params/params.gd")
const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Cues = preload("res://05_SYSTEMS/sound_cues/sound_cues.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Validator = preload("res://05_SYSTEMS/map_validator/map_validator.gd")
const Content = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")

var _audio
var _f := 0
var _fait := false

func _initialize() -> void:
	Audio.reinitialiser_journal()
	_audio = Audio.new()
	get_root().add_child(_audio)

func _process(_d: float) -> bool:
	_f += 1
	if _f < 6:
		return false
	if _fait:
		return true
	_fait = true

	# Partie REELLE : on ne declenche pas les sons a la main, on joue et on ecoute ce que
	# la boucle emet.
	var desc: Dictionary = Content.descripteur(0)
	var s = State.initial(Validator.carte_validee(desc), desc, 1, 4)
	s.acteurs[0]["rayon"] = 3
	var r: Dictionary = Loop.step(s, [P.POSER, P.AUCUNE, P.AUCUNE, P.AUCUNE])
	s = r["state"]
	_audio.consommer(r["events"], int(s.ticks))
	for i in range(P.MECHE_TICKS + P.DUREE_FLAMME + 8):
		r = Loop.step(s, [P.AUCUNE, P.AUCUNE, P.AUCUNE, P.AUCUNE])
		s = r["state"]
		_audio.consommer(r["events"], int(s.ticks))

	var fails: Array = []
	var moments := {}
	var total_ech: int = 0
	for e in Audio.journal:
		moments[String(e["cue"])] = true
		total_ech += int(e["echantillons"])

	if Audio.journal.is_empty():
		fails.append("aucun declenchement trace sur une partie jouee")
	if not moments.has(Cues.CUE_POSE):
		fails.append("poser une bombe n'a declenche aucun son")
	if not moments.has(Cues.CUE_EXPLOSION):
		fails.append("une explosion n'a declenche aucun son")
	if total_ech <= 0:
		fails.append("0 echantillon REELLEMENT synthetise (peripherique absent ?)")

	print("FORGE_ORACLE core_audio " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"declenchements": Audio.journal.size(),
		"moments_distincts": moments.keys(),
		"echantillons_synthetises": total_ech,
	}))
	quit(0 if fails.is_empty() else 1)
	return true
