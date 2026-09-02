# harness.gd — ligne proof.harness (glue NEUVE, declaree telle : le RUNNER copie vit dans
# tests/run_tests.gd). Helper de test partage : compteur d'assertions (garde anti-FAUX-VERT
# du patron chess_tcg). Chaque 07_TESTS/unit/*.test.gd recoit une instance et appelle ok()/eq().
# RefCounted : aucune API de moteur, utilisable en headless.
extends RefCounted

var passed: int = 0
var failed: int = 0
var fails: Array = []

func ok(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		fails.append(name)

# Egalite STRICTE (jamais un >=). Trace la valeur observee en cas d'echec.
func eq(a, b, name: String) -> void:
	if a == b:
		passed += 1
	else:
		failed += 1
		fails.append("%s (attendu %s, obtenu %s)" % [name, str(b), str(a)])
