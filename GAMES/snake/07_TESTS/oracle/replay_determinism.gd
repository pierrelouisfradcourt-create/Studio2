# replay_determinism.gd — oracle de la ligne arch.determinism_replay. SceneTree headless :
# a etat initial, graine de spawn et sequence d'entrees identiques, deux executions
# produisent un etat final STRICTEMENT EGAL (egalite profonde sur tous les champs).
# Sortie : "FORGE_ORACLE replay_determinism {json}", exit 0 si vert.
extends SceneTree

const State = preload("res://05_SYSTEMS/game_state/state.gd")
const Loop = preload("res://05_SYSTEMS/game_loop/loop.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/bot_policy.gd")

const GRAINE := 12345
const TICKS := 400

# Joue une partie deterministe (bot sur canal public), renvoie l'etat final.
func _jouer(graine: int, ticks: int) -> Object:
	var s = State.initial(graine)
	var t := 0
	while t < ticks and s.statut == State.Statut.EN_COURS:
		var action: Vector2i = Bot.choisir_action(s)
		s = Loop.step(s, action)["etat"]
		t += 1
	return s

func _initialize() -> void:
	var fails: Array = []
	var a = _jouer(GRAINE, TICKS)
	var b = _jouer(GRAINE, TICKS)
	if not a.egal_profond(b):
		fails.append("deux executions identiques -> etats finaux differents")
	# Une graine DIFFERENTE doit produire un etat different (le replay depend bien de la
	# graine, pas une egalite triviale). Assertion anti-tautologie.
	var c = _jouer(GRAINE + 1, TICKS)
	if a.egal_profond(c):
		fails.append("graines differentes -> etats identiques (replay insensible a la graine)")
	print("FORGE_ORACLE replay_determinism " + JSON.stringify({
		"ok": fails.is_empty(), "fails": fails,
		"ticks_a": a.ticks, "score_a": a.score, "statut_a": a.statut,
	}))
	quit(0 if fails.is_empty() else 1)
