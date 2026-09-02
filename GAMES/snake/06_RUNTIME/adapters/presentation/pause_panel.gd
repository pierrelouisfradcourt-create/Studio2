# pause_panel.gd — ligne render.pause_panel. Panneau de pause : quand le statut vaut
# en-pause, EXACTEMENT une mention de pause est lisible et le plateau reste affiche
# (l'overlay ne masque pas le jeu). Logique PURE, testable en headless ; le pilote de scene
# pose l'overlay. RefCounted.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/state.gd")

const MENTION_PAUSE := "Pause"

# Nombre de mentions de pause lisibles : EXACTEMENT 1 en pause, 0 sinon.
static func mentions_pause(statut: int) -> int:
	return 1 if statut == State.Statut.EN_PAUSE else 0

# Le plateau reste-t-il affiche ? Toujours vrai : l'overlay de pause ne remplace pas le jeu.
static func plateau_visible(_statut: int) -> bool:
	return true
