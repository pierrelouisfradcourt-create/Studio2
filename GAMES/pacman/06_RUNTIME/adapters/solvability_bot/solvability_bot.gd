# solvability_bot.gd — SOLVABILITE CARTE PAR CARTE (ligne bot.solvability_per_map).
#
# Le bot planifie l'itineraire de collecte de TOUS les collectibles de la carte
# COURANTE, quelle que soit la carte, et emet des INTENTIONS sur le meme canal que le
# joueur, dans un budget de ticks DECLARE. Il ne calcule aucun deplacement lui-meme : il
# demande, le jeu decide.
#
# Les CARTES lui sont REMISES en argument : ce module n'ouvre aucun fichier et n'enumere
# aucun contenu. Une deuxieme carte non prouvee solvable serait un jeu injouable certifie.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const Driver = preload("res://06_RUNTIME/adapters/solvability_bot/bot_driver.gd")
const Verdict = preload("res://06_RUNTIME/adapters/solvability_bot/verdict.gd")

# Budget de ticks DECLARE par essai. Valeur du run V1, conservee : elle borne l'essai,
# elle ne le facilite pas.
const BUDGET_DEFAUT: int = 20000


# Joue UNE carte depuis une graine et rend le verdict de solvabilite de CETTE carte.
static func jouer_carte(carte, graine: int, budget: int = BUDGET_DEFAUT, cadence: int = 0) -> Dictionary:
	if carte == null:
		return {
			"succeeded": false, "ticks": null, "carte": "",
			"libelle": Verdict.LIBELLE_INJOUABLE, "consommees": 0, "total_pose": 0,
			"statut": State.Statut.PERDU,
		}
	var partie: Dictionary = Driver.jouer_depuis_graine(carte, graine, budget, cadence)
	var evaluation: Dictionary = Verdict.evaluer(partie["etat"], partie["ticks"])
	evaluation["carte"] = carte.ID
	return evaluation


# SELECTION DE CARTE PAR LA GRAINE : l'essai numero `graine` exerce la carte d'index
# (graine - 1) modulo le nombre de cartes du catalogue. Les 50 essais de l'oracle
# couvrent ainsi REELLEMENT chaque carte, au lieu de rejouer cinquante fois la premiere.
static func index_de_la_graine(graine: int, nb_cartes: int) -> int:
	if nb_cartes <= 0:
		return 0
	var i: int = (graine - 1) % nb_cartes
	if i < 0:
		i += nb_cartes
	return i


# Nombre d'essais qui echoient a chaque carte pour un nombre d'essais donne : sert a
# constater que la couverture est EFFECTIVE, et non seulement declaree.
static func repartition(nb_essais: int, nb_cartes: int) -> Array:
	var sortie: Array = []
	for _i in range(max(nb_cartes, 0)):
		sortie.append(0)
	for graine in range(1, nb_essais + 1):
		var i: int = index_de_la_graine(graine, nb_cartes)
		if i < sortie.size():
			sortie[i] += 1
	return sortie


# Nombre de cartes du catalogue QUE AUCUN essai n'exerce. Attendu : exactement 0.
static func cartes_non_exercees(nb_essais: int, nb_cartes: int) -> int:
	var n: int = 0
	for c in repartition(nb_essais, nb_cartes):
		if c == 0:
			n += 1
	return n
