# demo_lives_score.gd — oracle du volet observable demo_lives_score (ligne render.hud_lives_score).
# Protocole FORGE_ORACLE lu par product_oracle_godot.py. La logique testee n'est PAS modifiee :
# le test unitaire DEJA declare par la wiremap pour cette ligne (07_TESTS/unit/hud_readout.test.gd
# — round-trip strict texte<->valeur pour vies et score) est instancie et rejoue tel quel ; seul
# le protocole de sortie change.
extends SceneTree

const Harness = preload("res://06_RUNTIME/adapters/proof_harness/harness.gd")
const T = preload("res://07_TESTS/unit/hud_readout.test.gd")

func _initialize() -> void:
	var h = Harness.new()
	T.new().run(h)
	var ok: bool = h.failed == 0
	print("FORGE_ORACLE demo_lives_score " + JSON.stringify({"ok": ok, "fails": h.fails, "data": {"passed": h.passed, "failed": h.failed}}))
	quit(0 if ok else 1)
