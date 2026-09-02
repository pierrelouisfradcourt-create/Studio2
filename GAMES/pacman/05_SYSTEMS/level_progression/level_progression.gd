# level_progression.gd — BASCULE DE NIVEAU (lignes progression.level_switch,
# progression.carry_score_lives, progression.reset_rest, progression.final_state).
#
# La bascule est une TRANSFORMATION D'ETAT dans la MEME execution : jamais une relance
# de l'application, jamais un retour force au titre.
#
# Ce module declare EXACTEMENT ce qui traverse la bascule et ce qui repart. Les deux
# declarations sont complementaires : ensemble elles ferment la question « qu'est-ce qui
# survit ? » sans zone grise.
#
# Logique PURE. Ne depend que de params et game_state.
extends RefCounted

const State = preload("res://05_SYSTEMS/game_state/game_state.gd")
const P = preload("res://05_SYSTEMS/params/params.gd")

# CE QUI SURVIT a une bascule de niveau, nomme.
const CONSERVES: Array = ["score", "vies"]
# CE QUI REPART, nomme. Complementaire strict du precedent.
const REINITIALISES: Array = [
	"pastilles", "consommees", "total_pose", "pac", "fantomes",
	"horloge", "effraye_restant", "rang_capture", "rng_etat", "ticks",
]

# Vocabulaire ferme des issues d'une carte videe.
const SUITE_NIVEAU_SUIVANT := "niveau_suivant"
const SUITE_CATALOGUE_TERMINE := "catalogue_termine"


# La carte courante est-elle videe ? Egalite STRICTE, jamais un >=.
static func carte_videe(s) -> bool:
	return s.consommees == s.total_pose


# Le niveau courant est-il le DERNIER du catalogue ? `nb_niveaux` est REMIS par
# l'appelant qui lit le catalogue : ce module n'enumere aucune carte.
static func dernier_niveau(niveau: int, nb_niveaux: int) -> bool:
	return niveau >= nb_niveaux


# Issue d'une carte videe : niveau suivant, ou etat FINAL EXPLICITE quand la derniere
# carte du catalogue est terminee. Le catalogue epuise est un CAS NOMME, jamais un
# indice hors bornes ni un blocage.
static func suite(s, nb_niveaux: int) -> String:
	if dernier_niveau(s.niveau, nb_niveaux):
		return SUITE_CATALOGUE_TERMINE
	return SUITE_NIVEAU_SUIVANT


# BASCULE : construit l'etat du niveau suivant sur la CARTE REMISE en argument. Le score
# et les vies SURVIVENT ; tout le reste repart au niveau de la carte suivante —
# collectibles au total de la nouvelle carte, positions de depart de la nouvelle carte,
# horloge a sa phase initiale, rang de capture a sa premiere valeur, generateur reseede
# a la graine DECLAREE du niveau.
static func basculer(s, carte_suivante, cadence_suivante: int, graine_partie: int) -> Object:
	var niveau_suivant: int = s.niveau + 1
	var reglages: Dictionary = {"mode": s.mode, "dash_actif": s.dash_actif}
	var suite_etat = State.initial(
		carte_suivante,
		State.graine_du_niveau(graine_partie, niveau_suivant),
		cadence_suivante,
		reglages)
	suite_etat.niveau = niveau_suivant
	# Les DEUX seules grandeurs qui traversent la bascule.
	suite_etat.score = s.score
	suite_etat.vies = s.vies
	return suite_etat


# ETAT FINAL EXPLICITE : la partie est GAGNEE, definitivement, quand la derniere carte
# du catalogue est terminee. L'etat rendu est un clone — l'entree n'est jamais mutee.
static func etat_final(s) -> Object:
	var f = s.clone()
	f.statut = State.Statut.GAGNE
	return f


# Valeur du parametre de progression a utiliser si le catalogue n'en declare pas :
# repli DECLARE, jamais une table indexee par niveau.
static func cadence_de_repli() -> int:
	return P.CADENCE_FANTOME_PERIODE
