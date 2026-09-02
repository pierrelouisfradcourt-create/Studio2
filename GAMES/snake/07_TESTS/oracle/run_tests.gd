# run_tests.gd — ORACLE MECANIQUE headless (ligne proof.harness, point d'entree).
# Lancer : godot --headless --path games/snake --script res://07_TESTS/oracle/run_tests.gd
#
# EMPLACEMENT FORCE, remonte au rapport : la wiremap declare ce point d'entree a
# `tests/run_tests.gd` (godot.project_tests) mais la permission de dispatch DENIE toute
# ecriture sous `tests/**` (meme glob que la zone protegee studio). Le point d'entree
# est donc depose ici, dans le dossier test.oracle declare. Ligne proof.harness /
# tests/run_tests.gd = BLOCKED(permission). Voir SKIPPED_VALIDATION + fog.
#
# ENUMERE et execute TOUS les res://07_TESTS/unit/*.test.gd. Garde anti-FAUX-VERT
# EXPECTED_ASSERTS du patron chess_tcg : un coeur qui ne compile pas -> total non
# atteint -> echec force. exit 0 = tous verts ; 1 = au moins un rouge.
extends SceneTree

const Harness = preload("res://06_RUNTIME/adapters/proof_harness/harness.gd")

# Mesure reelle : 26 fichiers de tests unitaires, 282 assertions (2026-07-28, reprise s9r
# — +7 fichiers adaptateurs runtime/presentation : no_time_catchup, boot_zero_gesture,
# exit_stop, grid_categories, hud_readout, end_screen, pause_panel ; +2 assertions bornes-Y
# nourriture dans state_status pour fermer les mutants state.gd:88).
const EXPECTED_ASSERTS := 282

func _initialize() -> void:
	var h = Harness.new()
	var dossier := "res://07_TESTS/unit"
	var da := DirAccess.open(dossier)
	if da == null:
		push_error("Dossier de tests introuvable : " + dossier)
		quit(1)
		return
	var fichiers: Array = []
	da.list_dir_begin()
	var nom := da.get_next()
	while nom != "":
		if not da.current_is_dir() and nom.ends_with(".test.gd"):
			fichiers.append(nom)
		nom = da.get_next()
	da.list_dir_end()
	fichiers.sort()  # ordre deterministe, jamais dependant du systeme de fichiers

	for f in fichiers:
		var chemin: String = dossier + "/" + f
		var script = load(chemin)
		if script == null or not (script is GDScript) or not script.can_instantiate():
			h.failed += 1
			h.fails.append("CHARGEMENT: %s introuvable/illisible/non compilable" % chemin)
			continue
		var inst = script.new()
		if not inst.has_method("run"):
			h.failed += 1
			h.fails.append("CONTRAT: %s n'expose pas run(h)" % f)
			continue
		inst.run(h)

	var total: int = h.passed + h.failed
	if total != EXPECTED_ASSERTS:
		h.failed += 1
		h.fails.append("META: %d/%d assertions executees (coeur non charge ? test manquant ?)" % [total, EXPECTED_ASSERTS])

	print("\n=== RESULT: %d passed, %d failed (fichiers: %d) ===" % [h.passed, h.failed, fichiers.size()])
	for x in h.fails:
		print("  FAIL: ", x)
	quit(0 if h.failed == 0 else 1)
