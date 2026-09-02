# v2_core_audio.gd — ligne core.audio, capacites F90/F93.
# Au moins un retour sonore est declenche par une action de jeu. FIN DU DEFERRED : le
# charter V2 a tranche — audio INCLUS, entierement GENERE a l'execution, zero fichier
# importe.
# CONTROLE CROISE OBLIGATOIRE : l'inventaire porte EXACTEMENT 0 fichier audio. Un son
# present sans asset est la SEULE lecture acceptable des deux mesures ensemble.
extends RefCounted

const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const InventoryV2 = preload("res://06_RUNTIME/adapters/proof_harness/harness_asset_inventory_v2.gd")
const Events = preload("res://05_SYSTEMS/game_events/game_events.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))


func run(h) -> void:
	Audio.reinitialiser()

	# UNE ACTION DE JEU declenche un son, trace au tick.
	var jeu = State.initial(Maze, 5)
	var declenches: int = 0
	for _t in range(30):
		var r: Dictionary = Loop.step(jeu, Maze.DEPART_DIRECTION)
		jeu = r["etat"]
		declenches += Audio.jouer_evenements(r["evenements_sonores"], jeu.ticks).size()
	h.gt(declenches, 0, "core.audio: une action de jeu declenche un son")
	h.gt(Audio.journal().size(), 0, "core.audio: le declenchement est trace")

	# LES SIX EVENEMENTS declenchent chacun un son.
	Audio.reinitialiser()
	Audio.jouer_evenements(Events.MOMENTS, 1)
	h.eq(Audio.moments_muets(), 0, "core.audio: aucun des six ne reste muet")
	h.eq(Audio.moments_joues().size(), 6, "core.audio: six moments distincts declenches")

	# CONTROLE CROISE : 0 fichier audio dans le jeu.
	var inv: Dictionary = InventoryV2.mesurer()
	h.eq(inv["fichiers_audio"], 0, "core.audio: 0 fichier audio dans l'inventaire")
	h.gt(inv["fichiers"], 0, "core.audio: l'inventaire a reellement parcouru le projet")
	h.eq(inv["descripteurs_de_synthese"], 6, "core.audio: six descripteurs de synthese a la place")
	h.gt(Audio.echantillons(Bank.descripteur("son_victoire")).size(), 0,
		"core.audio: le signal est fabrique a l'execution")
	Audio.reinitialiser()
