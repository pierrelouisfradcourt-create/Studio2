# demo_end_screen.gd — oracle du volet observable demo_end_screen (ligne render.end_screen).
# Protocole FORGE_ORACLE lu par product_oracle_godot.py. La logique testee n'est PAS modifiee :
# le test unitaire DEJA declare par la wiremap pour cette ligne (07_TESTS/unit/end_screen.test.gd
# — ecran de fin actif seulement en terminal, message distinct gagne/perdu, vide hors terminal)
# est instancie et rejoue tel quel ; seul le protocole de sortie change.
extends SceneTree

const Harness = preload("res://06_RUNTIME/adapters/proof_harness/harness.gd")
const T = preload("res://07_TESTS/unit/end_screen.test.gd")

func _initialize() -> void:
	var h = Harness.new()
	T.new().run(h)
	var ok: bool = h.failed == 0
	print("FORGE_ORACLE demo_end_screen " + JSON.stringify({"ok": ok, "fails": h.fails, "data": {"passed": h.passed, "failed": h.failed}}))
	quit(0 if ok else 1)
