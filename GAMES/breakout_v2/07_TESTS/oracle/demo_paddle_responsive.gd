# demo_paddle_responsive.gd — oracle du volet observable demo_paddle_responsive (ligne
# input.paddle_responsive). Protocole FORGE_ORACLE lu par product_oracle_godot.py. La logique
# testee n'est PAS modifiee : le test unitaire DEJA declare par la wiremap pour cette ligne
# (07_TESTS/unit/paddle_latency.test.gd — deplacement DES le meme tick=latence 0, gauche/droite
# distincts, AUCUNE immobile) est instancie et rejoue tel quel ; seul le protocole de sortie change.
extends SceneTree

const Harness = preload("res://06_RUNTIME/adapters/proof_harness/harness.gd")
const T = preload("res://07_TESTS/unit/paddle_latency.test.gd")

func _initialize() -> void:
	var h = Harness.new()
	T.new().run(h)
	var ok: bool = h.failed == 0
	print("FORGE_ORACLE demo_paddle_responsive " + JSON.stringify({"ok": ok, "fails": h.fails, "data": {"passed": h.passed, "failed": h.failed}}))
	quit(0 if ok else 1)
