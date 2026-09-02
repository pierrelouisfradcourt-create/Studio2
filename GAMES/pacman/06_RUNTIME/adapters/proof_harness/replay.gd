# replay.gd — rejeu d'une suite d'appuis depuis une graine et comparaison de deux traces
# CHAMP PAR CHAMP (ligne harness.replay_determinism).
# Mesure depuis l'ETAT EXPOSE (game_state/observable.gd) : il ne rappelle jamais les
# systemes qu'il mesure pour recalculer ce qu'il devrait constater.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/game_loop.gd")
const Observable = preload("res://05_SYSTEMS/game_state/observable.gd")
const Chase = preload("res://05_SYSTEMS/chase_state/chase_state.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")

# Fenetre de rejeu : elle DOIT franchir au moins deux seuils de la sequence d'etats.
# Le deuxieme seuil tombe a 180 ticks ; 400 le franchit largement.
const FENETRE_REJEU: int = 400
const GRAINE_REJEU: int = 7


# Enregistre une partie : rend la suite d'APPUIS emis et la trace des releves exposes.
static func enregistrer(carte, graine: int, fenetre: int) -> Dictionary:
	var s = State.initial(carte, graine)
	var appuis: Array = []
	var trace: Array = [Observable.projeter(s)]
	var t: int = 0
	while t < fenetre and s.statut == State.Statut.EN_COURS:
		var action: Vector2i = Bot.choisir_action(s)
		appuis.append(action)
		s = Loop.step(s, action)["etat"]
		trace.append(Observable.projeter(s))
		t += 1
	return {"appuis": appuis, "trace": trace, "etat": s}


# Rejoue une suite d'appuis DEJA enregistree depuis la meme graine.
static func rejouer(carte, graine: int, appuis: Array) -> Dictionary:
	var s = State.initial(carte, graine)
	var trace: Array = [Observable.projeter(s)]
	for action in appuis:
		if s.statut != State.Statut.EN_COURS:
			break
		s = Loop.step(s, action)["etat"]
		trace.append(Observable.projeter(s))
	return {"trace": trace, "etat": s}


# Compare deux traces champ par champ. Rend le nombre de champs divergents et le
# premier point de divergence — jamais un simple booleen.
static func comparer(a: Array, b: Array) -> Dictionary:
	if a.size() != b.size():
		return {"divergences": 1, "premier": 0, "raison": "longueurs %d vs %d" % [a.size(), b.size()]}
	var divergences: int = 0
	var premier: int = -1
	for i in range(a.size()):
		for cle in Observable.CLES:
			if a[i].get(cle) != b[i].get(cle):
				divergences += 1
				if premier < 0:
					premier = i
	return {"divergences": divergences, "premier": premier, "raison": ""}


# Nombre de seuils de la sequence d'etats franchis par une trace : c'est ce qui rend la
# fenetre de rejeu QUALIFIANTE, plutot que declaree assez longue.
static func seuils_franchis(trace: Array) -> int:
	var n: int = 0
	for seuil in Chase.seuils():
		if trace.size() > seuil:
			n += 1
	return n


# La mesure complete : enregistrer, rejouer, comparer.
static func mesurer(carte) -> Dictionary:
	var premier: Dictionary = enregistrer(carte, GRAINE_REJEU, FENETRE_REJEU)
	var second: Dictionary = rejouer(carte, GRAINE_REJEU, premier["appuis"])
	var comparaison: Dictionary = comparer(premier["trace"], second["trace"])
	return {
		"divergences": comparaison["divergences"],
		"premier": comparaison["premier"],
		"raison": comparaison["raison"],
		"seuils_franchis": seuils_franchis(premier["trace"]),
		"score_a": premier["etat"].score,
		"score_b": second["etat"].score,
		"statut_a": premier["etat"].statut,
		"statut_b": second["etat"].statut,
	}
