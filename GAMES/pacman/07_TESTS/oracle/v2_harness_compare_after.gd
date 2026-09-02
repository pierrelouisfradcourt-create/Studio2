# v2_harness_compare_after.gd — ligne harness.compare_after, capacite F117.
# Le MEME oracle est releve APRES les ajouts V2 : aucune assertion ne tombe, le nombre
# d'assertions passantes NE DIMINUE PAS, et la contre-epreuve de solvabilite conserve
# son resultat. La comparaison porte sur deux sorties, pas sur deux souvenirs.
extends RefCounted

const Baseline = preload("res://06_RUNTIME/adapters/proof_harness/harness_oracle_baseline.gd")
const Bot = preload("res://06_RUNTIME/adapters/solvability_bot/solvability_bot.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")


func run(h) -> void:
	var m: Dictionary = Baseline.mesurer()
	h.gt(m["assertions_apres"], 0, "harness.apres: le nombre attendu courant est lisible")
	h.eq(m["non_diminue"], true, "harness.apres: le nombre d'assertions ne diminue pas")
	h.eq(Baseline.assertions_non_diminuees(), true, "harness.apres: propriete verifiee directement")
	h.ok(m["assertions_apres"] >= m["baseline"]["assertions"],
		"harness.apres: strictement superieur ou egal a la baseline")

	# LES ASSERTIONS V1 SONT CONSERVEES, et d'autres s'ajoutent.
	h.gt(m["assertions_apres"], m["baseline"]["assertions"],
		"harness.apres: des assertions ont ete ajoutees, aucune n'a disparu")

	# LA CONTRE-EPREUVE DE SOLVABILITE conserve son resultat, et l'ETEND : le meme nombre
	# d'essais couvre desormais CHAQUE carte du catalogue au lieu d'une seule.
	h.eq(Bot.cartes_non_exercees(m["baseline"]["essais"], ContentV2.nb_niveaux()), 0,
		"harness.apres: les 50 essais exercent chaque carte")
	h.gt(ContentV2.nb_niveaux(), m["baseline"]["cartes_exercees"],
		"harness.apres: la couverture de cartes a strictement augmente")
	var repartition: Array = Bot.repartition(m["baseline"]["essais"], ContentV2.nb_niveaux())
	var somme: int = 0
	for r in repartition:
		somme += int(r)
	h.eq(somme, m["baseline"]["essais"], "harness.apres: le budget d'essais est inchange")
	h.eq(repartition.size(), ContentV2.nb_niveaux(), "harness.apres: une part par carte")

	# LE HARNAIS LU est bien celui qui s'execute.
	h.eq(Baseline.CHEMIN_HARNAIS, "res://tests/run_tests.gd", "harness.apres: le harnais lu est le harnais du jeu")
