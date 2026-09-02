# v2_params_rules_only.test.gd — ligne params.rules_only, capacites F96/F108.
# Le bloc de parametres PERD les grandeurs qui decrivent une carte : deuxieme cause
# mesuree de la baseline V1. Ne restent que les regles vraies pour TOUTES les cartes.
extends RefCounted

const P = preload("res://05_SYSTEMS/params/params.gd")
const ContentV2 = preload("res://06_RUNTIME/adapters/content_provider/content_provider.gd")


func run(h) -> void:
	var f := FileAccess.open("res://05_SYSTEMS/params/params.gd", FileAccess.READ)
	h.ok(f != null, "params.rules: le bloc de parametres est lisible")
	var texte: String = f.get_as_text() if f != null else ""

	# GRANDEURS DE CARTE : absentes du bloc, comptage a 0.
	var restantes: int = 0
	for nom in ["LARGEUR_GRILLE", "HAUTEUR_GRILLE", "LIGNE_TUNNEL", "LABY_PREMIERE_LIGNE", "LABY_DERNIERE_LIGNE"]:
		if texte.contains("const " + nom):
			restantes += 1
	h.eq(restantes, 0, "params.rules: aucune grandeur de carte ne reste dans le bloc")

	# REGLES DE JEU : toujours presentes, et vraies pour toutes les cartes.
	h.eq(P.POINTS_PASTILLE, 10, "params.rules: bareme de pastille")
	h.eq(P.POINTS_SUPER, 50, "params.rules: bareme de super-pastille")
	h.eq(P.VALEURS_CAPTURE.size(), 4, "params.rules: quatre valeurs de capture")
	# TRIAGE V6 : DECISION_OBSOLETE. `VIES_INITIALES` figeait UN nombre de vies unique ;
	# depuis la decision Pierre du 2026-08-06 le mode de jeu gouverne les vies, et un
	# nombre unique serait FAUX dans l'un des deux modes. La constante a disparu, donc
	# l'assertion qui la figeait aussi. Elle est REMPLACEE, jamais affaiblie : deux
	# egalites strictes sur litteral la ou il y en avait une, plus la garde d'ordre qui
	# interdit d'inverser les deux valeurs par accident.
	h.eq(P.VIES_MODE_DEFI, 3, "params.rules: vies du mode du defi")
	h.eq(P.VIES_MODE_MARGE, 5, "params.rules: vies du mode de la marge d'erreur")
	h.gt(P.VIES_MODE_MARGE, P.VIES_MODE_DEFI, "params.rules: la marge est strictement plus genereuse")
	h.eq(texte.contains("const VIES_INITIALES"), false, "params.rules: l'ancienne constante unique a disparu")
	h.eq(P.DELAIS_SORTIE_MAISON.size(), 4, "params.rules: quatre delais de sortie")
	h.eq(P.DUREE_EFFRAYE_TICKS, 40, "params.rules: duree de la fenetre Effraye")
	h.eq(P.PAS_NORMAL, 1, "params.rules: budget de pas normal")
	h.gt(P.PAS_DASH, P.PAS_NORMAL, "params.rules: le budget de dash est strictement superieur")
	h.gt(P.RECHARGE_DASH_TICKS, 0, "params.rules: delai de recharge declare")

	# La cadence du bloc est un REPLI, pas la valeur effective d'un niveau : les valeurs
	# effectives vivent dans le catalogue.
	h.eq(P.CADENCE_FANTOME_PERIODE, 20, "params.rules: cadence de repli declaree")
	var differentes: int = 0
	for i in range(ContentV2.nb_niveaux()):
		if ContentV2.cadence(i) != P.CADENCE_FANTOME_PERIODE:
			differentes += 1
	h.gt(differentes, 0, "params.rules: au moins un niveau declare une cadence propre")
	h.eq(texte.contains("CADENCE_PAR_NIVEAU"), false, "params.rules: aucune table indexee par niveau")
