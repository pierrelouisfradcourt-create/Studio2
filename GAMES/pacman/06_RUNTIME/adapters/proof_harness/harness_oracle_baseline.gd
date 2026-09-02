# harness_oracle_baseline.gd — BASELINE AVANT / COMPARAISON APRES
# (lignes harness.baseline_before, harness.compare_after).
#
# ORDRE IMPOSE ET RESPECTE : le releve AVANT a ete pris par execution reelle de
# `node scripts/forge/godot_oracle.mjs games/pacman` AVANT la premiere ecriture de code
# V2 — pris apres, il ne mesurerait plus une baseline. Les valeurs ci-dessous sont CE
# RELEVE, recopie ici pour devenir comparable mecaniquement ; ce ne sont PAS les chiffres
# transmis par le charter (declares TRANSMIS_NON_REMESURES), mais une mesure de ce poste.
#
# SORTIE BRUTE DU RELEVE AVANT (2026-08-05, exit code 0) :
#   === RESULT: 1012 passed, 0 failed (fichiers: 65) ===
#   {"project":"games/pacman","trials":50,"won":50,"lost":0,"failed_seeds":[],"verdict":"OK"}
#
# La comparaison APRES ne se fait pas sur deux souvenirs : le nombre d'assertions attendu
# est LU dans le harnais de test (tests/run_tests.gd), et la couverture de solvabilite
# est LUE dans le catalogue et le selecteur de carte.
extends RefCounted

const CHEMIN_HARNAIS := "res://tests/run_tests.gd"
const MARQUEUR_ATTENDU := "const EXPECTED_ASSERTS := "

# --- RELEVE AVANT (mesure, jamais transmis) ---
const BASELINE_ASSERTIONS: int = 1012
const BASELINE_ECHECS: int = 0
const BASELINE_FICHIERS: int = 65
const BASELINE_ESSAIS: int = 50
const BASELINE_VICTOIRES: int = 50
const BASELINE_EXIT: int = 0
const BASELINE_CARTES_EXERCEES: int = 1


static func baseline() -> Dictionary:
	return {
		"assertions": BASELINE_ASSERTIONS,
		"echecs": BASELINE_ECHECS,
		"fichiers": BASELINE_FICHIERS,
		"essais": BASELINE_ESSAIS,
		"victoires": BASELINE_VICTOIRES,
		"exit": BASELINE_EXIT,
		"cartes_exercees": BASELINE_CARTES_EXERCEES,
	}


# Nombre d'assertions ATTENDU par le harnais courant, LU dans son texte : la valeur
# n'est pas recopiee ici, elle est relue a chaque execution.
static func assertions_attendues() -> int:
	var f := FileAccess.open(CHEMIN_HARNAIS, FileAccess.READ)
	if f == null:
		return -1
	var t: String = f.get_as_text()
	f.close()
	var i: int = t.find(MARQUEUR_ATTENDU)
	if i < 0:
		return -1
	var reste: String = t.substr(i + MARQUEUR_ATTENDU.length())
	var chiffres := ""
	for k in range(reste.length()):
		var c: String = reste[k]
		if c >= "0" and c <= "9":
			chiffres += c
		else:
			break
	if chiffres.is_empty():
		return -1
	return int(chiffres)


# COMPARAISON : le nombre d'assertions attendues ne DIMINUE pas. Une baisse signalerait
# qu'une preuve V1 a disparu au lieu d'avoir ete conservee.
static func assertions_non_diminuees() -> bool:
	var apres: int = assertions_attendues()
	if apres < 0:
		return false
	return apres >= BASELINE_ASSERTIONS


static func mesurer() -> Dictionary:
	return {
		"baseline": baseline(),
		"assertions_apres": assertions_attendues(),
		"non_diminue": assertions_non_diminuees(),
	}
