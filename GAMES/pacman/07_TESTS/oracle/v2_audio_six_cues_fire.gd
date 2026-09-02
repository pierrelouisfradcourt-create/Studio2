# v2_audio_six_cues_fire.gd — ligne audio.six_cues_fire, capacite F93.
# Chacun des SIX evenements nommes est branche sur SON PROPRE descripteur et declenche
# effectivement un son : aucun des six ne reste muet, aucun n'emprunte le descripteur
# d'un autre.
extends RefCounted

const Audio = preload("res://06_RUNTIME/adapters/audio/audio.gd")
const Bank = preload("res://06_RUNTIME/adapters/sound_bank/sound_bank.gd")
const Events = preload("res://05_SYSTEMS/game_events/game_events.gd")


func run(h) -> void:
	Audio.reinitialiser()
	var resultats: Array = Audio.jouer_evenements(Events.MOMENTS, 1)
	h.eq(resultats.size(), 6, "audio.six: les six evenements sont joues")

	var muets: int = 0
	for r in resultats:
		if not r["joue"]:
			muets += 1
	h.eq(muets, 0, "audio.six: aucun des six ne reste muet")
	h.eq(Audio.moments_muets(), 0, "audio.six: le comptage des muets vaut 0")
	h.eq(Audio.moments_joues().size(), 6, "audio.six: six moments distincts declenches")

	# CHACUN SUR SON PROPRE DESCRIPTEUR : les longueurs de signal ne sont pas toutes egales.
	var tailles: Array = []
	for r in resultats:
		tailles.append(int(r["echantillons"]))
	var distinctes: Array = []
	for t in tailles:
		if not distinctes.has(t):
			distinctes.append(t)
	h.gt(distinctes.size(), 1, "audio.six: les six signaux ne sont pas tous identiques")
	h.eq(Bank.paires_identiques(), 0, "audio.six: aucun evenement n'emprunte le descripteur d'un autre")

	# UN MOMENT INCONNU ne joue rien et n'entre pas au journal.
	var avant: int = Audio.journal().size()
	var rien: Dictionary = Audio.jouer("son_absent", 2)
	h.eq(rien["joue"], false, "audio.six: un moment inconnu ne joue rien")
	h.eq(Audio.journal().size(), avant, "audio.six: il n'entre pas au journal")

	# LE TICK de declenchement est trace pour chacun.
	var sans_tick: int = 0
	for e in Audio.journal():
		if not e.has("tick"):
			sans_tick += 1
	h.eq(sans_tick, 0, "audio.six: chaque declenchement porte son tick")
	Audio.reinitialiser()
	h.eq(Audio.moments_joues().size(), 0, "audio.six: la remise a zero vide le journal")
