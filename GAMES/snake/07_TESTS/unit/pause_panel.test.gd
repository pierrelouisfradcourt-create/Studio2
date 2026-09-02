# pause_panel.test.gd — ligne render.pause_panel. En pause, EXACTEMENT 1 mention de pause
# est lisible et le plateau reste affiche ; hors pause, 0 mention. Testable en headless.
extends RefCounted

const PP = preload("res://06_RUNTIME/adapters/presentation/pause_panel.gd")
const State = preload("res://05_SYSTEMS/game_state/state.gd")

func run(h) -> void:
	h.eq(PP.mentions_pause(State.Statut.EN_PAUSE), 1, "en pause : EXACTEMENT 1 mention")
	h.eq(PP.mentions_pause(State.Statut.EN_COURS), 0, "en cours : 0 mention")
	h.eq(PP.mentions_pause(State.Statut.TERMINE_PERDU), 0, "terminal : 0 mention")
	h.ok(PP.plateau_visible(State.Statut.EN_PAUSE), "plateau reste visible en pause")
