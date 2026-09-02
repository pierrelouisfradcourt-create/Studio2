# demo_immediate_start.gd — oracle du volet observable demo_immediate_start (ligne
# runtime.immediate_start). Protocole FORGE_ORACLE lu par scripts/forge/product_oracle_godot.py.
# La logique testee n'est PAS modifiee : le test unitaire DEJA declare par la wiremap pour cette
# ligne (07_TESTS/unit/boot_zero_gesture.test.gd — 0 geste/0 ecran avant le jeu, balle en
# mouvement des le boot) est instancie et rejoue tel quel ; seul le protocole de sortie change.
extends SceneTree

const Harness = preload("res://06_RUNTIME/adapters/proof_harness/harness.gd")
const T = preload("res://07_TESTS/unit/boot_zero_gesture.test.gd")

func _initialize() -> void:
	var h = Harness.new()
	T.new().run(h)
	var ok: bool = h.failed == 0
	print("FORGE_ORACLE demo_immediate_start " + JSON.stringify({"ok": ok, "fails": h.fails, "data": {"passed": h.passed, "failed": h.failed}}))
	quit(0 if ok else 1)
