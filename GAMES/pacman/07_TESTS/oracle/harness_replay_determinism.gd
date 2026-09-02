# harness_replay_determinism.gd — ligne harness.replay_determinism, capacite F52.
# Deux executions comparees CHAMP PAR CHAMP : trace des positions, score et statut final
# STRICTEMENT identiques, sur une fenetre rejouee qui franchit AU MOINS DEUX seuils de la
# sequence d'etats de poursuite.
extends RefCounted

const Replay = preload("res://06_RUNTIME/adapters/proof_harness/replay.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
var Maze = preload("res://05_SYSTEMS/maze/maze.gd").depuis_descripteur(ContentV2.descripteur_classique())


func run(h) -> void:
	var mesure: Dictionary = Replay.mesurer(Maze)

	# La fenetre rejouee franchit AU MOINS DEUX seuils : sans cela, le rejeu ne couvrirait
	# aucune bascule d'etat et ne prouverait rien de la machine a etats.
	h.gt(mesure["seuils_franchis"], 1, "harness.replay: au moins deux seuils franchis")
	h.eq(mesure["raison"], "", "harness.replay: les deux traces ont la meme longueur")

	# CHAMP PAR CHAMP : zero divergence.
	h.eq(mesure["divergences"], 0, "harness.replay: 0 champ divergent entre les deux traces")
	h.eq(mesure["premier"], -1, "harness.replay: aucun premier point de divergence")

	# Score et statut FINAUX strictement identiques.
	h.eq(mesure["score_a"], mesure["score_b"], "harness.replay: score final identique")
	h.eq(mesure["statut_a"], mesure["statut_b"], "harness.replay: statut final identique")

	# La suite d'appuis est REJOUEE, pas recalculee : c'est l'entree qui pilote.
	var enregistre: Dictionary = Replay.enregistrer(Maze, Replay.GRAINE_REJEU, 120)
	h.eq(enregistre["appuis"].size(), 120, "harness.replay: 120 appuis enregistres")
	var rejoue: Dictionary = Replay.rejouer(Maze, Replay.GRAINE_REJEU, enregistre["appuis"])
	h.eq(Replay.comparer(enregistre["trace"], rejoue["trace"])["divergences"], 0,
		"harness.replay: la suite d'appuis rejouee reproduit la trace")

	# CONTRE-EPREUVE du comparateur : il DETECTE une divergence. Sans elle, un
	# comparateur qui rendrait toujours 0 passerait pour une preuve de determinisme.
	var altere: Array = []
	for r in rejoue["trace"]:
		altere.append(r.duplicate())
	altere[10]["score"] = altere[10]["score"] + 1
	h.gt(Replay.comparer(enregistre["trace"], altere)["divergences"], 0,
		"harness.replay: le comparateur detecte une trace alteree")
	h.eq(Replay.comparer(enregistre["trace"], altere)["premier"], 10,
		"harness.replay: il nomme le premier point de divergence")

	# CONTRE-EPREUVE de graine : une graine differente produit une trace differente.
	var autre: Dictionary = Replay.enregistrer(Maze, Replay.GRAINE_REJEU + 1, 120)
	h.gt(Replay.comparer(enregistre["trace"], autre["trace"])["divergences"], 0,
		"harness.replay: une graine differente donne une trace differente")

	# La mesure est faite depuis l'ETAT EXPOSE : la trace est une suite de releves.
	h.eq(enregistre["trace"].size(), 121, "harness.replay: un releve par tick, plus l'etat initial")
	h.ok(enregistre["trace"][0].has("pac"), "harness.replay: la trace porte les positions exposees")
	h.ok(enregistre["trace"][0].has("statut_nom"), "harness.replay: la trace porte le statut expose")
