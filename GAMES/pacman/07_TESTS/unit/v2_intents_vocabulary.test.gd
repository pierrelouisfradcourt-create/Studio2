# v2_intents_vocabulary.test.gd — ligne intents.vocabulary, capacites F75/F80.
# Le vocabulaire FERME des intentions est la SEULE entree de la logique. Aucun code de
# touche, aucun bouton, aucun contact n'existe ici — c'est cette absence, comptable
# statiquement, qui rend l'invariant falsifiable au lieu d'etre redactionnel.
extends RefCounted

const Intents = preload("res://05_SYSTEMS/input_intents/input_intents.gd")
const Purity = preload("res://06_RUNTIME/adapters/proof_harness/harness_purity_counts.gd")


func run(h) -> void:
	# VOCABULAIRE FERME, exclusif et exhaustif.
	h.eq(Intents.TOUTES.size(), 11, "intents.vocab: onze intentions declarees")
	h.eq(Intents.DIRECTIONS.size(), 4, "intents.vocab: quatre intentions de direction")
	h.eq(Intents.COMMANDES.size(), 6, "intents.vocab: six intentions de commande")
	h.eq(Intents.NOMS.size(), Intents.TOUTES.size(), "intents.vocab: un nom par intention")
	var doublons: int = 0
	for i in range(Intents.TOUTES.size()):
		for j in range(i + 1, Intents.TOUTES.size()):
			if Intents.TOUTES[i] == Intents.TOUTES[j]:
				doublons += 1
	h.eq(doublons, 0, "intents.vocab: aucune intention en double")

	# Direction et commande sont DISJOINTES.
	var chevauchement: int = 0
	for d in Intents.DIRECTIONS:
		if Intents.est_commande(d):
			chevauchement += 1
	h.eq(chevauchement, 0, "intents.vocab: aucune direction n'est une commande")
	h.eq(Intents.est_direction(Intents.Intention.DASH), false, "intents.vocab: le dash n'est pas une direction")
	h.eq(Intents.est_commande(Intents.Intention.DASH), true, "intents.vocab: le dash est une commande")
	h.eq(Intents.valide(Intents.Intention.PAUSE), true, "intents.vocab: la pause appartient au vocabulaire")
	h.eq(Intents.valide(99), false, "intents.vocab: une valeur hors vocabulaire est refusee")

	# RANG : l'unique point de contact avec l'ordre fixe des directions.
	h.eq(Intents.rang_direction(Intents.Intention.HAUT), 0, "intents.vocab: rang du haut")
	h.eq(Intents.rang_direction(Intents.Intention.GAUCHE), 1, "intents.vocab: rang de la gauche")
	h.eq(Intents.rang_direction(Intents.Intention.BAS), 2, "intents.vocab: rang du bas")
	h.eq(Intents.rang_direction(Intents.Intention.DROITE), 3, "intents.vocab: rang de la droite")
	h.eq(Intents.rang_direction(Intents.Intention.PAUSE), Intents.RANG_ABSENT,
		"intents.vocab: une commande n'a pas de rang de direction")
	h.eq(Intents.direction_du_rang(0), Intents.Intention.HAUT, "intents.vocab: rang 0 rend le haut")
	h.eq(Intents.direction_du_rang(4), Intents.Intention.AUCUNE, "intents.vocab: hors bornes rend AUCUNE")
	h.eq(Intents.direction_du_rang(-1), Intents.Intention.AUCUNE, "intents.vocab: rang negatif rend AUCUNE")
	h.eq(Intents.nom(Intents.Intention.DASH), "DASH", "intents.vocab: nom lisible")

	# COMPTAGE STATIQUE : aucune API d'entree de la plateforme dans 05_SYSTEMS.
	h.eq(Purity.entree_dans_logique().size(), 0,
		"intents.vocab: 0 fichier de logique reference une API d'entree")
	# CONTROLE POSITIF : les memes references SONT trouvees dans 06_RUNTIME.
	h.gt(Purity.entree_dans_runtime().size(), 0,
		"intents.vocab: le controle positif trouve ces references dans le runtime")
	# --- GATE MUTATION : le rang EGAL a la taille est hors bornes --------------------
	h.eq(Intents.direction_du_rang(Intents.DIRECTIONS.size()), Intents.Intention.AUCUNE,
		"intents.vocab: un rang egal a la taille est hors bornes")
	h.eq(Intents.direction_du_rang(Intents.DIRECTIONS.size() - 1), Intents.Intention.DROITE,
		"intents.vocab: le dernier rang valide rend bien la derniere direction")
	h.eq(Intents.direction_du_rang(3), Intents.Intention.DROITE, "intents.vocab: rang 3 = droite")
	h.eq(Intents.nom(99), "AUCUNE", "intents.vocab: une intention inconnue retombe sur un nom declare")
