# v2_audio_runtime_synthesis.gd — ligne audio.runtime_synthesis, capacite F90.
# Le son est FABRIQUE A L'EXECUTION a partir d'un descripteur de synthese, via
# AudioStreamGenerator : AUCUN echantillon n'est lu depuis un fichier.
extends RefCounted

const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")
const MazeClass = preload("res://05_SYSTEMS/maze/maze.gd")
var Maze = MazeClass.depuis_descripteur(ContentV2.descripteur(0))
const Events = preload("res://05_SYSTEMS/game_events/game_events.gd")


func run(h) -> void:
	Audio.reinitialiser()
	h.eq(Audio.journal().size(), 0, "audio.synthese: le journal part vide")

	# LE FLUX est GENERE, pas charge.
	var flux := Audio.fabriquer_flux()
	h.ok(flux != null, "audio.synthese: un flux est fabrique")
	h.eq(Audio.est_flux_de_plateforme(flux), true, "audio.synthese: c'est un flux de la plateforme")
	h.eq(flux.mix_rate, Bank.FREQUENCE_ECHANTILLONNAGE, "audio.synthese: frequence declaree")

	# LES ECHANTILLONS sont CALCULES : la suite n'existe dans aucun fichier.
	var buffer: PackedFloat32Array = Audio.echantillons(Bank.descripteur("son_collecte"))
	h.gt(buffer.size(), 0, "audio.synthese: des echantillons sont synthetises")
	var non_nuls: int = 0
	for v in buffer:
		if absf(v) > 0.0001:
			non_nuls += 1
	h.gt(non_nuls, 0, "audio.synthese: le signal n'est pas silencieux")
	h.eq(Audio.echantillons({}).size(), 0, "audio.synthese: un descripteur vide ne synthetise rien")

	# L'ENVELOPPE et l'ONDE sont deterministes et bornees.
	var desc: Dictionary = Bank.descripteur("son_collecte")
	h.eq(Audio.enveloppe(-1.0, desc), 0.0, "audio.synthese: aucune amplitude avant le debut")
	h.eq(Audio.enveloppe(999.0, desc), 0.0, "audio.synthese: aucune amplitude apres la fin")
	h.eq(Audio.onde(Bank.ONDE_CARREE, 0.25), 1.0, "audio.synthese: onde carree, premiere moitie")
	h.eq(Audio.onde(Bank.ONDE_CARREE, 0.75), -1.0, "audio.synthese: onde carree, seconde moitie")

	# UNE ACTION DE JEU declenche un flux, TRACE AU TICK de son declenchement.
	var jeu = State.initial(Maze, 5)
	var declenches: int = 0
	for _t in range(20):
		var r: Dictionary = Loop.step(jeu, Maze.DEPART_DIRECTION)
		jeu = r["etat"]
		declenches += Audio.jouer_evenements(r["evenements_sonores"], jeu.ticks).size()
	h.gt(declenches, 0, "audio.synthese: une action de jeu declenche un flux")
	h.gt(Audio.journal().size(), 0, "audio.synthese: les declenchements sont traces")
	h.eq(Audio.journal()[0]["joue"], true, "audio.synthese: le premier declenchement a produit du signal")
	h.gt(int(Audio.journal()[0]["tick"]), 0, "audio.synthese: le tick de declenchement est trace")
	h.gt(int(Audio.journal()[0]["echantillons"]), 0, "audio.synthese: le nombre d'echantillons est trace")
	Audio.reinitialiser()
