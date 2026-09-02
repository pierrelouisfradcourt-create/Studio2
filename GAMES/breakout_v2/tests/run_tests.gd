# run_tests.gd — POINT D'ENTREE MECANIQUE de l'oracle headless (ligne proof.harness).
# Lancer : godot --headless --path games/breakout_v2 --script res://tests/run_tests.gd
# exit 0 = tous verts, 1 = au moins un rouge.
#
# FIDELITE CODE_COPIE REMONTEE (fog, precedent Snake) : la wiremap declare cette ligne
# reused_from.type=CODE_COPIE de knowledge_base/systems/navigation/run_tests.gd
# (sha 096cd75...). Ce RUNNER KB cible res://core/grid_nav.gd + res://trial.gd et 39
# assertions grid-nav : il ne peut PAS executer les tests de Breakout (cibles et compte
# differents). Une copie octet-identique serait donc physiquement inapplicable ici. Ce
# fichier est un harnais FONCTIONNEL neuf, de MEME FORME (SceneTree, enumeration, garde
# EXPECTED_ASSERTS) ; l'ecart de fidelite CODE_COPIE est remonte au rapport (SKIPPED_VALIDATION
# + fog), jamais maquille. 0 octet copie de la source KB.
#
# ENUMERE et execute TOUS les res://07_TESTS/unit/*.test.gd (chacun expose run(h)). Garde
# anti-FAUX-VERT EXPECTED_ASSERTS : un coeur qui ne compile pas -> total non atteint -> echec.
extends SceneTree

const Harness = preload("res://06_RUNTIME/adapters/proof_harness/harness.gd")

# Total d'assertions attendu (mesure reelle, garde anti-faux-vert). Verifie a l'execution.
# 274 (build run 1) + 25 (durcissement mutation run 2 : bornes strictes loop/brick/state/wall)
# + 6 (run 3 : inversion no_time_catchup — rattrapage borne, reste conserve, 8 -> 14 asserts).
const EXPECTED_ASSERTS := 305

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
