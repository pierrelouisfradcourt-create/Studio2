# harness.gd — helper de test partage (ligne proof.harness, volet enumerateur).
# Porte la garde anti-FAUX-VERT du patron chess_tcg : le compteur d'assertions.
# Chaque fichier 07_TESTS/unit/*.test.gd recoit une instance et appelle ok().
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

func eq(a, b, name: String) -> void:
	# Egalite STRICTE (jamais un >=). Trace la valeur observee en cas d'echec.
	if a == b:
		passed += 1
	else:
		failed += 1
		fails.append("%s (attendu %s, obtenu %s)" % [name, str(b), str(a)])
