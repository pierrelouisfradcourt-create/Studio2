# run_tests.gd — POINT D'ENTREE MECANIQUE au chemin EXIGE par l'oracle maitre.
# godot_oracle.mjs:17 charge `res://tests/run_tests.gd` (chemin impose par le moteur,
# categorie godot.project_tests -> tests/{id} dans repo_map.yaml). Ligne proof.harness.
#
# NON-DUPLICATION : ce fichier ne recopie PAS la garde anti-faux-vert. Il DELEGUE au
# harnais fonctionnel deja depose et prouve (res://07_TESTS/oracle/run_tests.gd, categorie
# test.oracle) : meme Harness, meme dossier de tests, et la constante EXPECTED_ASSERTS est
# LUE du harnais canonique (jamais recopiee) pour interdire toute derive du total.
#
# CE FICHIER N'EST PAS la copie octet-identique de la brique KB grid_nav
# (knowledge_base/systems/navigation/run_tests.gd, sha 096cd75...) : cette brique cible
# res://core/grid_nav.gd + res://trial.gd et 39 assertions grid-nav — elle ne peut pas
# executer les 282 assertions de Snake. La forme CODE_COPIE declaree pour cette ligne est
# donc physiquement inapplicable ici ; l'ecart est remonte en fog HumanGate (voir wiremap
# proof.harness.reason et le rapport final, section SKIPPED_VALIDATION).
extends SceneTree

const Harness = preload("res://06_RUNTIME/adapters/proof_harness/harness.gd")
const OracleTests = preload("res://07_TESTS/oracle/run_tests.gd")

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
	# Garde anti-faux-vert : total attendu LU du harnais canonique, jamais recopie ici.
	var attendu: int = OracleTests.EXPECTED_ASSERTS
	if total != attendu:
		h.failed += 1
		h.fails.append("META: %d/%d assertions executees (coeur non charge ? test manquant ?)" % [total, attendu])

	print("\n=== RESULT: %d passed, %d failed (fichiers: %d) ===" % [h.passed, h.failed, fichiers.size()])
	for x in h.fails:
		print("  FAIL: ", x)
	quit(0 if h.failed == 0 else 1)
