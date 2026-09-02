# v2_harness_baseline_before.gd — ligne harness.baseline_before, capacite F116.
# Le releve AVANT a ete pris par execution reelle de l'oracle du jeu AVANT la premiere
# ecriture de code V2 — pris apres, il ne mesurerait plus une baseline. Les chiffres du
# charter (declares TRANSMIS_NON_REMESURES) sont remplaces par CETTE mesure.
extends RefCounted

const Baseline = preload("res://06_RUNTIME/adapters/proof_harness/harness_oracle_baseline.gd")


func run(h) -> void:
	var b: Dictionary = Baseline.baseline()
	h.eq(b["assertions"], 1012, "harness.baseline: 1012 assertions relevees AVANT")
	h.eq(b["echecs"], 0, "harness.baseline: 0 echec releve AVANT")
	h.eq(b["fichiers"], 65, "harness.baseline: 65 fichiers de preuve releves AVANT")
	h.eq(b["essais"], 50, "harness.baseline: 50 essais de solvabilite AVANT")
	h.eq(b["victoires"], 50, "harness.baseline: 50 victoires AVANT")
	h.eq(b["exit"], 0, "harness.baseline: code de retour nul AVANT")
	h.eq(b["cartes_exercees"], 1, "harness.baseline: une seule carte exercee AVANT")

	# LE RELEVE est JOINT au module, donc relisible : ce n'est pas un souvenir.
	var f := FileAccess.open("res://06_RUNTIME/adapters/proof_harness/harness_oracle_baseline.gd", FileAccess.READ)
	h.ok(f != null, "harness.baseline: le releve est joint et lisible")
	var texte: String = f.get_as_text() if f != null else ""
	h.eq(texte.contains("=== RESULT: 1012 passed, 0 failed (fichiers: 65) ==="), true,
		"harness.baseline: la sortie brute du releve AVANT est jointe")
	h.eq(texte.contains('"won":50'), true, "harness.baseline: la sortie brute de solvabilite est jointe")
	h.eq(texte.contains("TRANSMIS_NON_REMESURES"), true,
		"harness.baseline: le statut des chiffres transmis est nomme")

	# LA VALEUR ATTENDUE COURANTE est LUE dans le harnais, pas recopiee.
	h.gt(Baseline.assertions_attendues(), 0, "harness.baseline: la valeur courante est relue")
